import AppKit

@MainActor final class TopBarColorClient {
    static let shared = TopBarColorClient(defaults: .standard)
    static let privateBrowsing = TopBarColorClient(defaults: nil)
    static func client(privateBrowsing: Bool) -> TopBarColorClient { privateBrowsing ? Self.privateBrowsing : shared }

    nonisolated static let defaultsKey = "TopBarColorCache"
    static let convergenceDistance = 0.015
    static let maximumConvergenceAttempts = 4
    static let convergenceDelay: TimeInterval = 0.4
    static let trackingDelay: TimeInterval = 0.25
    static let maximumEntries = 50
    static let persistDelay: TimeInterval = 1

    struct Entry: Equatable { var color: NSColor; var lastUpdated: TimeInterval }
    struct State {
        var colorToDisplay: NSColor?
        var currentColorSample: NSColor?
        var currentColorSampleHost: String?
        var numConvergenceAttempts = 0
        var requireConvergence = true
    }
    struct Sample { var color: NSColor?; var host: String? }

    private let defaults: UserDefaults?
    private let now: () -> TimeInterval
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private(set) var domainCache: [String: Entry]
    private var states: [ObjectIdentifier: State] = [:]
    private struct Delivered: Equatable { var color: NSColor?; var host: String? }
    private struct Tracked { weak var key: AnyObject?; var read: () -> Sample?; var delivered: Delivered? }
    private var tracked: [ObjectIdentifier: Tracked] = [:]
    private var persistScheduled = false

