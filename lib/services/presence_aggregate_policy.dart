import 'online_status.dart';

/// Resultado da consulta a outras sessões do mesmo UID.
enum OtherSessionsLookup {
  /// Existe pelo menos uma outra sessão online (fresca).
  hasOtherOnline,

  /// Nenhuma outra sessão online (consulta completa e determinística).
  noOtherOnline,

  /// Rede, Rules ou falha — não é seguro concluir.
  inconclusive,
}

/// Política de escrita do agregado `publicUsers/{uid}` / `users/{uid}`.
///
/// Regras:
/// - Sessão do aparelho é a fonte verdadeira no cliente.
/// - O cliente **nunca** grava `isOnline: false` no agregado a partir de
///   leitura+escrita local (corrida multi-aparelho / fail-open).
/// - Offline do agregado: Cloud Function (`onPublicUserSessionWritten`) ou
///   expiração natural de `lastSeenAt` na UI.
class PresenceAggregatePolicy {
  PresenceAggregatePolicy._();

  /// Cliente pode renovar o agregado como online no heartbeat.
  static bool shouldClientWriteAggregateOnline({required bool sessionOnline}) {
    return sessionOnline;
  }

  /// Cliente NÃO deve gravar agregado offline, independentemente do lookup.
  static bool shouldClientWriteAggregateOffline(
    OtherSessionsLookup lookup,
  ) {
    // Mesmo com [noOtherOnline], o cliente não fecha o agregado:
    // outro aparelho pode estar a escrever online em paralelo.
    return false;
  }

  /// Classifica sessões irmãs de forma determinística (sem `.limit` cego).
  static OtherSessionsLookup classifyOtherSessions({
    required Iterable<Map<String, dynamic>> sessionDocs,
    required String currentSessionId,
    required DateTime now,
    String Function(Map<String, dynamic> data)? idOf,
  }) {
    final idFn = idOf ??
        (Map<String, dynamic> d) => (d['sessionId'] ?? '').toString();
    var sawAny = false;
    for (final data in sessionDocs) {
      sawAny = true;
      final sid = idFn(data).trim();
      if (sid.isNotEmpty && sid == currentSessionId) continue;
      // Fallback: se o mapa não traz sessionId, o caller deve injetar o doc id.
      if (OnlineStatus.isOnline(data, now)) {
        return OtherSessionsLookup.hasOtherOnline;
      }
    }
    // Lista vazia ou só a sessão atual = nenhuma outra online.
    // (Consulta vazia por erro de permissão deve ser marcada inconclusive
    // pelo caller — aqui assumimos snapshot bem-sucedido.)
    if (!sawAny) return OtherSessionsLookup.noOtherOnline;
    return OtherSessionsLookup.noOtherOnline;
  }

  /// Agregação server-side a partir de todas as sessões (espelho da CF).
  static bool aggregateOnlineFromSessions({
    required Iterable<Map<String, dynamic>> sessions,
    required DateTime now,
  }) {
    for (final data in sessions) {
      if (OnlineStatus.isOnline(data, now)) return true;
    }
    return false;
  }

  /// Conta UIDs únicos online (um UID = 1, mesmo com N sessões).
  static int countUniqueUidsOnline({
    required Iterable<Map<String, dynamic>> sessions,
    required DateTime now,
    required String Function(Map<String, dynamic> data) uidOf,
  }) {
    return OnlineStatus.countUniqueOnline(
      docs: sessions,
      now: now,
      idOf: uidOf,
    );
  }
}
