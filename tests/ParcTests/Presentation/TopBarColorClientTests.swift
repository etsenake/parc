import AppKit
import ParcTestSupport
import Testing
@testable import Parc

struct TopBarColorClientTests {
    private let blue = NSColor(srgbRed: 26.0 / 255, green: 115.0 / 255, blue: 232.0 / 255, alpha: 1)
    private let dark = NSColor(srgbRed: 15.0 / 255, green: 15.0 / 255, blue: 15.0 / 255, alpha: 1)

    @MainActor private final class Clock {
        var time: TimeInterval = 1000
        var pending: [(TimeInterval, @MainActor () -> Void)] = []

        func client(defaults: UserDefaults? = nil) -> TopBarColorClient {
            TopBarColorClient(defaults: defaults, now: { [weak self] in self?.time ?? 0 },
                              schedule: { [weak self] in self?.pending.append(($0, $1)) })
        }

        func advance(by delay: TimeInterval) {
            let due = pending.filter { $0.0 == delay }
            pending.removeAll { $0.0 == delay }
            due.forEach { $0.1() }
        }
    }

    @MainActor private final class Page {
        var sample: TopBarColorClient.Sample?
        func track(with client: TopBarColorClient) {
            client.track(self) { [weak self] in self?.sample }
        }
    }

