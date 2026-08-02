import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/international_chat_service.dart';

void main() {
  group('InternationalChatService', () {
    test('readHomeCountryCode prefers homeCountryCode', () {
      expect(
        InternationalChatService.readHomeCountryCode({
          'homeCountryCode': 'BR',
          'countryCode': 'ca',
        }),
        'br',
      );
      expect(
        InternationalChatService.readHomeCountryCode({'countryCode': 'CA'}),
        'ca',
      );
    });

    test('isInternational', () {
      expect(InternationalChatService.isInternational('br', 'ca'), true);
      expect(InternationalChatService.isInternational('br', 'br'), false);
      expect(InternationalChatService.isInternational('', 'ca'), false);
      expect(InternationalChatService.isInternational('br', ''), false);
    });

    test('canSendMessage same country free', () {
      expect(
        InternationalChatService.canSendMessage(
          senderData: {'countryCode': 'br'},
          recipientData: {'countryCode': 'br'},
        ),
        true,
      );
    });

    test('canSendMessage international free blocked', () {
      expect(
        InternationalChatService.canSendMessage(
          senderData: {'countryCode': 'br', 'isPremium': false},
          recipientData: {'countryCode': 'ca'},
        ),
        false,
      );
    });

    test('canSendMessage international premium allowed', () {
      expect(
        InternationalChatService.canSendMessage(
          senderData: {'countryCode': 'br', 'isPremium': true},
          recipientData: {'countryCode': 'ca'},
        ),
        true,
      );
      expect(
        InternationalChatService.canSendMessage(
          senderData: {
            'countryCode': 'br',
            'premiumUntil': DateTime.now().add(const Duration(days: 2)),
          },
          recipientData: {'countryCode': 'ca'},
        ),
        true,
      );
    });

    test('pairKey is order-independent', () {
      expect(
        InternationalChatService.pairKey('b', 'a'),
        InternationalChatService.pairKey('a', 'b'),
      );
    });

    test('isActiveAccount', () {
      expect(InternationalChatService.isActiveAccount(null), false);
      expect(InternationalChatService.isActiveAccount({}), true);
      expect(
        InternationalChatService.isActiveAccount({'isBanned': true}),
        false,
      );
      expect(
        InternationalChatService.isActiveAccount({'accountDeleted': true}),
        false,
      );
    });
  });
}
