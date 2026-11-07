import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/event_share_origin.dart';

/// Keeps the group's existing InkWell/child layout, anchoring the native sheet
/// to this button (required by iOS popover presentations).
class GroupInviteShareButton extends StatelessWidget {
  const GroupInviteShareButton({
    super.key,
    required this.inviteLink,
    required this.onError,
    required this.child,
  });

  final String inviteLink;
  final VoidCallback onError;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: inviteLink.isEmpty
          ? null
          : () async {
              // Resolve before awaiting: the group page may be closed while the
              // system share sheet is open.
              final origin = EventShareOrigin.fromContext(context);
              try {
                await Share.share(inviteLink, sharePositionOrigin: origin);
              } catch (error, stack) {
                debugPrint('Group invite share failed: $error\n$stack');
                if (context.mounted) onError();
              }
            },
      child: child,
    );
  }
}
