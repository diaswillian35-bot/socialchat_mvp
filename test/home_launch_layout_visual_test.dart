import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';

/// Layout preview (sem Firebase) para confirmar visualmente que Canadá,
/// Portugal e Mundo voltam na Home sem copy "Em breve".
void main() {
  testWidgets('Home Ao Vivo shows Canada, Portugal and Mundo without Em breve',
      (tester) async {
    AppTexts.loadFromMap({
      'live_now': 'Agora ao vivo',
      'country_brazil': 'Brasil',
      'country_canada': 'Canadá',
      'country_portugal': 'Portugal',
      'world': 'Mundo',
      'online': 'online',
    });
    final t = AppTexts.current;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.get('live_now'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Text('🇧🇷', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 10),
                    Text('Brasil'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('🌍', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Text(
                      t.get('world'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Conheça pessoas',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _tile('🇧🇷', t.get('country_brazil')),
                    const SizedBox(width: 8),
                    _tile('🇨🇦', t.get('country_canada')),
                    const SizedBox(width: 8),
                    _tile('🇵🇹', t.get('country_portugal')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Agora ao vivo'), findsOneWidget);
    expect(find.text('Canadá'), findsOneWidget);
    expect(find.text('Portugal'), findsOneWidget);
    expect(find.text('Mundo'), findsOneWidget);
    expect(find.textContaining('Em breve'), findsNothing);
    expect(find.textContaining('Coming soon'), findsNothing);

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/home_restore_ca_pt_mundo.png'),
    );
  });
}

Widget _tile(String flag, String name) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Text(flag, style: const TextStyle(fontSize: 28, height: 1)),
          const SizedBox(height: 4),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}
