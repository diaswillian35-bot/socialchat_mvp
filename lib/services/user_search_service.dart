import 'package:cloud_functions/cloud_functions.dart';

import '../utils/user_search_normalize.dart';
import 'international_chat_service.dart';

/// Tipos de pesquisa permitidos (espelha whitelist da Cloud Function).
enum UserSearchType {
  name,
  city,
  region,
  country,
}

extension UserSearchTypeX on UserSearchType {
  String get apiValue {
    switch (this) {
      case UserSearchType.name:
        return 'name';
      case UserSearchType.city:
        return 'city';
      case UserSearchType.region:
        return 'region';
      case UserSearchType.country:
        return 'country';
    }
  }

  /// Chave de hint / empty state por filtro.
  String get hintKey {
    switch (this) {
      case UserSearchType.name:
        return 'user_search_hint';
      case UserSearchType.city:
        return 'user_search_hint_city';
      case UserSearchType.region:
        return 'user_search_hint_region';
      case UserSearchType.country:
        return 'user_search_hint_country';
    }
  }

  String get emptyKey {
    switch (this) {
      case UserSearchType.name:
        return 'user_search_empty';
      case UserSearchType.city:
        return 'user_search_empty_city';
      case UserSearchType.region:
        return 'user_search_empty_region';
      case UserSearchType.country:
        return 'user_search_empty_country';
    }
  }

  String get resultsKey {
    switch (this) {
      case UserSearchType.name:
        return 'user_search_results';
      case UserSearchType.city:
        return 'user_search_results_city';
      case UserSearchType.region:
        return 'user_search_results_region';
      case UserSearchType.country:
        return 'user_search_results_country';
    }
  }
}

/// Resultado público seguro.
class UserSearchHit {
  const UserSearchHit({
    required this.uid,
    required this.name,
    this.photoUrl,
    this.city,
    this.region,
    this.country,
    this.countryCode,
  });

  final String uid;
  final String name;
  final String? photoUrl;
  final String? city;
  final String? region;
  final String? country;
  final String? countryCode;

  Map<String, dynamic> toSafeMap() => {
        'uid': uid,
        'name': name,
        if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
        if (city != null && city!.isNotEmpty) 'city': city,
        if (region != null && region!.isNotEmpty) 'region': region,
        if (country != null && country!.isNotEmpty) 'country': country,
        if (countryCode != null && countryCode!.isNotEmpty)
          'countryCode': countryCode,
      };

  static const _allowedKeys = {
    'uid',
    'name',
    'photoUrl',
    'city',
    'region',
    'country',
    'countryCode',
  };

  /// Lê SOMENTE campos seguros; descarta chaves desconhecidas.
  static UserSearchHit? fromCallable(Map<Object?, Object?> raw) {
    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      if (_allowedKeys.contains(key)) {
        map[key] = entry.value;
      }
    }

    final uid = (map['uid'] ?? '').toString().trim();
    final name = (map['name'] ?? '').toString().trim();
    if (uid.isEmpty || name.isEmpty) return null;

    String? opt(String k) {
      final v = (map[k] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }

    return UserSearchHit(
      uid: uid,
      name: name,
      photoUrl: opt('photoUrl'),
      city: opt('city'),
      region: opt('region'),
      country: opt('country'),
      countryCode: opt('countryCode')?.toLowerCase(),
    );
  }
}

/// Cursor opaco/seguro: { v, id }.
class UserSearchCursor {
  const UserSearchCursor({required this.v, required this.id});

  final String v;
  final String id;

  Map<String, String> toMap() => {'v': v, 'id': id};

  static UserSearchCursor? fromDynamic(Object? raw) {
    if (raw is! Map) return null;
    final v = (raw['v'] ?? raw['value'] ?? '').toString();
    final id = (raw['id'] ?? raw['docId'] ?? '').toString().trim();
    if (v.isEmpty || id.isEmpty) return null;
    if (id.length > 128) return null;
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) return null;
    return UserSearchCursor(v: v, id: id);
  }
}

class UserSearchPageResult {
  const UserSearchPageResult({
    required this.hits,
    required this.hasMore,
    this.nextCursor,
    this.type = UserSearchType.name,
  });

