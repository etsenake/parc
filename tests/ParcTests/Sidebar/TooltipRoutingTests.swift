import AppKit
import SwiftUI
import Testing
@testable import Parc
@testable import ParcKit

@MainActor
final class TooltipTestClock {
    private(set) var now = Date(timeIntervalSinceReferenceDate: 50_000)
    private var timers: [(timer: Timer, interval: TimeInterval, repeats: Bool)] = []
    private var fades: [(at: Date, order: Int, body: @MainActor () -> Void)] = []
    private var order = 0
    var modifiers: NSEvent.ModifierFlags = []
    var commandShortcut: (String) -> ParcKit.KeyboardShortcut? = { _ in nil }

    func install(on window: NSWindow) {
        let controller = TooltipController.controller(for: window)
        controller.currentDate = { [weak self] in self?.now ?? .distantPast }
        controller.makeTimer = { [weak self] interval, repeats, body in
            let timer = Timer(fire: (self?.now ?? .distantPast).addingTimeInterval(interval), interval: interval, repeats: repeats) { _ in
                MainActor.assumeIsolated { body() }
            }
            self?.timers.append((timer, interval, repeats))
            return timer
        }
        controller.whenFadeEnds = { [weak self] duration, body in
            guard let self else { return }
            order += 1
            fades.append((now.addingTimeInterval(duration), order, body))
        }
        controller.pointerInput = { [weak self] in (0, self?.modifiers ?? []) }
        controller.shortcutForCommand = { [weak self] in self?.commandShortcut($0) }
    }

    func advance(_ seconds: TimeInterval) {
        let target = now.addingTimeInterval(seconds + 1e-9)
        var fired = 0
        while true {
            timers.removeAll { !$0.timer.isValid }
            let timer = timers.filter { $0.timer.fireDate <= target }.min { $0.timer.fireDate < $1.timer.fireDate }
            let fade = fades.filter { $0.at <= target }.min { ($0.at, $0.order) < ($1.at, $1.order) }
            guard timer != nil || fade != nil else { break }
            fired += 1
            guard fired < 1_000 else { Issue.record("a timer keeps firing without time passing"); return }
            if let timer, fade.map({ timer.timer.fireDate <= $0.at }) ?? true {
                let due = timer.timer.fireDate
                now = max(now, due)
                timer.timer.fire()
                if timer.repeats, timer.timer.isValid, timer.timer.fireDate == due {
                    timer.timer.fireDate = due.addingTimeInterval(timer.interval)
                }
            } else if let fade {
                fades.removeAll { $0.order == fade.order }
                now = max(now, fade.at)
                fade.body()
            }
        }
        now = max(now, target.addingTimeInterval(-1e-9))
    }
}

@MainActor
struct TooltipRoutingTests {
    final class StandInWindow: NSWindow {
        var pointer = NSPoint(x: -10_000, y: -10_000)
        override var isKeyWindow: Bool { true }
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    }

