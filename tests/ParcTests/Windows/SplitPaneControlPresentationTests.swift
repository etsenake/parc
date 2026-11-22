import AppKit
import QuartzCore
import Testing
@testable import Parc

@MainActor private final class ControlWindow: NSWindow {
    var key = true
    var pointer = NSPoint(x: -100, y: -100)
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    override var isKeyWindow: Bool { key }
}

private final class FlippedControlHost: NSView { override var isFlipped: Bool { true } }

private final class TrackingEvent: NSEvent {
    var area: NSTrackingArea?
    var location = NSPoint.zero
    var eventWindow: NSWindow?
    override var trackingArea: NSTrackingArea? { area }
    override var locationInWindow: NSPoint { location }
    override var window: NSWindow? { eventWindow }
}

private final class SeeThroughView: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }

@MainActor private final class ControlFixture {
    let window: ControlWindow
    let host: NSView
    let control: SplitPaneControl
    let background: CALayer
    let glyph: NSImageView
    var actions = 0

    init(kind: SplitPaneControl.Kind = .menu, frame: NSRect = NSRect(x: 20, y: 20, width: 32, height: 24),
         reduceMotion: Bool = false) {
        _ = NSApplication.shared
        window = ControlWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host = NSView(frame: window.contentView!.bounds)
        window.contentView = host
        control = SplitPaneControl(kind, reduceMotion: { reduceMotion })
        control.frame = frame
        host.addSubview(control)
        control.layoutSubtreeIfNeeded()
        control.updateTrackingAreas()
        background = control.layer!.sublayers!.first!
        glyph = control.subviews.compactMap { $0 as? NSImageView }.first!
        control.actionBlock = { [weak self] in self?.actions += 1 }
        control.appearance = NSAppearance(named: .aqua)
        control.viewDidChangeEffectiveAppearance()
    }

    deinit { MainActor.assumeIsolated { window.close() } }

    var ownedAreas: [NSTrackingArea] {
        control.trackingAreas.filter { $0.owner === control && $0.options == [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeInKeyWindow] }
    }

    var hoverEvent: TrackingEvent {
        let event = TrackingEvent()
        event.area = ownedAreas[0]
        return event
    }

    func setDark(_ dark: Bool) {
        control.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        control.viewDidChangeEffectiveAppearance()
    }

    func press(_ pressed: Bool) { control.cell!.highlight(pressed, withFrame: control.bounds, in: control) }
}

@MainActor
struct SplitPaneControlPresentationTests {
    private static func near(_ value: CGFloat?, _ expected: CGFloat) -> Bool { abs((value ?? -1) - expected) < 0.00001 }
    private static func near(_ value: Float, _ expected: Float) -> Bool { abs(value - expected) < 0.00001 }

    @Test func theTopBarSharesItsParentDimensions() {
        #expect(PaneTopBarLayout.height == 32)
        #expect(PaneTopBarLayout.horizontalInset == 5)
    }

    @Test func aSymbolIsCentredIndependentlyOfTheContentInset() {
        #expect(PaneTopBarLayout.frame(x: 15, width: 32, height: 24) == NSRect(x: 15, y: 4, width: 32, height: 24))
    }

    @Test func aTitleCentresInTheSameParentRow() {
        #expect(PaneTopBarLayout.frame(x: 13, width: 100, height: 26).midY == 16)
    }

    @Test func theMenuControlHasTheOriginalSymbolSurface() {
        let fixture = ControlFixture()
        #expect(fixture.control.intrinsicContentSize == NSSize(width: 32, height: 24))
    }

    @Test func theBackgroundIsContinuousAndRounded() {
        let fixture = ControlFixture()
        #expect(fixture.background.frame == fixture.control.bounds)
        #expect(fixture.background.cornerRadius == 6)
        #expect(fixture.background.cornerCurve == .continuous)
    }

    @Test func theFocusRingFollowsTheSymbolSurface() {
        let fixture = ControlFixture()
        #expect(fixture.control.focusRingMaskBounds == fixture.control.bounds)
    }

