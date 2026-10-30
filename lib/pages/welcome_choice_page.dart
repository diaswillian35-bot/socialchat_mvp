import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';

/// Pop-up de boas-vindas do 1º acesso (sobre a Home, sem foto/logo):
/// "Quero conhecer pessoas" ou "Só explorar locais e eventos" (liga o modo
/// Só explorar). Fecha depois da escolha.
class WelcomeChoiceDialog extends StatefulWidget {
  const WelcomeChoiceDialog({super.key, required this.onChoose});

  /// Mostra uma vez (quem chama confere welcomeChoiceDone). Sem fechar
  /// tocando fora: a pessoa escolhe uma das opções.
  static Future<void> show(
    BuildContext context, {
    required Future<void> Function(bool exploreOnly) onChoose,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WelcomeChoiceDialog(onChoose: onChoose),
    );
  }

  /// Recebe exploreOnly (true = Só explorar).
  final Future<void> Function(bool exploreOnly) onChoose;

  @override
  State<WelcomeChoiceDialog> createState() => _WelcomeChoiceDialogState();
}

class _WelcomeChoiceDialogState extends State<WelcomeChoiceDialog> {
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  bool _busy = false;

  Future<void> _choose(bool exploreOnly) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onChoose(exploreOnly);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.current.get('save_error'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _option({
    required Key key,
    required IconData icon,
    required String title,
    required String info,
    required bool exploreOnly,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(16),
        onTap: _busy ? null : () => _choose(exploreOnly),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: _remdyBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(info,
                        style: const TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    return Dialog(
      key: const Key('welcome_choice_dialog'),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.get('welcome_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _text, fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 6),
            Text(t.get('welcome_subtitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _muted, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 10),
            Container(
              key: const Key('welcome_launch_free'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(t.get('welcome_launch_free'),
                  style: const TextStyle(
                      color: Color(0xFF16A34A),
                      fontWeight: FontWeight.bold,
                      fontSize: 11)),
            ),
            const SizedBox(height: 14),
            _option(
              key: const Key('welcome_meet_people'),
              icon: Icons.people_alt_rounded,
              title: t.get('welcome_meet_title'),
              info: t.get('welcome_meet_info'),
              exploreOnly: false,
            ),
            const SizedBox(height: 10),
            _option(
              key: const Key('welcome_explore_only'),
              icon: Icons.explore_rounded,
              title: t.get('welcome_explore_title'),
              info: t.get('welcome_explore_info'),
              exploreOnly: true,
            ),
            const SizedBox(height: 12),
            Text(t.get('welcome_change_later'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _muted, fontWeight: FontWeight.w600, fontSize: 12)),
            if (_busy) ...[
              const SizedBox(height: 12),
              const CircularProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}
