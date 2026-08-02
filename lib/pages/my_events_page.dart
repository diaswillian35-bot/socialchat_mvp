import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../pages/edit_event_page.dart';
import '../pages/event_detail_page.dart';
import '../services/event_list_queries.dart';
import '../services/event_management_service.dart';
import '../utils/event_lifecycle.dart';

enum _MyEventsSection { upcoming, live, past, archived }

class MyEventsPage extends StatefulWidget {
  const MyEventsPage({super.key});

  @override
  State<MyEventsPage> createState() => _MyEventsPageState();
}

class _MyEventsPageState extends State<MyEventsPage> {
  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _border = Color(0xFFE5E7EB);

  _MyEventsSection _section = _MyEventsSection.upcoming;

  final Map<_MyEventsSection, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _docs = {};
  final Map<_MyEventsSection, DocumentSnapshot<Map<String, dynamic>>?> _cursors =
      {};
  final Map<_MyEventsSection, bool> _loading = {};
  final Map<_MyEventsSection, bool> _loadingMore = {};
  final Map<_MyEventsSection, bool> _loadedOnce = {};
  final Map<_MyEventsSection, bool> _hasMore = {};
  final Map<_MyEventsSection, Object?> _errors = {};
  final Map<_MyEventsSection, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?> _subs = {};

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSectionLoaded(_section));
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      s?.cancel();
    }
    super.dispose();
  }

  String _fmtDate(Timestamp? ts) {
    if (ts == null) return AppTexts.t('events_no_date');
    final d = ts.toDate();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} • ${two(d.hour)}:${two(d.minute)}';
  }

  Color _statusColor(String status) {
    if (status == 'approved') return Colors.green;
    if (status == 'rejected') return Colors.red;
    return Colors.orange;
  }

  Color _cardColor(String status) {
    if (status == 'cancelled') return const Color(0xFFF3F4F6);
    return Colors.white;
  }

  String _statusText(String status, {bool hasPendingChanges = false}) {
    if (hasPendingChanges && status == 'approved') {
      return AppTexts.t('event_changes_pending');
    }
    if (status == 'approved') return AppTexts.t('my_events_approved');
    if (status == 'rejected') return AppTexts.t('my_events_rejected');
    if (status == 'cancelled') return AppTexts.t('my_events_cancelled');
    return AppTexts.t('my_events_pending');
  }

  Query<Map<String, dynamic>> _queryFor(
    _MyEventsSection section, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) {
    final uid = _uid!;
    switch (section) {
      case _MyEventsSection.upcoming:
        return EventListQueries.myUpcoming(uid: uid, startAfter: startAfter);
      case _MyEventsSection.live:
        return EventListQueries.myLive(uid: uid, startAfter: startAfter);
      case _MyEventsSection.past:
        return EventListQueries.myPast(uid: uid, startAfter: startAfter);
      case _MyEventsSection.archived:
        return EventListQueries.myArchived(uid: uid, startAfter: startAfter);
    }
  }

  bool _clientKeep(Map<String, dynamic> data, _MyEventsSection section) {
    if (data['deleted'] == true) return false;
    final archived = data['archived'] == true;
    switch (section) {
      case _MyEventsSection.archived:
        return archived;
      case _MyEventsSection.upcoming:
      case _MyEventsSection.live:
      case _MyEventsSection.past:
        return !archived;
    }
  }

  Future<void> _ensureSectionLoaded(_MyEventsSection section) async {
    if (_loadedOnce[section] == true || _loading[section] == true) return;
    await _reloadSection(section);
  }

  Future<void> _reloadSection(_MyEventsSection section) async {
    final uid = _uid;
    if (uid == null) return;

    await _subs[section]?.cancel();
    _subs[section] = null;

    setState(() {
      _loading[section] = true;
      _errors[section] = null;
      _cursors[section] = null;
      _hasMore[section] = true;
    });

    final usesStream =
        section == _MyEventsSection.upcoming || section == _MyEventsSection.live;

    try {
      if (usesStream) {
        final q = _queryFor(section);
        _subs[section] = q.snapshots().listen(
          (snap) {
            final docs = snap.docs
                .where((d) => _clientKeep(d.data(), section))
                .toList();
            if (!mounted) return;
            setState(() {
              _docs[section] = docs;
              _cursors[section] = docs.isEmpty ? null : docs.last;
              _hasMore[section] = snap.docs.length >= EventLifecycle.pageSize;
              _loading[section] = false;
              _loadedOnce[section] = true;
              _errors[section] = null;
            });
          },
          onError: (e) {
            if (!mounted) return;
            setState(() {
              _loading[section] = false;
              _loadedOnce[section] = true;
              _errors[section] = e;
            });
          },
        );
      } else {
        // Passados / Arquivados: one-shot, sem listener contínuo.
        final snap = await _queryFor(section).get();
        final docs =
            snap.docs.where((d) => _clientKeep(d.data(), section)).toList();
        if (!mounted) return;
        setState(() {
          _docs[section] = docs;
          _cursors[section] = docs.isEmpty ? null : docs.last;
          _hasMore[section] = snap.docs.length >= EventLifecycle.pageSize;
          _loading[section] = false;
          _loadedOnce[section] = true;
          _errors[section] = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading[section] = false;
        _loadedOnce[section] = true;
        _errors[section] = e;
      });
    }
  }

  Future<void> _loadMore(_MyEventsSection section) async {
    if (_loadingMore[section] == true || _hasMore[section] == false) return;
    final cursor = _cursors[section];
    if (cursor == null) return;

    setState(() => _loadingMore[section] = true);
    try {
      final snap = await _queryFor(section, startAfter: cursor).get();
      final more =
          snap.docs.where((d) => _clientKeep(d.data(), section)).toList();
      if (!mounted) return;
      setState(() {
        final existing = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          _docs[section] ?? const [],
        );
        final seen = existing.map((e) => e.id).toSet();
        for (final d in more) {
          if (seen.add(d.id)) existing.add(d);
        }
        _docs[section] = existing;
        if (more.isNotEmpty) _cursors[section] = more.last;
        _hasMore[section] = snap.docs.length >= EventLifecycle.pageSize;
        _loadingMore[section] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore[section] = false;
        _errors[section] = e;
      });
    }
  }

  Future<void> _selectSection(_MyEventsSection section) async {
    setState(() => _section = section);
    await _ensureSectionLoaded(section);
  }

  Future<bool> _confirm({
    required String titleKey,
    required String messageKey,
    required String confirmKey,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppTexts.t(titleKey)),
        content: Text(AppTexts.t(messageKey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppTexts.t('back')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppTexts.t(confirmKey)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      await _reloadSection(_section);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTexts.t(EventManagementService.lifecycleErrorKey(e))),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t('events_error_generic'))),
      );
    }
  }

  Future<void> _cancelEvent(String eventId) async {
    final ok = await _confirm(
      titleKey: 'my_events_cancel_title',
      messageKey: 'my_events_cancel_message',
      confirmKey: 'my_events_cancel_button',
    );
    if (!ok) return;
    await _runAction(
      () => EventManagementService.cancelEvent(eventId: eventId),
    );
  }

  Future<void> _archive(String eventId) async {
    final ok = await _confirm(
      titleKey: 'events_confirm_archive_title',
      messageKey: 'events_confirm_archive_message',
      confirmKey: 'events_action_archive',
    );
    if (!ok) return;
    await _runAction(
      () => EventManagementService.archiveEvent(eventId: eventId),
    );
  }

  Future<void> _restore(String eventId) async {
    final ok = await _confirm(
      titleKey: 'events_confirm_restore_title',
      messageKey: 'events_confirm_restore_message',
      confirmKey: 'events_action_restore',
    );
    if (!ok) return;
    await _runAction(
      () => EventManagementService.restoreEvent(eventId: eventId),
    );
  }

  Future<void> _duplicate(String eventId) async {
    final ok = await _confirm(
      titleKey: 'events_confirm_duplicate_title',
      messageKey: 'events_confirm_duplicate_message',
      confirmKey: 'events_action_duplicate',
    );
    if (!ok) return;
    try {
      final result =
          await EventManagementService.duplicateEvent(eventId: eventId);
      final newId = (result['eventId'] ?? '').toString();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t('events_duplicate_success'))),
      );
      if (newId.isNotEmpty) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EditEventPage(eventId: newId)),
        );
      }
      await _reloadSection(_MyEventsSection.upcoming);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTexts.t(EventManagementService.lifecycleErrorKey(e))),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t('events_error_generic'))),
      );
    }
  }

  Future<void> _deletePermanent(String eventId) async {
    final ok = await _confirm(
      titleKey: 'events_confirm_delete_title',
      messageKey: 'events_confirm_delete_message',
      confirmKey: 'events_action_delete_permanent',
    );
    if (!ok) return;
    await _runAction(
      () => EventManagementService.deleteEventPermanently(eventId: eventId),
    );
  }

  Widget _segmentChip(_MyEventsSection section, String labelKey) {
    final selected = _section == section;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          AppTexts.t(labelKey),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : _text,
            fontSize: 12,
          ),
        ),
        selected: selected,
        selectedColor: _remdyBlue,
        backgroundColor: Colors.white,
        side: const BorderSide(color: _border),
        onSelected: (_) => _selectSection(section),
      ),
    );
  }

  Widget _actionsFor(
    _MyEventsSection section,
    String eventId,
    String status,
  ) {
    final t = AppTexts.t;
    Widget btn(String label, VoidCallback? onPressed, {IconData? icon}) {
      return Expanded(
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: _remdyBlue,
            backgroundColor: Colors.white,
            side: const BorderSide(color: _border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: onPressed,
          icon: Icon(icon ?? Icons.circle_outlined, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 11)),
        ),
      );
    }

    void view() {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EventDetailPage(eventId: eventId)),
      );
    }

    if (section == _MyEventsSection.past) {
      return Column(
        children: [
          Row(
            children: [
              btn(t('events_action_view'), view, icon: Icons.visibility_outlined),
              const SizedBox(width: 8),
              btn(t('events_action_duplicate'), () => _duplicate(eventId),
                  icon: Icons.copy_outlined),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              btn(t('events_action_archive'), () => _archive(eventId),
                  icon: Icons.archive_outlined),
              const SizedBox(width: 8),
              btn(t('events_action_delete_permanent'),
                  () => _deletePermanent(eventId),
                  icon: Icons.delete_forever_outlined),
            ],
          ),
        ],
      );
    }

    if (section == _MyEventsSection.archived) {
      return Row(
        children: [
          btn(t('events_action_view'), view, icon: Icons.visibility_outlined),
          const SizedBox(width: 8),
          btn(t('events_action_restore'), () => _restore(eventId),
              icon: Icons.unarchive_outlined),
          const SizedBox(width: 8),
          btn(t('events_action_delete_permanent'),
              () => _deletePermanent(eventId),
              icon: Icons.delete_forever_outlined),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _remdyBlue,
              backgroundColor: Colors.white,
              side: const BorderSide(color: _border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: status == 'cancelled'
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditEventPage(eventId: eventId),
                      ),
                    );
                  },
            icon: const Icon(Icons.edit_outlined),
            label: Text(t('my_events_edit')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _remdyBlue,
              backgroundColor: Colors.white,
              side: const BorderSide(color: _border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: status == 'cancelled' ? null : () => _cancelEvent(eventId),
            icon: const Icon(Icons.cancel_outlined),
            label: Text(t('my_events_cancel')),
          ),
        ),
      ],
    );
  }

  String _emptyKey(_MyEventsSection s) {
    switch (s) {
      case _MyEventsSection.upcoming:
        return 'events_empty_upcoming';
      case _MyEventsSection.live:
        return 'events_empty_live';
      case _MyEventsSection.past:
        return 'events_empty_past';
      case _MyEventsSection.archived:
        return 'events_empty_archived';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          AppTexts.t('my_events_title'),
          style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
        ),
      ),
      body: uid == null
          ? Center(child: Text(AppTexts.t('my_events_login_required')))
          : Column(
              children: [
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    children: [
                      _segmentChip(
                          _MyEventsSection.upcoming, 'events_bucket_upcoming'),
                      _segmentChip(_MyEventsSection.live, 'events_bucket_live'),
                      _segmentChip(_MyEventsSection.past, 'events_bucket_past'),
                      _segmentChip(
                          _MyEventsSection.archived, 'events_bucket_archived'),
                    ],
                  ),
                ),
                Expanded(child: _buildBody(_section)),
              ],
            ),
    );
  }

  Widget _buildBody(_MyEventsSection section) {
    if (_loading[section] == true && (_docs[section] ?? []).isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errors[section] != null && (_docs[section] ?? []).isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppTexts.t('events_load_error'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() => _loadedOnce[section] = false);
                  _reloadSection(section);
                },
                child: Text(AppTexts.t('events_retry')),
              ),
            ],
          ),
        ),
      );
    }

    final docs = _docs[section] ?? [];
    if (docs.isEmpty) {
      return Center(
        child: Text(
          AppTexts.t(_emptyKey(section)),
          style: const TextStyle(color: _muted, fontWeight: FontWeight.w800),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _reloadSection(section),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        itemCount: docs.length + (_hasMore[section] == true ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= docs.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _loadingMore[section] == true
                    ? const CircularProgressIndicator()
                    : TextButton(
                        onPressed: () => _loadMore(section),
                        child: Text(AppTexts.t('events_load_more')),
                      ),
              ),
            );
          }

          final doc = docs[index];
          final data = doc.data();
          final title = (data['title'] ?? AppTexts.t('events_default_category'))
              .toString();
          final city = (data['city'] ?? '').toString();
          final place = (data['placeName'] ?? '').toString();
          final category = (data['category'] ?? '').toString();
          final status = (data['status'] ?? 'pending').toString();
          final hasPendingChanges = data['hasPendingChanges'] == true;
          final attendees = data['attendeesCount'] is int
              ? data['attendeesCount'] as int
              : 0;
          final sponsorInterested = data['sponsorInterested'] == true;

          return Card(
            color: _cardColor(status),
            surfaceTintColor: Colors.white,
            elevation: 1.5,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: (hasPendingChanges && status == 'approved'
                                  ? Colors.orange
                                  : _statusColor(status))
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _statusText(
                            status,
                            hasPendingChanges: hasPendingChanges,
                          ),
                          style: TextStyle(
                            color: hasPendingChanges && status == 'approved'
                                ? Colors.orange
                                : _statusColor(status),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$category • $city',
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (place.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      place,
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _fmtDate(data['startAt'] as Timestamp?),
                    style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$attendees ${AppTexts.t('my_events_attending')}',
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (sponsorInterested) ...[
                    const SizedBox(height: 8),
                    Text(
                      AppTexts.t('my_events_sponsor_interested'),
                      style: const TextStyle(
                        color: _remdyBlue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _actionsFor(section, doc.id, status),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
