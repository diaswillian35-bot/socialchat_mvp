import 'package:flutter/material.dart';


class AboutPage extends StatelessWidget {
  const AboutPage({super.key});


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
        title: const Text(
          'Sobre',
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
                  'Sobre o Remdy',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _text,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'O Remdy é um aplicativo criado para conectar pessoas reais ao redor do mundo de forma simples, natural e segura.\n\n'
                  'Vivemos em uma era em que existem muitas redes sociais, mas poucas realmente ajudam as pessoas a criar conexões verdadeiras. '
                  'O Remdy nasceu com um propósito diferente: aproximar pessoas, culturas e idiomas através de conversas reais.\n\n'
                  'Nossa ideia\n'
                  'Aprender um idioma, fazer amigos em outros países ou conhecer novas culturas não deveria ser difícil.\n\n'
                  'Acreditamos que a melhor forma de aprender é conversando, trocando experiências e vivendo o idioma no dia a dia.\n\n'
                  'Por isso, o Remdy foi criado para permitir que qualquer pessoa possa:\n'
                  '• Conversar com pessoas reais\n'
                  '• Praticar idiomas naturalmente\n'
                  '• Fazer novas amizades\n'
                  '• Descobrir culturas diferentes\n\n'
                  'Sem complicações. Sem algoritmos confusos. Apenas pessoas conectando com pessoas.\n\n'
                  'Um aplicativo global desde o início\n'
                  'O Remdy foi pensado para o mundo. Desde o primeiro dia, o objetivo sempre foi criar uma comunidade internacional.\n\n'
                  'Segurança e respeito\n'
                  'Criar um ambiente saudável é prioridade. Trabalhamos com regras claras, moderação e controles para proteger os usuários.\n\n'
                  'Estamos apenas começando\n'
                  'O Remdy ainda está em crescimento, e muitas novidades estão a caminho.\n\n'
                  'Obrigado por fazer parte\n'
                  'O Remdy não é apenas um aplicativo. É uma comunidade global construída por pessoas, para pessoas.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 46,
            decoration: BoxDecoration(
              gradient: _primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              label: const Text(
                'Voltar',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
