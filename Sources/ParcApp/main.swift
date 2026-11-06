import AppKit

@objc(ParcApplication)
final class ParcApplication: NSApplication, CefAppProtocol {
    private var approvedTermination = false
    private var handlingEvent = false
    private let inputDiagnosticsEnabled = CommandLine.arguments.contains("--parc-input-diagnostics")
    @objc func isHandlingSendEvent() -> Bool { handlingEvent }
    @objc func setHandlingSendEvent(_ value: Bool) { handlingEvent = value }

    override func accessibilityRole() -> NSAccessibility.Role? {
        PCNativeBrowserApplication.accessibilityRoleRequested()
        return super.accessibilityRole()
    }

    // This exact legacy AppKit entry still carries AXManualAccessibility and
    // AXEnhancedUserInterface. Match its inherited availability annotation.
    @available(macOS, deprecated: 10.10)
    override func accessibilitySetValue(_ value: Any?, forAttribute attribute: NSAccessibility.Attribute) {
        PCNativeBrowserApplication.accessibilitySetValue(value, forAttribute: attribute.rawValue)
        super.accessibilitySetValue(value, forAttribute: attribute)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if PCNativeBrowserApplication.handleAccessibilityObservation(
            forKeyPath: keyPath, of: object, change: change, context: context) { return }
        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }

    override func sendEvent(_ event: NSEvent) {
        let previous = handlingEvent
        handlingEvent = true
        defer { handlingEvent = previous }
        let traceMouse = inputDiagnosticsEnabled &&
            [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp].contains(event.type)
        if traceMouse {
            // Event identity only: no coordinates, keys, URLs or page content.
            NSLog("[ParcInput] phase=app-send event=%ld window=%ld type=%lu time=%.6f",
                  event.eventNumber, event.windowNumber, event.type.rawValue, event.timestamp)
        }
        // Instrumentation only. Weak captures cannot keep a page/window alive
        // through local monitors or AppKit dispatch, and perform no hit test.
        let inputSnapshot = NativeInputDiagnostics.beforeDispatch(event)
        super.sendEvent(event)
        NativeInputDiagnostics.afterDispatch(event, snapshot: inputSnapshot)
        if traceMouse {
            NSLog("[ParcInput] phase=app-return event=%ld window=%ld type=%lu time=%.6f",
                  event.eventNumber, event.windowNumber, event.type.rawValue, event.timestamp)
        }
    }

    // CEF must unwind its own run loop before shutdown. Do not enter AppKit's
    // NSTerminateLater nested loop while waiting for that same unwind.
    override func terminate(_ sender: Any?) {
        if approvedTermination {
            super.terminate(sender)
        } else {
            (delegate as? AppDelegate)?.requestApplicationTermination(sender)
        }
    }

    func finishApprovedTermination(_ sender: Any?) {
        guard !approvedTermination else { return }
        approvedTermination = true
        // Genuine browser consent, native-service drain and CefShutdown have
        // finished. Preserve AppKit's final termination/notification behavior.
        super.terminate(sender)
    }
}

MainActor.assumeIsolated {
    let application = ParcApplication.shared
    precondition(application is ParcApplication, "NSApplication was created before ParcApplication")
    application.setActivationPolicy(.regular)
    let applicationDelegate = AppDelegate()
    application.delegate = applicationDelegate
    switch applicationDelegate.prepare() {
    case .ready:
        DispatchQueue.main.async { applicationDelegate.openInitialWindow() }
        let result = PCBrowserEngine.run()
        applicationDelegate.finishShutdown()
        exit(result)
    case .exit(let code):
        exit(code)
    }
}
