import AppKit
import SwiftUI
import Testing
@testable import Parc

@MainActor
struct SidebarHeaderGlyphTestsNavigationTests {
    private typealias Support = SidebarHeaderGlyphTestsSupport
    private typealias Face = Support.Face

    private func capture(_ view: NSView) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func maxAlpha(_ rep: NSBitmapImageRep) -> CGFloat {
        var best: CGFloat = 0
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide { best = max(best, rep.colorAt(x: x, y: y)!.alphaComponent) } }
        return best
    }

    private func reloadAlpha(_ glyph: ReloadGlyph, _ tint: NSColor, in view: NSView) -> CGFloat {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 56, pixelsHigh: 56, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = view.bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        glyph.draw(in: view.bounds, tint: tint, in: view)
        NSGraphicsContext.restoreGraphicsState()
        return maxAlpha(rep)
    }

    @Test func anEnabledToolbarReloadIsOpaque() {
        let f = Face()
        let flipped = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        let toolbar = ReloadGlyph(view: f.view, pointSize: ReloadGlyph.toolbarPointSize, rasterized: false)
        #expect(reloadAlpha(toolbar, .black, in: flipped) > 0.97)
    }

    @Test func aDisabledToolbarReloadIsATrueHalfAlpha() {
        let f = Face()
        let flipped = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        let toolbar = ReloadGlyph(view: f.view, pointSize: ReloadGlyph.toolbarPointSize, rasterized: false)
        #expect(Support.near(reloadAlpha(toolbar, NSColor(white: 0, alpha: 0.5), in: flipped), 0.5, 0.02))
    }

    @Test(arguments: [0.565, 0.910])
    func theSidebarReloadKeepsItsAlpha(alpha: Double) {
        let flipped = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        let glyph = ReloadGlyph(view: flipped, pointSize: 16, rasterized: true)
        #expect(Support.near(reloadAlpha(glyph, NSColor(white: 0, alpha: CGFloat(alpha)), in: flipped), CGFloat(alpha), 0.02))
    }

    private func backButton() -> NavigationControlButton {
        let button = NavigationControlButton("Go back", symbol: "arrow.left", history: true, glyphPointSize: 16)
        button.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        button.appearance = NSAppearance(named: .aqua)
        return button
    }

    @Test func theArrowAtRestIsGrayA11() {
        #expect(Support.near(maxAlpha(capture(backButton())), 0.565, 0.03))
    }

    @Test func aDisabledArrowIsGrayA8() {
        let button = backButton()
        button.isEnabled = false
        #expect(Support.near(maxAlpha(capture(button)), 0.220, 0.03))
    }

    @Test func aPressedArrowIsGrayA12OverGrayA5() {
        let button = backButton()
        button.isHighlighted = true
        #expect(Support.near(maxAlpha(capture(button)), 0.910, 0.03))
    }

    @Test func aPressedBackMovesLeftByAtMostThreePointsScaledAboutTheCentre() {
        let button = backButton()
        let rest = capture(button)
        button.isHighlighted = true
        let pressed = capture(button)
        let shift = Support.inkBounds(pressed, threshold: 0.5).minX - Support.inkBounds(rest, threshold: 0.5).minX
        #expect(shift < 0)
        #expect(shift >= -6)
    }

    @Test func theToolbarsArrowKeepsItsOpaqueTint() {
        let button = NavigationControlButton("Go back", symbol: "arrow.left", history: true)
        button.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        button.appearance = NSAppearance(named: .aqua)
        button.contentTintColor = .black
        #expect(maxAlpha(capture(button)) > 0.97)
    }

    private func chevron() -> NavigationControlButton {
        let chevron = NavigationControlButton("Reload options", symbol: "chevron.down")
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Refresh options button")
        chevron.windowControlStyle = true
        chevron.frame = NSRect(x: 0, y: 0, width: 14, height: 32)
        chevron.appearance = NSAppearance(named: .aqua)
        return chevron
    }

    private func entered() -> NSEvent {
        NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                               eventNumber: 0, trackingNumber: 0, userData: nil)!
    }

    @Test func theChevronIsGrayA11AtRestWithNoFill() {
        let rest = capture(chevron())
        #expect(Support.near(maxAlpha(rest), 0.565, 0.03))
        #expect(rest.colorAt(x: 4, y: 8)!.alphaComponent < 0.01)
    }

    @Test func theChevronFillsGrayA4WhileHovered() {
        let c = chevron()
        c.mouseEntered(with: entered())
        #expect(Support.near(capture(c).colorAt(x: 4, y: 8)!.alphaComponent, 0.071, 0.01))
    }

    @Test func theChevronIsGrayA12WhilePressed() {
        let c = chevron()
        c.mouseEntered(with: entered())
        c.isHighlighted = true
        #expect(Support.near(maxAlpha(capture(c)), 0.910, 0.03))
    }

    @Test func thereIsNoHoverFillWhileDisabled() {
        let c = chevron()
        c.mouseEntered(with: entered())
        c.isHighlighted = false
        c.isEnabled = false
        #expect(capture(c).colorAt(x: 4, y: 8)!.alphaComponent < 0.01)
    }

    @Test(arguments: [RoundedCornerStyle.continuous, .circular])
    func theHoverPlateIsContinuousSixPointCornersNotCircular(style: RoundedCornerStyle) {
        let plateView = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        plateView.appearance = NSAppearance(named: .aqua)
        let plateFace = TranslucentButtonFace(view: plateView)
        plateFace.setHovered(true)
        let plate = Support.render(plateView.bounds.size) { plateFace.draw(in: plateView.bounds, enabled: true, view: plateView) { _ in } }
        let reference = Support.render(plateView.bounds.size) {
            Support.light.hoveredBackground.setFill()
            let context = NSGraphicsContext.current!.cgContext
            context.addPath(Path(roundedRect: plateView.bounds, cornerRadius: 6, style: style).cgPath)
            context.fillPath()
        }
        var worst: CGFloat = 0
        for y in 0..<plate.pixelsHigh {
            for x in 0..<plate.pixelsWide { worst = max(worst, abs(plate.colorAt(x: x, y: y)!.alphaComponent - reference.colorAt(x: x, y: y)!.alphaComponent)) }
        }
        #expect(style == .continuous ? worst < 0.005 : worst > 0.01)
    }

    @Test func hoveringTheButtonHoversItsFace() {
        let faced = ActionButton("Hide sidebar")
        faced.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        faced.appearance = NSAppearance(named: .aqua)
        faced.translucentFace = TranslucentButtonFace(view: faced)
        faced.mouseEntered(with: entered())
        #expect(Support.near(capture(faced).colorAt(x: 32, y: 32)!.alphaComponent, 0.071, 0.01))
    }

    @Test func refreshHoverClearsTheFaceWithoutAWindow() {
        let faced = ActionButton("Hide sidebar")
        faced.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        faced.appearance = NSAppearance(named: .aqua)
        faced.translucentFace = TranslucentButtonFace(view: faced)
        faced.mouseEntered(with: entered())
        faced.refreshHover()
        #expect(capture(faced).colorAt(x: 32, y: 32)!.alphaComponent < 0.01)
    }
}