    @Test func theMenuControlKeepsItsIdentityTooltipAndHelp() {
        let control = ControlFixture().control
        #expect(control.accessibilityLabel() == "Split View Menu")
        #expect(control.parcTooltip == TooltipConfiguration("Split View Options"))
        #expect(control.toolTip == nil)
        #expect(control.accessibilityHelp() == "Split View Options")
        #expect(control.accessibilityRole() == .button)
    }

    @Test func theGlyphTakesNoInputAndHasNoAccessibilityIdentity() {
        let fixture = ControlFixture()
        #expect(fixture.glyph.hitTest(.zero) == nil)
        #expect(!fixture.glyph.isAccessibilityElement())
    }

    @Test func theButtonOwnsTheGlyphHit() {
        let fixture = ControlFixture()
        #expect(fixture.control.hitTest(NSPoint(x: 30, y: 30)) === fixture.control)
    }

    @Test func theSystemCellAddsNoUnrelatedPressFill() {
        #expect((ControlFixture().control.cell as? NSButtonCell)?.highlightsBy == [])
    }

    @Test func oneDecorationTrackingAreaSitsAlongsideAppKitsOwn() {
        #expect(ControlFixture().ownedAreas.count == 1)
    }

    @Test func aRetiredTrackingEventCannotStartHover() {
        let fixture = ControlFixture()
        let old = fixture.hoverEvent
        fixture.control.updateTrackingAreas()
        fixture.control.mouseEntered(with: old)
        #expect(!fixture.control.isHovered)
    }

    @Test func restInLightIsSoftInkWithNoSurface() {
        let fixture = ControlFixture()
        #expect(Self.near(fixture.glyph.contentTintColor?.alphaComponent, 0.55))
        #expect(fixture.background.opacity == 0)
    }

    @Test func lightHoverRaisesTheSurfaceToFivePercent() {
        let fixture = ControlFixture()
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        #expect(fixture.control.isHovered)
        #expect(Self.near(fixture.background.opacity, 0.05))
    }

    @Test(arguments: [false, true])
    func hoverFadesOnlyWhenMotionIsAllowed(reduceMotion: Bool) {
        let fixture = ControlFixture(reduceMotion: reduceMotion)
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        #expect(fixture.background.animation(forKey: "split-control-opacity")?.duration == (reduceMotion ? nil : 0.18))
    }

    @Test func aNativePressTakesPrecedenceOverHover() {
        let fixture = ControlFixture()
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        fixture.press(true)
        #expect(fixture.control.isPressed)
        #expect(Self.near(fixture.background.opacity, 0.09))
    }

    @Test(arguments: [false, true])
    func pressingFadesOnlyWhenMotionIsAllowed(reduceMotion: Bool) {
        let fixture = ControlFixture(reduceMotion: reduceMotion)
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        fixture.press(true)
        #expect(fixture.background.animation(forKey: "split-control-opacity")?.duration == (reduceMotion ? nil : 0.16))
    }

    @Test func darkEnabledPressRaisesInkAndSurface() {
        let fixture = ControlFixture()
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        fixture.press(true)
        fixture.setDark(true)
        #expect(Self.near(fixture.glyph.contentTintColor?.alphaComponent, 0.675))
        #expect(Self.near(fixture.background.opacity, 0.13))
    }

    @Test func darkInkIsWhite() {
        let fixture = ControlFixture()
        fixture.setDark(true)
        #expect(NSColor(cgColor: fixture.background.backgroundColor!)?.usingColorSpace(.sRGB)?.redComponent == 1)
    }

    @Test func aNativeReleaseReturnsToDarkHover() {
        let fixture = ControlFixture()
        fixture.setDark(true)
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        fixture.press(true)
        fixture.press(false)
        #expect(!fixture.control.isPressed)
        #expect(Self.near(fixture.background.opacity, 0.09))
    }

    @Test func aRetiredExitCannotClearCurrentHover() {
        let fixture = ControlFixture()
        let old = fixture.hoverEvent
        fixture.control.updateTrackingAreas()
        let current = fixture.hoverEvent
        fixture.control.mouseEntered(with: current)
        fixture.control.mouseExited(with: old)
        #expect(fixture.control.isHovered)
    }

