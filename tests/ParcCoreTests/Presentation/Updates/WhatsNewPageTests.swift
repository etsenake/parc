import Foundation
import Testing
@testable import ParcCore

@MainActor
struct WhatsNewPageTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("whats-new-\(UUID().uuidString)")
    let range = "#from=1.7.0&to=1.9.0"
    let update = "parc://whats-new/#from=2.5.1&to=2.6.0"

    var running: URL { root.appendingPathComponent("Parc Dev.app") }

    func page(in app: String, identifier: String?) throws -> URL {
        let contents = root.appendingPathComponent(app).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        if let identifier {
            let written = (["CFBundleIdentifier": identifier] as NSDictionary)
                .write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
            try #require(written)
        }
        return contents.appendingPathComponent("Resources/WhatsNew.html")
    }

    func runningPage() throws -> String { try page(in: "Parc Dev.app", identifier: "org.parc.Browser.dev").absoluteString }
    func olderPage() throws -> String { try page(in: "Parc 1.0.app", identifier: "org.parc.Browser").absoluteString }
    func otherPage() throws -> String { try page(in: "Other.app", identifier: "com.example.Other").absoluteString }

    func spelledRunningPage() throws -> String {
        try URL(string: runningPage())!.deletingLastPathComponent().absoluteString + "./WhatsNew.html"
    }

    func pageRange() throws -> NSRegularExpression {
        let script = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/WhatsNew/WhatsNew.js"), encoding: .utf8)
        let literal = try NSRegularExpression(pattern: #"/(\^#from=.*?\$)/"#)
        let match = try #require(literal.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
                                 "WhatsNew.js still reads the update range with its from/to pattern")
        return try NSRegularExpression(pattern: (script as NSString).substring(with: match.range(at: 1)))
    }

    func rangeOnPage(_ address: String, _ pageRange: NSRegularExpression) -> [String]? {
        guard let url = URL(string: address), url.host == "whats-new", url.path == "/" else { return nil }
        let hash = url.fragment.map { "#" + $0 } ?? ""
        guard let found = pageRange.firstMatch(in: hash, range: NSRange(hash.startIndex..., in: hash)) else { return nil }
        return (1..<found.numberOfRanges).map { (hash as NSString).substring(with: found.range(at: $0)) }
    }

    @Test func whatsNewHasItsOwnInternalAddress() {
        #expect(WhatsNewPage.address == "parc://whats-new/")
    }

    @Test func aParcBundlesPageFileIsRecognised() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let running = running
        let runningPage = try runningPage(), older = try olderPage(), spelled = try spelledRunningPage()
        for address in [runningPage, spelled, runningPage + range, older, older + range] {
            #expect(WhatsNewPage.isBundledFile(address, running: running), "A Parc bundle's page file: \(address)")
        }
    }

    @Test func otherAddressesAreNotABundlesPageFileAndStayAsSaved() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let running = running
        _ = try runningPage()
        let older = try olderPage(), other = try otherPage()
        let unidentified = try page(in: "Unidentified.app", identifier: nil).absoluteString
        let removed = root.appendingPathComponent("Removed.app/Contents/Resources/WhatsNew.html").absoluteString
        let otherFile = URL(string: older)!.deletingLastPathComponent().appendingPathComponent("Other.html").absoluteString
        for address in [other, unidentified, removed, otherFile, "https://parc.example/WhatsNew.html",
                        "file:///Users/me/WhatsNew.html", "parc://note/" + UUID().uuidString, WhatsNewPage.address,
                        WhatsNewPage.address + range, "", "about:blank"] {
            #expect(!WhatsNewPage.isBundledFile(address, running: running), "Not a Parc bundle's page file: \(address)")
            #expect(WhatsNewPage.relocated(address, running: running) == address, "Other addresses stay as saved: \(address)")
        }
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

    @Test func seeWhatsNewCarriesTheUpdateAfterThePageNotInItsPath() throws {
        let pageRange = try pageRange()
        let address = WhatsNewPage.address(range: "from=2.5.1&to=2.6.0")
        #expect(address == update)
        #expect(rangeOnPage(address, pageRange) == ["2.5.1", "2.6.0"])
    }

    @Test func releaseNotesOpensThePlainPage() throws {
        let pageRange = try pageRange()
        #expect(WhatsNewPage.address(range: nil) == WhatsNewPage.address)
        #expect(rangeOnPage(WhatsNewPage.address, pageRange) == nil)
    }

    @Test(arguments: ["chrome://whats-new/#from=2.5.1&to=2.6.0", "CHROME://whats-new/#from=2.5.1&to=2.6.0"])
    func theEnginesOwnAddressComesBackAsParc(shown: String) {
        #expect(BrowserInternalURL.publicString(shown) == update)
    }

    @Test(arguments: ["parc://whats-new/%23from=2.5.1&to=2.6.0", "parc://whats-new/from=2.5.1&to=2.6.0",
                      "parc://whats-new/?from=2.5.1&to=2.6.0", "parc://whats-new/#from=2.5.1"])
    func aRangeOutsideThePagesFragmentNeverReachesIt(broken: String) throws {
        #expect(rangeOnPage(broken, try pageRange()) == nil)
    }

    @Test func webPagesKeepTheirOwnAddress() {
        let web = "https://parc.example/#from=2.5.1&to=2.6.0"
        #expect(BrowserInternalURL.publicString(web) == web)
    }

    func restoredStore() throws -> (store: BrowserStore, restored: [BrowserTab], web: String, other: String) {
        let directory = root.appendingPathComponent("Profile")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let older = try olderPage(), other = try otherPage()
        var state = BrowserState.initial()
        let now = Date(), profile = state.profiles[0].id, space = state.spaces[0].id
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

    @Test func restoredTabsOpenWhatsNewAtItsInternalAddress() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try restoredStore()
        #expect(fixture.restored.map(\.url) == [WhatsNewPage.address + range, WhatsNewPage.address, fixture.web, fixture.other,
                                                WhatsNewPage.address + range, WhatsNewPage.address + range, "parc://whats-new"])
    }

    @Test func pinnedWhatsNewTabsResetToTheInternalAddress() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try restoredStore()
        #expect(fixture.restored.map(\.savedURL) == [WhatsNewPage.address + range, WhatsNewPage.address, WhatsNewPage.address,
                                                     fixture.other, WhatsNewPage.address + range, WhatsNewPage.address + range,
                                                     "parc://whats-new"])
    }

    @Test func noRestoredWhatsNewTabKeepsABundlePathOrTheEnginesAddress() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try restoredStore()
        #expect(!fixture.restored.contains { $0.url.contains("WhatsNew.html") && $0.url != fixture.other })
        #expect(fixture.restored.allSatisfy { !$0.url.lowercased().hasPrefix("chrome:") && !$0.savedURL.lowercased().hasPrefix("chrome:") })
    }

    @Test func restoredUpdateRangesStillReachThePage() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let pageRange = try pageRange()
        let fixture = try restoredStore()
        #expect(fixture.restored.compactMap { rangeOnPage($0.url, pageRange) }.count == 3)
    }

    @Test func aNewWhatsNewTabKeepsTheUpdatesRange() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try restoredStore().store
        let opened = store.openResolvedURL(URL(string: update)!)
        #expect(store.state.tab(opened)?.url == update)
    }

    @Test func aLoadTheEngineReportsAtChromeShowsAndCopiesAsParcAndStaysOutOfHistory() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try restoredStore().store
        let opened = store.openResolvedURL(URL(string: update)!)
        let visits = store.state.history
        store.updateTab(opened, title: "whats-new", url: "chrome://whats-new/#from=2.5.1&to=2.6.0")
        #expect(store.state.tab(opened)?.url == update && store.state.tab(opened)?.savedURL == update)
        #expect(store.state.history == visits)
    }
}
