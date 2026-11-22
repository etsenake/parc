import AppKit
import ParcEngine
import ParcTestSupport
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcCommandBar

struct SiteSearchOfferTests {
    @MainActor private final class Window: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    @MainActor private final class Fixture {
        static let profile = UUID()
        let window: Window
        let native: PCNativeOmnibox
        let bar: CommandBar
        let address: String?

        init(query: String, address: String? = nil, allowsExtension: Bool = true) throws {
            _ = NSApplication.shared
            window = Window(contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
                            styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let native = PCNativeOmnibox(profilePath: "test", page: nil, window: nil)
            self.native = native
            self.address = address
            let tabs = address.map { value in
                [BrowserTab(id: UUID(), spaceID: UUID(), profileID: Self.profile, url: value, title: value, kind: .today,
                            createdAt: .distantPast, lastAccessed: .distantPast, savedURL: "", savedTitle: "")]
            } ?? []
            let defaults = try #require(TestDefaults("Parc.SiteSearchOffer."))
            bar = CommandBar(parent: window, tabs: tabs, history: [], currentURL: nil, profilePath: "test", page: nil,
                initialEdit: query.isEmpty ? nil : (query, NSRange(location: query.utf16.count, length: 0)),
                extensionDisposition: allowsExtension ? .currentTab : nil,
                shortcuts: KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false),
                privacyDefaults: defaults, makeOmnibox: { _, _, _ in native }, loadFavicon: { _, _, _ in })
            bar.present()
        }

        func publish(query: String = "", scopes: [[String: Any]], results: [[String: Any]] = [],
                     extensions: [[String: Any]] = []) {
            let message: [String: Any] = ["input": query, "scopes": scopes, "results": results, "extensions": extensions]
            _ = native.perform(NSSelectorFromString("parcTestPublish:"), with: message)
        }

        func offeredSite() -> String? {
            let surface = window.contentView?.subviews.last?.subviews.compactMap { $0 as? PopoverBackgroundView }.first
            let hint = surface?.subviews.compactMap { $0 as? CommandBarScopeHint }.first
            guard let hint, !hint.isHidden else { return nil }
            return hint.accessibilityLabel()
        }
    }

    static let activeCases: [(String, [String], String?)] = [
        ("https://www.google.com/", ["www.google.com"], "www.google.com"),
        ("https://www.youtube.com/", ["www.youtube.com"], "www.youtube.com"),
        ("https://www.linkedin.com/feed/", ["linkedin.com"], "linkedin.com"),
        ("https://en.wikipedia.org/wiki/Chromium", ["wikipedia.org"], "wikipedia.org"),
        ("https://mobile.twitter.com/home", ["twitter.com"], "twitter.com"),
        ("https://notlinkedin.com/", ["linkedin.com"], nil),
        ("https://mail.google.com/mail/u/0/", ["www.google.com", "mail.google.com", "docs.google.com"], "mail.google.com"),
        ("https://docs.google.com/document/u/0/", ["www.google.com", "mail.google.com", "docs.google.com"], "docs.google.com"),
        ("https://mail.google.com/mail/u/0/", ["google.com", "mail.google.com"], "mail.google.com"),
        ("https://news.google.com/", ["google.com", "mail.google.com"], "google.com"),
        ("https://EN.Wikipedia.org/wiki/Chromium", ["wikipedia.org", "en.wikipedia.org"], "en.wikipedia.org"),
        ("https://m.en.wikipedia.org/wiki/Chromium", ["wikipedia.org", "en.wikipedia.org"], "en.wikipedia.org"),
        ("https://minecraft.wiki/", ["wiki"], nil),
        ("https://spotify.com/", ["open.spotify.com"], "open.spotify.com"),
        ("parc://www.youtube.com/", ["www.youtube.com"], nil),
        ("https://www.youtube.com/", [], nil),
    ]

    @Test(arguments: activeCases)
    @MainActor func anOpenWebsiteOffersItsBestActiveTemplate(address: String, hosts: [String], expected: String?) throws {
        let fixture = try Fixture(query: "", address: address)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish(scopes: hosts.map { ["host": $0] })
        #expect(fixture.offeredSite() == expected.map { "Search " + $0 })
    }

