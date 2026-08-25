import 'dart:io';

/// Valores canônicos do OAuth iOS alinhados a Runner/GoogleService-Info.plist.
class IosGoogleConfig {
  IosGoogleConfig._();

  static const String clientId =
      '384686982032-a3qnnfdcducpqi7nivk17oh1kub214rl.apps.googleusercontent.com';
  static const String reversedClientId =
      'com.googleusercontent.apps.384686982032-a3qnnfdcducpqi7nivk17oh1kub214rl';
  static const String firebaseAppId =
      '1:384686982032:ios:4862e501b472570ebf2915';
  static const String bundleId = 'com.remdy.app';
  static const String plistFileName = 'GoogleService-Info.plist';

  static String? readPlistValue(String key, {String? path}) {
    final file = File(path ?? 'ios/Runner/$plistFileName');
    if (!file.existsSync()) return null;
    final content = file.readAsStringSync();
    final pattern = RegExp(
      '<key>$key</key>\\s*<string>([^<]+)</string>',
      multiLine: true,
    );
    return pattern.firstMatch(content)?.group(1)?.trim();
  }

  static String? readInfoPlistUrlScheme({String? path}) {
    final file = File(path ?? 'ios/Runner/Info.plist');
    if (!file.existsSync()) return null;
    final content = file.readAsStringSync();
    final match = RegExp(
      r'<key>CFBundleURLSchemes</key>\s*<array>\s*<string>([^<]+)</string>',
      multiLine: true,
    ).firstMatch(content);
    return match?.group(1)?.trim();
  }

  static String? readInfoPlistGidClientId({String? path}) {
    final file = File(path ?? 'ios/Runner/Info.plist');
    if (!file.existsSync()) return null;
    final content = file.readAsStringSync();
    return RegExp(
      r'<key>GIDClientID</key>\s*<string>([^<]+)</string>',
      multiLine: true,
    ).firstMatch(content)?.group(1)?.trim();
  }
}
