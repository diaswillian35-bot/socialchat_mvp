import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


class SupportContactPage extends StatefulWidget {
  const SupportContactPage({super.key});


  @override
  State<SupportContactPage> createState() => _SupportContactPageState();
}


class _SupportContactPageState extends State<SupportContactPage> {
  final _subjectC = TextEditingController();
  final _messageC = TextEditingController();


  bool _sending = false;


  @override
  void dispose() {
    _subjectC.dispose();
    _messageC.dispose();
    super.dispose();
  }


  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }


  Future<void> _send() async {
    if (_sending) return;


    final subject = _subjectC.text.trim();
    final message = _messageC.text.trim();


    if (subject.isEmpty) {
      _toast('Digite um assunto.');
      return;
    }
    if (message.isEmpty) {
      _toast('Digite sua mensagem.');
      return;
    }


    setState(() => _sending = true);


    try {
      final user = FirebaseAuth.instance.currentUser;


      await FirebaseFirestore.instance.collection('supportTickets').add({
        'subject': subject,
        'message': message,


        // usuário (se estiver logado)
        'uid': user?.uid,
        'email': user?.email,


        // status do ticket
        'status': 'open', // open | closed
        'createdAt': FieldValue.serverTimestamp(),


        // opcional (ajuda muito no admin)
        'app': 'Remdy',
        'platform': Theme.of(context).platform.toString(),
      });


      if (!mounted) return;
      _toast('✅ Mensagem enviada! Nossa equipe vai responder em breve.');
      Navigator.pop(context);
    } catch (e) {
      _toast('Erro ao enviar. Tente novamente.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFF313A5F); // azul Remdy


    return Scaffold(
      appBar: AppBar(
        title: const Text('Fale com a Remdy'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // LOGO EM CIMA (se você tiver assets/remdy_logo.png)
            Center(
              child: Column(
                children: [
                  Image.asset(
                    'assets/remdy_logo.png',
                    height: 70,
                    errorBuilder: (_, __, ___) => const SizedBox(height: 70),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Suporte Remdy',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Envie sua mensagem e a gente te responde por e-mail.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),


            const SizedBox(height: 18),


            // Assunto
            TextField(
              controller: _subjectC,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Assunto',
                hintText: 'Ex: Não consigo entrar',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),


            const SizedBox(height: 12),


            // Mensagem
            TextField(
              controller: _messageC,
              minLines: 6,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: 'Mensagem',
                hintText: 'Explique o que aconteceu...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),


            const SizedBox(height: 16),


            // Botão enviar
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _sending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _sending
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Enviar',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
              ),
            ),


            const SizedBox(height: 10),


            const Text(
              'Dica: Se estiver bloqueado, mande print e descreva o ocorrido.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
