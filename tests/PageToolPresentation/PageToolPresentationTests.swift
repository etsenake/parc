import AppKit
import QuartzCore

@MainActor private final class KeyWindow: NSWindow {
    var key = true
    var pointer = NSPoint.zero
    override var isKeyWindow: Bool { key }
    override var canBecomeKey: Bool { true }
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}

@main struct PageToolPresentationTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }

        check(PageZoomAvailability.canChange(windowReady: true, closing: false, hasOriginalPage: true),
              "zoom stays available on the original page")
        check(!PageZoomAvailability.canChange(windowReady: false, closing: false, hasOriginalPage: true),
              "unready window cannot zoom")
        check(!PageZoomAvailability.canChange(windowReady: true, closing: true, hasOriginalPage: true),
              "closing window cannot zoom")
        check(!PageZoomAvailability.canChange(windowReady: true, closing: false, hasOriginalPage: false),
              "zoom requires an original page")
        check(PageZoomAvailability.canChange(windowReady: true, closing: false, hasOriginalPage: true),
              "no recovered min/max zoom disable")

        check(DeveloperToolbarSpring.restResponse == 0.2 && DeveloperToolbarSpring.restDampingRatio == 0.6,
              "rest spring is response 0.2 damping 0.6")
        check(DeveloperToolbarSpring.shakeResponse == 0.3 && DeveloperToolbarSpring.shakeDampingRatio == 0.4,
              "shake spring is response 0.3 damping 0.4")
        check(DeveloperToolbarSpring.shakeOffset == -5 && DeveloperToolbarSpring.resetDelay == 0.1,
              "shake offset -5 resets after 0.1s")
        let shake = DeveloperToolbarSpring.spring(response: 0.3, dampingRatio: 0.4)
        let omega = 2 * Double.pi / 0.3
        check(abs(shake.stiffness - omega * omega) < 0.0001, "shake stiffness is (2π/response)²")
        check(abs(shake.damping - 2 * 0.4 * omega) < 0.0001, "shake damping is 2ζ(2π/response)")
        check(shake.mass == 1, "shake spring uses unit mass")

        let hoverWindow = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: .borderless, backing: .buffered, defer: false)
        hoverWindow.isReleasedWhenClosed = false
        let surface = NSView(frame: hoverWindow.contentView!.bounds)
        hoverWindow.contentView = surface
        let control = DeveloperToolbarButton(symbol: "link", title: "Copy Link")
        control.frame = NSRect(x: 20, y: 20, width: 28, height: 28)
        surface.addSubview(control)
        control.updateTrackingAreas()
        let hoverAreas = control.trackingAreas.filter { !$0.options.contains(.cursorUpdate) }
        check(hoverAreas.count == 1, "one original hover tracking area")
        check(hoverAreas[0].options.rawValue == 0x223, "recovered key-window visible-rect tracking options")
        check(control.accessibilityRole() == .button, "named button role")
        check(control.accessibilityLabel() == "Copy Link", "named developer-strip control")
        check(control.focusRingType == .exterior, "exterior focus ring")
        check(control.focusRingMaskBounds == control.bounds, "native focus ring uses original bounds")
        control.updateLayer()
        check(control.layer?.cornerRadius == 5, "HoverableButtonStyle radius 5")

        let move = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: hoverWindow.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0)!
        hoverWindow.pointer = NSPoint(x: 34, y: 34)
        control.mouseMoved(with: move)
        check(control.isHovered, "actual same-window hit test admits pointer")
        control.appearance = NSAppearance(named: .aqua); control.updateLayer()
        check(control.layer?.cornerRadius == 5 && control.layer?.cornerCurve == .continuous,
              "original hover radius and curve")
        check(abs((control.layer?.backgroundColor?.alpha ?? 0) - 0.071) < 0.00001, "light GrayA4 alpha")
        control.appearance = NSAppearance(named: .darkAqua); control.updateLayer()
        check(abs((control.layer?.backgroundColor?.alpha ?? 0) - 0.077) < 0.00001, "dark GrayA4")
        (control.cell as? NSButtonCell)?.highlight(true, withFrame: control.bounds, in: control)
        control.updateLayer()
        check(control.isPressed, "native cell highlight owns press")
        check(abs((control.layer?.backgroundColor?.alpha ?? 0) - 0.103) < 0.00001, "dark GrayA5 press")
        control.appearance = NSAppearance(named: .aqua); control.updateLayer()
        check(abs((control.layer?.backgroundColor?.alpha ?? 0) - 0.090) < 0.00001, "light GrayA5 press")
        (control.cell as? NSButtonCell)?.highlight(false, withFrame: control.bounds, in: control)
        control.updateLayer()
        check(!control.isPressed, "native unhighlight clears press")
        control.isEnabled = false; control.updateLayer()
        check(!control.isHovered && (control.layer?.backgroundColor?.alpha ?? 1) == 0,
              "disabled control has no hover decoration")
        control.isEnabled = true; control.mouseMoved(with: move); control.updateLayer()
        check(control.isHovered && (control.layer?.backgroundColor?.alpha ?? 0) > 0,
              "reenabled original pointer state restores decoration")
        hoverWindow.key = false; control.mouseMoved(with: move)
        check(!control.isHovered, "inactive window refuses hover")
        hoverWindow.key = true; control.mouseMoved(with: move)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: hoverWindow)
        check(!control.isHovered, "original key loss clears decoration")
        control.mouseMoved(with: move)
        control.setTrailingHidden(true)
        check(control.isHidden && control.isAccessibilityHidden(), "layout-hidden trailing control leaves AX")
        control.viewDidHide()
        check(!control.isHovered, "native hide lifecycle retires hover")
        control.isHidden = false
        hoverWindow.close()

        let field = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
        field.wantsLayer = true
        DeveloperToolbarSpring.shake(field, reduceMotion: true)
        check(field.layer?.animation(forKey: DeveloperToolbarSpring.animationKey) == nil,
              "Reduce Motion skips the offset mutation")
        check(abs(DeveloperToolbarSpring.currentOffset(field)) < 0.0001, "Reduce Motion leaves offset at rest")
        DeveloperToolbarSpring.shake(field, reduceMotion: false)
        let motion = field.layer?.animation(forKey: DeveloperToolbarSpring.animationKey) as? CASpringAnimation
        check(motion != nil, "first-edit shake applies the recovered spring")
        check(abs((motion?.toValue as? CGFloat ?? 0) - (-5)) < 0.0001, "shake offset is -5")
        check(abs((motion?.stiffness ?? 0) - omega * omega) < 0.0001, "applied shake stiffness")
        check(abs((motion?.damping ?? 0) - 2 * 0.4 * omega) < 0.0001, "applied shake damping")
        DeveloperToolbarSpring.resetToRest(field)
        let reset = field.layer?.animation(forKey: DeveloperToolbarSpring.animationKey) as? CASpringAnimation
        check(abs((reset?.toValue as? CGFloat ?? 99)) < 0.0001, "reset returns offset to 0")
        check(abs((reset?.stiffness ?? 0) - omega * omega) < 0.0001, "reset keeps the shake spring")

        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 48),
                               styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let address = NSTextField(frame: NSRect(x: 8, y: 8, width: 200, height: 22))
        address.stringValue = "https://localhost/"
        window.contentView?.addSubview(address)
        check(window.makeFirstResponder(address), "first-edit window can focus the address")
        DeveloperToolbarFirstEdit.apply(address, reduceMotion: true)
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        let selected = address.currentEditor()?.selectedRange
        check(selected?.location == 0 && selected?.length == address.stringValue.utf16.count,
              "first-edit still selects the whole address when Reduce Motion skips shake")
        check(address.layer?.animation(forKey: DeveloperToolbarSpring.animationKey) == nil,
              "first-edit Reduce Motion skips the offset mutation")
        window.close()

        print("\(checks) page-tool presentation assertions passed")
    }
}