    @Test func theCurrentExitReturnsToRest() {
        let fixture = ControlFixture()
        let hover = fixture.hoverEvent
        fixture.control.mouseEntered(with: hover)
        fixture.control.mouseExited(with: hover)
        #expect(!fixture.control.isHovered)
        #expect(fixture.background.opacity == 0)
    }

    @Test func aClickReachesTheCallback() {
        let fixture = ControlFixture()
        fixture.control.sendClick()
        #expect(fixture.actions == 1)
    }

    @Test func aDisabledControlRefusesActionAndDecoration() {
        let fixture = ControlFixture()
        fixture.control.isEnabled = false
        fixture.control.sendClick()
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        #expect(fixture.actions == 0)
        #expect(!fixture.control.isHovered && !fixture.control.isPressed)
        #expect(fixture.background.opacity == 0)
    }

    @Test func aDisabledControlUsesTheDisabledInk() {
        let fixture = ControlFixture()
        fixture.control.isEnabled = false
        #expect(fixture.glyph.contentTintColor?.alphaComponent == 0.25)
    }

    @Test func losingKeyCancelsStateAndDispatch() {
        let fixture = ControlFixture()
        let hover = fixture.hoverEvent
        fixture.control.mouseEntered(with: hover)
        fixture.window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        fixture.control.sendClick()
        fixture.control.mouseEntered(with: hover)
        #expect(fixture.actions == 0)
        #expect(!fixture.control.isHovered)
        #expect(fixture.background.animationKeys()?.isEmpty != false)
    }

    @Test func aHiddenControlCannotInvoke() {
        let fixture = ControlFixture()
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        fixture.control.isHidden = true
        fixture.control.viewDidHide()
        fixture.control.sendClick()
        #expect(fixture.actions == 0)
        #expect(!fixture.control.isHovered && !fixture.control.isPressed)
    }

    @Test func anAppearanceOptionsChangeRetiresInFlightMotion() {
        let fixture = ControlFixture()
        fixture.control.mouseEntered(with: fixture.hoverEvent)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(fixture.background.animationKeys()?.isEmpty != false)
    }

    @Test func detachingRevokesTrackingAndCallbackAdmission() {
        let fixture = ControlFixture()
        let hover = fixture.hoverEvent
        fixture.control.mouseEntered(with: hover)
        fixture.control.removeFromSuperview()
        fixture.control.mouseEntered(with: hover)
        fixture.control.sendClick()
        #expect(fixture.actions == 0)
        #expect(!fixture.control.isHovered)
        #expect(fixture.ownedAreas.isEmpty)
    }

    @Test func anEventWithoutAnAttributedAreaCannotStartDecoration() {
        let fixture = ControlFixture()
        fixture.control.removeFromSuperview()
        fixture.host.addSubview(fixture.control)
        fixture.control.mouseEntered(with: TrackingEvent())
        #expect(!fixture.control.isHovered)
    }

    @Test func oldWindowTrackingDoesNotReviveAfterAttach() {
        let fixture = ControlFixture()
        let old = fixture.hoverEvent
        fixture.control.removeFromSuperview()
        fixture.host.addSubview(fixture.control)
        fixture.control.updateTrackingAreas()
        fixture.control.mouseEntered(with: old)
        #expect(!fixture.control.isHovered)
    }

    @Test func theCloseControlSharesStyleWithADistinctActionIdentity() {
        let fixture = ControlFixture()
        let close = SplitPaneControl(.close)
        #expect(close.accessibilityLabel() == "Close Split View Pane")
        #expect(close.parcTooltip?.label == "Remove Tab from Split View")
        #expect(close.intrinsicContentSize == fixture.control.intrinsicContentSize)
    }

    @Test(arguments: [0, 1])
    func eachSplitPanesCloseRetiresThatPage(_ index: Int) {
        let panes = [UUID(), UUID()]
        #expect(SplitPaneCloseAdmission.accepts(tabID: panes[index], selected: panes))
    }

    @Test func closeCannotRetireAPageOutsideTheSplit() {
        #expect(!SplitPaneCloseAdmission.accepts(tabID: UUID(), selected: [UUID(), UUID()]))
    }

    @Test func closeCannotRetireASinglePage() {
        let pane = UUID()
        #expect(!SplitPaneCloseAdmission.accepts(tabID: pane, selected: [pane]))
    }

