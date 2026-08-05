import SwiftUI
import FindPhoneKit

/// One device, large enough to read while walking.
struct HuntView: View {
    @EnvironmentObject private var store: DeviceStore

    /// Stopping clears the selection and lets the list unwind the navigation.
    /// This view never ends the hunt itself: doing that from `onDisappear`
    /// fired during the push and bounced the screen straight back.
    @Binding var selected: UUID?

    private var snapshot: Snapshot { store.snapshot }

    var body: some View {
        VStack(spacing: 22) {
            if let issue = snapshot.radioIssue {
                ContentUnavailableView("Bluetooth", systemImage: "exclamationmark.triangle",
                                       description: Text(issue))
            } else if let live = snapshot.live, let last = snapshot.readings.last {
                reading(live: live, last: last)
            } else {
                ContentUnavailableView(
                    "No contact yet",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Powered off, out of range (~10-20 m), or shut inside "
                                      + "something metal. \(snapshot.deviceCount) other devices "
                                      + "are in range."))
            }
        }
        .padding()
        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .center)
        .frame(maxWidth: .infinity)
        .navigationTitle(snapshot.targetLabel ?? "Hunting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.canBuzz {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $store.hapticsOn) {
                        Label("Buzz", systemImage: store.hapticsOn
                              ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3.slash")
                    }
                    .toggleStyle(.button)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $store.soundOn) {
                    Label("Sound", systemImage: store.soundOn ? "speaker.wave.3" : "speaker.slash")
                }
                .toggleStyle(.button)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Stop") { selected = nil }
            }
        }
    }

    @ViewBuilder
    private func reading(live: Int, last: Reading) -> some View {
        let tone = BandStyle.color(live)
        let age = Int(snapshot.at.timeIntervalSince(last.at).rounded())
        let lastMinute = snapshot.readings.since(60, now: snapshot.at)

        VStack(spacing: 6) {
            Text("\(live)")
                .font(.system(size: 108, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tone)
                .contentTransition(.numericText())
                .animation(.snappy, value: live)
            Text("dBm").font(.headline).foregroundStyle(.secondary)
        }

        HStack(spacing: 16) {
            Text(Proximity.describe(live).uppercased())
                .font(.headline)
                .foregroundStyle(tone)
            TrendLabel(trend: Trend.of(snapshot.readings, now: snapshot.at))
        }

        SignalBar(rssi: live)
            .frame(height: 22)

        Sparkline(readings: Array(snapshot.readings.suffix(80)))
            .frame(height: 54)

        VStack(spacing: 4) {
            Text("\(snapshot.link.rawValue) · via \(last.source) · refreshed \(age)s ago")
            Text("peak/min \(lastMinute.peakRSSI ?? live) · \(lastMinute.count) measurements "
                 + "last min · \(snapshot.readings.count) total")
            if age > 15 {
                Text("stale — hold still for a refresh").foregroundStyle(.orange)
            }
            if store.hapticsOn {
                Text(HapticRamp.isSolid(live)
                     ? "buzzing — it is within arm's reach"
                     : "buzz starts at \(HapticRamp.floor) dBm, solid at arm's reach")
                    .foregroundStyle(HapticRamp.isSolid(live) ? tone : .secondary)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

        Text("Signal strength is a coarse proxy for distance: walls, metal and bodies "
             + "flatten it. Trust the trend as you move, not any single number.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}

struct TrendLabel: View {
    let trend: Trend

    var body: some View {
        switch trend {
        case .warmer:  Label("WARMER", systemImage: "arrow.up").foregroundStyle(.green)
        case .colder:  Label("colder", systemImage: "arrow.down").foregroundStyle(.red)
        case .steady:  Label("steady", systemImage: "equal").foregroundStyle(.secondary)
        case .unknown: Text("").hidden()
        }
    }
}

/// Colours keyed off the same bands as the labels, so the two cannot drift.
enum BandStyle {
    private static let tones: [Color] = [.green, .mint, .yellow, .orange, .red]

    static func color(_ rssi: Int) -> Color { tones[Proximity.band(rssi)] }
}

struct SignalBar: View {
    let rssi: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(BandStyle.color(rssi))
                    .frame(width: geo.size.width * Proximity.fraction(rssi))
                    .animation(.easeOut(duration: 0.25), value: rssi)
            }
        }
    }
}

#Preview("Hunt") {
    @Previewable @State var selected: UUID? = UUID()
    NavigationStack { HuntView(selected: $selected) }
        .environmentObject(DeviceStore(demo: true, snapshot: PreviewData.huntSnapshot()))
}

/// One bar per measurement, oldest at the left — the shape of the walk.
struct Sparkline: View {
    let readings: [Reading]

    var body: some View {
        GeometryReader { geo in
            let count = max(readings.count, 1)
            let width = geo.size.width / CGFloat(count)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(readings.enumerated()), id: \.offset) { _, reading in
                    Rectangle()
                        .fill(BandStyle.color(reading.rssi).opacity(0.85))
                        .frame(width: max(width - 1, 1),
                               height: max(geo.size.height * Proximity.fraction(reading.rssi), 1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}
