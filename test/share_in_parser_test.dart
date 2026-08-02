import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/share_in_parser.dart';

void main() {
  group('ShareInParser mime', () {
    test('aceita text/plain e text/*', () {
      expect(ShareInParser.isAllowedMimeType('text/plain'), isTrue);
      expect(ShareInParser.isAllowedMimeType('text/html'), isTrue);
      expect(ShareInParser.isAllowedMimeType('text/*'), isTrue);
      expect(ShareInParser.isAllowedMimeType(null), isTrue);
      expect(ShareInParser.isAllowedMimeType(''), isTrue);
    });

    test('rejeita imagem/vídeo/arquivo', () {
      expect(ShareInParser.isAllowedMimeType('image/jpeg'), isFalse);
      expect(ShareInParser.isAllowedMimeType('video/mp4'), isFalse);
      expect(ShareInParser.isAllowedMimeType('application/pdf'), isFalse);
      expect(ShareInParser.isAllowedMimeType('audio/mpeg'), isFalse);
    });
  });

  group('ShareInParser texto/HTTPS', () {
    test('texto puro ok', () {
      final r = ShareInParser.parseText('Olá mundo Remdy');
      expect(r.isOk, isTrue);
      expect(r.payload!.text, 'Olá mundo Remdy');
      expect(r.payload!.hasLink, isFalse);
    });

    test('HTTPS ok', () {
      final r = ShareInParser.parseText(
        'Veja https://www.amazon.com/dp/B0TEST',
      );
      expect(r.isOk, isTrue);
      expect(r.payload!.hasLink, isTrue);
      expect(
        r.payload!.primaryLink!.normalizedHttpsUrl,
        contains('https://www.amazon.com'),
      );
      expect(r.payload!.primaryLink!.isRemdyInternal, isFalse);
    });

    test('http é upgradado para https', () {
      final r = ShareInParser.parseText('http://example.com/path');
      expect(r.isOk, isTrue);
      expect(r.payload!.text, contains('https://example.com/path'));
    });

    test('javascript rejeitado', () {
      final r = ShareInParser.parseText('javascript:alert(1)');
      expect(r.isOk, isFalse);
      expect(r.errorKey, isNotNull);
    });

    test('content:// rejeitado', () {
      final r = ShareInParser.parseNativeMap({
        'text': '',
        'uri': 'content://media/external/images/1',
        'mimeType': 'image/jpeg',
      });
      expect(r.isOk, isFalse);
      expect(r.errorKey, 'share_in_unsupported_type');
    });

    test('file:// rejeitado', () {
      final r = ShareInParser.parseText('file:///tmp/a.png');
      expect(r.isOk, isFalse);
    });

    test('link Remdy interno marcado', () {
      final r = ShareInParser.parseText(
        'Entre https://remdy.app/g/ABC123',
      );
      expect(r.isOk, isTrue);
      expect(r.payload!.primaryLink!.isRemdyInternal, isTrue);
    });

    test('vazio inválido', () {
      final r = ShareInParser.parseText('   ');
      expect(r.isOk, isFalse);
      expect(r.errorKey, 'share_in_invalid');
    });

    test('fingerprint estável', () {
      final a = ShareInParser.fingerprintFor(
        text: 'hello',
        intentId: 'id1',
        receivedAtMs: 100,
      );
      final b = ShareInParser.fingerprintFor(
        text: 'hello',
        intentId: 'id1',
        receivedAtMs: 100,
      );
      final c = ShareInParser.fingerprintFor(
        text: 'hello',
        intentId: 'id2',
        receivedAtMs: 100,
      );
      expect(a, b);
      expect(a, isNot(c));
    });

    test('mime image no mapa nativo rejeitado mesmo com texto', () {
      final r = ShareInParser.parseNativeMap({
        'text': 'oi',
        'mimeType': 'image/png',
      });
      expect(r.isOk, isFalse);
      expect(r.errorKey, 'share_in_unsupported_type');
    });
  });
}
