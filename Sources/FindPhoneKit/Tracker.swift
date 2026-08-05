import Foundation
import CoreBluetooth

public enum LinkState: String, Sendable {
    case down = "LINK DOWN"
    case classic = "link up"
    case live = "LIVE LINK"
}

/// What the hunt is pointed at. A name is what someone types; a peripheral is
/// what they tap in a list, where most Apple devices never offer a name.
public enum Target: Equatable, Sendable {
    case none
    case name(String)
    case peripheral(UUID)

    public var isNone: Bool { self == .none }
}

public struct Advertiser: Identifiable, Sendable {
    public let id: UUID
    public var name: String?
    public var model: String?
    public var kind: DeviceKind
    public var peak: Int
    public var smoothed: Double
    public var types: Set<UInt8>
    public var first: Date
    public var last: Date

    public init(id: UUID, name: String?, model: String?, kind: DeviceKind, peak: Int,
                smoothed: Double, types: Set<UInt8>, first: Date, last: Date) {
        self.id = id
        self.name = name
        self.model = model
        self.kind = kind
        self.peak = peak
        self.smoothed = smoothed
        self.types = types
        self.first = first
        self.last = last
    }

    /// Best available identity, in descending order of usefulness. Falls back
    /// to the kind, which carries no identity — so it is also what redacted
    /// output shows in place of a name that may not be yours.
    public var label: String { name ?? model ?? kind.rawValue }

    /// The Continuity messages seen from this device, which is the evidence
    /// behind `kind`.
    public var typeSummary: String {
        types.isEmpty ? "no Continuity data"
            : types.sorted().map(Continuity.name(for:)).joined(separator: " ")
    }

    public var rssi: Int { Int(smoothed.rounded()) }
}

/// One advertisement exactly as it arrived, for `--raw`. The point is being
/// able to check the kind labels against a house full of real devices.
public struct RawAdvert: Sendable {
    public let id: UUID
    public let rssi: Int
    public let name: String?
    public let manufacturer: Data?
    public let services: [String]
}

public struct Snapshot: Sendable {
    public let target: Target
    public let targetLabel: String?
    public let address: String?
    public let at: Date
    public let elapsed: Int
    public let readings: [Reading]
    public let link: LinkState
    public let radioIssue: String?
    public let advertisers: [Advertiser]
    public let deviceCount: Int

    public init(target: Target, targetLabel: String?, address: String?, at: Date, elapsed: Int,
                readings: [Reading], link: LinkState, radioIssue: String?,
                advertisers: [Advertiser], deviceCount: Int) {
        self.target = target
        self.targetLabel = targetLabel
        self.address = address
        self.at = at
        self.elapsed = elapsed
        self.readings = readings
        self.link = link
        self.radioIssue = radioIssue
        self.advertisers = advertisers
        self.deviceCount = deviceCount
    }

    /// The reading everything reports: a short median, so one reflected spike
    /// cannot move the number, the arrow and the clicks apart from each other.
    public var live: Int? {
        readings.since(liveWindow, now: at).medianRSSI ?? readings.last?.rssi
    }

    /// Whether the last reading is recent enough to steer by.
    public var isFresh: Bool {
        readings.last.map { at.timeIntervalSince($0.at) < 10 } ?? false
    }
}

/// A source of readings CoreBluetooth cannot provide — on macOS, the link RSSI
/// of a paired classic device. Nothing supplies this on iOS, which is why it
/// is injected rather than assumed.
public protocol AuxiliarySource: AnyObject {
    func poll(name: String) -> (address: String, rssi: Int?)?
}

private let historyWindow: TimeInterval = 600
private let advertiserTTL: TimeInterval = 20

