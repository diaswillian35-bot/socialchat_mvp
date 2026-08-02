import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:socialchat_mvp/services/groups_list_logic.dart';

void main() {
  group('GroupsListLogic.decideState', () {
    test('carregamento com grupos: hasData => loaded', () {
      expect(
        GroupsListLogic.decideState(
          hasError: false,
          hasData: true,
          waiting: false,
        ),
        GroupsListState.loaded,
      );
    });

    test('resultado vazio ainda é "loaded" (não spinner infinito)', () {
      // Uma lista vazia é dado válido: o estado é "loaded" e a UI decide a
      // mensagem de vazio. Nunca deve virar spinner eterno.
      expect(
        GroupsListLogic.decideState(
          hasError: false,
          hasData: true,
          waiting: false,
        ),
        GroupsListState.loaded,
      );
    });

    test('sem dados e aguardando => loading', () {
      expect(
        GroupsListLogic.decideState(
          hasError: false,
          hasData: false,
          waiting: true,
        ),
        GroupsListState.loading,
      );
    });

    test('stream que emite erro => error (mesmo aguardando)', () {
      expect(
        GroupsListLogic.decideState(
          hasError: true,
          hasData: false,
          waiting: true,
        ),
        GroupsListState.error,
      );
    });

    test('erro tem prioridade sobre dados antigos', () {
      expect(
        GroupsListLogic.decideState(
          hasError: true,
          hasData: true,
          waiting: false,
        ),
        GroupsListState.error,
      );
    });

    test('reinscrição transitória com dados não volta ao spinner', () {
      // hasData true + waiting true (novo stream trazendo cache) => loaded,
      // preservando a lista já exibida.
      expect(
        GroupsListLogic.decideState(
          hasError: false,
          hasData: true,
          waiting: true,
        ),
        GroupsListState.loaded,
      );
    });
  });

  group('GroupsListLogic.errorMessageKey', () {
    test('erro de permissão', () {
      final e = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      expect(GroupsListLogic.errorMessageKey(e), 'groups_error_permission');
    });

    test('erro de índice (failed-precondition)', () {
      final e = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'failed-precondition',
        message: 'The query requires an index.',
      );
      expect(GroupsListLogic.errorMessageKey(e), 'groups_error_index');
    });

    test('indisponível também mostra mensagem amigável de índice/serviço', () {
      final e = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      expect(GroupsListLogic.errorMessageKey(e), 'groups_error_index');
    });

    test('erro genérico/desconhecido cai no erro de carregamento', () {
      expect(GroupsListLogic.errorMessageKey(Exception('boom')),
          'groups_load_error');
      expect(GroupsListLogic.errorMessageKey(null), 'groups_load_error');
    });
  });

  group('GroupsListLogic.emptyMessageKey', () {
    test('perfil sem país => orientação de localização', () {
      expect(
        GroupsListLogic.emptyMessageKey(
          profileLoaded: true,
          countryCode: '',
        ),
        'groups_need_location',
      );
    });

    test('perfil ainda carregando não mostra orientação prematura', () {
      expect(
        GroupsListLogic.emptyMessageKey(
          profileLoaded: false,
          countryCode: '',
        ),
        'no_groups_found',
      );
    });

    test('com país definido => "nenhum grupo encontrado"', () {
      expect(
        GroupsListLogic.emptyMessageKey(
          profileLoaded: true,
          countryCode: 'br',
        ),
        'no_groups_found',
      );
    });
  });

  group('GroupsListLogic.streamKey', () {
    test('usuário Free ignora seletor de país e busca (client-side)', () {
      final a = GroupsListLogic.streamKey(
        isPremium: false,
        countryCode: 'br',
        selectedCountry: 'all',
        searchActive: false,
        retryToken: 0,
      );
      final b = GroupsListLogic.streamKey(
        isPremium: false,
        countryCode: 'br',
        selectedCountry: 'portugal',
        searchActive: true,
        retryToken: 0,
      );
      // Digitar na busca ou trocar o seletor NÃO recria o stream de um Free
      // (evita flicker/spinner ao digitar).
      expect(a, b);
    });

    test('usuário Premium reage ao seletor de país', () {
      final a = GroupsListLogic.streamKey(
        isPremium: true,
        countryCode: 'br',
        selectedCountry: 'all',
        searchActive: false,
        retryToken: 0,
      );
      final b = GroupsListLogic.streamKey(
        isPremium: true,
        countryCode: 'br',
        selectedCountry: 'portugal',
        searchActive: false,
        retryToken: 0,
      );
      expect(a, isNot(b));
    });

    test('Free e Premium produzem chaves diferentes', () {
      final free = GroupsListLogic.streamKey(
        isPremium: false,
        countryCode: 'br',
        selectedCountry: 'all',
        searchActive: false,
        retryToken: 0,
      );
      final premium = GroupsListLogic.streamKey(
        isPremium: true,
        countryCode: 'br',
        selectedCountry: 'all',
        searchActive: false,
        retryToken: 0,
      );
      expect(free, isNot(premium));
    });

    test('retry sem duplicar listener: token muda a chave', () {
      final before = GroupsListLogic.streamKey(
        isPremium: false,
        countryCode: 'br',
        selectedCountry: 'all',
        searchActive: false,
        retryToken: 0,
      );
      final after = GroupsListLogic.streamKey(
        isPremium: false,
        countryCode: 'br',
        selectedCountry: 'all',
        searchActive: false,
        retryToken: 1,
      );
      // Chave nova => StreamBuilder cancela a assinatura anterior e cria uma
      // única nova (sem listeners acumulados).
      expect(before, isNot(after));
    });

    test('mesmos filtros => mesma chave (sair e voltar / hot restart estáveis)',
        () {
      String key() => GroupsListLogic.streamKey(
            isPremium: true,
            countryCode: 'br',
            selectedCountry: 'canada',
            searchActive: true,
            retryToken: 3,
          );
      expect(key(), key());
    });

    test('documento/perfil antigo sem país usa branch estável (country vazio)',
        () {
      final k = GroupsListLogic.streamKey(
        isPremium: false,
        countryCode: '',
        selectedCountry: 'all',
        searchActive: false,
        retryToken: 0,
      );
      expect(k.contains('free'), isTrue);
      // countryCode vazio é aceito sem lançar (não trava a lista).
      expect(k, 'free||||r0');
    });
  });
}
