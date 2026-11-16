import Foundation

@main struct WhatsNewPageTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ reason: String) { checks += 1; precondition(value(), reason) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whats-new-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func page(in app: String, identifier: String?) -> URL {
            let contents = root.appendingPathComponent(app).appendingPathComponent("Contents")
            try! FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            if let identifier {
                precondition((["CFBundleIdentifier": identifier] as NSDictionary)
                    .write(to: contents.appendingPathComponent("Info.plist"), atomically: true))
            }
            return contents.appendingPathComponent("Resources/WhatsNew.html")
        }
        let running = root.appendingPathComponent("Parc Dev.app")
        let runningPage = page(in: "Parc Dev.app", identifier: "org.parc.Browser.dev").absoluteString
        let older = page(in: "Parc 1.0.app", identifier: "org.parc.Browser").absoluteString
        let other = page(in: "Other.app", identifier: "com.example.Other").absoluteString
        let unidentified = page(in: "Unidentified.app", identifier: nil).absoluteString
        let removed = root.appendingPathComponent("Removed.app/Contents/Resources/WhatsNew.html").absoluteString
        let otherFile = URL(string: older)!.deletingLastPathComponent().appendingPathComponent("Other.html").absoluteString
        let spelled = URL(string: runningPage)!.deletingLastPathComponent().absoluteString + "./WhatsNew.html"
        let range = "#from=1.7.0&to=1.9.0"

        expect(WhatsNewPage.address == "parc://whats-new/", "What's New has its own internal address")
        for address in [runningPage, spelled, runningPage + range, older, older + range] {
            expect(WhatsNewPage.isBundledFile(address, running: running), "A Parc bundle's page file: \(address)")
        }
        for address in [other, unidentified, removed, otherFile, "https://parc.example/WhatsNew.html",
                        "file:///Users/me/WhatsNew.html", "parc://note/" + UUID().uuidString, WhatsNewPage.address,
                        WhatsNewPage.address + range, "", "about:blank"] {
            expect(!WhatsNewPage.isBundledFile(address, running: running), "Not a Parc bundle's page file: \(address)")
            expect(WhatsNewPage.relocated(address, running: running) == address, "Other addresses stay as saved: \(address)")
        }

        expect(WhatsNewPage.relocated(runningPage, running: running) == WhatsNewPage.address,
               "This build's page file opens at the internal address")
        expect(WhatsNewPage.relocated(spelled, running: running) == WhatsNewPage.address,
               "Another spelling of this build's page file opens at the internal address")
        expect(WhatsNewPage.relocated(older, running: running) == WhatsNewPage.address,
               "An earlier Parc install's page file opens at the internal address")
        expect(WhatsNewPage.relocated(runningPage + range, running: running) == WhatsNewPage.address + range,
               "A saved update range survives the move")

        let script = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../Sources/WhatsNew/WhatsNew.js"), encoding: .utf8)
        let literal = try NSRegularExpression(pattern: #"/(\^#from=.*?\$)/"#)
        let match = literal.firstMatch(in: script, range: NSRange(script.startIndex..., in: script))
        expect(match != nil, "WhatsNew.js still reads the update range with its from/to pattern")
        let pageRange = try NSRegularExpression(pattern: match.map { (script as NSString).substring(with: $0.range(at: 1)) } ?? "(?!)")
        func rangeOnPage(_ address: String) -> [String]? {
            guard let url = URL(string: address), url.host == "whats-new", url.path == "/" else { return nil }
            let hash = url.fragment.map { "#" + $0 } ?? ""
            guard let found = pageRange.firstMatch(in: hash, range: NSRange(hash.startIndex..., in: hash)) else { return nil }
            return (1..<found.numberOfRanges).map { (hash as NSString).substring(with: found.range(at: $0)) }
        }
        let update = WhatsNewPage.address(range: "from=2.5.1&to=2.6.0")
        expect(update == "parc://whats-new/#from=2.5.1&to=2.6.0", "See What's New carries the update after the page, not in its path")
        expect(rangeOnPage(update) == ["2.5.1", "2.6.0"], "The page reads the update's from and to")
        expect(WhatsNewPage.address(range: nil) == WhatsNewPage.address && rangeOnPage(WhatsNewPage.address) == nil,
               "Release Notes opens the plain page")
        for shown in ["chrome://whats-new/#from=2.5.1&to=2.6.0", "CHROME://whats-new/#from=2.5.1&to=2.6.0"] {
            expect(BrowserInternalURL.publicString(shown) == update, "The engine's own address comes back as parc://: \(shown)")
        }
        for broken in ["parc://whats-new/%23from=2.5.1&to=2.6.0", "parc://whats-new/from=2.5.1&to=2.6.0",
                       "parc://whats-new/?from=2.5.1&to=2.6.0", "parc://whats-new/#from=2.5.1"] {
            expect(rangeOnPage(broken) == nil, "The check bites: a range outside the page's fragment never reaches it: \(broken)")
        }
        expect(BrowserInternalURL.publicString("https://parc.example/#from=2.5.1&to=2.6.0") == "https://parc.example/#from=2.5.1&to=2.6.0",
               "Web pages keep their own address")

        let directory = root.appendingPathComponent("Profile")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
        let restored = store.state.tabs
        expect(restored.map(\.url) == [WhatsNewPage.address + range, WhatsNewPage.address, web, other,
                                        WhatsNewPage.address + range, WhatsNewPage.address + range, "parc://whats-new"],
               "Restored tabs open What's New at its internal address")
        expect(restored.map(\.savedURL) == [WhatsNewPage.address + range, WhatsNewPage.address, WhatsNewPage.address, other,
                                             WhatsNewPage.address + range, WhatsNewPage.address + range, "parc://whats-new"],
               "Pinned What's New tabs reset to the internal address")
        expect(!restored.contains { $0.url.contains("WhatsNew.html") && $0.url != other },
               "No restored What's New tab keeps a bundle path")
        expect(restored.allSatisfy { !$0.url.lowercased().hasPrefix("chrome:") && !$0.savedURL.lowercased().hasPrefix("chrome:") },
               "No restored What's New tab shows the engine's address")
        expect(restored.compactMap { rangeOnPage($0.url) }.count == 3, "Restored update ranges still reach the page")

        let opened = store.openResolvedURL(URL(string: update)!)
        expect(store.state.tab(opened)?.url == update, "A new What's New tab keeps the update's range")
        let visits = store.state.history
        store.updateTab(opened, title: "whats-new", url: "chrome://whats-new/#from=2.5.1&to=2.6.0")
        expect(store.state.tab(opened)?.url == update && store.state.tab(opened)?.savedURL == update,
               "A load or failed load the engine reports at chrome:// shows and copies as parc://")
        expect(store.state.history == visits, "What's New never enters History")
        print("What's New page: \(checks) checks passed")
    }
}
