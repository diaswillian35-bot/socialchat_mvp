import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/group_discovery_logic.dart';
import 'package:socialchat_mvp/services/group_location_normalize.dart';

void main() {
  Map<String, dynamic> yorkCreatedOnPhone15() => {
        'id': 'created-on-15',
        'scope': 'city',
        'countryCode': 'ca',
        'city': 'York',
        'cityName': 'York',
        'cityKey': 'york',
        'displayLocation': 'York, ON, Canadá',
        'deleted': false,
        'ownerId': 'phone15',
        'members': ['phone15'],
        'admins': ['phone15'],
      };

  Map<String, dynamic> legacyToronto() => {
        'id': 'legacy',
        'scope': 'city',
        'countryCode': 'ca',
        'city': 'Toronto',
        'cityName': 'Toronto',
        'cityKey': 'toronto',
        'displayLocation': 'North York, ON, Canadá',
        'deleted': false,
        'ownerId': 'phone15',
        'members': ['phone15', 'phone16'],
        'admins': ['phone15'],
      };

  test('opening the list after a live snapshot cannot keep the spinner', () {
    final outcome = GroupDiscoveryLogic.completeListFetch(
      liveSeen: true,
      failed: false,
      hasItems: true,
    );
    expect(outcome.loading, isFalse);
    expect(outcome.loadedOnce, isTrue);
    expect(outcome.applyRemotePage, isFalse);
    expect(outcome.showError, isFalse);

    final ui = GroupDiscoveryLogic.decideState(
      profileLoaded: true,
      locationOk: true,
      loading: outcome.loading,
      hasError: false,
      hasItems: true,
    );
    expect(ui, GroupDiscoveryUiState.list);
  });

  test('phone 16 sees its own group and not a York group it did not join', () {
    final created = yorkCreatedOnPhone15();
    final legacy = legacyToronto();
    final mine = GroupDiscoveryLogic.replaceMembershipSnapshot(
      previous: const [],
      updates: {
        'legacy': legacy,
        'created-on-15': created,
      },
    );
    final phone16 = mine.where((item) {
      return GroupDiscoveryLogic.matchesMine(item.data, 'phone16');
    }).toList();
    expect(phone16.map((item) => item.id), ['legacy']);
    expect(
      GroupLocationNormalize.cityDisplayName(legacy),
      'North York',
    );

    final cityForPhone16 = GroupDiscoveryLogic.visibleDiscoveryFromDocs(
      docs: [created, legacy],
      tab: GroupDiscoveryTab.city,
      uid: 'phone16',
      userCountryCode: 'ca',
      userCityKey: 'toronto',
      userCityLatitude: 43.65,
      userCityLongitude: -79.38,
      pendingIds: const {},
    );
    expect(cityForPhone16.map((item) => item.id), isNot(contains('created-on-15')));
    expect(cityForPhone16.map((item) => item.id), isNot(contains('legacy')));

    final yorkViewer = GroupDiscoveryLogic.visibleDiscoveryFromDocs(
      docs: [created],
      tab: GroupDiscoveryTab.city,
      uid: 'other',
      userCountryCode: 'ca',
      userCityKey: 'york',
      userCityLatitude: null,
      userCityLongitude: null,
      pendingIds: const {},
    );
    expect(yorkViewer.single.id, 'created-on-15');
  });

  test('a failed index or permission does not hide groups already loaded', () {
    final failedEmpty = GroupDiscoveryLogic.completeListFetch(
      liveSeen: false,
      failed: true,
      hasItems: false,
    );
    expect(failedEmpty.loading, isFalse);
    expect(failedEmpty.loadedOnce, isTrue);
    expect(failedEmpty.showError, isTrue);
    expect(
      GroupDiscoveryLogic.decideState(
        profileLoaded: true,
        locationOk: true,
        loading: failedEmpty.loading,
        hasError: failedEmpty.showError,
        hasItems: false,
      ),
      GroupDiscoveryUiState.error,
    );

    final failedButCached = GroupDiscoveryLogic.completeListFetch(
      liveSeen: false,
      failed: true,
      hasItems: true,
    );
    expect(failedButCached.showError, isFalse);
    expect(failedButCached.applyRemotePage, isFalse);
    expect(failedButCached.loading, isFalse);
  });

  test('one tab failing leaves the other tab able to show its groups', () {
    final mine = GroupDiscoveryLogic.completeListFetch(
      liveSeen: true,
      failed: false,
      hasItems: true,
    );
    final city = GroupDiscoveryLogic.completeListFetch(
      liveSeen: false,
      failed: true,
      hasItems: false,
    );
    expect(mine.showError, isFalse);
    expect(mine.loading, isFalse);
    expect(city.showError, isTrue);
    expect(city.loading, isFalse);
  });

  test('a legacy membership document still appears for its member', () {
    final legacy = {
      'id': 'old',
      'deleted': false,
      'members': ['phone16'],
      'scope': 'unknown',
    };
    expect(GroupDiscoveryLogic.matchesMine(legacy, 'phone16'), isTrue);
    final listed = GroupDiscoveryLogic.replaceMembershipSnapshot(
      previous: const [],
      updates: {'old': legacy},
    );
    expect(listed.single.id, 'old');
    expect(
      GroupDiscoveryLogic.visibleDiscoveryFromDocs(
        docs: [legacy],
        tab: GroupDiscoveryTab.city,
        uid: 'other',
        userCountryCode: 'ca',
        userCityKey: 'toronto',
        userCityLatitude: null,
        userCityLongitude: null,
        pendingIds: const {},
      ),
      isEmpty,
    );
  });
}
