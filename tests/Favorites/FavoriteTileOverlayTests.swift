import AppKit
import QuartzCore

private final class ActivityWindow: NSWindow {
    var key = true, main = true
    override var isKeyWindow: Bool { key }
    override var isMainWindow: Bool { main }
}

@main struct FavoriteTileOverlayTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        GeometryWrites.install()
        SystemOverrides.install()
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }
        typealias Rules = FavoriteTileOverlayRules

        func music(_ url: String) -> Bool { Rules.isMusicHost(URL(string: url)?.host) }
        check(Rules.musicHosts.count == 8, "Eight recovered music hosts")
        for host in Rules.musicHosts { check(music("https://\(host)/x"), "Exact host \(host)") }
        check(music("https://open.spotify.com/track/1"), "Subdomain of spotify.com")
        check(music("https://www.music.apple.com/album"), "Subdomain of music.apple.com")
        check(music("https://www.nts.live"), "Subdomain of nts.live")
        check(!music("https://youtube.com/watch"), "Only music.youtube.com, not youtube.com")
        check(!music("https://apple.com/music"), "apple.com is not music.apple.com")
        check(!music("https://notspotify.com"), "A lookalike prefix is not a subdomain")
        check(!music("https://spotify.com.example.test"), "A lookalike suffix does not match")
        check(!music("https://example.test/?next=spotify.com"), "Query text never matches")
        check(!music("https://tidal.co"), "A different domain does not match")
        check(!Rules.isMusicHost("SPOTIFY.COM"), "Matching is case-sensitive, as recovered")
        check(!music("about:blank") && !music("file:///tmp/x") && !music("not a url") && !music(""),
              "No host never matches")
        check(!Rules.isMusicHost(nil), "Nil host never matches")

        let spotify = "https://open.spotify.com/playlist/1"
        check(Rules.showsMusic(singlePage: true, status: .active, savedURL: spotify), "Active single-page music Favorite")
        check(!Rules.showsMusic(singlePage: false, status: .active, savedURL: spotify), "Split Favorites never show particles")
        for status in [FavoriteMediaSessionStatus.ducking, .suspended, .inactive] {
            check(!Rules.showsMusic(singlePage: true, status: status, savedURL: spotify), "Status \(status) is not active")
        }
        check(!Rules.showsMusic(singlePage: true, status: nil, savedURL: spotify), "No engine selector keeps particles hidden")
        check(!Rules.showsMusic(singlePage: true, status: .active, savedURL: "https://example.test"), "Saved host off the list")
        check(FavoriteMediaSessionStatus(rawStatus: 0) == .active && FavoriteMediaSessionStatus(rawStatus: 1) == .ducking
              && FavoriteMediaSessionStatus(rawStatus: 2) == .suspended && FavoriteMediaSessionStatus(rawStatus: 3) == .inactive,
              "the media session status order")
        check(FavoriteMediaSessionStatus(rawStatus: 7) == .inactive && FavoriteMediaSessionStatus(rawStatus: -1) == .inactive,
              "Out-of-range status is inactive")

        func recording(camera: Bool = false, microphone: Bool = false, tab: Bool = false, window: Bool = false,
                       display: Bool = false, mirrored: Bool = false, shared: Bool = false) -> Bool {
            Rules.isRecording(camera: camera, microphone: microphone, tab: tab, window: window,
                              display: display, mirrored: mirrored, shared: shared)
        }
        check(recording(camera: true) && recording(microphone: true) && recording(camera: true, microphone: true),
              "Camera or microphone is mediaRecording")
        check(recording(mirrored: true), "Being mirrored is tabCapturing")
        check(!recording(), "No capture, no dot")
        check(!recording(window: true) && !recording(display: true), "Desktop capturing is not tested by the dot")
        check(!recording(tab: true), "Capturing another tab is not this tab being captured")
        check(!recording(shared: true), "A display-media source flag feeds no tested trait")
        check(recording(display: true, mirrored: true), "A tested trait still shows alongside desktop capture")

        typealias G = FavoriteTileOverlayGeometry
        let tileBounds = CGRect(x: 0, y: 0, width: 60, height: 47)
        check(G.dot(in: tileBounds) == CGRect(x: 46, y: 33, width: 8, height: 8), "Dot at (W-14, H-14, 8, 8)")
        check(G.badge(in: tileBounds) == CGRect(x: 44, y: -4, width: 20, height: 20), "Badge at (W-16, -4, 20, 20)")
        check(G.badgeIcon(in: CGRect(x: 0, y: 0, width: 20, height: 20)) == CGRect(x: 2, y: 2, width: 16, height: 16),
              "Centred 16-point badge image")
        check(G.particles(in: tileBounds) == CGRect(x: -30, y: -38, width: 120, height: 107),
              "Particles inset -30 and raised 8")
        check(G.place(G.dot(in: tileBounds), in: tileBounds, flipped: true) == G.dot(in: tileBounds),
              "Flipped hosts use the rectangle directly")
        check(G.place(G.dot(in: tileBounds), in: tileBounds, flipped: false) == CGRect(x: 46, y: 6, width: 8, height: 8),
              "An unflipped host keeps the dot at the bottom-right")
        check(G.place(G.badge(in: tileBounds), in: tileBounds, flipped: false) == CGRect(x: 44, y: 31, width: 20, height: 20),
              "An unflipped host keeps the badge at the top-right")
        let collapsed = G.collapsedBadgeTransform(tileBounds: tileBounds, badgePosition: CGPoint(x: 54, y: 6))
        check(close(collapsed.m11, 0.1) && close(collapsed.m22, 0.1) && close(collapsed.m33, 1), "Collapsed scale 0.1")
        check(close(collapsed.m41, -24) && close(collapsed.m42, 17.5), "Collapsed onto the tile centre")

        let spring = FavoriteTileSpring.make(keyPath: "opacity")
        check(close(spring.mass, 1) && close(spring.stiffness, pow(2 * .pi / 0.4, 2))
              && close(spring.damping, 4 * .pi * 0.6 / 0.4) && close(spring.duration, spring.settlingDuration),
              "Badge spring parameters")

        let configurations = FavoriteParticleCellConfiguration.cells
        check(configurations.map(\.birthRate) == [1.4, 1.0], "Two cells, birth rates 1.4 and 1.0")
        let dark = FavoriteMusicParticlesView(dark: true)
        let light = FavoriteMusicParticlesView(dark: false)
        check(dark.layer === dark.emitter && dark.emitter.emitterShape == .circle
              && dark.emitter.emitterSize == CGSize(width: 6, height: 6), "Circle emitter 6 × 6 as backing layer")
        check(!dark.isFlipped, "Particle view is unflipped so longitude π/2 rises")
        check(dark.emitter.renderMode == .unordered && dark.emitter.emitterMode == .volume
              && dark.emitter.birthRate == 1 && dark.emitter.velocity == 1 && dark.emitter.scale == 1,
              "Emitter-layer properties keep their defaults")
        let cells = dark.emitter.emitterCells ?? []
        check(cells.count == 2 && cells[0].birthRate == 1.4 && cells[1].birthRate == 1.0, "Cells in sprite order")
        for cell in cells {
            check(cell.lifetime == 2 && cell.lifetimeRange == 0, "Lifetime 2 ± 0")
            check(cell.scale == 0 && close(cell.scaleRange, 0.2) && cell.scaleSpeed == 1, "Scale 0 ± 0.2, speed 1")
            check(cell.alphaRange == 0.15 && cell.alphaSpeed == -0.5, "Alpha range 0.15, speed -0.5")
            check(cell.emissionLatitude == 0 && cell.emissionLongitude == .pi / 2
                  && cell.emissionRange == 1.0471975511965976, "Longitude π/2, range π/3")
            check(cell.spin == 0 && cell.spinRange == 0 && cell.xAcceleration == 0 && cell.yAcceleration == 0,
                  "No spin or acceleration")
            check(cell.velocity == 20 && cell.velocityRange == 5, "Velocity 20 ± 5")
            check(cell.contentsScale == 1 && cell.name == nil && cell.zAcceleration == 0, "Unset properties stay default")
            check(cell.contents != nil, "Parc-drawn sprite contents")
        }
        check(NSColor(cgColor: cells[0].color!)?.usingColorSpace(.sRGB).map { close($0.redComponent, 1) && close($0.alphaComponent, 0.8) } == true,
              "Dark tint white 0.8")
        let lightColor = (light.emitter.emitterCells ?? []).first?.color.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
        check(lightColor.map { close($0.redComponent, 0) && close($0.alphaComponent, 0.6) } == true, "Light tint black 0.6")
        check(FavoriteNoteSprites.single.size == NSSize(width: 6, height: 6) && FavoriteNoteSprites.pair.size == NSSize(width: 6, height: 6)
              && FavoriteNoteSprites.single.isTemplate && FavoriteNoteSprites.pair.isTemplate, "Two 6 × 6 template sprites")
        check(FavoriteNoteSprites.single.tiffRepresentation != FavoriteNoteSprites.pair.tiffRepresentation, "Two distinct note shapes")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let tile = FavoriteTile(title: "Original Favorite", monogram: "O", url: "https://open.spotify.com")
        tile.frame = NSRect(x: 20, y: 20, width: 60, height: 47)
        tile.applyPalette(isDark: false, glyphColor: .labelColor)
        let overlays = tile.overlays
        SystemOverrides.reduceMotion = false
        window.contentView!.addSubview(tile)
        tile.layoutSubtreeIfNeeded()
        check(tile.isFlipped, "Tile geometry is flipped")

        tile.setOverlays(FavoriteTileOverlayState(recording: true))
        let dot = overlays.dotView
        let pulse = dot?.pulse as? CABasicAnimation
        check(dot != nil && dot?.superview === tile && dot?.frame == CGRect(x: 46, y: 33, width: 8, height: 8), "Dot placed")
        check(pulse.map { ($0.fromValue as? Double) == 0.4 && $0.toValue == nil && $0.duration == 0.75 && $0.autoreverses
            && $0.repeatCount == .infinity && $0.timingFunction == CAMediaTimingFunction(name: .easeInEaseOut) } == true,
              "Pulse 0.4 ↔ 1, 0.75 s, ease-in-ease-out, autoreversing")
        check(dot?.hitTest(NSPoint(x: 4, y: 4)) == nil && tile.hitTest(tile.convert(NSPoint(x: 50, y: 37), to: tile.superview)) === tile,
              "Dot never takes the pointer")
        tile.setOverlays(FavoriteTileOverlayState(recording: true))
        check(overlays.dotView === dot && dot?.pulse === pulse, "Same recording value keeps the dot and pulse")

        let first = NSImage(size: NSSize(width: 16, height: 16))
        tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: first)))
        let badge = overlays.badgeView
        let show = badge?.layer?.animation(forKey: "badge_transform")
        check(badge?.frame == CGRect(x: 44, y: -4, width: 20, height: 20) && badge?.isFlipped == true, "Badge placed")
        check(overlays.badgeShown && badge?.layer?.opacity == 1 && show != nil
              && badge?.layer?.animation(forKey: "badge_opacity") != nil, "Badge springs in")
        check((show as? CASpringAnimation).map { close($0.damping, 4 * .pi * 0.6 / 0.4) } == true, "Show uses the recovered spring")
        check(badge?.layer?.anchorPoint == CGPoint(x: 0.5, y: 0.5) && badge?.layer?.position == CGPoint(x: 54, y: 6),
              "Badge pivots on its centre")
        check(badge?.icon.contents as? NSImage === first, "Badge shows the Peek favicon")
        check(badge?.layer?.cornerRadius == 6 && badge?.layer?.shadowOpacity == 0.25 && badge?.layer?.shadowRadius == 4
              && badge?.layer?.shadowOffset == CGSize(width: 0, height: 1.5) && badge?.layer?.masksToBounds == false,
              "Badge corner and shadow")
        check(badge?.hitTest(NSPoint(x: 10, y: 10)) == nil, "Badge never takes the pointer")
        tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: first)))
        check(overlays.badgeView === badge && badge?.layer?.animation(forKey: "badge_transform") === show,
              "Same badge image does not restart the springs")
        let second = NSImage(size: NSSize(width: 16, height: 16))
        tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: second)))
        let reshow = badge?.layer?.animation(forKey: "badge_transform") as? CASpringAnimation
        check(overlays.badgeView === badge && badge?.icon.contents as? NSImage === second
              && badge?.icon.animationKeys() == nil, "Image change is an instant swap")
        check(reshow != nil && reshow !== show && overlays.badgeShown && badge?.layer?.opacity == 1
              && (reshow?.toValue as? NSValue).map { CATransform3DIsIdentity($0.caTransform3DValue) } == true,
              "A new image re-runs show() toward identity (ANIM-03)")
        tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: nil)))
        check(badge?.icon.contents as? NSImage === FavoriteTileOverlayLayers.emptyPage(dark: false),
              "No Peek favicon shows Parc's empty-page glyph")

        tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: second), music: true))
        let particles = overlays.particlesView
        window.contentView!.layoutSubtreeIfNeeded()
        check(particles?.superview === tile && particles?.frame == CGRect(x: -30, y: -38, width: 120, height: 107),
              "Particles placed beyond the tile")
        check(tile.layer?.masksToBounds == false, "The tile does not clip the particles")
        check(particles?.emitter.emitterPosition == CGPoint(x: 60, y: 53.5), "Emitter centred in its view")
        let emitterCells = particles?.emitter.emitterCells
        tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: second), music: true))
        tile.applyPalette(isDark: false, glyphColor: .labelColor)
        tile.applyPalette(isDark: false, glyphColor: .labelColor)
        check(overlays.particlesView === particles && particles?.emitter.emitterCells?.first === emitterCells?.first,
              "Same music value and appearance keep the emitter")
        check(tile.subviews.compactMap { $0 as? FavoriteRecordingDotView }.count == 1
              && tile.subviews.firstIndex { $0 === dot }! < tile.subviews.firstIndex { $0 === badge }!
              && tile.subviews.firstIndex { $0 === badge }! < tile.subviews.firstIndex { $0 === particles }!,
              "Recording below badge below music")

        tile.applyPalette(isDark: true, glyphColor: .white)
        check(overlays.particlesView !== particles && overlays.particlesView?.isDark == true, "Appearance rebuilds the particles")
        check(badge?.isDark == true && NSColor(cgColor: badge!.layer!.backgroundColor!)?.usingColorSpace(.sRGB)?.redComponent == 0,
              "Badge fill follows the appearance")
        let darkParticles = overlays.particlesView
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        tile.isHidden = true
        tile.isHidden = false
        check(overlays.particlesView === darkParticles && darkParticles?.superview === tile,
              "occlusion and hiding leave the emitter")
        tile.viewDidChangeEffectiveAppearance()
        check(overlays.particlesView !== darkParticles && darkParticles?.superview == nil
              && overlays.particlesView?.superview === tile && overlays.particlesView?.isDark == true,
              "Every effective-appearance change rebuilds running particles")
        SystemOverrides.reduceMotion = true
        tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: second)))
        tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: second), music: true))
        check(overlays.particlesView == nil, "Reduce Motion shows no particles")
        SystemOverrides.reduceMotion = false
        tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: second)))
        check(overlays.particlesView == nil, "Ineligible music removes the emitter")

        tile.setOverlays(FavoriteTileOverlayState(recording: true))
        let hide = badge?.layer?.animation(forKey: "badge_transform") as? CASpringAnimation
        check(overlays.badgeView === badge && !overlays.badgeShown && badge?.layer?.opacity == 0
              && hide !== show && (hide?.toValue as? NSValue)?.caTransform3DValue.m11 == 0.1,
              "Badge collapses toward the tile centre")
        tile.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: first)))
        check(overlays.badgeView === badge && overlays.badgeShown && badge?.layer?.opacity == 1,
              "A show during the hide reuses the badge")
        tile.setOverlays(FavoriteTileOverlayState(recording: false, badge: FavoriteTileBadge(favicon: first)))
        check(overlays.dotView == nil && dot?.superview == nil, "Recording off removes the dot at once")
        check(dot?.pulse == nil, "A removed dot leaves no pulse running")

        tile.removeFromSuperview()
        tile.setOverlays(.none)
        check(overlays.badgeView == nil && badge?.superview == nil, "Without a window the badge is removed at once")
        tile.setOverlays(FavoriteTileOverlayState(music: true))
        check(overlays.particlesView?.superview === tile, "eligibility alone creates the emitter")
        tile.setOverlays(.none)
        window.close()

        check(Rules.shouldDim(isKey: false, isMain: false) && !Rules.shouldDim(isKey: true, isMain: false)
              && !Rules.shouldDim(isKey: false, isMain: true) && !Rules.shouldDim(isKey: true, isMain: true),
              "shouldDim truth table")
        func alpha(_ color: CGColor?) -> CGFloat? { color.map(\.alpha) }
        let browser = ActivityWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                                     styleMask: [.titled], backing: .buffered, defer: false)
        browser.isReleasedWhenClosed = false
        let other = ActivityWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        let lit = FavoriteTile(title: "Highlighted Favorite", monogram: "H", url: "https://example.test")
        lit.frame = NSRect(x: 20, y: 20, width: 60, height: 47)
        let maxContrast = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        lit.applyPalette(isDark: false, glyphColor: .black, highlightColor: maxContrast)
        lit.selected = true
        check(!lit.dimmed, "A detached tile is not dimmed")
        browser.contentView!.addSubview(lit)
        browser.contentView!.layoutSubtreeIfNeeded()
        func undimmed(dark: Bool) -> Bool {
            !lit.dimmed && lit.shadowLayer.shadowOpacity == 0.1 && !lit.shadowLayer.isHidden
                && close(alpha(lit.selectionFill.backgroundColor) ?? -1, dark ? 0.45 : 0.8)
                && lit.washLayer.opacity == (dark ? 0.2 : 0) && !lit.outlineImage.isHidden
                && lit.outlineLayer.backgroundColor == nil
        }
        func dimmedStyle(dark: Bool) -> Bool {
            lit.dimmed && lit.shadowLayer.shadowOpacity == 0 && !lit.selectionFill.isHidden
                && close(alpha(lit.selectionFill.backgroundColor) ?? -1, dark ? 0.225 : 0.4)
                && lit.washLayer.opacity == 0 && lit.outlineImage.isHidden && !lit.outlineLayer.isHidden
                && close(alpha(lit.outlineLayer.backgroundColor) ?? -1, 0.2)
        }
        check(undimmed(dark: false), "Key and main window: undimmed selected tile")
        check(lit.outlineImage.superlayer === lit.outlineLayer && lit.outlineLayer.mask != nil,
              "Outline image sits inside the masked ring")
        browser.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: browser)
        check(undimmed(dark: false), "Main without key stays undimmed")
        browser.main = false
        NotificationCenter.default.post(name: NSWindow.didResignMainNotification, object: browser)
        check(dimmedStyle(dark: false), "Neither key nor main: fill ×.5, wash and shadow 0, muted outline")
        check(NSColor(cgColor: lit.outlineLayer.backgroundColor!)?.usingColorSpace(.sRGB).map {
            close($0.redComponent, 0) && close($0.greenComponent, 0) && close($0.blueComponent, 0) } == true,
              "Muted outline uses the palette title colour")
        check(lit.washLayer.animation(forKey: "wash") == nil && lit.selectionFill.animationKeys() == nil
              && lit.shadowLayer.animationKeys() == nil && lit.outlineLayer.animationKeys() == nil,
              "Dim changes apply without animation")
        lit.applyPalette(isDark: true, glyphColor: .white, highlightColor: maxContrast)
        check(dimmedStyle(dark: true), "Dark dimmed fill is .45 × .5")
        browser.key = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: other)
        check(lit.dimmed, "Another window's activity is ignored")
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: browser)
        check(undimmed(dark: true), "Becoming key undims at once")
        browser.key = false; browser.main = true
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: browser)
        NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: browser)
        check(undimmed(dark: true), "Main alone keeps the tile undimmed")
        browser.main = false
        lit.removeFromSuperview()
        check(!lit.dimmed, "Leaving the window clears the dim")
        browser.contentView!.addSubview(lit)
        check(dimmedStyle(dark: true), "Entering an inactive window dims at once")
        lit.selected = false
        check(lit.selectionFill.isHidden && lit.shadowLayer.isHidden && lit.outlineLayer.isHidden,
              "Dim never shows the selected layers")
        lit.selected = true
        lit.applyPalette(isDark: false, glyphColor: .black, highlightColor: maxContrast)

        let litOverlays = lit.overlays
        SystemOverrides.reduceMotion = true
        check(litOverlays.ringView == nil && !litOverlays.highlighted, "No ring until highlighted")
        lit.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: first)))
        lit.setKeyboardHighlighted(true)
        browser.contentView!.layoutSubtreeIfNeeded()
        guard let ring = litOverlays.ringView else { preconditionFailure("Highlight creates the ring") }
        check(litOverlays.highlighted && ring.superview === lit && !ring.isHidden && ring.frame == lit.bounds,
              "Ring covers the tile bounds")
        for shape in [ring.ring, ring.foreground] {
            check(shape.lineWidth == 2 && shape.fillColor == nil && shape.frame == ring.bounds
                  && shape.path == FavoriteTilePaths.highlightRing(bounds: ring.bounds), "2-point ring inset 1, radius 11")
        }
        check(ring.foreground.strokeColor == nil, "Highlight strokes only the background layer")
        check(NSColor(cgColor: ring.ring.strokeColor!)?.usingColorSpace(.sRGB).map {
            close($0.redComponent, 0.1) && close($0.greenComponent, 0.2) && close($0.blueComponent, 0.3) } == true,
              "Ring strokes the palette maxContrastColor")
        let litSubviews = lit.subviews
        check(litSubviews.firstIndex { $0 === litOverlays.dotView }! < litSubviews.firstIndex { $0 === ring }!
              && litSubviews.firstIndex { $0 === ring }! < litSubviews.firstIndex { $0 === litOverlays.badgeView }!,
              "Recording below ring below badge")
        check(ring.hitTest(NSPoint(x: 1, y: 1)) == nil && !ring.isAccessibilityElement()
              && lit.hitTest(lit.convert(NSPoint(x: 1, y: 20), to: lit.superview)) === lit,
              "Ring never takes the pointer or accessibility")
        check(ring.ring.animationKeys() == nil && ring.layer?.animationKeys() == nil, "Ring appears without animation")
        lit.setKeyboardHighlighted(true)
        check(litOverlays.ringView === ring && !ring.isHidden, "Repeated highlight keeps the ring")
        lit.setKeyboardHighlighted(false)
        check(litOverlays.ringView === ring && ring.isHidden && !litOverlays.highlighted, "Unhighlighted ring hides")
        lit.setKeyboardHighlighted(true)
        check(litOverlays.ringView === ring && !ring.isHidden, "A later highlight reuses the ring")
        lit.applyPalette(isDark: true, glyphColor: .white)
        check(NSColor(cgColor: ring.ring.strokeColor!)?.usingColorSpace(.sRGB).map { close($0.redComponent, 1) } == true,
              "Without a palette colour the dark ring is white")
        lit.applyPalette(isDark: false, glyphColor: .black)
        check(NSColor(cgColor: ring.ring.strokeColor!)?.usingColorSpace(.sRGB).map { close($0.redComponent, 0) } == true,
              "Without a palette colour the light ring is black")
        lit.frame.size = NSSize(width: 80, height: 47)
        browser.contentView!.layoutSubtreeIfNeeded()
        check(ring.frame == lit.bounds && ring.ring.path == FavoriteTilePaths.highlightRing(bounds: ring.bounds),
              "Ring follows the tile size")

        var yellow: CGColor?
        lit.effectiveAppearance.performAsCurrentDrawingAppearance { yellow = NSColor.systemYellow.cgColor }
        func developerStyle() -> Bool {
            !ring.isHidden && ring.ring.strokeColor == NSColor.black.cgColor && ring.foreground.strokeColor == yellow
                && ring.foreground.lineDashPattern == [6, 6]
        }
        lit.setKeyboardHighlighted(false)
        check(ring.isHidden, "No highlight and no developer tab hides the ring")
        let developer = FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: first), developerTab: true)
        lit.setOverlays(developer)
        check(litOverlays.ringView === ring && developerStyle(), "Selected developer tab: black under a yellow [6, 6] dash")
        lit.setKeyboardHighlighted(true)
        check(!ring.isHidden && ring.foreground.strokeColor == nil
              && NSColor(cgColor: ring.ring.strokeColor!)?.usingColorSpace(.sRGB).map { close($0.redComponent, 0) } == true,
              "Highlight takes priority over the developer-tab style")
        lit.setKeyboardHighlighted(false)
        check(developerStyle(), "Dropping the highlight returns to the developer-tab style")
        lit.selected = false
        check(ring.isHidden, "An unselected developer tab shows no ring")
        lit.selected = true
        check(developerStyle(), "Reselecting shows the developer-tab ring again")
        lit.setOverlays(FavoriteTileOverlayState(recording: true, badge: FavoriteTileBadge(favicon: first)))
        check(ring.isHidden && litOverlays.ringView === ring, "Leaving Developer Mode hides the ring")
        check(ring.ring.animationKeys() == nil && ring.foreground.animationKeys() == nil, "Style changes add no animation")
        let fresh = FavoriteTile(title: "Developer Favorite", monogram: "D", url: "http://localhost:3000")
        fresh.frame = NSRect(x: 100, y: 20, width: 60, height: 47)
        browser.contentView!.addSubview(fresh)
        fresh.setOverlays(FavoriteTileOverlayState(developerTab: true))
        check(fresh.overlays.ringView == nil, "An unselected developer tab creates no ring")
        fresh.selected = true
        check(fresh.overlays.ringView?.isHidden == false && fresh.overlays.ringView?.style == .developerTab,
              "Selecting a developer tab creates the ring lazily")

        typealias Skip = FavoriteOverlayPresentationSkip
        check(Skip.shouldSkip(previous: nil, next: "a") == false, "First fingerprint never skips")
        check(Skip.shouldSkip(previous: "a", next: "a"), "Identical fingerprint skips")
        check(Skip.shouldSkip(previous: "a", next: "b") == false, "Changed fingerprint does not skip")
        check(Skip.shouldSkip(previous: Skip.gatedToken, next: Skip.gatedToken), "Identical gated token skips")
        check(Skip.needsMediaSessionRead(savedURL: spotify, engineRespondsToStatus: true),
              "Listed music host with bridge may read status")
        check(!Skip.needsMediaSessionRead(savedURL: spotify, engineRespondsToStatus: false),
              "Without the bridge, do not read status")
        check(!Skip.needsMediaSessionRead(savedURL: "https://example.test", engineRespondsToStatus: true),
              "Non-music host must not read status (would arm observers)")
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let peek = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let idle = Skip.tileToken(id: id, pageIdentifier: "page-a", recording: false, badge: nil,
                                  developerTab: false, music: false)
        check(Skip.shouldSkip(previous: idle, next: idle), "Idle tile token is a stable no-op")
        let recordingOn = Skip.tileToken(id: id, pageIdentifier: "page-a", recording: true, badge: nil,
                                         developerTab: false, music: false)
        check(!Skip.shouldSkip(previous: idle, next: recordingOn), "Recording bit change must not skip")
        let musicOn = Skip.tileToken(id: id, pageIdentifier: "page-a", recording: false, badge: nil,
                                     developerTab: false, music: true)
        check(!Skip.shouldSkip(previous: idle, next: musicOn), "Music bit change must not skip")
        let badgeA = Skip.badgeToken(peekID: peek, tiffData: Data([1, 2, 3]))
        let badgeB = Skip.badgeToken(peekID: peek, tiffData: Data([1, 2, 4]))
        check(badgeA != badgeB, "Distinct Peek badge pixels produce distinct tokens")
        check(Skip.badgeToken(peekID: peek, tiffData: Data([1, 2, 3])) == badgeA,
              "Same Peek badge pixels are stable")
        check(Skip.tiffDataToken(Data()) == "0.cbf29ce484222325",
              "Empty TIFF token is FNV-1a over zero bytes")

        typealias LayerSkip = FavoriteOverlayLayerLayoutSkip
        let dotBounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        let stroke = FavoriteTileOverlayGeometry.dotStroke
        let matchedOuter = dotBounds
        let matchedInner = dotBounds.insetBy(dx: stroke, dy: stroke)
        check(LayerSkip.shouldSkipDot(
            outerFrame: matchedOuter, innerFrame: matchedInner,
            outerRadius: matchedOuter.height / 2, innerRadius: matchedInner.height / 2,
            bounds: dotBounds), "Matching dot frames/radii skip")
        check(!LayerSkip.shouldSkipDot(
            outerFrame: .zero, innerFrame: matchedInner,
            outerRadius: matchedOuter.height / 2, innerRadius: matchedInner.height / 2,
            bounds: dotBounds), "Mismatched outer frame does not skip")
        check(!LayerSkip.shouldSkipDot(
            outerFrame: matchedOuter, innerFrame: matchedInner,
            outerRadius: 0, innerRadius: matchedInner.height / 2,
            bounds: dotBounds), "Mismatched outer radius does not skip")
        let ringBounds = CGRect(x: 0, y: 0, width: 60, height: 47)
        let ringPath = FavoriteTilePaths.highlightRing(bounds: ringBounds)
        check(LayerSkip.shouldSkipRing(
            ringFrame: ringBounds, foregroundFrame: ringBounds,
            ringPath: ringPath, foregroundPath: ringPath,
            bounds: ringBounds, path: ringPath), "Matching ring frames/paths skip")
        check(!LayerSkip.shouldSkipRing(
            ringFrame: .zero, foregroundFrame: ringBounds,
            ringPath: ringPath, foregroundPath: ringPath,
            bounds: ringBounds, path: ringPath), "Mismatched ring frame does not skip")
        check(!LayerSkip.shouldSkipRing(
            ringFrame: ringBounds, foregroundFrame: ringBounds,
            ringPath: nil, foregroundPath: ringPath,
            bounds: ringBounds, path: ringPath), "Missing ring path does not skip")

        func layoutWrites(_ view: NSView) -> Int { GeometryWrites.layerWrites(by: view) { view.layout() }.count }
        let isolatedDot = FavoriteRecordingDotView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        SystemOverrides.reduceMotion = true
        check(layoutWrites(isolatedDot) > 0, "first recording-dot layout writes its layers")
        check(layoutWrites(isolatedDot) == 0, "no-op recording-dot layout skips CATransaction rewrite")
        isolatedDot.setFrameSize(NSSize(width: 10, height: 10))
        check(layoutWrites(isolatedDot) > 0, "a recording-dot bounds change still rewrites layers")
        check(layoutWrites(isolatedDot) == 0, "follow-up recording-dot layout at the new size remains a no-op")
        let pulseWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        pulseWindow.isReleasedWhenClosed = false
        pulseWindow.contentView!.addSubview(isolatedDot)
        check(isolatedDot.pulse == nil, "Reduce Motion arms no recording-dot pulse")
        isolatedDot.removeFromSuperview()
        SystemOverrides.reduceMotion = false
        pulseWindow.contentView!.addSubview(isolatedDot)
        check(isolatedDot.pulse != nil, "recording-dot pulse still arms after layout skips")
        check(layoutWrites(isolatedDot) == 0 && isolatedDot.pulse != nil,
              "layout skip leaves the pulse animation installed")
        isolatedDot.removeFromSuperview()
        pulseWindow.close()

        let isolatedRing = FavoriteHighlightRingView(frame: ringBounds)
        isolatedRing.style = .highlight(maxContrast)
        check(layoutWrites(isolatedRing) > 0, "first highlight-ring layout writes its layers")
        let strokeBefore = isolatedRing.ring.strokeColor
        check(layoutWrites(isolatedRing) == 0 && isolatedRing.ring.strokeColor === strokeBefore,
              "no-op highlight-ring layout skips rewrite and leaves style")
        isolatedRing.setFrameSize(NSSize(width: 80, height: 47))
        check(layoutWrites(isolatedRing) > 0
              && isolatedRing.ring.path == FavoriteTilePaths.highlightRing(bounds: isolatedRing.bounds),
              "a highlight-ring bounds change still rewrites path")
        check(layoutWrites(isolatedRing) == 0, "follow-up highlight-ring layout at the new size remains a no-op")
        isolatedRing.style = .developerTab
        check(isolatedRing.ring.strokeColor == NSColor.black.cgColor
              && isolatedRing.foreground.lineDashPattern == [6, 6],
              "style changes stay ungated by the layout skip")

        browser.close(); other.close()
        SystemOverrides.reduceMotion = nil
        print("\(checks) Favorite overlay assertions passed (no browser)")
    }
}
