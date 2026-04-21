import Flutter
import Foundation
import NetworkExtension
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    UIDevice.current.isBatteryMonitoringEnabled = true
    GeneratedPluginRegistrant.register(with: self)

    if let registrar = registrar(forPlugin: "noc_tune/device_info") {
      let channel = FlutterMethodChannel(
        name: "noc_tune/device_info",
        binaryMessenger: registrar.messenger()
      )

      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "unavailable", message: "AppDelegate unavailable", details: nil))
          return
        }

        switch call.method {
        case "getDeviceContext":
          self.getDeviceContext(result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func getDeviceContext(result: @escaping FlutterResult) {
    UIDevice.current.isBatteryMonitoringEnabled = true

    var payload: [String: Any?] = [
      "deviceName": UIDevice.current.name,
      "deviceModel": marketingDeviceName(),
      "osName": "iOS",
      "osVersion": UIDevice.current.systemVersion,
      "connectivityType": nil,
      "batteryLevel": nil,
      "batteryCharging": nil,
      "ssid": nil,
      "bssid": nil,
      "wifiRssi": nil,
      "wifiBand": nil,
      "wifiChannel": nil,
      "dnsPrimary": nil,
      "dnsServers": []
    ]

    let finish: () -> Void = {
      payload["batteryLevel"] = self.batteryLevelPercent()
      payload["batteryCharging"] = self.isBatteryCharging()
      result(payload)
    }

    if #available(iOS 14.0, *) {
      NEHotspotNetwork.fetchCurrent { network in
        if let network = network {
          payload["ssid"] = network.ssid
          payload["bssid"] = network.bssid
          payload["wifiRssi"] = self.approximateRssi(from: network.signalStrength)
          payload["connectivityType"] = "WiFi"
        }
        finish()
      }
    } else {
      finish()
    }
  }

  private func batteryLevelPercent() -> Int? {
    let level = UIDevice.current.batteryLevel
    guard level >= 0 else { return nil }
    return Int((level * 100.0).rounded())
  }

  private func isBatteryCharging() -> Bool? {
    switch UIDevice.current.batteryState {
    case .charging, .full:
      return true
    case .unplugged:
      return false
    default:
      return nil
    }
  }

  private func approximateRssi(from signalStrength: Double) -> Int {
    let clamped = max(0.0, min(1.0, signalStrength))
    return Int((-90.0 + (clamped * 60.0)).rounded())
  }

  private func marketingDeviceName() -> String {
    let identifier = hardwareIdentifier()
    let baseModel = UIDevice.current.model
    if identifier.isEmpty {
      return baseModel
    }
    return "\(baseModel) (\(identifier))"
  }

  private func hardwareIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafePointer(to: &systemInfo.machine) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { cString in
        String(cString: cString)
      }
    }
  }
}
