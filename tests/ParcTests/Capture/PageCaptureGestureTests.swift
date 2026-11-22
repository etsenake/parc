import AppKit
import ParcTestSupport
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit

struct PageCaptureGestureTests {
    @MainActor private final class Receiver: CaptureGestureReceiver {
        var states: [NSGestureRecognizer.State] = []
        func handleCaptureGesture(_ recognizer: NSPanGestureRecognizer) {
            states.append(recognizer.state)
        }
    }

    @MainActor private final class Pan: NSPanGestureRecognizer {
        override var state: NSGestureRecognizer.State {
            get { testState }
            set { testState = newValue }
        }
        private var testState = NSGestureRecognizer.State.possible

        func deliver(_ state: NSGestureRecognizer.State) throws {
            self.state = state
            _ = NSApplication.shared.sendAction(try #require(action), to: target, from: self)
        }
    }

    @MainActor private final class Fixture {
        let receiver = Receiver()
        let pan = Pan()
        let window: NSWindow
        let view: NSView
        let defaults: UserDefaults
        var current = true
        var available = true
        var admissions = 0
        var beginnings = 0
        lazy var gesture = PageCaptureGesture(view: view, defaults: defaults, pan: pan) { [weak self] point in
            guard let self else { return nil }
            self.admissions += 1
            guard self.available, point == CGPoint(x: 50, y: 60) else { return nil }
            return .init(isCurrent: { [weak self] in self?.current == true }, begin: { [weak self] in
                self?.beginnings += 1
                return self?.receiver
            })
        }

        init() throws {
            _ = NSApplication.shared
            window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            view = try #require(window.contentView)
            defaults = try #require(TestDefaults("ParcTests.captureGesture."))
            _ = gesture
        }

        func admit(flags: NSEvent.ModifierFlags = [.command, .shift], type: NSEvent.EventType = .leftMouseDown) throws -> Bool {
            let event = try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: 50, y: 60), modifierFlags: flags,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
            return gesture.gestureRecognizer(pan, shouldAttemptToRecognizeWith: event)
        }
    }

    @MainActor @Test func theOriginalViewOwnsTheNativeRecognizer() throws {
        let fixture = try Fixture()
        #expect(fixture.view.gestureRecognizers.contains { $0 === fixture.pan })
        #expect(fixture.pan.delegate === fixture.gesture)
    }

    @MainActor @Test func aPressWithoutTheShortcutNeverChecksThePage() throws {
        let fixture = try Fixture()
        #expect(try !fixture.admit(flags: .command))
        #expect(fixture.admissions == 0)
    }

    @MainActor @Test func aSecondaryPressCannotStartTheCaptureGesture() throws {
        let fixture = try Fixture()
        #expect(try !fixture.admit(type: .rightMouseDown))
        #expect(fixture.admissions == 0)
    }

    @MainActor @Test func disablingTheGestureSkipsPageAdmission() throws {
        let fixture = try Fixture()
        CaptureGesturePreference.setEnabled(false, defaults: fixture.defaults)
        #expect(try !fixture.admit())
        #expect(fixture.admissions == 0)
    }

    @MainActor @Test func anUnavailablePageKeepsOrdinaryInput() throws {
        let fixture = try Fixture()
        fixture.available = false
        #expect(try !fixture.admit())
    }

    @MainActor @Test func admissionWithAnExtraModifierDoesNotStartCaptureYet() throws {
        let fixture = try Fixture()
        #expect(try fixture.admit(flags: [.command, .shift, .option]))
        #expect(fixture.beginnings == 0)
    }

    @MainActor @Test func aStalePageCannotBeginTheGesture() throws {
        let fixture = try Fixture()
        try #require(try fixture.admit())
        fixture.current = false
        #expect(!fixture.gesture.gestureRecognizerShouldBegin(fixture.pan))
    }

    @MainActor @Test func aDelayedBeginDoesNotResurrectAStalePage() throws {
        let fixture = try Fixture()
        try #require(try fixture.admit())
        fixture.current = false
        try fixture.pan.deliver(.began)
        #expect(fixture.beginnings == 0)
    }

    @MainActor @Test func changingThePreferenceCancelsPendingRecognition() throws {
        let fixture = try Fixture()
        try #require(try fixture.admit())
        CaptureGesturePreference.setEnabled(false, defaults: fixture.defaults)
        #expect(!fixture.gesture.gestureRecognizerShouldBegin(fixture.pan))
    }

    @MainActor @Test func aCurrentNativeStreamCanBegin() throws {
        let fixture = try Fixture()
        try #require(try fixture.admit())
        #expect(fixture.gesture.gestureRecognizerShouldBegin(fixture.pan))
    }

    @MainActor @Test(arguments: [NSGestureRecognizer.State.ended, .cancelled, .failed])
    func aTerminalEventRetiresTheDragReceiver(_ terminal: NSGestureRecognizer.State) throws {
        let fixture = try Fixture()
        try #require(try fixture.admit())
        try fixture.pan.deliver(.began)
        try fixture.pan.deliver(.changed)
        try fixture.pan.deliver(terminal)
        try fixture.pan.deliver(.changed)
        #expect(fixture.receiver.states == [.began, .changed, terminal])
    }
}
