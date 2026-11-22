import AppKit
import Testing
import ParcCore
@testable import ParcSidebar

extension SpaceThemeControlTests {
    @Test func theSliderThumbAndDialMarkerSwellWithTheButtonsHoverScale() {
        var hovered = ThemeButtonMotion()
        hovered.setHovered(true, animated: false)
        #expect(hovered.hoverScale == 1.05)
        #expect(ThemeButtonMotion().hoverScale == 1)
    }

    @Test(arguments: [(0.0, 0.05, 1.5, 2.0), (1.0, 0.12, 4.0, 3.0)])
    func aHandlesShadowDeepensWithHover(example: (Double, Double, Double, Double)) {
        let hover = CGFloat(example.0)
        #expect(abs(ThemeControlHandle.shadowOpacity(hover: hover) - example.1) < 1e-9)
        #expect(ThemeControlHandle.shadowBlur(hover: hover) == CGFloat(example.2))
        #expect(ThemeControlHandle.shadowDrop(hover: hover) == CGFloat(example.3))
    }

    @Test(arguments: [(6, 0.33, 0.6), (0, 0.0, 0.0), (5, 0.33, 1.0), (7, 0.33, 0.0), (19, 1.0, 1.0)])
    func aDialDotFillsWithTheTurnFromItsStepToTheNext(example: (Int, Double, Double)) {
        #expect(abs(Double(ThemeControlHandle.dotFill(step: example.0, value: example.1)) - example.2) < 0.000001)
    }

    private func handleTheme() -> SpaceTheme {
        var theme = SpaceTheme()
        theme.intensity = 0.5
        theme.noise = 0.25
        return theme
    }

    @Test func theSliderDrawsWithRoomAroundItsOldFrameOnTheDialsCentreLine() throws {
        let f = try Fixture(handleTheme())
        #expect(f.intensity.frame.size == NSSize(width: 248, height: 80))
        #expect(f.intensity.frame.midY == f.noise.frame.midY)
        #expect(f.intensity.frame.minX == 6)
    }

    @Test(arguments: [(0.0, -31.0, false), (0.0, -29.0, true), (3.0, 0.0, false), (5.0, 0.0, true),
                      (-3.0, 0.0, false), (-5.0, 0.0, true)])
    func clicksKeepTheSlidersOldBand(example: (Double, Double, Bool)) throws {
        let f = try Fixture(handleTheme())
        let slider = f.intensity
        let x = example.0 == 0 ? slider.bounds.midX : example.0 > 0 ? example.0 : slider.bounds.width + example.0
        let superview = try #require(slider.superview)
        let point = slider.convert(NSPoint(x: x, y: slider.bounds.midY + example.1), to: superview)
        #expect((slider.hitTest(point) === slider) == example.2)
    }

    @Test func hoveringTheTrackSwellsTheThumb() throws {
        let f = try Fixture(handleTheme())
        let resting = try Self.pixels(f.intensity)
        f.intensity.mouseEntered(with: try Self.edge(.mouseEntered))
        #expect(try Self.pixels(f.intensity) != resting)
    }

    @Test func leavingTheTrackSettlesTheThumb() throws {
        let f = try Fixture(handleTheme())
        let resting = try Self.pixels(f.intensity)
        f.intensity.mouseEntered(with: try Self.edge(.mouseEntered))
        f.intensity.mouseExited(with: try Self.edge(.mouseExited))
        #expect(try Self.pixels(f.intensity) == resting)
    }

    @Test func aHeldSliderDragKeepsTheThumbSwollen() throws {
        let f = try Fixture(handleTheme())
        f.intensity.mouseEntered(with: try Self.edge(.mouseEntered))
        let swollen = try Self.pixels(f.intensity)
        f.intensity.mouseExited(with: try Self.edge(.mouseExited))
        try f.press(f.intensity, f.center(f.intensity))
        #expect(f.view.theme.intensity == 0.5)
        #expect(try Self.pixels(f.intensity) == swollen)
    }

    @Test func releasingOutsideTheSlidersBandSettlesTheThumb() throws {
        let f = try Fixture(handleTheme())
        let resting = try Self.pixels(f.intensity)
        try f.press(f.intensity, f.center(f.intensity))
        try f.release(f.intensity, NSPoint(x: f.intensity.bounds.midX, y: 2))
        #expect(try Self.pixels(f.intensity) == resting)
    }

    private func marker(_ f: Fixture) throws -> NSView {
        try #require(f.view.subviews.first { $0.identifier?.rawValue == "ThemeNoiseMarker" })
    }

