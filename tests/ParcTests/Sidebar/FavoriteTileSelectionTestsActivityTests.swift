import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcSidebar

@MainActor
struct FavoriteTileSelectionTestsActivityTests {
    private typealias Support = FavoriteTileSelectionTestsSupport
    private typealias Lit = Support.Lit

    @Test func aDetachedTileIsNotDimmed() {
        let lit = Lit(attached: false)
        #expect(!lit.tile.dimmed)
    }

    @Test func aKeyAndMainWindowShowsTheUndimmedSelectedTile() {
        let lit = Lit()
        #expect(lit.undimmed(dark: false))
    }

    @Test func theOutlineImageSitsInsideTheOutlineLayer() {
        let lit = Lit()
        #expect(lit.tile.outlineImage.superlayer === lit.tile.outlineLayer)
    }

    @Test func theOutlineLayerHasAMask() {
        let lit = Lit()
        #expect(lit.tile.outlineLayer.mask != nil)
    }

    @Test func mainWithoutKeyStaysUndimmed() {
        let lit = Lit()
        lit.loseKey()
        #expect(lit.undimmed(dark: false))
    }

    @Test func neitherKeyNorMainHalvesTheFillAndDropsWashAndShadow() {
        let lit = Lit()
        lit.inactive()
        #expect(lit.dimmedStyle(dark: false))
    }

    @Test func theMutedOutlineUsesThePaletteTitleColour() throws {
        let lit = Lit()
        lit.inactive()
        let background = try #require(lit.tile.outlineLayer.backgroundColor)
        let color = try #require(NSColor(cgColor: background)?.usingColorSpace(.sRGB))
        #expect(Support.close(color.redComponent, 0))
        #expect(Support.close(color.greenComponent, 0))
        #expect(Support.close(color.blueComponent, 0))
    }

    @Test func dimChangesApplyWithoutAnimation() {
        let lit = Lit()
        lit.inactive()
        #expect(lit.tile.washLayer.animation(forKey: "wash") == nil)
        #expect(lit.tile.selectionFill.animationKeys() == nil)
        #expect(lit.tile.shadowLayer.animationKeys() == nil)
        #expect(lit.tile.outlineLayer.animationKeys() == nil)
    }

    @Test func aDarkDimmedFillIsPointFortyFiveTimesAHalf() {
        let lit = Lit()
        lit.inactive()
        lit.tile.applyPalette(isDark: true, glyphColor: .white, highlightColor: lit.maxContrast)
        #expect(lit.dimmedStyle(dark: true))
    }

    @Test func anotherWindowsActivityIsIgnored() {
        let lit = Lit()
        lit.inactive()
        lit.browser.key = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: lit.other)
        #expect(lit.tile.dimmed)
    }

    @Test func becomingKeyUndimsAtOnce() {
        let lit = Lit()
        lit.inactive()
        lit.tile.applyPalette(isDark: true, glyphColor: .white, highlightColor: lit.maxContrast)
        lit.browser.key = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: lit.browser)
        #expect(lit.undimmed(dark: true))
    }

    @Test func mainAloneKeepsTheTileUndimmed() {
        let lit = Lit()
        lit.inactive()
        lit.tile.applyPalette(isDark: true, glyphColor: .white, highlightColor: lit.maxContrast)
        lit.browser.main = true
        NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: lit.browser)
        #expect(lit.undimmed(dark: true))
    }

    @Test func leavingTheWindowClearsTheDim() {
        let lit = Lit()
        lit.inactive()
        lit.tile.removeFromSuperview()
        #expect(!lit.tile.dimmed)
    }

    @Test func enteringAnInactiveWindowDimsAtOnce() {
        let lit = Lit(attached: false)
        lit.browser.key = false
        lit.browser.main = false
        lit.browser.contentView!.addSubview(lit.tile)
        #expect(lit.dimmedStyle(dark: false))
    }

    @Test func dimNeverShowsTheSelectedLayersOfAnUnselectedTile() {
        let lit = Lit()
        lit.inactive()
        lit.tile.selected = false
        #expect(lit.tile.selectionFill.isHidden)
        #expect(lit.tile.shadowLayer.isHidden)
        #expect(lit.tile.outlineLayer.isHidden)
    }
}
