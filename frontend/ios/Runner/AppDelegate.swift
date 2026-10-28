import Flutter
import UIKit
import UserNotifications
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let secureStoreChannelName = "smart_medicine_box/secure_store"
  private let biometricChannelName = "smart_medicine_box/biometric_auth"
  private let keychainService = Bundle.main.bundleIdentifier ?? "smart_medicine_box"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()

    let secureStoreChannel = FlutterMethodChannel(
      name: secureStoreChannelName,
      binaryMessenger: messenger
    )
    secureStoreChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      guard let arguments = call.arguments as? [String: Any],
            let key = arguments["key"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "key is required", details: nil))
        return
      }
      switch call.method {
      case "write":
        guard let value = arguments["value"] as? String else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "value is required", details: nil))
          return
        }
        result(self.writeSecureValue(key: key, value: value))
      case "read":
        result(self.readSecureValue(key: key))
      case "delete":
        result(self.deleteSecureValue(key: key))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

  private func keychainQuery(key: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: key
    ]
  }

  private func writeSecureValue(key: String, value: String) -> Bool {
    let query = keychainQuery(key: key)
    SecItemDelete(query as CFDictionary)
    guard let data = value.data(using: .utf8) else { return false }
    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  private func readSecureValue(key: String) -> String? {
    var query = keychainQuery(key: key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
          let data = item as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private func deleteSecureValue(key: String) -> Bool {
    let status = SecItemDelete(keychainQuery(key: key) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

}
