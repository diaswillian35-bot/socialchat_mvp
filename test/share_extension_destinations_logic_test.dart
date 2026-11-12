import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/share_extension_destinations_logic.dart';

void main() {
  group('ShareExtensionDestinationsLogic', () {
    test('pairKey é determinístico', () {
      expect(
        ShareExtensionDestinationsLogic.pairKey('b', 'a'),
        'a_b',
      );
    });

    test('collectGroupMemberUids deduplica e exclui o próprio', () {
      final uids = ShareExtensionDestinationsLogic.collectGroupMemberUids(
        uid: 'me',
        groups: [
          {
            'members': ['me', 'u1', 'u2'],
            'ownerId': 'me',
            'admins': ['u1'],
          },
          {
            'members': ['u2', 'u3'],
            'ownerId': 'u4',
          },
        ],
      );
      expect(uids, ['u1', 'u2', 'u3', 'u4']);
    });

    test('shouldIncludePerson aplica filtros de privacidade', () {
      expect(
        ShareExtensionDestinationsLogic.shouldIncludePerson(
          uid: 'me',
          otherUid: 'me',
          otherData: const {},
          isContact: false,
        ),
        isFalse,
      );
      expect(
        ShareExtensionDestinationsLogic.shouldIncludePerson(
          uid: 'me',
          otherUid: 'u1',
          otherData: const {},
          isContact: false,
          blocked: true,
        ),
        isFalse,
      );
      expect(
        ShareExtensionDestinationsLogic.shouldIncludePerson(
          uid: 'me',
          otherUid: 'u1',
          otherData: const {'hiddenFromLists': true},
          isContact: false,
        ),
        isFalse,
      );
      expect(
        ShareExtensionDestinationsLogic.shouldIncludePerson(
          uid: 'me',
          otherUid: 'u1',
          otherData: const {'exploreOnly': true},
          isContact: false,
        ),
        isFalse,
      );
      expect(
        ShareExtensionDestinationsLogic.shouldIncludePerson(
          uid: 'me',
          otherUid: 'u1',
          otherData: const {'exploreOnly': true},
          isContact: true,
        ),
        isTrue,
      );
    });

    test('mergePeople: DMs primeiro, depois membros, com teto e dedup', () {
      final merged = ShareExtensionDestinationsLogic.mergePeople(
        conversations: [
          {'otherUid': 'a'},
          {'otherUid': 'b'},
        ],
        groupMembers: [
          {'otherUid': 'b'},
          {'otherUid': 'c'},
          {'otherUid': 'd'},
        ],
        searchHits: [
          {'otherUid': 'c'},
          {'otherUid': 'e'},
        ],
        cap: 4,
      );
      expect(merged.map((e) => e['otherUid']), ['a', 'b', 'c', 'd']);
    });
  });
}
