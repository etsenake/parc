import Foundation

@main
struct EaselWebItemChromeTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
    static let layout = EaselCaptureLayout(viewport: .init(x: 1280, y: 800), scroll: .init(x: 0, y: 420),
                                           region: .init(x: 100, y: 60, width: 640, height: 360))

    static func card(layout: EaselCaptureLayout? = layout, live: Bool? = nil, url: String = "https://www.example.com/a",
                     captured: Date? = nil, text: String = "") -> EaselItem {
        EaselItem(kind: .webCard, frame: .init(x: 40, y: 40, width: 320, height: 180), text: text, url: url, assetID: "asset",
                  capturedAt: captured, captureLayout: layout, liveCapture: live)
    }

    @MainActor static func main() {
        exitOnFailure {
            makeLiveDecision()
            labels()
            headerPlacement()
            statusText()
            try geometryPersists()
            print("EaselWebItemChromeTests: \(assertions) assertions passed")
        }
    }

    @MainActor static func makeLiveDecision() {
        expect(EaselWebItemChrome.canMakeLive(card()), "A card with saved region geometry can go live")
        expect(EaselWebItemChrome.state(of: card()) == .snapshot(canGoLive: true), "It is a live-capable snapshot")
        expect(!EaselWebItemChrome.canMakeLive(card(layout: nil)), "Full-page, cropped, annotated and old cards cannot")
        expect(EaselWebItemChrome.state(of: card(layout: nil)) == .snapshot(canGoLive: false), "They are snapshot-only")
        var broken = layout; broken.region.width = 0
        expect(!EaselWebItemChrome.canMakeLive(card(layout: broken)), "Invalid geometry never offers Make live")
        expect(!EaselWebItemChrome.canMakeLive(card(url: "file:///tmp/a.html")), "Only web addresses can go live")
        expect(EaselWebItemChrome.state(of: card(live: true)) == .live, "A live card reports Live")
        expect(EaselWebItemChrome.isSnapshot(card()) && EaselWebItemChrome.isSnapshot(card(layout: nil)), "Every captured image gets the snapshot header")
        expect(!EaselWebItemChrome.isSnapshot(card(live: true)), "A live card's header belongs to its page")
        expect(EaselWebItemChrome.canMakeLive(card(live: true)), "A live card can return and go live again")
        var noImage = card(); noImage.assetID = nil
        expect(EaselWebItemChrome.state(of: noImage) == nil, "A card without an image has no snapshot chrome")
        let browser = EaselItem(kind: .browser, frame: .init(x: 0, y: 0, width: 400, height: 300), url: "https://example.org")
        expect(EaselWebItemChrome.state(of: browser) == .page, "Webpage objects are plain live pages")
        expect(EaselWebItemChrome.badge(for: browser) == nil, "Webpage objects show no snapshot badge")
    }

    @MainActor static func labels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        let now = Date(timeIntervalSince1970: 1_763_640_000)
        func badge(_ item: EaselItem) -> String? { EaselWebItemChrome.badge(for: item, now: now, calendar: calendar, locale: locale) }
        expect(badge(card(captured: now)) == "Snapshot · captured today", "Same-day capture says today")
        expect(badge(card(captured: now.addingTimeInterval(-86_400))) == "Snapshot · captured yesterday", "Previous day says yesterday")
        expect(badge(card(captured: now.addingTimeInterval(-86_400 * 10))) == "Snapshot · captured Nov 10", "Same year shows month and day")
        expect(badge(card(captured: now.addingTimeInterval(-86_400 * 400))) == "Snapshot · captured Oct 16, 2024", "Older captures show the year")
        expect(badge(card()) == "Snapshot", "No capture date just says Snapshot")
        expect(badge(card(layout: nil, captured: now)) == "Snapshot only · captured today", "Cards without geometry say Snapshot only")
        expect(badge(card(live: true)) == "Live", "Live cards say Live")
        expect(EaselWebItemChrome.badgeHelp(for: card(layout: nil)) == EaselWebItemChrome.snapshotOnlyHelp, "Snapshot only explains why")
        expect(EaselWebItemChrome.title(for: card(text: "Recipe")) == "Recipe", "Saved page title is the header title")
        expect(EaselWebItemChrome.title(for: card()) == "example.com", "Untitled cards fall back to the host without www")
        expect(EaselWebItemChrome.title(for: card(text: "Recipe"), pageTitle: " Live title ") == "Live title", "A live page title wins")
    }

    @MainActor static func headerPlacement() {
        let visible = EaselRect(x: 0, y: 0, width: 1000, height: 700)
        let item = EaselRect(x: 100, y: 200, width: 400, height: 300)
        let top = EaselWebItemChrome.headerFrame(item: item, visible: visible)
        expect(top.x == 100 && top.y == 200 && top.width == 400 && top.height == 38, "Header sits inside the card's top edge")
        let scrolled = EaselWebItemChrome.headerFrame(item: item, visible: .init(x: 0, y: 260, width: 1000, height: 700))
        expect(scrolled.y == 260, "Header stays pinned to the visible top while the card is partly scrolled away")
        let nearlyGone = EaselWebItemChrome.headerFrame(item: item, visible: .init(x: 0, y: 480, width: 1000, height: 700))
        expect(nearlyGone.y == 462, "Header never leaves its card")
        let atTop = EaselWebItemChrome.headerFrame(item: .init(x: 10, y: 0, width: 400, height: 300), visible: visible)
        expect(atTop.y == 0, "A card at the canvas top keeps its header visible inside it")
        let short = EaselWebItemChrome.headerFrame(item: .init(x: 100, y: 200, width: 400, height: 20), visible: visible)
        expect(short.y == 162, "A short card carries its header just above it")
        let shortAtTop = EaselWebItemChrome.headerFrame(item: .init(x: 100, y: 10, width: 400, height: 20), visible: visible)
        expect(shortAtTop.y == 30, "A short card at the top carries its header just below it")
        let narrow = EaselWebItemChrome.headerFrame(item: .init(x: 400, y: 200, width: 120, height: 200), visible: visible)
        expect(narrow.width == 320 && narrow.x == 300, "A narrow card's header widens around its centre")
        let narrowAtEdge = EaselWebItemChrome.headerFrame(item: .init(x: 0, y: 200, width: 120, height: 200), visible: visible)
        expect(narrowAtEdge.x == 0, "A widened header stays inside the visible canvas")
    }

    @MainActor static func statusText() {
        expect(EmbeddedPageStatusText.friendly("Loading webpage…", document: "Easel") == "Waking the page up…", "Warm-up matches notes")
        expect(EmbeddedPageStatusText.friendly("This webpage owner is unavailable.", document: "Easel")
            == "Live pages wake up when the Easel is open in a window.", "Unavailable owner names the document")
        expect(EmbeddedPageStatusText.friendly("This webpage owner is unavailable.", document: "note")
            == "Live pages wake up when the note is open in a window.", "Notes keep their wording")
        expect(EmbeddedPageStatusText.friendly("Webpage closed", document: "Easel") == "This page closed. Give it another go?", "Closed page")
        expect(EmbeddedPageStatusText.friendly("Something else", document: "Easel") == "Something else", "Other errors pass through")
    }

    @MainActor static func geometryPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-easel-chrome-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try EaselStore(directory: directory).create()
        let asset = try session.importPNG(png)
        var item = card(captured: Date(timeIntervalSince1970: 1_700_000_000)); item.assetID = asset
        var flat = card(layout: nil); flat.assetID = asset
        try session.perform("Add capture") { $0.items = [item, flat] }
        try session.perform("Make live") { $0.items[0].liveCapture = true }
        try session.perform("Back to snapshot") { $0.items[0].liveCapture = false }
        let reopened = try EaselStore(directory: directory).load(session.document.id)
        let saved = reopened.document.items[0]
        expect(saved.captureLayout == layout, "Capture geometry survives closing and reopening the Easel")
        expect(EaselWebItemChrome.canMakeLive(saved), "A reopened card still offers Make live after going back to its snapshot")
        expect(EaselWebItemChrome.state(of: saved) == .snapshot(canGoLive: true), "A reopened card is a live-capable snapshot")
        expect(EaselWebItemChrome.state(of: reopened.document.items[1]) == .snapshot(canGoLive: false), "Cards without geometry stay snapshot-only")
        let encoded = String(data: try JSONEncoder().encode(saved), encoding: .utf8) ?? ""
        expect(encoded.contains("captureLayout"), "Geometry is written to the document")
    }
}
