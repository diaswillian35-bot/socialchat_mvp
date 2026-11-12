import 'package:cloud_functions/cloud_functions.dart';

import '../l10n/app_texts.dart';

/// Chave de l10n para erros da autorização do QR do portal.
///
/// Não devolve a mensagem crua da Function (pode vir em inglês).
String portalQrErrorKey(String? code, {String? message}) {
  switch ((code ?? '').trim().toLowerCase()) {
    case 'deadline-exceeded':
      return 'portal_qr_expired';
    case 'not-found':
      return 'portal_qr_session_not_found';
    case 'failed-precondition':
      return 'portal_qr_unavailable';
    case 'unauthenticated':
      return 'portal_qr_unauthenticated';
    default:
      return _keyForKnownMessage(message) ?? 'portal_qr_generic';
  }
}

String portalQrErrorText(Object error) {
  if (error is FirebaseFunctionsException) {
    return AppTexts.t(
      portalQrErrorKey(error.code, message: error.message),
    );
  }
  return AppTexts.t('portal_qr_generic');
}

String? _keyForKnownMessage(String? message) {
  final m = (message ?? '').trim().toLowerCase();
  if (m.isEmpty) return null;
  if (m.contains('expir')) return 'portal_qr_expired';
  if (m.contains('não encontrada') || m.contains('not found')) {
    return 'portal_qr_session_not_found';
  }
  if (m.contains('não está mais disponível') ||
      m.contains('no longer available') ||
      m.contains('not available')) {
    return 'portal_qr_unavailable';
  }
  if (m.contains('faça login') ||
      m.contains('sign in') ||
      m.contains('unauth')) {
    return 'portal_qr_unauthenticated';
  }
  return null;
}
