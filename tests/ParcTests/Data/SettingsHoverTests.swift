import AppKit
import Testing
@testable import Parc

@MainActor
private final class HoverWindow: NSWindow {
    var key = true
    var simulatedVisible = true
    var pointer = NSPoint(x: -10, y: -10)
    var modal: NSWindow?
    override var isKeyWindow: Bool { key }
    override var isVisible: Bool { simulatedVisible }
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    override var attachedSheet: NSWindow? { modal }
}

@MainActor
private final class ActionCounter: NSObject {
    var count = 0
    @objc func invoke() { count += 1 }
}

private final class HoverTrackingEvent: NSEvent {
    var area: NSTrackingArea?
    var ownerNumber = 0
    override var trackingArea: NSTrackingArea? { area }
    override var windowNumber: Int { ownerNumber }
}

@MainActor
struct SettingsHoverTests {
    @MainActor private final class Fixture {
        let first = Fixture.makeWindow()
        let second = Fixture.makeWindow()
        let control = SettingsHoverButton(frame: NSRect(x: 20, y: 20, width: 180, height: 34))
        let counter = ActionCounter()
        private final class Activity { var active = true }

        private let activity = Activity()
        var applicationActive: Bool {
            get { activity.active }
            set { activity.active = newValue }
        }

        init() {
            _ = NSApplication.shared
            control.title = "Manage Passwords"
            control.target = counter
            control.action = #selector(ActionCounter.invoke)
            let activity = activity
            control.applicationIsActive = { activity.active }
            first.contentView!.addSubview(control)
        }

        deinit {
            MainActor.assumeIsolated {
                first.close()
                second.close()
            }
        }

        static func makeWindow() -> HoverWindow {
            let window = HoverWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
                                     styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
            return window
        }

