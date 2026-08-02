import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    setupNativeChannelsIfNeeded()
    return ok
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return super.application(app, open: url, options: options)
  }

  private func setupNativeChannelsIfNeeded() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      DispatchQueue.main.async { [weak self] in
        self?.setupNativeChannelsIfNeeded()
      }
      return
    }

    let badgeChannel = FlutterMethodChannel(
      name: "remdy/app_badge",
      binaryMessenger: controller.binaryMessenger
    )
    badgeChannel.setMethodCallHandler { call, result in
      if call.method == "setBadge" {
        let count = (call.arguments as? Int) ?? 0
        DispatchQueue.main.async {
          UIApplication.shared.applicationIconBadgeNumber = max(0, count)
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let shareSession = FlutterMethodChannel(
      name: "remdy/share_session",
      binaryMessenger: controller.binaryMessenger
    )
    shareSession.setMethodCallHandler { call, result in
      switch call.method {
      case "saveSession":
        guard let args = call.arguments as? [String: Any],
              let token = args["token"] as? String,
              !token.isEmpty,
              let sid = args["sid"] as? String
        else {
          result(FlutterError(code: "bad_args", message: nil, details: nil))
          return
        }
        let exp = (args["expiresAtMs"] as? NSNumber)?.int64Value ?? 0
        let ok = ShareSessionKeychain.save(
          ShareSessionKeychain.Session(token: token, sid: sid, expiresAtMs: exp)
        )
        result(ok)
      case "clearSession":
        result(ShareSessionKeychain.clear())
      case "hasSession":
        result(ShareSessionKeychain.load() != nil)
      case "readSessionMeta":
        if let s = ShareSessionKeychain.load() {
          result([
            "sid": s.sid,
            "expiresAtMs": s.expiresAtMs,
            "hasToken": !s.token.isEmpty,
          ])
        } else {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
