import AppKit

@MainActor private final class HoverApplication: NSApplication {
    var simulatedActive = true
    override var isActive: Bool { simulatedActive }
}

@MainActor private final class HoverWindow: NSWindow {
    var key = true
    var simulatedVisible = true
    var pointer = NSPoint(x: -10, y: -10)
    var modal: NSWindow?
    override var isKeyWindow: Bool { key }
    override var isVisible: Bool { simulatedVisible }
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    override var attachedSheet: NSWindow? { modal }
}

@MainActor private final class ActionCounter: NSObject {
    var count = 0
    @objc func invoke() { count += 1 }
}

private final class HoverTrackingEvent: NSEvent {
    var area: NSTrackingArea?
    var ownerNumber = 0
    override var trackingArea: NSTrackingArea? { area }
    override var windowNumber: Int { ownerNumber }
}

@main @MainActor struct SettingsHoverTests {
    static func main() {
        let app = HoverApplication.shared as! HoverApplication
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        func makeWindow() -> HoverWindow {
            let window = HoverWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
                                    styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
            return window
        }
        let first = makeWindow(), second = makeWindow()
        let control = SettingsHoverButton(frame: NSRect(x: 20, y: 20, width: 180, height: 34))
        let counter = ActionCounter()
        control.title = "Manage Passwords"; control.target = counter; control.action = #selector(ActionCounter.invoke)
        first.contentView!.addSubview(control)
        func move(_ window: HoverWindow, _ point: NSPoint = NSPoint(x: 40, y: 35)) {
            window.pointer = point
            control.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        }
        control.updateTrackingAreas(); control.updateTrackingAreas()
        check(control.trackingAreas.filter { !$0.options.contains(.cursorUpdate) }.count == 1,
              "Layout replaces the original tracking area")
        move(first)
        check(control.isHovered, "Current native window pointer enters the original control")
        control.needsDisplay = false
        move(first, NSPoint(x: 201, y: 35))
        check(!control.isHovered && control.needsDisplay, "Bounds exit immediately retires decoration")
        move(first)
        control.isEnabled = false
        check(!control.isHovered, "Disabling a hovered command clears decoration")
        control.performClick(nil)
        check(counter.count == 0, "Disabled native action is not accepted")
        control.isEnabled = true
        check(control.isHovered, "Enabling refreshes the actual original pointer")
        control.isEnabled = false
        first.pointer = NSPoint(x: -10, y: -10)
        control.isEnabled = true
        check(!control.isHovered, "Enabling cannot revive a pointer that has left")
        move(first)
        control.performClick(nil)
        check(counter.count == 1, "Native accepted action is dispatched exactly once")
        let cover = NSView(frame: control.frame)
        first.contentView!.addSubview(cover)
        move(first)
        check(!control.isHovered, "An overlapping native view owns the pointer")
        cover.removeFromSuperview(); move(first)
        check(control.isHovered, "Removing the covering view restores the original hit target")
        first.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: first)
        check(!control.isHovered, "Key-window loss retires hover")
        move(first)
        check(!control.isHovered, "A background-window event cannot revive decoration")
        first.key = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: first)
        check(control.isHovered, "Key return uses the actual current pointer")
        app.simulatedActive = false
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: app)
        check(!control.isHovered, "App deactivation clears hover")
        app.simulatedActive = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: app)
        check(control.isHovered, "App activation refreshes the original owner")
        NotificationCenter.default.post(name: NSWindow.willBeginSheetNotification, object: first)
        move(first)
        check(!control.isHovered, "Sheet admission suppresses parent hover before attachment")
        first.modal = second
        NotificationCenter.default.post(name: NSWindow.didEndSheetNotification, object: first)
        check(!control.isHovered, "A still-attached sheet remains authoritative")
        first.modal = nil
        NotificationCenter.default.post(name: NSWindow.didEndSheetNotification, object: first)
        check(control.isHovered, "Sheet completion refreshes the original pointer")
        control.isHidden = true
        check(!control.isHovered, "Hidden control cannot show hover")
        control.isHidden = false
        move(first)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: first)
        move(first)
        check(!control.isHovered, "Closing owner rejects late pointer updates")
        second.contentView!.addSubview(control)
        check(!control.isHovered, "Moving to a new owner discards the old pointer")
        move(first)
        check(!control.isHovered, "Event from the former window cannot enter new control")
        move(second)
        check(control.isHovered, "New owner has its own hover lifecycle")
        move(first)
        check(control.isHovered, "A late former-window event cannot clear current hover")
        let retiredExit = HoverTrackingEvent()
        retiredExit.area = control.trackingAreas.first { !$0.options.contains(.cursorUpdate) }
        retiredExit.ownerNumber = second.windowNumber
        control.updateTrackingAreas()
        control.mouseExited(with: retiredExit)
        check(control.isHovered, "Replaced tracking area cannot clear current hover")
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: first)
        NotificationCenter.default.post(name: NSWindow.willBeginSheetNotification, object: first)
        check(control.isHovered, "Former-window notifications cannot retire current hover")
        control.removeFromSuperview()
        check(!control.isHovered, "Detachment clears presentation")
        second.contentView!.addSubview(control)
        move(second)
        second.simulatedVisible = false
        check(!control.isHovered, "Nonvisible window never exposes decoration")
        first.simulatedVisible = false
        first.close(); second.close()
        print("Settings hover: \(checks) assertions passed")
    }
}
