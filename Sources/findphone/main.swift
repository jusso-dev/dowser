import Foundation
import FindPhoneKit

let usage = """
findphone — locate a nearby Bluetooth device by signal strength

  findphone            survey every nearby Apple device
  findphone <name>     track one device by name (case-insensitive)
  findphone --list     show paired devices and their addresses

  --sound              click faster as you get closer (hunt mode)
  --redact             mask Bluetooth addresses, for screen recording
  --all                also list devices that are not Apple hardware
  --raw                print advertisements as they arrive, and stop drawing
"""

let knownFlags: Set<String> = ["-h", "--help", "--list", "--redact", "--sound", "--all", "--raw"]

func usageError(_ message: String) -> Never {
    FileHandle.standardError.write(Data("findphone: \(message)\n\n\(usage)\n".utf8))
    exit(2)
}

let args = CommandLine.arguments.dropFirst()

if args.contains("-h") || args.contains("--help") {
    print(usage)
    exit(0)
}

if let unknown = args.first(where: { $0.hasPrefix("-") && !knownFlags.contains($0) }) {
    usageError("unknown option '\(unknown)'")
}

let names = args.filter { !$0.hasPrefix("-") }
if names.count > 1 {
    usageError("expected one device name, got \(names.count): \(names.joined(separator: ", "))")
}

let redact = args.contains("--redact")

if args.contains("--list") {
    Display.list(Classic.devicesByStrength(), redact: redact)
    exit(0)
}

/// Clicks only make sense with a single target; survey mode tracks many.
var clicker: Clicker?
if args.contains("--sound") {
    if names.isEmpty {
        usageError("--sound needs a device name to track")
    }
    clicker = Clicker()
    if clicker == nil {
        FileHandle.standardError.write(Data("findphone: could not open the click sound\n".utf8))
    }
    clicker?.start()
}

let target: Target = names.first.map(Target.name) ?? .none
let tracker = Tracker(target: target, aux: ClassicSource())
tracker.includeNonApple = args.contains("--all")
tracker.onFatal = { fail($0) }

/// Raw mode replaces the display rather than sharing the screen with it: the
/// point is a scrollable log to check kind labels against real hardware.
if args.contains("--raw") {
    if redact {
        fail("--raw prints raw identifying advertisement data; --redact cannot mask it")
    }
    tracker.onRaw = { print(Display.raw($0)) }
    tracker.start()
    RunLoop.main.run()
}

tracker.start()

/// Survey mode also lists what is paired with this Mac: a Mac or a HomePod can
/// go a long time without sending a Continuity packet, so BLE alone would
/// under-report the house.
let paired = ClassicWatcher()
if names.isEmpty { paired.start() }

Timer.scheduledTimer(withTimeInterval: names.isEmpty ? 1.0 : 0.25, repeats: true) { _ in
    let snapshot = tracker.snapshot()
    Display.render(snapshot, redact: redact, paired: paired.devices)
    clicker?.update(rssi: snapshot.isFresh ? snapshot.live : nil)
}

RunLoop.main.run()

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("findphone: \(message)\n".utf8))
    exit(1)
}
