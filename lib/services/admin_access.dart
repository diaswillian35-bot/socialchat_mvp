import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Administrador total do Remdy — somente a conta do Willian.
///
/// Critério: email exato + email verificado no Firebase Auth, ou custom
/// claim `admin: true`. O admin vê pessoas, eventos, locais e grupos de
/// todos os países e entra em qualquer grupo sem aprovação.
///
/// NUNCA libera conversas privadas (DMs): nada aqui é consultado no fluxo
/// de conversations/messages; as Rules exigem participação sem exceção.
class AdminAccess extends ChangeNotifier {
  AdminAccess._();

  static final AdminAccess instance = AdminAccess._();

  static const Set<String> adminEmails = {'diaswillian35@gmail.com'};

  /// Países que o admin pode escolher para ver conteúdo.
  static const List<String> viewableCountries = ['br', 'ca', 'pt'];

  static const String _prefsKey = 'admin_view_country';

  bool _isAdmin = false;
  String _viewCountry = '';
  StreamSubscription<User?>? _sub;

  /// Cache síncrono (false em testes/VM sem Firebase).
  static bool get isAdmin => instance._isAdmin;

  /// País escolhido no Modo administrador ('' = país do próprio perfil).
  String get viewCountry => _isAdmin ? _viewCountry : '';

  /// Regra pura (testável): email exato + verificado.
  static bool isAdminEmail({required String? email, required bool verified}) {
    final e = (email ?? '').trim().toLowerCase();
    return verified && adminEmails.contains(e);
  }

  /// País efetivo para consultas de descoberta (grupos/eventos/pessoas).
  /// Para não-admin devolve sempre [ownCountry].
  static String effectiveCountry(String ownCountry) {
    final override = instance.viewCountry;
    if (override.isEmpty) return ownCountry;
    return override;
  }

  void start() {
    _sub ??= FirebaseAuth.instance.userChanges().listen(_refresh);
    unawaited(_refresh(FirebaseAuth.instance.currentUser));
  }

  Future<void> _refresh(User? user) async {
    var admin = false;
    if (user != null) {
      admin = isAdminEmail(email: user.email, verified: user.emailVerified);
      if (!admin) {
        try {
          final token = await user.getIdTokenResult();
          admin = token.claims?['admin'] == true;
        } catch (_) {}
      }
    }
    if (admin && _viewCountry.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _viewCountry = prefs.getString(_prefsKey) ?? '';
      } catch (_) {}
    }
    if (!admin) _viewCountry = '';
    if (admin != _isAdmin) {
      _isAdmin = admin;
      notifyListeners();
    }
  }

  Future<void> setViewCountry(String code) async {
    if (!_isAdmin) return;
    final c = code.trim().toLowerCase();
    _viewCountry = c;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (c.isEmpty) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, c);
      }
    } catch (_) {}
    notifyListeners();
  }

  @visibleForTesting
  void debugSet({required bool admin, String viewCountry = ''}) {
    _isAdmin = admin;
    _viewCountry = viewCountry;
    notifyListeners();
  }
}
