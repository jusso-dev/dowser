import Foundation
import FindPhoneKit

/// Sound and buzz, driven off one clock so they cannot drift apart.
///
/// Self-paced rather than driven by the render loop, which ticks at 4 Hz and
/// would cap the cadence at four beats a second.
@MainActor
final class ProximityFeedback {
    var sound = false { didSet { sound ? clicker.start() : clicker.stop(); sync() } }
    var haptics = false { didSet { haptics ? haptic.start() : haptic.stop(); sync() } }

    private let clicker = ClickPlayer()
    private let haptic = HapticPlayer()
    private var timer: Timer?
    private var rssi: Int?

    /// Pass nil when contact is stale, so silence and stillness mean no
    /// signal rather than no device.
    func update(rssi: Int?) {
        self.rssi = rssi
        if rssi == nil { haptic.stopBuzz() }
    }

    func stop() {
        sound = false
        haptics = false
    }

    private var running: Bool { sound || haptics }

    private func sync() {
        if running {
            if timer == nil { schedule() }
        } else {
            timer?.invalidate()
            timer = nil
            haptic.stopBuzz()
        }
    }

    private func schedule() {
        guard running else { return }
        let wait = rssi.map(ClickCadence.interval(for:)) ?? ClickCadence.slowest
        let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                self.beat()
                self.schedule()
            }
        }
        // Common modes, so the clicks do not stall while the screen scrolls.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func beat() {
        guard let rssi else { return }
        if sound { clicker.play() }
        guard haptics else { return }

        // Below the ramp there is nothing to feel: a buzz that ran the whole
        // walk would say nothing about being close, which is the one thing it
        // is here to say.
        guard let intensity = HapticRamp.intensity(for: rssi) else { return haptic.stopBuzz() }
        if HapticRamp.isSolid(rssi) {
            haptic.buzz(intensity: intensity)
        } else {
            haptic.stopBuzz()
            haptic.tap(intensity: intensity)
        }
    }
}