    final class PartView: NSView {
        var part = NSRect.zero
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let superview else { return nil }
            return part.contains(convert(point, from: superview)) ? self : nil
        }
    }

    @MainActor final class Scene {
        let clock = TooltipTestClock()
        let window = StandInWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 200), styleMask: .borderless, backing: .buffered, defer: false)

        init() {
            window.isReleasedWhenClosed = false
            clock.install(on: window)
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func add(_ view: NSView, _ configuration: TooltipConfiguration) -> NSResponder {
            window.contentView!.addSubview(view)
            view.parcTooltip = configuration
            return view.trackingAreas.compactMap { $0.owner as? NSResponder }.first!
        }
        var tooltip: NSWindow? { window.childWindows?.first }
        var label: String? { (tooltip?.contentView as? TooltipView)?.content.label }
        var palette: TooltipColorPalette? { (tooltip?.contentView as? TooltipView)?.content.palette }

        func entered(at point: NSPoint) -> NSEvent {
            NSEvent.enterExitEvent(with: .mouseEntered, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        func moved(to point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        }
    }

    private static let hide = TooltipConfiguration("Hide sidebar", shortcut: .fixed(ParcKit.KeyboardShortcut(key: "s", flags: .command)))
    private static let centre = NSPoint(x: 40, y: 140)

    private func control(_ scene: Scene, _ configuration: TooltipConfiguration? = nil) -> (NSView, NSResponder) {
        let anchor = NSView(frame: NSRect(x: 20, y: 120, width: 40, height: 40))
        return (anchor, scene.add(anchor, configuration ?? Self.hide))
    }

    @Test func nothingShowsBeforeTheIdleDelay() {
        let scene = Scene()
        let (_, owner) = control(scene)
        owner.mouseEntered(with: scene.entered(at: Self.centre))
        scene.clock.advance(0.449)
        #expect(scene.tooltip == nil)
    }

    @Test func enteringShowsTheTooltipAtTheIdleDelay() {
        let scene = Scene()
        let (_, owner) = control(scene)
        owner.mouseEntered(with: scene.entered(at: Self.centre))
        scene.clock.advance(0.45)
        #expect(scene.tooltip != nil)
    }

    @Test func theTooltipWindowNeverTakesKeyMainOrTheMouseAndIsHiddenFromAccessibility() throws {
        let scene = Scene()
        let (_, owner) = control(scene)
        owner.mouseEntered(with: scene.entered(at: Self.centre))
        scene.clock.advance(0.45)
        let child = try #require(scene.tooltip)
        #expect(!child.canBecomeKey && !child.canBecomeMain && child.ignoresMouseEvents)
        #expect(!child.isAccessibilityElement())
        #expect(!child.isVisible && !scene.window.isVisible)
    }

    @Test func aSecondDismissalDuringAFadeKeepsFadingAndTheLatestFadeClosesTheWindow() {
        let scene = Scene()
        let (_, owner) = control(scene)
        owner.mouseEntered(with: scene.entered(at: Self.centre))
        scene.clock.advance(0.45)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: scene.window)
        scene.clock.advance(0.05)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: scene.window)
        scene.clock.advance(0.27)
        #expect(scene.tooltip != nil)
        scene.clock.advance(0.029)
        #expect(scene.tooltip != nil)
        scene.clock.advance(0.001)
        #expect(scene.tooltip == nil)
    }

    @Test func aMouseMovedReachesTheControllerAndCancelsThePendingTooltip() {
        let scene = Scene()
        let (_, owner) = control(scene)
        owner.mouseEntered(with: scene.entered(at: Self.centre))
        scene.clock.advance(0.2)
        owner.mouseMoved(with: scene.moved(to: Self.centre))
        scene.clock.advance(0.4)
        #expect(scene.tooltip == nil)
    }

    @Test func aViewHiddenDuringTheIdleDelayNeverShowsItsTooltip() {
        let scene = Scene()
        let (anchor, owner) = control(scene)
        owner.mouseEntered(with: scene.entered(at: Self.centre))
        scene.clock.advance(0.2)
        anchor.superview?.isHidden = true
        scene.clock.advance(0.4)
        #expect(scene.tooltip == nil)
    }

    @Test func aHeldModifierDeclinesTheTooltip() {
        let scene = Scene()
        let (_, owner) = control(scene)
        scene.clock.modifiers = .shift
        owner.mouseEntered(with: scene.entered(at: Self.centre))
        scene.clock.advance(0.55)
        #expect(scene.tooltip == nil)
    }

    private static let resetTab = TooltipConfiguration("Reset Tab", shortcut: .command("resetTab:"), requiresShortcut: true)

    @Test func withoutABindingThereIsNoResetTabTooltip() {
        let scene = Scene()
        let (_, owner) = control(scene, Self.resetTab)
        owner.mouseEntered(with: scene.entered(at: Self.centre))
        scene.clock.advance(0.55)
        #expect(scene.tooltip == nil)
    }

    @Test func aBindingShowsTheResetTabTooltip() {
        let scene = Scene()
        scene.clock.commandShortcut = { $0 == "resetTab:" ? ParcKit.KeyboardShortcut(key: "r", flags: [.command, .option]) : nil }
        let (_, owner) = control(scene, Self.resetTab)
        owner.mouseEntered(with: scene.entered(at: Self.centre))
        scene.clock.advance(0.55)
        #expect(scene.tooltip != nil)
    }

    private func canvas(_ scene: Scene) -> (PartView, NSResponder) {
        let canvas = PartView(frame: NSRect(x: 20, y: 40, width: 200, height: 140))
        canvas.part = NSRect(x: 100, y: 20, width: 40, height: 40)
        return (canvas, scene.add(canvas, TooltipConfiguration("View Library", anchorRect: canvas.part)))
    }

    @Test func enteringAViewOutsideItsPartSchedulesNothing() {
        let scene = Scene()
        let (_, owner) = canvas(scene)
        owner.mouseEntered(with: scene.entered(at: NSPoint(x: 30, y: 50)))
        scene.clock.advance(0.55)
        #expect(scene.tooltip == nil)
    }

    @Test func enteringOverThePartShowsItsTooltipAtThePartsBottomTrailingCorner() throws {
        let scene = Scene()
        let (_, owner) = canvas(scene)
        owner.mouseEntered(with: scene.entered(at: NSPoint(x: 140, y: 80)))
        scene.clock.advance(0.55)
        let tip = try #require(scene.tooltip)
        let margin = TooltipView.margin(scale: tip.screen?.backingScaleFactor ?? scene.window.backingScaleFactor)
        #expect(abs(tip.frame.minX + margin - (200 + 160 - 6)) <= 1)
        #expect(abs(tip.frame.maxY - margin - (400 - (140 - 6))) <= 1)
    }

    private func stopping(_ scene: Scene) -> (NSResponder, (NSPoint) -> Void) {
        let (_, owner) = canvas(scene)
        scene.window.pointer = NSPoint(x: 30, y: 50)
        owner.mouseEntered(with: scene.entered(at: scene.window.pointer))
        scene.clock.advance(0.55)
        return (owner, { point in
            scene.window.pointer = point
            owner.mouseMoved(with: scene.moved(to: point))
        })
    }

    @Test func enteringOutsideThePartShowsNothing() {
        let scene = Scene()
        _ = stopping(scene)
        #expect(scene.tooltip == nil)
    }

    @Test func thePointerStoppingOnThePartWaitsTheStopAndTheIdleDelay() {
        let scene = Scene()
        let (_, move) = stopping(scene)
        move(NSPoint(x: 140, y: 80))
        scene.clock.advance(0.529)
        #expect(scene.tooltip == nil)
        scene.clock.advance(0.001)
        #expect(scene.tooltip != nil)
    }

    @Test func pastTheBackstopAGapInsideTheViewHidesItsPartsTooltip() {
        let scene = Scene()
        let (_, move) = stopping(scene)
        move(NSPoint(x: 140, y: 80))
        scene.clock.advance(0.53)
        move(NSPoint(x: 60, y: 120))
        scene.clock.advance(0.9)
        #expect(scene.tooltip == nil)
    }

    @Test func stoppingOnThePartAgainShowsItsTooltipWithoutANewEntry() {
        let scene = Scene()
        let (_, move) = stopping(scene)
        move(NSPoint(x: 140, y: 80))
        scene.clock.advance(0.53)
        move(NSPoint(x: 60, y: 120))
        scene.clock.advance(0.9)
        move(NSPoint(x: 130, y: 70))
        scene.clock.advance(0.9)
        #expect(scene.tooltip != nil)
    }

    private func muted(_ scene: Scene) -> (NSView, TooltipController) {
        let control = NSView(frame: NSRect(x: 20, y: 120, width: 40, height: 40))
        let owner = scene.add(control, TooltipConfiguration("Mute this tab"))
        scene.window.pointer = Self.centre
        owner.mouseEntered(with: scene.entered(at: scene.window.pointer))
        scene.clock.advance(0.55)
        return (control, TooltipController.controller(for: scene.window))
    }

    private static var themed: TooltipColorPalette {
        var themed = TooltipColorPalette.neutral
        themed.background = .init(NSColor(srgbRed: 0, green: 0.5, blue: 0.2, alpha: 1))
        return themed
    }

    @Test func theControlsTooltipShows() {
        let scene = Scene()
        _ = muted(scene)
        #expect(scene.label == "Mute this tab")
    }

    @Test func aNewWindowPaletteRepaintsTheShownTooltipInPlace() {
        let scene = Scene()
        let (_, controller) = muted(scene)
        let shown = scene.tooltip, frame = shown?.frame
        controller.palette = Self.themed
        #expect(scene.palette == Self.themed)
        #expect(scene.tooltip === shown && shown?.frame == frame)
    }

    @Test func clearingTheWindowPaletteRepaintsItNeutral() {
        let scene = Scene()
        let (_, controller) = muted(scene)
        let shown = scene.tooltip
        controller.palette = Self.themed
        controller.palette = nil
        #expect(scene.palette == .neutral && scene.tooltip === shown)
    }

    @Test func aTooltipWithItsOwnPaletteKeepsItWhenTheWindowPaletteChanges() {
        let scene = Scene()
        let (control, controller) = muted(scene)
        var own = TooltipColorPalette.neutral
        own.title = .init(NSColor(srgbRed: 0.8, green: 0, blue: 0, alpha: 1))
        control.parcTooltip = TooltipConfiguration("Mute this tab", palette: own)
        controller.palette = Self.themed
        #expect(scene.palette == own)
    }

    @Test func droppingItsOwnPaletteTakesTheWindows() {
        let scene = Scene()
        let (control, controller) = muted(scene)
        var own = TooltipColorPalette.neutral
        own.title = .init(NSColor(srgbRed: 0.8, green: 0, blue: 0, alpha: 1))
        control.parcTooltip = TooltipConfiguration("Mute this tab", palette: own)
        controller.palette = Self.themed
        control.parcTooltip = TooltipConfiguration("Mute this tab")
        #expect(scene.palette == Self.themed)
    }

    @Test func aChangeWithThePointerOverTheViewReplacesTheShownContent() {
        let scene = Scene()
        let (control, _) = muted(scene)
        control.parcTooltip = TooltipConfiguration("Unmute this tab")
        #expect(scene.label == "Unmute this tab")
    }

    @Test func aChangeAfterThePointerLeftDoesNotShowTheNewContent() {
        let scene = Scene()
        let (control, _) = muted(scene)
        control.parcTooltip = TooltipConfiguration("Unmute this tab")
        scene.window.pointer = NSPoint(x: 250, y: 20)
        control.parcTooltip = TooltipConfiguration("Mute this tab")
        #expect(scene.label == "Unmute this tab")
    }

    @Test func aFadingTooltipRepaintsWithoutRestartingItsFadeThenCloses() {
        let scene = Scene()
        let (control, controller) = muted(scene)
        func fadeStart() -> CFTimeInterval? { scene.tooltip?.contentView?.layer?.animation(forKey: "alpha_animation")?.beginTime }
        control.parcTooltip = TooltipConfiguration("Unmute this tab")
        scene.window.pointer = NSPoint(x: 250, y: 20)
        control.parcTooltip = TooltipConfiguration("Mute this tab")
        controller.palette = Self.themed
        let fading = fadeStart()
        controller.palette = nil
        #expect(fading != nil && fadeStart() == fading)
        #expect(scene.palette == .neutral && scene.label == "Unmute this tab")
        scene.clock.advance(0.5)
        #expect(scene.tooltip == nil)
    }

    @MainActor final class Bridge {
        let scene = Scene()
        let host: NSHostingView<AnyView>
        var clicks = 0

        init() {
            scene.window.setContentSize(NSSize(width: 120, height: 80))
            host = NSHostingView(rootView: AnyView(EmptyView()))
            host.rootView = AnyView(SwiftUI.Button("Copy") { [weak self] in guard let self else { return }; clicks += 1 }
                .frame(width: 48, height: 32)
                .parcTooltip(TooltipConfiguration("Copy URL", shortcut: .fixed(ParcKit.KeyboardShortcut(key: "c", flags: [.command, .shift])))))
            host.frame = scene.window.contentView!.bounds
            scene.window.contentView!.addSubview(host)
            host.layoutSubtreeIfNeeded()
        }

        var anchors: [TooltipAnchorView] { Self.anchors(host) }
        private static func anchors(_ view: NSView) -> [TooltipAnchorView] {
            ((view as? TooltipAnchorView).map { [$0] } ?? []) + view.subviews.flatMap(anchors)
        }
        var centre: NSPoint {
            let anchor = anchors[0]
            return anchor.convert(NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: nil)
        }
        func enter() {
            scene.window.pointer = centre
            let owner = anchors[0].trackingAreas.compactMap { $0.owner as? NSResponder }.first!
            owner.mouseEntered(with: scene.entered(at: centre))
        }
    }

    @Test func theModifierOverlaysOneAnchorCarryingTheConfiguration() {
        let bridge = Bridge()
        #expect(bridge.anchors.count == 1 && bridge.anchors.first?.parcTooltip?.label == "Copy URL")
    }

    @Test func theAnchorCoversTheControl() throws {
        let bridge = Bridge()
        #expect(try #require(bridge.anchors.first).bounds.size == CGSize(width: 48, height: 32))
    }

    @Test func ordinaryHitTestsPassThroughTheAnchorToTheSwiftUIControl() throws {
        let bridge = Bridge()
        let anchor = try #require(bridge.anchors.first)
        let hit = bridge.scene.window.contentView!.hitTest(bridge.centre)
        #expect(hit != nil && !(hit is TooltipAnchorView) && hit?.isDescendant(of: anchor) == false)
        #expect(TooltipController.controller(for: bridge.scene.window).hitTestingView == nil)
    }

    @Test func theControllerClearsItsHitTestingViewAfterItsHitTest() {
        let bridge = Bridge()
        bridge.enter()
        #expect(TooltipController.controller(for: bridge.scene.window).hitTestingView == nil)
    }

    @Test func theControllersOwnHitTestReachesTheAnchorAndShowsItsTooltip() {
        let bridge = Bridge()
        bridge.enter()
        bridge.scene.clock.advance(0.55)
        #expect(bridge.scene.label == "Copy URL")
        #expect(bridge.scene.tooltip?.isVisible == false && !bridge.scene.window.isVisible && bridge.clicks == 0)
    }

    @Test func theBackstopsOwnHitTestReachesTheAnchorTooSoTheTooltipStays() {
        let bridge = Bridge()
        bridge.enter()
        bridge.scene.clock.advance(0.55)
        bridge.scene.clock.advance(0.8)
        #expect(bridge.scene.tooltip != nil)
    }

    @Test func onceThePointerLeavesTheBackstopHidesIt() {
        let bridge = Bridge()
        bridge.enter()
        bridge.scene.clock.advance(0.55)
        bridge.scene.window.pointer = NSPoint(x: -100, y: -100)
        bridge.scene.clock.advance(0.9)
        #expect(bridge.scene.tooltip == nil)
    }

    @Test func aNilConfigurationRemovesTheAnchor() {
        let bridge = Bridge()
        bridge.host.rootView = AnyView(SwiftUI.Button("Copy") {}.frame(width: 48, height: 32).parcTooltip(nil))
        bridge.host.layoutSubtreeIfNeeded()
        #expect(bridge.anchors.isEmpty)
    }
}
