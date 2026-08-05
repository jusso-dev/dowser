import Foundation
import FindPhoneKit

/// A stand-in house, for previews and for the simulator — which has no
/// Bluetooth radio at all, so it can never show a real reading.
enum PreviewData {
    static func snapshot(target: Target = .none, advertisers: [Advertiser]? = nil,
                         at: Date = Date()) -> Snapshot {
        let devices = advertisers ?? self.advertisers(at: at)
        let label = { () -> String? in
            guard case .peripheral(let id) = target else { return nil }
            return devices.first { $0.id == id }?.label
        }()
        return Snapshot(
            target: target,
            targetLabel: label,
            address: nil,
            at: at,
            elapsed: 47,
            readings: readings(at: at),
            link: .live,
            radioIssue: nil,
            advertisers: devices,
            deviceCount: devices.count)
    }

    /// The same house, mid-hunt on its strongest device.
    static func huntSnapshot(at: Date = Date()) -> Snapshot {
        let devices = advertisers(at: at)
        return snapshot(target: .peripheral(devices[0].id), advertisers: devices, at: at)
    }

    static func advertisers(at: Date = Date()) -> [Advertiser] {
        let house: [(String?, DeviceKind, Int, Set<UInt8>)] =
            [("Justin iPhone 17 Pro Max", .phone, -48, [0x0C, 0x10, 0x0E]),
             ("AirPods Max", .airPods, -57, [0x07, 0x10]),
             (nil, .watch, -66, [0x0B, 0x10]),
             ("Lounge Room", .tv, -74, [0x09, 0x06]),
             (nil, .findMy, -81, [0x12]),
             (nil, .apple, -88, [0x10])]
        return house
            .enumerated()
            .map { i, d in
                Advertiser(id: UUID(), name: d.0, model: nil, kind: d.1, peak: d.2 + 3,
                           smoothed: Double(d.2), types: d.3,
                           first: at.addingTimeInterval(-40),
                           last: at.addingTimeInterval(-Double(i)))
            }
    }

    /// A walk towards the device: far, then closing.
    static func readings(at: Date = Date()) -> [Reading] {
        (0..<80).map { i in
            let ramp = -82.0 + Double(i) * 0.45
            let wobble = sin(Double(i) / 3) * 2.5
            return Reading(rssi: Int(ramp + wobble), at: at.addingTimeInterval(Double(i - 80) / 3),
                           source: "link")
        }
    }
}
