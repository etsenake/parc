import AppKit
import QuartzCore
import Testing
@testable import Parc

private final class ActivityWindow: NSWindow {
    var key = true
    var main = true
    override var isKeyWindow: Bool { key }
    override var isMainWindow: Bool { main }
}

@Suite(.serialized) @MainActor
struct FavoriteTileSelectionTests {
    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }
    private func alpha(_ color: CGColor?) -> CGFloat? { color.map(\.alpha) }

    @MainActor private final class Lit {
        let browser = ActivityWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 120),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        let other = ActivityWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 120),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        let tile = FavoriteTile(title: "Highlighted Favorite", monogram: "H", url: "https://example.test")
        let badgeImage = NSImage(size: NSSize(width: 16, height: 16))
        let maxContrast = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        var overlays: FavoriteTileOverlays { tile.overlays }

        init(attached: Bool = true, reduceMotion: Bool? = nil) {
            SystemOverrides.install()
            SystemOverrides.reduceMotion = reduceMotion
            browser.isReleasedWhenClosed = false
            other.isReleasedWhenClosed = false
            tile.frame = NSRect(x: 20, y: 20, width: 60, height: 47)
            tile.applyPalette(isDark: false, glyphColor: .black, highlightColor: maxContrast)
            tile.selected = true
            if attached {
                browser.contentView!.addSubview(tile)
                browser.contentView!.layoutSubtreeIfNeeded()
            }
        }

        deinit {
            SystemOverrides.reduceMotion = nil
            MainActor.assumeIsolated {
                browser.close()
                other.close()
            }
        }

        func loseKey() {
            browser.key = false
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: browser)
        }

        func loseMain() {
            browser.main = false
            NotificationCenter.default.post(name: NSWindow.didResignMainNotification, object: browser)
        }

        func inactive() {
            loseKey()
            loseMain()
        }

        func undimmed(dark: Bool) -> Bool {
            !tile.dimmed && tile.shadowLayer.shadowOpacity == 0.1 && !tile.shadowLayer.isHidden
                && abs((tile.selectionFill.backgroundColor?.alpha ?? -1) - (dark ? 0.45 : 0.8)) < 0.0001
                && tile.washLayer.opacity == (dark ? 0.2 : 0) && !tile.outlineImage.isHidden
                && tile.outlineLayer.backgroundColor == nil
        }

        func dimmedStyle(dark: Bool) -> Bool {
            tile.dimmed && tile.shadowLayer.shadowOpacity == 0 && !tile.selectionFill.isHidden
                && abs((tile.selectionFill.backgroundColor?.alpha ?? -1) - (dark ? 0.225 : 0.4)) < 0.0001
                && tile.washLayer.opacity == 0 && tile.outlineImage.isHidden && !tile.outlineLayer.isHidden
                && abs((tile.outlineLayer.backgroundColor?.alpha ?? -1) - 0.2) < 0.0001
        }
    }

    @Test func aDetachedTileIsNotDimmed() {
        let lit = Lit(attached: false)
        #expect(!lit.tile.dimmed)
    }

    @Test func aKeyAndMainWindowShowsTheUndimmedSelectedTile() {
        let lit = Lit()
        #expect(lit.undimmed(dark: false))
    }

    @Test func theOutlineImageSitsInsideTheMaskedRing() {
        let lit = Lit()
        #expect(lit.tile.outlineImage.superlayer === lit.tile.outlineLayer)
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
        #expect(close(color.redComponent, 0))
        #expect(close(color.greenComponent, 0))
        #expect(close(color.blueComponent, 0))
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

    private func ring(of lit: Lit) -> FavoriteHighlightRingView? {
        lit.tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: lit.badgeImage)))
        lit.tile.setKeyboardHighlighted(true)
        lit.browser.contentView!.layoutSubtreeIfNeeded()
        return lit.overlays.ringView
    }

    @Test func noRingExistsUntilHighlighted() {
        let lit = Lit(reduceMotion: true)
        #expect(lit.overlays.ringView == nil)
        #expect(!lit.overlays.highlighted)
    }

    @Test func aHighlightCoversTheTileBoundsWithARing() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(ring(of: lit))
        #expect(lit.overlays.highlighted)
        #expect(ring.superview === lit.tile)
        #expect(!ring.isHidden)
        #expect(ring.frame == lit.tile.bounds)
    }

    @Test(arguments: [0, 1])
    func eachRingLayerIsATwoPointStrokeInsetOneWithRadiusEleven(index: Int) throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(ring(of: lit))
        let shape = [ring.ring, ring.foreground][index]
        #expect(shape.lineWidth == 2)
        #expect(shape.fillColor == nil)
        #expect(shape.frame == ring.bounds)
        #expect(shape.path == FavoriteTilePaths.highlightRing(bounds: ring.bounds))
    }

    @Test func aHighlightStrokesOnlyTheBackgroundLayer() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(ring(of: lit))
        #expect(ring.foreground.strokeColor == nil)
    }

    @Test func theRingStrokesThePaletteMaxContrastColour() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(ring(of: lit))
        let stroke = try #require(ring.ring.strokeColor)
        let color = try #require(NSColor(cgColor: stroke)?.usingColorSpace(.sRGB))
        #expect(close(color.redComponent, 0.1))
        #expect(close(color.greenComponent, 0.2))
        #expect(close(color.blueComponent, 0.3))
    }

    @Test func recordingSitsBelowTheRingWhichSitsBelowTheBadge() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(ring(of: lit))
        let views = lit.tile.subviews
        let dot = views.firstIndex { $0 === lit.overlays.dotView }
        let badge = views.firstIndex { $0 === lit.overlays.badgeView }
        let ringIndex = views.firstIndex { $0 === ring }
        #expect(dot! < ringIndex!)
        #expect(ringIndex! < badge!)
    }

    @Test func theRingNeverTakesThePointerOrAccessibility() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(ring(of: lit))
        #expect(ring.hitTest(NSPoint(x: 1, y: 1)) == nil)
        #expect(!ring.isAccessibilityElement())
        #expect(lit.tile.hitTest(lit.tile.convert(NSPoint(x: 1, y: 20), to: lit.tile.superview)) === lit.tile)
    }

    @Test func theRingAppearsWithoutAnimation() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(ring(of: lit))
        #expect(ring.ring.animationKeys() == nil)
        #expect(ring.layer?.animationKeys() == nil)
    }

    @Test func aRepeatedHighlightKeepsTheRing() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(ring(of: lit))
        lit.tile.setKeyboardHighlighted(true)
        #expect(lit.overlays.ringView === ring)
        #expect(!ring.isHidden)
    }

    @Test func anUnhighlightedRingHides() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(ring(of: lit))
        lit.tile.setKeyboardHighlighted(false)
        #expect(lit.overlays.ringView === ring)
        #expect(ring.isHidden)
        #expect(!lit.overlays.highlighted)
    }

    @Test func aLaterHighlightReusesTheRing() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(ring(of: lit))
        lit.tile.setKeyboardHighlighted(false)
        lit.tile.setKeyboardHighlighted(true)
        #expect(lit.overlays.ringView === ring)
        #expect(!ring.isHidden)
    }

    @Test func withoutAPaletteColourTheDarkRingIsWhite() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(ring(of: lit))
        lit.tile.applyPalette(isDark: true, glyphColor: .white)
        let stroke = try #require(ring.ring.strokeColor)
        #expect(NSColor(cgColor: stroke)?.usingColorSpace(.sRGB).map { close($0.redComponent, 1) } == true)
    }

    @Test func withoutAPaletteColourTheLightRingIsBlack() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(ring(of: lit))
        lit.tile.applyPalette(isDark: false, glyphColor: .black)
        let stroke = try #require(ring.ring.strokeColor)
        #expect(NSColor(cgColor: stroke)?.usingColorSpace(.sRGB).map { close($0.redComponent, 0) } == true)
    }

    @Test func theRingFollowsTheTileSize() throws {
        let lit = Lit(reduceMotion: true)
        let ring = try #require(ring(of: lit))
        lit.tile.frame.size = NSSize(width: 80, height: 47)
        lit.browser.contentView!.layoutSubtreeIfNeeded()
        #expect(ring.frame == lit.tile.bounds)
        #expect(ring.ring.path == FavoriteTilePaths.highlightRing(bounds: ring.bounds))
    }

    private func developerRing(_ lit: Lit) throws -> FavoriteHighlightRingView {
        let ring = try #require(ring(of: lit))
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
        let ring = try #require(ring(of: lit))
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
        #expect(ring.ring.strokeColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }.map { close($0.redComponent, 0) } == true)
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

    private func layoutWrites(_ view: NSView) -> Int {
        GeometryWrites.install()
        return GeometryWrites.layerWrites(by: view) { view.layout() }.count
    }

    @Test func theFirstRecordingDotLayoutWritesItsLayers() {
        SystemOverrides.install()
        let dot = FavoriteRecordingDotView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        #expect(layoutWrites(dot) > 0)
    }

    @Test func aNoOpRecordingDotLayoutSkipsTheRewrite() {
        let dot = FavoriteRecordingDotView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        _ = layoutWrites(dot)
        #expect(layoutWrites(dot) == 0)
    }

    @Test func aRecordingDotBoundsChangeStillRewritesLayers() {
        let dot = FavoriteRecordingDotView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        _ = layoutWrites(dot)
        dot.setFrameSize(NSSize(width: 10, height: 10))
        #expect(layoutWrites(dot) > 0)
    }

    @Test func aFollowUpRecordingDotLayoutAtTheNewSizeIsANoOp() {
        let dot = FavoriteRecordingDotView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        _ = layoutWrites(dot)
        dot.setFrameSize(NSSize(width: 10, height: 10))
        _ = layoutWrites(dot)
        #expect(layoutWrites(dot) == 0)
    }

    @Test func reduceMotionArmsNoRecordingDotPulse() {
        let host = PulseHost(reduceMotion: true)
        host.window.contentView!.addSubview(host.dot)
        #expect(host.dot.pulse == nil)
    }

    @Test func theRecordingDotPulseStillArmsAfterLayoutSkips() {
        let host = PulseHost(reduceMotion: false)
        host.window.contentView!.addSubview(host.dot)
        #expect(host.dot.pulse != nil)
    }

    @Test func aLayoutSkipLeavesThePulseAnimationInstalled() {
        let host = PulseHost(reduceMotion: false)
        host.window.contentView!.addSubview(host.dot)
        _ = layoutWrites(host.dot)
        #expect(layoutWrites(host.dot) == 0)
        #expect(host.dot.pulse != nil)
    }

    @MainActor private final class PulseHost {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 40, height: 40),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let dot = FavoriteRecordingDotView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))

        init(reduceMotion: Bool) {
            SystemOverrides.install()
            SystemOverrides.reduceMotion = reduceMotion
            window.isReleasedWhenClosed = false
        }

        deinit {
            SystemOverrides.reduceMotion = nil
            MainActor.assumeIsolated { window.close() }
        }
    }

    private func isolatedRing() -> FavoriteHighlightRingView {
        let ring = FavoriteHighlightRingView(frame: CGRect(x: 0, y: 0, width: 60, height: 47))
        ring.style = .highlight(NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        return ring
    }

    @Test func theFirstHighlightRingLayoutWritesItsLayers() {
        let ring = isolatedRing()
        #expect(layoutWrites(ring) > 0)
    }

    @Test func aNoOpHighlightRingLayoutSkipsTheRewriteAndLeavesTheStyle() {
        let ring = isolatedRing()
        _ = layoutWrites(ring)
        let strokeBefore = ring.ring.strokeColor
        #expect(layoutWrites(ring) == 0)
        #expect(ring.ring.strokeColor === strokeBefore)
    }

    @Test func aHighlightRingBoundsChangeStillRewritesThePath() {
        let ring = isolatedRing()
        _ = layoutWrites(ring)
        ring.setFrameSize(NSSize(width: 80, height: 47))
        #expect(layoutWrites(ring) > 0)
        #expect(ring.ring.path == FavoriteTilePaths.highlightRing(bounds: ring.bounds))
    }

    @Test func aFollowUpHighlightRingLayoutAtTheNewSizeIsANoOp() {
        let ring = isolatedRing()
        _ = layoutWrites(ring)
        ring.setFrameSize(NSSize(width: 80, height: 47))
        _ = layoutWrites(ring)
        #expect(layoutWrites(ring) == 0)
    }

    @Test func styleChangesStayUngatedByTheLayoutSkip() {
        let ring = isolatedRing()
        _ = layoutWrites(ring)
        ring.style = .developerTab
        #expect(ring.ring.strokeColor == NSColor.black.cgColor)
        #expect(ring.foreground.lineDashPattern == [6, 6])
    }
}
