import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class InvitePage extends StatelessWidget {
  final int invites; // quantos convites válidos (confirmados) a pessoa tem
  final int limit; // meta (ex: 5)
  final String myUid; // pra mostrar o código por enquanto (depois vira link)

  const InvitePage({
    super.key,
    required this.invites,
    required this.limit,
    required this.myUid,
  });

  // Remdy colors (visual apenas)
  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _card = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);

  @override
  Widget build(BuildContext context) {
    final progress = (limit <= 0) ? 0.0 : (invites / limit).clamp(0.0, 1.0);
    final remaining = (limit - invites) < 0 ? 0 : (limit - invites);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: _text),
        title: const Text(
          'Convites',
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
          // ===== Card de progresso =====
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('🎁', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Convide amigos e ganhe benefícios',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: _text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Meta: $invites/$limit',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: const Color(0xFFF1F5F9),
                    valueColor: const AlwaysStoppedAnimation<Color>(_remdyBlue),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  progress >= 1.0
                      ? '🎉 Parabéns! Você atingiu a meta.'
                      : 'Faltam $remaining para bater a meta.',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ===== Código =====
          const Text(
            'Seu código (por enquanto)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: _text,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    myUid,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _text,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [_remdyBlue, _logoBlue],
                    ),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: myUid));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Código copiado!'),
                          behavior: SnackBarBehavior.floating,
                          margin: EdgeInsets.all(12),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text(
                      'Copiar',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ===== Como funciona =====
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Como funciona',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _text,
                  ),
                ),
                SizedBox(height: 10),
                _HowRow(text: '1) Você manda seu código para um amigo.'),
                SizedBox(height: 6),
                _HowRow(text: '2) Ele cria conta e coloca o código (ou usa um link).'),
                SizedBox(height: 6),
                _HowRow(text: '3) Quando ele completar o cadastro, conta como 1 convite.'),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ===== Voltar =====
          
        ],
      ),
    );
  }
}

class _HowRow extends StatelessWidget {
  final String text;
  const _HowRow({required this.text});

  static const Color _muted = Color(0xFF374151);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle, size: 18, color: Color(0xFF2563EB)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.25,
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
