import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_texts.dart';


class InvitePage extends StatelessWidget {
  final int invites;
  final int limit;
  final String myUid;


  const InvitePage({
    super.key,
    required this.invites,
    required this.limit,
    required this.myUid,
  });


  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _card = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);
  static const Color _success = Color(0xFF16A34A);
  static const Color _softBlue = Color(0xFFEFF6FF);


  String _rewardLabel(int limit) {
    final t = AppTexts.current;


    if (limit >= 10) return t.get('invite_reward_premium_access');
    if (limit >= 5) return t.get('invite_reward_premium_days');
    return t.get('invite_reward_exclusive_benefit');
  }


  String _inviteMessage() {
    final t = AppTexts.current;
   

    return '''
${t.get('invite_share_title')} 🌍


${t.get('invite_share_description')}


${t.get('invite_share_use_code')}
$myUid
''';
  }


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final safeLimit = limit <= 0 ? 1 : limit;
    final progress = (invites / safeLimit).clamp(0.0, 1.0);
    final remaining = (safeLimit - invites) < 0 ? 0 : (safeLimit - invites);
    final reachedGoal = progress >= 1.0;


    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          t.get('invite_friends'),
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🎁', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t.get('invite_unlock_rewards'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: _text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  t.get('invite_track_progress'),
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _softBlue,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFDBEAFE)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.workspace_premium_rounded,
                        color: _logoBlue,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _rewardLabel(safeLimit),
                          style: const TextStyle(
                            color: _logoBlue,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '$invites / $safeLimit ${t.get('invite_completed_count')}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: const Color(0xFFF1F5F9),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      reachedGoal ? _success : _remdyBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  reachedGoal
                      ? t.get('invite_goal_reached')
                      : '$remaining ${remaining == 1 ? t.get('invite_left_single') : t.get('invite_left_plural')}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: reachedGoal ? _success : _text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            t.get('your_invite_code'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: _text,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border),
                  ),
                  child: Text(
                    myUid,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: _text,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: myUid));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(t.get('invite_code_copied')),
                              behavior: SnackBarBehavior.floating,
                              margin: const EdgeInsets.all(12),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: Text(
                          t.get('copy'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _remdyBlue,
                          side: const BorderSide(color: _border),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
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
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await Share.share(_inviteMessage());
                          },
                          icon: const Icon(Icons.share_rounded, size: 18),
                          label: Text(
                            t.get('share'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
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
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.get('how_it_works'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 10),
                _HowRow(text: t.get('invite_step_1')),
                const SizedBox(height: 8),
                _HowRow(text: t.get('invite_step_2')),
                const SizedBox(height: 8),
                _HowRow(text: t.get('invite_step_3')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.get('important'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  t.get('invite_important_text'),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _HowRow extends StatelessWidget {
  final String text;
  const _HowRow({required this.text});


  static const Color _muted = Color(0xFF374151);


  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: Color(0xFF2563EB),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.3,
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
