import Foundation
import Testing
@testable import ParcCore

struct EaselLiveCaptureFramingTests {
    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }

    static let viewport = EaselPoint(x: 1280, y: 800)
    static let panel = EaselScrollContainer(anchorID: "main", path: "div:1>^>section:0", scroll: .init(x: 0, y: 2400.5),
                                            frame: .init(x: 240, y: 64, width: 1040, height: 736))
    static let region = EaselRect(x: 300, y: 200, width: 400, height: 300)

    static var elementArea: EaselRect {
        EaselCaptureGeometry.elementCaptureArea(elementRect: .init(x: 100, y: 200, width: 300, height: 120), viewport: viewport)!
    }

    static var capturedLayout: EaselCaptureLayout {
        EaselCaptureLayout(viewport: viewport, scroll: .init(x: 0, y: 1500), region: .init(x: 98, y: 198, width: 304, height: 124))
    }

    static func windowOnly() -> EaselCaptureLayout {
        EaselCaptureGeometry.captured(viewport: viewport, scroll: .init(x: 0, y: 0), region: region, scrollContainers: [])!
    }

    @Test func anElementCaptureKeepsATwoPointMargin() {
        #expect(Self.elementArea == EaselRect(x: 98, y: 198, width: 304, height: 124))
    }

    @Test func elementsPastTheViewportAreClippedToWhatWasVisible() {
        let edge = EaselCaptureGeometry.elementCaptureArea(elementRect: .init(x: 0, y: 700, width: 1280, height: 200), viewport: Self.viewport)
        #expect(edge == EaselRect(x: 0, y: 698, width: 1280, height: 102))
    }

    @Test func anElementOutsideTheViewportHasNoCaptureArea() {
        #expect(EaselCaptureGeometry.elementCaptureArea(elementRect: .init(x: 0, y: 900, width: 100, height: 50), viewport: Self.viewport) == nil)
    }

    @Test func atFullZoomTheRegionIsTheElementsViewportRect() {
        let scroll = EaselPoint(x: 0, y: 1500)
        let plain = EaselCaptureGeometry.layout(captureArea: Self.elementArea, viewport: Self.viewport, scroll: scroll, pageZoom: 1, visualScale: 1)
        #expect(plain?.region == Self.elementArea && plain?.scroll == scroll && plain?.viewport == Self.viewport)
    }

    @Test func pageZoomConvertsTheCaptureToCSSPixels() {
        let zoomed = EaselCaptureGeometry.layout(captureArea: Self.elementArea, viewport: Self.viewport, scroll: .init(x: 0, y: 1500),
                                                 pageZoom: 2, visualScale: 1)
        #expect(zoomed?.region == EaselRect(x: 49, y: 99, width: 152, height: 62))
    }

    @Test func pinchZoomAlsoConvertsToCSSPixels() {
        let pinched = EaselCaptureGeometry.layout(captureArea: Self.elementArea, viewport: Self.viewport, scroll: .init(x: 0, y: 1500),
                                                  pageZoom: 1, visualScale: 2)
        #expect(pinched?.region.width == 152)
    }

    @Test func noZoomMeansNoLayout() {
        #expect(EaselCaptureGeometry.layout(captureArea: Self.elementArea, viewport: Self.viewport, scroll: .init(x: 0, y: 1500),
                                            pageZoom: 0, visualScale: 1) == nil)
    }

    @Test func aRegionOutsideTheViewportIsNeverSaved() {
        let outside = EaselCaptureGeometry.layout(captureArea: .init(x: 1200, y: 0, width: 200, height: 20), viewport: Self.viewport,
                                                  scroll: .init(x: 0, y: 1500), pageZoom: 1, visualScale: 1)
        #expect(outside == nil)
    }

    @Test func theLiveViewKeepsTheElementsAspectRatio() {
        let size = EaselCaptureGeometry.displaySize(Self.capturedLayout, availableWidth: 608, availableHeight: 1000, pageZoom: 1)
        #expect(Self.close(size.width, 608) && Self.close(size.height, 248))
    }

    @Test func aShortCardLetterboxesInsteadOfStretching() {
        let short = EaselCaptureGeometry.displaySize(Self.capturedLayout, availableWidth: 608, availableHeight: 124, pageZoom: 1)
        #expect(Self.close(short.height, 124) && Self.close(short.width, 304))
    }

    @Test func thePageScalesSoTheElementFillsTheCard() throws {
        let size = EaselCaptureGeometry.displaySize(Self.capturedLayout, availableWidth: 608, availableHeight: 1000, pageZoom: 1)
        let framing = try #require(EaselCaptureGeometry.framing(Self.capturedLayout, displayWidth: size.width, pageZoom: 1))
        #expect(Self.close(framing.scale, 2))
        #expect(framing.documentRegion == EaselRect(x: 98, y: 1698, width: 304, height: 124))
        #expect(framing.scrollTarget == EaselPoint(x: 0, y: 3000))
        #expect(Self.close(framing.documentRegion.width * framing.scale, size.width)
            && Self.close(framing.documentRegion.height * framing.scale, size.height))
    }

    @Test func browserZoomIsAccountedForInTheScale() throws {
        let size = EaselCaptureGeometry.displaySize(Self.capturedLayout, availableWidth: 608, availableHeight: 1000, pageZoom: 1)
        let zoomed = try #require(EaselCaptureGeometry.framing(Self.capturedLayout, displayWidth: size.width, pageZoom: 2))
        #expect(Self.close(zoomed.scale, 1))
    }

    @Test func aFramedRegionNeverScrollsTheWholeDocumentButOrdinaryPagesDo() {
        #expect(!EaselLiveFraming.admitsPageScrolling(framesCapture: true))
        #expect(EaselLiveFraming.admitsPageScrolling(framesCapture: false))
    }

    @Test func thePageStaysCoveredUntilItIsFramed() {
        var state = EaselLiveFraming()
        #expect(!state.revealsPage)
        #expect(state.positioned(success: false, pageStillLoading: true) == .keepWaiting && !state.revealsPage)
        #expect(state.positioned(success: true, pageStillLoading: true) == .reveal && state.revealsPage)
    }

    @Test func aNewDocumentIsCoveredAgainAndAnUnframablePageGoesBackToTheSnapshot() {
        var state = EaselLiveFraming()
        _ = state.positioned(success: true, pageStillLoading: true)
        state.pageChanged()
        #expect(!state.revealsPage)
        #expect(state.positioned(success: false, pageStillLoading: false) == .backToSnapshot && !state.revealsPage)
    }

    @Test func aLocatedInnerPanelWithItsScrollOffsetIsValid() {
        #expect(Self.panel.isValid)
    }

    @Test(arguments: [("sidebar-nav", true), ("feed_2", true), ("ember1234", false),
                      (":r1:", false), ("1main", false), ("main panel", false)])
    func onlyReadableIdsAnchorAnInnerPanel(_ id: String, _ valid: Bool) {
        #expect(EaselScrollContainer.isValidAnchor(id) == valid)
    }

    @Test(arguments: [("", true), ("main:0>div:12", true), ("div", false), ("div:x", false),
                      ("div:1>", false), ("di v:1", false), ("div:123456", false)])
    func onlyTagAndIndexStepsFormAnInnerPanelPath(_ path: String, _ valid: Bool) {
        #expect(EaselScrollContainer.isValidPath(path) == valid)
    }

    @Test func aNegativePanelSizeIsRefused() {
        var negative = Self.panel
        negative.frame.width = -1
        #expect(!negative.isValid)
    }

    @Test func panelsEncodeCompactlyOutermostFirstAndDecodeExactly() {
        let root = EaselScrollContainer(anchorID: nil, path: "", scroll: .init(x: -30, y: 0), frame: .init(x: 0, y: 0, width: 500, height: 400))
        let encoded = EaselScrollContainer.encode([root, Self.panel])
        #expect(encoded == "- - -30,0 0,0,500,400;#main div:1>^>section:0 0,2400.5 240,64,1040,736")
        #expect(EaselScrollContainer.decode(encoded) == [root, Self.panel])
    }

    @Test func malformedPanelRecordsAreRefused() {
        #expect(EaselScrollContainer.decode("") == nil && EaselScrollContainer.decode("#main div:1 0,0 0,0,1") == nil
            && EaselScrollContainer.decode("main div:1 0,0 0,0,1,1") == nil && EaselScrollContainer.decode("#main div:1 0,nan 0,0,1,1") == nil)
    }

    @Test func atMostEightPanelsDecode() {
        #expect(EaselScrollContainer.decode(Array(repeating: "- - 0,0 0,0,1,1", count: 9).joined(separator: ";")) == nil)
    }

    @Test func aCaptureWithoutInnerPanelsKeepsWindowOnlyFraming() {
        #expect(Self.windowOnly().scrollContainers == nil)
    }

    @Test func aCaptureInsideAScrolledPanelRecordsIt() {
        let panelled = EaselCaptureGeometry.captured(viewport: Self.viewport, scroll: .init(x: 0, y: 0), region: Self.region,
                                                     scrollContainers: [Self.panel])
        #expect(panelled?.scrollContainers == [Self.panel])
    }

    @Test func unusablePanelRecordsNeverProduceALiveRegion() {
        var negative = Self.panel
        negative.frame.width = -1
        #expect(EaselCaptureGeometry.captured(viewport: Self.viewport, scroll: .init(x: 0, y: 0), region: Self.region,
                                              scrollContainers: [negative]) == nil)
    }

    @Test func anEmptyPanelListIsNotTheSavedForm() {
        var empty = Self.windowOnly()
        empty.scrollContainers = []
        #expect(!empty.isValid)
    }

    @Test func moreThanEightPanelsAreRefused() {
        var crowded = Self.windowOnly()
        crowded.scrollContainers = Array(repeating: Self.panel, count: 9)
        #expect(!crowded.isValid)
    }

    @Test func cardsSavedBeforePanelsExistedKeepWindowOnlyFraming() throws {
        let old = #"{"viewport":{"x":1280,"y":800},"scroll":{"x":0,"y":0},"region":{"x":300,"y":200,"width":400,"height":300}}"#
        let decoded = try JSONDecoder().decode(EaselCaptureLayout.self, from: Data(old.utf8))
        #expect(decoded == Self.windowOnly())
    }

    @Test func windowOnlyCardsSaveExactlyAsBefore() throws {
        let reencoded = String(data: try JSONEncoder().encode(Self.windowOnly()), encoding: .utf8) ?? ""
        #expect(!reencoded.contains("scrollContainers"))
    }

    @Test func panelsPersistWithTheCard() throws {
        let panelled = try #require(EaselCaptureGeometry.captured(viewport: Self.viewport, scroll: .init(x: 0, y: 0), region: Self.region,
                                                                  scrollContainers: [Self.panel]))
        let saved = try JSONDecoder().decode(EaselCaptureLayout.self, from: JSONEncoder().encode(panelled))
        #expect(saved == panelled)
    }

    static var fullPage: EaselCaptureLayout {
        EaselCaptureGeometry.captured(viewport: viewport, scroll: .init(x: 0, y: 0),
                                      region: .init(x: 0, y: 0, width: 1280, height: 800), scrollContainers: [], fullPage: true)!
    }

    static func card(_ layout: EaselCaptureLayout, frame: EaselRect, live: Bool? = nil) -> EaselItem {
        EaselItem(kind: .webCard, frame: frame, url: "https://example.com", assetID: "a.png", captureLayout: layout, liveCapture: live)
    }

    @Test func aFullPageCaptureRecordsItsPageAndNothingElseDoes() {
        #expect(Self.fullPage.isFullPage)
        #expect(!Self.windowOnly().isFullPage)
        #expect(Self.windowOnly().fullPage == nil)
    }

    @Test func layoutsSavedBeforeFullPageCapturesStillDecode() throws {
        let old = #"{"viewport":{"x":1280,"y":800},"scroll":{"x":0,"y":10},"region":{"x":1,"y":2,"width":30,"height":40}}"#
        let decoded = try JSONDecoder().decode(EaselCaptureLayout.self, from: Data(old.utf8))
        #expect(decoded.fullPage == nil && decoded.isValid)
        let again = try JSONDecoder().decode(EaselCaptureLayout.self, from: JSONEncoder().encode(Self.fullPage))
        #expect(again == Self.fullPage && again.isFullPage)
    }

    @Test func onlyRegionCapturesAreFramed() {
        #expect(EaselLiveFraming.framesCapture(Self.windowOnly()))
        #expect(!EaselLiveFraming.framesCapture(Self.fullPage))
        #expect(!EaselLiveFraming.framesCapture(nil))
    }

    @Test func goingLiveMakesAScreenShapedWindowUnderTheSameTopEdge() {
        let live = EaselCaptureGeometry.settingLive(Self.card(Self.fullPage, frame: .init(x: 40, y: 60, width: 320, height: 2400)),
                                                    enabled: true, imageSize: CGSize(width: 1280, height: 9600))
        #expect(live.liveCapture == true)
        #expect(live.frame == EaselRect(x: 40, y: 60, width: 320, height: 200))
    }

    @Test func theLiveWindowAddsItsHeaderBelowTheScreenShape() {
        let live = EaselCaptureGeometry.settingLive(Self.card(Self.fullPage, frame: .init(x: 40, y: 60, width: 320, height: 2400)),
                                                    enabled: true, imageSize: CGSize(width: 1280, height: 9600), chrome: 38)
        #expect(live.frame == EaselRect(x: 40, y: 60, width: 320, height: 238))
    }

    @Test func aFullPageLivePageZoomsToTheCapturedWidth() {
        #expect(EaselCaptureGeometry.fullPageZoom(width: 320, layout: Self.fullPage) == 320 / Self.fullPage.viewport.x)
        #expect(EaselCaptureGeometry.fullPageZoom(width: 0, layout: Self.fullPage) == nil)
        #expect(EaselCaptureGeometry.fullPageZoom(width: 320, layout: Self.windowOnly()) == nil)
    }

    @Test func backToSnapshotUsesTheLiveWidthAndTheImageShape() {
        let snapshot = EaselCaptureGeometry.settingLive(Self.card(Self.fullPage, frame: .init(x: 40, y: 60, width: 500, height: 312.5), live: true),
                                                        enabled: false, imageSize: CGSize(width: 1280, height: 9600))
        #expect(snapshot.liveCapture == false)
        #expect(snapshot.frame == EaselRect(x: 40, y: 60, width: 500, height: 3750))
    }

    @Test func regionCapturesKeepTheirFrameEitherWay() {
        let frame = EaselRect(x: 40, y: 60, width: 320, height: 240)
        let live = EaselCaptureGeometry.settingLive(Self.card(Self.windowOnly(), frame: frame), enabled: true, imageSize: CGSize(width: 10, height: 90))
        #expect(live.frame == frame && live.liveCapture == true)
        let back = EaselCaptureGeometry.settingLive(live, enabled: false, imageSize: CGSize(width: 10, height: 90))
        #expect(back.frame == frame && back.liveCapture == false)
    }

    @Test func aMissingImageLeavesTheFrameAlone() {
        let frame = EaselRect(x: 0, y: 0, width: 500, height: 312.5)
        let back = EaselCaptureGeometry.settingLive(Self.card(Self.fullPage, frame: frame, live: true), enabled: false, imageSize: nil)
        #expect(back.frame == frame && back.liveCapture == false)
    }
}
