import 'package:flutter/material.dart';


class TermsPage extends StatelessWidget {
  const TermsPage({super.key});


  // Remdy style
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


  static const String _terms = '''
Termos de Uso — Remdy 
Última atualização: 2026


Bem-vindo ao Remdy. Ao utilizar o aplicativo, você concorda com os termos abaixo.


1. Sobre o Remdy
O Remdy é uma plataforma destinada a:
• Fazer amizades reais entre pessoas
• Praticar idiomas
• Participar de conversas e grupos
• Compartilhar experiências culturais


O Remdy não é um aplicativo de relacionamento amoroso e não utiliza bots para conversar com usuários.


2. Regras de uso
Ao utilizar o aplicativo, você concorda em:
• Respeitar outros usuários
• Não enviar conteúdo ofensivo, ilegal ou impróprio
• Não compartilhar pornografia, violência ou discurso de ódio
• Não enviar links maliciosos ou spam
• Não tentar enganar ou aplicar golpes


Contas que violarem essas regras podem ser advertidas, suspensas ou banidas permanentemente, sem aviso prévio em casos graves.


3. Fotos e perfil
Ao enviar fotos ou informações:
• Você declara que possui direito de uso dessas imagens
• Não deve enviar fotos ofensivas ou impróprias
• O Remdy pode remover conteúdo que viole as regras


4. Privacidade
O Remdy coleta apenas dados necessários para funcionamento, como:
• Nome e perfil
• Idioma e país
• Mensagens e interações
• Token de notificação


Esses dados são usados apenas para funcionamento do aplicativo e segurança.
O Remdy não vende dados pessoais.


5. Segurança
O Remdy se esforça para manter um ambiente seguro, mas:
• Não pode garantir o comportamento de outros usuários
• Recomenda não compartilhar informações pessoais sensíveis


6. Premium
Alguns recursos podem ser pagos.
• Benefícios podem mudar ou evoluir
• Assinaturas seguem as regras da App Store ou Google Play


7. Disponibilidade
O aplicativo pode passar por manutenção, ter atualizações e alterar recursos sem aviso prévio.


8. Encerramento de conta
O usuário pode parar de usar o aplicativo a qualquer momento.
O Remdy pode encerrar contas que violem os termos.


9. Alterações nos termos
Os termos podem ser atualizados para melhorar o serviço.
O uso contínuo do aplicativo significa aceitação das mudanças.


10. Contato
Para dúvidas ou suporte:
contact@remdy.app
''';


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
        automaticallyImplyLeading: true,
        title: const Text(
          'Termos',
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
                  'Termos de Uso',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _text,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Leia com atenção. Ao usar o Remdy, você concorda com estes termos.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 12),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: SelectableText(
              _terms,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: _text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          
        ],
      ),
    );
  }
}
