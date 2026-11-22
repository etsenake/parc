import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor
struct BrowserStoreNavigationTests {
    @Test static func todayNavigationPublishesCompleteTabMetadataAndHistoryOnce() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            var publications: [BrowserState] = []
            let subscription = store.statePublisher.dropFirst().sink { publications.append($0) }
            store.updateTab(id, title: "Destination", url: "https://example.test/destination")
            guard let first = publications.first, let tab = first.tabs.first(where: { $0.id == id }) else {
                throw BrowserStoreTestsSupport.Failure(description: "Metadata callback did not publish the tab")
            }
            #expect(tab.title == "Destination" && tab.savedTitle == tab.title &&
                tab.url == "https://example.test/destination" && tab.savedURL == tab.url, "First publication contains the complete Today tab metadata")
            #expect(first.history.last?.url == tab.url && first.history.last?.title == tab.title, "History and metadata publish together")
            #expect(publications.count == 1, "Metadata publishes once; identical changed() selection rewrite does not fan out again")
            withExtendedLifetime(subscription) {}
        }
    }

    @Test static func aRepeatedRecentURLUpdatesTheExistingHistoryTitle() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            store.updateTab(id, title: "Destination", url: "https://example.test/destination")
            store.updateTab(id, title: "Updated", url: "https://example.test/destination")
            #expect(store.state.history.filter { $0.url == "https://example.test/destination" }.count == 1 && store.state.history.last?.title == "Updated", "Repeated recent URL updates the existing history title")
        }
    }

    @Test static func aHistoryTitleUpdateKeepsTheChromeAndSidebarLayouts() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            store.updateTab(id, title: "Destination", url: "https://example.test/destination")
            let first = store.state
            store.updateTab(id, title: "Updated", url: "https://example.test/destination")
            let afterTitle = store.state
            #expect(afterTitle.preservesChromeLayout(relativeTo: first), "Title and history ticks keep sidebar membership and selection")
            #expect(afterTitle.preservesSidebarOutline(relativeTo: first), "Title ticks keep sidebar outline membership")
        }
    }

    @Test static func unchangedAndEmptyTitlesDoNotPublish() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            store.updateTab(id, title: "Destination", url: "https://example.test/destination")
            store.updateTab(id, title: "Updated", url: "https://example.test/destination")
            var publications: [BrowserState] = []
            let subscription = store.statePublisher.dropFirst().sink { publications.append($0) }
            let published = publications.count
            store.updateTab(id, title: "Updated")
            store.updateTab(id, title: "", url: "https://example.test/destination")
            #expect(publications.count == published && store.state.tabs.first { $0.id == id }?.title == "Updated", "Unchanged title and empty title do not copy or publish BrowserState")
            withExtendedLifetime(subscription) {}
        }
    }

    @Test static func aCustomTitleChangesChromeWithoutRebuildingTheSidebar() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            let beforeCustom = store.state
            guard let expected = beforeCustom.tabs.first(where: { $0.id == id }) else {
                throw BrowserStoreTestsSupport.Failure(description: "Expected tab missing before customTitle")
            }
            _ = try store.saveSidebarTitle(expected, title: "Pinned name")
            #expect(store.state.preservesSidebarOutline(relativeTo: beforeCustom), "customTitle keeps outline membership for live cell patch")
            #expect(!store.state.preservesChromeLayout(relativeTo: beforeCustom), "customTitle is still a chrome-layout change for window-level live")
        }
    }

    @Test static func aDownloadChangesChromeWithoutRebuildingTheSidebar() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_000)
            let store = try BrowserStore(directory: directory, now: { now })
            _ = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            let beforeDownload = store.state
            store.recordDownload(["id": "outline-skip-download", "name": "file.pdf", "isComplete": true])
            #expect(store.state.preservesSidebarOutline(relativeTo: beforeDownload), "Download ticks keep outline membership so sidebar skips row rebuild")
            #expect(!store.state.preservesChromeLayout(relativeTo: beforeDownload), "Download ticks remain chrome-layout changes for window-level live")
        }
    }

    @Test static func openingAnotherTabChangesBothLayouts() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            let afterOutlineStable = store.state
            let extra = store.openResolvedURL(URL(string: "https://example.test/other")!, kind: .today)
            #expect(!store.state.preservesChromeLayout(relativeTo: afterOutlineStable) && extra != id, "A new tab is a chrome-layout change")
            #expect(!store.state.preservesSidebarOutline(relativeTo: afterOutlineStable), "A new tab is an outline membership change")
        }
    }

    @Test static func switchingEaselDocumentsChangesBothLayouts() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            let easelA = InternalPage.easel(UUID()).urlString
            let easelB = InternalPage.easel(UUID()).urlString
            store.updateTab(id, url: easelA)
            let afterEaselA = store.state
            store.updateTab(id, url: easelB)
            #expect(!store.state.preservesChromeLayout(relativeTo: afterEaselA), "A different Easel document is a chrome-layout change")
            #expect(!store.state.preservesSidebarOutline(relativeTo: afterEaselA), "A different Easel document is an outline membership change")
        }
    }

    @Test static func renamingTheSameEaselKeepsBothLayouts() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            let easelB = InternalPage.easel(UUID()).urlString
            store.updateTab(id, url: easelB)
            let afterEaselB = store.state
            store.updateTab(id, title: "Canvas")
            #expect(store.state.preservesChromeLayout(relativeTo: afterEaselB), "Title on the same Easel keeps layout")
            #expect(store.state.preservesSidebarOutline(relativeTo: afterEaselB), "Title on the same Easel keeps outline membership")
        }
    }

    @Test static func navigationPreservesTheSavedPinDestination() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let pinned = store.openResolvedURL(URL(string: "https://example.test/home")!, kind: .pinned)
            store.updateTab(pinned, title: "Away", url: "https://example.test/away")
            let pin = store.state.tabs.first { $0.id == pinned }!
            #expect(pin.savedURL == "https://example.test/home" && pin.url == "https://example.test/away", "Metadata updates preserve a saved pin destination")
        }
    }

    @Test static func privateNavigationUpdatesMetadataWithoutRecordingHistory() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let privateStore = BrowserStore(privateParentProfileID: store.activeSpace.profileID,
                engineProfilePath: "/disposable", directory: directory, settings: store.state.settings, now: { now })
            let privateID = privateStore.openResolvedURL(URL(string: "https://example.test/private")!, kind: .today)
            privateStore.updateTab(privateID, title: "Private", url: "https://example.test/private-next")
            #expect(privateStore.state.history.isEmpty && privateStore.state.tabs.first { $0.id == privateID }?.savedTitle == "Private", "Private metadata stays ephemeral and creates no history")
        }
    }

    @Test static func blankInputDoesNotNavigate() {
        #expect(NavigationInput.resolve("   ") == nil, "Blank input must not navigate")
    }

    @Test static func anExplicitAddressPreservesItsPathQueryAndFragment() {
        let direct = NavigationInput.resolve(" https://example.org/path?a=1#section ")
        #expect(direct?.absoluteString == "https://example.org/path?a=1#section", "An explicit HTTPS address must preserve its path, query, and fragment")
    }

    @Test static func aBareDomainUsesHTTPS() {
        let domain = NavigationInput.resolve("example.org/reference")
        #expect(domain?.scheme == "https" && domain?.host == "example.org"
                   && domain?.path == "/reference", "A bare domain must navigate over HTTPS")
    }

    @Test static func searchEncodingRoundTripsUnicodeAndReservedCharacters() throws {
        let query = "stars & galaxies #1 + café / Δ"
        guard let url = NavigationInput.resolve(query),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw BrowserStoreTestsSupport.Failure(description: "Search text did not produce a URL")
        }
        #expect(components.host == "duckduckgo.com", "Search must use the configured search engine")
        #expect(components.fragment == nil, "A search hash must remain part of the query")
        #expect(components.queryItems?.filter { $0.name == "q" }.count == 1, "Search punctuation must not inject another query parameter")
        #expect(components.queryItems?.first { $0.name == "q" }?.value == query, "Search encoding must round-trip Unicode and reserved characters")
    }
}