    @MainActor private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let defaults = try #require(TestDefaults("parc.top-bar-color."))
        try body(defaults)
    }

    private func matches(_ candidate: NSColor?, _ expected: NSColor) -> Bool {
        candidate.map { TopBarColorClient.distance($0, expected) < 0.0001 } ?? false
    }

    @Test @MainActor func theFirstTrackedSampleIsDisplayedAndCached() {
        let clock = Clock()
        let client = clock.client()
        let page = Page()
        #expect(matches(client.initialColor(for: page, host: "example.test"), .white))
        page.track(with: client)
        #expect(clock.pending.map(\.0) == [TopBarColorClient.trackingDelay])
        #expect(client.deliver(.init(color: blue, host: "example.test"), for: page))
        #expect(matches(client.colorToDisplay(for: page), blue))
        #expect(matches(client.cachedColor(forHost: "example.test"), blue))
    }

    @Test(arguments: [false, true])
    @MainActor func missingOrRepeatedSamplesKeepTheDisplayedColor(missing: Bool) {
        let clock = Clock()
        let client = clock.client()
        let page = Page()
        page.track(with: client)
        client.deliver(.init(color: blue, host: "example.test"), for: page)
        #expect(!client.deliver(.init(color: missing ? nil : blue, host: "example.test"), for: page))
        #expect(matches(client.colorToDisplay(for: page), blue))
    }

    @Test @MainActor func aChangedSampleIsDisplayedBeforeItHasSettledForTheCache() {
        let clock = Clock()
        let client = clock.client()
        let page = Page()
        page.track(with: client)
        page.sample = .init(color: blue, host: "example.test")
        clock.advance(by: TopBarColorClient.trackingDelay)
        let changed = TopBarColorClient.Sample(color: dark, host: "example.test")
        page.sample = changed
        #expect(client.deliver(changed, for: page))
        #expect(matches(client.colorToDisplay(for: page), dark))
        #expect(matches(client.cachedColor(forHost: "example.test"), blue))
        clock.advance(by: TopBarColorClient.convergenceDelay)
        #expect(matches(client.cachedColor(forHost: "example.test"), dark))
    }

    @Test @MainActor func switchingHostsDoesNotReuseTheOldHostsSettledSample() {
        let clock = Clock()
        let client = clock.client()
        let page = Page()
        page.track(with: client)
        page.sample = .init(color: blue, host: "old.test")
        clock.advance(by: TopBarColorClient.trackingDelay)
        let changed = TopBarColorClient.Sample(color: blue, host: "new.test")
        page.sample = changed
        #expect(!client.deliver(changed, for: page))
        #expect(client.cachedColor(forHost: "new.test") == nil)
        clock.advance(by: TopBarColorClient.convergenceDelay)
        #expect(matches(client.cachedColor(forHost: "old.test"), blue))
        #expect(matches(client.cachedColor(forHost: "new.test"), blue))
    }

    @Test @MainActor func aHostlessDocumentCanColorItsOwnBarWithoutCreatingACacheEntry() {
        let clock = Clock()
        let client = clock.client()
        let page = Page()
        page.track(with: client)
        client.deliver(.init(color: blue, host: nil), for: page)
        #expect(matches(client.colorToDisplay(for: page), blue))
        #expect(client.domainCache.isEmpty)
    }

    @Test @MainActor func aCachedHostColorIsRestoredFromThePersistedRecord() throws {
        try withDefaults { defaults in
            let clock = Clock()
            let client = clock.client(defaults: defaults)
            let page = Page()
            page.track(with: client)
            client.deliver(.init(color: dark, host: "example.test"), for: page)
            #expect(defaults.dictionary(forKey: TopBarColorClient.defaultsKey) == nil)
            clock.advance(by: TopBarColorClient.persistDelay)
            let entry = defaults.dictionary(forKey: TopBarColorClient.defaultsKey)?["example.test"] as? [String: Any]
            #expect(entry?["Color"] as? String == "#0F0F0F")
            #expect(entry?["LastUsed"] as? Double == clock.time)
            let reopened = clock.client(defaults: defaults)
            #expect(matches(reopened.initialColor(for: Page(), host: "example.test"), dark))
        }
    }

    @Test @MainActor func privateSamplesStayInMemoryAndCanBeForgotten() throws {
        try withDefaults { defaults in
            let clock = Clock()
            let client = clock.client()
            let page = Page()
            page.track(with: client)
            client.deliver(.init(color: blue, host: "private.test"), for: page)
            #expect(matches(client.cachedColor(forHost: "private.test"), blue))
            #expect(!clock.pending.contains { $0.0 == TopBarColorClient.persistDelay })
            client.persist()
            #expect(defaults.dictionary(forKey: TopBarColorClient.defaultsKey) == nil)
            client.forgetAll()
            #expect(client.domainCache.isEmpty)
        }
    }

    @Test @MainActor func theCacheEvictsItsLeastRecentlySampledHost() throws {
        try withDefaults { defaults in
            let clock = Clock()
            let entries = (0..<TopBarColorClient.maximumEntries).map {
                ("site\($0).test", ["Color": "#0F0F0F", "LastUsed": $0] as [String: Any])
            }
            defaults.set(Dictionary(uniqueKeysWithValues: entries), forKey: TopBarColorClient.defaultsKey)
            let client = clock.client(defaults: defaults)
            let page = Page()
            page.track(with: client)
            client.deliver(.init(color: blue, host: "new.test"), for: page)
            #expect(client.domainCache.count == TopBarColorClient.maximumEntries)
            #expect(client.cachedColor(forHost: "site0.test") == nil)
            #expect(matches(client.cachedColor(forHost: "new.test"), blue))
        }
    }

    @Test(arguments: [false, true])
    @MainActor func selectiveHistoryDeletionImmediatelyPersistsOnlyRemainingHosts(timeRange: Bool) throws {
        try withDefaults { defaults in
            let clock = Clock()
            defaults.set(["old.test": ["Color": "#0F0F0F", "LastUsed": 10.0],
                          "new.test": ["Color": "#1A73E8", "LastUsed": 100.0]], forKey: TopBarColorClient.defaultsKey)
            let client = clock.client(defaults: defaults)
            let deletion: [AnyHashable: Any] = timeRange ? ["timeRange": true, "begin": 0.0, "end": 50.0]
                : ["hosts": ["old.test"]]
            client.forgetHistory(deletion)
            #expect(client.cachedColor(forHost: "old.test") == nil)
            let persisted = defaults.dictionary(forKey: TopBarColorClient.defaultsKey)
            #expect(persisted?["old.test"] == nil && persisted?["new.test"] != nil)
        }
    }

    @Test @MainActor func deletingAllHistoryClearsThePersistedColors() throws {
        try withDefaults { defaults in
            let clock = Clock()
            defaults.set(["old.test": ["Color": "#0F0F0F", "LastUsed": 10.0]], forKey: TopBarColorClient.defaultsKey)
            let client = clock.client(defaults: defaults)
            client.forgetHistory(["allHistory": true])
            #expect(client.domainCache.isEmpty)
            #expect(defaults.dictionary(forKey: TopBarColorClient.defaultsKey)?.isEmpty == true)
        }
    }
}
