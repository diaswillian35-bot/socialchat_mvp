import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/pages/country_people_page.dart').readAsStringSync();

  test('country page paginates beyond first 40 and search drains pages', () {
    expect(source, contains('static const int _pageSize = 40'));
    expect(source, contains('startAfterDocument(_lastDoc!)'));
    expect(source, contains('while (_hasMore && _lastDoc != null)'));
  });

  test('country page uses live presence and nested accordions without counts',
      () {
    expect(source, contains('PresenceOnlineSetBuilder'));
    expect(source, contains("PageStorageKey('country-state-"));
    expect(source, contains('CountryPeopleView.build'));
    expect(source, isNot(contains('people.length}')));
  });

  test('all country sections open by default', () {
    expect(source, contains('people_other_cities_of_state'));
    expect(source, contains('people_near_you_region'));
    expect(source, contains('people_say_hi'));
    // Barra de baixo: switch Só explorar (mesma lógica do Editar perfil).
    expect(source, contains('ExploreOnly.setMode(uid, value)'));
    expect(source, contains('people_explore_only_now_on'));
    // Falha: volta o switch e mostra erro.
    expect(source, contains("'exploreOnly': previous"));
    expect(source, contains("get('save_error')"));
    expect(source, contains('Share.share'));
    expect(source, isNot(contains('nearbyCities')));
  });

  test('security and international chat paths remain wired', () {
    expect(source, contains('blockedUids.contains'));
    expect(source, contains("ageVerificationStatus'] != 'verified'"));
    // Opt-in "Mostrar pessoas perto de mim" continua obrigatório.
    expect(source, contains("data['nearbyEnabled'] != true"));
    expect(source, contains('InternationalChatService.canSendMessage'));
    expect(source, contains('BlockService.allowOpenPeer'));
  });
}
