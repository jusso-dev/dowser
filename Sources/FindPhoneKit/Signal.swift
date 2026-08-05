import Foundation

public struct Reading: Sendable {
    public let rssi: Int
    public let at: Date
    public let source: String

    public init(rssi: Int, at: Date, source: String) {
        self.rssi = rssi
        self.at = at
        self.source = source
    }
}

extension Array where Element == Reading {
    /// Readings are appended in time order, so a window is found by walking
    /// back from the end rather than scanning the whole history.
    public func since(_ seconds: TimeInterval, now: Date) -> ArraySlice<Reading> {
        let cutoff = now.addingTimeInterval(-seconds)
        var i = endIndex
        while i > startIndex, self[i - 1].at >= cutoff { i -= 1 }
        return self[i...]
    }
}

extension Sequence where Element == Reading {
    /// Median rather than mean, so one reflected spike cannot yank the display
    /// several metres.
    public var medianRSSI: Int? {
        let sorted = map(\.rssi).sorted()
        return sorted.isEmpty ? nil : sorted[sorted.count / 2]
    }

    public var peakRSSI: Int? { lazy.map(\.rssi).max() }
}

public enum Proximity {
    private static let bands: [(floor: Int, label: String)] = [
        (-45, "ARM'S REACH"),
        (-60, "same table"),
        (-72, "same room"),
        (-85, "far / behind something"),
        (.min, "very far or shielded"),
    ]

    public static let labelWidth = bands.map(\.label.count).max() ?? 0
    public static let bandCount = bands.count

    /// Index into the bands, so callers can key their own tables off the same
    /// thresholds instead of restating them.
    public static func band(_ rssi: Int) -> Int {
        bands.firstIndex { rssi >= $0.floor } ?? bands.count - 1
    }

    public static func describe(_ rssi: Int) -> String { bands[band(rssi)].label }

    /// The weakest signal that still counts as `band`, so other tables can key
    /// off these thresholds rather than restating them.
    public static func floor(of band: Int) -> Int { bands[band].floor }

    /// Fraction of the useful -100..-30 dBm span, clamped to 0...1.
    public static func fraction(_ rssi: Int) -> Double {
        (Double(max(-100, min(-30, rssi))) + 100.0) / 70.0
    }
}

/// How much recent history the displayed reading is drawn from.
public let liveWindow: TimeInterval = 4

/// Whether the signal is climbing, by comparing the last few seconds against
/// the several before them. Stays unknown until both windows have samples.
public enum Trend: Sendable {
    case warmer, colder, steady, unknown

    private static let window: TimeInterval = 12
    private static let threshold = 3

    public static func of(_ readings: [Reading], now: Date) -> Trend {
        let near = readings.since(liveWindow, now: now)
        let prior = readings.since(window, now: now)[..<near.startIndex]
        guard near.count >= 2, prior.count >= 2,
              let new = near.medianRSSI, let old = prior.medianRSSI else { return .unknown }
        if new - old > threshold { return .warmer }
        if new - old < -threshold { return .colder }
        return .steady
    }
}

/// Click cadence for proximity sound, shared so the command line and the app
/// stay calibrated the same way.
///
/// Calibrated to what the radio delivers rather than to the display scale: a
/// laptop resting on the phone reads about -50 dBm, so the cadence tops out
/// there instead of ramping toward a -30 that never arrives.
public enum ClickCadence {
    public static let touching = -50.0
    public static let distant = -95.0
    public static let fastest: TimeInterval = 0.07
    public static let slowest: TimeInterval = 1.0

    public static func interval(for rssi: Int) -> TimeInterval {
        let ramp = (Double(rssi) - distant) / (touching - distant)
        return slowest - min(1, max(0, ramp)) * (slowest - fastest)
    }
}

/// Haptics ramp differently from clicks. Clicks accompany the whole walk, so
/// their rate carries the information; a buzz that ran the whole walk would
/// just be noise against the leg. Nothing is felt until the device is in the
/// room, and at arm's reach the taps run together into one continuous buzz —
/// so a buzz means "here", not "warmer".
public enum HapticRamp {
    /// Keyed to the proximity bands, so the buzz starts exactly where the
    /// screen starts saying "same room".
    public static let floor = Proximity.floor(of: 2)
    public static let solid = Proximity.floor(of: 0)

    /// Strength from 0.35 to 1, or nil when the device is too far to be worth
    /// feeling at all.
    public static func intensity(for rssi: Int) -> Double? {
        guard rssi >= floor else { return nil }
        let ramp = Double(rssi - floor) / Double(solid - floor)
        return 0.35 + min(1, max(0, ramp)) * 0.65
    }

    /// Whether to stop tapping and hold a continuous buzz.
    public static func isSolid(_ rssi: Int) -> Bool { rssi >= solid }
}
