import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/block_service.dart';

class PublicProfilePage extends StatelessWidget {
  final String userUid;

  const PublicProfilePage({
    super.key,
    required this.userUid,
  });

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  // ====== converte código/nome para rótulo bonito e consistente ======
  static const Map<String, String> _langMap = {
    'en': 'Inglês',
    'fr': 'Francês',
    'es': 'Espanhol',
    'pt': 'Português',
    'it': 'Italiano',
    'de': 'Alemão',
  };

  String _normalizeLang(dynamic raw) {
    final v = (raw ?? '').toString().trim();
    if (v.isEmpty) return '';

    final lower = v.toLowerCase();

    if (_langMap.containsKey(lower)) return _langMap[lower]!;

    if (lower == 'portugues' || lower == 'português') return 'Português';
    if (lower == 'ingles' || lower == 'inglês' || lower == 'english') return 'Inglês';
    if (lower == 'frances' || lower == 'francês' || lower == 'french') return 'Francês';
    if (lower == 'espanhol' || lower == 'spanish') return 'Espanhol';
    if (lower == 'alemao' || lower == 'alemão' || lower == 'german') return 'Alemão';
    if (lower == 'italiano' || lower == 'italian') return 'Italiano';

    return v;
  }

  List<String> _galleryFrom(Map<String, dynamic> data) {
    final raw = data['gallery'];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  void _openPhoto(BuildContext context, List<String> urls, int initialIndex) {
  if (urls.isEmpty) return;


  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _PhotoCarouselPage(
        urls: urls,
        initialIndex: initialIndex.clamp(0, urls.length - 1),
      ),
    ),
  );
}

  Future<void> _toggleBlock(BuildContext context, bool isBlocked) async {
    try {
      if (isBlocked) {
        await BlockService.unblockUser(userUid);
      } else {
        await BlockService.blockUser(userUid);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar bloqueio: $e')),
      );
    }
  }
 // ====== REPORT (perfil público) ======
 

