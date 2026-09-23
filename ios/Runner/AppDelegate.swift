import Flutter
import UIKit

enum RemdyLaunchURL {
  static func handleShareInIfNeeded(_ url: URL) {
    if url.scheme?.lowercased() == "remdy",
       url.host?.lowercased() == "share-in" {
      NotificationCenter.default.post(
        name: Notification.Name("RemdyShareInJobAvailable"),
        object: nil
      )
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var channelsReady = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Plugins and method channels must be registered in
    // didInitializeImplicitFlutterEngine. Touching window/rootViewController
    // here crashes under the UIScene lifecycle required by the iOS 27 SDK.
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerNativeChannels(messenger: engineBridge.applicationRegistrar.messenger())
    NSLog("RemdyShareSession channel via implicit engine")
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    RemdyLaunchURL.handleShareInIfNeeded(url)
    return super.application(app, open: url, options: options)
  }

  private func registerNativeChannels(messenger: FlutterBinaryMessenger) {
    if channelsReady { return }
    channelsReady = true

    let badgeChannel = FlutterMethodChannel(
      name: "remdy/app_badge",
      binaryMessenger: messenger
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
      binaryMessenger: messenger
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
        let exp = ShareSessionKeychain.int64Value(args["expiresAtMs"])
        let report = ShareSessionStore.saveAndReport(
          ShareSessionKeychain.Session(token: token, sid: sid, expiresAtMs: exp)
        )
        result(report)
      case "clearSession":
        result(ShareSessionStore.clear())
      case "hasSession":
        result(ShareSessionStore.promoteIfNeeded() || ShareSessionStore.hasSharedSession())
      case "readSessionMeta":
        result(ShareSessionStore.meta())
      case "markCallable":
        let args = call.arguments as? [String: Any]
        let ok = (args?["ok"] as? Bool) ?? false
        let code = (args?["code"] as? String) ?? ""
        NSLog("RemdyShareSession callable ok=%d code=%@", ok ? 1 : 0, code)
        result(nil)
      case "saveDestinations":
        let args = (call.arguments as? [String: Any]) ?? [:]
        result(ShareAppGroupSession.saveDestinations(args))
      case "hasDestinations":
        result(ShareAppGroupSession.loadDestinations() != nil)
      case "peekShareJobs":
        result(ShareIncomingStore.peekJobs())
      case "peekShareDiag":
        let tail = ShareDiag.readTail()
        if !tail.isEmpty {
          NSLog("RemdyShareExtDiagHost\n%@", tail)
        }
        result(tail)
      case "ackShareJob":
        let jobId = (call.arguments as? [String: Any])?["jobId"] as? String
          ?? (call.arguments as? String)
          ?? ""
        if jobId.isEmpty {
          result(false)
        } else {
          ShareIncomingStore.removeJob(jobId: jobId)
          result(true)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    ShareSessionStore.promoteIfNeeded()
    let diag = ShareDiag.readTail()
    if !diag.isEmpty {
      NSLog("RemdyShareExtDiagHost\n%@", diag)
    }
  }
}