    init(defaults: UserDefaults?,
         now: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate },
         schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(work) }
         }) {
        self.defaults = defaults
        self.now = now
        self.schedule = schedule
        domainCache = defaults.map(Self.load(from:)) ?? [:]
        NotificationCenter.default.addObserver(forName: Self.historyDidDeleteNotification, object: nil,
                                               queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { self?.forgetHistory(info) }
        }
    }

    nonisolated static let historyDidDeleteNotification = Notification.Name("PCNativeHistoryDidDeleteNotification")

    func track(_ key: AnyObject, read: @escaping () -> Sample?) {
        let id = ObjectIdentifier(key)
        guard tracked[id]?.key !== key else { return }
        for (dead, entry) in tracked where entry.key == nil { tracked[dead] = nil; states[dead] = nil }
        tracked[id] = Tracked(key: key, read: read, delivered: nil)
        states[id] = nil
        recheck(id, requireConvergence: false, after: Self.trackingDelay)
    }

    @discardableResult
    func deliver(_ sample: Sample, for key: AnyObject) -> Bool {
        let id = ObjectIdentifier(key)
        guard var entry = tracked[id], entry.key === key else { return false }
        let delivery = Delivered(color: sample.color, host: sample.host)
        if entry.delivered == delivery { return false }
        entry.delivered = delivery
        tracked[id] = entry
        return receive(sample, id: id)
    }

    func untrack(_ key: AnyObject) {
        let id = ObjectIdentifier(key)
        tracked[id] = nil
        states[id] = nil
    }

    func colorToDisplay(for key: AnyObject) -> NSColor? { states[ObjectIdentifier(key)]?.colorToDisplay }

    func cachedColor(forHost host: String?) -> NSColor? {
        guard let host, !host.isEmpty else { return nil }
        return domainCache[host]?.color
    }

    func initialColor(for key: AnyObject, host: String?) -> NSColor {
        colorToDisplay(for: key) ?? cachedColor(forHost: host) ?? .white
    }

    @discardableResult
    func receive(_ sample: Sample, for key: AnyObject) -> Bool {
        receive(sample, id: ObjectIdentifier(key))
    }

    @discardableResult
    private func receive(_ sample: Sample, id: ObjectIdentifier) -> Bool {
        guard let color = sample.color?.usingColorSpace(.sRGB) else { return false }
        var state = states[id] ?? State()
        let host = sample.host.flatMap { $0.isEmpty ? nil : $0 }
        let converged = state.currentColorSampleHost == host
            && state.currentColorSample.map { Self.distance(color, $0) <= Self.convergenceDistance } ?? false
        let cached = cachedColor(forHost: host)
        let matchesCache = cached.map { Self.distance(color, $0) <= Self.convergenceDistance } ?? false
        if host == nil {
            state.numConvergenceAttempts = 0
        } else if let host, !state.requireConvergence || converged || matchesCache {
            domainCache[host] = Entry(color: color, lastUpdated: now())
            trim()
            schedulePersist()
            state.numConvergenceAttempts = 0
        } else if state.numConvergenceAttempts < Self.maximumConvergenceAttempts {
            recheck(id, requireConvergence: true, after: Self.convergenceDelay)
            state.numConvergenceAttempts += 1
        }
        state.requireConvergence = true
        let changed = state.colorToDisplay.map { !$0.isEqual(color) } ?? true
        state.colorToDisplay = color
        state.currentColorSample = color
        state.currentColorSampleHost = host
        states[id] = state
        return changed
    }

    private func recheck(_ id: ObjectIdentifier, requireConvergence: Bool, after delay: TimeInterval) {
        var state = states[id] ?? State()
        state.requireConvergence = requireConvergence
        states[id] = state
        schedule(delay) { [weak self] in
            guard let self, let entry = self.tracked[id], let key = entry.key else { return }
            guard let sample = entry.read() else { self.untrack(key); return }
            if self.receive(sample, id: id) {
                NotificationCenter.default.post(name: Self.displayColorDidChangeNotification, object: key)
            }
        }
    }

    static let displayColorDidChangeNotification = Notification.Name("TopBarColorClientDisplayColorDidChange")

    nonisolated static func distance(_ a: NSColor, _ b: NSColor) -> Double {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return .greatestFiniteMagnitude }
        let red = Double(a.redComponent - b.redComponent)
        let green = Double(a.greenComponent - b.greenComponent)
        let blue = Double(a.blueComponent - b.blueComponent)
        return (red * red + green * green + blue * blue).squareRoot()
    }

    private func schedulePersist() {
        guard defaults != nil, !persistScheduled else { return }
        persistScheduled = true
        schedule(Self.persistDelay) { [weak self] in
            guard let self else { return }
            self.persistScheduled = false
            self.persist()
        }
    }

    private func trim() {
        guard domainCache.count > Self.maximumEntries else { return }
        let kept = domainCache.sorted { $0.value.lastUpdated > $1.value.lastUpdated }.prefix(Self.maximumEntries)
        domainCache = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    func forgetHistory(_ info: [AnyHashable: Any]) {
        if info["allHistory"] as? Bool == true { forgetAll(); return }
        let hosts = Set(info["hosts"] as? [String] ?? [])
        let range = info["timeRange"] as? Bool == true
            ? (info["begin"] as? Double ?? -.greatestFiniteMagnitude)...(info["end"] as? Double ?? .greatestFiniteMagnitude)
            : nil
        let before = domainCache.count
        domainCache = domainCache.filter { host, entry in
            !hosts.contains(host) && !(range?.contains(entry.lastUpdated) ?? false)
        }
        if domainCache.count != before { persist() }
    }

    func forgetAll() {
        domainCache.removeAll()
        for id in states.keys { states[id]?.requireConvergence = true }
        persist()
    }

    func persist() {
        trim()
        guard let defaults else { return }
        let encoded = domainCache.mapValues { entry -> [String: Any] in
            ["Color": Self.hex(entry.color), "LastUsed": entry.lastUpdated]
        }
        defaults.set(encoded, forKey: Self.defaultsKey)
    }

    nonisolated static func load(from defaults: UserDefaults) -> [String: Entry] {
        guard let stored = defaults.dictionary(forKey: defaultsKey) else { return [:] }
        var cache: [String: Entry] = [:]
        for (host, value) in stored {
            guard let fields = value as? [String: Any], let hex = fields["Color"] as? String,
                  let lastUsed = fields["LastUsed"] as? Double, let color = color(hex: hex) else { continue }
            cache[host] = Entry(color: color, lastUpdated: lastUsed)
        }
        return cache
    }

    nonisolated static func hex(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }

    nonisolated static func color(hex: String) -> NSColor? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
