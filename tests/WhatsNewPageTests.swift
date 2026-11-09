import Foundation

@main struct WhatsNewPageTests {
    static func main() {
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
        let running = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/WhatsNew.html")
        let current = page(in: "Parc.app", identifier: "org.parc.Browser")
        let older = page(in: "Parc 1.0.app", identifier: "org.parc.Browser").absoluteString
        let other = page(in: "Other.app", identifier: "com.example.Other").absoluteString
        let unidentified = page(in: "Unidentified.app", identifier: nil).absoluteString
        let removed = root.appendingPathComponent("Removed.app/Contents/Resources/WhatsNew.html").absoluteString

        for address in [running.absoluteString, running.deletingLastPathComponent().absoluteString + "./WhatsNew.html"] {
            expect(WhatsNewPage.matches(address), "The running app's page is What's New: \(address)")
            expect(WhatsNewPage.presented(address).isEmpty, "What's New has no address to show: \(address)")
        }
        for address in [older, other, unidentified, current.absoluteString, "https://parc.example/WhatsNew.html",
                        "file:///Users/me/WhatsNew.html", "parc://note/" + UUID().uuidString, "", "about:blank"] {
            expect(!WhatsNewPage.matches(address), "Not this app's What's New: \(address)")
            expect(WhatsNewPage.presented(address) == address, "Other addresses are shown as they are: \(address)")
        }

        expect(WhatsNewPage.relocated(older, to: current) == current.absoluteString, "An earlier Parc install's page opens this build's")
        expect(WhatsNewPage.relocated(other, to: current) == other, "Another app's page is not relocated")
        let otherFile = URL(string: older)!.deletingLastPathComponent().appendingPathComponent("Other.html").absoluteString
        expect(WhatsNewPage.relocated(otherFile, to: current) == otherFile, "Another file in a Parc bundle is not relocated")
        expect(WhatsNewPage.relocated(unidentified, to: current) == unidentified, "A bundle without Parc's identifier is not relocated")
        expect(WhatsNewPage.relocated(removed, to: current) == removed, "A removed bundle is not known to be Parc")
        let spelled = current.deletingLastPathComponent().absoluteString + "./WhatsNew.html"
        expect(WhatsNewPage.relocated(spelled, to: current) == spelled, "This build's page keeps the engine's spelling")
        expect(WhatsNewPage.relocated(older, to: nil) == older, "A build without the page keeps the saved address")
        expect(WhatsNewPage.relocated("https://parc.example/", to: current) == "https://parc.example/", "Web pages are not relocated")

        let now = Date(), profile = UUID(), space = UUID()
        func tab(_ url: String, _ title: String) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space, profileID: profile, url: url, title: title,
                       kind: .today, createdAt: now, lastAccessed: now, savedURL: url, savedTitle: title)
        }
        var archived = [tab(running.absoluteString, ""), tab("https://parc.example/", "Parc")]
        for index in archived.indices { archived[index].archivedAt = now }
        let item = BrowserArchivedItem(tabs: archived)
        expect(item.urls == ["", "https://parc.example/"], "The Archive shows no address for What's New")
        expect(item.title == " · Parc", "An untitled What's New tab does not fall back to its address")
        print("What's New page: \(checks) checks passed")
    }
}
