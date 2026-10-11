import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/group_create_flow.dart';
import 'package:socialchat_mvp/services/group_creation_service.dart';
import 'package:socialchat_mvp/widgets/required_field.dart';

void main() {
  const toronto = GroupCityCandidate(
    cityName: 'Toronto',
    stateName: 'ON',
    countryName: 'Canada',
    display: 'Toronto, ON, Canada',
    placeId: 'place-toronto',
  );
  const torontoNorth = GroupCityCandidate(
    cityName: 'Toronto',
    stateName: 'NS',
    countryName: 'Canada',
    display: 'Toronto, NS, Canada',
    placeId: 'place-toronto-ns',
  );

  test('the same account can create a second, third, and later group', () {
    for (final owned in [1, 2, 3, 8]) {
      final id = GroupCreateFlow.requestIdFor(
        currentId: null,
        boundSignature: null,
        signature: 'group-$owned',
        mint: () => 'req-$owned',
      );
      expect(id, 'req-$owned');
    }
  });

  test('a selected or profile city is valid without another list tap', () {
    final decision = GroupCreateFlow.resolveCity(
      required: true,
      typed: 'Toronto, ON, Canada',
      selectedPlaceId: 'place-toronto',
      selectedCityName: 'Toronto',
      selectedStateName: 'ON',
      selectedDisplay: 'Toronto, ON, Canada',
      suggestions: const [],
      searched: false,
    );
    expect(decision.accepted, isTrue);
    expect(decision.pending, isFalse);
    expect(decision.placeId, 'place-toronto');
  });

  test('typed text with one matching suggestion is accepted', () {
    final decision = GroupCreateFlow.resolveCity(
      required: true,
      typed: 'Toronto',
      selectedPlaceId: '',
      selectedCityName: '',
      selectedStateName: '',
      selectedDisplay: '',
      suggestions: const [toronto],
      searched: true,
    );
    expect(decision.accepted, isTrue);
    expect(decision.placeId, 'place-toronto');
    expect(decision.messageKey, isNull);
  });

  test('an unknown city stays pending with a specific message', () {
    final decision = GroupCreateFlow.resolveCity(
      required: true,
      typed: 'Cidade Inexistente',
      selectedPlaceId: '',
      selectedCityName: '',
      selectedStateName: '',
      selectedDisplay: '',
      suggestions: const [],
      searched: true,
    );
    expect(decision.accepted, isFalse);
    expect(decision.pending, isTrue);
    expect(decision.messageKey, 'group_create_city_invalid');
    expect(decision.messageKey, isNot('group_create_error'));
  });

  test('several suggestions stay pending until one is chosen', () {
    final decision = GroupCreateFlow.resolveCity(
      required: true,
      typed: 'Toronto',
      selectedPlaceId: '',
      selectedCityName: '',
      selectedStateName: '',
      selectedDisplay: '',
      suggestions: const [toronto, torontoNorth],
      searched: true,
    );
    expect(decision.pending, isTrue);
    expect(decision.messageKey, 'group_create_place_required');
  });

  test('a double tap reuses the request id and a new form mints another', () {
    const signature = 'name\u0001city\u0001place\u0001ca\u0001open';
    final first = GroupCreateFlow.requestIdFor(
      currentId: null,
      boundSignature: null,
      signature: signature,
      mint: () => 'req-1',
    );
    final retry = GroupCreateFlow.requestIdFor(
      currentId: first,
      boundSignature: signature,
      signature: signature,
      mint: () => 'req-2',
    );
    final nextGroup = GroupCreateFlow.requestIdFor(
      currentId: first,
      boundSignature: signature,
      signature: 'other-name\u0001city\u0001place\u0001ca\u0001open',
      mint: () => 'req-3',
    );
    expect(retry, 'req-1');
    expect(nextGroup, 'req-3');
    expect(GroupCreateFlow.shouldStartSubmit(inFlight: true), isFalse);
    expect(GroupCreateFlow.shouldStartSubmit(inFlight: false), isTrue);
  });

  test('an image failure keeps the group and does not create another', () {
    final finish = GroupCreateFlow.finish(
      groupId: 'group-2',
      avatarFailed: true,
    );
    expect(finish.keepGroup, isTrue);
    expect(finish.createAgain, isFalse);
    expect(finish.toastKey, 'group_create_avatar_failed');
    expect(finish.toastKey, isNot('group_create_error'));
  });

  test('city and place failures are specific, not the generic create error', () {
    expect(
      GroupCreationService.errorKey(
        FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'placeId required.',
        ),
      ),
      'group_create_place_required',
    );
    expect(
      GroupCreationService.errorKey(
        FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'Invalid placeId.',
        ),
      ),
      'group_create_city_invalid',
    );
    expect(
      GroupCreationService.errorKey(
        FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'City/country mismatch.',
        ),
      ),
      'group_create_city_country',
    );
    expect(
      GroupCreationService.errorKey(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Places lookup unavailable.',
        ),
      ),
      'group_create_places_unavailable',
    );
  });

  test('callable data is read without throwing on a loosely typed map', () {
    final data = GroupCreationService.readCallableData(<Object?, Object?>{
      'groupId': 'abc',
      'created': true,
    });
    expect(data['groupId'], 'abc');
    expect(GroupCreationService.readCallableData(null), isEmpty);
  });

  test('pending state appears only after blur or submit and is not color-only', () {
    expect(
      RequiredFieldChrome.reveal(
        invalid: true,
        blurred: false,
        submitAttempted: false,
      ),
      isFalse,
    );
    expect(
      RequiredFieldChrome.reveal(
        invalid: true,
        blurred: true,
        submitAttempted: false,
      ),
      isTrue,
    );
    final page = File('lib/pages/create_group_page.dart').readAsStringSync();
    final notice = File('lib/widgets/required_field.dart').readAsStringSync();
    expect(page, contains('RequiredPendingNotice'));
    expect(page, contains('field_pending'));
    expect(notice, contains('Icons.error_outline'));
    expect(notice, contains('pendingLabel'));
  });

  test('create flow is the same on Android and iOS and does not delete a group', () {
    final flow = File('lib/services/group_create_flow.dart').readAsStringSync();
    final page = File('lib/pages/create_group_page.dart').readAsStringSync();
    expect(flow, isNot(contains('Platform.is')));
    expect(flow, isNot(contains('dart:io')));
    expect(page, contains('GroupCreateFlow.finish'));
    expect(page, contains('_uploadCover'));
    expect(page, isNot(contains('deleteGroup')));
    expect(page, isNot(contains('ownedCount')));
    expect(page, isNot(contains('_createdOnce')));
  });
}
