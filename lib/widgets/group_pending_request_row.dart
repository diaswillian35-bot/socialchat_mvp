import 'package:flutter/material.dart';

/// Layout de pedido pendente: nome na 1ª linha (máx. 2 + ellipsis);
/// ações na 2ª linha com [Wrap] (não comprime o nome).
class GroupPendingRequestRow extends StatelessWidget {
  const GroupPendingRequestRow({
    super.key,
    required this.userName,
    required this.avatar,
    required this.rejectLabel,
    required this.approveLabel,
    required this.onReject,
    required this.onApprove,
    this.busy = false,
    this.busyAny = false,
    this.borderColor = const Color(0xFFE5E7EB),
    this.textColor = const Color(0xFF111827),
    this.mutedColor = const Color(0xFF6B7280),
    this.primaryColor = const Color(0xFF264E9A),
  });

  final String userName;
  final Widget avatar;
  final String rejectLabel;
  final String approveLabel;
  final VoidCallback? onReject;
  final VoidCallback? onApprove;
  final bool busy;
  final bool busyAny;
  final Color borderColor;
  final Color textColor;
  final Color mutedColor;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    final name = userName.trim().isEmpty ? 'Usuário' : userName.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    height: 1.25,
                  ),
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          if (!busy) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: busyAny ? null : onReject,
                  child: Text(rejectLabel),
                ),
                ElevatedButton(
                  onPressed: busyAny ? null : onApprove,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: Text(approveLabel),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
