import AppKit

private final class VisibleWindow: NSWindow {
    override var occlusionState: NSWindow.OcclusionState { .visible }
}

@MainActor @main struct NavigationLoadingChecks {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("NavigationLoading: \(message)") }
    }
    static func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.0001) -> Bool { abs(a - b) <= e }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        FrameSources.install()
        Redraws.install()
        GeometryWrites.install()
        SystemOverrides.install()
        check(PageLoadingIndicator.size == NSSize(width: 128, height: 4), "the 128 × 4 size")
        check(PageLoadingIndicator.frame(paneMinX: 0, paneWidth: 1000, bandHeight: 10) == NSRect(x: 436, y: 3, width: 128, height: 4), "centred in band")
        check(PageLoadingIndicator.frame(paneMinX: 500, paneWidth: 500, bandHeight: 10).midX == 750, "centred over the second pane")
        check(PageLoadingIndicator.frame(paneMinX: 0, paneWidth: 100, bandHeight: 10).width == 100, "narrow pane clips the pill")
        check(PageLoadingIndicatorHost.frame(pageHost: NSRect(x: 228, y: 10, width: 1232, height: 811)) == NSRect(x: 228, y: 0, width: 1232, height: 10), "host spans the top inset")
        check(PageLoadingIndicatorHost.frame(pageHost: NSRect(x: 0, y: 0, width: 1470, height: 831)).height == 0, "no band in page full screen")

        let a = UUID(), b = UUID(), c = UUID()
        check(PageLoadingIndicatorHost.eligible([a, b, c], stacked: true) == [a], "stacked: first pane only")
        check(PageLoadingIndicatorHost.eligible([a, b, c], stacked: false) == [a, b, c], "side by side: every pane")
        check(PageLoadingIndicatorHost.eligible([], stacked: true).isEmpty, "no panes")

        let host = PageLoadingIndicatorHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 10))
        host.update([.init(id: a, minX: 0, width: 500, loading: true), .init(id: b, minX: 500, width: 500, loading: false)])
        check(host.indicators.count == 2 && !host.isHidden, "one indicator per eligible pane")
        check(host.indicators[a]?.isLoading == true && host.indicators[b]?.isLoading == false, "each follows its own pane")
        check(host.indicators[b]?.frame == NSRect(x: 686, y: 3, width: 128, height: 4), "second pane's pill")
        host.update([.init(id: b, minX: 0, width: 1000, loading: true)])
        check(host.indicators.count == 1 && host.indicators[a] == nil && host.indicators[b]?.isLoading == true, "removed pane loses its indicator")
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 0)
        host.update([.init(id: b, minX: 0, width: 1000, loading: true)])
        check(host.isHidden && host.indicators[b]?.isLoading == false, "zero band hides and stops")
        host.reset()
        check(host.indicators.isEmpty, "reset removes every indicator")

        func stroke(_ t: Double) -> (CGFloat, CGFloat) { let s = PageLoadingIndicator.stroke(at: t); return (s.start, s.end) }
        check(stroke(0) == (0, 0), "cycle starts empty")
        check(near(stroke(0.1875).1, 0.5) && stroke(0.1875).0 == 0, "grows from the start")
        check(near(stroke(0.5625).0, 0.5) && stroke(0.5625).1 == 1, "shrinks from the start")
        check(stroke(0.9) == (0, 0), "empty third")
        check(near(stroke(1.125 + 0.1875).1, 0.5), "repeats every 1.125 s")
        check(PageLoadingIndicator.sweepDelay == 3.2, "sweep after 3.2 s")

        check(ReloadGlyph.spring(0) == 0, "spring starts at rest")
        check(abs(ReloadGlyph.spring(ReloadGlyph.settlingTime) - 1) < 0.001, "settled within the envelope")
        check(ReloadGlyph.settlingTime > 0.3 && ReloadGlyph.settlingTime < 0.5, "settles in under half a second")
        check((1...40).map { ReloadGlyph.spring(Double($0) / 200) }.max()! > 1.05, "underdamped overshoot")
        check(ReloadGlyph.delay(enteringLoading: true) == 0.2 && ReloadGlyph.delay(enteringLoading: false) == 0.1, "0.2 s entering and 0.1 s leaving delays")
        let view = NSView()
        let glyph = ReloadGlyph(view: view, pointSize: SidebarChromeLayout.navigationGlyphPointSize, rasterized: true)
        func driving(_ sources: [FrameSource]) -> Bool { sources.contains(where: \.isLive) }
        var unanimated = FrameSources.scheduled { glyph.update(loading: true, forceReload: false, animated: false) }
        check(glyph.progress == 1 && glyph.loading, "unanimated switch to Stop")
        unanimated += FrameSources.scheduled { glyph.update(loading: false, forceReload: true, animated: false) }
        check(glyph.progress == 0 && glyph.forceReload, "force default switches the idle glyph")
        let force = NavigationControlArtwork.forceReload
        check(NavigationControlArtwork.directory == Bundle.main.resourceURL?.appendingPathComponent("NavigationControls", isDirectory: true)
              && force?.size == NSSize(width: 22, height: 15) && force?.isTemplate == true
              && force?.representations.contains { $0.pixelsWide == 44 } == true,
              "The force-reload artwork loads from the bundle's NavigationControls resources with its 2x rendition")
        check(glyph.idleImage === force, "the force default draws the force-reload artwork")
        check(SidebarChromeLayout.navigationGlyphPointSize == 16 && glyph.pointSize == 16, "16-point medium glyphs")
        let arrow = NavigationControlArtwork.symbol("arrow.clockwise", pointSize: 16)
        check(arrow?.isTemplate == true && arrow?.representations.count == 2
              && NavigationControlArtwork.symbol("xmark", pointSize: 16) != nil, "1x and 2x template arrow and stop")
        check(arrow.map { $0.size.width == $0.size.width.rounded() && $0.size.height == $0.size.height.rounded() } == true,
              "whole-point glyph frame")
        check(NavigationControlArtwork.symbol("arrow.clockwise", pointSize: 16) === arrow, "rendered once per symbol and size")
        check(ReloadGlyph.clipCornerRadius == 6, "the 6-point frame clip")
        check(ReloadGlyph.actionRotation == 2 * .pi && ReloadGlyph.actionResponse == 0.4 && ReloadGlyph.actionDamping == 0.6,
              "after-action 2π spring")
        check(ReloadGlyph.actionSettlingTime > ReloadGlyph.settlingTime, "click spin lasts longer than the Stop crossfade")
        unanimated += FrameSources.scheduled { glyph.playActionSpin(animated: false) }
        check(abs(glyph.rotation) < 0.001, "Reduce-Motion wrap leaves the glyph upright")
        check(unanimated.isEmpty, "unanimated reload idle does not tick")
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let load = FrameSources.scheduled { glyph.update(loading: true, forceReload: false, animated: true) }
        if reduceMotion {
            check(!driving(load) && glyph.progress == 1, "Reduce Motion snaps the glyph and idles")
        } else {
            check(driving(load), "load spring samples on the display link")
            let redraws = Redraws.count(view)
            load.forEach { $0.fire() }
            check(glyph.progress == 0 && driving(load) && Redraws.count(view) == redraws + 1,
                  "a frame inside the 0.2 s delay redraws the idle glyph and keeps sampling")
            glyph.stop()
            check(!driving(load) && glyph.progress == 1, "stop settles the glyph and idles")
            let spin = FrameSources.scheduled { glyph.playActionSpin(animated: true) }
            check(driving(spin), "action spin samples on the display link")
            glyph.stop()
            check(!driving(spin), "stop idles the action spin")
            let unload = FrameSources.scheduled { glyph.update(loading: false, forceReload: false, animated: true) }
            check(driving(unload), "leaving loading samples on the display link")
            Thread.sleep(forTimeInterval: ReloadGlyph.delay(enteringLoading: false) + ReloadGlyph.settlingTime + 0.05)
            unload.forEach { $0.fire() }
            check(glyph.progress == 0 && !driving(unload), "a settled spring stops its own display link")
        }

        let indicator = PageLoadingIndicator(frame: NSRect(x: 0, y: 0, width: 128, height: 4))
        var unwindowed = FrameSources.scheduled { indicator.setLoading(true) }
        check(indicator.isLoading && unwindowed.isEmpty, "no window: loading does not tick")
        unwindowed += FrameSources.scheduled { indicator.setLoading(false) }
        check(!indicator.isLoading && unwindowed.isEmpty, "no window: hide does not tick")

        typealias Skip = PageLoadingPresentationSkip
        let empty = PageLoadingIndicator.presentation(
            pulse: 1, sweeping: true, stroke: (0, 0), barOpacity: 0.92, hidden: false)
        check(Skip.shouldSkip(previous: nil, next: empty) == false, "first fingerprint never skips")
        check(Skip.shouldSkip(previous: empty, next: empty), "identical empty-third settled skips")
        let growing = PageLoadingIndicator.presentation(
            pulse: 1, sweeping: true, stroke: (0, 0.5), barOpacity: 0.92, hidden: false)
        check(Skip.shouldSkip(previous: empty, next: growing) == false, "stroke growth must present")
        let pulseA = PageLoadingIndicator.presentation(
            pulse: 0.40, sweeping: false, stroke: (0, 0), barOpacity: 0, hidden: false)
        let pulseB = PageLoadingIndicator.presentation(
            pulse: 0.41, sweeping: false, stroke: (0, 0), barOpacity: 0, hidden: false)
        check(Skip.shouldSkip(previous: pulseA, next: pulseB) == false, "loading pulse change must present")
        check(PageLoadingIndicator.stroke(at: 0.9) == (0, 0), "0.9 s is the empty third")

        check(near(CGFloat(pulseA.fillOpacity), 0.368) && near(CGFloat(empty.fillOpacity), 0.276), "fill opacity per phase")
        check(PageLoadingIndicator.trackSize(sweeping: false) == CGSize(width: 48, height: 4)
              && PageLoadingIndicator.trackSize(sweeping: true) == CGSize(width: 128, height: 4), "the per-phase track sizes")

        let spaceHost = PageLoadingIndicatorHost(frame: NSRect(x: 0, y: 0, width: 400, height: 10))
        spaceHost.appearance = NSAppearance(named: .aqua)
        spaceHost.update([.init(id: a, minX: 0, width: 200, loading: false), .init(id: b, minX: 200, width: 200, loading: true)])
        func colors(_ id: UUID) -> (fill: CGColor, bar: CGColor) {
            let layers = spaceHost.indicators[id]!.layer!.sublayers!.first!.sublayers!
            return (layers.first!.backgroundColor!, (layers.last as! CAShapeLayer).strokeColor!)
        }
        func showsLight(_ id: UUID) -> Bool {
            let (fill, bar) = colors(id)
            return fill == bar && fill.colorSpace?.name == CGColorSpace.displayP3
                && fill.components == [14.0 / 255, 15.0 / 255, 16.0 / 255, 0.9]
        }
        func showsDark(_ id: UUID) -> Bool {
            let (fill, bar) = colors(id)
            return fill == bar && fill.colorSpace?.name == CGColorSpace.sRGB && fill.components == [1, 1, 1, 0.8]
        }
        check(spaceHost.indicators.count == 2 && showsLight(a) && showsLight(b),
              "light content: both panes' fill and bar are Display P3 near-black at 0.9")
        spaceHost.appearance = NSAppearance(named: .darkAqua)
        check(showsDark(a) && showsDark(b), "dark content: both panes' fill and bar are white at 0.8")
        spaceHost.appearance = NSAppearance(named: .aqua)
        check(showsLight(a) && showsLight(b), "returning to light content restores near-black")
        spaceHost.reset()

        SystemOverrides.reduceMotion = false
        let pillWindow = VisibleWindow(contentRect: NSRect(x: 0, y: 0, width: 128, height: 4),
                                       styleMask: .borderless, backing: .buffered, defer: true)
        pillWindow.isReleasedWhenClosed = false
        let driven = PageLoadingIndicator(frame: NSRect(x: 0, y: 0, width: 128, height: 4))
        pillWindow.contentView = driven
        var loadingStarted = CACurrentMediaTime()
        var pill = FrameSources.scheduled { driven.setLoading(true) }
        check(driving(pill), "a visible loading pill samples on the display link")
        let track = driven.layer!.sublayers!.first!
        let bar = track.sublayers!.last as! CAShapeLayer
        func deliverFrame() -> [GeometryWrite] {
            Thread.sleep(forTimeInterval: 1.0 / 60)
            return GeometryWrites.layerWrites(by: driven) { pill.forEach { $0.fire() } }
        }
        func presentations(_ writes: [GeometryWrite]) -> Int { writes.filter { $0.object === track && $0.key == "transform" }.count }
        func boundsSpring() -> (from: CGFloat, to: CGFloat, spring: CASpringAnimation)? {
            guard let spring = track.animation(forKey: "bounds") as? CASpringAnimation,
                  let from = spring.fromValue as? NSValue, let to = spring.toValue as? NSValue else { return nil }
            return (from.rectValue.width, to.rectValue.width, spring)
        }
        func barTarget() -> Float? { ((bar.animation(forKey: "opacity") as? CASpringAnimation)?.toValue as? NSNumber)?.floatValue }
        func isSweepSpring(_ spring: CASpringAnimation) -> Bool {
            let response = 2 * Double.pi / (spring.stiffness / spring.mass).squareRoot()
            let fraction = spring.damping / (2 * (spring.stiffness * spring.mass).squareRoot())
            return abs(response - 0.8) < 0.0001 && abs(fraction - 0.92) < 0.0001 && spring.duration == spring.settlingDuration
        }
        func waitForSweep() -> CFTimeInterval {
            while bar.opacity == 0, CACurrentMediaTime() - loadingStarted < 5 { _ = deliverFrame() }
            return CACurrentMediaTime() - loadingStarted
        }
        check(track.bounds.size == PageLoadingIndicator.trackSize(sweeping: false), "loading shows the 48-point track")
        let sweepAfter = waitForSweep()
        check(bar.opacity == PageLoadingIndicator.sweepBarOpacity && sweepAfter > PageLoadingIndicator.sweepDelay
              && sweepAfter < PageLoadingIndicator.sweepDelay + 0.5,
              "the pill sweeps at the pulse trough after 3.2 s")
        let widen = boundsSpring()
        check(track.bounds.size == PageLoadingIndicator.trackSize(sweeping: true) && widen.map { near($0.from, 48) && $0.to == 128 } == true
              && widen.map { isSweepSpring($0.spring) } == true && barTarget() == PageLoadingIndicator.sweepBarOpacity,
              "the sweep springs the track from 48 to 128 points and the bar to 0.92 on the sweep spring")
        var skipped = 0
        let settleDeadline = Date(timeIntervalSinceNow: 8)
        while skipped < 2, Date() < settleDeadline {
            let empty = bar.strokeStart == 0 && bar.strokeEnd == 0
            let writes = deliverFrame()
            skipped = empty && bar.strokeEnd == 0 && writes.isEmpty ? skipped + 1 : 0
        }
        check(skipped == 2 && driving(pill), "settled empty-third ticks skip layer writes while the link keeps sampling")
        var growth: [GeometryWrite] = []
        let growthDeadline = Date(timeIntervalSinceNow: 1.5)
        while bar.strokeEnd == 0, Date() < growthDeadline { growth = deliverFrame() }
        check(bar.strokeEnd > 0 && presentations(growth) == 1, "stroke growth presents")
        driven.setLoading(false)
        let shrink = boundsSpring()
        check(track.bounds.size == PageLoadingIndicator.trackSize(sweeping: false) && bar.opacity == 0
              && shrink.map { abs($0.from - 128) < 0.5 && $0.to == 48 && isSweepSpring($0.spring) } == true
              && barTarget() == 0 && driving(pill),
              "ending a load mid-sweep springs the track from 128 to 48 points and the bar to 0")
        driven.reset()
        check(track.animation(forKey: "bounds") == nil && bar.animation(forKey: "opacity") == nil && !driving(pill),
              "reset removes the track and bar springs and idles the pill")
        loadingStarted = CACurrentMediaTime()
        pill = FrameSources.scheduled { driven.setLoading(true) }
        check(waitForSweep() < PageLoadingIndicator.sweepDelay + 0.5 && bar.opacity > 0, "a second load sweeps again")
        SystemOverrides.reduceMotion = true
        let exit = deliverFrame()
        check(presentations(exit) == 1 && bar.opacity == 0 && !driving(pill)
              && track.bounds.size == PageLoadingIndicator.trackSize(sweeping: false) && track.animation(forKey: "bounds") == nil
              && bar.animation(forKey: "opacity") == nil,
              "Reduce Motion sweep exit presents once, narrows the track without a spring and idles the link")
        SystemOverrides.reduceMotion = false
        let hiding = FrameSources.scheduled { driven.setLoading(false) }
        check(driving(hiding), "hiding samples the pulse back to rest")
        driven.reset()
        check(!driving(hiding), "reset idles the pill")
        SystemOverrides.reduceMotion = nil
        pillWindow.close()

        var chosen: [ReloadOptionsMenu.Choice] = []
        let menu = ReloadOptionsMenu.make(state: .forceReload, canReload: true, canForceReload: true, canClearCookies: false) { chosen.append($0) }
        check(menu.items.map(\.title) == ["Reload", "Refresh (Ignore Cache)", "", "Clear Cookies and Refresh"], "the reload menu items")
        check(menu.items[2].isSeparatorItem, "separator before Clear Cookies")
        check(menu.items[0].state == .off && menu.items[1].state == .on, "checkmark on the stored default")
        check(menu.items[3].isEnabled == false && menu.items[0].isEnabled, "availability")
        for index in [0, 1] { let item = menu.items[index]; _ = (item.target as? NSObject)?.perform(item.action) }
        check(chosen == [.reload, .forceReload], "items run their choices")
        let defaults = UserDefaults(suiteName: "parc.navigation-loading-checks")!
        defaults.removePersistentDomain(forName: "parc.navigation-loading-checks")
        SystemOverrides.standardDefaults = defaults
        check(DeveloperReloadPreference.state == .reload, "the default is Reload")
        DeveloperReloadPreference.state = .forceReload
        check(defaults.string(forKey: DeveloperReloadPreference.key) == "forceReload", "the forceReload raw value is stored")
        check(DeveloperReloadPreference.state == .forceReload, "the stored default reads back")
        SystemOverrides.standardDefaults = nil
        defaults.removePersistentDomain(forName: "parc.navigation-loading-checks")

        let lights = CGSize(width: 60, height: 14)
        let regular = SidebarChromeLayout.toolbar(width: 228, windowButtons: lights, showsNavigation: true)
        let developer = SidebarChromeLayout.toolbar(width: 228, windowButtons: lights, showsNavigation: true, developerReload: true)
        check(developer.reload?.width == 19 && developer.reloadOptions?.width == 14, "19 + 14 points")
        check(developer.reload?.maxX == developer.reloadOptions?.minX, "chevron abuts Reload")
        check(developer.reloadOptions?.maxX == regular.reload?.maxX, "same trailing edge")
        check(developer.forward.map { $0.maxX + 2 } == developer.reload?.minX && developer.forward?.width == 32, "regular spacing before the pair")
        check(regular.reloadOptions == nil, "no chevron outside Developer Mode")
        let narrow = SidebarChromeLayout.toolbar(width: 200, windowButtons: lights, showsNavigation: true, developerReload: true)
        check(narrow.reloadOptions == nil, "narrow row keeps its ordinary Reload")
        print("NavigationLoading checks: \(count) passed")
    }
}
