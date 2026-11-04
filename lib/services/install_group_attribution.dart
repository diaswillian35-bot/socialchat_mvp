import 'package:shared_preferences/shared_preferences.dart';

import 'pending_group_code.dart';

/// Primeiro uso depois da instalação: Play Install Referrer (Android) ou
/// uma leitura da área de transferência (iOS).
class InstallGroupAttribution {
  InstallGroupAttribution._();

  static Future<void> captureIfNeeded({
    required bool isAndroid,
    required bool isIos,
    required Future<AndroidReferrerRead> Function() readAndroidReferrer,
    required Future<String?> Function() readClipboard,
    required Future<void> Function() clearClipboard,
    DateTime Function()? clock,
    SharedPreferences? preferences,
  }) async {
    if (!isAndroid && !isIos) return;
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final now = (clock ?? DateTime.now)();

    if (isAndroid &&
        prefs.getBool(PendingGroupCodeLogic.androidCheckedKey) != true) {
      await _captureAndroid(prefs, readAndroidReferrer, now);
    }
    if (isIos && prefs.getBool(PendingGroupCodeLogic.iosCheckedKey) != true) {
      await _captureIos(prefs, readClipboard, clearClipboard, now);
    }
  }

  static Future<void> _captureAndroid(
    SharedPreferences prefs,
    Future<AndroidReferrerRead> Function() readAndroidReferrer,
    DateTime now,
  ) async {
    AndroidReferrerRead read;
    try {
      read = await readAndroidReferrer();
    } catch (_) {
      read = const AndroidReferrerRead(definitive: false);
    }
    if (!read.definitive) return;
    await prefs.setBool(PendingGroupCodeLogic.androidCheckedKey, true);

    if (!PendingGroupCodeLogic.isRecentPlayInstall(
      installBeginTimestampSeconds: read.installBeginTimestampSeconds,
      nowSeconds: now.millisecondsSinceEpoch ~/ 1000,
    )) {
      return;
    }

    final extracted =
        PendingGroupCodeLogic.codeFromInstallReferrer(read.referrer);
    final toWrite = PendingGroupCodeLogic.installCodeToWrite(
      extracted: extracted,
      alreadyPending: prefs.getString(PendingGroupCodeLogic.pendingKey),
    );
    if (toWrite == null) return;
    await prefs.setString(PendingGroupCodeLogic.pendingKey, toWrite);
  }

  static Future<void> _captureIos(
    SharedPreferences prefs,
    Future<String?> Function() readClipboard,
    Future<void> Function() clearClipboard,
    DateTime now,
  ) async {
    final firstLaunch = prefs.getInt(PendingGroupCodeLogic.firstLaunchKey);
    final firstSession = PendingGroupCodeLogic.isFirstAppSession(
      firstLaunchMs: firstLaunch,
      nowMs: now.millisecondsSinceEpoch,
    );
    // Quem já abriu o app antes (atualização) não vê o aviso de colar.
    if (!firstSession) {
      await prefs.setBool(PendingGroupCodeLogic.iosCheckedKey, true);
      return;
    }

    String? text;
    try {
      text = await readClipboard();
    } catch (_) {
      text = null;
    }
    await prefs.setBool(PendingGroupCodeLogic.iosCheckedKey, true);

    final extracted = PendingGroupCodeLogic.codeFromIosClipboard(text);
    if (extracted == null) return;

    final toWrite = PendingGroupCodeLogic.installCodeToWrite(
      extracted: extracted,
      alreadyPending: prefs.getString(PendingGroupCodeLogic.pendingKey),
    );
    if (toWrite != null) {
      await prefs.setString(PendingGroupCodeLogic.pendingKey, toWrite);
    }
    try {
      await clearClipboard();
    } catch (_) {}
  }
}
