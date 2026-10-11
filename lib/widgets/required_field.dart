import 'package:flutter/material.dart';

/// Pending state for a required field after blur or a submit attempt.
/// Color is paired with an icon and the visible label "Pendente".
class RequiredFieldChrome {
  RequiredFieldChrome._();

  static const Color pendingColor = Color(0xFFB91C1C);

  static bool reveal({
    required bool invalid,
    required bool blurred,
    required bool submitAttempted,
  }) {
    return invalid && (blurred || submitAttempted);
  }

  static InputDecoration apply({
    required InputDecoration base,
    required bool pending,
  }) {
    if (!pending) return base;
    OutlineInputBorder paint(InputBorder? current) {
      final radius = current is OutlineInputBorder
          ? current.borderRadius
          : BorderRadius.circular(14);
      return OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: pendingColor, width: 1.6),
      );
    }

    return base.copyWith(
      enabledBorder: paint(base.enabledBorder),
      focusedBorder: paint(base.focusedBorder),
      border: paint(base.border),
      errorBorder: paint(base.errorBorder),
      focusedErrorBorder: paint(base.focusedErrorBorder),
    );
  }
}

class RequiredPendingNotice extends StatelessWidget {
  const RequiredPendingNotice({
    super.key,
    required this.pendingLabel,
    required this.message,
  });

  final String pendingLabel;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      label: '$pendingLabel. $message',
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.error_outline,
                color: RequiredFieldChrome.pendingColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              pendingLabel,
              style: const TextStyle(
                color: RequiredFieldChrome.pendingColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: RequiredFieldChrome.pendingColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
