import SwiftUI

@main
struct DowserApp: App {
    @StateObject private var store = DeviceStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { store.start() }
        }
    }
}

/// A list beside a hunt: on an iPad the two fit side by side, so the reading
/// can be watched while the rest of the house stays visible. On a phone the
/// same structure collapses to push-and-pop.
///
/// Selection is the only thing that navigates. The tracker follows the
/// selection rather than the other way round — driving both from tracker state
/// gave the detail view a way to unselect itself mid-push, which read as a
/// screen that bounced straight back.
struct RootView: View {
    @EnvironmentObject private var store: DeviceStore
    @State private var selected: UUID?

    /// Held open: an iPad in portrait hides the sidebar by default, and a list
    /// you have to summon is the wrong default for the screen the whole app is
    /// about.
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SurveyView(selected: $selected)
        } detail: {
            if selected == nil {
                ContentUnavailableView(
                    "Pick a device",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Tap anything in the list to start walking it down."))
            } else {
                NavigationStack { HuntView(selected: $selected) }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selected) { _, id in
            guard let id, let device = store.snapshot.advertisers.first(where: { $0.id == id })
            else { return store.stopHunting() }
            store.hunt(device)
        }
    }
}
