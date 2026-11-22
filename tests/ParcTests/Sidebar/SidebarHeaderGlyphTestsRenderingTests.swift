import AppKit
import SwiftUI
import Testing
@testable import Parc

@MainActor
struct SidebarHeaderGlyphTestsRenderingTests {
    private typealias Support = SidebarHeaderGlyphTestsSupport
    private typealias Face = Support.Face

    private typealias Chrome = SidebarChromeLayout

    private func gray(_ color: NSColor, white: CGFloat, alpha: CGFloat) -> Bool {
        let c = color.usingColorSpace(.sRGB)!
        return Support.near(c.redComponent, white) && Support.near(c.greenComponent, white) && Support.near(c.blueComponent, white) && Support.near(c.alphaComponent, alpha)
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

    private let dark = TranslucentButtonColors.standard(dark: true)

    @Test func grayA11IsTheRestForeground() {
        #expect(gray(Support.light.foreground, white: 0, alpha: 0.565))
        #expect(gray(dark.foreground, white: 1, alpha: 0.592))
    }

    @Test func grayA8IsTheDisabledForeground() {
        #expect(gray(Support.light.disabledForeground, white: 0, alpha: 0.220))
        #expect(gray(dark.disabledForeground, white: 1, alpha: 0.249))
    }

    @Test func grayA4IsTheHoverPlate() {
        #expect(gray(Support.light.hoveredBackground, white: 0, alpha: 0.071))
        #expect(gray(dark.hoveredBackground, white: 1, alpha: 0.077))
    }

    @Test func grayA5IsThePressedPlate() {
        #expect(gray(Support.light.pressedBackground, white: 0, alpha: 0.090))
        #expect(gray(dark.pressedBackground, white: 1, alpha: 0.103))
    }

    @Test func grayA12IsThePressedForeground() {
        #expect(gray(Support.light.pressedForeground, white: 0, alpha: 0.910))
        #expect(gray(dark.pressedForeground, white: 1, alpha: 0.923))
    }

    @Test func disabledWinsOverHoverAndPress() {
        #expect(Support.light.background(hovered: true, pressed: true, enabled: false) == Support.light.disabledBackground)
    }

    @Test func theFaceHasSixPointCornersAndAPointNinetyFivePress() {
        #expect(TranslucentButtonFace.cornerRadius == 6)
        #expect(TranslucentButtonFace.pressedScale == 0.95)
    }

    @Test func thePressUsesTheRecoveredSpring() {
        #expect(TranslucentButtonFace.pressResponse == 0.3)
        #expect(TranslucentButtonFace.pressDamping == 0.6)
    }

    @Test func theFaceHoverLastsOneTenthOfASecond() {
        #expect(TranslucentButtonFace.hoverDuration == 0.1)
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
        #expect(Support.near(f.draw().fill, 0.071, 0.01))
    }

    @Test func aWindowlessPressIsImmediate() {
        let f = Face()
        f.face.setHovered(true)
        f.face.setPressed(true)
        #expect(f.face.pressProgress == 1)
    }

    @Test func thePressedForegroundIsGrayA12() {
        let f = Face()
        f.face.setPressed(true)
        #expect(gray(f.face.foreground(enabled: true, in: f.view), white: 0, alpha: 0.910))
    }

    @Test func aDisabledFaceIgnoresThePress() {
        let f = Face()
        f.face.setPressed(true)
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
        #expect(gray(TranslucentButtonFace.blend(.clear, Support.light.hoveredBackground, 0.5), white: 0, alpha: 0.0355))
    }

    @Test func easeInEndsAtZeroAndOne() {
        #expect(TranslucentButtonFace.easeIn(0) == 0)
        #expect(TranslucentButtonFace.easeIn(1) == 1)
    }

    @Test func easeInMatchesCAMediaTimingFunctionAtTheMidpoint() {
        #expect(Support.near(TranslucentButtonFace.easeIn(0.5), 0.3153, 0.001))
    }

    @Test func aPressedFaceFillsGrayA5AndLeavesTheEdgeClear() {
        let f = Face()
        f.face.setHovered(true)
        f.face.setPressed(true)
        let pressed = f.draw()
        #expect(Support.near(pressed.fill, 0.090, 0.01))
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
            let ink = Support.inkBounds(Support.render(f.view.bounds.size) { glyph.draw(in: f.view.bounds, tint: .black, in: f.view) })
            return ink.maxX - ink.minX
        }
        let regularWidth = width()
        glyph.pointSize = 14
        #expect(regularWidth > 0)
        #expect(width() < regularWidth)
    }
}