    @Test func closeCannotRetireAPeek() {
        let panes = [UUID(), UUID()]
        #expect(!SplitPaneCloseAdmission.accepts(tabID: panes[0], selected: panes, isPeek: true))
    }

    @Test func releasedControlsAreNotRetainedByObserversOrLayers() {
        let fixture = ControlFixture()
        weak var retired: SplitPaneControl?
        autoreleasepool {
            let temporary = SplitPaneControl(.menu)
            retired = temporary
            fixture.host.addSubview(temporary)
            temporary.removeFromSuperview()
        }
        #expect(retired == nil)
    }
}

@MainActor
struct SplitPaneInsecureLockTests {
    private static func near(_ value: Float, _ expected: Float) -> Bool { abs(value - expected) < 0.00001 }

    @MainActor private final class Lock {
        let fixture = ControlFixture(kind: .insecure, frame: NSRect(x: 60, y: 20, width: 24, height: 24))
        var control: SplitPaneControl { fixture.control }
        var surface: CALayer { fixture.background }
        var glyph: NSImageView { fixture.glyph }
        let area = TrackingEvent()

        init() {
            area.area = control.trackingAreas.first { $0.owner === control && $0.options.contains(.inVisibleRect) && !$0.options.contains(.cursorUpdate) }
            area.location = control.convert(NSPoint(x: 12, y: 12), to: nil)
        }
    }

    @Test func theLockHasTheTwentyFourPointSlotAndSurface() {
        let lock = Lock()
        #expect(lock.control.intrinsicContentSize == NSSize(width: 24, height: 24))
        #expect(lock.surface.frame == lock.control.bounds)
    }

    @Test func theLockKeepsItsLabelTooltipAndHelp() {
        let control = Lock().control
        #expect(control.accessibilityLabel() == "Site is not secure")
        #expect(control.parcTooltip?.label == "Site is not secure")
        #expect(control.accessibilityHelp() == "Site is not secure")
        #expect(control.accessibilityRole() == .button)
    }

    @Test func theLockIsRed() {
        #expect(Lock().glyph.contentTintColor == .systemRed)
    }

    @Test func aDisabledLockKeepsItsForegroundAndShowsNoSurface() {
        let lock = Lock()
        lock.control.isEnabled = false
        #expect(lock.glyph.contentTintColor == .systemRed)
        #expect(lock.surface.opacity == 0)
    }

    @Test func theLockSharesTheSymbolHoverSurface() {
        let lock = Lock()
        lock.control.mouseEntered(with: lock.area)
        #expect(lock.control.isHovered)
        #expect(Self.near(lock.surface.opacity, 0.05))
    }

    @Test func aCommandSurfaceCoveringTheControlKeepsHoverOff() {
        let lock = Lock()
        lock.fixture.host.addSubview(NSView(frame: lock.control.frame.insetBy(dx: -4, dy: -4)))
        lock.control.mouseEntered(with: lock.area)
        #expect(!lock.control.isHovered)
        #expect(lock.surface.opacity == 0)
    }

    @Test func movingOutFromUnderTheCoverRestoresHover() throws {
        let lock = Lock()
        let cover = NSView(frame: lock.control.frame.insetBy(dx: -4, dy: -4))
        lock.fixture.host.addSubview(cover)
        lock.control.mouseEntered(with: lock.area)
        cover.removeFromSuperview()
        let move = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: lock.area.location, modifierFlags: [], timestamp: 0,
                                                   windowNumber: lock.fixture.window.windowNumber, context: nil, eventNumber: 0,
                                                   clickCount: 0, pressure: 0))
        lock.control.mouseMoved(with: move)
        #expect(lock.control.isHovered)
        #expect(Self.near(lock.surface.opacity, 0.05))
    }

    @Test func aSeeThroughOverlayLeavesHoverAlone() {
        let lock = Lock()
        lock.fixture.host.addSubview(SeeThroughView(frame: lock.control.frame.insetBy(dx: -4, dy: -4)))
        lock.control.mouseEntered(with: lock.area)
        #expect(lock.control.isHovered)
    }
}