        func move(_ window: HoverWindow, to point: NSPoint = NSPoint(x: 40, y: 35)) {
            window.pointer = point
            control.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0,
                pressure: 0)!)
        }

        func hovering() -> Fixture {
            move(first)
            return self
        }

        func post(_ name: Notification.Name, from window: NSWindow) {
            NotificationCenter.default.post(name: name, object: window)
        }

        func postApplication(_ name: Notification.Name) {
            NotificationCenter.default.post(name: name, object: NSApp)
        }
    }

    @Test func layoutReplacesTheOriginalTrackingArea() {
        let fixture = Fixture()
        fixture.control.updateTrackingAreas()
        fixture.control.updateTrackingAreas()
        #expect(fixture.control.trackingAreas.filter { !$0.options.contains(.cursorUpdate) }.count == 1)
    }

    @Test func theCurrentWindowPointerEntersTheOriginalControl() {
        let fixture = Fixture().hovering()
        #expect(fixture.control.isHovered)
    }

    @Test func leavingTheBoundsRetiresDecorationImmediately() {
        let fixture = Fixture().hovering()
        fixture.control.needsDisplay = false
        fixture.move(fixture.first, to: NSPoint(x: 201, y: 35))
        #expect(!fixture.control.isHovered)
        #expect(fixture.control.needsDisplay)
    }

    @Test func disablingAHoveredCommandClearsDecoration() {
        let fixture = Fixture().hovering()
        fixture.control.isEnabled = false
        #expect(!fixture.control.isHovered)
    }

    @Test func aDisabledActionIsNotAccepted() {
        let fixture = Fixture().hovering()
        fixture.control.isEnabled = false
        fixture.control.performClick(nil)
        #expect(fixture.counter.count == 0)
    }

    @Test func enablingRefreshesTheActualPointer() {
        let fixture = Fixture().hovering()
        fixture.control.isEnabled = false
        fixture.control.isEnabled = true
        #expect(fixture.control.isHovered)
    }

    @Test func enablingCannotReviveAPointerThatHasLeft() {
        let fixture = Fixture().hovering()
        fixture.control.isEnabled = false
        fixture.first.pointer = NSPoint(x: -10, y: -10)
        fixture.control.isEnabled = true
        #expect(!fixture.control.isHovered)
    }

    @Test func anAcceptedActionIsDispatchedExactlyOnce() {
        let fixture = Fixture().hovering()
        _ = fixture.control.sendAction(fixture.control.action, to: fixture.control.target)
        #expect(fixture.counter.count == 1)
    }

    @Test func anOverlappingViewOwnsThePointer() {
        let fixture = Fixture()
        let cover = NSView(frame: fixture.control.frame)
        fixture.first.contentView!.addSubview(cover)
        fixture.move(fixture.first)
        #expect(!fixture.control.isHovered)
    }

    @Test func removingTheCoveringViewRestoresTheOriginalHitTarget() {
        let fixture = Fixture()
        let cover = NSView(frame: fixture.control.frame)
        fixture.first.contentView!.addSubview(cover)
        fixture.move(fixture.first)
        cover.removeFromSuperview()
        fixture.move(fixture.first)
        #expect(fixture.control.isHovered)
    }

    @Test func losingKeyRetiresHover() {
        let fixture = Fixture().hovering()
        fixture.first.key = false
        fixture.post(NSWindow.didResignKeyNotification, from: fixture.first)
        #expect(!fixture.control.isHovered)
    }

    @Test func aBackgroundWindowEventCannotReviveDecoration() {
        let fixture = Fixture().hovering()
        fixture.first.key = false
        fixture.post(NSWindow.didResignKeyNotification, from: fixture.first)
        fixture.move(fixture.first)
        #expect(!fixture.control.isHovered)
    }

    @Test func returningKeyUsesTheActualCurrentPointer() {
        let fixture = Fixture().hovering()
        fixture.first.key = false
        fixture.post(NSWindow.didResignKeyNotification, from: fixture.first)
        fixture.first.key = true
        fixture.post(NSWindow.didBecomeKeyNotification, from: fixture.first)
        #expect(fixture.control.isHovered)
    }

    @Test func applicationDeactivationClearsHover() {
        let fixture = Fixture().hovering()
        fixture.applicationActive = false
        fixture.postApplication(NSApplication.didResignActiveNotification)
        #expect(!fixture.control.isHovered)
    }

    @Test func applicationActivationRefreshesTheOriginalOwner() {
        let fixture = Fixture().hovering()
        fixture.applicationActive = false
        fixture.postApplication(NSApplication.didResignActiveNotification)
        fixture.applicationActive = true
        fixture.postApplication(NSApplication.didBecomeActiveNotification)
        #expect(fixture.control.isHovered)
    }

    @Test func sheetAdmissionSuppressesParentHoverBeforeAttachment() {
        let fixture = Fixture().hovering()
        fixture.post(NSWindow.willBeginSheetNotification, from: fixture.first)
        fixture.move(fixture.first)
        #expect(!fixture.control.isHovered)
    }

    @Test func aStillAttachedSheetRemainsAuthoritative() {
        let fixture = Fixture().hovering()
        fixture.post(NSWindow.willBeginSheetNotification, from: fixture.first)
        fixture.first.modal = fixture.second
        fixture.post(NSWindow.didEndSheetNotification, from: fixture.first)
        #expect(!fixture.control.isHovered)
    }

    @Test func sheetCompletionRefreshesTheOriginalPointer() {
        let fixture = Fixture().hovering()
        fixture.post(NSWindow.willBeginSheetNotification, from: fixture.first)
        fixture.post(NSWindow.didEndSheetNotification, from: fixture.first)
        #expect(fixture.control.isHovered)
    }

    @Test func aHiddenControlCannotShowHover() {
        let fixture = Fixture().hovering()
        fixture.control.isHidden = true
        #expect(!fixture.control.isHovered)
    }

    @Test func aClosingOwnerRejectsLatePointerUpdates() {
        let fixture = Fixture().hovering()
        fixture.post(NSWindow.willCloseNotification, from: fixture.first)
        fixture.move(fixture.first)
        #expect(!fixture.control.isHovered)
    }

    @Test func movingToANewOwnerDiscardsTheOldPointer() {
        let fixture = Fixture().hovering()
        fixture.second.contentView!.addSubview(fixture.control)
        #expect(!fixture.control.isHovered)
    }

    @Test func anEventFromTheFormerWindowCannotEnterTheNewControl() {
        let fixture = Fixture().hovering()
        fixture.second.contentView!.addSubview(fixture.control)
        fixture.move(fixture.first)
        #expect(!fixture.control.isHovered)
    }

    @Test func aNewOwnerHasItsOwnHoverLifecycle() {
        let fixture = Fixture().hovering()
        fixture.second.contentView!.addSubview(fixture.control)
        fixture.move(fixture.second)
        #expect(fixture.control.isHovered)
    }

    @Test func aLateFormerWindowEventCannotClearCurrentHover() {
        let fixture = Fixture().hovering()
        fixture.second.contentView!.addSubview(fixture.control)
        fixture.move(fixture.second)
        fixture.move(fixture.first)
        #expect(fixture.control.isHovered)
    }

    @Test func aReplacedTrackingAreaCannotClearCurrentHover() {
        let fixture = Fixture().hovering()
        fixture.second.contentView!.addSubview(fixture.control)
        fixture.move(fixture.second)
        let retiredExit = HoverTrackingEvent()
        retiredExit.area = fixture.control.trackingAreas.first { !$0.options.contains(.cursorUpdate) }
        retiredExit.ownerNumber = fixture.second.windowNumber
        fixture.control.updateTrackingAreas()
        fixture.control.mouseExited(with: retiredExit)
        #expect(fixture.control.isHovered)
    }

    @Test func formerWindowNotificationsCannotRetireCurrentHover() {
        let fixture = Fixture().hovering()
        fixture.second.contentView!.addSubview(fixture.control)
        fixture.move(fixture.second)
        fixture.post(NSWindow.willCloseNotification, from: fixture.first)
        fixture.post(NSWindow.willBeginSheetNotification, from: fixture.first)
        #expect(fixture.control.isHovered)
    }

    @Test func detachmentClearsPresentation() {
        let fixture = Fixture().hovering()
        fixture.control.removeFromSuperview()
        #expect(!fixture.control.isHovered)
    }

    @Test func aNonvisibleWindowNeverExposesDecoration() {
        let fixture = Fixture().hovering()
        fixture.first.simulatedVisible = false
        #expect(!fixture.control.isHovered)
    }
}
