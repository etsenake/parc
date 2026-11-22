import AppKit
import QuartzCore
import Testing
@testable import ParcSidebar

@MainActor
struct FavoriteTileSelectionTestsDeveloperModeTests {
    private typealias Support = FavoriteTileSelectionTestsSupport
    private typealias Lit = Support.Lit

    private func developerRing(_ lit: Lit) throws -> FavoriteHighlightRingView {
        let ring = try #require(Support.ring(of: lit))
        lit.tile.setKeyboardHighlighted(false)
        lit.tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: lit.badgeImage), developerTab: true))
        return ring
    }

    private func isDeveloperStyle(_ ring: FavoriteHighlightRingView, in lit: Lit) -> Bool {
        var yellow: CGColor?
        lit.tile.effectiveAppearance.performAsCurrentDrawingAppearance { yellow = NSColor.systemYellow.cgColor }
        return !ring.isHidden && ring.ring.strokeColor == NSColor.black.cgColor && ring.foreground.strokeColor == yellow
            && ring.foreground.lineDashPattern == [6, 6]
    }

    @Test func noHighlightAndNoDeveloperTabHidesTheRing() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(Support.ring(of: lit))
        lit.tile.setKeyboardHighlighted(false)
        #expect(ring.isHidden)
    }

    @Test func aSelectedDeveloperTabIsBlackUnderAYellowDash() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try developerRing(lit)
        #expect(lit.overlays.ringView === ring)
        #expect(isDeveloperStyle(ring, in: lit))
    }

    @Test func aHighlightTakesPriorityOverTheDeveloperTabStyle() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try developerRing(lit)
        lit.tile.applyPalette(isDark: false, glyphColor: .black)
        lit.tile.setKeyboardHighlighted(true)
        #expect(!ring.isHidden)
        #expect(ring.foreground.strokeColor == nil)
        #expect(ring.ring.strokeColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }.map { Support.close($0.redComponent, 0) } == true)
    }

    @Test func droppingTheHighlightReturnsToTheDeveloperTabStyle() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try developerRing(lit)
        lit.tile.setKeyboardHighlighted(true)
        lit.tile.setKeyboardHighlighted(false)
        #expect(isDeveloperStyle(ring, in: lit))
    }

    @Test func anUnselectedDeveloperTabShowsNoRing() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try developerRing(lit)
        lit.tile.selected = false
        #expect(ring.isHidden)
    }

    @Test func reselectingShowsTheDeveloperTabRingAgain() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try developerRing(lit)
        lit.tile.selected = false
        lit.tile.selected = true
        #expect(isDeveloperStyle(ring, in: lit))
    }

    @Test func leavingDeveloperModeHidesTheRing() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try developerRing(lit)
        lit.tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: lit.badgeImage)))
        #expect(ring.isHidden)
        #expect(lit.overlays.ringView === ring)
    }

    @Test func styleChangesAddNoAnimation() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try developerRing(lit)
        lit.tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: lit.badgeImage)))
        #expect(ring.ring.animationKeys() == nil)
        #expect(ring.foreground.animationKeys() == nil)
    }

    @Test func anUnselectedDeveloperTabCreatesNoRing() {
        let lit = Lit(attached: false, reduceMotion: true)
        let fresh = FavoriteTile(title: "Developer Favorite", monogram: "D", url: "http://localhost:3000")
        fresh.frame = NSRect(x: 100, y: 20, width: 60, height: 47)
        lit.browser.contentView!.addSubview(fresh)
        fresh.setOverlays(FavoriteTileOverlayState(developerTab: true))
        #expect(fresh.overlays.ringView == nil)
    }

    @Test func selectingADeveloperTabCreatesTheRingLazily() {
        let lit = Lit(attached: false, reduceMotion: true)
        let fresh = FavoriteTile(title: "Developer Favorite", monogram: "D", url: "http://localhost:3000")
        fresh.frame = NSRect(x: 100, y: 20, width: 60, height: 47)
        lit.browser.contentView!.addSubview(fresh)
        fresh.setOverlays(FavoriteTileOverlayState(developerTab: true))
        fresh.selected = true
        #expect(fresh.overlays.ringView?.isHidden == false)
        #expect(fresh.overlays.ringView?.style == .developerTab)
    }
}