@MainActor
struct SplitPaneControlLayoutSkipTests {
    private typealias Skip = SplitPaneControlLayoutSkip
    private static let bounds = NSRect(x: 0, y: 0, width: 32, height: 24)

    private final class GeometryWrites: NSObject {
        private let surface: CALayer
        private var surfaceFrameWrites = 0
        private var surfaceLayerWrites = 0
        private var glyphFrameWrites = 0

        init(surface: CALayer) { self.surface = surface }

        @MainActor static func during(_ fixture: ControlFixture, _ update: () -> Void)
            -> (surfaceFrame: Int, surfaceLayer: Int, glyphFrame: Int) {
            let keys = ["frame", "bounds", "position", "transform", "cornerRadius", "maskedCorners", "shadowPath"]
            let writes = GeometryWrites(surface: fixture.background)
            let writeSurfaceFrame = fixture.control.writeSurfaceFrame
            fixture.control.writeSurfaceFrame = { layer, frame in
                writes.surfaceFrameWrites += 1
                writeSurfaceFrame(layer, frame)
            }
            for key in keys { fixture.background.addObserver(writes, forKeyPath: key, options: [], context: nil) }
            fixture.glyph.addObserver(writes, forKeyPath: "frame", options: [], context: nil)
            defer {
                fixture.glyph.removeObserver(writes, forKeyPath: "frame")
                for key in keys { fixture.background.removeObserver(writes, forKeyPath: key) }
                fixture.control.writeSurfaceFrame = writeSurfaceFrame
            }
            update()
            return (writes.surfaceFrameWrites, writes.surfaceLayerWrites, writes.glyphFrameWrites)
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                                   context: UnsafeMutableRawPointer?) {
            if object as? CALayer === surface { surfaceLayerWrites += 1 }
            else { glyphFrameWrites += 1 }
        }
    }

    @Test func aMatchingCentredSurfaceFrameSkips() {
        let current = Skip.surfaceFrame(bounds: Self.bounds, surfaceSize: SplitPaneControl.surfaceSize)
        #expect(Skip.shouldSkipSurface(current: current, bounds: Self.bounds, surfaceSize: SplitPaneControl.surfaceSize))
    }

    @Test func aMismatchedSurfaceFrameDoesNotSkip() {
        #expect(!Skip.shouldSkipSurface(current: .zero, bounds: Self.bounds, surfaceSize: SplitPaneControl.surfaceSize))
    }

    @Test func aMatchingGlyphFrameSkips() {
        #expect(Skip.shouldSkipGlyph(current: Self.bounds, bounds: Self.bounds))
    }

    @Test func aMismatchedGlyphFrameDoesNotSkip() {
        #expect(!Skip.shouldSkipGlyph(current: .zero, bounds: Self.bounds))
    }

    @Test func theSurfaceStaysCentredInsideALargerControl() {
        let oversized = NSRect(x: 0, y: 0, width: 40, height: 30)
        #expect(Skip.surfaceFrame(bounds: oversized, surfaceSize: SplitPaneControl.surfaceSize) == NSRect(x: 4, y: 3, width: 32, height: 24))
    }

    @Test func theFirstLargerLayoutWritesTheSurfaceAndGlyphFrames() {
        let fixture = ControlFixture()
        fixture.control.setFrameSize(NSSize(width: 36, height: 28))
        let writes = GeometryWrites.during(fixture) { fixture.control.layoutSubtreeIfNeeded() }
        #expect(writes.surfaceFrame == 1)
        #expect(writes.surfaceLayer > 0)
        #expect(writes.glyphFrame == 1)
    }

    @Test func aBoundsChangeRelaysTheCentredSurfaceAndGlyph() {
        let fixture = ControlFixture()
        fixture.control.frame = NSRect(x: 20, y: 20, width: 36, height: 28)
        fixture.control.layoutSubtreeIfNeeded()
        fixture.control.setFrameSize(NSSize(width: 40, height: 30))
        let writes = GeometryWrites.during(fixture) { fixture.control.layout() }
        #expect(writes.surfaceFrame == 1)
        #expect(writes.surfaceLayer > 0)
        #expect(writes.glyphFrame == 1)
        #expect(fixture.background.frame == Skip.surfaceFrame(bounds: fixture.control.bounds, surfaceSize: fixture.control.surfaceSize))
        #expect(fixture.glyph.frame == fixture.control.bounds)
    }

