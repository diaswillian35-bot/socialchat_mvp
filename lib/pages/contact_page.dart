import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'support_contact_page.dart';
import '../l10n/app_texts.dart';


class ContactPage extends StatelessWidget {
  const ContactPage({super.key});


  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);


  static const LinearGradient _primaryGradient = LinearGradient(
    colors: [
      Color(0xFF313A5F),
      Color(0xFF264E9A),
    ],
  );


  static const bool enableWhatsApp = false;
  static const bool enableEmail = true;
  static const bool enableInstagram = true;


  static const String whatsappNumberE164 = '+14160000000';
  static const String whatsappMessage = 'Olá! Preciso de ajuda no Remdy.';
  static const String supportEmail = 'support@remdy.app';
  static const String instagramUrl = 'https://www.instagram.com/remdy.app/';


  Future<void> _open(BuildContext context, String url) async {
    final t = AppTexts.current;
    final uri = Uri.parse(url);


    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.get('cannot_open_link')),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(12),
          ),
        );
      }
      return;
    }


    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }


  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }


  Widget _btn({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final t = AppTexts.current;


    return InkWell(
      onTap: enabled
          ? onTap
          : () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(t.get('coming_soon')),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(12),
                ),
              );
            },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: _primaryGradient,
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              enabled ? Icons.arrow_forward_ios : Icons.lock_outline,
              size: 16,
              color: const Color(0xFF6B7280),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;


    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        iconTheme: const IconThemeData(color: _muted),
        title: Text(
          t.get('contact'),
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.get('contact_title'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t.get('contact_subtitle'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),


          _btn(
            context: context,
            icon: Icons.email_outlined,
            title: t.get('email'),
            subtitle: supportEmail,
            enabled: enableEmail,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SupportContactPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 10),


          _btn(
            context: context,
            icon: Icons.camera_alt_outlined,
            title: 'Instagram',
            subtitle: '@remdy.app',
            enabled: enableInstagram,
            onTap: () => _open(context, instagramUrl),
          ),
        ],
      ),
    );
  }
}
