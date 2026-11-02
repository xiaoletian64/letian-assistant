import Flutter
import UIKit
import UserNotifications

enum NotificationEventRules {
  static func identifier(_ value: Any?) -> String? {
    guard let id = value as? String,
          id.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { return nil }
    return id
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var notificationChannel: FlutterMethodChannel?
  private var notificationToken: String?
  private var notificationRegistrationFailed = false
  private var notificationPermissionPending = false
  private var pendingNotificationEvent: String?
  private var notificationBindingGeneration = 0
  private var notificationBindingsEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: "letian_notifications_enabled") }
    set { UserDefaults.standard.set(newValue, forKey: "letian_notifications_enabled") }
  }

  // Compiled APNs support is not a valid signature or a configured server sender.
  // Generic CI is unsigned and opens only the configuration-required screen.
  // Actual availability additionally requires an APNs-enabled profile and token.
  private var apnsConfigured: Bool {
    #if LETIAN_APNS_ENABLED
    return true
    #else
    return false
    #endif
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    if let payload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      captureNotificationEvent(payload)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LetianNative") {
      LetianNative.register(with: registrar)
      let channel = FlutterMethodChannel(name: "site.zhangyue.vault/notifications", binaryMessenger: registrar.messenger())
      notificationChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { result(FlutterError(code: "notification_unavailable", message: "通知服务暂不可用", details: nil)); return }
        switch call.method {
        case "status": self.notificationStatus(result)
        case "requestPermission": self.requestNotificationPermission(result)
        case "openSettings":
          let path: String
          if #available(iOS 16.0, *) { path = UIApplication.openNotificationSettingsURLString }
          else { path = UIApplication.openSettingsURLString }
          guard let url = URL(string: path) else { result(false); return }
          UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
        case "clearBindings":
          self.notificationBindingGeneration += 1
          self.notificationBindingsEnabled = false
          UIApplication.shared.unregisterForRemoteNotifications()
          self.notificationToken = nil
          self.notificationRegistrationFailed = false
          self.pendingNotificationEvent = nil
          UNUserNotificationCenter.current().removeAllDeliveredNotifications()
          UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
          result(true)
        case "getPendingEvent":
          result(self.pendingNotificationEvent)
          self.pendingNotificationEvent = nil
        default: result(FlutterMethodNotImplemented)
        }
      }
      // Re-register every launch; APNs tokens can change. Permission is requested
      // only through the explicit requestPermission method.
      UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
        DispatchQueue.main.async {
          guard let self = self, self.apnsConfigured, self.notificationBindingsEnabled,
                self.isAuthorized(settings.authorizationStatus) else { return }
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
    }
  }

  private func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
    return status == .authorized || status == .provisional || status == .ephemeral
  }

  private func notificationStatus(_ result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
      DispatchQueue.main.async {
        guard let self = self else { result(FlutterError(code: "notification_unavailable", message: "通知服务暂不可用", details: nil)); return }
        let authorization: String
        switch settings.authorizationStatus {
        case .notDetermined: authorization = "notDetermined"
        case .denied: authorization = "denied"
        case .authorized, .provisional, .ephemeral: authorization = "authorized"
        @unknown default: authorization = "unsupported"
        }
        let code = !self.apnsConfigured ? "apns_not_configured" :
          (self.notificationRegistrationFailed ? "apns_registration_failed" :
            (self.notificationToken == nil ? "apns_registration_pending" : "ready"))
        result([
          "authorization": authorization,
          "token": self.notificationToken as Any? ?? NSNull(),
          "background_available": self.apnsConfigured && authorization == "authorized" && self.notificationToken != nil,
          "status_code": code
        ])
      }
    }
  }

  private func requestNotificationPermission(_ result: @escaping FlutterResult) {
    guard !notificationPermissionPending else {
      result(FlutterError(code: "permission_request_in_progress", message: "通知授权请求正在进行", details: nil)); return
    }
    notificationPermissionPending = true
    let bindingGeneration = notificationBindingGeneration
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
      DispatchQueue.main.async {
        guard let self = self else { result(FlutterError(code: "notification_unavailable", message: "通知服务暂不可用", details: nil)); return }
        self.notificationPermissionPending = false
        if error != nil {
          result(FlutterError(code: "permission_request_failed", message: "无法完成系统通知授权，请稍后重试", details: nil)); return
        }
        if granted && bindingGeneration == self.notificationBindingGeneration {
          self.notificationBindingsEnabled = true
        }
        if granted && self.apnsConfigured && self.notificationBindingsEnabled {
          self.notificationRegistrationFailed = false
          UIApplication.shared.registerForRemoteNotifications()
        }
        self.notificationStatus(result)
      }
    }
  }

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    guard notificationBindingsEnabled else { application.unregisterForRemoteNotifications(); return }
    notificationToken = deviceToken.map { String(format: "%02x", $0) }.joined()
    notificationRegistrationFailed = false
    notificationChannel?.invokeMethod("tokenChanged", arguments: nil)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    notificationToken = nil
    notificationRegistrationFailed = true
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  private func captureNotificationEvent(_ payload: [AnyHashable: Any]) {
    guard notificationBindingsEnabled else { return }
    // Payload is only navigation context; Flutter/backend must authenticate the
    // detail request. Never put private account details into the alert payload.
    if let id = NotificationEventRules.identifier(payload["eventID"] ?? payload["event_id"]) {
      pendingNotificationEvent = id
    }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
      willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler(notificationBindingsEnabled ? [.banner, .list, .sound] : [])
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
      didReceive response: UNNotificationResponse,
      withCompletionHandler completionHandler: @escaping () -> Void) {
    captureNotificationEvent(response.notification.request.content.userInfo)
    completionHandler()
  }
}
