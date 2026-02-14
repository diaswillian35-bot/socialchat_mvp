import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

class PostUploaderPage extends StatefulWidget {
  const PostUploaderPage({super.key});

  @override
  State<PostUploaderPage> createState() => _PostUploaderPageState();
}

class _PostUploaderPageState extends State<PostUploaderPage> {
  final _captionC = TextEditingController();
  final _picker = ImagePicker();
  final _uuid = const Uuid();

  bool _uploading = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickAndUploadPost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack("Você precisa estar logado.");
      return;
    }

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploading = true);

    final postId = _uuid.v4();
    final fileName = "${DateTime.now().millisecondsSinceEpoch}.jpg";

    try {
      _snack("Enviando foto...");

      final storageRef =
          FirebaseStorage.instance.ref().child("posts/$postId/$fileName");

      // Upload (mobile vs web)
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        await storageRef.putData(
          bytes,
          SettableMetadata(contentType: "image/jpeg"),
        );
      } else {
        await storageRef.putFile(File(picked.path));
      }

      final imageUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('posts').doc(postId).set({
        'id': postId,
        'uid': user.uid,
        'imageUrl': imageUrl,
        'caption': _captionC.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      _snack("Post publicado ✅");
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack("Erro ao publicar: $e");
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _captionC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Novo post")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _captionC,
              decoration: const InputDecoration(
                labelText: "Legenda (opcional)",
                border: OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _uploading ? null : _pickAndUploadPost,
                icon: const Icon(Icons.photo_library),
                label: Text(_uploading ? "Enviando..." : "Escolher foto e publicar"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}