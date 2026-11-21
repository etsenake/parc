import AppKit
import SwiftUI
import Testing
@testable import Parc

private final class PointerWindow: NSWindow, ApplicationActivityReporting {
    var pointer = NSPoint(x: -1, y: -1)
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    var reportsApplicationActive: Bool { false }
}

@MainActor
struct SidebarPlusButtonTests {
    private func near(_ value: CGFloat, _ expected: CGFloat, _ tolerance: CGFloat = 0.002) -> Bool { abs(value - expected) <= tolerance }

    private func gray(_ color: NSColor) -> (white: CGFloat, alpha: CGFloat) {
        let srgb = color.usingColorSpace(.sRGB)!
        return (srgb.redComponent, srgb.alphaComponent)
    }

    fileprivate struct Scheme: Sendable {
        let dark: Bool
        let white: CGFloat
        let a4: CGFloat
        let a5: CGFloat
        let a11: CGFloat
        let a12: CGFloat
        var name: String { dark ? "dark" : "light" }
    }

    nonisolated fileprivate static let schemes = [Scheme(dark: false, white: 0, a4: 0.071, a5: 0.090, a11: 0.565, a12: 0.910),
                                  Scheme(dark: true, white: 1, a4: 0.077, a5: 0.103, a11: 0.592, a12: 0.923)]

    @Test(arguments: schemes)
    fileprivate func theRestPlateIsClear(scheme: Scheme) {
        #expect(gray(TranslucentButtonColors.standard(dark: scheme.dark).background(hovered: false, pressed: false, enabled: true)).alpha == 0)
    }

    @Test(arguments: schemes)
    fileprivate func theHoveredPlateIsGrayA4(scheme: Scheme) {
        let hovered = gray(TranslucentButtonColors.standard(dark: scheme.dark).background(hovered: true, pressed: false, enabled: true))
        #expect(near(hovered.alpha, scheme.a4))
        #expect(hovered.white == scheme.white)
    }

    @Test(arguments: schemes)
    fileprivate func thePressedPlateIsGrayA5(scheme: Scheme) {
        #expect(near(gray(TranslucentButtonColors.standard(dark: scheme.dark).background(hovered: true, pressed: true, enabled: true)).alpha, scheme.a5))
    }

    @Test(arguments: schemes)
    fileprivate func theGlyphIsGrayA11(scheme: Scheme) {
        let glyph = gray(TranslucentButtonColors.standard(dark: scheme.dark).foreground(pressed: false, enabled: true))
        #expect(near(glyph.alpha, scheme.a11))
        #expect(glyph.white == scheme.white)
    }

    @Test(arguments: schemes)
    fileprivate func thePressedGlyphIsGrayA12(scheme: Scheme) {
        #expect(near(gray(TranslucentButtonColors.standard(dark: scheme.dark).foreground(pressed: true, enabled: true)).alpha, scheme.a12))
    }

    @MainActor private final class Plus {
        let window = PointerWindow(contentRect: NSRect(x: -12_000, y: -12_000, width: 64, height: 64), styleMask: [.borderless], backing: .buffered, defer: false)
        let button = ActionButton("New Tab, Folder, or Space")
        let state = SidebarPlusButtonState()

        init() {
            window.isReleasedWhenClosed = false
            button.title = ""
            button.toolTip = "New Tab, Folder, or Space"
            button.frame = NSRect(x: 16, y: 16, width: 32, height: 32)
            window.contentView?.addSubview(button)
            state.install(in: button)
            button.onHighlight = { [state] in state.pressed = $0 }
            button.onHover = { [state] in state.hovered = $0 }
        }

