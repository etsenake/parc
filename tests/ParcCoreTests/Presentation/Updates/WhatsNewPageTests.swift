import Foundation
import Testing
@testable import ParcCore

struct WhatsNewPageTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("whats-new-\(UUID().uuidString)")
    let range = "#from=1.7.0&to=1.9.0"
    let update = "parc://whats-new/#from=2.5.1&to=2.6.0"

    var running: URL { root.appendingPathComponent("Parc Dev.app") }

    private func page(in app: String, identifier: String?) throws -> URL {
        let contents = root.appendingPathComponent(app).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        if let identifier {
            let written = (["CFBundleIdentifier": identifier] as NSDictionary)
                .write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
            try #require(written)
        }
        return contents.appendingPathComponent("Resources/WhatsNew.html")
    }

    private func runningPage() throws -> String { try page(in: "Parc Dev.app", identifier: "org.parc.Browser.dev").absoluteString }
    private func olderPage() throws -> String { try page(in: "Parc 1.0.app", identifier: "org.parc.Browser").absoluteString }
    private func otherPage() throws -> String { try page(in: "Other.app", identifier: "com.example.Other").absoluteString }

    private func spelledRunningPage() throws -> String {
        try URL(string: runningPage())!.deletingLastPathComponent().absoluteString + "./WhatsNew.html"
    }

    private func rangeOnPage(_ address: String) -> String? {
        guard let url = URL(string: address), url.host == "whats-new", url.path == "/" else { return nil }
        return url.fragment
    }

    @Test func whatsNewHasItsOwnInternalAddress() {
        #expect(WhatsNewPage.address == "parc://whats-new/")
    }

    enum BundledAddress: CaseIterable, Sendable {
        case running, alternateSpelling, runningWithRange, previous, previousWithRange
    }

    @Test(arguments: BundledAddress.allCases)
    func aParcBundlesPageFileIsRecognised(example: BundledAddress) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let address: String
        switch example {
        case .running: address = try runningPage()
        case .alternateSpelling: address = try spelledRunningPage()
        case .runningWithRange: address = try runningPage() + range
        case .previous: address = try olderPage()
        case .previousWithRange: address = try olderPage() + range
        }
        #expect(WhatsNewPage.isBundledFile(address, running: running))
    }

    enum OtherBundleAddress: CaseIterable, Sendable {
        case otherApp, noIdentifier, missingApp, differentFile
    }

    @Test(arguments: OtherBundleAddress.allCases)
    func otherBundleFilesStayAsSaved(example: OtherBundleAddress) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let address: String
        switch example {
        case .otherApp: address = try otherPage()
        case .noIdentifier: address = try page(in: "Unidentified.app", identifier: nil).absoluteString
        case .missingApp: address = root.appendingPathComponent("Removed.app/Contents/Resources/WhatsNew.html").absoluteString
        case .differentFile:
            let older = try #require(URL(string: olderPage()))
            address = older.deletingLastPathComponent().appendingPathComponent("Other.html").absoluteString
        }
        #expect(!WhatsNewPage.isBundledFile(address, running: running))
        #expect(WhatsNewPage.relocated(address, running: running) == address)
    }

    @Test(arguments: ["https://parc.example/WhatsNew.html", "file:///Users/me/WhatsNew.html",
                      "parc://note/8FFEB1BA-5B65-49C3-B581-C23946BF0B43", "parc://whats-new/",
                      "parc://whats-new/#from=1.7.0&to=1.9.0", "", "about:blank"])
    func otherAddressesStayAsSaved(address: String) {
        #expect(!WhatsNewPage.isBundledFile(address, running: running))
        #expect(WhatsNewPage.relocated(address, running: running) == address)
    }

    @Test func thisBuildsPageFileOpensAtTheInternalAddress() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(WhatsNewPage.relocated(try runningPage(), running: running) == WhatsNewPage.address)
    }

    @Test func anotherSpellingOfThisBuildsPageFileOpensAtTheInternalAddress() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try runningPage()
        #expect(WhatsNewPage.relocated(try spelledRunningPage(), running: running) == WhatsNewPage.address)
    }

    @Test func anEarlierInstallsPageFileOpensAtTheInternalAddress() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try runningPage()
        #expect(WhatsNewPage.relocated(try olderPage(), running: running) == WhatsNewPage.address)
    }

    @Test func aSavedUpdateRangeSurvivesTheMove() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let runningPage = try runningPage()
        #expect(WhatsNewPage.relocated(runningPage + range, running: running) == WhatsNewPage.address + range)
    }

    @Test func seeWhatsNewCarriesTheUpdateAfterThePageNotInItsPath() {
        let address = WhatsNewPage.address(range: "from=2.5.1&to=2.6.0")
        #expect(address == update)
        #expect(rangeOnPage(address) == "from=2.5.1&to=2.6.0")
    }

    @Test func releaseNotesOpensThePlainPage() {
        #expect(WhatsNewPage.address(range: nil) == WhatsNewPage.address)
        #expect(rangeOnPage(WhatsNewPage.address) == nil)
    }

    @Test(arguments: ["chrome://whats-new/#from=2.5.1&to=2.6.0", "CHROME://whats-new/#from=2.5.1&to=2.6.0"])
    func theEnginesOwnAddressComesBackAsParc(shown: String) {
        #expect(BrowserInternalURL.publicString(shown) == update)
    }

    @Test func webPagesKeepTheirOwnAddress() {
        let web = "https://parc.example/#from=2.5.1&to=2.6.0"
        #expect(BrowserInternalURL.publicString(web) == web)
    }

    @MainActor private func restoredStore() throws -> (store: BrowserStore, restored: [BrowserTab], web: String, other: String) {
        let directory = root.appendingPathComponent("Profile")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let older = try olderPage(), other = try otherPage()
        var state = BrowserState.initial()
        let now = Date(timeIntervalSince1970: 1_700_000_000), profile = state.profiles[0].id, space = state.spaces[0].id
        func tab(_ url: String, _ title: String, kind: TabKind, saved: String? = nil) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space, profileID: profile, url: url, title: title,
                       kind: kind, createdAt: now, lastAccessed: now, savedURL: saved ?? url, savedTitle: title)
        }
        let web = "https://parc.example/"
        state.tabs = [tab(older + range, "What's New in Parc", kind: .today), tab(older, "What's New in Parc", kind: .pinned),
                      tab(web, "Parc", kind: .pinned, saved: older), tab(other, "Other", kind: .today),
                      tab("chrome://whats-new/" + range, "What's New in Parc", kind: .today),
                      tab(WhatsNewPage.address + range, "What's New in Parc", kind: .today),
                      tab("parc://whats-new", "What's New in Parc", kind: .pinned)]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory)
        return (store, store.state.tabs, web, other)
    }

    @Test @MainActor func restoredTabsOpenWhatsNewAtItsInternalAddress() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try restoredStore()
        #expect(fixture.restored.map(\.url) == [WhatsNewPage.address + range, WhatsNewPage.address, fixture.web, fixture.other,
                                                WhatsNewPage.address + range, WhatsNewPage.address + range, "parc://whats-new"])
    }

    @Test @MainActor func pinnedWhatsNewTabsResetToTheInternalAddress() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try restoredStore()
        #expect(fixture.restored.map(\.savedURL) == [WhatsNewPage.address + range, WhatsNewPage.address, WhatsNewPage.address,
                                                     fixture.other, WhatsNewPage.address + range, WhatsNewPage.address + range,
                                                     "parc://whats-new"])
    }

    @Test @MainActor func noRestoredWhatsNewTabKeepsABundlePathOrTheEnginesAddress() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try restoredStore()
        #expect(!fixture.restored.contains { $0.url.contains("WhatsNew.html") && $0.url != fixture.other })
        #expect(fixture.restored.allSatisfy { !$0.url.lowercased().hasPrefix("chrome:") && !$0.savedURL.lowercased().hasPrefix("chrome:") })
    }

    @Test @MainActor func restoredUpdateRangesStillReachThePage() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try restoredStore()
        #expect(fixture.restored.compactMap { rangeOnPage($0.url) }.count == 3)
    }

    @Test @MainActor func aNewWhatsNewTabKeepsTheUpdatesRange() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try restoredStore().store
        let opened = store.openResolvedURL(URL(string: update)!)
        #expect(store.state.tab(opened)?.url == update)
    }

    @Test @MainActor func aLoadTheEngineReportsAtChromeShowsAndCopiesAsParcAndStaysOutOfHistory() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try restoredStore().store
        let opened = store.openResolvedURL(URL(string: update)!)
        let visits = store.state.history
        store.updateTab(opened, title: "whats-new", url: "chrome://whats-new/#from=2.5.1&to=2.6.0")
        #expect(store.state.tab(opened)?.url == update && store.state.tab(opened)?.savedURL == update)
        #expect(store.state.history == visits)
    }
}
