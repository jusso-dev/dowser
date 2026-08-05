import AVFoundation
import Foundation

/// The click itself. Cadence belongs to ProximityFeedback, which shares one
/// clock with the buzz.
///
/// The sound is synthesised rather than shipped as an asset, and played
/// through the playback category, so it is audible with the ringer switched
/// off — which is the state a phone that has gone missing is usually in.
@MainActor
final class ClickPlayer {
    private var player: AVAudioPlayer?

    func start() {
        if player == nil { player = Self.makePlayer() }
        try? AVAudioSession.sharedInstance()
            .setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func stop() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func play() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    private static func makePlayer() -> AVAudioPlayer? {
        guard let player = try? AVAudioPlayer(data: clickWAV()) else { return nil }
        player.prepareToPlay()
        return player
    }

    /// A 12 ms decaying tone, written as a WAV in memory. Short and percussive
    /// so clicks stay countable when they run together near the device.
    private static func clickWAV(rate: Double = 44_100, seconds: Double = 0.012,
                                 frequency: Double = 2_000) -> Data {
        let frames = Int(rate * seconds)
        var samples = Data(capacity: frames * 2)
        for i in 0..<frames {
            let t = Double(i) / rate
            let decay = exp(-t * 320)
            let value = sin(2 * .pi * frequency * t) * decay * 0.6
            let sample = Int16(max(-1, min(1, value)) * Double(Int16.max))
            withUnsafeBytes(of: sample.littleEndian) { samples.append(contentsOf: $0) }
        }
        return wav(pcm: samples, rate: Int(rate))
    }

    private static func wav(pcm: Data, rate: Int) -> Data {
        var out = Data()
        func ascii(_ s: String) { out.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }

        ascii("RIFF"); u32(UInt32(36 + pcm.count)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1)          // PCM, mono
        u32(UInt32(rate)); u32(UInt32(rate * 2))        // sample rate, byte rate
        u16(2); u16(16)                                 // block align, bit depth
        ascii("data"); u32(UInt32(pcm.count)); out.append(pcm)
        return out
    }
}
