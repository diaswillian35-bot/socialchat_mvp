import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socialchat_mvp/services/group_discovery_logic.dart';
import 'package:socialchat_mvp/services/group_hidden_prefs_service.dart';
import 'package:socialchat_mvp/services/remdy_launch_access.dart';

void main() {
  group('leave / hide / discovery privacy', () {
    test('excludeHidden removes only listed ids for current user', () {
      final items = [
        const GroupDiscoveryItem(id: 'a', data: {'name': 'A'}),
        const GroupDiscoveryItem(id: 'b', data: {'name': 'B'}),
        const GroupDiscoveryItem(id: 'c', data: {'name': 'C'}),
      ];
      final filtered = GroupDiscoveryLogic.excludeHidden(
        items: items,
        hiddenIds: {'b'},
      );
      expect(filtered.map((e) => e.id), ['a', 'c']);
    });

    test('private non-member gets locked discovery card flag', () {
      expect(
        GroupDiscoveryLogic.shouldShowLockedPrivateDiscoveryCard(
          data: {'isPrivate': true},
          isMember: false,
        ),
        isTrue,
      );
      expect(
        GroupDiscoveryLogic.shouldShowLockedPrivateDiscoveryCard(
          data: {'isPrivate': true},
          isMember: true,
        ),
        isFalse,
      );
      expect(
        GroupDiscoveryLogic.shouldShowLockedPrivateDiscoveryCard(
          data: {'isPrivate': false},
          isMember: false,
        ),
        isFalse,
      );
    });

    test('opt-out discoverable:false excludes from city discovery', () {
      final data = {
        'scope': 'city',
        'countryCode': 'br',
        'cityKey': 'navegantes',
        'city': 'Navegantes',
        'members': <String>[],
        'discoverable': false,
      };
      expect(
        GroupDiscoveryLogic.matchesCityDiscovery(
          data: data,
          uid: 'u1',
          userCountryCode: 'br',
          userCityKey: 'navegantes',
        ),
        isFalse,
      );
    });

    test('canHideWhileMember blocks hide until leave', () {
      expect(GroupHiddenPrefsService.canHideWhileMember(isMember: true), isFalse);
      expect(GroupHiddenPrefsService.canHideWhileMember(isMember: false), isTrue);
    });

    test('local hide persists and unhide clears for same uid only', () async {
      SharedPreferences.setMockInitialValues({});
      final service = GroupHiddenPrefsService(
        prefsFactory: SharedPreferences.getInstance,
        enableRemote: false,
      );

      await service.hideGroup(uid: 'uidA', groupId: 'g1', groupName: 'Test');
      final a = await service.loadHiddenIds('uidA');
      final b = await service.loadHiddenIds('uidB');
      expect(a, contains('g1'));
      expect(b, isEmpty);

      await service.unhideGroup(uid: 'uidA', groupId: 'g1');
      final a2 = await service.loadHiddenIds('uidA');
      expect(a2, isNot(contains('g1')));
    });

    test('mine membership still true until leave (data without uid)', () {
      final data = {
        'members': ['u1', 'u2'],
        'isPrivate': true,
        'deleted': false,
      };
      expect(GroupDiscoveryLogic.matchesMine(data, 'u1'), isTrue);
      expect(GroupDiscoveryLogic.matchesMine(data, 'u3'), isFalse);
    });

    test('BR user cannot access CA group during free launch', () {
      expect(
        RemdyLaunchAccess.canAccessGroupCountry(
          userHomeCountryCode: 'br',
          groupCountryCode: 'ca',
        ),
        isFalse,
      );
      expect(
        RemdyLaunchAccess.canAccessGroupCountry(
          userHomeCountryCode: 'ca',
          groupCountryCode: 'br',
        ),
        isFalse,
      );
      expect(
        RemdyLaunchAccess.canAccessGroupCountry(
          userHomeCountryCode: 'br',
          groupCountryCode: 'br',
        ),
        isTrue,
      );
    });

    test('hide is personal preference — never implies global delete', () {
      // Documentação viva do contrato: hide ≠ deleteGroup.
      final stillExists = {
        'deleted': false,
        'isActive': true,
        'members': ['owner1', 'other'],
      };
      expect(GroupDiscoveryLogic.isDeletedOrInactive(stillExists), isFalse);
      expect(
        GroupDiscoveryLogic.excludeHidden(
          items: [
            GroupDiscoveryItem(id: 'g', data: stillExists),
          ],
          hiddenIds: {'g'},
        ),
        isEmpty,
      );
      expect(stillExists['deleted'], isFalse);
      expect((stillExists['members'] as List).length, 2);
    });
  });
}
