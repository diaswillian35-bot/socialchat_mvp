import 'dart:async';

import 'package:flutter/material.dart';

import '../services/block_visibility.dart';

/// Rebuilds [State] when [BlockVisibility.mine] changes (no stale one-shot cache).
mixin BlockedUidsListenable<T extends StatefulWidget> on State<T> {
  StreamSubscription<Set<String>>? _blockedUidsSub;
  Set<String> blockedUids = BlockVisibility.mine;

  @override
  void initState() {
    super.initState();
    blockedUids = Set<String>.from(BlockVisibility.mine);
    _blockedUidsSub = BlockVisibility.mineStream.listen((next) {
      if (!mounted) return;
      setState(() => blockedUids = Set<String>.from(next));
    });
  }

  @override
  void dispose() {
    _blockedUidsSub?.cancel();
    super.dispose();
  }
}

class BlockedUidsBuilder extends StatelessWidget {
  const BlockedUidsBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, Set<String> blocked) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: BlockVisibility.mineStream,
      initialData: BlockVisibility.mine,
      builder: (context, snap) {
        return builder(context, snap.data ?? BlockVisibility.mine);
      },
    );
  }
}
