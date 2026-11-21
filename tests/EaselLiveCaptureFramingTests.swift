import Foundation

@main
struct EaselLiveCaptureFramingTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }

    @MainActor static func main() {
        exitOnFailure {
            elementArea()
            elementLayout()
            framingShowsExactlyTheElement()
            framingState()
            print("EaselLiveCaptureFramingTests: \(assertions) assertions passed")
        }
    }

    @MainActor static func elementArea() {
        let viewport = EaselPoint(x: 1280, y: 800)
        let area = EaselCaptureGeometry.elementCaptureArea(elementRect: .init(x: 100, y: 200, width: 300, height: 120), viewport: viewport)
        expect(area == EaselRect(x: 98, y: 198, width: 304, height: 124), "An element capture keeps a two-point margin")
        let edge = EaselCaptureGeometry.elementCaptureArea(elementRect: .init(x: 0, y: 700, width: 1280, height: 200), viewport: viewport)
        expect(edge == EaselRect(x: 0, y: 698, width: 1280, height: 102), "Elements past the viewport are clipped to what was visible")
        expect(EaselCaptureGeometry.elementCaptureArea(elementRect: .init(x: 0, y: 900, width: 100, height: 50), viewport: viewport) == nil,
               "An element outside the viewport has no capture area")
    }

    @MainActor static func elementLayout() {
        let viewport = EaselPoint(x: 1280, y: 800), scroll = EaselPoint(x: 0, y: 1500)
        let area = EaselCaptureGeometry.elementCaptureArea(elementRect: .init(x: 100, y: 200, width: 300, height: 120), viewport: viewport)!
        let plain = EaselCaptureGeometry.layout(captureArea: area, viewport: viewport, scroll: scroll, pageZoom: 1, visualScale: 1)
        expect(plain?.region == area && plain?.scroll == scroll && plain?.viewport == viewport, "At 100% the region is the element's viewport rect")
        let zoomed = EaselCaptureGeometry.layout(captureArea: area, viewport: viewport, scroll: scroll, pageZoom: 2, visualScale: 1)
        expect(zoomed?.region == EaselRect(x: 49, y: 99, width: 152, height: 62), "Page zoom converts the capture to CSS pixels")
        let pinched = EaselCaptureGeometry.layout(captureArea: area, viewport: viewport, scroll: scroll, pageZoom: 1, visualScale: 2)
        expect(pinched?.region.width == 152, "Pinch zoom also converts to CSS pixels")
        expect(EaselCaptureGeometry.layout(captureArea: area, viewport: viewport, scroll: scroll, pageZoom: 0, visualScale: 1) == nil,
               "No zoom, no layout")
        let outside = EaselCaptureGeometry.layout(captureArea: .init(x: 1200, y: 0, width: 200, height: 20), viewport: viewport,
                                                 scroll: scroll, pageZoom: 1, visualScale: 1)
        expect(outside == nil, "A region outside the viewport is never saved")
    }

    @MainActor static func framingShowsExactlyTheElement() {
        let layout = EaselCaptureLayout(viewport: .init(x: 1280, y: 800), scroll: .init(x: 0, y: 1500),
                                        region: .init(x: 98, y: 198, width: 304, height: 124))
        let size = EaselCaptureGeometry.displaySize(layout, availableWidth: 608, availableHeight: 1000, pageZoom: 1)
        expect(close(size.width, 608) && close(size.height, 248), "The live view keeps the element's aspect ratio")
        let short = EaselCaptureGeometry.displaySize(layout, availableWidth: 608, availableHeight: 124, pageZoom: 1)
        expect(close(short.height, 124) && close(short.width, 304), "A short card letterboxes instead of stretching")
        let framing = EaselCaptureGeometry.framing(layout, displayWidth: size.width, pageZoom: 1)!
        expect(close(framing.scale, 2), "The page scales so the element fills the card")
        expect(framing.documentRegion == EaselRect(x: 98, y: 1698, width: 304, height: 124), "The view shows the element's place in the document")
        expect(framing.scrollTarget == EaselPoint(x: 0, y: 3000), "The page scrolls to the captured offset at the new scale")
        expect(close(framing.documentRegion.width * framing.scale, size.width)
               && close(framing.documentRegion.height * framing.scale, size.height), "Exactly the element's region fills the view")
        let zoomed = EaselCaptureGeometry.framing(layout, displayWidth: size.width, pageZoom: 2)!
        expect(close(zoomed.scale, 1), "Browser zoom is accounted for in the scale")
        expect(!EaselLiveFraming.admitsPageScrolling(framesCapture: true), "A framed region never scrolls the whole document")
        expect(EaselLiveFraming.admitsPageScrolling(framesCapture: false), "Ordinary webpage objects scroll")
    }

    @MainActor static func framingState() {
        var state = EaselLiveFraming()
        expect(!state.revealsPage, "The page stays covered until it is framed")
        expect(state.positioned(success: false, pageStillLoading: true) == .keepWaiting && !state.revealsPage,
               "A failed attempt while loading keeps waiting, covered")
        expect(state.positioned(success: true, pageStillLoading: true) == .reveal && state.revealsPage, "Success reveals the framed page")
        state.pageChanged()
        expect(!state.revealsPage, "A new document is covered again until it is framed")
        expect(state.positioned(success: false, pageStillLoading: false) == .backToSnapshot && !state.revealsPage,
               "A loaded page that can't be framed goes back to the snapshot")
    }
}
