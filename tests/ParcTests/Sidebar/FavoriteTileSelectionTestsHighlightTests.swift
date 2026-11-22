import AppKit
import QuartzCore
import Testing
@testable import Parc

@MainActor
struct FavoriteTileSelectionTestsHighlightTests {
    private typealias Support = FavoriteTileSelectionTestsSupport
    private typealias Lit = Support.Lit

    @Test func noRingExistsUntilHighlighted() {
        let lit = Lit(reduceMotion: true)
        #expect(lit.overlays.ringView == nil)
        #expect(!lit.overlays.highlighted)
    }

    @Test func aHighlightCoversTheTileBoundsWithARing() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        #expect(lit.overlays.highlighted)
        #expect(ring.superview === lit.tile)
        #expect(!ring.isHidden)
        #expect(ring.frame == lit.tile.bounds)
    }

    @Test(arguments: [0, 1])
    func eachRingLayerIsATwoPointStrokeInsetOneWithRadiusEleven(index: Int) throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        let shape = [ring.ring, ring.foreground][index]
        #expect(shape.lineWidth == 2)
        #expect(shape.fillColor == nil)
        #expect(shape.frame == ring.bounds)
        #expect(shape.path == FavoriteTilePaths.highlightRing(bounds: ring.bounds))
    }

    @Test func aHighlightStrokesOnlyTheBackgroundLayer() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        #expect(ring.foreground.strokeColor == nil)
    }

    @Test func theRingStrokesThePaletteMaxContrastColour() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        let stroke = try #require(ring.ring.strokeColor)
        let color = try #require(NSColor(cgColor: stroke)?.usingColorSpace(.sRGB))
        #expect(Support.close(color.redComponent, 0.1))
        #expect(Support.close(color.greenComponent, 0.2))
        #expect(Support.close(color.blueComponent, 0.3))
    }

    @Test func recordingSitsBelowTheRingWhichSitsBelowTheBadge() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        let views = lit.tile.subviews
        let dot = views.firstIndex { $0 === lit.overlays.dotView }
        let badge = views.firstIndex { $0 === lit.overlays.badgeView }
        let ringIndex = views.firstIndex { $0 === ring }
        #expect(dot! < ringIndex!)
        #expect(ringIndex! < badge!)
    }

    @Test func theRingNeverTakesThePointerOrAccessibility() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        #expect(ring.hitTest(NSPoint(x: 1, y: 1)) == nil)
        #expect(!ring.isAccessibilityElement())
        #expect(lit.tile.hitTest(lit.tile.convert(NSPoint(x: 1, y: 20), to: lit.tile.superview)) === lit.tile)
    }

    @Test func theRingAppearsWithoutAnimation() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        #expect(ring.ring.animationKeys() == nil)
        #expect(ring.layer?.animationKeys() == nil)
    }

    @Test func aRepeatedHighlightKeepsTheRing() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        lit.tile.setKeyboardHighlighted(true)
        #expect(lit.overlays.ringView === ring)
        #expect(!ring.isHidden)
    }

    @Test func anUnhighlightedRingHides() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        lit.tile.setKeyboardHighlighted(false)
        #expect(lit.overlays.ringView === ring)
        #expect(ring.isHidden)
        #expect(!lit.overlays.highlighted)
    }

    @Test func aLaterHighlightReusesTheRing() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        lit.tile.setKeyboardHighlighted(false)
        lit.tile.setKeyboardHighlighted(true)
        #expect(lit.overlays.ringView === ring)
        #expect(!ring.isHidden)
    }

    @Test func withoutAPaletteColourTheDarkRingIsWhite() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        lit.tile.applyPalette(isDark: true, glyphColor: .white)
        let stroke = try #require(ring.ring.strokeColor)
        #expect(NSColor(cgColor: stroke)?.usingColorSpace(.sRGB).map { Support.close($0.redComponent, 1) } == true)
    }

    @Test func withoutAPaletteColourTheLightRingIsBlack() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        lit.tile.applyPalette(isDark: false, glyphColor: .black)
        let stroke = try #require(ring.ring.strokeColor)
        #expect(NSColor(cgColor: stroke)?.usingColorSpace(.sRGB).map { Support.close($0.redComponent, 0) } == true)
    }

    @Test func theRingFollowsTheTileSize() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        lit.tile.frame.size = NSSize(width: 80, height: 47)
        lit.browser.contentView!.layoutSubtreeIfNeeded()
        #expect(ring.frame == lit.tile.bounds)
        #expect(ring.ring.path == FavoriteTilePaths.highlightRing(bounds: ring.bounds))
    }
}
