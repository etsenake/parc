import Foundation
import Testing
@testable import ParcCore

struct EaselWebItemChromeTests {
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
    static let layout = EaselCaptureLayout(viewport: .init(x: 1280, y: 800), scroll: .init(x: 0, y: 420),
                                           region: .init(x: 100, y: 60, width: 640, height: 360))

    static func card(layout: EaselCaptureLayout? = layout, live: Bool? = nil, url: String = "https://www.example.com/a",
                     captured: Date? = nil, text: String = "") -> EaselItem {
        EaselItem(kind: .webCard, frame: .init(x: 40, y: 40, width: 320, height: 180), text: text, url: url, assetID: "asset",
                  capturedAt: captured, captureLayout: layout, liveCapture: live)
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    static let now = Date(timeIntervalSince1970: 1_763_640_000)

    static func badge(_ item: EaselItem) -> String? {
        EaselWebItemChrome.badge(for: item, now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
    }

    static let visible = EaselRect(x: 0, y: 0, width: 1000, height: 700)
    static let headerItem = EaselRect(x: 100, y: 200, width: 400, height: 300)

    @Test func aCardWithSavedRegionGeometryCanGoLive() {
        #expect(EaselWebItemChrome.canMakeLive(Self.card()))
        #expect(EaselWebItemChrome.state(of: Self.card()) == .snapshot(canGoLive: true))
    }

    @Test func fullPageCroppedAnnotatedAndOldCardsCannotGoLive() {
        #expect(!EaselWebItemChrome.canMakeLive(Self.card(layout: nil)))
        #expect(EaselWebItemChrome.state(of: Self.card(layout: nil)) == .snapshot(canGoLive: false))
    }

    @Test func invalidGeometryNeverOffersMakeLive() {
        var broken = Self.layout
        broken.region.width = 0
        #expect(!EaselWebItemChrome.canMakeLive(Self.card(layout: broken)))
    }

    @Test func onlyWebAddressesCanGoLive() {
        #expect(!EaselWebItemChrome.canMakeLive(Self.card(url: "file:///tmp/a.html")))
    }

    @Test func aLiveCardReportsLiveAndCanReturnAndGoLiveAgain() {
        #expect(EaselWebItemChrome.state(of: Self.card(live: true)) == .live)
        #expect(EaselWebItemChrome.canMakeLive(Self.card(live: true)))
    }

    @Test func everyCapturedImageGetsTheSnapshotHeaderAndALiveCardKeepsItsPagesOwn() {
        #expect(EaselWebItemChrome.isSnapshot(Self.card()) && EaselWebItemChrome.isSnapshot(Self.card(layout: nil)))
        #expect(!EaselWebItemChrome.isSnapshot(Self.card(live: true)))
    }

    @Test func aCardWithoutAnImageHasNoSnapshotChrome() {
        var noImage = Self.card()
        noImage.assetID = nil
        #expect(EaselWebItemChrome.state(of: noImage) == nil)
    }

    @Test func webpageObjectsArePlainLivePagesWithNoBadge() {
        let browser = EaselItem(kind: .browser, frame: .init(x: 0, y: 0, width: 400, height: 300), url: "https://example.org")
        #expect(EaselWebItemChrome.state(of: browser) == .page)
        #expect(EaselWebItemChrome.badge(for: browser) == nil)
    }

    @Test func aSameDayCaptureSaysToday() {
        #expect(Self.badge(Self.card(captured: Self.now)) == "Snapshot · captured today")
    }

    @Test func thePreviousDaySaysYesterday() {
        #expect(Self.badge(Self.card(captured: Self.now.addingTimeInterval(-86_400))) == "Snapshot · captured yesterday")
    }

    @Test func theSameYearShowsMonthAndDay() {
        #expect(Self.badge(Self.card(captured: Self.now.addingTimeInterval(-86_400 * 10))) == "Snapshot · captured Nov 10")
    }

    @Test func olderCapturesShowTheYear() {
        #expect(Self.badge(Self.card(captured: Self.now.addingTimeInterval(-86_400 * 400))) == "Snapshot · captured Oct 16, 2024")
    }

    @Test func noCaptureDateJustSaysSnapshot() {
        #expect(Self.badge(Self.card()) == "Snapshot")
    }

    @Test func cardsWithoutGeometrySaySnapshotOnlyAndExplainWhy() {
        #expect(Self.badge(Self.card(layout: nil, captured: Self.now)) == "Snapshot only · captured today")
        #expect(EaselWebItemChrome.badgeHelp(for: Self.card(layout: nil)) == EaselWebItemChrome.snapshotOnlyHelp)
    }

    @Test func liveCardsSayLive() {
        #expect(Self.badge(Self.card(live: true)) == "Live")
    }

    @Test func theSavedPageTitleIsTheHeaderTitle() {
        #expect(EaselWebItemChrome.title(for: Self.card(text: "Recipe")) == "Recipe")
    }

    @Test func untitledCardsFallBackToTheHostWithoutWww() {
        #expect(EaselWebItemChrome.title(for: Self.card()) == "example.com")
    }

    @Test func aLivePageTitleWins() {
        #expect(EaselWebItemChrome.title(for: Self.card(text: "Recipe"), pageTitle: " Live title ") == "Live title")
    }

    @Test func theHeaderSitsInsideTheCardsTopEdge() {
        let top = EaselWebItemChrome.headerFrame(item: Self.headerItem, visible: Self.visible)
        #expect(top.x == 100 && top.y == 200 && top.width == 400 && top.height == 38)
    }

    @Test func theHeaderStaysPinnedToTheVisibleTopWhileTheCardIsPartlyScrolledAway() {
        let scrolled = EaselWebItemChrome.headerFrame(item: Self.headerItem, visible: .init(x: 0, y: 260, width: 1000, height: 700))
        #expect(scrolled.y == 260)
    }

    @Test func theHeaderNeverLeavesItsCard() {
        let nearlyGone = EaselWebItemChrome.headerFrame(item: Self.headerItem, visible: .init(x: 0, y: 480, width: 1000, height: 700))
        #expect(nearlyGone.y == 462)
    }

    @Test func aCardAtTheCanvasTopKeepsItsHeaderVisibleInsideIt() {
        let atTop = EaselWebItemChrome.headerFrame(item: .init(x: 10, y: 0, width: 400, height: 300), visible: Self.visible)
        #expect(atTop.y == 0)
    }

    @Test func aShortCardCarriesItsHeaderJustAboveIt() {
        let short = EaselWebItemChrome.headerFrame(item: .init(x: 100, y: 200, width: 400, height: 20), visible: Self.visible)
        #expect(short.y == 162)
    }

    @Test func aShortCardAtTheTopCarriesItsHeaderJustBelowIt() {
        let shortAtTop = EaselWebItemChrome.headerFrame(item: .init(x: 100, y: 10, width: 400, height: 20), visible: Self.visible)
        #expect(shortAtTop.y == 30)
    }

    @Test func aNarrowCardsHeaderWidensAroundItsCentre() {
        let narrow = EaselWebItemChrome.headerFrame(item: .init(x: 400, y: 200, width: 120, height: 200), visible: Self.visible)
        #expect(narrow.width == 320 && narrow.x == 300)
    }

    @Test func aWidenedHeaderStaysInsideTheVisibleCanvas() {
        let narrowAtEdge = EaselWebItemChrome.headerFrame(item: .init(x: 0, y: 200, width: 120, height: 200), visible: Self.visible)
        #expect(narrowAtEdge.x == 0)
    }

    @Test func warmUpStatusMatchesNotes() {
        #expect(EmbeddedPageStatusText.friendly("Loading webpage…", document: "Easel") == "Waking the page up…")
    }

    @Test func anUnavailableOwnerNamesTheDocument() {
        #expect(EmbeddedPageStatusText.friendly("This webpage owner is unavailable.", document: "Easel")
            == "Live pages wake up when the Easel is open in a window.")
        #expect(EmbeddedPageStatusText.friendly("This webpage owner is unavailable.", document: "note")
            == "Live pages wake up when the note is open in a window.")
    }

