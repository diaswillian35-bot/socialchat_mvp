  import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'suport_contact_page.dart';


class ContactPage extends StatelessWidget {
  const ContactPage({super.key});


  // ✅ Remdy style (igual padrão)
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);


  static const LinearGradient _primaryGradient = LinearGradient(
    colors: [
      Color(0xFF313A5F), // azul Remdy
      Color(0xFF264E9A), // azul logo
    ],
  );


  // =========================
  // ✅ ATIVA/DESATIVA AQUI
  // =========================
  static const bool enableWhatsApp = false;
  static const bool enableEmail = true;
  static const bool enableInstagram = true;


  // =========================
  // ✅ SEUS LINKS AQUI
  // =========================
  static const String whatsappNumberE164 = '+14160000000'; // ex: +1416...
  static const String whatsappMessage = 'Olá! Preciso de ajuda no Remdy.';
  static const String supportEmail = 'support@remdy.app';


  // ✅ link limpo (abre o @remdy.app certo)
  static const String instagramUrl = 'https://www.instagram.com/remdy.app/';


  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);


    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir no seu celular.'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(12),
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
    return InkWell(
      onTap: enabled
          ? onTap
          : () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Em breve ✅'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                  margin: EdgeInsets.all(12),
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
              // ✅ antes estava fixo no mail; agora usa o icon do botão
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
    return Scaffold(
      backgroundColor: _bg,


      // ✅ AppBar branco (sem rosa / sem M3 tint)
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        iconTheme: const IconThemeData(color: _muted),
        title: const Text(
          'Contato',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),


      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _card(
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fale com a gente',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _text,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Escolha um canal. Se estiver “bloqueado”, é só ativar depois.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),


     


          // ✅ Email
          _btn(
            context: context,
            icon: Icons.email_outlined,
            title: 'E-mail',
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


          // ✅ Instagram
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
