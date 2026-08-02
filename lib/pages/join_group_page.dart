import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/group_join_service.dart';
import '../services/group_join_ui_logic.dart';
import '../services/group_location_normalize.dart';
import '../services/iso_country_names.dart';
import '../services/safe_remdy_navigation.dart';
import '../services/premium_access_service.dart';
import '../widget/remdy_app.dart';
import '../widgets/international_premium_dialog.dart';
import 'group_chat_page.dart';

/// Rótulo de localização da tela Entrar no grupo.
/// Usa ISO `countryCode` + [IsoCountryNames] — nunca o nome cru do Places.
class JoinGroupLocationLabel {
  JoinGroupLocationLabel._();

  /// Formato: `Brasil • Navegantes` (país traduzido • cidade).
  /// País-only: só o nome do país. Sem gravar no Firestore.
  static String format(
    Map<String, dynamic> group, {
    required String languageCode,
  }) {
    final code = GroupLocationNormalize.countryCode(
      group['countryCode'] ?? group['country'],
    );
    final country = code.isEmpty
        ? '--'
        : IsoCountryNames.displayName(code, languageCode);
    final scope = GroupLocationNormalize.scope(group['scope']);
    if (scope == 'country') return country;

    final city = GroupLocationNormalize.cityDisplayName(group);
    if (city.isEmpty) return country;
    return '$country • $city';
  }
}

class JoinGroupPage extends StatefulWidget {
  final String inviteCode;

  const JoinGroupPage({
    super.key,
    required this.inviteCode,
  });

  @override
  State<JoinGroupPage> createState() => _JoinGroupPageState();
}

class _JoinGroupPageState extends State<JoinGroupPage> {
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  bool _loading = true;
  bool _joining = false;

  DocumentSnapshot<Map<String, dynamic>>? _groupDoc;
  String? _error;

  String get _code => GroupJoinService.normalizeInviteCode(widget.inviteCode);