    @Test(arguments: [NSSize(width: 36, height: 28), NSSize(width: 40, height: 30)])
    func aLayoutAtTheSameSizeWritesNeitherTheSurfaceNorTheGlyph(size: NSSize) {
        let fixture = ControlFixture()
        fixture.control.setFrameSize(size)
        fixture.control.layoutSubtreeIfNeeded()
        let surface = fixture.background.frame, glyph = fixture.glyph.frame
        let writes = GeometryWrites.during(fixture) { fixture.control.layout() }
        #expect(writes == (0, 0, 0))
        #expect(fixture.background.frame == surface)
        #expect(fixture.glyph.frame == glyph)
    }

    @Test func aHoverRefreshIsNotGatedByTheLayoutSkip() {
        let fixture = ControlFixture()
        fixture.control.frame = NSRect(x: 20, y: 20, width: 36, height: 28)
        fixture.control.layoutSubtreeIfNeeded()
        fixture.control.updateTrackingAreas()
        let event = TrackingEvent()
        event.area = fixture.control.trackingAreas.first { $0.owner === fixture.control && $0.options.contains(.inVisibleRect) && !$0.options.contains(.cursorUpdate) }
        let writes = GeometryWrites.during(fixture) { fixture.control.mouseEntered(with: event) }
        #expect(fixture.control.isHovered)
        #expect(abs(fixture.background.opacity - 0.05) < 0.00001)
        #expect(writes == (0, 0, 0))
    }
}

@MainActor
struct PaneControlVisibilityTests {
    @MainActor private final class Fixture {
        let window: ControlWindow
        let host = NSView()
        let pane = FlippedControlHost(frame: NSRect(x: 20, y: 10, width: 120, height: 70))
        let reveal: PaneControlVisibility
        let bar = NSRect(x: 0, y: 0, width: 120, height: 32)
        var applicationActive = true
        var changes: [Bool] = []
        var durations: [TimeInterval?] = []

        init(focused: Bool = false) {
            _ = NSApplication.shared
            window = ControlWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            host.frame = window.contentView!.bounds
            window.contentView = host
            host.addSubview(pane)
            let box = Box()
            reveal = PaneControlVisibility(applicationIsActive: { box.active })
            box.owner = self
            reveal.onChange = { [weak self] value, duration in self?.changes.append(value); self?.durations.append(duration) }
            reveal.update(host: pane, bar: bar, focused: focused)
        }

        @MainActor final class Box {
            weak var owner: Fixture?
            var active: Bool { owner?.applicationActive ?? true }
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        var areas: [NSTrackingArea] { host.trackingAreas.filter { $0.owner === reveal } }

        func event(window: NSWindow? = nil) -> TrackingEvent {
            let event = TrackingEvent()
            event.area = areas.first
            event.eventWindow = window
            return event
        }

        func point(_ x: CGFloat, _ y: CGFloat) { window.pointer = pane.convert(NSPoint(x: x, y: y), to: nil) }

        func hover() -> TrackingEvent {
            point(60, 50)
            let enter = event()
            reveal.mouseEntered(with: enter)
            return enter
        }
    }

    @Test func theHoverRegionIsTheOriginalExpandedRegion() {
        #expect(PaneControlVisibility.hoverRegion(for: NSRect(x: 0, y: 0, width: 120, height: 32)) == NSRect(x: 0, y: -40, width: 120, height: 100))
    }

    @Test func anUnfocusedPaneBeginsEssentialOnly() {
        let fixture = Fixture()
        #expect(!fixture.reveal.isRevealed)
        #expect(fixture.changes == [false])
    }

    @Test func passiveRootTrackingCoversTheParentExtent() {
        let fixture = Fixture()
        #expect(fixture.areas.count == 1)
        #expect(fixture.areas[0].options == [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow])
    }