    @Test func theMarkerDrawsInItsOwnSilentLayerBeyondTheDial() throws {
        let f = try Fixture(handleTheme())
        let layer = try marker(f)
        #expect(layer.frame == f.noise.frame.insetBy(dx: -8, dy: -8))
        #expect(!layer.isAccessibilityElement())
        #expect(layer.hitTest(NSPoint(x: layer.frame.midX, y: layer.frame.midY)) == nil)
    }

    @Test func clicksReachTheDialOnlyInsideItsOwnFrame() throws {
        let f = try Fixture(handleTheme())
        let layer = try marker(f)
        func hit(_ x: CGFloat) -> NSView? { f.view.hitTest(f.view.convert(NSPoint(x: x, y: f.noise.frame.midY), to: nil)) }
        #expect(hit(f.noise.frame.minX + 70) === f.noise)
        #expect(hit(f.noise.frame.maxX + 4) !== f.noise)
        #expect(hit(f.noise.frame.maxX + 4) !== layer)
    }

    private func markerPatch(_ f: Fixture) throws -> [CGFloat] {
        let layer = try marker(f), rep = try Self.snapshot(layer)
        let rect = NSRect(x: 69, y: 39, width: 26, height: 18)
        return try stride(from: rect.minY, to: rect.maxY, by: 0.5).flatMap { y in
            try stride(from: rect.minX, to: rect.maxX, by: 0.5).map { try Self.ink(rep, layer, NSPoint(x: $0, y: y)) }
        }
    }

    @Test func hoveringTheRingSwellsThePositionMarker() throws {
        let f = try Fixture(handleTheme())
        let resting = try markerPatch(f)
        try f.move(f.noise, NSPoint(x: f.noise.bounds.midX - 30, y: f.noise.bounds.midY))
        #expect(try markerPatch(f) != resting)
    }

    @Test func theCentreKnobGrowsItsTextureNotTheMarker() throws {
        let f = try Fixture(handleTheme())
        let resting = try markerPatch(f)
        try f.move(f.noise, NSPoint(x: f.noise.bounds.midX - 30, y: f.noise.bounds.midY))
        try f.hoverCenter()
        #expect(try markerPatch(f) == resting)
    }

    private func dragOverKnob(_ f: Fixture) throws -> NSPoint {
        let c = f.center(f.noise)
        try f.press(f.noise, NSPoint(x: c.x + 24, y: c.y))
        try f.drag(f.noise, NSPoint(x: c.x + 38, y: c.y))
        let overKnob = NSPoint(x: c.x + 5, y: c.y)
        try f.drag(f.noise, overKnob)
        return overKnob
    }

    @Test func aDialDragKeepsTheMarkerSwollenEvenOverTheKnob() throws {
        let f = try Fixture(handleTheme())
        try f.move(f.noise, NSPoint(x: f.noise.bounds.midX - 30, y: f.noise.bounds.midY))
        let swollen = try markerPatch(f)
        try f.hoverCenter()
        _ = try dragOverKnob(f)
        #expect(f.view.theme.noise == 0.25)
        #expect(try markerPatch(f) == swollen)
    }

    @Test func releasingADialDragOverTheKnobSettlesTheMarker() throws {
        let f = try Fixture(handleTheme())
        let resting = try markerPatch(f)
        let overKnob = try dragOverKnob(f)
        try f.release(f.noise, overKnob)
        #expect(try markerPatch(f) == resting)
    }

