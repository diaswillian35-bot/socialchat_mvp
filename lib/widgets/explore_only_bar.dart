import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';

/// Barra fixa de baixo de Conheça Pessoas: "Não quero conhecer ninguém,
/// só usar o app" (modo Só explorar). Mesmo visual da antiga barra
/// "Aparecer para pessoas perto de mim".
class ExploreOnlyBar extends StatelessWidget {
  const ExploreOnlyBar({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const Color _online = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('country-explore-only-bar'),
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(Icons.location_on_rounded, color: scheme.onPrimary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.get('people_explore_only_switch'),
                      style: TextStyle(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  Text(
                      t.get(value
                          ? 'people_explore_only_on_caption'
                          : 'people_explore_only_off_caption'),
                      style: TextStyle(
                          color: scheme.onPrimary.withValues(alpha: 0.8),
                          fontSize: 12)),
                ],
              ),
            ),
            Switch(
              key: const Key('explore_only_switch'),
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: _online,
            ),
          ],
        ),
      ),
    );
  }
}
