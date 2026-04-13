import CoreWLAN
import CoreLocation
import Foundation

class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var done = false
    var authorized = false
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status != .notDetermined {
            authorized = (status == .authorizedAlways || status == .authorized)
            done = true
        }
    }
}

func getWiFiInfo() {
    let outputPath = ProcessInfo.processInfo.environment["SSID_OUTPUT"] 
        ?? "/tmp/noctune_ssid.txt"
    
    let locationManager = CLLocationManager()
    let delegate = LocationDelegate()
    locationManager.delegate = delegate
    
    let status = locationManager.authorizationStatus
    var locationNote = "status:\(status.rawValue)"
    
    if status == .notDetermined {
        locationManager.requestWhenInUseAuthorization()
        // Run the run loop to process the authorization callback
        let deadline = Date().addingTimeInterval(30)
        while !delegate.done && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        if delegate.done {
            locationNote = "status:\(locationManager.authorizationStatus.rawValue)"
        } else {
            locationNote = "status:timeout"
        }
    } else if status == .denied || status == .restricted {
        locationNote = "status:denied"
    }
    
    // Small delay to let the system process the authorization
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    
    var output = ""
    let client = CWWiFiClient.shared()
    if let iface = client.interface() {
        let ssid = iface.ssid() ?? "nil"
        let rssi = iface.rssiValue()
        let channel = iface.wlanChannel()?.channelNumber ?? 0
        let band = channel >= 36 ? "5GHz" : "2.4GHz"
        output += "SSID:\(ssid)\n"
        output += "RSSI:\(rssi)\n"
        output += "CHANNEL:\(channel)\n"
        output += "BAND:\(band)\n"
        output += "LOCATION:\(locationNote)\n"
    } else {
        output += "ERROR:No Wi-Fi interface found\n"
    }
    
    print(output, terminator: "")
    try? output.write(toFile: outputPath, atomically: true, encoding: .utf8)
}

getWiFiInfo()
