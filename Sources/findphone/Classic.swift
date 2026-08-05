import Foundation
import FindPhoneKit

struct ClassicDevice {
    let name: String
    let address: String
    let rssi: Int?
    let connected: Bool
}

/// The paired-device table from system_profiler. Unlike BLE advertising
/// addresses, which Apple rotates every few minutes, these public addresses
/// are stable, so a device stays identifiable across runs.
enum Classic {
    static func devices() -> [ClassicDevice] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bt = (root["SPBluetoothDataType"] as? [[String: Any]])?.first
        else { return [] }

        return bt.flatMap { section, value -> [ClassicDevice] in
            guard let items = value as? [[String: Any]] else { return [] }
            return items.flatMap { item in
                item.compactMap { name, raw -> ClassicDevice? in
                    guard let info = raw as? [String: Any],
                          let address = info["device_address"] as? String else { return nil }
                    let rssi = (info["device_rssi"] as? String).flatMap(Int.init)
                        ?? info["device_rssi"] as? Int
                    return ClassicDevice(name: name, address: address, rssi: rssi,
                                         connected: section == "device_connected")
                }
            }
        }
    }

    static func devicesByStrength() -> [ClassicDevice] {
        devices().sorted { ($0.rssi ?? .min) > ($1.rssi ?? .min) }
    }

    static func find(name: String) -> ClassicDevice? {
        devices().first { $0.name.localizedCaseInsensitiveContains(name) }
    }
}

/// The classic table as a reading source for the tracker. Only macOS has one:
/// iOS exposes neither `system_profiler` nor the classic radio, which is the
/// main reason the app sees less than the command line does.
final class ClassicSource: AuxiliarySource {
    func poll(name: String) -> (address: String, rssi: Int?)? {
        Classic.find(name: name).map { ($0.address, $0.rssi) }
    }
}

/// Keeps a current copy of the paired table for survey mode. Macs, Apple TVs
/// and HomePods can go long stretches without sending a Continuity packet, so
/// the BLE list alone is not the household; anything paired with this Mac and
/// reporting an RSSI is in range whether or not it is advertising.
///
/// Polled on its own thread because system_profiler takes the better part of a
/// second, and refreshed no faster than macOS updates the value behind it.
final class ClassicWatcher {
    private let lock = NSLock()
    private var latest: [ClassicDevice] = []

    var devices: [ClassicDevice] { lock.withLock { latest } }

    func start() {
        DispatchQueue(label: "classic.survey").async { [weak self] in
            while let self {
                let found = Classic.devicesByStrength().filter { $0.rssi != nil }
                self.lock.withLock { self.latest = found }
                Thread.sleep(forTimeInterval: 3)
            }
        }
    }
}
