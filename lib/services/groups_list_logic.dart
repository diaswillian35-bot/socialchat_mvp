import 'package:firebase_core/firebase_core.dart';

/// Estados visuais possíveis da lista de grupos.
///
/// Extraído da UI para ser testável sem Firebase. NÃO contém a lógica de
/// organização por cidade/região/país (mantida na página, intocada).
enum GroupsListState { loading, error, loaded }

/// Regras puras (sem UI, sem Firebase runtime) que controlam a lista de grupos.
///
/// Objetivo principal: eliminar o "carregamento infinito". Antes, o stream do
/// Firestore era recriado a cada build e o `StreamBuilder` voltava para
/// `waiting` (spinner) sem nunca expor dados nem erro. Aqui centralizamos:
///  - a CHAVE do stream (só recriar quando os filtros mudam de verdade);
///  - a DECISÃO de estado (erro tem prioridade sobre spinner);
///  - o MAPEAMENTO de erro/vazio para chaves de tradução.
class GroupsListLogic {
  GroupsListLogic._();

  /// Identidade da consulta atual. O stream só deve ser recriado quando esta
  /// chave muda — rebuilds cosméticos (idioma, banner, digitação em conta
  /// Free) NÃO devem reabrir a assinatura.
  ///
  /// [retryToken] muda a cada "Tentar novamente", garantindo uma nova
  /// assinatura (o `StreamBuilder` cancela a anterior — sem listener duplicado).
  static String streamKey({
    required bool isPremium,
    required String countryCode,
    required String selectedCountry,
    required bool searchActive,
    required int retryToken,
  }) {
    return <String>[
      isPremium ? 'premium' : 'free',
      countryCode.trim().toLowerCase(),
      // O seletor de país só altera a consulta para usuários Premium.
      isPremium ? selectedCountry : '',
      // Busca só altera a consulta (server-side) para Premium.
      (isPremium && searchActive) ? 'search' : '',
      'r$retryToken',
    ].join('|');
  }

  /// Decide o estado a partir do snapshot. Erro tem prioridade; o spinner só
  /// aparece quando ainda não há NENHUM dado (evita apagar a lista atual numa
  /// reinscrição transitória).
  static GroupsListState decideState({
    required bool hasError,
    required bool hasData,
    required bool waiting,
  }) {
    if (hasError) return GroupsListState.error;
    if (!hasData && waiting) return GroupsListState.loading;
    return GroupsListState.loaded;
  }

  /// Chave de tradução para a mensagem de erro amigável.
  static String errorMessageKey(Object? error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'groups_error_permission';
        case 'failed-precondition':
        case 'unavailable':
          return 'groups_error_index';
      }
    }
    return 'groups_load_error';
  }

  /// Chave de tradução para o estado vazio: orienta o usuário quando o perfil
  /// já carregou mas não há país definido; caso contrário, "nenhum grupo".
  static String emptyMessageKey({
    required bool profileLoaded,
    required String countryCode,
  }) {
    if (profileLoaded && countryCode.trim().isEmpty) {
      return 'groups_need_location';
    }
    return 'no_groups_found';
  }
}