public final class Tracker: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    /// Whether to list devices that are not Apple hardware. Off by default:
    /// a house answers with light bulbs and televisions otherwise.
    public var includeNonApple = false

    /// Called when Bluetooth is unusable in a way that waiting will not fix.
    /// The command line exits; the app puts it on screen.
    public var onFatal: ((String) -> Void)?

    /// Set to receive every advertisement as it arrives.
    public var onRaw: ((RawAdvert) -> Void)?

    private var target: Target = .none
    private let aux: AuxiliarySource?
    private let startedAt = Date()

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var linkTimer: Timer?

    private var readings: [Reading] = []
    private var advertisers: [UUID: Advertiser] = [:]
    private var address: String?
    private var radioIssue: String?
    private var cachedID: UUID?

    private let lock = NSLock()
    private var liveLink = false
    private var linkUp = false

    /// Read from the polling thread, so it sits behind the lock.
    private var isLive: Bool { lock.withLock { liveLink } }

    public init(target: Target = .none, aux: AuxiliarySource? = nil) {
        self.target = target
        self.aux = aux
        super.init()
    }

    public func start() {
        central = CBCentralManager(delegate: self, queue: nil)
        if case .name(let n) = target {
            cachedID = DeviceCache.peripheralID(for: n)
            startAuxPolling(name: n)
        }
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.prune()
        }
    }

    /// Switching target throws the history away: those readings describe the
    /// old device, and a hunt that opens with someone else's signal is worse
    /// than one that opens empty.
    public func retarget(_ new: Target) {
        guard new != target else { return }
        target = new
        readings.removeAll()
        address = nil
        linkUp = false
        if let p = peripheral {
            central?.cancelPeripheralConnection(p)
            peripheral = nil
        }
        dropLink()

        switch new {
        case .none:
            cachedID = nil
        case .name(let n):
            cachedID = DeviceCache.peripheralID(for: n)
            startAuxPolling(name: n)
            restoreCachedTarget()
        case .peripheral(let id):
            cachedID = id
            restoreCachedTarget()
        }
    }

    public func snapshot() -> Snapshot {
        let now = Date()
        return Snapshot(
            target: target,
            targetLabel: targetLabel,
            address: address,
            at: now,
            elapsed: Int(now.timeIntervalSince(startedAt)),
            readings: readings,
            link: isLive ? .live : (linkUp ? .classic : .down),
            radioIssue: radioIssue,
            advertisers: advertisers.values.sorted { $0.smoothed > $1.smoothed },
            deviceCount: advertisers.count)
    }

    private var targetLabel: String? {
        switch target {
        case .none: return nil
        case .name(let n): return n
        case .peripheral(let id): return advertisers[id]?.label ?? peripheral?.name ?? "device"
        }
    }

    private func prune() {
        let now = Date()
        while let oldest = readings.first,
              now.timeIntervalSince(oldest.at) >= historyWindow {
            readings.removeFirst()
        }
        // A device that has stopped advertising and one whose address has just
        // rotated look identical from here, so both simply age out. The one
        // being hunted stays, so its row cannot vanish mid-sweep.
        advertisers = advertisers.filter {
            $0.key == currentTargetID || now.timeIntervalSince($0.value.last) < advertiserTTL
        }
    }

    private var currentTargetID: UUID? {
        if case .peripheral(let id) = target { return id }
        return nil
    }

    private func record(_ rssi: Int, _ source: String) {
        guard rssi < 0, rssi > -127 else { return }
        readings.append(Reading(rssi: rssi, at: Date(), source: source))
    }

    // MARK: - Auxiliary polling

    /// Skipped while the GATT link is live: the link is both fresher and far
    /// cheaper than spawning system_profiler. macOS serves a cached RSSI
    /// between its own refreshes, so only a changed value is a real
    /// measurement.
    private func startAuxPolling(name: String) {
        guard let aux else { return }
        DispatchQueue(label: "aux.poll").async { [weak self] in
            var lastRaw: Int?
            var addressResolved = false
            while true {
                guard let self else { return }
                guard case .name(let current) = self.target, current == name else { return }
                if self.isLive && addressResolved {
                    lastRaw = nil
                } else {
                    let found = aux.poll(name: name)
                    let value = found?.rssi
                    let changed = value != nil && value != lastRaw
                    lastRaw = value
                    addressResolved = true
                    DispatchQueue.main.async {
                        self.address = found?.address ?? self.address
                        self.linkUp = value != nil
                        if changed, let v = value { self.record(v, "classic") }
                    }
                }
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
    }

    // MARK: - Central

    public func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            radioIssue = nil
            c.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            restoreCachedTarget()
        case .poweredOff:
            radioIssue = "Bluetooth is off. Waiting for it to come back on."
            dropLink()
        case .unauthorized:
            radioIssue = Self.permissionHelp
            onFatal?(Self.permissionHelp)
        case .unsupported:
            radioIssue = "This device has no Bluetooth LE support."
            onFatal?("This device has no Bluetooth LE support.")
        default:
            radioIssue = "Bluetooth unavailable."
        }
    }

    #if os(macOS)
    static let permissionHelp = """
        Bluetooth permission denied.
        System Settings > Privacy & Security > Bluetooth > enable your terminal.
        """
    #else
    static let permissionHelp = """
        Bluetooth permission denied.
        Settings > Privacy & Security > Bluetooth.
        """
    #endif

    /// A remembered peripheral can be connected before any advertisement
    /// arrives, which is the difference between a 2s and a 30s cold start.
    private func restoreCachedTarget() {
        guard peripheral == nil, central?.state == .poweredOn, let id = cachedID,
              let p = central.retrievePeripherals(withIdentifiers: [id]).first
        else { return }
        adopt(p)
    }

    private func adopt(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        central.connect(p, options: nil)
    }

    private func dropLink() {
        lock.withLock { liveLink = false }
        linkTimer?.invalidate()
        linkTimer = nil
    }

    public func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                               advertisementData d: [String: Any], rssi RSSI: NSNumber) {
        let r = RSSI.intValue
        guard r < 0, r > -127 else { return }

        let mfg = d[CBAdvertisementDataManufacturerDataKey] as? Data
        let services = (d[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            + Array((d[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]).keys)
        let advertName = d[CBAdvertisementDataLocalNameKey] as? String ?? p.name

        onRaw?(RawAdvert(id: p.identifier, rssi: r, name: advertName,
                         manufacturer: mfg, services: services.map(\.uuidString)))

        let records = mfg.map(Continuity.records) ?? [:]
        let hasFindMy = services.contains(findMyService)
        let isApple = !records.isEmpty || hasFindMy

        // Everything Apple is listed; anything else only on request, or when
        // it is the device being hunted.
        guard isApple || includeNonApple || currentTargetID == p.identifier
                || matchesTargetName(advertName) else { return }

        let now = Date()
        var a = advertisers[p.identifier] ?? Advertiser(
            id: p.identifier, name: nil, model: nil, kind: .other,
            peak: r, smoothed: Double(r), types: [], first: now, last: now)
        a.name = a.name ?? advertName
        a.peak = max(a.peak, r)
        a.smoothed = a.smoothed * 0.7 + Double(r) * 0.3
        a.types.formUnion(records.keys)
        a.last = now
        if a.model == nil, let pairing = records[Continuity.proximityPairing] {
            a.model = ProximityPairing.model(pairing)
        }
        a.kind = DeviceKind.infer(types: a.types, hasFindMyService: hasFindMy,
                                  name: a.name ?? a.model)
        advertisers[p.identifier] = a

        switch target {
        case .none:
            return
        case .peripheral(let id):
            guard id == p.identifier else { return }
            record(r, "advert")
            if peripheral == nil { adopt(p) }
        case .name(let t):
            guard let n = a.name, n.localizedCaseInsensitiveContains(t) else { return }
            record(r, "advert")
            if cachedID != p.identifier {
                cachedID = p.identifier
                DeviceCache.store(p.identifier, for: t)
            }
            guard let current = peripheral else { return adopt(p) }
            if current.state != .connected && current.identifier != p.identifier {
                central.cancelPeripheralConnection(current)
                adopt(p)
            }
        }
    }

    private func matchesTargetName(_ name: String?) -> Bool {
        guard case .name(let t) = target, let name else { return false }
        return name.localizedCaseInsensitiveContains(t)
    }

    public func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        lock.withLock { liveLink = true }
        linkTimer?.invalidate()
        linkTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            p.readRSSI()
        }
    }

    /// CoreBluetooth holds an unfulfilled connect pending indefinitely, so
    /// simply reissuing it is a complete reconnect strategy. A peripheral we
    /// have since retargeted away from is left alone.
    public func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral,
                               error: Error?) {
        guard p.identifier == peripheral?.identifier else { return }
        dropLink()
        c.connect(p, options: nil)
    }

    public func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral,
                               error: Error?) {
        guard p.identifier == peripheral?.identifier else { return }
        dropLink()
        c.connect(p, options: nil)
    }

    public func peripheral(_ p: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil, p.identifier == peripheral?.identifier else { return }
        record(RSSI.intValue, "link")
    }
}

/// Remembers which CoreBluetooth peripheral matched a search, so a later run
/// can connect straight away instead of waiting for one of the rare
/// advertisements that carries the device name.
public enum DeviceCache {
    /// A dotfile where a command-line tool's config belongs; inside the
    /// container on iOS, where there is nowhere else to put it.
    private static let url: URL = {
        #if os(macOS)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/findphone/devices.json")
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("findphone/devices.json")
        #endif
    }()

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    public static func peripheralID(for name: String) -> UUID? {
        load()[name.lowercased()].flatMap(UUID.init(uuidString:))
    }

    public static func store(_ id: UUID, for name: String) {
        var map = load()
        map[name.lowercased()] = id.uuidString
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(map).write(to: url)
    }
}
