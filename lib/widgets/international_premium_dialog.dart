import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../pages/invite_page.dart';
import '../pages/premium_page.dart';

enum InternationalPremiumDialogMode { start, reply, quotaExhausted }

class InternationalPremiumDialog {
  InternationalPremiumDialog._();

  static Future<void> showStart(BuildContext context) {
    return show(
      context,
      mode: InternationalPremiumDialogMode.start,
    );
  }

  static Future<void> showReply(BuildContext context) {
    return show(
      context,
      mode: InternationalPremiumDialogMode.reply,
    );
  }

  static Future<void> showQuotaExhausted(
    BuildContext context, {
    required String otherFirstName,
  }) {
    return show(
      context,
      mode: InternationalPremiumDialogMode.quotaExhausted,
      otherFirstName: otherFirstName,
    );
  }

  static Future<void> show(
    BuildContext context, {
    required InternationalPremiumDialogMode mode,
    String otherFirstName = '',
  }) async {
    final t = AppTexts.current;
    final isStart = mode == InternationalPremiumDialogMode.start;
    final isQuota = mode == InternationalPremiumDialogMode.quotaExhausted;

    final fallbackName = t.get('dm_quota_person_fallback');
    final name = otherFirstName.trim().isEmpty ? fallbackName : otherFirstName.trim();

    final title = t.get(
      isQuota
          ? 'dm_quota_title'
          : (isStart ? 'user_search_intl_title' : 'intl_chat_reply_title'),
    );
    final message = isQuota
        ? t.get('dm_quota_message').replaceAll('{nome}', name).replaceAll('{name}', name)
        : t.get(
            isStart ? 'user_search_premium_required' : 'intl_chat_reply_message',
          );
    final subscribeLabel = t.get(
      isQuota || !isStart
          ? 'intl_chat_subscribe_premium'
          : 'user_search_view_premium',
    );
    final inviteLabel = t.get('intl_chat_invite_friends');
    final notNowLabel = t.get(
      isStart && !isQuota ? 'user_search_cancel' : 'intl_chat_not_now',
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PremiumPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF313A5F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      subscribeLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                if (!isQuota) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _openInvitePage(context);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      inviteLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF313A5F),
                      ),
                    ),
                  ),
                ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text(
                      notNowLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _openInvitePage(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data() ?? {};

      final invites = (data['invitesCount'] is int)
          ? data['invitesCount'] as int
          : ((data['invites'] is int) ? data['invites'] as int : 0);
      final limit =
          (data['invitesGoal'] is int) ? data['invitesGoal'] as int : 5;
      final inviteCodeRaw = (data['inviteCode'] ?? '').toString().trim();
      final inviteCode = inviteCodeRaw.isEmpty ? uid : inviteCodeRaw;

      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvitePage(
            invites: invites,
            limit: limit,
            myUid: uid,
            inviteCode: inviteCode,
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTexts.current.get('intl_chat_invite_open_error')),
        ),
      );
    }
  }
}
