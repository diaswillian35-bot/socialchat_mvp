/// Pure helper: Terms/EULA must be accepted before any auth attempt.
///
/// Used by LoginPage for email, Google, Apple, Facebook (and tests).
class AuthTermsGate {
  AuthTermsGate._();

  /// Error / toast key when the checkbox is unchecked.
  static const String requiredKey = 'age_terms_required';

  static bool canAuthenticate({required bool termsAccepted}) => termsAccepted;

  /// Returns null when OK; otherwise [requiredKey].
  static String? rejectReason({required bool termsAccepted}) =>
      termsAccepted ? null : requiredKey;
}
