import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/utils/event_lifecycle.dart';

/// Contrato da lista pública clássica após organização por data (local).
void main() {
  String readEventsPage() =>
      File('lib/pages/events_page_new.dart').readAsStringSync();

  String readShell() => File('lib/pages/main_shell_page.dart').readAsStringSync();

  String readHomeDiscover() =>
      File('lib/widgets/home_discover_section.dart').readAsStringSync();

  group('wiring', () {
    test('aba Eventos usa EventsPage', () {
      final shell = readShell();
      expect(shell.contains('const EventsPage()'), isTrue);
      expect(shell.contains('EventsDiscoverPage'), isFalse);
    });

    test('IndexedStack mantém páginas vivas', () {
      final shell = readShell();
      expect(shell.contains('IndexedStack('), isTrue);
    });

    test('Home Ver todos seleciona a aba Eventos do shell', () {
      final home = readHomeDiscover();
      expect(home.contains('EventDetailPage('), isTrue);
      expect(home.contains('onOpenEventsTab'), isTrue);
      expect(home.contains('EventsDiscoverPage'), isFalse);
      expect(
        home.contains("MaterialPageRoute(builder: (_) => const EventsDiscoverPage())"),
        isFalse,
      );
    });

    test('card navega para EventDetailPage', () {
      final src = readEventsPage();
      expect(src.contains('EventDetailPage('), isTrue);
      expect(src.contains("builder: (_) => EventDetailPage("), isTrue);
    });
  });

  group('queries Firestore (contrato date-org)', () {
    test('usa EventListQueries publicUpcoming + publicLive', () {
      final src = readEventsPage();
      expect(src.contains('EventListQueries.publicUpcoming'), isTrue);
      expect(src.contains('EventListQueries.publicLive'), isTrue);
      expect(src.contains('EventLifecycle.passesPublicVisibility'), isTrue);
    });

    test('sem listener attendees/{uid} por card', () {
      final src = readEventsPage();
      expect(src.contains(".collection('attendees')"), isFalse);
      expect(src.contains('_isJoinedLocally'), isTrue);
      expect(src.contains('attendeesUids'), isTrue);
    });

    test('join/leave usam EventAttendanceService', () {
      final src = readEventsPage();
      expect(src.contains('EventAttendanceService.joinEvent'), isTrue);
      expect(src.contains('EventAttendanceService.leaveEvent'), isTrue);
      expect(
        src.contains("attendeesUids': FieldValue.arrayUnion"),
        isFalse,
      );
    });
  });

  group('filtros client-side', () {
    test('cancelado/apagado/arquivado/inativo não passam visibilidade pública', () {
      expect(
        EventLifecycle.passesPublicVisibility({
          'status': 'approved',
          'isActive': true,
        }),
        isTrue,
      );
      expect(
        EventLifecycle.passesPublicVisibility({
          'status': 'cancelled',
          'isActive': true,
        }),
        isFalse,
      );
      expect(
        EventLifecycle.passesPublicVisibility({
          'status': 'approved',
          'isActive': true,
          'deleted': true,
        }),
        isFalse,
      );
      expect(
        EventLifecycle.passesPublicVisibility({
          'status': 'approved',
          'isActive': true,
          'archived': true,
        }),
        isFalse,
      );
    });

    test('arredores exclui mesma cidade e >110km (espelho)', () {
      bool nearbyScopeKeeps({
        required String eventCity,
        required String userCity,
        required double? userLat,
        required double? userLng,
        required double? eventLat,
        required double? eventLng,
        required double Function(double, double, double, double) distanceKm,
      }) {
        if (userLat == null || userLng == null) return false;
        if (eventLat == null || eventLng == null) return false;
        if (eventCity.toLowerCase().trim() == userCity.toLowerCase().trim()) {
          return false;
        }
        final d = distanceKm(userLat, userLng, eventLat, eventLng);
        return d <= 110;
      }

      expect(
        nearbyScopeKeeps(
          eventCity: 'toronto',
          userCity: 'toronto',
          userLat: 1,
          userLng: 1,
          eventLat: 1,
          eventLng: 1,
          distanceKm: (a, b, c, d) => 50,
        ),
        isFalse,
      );
      expect(
        nearbyScopeKeeps(
          eventCity: 'ottawa',
          userCity: 'toronto',
          userLat: 1,
          userLng: 1,
          eventLat: 1,
          eventLng: 1,
          distanceKm: (a, b, c, d) => 80,
        ),
        isTrue,
      );
      expect(
        nearbyScopeKeeps(
          eventCity: 'ottawa',
          userCity: 'toronto',
          userLat: 1,
          userLng: 1,
          eventLat: 1,
          eventLng: 1,
          distanceKm: (a, b, c, d) => 101,
        ),
        isTrue,
      );
      expect(
        nearbyScopeKeeps(
          eventCity: 'ottawa',
          userCity: 'toronto',
          userLat: 1,
          userLng: 1,
          eventLat: 1,
          eventLng: 1,
          distanceKm: (a, b, c, d) => 120,
        ),
        isFalse,
      );
    });

    test('wiring Brasil / constante 110', () {
      final src = readEventsPage();
      expect(src.contains('EventsBrasilExploreLogic'), isTrue);
      expect(src.contains('EVENTS_SURROUNDINGS_RADIUS_KM'), isTrue);
      expect(src.contains('publicUpcomingExplore'), isTrue);
      expect(src.contains('_buildBrasilExplore'), isTrue);
      expect(src.contains('events_brasil_search_hint'), isTrue);
    });
  });

  group('estados UI', () {
    test('loading, erro com retry e vazio', () {
      final src = readEventsPage();
      expect(src.contains('CircularProgressIndicator'), isTrue);
      expect(src.contains('snap.hasError'), isTrue);
      expect(src.contains('events_retry'), isTrue);
      expect(src.contains('events_load_error'), isTrue);
      expect(src.contains('events_empty_city'), isTrue);
      expect(src.contains('events_empty_nearby'), isTrue);
      expect(src.contains('EventsCountryScope'), isTrue);
      expect(src.contains('emptySubdivisionsLabel'), isTrue);
      expect(src.contains('emptySubdivisionLabel'), isTrue);
      expect(src.contains('events_need_country'), isTrue);
    });

    test('SafeArea + RemdyLogo', () {
      final src = readEventsPage();
      expect(src.contains('SafeArea('), isTrue);
      expect(src.contains('RemdyLogo()'), isTrue);
    });
  });
}
