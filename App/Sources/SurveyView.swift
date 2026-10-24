import SwiftUI
import FindPhoneKit

/// Everything Apple that is advertising within range, strongest first.
struct SurveyView: View {
    @EnvironmentObject private var store: DeviceStore
    @Binding var selected: UUID?

    var body: some View {
        List(selection: $selected) {
            if let issue = store.snapshot.radioIssue {
                Section { Text(issue).foregroundStyle(.orange) }
            }
            Section {
                // Plain rows, tagged for selection: a Button here would eat the
                // tap before the list could navigate on it.
                ForEach(store.snapshot.advertisers) { advertiser in
                    DeviceRow(advertiser: advertiser, now: store.snapshot.at)
                        .tag(advertiser.id)
                }
            } header: {
                Text("\(store.snapshot.deviceCount) nearby · \(store.snapshot.elapsed)s")
            } footer: {
                Text("Walk slowly. The one that climbs as you approach a spot is the "
                     + "one you are near. Devices rotate their Bluetooth address every "
                     + "few minutes, so a row can be replaced by an identical-looking one.")
            }
        }
        .animation(.default, value: store.snapshot.advertisers.map(\.id))
        .overlay {
            if store.snapshot.advertisers.isEmpty && store.snapshot.radioIssue == nil {
                ContentUnavailableView(
                    "Listening",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Apple devices advertise in bursts. Give it a few seconds."))
            }
        }
        .navigationTitle("Nearby")
        .navigationSplitViewColumnWidth(min: 330, ideal: 360, max: 460)
        .toolbar {
            Toggle("Everything", isOn: $store.includeNonApple)
                .toggleStyle(.button)
                .help("Also list hardware that is not Apple")
        }
    }
}

#Preview("Survey") {
    @Previewable @State var selected: UUID?
    NavigationStack { SurveyView(selected: $selected) }
        .environmentObject(DeviceStore(demo: true))
}

struct DeviceRow: View {
    let advertiser: Advertiser
    let now: Date

    @Environment(\.dynamicTypeSize) private var typeSize

    private var stale: Bool { now.timeIntervalSince(advertiser.last) > 3 }

    /// At accessibility text sizes three columns leave the name a few letters
    /// wide, so the row stacks instead and the name may wrap.
    private var stacked: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                             : AnyLayout(HStackLayout(spacing: 14))
        layout {
            Image(systemName: advertiser.kind.symbol)
                .font(.title2)
                .frame(width: stacked ? nil : 34)
                .foregroundStyle(BandStyle.color(advertiser.rssi))

            VStack(alignment: .leading, spacing: 3) {
                Text(advertiser.label)
                    .font(.body.weight(.medium))
                    .lineLimit(stacked ? nil : 1)
                Text(advertiser.kind.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SignalBar(rssi: advertiser.rssi)
                    .frame(height: 5)
            }

            VStack(alignment: stacked ? .leading : .trailing, spacing: 3) {
                Text("\(advertiser.rssi)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(BandStyle.color(advertiser.rssi))
                Text(Proximity.describe(advertiser.rssi))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(stacked ? .leading : .trailing)
                    // Dimming is the only other sign a row has gone quiet.
                    .accessibilityLabel(stale ? "\(Proximity.describe(advertiser.rssi)), stale"
                                              : Proximity.describe(advertiser.rssi))
            }
        }
        .padding(.vertical, 4)
        .opacity(stale ? 0.45 : 1)
        .contentShape(Rectangle())
    }
}
