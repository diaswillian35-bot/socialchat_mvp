import 'package:flutter/material.dart';
import 'remi_languages_page.dart';


class RemiIntroPage extends StatefulWidget {
  const RemiIntroPage({super.key});

  @override
  State<RemiIntroPage> createState() => _RemiIntroPageState();
}

class _RemiIntroPageState extends State<RemiIntroPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

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

  @override
  Widget build(BuildContext context) {
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

              const Text(
                'Remi Language Support',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _text,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                'Learn real phrases for travel, work, daily life and conversations.',
                textAlign: TextAlign.center,
                style: TextStyle(
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
                children: const [
                  _LangChip(text: 'Travel'),
                  _LangChip(text: 'Daily Life'),
                  _LangChip(text: 'Work'),
                  _LangChip(text: 'Conversations'),
                ],
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
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RemiLanguagesPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Start learning',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Learn useful phrases to use inside Remdy.',
                textAlign: TextAlign.center,
                style: TextStyle(
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