  final List<UserSearchHit> hits;
  final bool hasMore;
  final UserSearchCursor? nextCursor;
  final UserSearchType type;
}

/// Debounce helper testável.
class UserSearchDebounce {
  UserSearchDebounce({this.delay = const Duration(milliseconds: 400)});

  final Duration delay;
  int _generation = 0;

  /// Incrementa geração; retorna true se [token] ainda for a geração atual.
  int schedule() => ++_generation;

  bool isCurrent(int token) => token == _generation;

  void cancel() => _generation++;
}

/// Busca via Cloud Function `searchUsers` (us-central1).
class UserSearchService {
  UserSearchService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  static const int defaultPageSize = 20;

  Future<UserSearchPageResult> search({
    required String rawQuery,
    required UserSearchType type,
    UserSearchCursor? cursor,
    int pageSize = defaultPageSize,
  }) async {
    if (!UserSearchNormalize.isQueryReady(rawQuery)) {
      return UserSearchPageResult(
        hits: const [],
        hasMore: false,
        type: type,
      );
    }

    final callable = _functions.httpsCallable('searchUsers');
    final response = await callable.call<Object?>({
      'query': rawQuery,
      'type': type.apiValue,
      'limit': pageSize,
      if (cursor != null) 'cursor': cursor.toMap(),
    });

    return parseResult(response.data, fallbackType: type);
  }

  /// Alias legado.
  Future<UserSearchPageResult> searchByName({
    required String rawQuery,
    Object? cursor,
    int pageSize = defaultPageSize,
  }) {
    return search(
      rawQuery: rawQuery,
      type: UserSearchType.name,
      cursor: cursor is UserSearchCursor
          ? cursor
          : UserSearchCursor.fromDynamic(cursor),
      pageSize: pageSize,
    );
  }

  static UserSearchPageResult parseResult(
    Object? data, {
    UserSearchType fallbackType = UserSearchType.name,
  }) {
    if (data is! Map) {
      return UserSearchPageResult(
        hits: const [],
        hasMore: false,
        type: fallbackType,
      );
    }

    final hits = <UserSearchHit>[];
    final rawList = data['results'];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          final hit = UserSearchHit.fromCallable(item.cast<Object?, Object?>());
          if (hit != null) hits.add(hit);
        }
      }
    }

    final next = UserSearchCursor.fromDynamic(data['nextCursor']);
    final hasMore = data['hasMore'] == true;
    final type = _parseType(data['type']) ?? fallbackType;

    return UserSearchPageResult(
      hits: hits,
      hasMore: hasMore,
      nextCursor: next,
      type: type,
    );
  }

  static UserSearchType? _parseType(Object? raw) {
    switch ((raw ?? '').toString()) {
      case 'name':
        return UserSearchType.name;
      case 'city':
        return UserSearchType.city;
      case 'region':
        return UserSearchType.region;
      case 'country':
        return UserSearchType.country;
      default:
        return null;
    }
  }

  static Future<String> getOrCreateConversation({
    required String myUid,
    required String otherUid,
  }) {
    return InternationalChatService.getOrCreateConversation(myUid, otherUid);
  }
}

/// Campos normalizados públicos (cliente ao salvar perfil).
class PublicUserSearchFields {
  static Map<String, String> build({
    required String name,
    String? city,
    String? region,
    String? country,
    String? countryCode,
  }) {
    final out = <String, String>{};
    final n = name.trim();
    if (n.isNotEmpty) {
      out['nameSearch'] = UserSearchNormalize.normalize(n);
    }
    final c = (city ?? '').trim();
    if (c.isNotEmpty) {
      out['citySearch'] = UserSearchNormalize.normalize(c);
    }
    final r = (region ?? '').trim();
    if (r.isNotEmpty) {
      out['regionSearch'] = UserSearchNormalize.normalize(r);
    }
    final co = (country ?? '').trim();
    if (co.isNotEmpty) {
      out['countrySearch'] = UserSearchNormalize.normalize(co);
    }
    final cc = (countryCode ?? '').trim().toLowerCase();
    if (cc.isNotEmpty) {
      out['countryCode'] = cc;
    }
    return out;
  }
}
