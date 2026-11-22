import AppKit
import Testing
@testable import Parc
@testable import ParcOnboarding

struct PasswordHelpPanelTests {
    enum Host: CaseIterable { case setup, menu }

    @MainActor
    private final class OffscreenKeyWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var canBecomeKey: Bool { true }
    }

    @MainActor
    private final class Fixture {
        let window: NSWindow
        let root: NSView
        let covered: [NSView]
        let help: OnboardingPasswordHelp

        init(host: Host) {
            _ = NSApplication.shared
            let frame = CGRect(x: 0, y: 0, width: 1080, height: 760)
            window = OffscreenKeyWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            root = NSView(frame: frame)
            window.contentView = root
            let controls = (0..<(host == .setup ? 1 : 2)).map { _ in NSButton(frame: frame) }
            for control in controls { root.addSubview(control) }
            covered = controls
            help = OnboardingPasswordHelp.install(in: root) {
                OnboardingPasswordHelp.cover(controls, hidden: false)
            }
            OnboardingPasswordHelp.cover(root.subviews, hidden: true, except: help)
            help.present(animated: false)
            root.layoutSubtreeIfNeeded()
        }
    }

    @MainActor @Test(arguments: Host.allCases)
    func passwordHelpSitsInTheHostAboveTheExistingControls(_ host: Host) throws {
        let fixture = Fixture(host: host)

        #expect(fixture.help.isPresented)
        #expect(fixture.root.subviews.last === fixture.help)
        #expect(fixture.help.bounds.size == fixture.root.bounds.size)
        #expect(fixture.help.window === fixture.window)
        #expect(fixture.window.attachedSheet == nil)
        let hit = try #require(fixture.root.hitTest(CGPoint(x: 40, y: 40)))
        #expect(hit === fixture.help || hit.isDescendant(of: fixture.help))
    }

    @MainActor @Test(arguments: Host.allCases)
    func presentingHelpHidesCoveredControlsFromAccessibilityUntilDismissal(_ host: Host) {
        let fixture = Fixture(host: host)

        #expect(fixture.covered.allSatisfy { $0.isAccessibilityHidden() })
        #expect(!fixture.help.isAccessibilityHidden())
        fixture.help.dismiss(animated: false)
        #expect(fixture.covered.allSatisfy { !$0.isAccessibilityHidden() })
    }

    @MainActor @Test(arguments: Host.allCases)
    func escapeDismissesThePasswordHelp(_ host: Host) throws {
        let fixture = Fixture(host: host)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: fixture.window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))

        fixture.window.sendEvent(escape)

        #expect(!fixture.help.isPresented)
    }

    @MainActor @Test(arguments: Host.allCases)
    func returnKeepsFocusInsideTheHelp(_ host: Host) throws {
        let fixture = Fixture(host: host)
        let enter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: fixture.window.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))

        fixture.window.sendEvent(enter)

        let presented = fixture.help.isPresented
        #expect(presented)
        let responder = try #require(fixture.window.firstResponder as? NSView)
        #expect(responder.isDescendant(of: fixture.help))
    }
}
