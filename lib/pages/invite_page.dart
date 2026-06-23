import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_texts.dart';

class InvitePage extends StatelessWidget {
  final int invites;
  final int limit;
  final String myUid;
  final String inviteCode;

  const InvitePage({
    super.key,
    required this.invites,
    required this.limit,
    required this.myUid,
    required this.inviteCode,
  });

  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _card = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);
  static const Color _success = Color(0xFF16A34A);

  String _inviteLink() {
    return 'https://remdy.app/invite?ref=$inviteCode';
  }

  String _currentRewardLabel(int rewardLevel, AppTexts t) {
    if (rewardLevel >= 30) return t.get('invite_reward_current_30');
    if (rewardLevel >= 15) return t.get('invite_reward_current_15');
    if (rewardLevel >= 3) return t.get('invite_reward_current_3');
    return t.get('invite_reward_current_none');
  }

  int _nextRewardTarget(int invites) {
    if (invites < 3) return 3;
    if (invites < 15) return 15;
    if (invites < 30) return 30;
    return 30;
  }

  String _nextRewardLabel(int invites, AppTexts t) {
    if (invites < 3) return t.get('invite_reward_3');
    if (invites < 15) return t.get('invite_reward_15');
    if (invites < 30) return t.get('invite_reward_30');
    return t.get('invite_all_rewards_unlocked');
  }

  String _remainingText(int invites, AppTexts t) {
    final target = _nextRewardTarget(invites);

    if (invites >= 30) {
      return t.get('invite_all_rewards_unlocked');
    }

    final missing = target - invites;

    if (missing == 1) {
      return t.get('invite_missing_one');
    }

    return t.get('invite_missing').replaceAll('{count}', '$missing');
  }

  String _inviteMessage() {
    final t = AppTexts.current;
    final link = _inviteLink();

    return '''
🔥 ${t.get('invite_share_title')}

${t.get('invite_share_description')}

🚀 $link
''';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(myUid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};

        final invites = (data['invitesCount'] is num)
            ? (data['invitesCount'] as num).toInt()
            : 0;

        final rewardLevel = (data['inviteRewardLevel'] is num)
            ? (data['inviteRewardLevel'] as num).toInt()
            : 0;

        final progressLimit = _nextRewardTarget(invites);
        final progress = progressLimit <= 0
            ? 0.0
            : (invites / progressLimit).clamp(0.0, 1.0);

        final reachedGoal = progress >= 1.0;

        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            elevation: 0,
            iconTheme: const IconThemeData(color: _text),
            title: Text(
              t.get('invite_title'),
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.get('invite_subtitle'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${t.get('invite_current_reward')} ${_currentRewardLabel(rewardLevel, t)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${t.get('invite_next_goal')} ${_nextRewardLabel(invites, t)}',
                      style: const TextStyle(color: _muted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _remainingText(invites, t),
                      style: const TextStyle(
                        color: _logoBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      color: reachedGoal ? _success : _remdyBlue,
                      backgroundColor: const Color(0xFFF1F5F9),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t.get('invite_rewards_title'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• ${t.get('invite_reward_3')}\n'
                      '• ${t.get('invite_reward_15')}\n'
                      '• ${t.get('invite_reward_30')}',
                      style: const TextStyle(color: _muted),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t.get('invite_auto_unlock'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  children: [
                    Text(_inviteLink()),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: _inviteLink()),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(t.get('invite_code_copied')),
                                ),
                              );
                            },
                            child: Text(t.get('invite_copy')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: const LinearGradient(
                                colors: [_remdyBlue, _logoBlue],
                              ),
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                Share.share(_inviteMessage());
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                t.get('invite_share'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
