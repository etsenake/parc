import AppKit
import QuartzCore
import Testing
@testable import Parc

@MainActor
struct SplitPaneControlPresentationTestsVisibility {
    private typealias Support = SplitPaneControlPresentationTestsSupport

    private typealias ControlWindow = Support.ControlWindow
    private typealias FlippedControlHost = Support.FlippedControlHost
    private typealias TrackingEvent = Support.TrackingEvent
    private typealias SeeThroughView = Support.SeeThroughView

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
