import Foundation
import FindPhoneKit

private let clearScreen = "\u{1B}[2J\u{1B}[H"
private let huntWidth = 60
private let margin = "    "
private let surveyRule = String(repeating: "-", count: 78)

/// Frame-invariant pieces, built once rather than on every redraw.
private let huntRule = Style.wrap(String(repeating: "─", count: huntWidth), Style.dim)
private let huntFooter = Style.wrap(
    " Move a few metres, then stand still ~10s.   Ctrl-C to stop.", Style.dim)
private let dBmSuffix = Style.wrap("   dBm", Style.dim)
private let sparkCaption = "1 block = 1 measurement"

/// Indexed by Proximity.band, so the colour cannot drift from the label.
private let bandTones = [Style.brightGreen, Style.green, Style.yellow, Style.amber, Style.red]

/// A Bluetooth public address is a stable hardware identifier, so it is worth
/// hiding when the screen is being recorded.
private let maskedAddress = "••:••:••:••:••:••"

enum Display {
    /// One write per frame; twenty prints to a line-buffered TTY tears.
    static func render(_ s: Snapshot, redact: Bool = false,
                       paired: [ClassicDevice] = []) {
        let lines = s.target.isNone
            ? survey(s, redact: redact, paired: paired)
            : hunt(s, redact: redact)
        print(clearScreen + lines.joined(separator: "\n"), terminator: "\n")
        fflush(stdout)
    }

    private static func hunt(_ s: Snapshot, redact: Bool) -> [String] {
        let address = redact ? maskedAddress : (s.address ?? "")
        let status = "\(s.link.rawValue) · \(s.elapsed)s"
        let title = " \(s.targetLabel ?? "device")   \(address)"
        let gap = max(1, huntWidth - title.count - status.count)
        let out = [Style.wrap(title + String(repeating: " ", count: gap) + status, Style.dim),
                   huntRule]

        if let issue = s.radioIssue {
            return out + ["", "  \(issue)"]
        }
        guard let last = s.readings.last else {
            return out + ["", "  No contact yet — \(s.deviceCount) other devices in range.", "",
                          "  If this persists the device is powered off, out of range",
                          "  (~10-20 m), or shut inside something metal."]
        }

        let live = s.live ?? last.rssi
        let lastMinute = s.readings.since(60, now: s.at)
        let peak = lastMinute.peakRSSI ?? live
        let age = Int(s.at.timeIntervalSince(last.at).rounded())
        let tone = bandTones[Proximity.band(live)]

        let digits = bigNumber(String(live)).enumerated().map { row, glyph in
            margin + Style.wrap(glyph, tone) + (row == bigTextMiddle ? dBmSuffix : "")
        }

        let label = Style.wrap(Proximity.describe(live).uppercased(), tone)
        let trend = trendLabel(Trend.of(s.readings, now: s.at))

        return out + [""] + digits + [
            "",
            margin + label + "     " + trend,
            "",
            margin + Style.wrap(bar(live, width: 44, fill: "█", empty: "░"), tone),
            "",
            margin + Style.wrap(sparkline(s.readings.suffix(44)), Style.dim),
            Style.wrap("\(margin)\(sparkCaption) · \(lastMinute.count) last min"
                       + " · \(s.readings.count) total", Style.dim),
            Style.wrap("\(margin)peak/min \(peak) · via \(last.source)"
                       + " · refreshed \(age)s ago", Style.dim),
        ]
        + (age > 15 ? [Style.wrap("\(margin)stale — hold still for a refresh", Style.amber)] : [])
        + [huntRule, huntFooter]
    }

    private static func trendLabel(_ trend: Trend) -> String {
        switch trend {
        case .warmer:  return Style.wrap("▲ WARMER", Style.brightGreen)
        case .colder:  return Style.wrap("▼ colder", Style.red)
        case .steady:  return Style.wrap("· steady", Style.dim)
        case .unknown: return ""
        }
    }

    private static func survey(_ s: Snapshot, redact: Bool,
                               paired: [ClassicDevice]) -> [String] {
        var out = [
            "Nearby Apple devices — live signal   [\(s.elapsed)s, \(s.deviceCount) tracked]",
            "Walk slowly. The one that climbs as you approach a spot is your device.",
            surveyRule,
            Style.wrap("Advertising over BLE — anyone's devices, not only yours", Style.dim),
        ]
        if let issue = s.radioIssue { out.append("  \(issue)") }
        if s.advertisers.isEmpty { out.append("  (nothing yet — give it a few seconds)") }

        for (i, a) in s.advertisers.prefix(12).enumerated() {
            let live = a.rssi
            let stale = s.at.timeIntervalSince(a.last) > 3 ? " (stale)" : ""
            out.append(String(format: "%2d. %@ %4d dBm  peak %4d  ", i + 1, bar(live), live, a.peak)
                       + pad(Proximity.describe(live), Proximity.labelWidth) + stale)
            // The kind is inferred and carries no identity, so it is what a
            // redacted screen keeps; the name may be a neighbour's.
            let identity = redact ? a.kind.rawValue : "\(a.kind.rawValue) · \(a.label)"
            out.append("    " + pad(identity, 40) + Style.wrap(a.typeSummary, Style.dim))
        }
        return out + pairedSection(paired, redact: redact) + [surveyRule, "Ctrl-C to stop."]
    }

    /// Paired devices carry a stable address and a name you chose, so this
    /// section is the one that answers "where is my Mac" — but its RSSI comes
    /// from a value macOS refreshes only every few seconds.
    private static func pairedSection(_ paired: [ClassicDevice], redact: Bool) -> [String] {
        guard !paired.isEmpty else { return [] }
        var out = [surveyRule,
                   Style.wrap("Paired with this Mac — classic radio, macOS refreshes it "
                              + "every 3-12s", Style.dim)]
        for d in paired.prefix(8) {
            guard let rssi = d.rssi else { continue }
            // The name is one you chose and identifies your own hardware, so a
            // redacted screen gets the kind guessed from it instead.
            let kind = DeviceKind.infer(types: [], hasFindMyService: false, name: d.name)
            out.append(String(format: "    %@ %4d dBm  ", bar(rssi), rssi)
                       + pad(Proximity.describe(rssi), Proximity.labelWidth) + "  "
                       + (redact ? kind.rawValue : d.name))
        }
        return out
    }

    static func list(_ devices: [ClassicDevice], redact: Bool = false) {
        guard !devices.isEmpty else {
            print("No paired Bluetooth devices found.")
            return
        }
        print(pad("NAME", 26) + pad("ADDRESS", 20) + pad("RSSI", 7) + "STATE")
        for d in devices {
            print(pad(d.name, 26) + pad(redact ? maskedAddress : d.address, 20)
                  + pad(d.rssi.map(String.init) ?? "-", 7)
                  + (d.connected ? "connected" : "not connected"))
        }
        print("\nTrack one with:  findphone <name>")
    }

    /// One line per advertisement, so the Continuity types this house actually
    /// emits can be checked against the table that names them.
    static func raw(_ a: RawAdvert) -> String {
        let mfg = a.manufacturer.map { $0.map { String(format: "%02x", $0) }.joined() } ?? "-"
        let types = a.manufacturer.map(Continuity.records)?.keys.sorted()
            .map(Continuity.name(for:)).joined(separator: ",") ?? ""
        return pad(String(a.id.uuidString.prefix(8)), 10)
            + pad("\(a.rssi)", 6)
            + pad(a.name ?? "-", 22)
            + pad(types.isEmpty ? "-" : types, 34)
            + pad(a.services.joined(separator: ","), 20)
            + mfg
    }
}
