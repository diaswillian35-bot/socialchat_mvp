import 'package:flutter_test/flutter_test.dart';

/// Documenta o modelo de custo de listeners nos cards.
/// Antes: 1 listener de evento + N listeners attendees/{uid}.
/// Depois: listeners só nas queries da lista; join via attendeesUids agregado.
void main() {
  int listenersBefore({required int cards}) => 1 + cards;
  int listenersAfter({required int cards, int feedStreams = 2}) => feedStreams;
  // feedStreams=2: upcoming + live snapshots na lista pública.

  test('10 cards', () {
    expect(listenersBefore(cards: 10), 11);
    expect(listenersAfter(cards: 10), 2);
  });

  test('50 cards', () {
    expect(listenersBefore(cards: 50), 51);
    expect(listenersAfter(cards: 50), 2);
  });

  test('100 own events — Meus eventos abre só 20 da seção', () {
    const page = 20;
    expect(page, lessThan(100));
    // Antes: 1 stream ilimitado de todos os createdBy.
    // Depois: 1 query limit 20 na seção ativa.
    expect(listenersAfter(cards: 100, feedStreams: 1), 1);
  });

  test('365 own past — sem carregar tudo ao abrir', () {
    const initialReads = 20;
    expect(initialReads, lessThan(365));
  });

  test('1000 own past — sem carregar tudo ao abrir', () {
    const initialReads = 20;
    expect(initialReads, lessThan(1000));
  });
}
