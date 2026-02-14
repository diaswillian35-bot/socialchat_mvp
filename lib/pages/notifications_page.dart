import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


import '../services/push_service.dart';


class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});


  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}


class _NotificationsPageState extends State<NotificationsPage> {
  final db = FirebaseFirestore.instance;


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


  String? get _uid => FirebaseAuth.instance.currentUser?.uid;


  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      db.collection('users').doc(uid);


  bool _saving = false;


  // prefs
  bool _enabled = true;
  bool _chat = true;
  bool _groups = true;
  bool _events = true;


  @override
  void initState() {
    super.initState();
    _load();
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


  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;


    try {
      final snap = await _userDoc(uid).get();
      final data = snap.data() ?? {};


      // defaults caso não exista
      final enabled = (data['notifEnabled'] ?? true) == true;
      final chat = (data['notifChat'] ?? true) == true;
      final groups = (data['notifGroups'] ?? true) == true;
      final events = (data['notifEvents'] ?? true) == true;


      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _chat = chat;
        _groups = groups;
        _events = events;
      });
    } catch (_) {
      // silencioso
    }
  }


  Future<void> _save() async {
    final uid = _uid;
    if (uid == null) return;


    setState(() => _saving = true);


    try {
      // salva prefs (backup no Firestore)
      await _userDoc(uid).set({
        'notifEnabled': _enabled,
        'notifChat': _chat,
        'notifGroups': _groups,
        'notifEvents': _events,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));


      // aplica efeito real no push (o principal)
      if (_enabled) {
        final ok = await PushService.enableAndSyncToken(uid);
        if (!mounted) return;


        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? 'Notificações ativadas ✅'
                : 'Ativado, mas sem permissão no celular. Libere em Ajustes.'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        await PushService.disableAndClearToken(uid);
        if (!mounted) return;


        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notificações desativadas ✅'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(12),
            duration: Duration(seconds: 1),
          ),
        );
      }


      // seu fluxo: salva e volta pro menu
      if (Navigator.canPop(context)) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar: $e'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Você precisa estar logado.')),
      );
    }


    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: true, // ✅ flecha voltar
        title: const Text(
          'Notificações',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Preferências',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Controle quais notificações você quer receber.',
                    style: TextStyle(
                      fontSize: 13,
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),


                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                    title: const Text(
                      'Ativar notificações',
                      style: TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: const Text(
                      'Se desligar, o app para de receber push.',
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),


                  const Divider(height: 14),


                  // desabilita opções se _enabled=false (visual)
                  Opacity(
                    opacity: _enabled ? 1 : 0.45,
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _chat,
                          onChanged: _enabled ? (v) => setState(() => _chat = v) : null,
                          title: const Text(
                            'Mensagens',
                            style: TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _groups,
                          onChanged: _enabled ? (v) => setState(() => _groups = v) : null,
                          title: const Text(
                            'Grupos',
                            style: TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _events,
                          onChanged: _enabled ? (v) => setState(() => _events = v) : null,
                          title: const Text(
                            'Eventos',
                            style: TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),


            const SizedBox(height: 14),


            // ✅ botão salvar (Remdy)
            SizedBox(
              height: 46,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: _primaryGradient,
                ),
                child: ElevatedButton.icon(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.save, color: Colors.white),
                  label: Text(
                    _saving ? 'Salvando...' : 'Salvar',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
