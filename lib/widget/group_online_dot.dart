import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';


class GroupOnlineDot extends StatefulWidget {
  final List<String> memberIds;


  /// Se true: verde quando qualquer membro estiver online
  /// Se false: sempre vermelho (debug)
  final bool enabled;


  /// Tamanho do pontinho
  final double size;


  /// Tempo máximo (em segundos) para considerar "online" via lastSeen fallback
  /// (caso seu sistema não tenha isOnline)
  final int lastSeenWindowSeconds;


  const GroupOnlineDot({
    super.key,
    required this.memberIds,
    this.enabled = true,
    this.size = 10,
    this.lastSeenWindowSeconds = 120, // 2 minutos
  });


  @override
  State<GroupOnlineDot> createState() => _GroupOnlineDotState();
}


class _GroupOnlineDotState extends State<GroupOnlineDot> {
  Timer? _timer;
  bool _anyOnline = false;
  bool _loading = true;


  @override
  void initState() {
    super.initState();
    _tick(); // carrega na hora
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
  }


  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }


  Future<void> _tick() async {
    if (!mounted) return;


    final ids = widget.memberIds
        .where((e) => e.trim().isNotEmpty)
        .map((e) => e.trim())
        .toSet()
        .toList();


    if (!widget.enabled || ids.isEmpty) {
      if (!mounted) return;
      setState(() {
        _anyOnline = false;
        _loading = false;
      });
      return;
    }


    try {
      // Busca em lotes de 10 por causa do whereIn
      bool anyOnline = false;


      for (int i = 0; i < ids.length; i += 10) {
        final chunk = ids.sublist(i, (i + 10 > ids.length) ? ids.length : i + 10);


        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();


        for (final doc in snap.docs) {
          final d = doc.data();


          // ✅ TENTA 1: campo booleano "isOnline"
          final isOnline = (d['isOnline'] == true);


          // ✅ TENTA 2 (fallback): lastSeen/lastActive recente
          // Ajuste aqui se seu campo tiver outro nome:
          final ts = d['lastSeenAt'] ?? d['lastActiveAt'] ?? d['lastSeen'] ?? d['lastActive'];
          DateTime? last;
          if (ts is Timestamp) last = ts.toDate();


          final recent = (last != null)
              ? DateTime.now().difference(last).inSeconds <= widget.lastSeenWindowSeconds
              : false;


          if (isOnline || recent) {
            anyOnline = true;
            break;
          }
        }


        if (anyOnline) break;
      }


      if (!mounted) return;
      setState(() {
        _anyOnline = anyOnline;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _anyOnline = false;
        _loading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final color = _anyOnline ? Colors.green : Colors.red;


    // opcional: enquanto carrega, deixa cinza
    final dotColor = _loading ? Colors.grey : color;


    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}