    @Test func theFlippedRegionIsConvertedIntoTheWindowContent() {
        let fixture = Fixture()
        #expect(fixture.areas[0].rect == fixture.host.convert(PaneControlVisibility.hoverRegion(for: fixture.bar), from: fixture.pane).intersection(fixture.host.bounds))
    }

    @Test func hoveringBelowTheBarRevealsTheBackgroundPaneOptions() {
        let fixture = Fixture()
        _ = fixture.hover()
        #expect(fixture.reveal.isHovered && fixture.reveal.isRevealed)
        #expect(fixture.changes.last == true)
    }

    @Test func theHoverRevealUsesTheOriginalFade() {
        let fixture = Fixture()
        _ = fixture.hover()
        #expect(fixture.durations.last == PaneTopBarFade.hover)
        #expect(PaneTopBarFade.hover == 0.18)
    }

    @Test func aPassiveRevealDoesNotMoveTheFirstResponder() {
        let fixture = Fixture()
        let responder = fixture.window.firstResponder
        _ = fixture.hover()
        #expect(fixture.window.firstResponder === responder)
    }

    @Test func leavingTheExactRegionRestoresEssentialOnly() {
        let fixture = Fixture()
        let enter = fixture.hover()
        fixture.point(60, 61)
        fixture.reveal.mouseExited(with: enter)
        #expect(!fixture.reveal.isHovered && !fixture.reveal.isRevealed)
    }

    @Test func aFocusedPaneNeedsNoHoverAndRevealsImmediately() {
        let fixture = Fixture()
        fixture.reveal.update(host: fixture.pane, bar: fixture.bar, focused: true)
        #expect(fixture.reveal.isRevealed && !fixture.reveal.isHovered)
        #expect(fixture.durations.last! == nil)
    }

    @Test func aPresentedModalHidesEvenAFocusedPanesMenu() {
        let fixture = Fixture()
        fixture.reveal.update(host: fixture.pane, bar: fixture.bar, focused: true)
        fixture.reveal.update(host: fixture.pane, bar: fixture.bar, focused: true, obstructed: true)
        #expect(!fixture.reveal.isRevealed)
        #expect(fixture.durations.last == PaneTopBarFade.obstruction)
        #expect(PaneTopBarFade.obstruction == 0.17)
    }

    @Test func retiringTheModalRestoresTheMenu() {
        let fixture = Fixture()
        fixture.reveal.update(host: fixture.pane, bar: fixture.bar, focused: true)
        fixture.reveal.update(host: fixture.pane, bar: fixture.bar, focused: true, obstructed: true)
        fixture.reveal.update(host: fixture.pane, bar: fixture.bar, focused: true, obstructed: false)
        #expect(fixture.reveal.isRevealed)
        #expect(fixture.durations.last == PaneTopBarFade.obstruction)
    }

    @Test func menuTrackingRetainsTheControlAndNestedTrackingKeepsIt() {
        let fixture = Fixture()
        var outer = false, nested = false, afterNested = false
        fixture.reveal.trackMenu {
            outer = fixture.reveal.isRevealed
            fixture.reveal.trackMenu { nested = fixture.reveal.isRevealed }
            afterNested = fixture.reveal.isRevealed
        }
        #expect(outer && nested && afterNested)
    }

    @Test func menuCompletionSamplesTheCurrentPointer() {
        let fixture = Fixture()
        fixture.reveal.trackMenu {}
        #expect(!fixture.reveal.isRevealed)
    }

    @Test func anObsoleteGeometryEventCannotRevealANewRegion() {
        let fixture = Fixture()
        let stale = fixture.event()
        fixture.pane.frame.origin.x += 5
        fixture.reveal.update(host: fixture.pane, bar: fixture.bar, focused: false)
        fixture.point(60, 20)
        fixture.reveal.mouseEntered(with: stale)
        #expect(!fixture.reveal.isRevealed)
    }

    @Test func currentGeometryAcceptsTheActualPointer() {
        let fixture = Fixture()
        fixture.pane.frame.origin.x += 5
        fixture.reveal.update(host: fixture.pane, bar: fixture.bar, focused: false)
        fixture.point(60, 20)
        fixture.reveal.mouseEntered(with: fixture.event())
        #expect(fixture.reveal.isRevealed)
    }

