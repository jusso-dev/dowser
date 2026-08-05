import Foundation
import CoreBluetooth

/// Apple's company identifier in BLE manufacturer data.
public let appleCompanyID: UInt16 = 0x004C

/// Find My (offline finding) service data. A separated AirTag or a lost Apple
/// device advertises here as well as in manufacturer data.
public let findMyService = CBUUID(string: "FD44")

/// Apple's Continuity messages, keyed by the type byte that opens each
/// type-length-value record inside its manufacturer data.
///
/// Apple documents none of this; the mapping comes from published protocol
/// analysis and holds only as far as it has been observed. `findphone --raw`
/// prints the bytes as they arrive so an unrecognised type shows up as a
/// number rather than being silently dropped.
public enum Continuity {
    public static let names: [UInt8: String] = [
        0x02: "iBeacon",
        0x03: "AirPrint",
        0x05: "AirDrop",
        0x06: "HomeKit",
        0x07: "ProxPairing",
        0x08: "HeySiri",
        0x09: "AirPlay-tgt",
        0x0A: "AirPlay-src",
        0x0B: "MagicSwitch",
        0x0C: "Handoff",
        0x0D: "Hotspot-tgt",
        0x0E: "Hotspot-src",
        0x0F: "NearbyAction",
        0x10: "NearbyInfo",
        0x12: "FindMy",
    ]

    public static let proximityPairing: UInt8 = 0x07
    public static let findMy: UInt8 = 0x12

    /// Splits manufacturer data into its Continuity records. Returns nothing
    /// for a non-Apple advertisement, which is how non-Apple hardware is told
    /// apart from an Apple device that happens to be quiet.
    public static func records(_ data: Data) -> [UInt8: Data] {
        let bytes = [UInt8](data)
        guard bytes.count >= 3,
              UInt16(bytes[0]) | (UInt16(bytes[1]) << 8) == appleCompanyID else { return [:] }

        var out: [UInt8: Data] = [:]
        var i = 2
        while i + 1 < bytes.count {
            let type = bytes[i]
            let len = Int(bytes[i + 1])
            let start = i + 2
            let end = min(start + len, bytes.count)
            out[type] = Data(bytes[start..<end])
            if len == 0 { break }
            i = start + len
        }
        return out
    }

    public static func name(for type: UInt8) -> String {
        names[type] ?? String(format: "type-0x%02X", type)
    }
}

/// What a device appears to be. Inferred from which Continuity messages it
/// sends, which is a hint rather than an identification: several kinds share a
/// message, and a device only sends what it currently has to say.
public enum DeviceKind: String, CaseIterable, Sendable {
    case airPods = "AirPods / Beats"
    case watch = "Apple Watch"
    case phone = "iPhone"
    case handheld = "iPhone / iPad"
    case computer = "Mac / iPad"
    case tv = "Apple TV / HomePod"
    case findMy = "AirTag / Find My"
    case homeKit = "HomeKit accessory"
    case beacon = "iBeacon"
    case apple = "Apple device"
    case other = "non-Apple"

    /// SF Symbol for the app; harmless on the command line.
    public var symbol: String {
        switch self {
        case .airPods:   return "airpods"
        case .watch:     return "applewatch"
        case .phone:     return "iphone"
        case .handheld:  return "ipad.and.iphone"
        case .computer:  return "laptopcomputer"
        case .tv:        return "appletv"
        case .findMy:    return "location.circle"
        case .homeKit:   return "house"
        case .beacon:    return "dot.radiowaves.left.and.right"
        case .apple:     return "apple.logo"
        case .other:     return "antenna.radiowaves.left.and.right"
        }
    }

    /// Ordered most specific first: a device sending both proximity pairing and
    /// Nearby Info is a pair of AirPods, not a generic Apple device.
    public static func infer(types: Set<UInt8>, hasFindMyService: Bool,
                             name: String?) -> DeviceKind {
        if let n = name?.lowercased() {
            if n.contains("airpod") || n.contains("beats") { return .airPods }
            if n.contains("watch") { return .watch }
            if n.contains("iphone") { return .phone }
            if n.contains("ipad") || n.contains("mac") || n.contains("book") { return .computer }
            if n.contains("homepod") || n.contains("apple tv") { return .tv }
            if n.contains("airtag") { return .findMy }
        }
        if types.contains(0x07) { return .airPods }
        if types.contains(0x0B) { return .watch }
        if types.contains(0x0E) { return .phone }        // only a phone shares a hotspot
        if types.contains(0x09) && !types.contains(0x0A) { return .tv }
        if types.contains(0x0D) { return .computer }     // asking for someone's hotspot
        if types.contains(0x06) { return .homeKit }
        if types.contains(0x02) && types.count == 1 { return .beacon }
        if types.contains(0x12) || hasFindMyService {
            // Anything Apple that is out of touch with its owner also lands
            // here, so this is "in the Find My network", not "is an AirTag".
            return types.isEmpty || types == [0x12] ? .findMy : .apple
        }
        if types.contains(0x0A) || types.contains(0x05) || types.contains(0x0C) {
            return .handheld
        }
        return types.isEmpty ? .other : .apple
    }
}

/// AirPods and Beats announce their model in the clear, in the proximity
/// pairing record. Only the models confirmed by observation are listed; an
/// unknown one keeps its hex so it can be added rather than guessed at.
public enum ProximityPairing {
    static let models: [UInt16: String] = [
        0x0220: "AirPods",
        0x0F20: "AirPods (2nd gen)",
        0x1320: "AirPods (3rd gen)",
        0x0E20: "AirPods Pro",
        0x1420: "AirPods Pro (2nd gen)",
        0x0A20: "AirPods Max",
        0x0320: "Powerbeats3",
        0x0B20: "Powerbeats Pro",
        0x0520: "BeatsX",
        0x0620: "Beats Solo3",
        0x0920: "Beats Studio3",
        0x1020: "Beats Flex",
        0x1120: "Beats Studio Buds",
    ]

    /// The model sits after a one-byte prefix, big-endian.
    public static func model(_ payload: Data) -> String? {
        let b = [UInt8](payload)
        guard b.count >= 3 else { return nil }
        let id = UInt16(b[1]) << 8 | UInt16(b[2])
        return models[id] ?? String(format: "AirPods/Beats (model %04X)", id)
    }
}
