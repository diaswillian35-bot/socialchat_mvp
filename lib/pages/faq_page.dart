import 'package:flutter/material.dart';


class FaqPage extends StatelessWidget {
  const FaqPage({super.key});


  // Remdy style (igual padrão)
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


  Widget _qa({
    required String q,
    required String a,
  }) {
    return _card(
      child: Theme(
        data: ThemeData(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          title: Text(
            q,
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          iconColor: _muted,
          collapsedIconColor: _muted,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                a,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,


        // ✅ flecha voltar (volta pro menu)
        automaticallyImplyLeading: true,


        title: const Text(
          'FAQ',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Dúvidas frequentes',
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Aqui você encontra respostas rápidas sobre o Remdy.',
                  style: TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),


          _qa(
            q: 'O que é o Remdy?',
            a: 'Um app de amizade e prática de idiomas com pessoas reais.',
          ),
          const SizedBox(height: 10),


          _qa(
            q: 'Como funciona o Premium?',
            a: 'O Premium libera recursos extras. Você pode ver os detalhes na tela Premium.',
          ),
          const SizedBox(height: 10),


          _qa(
            q: 'Por que não consigo falar com alguns países?',
            a: 'No plano grátis, você conversa apenas com seu país. Outros países aparecem como Premium.',
          ),
          const SizedBox(height: 10),


          _qa(
            q: 'Como mudar o idioma do app?',
            a: 'Abra o Menu > Idioma e selecione Português, English, Español ou Français.',
          ),
          const SizedBox(height: 10),


          _qa(
            q: 'Como ativar/desativar notificações?',
            a: 'Abra o Menu > Notificações e ajuste as opções. No celular, também verifique as permissões do app.',
          ),


          const SizedBox(height: 16),


          // ✅ botão padrão Remdy (opcional: só “Voltar”)
          
        ],
      ),
    );
  }
}
