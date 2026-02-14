import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  final db = FirebaseFirestore.instance;
  final uid = FirebaseAuth.instance.currentUser?.uid;

  bool _loading = false;

  // Remdy colors
  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _card = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      db.collection('users').doc(uid);

  Future<void> _setPremiumTest(bool value) async {
    if (uid == null) return;

    setState(() => _loading = true);
    try {
      await _userDoc.set({
        'isPremium': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'Premium ativado ✅' : 'Premium desativado ✅'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar Premium: $e'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restorePurchaseStub() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Restaurar compra: em breve ✅'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(12),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ trava o estilo da STATUS BAR (não muda ao rolar)
    const overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light, // iOS
    );

    if (uid == null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            systemOverlayStyle: overlay,
            iconTheme: const IconThemeData(color: _text),
            title: const Text(
              'Premium',
              style: TextStyle(color: _text, fontWeight: FontWeight.w900),
            ),
          ),
          body: const Center(child: Text('Você precisa estar logado.')),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDoc.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final isPremium = (data['isPremium'] ?? false) == true;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: Scaffold(
            backgroundColor: _bg,
            appBar: AppBar(
              backgroundColor: _bg,
              elevation: 0,
              scrolledUnderElevation: 0, // ✅ remove efeito ao rolar
              surfaceTintColor: Colors.transparent, // ✅ remove “tinta” M3
              systemOverlayStyle: overlay, // ✅ status bar fixo
              iconTheme: const IconThemeData(color: _text),
              title: const Text(
                'Premium',
                style: TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 14,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7CC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFFE08A)),
                        ),
                        child: const Icon(Icons.star_rounded, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isPremium
                              ? 'Seu Premium está ATIVO ✅'
                              : 'Ative o Premium e libere o Mundo 🌍',
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: _text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                const Text(
                  'O que você ganha com Premium',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 10),

                const _BenefitTile(
                  icon: Icons.public,
                  title: 'Brasil + Mundo',
                  subtitle: 'Converse com pessoas de todos os países liberados.',
                ),
                const _BenefitTile(
                  icon: Icons.flash_on,
                  title: 'Sem bloqueio por país',
                  subtitle: 'Você não fica preso apenas ao seu país.',
                ),
                const _BenefitTile(
                  icon: Icons.timer_off,
                  title: 'Sem limite de tempo',
                  subtitle: 'Chat livre (sem 1h/dia).',
                ),
                const _BenefitTile(
                  icon: Icons.support_agent,
                  title: 'Prioridade no suporte',
                  subtitle: 'Ajuda mais rápida quando precisar.',
                ),

                const SizedBox(height: 16),

                // CTA
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
                      Text(
                        isPremium
                            ? 'Você já é Premium ✅'
                            : 'Pronto para liberar o Mundo?',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: _text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isPremium
                            ? 'Se quiser testar desativar, use o botão abaixo.'
                            : 'Assine e comece a conversar fora do seu país.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),

                      if (!isPremium)
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [_remdyBlue, _logoBlue],
                            ),
                          ),
                          child: ElevatedButton.icon(
                            onPressed:
                                _loading ? null : () => _setPremiumTest(true),
                            icon: const Icon(Icons.star, size: 18),
                            label: Text(
                              _loading ? 'Aguarde...' : 'Assinar Premium',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed:
                              _loading ? null : () => _setPremiumTest(false),
                          icon: const Icon(Icons.star_border, size: 18),
                          label: const Text(
                            'Desativar (teste)',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _remdyBlue,
                            side: const BorderSide(color: _border),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),

                      const SizedBox(height: 10),

                      OutlinedButton.icon(
                        onPressed: _loading ? null : _restorePurchaseStub,
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text(
                          'Restaurar compra',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _remdyBlue,
                          side: const BorderSide(color: _border),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  'Observação: por enquanto isso é modo teste (liga/desliga isPremium no Firestore). '
                  'Depois a gente conecta pagamento real.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BenefitTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _BenefitTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  static const Color _card = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(icon, color: _remdyBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
