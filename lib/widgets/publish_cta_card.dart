import 'package:flutter/material.dart';

/// Card pequeno de convite ("Cadastre seu local grátis" / "Divulgue grátis").
/// Usa o mesmo padrão dos cards do app: fundo branco, borda #E5E7EB,
/// azul Remdy #313A5F, textos #111827 / #6B7280, ListTile padrão.
class PublishCtaCard extends StatelessWidget {
  const PublishCtaCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;

  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _blue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          onTap: onTap,
          leading: Icon(icon, color: _blue),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, color: _text),
          ),
          subtitle: Text(subtitle, style: const TextStyle(color: _muted)),
          trailing: const Icon(Icons.chevron_right_rounded, color: _blue),
        ),
      ),
    );
  }
}
