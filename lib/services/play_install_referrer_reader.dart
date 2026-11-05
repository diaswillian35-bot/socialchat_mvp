import 'package:flutter/services.dart';
import 'package:play_install_referrer/play_install_referrer.dart';

import 'pending_group_code.dart';

/// Leitura única do Install Referrer. No iOS o plugin lança — só chamar
/// em Android.
class PlayInstallReferrerReader {
  PlayInstallReferrerReader._();

  static Future<AndroidReferrerRead> read() async {
    try {
      final details = await PlayInstallReferrer.installReferrer;
      final server = details.installBeginTimestampServerSeconds;
      final client = details.installBeginTimestampSeconds;
      final stamp = server > 0 ? server : client;
      return AndroidReferrerRead(
        referrer: details.installReferrer,
        installBeginTimestampSeconds: stamp > 0 ? stamp : null,
        definitive: true,
      );
    } on PlatformException catch (e) {
      final retry = e.code == 'TIMEOUT' ||
          e.code == 'SERVICE_DISCONNECTED' ||
          e.code == 'SERVICE_UNAVAILABLE' ||
          e.code == 'DEAD_OBJECT_EXCEPTION';
      return AndroidReferrerRead(definitive: !retry);
    } catch (_) {
      return const AndroidReferrerRead(definitive: false);
    }
  }
}
