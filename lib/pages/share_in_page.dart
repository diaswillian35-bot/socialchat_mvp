import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../models/share_in_payload.dart';
import '../services/group_ban_service.dart';
import '../services/group_discovery_logic.dart';
import '../services/international_chat_service.dart';
import '../services/message_link_utils.dart';
import '../services/outgoing_text_message_service.dart';
import '../services/premium_access_service.dart';
import '../services/safe_external_link.dart';
import '../services/safe_remdy_navigation.dart';
import '../services/share_in_service.dart';
import 'chat_page.dart';
import 'group_chat_page.dart';

class ShareInPage extends StatefulWidget {
  const ShareInPage({super.key, required this.payload});

  final ShareInPayload payload;

  @override
  State<ShareInPage> createState() => _ShareInPageState();
}

class _ShareInPageState extends State<ShareInPage>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _textC;
  late final TextEditingController _searchC;
  late final TabController _tabs;

  final _sender = OutgoingTextMessageService();

  List<ShareInDestination> _dms = const [];
  List<ShareInDestination> _groups = const [];
  ShareInDestination? _selected;
  bool _loading = true;
  bool _sending = false;
  String? _retryMessageId;
  String _loadedLocaleCode = '';

  @override
  void initState() {
    super.initState();
    _textC = TextEditingController(text: widget.payload.text);
    _searchC = TextEditingController();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    _searchC.addListener(() => setState(() {}));
    _loadDestinations();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    final next = '${locale.languageCode}_${locale.countryCode ?? ''}';
    if (_loadedLocaleCode == next) return;
    _loadedLocaleCode = next;
    AppTexts.load(locale).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _textC.dispose();
    _searchC.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadDestinations() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    final db = FirebaseFirestore.instance;
    final mySnap = await db.collection('users').doc(uid).get();
    final myData = mySnap.data() ?? {};
    final isPremium = PremiumAccessService.isPremiumActiveFromData(myData);

    final convSnap = await db
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .limit(80)
        .get();

    final dms = <ShareInDestination>[];
    for (final doc in convSnap.docs) {
      final data = doc.data();
      final hidden = (data['hiddenFor'] is List)
          ? List<String>.from((data['hiddenFor'] as List).map((e) => '$e'))
          : <String>[];
      if (hidden.contains(uid)) continue;

      final parts = (data['participants'] is List)
          ? List<String>.from((data['participants'] as List).map((e) => '$e'))
          : <String>[];
      final otherUid = parts.firstWhere((u) => u != uid, orElse: () => '');
      if (otherUid.isEmpty) continue;

      String name = '';
      try {
        final pub = await db.collection('publicUsers').doc(otherUid).get();
        name = (pub.data()?['displayName'] ??
                pub.data()?['name'] ??
                pub.data()?['username'] ??
                '')
            .toString()
            .trim();
      } catch (_) {}
      if (name.isEmpty) name = AppTexts.current.get('user');

      final otherData =
          await InternationalChatService.fetchUserData(otherUid) ?? {};
      final canSend = InternationalChatService.canSendMessage(
        senderData: myData,
        recipientData: otherData,
      );

      dms.add(
        ShareInDestination(
          kind: ShareInDestinationKind.conversation,
          id: doc.id,
          title: name,
          otherUid: otherUid,
          canSend: canSend,
          disabledReasonKey: canSend ? '' : 'share_in_no_permission',
        ),
      );
    }

    // Grupos: query por members arrayContains quando possível.
    QuerySnapshot<Map<String, dynamic>> groupSnap;
    try {
      groupSnap = await db
          .collection('groups')
          .where('members', arrayContains: uid)
          .limit(80)
          .get();
    } catch (_) {
      // Fallback: ownerId
      groupSnap = await db
          .collection('groups')
          .where('ownerId', isEqualTo: uid)
          .limit(40)
          .get();
    }

    final groups = <ShareInDestination>[];
    final seen = <String>{};
    for (final doc in groupSnap.docs) {
      if (!seen.add(doc.id)) continue;
      final data = doc.data();
      if (GroupDiscoveryLogic.isDeletedOrInactive(data)) continue;
      if (!GroupDiscoveryLogic.isParticipating(data: data, uid: uid)) continue;

      final banned =
          await GroupBanService.isUserBanned(groupId: doc.id, uid: uid);
      final myCountry = InternationalChatService.readHomeCountryCode(myData);
      final groupCountry =
          (data['countryCode'] ?? data['country'] ?? '').toString().trim().toLowerCase();
      final isWorld = myCountry.isNotEmpty &&
          groupCountry.isNotEmpty &&
          myCountry != groupCountry;
      final canSend = !banned && !(isWorld && !isPremium);
      final title = (data['name'] ?? data['title'] ?? 'Grupo').toString().trim();

      groups.add(
        ShareInDestination(
          kind: ShareInDestinationKind.group,
          id: doc.id,
          title: title.isEmpty ? 'Grupo' : title,
          canSend: canSend,
          disabledReasonKey: canSend ? '' : 'share_in_no_permission',
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _dms = dms;
      _groups = groups;
      _loading = false;
    });
  }

  List<ShareInDestination> _filtered(List<ShareInDestination> source) {
    final q = _searchC.text.trim().toLowerCase();
    if (q.isEmpty) return source;
    return source
        .where((d) => d.title.toLowerCase().contains(q))
        .toList(growable: false);
  }

  MessageLinkMatch? get _previewLink {
    final links = MessageLinkUtils.extractLinks(_textC.text);
    return links.isEmpty ? null : links.first;
  }

  Future<void> _onCancel() async {
    await ShareInService.markCancelled(widget.payload);
    if (!mounted) return;
    SafeRemdyNavigation.popOrShell(context, shellIndex: 1);
  }

  Future<void> _onSend() async {
    if (_sending) return;
    final dest = _selected;
    final t = AppTexts.current;
    if (kDebugMode) {
      debugPrint(
        'ShareIn: _onSend start dest=${dest?.kind.name}:${dest?.id} '
        'textLen=${_textC.text.trim().length}',
      );
    }
    if (dest == null) {
      _snack(t.get('share_in_choose_destination'));
      return;
    }
    if (!dest.canSend) {
      _snack(t.get('share_in_no_permission'));
      return;
    }

    final text = _textC.text.trim();
    if (text.isEmpty) {
      _snack(t.get('share_in_invalid'));
      return;
    }

    setState(() => _sending = true);
    final result = await _sender.send(
      OutgoingTextSendRequest(
        target: dest.kind == ShareInDestinationKind.conversation
            ? OutgoingTextSendTarget.conversation
            : OutgoingTextSendTarget.group,
        targetId: dest.id,
        otherUid: dest.otherUid,
        text: text,
        messageId: _retryMessageId,
      ),
    );

    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _sending = false;
        _retryMessageId = result.messageId ?? _retryMessageId;
      });
      _snack(t.get(result.errorKey ?? 'share_in_failed'));
      return;
    }

    _retryMessageId = result.messageId;
    await ShareInService.markSent(
      widget.payload.copyWithText(text),
    );

    if (!mounted) return;
    _snack(t.get('share_in_sent'));

    // Abre o chat destino (mensagem já no servidor).
    final page = dest.kind == ShareInDestinationKind.conversation
        ? ChatPage(
            conversationId: dest.id,
            otherUid: dest.otherUid,
            otherName: dest.title,
          )
        : GroupChatPage(
            groupId: dest.id,
            groupName: dest.title,
          );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final link = _previewLink;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = theme.scaffoldBackgroundColor;
    final muted = scheme.onSurfaceVariant;
    final border = scheme.outline;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          await ShareInService.markCancelled(widget.payload);
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        // Scaffold já sobe o body com o teclado — não somar viewInsets de novo.
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          foregroundColor: scheme.primary,
          title: Text(
            t.get('share_in_title'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _sending ? null : _onCancel,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    Text(
                      t.get('share_in_preview'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _textC,
                      minLines: 3,
                      maxLines: 6,
                      enabled: !_sending,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: scheme.primary),
                        ),
                      ),
                    ),
                    if (link != null) ...[
                      const SizedBox(height: 12),
                      Material(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _sending
                              ? null
                              : () => SafeExternalLink.open(
                                    context,
                                    url: link.normalizedHttpsUrl,
                                    isRemdyInternal: link.isRemdyInternal,
                                    displayHost: link.displayHost,
                                  ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(
                                  link.isRemdyInternal
                                      ? Icons.link
                                      : Icons.public,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        link.displayHost,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        link.normalizedHttpsUrl,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      t.get('share_in_choose_destination'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchC,
                      enabled: !_sending,
                      decoration: InputDecoration(
                        hintText: t.get('share_in_search'),
                        prefixIcon: Icon(Icons.search, color: muted),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TabBar(
                      controller: _tabs,
                      labelColor: scheme.primary,
                      unselectedLabelColor: muted,
                      indicatorColor: scheme.primary,
                      tabs: [
                        Tab(text: t.get('share_in_private')),
                        Tab(text: t.get('share_in_groups')),
                      ],
                      onTap: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      _buildDestinationList(
                        _tabs.index == 0 ? _filtered(_dms) : _filtered(_groups),
                        t,
                        scheme,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _sending ? null : _onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.primary,
                          side: BorderSide(color: scheme.primary),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text(t.get('share_in_cancel')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      // InkWell + Material: hit target confiável no device
                      // (FilledButton+AbsorbPointer falhava com input tap no Enviar).
                      child: Material(
                        color: _sending
                            ? scheme.surfaceContainerHighest
                            : scheme.primary,
                        borderRadius: BorderRadius.circular(24),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _sending ? null : _onSend,
                          child: SizedBox(
                            height: 48,
                            child: Center(
                              child: Text(
                                _sending
                                    ? t.get('share_in_sending')
                                    : t.get('share_in_send'),
                                style: TextStyle(
                                  color: _sending
                                      ? muted
                                      : scheme.onPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDestinationList(
    List<ShareInDestination> items,
    AppTexts t,
    ColorScheme scheme,
  ) {
    final muted = scheme.onSurfaceVariant;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            t.get('share_in_empty_destinations'),
            style: TextStyle(color: muted, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final d in items)
          ListTile(
            enabled: d.canSend && !_sending,
            selected: _selected?.id == d.id && _selected?.kind == d.kind,
            selectedTileColor: scheme.primaryContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: (_selected?.id == d.id && _selected?.kind == d.kind)
                    ? scheme.primary
                    : scheme.outline,
              ),
            ),
            leading: Icon(
              d.kind == ShareInDestinationKind.conversation
                  ? Icons.person_outline
                  : Icons.groups_outlined,
              color: d.canSend ? scheme.primary : muted,
            ),
            title: Text(
              d.title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: d.canSend ? scheme.onSurface : muted,
              ),
            ),
            subtitle: d.canSend
                ? null
                : Text(
                    t.get(d.disabledReasonKey.isEmpty
                        ? 'share_in_no_permission'
                        : d.disabledReasonKey),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
            onTap: (!d.canSend || _sending)
                ? null
                : () => setState(() => _selected = d),
          ),
      ],
    );
  }
}