        deinit {
            MainActor.assumeIsolated { window.close() }
        }

        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                   eventNumber: 0, trackingNumber: 0, userData: nil)!
        }

        func ink(threshold: CGFloat = 0.3) -> Ink {
            let renderer = ImageRenderer(content: SidebarPlusButtonFace(state: state))
            renderer.scale = 2
            let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
            var maxAlpha: CGFloat = 0, minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    let alpha = rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    maxAlpha = max(maxAlpha, alpha)
                    if alpha > threshold { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
                }
            }
            return Ink(maxAlpha: maxAlpha, width: maxX - minX + 1, height: maxY - minY + 1,
                       plate: rep.colorAt(x: 6, y: rep.pixelsHigh / 2)?.alphaComponent ?? 0,
                       corner: rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 0)
        }
    }

    private struct Ink {
        let maxAlpha: CGFloat
        let width: Int
        let height: Int
        let plate: CGFloat
        let corner: CGFloat
    }

    @Test func theFaceStartsAtRest() {
        let state = SidebarPlusButtonState()
        #expect(!state.hovered)
        #expect(!state.pressed)
        #expect(!state.open)
        #expect(state.colors == .standard(dark: false))
    }

    @Test func theFaceFillsTheButton() {
        let p = Plus()
        #expect(p.button.subviews.count == 1)
        #expect(p.button.subviews[0].frame == p.button.bounds)
        #expect(p.button.subviews[0].autoresizingMask == [.width, .height])
    }

    @Test func theFaceIsNotAnAccessibilityElement() {
        #expect(!Plus().button.subviews[0].isAccessibilityElement())
    }

    @Test func clicksOnTheFaceReachTheButton() {
        let p = Plus()
        #expect(p.window.contentView?.hitTest(NSPoint(x: 32, y: 32)) === p.button)
    }

    @Test func theButtonKeepsItsLabel() {
        #expect(Plus().button.accessibilityLabel() == "New Tab, Folder, or Space")
    }

    @Test func nsButtonsPressHighlightPressesTheFace() {
        let p = Plus()
        p.button.highlight(true)
        #expect(p.state.pressed)
    }

    @Test func releasingTheHighlightReleasesTheFace() {
        let p = Plus()
        p.button.highlight(true)
        p.button.highlight(false)
        #expect(!p.state.pressed)
    }

    @Test func enteringTheButtonHoversTheFaceWhileTheAppIsActive() {
        let p = Plus()
        p.button.mouseEntered(with: p.event(.mouseEntered))
        #expect(p.state.hovered)
    }

    @Test func anInactiveAppsButtonDropsItsHoverThoughThePointerIsOverIt() {
        let p = Plus()
        p.button.mouseEntered(with: p.event(.mouseEntered))
        p.window.pointer = NSPoint(x: 32, y: 32)
        p.button.refreshHover()
        #expect(!p.state.hovered)
        #expect(!p.button.hovered)
    }

    @Test func pressingOrDraggingBackOnReReadsTheHover() {
        let p = Plus()
        p.button.mouseEntered(with: p.event(.mouseEntered))
        #expect(p.button.hovered)
        #expect(p.state.hovered)
        p.window.pointer = NSPoint(x: 32, y: 32)
        p.button.highlight(true)
        #expect(!p.button.hovered)
        #expect(!p.state.hovered)
        #expect(p.state.pressed)
    }

    @Test func draggingThePressOffTheButtonClearsTheHoverAndPressPlates() {
        let p = Plus()
        p.button.mouseEntered(with: p.event(.mouseEntered))
        p.window.pointer = NSPoint(x: 32, y: 32)
        p.button.highlight(true)
        p.button.mouseEntered(with: p.event(.mouseEntered))
        p.window.pointer = NSPoint(x: -40, y: -40)
        p.button.highlight(false)
        #expect(!p.button.hovered)
        #expect(!p.state.hovered)
        #expect(!p.state.pressed)
    }

    @Test func theRestPlusIsFourteenPointsWide() {
        let ink = Plus().ink()
        #expect(ink.width == 28)
        #expect(ink.height == 28)
    }

    @Test func theRestCrossingIsOneGrayA11CoverageNotTwo() {
        #expect(near(Plus().ink().maxAlpha, 0.565, 0.02))
    }

    @Test func theRestPlateIsClearOnScreen() {
        #expect(Plus().ink().plate == 0)
    }

    @Test func hoveringShowsTheRadiusSixGrayA4Plate() {
        let p = Plus()
        p.button.mouseEntered(with: p.event(.mouseEntered))
        let ink = p.ink()
        #expect(near(ink.plate, 0.071, 0.01))
        #expect(ink.corner < 0.01)
    }

    @Test func theHoveredGlyphStaysGrayA11() {
        let p = Plus()
        p.button.mouseEntered(with: p.event(.mouseEntered))
        let ink = p.ink()
        #expect(ink.width == 28)
        #expect(near(ink.maxAlpha, 0.596, 0.02))
    }

    @Test func pressingShowsTheGrayA5PlateAndAGrayA12Glyph() {
        let p = Plus()
        p.button.mouseEntered(with: p.event(.mouseEntered))
        p.button.highlight(true)
        let ink = p.ink()
        #expect(near(ink.plate, 0.090, 0.01))
        #expect(near(ink.maxAlpha, 0.918, 0.02))
    }

    @Test func thePressScalesTheGlyphByPointNineFive() {
        let p = Plus()
        p.button.mouseEntered(with: p.event(.mouseEntered))
        p.button.highlight(true)
        let ink = p.ink()
        #expect((26...27).contains(ink.width))
        #expect(ink.height == ink.width)
    }

    @Test func theDraggedOffPlusShowsNoPlate() {
        let p = Plus()
        p.button.mouseEntered(with: p.event(.mouseEntered))
        p.window.pointer = NSPoint(x: 32, y: 32)
        p.button.highlight(true)
        p.button.mouseEntered(with: p.event(.mouseEntered))
        p.window.pointer = NSPoint(x: -40, y: -40)
        p.button.highlight(false)
        #expect(p.ink().plate == 0)
    }

    @Test func theOpenCrossSettlesAtAQuarterTurn() {
        let p = Plus()
        p.state.open = true
        let ink = p.ink()
        #expect(ink.width == 20)
        #expect(ink.height == 20)
    }

    @Test func theOpenCrossesVisibleEdgeSpansTwentyTwoPixels() {
        let p = Plus()
        p.state.open = true
        let edge = p.ink(threshold: 0.05)
        #expect(edge.width == 22)
        #expect(edge.height == 22)
    }

    @Test func theOpenCrossStaysGrayA11OnAClearPlate() {
        let p = Plus()
        p.state.open = true
        let ink = p.ink()
        #expect(near(ink.maxAlpha, 0.565, 0.02))
        #expect(ink.plate == 0)
    }

    @Test func closingTurnsTheCrossBackIntoThePlus() {
        let p = Plus()
        p.state.open = true
        _ = p.ink()
        p.state.open = false
        let ink = p.ink()
        #expect(ink.width == 28)
        #expect(ink.height == 28)
    }
}
