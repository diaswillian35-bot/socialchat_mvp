import 'package:flutter/material.dart';
import '../widget/remdy_app.dart';


class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});


  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: const RemdyAppBar(title: 'Política de Privacidade'),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
            '''
POLÍTICA DE PRIVACIDADE – REMDY
Última atualização: 2026


1. INFORMAÇÕES COLETADAS
O Remdy pode coletar:
• Nome e email
• País e idioma
• Foto de perfil
• Mensagens enviadas dentro do app
• Token de notificação para envio de alertas


2. COMO USAMOS OS DADOS
Utilizamos os dados para:
• Criar sua conta
• Permitir conversas entre usuários
• Melhorar o funcionamento do aplicativo
• Enviar notificações importantes


3. COMPARTILHAMENTO
O Remdy não vende dados pessoais.
Informações podem ser usadas apenas para funcionamento do serviço.


4. SEGURANÇA
Seus dados são armazenados em servidores seguros
utilizando tecnologias como Firebase.


5. CONTEÚDO DO USUÁRIO
Usuários são responsáveis pelas mensagens enviadas.
Conteúdos ofensivos, ilegais ou abusivos podem resultar em banimento.


6. ALTERAÇÕES
Esta política pode ser atualizada a qualquer momento.


7. CONTATO
Email: contact@remdy.app
''',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: _text,
            ),
          ),
        ),
      ),
    );
  }
}
