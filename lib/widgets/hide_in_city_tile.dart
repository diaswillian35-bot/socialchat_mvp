import 'package:flutter/material.dart';

/// Linha com switch no Menu (mesmo estilo de Idioma/Notificações):
/// "Não aparecer na minha cidade" e "Avisos de pessoas com interesses em comum".
class MenuSwitchTile extends StatelessWidget {
  const MenuSwitchTile({
    super.key,
    required this.tileKey,
    required this.switchKey,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final Key tileKey;
  final Key switchKey;
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  static const Color _muted = Color(0xFF6B7280);
  static const Color _text = Color(0xFF111827);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: tileKey,
      leading: Icon(icon, color: _muted),
      title: Text(
        title,
        style: const TextStyle(color: _text, fontWeight: FontWeight.w800),
      ),
      trailing: Switch(key: switchKey, value: value, onChanged: onChanged),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}
