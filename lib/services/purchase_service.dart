import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Compras via RevenueCat. Premium no Firestore vem do webhook/sync server-side.
class PurchaseService {
  PurchaseService._();
  static final instance = PurchaseService._();

  bool _configured = false;

  /// Chaves públicas do SDK (podem ir no app). Preferir --dart-define em produção.
  /// NÃO usar chave secreta da API aqui.
  static const String _revenueCatIosKey = String.fromEnvironment(
    'REVENUECAT_IOS_KEY',
    defaultValue: 'test_zbKrcZOlsGbWrwEdtdYsKPdSsLx',
  );
  static const String _revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
    defaultValue: 'test_zbKrcZOlsGbWrwEdtdYsKPdSsLx',
  );

  static const String entitlementId = 'premium';
  static const String offeringId = 'default';

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<void> configure({required String appUserId}) async {
    final uid = appUserId.trim();
    if (uid.isEmpty) {
      throw ArgumentError('appUserId (Firebase UID) required');
    }

    if (_configured) {
      await Purchases.logIn(uid);
      return;
    }

    await Purchases.setLogLevel(
      kDebugMode ? LogLevel.info : LogLevel.warn,
    );

    final key = Platform.isIOS ? _revenueCatIosKey : _revenueCatAndroidKey;
    await Purchases.configure(
      PurchasesConfiguration(key)..appUserID = uid,
    );

    _configured = true;
  }

  /// Desvincula o usuário do SDK no logout (não apaga compras nas lojas).
  Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (_) {}
  }

  Future<bool> hasActiveEntitlementLocally() async {
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active[entitlementId] != null;
  }

  /// Compra a assinatura (primeiro package do offering).
  Future<CustomerInfo> buyPremium() async {
    final offerings = await Purchases.getOfferings();
    final off = offerings.getOffering(offeringId) ?? offerings.current;

    if (off == null) {
      throw Exception('Offering não encontrado no RevenueCat.');
    }

    final pkg =
        off.availablePackages.isNotEmpty ? off.availablePackages.first : null;
    if (pkg == null) {
      throw Exception('Nenhum pacote disponível no Offering.');
    }

    return Purchases.purchasePackage(pkg);
  }

  Future<CustomerInfo> restore() async {
    return Purchases.restorePurchases();
  }

  /// Sincroniza entitlement no Firestore via Function (API secreta server-side).
  Future<Map<String, dynamic>> syncEntitlementWithServer() async {
    final callable = _functions.httpsCallable('syncRevenueCatEntitlement');
    final result = await callable.call(<String, dynamic>{});
    final data = result.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{'success': false};
  }

  Future<String?> getDefaultPriceString() async {
    final offerings = await Purchases.getOfferings();
    final off = offerings.getOffering(offeringId) ?? offerings.current;
    if (off == null) return null;

    final pkg =
        off.availablePackages.isNotEmpty ? off.availablePackages.first : null;
    if (pkg == null) return null;

    return pkg.storeProduct.priceString;
  }

  Future<bool> hasPackageAvailable() async {
    final offerings = await Purchases.getOfferings();
    final off = offerings.getOffering(offeringId) ?? offerings.current;
    if (off == null) return false;

    return off.availablePackages.isNotEmpty;
  }
}
