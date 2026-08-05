import AudioToolbox
import Foundation
import FindPhoneKit

/// Proximity clicks in the manner of a parking sensor: the closer the device,
/// the faster they come, so a room can be swept by ear while looking at the
/// room.
///
/// Deliberately not a Geiger counter. A counter clicks once per detected
/// particle, and the rate is the measurement. Here the rate is a function of
/// the smoothed signal and no click corresponds to a packet — because packets
/// arrive on our own 0.3s readRSSI timer, so their rate is near constant with
/// distance and counting them would drone rather than guide.
///
/// Self-paced rather than driven by the render loop, which ticks at 4 Hz and
/// would cap the cadence at four clicks a second.
final class Clicker {
    /// Cadence lives in the kit, so the app and the command line ramp
    /// identically.
    private var sound: SystemSoundID = 0
    private var rssi: Int?

    init?(path: String = "/System/Library/Sounds/Tink.aiff") {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path),
              AudioServicesCreateSystemSoundID(url as CFURL, &sound) == kAudioServicesNoError
        else { return nil }
    }

    deinit {
        AudioServicesDisposeSystemSoundID(sound)
    }

    func start() {
        schedule()
    }

    /// Pass nil when contact is stale, so silence means no signal.
    func update(rssi: Int?) {
        self.rssi = rssi
    }

    private func schedule() {
        let wait = rssi.map(ClickCadence.interval(for:)) ?? ClickCadence.slowest
        Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.rssi != nil { AudioServicesPlaySystemSound(self.sound) }
            self.schedule()
        }
    }
}
