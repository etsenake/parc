import Foundation

@main struct WhatsNewPageTests {
    static func main() {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ reason: String) { checks += 1; precondition(value(), reason) }
        let current = URL(fileURLWithPath: "/Applications/Parc.app/Contents/Resources/WhatsNew.html")
        let older = "file:///opt/homebrew/Caskroom/parc/1.0.0/Parc.app/Contents/Resources/WhatsNew.html"
        let renamed = "file:///Users/me/Apps/Parc%202.app/Contents/Resources/WhatsNew.html"

        for page in [current.absoluteString, older, renamed, "file:///Parc.app/Contents/Resources/WhatsNew.html"] {
            expect(WhatsNewPage.matches(page), "Any app bundle's bundled page is What's New: \(page)")
            expect(WhatsNewPage.presented(page).isEmpty, "What's New has no address to show: \(page)")
        }
        for other in ["https://parc.example/WhatsNew.html", "file:///Users/me/WhatsNew.html",
                      "file:///Users/me/Parc/Contents/Resources/WhatsNew.html",
                      "file:///Applications/Parc.app/Contents/Resources/Other.html",
                      "file:///Contents/Resources/WhatsNew.html", "parc://note/" + UUID().uuidString, "", "about:blank"] {
            expect(!WhatsNewPage.matches(other), "Not What's New: \(other)")
            expect(WhatsNewPage.presented(other) == other, "Other addresses are shown as they are: \(other)")
        }

        expect(WhatsNewPage.relocated(older, to: current) == current.absoluteString, "An earlier install's page opens this build's")
        expect(WhatsNewPage.relocated(renamed, to: current) == current.absoluteString, "A renamed app's page opens this build's")
        let spelled = "file:///Applications/Parc.app/Contents/Resources/./WhatsNew.html"
        expect(WhatsNewPage.relocated(spelled, to: current) == spelled, "This build's page keeps the engine's spelling")
        expect(WhatsNewPage.relocated(older, to: nil) == older, "A build without the page keeps the saved address")
        expect(WhatsNewPage.relocated("https://parc.example/", to: current) == "https://parc.example/", "Web pages are not relocated")

        let now = Date(), profile = UUID(), space = UUID()
        func tab(_ url: String, _ title: String) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space, profileID: profile, url: url, title: title,
                       kind: .today, createdAt: now, lastAccessed: now, savedURL: url, savedTitle: title)
        }
        var archived = [tab(older, ""), tab("https://parc.example/", "Parc")]
        for index in archived.indices { archived[index].archivedAt = now }
        let item = BrowserArchivedItem(tabs: archived)
        expect(item.urls == ["", "https://parc.example/"], "The Archive shows no address for What's New")
        expect(item.title == " · Parc", "An untitled What's New tab does not fall back to its address")
        print("What's New page: \(checks) checks passed")
    }
}
