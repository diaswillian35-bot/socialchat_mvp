import 'dart:io';
import 'package:purchases_flutter/purchases_flutter.dart';



class PurchaseService {
  PurchaseService._();
  static final instance = PurchaseService._();


  bool _configured = false;


  // Você vai pegar essas chaves no RevenueCat
  // iOS: public_sdk_key
  // Android: public_sdk_key
  static const String _revenueCatIosKey = 'test_zbKrcZOlsGbWrwEdtdYsKPdSsLx';
  static const String _revenueCatAndroidKey = 'test_zbKrcZOlsGbWrwEdtdYsKPdSsLx';


  // ID do seu entitlement no RevenueCat (ex: "premium")
  static const String entitlementId = 'premium';


  // ID do Offering (geralmente "default")
  static const String offeringId = 'default';


  Future<void> configure({required String appUserId}) async {
    if (_configured) {
      // Mesmo assim, vincula o usuário (pra restaurar e sincronizar)
      await Purchases.logIn(appUserId);
      return;
    }


    await Purchases.setLogLevel(LogLevel.info);


    final key = Platform.isIOS ? _revenueCatIosKey : _revenueCatAndroidKey;
    await Purchases.configure(PurchasesConfiguration(key)..appUserID = appUserId);


    _configured = true;
  }


  Future<bool> isPremium() async {
    final info = await Purchases.getCustomerInfo();
    final ent = info.entitlements.active[entitlementId];
    return ent != null;
  }


  /// Compra a assinatura (usa o primeiro package do offering)
  Future<void> buyPremium() async {
    final offerings = await Purchases.getOfferings();
    final off = offerings.getOffering(offeringId) ?? offerings.current;


    if (off == null) {
      throw Exception('Offering não encontrado no RevenueCat.');
    }


    final pkg = off.availablePackages.isNotEmpty ? off.availablePackages.first : null;
    if (pkg == null) {
      throw Exception('Nenhum pacote disponível no Offering.');
    }


    await Purchases.purchasePackage(pkg);
  }


  Future<void> restore() async {
    await Purchases.restorePurchases();
  }
   // ✅ Pega o pacote do offering (default) e devolve o preço formatado (ex: "$9.99")
  Future<String?> getDefaultPriceString() async {
    final offerings = await Purchases.getOfferings();
    final off = offerings.getOffering(offeringId) ?? offerings.current;
    if (off == null) return null;


    final pkg = off.availablePackages.isNotEmpty ? off.availablePackages.first : null;
    if (pkg == null) return null;


    return pkg.storeProduct.priceString;
  }


  // ✅ Verifica se já existe pacote configurado (para não estourar erro)
  Future<bool> hasPackageAvailable() async {
    final offerings = await Purchases.getOfferings();
    final off = offerings.getOffering(offeringId) ?? offerings.current;
    if (off == null) return false;


    return off.availablePackages.isNotEmpty;
  }

}
