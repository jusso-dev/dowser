import CoreHaptics
import Foundation
import UIKit
import FindPhoneKit

/// The buzz. Taps that firm up as the device gets closer, becoming one
/// continuous buzz at arm's reach, so the last few steps can be walked with
/// the screen in a pocket.
///
/// Only hardware with a Taptic Engine can do any of this. Every iPad reports
/// no haptic support, and the caller hides the control rather than offering a
/// switch that does nothing.
@MainActor
final class HapticPlayer {
    static var isSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    private var engine: CHHapticEngine?
    private var buzzPlayer: CHHapticAdvancedPatternPlayer?
    private var buzzing = false
    /// Set once the system has stopped the engine; the next beat restarts it.
    private var stopped = false

    func start() {
        guard Self.isSupported, engine == nil else { return }
        engine = try? CHHapticEngine()
        // The system stops the engine on interruption and on the way to the
        // background; without these it stays silently dead afterwards. It
        // cannot be restarted from the background, so the next beat does it.
        engine?.stoppedHandler = { [weak self] _ in
            Task { @MainActor in
                self?.buzzing = false
                self?.stopped = true
            }
        }
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in
                self?.buzzing = false
                try? self?.engine?.start()
            }
        }
        engine?.playsHapticsOnly = true
        try? engine?.start()
    }

    func stop() {
        stopBuzz()
        engine?.stop()
        engine = nil
        buzzPlayer = nil
        stopped = false
    }

    /// The engine, started again if the system stopped it.
    private var running: CHHapticEngine? {
        guard let engine else { return nil }
        if stopped {
            guard (try? engine.start()) != nil else { return nil }
            stopped = false
        }
        return engine
    }

    /// One tap. Sharpness rises with intensity so close taps feel crisp rather
    /// than merely stronger.
    func tap(intensity: Double) {
        guard let engine = running else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness,
                                       value: Float(0.3 + intensity * 0.7)),
            ],
            relativeTime: 0)
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    /// A held buzz, started once and then steered by intensity, because
    /// restarting it every tick would chop it into taps again.
    func buzz(intensity: Double) {
        guard let engine = running else { return }
        if !buzzing {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                ],
                relativeTime: 0,
                duration: 30)
            guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
                  let player = try? engine.makeAdvancedPlayer(with: pattern) else { return }
            player.loopEnabled = true
            try? player.start(atTime: CHHapticTimeImmediate)
            buzzPlayer = player
            buzzing = true
            return
        }
        let control = CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                               value: Float(intensity), relativeTime: 0)
        try? buzzPlayer?.sendParameters([control], atTime: CHHapticTimeImmediate)
    }

    func stopBuzz() {
        guard buzzing else { return }
        try? buzzPlayer?.stop(atTime: CHHapticTimeImmediate)
        buzzing = false
    }
}
