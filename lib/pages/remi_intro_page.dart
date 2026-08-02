import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/remi_intro_service.dart';
import 'remi_languages_page.dart';

class RemiIntroPage extends StatefulWidget {
  /// Se true, só reexibe a apresentação (não grava flag / não sincroniza).
  final bool reviewMode;

  const RemiIntroPage({
    super.key,
    this.reviewMode = false,
  });

  @override
  State<RemiIntroPage> createState() => _RemiIntroPageState();
}

class _RemiIntroPageState extends State<RemiIntroPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;
  bool _completing = false;

  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.97, end: 1.04).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_completing) return;
    setState(() => _completing = true);

    if (!widget.reviewMode) {
      // Local primeiro; falha remota não prende o usuário.
      await RemiIntroService.instance.markIntroCompleted();
    }

    if (!mounted) return;

    if (widget.reviewMode) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const RemiLanguagesPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chips = [
      AppTexts.t('remi_chip_travel'),
      AppTexts.t('remi_chip_daily_life'),
      AppTexts.t('remi_chip_work'),
      AppTexts.t('remi_chip_conversations'),
    ];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        surfaceTintColor: _bg,
        iconTheme: const IconThemeData(color: _text),
        title: const Text(
          'Remi',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            children: [
              const Spacer(),
              ScaleTransition(
                scale: _pulse,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Image.asset(
                      'assets/remdy_logo_s_fundo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                AppTexts.t('remi_presentation_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _text,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                AppTexts.t('remi_presentation_subtitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: chips
                    .map((text) => _LangChip(text: text))
                    .toList(),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [_remdyBlue, _logoBlue],
                  ),
                ),
                child: ElevatedButton(
                  onPressed: _completing ? null : _finish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    AppTexts.t('remi_presentation_start'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _completing ? null : _finish,
                child: Text(
                  AppTexts.t('remi_presentation_skip'),
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppTexts.t('remi_presentation_footer'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String text;

  const _LangChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
