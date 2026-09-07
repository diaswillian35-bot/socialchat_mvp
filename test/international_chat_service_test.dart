import 'package:flutter_test/flutter_test.dart';

import 'package:socialchat_mvp/services/dm_reply_quota.dart';
import 'package:socialchat_mvp/services/international_chat_service.dart';
import 'package:socialchat_mvp/services/international_country_codes.dart';

void main() {
  group('InternationalCountryCodes', () {
    test('resolve ISO and legacy names', () {
      expect(
        InternationalCountryCodes.resolve({'homeCountryCode': 'BR'}),
        'br',
      );
      expect(
        InternationalCountryCodes.resolve({'country': 'Brazil'}),
        'br',
      );
      expect(InternationalCountryCodes.resolve({'country': 'Canadá'}), 'ca');
      expect(InternationalCountryCodes.resolve({'homeCountryCode': 'xx'}), '');
    });
  });

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

    test('dmCountryRelation safe mode', () {
      expect(
        InternationalChatService.dmCountryRelation(
          {'homeCountryCode': 'br'},
          {'homeCountryCode': 'ca'},
        ),
        DmCountryRelation.international,
      );
      expect(
        InternationalChatService.dmCountryRelation(
          {'homeCountryCode': 'br'},
          {},
        ),
        DmCountryRelation.unknown,
      );
      expect(
        InternationalChatService.dmCountryRelation(
          {'homeCountryCode': 'br'},
          {'homeCountryCode': 'br'},
        ),
        DmCountryRelation.same,
      );
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

    test('canSendMessage unknown country blocked for free', () {
      expect(
        InternationalChatService.canSendMessage(
          senderData: {'countryCode': 'br'},
          recipientData: {},
        ),
        false,
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

    test('canSendMessage international blocked even with premium in free launch',
        () {
      expect(
        InternationalChatService.canSendMessage(
          senderData: {'countryCode': 'br', 'isPremium': true},
          recipientData: {'countryCode': 'ca'},
        ),
        false,
      );
      expect(
        InternationalChatService.canSendMessage(
          senderData: {
            'homeCountryCode': 'br',
            'isMaster': true,
            'premiumUntil': DateTime.now().add(const Duration(days: 30)),
          },
          recipientData: {'homeCountryCode': 'ca'},
        ),
        false,
      );
    });
  });

  group('DmReplyQuota.countCodePoints', () {
    test('ascii spaces and accents', () {
      expect(DmReplyQuota.countCodePoints(''), 0);
      expect(DmReplyQuota.countCodePoints('abc'), 3);
      expect(DmReplyQuota.countCodePoints('a b'), 3);
      expect(DmReplyQuota.countCodePoints('ação'), 4);
      expect(DmReplyQuota.countCodePoints('a\nb'), 3);
    });

    test('emoji code points', () {
      expect(DmReplyQuota.countCodePoints('😀'), 1);
      expect(DmReplyQuota.countCodePoints('a😀b'), 3);
    });
  });

  group('DmSendPath', () {
    test('callable for free international and unknown country', () {
      expect(
        DmSendPath.requiresCallable(
          senderIsPremium: false,
          senderData: {'homeCountryCode': 'br'},
          recipientData: {'homeCountryCode': 'ca'},
        ),
        isTrue,
      );
      expect(
        DmSendPath.requiresCallable(
          senderIsPremium: false,
          senderData: {'homeCountryCode': 'br'},
          recipientData: {},
        ),
        isTrue,
      );
      expect(
        DmSendPath.requiresCallable(
          senderIsPremium: true,
          senderData: {'homeCountryCode': 'br'},
          recipientData: {'homeCountryCode': 'ca'},
        ),
        isFalse,
      );
      expect(
        DmSendPath.requiresCallable(
          senderIsPremium: false,
          senderData: {'homeCountryCode': 'br'},
          recipientData: {'homeCountryCode': 'br'},
        ),
        isFalse,
      );
    });
  });
}
