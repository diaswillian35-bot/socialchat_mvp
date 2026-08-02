import 'package:cloud_functions/cloud_functions.dart';

/// Convites / Premium trial — somente via Cloud Functions.
class InvitePremiumService {
  InvitePremiumService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Convidado aplica código de convite (atribuição + incremento + recompensa).
  static Future<Map<String, dynamic>> applyInviteCode(String inviteCode) async {
    final code = inviteCode.trim();
    if (code.isEmpty) {
      return <String, dynamic>{'success': false, 'applied': false};
    }

    final callable = _functions.httpsCallable('applyInviteCode');
    final result = await callable.call(<String, dynamic>{
      'inviteCode': code,
    });
    final data = result.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{'success': true};
  }

  /// Convidante reivindica marcos pendentes com base no invitesCount do servidor.
  static Future<Map<String, dynamic>> claimInvitePremiumReward() async {
    final callable = _functions.httpsCallable('claimInvitePremiumReward');
    final result = await callable.call(<String, dynamic>{});
    final data = result.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{'success': true, 'granted': false};
  }
}
