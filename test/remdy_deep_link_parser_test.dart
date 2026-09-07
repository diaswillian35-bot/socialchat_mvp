import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/remdy_deep_link_parser.dart';

void main() {
  group('RemdyDeepLinkParser — raiz e landing', () {
    test('https://remdy.app não abre grupo e limpa pendência', () {
      final link = RemdyDeepLinkParser.parse(Uri.parse('https://remdy.app'));
      expect(link.kind, RemdyDeepLinkKind.none);
      expect(link.opensGroupPreview, isFalse);
      expect(link.clearsPendingGroup, isTrue);
      expect(link.groupCode, isNull);
    });

    test('https://remdy.app/ idem', () {
      final link = RemdyDeepLinkParser.parse(Uri.parse('https://remdy.app/'));
      expect(link.kind, RemdyDeepLinkKind.none);
      expect(link.clearsPendingGroup, isTrue);
    });

    test('www e /eventos ficam na web', () {
      expect(
        RemdyDeepLinkParser.parse(Uri.parse('https://www.remdy.app/')).kind,
        RemdyDeepLinkKind.none,
      );
      expect(
        RemdyDeepLinkParser.parse(Uri.parse('https://remdy.app/eventos')).kind,
        RemdyDeepLinkKind.none,
      );
      expect(
        RemdyDeepLinkParser.parse(
          Uri.parse('https://remdy.app/eventos/navegantes'),
        ).clearsPendingGroup,
        isTrue,
      );
    });
  });

  group('RemdyDeepLinkParser — eventos', () {
    test('/e/{id} válido', () {
      final link = RemdyDeepLinkParser.parse(
        Uri.parse('https://remdy.app/e/abc123'),
      );
      expect(link.kind, RemdyDeepLinkKind.event);
      expect(link.eventId, 'abc123');
      expect(link.clearsPendingGroup, isTrue);
      expect(link.opensGroupPreview, isFalse);
    });

    test('/e/ inválido não vira grupo', () {
      final link =
          RemdyDeepLinkParser.parse(Uri.parse('https://remdy.app/e/'));
      expect(link.kind, RemdyDeepLinkKind.none);
      expect(link.groupCode, isNull);
      expect(link.clearsPendingGroup, isTrue);
    });
  });

  group('RemdyDeepLinkParser — grupo', () {
    test('/g/{code} válido abre prévia', () {
      final link = RemdyDeepLinkParser.parse(
        Uri.parse('https://remdy.app/g/ABC123'),
      );
      expect(link.kind, RemdyDeepLinkKind.groupInvite);
      expect(link.groupCode, 'ABC123');
      expect(link.opensGroupPreview, isTrue);
      expect(link.clearsPendingGroup, isFalse);
    });

    test('/g e /g/ inválidos limpam pendência e não reusam código', () {
      for (final raw in [
        'https://remdy.app/g',
        'https://remdy.app/g/',
        'https://remdy.app/g/%20',
        'https://remdy.app/group',
        'https://remdy.app/group?code=',
      ]) {
        final link = RemdyDeepLinkParser.parse(Uri.parse(raw));
        expect(link.kind, RemdyDeepLinkKind.groupInviteInvalid, reason: raw);
        expect(link.groupCode, isNull, reason: raw);
        expect(link.opensGroupPreview, isFalse, reason: raw);
        expect(link.clearsPendingGroup, isTrue, reason: raw);
      }
    });

    test('host estranho nunca abre grupo', () {
      final link = RemdyDeepLinkParser.parse(
        Uri.parse('https://evil.com/g/ABC123'),
      );
      expect(link.kind, RemdyDeepLinkKind.none);
      expect(link.opensGroupPreview, isFalse);
      expect(link.clearsPendingGroup, isTrue);
    });

    test('legado /group?code=', () {
      final link = RemdyDeepLinkParser.parse(
        Uri.parse('https://remdy.app/group?code=xy99'),
      );
      expect(link.kind, RemdyDeepLinkKind.groupInvite);
      expect(link.groupCode, 'XY99');
    });
  });

  group('RemdyDeepLinkParser — cold start vs app aberto', () {
    test('mesma URI raiz sempre none (idempotente)', () {
      final a = RemdyDeepLinkParser.parse(Uri.parse('https://remdy.app'));
      final b = RemdyDeepLinkParser.parse(Uri.parse('https://remdy.app/'));
      expect(a.kind, b.kind);
      expect(a.clearsPendingGroup, b.clearsPendingGroup);
    });

    test('trocar de /g/CODE para raiz limpa e não reabre grupo', () {
      final group = RemdyDeepLinkParser.parse(
        Uri.parse('https://remdy.app/g/CODE01'),
      );
      final root =
          RemdyDeepLinkParser.parse(Uri.parse('https://remdy.app'));
      expect(group.opensGroupPreview, isTrue);
      expect(root.opensGroupPreview, isFalse);
      expect(root.clearsPendingGroup, isTrue);
      expect(root.groupCode, isNull);
    });
  });
}
