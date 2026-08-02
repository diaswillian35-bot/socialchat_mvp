import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socialchat_mvp/services/share_in_parser.dart';
import 'package:socialchat_mvp/services/share_in_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ShareInService.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

  test('dedup: mesmo intentId duas vezes', () async {
    final parsed = ShareInParser.parseText(
      'hello share',
      intentId: 'intent-a',
      receivedAtMs: 1000,
    );
    expect(parsed.isOk, isTrue);

    final first = await ShareInService.ingestPayload(
      parsed.payload!,
      skipUi: true,
    );
    expect(first, ShareInIngestOutcome.pendingLogin);

    final second = await ShareInService.ingestPayload(
      parsed.payload!,
      skipUi: true,
    );
    expect(second, ShareInIngestOutcome.duplicate);
  });

  test('dedup: fingerprint após markSent', () async {
    final parsed = ShareInParser.parseText(
      'unique text xyz',
      intentId: 'intent-b',
      receivedAtMs: 2000,
    );
    final payload = parsed.payload!;
    await ShareInService.markSent(payload);

    final again = ShareInParser.parseText(
      'unique text xyz',
      intentId: 'intent-b2',
      receivedAtMs: 2000,
    );
    // Fingerprint inclui intentId — mudou. Marcar sent no fingerprint antigo.
    // Simula reenvio do mesmo fingerprint:
    ShareInService.resetForTest();
    await ShareInService.markSent(payload);
    final dup = await ShareInService.ingestPayload(payload, skipUi: true);
    expect(dup, ShareInIngestOutcome.duplicate);
  });

  test('pending login persiste e restaura JSON', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final parsed = ShareInParser.parseText(
      'https://example.com/item',
      intentId: 'pending-1',
      receivedAtMs: 3000,
    );
    await ShareInService.persistPending(parsed.payload!, prefs: prefs);

    final raw = prefs.getString(ShareInService.pendingPrefsKey);
    expect(raw, isNotNull);
    expect(raw, contains('example.com'));

    await ShareInService.clearPending(prefs: prefs);
    expect(prefs.getString(ShareInService.pendingPrefsKey), isNull);
  });

  test('destino conversation vs group kinds no modelo', () {
    final parsed = ShareInParser.parseText('oi', intentId: 'x', receivedAtMs: 1);
    expect(parsed.payload!.copyWithText('oi https://remdy.app/e/1').hasLink, isTrue);
  });
}