    @Test func keyLossRetiresHover() {
        let fixture = Fixture()
        let enter = fixture.hover()
        fixture.window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        fixture.reveal.mouseEntered(with: enter)
        #expect(!fixture.reveal.isRevealed && !fixture.reveal.isHovered)
    }

    @Test func keyReturnResamplesThePointer() {
        let fixture = Fixture()
        let enter = fixture.hover()
        fixture.window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        fixture.reveal.mouseEntered(with: enter)
        fixture.window.key = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: fixture.window)
        #expect(fixture.reveal.isRevealed)
    }

    @Test func applicationResignationClearsAndRefusesHover() {
        let fixture = Fixture()
        let enter = fixture.hover()
        fixture.applicationActive = false
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        fixture.reveal.mouseEntered(with: enter)
        #expect(!fixture.reveal.isHovered && !fixture.reveal.isRevealed)
    }

    @Test func applicationActivationSamplesTheCurrentPointer() {
        let fixture = Fixture()
        _ = fixture.hover()
        fixture.applicationActive = false
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        fixture.applicationActive = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        #expect(fixture.reveal.isRevealed)
    }

    @Test func aHiddenPaneReleasesRootTracking() {
        let fixture = Fixture()
        let enter = fixture.hover()
        fixture.pane.isHidden = true
        fixture.reveal.update(host: fixture.pane, bar: fixture.bar, focused: false)
        fixture.reveal.mouseEntered(with: enter)
        #expect(!fixture.reveal.isRevealed)
        #expect(fixture.areas.isEmpty)
    }

    @Test func aRevealedPaneSamplesThePointerWithoutSyntheticInput() {
        let fixture = Fixture()
        _ = fixture.hover()
        fixture.pane.isHidden = true
        fixture.reveal.update(host: fixture.pane, bar: fixture.bar, focused: false)
        fixture.pane.isHidden = false
        fixture.reveal.update(host: fixture.pane, bar: fixture.bar, focused: false)
        #expect(fixture.reveal.isRevealed)
    }

    @Test func movingOntoACommandSurfaceHidesTheOptions() {
        let fixture = Fixture()
        _ = fixture.hover()
        let move = fixture.event(window: fixture.window)
        fixture.host.addSubview(NSView(frame: fixture.pane.frame))
        fixture.reveal.mouseMoved(with: move)
        #expect(!fixture.reveal.isHovered && !fixture.reveal.isRevealed)
    }

    @Test func movingOutFromUnderTheCoverRevealsTheOptionsAgain() {
        let fixture = Fixture()
        _ = fixture.hover()
        let move = fixture.event(window: fixture.window)
        let cover = NSView(frame: fixture.pane.frame)
        fixture.host.addSubview(cover)
        fixture.reveal.mouseMoved(with: move)
        cover.removeFromSuperview()
        fixture.reveal.mouseMoved(with: move)
        #expect(fixture.reveal.isRevealed)
    }

    @Test func aSeeThroughOverlayLeavesTheHoverRevealAlone() {
        let fixture = Fixture()
        _ = fixture.hover()
        let move = fixture.event(window: fixture.window)
        fixture.host.addSubview(SeeThroughView(frame: fixture.pane.frame))
        fixture.reveal.mouseMoved(with: move)
        #expect(fixture.reveal.isRevealed)
    }

    @Test func invalidatingRetiresTheOldArea() {
        let fixture = Fixture()
        let enter = fixture.hover()
        fixture.reveal.invalidate()
        fixture.reveal.mouseEntered(with: enter)
        #expect(!fixture.reveal.isRevealed)
        #expect(fixture.areas.isEmpty)
    }

    @Test func aReleasedOwnerLeavesNoTrackingOrObserversBehind() {
        let fixture = Fixture()
        weak var retired: PaneControlVisibility?
        autoreleasepool {
            let temporary = PaneControlVisibility(applicationIsActive: { true })
            retired = temporary
            temporary.update(host: fixture.pane, bar: fixture.bar, focused: false)
        }
        #expect(retired == nil)
        #expect(fixture.host.trackingAreas.allSatisfy { !($0.owner is PaneControlVisibility) || $0.owner === fixture.reveal })
    }
}
