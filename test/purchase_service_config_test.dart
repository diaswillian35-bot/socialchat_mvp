import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/purchase_service.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  group('PurchaseService key guards', () {
    test('no test_ default fallback in purchase_service.dart', () {
      final dart = source('lib/services/purchase_service.dart');
      expect(dart, isNot(contains("defaultValue: 'test_")));
      expect(dart, isNot(contains('test_zbKrc')));
      expect(dart, contains("defaultValue: ''"));
    });

    test('distribution guard rejects test keys and empty keys in source', () {
      final dart = source('lib/services/purchase_service.dart');
      expect(dart, contains('evaluateKeyAvailability'));
      expect(dart, contains('invalidTestKeyInDistribution'));
      expect(dart, contains('missingProductionKey'));
      expect(dart, contains('_isTestStoreKey'));
    });

    test('friendly messages never echo raw RevenueCat API key errors', () {
      final dart = source('lib/services/purchase_service.dart');
      expect(dart, contains('friendlyErrorMessage'));
      expect(dart, contains('wrong api key'));
      expect(dart, contains('PurchaseUnavailableException'));
    });

    test('friendlyErrorMessage maps Wrong API Key to setup message', () {
      const setup = 'Premium em configuração.';
      final msg = PurchaseService.friendlyErrorMessage(
        Exception('Wrong API Key'),
        setupMessage: setup,
        purchaseErrorLabel: 'Erro na compra',
      );
      expect(msg, setup);
    });

    test('friendlyErrorMessage maps StoreKit product-fetch failures to setup message', () {
      const setup = 'Premium em configuração.';
      final msg = PurchaseService.friendlyErrorMessage(
        Exception(
          'None of the products registered in the RevenueCat dashboard '
          'could be fetched from App Store Connect',
        ),
        setupMessage: setup,
        purchaseErrorLabel: 'Erro na compra',
      );
      expect(msg, setup);
    });

    test('friendlyAvailabilityMessage keeps products message only without store package', () {
      const setup = 'Premium em configuração.';
      const products = 'Premium em configuração (produtos ainda não conectados).';
      expect(
        PurchaseService.friendlyAvailabilityMessage(
          PurchaseAvailability.available,
          setupMessage: setup,
          productsNotConnectedMessage: products,
          hasStorePackage: true,
        ),
        '',
      );
      expect(
        PurchaseService.friendlyAvailabilityMessage(
          PurchaseAvailability.available,
          setupMessage: setup,
          productsNotConnectedMessage: products,
          hasStorePackage: false,
        ),
        products,
      );
      expect(
        PurchaseService.friendlyAvailabilityMessage(
          PurchaseAvailability.missingProductionKey,
          setupMessage: setup,
          productsNotConnectedMessage: products,
        ),
        setup,
      );
    });

    test('purchase service resolves monthly package helper in source', () {
      final dart = source('lib/services/purchase_service.dart');
      expect(dart, contains('resolveMonthlyPackage'));
      expect(dart, contains(r'$rc_monthly'));
      expect(dart, contains('debugOfferSnapshot'));
    });

    test('premium page uses store price only when RC package is loaded', () {
      final page = source('lib/pages/premium_page.dart');
      expect(page, contains('_hasPackage'));
      expect(page, contains('_storeOfferResolved'));
      expect(page, contains('_priceString'));
      expect(page, isNot(contains('_adminPriceText')));
      expect(page, isNot(contains('_loadAdminPremiumPrice')));
      expect(page, contains('_loadAdminPremiumGate'));
      expect(page, contains('!_hasPackage'));
      expect(page, contains('premium_products_not_connected'));
    });
  });
}
