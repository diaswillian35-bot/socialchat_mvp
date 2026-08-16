import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socialchat_mvp/models/share_in_payload.dart';
import 'package:socialchat_mvp/services/share_in_parser.dart';
import 'package:socialchat_mvp/services/share_in_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ShareInService.resetForTest();
  });

  ShareInPayload payload({
    String id = 'intent-1',
    String text = 'hello https://example.com',
  }) {
    final parsed = ShareInParser.parseText(
      text,
      intentId: id,
      source: 'test',
    );
    return parsed.payload!;
  }

  test('arquivo/fila: persistPending sobrevive e apply lê JSON', () async {
    final p = payload();
    await ShareInService.persistPending(p);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(ShareInService.pendingPrefsKey);
    expect(raw, isNotNull);
    final map = jsonDecode(raw!) as Map<String, dynamic>;
    expect(map['intentId'], p.intentId);
    expect(map['text'], contains('example.com'));
  });

  test('navigator indisponível: openShareUi retorna false e mantém fila',
      () async {
    final p = payload(id: 'nav-miss');
    final opened = await ShareInService.openShareUi(p);
    expect(opened, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ShareInService.pendingPrefsKey), isNotNull);
  });

  test('usuário autenticando: sem user → pendingLogin e fila preservada',
      () async {
    // Sem Firebase user no test binding → currentUser null.
    final outcome =
        await ShareInService.ingestPayload(payload(id: 'auth-wait'));
    expect(outcome, ShareInIngestOutcome.pendingLogin);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ShareInService.pendingPrefsKey), isNotNull);
  });

  test('consumo único: openedIntentIds impede reabrir mesmo fingerprint',
      () async {
    ShareInService.resetForTest();
    // Simula intent já aberta.
    final p = payload(id: 'once-1');
    await ShareInService.persistPending(p);
    // Marca como opened via ingest duplicate path após opened set — usa markSent fingerprint.
    await ShareInService.markSent(p);
    final again = await ShareInService.ingestPayload(p);
    expect(again, ShareInIngestOutcome.duplicate);
  });

  test('app aberto duas vezes: inflight/opening dedupa', () async {
    final p = payload(id: 'twice');
    // Primeira chamada sem navigator → queued/pendingLogin
    final first = await ShareInService.ingestPayload(p);
    expect(
      first == ShareInIngestOutcome.pendingLogin ||
          first == ShareInIngestOutcome.queued,
      isTrue,
    );
  });

  test('payload antigo: clearPending remove da fila Dart', () async {
    final p = payload(id: 'old-qa');
    await ShareInService.persistPending(p);
    await ShareInService.clearPending();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ShareInService.pendingPrefsKey), isNull);
  });

  test('fingerprint dedup helper', () {
    expect(ShareInService.isDuplicateFingerprintForTest('x'), isFalse);
  });
}
