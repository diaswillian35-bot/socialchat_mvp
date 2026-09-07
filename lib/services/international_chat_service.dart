import 'package:cloud_firestore/cloud_firestore.dart';

import 'international_country_codes.dart';
import 'premium_access_service.dart';
import 'remdy_launch_access.dart';

/// Erro ao consultar conversas existentes — não criar DM sem confirmação.
class ConversationLookupException implements Exception {
  ConversationLookupException(this.messageKey);
  final String messageKey;

  @override
  String toString() => 'ConversationLookupException($messageKey)';
}

/// Regras centralizadas de conversa internacional (país = homeCountryCode).
class InternationalChatService {
  InternationalChatService._();

  static const int _legacyPageSize = 100;

  /// Resolve ISO alpha-2 canônico (modo seguro: "" se inválido/ausente).
  static String resolveCountryCode(Map<String, dynamic> data) {
    return InternationalCountryCodes.resolve(data);
  }

  /// Retrocompat — alias de [resolveCountryCode].
  static String readHomeCountryCode(Map<String, dynamic> data) {
    return resolveCountryCode(data);
  }

  static bool isCountryKnown(Map<String, dynamic> data) {
    return resolveCountryCode(data).isNotEmpty;
  }

  static DmCountryRelation dmCountryRelation(
    Map<String, dynamic> senderData,
    Map<String, dynamic> recipientData,
  ) {
    final a = resolveCountryCode(senderData);
    final b = resolveCountryCode(recipientData);
    if (a.isEmpty || b.isEmpty) return DmCountryRelation.unknown;
    if (a == b) return DmCountryRelation.same;
    return DmCountryRelation.international;
  }

  static bool isPremiumActive(
    Map<String, dynamic>? data, {
    DateTime? now,
  }) {
    return PremiumAccessService.isPremiumActiveFromData(data, now: now);
  }

  static bool isInternational(String myCountryCode, String otherCountryCode) {
    if (myCountryCode.isEmpty || otherCountryCode.isEmpty) return false;
    return myCountryCode != otherCountryCode;
  }

  static bool isSameCountryCodes(String a, String b) {
    return a.isNotEmpty && b.isNotEmpty && a == b;
  }

  /// Premium/Master ou mesmo país com ambos códigos conhecidos.
  /// No lançamento BR+CA (iOS): só mesmo país aberto (BR↔BR ou CA↔CA).
  static bool canSendMessage({
    required Map<String, dynamic> senderData,
    required Map<String, dynamic> recipientData,
    DateTime? now,
  }) {
    if (RemdyLaunchAccess.isFreeBrazilLaunch) {
      return RemdyLaunchAccess.canChatBetweenCountries(
        senderCountryCode: resolveCountryCode(senderData),
        recipientCountryCode: resolveCountryCode(recipientData),
        premiumActive: false,
      );
    }
    if (isPremiumActive(senderData, now: now)) return true;
    return dmCountryRelation(senderData, recipientData) ==
        DmCountryRelation.same;
  }

  /// Free precisa de Premium (ou "Em breve" no lançamento BR) para intl.
  static bool needsPremiumToStartChat({
    required Map<String, dynamic> senderData,
    required Map<String, dynamic> recipientData,
    required bool conversationAlreadyExists,
    DateTime? now,
  }) {
    if (conversationAlreadyExists) return false;
    return !canSendMessage(
      senderData: senderData,
      recipientData: recipientData,
      now: now,
    );
  }

  static Future<Map<String, dynamic>?> fetchUserData(
    String uid, {
    FirebaseFirestore? firestore,
  }) async {
    if (uid.trim().isEmpty) return null;
    final db = firestore ?? FirebaseFirestore.instance;
    final snap = await db.collection('users').doc(uid).get();
    if (!snap.exists) return null;
    return snap.data();
  }

  static bool isActiveAccount(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['isBanned'] == true) return false;
    if (data['deleted'] == true) return false;
    if (data['isDeleted'] == true) return false;
    if (data['accountDeleted'] == true) return false;
    final uid = (data['uid'] ?? '').toString().trim();
    if (data.containsKey('uid') && uid.isEmpty) return false;
    return true;
  }

  static Future<Map<String, dynamic>?> fetchActiveUserData(
    String uid, {
    FirebaseFirestore? firestore,
  }) async {
    final data = await fetchUserData(uid, firestore: firestore);
    if (!isActiveAccount(data)) return null;
    return data;
  }

  static String pairKey(String a, String b) {
    final list = [a, b]..sort();
    return '${list[0]}_${list[1]}';
  }

  /// Decide o id de uma conversa já existente (legado ou determinístico).
  static String? resolveExistingConversationId({
    required String myUid,
    required String otherUid,
    required List<String> pairKeyMatchIds,
    Map<String, List<String>> participantConversations = const {},
  }) {
    for (final id in pairKeyMatchIds) {
      if (id.trim().isNotEmpty) return id;
    }
    for (final entry in participantConversations.entries) {
      final parts = entry.value;
      if (parts.contains(myUid) && parts.contains(otherUid)) {
        return entry.key;
      }
    }
    return null;
  }

  static Future<String?> findExistingConversationId(
    String myUid,
    String otherUid, {
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final key = pairKey(myUid, otherUid);
    final conversations = db.collection('conversations');

    try {
      final direct = await conversations.doc(key).get();
      if (direct.exists) return direct.id;
    } catch (_) {
      throw ConversationLookupException(
          'user_search_conversation_lookup_error');
    }

    try {
      final byPairKey =
          await conversations.where('pairKey', isEqualTo: key).limit(5).get();
      if (byPairKey.docs.isNotEmpty) return byPairKey.docs.first.id;
    } catch (_) {}

    try {
      final snap = await conversations
          .where('participants', arrayContains: myUid)
          .limit(_legacyPageSize)
          .get();
      for (final doc in snap.docs) {
        final parts = (doc.data()['participants'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        if (parts.contains(otherUid)) return doc.id;
      }
    } catch (_) {}

    return null;
  }

  static Future<bool> conversationExists(
    String myUid,
    String otherUid, {
    FirebaseFirestore? firestore,
  }) async {
    final id = await findExistingConversationId(
      myUid,
      otherUid,
      firestore: firestore,
    );
    return id != null;
  }

  static Future<String> getOrCreateConversation(
    String myUid,
    String otherUid, {
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final key = pairKey(myUid, otherUid);

    final existing = await findExistingConversationId(
      myUid,
      otherUid,
      firestore: db,
    );
    if (existing != null) return existing;

    final ref = db.collection('conversations').doc(key);
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return;
      tx.set(ref, {
        'participants': [myUid, otherUid],
        'pairKey': key,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unread': {
          myUid: 0,
          otherUid: 0,
        },
      });
    });
    return ref.id;
  }
}
