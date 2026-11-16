import AppKit

@MainActor final class PageCaptureController {
    var received: [NSGestureRecognizer.State] = []
    func handleCaptureGesture(_ recognizer: NSPanGestureRecognizer) { received.append(recognizer.state) }
}
@MainActor private final class TestPan: NSPanGestureRecognizer {
    private var simulatedState = NSGestureRecognizer.State.possible
    override var state: NSGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }
    func deliver(_ state: NSGestureRecognizer.State) {
        self.state = state
        _ = NSApp.sendAction(action!, to: target, from: self)
    }
}

@main @MainActor struct PageCaptureGestureChecks {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let domain = "Parc.CAP17." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: .titled, backing: .buffered, defer: false)
        let view = window.contentView!, pan = TestPan()
        var current = true, allowed = true, admissions = 0, beginnings = 0
        let capture = PageCaptureController()
        let gesture = PageCaptureGesture(view: view, defaults: defaults, pan: pan) { point in
            admissions += 1
            guard allowed, point == NSPoint(x: 50, y: 60) else { return nil }
            return .init(isCurrent: { current }, begin: { beginnings += 1; return capture })
        }
        var assertions = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            assertions += 1; precondition(value(), message)
        }
        func event(_ flags: NSEvent.ModifierFlags, type: NSEvent.EventType = .leftMouseDown,
                   windowNumber: Int? = nil) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: 50, y: 60), modifierFlags: flags,
                timestamp: 0, windowNumber: windowNumber ?? window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        func admit(_ flags: NSEvent.ModifierFlags = [.command, .shift]) -> Bool {
            gesture.gestureRecognizer(pan, shouldAttemptToRecognizeWith: event(flags))
        }
        expect(view.gestureRecognizers.contains { $0 === pan } && pan.delegate === gesture, "Original host owns one native recognizer")
        expect(!admit(.command) && admissions == 0, "Ordinary page input never asks to capture")
        expect(!gesture.gestureRecognizer(pan, shouldAttemptToRecognizeWith: event([.command, .shift], type: .rightMouseDown)),
               "Only the primary pointer starts a capture pan")
        CaptureGesturePreference.setEnabled(false, defaults: defaults)
        expect(!admit() && admissions == 0, "Disabled gesture never consults the page owner")
        CaptureGesturePreference.setEnabled(true, defaults: defaults)
        allowed = false; expect(!admit() && beginnings == 0, "Unavailable page preserves native input")
        allowed = true; expect(admit([.command, .shift, .option]) && beginnings == 0, "Admission retains the original without starting capture")
        current = false
        expect(!gesture.gestureRecognizerShouldBegin(pan), "Changed document or selection cannot begin the retained admission")
        pan.deliver(.began)
        expect(beginnings == 0 && capture.received.isEmpty, "Delayed began cannot resurrect a stale owner")
        current = true; expect(admit(), "Fresh pointer stream admits its current page")
        CaptureGesturePreference.setEnabled(false, defaults: defaults)
        expect(!gesture.gestureRecognizerShouldBegin(pan), "Preference changed before began cancels pending recognition")
        CaptureGesturePreference.setEnabled(true, defaults: defaults)
        expect(admit() && gesture.gestureRecognizerShouldBegin(pan), "Current native stream can begin")
        pan.deliver(.began); pan.deliver(.changed); pan.deliver(.ended); pan.deliver(.changed)
        expect(beginnings == 1 && capture.received == [.began, .changed, .ended],
               "One actual session owns drag progression and no event survives its end")
        expect(admit(), "Next native stream is independent")
        pan.deliver(.began); pan.deliver(.cancelled); pan.deliver(.changed)
        expect(beginnings == 2 && capture.received.suffix(2) == [.began, .cancelled], "Cancellation retires gesture forwarding")
        print("PASS: \(assertions) capture gesture admission/lifetime assertions")
    }
}
