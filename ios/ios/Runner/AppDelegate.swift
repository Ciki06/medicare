import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let deepLinkChannelName = "medicare/deeplinks"
  private var deepLinkChannel: FlutterMethodChannel?
  private var pendingInitialDeepLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: deepLinkChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "consumeInitialDeepLink" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let link = self?.pendingInitialDeepLink
      self?.pendingInitialDeepLink = nil
      result(link)
    }
    deepLinkChannel = channel
  }

  @discardableResult
  func receiveDeepLink(_ url: URL, initial: Bool) -> Bool {
    guard url.scheme?.lowercased() == "medicare",
          url.host?.lowercased() == "sos",
          url.path == "/trigger" else {
      return false
    }

    let link = url.absoluteString
    if initial || deepLinkChannel == nil {
      pendingInitialDeepLink = link
    } else {
      deepLinkChannel?.invokeMethod("onDeepLink", arguments: link)
    }
    return true
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let handled = receiveDeepLink(url, initial: false)
    return super.application(app, open: url, options: options) || handled
  }
}
