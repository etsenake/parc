import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcKit

@MainActor
struct SplitPaneControlPresentationTestsLock {
    private typealias TrackingEvent = SplitPaneControlPresentationTestsSupport.TrackingEvent
    private typealias SeeThroughView = SplitPaneControlPresentationTestsSupport.SeeThroughView
    private typealias ControlFixture = SplitPaneControlPresentationTestsSupport.ControlFixture

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