    @Test(arguments: [
        ("https://gitlab.com/gitlab-org/gitlab", true), ("https://www.gitlab.com/", true),
        ("https://GitLab.com/explore", true), ("https://docs.gitlab.com/", false),
        ("https://about.gitlab.com.evil.example/", false), ("https://notgitlab.com/", false),
        ("https://evil.example/gitlab.com", false),
    ])
    @MainActor func learnedSearchStaysWithItsOwnSite(address: String, offers: Bool) throws {
        let fixture = try Fixture(query: "", address: address)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish(scopes: [["host": "gitlab.com", "learned": true]])
        #expect(fixture.offeredSite() == (offers ? "Search gitlab.com" : nil))
    }

    @Test @MainActor func anActiveTemplateWinsOverALearnedSearch() throws {
        let fixture = try Fixture(query: "", address: "https://docs.github.com/en")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish(scopes: [["host": "docs.github.com", "learned": true], ["host": "github.com"]])
        #expect(fixture.offeredSite() == "Search github.com")
    }

    @Test(arguments: [false, true])
    @MainActor func aNativeSearchNeedsAnExplicitKeywordOffer(explicit: Bool) throws {
        let fixture = try Fixture(query: "music")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        var scope: [String: Any] = ["host": "www.youtube.com", "name": "YouTube"]
        if explicit { scope["result"] = 0 }
        fixture.publish(query: "music", scopes: [scope], results: [
            ["url": "https://www.youtube.com/results?search_query=music", "title": "music", "search": true],
        ])
        #expect(fixture.offeredSite() == (explicit ? "Search YouTube" : nil))
    }

    @Test(arguments: [false, true])
    @MainActor func anExtensionScopeRequiresAnAvailableOwner(allowsExtension: Bool) throws {
        let fixture = try Fixture(query: "extension", allowsExtension: allowsExtension)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish(query: "extension", scopes: [["host": "", "name": "Extension Finder", "extension": 0]],
                        extensions: [["title": "Extension search"]])
        #expect(fixture.offeredSite() == (allowsExtension ? "Search Extension Finder" : nil))
    }

    @Test @MainActor func unclassifiedTextDoesNotAcquireAWebsiteOffer() throws {
        let fixture = try Fixture(query: "youtube.com")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish(query: "youtube.com", scopes: [["host": "youtube.com"]])
        #expect(fixture.offeredSite() == nil)
    }
}

extension SiteSearchOfferTests {
    @Test(arguments: [false, true])
    @MainActor func aPublishedWebsiteCanOfferItsMatchingSearch(learned: Bool) throws {
        let fixture = try Fixture(query: "gitlab.com")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish(query: "gitlab.com", scopes: [["host": "gitlab.com", "learned": learned]],
                        results: [["url": "https://gitlab.com/explore", "title": "GitLab"]])
        #expect(fixture.offeredSite() == "Search gitlab.com")
    }

    @Test @MainActor func aRecentPageCanOfferItsMatchingSearch() throws {
        let fixture = try Fixture(query: "")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.bar.updateRecentPages([("https://www.youtube.com/watch?v=123", "Video")])
        fixture.publish(scopes: [["host": "www.youtube.com", "name": "YouTube"]])
        #expect(fixture.offeredSite() == "Search YouTube")
    }

    @Test @MainActor func withdrawingTheOnlyActiveTemplateRemovesTheOffer() throws {
        let fixture = try Fixture(query: "", address: "https://www.youtube.com/")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish(scopes: [["host": "www.youtube.com", "name": "YouTube"]])
        try #require(fixture.offeredSite() == "Search YouTube")
        fixture.publish(scopes: [])
        #expect(fixture.offeredSite() == nil)
    }

    @Test @MainActor func aPreviousPublicationCannotOfferItsSiteAfterASearch() throws {
        let fixture = try Fixture(query: "youtube")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish(query: "youtube", scopes: [["host": "www.youtube.com", "name": "YouTube"]],
                        results: [["url": "https://www.youtube.com/", "title": "YouTube"]])
        try #require(fixture.offeredSite() == "Search YouTube")
        fixture.publish(query: "youtube", scopes: [["host": "www.youtube.com", "name": "YouTube"]],
                        results: [["url": "https://www.youtube.com/results?search_query=youtube",
                                   "search": true, "title": "youtube"]])
        #expect(fixture.offeredSite() == nil)
    }
}
