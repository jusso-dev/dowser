import Foundation
import SwiftUI
import UIKit
import FindPhoneKit

/// Owns the tracker and republishes it at a fixed rate. The tracker mutates on
/// the main queue, so reading a snapshot from here is safe, and one timer is
/// cheaper than a publisher per advertisement — a busy house delivers hundreds
/// a second.
@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var snapshot: Snapshot
    @Published var soundOn = false { didSet { feedback.sound = soundOn } }
    @Published var hapticsOn = false { didSet { feedback.haptics = hapticsOn } }
    @Published var includeNonApple = false {
        didSet { tracker.includeNonApple = includeNonApple }
    }

    /// Only hardware with a Taptic Engine can buzz — no iPad has one — so the
    /// control is hidden rather than shown doing nothing.
    let canBuzz = HapticPlayer.isSupported

    private let tracker = Tracker()
    private let feedback = ProximityFeedback()
    private var timer: Timer?

    /// A simulator has no Bluetooth radio, so the only way to see the hunt
    /// screen anywhere but on real hardware is to feed it a stand-in house.
    /// Launch with `-demo`, or use the SwiftUI previews.
    private let demo: Bool

    /// Survey redraws twice a second; a hunt needs the faster tick because the
    /// number is being steered by.
    private var tickRate: TimeInterval { snapshot.target.isNone ? 0.5 : 0.25 }

    init(demo: Bool = ProcessInfo.processInfo.arguments.contains("-demo"),
         snapshot: Snapshot? = nil) {
        self.demo = demo
        self.snapshot = snapshot ?? (demo ? PreviewData.snapshot() : tracker.snapshot())
    }

    func start() {
        guard timer == nil, !demo else { return }
        tracker.start()
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        let rate = tickRate
        let timer = Timer(timeInterval: rate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.snapshot = self.tracker.snapshot()
                self.feedback.update(rssi: self.snapshot.isFresh ? self.snapshot.live : nil)
                if rate != self.tickRate { self.schedule() }
            }
        }
        // Common modes, so the reading keeps moving while a list or the hunt
        // itself is being scrolled.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The buzz arms itself with the hunt: it is silent until the device is in
    /// the room, so there is nothing to be surprised by, and having to switch
    /// it on at the moment both hands are busy is the wrong time to ask.
    func hunt(_ advertiser: Advertiser) {
        retarget(.peripheral(advertiser.id))
        hapticsOn = canBuzz
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stopHunting() {
        soundOn = false
        hapticsOn = false
        feedback.stop()
        retarget(.none)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func retarget(_ target: Target) {
        guard !demo else {
            snapshot = PreviewData.snapshot(target: target, advertisers: snapshot.advertisers)
            return
        }
        tracker.retarget(target)
        snapshot = tracker.snapshot()
        schedule()
    }

    /// The advertiser row for whatever is being hunted, which keeps its name
    /// and kind on screen after the list is out of view.
    var targetAdvertiser: Advertiser? {
        guard case .peripheral(let id) = snapshot.target else { return nil }
        return snapshot.advertisers.first { $0.id == id }
    }
}
