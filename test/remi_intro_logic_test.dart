import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/remi_intro_logic.dart';

void main() {
  group('RemiIntroLogic.parseIntroVersion', () {
    test('null and invalid => null (not seen)', () {
      expect(RemiIntroLogic.parseIntroVersion(null), isNull);
      expect(RemiIntroLogic.parseIntroVersion(0), isNull);
      expect(RemiIntroLogic.parseIntroVersion(-1), isNull);
      expect(RemiIntroLogic.parseIntroVersion(''), isNull);
      expect(RemiIntroLogic.parseIntroVersion('abc'), isNull);
      expect(RemiIntroLogic.parseIntroVersion(true), isNull);
      expect(RemiIntroLogic.parseIntroVersion({}), isNull);
    });

    test('valid int/num/string', () {
      expect(RemiIntroLogic.parseIntroVersion(1), 1);
      expect(RemiIntroLogic.parseIntroVersion(2), 2);
      expect(RemiIntroLogic.parseIntroVersion(1.0), 1);
      expect(RemiIntroLogic.parseIntroVersion('1'), 1);
      expect(RemiIntroLogic.parseIntroVersion(' 2 '), 2);
    });
  });

  group('RemiIntroLogic.hasSeenIntro', () {
    test('missing field shows intro once', () {
      expect(RemiIntroLogic.hasSeenIntro(null), isFalse);
    });

    test('version >= 1 skips intro', () {
      expect(RemiIntroLogic.hasSeenIntro(1), isTrue);
      expect(RemiIntroLogic.hasSeenIntro(2), isTrue);
    });

    test('future required version 2 does not re-show v1 requirement wrongly', () {
      // User already saw v1; required still 1 → skip
      expect(RemiIntroLogic.hasSeenIntro(1, requiredVersion: 1), isTrue);
      // When product ships v2, users with only v1 see again
      expect(RemiIntroLogic.hasSeenIntro(1, requiredVersion: 2), isFalse);
      expect(RemiIntroLogic.hasSeenIntro(2, requiredVersion: 2), isTrue);
    });
  });

  group('cache keys per uid', () {
    test('keys are account-scoped (never global)', () {
      final a = RemiIntroLogic.localVersionKey('uidA');
      final b = RemiIntroLogic.localVersionKey('uidB');
      expect(a, isNot(equals(b)));
      expect(a, contains('uidA'));
      expect(b, contains('uidB'));
      expect(a, isNot(contains('global')));
      expect(
        RemiIntroLogic.localPendingSyncKey('uidA'),
        isNot(equals(RemiIntroLogic.localPendingSyncKey('uidB'))),
      );
    });
  });

  group('nextStoredVersion idempotent', () {
    test('never decreases', () {
      expect(RemiIntroLogic.nextStoredVersion(null), 1);
      expect(RemiIntroLogic.nextStoredVersion(1), 1);
      expect(RemiIntroLogic.nextStoredVersion(2, target: 1), 2);
      expect(RemiIntroLogic.nextStoredVersion(1, target: 2), 2);
    });
  });

  test('currentVersion is 1 (no backfill of new version)', () {
    expect(RemiIntroLogic.currentVersion, 1);
  });
}
