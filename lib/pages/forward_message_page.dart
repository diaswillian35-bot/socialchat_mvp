import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_texts.dart';
import '../services/forward_message_service.dart';
import '../services/group_ban_service.dart';
import '../services/group_discovery_logic.dart';
import '../services/international_chat_service.dart';
import '../services/premium_access_service.dart';
import '../services/user_search_service.dart';

class ForwardMessagePage extends StatefulWidget {
  const ForwardMessagePage({
    super.key,
    required this.source,
    this.previewLabel,
  });

  final ForwardSource source;
  final String? previewLabel;

  @override
  State<ForwardMessagePage> createState() => _ForwardMessagePageState();
}

class _ForwardDest {
  _ForwardDest({
    required this.destination,
    required this.title,
    required this.canSend,
    this.subtitle = '',
  });

  final ForwardDestination destination;
  final String title;
  final String subtitle;
  final bool canSend;
}

class _ForwardMessagePageState extends State<ForwardMessagePage>
    with SingleTickerProviderStateMixin {
  static const Color _navy = Color(0xFF313A5F);

  late final TabController _tabs;
  late final TextEditingController _searchC;

  final Set<String> _selected = {};
  final Map<String, ForwardDestination> _byKey = {};

  List<_ForwardDest> _dms = const [];
  List<_ForwardDest> _groups = const [];
  List<_ForwardDest> _users = const [];

  bool _loading = true;
  bool _sending = false;
  bool _searchingUsers = false;
  String? _error;
  String _intentId = const Uuid().v4();
  String _loadedLocaleCode = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _searchC = TextEditingController();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    _searchC.addListener(_onSearchChanged);
    _load();
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
    _searchC.removeListener(_onSearchChanged);
    _searchC.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
    _scheduleUserSearch();
  }

  Future<void>? _pendingSearch;
  void _scheduleUserSearch() {
    final q = _searchC.text.trim();
    _pendingSearch = Future.delayed(const Duration(milliseconds: 400), () async {
      if (!mounted || _searchC.text.trim() != q) return;
      if (_pendingSearch == null) return;
      if (q.length < 2) {
        setState(() => _users = const []);
        return;
      }
      setState(() => _searchingUsers = true);
      try {
        final service = UserSearchService();
        final page = await service.search(
          rawQuery: q,
          type: UserSearchType.name,
          pageSize: 20,
        );
        if (!mounted || _searchC.text.trim() != q) return;
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final list = <_ForwardDest>[];
        for (final u in page.hits) {
          if (uid != null && u.uid == uid) continue;
          final already = _dms.any((d) => d.destination.otherUid == u.uid);
          if (already) continue;
          final dest = ForwardDestination.dm(otherUid: u.uid);
          final name = u.name.trim();
          list.add(
            _ForwardDest(
              destination: dest,
              title: name.isEmpty ? AppTexts.current.get('user') : name,
              subtitle: [u.city, u.countryCode]
                  .whereType<String>()
                  .where((e) => e.isNotEmpty)
                  .join(', '),
              canSend: true,
            ),
          );
        }
        setState(() {
          _users = list;
          _searchingUsers = false;
        });
      } catch (_) {
        if (mounted) setState(() => _searchingUsers = false);
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'forward_failed';
      });
      return;
    }

    try {
      final db = FirebaseFirestore.instance;
      final mySnap = await db.collection('users').doc(uid).get();
      final myData = mySnap.data() ?? {};
      final isPremium = PremiumAccessService.isPremiumActiveFromData(myData);

      final convSnap = await db
          .collection('conversations')
          .where('participants', arrayContains: uid)
          .limit(80)
          .get();

      final dms = <_ForwardDest>[];
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
          _ForwardDest(
            destination: ForwardDestination.dm(
              conversationId: doc.id,
              otherUid: otherUid,
            ),
            title: name,
            canSend: canSend,
          ),
        );
      }

      QuerySnapshot<Map<String, dynamic>> groupSnap;
      try {
        groupSnap = await db
            .collection('groups')
            .where('members', arrayContains: uid)
            .limit(80)
            .get();
      } catch (_) {
        groupSnap = await db
            .collection('groups')
            .where('ownerId', isEqualTo: uid)
            .limit(40)
            .get();
      }

      final groups = <_ForwardDest>[];
      final seen = <String>{};
      for (final doc in groupSnap.docs) {
        if (!seen.add(doc.id)) continue;
        final data = doc.data();
        if (GroupDiscoveryLogic.isDeletedOrInactive(data)) continue;
        if (!GroupDiscoveryLogic.isParticipating(data: data, uid: uid)) continue;
        final banned =
            await GroupBanService.isUserBanned(groupId: doc.id, uid: uid);
        final myCountry = InternationalChatService.readHomeCountryCode(myData);
        final groupCountry = (data['countryCode'] ?? data['country'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final isWorld = myCountry.isNotEmpty &&
            groupCountry.isNotEmpty &&
            myCountry != groupCountry;
        final canSend = !banned && !(isWorld && !isPremium);
        final title =
            (data['name'] ?? data['title'] ?? 'Grupo').toString().trim();
        groups.add(
          _ForwardDest(
            destination: ForwardDestination.group(groupId: doc.id),
            title: title.isEmpty ? 'Grupo' : title,
            canSend: canSend,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _dms = dms;
        _groups = groups;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'forward_failed';
      });
    }
  }

  List<_ForwardDest> _filtered(List<_ForwardDest> source) {
    final q = _searchC.text.trim().toLowerCase();
    if (q.isEmpty) return source;
    return source
        .where((d) => d.title.toLowerCase().contains(q))
        .toList(growable: false);
  }

  void _toggle(_ForwardDest item) {
    if (!item.canSend || _sending) return;
    final key = item.destination.selectionKey;
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
        _byKey.remove(key);
      } else {
        if (_selected.length >= ForwardMessageService.maxDestinations) {
          final t = AppTexts.current;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                t
                    .get('forward_limit')
                    .replaceAll('{max}', '${ForwardMessageService.maxDestinations}'),
              ),
            ),
          );
          return;
        }
        _selected.add(key);
        _byKey[key] = item.destination;
      }
    });
  }

  Future<void> _submit() async {
    if (_sending) return;
    final t = AppTexts.current;
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.get('forward_select_one'))),
      );
      return;
    }
    setState(() => _sending = true);
    final dests = _selected.map((k) => _byKey[k]!).toList();
    final result = await ForwardMessageService.instance.forward(
      source: widget.source,
      destinations: dests,
      intentId: _intentId,
    );
    if (!mounted) return;

    if (result.errorCode == 'busy') {
      setState(() => _sending = false);
      return;
    }

    if (result.successCount == 0) {
      setState(() => _sending = false);
      // New intent only if not duplicate idle — keep same intent for retry
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.get('forward_failed'))),
      );
      return;
    }

    final msg = result.failureCount > 0
        ? t
            .get('forward_partial')
            .replaceAll('{ok}', '${result.successCount}')
            .replaceAll('{total}', '${result.successCount + result.failureCount}')
        : t.get('forward_success');

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _navy,
        elevation: 0,
        title: Text(
          t.get('forward_title'),
          style: const TextStyle(
            color: _navy,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: t.get('forward_cancel'),
          onPressed: _sending ? null : () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.previewLabel != null &&
                widget.previewLabel!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.previewLabel!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchC,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: t.get('forward_search'),
                  prefixIcon: const Icon(Icons.search, color: _navy),
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TabBar(
              controller: _tabs,
              labelColor: _navy,
              unselectedLabelColor: const Color(0xFF6B7280),
              indicatorColor: _navy,
              tabs: [
                Tab(text: t.get('forward_chats')),
                Tab(text: t.get('forward_groups')),
              ],
            ),
            Expanded(
              child: _loading
                  ? Center(child: Text(t.get('forward_loading')))
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(t.get(_error!)),
                              TextButton(
                                onPressed: _load,
                                child: Text(t.get('forward_retry')),
                              ),
                            ],
                          ),
                        )
                      : TabBarView(
                          controller: _tabs,
                          children: [
                            _buildList(
                              [
                                ..._filtered(_dms),
                                if (_searchC.text.trim().length >= 2) ..._users,
                              ],
                              searching: _searchingUsers,
                            ),
                            _buildList(_filtered(_groups)),
                          ],
                        ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomInset * 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _sending || _selected.isEmpty ? null : _submit,
                  child: Text(
                    _sending
                        ? t.get('forward_sending')
                        : '${t.get('forward_button')}${_selected.isEmpty ? '' : ' (${_selected.length})'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<_ForwardDest> items, {bool searching = false}) {
    final t = AppTexts.current;
    if (items.isEmpty && !searching) {
      return Center(child: Text(t.get('forward_empty')));
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: items.length + (searching ? 1 : 0),
      itemBuilder: (context, i) {
        if (searching && i == items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: _navy)),
          );
        }
        final item = items[i];
        final key = item.destination.selectionKey;
        final selected = _selected.contains(key);
        return ListTile(
          enabled: item.canSend,
          leading: Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: item.canSend ? _navy : const Color(0xFF9CA3AF),
          ),
          title: Text(
            item.title,
            style: TextStyle(
              color: item.canSend ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: !item.canSend
              ? Text(t.get('forward_no_permission'))
              : (item.subtitle.isEmpty ? null : Text(item.subtitle)),
          onTap: () => _toggle(item),
        );
      },
    );
  }
}

/// Client-side gate only — server revalidates.
bool canForwardMessageData(Map<String, dynamic> data) {
  if (data['deleted'] == true) return false;
  final type = (data['type'] ?? 'text').toString().toLowerCase();
  if (type == 'text') {
    return (data['text'] ?? '').toString().trim().isNotEmpty;
  }
  if (type == 'image') {
    final url = (data['imageUrl'] ?? '').toString().trim();
    return url.startsWith('https://');
  }
  if (type == 'audio') {
    final url = (data['audioUrl'] ?? '').toString().trim();
    final dur = data['durationMs'];
    final ms = dur is num ? dur.toInt() : int.tryParse('$dur') ?? 0;
    return url.startsWith('https://') && ms > 0;
  }
  return false;
}
