import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var channelsReady = false
  private var channelRetry = 0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    setupNativeChannelsIfNeeded()
    return ok
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    registerNativeChannels(messenger: engineBridge.applicationRegistrar.messenger())
    NSLog("RemdyShareSession channel via implicit engine")
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme?.lowercased() == "remdy",
       url.host?.lowercased() == "share-in" {
      NotificationCenter.default.post(
        name: Notification.Name("RemdyShareInJobAvailable"),
        object: nil
      )
    }
    return super.application(app, open: url, options: options)
  }

  private func setupNativeChannelsIfNeeded() {
    if channelsReady { return }
    if let registrar = self.registrar(forPlugin: "RemdyShareSession") {
      registerNativeChannels(messenger: registrar.messenger())
      NSLog("RemdyShareSession channel via registrar")
      return
    }
    if let controller = flutterController() {
      registerNativeChannels(messenger: controller.binaryMessenger)
      NSLog("RemdyShareSession channel via FlutterViewController")
      return
    }
    channelRetry += 1
    guard channelRetry < 80 else {
      NSLog("RemdyShareSession channel not ready after retries")
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      self?.setupNativeChannelsIfNeeded()
    }
  }

  private func flutterController() -> FlutterViewController? {
    if let controller = window?.rootViewController as? FlutterViewController {
      return controller
    }
    if let nested = window?.rootViewController?.children.first as? FlutterViewController {
      return nested
    }
    if #available(iOS 13.0, *) {
      for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        for sceneWindow in windowScene.windows {
          if let controller = sceneWindow.rootViewController as? FlutterViewController {
            return controller
          }
          if let nested = sceneWindow.rootViewController?.children.first as? FlutterViewController {
            return nested
          }
        }
      }
    }
    return nil
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
