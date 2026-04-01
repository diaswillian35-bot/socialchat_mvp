import 'dart:io';
import 'dart:typed_data';


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';


class SupportContactPage extends StatefulWidget {
  const SupportContactPage({super.key});


  @override
  State<SupportContactPage> createState() => _SupportContactPageState();
}


class _SupportContactPageState extends State<SupportContactPage> {
  // Remdy
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


  final ImagePicker _picker = ImagePicker();


  /// Anexos (mobile = path; web = bytes)
  final List<XFile> _attachments = [];


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


  Future<void> _pickImages() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1600);
      if (files.isEmpty) return;


      setState(() {
        // limita pra não virar “bomba”
        final spaceLeft = 5 - _attachments.length;
        if (spaceLeft <= 0) return;
        _attachments.addAll(files.take(spaceLeft));
      });


      if (_attachments.length >= 5) {
        _toast('Máximo de 5 anexos.');
      }
    } catch (e) {
      _toast('Não consegui abrir a galeria. ($e)');
    }
  }


  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }


  bool _isValidEmail(String v) {
    final s = v.trim();
    if (s.isEmpty) return false;
    // simples e suficiente pro app
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
  }


  Future<List<Map<String, dynamic>>> _uploadAttachments(String ticketId) async {
    // retorna lista com {url, path, name}
    final out = <Map<String, dynamic>>[];


    for (int i = 0; i < _attachments.length; i++) {
      final f = _attachments[i];
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = (f.name.contains('.')) ? f.name.split('.').last : 'jpg';
      final storagePath = 'supportTickets/$ticketId/att_${ts}_$i.$ext';


      final ref = FirebaseStorage.instance.ref(storagePath);


      if (kIsWeb) {
        final Uint8List bytes = await f.readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'image/$ext'));
      } else {
        await ref.putFile(File(f.path));
      }


      final url = await ref.getDownloadURL();


      out.add({
        'url': url,
        'path': storagePath,
        'name': f.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }


    return out;
  }


  Future<void> _send() async {
    if (_sending) return;


    final subject = _subjectC.text.trim();
    final message = _messageC.text.trim();
    final email = _emailC.text.trim();
    final phone = _phoneC.text.trim();


    if (subject.isEmpty) {
      _toast('Digite um assunto.');
      return;
    }
    if (message.isEmpty) {
      _toast('Digite sua mensagem.');
      return;
    }
    if (!_isValidEmail(email)) {
      _toast('Digite um e-mail válido para retorno.');
      return;
    }


    setState(() => _sending = true);


    try {
      final user = FirebaseAuth.instance.currentUser;


      // 1) cria ticket primeiro (pra ter ticketId)
      final ticketRef = FirebaseFirestore.instance.collection('supportTickets').doc();


      await ticketRef.set({
        'subject': subject,
        'message': message,
        'replyEmail': email,
        'replyPhone': phone,


        'uid': user?.uid,
        'userEmail': user?.email,


        'status': 'open', // open | closed
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),


        'app': 'Remdy',
        'platform': Theme.of(context).platform.toString(),


        'attachmentsCount': _attachments.length,
      });


      // 2) upload anexos (se tiver)
      List<Map<String, dynamic>> attachments = [];
      if (_attachments.isNotEmpty) {
        attachments = await _uploadAttachments(ticketRef.id);


        // grava urls no ticket
        await ticketRef.set({
          'attachments': attachments.map((e) => {
                'url': e['url'],
                'path': e['path'],
                'name': e['name'],
              }).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }


      if (!mounted) return;
      _toast('✅ Enviado! Vamos responder no e-mail informado.');
      Navigator.pop(context, true);
    } catch (e) {
      _toast('Erro ao enviar. Tente novamente. ($e)');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
  backgroundColor: Colors.white,
  surfaceTintColor: Colors.transparent, // remove overlay Material 3
  elevation: 0,
  scrolledUnderElevation: 0,
  shadowColor: Colors.transparent,
  foregroundColor: const Color(0xFF111827),
  title: const Text(
    'Fale com a Remdy',
    style: TextStyle(
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
                  const Text(
                    'Suporte Remdy',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _text),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Envie sua mensagem. Se puder, anexe um print do problema.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),


            const SizedBox(height: 18),


            // E-mail
            TextField(
              controller: _emailC,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Seu e-mail (para retorno)',
                hintText: 'ex: seuemail@gmail.com',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
            ),
            const SizedBox(height: 12),


            // Telefone (opcional)
            TextField(
              controller: _phoneC,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Telefone (opcional)',
                hintText: 'ex: +1 416 000 0000',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
            ),
            const SizedBox(height: 12),


            // Assunto
            TextField(
              controller: _subjectC,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Assunto',
                hintText: 'Ex: Não consigo entrar / Bug em grupos',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
            ),


            const SizedBox(height: 12),


            // Mensagem
            TextField(
              controller: _messageC,
              minLines: 6,
              maxLines: 12,
              decoration: InputDecoration(
                labelText: 'Mensagem',
                hintText: 'Explique o que aconteceu e onde…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
            ),


            const SizedBox(height: 12),


            // Anexos
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.attach_file_rounded, color: _muted),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Anexar prints/fotos (até 5)',
                          style: TextStyle(fontWeight: FontWeight.w800, color: _text),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _sending ? null : _pickImages,
                        icon: const Icon(Icons.add_photo_alternate_rounded),
                        label: const Text('Adicionar', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                  if (_attachments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Dica: mande print do erro (ajuda muito a resolver rápido).',
                        style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: List.generate(_attachments.length, (i) {
                          final f = _attachments[i];


                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 86,
                                  height: 86,
                                  color: const Color(0xFFF3F4F6),
                                  child: kIsWeb
                                      ? FutureBuilder<Uint8List>(
                                          future: f.readAsBytes(),
                                          builder: (context, snap) {
                                            final Uint8List? b = snap.data;
                                            if (b == null) {
                                              return const Center(
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              );
                                            }
                                            return Image.memory(b, fit: BoxFit.cover);
                                          },
                                        )
                                      : Image.file(File(f.path), fit: BoxFit.cover),
                                ),
                              ),


                              // remover (bolinha vermelha)
                              Positioned(
                                right: -8,
                                top: -8,
                                child: InkWell(
                                  onTap: _sending ? null : () => _removeAttachment(i),
                                  borderRadius: BorderRadius.circular(999),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                ],
              ),
            ),


            const SizedBox(height: 16),


            // Botão enviar (texto branco)
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _sending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _sending
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Enviar',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
              ),
            ),


            const SizedBox(height: 10),


            const Text(
              'Você receberá resposta no e-mail informado.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
