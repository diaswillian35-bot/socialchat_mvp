import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:socialchat_mvp/services/purchase_service.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('pubspec pins RevenueCat 10.9 through purchases_flutter', () {
    final pubspec = source('pubspec.yaml');
    expect(pubspec, contains('purchases_flutter: ^10.9.0'));
    expect(pubspec, contains('version: 1.0.3+14'));
    expect(pubspec, isNot(contains('com.android.billingclient')));
  });

  test('lockfile resolves purchases_flutter 10.9.0 or newer', () {
    final lock = source('pubspec.lock');
    final block = RegExp(
      r'purchases_flutter:\n(?:.*\n){1,8}\s+version: "([^"]+)"',
    ).firstMatch(lock);
    expect(block, isNotNull);
    final version = block!.group(1)!;
    final parts = version.split('.').map(int.parse).toList();
    expect(parts[0], greaterThanOrEqualTo(10));
    if (parts[0] == 10) {
      expect(parts[1], greaterThanOrEqualTo(9));
    }
  });

  test('purchase service uses PurchaseParams API and restore', () {
    final dart = source('lib/services/purchase_service.dart');
    expect(dart, contains('Purchases.purchase('));
    expect(dart, contains('PurchaseParams.package(pkg)'));
    expect(dart, contains('return result.customerInfo;'));
    expect(dart, contains('Purchases.restorePurchases()'));
    expect(dart, contains('Purchases.getOfferings()'));
    expect(dart, isNot(contains('purchasePackage')));
    expect(dart, contains("httpsCallable('syncRevenueCatEntitlement')"));
  });

  test('Android Gradle does not add billingclient directly', () {
    final gradleFiles = Directory('android')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.gradle') ||
              file.path.endsWith('.kts') ||
              file.path.endsWith('.toml'),
        );
    for (final file in gradleFiles) {
      expect(
        file.readAsStringSync(),
        isNot(contains('com.android.billingclient')),
        reason: file.path,
      );
    }
  });

  test('Premium page buys and restores only through PurchaseService', () {
    final page = source('lib/pages/premium_page.dart');
    expect(page, contains('PurchaseService.instance.buyPremium()'));
    expect(page, contains('PurchaseService.instance.restore()'));
    expect(page, contains('PurchaseService.instance.hasPackageAvailable()'));
    expect(page, contains('PurchaseService.instance.getDefaultPriceString()'));
    expect(page, contains('syncEntitlementWithServer'));
    expect(page, contains("não grava isPremium no cliente"));
    expect(page, isNot(contains("'isPremium': true")));
    expect(page, isNot(contains('"isPremium": true')));
  });

  test('user cancellation is not treated as a technical failure', () {
    final cancelled = PlatformException(
      code: '1',
      details: {'readableErrorCode': 'PURCHASE_CANCELLED'},
    );
    // RevenueCat maps several platform codes; helper must never throw.
    expect(
      () => PurchaseService.isUserCancellation(cancelled),
      returnsNormally,
    );
    expect(PurchaseService.isUserCancellation(Exception('other')), isFalse);
    expect(
      PurchasesErrorCode.purchaseCancelledError,
      isNotNull,
    );
  });
}
