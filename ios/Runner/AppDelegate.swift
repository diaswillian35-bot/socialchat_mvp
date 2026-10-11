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

enum RemdyPushRegistration {
  static var pluginsReady = false
  static var pendingDeviceToken: Data?
  static var messenger: FlutterBinaryMessenger?
  private static var sceneObserver: NSObjectProtocol?

  static func noteDeviceToken(_ deviceToken: Data) {
    pendingDeviceToken = deviceToken
    NSLog("RemdyPush phase=apns state=buffered bytes=%d", deviceToken.count)
  }

  static func takePendingDeviceToken() -> Data? {
    let token = pendingDeviceToken
    pendingDeviceToken = nil
    return token
  }

  static func registerIfReady() {
    guard pluginsReady else {
      NSLog("RemdyPush phase=register state=plugins_not_ready")
      return
    }
    NSLog("RemdyPush phase=register state=requested")
    UIApplication.shared.registerForRemoteNotifications()
  }

  static func observeSceneActivation() {
    if sceneObserver != nil { return }
    sceneObserver = NotificationCenter.default.addObserver(
      forName: UIScene.didActivateNotification,
      object: nil,
      queue: .main
    ) { _ in
      registerIfReady()
    }
  }

  static func notifyDart(received: Bool, byteCount: Int, errorCode: Int?) {
    guard let messenger else { return }
    let channel = FlutterMethodChannel(
      name: "remdy/push_registration",
      binaryMessenger: messenger
    )
    var args: [String: Any] = [
      "received": received,
      "bytes": byteCount,
    ]
    if let errorCode {
      args["errorCode"] = errorCode
    }
    channel.invokeMethod("apns", arguments: args)
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
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerNativeChannels(messenger: messenger)
    RemdyPushRegistration.messenger = messenger
    RemdyPushRegistration.pluginsReady = true
    if let token = RemdyPushRegistration.takePendingDeviceToken() {
      super.application(
        UIApplication.shared,
        didRegisterForRemoteNotificationsWithDeviceToken: token
      )
      RemdyPushRegistration.notifyDart(received: true, byteCount: token.count, errorCode: nil)
    }
    RemdyPushRegistration.registerIfReady()
    RemdyPushRegistration.observeSceneActivation()
    NSLog("RemdyPush phase=engine state=plugins_ready")
    NSLog("RemdyShareSession channel via implicit engine")
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    NSLog("RemdyPush phase=apns state=callback bytes=%d pluginsReady=%d", deviceToken.count, RemdyPushRegistration.pluginsReady ? 1 : 0)
    if RemdyPushRegistration.pluginsReady {
      super.application(
        application,
        didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
      )
      RemdyPushRegistration.notifyDart(received: true, byteCount: deviceToken.count, errorCode: nil)
    } else {
      RemdyPushRegistration.noteDeviceToken(deviceToken)
    }
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    let nsError = error as NSError
    NSLog("RemdyPush phase=error source=apns code=%d", nsError.code)
    RemdyPushRegistration.notifyDart(received: false, byteCount: 0, errorCode: nsError.code)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
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
