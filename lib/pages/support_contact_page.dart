import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_texts.dart';

class SupportContactPage extends StatefulWidget {
  const SupportContactPage({super.key});

  @override
  State<SupportContactPage> createState() => _SupportContactPageState();
}

class _SupportContactPageState extends State<SupportContactPage> {
  static const Color _primary = Color(0xFF313A5F);
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  final _subjectC = TextEditingController();
  final _messageC = TextEditingController();
  final _emailC = TextEditingController();
  final _phoneC = TextEditingController();

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null && (user!.email!).trim().isNotEmpty) {
      _emailC.text = user.email!.trim();
    }
  }

  @override
  void dispose() {
    _subjectC.dispose();
    _messageC.dispose();
    _emailC.dispose();
    _phoneC.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  bool _isValidEmail(String v) {
    final s = v.trim();
    if (s.isEmpty) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
  }

  Future<void> _send() async {
    final t = AppTexts.current;

    if (_sending) return;

    final subject = _subjectC.text.trim();
    final message = _messageC.text.trim();
    final email = _emailC.text.trim();
    final phone = _phoneC.text.trim();

    if (subject.isEmpty) {
      _toast(t.get('support_contact_subject_required'));
      return;
    }
    if (message.isEmpty) {
      _toast(t.get('support_contact_message_required'));
      return;
    }
    if (!_isValidEmail(email)) {
      _toast(t.get('support_contact_invalid_email'));
      return;
    }

    setState(() => _sending = true);

    try {
      final body = '''
${t.get('support_contact_email_for_reply')}: $email
${t.get('support_contact_phone_label')}: ${phone.isEmpty ? t.get('support_contact_not_informed') : phone}

${t.get('support_contact_subject_label')}: $subject

${t.get('support_contact_message_label')}:
$message
''';

      final uri = Uri.parse(
        'mailto:support@remdy.app'
        '?subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}',
      );

      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        _toast(t.get('support_contact_email_app_error'));
        return;
      }
    } catch (e) {
      _toast('${t.get('support_contact_open_email_error')} ($e)');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        foregroundColor: const Color(0xFF111827),
        title: Text(
          t.get('support_contact_appbar_title'),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(
                children: [
                  Image.asset(
                    'assets/remdy_logo.png',
                    height: 70,
                    errorBuilder: (_, __, ___) => const SizedBox(height: 70),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t.get('support_contact_title'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.get('support_contact_subtitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _emailC,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: t.get('support_contact_email_label'),
                hintText: t.get('support_contact_email_hint'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneC,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: t.get('support_contact_phone_label'),
                hintText: t.get('support_contact_phone_hint'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subjectC,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: t.get('support_contact_subject_label'),
                hintText: t.get('support_contact_subject_hint'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageC,
              minLines: 6,
              maxLines: 12,
              decoration: InputDecoration(
                labelText: t.get('support_contact_message_label'),
                hintText: t.get('support_contact_message_hint'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _sending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _sending
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        t.get('support_contact_send'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              t.get('support_contact_footer'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
