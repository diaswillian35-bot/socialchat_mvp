import 'dart:async';

import 'package:flutter/material.dart';

import 'presence_watch.dart';

/// Mantém o conjunto de UIDs online entre [uids], sem ticker Firebase.
///
/// Um listener RTDB por UID; cancela todos no dispose.
class PresenceOnlineSetBuilder extends StatefulWidget {
  final Set<String> uids;
  final Set<String>? excludeUids;
  final int? maxWatches;
  final Widget Function(BuildContext context, Set<String> onlineUids) builder;

  const PresenceOnlineSetBuilder({
    super.key,
    required this.uids,
    required this.builder,
    this.excludeUids,
    this.maxWatches,
  });

  @override
  State<PresenceOnlineSetBuilder> createState() =>
      _PresenceOnlineSetBuilderState();
}

class _PresenceOnlineSetBuilderState extends State<PresenceOnlineSetBuilder> {
  final _online = <String>{};
  final _subs = <String, StreamSubscription<bool>>{};

  @override
  void initState() {
    super.initState();
    _syncSubs();
  }

  @override
  void didUpdateWidget(covariant PresenceOnlineSetBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uids != widget.uids ||
        oldWidget.excludeUids != widget.excludeUids ||
        oldWidget.maxWatches != widget.maxWatches) {
      _syncSubs();
    }
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }

  void _syncSubs() {
    final wanted = <String>{};
    final max = widget.maxWatches;
    for (final u in widget.uids) {
      final t = u.trim();
      if (t.isEmpty) continue;
      if (widget.excludeUids != null && widget.excludeUids!.contains(t)) {
        continue;
      }
      wanted.add(t);
      if (max != null && wanted.length >= max) break;
    }

    final toRemove =
        _subs.keys.where((k) => !wanted.contains(k)).toList(growable: false);
    for (final k in toRemove) {
      _subs.remove(k)?.cancel();
      _online.remove(k);
    }

    for (final uid in wanted) {
      if (_subs.containsKey(uid)) continue;
      _subs[uid] = PresenceWatch.watchIsOnline(uid).listen((isOn) {
        if (!mounted) return;
        final changed = isOn ? _online.add(uid) : _online.remove(uid);
        if (changed) setState(() {});
      });
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, Set<String>.from(_online));
  }
}
