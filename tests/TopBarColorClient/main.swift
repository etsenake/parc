import AppKit

@MainActor var failures = 0
@MainActor func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures += 1; print("FAIL: \(message)") }
}

func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}
func same(_ a: NSColor?, _ b: NSColor?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    return TopBarColorClient.distance(a, b) < 0.0001
}

@MainActor final class Harness {
    var time: TimeInterval = 1000
    var pending: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
    let suite = "org.parc.tests.top-bar-color.\(UUID().uuidString)"
    lazy var defaults = UserDefaults(suiteName: suite)!
    func client(persistent: Bool = true) -> TopBarColorClient {
        TopBarColorClient(defaults: persistent ? defaults : nil, now: { [unowned self] in self.time },
                          schedule: { [unowned self] delay, work in self.pending.append((delay, work)) })
    }
    func run(delay: TimeInterval) {
        let due = pending.filter { $0.delay == delay }
        pending.removeAll { $0.delay == delay }
        due.forEach { $0.work() }
    }
    deinit { UserDefaults().removePersistentDomain(forName: suite) }
}

final class Page { var sample: TopBarColorClient.Sample? }

@MainActor func main() {
    let harness = Harness()
    let client = harness.client()
    let page = Page()
    let blue = rgb(26, 115, 232), black = rgb(0, 0, 0), dark = rgb(15, 15, 15)

    //
    check(same(client.initialColor(for: page, host: "example.com"), .white), "unknown page starts white")

    // Tracking re-reads after 250 ms without convergence; the first delivered
    // sample is displayed and cached at once.
    client.track(page) { page.sample }
    check(harness.pending.map(\.delay) == [0.25], "tracking re-reads after 250 ms")
    page.sample = .init(color: blue, host: "1password.com")
    check(client.deliver(page.sample!, for: page), "first sample changes the display")
    check(same(client.colorToDisplay(for: page), blue), "sample is displayed")
    check(same(client.cachedColor(forHost: "1password.com"), blue), "first sample after tracking is cached")
    check(harness.pending.contains { $0.delay == 1 }, "a cache change persists after one second")

    // The same delivery again is not a new sample.
    check(!client.deliver(page.sample!, for: page), "repeat delivery is ignored")
    //
    check(!client.deliver(.init(color: nil, host: "1password.com"), for: page), "nil sample is ignored")
    check(same(client.colorToDisplay(for: page), blue), "nil sample keeps the colour")

    // A different sample is displayed at once but cached only once it holds:
    // the 400 ms re-read finds it unchanged.
    harness.run(delay: 0.25)
    page.sample = .init(color: black, host: "1password.com")
    check(client.deliver(page.sample!, for: page), "new sample changes the display")
    check(same(client.colorToDisplay(for: page), black), "new sample is displayed")
    check(same(client.cachedColor(forHost: "1password.com"), blue), "unsettled sample is not cached")
    check(harness.pending.contains { $0.delay == 0.4 }, "unsettled sample re-reads after 400 ms")
    harness.run(delay: 0.4)
    check(same(client.cachedColor(forHost: "1password.com"), black), "a held colour is cached on re-read")

    // A sample within 0.015 of the cache is cached directly.
    page.sample = .init(color: rgb(2, 2, 2), host: "1password.com")
    client.deliver(page.sample!, for: page)
    check(same(client.cachedColor(forHost: "1password.com"), rgb(2, 2, 2)), "sample matching the cache is cached")

    // At most four re-reads while the colour keeps moving.
    var shade = 40
    page.sample = .init(color: rgb(shade, 0, 0), host: "1password.com")
    client.deliver(page.sample!, for: page)
    var rereads = 0
    while harness.pending.contains(where: { $0.delay == 0.4 }) && rereads < 10 {
        shade += 40
        page.sample = .init(color: rgb(shade, 0, 0), host: "1password.com")
        harness.run(delay: 0.4)
        rereads += 1
    }
    check(rereads == 4, "a moving colour is re-read four times, not \(rereads)")

    // A new page for a cached host starts with the cached colour, and the
    // page's own colour wins once it has one.
    let other = Page()
    check(same(client.initialColor(for: other, host: "1password.com"), rgb(2, 2, 2)),
          "cached host colour is the initial colour")
    client.track(other) { other.sample }
    client.deliver(.init(color: dark, host: "1password.com"), for: other)
    check(same(client.initialColor(for: other, host: "1password.com"), dark), "displayed colour beats the cache")

    // Persistence: {host: {Color, LastUsed}} under TopBarColorCache.
    harness.run(delay: 1)
    let stored = harness.defaults.dictionary(forKey: TopBarColorClient.defaultsKey)
    let entry = stored?["1password.com"] as? [String: Any]
    check(entry?["Color"] as? String == "#0F0F0F", "cache stores the hex colour")
    check(entry?["LastUsed"] as? Double == 1000, "cache stores the update time")
    let reloaded = harness.client()
    check(same(reloaded.cachedColor(forHost: "1password.com"), dark), "cache reloads from defaults")

    // The cache keeps the 50 most recently updated hosts.
    for i in 0..<51 {
        harness.time = 2000 + Double(i)
        let key = Page()
        reloaded.track(key) { nil }
        reloaded.deliver(.init(color: rgb(i, i, i), host: "site\(i).test"), for: key)
    }
    reloaded.persist()
    check(reloaded.domainCache.count == 50, "cache keeps 50 hosts, not \(reloaded.domainCache.count)")
    check(reloaded.cachedColor(forHost: "1password.com") == nil, "oldest host is evicted")
    check(reloaded.cachedColor(forHost: "site50.test") != nil, "newest host is kept")

    // A private window's client never writes defaults.
    let privateClient = harness.client(persistent: false)
    let privatePage = Page()
    privateClient.track(privatePage) { nil }
    privateClient.deliver(.init(color: blue, host: "private.test"), for: privatePage)
    check(same(privateClient.cachedColor(forHost: "private.test"), blue), "private client caches in memory")
    privateClient.persist()
    check((harness.defaults.dictionary(forKey: TopBarColorClient.defaultsKey)?["private.test"]) == nil,
          "private client does not persist")

    // A document without a host is displayed but never cached.
    let local = Page()
    client.track(local) { nil }
    client.deliver(.init(color: blue, host: nil), for: local)
    check(same(client.colorToDisplay(for: local), blue), "a hostless document's colour is displayed")
    check(client.cachedColor(forHost: nil) == nil && client.domainCache["NullString"] == nil,
          "a hostless document's colour is not cached")

    // Navigation on the same page: a colour is stored only under the host it
    // was sampled for, and the previous host's sample is no convergence.
    let navigating = Page()
    let navigator = harness.client()
    navigator.track(navigating) { navigating.sample }
    navigating.sample = .init(color: blue, host: "a.test")
    navigator.deliver(navigating.sample!, for: navigating)
    harness.run(delay: 0.25)
    check(same(navigator.cachedColor(forHost: "a.test"), blue), "first host's colour is cached")
    navigating.sample = .init(color: blue, host: "b.test")
    check(navigator.deliver(navigating.sample!, for: navigating) == false, "same colour on a new host changes no display")
    check(navigator.cachedColor(forHost: "b.test") == nil, "the old host's sample does not settle the new host")
    navigating.sample = .init(color: black, host: "b.test")
    navigator.deliver(navigating.sample!, for: navigating)
    check(navigator.cachedColor(forHost: "b.test") == nil, "a new host's first sample waits to settle")
    check(same(navigator.cachedColor(forHost: "a.test"), blue), "the new host's colour never reaches the old host")
    harness.run(delay: 0.4)
    check(same(navigator.cachedColor(forHost: "b.test"), black), "the new host's held colour is cached under it")
    check(same(navigator.cachedColor(forHost: "a.test"), blue), "the old host keeps its own colour")

    // History deletions forget hosts, a time range, or everything, and write
    // the cache at once.
    let deletions = Harness()
    let clearing = deletions.client()
    let written = { deletions.defaults.dictionary(forKey: TopBarColorClient.defaultsKey) ?? [:] }
    for (i, host) in ["x.test", "y.test", "z.test"].enumerated() {
        deletions.time = 5000 + Double(i * 100)
        let key = Page()
        clearing.track(key) { nil }
        clearing.deliver(.init(color: rgb(i, 0, 0), host: host), for: key)
    }
    deletions.run(delay: 1)
    check(written()["x.test"] != nil && written()["z.test"] != nil, "colours are written before the deletion")
    clearing.forgetHistory(["hosts": ["x.test"]])
    check(clearing.cachedColor(forHost: "x.test") == nil && clearing.cachedColor(forHost: "y.test") != nil,
          "a deleted URL's host is forgotten")
    check(written()["x.test"] == nil && written()["y.test"] != nil, "a host deletion is written at once")
    clearing.forgetHistory(["timeRange": true, "begin": 5150.0, "end": 6000.0])
    check(clearing.cachedColor(forHost: "z.test") == nil && clearing.cachedColor(forHost: "y.test") != nil,
          "colours cached in a deleted time range are forgotten")
    check(written()["z.test"] == nil && written()["y.test"] != nil, "a time-range deletion is written at once")
    NotificationCenter.default.post(name: TopBarColorClient.historyDidDeleteNotification, object: nil,
                                    userInfo: ["allHistory": true, "hosts": [String](), "timeRange": false])
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    check(clearing.domainCache.isEmpty, "the engine's all-history deletion forgets every colour")

    // The private client trims to 50 as it caches, with nothing persisted.
    let trimmed = harness.client(persistent: false)
    for i in 0..<60 {
        harness.time = 9000 + Double(i)
        let key = Page()
        trimmed.track(key) { nil }
        trimmed.deliver(.init(color: rgb(i, i, 0), host: "p\(i).test"), for: key)
    }
    check(trimmed.domainCache.count == 50, "the private cache trims to 50 without persisting")
    trimmed.forgetAll()
    check(trimmed.domainCache.isEmpty, "closing the last private window empties its cache")

    if failures == 0 { print("Passed TopBarColorClient display, convergence, cache and persistence checks; no browser.") }
    exit(failures == 0 ? 0 : 1)
}

MainActor.assumeIsolated { main() }