    private func renderedColumn(_ view: NSView, x: CGFloat) throws -> [UInt8] {
        view.wantsLayer = true
        let layer = try #require(view.layer)
        layer.setNeedsDisplay()
        layer.displayIfNeeded()
        let width = Int(view.bounds.width * 2), height = Int(view.bounds.height * 2)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 2, y: 2)
        layer.render(in: context)
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<height).map { data[$0 * width * 4 + Int(x * 2) * 4 + 3] }
    }

    private struct ShadowSides {
        let nearEdge: Int
        let farEdge: Int
        let edgeClear: Bool
        let bottomFirst: Bool
    }

    private func shadowSides(_ column: [UInt8], bottomFirst: Bool? = nil) throws -> ShadowSides {
        let first = try #require(column.firstIndex { $0 > 250 }), last = try #require(column.lastIndex { $0 > 250 })
        let atStart = bottomFirst ?? (first < column.count - 1 - last)
        func shadow(_ rows: [UInt8]) -> Int { rows.prefix { $0 > 2 && $0 <= 250 }.count }
        let before = shadow(Array(column[..<first].reversed())), after = shadow(Array(column[(last + 1)...]))
        let edge = try #require(atStart ? column.first : column.last)
        return atStart ? ShadowSides(nearEdge: before, farEdge: after, edgeClear: edge <= 2, bottomFirst: true)
            : ShadowSides(nearEdge: after, farEdge: before, edgeClear: edge <= 2, bottomFirst: false)
    }

    private func bottomHandles(hovered: Bool) throws -> (marker: [UInt8], slider: [UInt8]) {
        var theme = SpaceTheme()
        theme.noise = 0.5
        theme.intensity = 0.5
        let f = try Fixture(theme)
        if hovered {
            try f.move(f.noise, NSPoint(x: f.noise.bounds.midX - 30, y: f.noise.bounds.midY))
            f.intensity.mouseEntered(with: try Self.edge(.mouseEntered))
        }
        let layer = try marker(f)
        return (try renderedColumn(layer, x: layer.bounds.midX), try renderedColumn(f.intensity, x: 4 + 16 + 208 * 0.5))
    }

    @Test func theRestingMarkerAtTheBottomCastsItsShadowDownPastItsTip() throws {
        let sides = try shadowSides(try bottomHandles(hovered: false).marker)
        #expect(sides.nearEdge >= 3)
        #expect(sides.nearEdge > sides.farEdge)
    }

    @Test func theSwollenMarkersDeeperShadowStillFitsInsideTheOverlay() throws {
        let resting = try shadowSides(try bottomHandles(hovered: false).marker)
        let swollen = try shadowSides(try bottomHandles(hovered: true).marker)
        #expect(swollen.nearEdge > resting.nearEdge)
        #expect(swollen.edgeClear)
    }

    @Test(arguments: [false, true])
    func theSliderThumbsShadowFallsBelowIt(hovered: Bool) throws {
        let bottomFirst = try shadowSides(try bottomHandles(hovered: false).marker).bottomFirst
        let sides = try shadowSides(try bottomHandles(hovered: hovered).slider, bottomFirst: bottomFirst)
        #expect(sides.nearEdge > sides.farEdge)
    }

    private func dotInk(_ value: Double, step: Int) throws -> CGFloat {
        let f = try Fixture({ var theme = SpaceTheme(); theme.noise = value; return theme }())
        let angle = (-90 + Double(step) * 18) * .pi / 180
        return try Self.ink(try Self.snapshot(f.noise), f.noise, NSPoint(x: 40 + cos(angle) * 32, y: 40 + sin(angle) * 32))
    }

    @Test func aDotTheMarkerHasNearlyPassedIsPartlyFilled() throws {
        let empty = try dotInk(0.25, step: 6), most = try dotInk(0.345, step: 6), full = try dotInk(0.35, step: 6)
        #expect(empty < most)
        #expect(most < full)
    }

    @Test func aPartlyFilledDotKeepsFillingAsTheDialTurns() throws {
        #expect(try dotInk(0.34, step: 6) < (try dotInk(0.345, step: 6)))
    }

    @Test func intensityStartsAtTheWavesPadding() throws {
        let f = try Fixture()
        try f.press(f.intensity, NSPoint(x: 16, y: f.intensity.bounds.midY))
        #expect(f.view.theme.intensity == 0)
    }

    @Test func intensityReachesItsUpperEndpoint() throws {
        let f = try Fixture()
        try f.press(f.intensity, NSPoint(x: 16, y: f.intensity.bounds.midY))
        try f.drag(f.intensity, NSPoint(x: f.intensity.bounds.width - 16, y: f.intensity.bounds.midY))
        #expect(f.view.theme.intensity == 1)
    }

    @Test func finishingEditingCommitsAnIntensityDragOnce() throws {
        let f = try Fixture()
        try f.press(f.intensity, NSPoint(x: 16, y: f.intensity.bounds.midY))
        try f.drag(f.intensity, NSPoint(x: f.intensity.bounds.width - 16, y: f.intensity.bounds.midY))
        f.view.finishEditing()
        #expect(f.commits == 1)
        f.view.undo(nil)
        #expect(Self.near(f.view.theme.intensity, 0.8))
    }

    @Test func aStaleIntensityDragCannotEnterANewNoiseGesture() throws {
        let f = try Fixture()
        let start = NSPoint(x: 16, y: f.intensity.bounds.midY)
        try f.press(f.intensity, start)
        f.view.finishEditing()
        f.view.undo(nil)
        f.rotate(.began, 10)
        try f.drag(f.intensity, start)
        #expect(Self.near(f.view.theme.intensity, 0.8))
    }
}