    @Test func aClosedPageOffersAnotherGo() {
        #expect(EmbeddedPageStatusText.friendly("Webpage closed", document: "Easel") == "This page closed. Give it another go?")
    }

    @Test func otherStatusErrorsPassThrough() {
        #expect(EmbeddedPageStatusText.friendly("Something else", document: "Easel") == "Something else")
    }

    @MainActor @Test func captureGeometrySurvivesClosingAndReopeningTheEasel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-easel-chrome-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try EaselStore(directory: directory).create()
        let asset = try session.importPNG(Self.png)
        var item = Self.card(captured: Date(timeIntervalSince1970: 1_700_000_000))
        item.assetID = asset
        var flat = Self.card(layout: nil)
        flat.assetID = asset
        try session.perform("Add capture") { $0.items = [item, flat] }
        try session.perform("Make live") { $0.items[0].liveCapture = true }
        try session.perform("Back to snapshot") { $0.items[0].liveCapture = false }
        let reopened = try EaselStore(directory: directory).load(session.document.id)
        let saved = reopened.document.items[0]
        #expect(saved.captureLayout == Self.layout)
        #expect(EaselWebItemChrome.canMakeLive(saved))
        #expect(EaselWebItemChrome.state(of: saved) == .snapshot(canGoLive: true))
        #expect(EaselWebItemChrome.state(of: reopened.document.items[1]) == .snapshot(canGoLive: false))
        let encoded = String(data: try JSONEncoder().encode(saved), encoding: .utf8) ?? ""
        #expect(encoded.contains("captureLayout"))
    }
}
