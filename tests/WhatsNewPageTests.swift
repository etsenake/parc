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
                      tab(web, "Parc", kind: .pinned, saved: older), tab(other, "Other", kind: .today)]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        let restored = try BrowserStore(directory: directory).state.tabs
        expect(restored.map(\.url) == [WhatsNewPage.address + range, WhatsNewPage.address, web, other],
               "Restored tabs open What's New at its internal address")
        expect(restored.map(\.savedURL) == [WhatsNewPage.address + range, WhatsNewPage.address, WhatsNewPage.address, other],
               "Pinned What's New tabs reset to the internal address")
        expect(!restored.contains { $0.url.contains("WhatsNew.html") && $0.url != other },
               "No restored What's New tab keeps a bundle path")
        print("What's New page: \(checks) checks passed")
    }
}
