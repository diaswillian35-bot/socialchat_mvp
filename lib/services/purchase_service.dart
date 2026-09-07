import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'remdy_launch_access.dart';

/// Motivo pelo qual compras in-app não estão disponíveis no build atual.
enum PurchaseAvailability {
  /// SDK configurado com chave de produção válida.
  available,

  /// Chave pública ausente (ex.: build Profile/Release sem --dart-define).
  missingProductionKey,

  /// Build de distribuição com chave `test_...` (proibido).
  invalidTestKeyInDistribution,

  /// SDK ainda não configurado nesta sessão.
  notConfigured,
}

/// Compras indisponíveis sem encerrar o app — UI deve mostrar mensagem amigável.
class PurchaseUnavailableException implements Exception {
  PurchaseUnavailableException(this.availability);

  final PurchaseAvailability availability;

  @override
  String toString() => 'PurchaseUnavailableException($availability)';
}

/// Compras via RevenueCat. Premium no Firestore vem do webhook/sync server-side.
class PurchaseService {
  PurchaseService._();
  static final instance = PurchaseService._();

  bool _configured = false;
  bool _purchasesEnabled = false;
  PurchaseAvailability _availability = PurchaseAvailability.notConfigured;

  /// Chaves públicas do SDK (podem ir no app). Obrigatórias em Profile/Release via
  /// `--dart-define` ou `--dart-define-from-file=dart_defines.local.json`.
  /// NÃO usar chave secreta da API aqui.
  static const String _revenueCatIosKey = String.fromEnvironment(
    'REVENUECAT_IOS_KEY',
    defaultValue: '',
  );
  static const String _revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
    defaultValue: '',
  );

  static const String entitlementId = 'premium';
  static const String offeringId = 'default';

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Profile e Release não devem usar chaves de teste nem operar sem chave.
  static bool get isDistributionBuild => !kDebugMode;

  static String get platformPublicKey =>
      Platform.isIOS ? _revenueCatIosKey : _revenueCatAndroidKey;

  bool get purchasesEnabled => _purchasesEnabled;
  PurchaseAvailability get availability => _availability;

  static bool _isTestStoreKey(String key) =>
      key.startsWith('test_') || key.startsWith('test-');

  /// Avalia a chave do SDK sem inicializar o RevenueCat.
  static PurchaseAvailability evaluateKeyAvailability() {
    if (!RemdyLaunchAccess.purchasesEnabled) {
      return PurchaseAvailability.notConfigured;
    }
    final key = platformPublicKey.trim();
    if (key.isEmpty) {
      return PurchaseAvailability.missingProductionKey;
    }
    if (isDistributionBuild && _isTestStoreKey(key)) {
      return PurchaseAvailability.invalidTestKeyInDistribution;
    }
    return PurchaseAvailability.available;
  }

  /// Mensagem segura para UI (sem vazar chaves ou detalhes técnicos).
  ///
  /// [productsNotConnectedMessage] só deve ser usado quando a chave está OK
  /// mas o offering/pacote StoreKit ainda não carregou — não quando
  /// [PurchaseAvailability.available] sozinho (isso só indica chave válida).
  static String friendlyAvailabilityMessage(
    PurchaseAvailability availability, {
    required String setupMessage,
    required String productsNotConnectedMessage,
    bool hasStorePackage = false,
  }) {
    switch (availability) {
      case PurchaseAvailability.available:
        return hasStorePackage ? '' : productsNotConnectedMessage;
      case PurchaseAvailability.missingProductionKey:
      case PurchaseAvailability.invalidTestKeyInDistribution:
      case PurchaseAvailability.notConfigured:
        return setupMessage;
    }
  }

  /// Pacote mensal do offering `default` (`$rc_monthly` / [PackageType.monthly]).
  static Package? resolveMonthlyPackage(Offering? offering) {
    if (offering == null) return null;

    Package? pkg = offering.monthly;
    if (pkg != null) return pkg;

    for (final candidate in offering.availablePackages) {
      if (candidate.identifier == '\$rc_monthly' ||
          candidate.packageType == PackageType.monthly) {
        return candidate;
      }
    }
    return null;
  }

  Future<Offering?> _defaultOffering() async {
    final offerings = await Purchases.getOfferings();
    return offerings.getOffering(offeringId) ?? offerings.current;
  }

  static String friendlyErrorMessage(
    Object error, {
    required String setupMessage,
    required String purchaseErrorLabel,
  }) {
    if (error is PurchaseUnavailableException) {
      return setupMessage;
    }
    if (isUserCancellation(error)) {
      return '';
    }
    final raw = error.toString().toLowerCase();
    // Map known RevenueCat / StoreKit configuration failures to the setup copy
    // (never echo raw SDK text like "Wrong API Key" or product-fetch errors).
    if (raw.contains('wrong api key') ||
        raw.contains('invalid api key') ||
        (raw.contains('api key') && raw.contains('invalid')) ||
        raw.contains('offering não encontrado') ||
        raw.contains('nenhum pacote disponível') ||
        raw.contains('none of the products') ||
        raw.contains('no products registered') ||
        raw.contains('could not be fetched') ||
        raw.contains('productnotavailable') ||
        raw.contains('configurationerror') ||
        raw.contains('storeproblem') ||
        raw.contains('offeringsempty') ||
        raw.contains('there are no products')) {
      return setupMessage;
    }
    return purchaseErrorLabel;
  }

  Future<PurchaseAvailability> configure({required String appUserId}) async {
    final uid = appUserId.trim();
    if (uid.isEmpty) {
      throw ArgumentError('appUserId (Firebase UID) required');
    }

    _availability = evaluateKeyAvailability();
    if (_availability != PurchaseAvailability.available) {
      _purchasesEnabled = false;
      _configured = false;
      return _availability;
    }

    if (_configured) {
      await Purchases.logIn(uid);
      _purchasesEnabled = true;
      return PurchaseAvailability.available;
    }

    await Purchases.setLogLevel(
      kDebugMode ? LogLevel.info : LogLevel.warn,
    );

    final key = platformPublicKey.trim();
    await Purchases.configure(
      PurchasesConfiguration(key)..appUserID = uid,
    );

    _configured = true;
    _purchasesEnabled = true;
    _availability = PurchaseAvailability.available;
    return PurchaseAvailability.available;
  }

  void _requirePurchasesEnabled() {
    if (!_purchasesEnabled) {
      throw PurchaseUnavailableException(_availability);
    }
  }

  /// Compra ou restore cancelado pelo usuário — não é falha técnica.
  static bool isUserCancellation(Object error) {
    if (error is! PlatformException) return false;
    return PurchasesErrorHelper.getErrorCode(error) ==
        PurchasesErrorCode.purchaseCancelledError;
  }

  /// Desvincula o usuário do SDK no logout (não apaga compras nas lojas).
  Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (_) {}
    _purchasesEnabled = false;
    _configured = false;
    _availability = PurchaseAvailability.notConfigured;
  }

  Future<bool> hasActiveEntitlementLocally() async {
    _requirePurchasesEnabled();
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active[entitlementId] != null;
  }

  /// Compra a assinatura mensal do offering `default` (pacote `$rc_monthly`).
  Future<CustomerInfo> buyPremium() async {
    _requirePurchasesEnabled();
    final off = await _defaultOffering();

    if (off == null) {
      throw Exception('Offering não encontrado no RevenueCat.');
    }

    final pkg = resolveMonthlyPackage(off);
    if (pkg == null) {
      throw Exception('Nenhum pacote disponível no Offering.');
    }

    final result = await Purchases.purchase(
      PurchaseParams.package(pkg),
    );
    return result.customerInfo;
  }

  Future<CustomerInfo> restore() async {
    _requirePurchasesEnabled();
    return Purchases.restorePurchases();
  }

  /// Sincroniza entitlement no Firestore via Function (API secreta server-side).
  Future<Map<String, dynamic>> syncEntitlementWithServer() async {
    if (!_purchasesEnabled) {
      return <String, dynamic>{'success': false, 'skipped': true};
    }
    final callable = _functions.httpsCallable('syncRevenueCatEntitlement');
    final result = await callable.call(<String, dynamic>{});
    final data = result.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{'success': false};
  }

  Future<String?> getDefaultPriceString() async {
    _requirePurchasesEnabled();
    final pkg = resolveMonthlyPackage(await _defaultOffering());
    return pkg?.storeProduct.priceString;
  }

  /// True somente com pacote mensal StoreKit real no offering `default`.
  Future<bool> hasPackageAvailable() async {
    if (!_purchasesEnabled) return false;
    return resolveMonthlyPackage(await _defaultOffering()) != null;
  }

  /// Diagnóstico seguro (sem chaves, product IDs sensíveis ou payloads).
  Future<Map<String, Object?>> debugOfferSnapshot() async {
    if (!_purchasesEnabled) {
      return <String, Object?>{
        'purchasesEnabled': false,
        'availability': _availability.name,
      };
    }
    try {
      final offerings = await Purchases.getOfferings();
      final off = offerings.getOffering(offeringId) ?? offerings.current;
      final pkg = resolveMonthlyPackage(off);
      final productId = pkg?.storeProduct.identifier ?? '';
      final looksMonthly = productId.endsWith('.premium.monthly');
      return <String, Object?>{
        'purchasesEnabled': true,
        'hasCurrentOffering': offerings.current != null,
        'hasDefaultOffering': offerings.getOffering(offeringId) != null,
        'packageCount': off?.availablePackages.length ?? 0,
        'hasMonthlyPackage': pkg != null,
        'priceLoaded': (pkg?.storeProduct.priceString ?? '').isNotEmpty,
        'productLooksMonthly': looksMonthly,
      };
    } catch (e) {
      return <String, Object?>{
        'purchasesEnabled': true,
        'errorKind': e.runtimeType.toString(),
      };
    }
  }
}
