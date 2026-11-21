import AppKit
import QuartzCore
import Testing
@testable import Parc

@Suite(.serialized) @MainActor
struct FavoriteTileOverlayTests {
    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }

    @MainActor private final class Overlay {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 120),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let tile = FavoriteTile(title: "Original Favorite", monogram: "O", url: "https://open.spotify.com")
        let first = NSImage(size: NSSize(width: 16, height: 16))
        let second = NSImage(size: NSSize(width: 16, height: 16))
        var overlays: FavoriteTileOverlays { tile.overlays }

        init(reduceMotion: Bool = false, attached: Bool = true) {
            SystemOverrides.install()
            SystemOverrides.reduceMotion = reduceMotion
            window.isReleasedWhenClosed = false
            tile.frame = NSRect(x: 20, y: 20, width: 60, height: 47)
            tile.applyPalette(isDark: false, glyphColor: .labelColor)
            if attached {
                window.contentView!.addSubview(tile)
                tile.layoutSubtreeIfNeeded()
            }
        }

        deinit {
            SystemOverrides.reduceMotion = nil
            MainActor.assumeIsolated { window.close() }
        }

        func state(recording: Bool = true, badge: NSImage?? = .none, music: Bool = false) -> FavoriteTileOverlayState {
            FavoriteTileOverlayState(recording: recording, badge: badge.map { FavoriteTileBadge(favicon: $0) }, music: music)
        }

        func show(recording: Bool = true, badge: NSImage?? = .none, music: Bool = false) {
            tile.setOverlays(state(recording: recording, badge: badge, music: music))
        }
    }

    @Test func tileGeometryIsFlipped() {
        let overlay = Overlay()
        #expect(overlay.tile.isFlipped)
    }

    @Test func theRecordingDotIsPlacedInTheTile() {
        let overlay = Overlay()
        overlay.show()
        let dot = overlay.overlays.dotView
        #expect(dot?.superview === overlay.tile)
        #expect(dot?.frame == CGRect(x: 46, y: 33, width: 8, height: 8))
    }

    @Test func theRecordingDotPulsesBetweenPointFourAndOneEveryThreeQuartersOfASecond() {
        let overlay = Overlay()
        overlay.show()
        let pulse = overlay.overlays.dotView?.pulse as? CABasicAnimation
        #expect(pulse?.fromValue as? Double == 0.4)
        #expect(pulse?.toValue == nil)
        #expect(pulse?.duration == 0.75)
        #expect(pulse?.autoreverses == true)
        #expect(pulse?.repeatCount == .infinity)
        #expect(pulse?.timingFunction == CAMediaTimingFunction(name: .easeInEaseOut))
    }

    @Test func theRecordingDotNeverTakesThePointer() {
        let overlay = Overlay()
        overlay.show()
        #expect(overlay.overlays.dotView?.hitTest(NSPoint(x: 4, y: 4)) == nil)
        #expect(overlay.tile.hitTest(overlay.tile.convert(NSPoint(x: 50, y: 37), to: overlay.tile.superview)) === overlay.tile)
    }

    @Test func theSameRecordingValueKeepsTheDotAndItsPulse() {
        let overlay = Overlay()
        overlay.show()
        let dot = overlay.overlays.dotView
        let pulse = dot?.pulse
        overlay.show()
        #expect(overlay.overlays.dotView === dot)
        #expect(dot?.pulse === pulse)
    }

    @Test func theBadgeIsPlacedFlippedBesideTheTile() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        let badge = overlay.overlays.badgeView
        #expect(badge?.frame == CGRect(x: 44, y: -4, width: 20, height: 20))
        #expect(badge?.isFlipped == true)
    }

    @Test func theBadgeSpringsIn() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        let layer = overlay.overlays.badgeView?.layer
        #expect(overlay.overlays.badgeShown)
        #expect(layer?.opacity == 1)
        #expect(layer?.animation(forKey: "badge_transform") != nil)
        #expect(layer?.animation(forKey: "badge_opacity") != nil)
    }

    @Test func theShowUsesTheRecoveredSpring() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        let spring = overlay.overlays.badgeView?.layer?.animation(forKey: "badge_transform") as? CASpringAnimation
        #expect(spring.map { close($0.damping, 4 * .pi * 0.6 / 0.4) } == true)
    }

    @Test func theBadgePivotsOnItsCentre() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        let layer = overlay.overlays.badgeView?.layer
        #expect(layer?.anchorPoint == CGPoint(x: 0.5, y: 0.5))
        #expect(layer?.position == CGPoint(x: 54, y: 6))
    }

    @Test func theBadgeShowsThePeekFavicon() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        #expect(overlay.overlays.badgeView?.icon.contents as? NSImage === overlay.first)
    }

    @Test func theBadgeHasItsCornerAndShadow() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        let layer = overlay.overlays.badgeView?.layer
        #expect(layer?.cornerRadius == 6)
        #expect(layer?.shadowOpacity == 0.25)
        #expect(layer?.shadowRadius == 4)
        #expect(layer?.shadowOffset == CGSize(width: 0, height: 1.5))
        #expect(layer?.masksToBounds == false)
    }

    @Test func theBadgeNeverTakesThePointer() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        #expect(overlay.overlays.badgeView?.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }

    @Test func theSameBadgeImageDoesNotRestartTheSprings() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        let badge = overlay.overlays.badgeView
        let show = badge?.layer?.animation(forKey: "badge_transform")
        overlay.show(badge: overlay.first)
        #expect(overlay.overlays.badgeView === badge)
        #expect(badge?.layer?.animation(forKey: "badge_transform") === show)
    }

    @Test func anImageChangeIsAnInstantSwap() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        let badge = overlay.overlays.badgeView
        overlay.show(badge: overlay.second)
        #expect(overlay.overlays.badgeView === badge)
        #expect(badge?.icon.contents as? NSImage === overlay.second)
        #expect(badge?.icon.animationKeys() == nil)
    }

    @Test func aNewImageRerunsTheShowTowardIdentity() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        let badge = overlay.overlays.badgeView
        let show = badge?.layer?.animation(forKey: "badge_transform")
        overlay.show(badge: overlay.second)
        let reshow = badge?.layer?.animation(forKey: "badge_transform") as? CASpringAnimation
        #expect(reshow != nil)
        #expect(reshow !== show)
        #expect(overlay.overlays.badgeShown)
        #expect(badge?.layer?.opacity == 1)
        #expect((reshow?.toValue as? NSValue).map { CATransform3DIsIdentity($0.caTransform3DValue) } == true)
    }

    @Test func noPeekFaviconShowsParcsEmptyPageGlyph() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        overlay.show(badge: .some(nil))
        #expect(overlay.overlays.badgeView?.icon.contents as? NSImage === FavoriteTileOverlayLayers.emptyPage(dark: false))
    }

    @Test func theParticlesArePlacedBeyondTheTile() {
        let overlay = Overlay()
        overlay.show(badge: overlay.second, music: true)
        overlay.window.contentView!.layoutSubtreeIfNeeded()
        let particles = overlay.overlays.particlesView
        #expect(particles?.superview === overlay.tile)
        #expect(particles?.frame == CGRect(x: -30, y: -38, width: 120, height: 107))
    }

    @Test func theTileDoesNotClipTheParticles() {
        let overlay = Overlay()
        overlay.show(badge: overlay.second, music: true)
        #expect(overlay.tile.layer?.masksToBounds == false)
    }

    @Test func theEmitterIsCentredInItsView() {
        let overlay = Overlay()
        overlay.show(badge: overlay.second, music: true)
        overlay.window.contentView!.layoutSubtreeIfNeeded()
        #expect(overlay.overlays.particlesView?.emitter.emitterPosition == CGPoint(x: 60, y: 53.5))
    }

    @Test func theSameMusicValueAndAppearanceKeepTheEmitter() {
        let overlay = Overlay()
        overlay.show(badge: overlay.second, music: true)
        let particles = overlay.overlays.particlesView
        let cell = particles?.emitter.emitterCells?.first
        overlay.show(badge: overlay.second, music: true)
        overlay.tile.applyPalette(isDark: false, glyphColor: .labelColor)
        overlay.tile.applyPalette(isDark: false, glyphColor: .labelColor)
        #expect(overlay.overlays.particlesView === particles)
        #expect(particles?.emitter.emitterCells?.first === cell)
    }

    @Test func recordingSitsBelowTheBadgeWhichSitsBelowMusic() {
        let overlay = Overlay()
        overlay.show(badge: overlay.second, music: true)
        let views = overlay.tile.subviews
        let dot = views.firstIndex { $0 === overlay.overlays.dotView }
        let badge = views.firstIndex { $0 === overlay.overlays.badgeView }
        let particles = views.firstIndex { $0 === overlay.overlays.particlesView }
        #expect(views.compactMap { $0 as? FavoriteRecordingDotView }.count == 1)
        #expect(dot! < badge!)
        #expect(badge! < particles!)
    }

    @Test func anAppearanceChangeRebuildsTheParticles() {
        let overlay = Overlay()
        overlay.show(badge: overlay.second, music: true)
        let particles = overlay.overlays.particlesView
        overlay.tile.applyPalette(isDark: true, glyphColor: .white)
        #expect(overlay.overlays.particlesView !== particles)
        #expect(overlay.overlays.particlesView?.isDark == true)
    }

    @Test func theBadgeFillFollowsTheAppearance() {
        let overlay = Overlay()
        overlay.show(badge: overlay.second, music: true)
        overlay.tile.applyPalette(isDark: true, glyphColor: .white)
        let badge = overlay.overlays.badgeView
        #expect(badge?.isDark == true)
        #expect(NSColor(cgColor: badge!.layer!.backgroundColor!)?.usingColorSpace(.sRGB)?.redComponent == 0)
    }

    @Test func occlusionAndHidingLeaveTheEmitter() {
        let overlay = Overlay()
        overlay.show(badge: overlay.second, music: true)
        let particles = overlay.overlays.particlesView
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: overlay.window)
        overlay.tile.isHidden = true
        overlay.tile.isHidden = false
        #expect(overlay.overlays.particlesView === particles)
        #expect(particles?.superview === overlay.tile)
    }

    @Test func everyEffectiveAppearanceChangeRebuildsRunningParticles() {
        let overlay = Overlay()
        overlay.show(badge: overlay.second, music: true)
        overlay.tile.applyPalette(isDark: true, glyphColor: .white)
        let darkParticles = overlay.overlays.particlesView
        overlay.tile.viewDidChangeEffectiveAppearance()
        #expect(overlay.overlays.particlesView !== darkParticles)
        #expect(darkParticles?.superview == nil)
        #expect(overlay.overlays.particlesView?.superview === overlay.tile)
        #expect(overlay.overlays.particlesView?.isDark == true)
    }

    @Test func reduceMotionShowsNoParticles() {
        let overlay = Overlay(reduceMotion: true)
        overlay.show(badge: overlay.second, music: true)
        #expect(overlay.overlays.particlesView == nil)
    }

    @Test func ineligibleMusicRemovesTheEmitter() {
        let overlay = Overlay()
        overlay.show(badge: overlay.second, music: true)
        overlay.show(badge: overlay.second)
        #expect(overlay.overlays.particlesView == nil)
    }

    @Test func theBadgeCollapsesTowardTheTileCentre() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        let badge = overlay.overlays.badgeView
        let show = badge?.layer?.animation(forKey: "badge_transform")
        overlay.show()
        let hide = badge?.layer?.animation(forKey: "badge_transform") as? CASpringAnimation
        #expect(overlay.overlays.badgeView === badge)
        #expect(!overlay.overlays.badgeShown)
        #expect(badge?.layer?.opacity == 0)
        #expect(hide !== show)
        #expect((hide?.toValue as? NSValue)?.caTransform3DValue.m11 == 0.1)
    }

    @Test func aShowDuringTheHideReusesTheBadge() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        let badge = overlay.overlays.badgeView
        overlay.show()
        overlay.show(badge: overlay.first)
        #expect(overlay.overlays.badgeView === badge)
        #expect(overlay.overlays.badgeShown)
        #expect(badge?.layer?.opacity == 1)
    }

    @Test func recordingOffRemovesTheDotAtOnce() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        let dot = overlay.overlays.dotView
        overlay.show(recording: false, badge: overlay.first)
        #expect(overlay.overlays.dotView == nil)
        #expect(dot?.superview == nil)
    }

    @Test func aRemovedDotLeavesNoPulseRunning() {
        let overlay = Overlay()
        overlay.show()
        let dot = overlay.overlays.dotView
        overlay.show(recording: false)
        #expect(dot?.pulse == nil)
    }

    @Test func withoutAWindowTheBadgeIsRemovedAtOnce() {
        let overlay = Overlay()
        overlay.show(badge: overlay.first)
        let badge = overlay.overlays.badgeView
        overlay.tile.removeFromSuperview()
        overlay.tile.setOverlays(.none)
        #expect(overlay.overlays.badgeView == nil)
        #expect(badge?.superview == nil)
    }

    @Test func eligibilityAloneCreatesTheEmitter() {
        let overlay = Overlay()
        overlay.tile.removeFromSuperview()
        overlay.tile.setOverlays(FavoriteTileOverlayState(music: true))
        #expect(overlay.overlays.particlesView?.superview === overlay.tile)
    }
}
