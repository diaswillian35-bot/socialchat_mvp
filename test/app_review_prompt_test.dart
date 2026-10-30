import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/app_review_prompt.dart';

void main() {
  late DateTime now;
  late MemoryReviewStore store;
  late int requests;
  AppReviewPrompt make({bool available = true}) => AppReviewPrompt(
        store: store,
        clock: () => now,
        isAvailable: () async => available,
        request: () async => requests++,
      );

  setUp(() {
    now = DateTime(2026, 11, 1, 12);
    store = MemoryReviewStore();
    requests = 0;
  });

  test('nunca no 1º dia desde o 1º uso', () async {
    final p = make();
    await p.recordLaunch();
    now = now.add(const Duration(hours: 23));
    expect(await p.onEventCreated(), isFalse);
    expect(requests, 0);
    now = now.add(const Duration(hours: 2));
    expect(await p.onEventCreated(), isTrue);
    expect(requests, 1);
  });

  test('sem data de 1º uso: grava agora e não pede', () async {
    final p = make();
    expect(await p.onEventCreated(), isFalse);
    expect(store.values[AppReviewPrompt.kFirstLaunch], isNotNull);
  });

  test('só a partir da 3ª mensagem enviada (total acumulado)', () async {
    final p = make();
    await p.recordLaunch();
    now = now.add(const Duration(days: 2));
    expect(await p.onMessageSent(), isFalse);
    expect(await p.onMessageSent(), isFalse);
    expect(await p.onMessageSent(), isTrue);
    expect(requests, 1);
    expect(store.values[AppReviewPrompt.kMessages], 3);
  });

  test('no máximo 1 vez a cada 90 dias', () async {
    final p = make();
    await p.recordLaunch();
    now = now.add(const Duration(days: 2));
    expect(await p.onEventCreated(), isTrue);
    now = now.add(const Duration(days: 89));
    expect(await p.onEventCreated(), isFalse);
    expect(await p.onMessageSent(), isFalse);
    now = now.add(const Duration(days: 2));
    expect(await p.onEventCreated(), isTrue);
    expect(requests, 2);
  });

  test('indisponível no aparelho: não pede e não gasta a janela', () async {
    final p = make(available: false);
    await p.recordLaunch();
    now = now.add(const Duration(days: 2));
    expect(await p.onEventCreated(), isFalse);
    expect(store.values[AppReviewPrompt.kLastPrompt], isNull);
  });

  test('recordLaunch não sobrescreve o 1º uso', () async {
    final p = make();
    await p.recordLaunch();
    final first = store.values[AppReviewPrompt.kFirstLaunch];
    now = now.add(const Duration(days: 5));
    await p.recordLaunch();
    expect(store.values[AppReviewPrompt.kFirstLaunch], first);
  });
}
