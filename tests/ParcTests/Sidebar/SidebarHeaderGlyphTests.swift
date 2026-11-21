import AppKit
import SwiftUI
import Testing
@testable import Parc

@MainActor
struct SidebarHeaderGlyphTests {
    typealias Chrome = SidebarChromeLayout

    private func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.0005) -> Bool { abs(a - b) <= e }

    private func gray(_ color: NSColor, white: CGFloat, alpha: CGFloat) -> Bool {
        let c = color.usingColorSpace(.sRGB)!
        return near(c.redComponent, white) && near(c.greenComponent, white) && near(c.blueComponent, white) && near(c.alphaComponent, alpha)
    }

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

    private func render(_ size: NSSize, _ draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func inkBounds(_ rep: NSBitmapImageRep, threshold: CGFloat = 0.2) -> (minX: Int, maxX: Int) {
        var minX = Int.max, maxX = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where rep.colorAt(x: x, y: y)!.alphaComponent > threshold { minX = min(minX, x); maxX = max(maxX, x) }
        }
        return (minX, maxX)
    }

    @Test func navigationGlyphsAreSixteenAndFourteenPoints() {
        #expect(Chrome.navigationGlyphPointSize == 16)
        #expect(Chrome.narrowNavigationGlyphPointSize == 14)
    }

    @Test func regularButtonsUseTheThirtyTwoGlyphAndNarrowOnesTheTwentyEight() {
        #expect(Chrome.navigationGlyphPointSize(buttonSide: 32) == 16)
        #expect(Chrome.navigationGlyphPointSize(buttonSide: 28) == 14)
    }

    @Test func theNineteenPointThinReloadStaysSixteen() {
        let bar = Chrome.toolbar(width: 228, windowButtons: CGSize(width: 60, height: 14), showsNavigation: true, developerReload: true)
        #expect(bar.reload.map { Chrome.navigationGlyphPointSize(buttonSide: $0.height) } == 16)
    }

    @Test func theNarrowRowDrawsFourteenPointGlyphs() {
        let bar = Chrome.toolbar(width: 200, windowButtons: CGSize(width: 60, height: 14), showsNavigation: true)
        #expect(bar.back.map { Chrome.navigationGlyphPointSize(buttonSide: $0.height) } == 14)
    }

    @Test func theAddressTextMatchesCommandBarPlaceholderTextView() {
        #expect(Chrome.addressFontSize == 13)
        #expect(Chrome.addressTextIndent == 12)
    }

    @Test func aGlyphIsAOneXAndTwoXTemplate() {
        let regular = NavigationControlArtwork.symbol("arrow.left", pointSize: 16)
        #expect(regular?.isTemplate == true)
        #expect(regular?.representations.count == 2)
    }

    @Test func aGlyphHasAWholePointFrame() {
        let regular = NavigationControlArtwork.symbol("arrow.left", pointSize: 16)
        #expect(regular.map { $0.size.width == $0.size.width.rounded() && $0.size.height == $0.size.height.rounded() } == true)
    }

    @Test func fourteenPointsDrawsSmallerThanSixteen() {
        let regular = NavigationControlArtwork.symbol("arrow.left", pointSize: 16)
        let small = NavigationControlArtwork.symbol("arrow.left", pointSize: 14)
        #expect((small?.size.width ?? 99) < (regular?.size.width ?? 0))
    }

    @Test func glyphsAreCachedPerSymbolAndSize() {
        #expect(NavigationControlArtwork.symbol("arrow.left", pointSize: 16) === NavigationControlArtwork.symbol("arrow.left", pointSize: 16))
    }

    private let light = TranslucentButtonColors.standard(dark: false)
    private let dark = TranslucentButtonColors.standard(dark: true)

    @Test func grayA11IsTheRestForeground() {
        #expect(gray(light.foreground, white: 0, alpha: 0.565))
        #expect(gray(dark.foreground, white: 1, alpha: 0.592))
    }

    @Test func grayA8IsTheDisabledForeground() {
        #expect(gray(light.disabledForeground, white: 0, alpha: 0.220))
        #expect(gray(dark.disabledForeground, white: 1, alpha: 0.249))
    }

    @Test func grayA4IsTheHoverPlate() {
        #expect(gray(light.hoveredBackground, white: 0, alpha: 0.071))
        #expect(gray(dark.hoveredBackground, white: 1, alpha: 0.077))
    }

    @Test func grayA5IsThePressedPlate() {
        #expect(gray(light.pressedBackground, white: 0, alpha: 0.090))
        #expect(gray(dark.pressedBackground, white: 1, alpha: 0.103))
    }

    @Test func grayA12IsThePressedForeground() {
        #expect(gray(light.pressedForeground, white: 0, alpha: 0.910))
        #expect(gray(dark.pressedForeground, white: 1, alpha: 0.923))
    }

    @Test func disabledWinsOverHoverAndPress() {
        #expect(light.background(hovered: true, pressed: true, enabled: false) == light.disabledBackground)
    }

    @Test func theFaceHasSixPointCornersAndAPointNinetyFivePress() {
        #expect(TranslucentButtonFace.cornerRadius == 6)
        #expect(TranslucentButtonFace.pressedScale == 0.95)
    }

    @Test func thePressSpringAndHoverTimingAreFixed() {
        #expect(TranslucentButtonFace.pressResponse == 0.3)
        #expect(TranslucentButtonFace.pressDamping == 0.6)
        #expect(TranslucentButtonFace.hoverDuration == 0.1)
    }

    @MainActor private final class Face {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        let face: TranslucentButtonFace

        init() {
            view.appearance = NSAppearance(named: .aqua)
            face = TranslucentButtonFace(view: view)
        }

        func draw() -> (fill: CGFloat, edge: CGFloat, tint: NSColor?) {
            var tint: NSColor?
            let size = view.bounds.size
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            face.draw(in: view.bounds, enabled: true, view: view) { tint = $0 }
            NSGraphicsContext.restoreGraphicsState()
            return (rep.colorAt(x: 32, y: 32)!.alphaComponent, rep.colorAt(x: 0, y: 32)!.alphaComponent, tint)
        }
    }

    @Test func theFaceStartsAtRest() {
        let f = Face()
        #expect(f.draw().fill < 0.01)
        #expect(f.face.pressProgress == 0)
    }

    @Test func theRestForegroundIsGrayA11() {
        let f = Face()
        #expect(gray(f.face.foreground(enabled: true, in: f.view), white: 0, alpha: 0.565))
    }

    @Test func theDisabledForegroundIsGrayA8() {
        let f = Face()
        #expect(gray(f.face.foreground(enabled: false, in: f.view), white: 0, alpha: 0.220))
    }

    @Test func aWindowlessHoverIsImmediate() {
        let f = Face()
        f.face.setHovered(true)
        #expect(near(f.draw().fill, 0.071, 0.01))
    }

    @Test func aWindowlessPressIsImmediate() {
        let f = Face()
        f.face.setHovered(true)
        f.face.setPressed(true)
        #expect(f.face.pressProgress == 1)
    }

    @Test func thePressedForegroundIsGrayA12AndDisabledIgnoresThePress() {
        let f = Face()
        f.face.setPressed(true)
        #expect(gray(f.face.foreground(enabled: true, in: f.view), white: 0, alpha: 0.910))
        #expect(gray(f.face.foreground(enabled: false, in: f.view), white: 0, alpha: 0.220))
    }

    @Test func darkAquaResolvesWhite() {
        let f = Face()
        f.face.setPressed(true)
        f.view.appearance = NSAppearance(named: .darkAqua)
        #expect(gray(f.face.foreground(enabled: true, in: f.view), white: 1, alpha: 0.923))
    }

    @Test func releaseReturnsToRest() {
        let f = Face()
        f.face.setHovered(true)
        f.face.setPressed(true)
        f.face.setPressed(false)
        f.face.setHovered(false)
        #expect(f.face.pressProgress == 0)
        #expect(f.draw().fill < 0.01)
    }

    @Test func aClearEndBlendsAlphaOnly() {
        #expect(gray(TranslucentButtonFace.blend(.clear, light.hoveredBackground, 0.5), white: 0, alpha: 0.0355))
    }

    @Test func easeInEndsAtZeroAndOne() {
        #expect(TranslucentButtonFace.easeIn(0) == 0)
        #expect(TranslucentButtonFace.easeIn(1) == 1)
    }

    @Test func easeInMatchesCAMediaTimingFunctionAtTheMidpoint() {
        #expect(near(TranslucentButtonFace.easeIn(0.5), 0.3153, 0.001))
    }

    @Test func aPressedFaceFillsGrayA5AndLeavesTheEdgeClear() {
        let f = Face()
        f.face.setHovered(true)
        f.face.setPressed(true)
        let pressed = f.draw()
        #expect(near(pressed.fill, 0.090, 0.01))
        #expect(pressed.edge < 0.01)
    }

    @Test func theGlyphClosureReceivesGrayA12WhenPressed() {
        let f = Face()
        f.face.setHovered(true)
        f.face.setPressed(true)
        #expect(f.draw().tint.map { gray($0, white: 0, alpha: 0.910) } == true)
    }

    @Test func theReloadPressTransform() {
        #expect(ReloadGlyph.pressedRotation == .pi / 2)
        #expect(ReloadGlyph.pressedOffset == 1)
    }

    @Test func aNarrowReloadReRendersAtFourteenPoints() {
        let f = Face()
        let glyph = ReloadGlyph(view: f.view, pointSize: 16, rasterized: true)
        func width() -> Int {
            let ink = inkBounds(render(f.view.bounds.size) { glyph.draw(in: f.view.bounds, tint: .black, in: f.view) })
            return ink.maxX - ink.minX
        }
        let regularWidth = width()
        glyph.pointSize = 14
        #expect(regularWidth > 0)
        #expect(width() < regularWidth)
    }

    @Test func thePillHasTwelvePointCornersAndAHundredTwentyMillisecondHover() {
        #expect(SidebarAddressPillView.cornerRadius == 12)
        #expect(SidebarAddressPillView.hoverDuration == 0.12)
    }

    private func p3(_ color: NSColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let c = color.usingColorSpace(.displayP3)!
        return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    @Test func sidebarItemBackgroundLightAndItsHoveredAlpha() {
        let rest = p3(SidebarAddressPillView.fill(dark: false, hovered: false))
        #expect(near(rest.0, 0.055) && near(rest.1, 0.059) && near(rest.2, 0.063) && near(rest.3, 0.05))
        #expect(near(p3(SidebarAddressPillView.fill(dark: false, hovered: true)).3, 0.1))
    }

    @Test func sidebarItemBackgroundDarkAndItsHoveredAlpha() {
        let rest = p3(SidebarAddressPillView.fill(dark: true, hovered: false))
        #expect(near(rest.0, 0.98) && near(rest.2, 1) && near(rest.3, 0.1))
        #expect(near(p3(SidebarAddressPillView.fill(dark: true, hovered: true)).3, 0.15))
    }

    @Test func thePillIsAContinuousTwelvePointMask() {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 212, height: 36))
        #expect(pill.layer?.cornerRadius == 12)
        #expect(pill.layer?.cornerCurve == .continuous)
        #expect(pill.layer?.masksToBounds == true)
    }

    @Test func thePillFillsRestHoverAndDark() {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 212, height: 36))
        #expect(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: false, hovered: false).cgColor)
        pill.setHovered(true)
        #expect(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: false, hovered: true).cgColor)
        pill.dark = true
        #expect(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: true, hovered: true).cgColor)
    }

    @Test func theSurfaceTakesNoClicks() {
        #expect(SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 212, height: 36)).hitTest(NSPoint(x: 10, y: 10)) == nil)
    }

    @Test(arguments: [(false, false, false, false), (false, false, false, true), (false, false, true, false), (false, false, true, true),
                      (false, true, false, false), (false, true, false, true), (false, true, true, false), (false, true, true, true),
                      (true, false, false, false), (true, false, false, true), (true, false, true, false), (true, false, true, true),
                      (true, true, false, false), (true, true, false, true), (true, true, true, false), (true, true, true, true)])
    func theRevealPredicateShowsTheButtonsForHoverMenuUnanchoredOrVoiceOver(hovered: Bool, menu: Bool, anchored: Bool, voiceOver: Bool) {
        #expect(SidebarAddressButtonsReveal.revealed(sidebarHovered: hovered, showingMenu: menu, anchored: anchored, voiceOverRunning: voiceOver)
                == (hovered || menu || !anchored || voiceOver))
    }

    @Test(arguments: [(false, false, true, true), (true, false, true, false), (false, true, true, false), (false, false, false, false)])
    func anExtensionPopupLoadingIsOnlyAnUnattachedUnseenWindowShowingItsPage(attached: Bool, visible: Bool, showsPage: Bool, loading: Bool) {
        #expect(SidebarAddressButtonsReveal.extensionPopupLoading(attached: attached, visible: visible, showsPage: showsPage) == loading)
    }

    @Test(arguments: [(false, false, false), (false, true, true), (true, false, true)])
    func siteControlCenterShowsWhenRevealedOrAQuoteLinkKeepsIt(revealed: Bool, quote: Bool, shows: Bool) {
        #expect(SidebarAddressButtonsReveal.showsSiteControlCenter(revealed: revealed, copyQuoteLink: quote) == shows)
    }

    @Test func theFadeIsFifteenHundredthsOfASecond() {
        #expect(SidebarAddressButtonsReveal.fadeDuration == 0.15)
    }

    @Test func aWindowlessHideIsImmediateAndKeepsTheViewInTheTree() {
        let button = NSView(frame: NSRect(x: 0, y: 0, width: 25, height: 28))
        SidebarAddressButtonsReveal.apply(false, to: button, animated: true)
        #expect(button.alphaValue == 0)
        #expect(!button.isHidden)
    }

    @Test func revealRestoresFullOpacity() {
        let button = NSView(frame: NSRect(x: 0, y: 0, width: 25, height: 28))
        SidebarAddressButtonsReveal.apply(false, to: button, animated: true)
        SidebarAddressButtonsReveal.apply(true, to: button, animated: true)
        #expect(button.alphaValue == 1)
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
        #expect(near(reloadAlpha(toolbar, NSColor(white: 0, alpha: 0.5), in: flipped), 0.5, 0.02))
    }

    @Test(arguments: [0.565, 0.910])
    func theSidebarReloadKeepsItsAlpha(alpha: Double) {
        let flipped = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        let glyph = ReloadGlyph(view: flipped, pointSize: 16, rasterized: true)
        #expect(near(reloadAlpha(glyph, NSColor(white: 0, alpha: CGFloat(alpha)), in: flipped), CGFloat(alpha), 0.02))
    }

    private func backButton() -> NavigationControlButton {
        let button = NavigationControlButton("Go back", symbol: "arrow.left", history: true, glyphPointSize: 16)
        button.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        button.appearance = NSAppearance(named: .aqua)
        return button
    }

    @Test func theArrowAtRestIsGrayA11() {
        #expect(near(maxAlpha(capture(backButton())), 0.565, 0.03))
    }

    @Test func aDisabledArrowIsGrayA8() {
        let button = backButton()
        button.isEnabled = false
        #expect(near(maxAlpha(capture(button)), 0.220, 0.03))
    }

    @Test func aPressedArrowIsGrayA12OverGrayA5() {
        let button = backButton()
        button.isHighlighted = true
        #expect(near(maxAlpha(capture(button)), 0.910, 0.03))
    }

    @Test func aPressedBackMovesLeftByAtMostThreePointsScaledAboutTheCentre() {
        let button = backButton()
        let rest = capture(button)
        button.isHighlighted = true
        let pressed = capture(button)
        let shift = inkBounds(pressed, threshold: 0.5).minX - inkBounds(rest, threshold: 0.5).minX
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
        #expect(near(maxAlpha(rest), 0.565, 0.03))
        #expect(rest.colorAt(x: 4, y: 8)!.alphaComponent < 0.01)
    }

    @Test func theChevronFillsGrayA4WhileHovered() {
        let c = chevron()
        c.mouseEntered(with: entered())
        #expect(near(capture(c).colorAt(x: 4, y: 8)!.alphaComponent, 0.071, 0.01))
    }

    @Test func theChevronIsGrayA12WhilePressed() {
        let c = chevron()
        c.mouseEntered(with: entered())
        c.isHighlighted = true
        #expect(near(maxAlpha(capture(c)), 0.910, 0.03))
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
        let plate = render(plateView.bounds.size) { plateFace.draw(in: plateView.bounds, enabled: true, view: plateView) { _ in } }
        let reference = render(plateView.bounds.size) {
            light.hoveredBackground.setFill()
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
        #expect(near(capture(faced).colorAt(x: 32, y: 32)!.alphaComponent, 0.071, 0.01))
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

    @MainActor private final class Faded {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        let pageButton = ActionButton("Site Control Center")
        let toolbarView = ExtensionToolbarView(frame: NSRect(x: 40, y: 5, width: 56, height: 28))

        init() {
            pageButton.frame = NSRect(x: 10, y: 5, width: 25, height: 28)
            host.addSubview(pageButton)
            host.addSubview(toolbarView)
            pageButton.alphaValue = 0
            toolbarView.alphaValue = 0
        }
    }

    @Test func transparentButtonsAndToolbarsHitTestByDefault() {
        let f = Faded()
        #expect(f.pageButton.hitTest(NSPoint(x: 20, y: 15)) === f.pageButton)
        #expect(f.toolbarView.hitTest(NSPoint(x: 60, y: 15)) === f.toolbarView)
    }

    @Test func aFadedSiteControlCenterButtonAndPinnedExtensionsPassClicksThrough() {
        let f = Faded()
        f.pageButton.hitTestsWhenTransparent = false
        f.toolbarView.hitTestsWhenTransparent = false
        #expect(f.pageButton.hitTest(NSPoint(x: 20, y: 15)) == nil)
        #expect(f.toolbarView.hitTest(NSPoint(x: 60, y: 15)) == nil)
    }

    @Test func revealedButtonsTakeClicks() {
        let f = Faded()
        f.pageButton.hitTestsWhenTransparent = false
        f.toolbarView.hitTestsWhenTransparent = false
        f.pageButton.alphaValue = 1
        f.toolbarView.alphaValue = 1
        #expect(f.pageButton.hitTest(NSPoint(x: 20, y: 15)) === f.pageButton)
        #expect(f.toolbarView.hitTest(NSPoint(x: 60, y: 15)) === f.toolbarView)
    }

    @Test func aSharedQuotePillHasTheEarlierSevenPointCornersAndTheThemesHoverFill() {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 200, height: 18))
        let hoverFill = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4)
        pill.style = .sharedQuote(fill: hoverFill)
        #expect(pill.layer?.cornerRadius == 7)
        #expect(pill.layer?.cornerCurve == .circular)
        #expect(pill.layer?.backgroundColor == hoverFill.cgColor)
        pill.setHovered(true)
        #expect(pill.layer?.backgroundColor == hoverFill.cgColor)
    }

    @Test func backToTheURLBarTheFillAndCornersReturn() {
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 200, height: 18))
        pill.style = .sharedQuote(fill: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4))
        pill.setHovered(true)
        pill.style = .urlBar
        #expect(pill.layer?.cornerRadius == 12)
        #expect(pill.layer?.cornerCurve == .continuous)
        #expect(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: false, hovered: true).cgColor)
    }

    @Test func anotherPopoverClosingKeepsTheHold() {
        let center = NotificationCenter.default
        var ended = 0
        let hold = AddressPopoverRevealHold { ended += 1 }
        let prompt = NSPopover()
        let other = NSPopover()
        center.post(name: NSPopover.willShowNotification, object: prompt)
        center.post(name: NSPopover.willShowNotification, object: other)
        center.post(name: NSPopover.didCloseNotification, object: other)
        #expect(ended == 0)
        center.post(name: NSPopover.didCloseNotification, object: prompt)
        #expect(ended == 1)
        withExtendedLifetime(hold) {}
    }

    @Test func endedHoldsIgnoreLaterPopovers() {
        let center = NotificationCenter.default
        var ended = 0
        let hold = AddressPopoverRevealHold { ended += 1 }
        let prompt = NSPopover()
        center.post(name: NSPopover.willShowNotification, object: prompt)
        center.post(name: NSPopover.didCloseNotification, object: prompt)
        center.post(name: NSPopover.willShowNotification, object: prompt)
        center.post(name: NSPopover.didCloseNotification, object: prompt)
        #expect(ended == 1)
        withExtendedLifetime(hold) {}
    }

    @MainActor private final class Popup {
        let center = NotificationCenter.default
        let popupWindow = Popup.window()
        let otherWindow = Popup.window()
        let browserWindow = Popup.window()

        static func window() -> NSWindow {
            let result = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: true)
            result.isReleasedWhenClosed = false
            return result
        }

        init() { browserWindow.addChildWindow(popupWindow, ordered: .above) }
        deinit { MainActor.assumeIsolated { browserWindow.removeChildWindow(popupWindow) } }
    }

    @Test func aPagePopupInThisBrowserWindowPlacedAtTheSidebarTakesAHold() {
        let p = Popup()
        #expect(SidebarAddressButtonsReveal.holdsExtensionPopup(p.popupWindow, of: p.browserWindow, showsPage: true, atSidebar: true))
    }

    @Test func aChildWindowWithoutAPageTakesNoHold() {
        let p = Popup()
        #expect(!SidebarAddressButtonsReveal.holdsExtensionPopup(p.popupWindow, of: p.browserWindow, showsPage: false, atSidebar: true))
    }

    @Test func aPopupPlacedAwayFromTheSidebarTakesNoHold() {
        let p = Popup()
        #expect(!SidebarAddressButtonsReveal.holdsExtensionPopup(p.popupWindow, of: p.browserWindow, showsPage: true, atSidebar: false))
    }

    @Test func anotherWindowsPopupTakesNoHold() {
        let p = Popup()
        #expect(!SidebarAddressButtonsReveal.holdsExtensionPopup(p.otherWindow, of: p.browserWindow, showsPage: true, atSidebar: true))
    }

    @Test func anAttachedPopupIsOpenAndOneWhoseBrowserWindowIsGoneIsNot() {
        let p = Popup()
        #expect(SidebarAddressButtonsReveal.extensionPopupOpen(p.popupWindow, of: p.browserWindow))
        #expect(!SidebarAddressButtonsReveal.extensionPopupOpen(p.popupWindow, of: nil))
    }

    @Test func aPopupTheEngineDetachedIsClosed() {
        let p = Popup()
        p.browserWindow.removeChildWindow(p.popupWindow)
        #expect(!SidebarAddressButtonsReveal.extensionPopupOpen(p.popupWindow, of: p.browserWindow))
    }

    @Test func anExtensionPopupThatLosesFocusButStaysOpenKeepsItsHold() {
        let p = Popup()
        var ended = 0
        let open = true
        let hold = AddressPopoverRevealHold(window: p.popupWindow, isOpen: { $0 === p.popupWindow && open }) { ended += 1 }
        p.center.post(name: NSWindow.didResignKeyNotification, object: p.popupWindow)
        hold.endIfWindowClosed()
        #expect(ended == 0)
    }

    @Test func anotherWindowResigningOrClosingKeepsThePopupsHold() {
        let p = Popup()
        var ended = 0
        let hold = AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in true }) { ended += 1 }
        p.center.post(name: NSWindow.didResignKeyNotification, object: p.otherWindow)
        p.center.post(name: NSWindow.willCloseNotification, object: p.otherWindow)
        #expect(ended == 0)
        withExtendedLifetime(hold) {}
    }

    @Test func aPopupDetachedFromItsBrowserWindowEndsItsHoldAsItLosesFocusAndOnlyOnce() {
        let p = Popup()
        var ended = 0
        let hold = AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in false }) { ended += 1 }
        p.center.post(name: NSWindow.didResignKeyNotification, object: p.popupWindow)
        #expect(ended == 1)
        p.center.post(name: NSWindow.willCloseNotification, object: p.popupWindow)
        hold.endIfWindowClosed()
        #expect(ended == 1)
    }

    @Test func closingThePopupEndsItsHoldWhateverClosedIt() {
        let p = Popup()
        var ended = 0
        let hold = AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in true }) { ended += 1 }
        p.center.post(name: NSWindow.willCloseNotification, object: p.popupWindow)
        #expect(ended == 1)
        withExtendedLifetime(hold) {}
    }

    @Test func aSweepEndsAHoldWhosePopupIsNoLongerOpen() {
        let p = Popup()
        var ended = 0
        let hold = AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in false }) { ended += 1 }
        hold.endIfWindowClosed()
        #expect(ended == 1)
    }

    @Test func aPopupSweepLeavesTheSitePanelsPopoverHoldAlone() {
        let p = Popup()
        var ended = 0
        let hold = AddressPopoverRevealHold { ended += 1 }
        let panel = NSPopover()
        p.center.post(name: NSPopover.willShowNotification, object: panel)
        hold.endIfWindowClosed()
        #expect(ended == 0)
        p.center.post(name: NSPopover.didCloseNotification, object: panel)
        #expect(ended == 1)
    }

    @MainActor private final class Holds {
        var holders = Set<ObjectIdentifier>()

        func shown(voiceOver: Bool = false) -> Bool {
            SidebarAddressButtonsReveal.revealed(sidebarHovered: false, showingMenu: !holders.isEmpty, anchored: true, voiceOverRunning: voiceOver)
        }

        func hold(_ owner: AnyObject, _ make: (@escaping () -> Void) -> AddressPopoverRevealHold) -> AddressPopoverRevealHold {
            holders.insert(ObjectIdentifier(owner))
            return make { [weak self] in self?.holders.remove(ObjectIdentifier(owner)) }
        }
    }

    @Test func aDockedSidebarHidesItsButtonsWithThePointerAwayAndNothingOpen() {
        #expect(!Holds().shown())
    }

    @Test func anOpenExtensionPopupKeepsTheButtonsRevealed() {
        let p = Popup()
        let h = Holds()
        let hold = h.hold(p.popupWindow) { AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in true }, onEnd: $0) }
        #expect(h.shown())
        withExtendedLifetime(hold) {}
    }

    @Test func closingTheSitePanelLeavesThePopupsHoldInPlace() {
        let p = Popup()
        let h = Holds()
        let hold = h.hold(p.popupWindow) { AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in true }, onEnd: $0) }
        let sitePanel = NSPopover()
        let owner = NSObject()
        let siteHold = h.hold(owner) { AddressPopoverRevealHold(onEnd: $0) }
        p.center.post(name: NSPopover.willShowNotification, object: sitePanel)
        p.center.post(name: NSPopover.didCloseNotification, object: sitePanel)
        #expect(h.shown())
        withExtendedLifetime((hold, siteHold)) {}
    }

    @Test func theButtonsFadeOnceThePopupClosesAndVoiceOverStillRevealsThem() {
        let p = Popup()
        let h = Holds()
        var open = true
        let hold = h.hold(p.popupWindow) { AddressPopoverRevealHold(window: p.popupWindow, isOpen: { _ in open }, onEnd: $0) }
        open = false
        p.center.post(name: NSWindow.didResignKeyNotification, object: p.popupWindow)
        #expect(!h.shown())
        #expect(h.shown(voiceOver: true))
        withExtendedLifetime(hold) {}
    }
}
