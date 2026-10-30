import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/user_interests.dart';

/// Seleção múltipla de interesses (chips no estilo do Criar grupo).
class InterestChips extends StatelessWidget {
  const InterestChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _muted = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    return Column(
      key: const Key('interest_chips'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.get('interests_title'),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          t.get('interests_helper'),
          style: const TextStyle(
              fontSize: 12, color: _muted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in UserInterests.keys)
              ChoiceChip(
                key: Key('interest_chip_$key'),
                label: Text(UserInterests.chipLabel(key, t)),
                selected: selected.contains(key),
                selectedColor: _logoBlue,
                backgroundColor: Colors.white,
                checkmarkColor: Colors.white,
                side: const BorderSide(color: _border),
                labelStyle: TextStyle(
                  color: selected.contains(key) ? Colors.white : _remdyBlue,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) {
                  final next = UserInterests.toggle(selected, key);
                  if (next == null) {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                      content: Text(t
                          .get('interests_max_reached')
                          .replaceAll('{max}', '${UserInterests.maxCount}')),
                    ));
                    return;
                  }
                  onChanged(next);
                },
              ),
          ],
        ),
      ],
    );
  }
}