  String _t(String key) {
    try {
      return AppTexts.current.get(key);
    } catch (_) {
      return key;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  Future<void> _popOrExit() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    // Nunca SystemNavigator.pop — volta ao shell seguro do Remdy.
    SafeRemdyNavigation.popOrShell(context, shellIndex: 2);
  }

  @override
  void initState() {
    super.initState();
    _loadGroupByCode();
  }

  Future<void> _loadGroupByCode() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _groupDoc = null;
    });

    try {
      final q = await FirebaseFirestore.instance
          .collection('groups')
          .where('inviteCode', isEqualTo: _code)
          .limit(1)
          .get();

      if (q.docs.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = _t('group_invite_expired');
          _loading = false;
        });
        return;
      }

      final doc = q.docs.first;
      final data = doc.data();
      if (data['deleted'] == true) {
        if (!mounted) return;
        setState(() {
          _error = _t('group_unavailable');
          _loading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _groupDoc = doc;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${_t('group_error_join_prefix')} $e';
        _loading = false;
      });
    }
  }

  Future<bool> _isUserPremium(String uid) async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return PremiumAccessService.isPremiumActiveFromData(snap.data());
    } catch (_) {
      return false;
    }
  }

  Future<void> _openGroupChat({
    required String groupId,
    required String groupName,
  }) async {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          groupId: groupId,
          groupName: groupName,
        ),
      ),
    );
  }

  Future<void> _join() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _toast(_t('group_login_to_join'));
      return;
    }

    if (_groupDoc == null) return;

    if (!GroupJoinUiLogic.canStartJoin(
      isJoining: _joining,
      isBanned: false,
    )) {
      return;
    }

    setState(() => _joining = true);

    try {
      final doc = _groupDoc!;
      final data = doc.data() ?? {};
      final bool isPremiumGroup = data['isPremiumGroup'] == true;

      if (isPremiumGroup) {
        final premium = await _isUserPremium(user.uid);
        if (!premium) {
          if (!mounted) return;
          await InternationalPremiumDialog.showStart(context);
          return;
        }
      }

      final result = await GroupJoinService.joinByInviteCode(
        inviteCode: _code,
        uid: user.uid,
      );

      if (!mounted) return;

      final decision = GroupJoinUiLogic.fromResult(result);

      if (decision.debugDetail != null) {
        debugPrint(
          'JoinGroupPage detail [${decision.effect}]: ${decision.debugDetail}',
        );
      }

      switch (decision.effect) {
        case GroupJoinUiEffect.enterChat:
          if (result.groupId == null) {
            _toast(_t(result.messageKey));
            return;
          }
          _toast(_t(result.messageKey));
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'lastJoinedGroupId': result.groupId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          final name = (result.groupName ?? '').trim();
          await _openGroupChat(
            groupId: result.groupId!,
            groupName: name.isEmpty ? _t('group_generic') : name,
          );
          return;

        case GroupJoinUiEffect.showPending:
          _toast(
            result.outcome == GroupJoinOutcome.pendingCreated
                ? _t('group_request_pending_toast')
                : _t('group_awaiting_approval'),
          );
          await _popOrExit();
          return;

        case GroupJoinUiEffect.showBanned:
        case GroupJoinUiEffect.showInviteOnly:
        case GroupJoinUiEffect.showLoginRequired:
        case GroupJoinUiEffect.showUnavailable:
        case GroupJoinUiEffect.showNetworkError:
          _toast(_t(decision.messageKey ?? result.messageKey));
          if (result.outcome == GroupJoinOutcome.invalidInvite ||
              result.outcome == GroupJoinOutcome.groupUnavailable) {
            await _popOrExit();
          }
          return;

        case GroupJoinUiEffect.showPremiumRequired:
          await InternationalPremiumDialog.showStart(context);
          return;

        case GroupJoinUiEffect.showGenericError:
          final detail = kDebugMode ? (result.errorDetail ?? '') : '';
          _toast(
            '${_t(decision.messageKey ?? result.messageKey)} $detail'.trim(),
          );
          return;

        case GroupJoinUiEffect.showJoining:
        case GroupJoinUiEffect.idle:
          return;
      }
    } catch (e) {
      debugPrint('JoinGroupPage._join unexpected: $e');
      _toast('${_t('group_error_join_prefix')} $e');
    } finally {
      if (mounted) {
        setState(() => _joining = false);
      } else {
        _joining = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = _groupDoc?.data() ?? {};

    final name = (group['name'] ?? _t('group_generic')).toString().trim();
    final lang = Localizations.localeOf(context).toLanguageTag();
    final locationLabel = JoinGroupLocationLabel.format(
      group,
      languageCode: lang,
    );
    final bio = (group['bio'] ?? '').toString().trim();
    final avatarUrl = (group['avatarUrl'] ?? '').toString().trim();

    final isPremiumGroup = group['isPremiumGroup'] == true;
    final joinPolicy =
        GroupJoinService.normalizeJoinPolicy(group['joinPolicy']);

    final joinButtonText = joinPolicy == 'approval'
        ? _t('group_join_group')
        : _t('group_join_group');

    final joinPolicyLabel = joinPolicy == 'approval'
        ? _t('group_awaiting_approval')
        : (joinPolicy == 'inviteOnly'
            ? _t('group_invite_only_message')
            : _t('group_join_group'));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: RemdyAppBar(title: _t('group_join_group')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _border),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: avatarUrl.isNotEmpty
                                  ? Image.network(
                                      avatarUrl,
                                      width: 150,
                                      height: 150,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.groups_rounded),
                                    )
                                  : const Icon(
                                      Icons.groups_rounded,
                                      color: _remdyBlue,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? _t('group_generic') : name,
                                  style: const TextStyle(
                                    color: _text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  locationLabel,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (bio.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    bio,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _Tag(
                                      text: isPremiumGroup ? 'Premium' : 'Free',
                                      filled: isPremiumGroup,
                                    ),
                                    _Tag(
                                      text: joinPolicyLabel,
                                      filled: false,
                                    ),
                                    _Tag(
                                      text: 'Code: $_code',
                                      filled: false,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: _remdyBlue,
                      ),
                      child: ElevatedButton(
                        onPressed: _joining ? null : _join,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _joining
                            ? const SizedBox(
                                height: 50,
                                width: 50,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                joinButtonText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    if (FirebaseAuth.instance.currentUser == null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _t('group_login_to_join'),
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final bool filled;

  const _Tag({
    required this.text,
    required this.filled,
  });

  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? _remdyBlue : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: filled ? _remdyBlue : const Color(0xFFE5E7EB),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: filled ? Colors.white : const Color(0xFF111827),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