Future<void> _sendReport(BuildContext context, String reason) async {
  try {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    await FirebaseFirestore.instance.collection('reports').add({
      'fromUid': myUid,
      'reportedUid': userUid,
      'reason': reason,
      'status': 'open',
      'contextType': 'profile',
      'source': 'public_profile',
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report enviado. Obrigado!')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erro ao enviar report: $e')),
    );
  }
}



  // ====== cores/estilo (somente visual) ======
  static const Color _primary = Color(0xFF313A5F); // azul Remdy
  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _card = Colors.white;

  bool _isOnlineFrom(Map<String, dynamic> data) {
    // não muda lógica do app, só um indicador visual
    final raw = data['lastSeenAt'];
    if (raw is! Timestamp) return false;

    final last = raw.toDate();
    final now = DateTime.now();
    // mesmo padrão do seu Home: 90s
    return now.difference(last) <= const Duration(seconds: 90);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Você precisa estar logado.')),
      );
    }

    final isMe = userUid == _myUid;
    final userDoc = _userDoc(userUid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Perfil')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Erro ao carregar perfil:\n${snap.error}'),
            ),
          );
        }

        final data = snap.data?.data();
        if (data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Perfil')),
            body: const Center(child: Text('Perfil não encontrado.')),
          );
        }

        final name = (data['name'] ?? '').toString().trim();
        final country = (data['country'] ?? '').toString().trim();
        final about = (data['about'] ?? '').toString().trim();
        final photoUrl = (data['photoUrl'] ?? data['photoURL'] ?? '').toString().trim();

        final nativeLang = _normalizeLang(
          data['nativeLanguage'] ??
              data['native_language'] ??
              data['nativeLanguageCode'] ??
              data['nativeLang'] ??
              '',
        );

        final learningLang = _normalizeLang(
          data['learningLanguage'] ??
              data['learning_language'] ??
              data['learningLang'] ??
              data['studyingLanguageName'] ??
              data['studyingLanguageCode'] ??
              data['learningLanguageCode'] ??
              '',
        );

        final gallery = _galleryFrom(data);
        final bool hasLastSeen = data['lastSeenAt'] is Timestamp;
        final bool isOnline = hasLastSeen ? _isOnlineFrom(data) : false;

        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            elevation: 0,
            title: null,
            centerTitle: false,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              // ===== Card principal (estilo referência) =====
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
  radius: 26, // 52 / 2
  backgroundColor: const Color(0xFFF1F5F9),
  backgroundImage:
      photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
  child: photoUrl.isEmpty
      ? const Icon(Icons.person, color: Color(0xFF6B7280))
      : null,
),

                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.isEmpty ? 'Usuário' : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: _text,
                                ),
                              ),
                              const SizedBox(height: 6),

                              // Status + País (bem parecido com a referência)
                              Row(
                                children: [
                                  if (hasLastSeen) ...[
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: isOnline ? Colors.green : const Color(0xFF9CA3AF),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isOnline ? 'Online' : 'Offline',
                                      style: const TextStyle(
                                        color: _muted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                  if (country.isNotEmpty) ...[
                                    const Icon(Icons.place_rounded, size: 16, color: _muted),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        country,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Botões grandes (estilo referência)
                    // Botões grandes (estilo referência)
Row(
  children: [
    Expanded(
  child: OutlinedButton.icon(
    onPressed: () => _openReportSheet(context, name),
    icon: const Icon(Icons.flag),
    label: const Text(
      'Reportar',
      style: TextStyle(fontWeight: FontWeight.w900),
    ),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14),
      side: BorderSide(color: Colors.grey.shade300),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      backgroundColor: Colors.white,
    ),
  ),
),
const SizedBox(width: 12),

    Expanded(
      child: (!isMe)
          ? StreamBuilder<bool>(
              stream: BlockService.isBlockedStream(userUid),
              initialData: false,
              builder: (context, blockSnap) {
                final isBlockedNow = blockSnap.data ?? false;

                return ElevatedButton.icon(
                  onPressed: () => _toggleBlock(context, isBlockedNow),
                  icon: Icon(
                    isBlockedNow ? Icons.lock_open_rounded : Icons.block_rounded,
                  ),
                  label: Text(
                    isBlockedNow ? 'Desbloquear' : 'Bloquear',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                );
              },
            )
          : ElevatedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text(
                'Você',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: _primary.withOpacity(0.25),
                foregroundColor: _primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
    ),
  ],
),

                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ===== Idiomas (card clean) =====
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Idiomas',
                        style: TextStyle(fontWeight: FontWeight.w900, color: _text)),
                    const SizedBox(height: 10),

                    _InfoRow(
                      icon: Icons.record_voice_over_rounded,
                      title: 'Nativo',
                      value: nativeLang.isEmpty ? '-' : nativeLang,
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      icon: Icons.school_rounded,
                      title: 'Aprendendo',
                      value: learningLang.isEmpty ? '-' : learningLang,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ===== Sobre (card clean) =====
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sobre',
                        style: TextStyle(fontWeight: FontWeight.w900, color: _text)),
                    const SizedBox(height: 10),
                    Text(
                      about.isEmpty ? '-' : about,
                      style: const TextStyle(
                        color: _text,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ===== Fotos (galeria) =====
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Fotos',
                        style: TextStyle(fontWeight: FontWeight.w900, color: _text)),
                    const SizedBox(height: 10),

                    if (gallery.isEmpty)
                      Text('-', style: TextStyle(color: Colors.grey.shade700))
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: gallery.length > 9 ? 9 : gallery.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemBuilder: (context, i) {
                          final url = gallery[i];
                          return GestureDetector(
                            onTap: () => _openPhoto(context, gallery, i),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                color: Colors.grey.shade200,
                                child: Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.broken_image, color: Colors.black38),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                    const SizedBox(height: 8),
                    Text(
                      'Toque para abrir.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
void _openReportSheet(BuildContext context, String name) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.report),
            title: Text('Reportar $name'),
          ),
          ListTile(
            title: const Text('Conteúdo impróprio'),
            onTap: () {
              Navigator.pop(context);
              _sendReport(context, 'Conteúdo impróprio');
            },
          ),
          ListTile(
            title: const Text('Spam'),
            onTap: () {
              Navigator.pop(context);
              _sendReport(context, 'Spam');
            },
          ),
          ListTile(
            title: const Text('Assédio'),
            onTap: () {
              Navigator.pop(context);
              _sendReport(context, 'Assédio');
            },
          ),
          ListTile(
            title: const Text('Perfil falso'),
            onTap: () {
              Navigator.pop(context);
              _sendReport(context, 'Perfil falso');
            },
          ),
          ListTile(
            title: const Text('Outro'),
            onTap: () {
              Navigator.pop(context);
              _sendReport(context, 'Outro');
            },
          ),
        ],
      ),
    ),
  );
}


}

// ===== helpers visuais (não mexem na lógica) =====
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _muted),
        const SizedBox(width: 10),
        Text(
          '$title:',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: _text,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: _muted,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
class _PhotoCarouselPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;


  const _PhotoCarouselPage({
    required this.urls,
    required this.initialIndex,
  });


  @override
  State<_PhotoCarouselPage> createState() => _PhotoCarouselPageState();
}


class _PhotoCarouselPageState extends State<_PhotoCarouselPage> {
  late final PageController _controller;


  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }


  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Fotos'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        itemBuilder: (_, index) {
          final url = widget.urls[index];
          return InteractiveViewer(
            child: Center(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image, color: Colors.white, size: 48),
              ),
            ),
          );
        },
      ),
    );
  }
}
