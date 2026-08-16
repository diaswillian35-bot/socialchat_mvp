import 'package:cloud_functions/cloud_functions.dart';

import 'age_verification.dart';

class AgeVerificationService {
  static Future<void> confirm({required DateTime dateOfBirth}) async {
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('confirmAdultAge')
        .call(<String, dynamic>{
      'dateOfBirth': AgeVerification.wireDate(dateOfBirth),
      'policyVersion': AgeVerification.policyVersion,
    });
  }
}
