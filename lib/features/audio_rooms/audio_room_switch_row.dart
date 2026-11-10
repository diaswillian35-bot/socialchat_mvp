import 'package:flutter/material.dart';

const Color _text = Color(0xFF111827);
const Color _muted = Color(0xFF6B7280);
const Color _remdyBlue = Color(0xFF313A5F);

/// Linha com ícone, texto e Switch das informações do grupo (mesmo visual
/// das outras linhas com Switch dessa tela).
class AudioRoomSwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData icon;

  const AudioRoomSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon = Icons.headset_mic_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _muted, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: Colors.white,
          activeTrackColor: _remdyBlue,
          inactiveThumbColor: const Color(0xFF6B7280),
          inactiveTrackColor: const Color(0xFFE5E7EB),
          trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
            (states) {
              if (states.contains(WidgetState.selected)) {
                return _remdyBlue;
              }
              return const Color(0xFFE5E7EB);
            },
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
