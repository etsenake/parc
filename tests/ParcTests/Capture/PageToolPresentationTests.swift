import AppKit
import Testing
@testable import Parc

struct PageToolPresentationTests {
    @MainActor private final class KeyWindow: NSWindow {
        var key = true
        var pointer = NSPoint.zero
        override var isKeyWindow: Bool { key }
        override var canBecomeKey: Bool { true }
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    }

    @MainActor private struct HoverFixture {
        let window: KeyWindow
        let control = DeveloperToolbarButton(symbol: "link", title: "Copy Link")

        init() {
            _ = NSApplication.shared
            window = KeyWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 100),
                               styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            control.frame = CGRect(x: 20, y: 20, width: 28, height: 28)
            window.contentView?.addSubview(control)
            control.updateTrackingAreas()
        }

        func movePointerInside() throws {
            window.pointer = CGPoint(x: 34, y: 34)
            let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
            control.mouseMoved(with: event)
        }

        func setPressed(_ pressed: Bool) {
            (control.cell as? NSButtonCell)?.highlight(pressed, withFrame: control.bounds, in: control)
        }
    }

    @Test(arguments: [(true, false, true, true), (false, false, true, false), (true, true, true, false), (true, false, false, false)])
    func zoomRequiresAReadyOpenWindowAndAnOriginalPage(_ ready: Bool, _ closing: Bool, _ original: Bool, _ allowed: Bool) {
        #expect(PageZoomAvailability.canChange(windowReady: ready, closing: closing, hasOriginalPage: original) == allowed)
    }

    @MainActor @Test func hoverTrackingUsesTheVisibleRectInTheKeyWindow() {
        let control = DeveloperToolbarButton(symbol: "link", title: "Copy Link")
        control.updateTrackingAreas()
        let areas = control.trackingAreas.filter { !$0.options.contains(.cursorUpdate) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect]
        #expect(areas.count == 1 && areas.first?.options == options)
    }

    @MainActor @Test func theToolbarControlNamesItsActionForAccessibility() {
        let control = DeveloperToolbarButton(symbol: "link", title: "Copy Link")
        #expect(control.accessibilityRole() == .button && control.accessibilityLabel() == "Copy Link")
    }

    @MainActor @Test func focusUsesAnExteriorRingOnTheControlBounds() {
        let control = HoverFixture().control
        #expect(control.focusRingType == .exterior && control.focusRingMaskBounds == control.bounds)
    }

    @MainActor @Test(arguments: [(false, 0.071), (true, 0.077)])
    func hoveringTheToolbarButtonUsesItsAppearanceColor(_ dark: Bool, _ alpha: Double) throws {
        let fixture = HoverFixture()
        fixture.control.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        try fixture.movePointerInside()
        fixture.control.updateLayer()
        #expect(fixture.control.isHovered)
        #expect(abs(Double(fixture.control.layer?.backgroundColor?.alpha ?? 0) - alpha) < 0.00001)
        #expect(fixture.control.layer?.cornerRadius == 5 && fixture.control.layer?.cornerCurve == .continuous)
    }

    @MainActor @Test(arguments: [(false, 0.090), (true, 0.103)])
    func aNativePressUsesItsAppearanceColor(_ dark: Bool, _ alpha: Double) {
        let fixture = HoverFixture()
        fixture.control.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        fixture.setPressed(true)
        fixture.control.updateLayer()
        #expect(fixture.control.isPressed)
        #expect(abs(Double(fixture.control.layer?.backgroundColor?.alpha ?? 0) - alpha) < 0.00001)
    }

    @MainActor @Test func releasingTheNativeCellClearsPress() {
        let fixture = HoverFixture()
        fixture.setPressed(true)
        fixture.setPressed(false)
        #expect(!fixture.control.isPressed)
    }

    @MainActor @Test func disablingTheControlClearsHoverFill() throws {
        let fixture = HoverFixture()
        try fixture.movePointerInside()
        fixture.control.isEnabled = false
        fixture.control.updateLayer()
        #expect(!fixture.control.isHovered && fixture.control.layer?.backgroundColor?.alpha == 0)
    }

    @MainActor @Test func aBackgroundWindowDoesNotTakeHover() throws {
        let fixture = HoverFixture()
        fixture.window.key = false
        try fixture.movePointerInside()
        #expect(!fixture.control.isHovered)
    }

    @MainActor @Test func losingTheKeyWindowClearsHover() throws {
        let fixture = HoverFixture()
        try fixture.movePointerInside()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        #expect(!fixture.control.isHovered)
    }

    @MainActor @Test func aTrailingControlHiddenByLayoutLeavesAccessibility() {
        let control = DeveloperToolbarButton(symbol: "link", title: "Copy Link")
        control.setTrailingHidden(true)
        #expect(control.isHidden && control.isAccessibilityHidden())
    }

    @MainActor @Test func hidingTheControlClearsHover() throws {
        let fixture = HoverFixture()
        try fixture.movePointerInside()
        fixture.control.isHidden = true
        #expect(!fixture.control.isHovered)
    }

    @MainActor @Test func reduceMotionKeepsTheToolbarAtRest() {
        let field = NSView()
        DeveloperToolbarSpring.shake(field, reduceMotion: true)
        #expect(DeveloperToolbarSpring.currentOffset(field) == 0)
        #expect(field.layer?.animation(forKey: DeveloperToolbarSpring.animationKey) == nil)
    }

    @MainActor @Test func aFirstEditShakesTheFieldWithItsSpring() throws {
        let field = NSView(frame: CGRect(x: 0, y: 0, width: 120, height: 28))
        DeveloperToolbarSpring.shake(field, reduceMotion: false)
        let spring = try #require(field.layer?.animation(forKey: DeveloperToolbarSpring.animationKey) as? CASpringAnimation)
        let omega = 2 * Double.pi / 0.3
        #expect(spring.toValue as? CGFloat == -5 && spring.mass == 1)
        #expect(abs(spring.stiffness - omega * omega) < 0.0001)
        #expect(abs(spring.damping - 2 * 0.4 * omega) < 0.0001)
    }

    @MainActor @Test func resettingTheShakeReturnsTheOffsetToZero() throws {
        let field = NSView(frame: CGRect(x: 0, y: 0, width: 120, height: 28))
        DeveloperToolbarSpring.shake(field, reduceMotion: false)
        DeveloperToolbarSpring.resetToRest(field)
        let spring = try #require(field.layer?.animation(forKey: DeveloperToolbarSpring.animationKey) as? CASpringAnimation)
        #expect(spring.toValue as? CGFloat == 0)
    }

    @MainActor @Test func firstEditStillSelectsTheAddressWithReducedMotion() async throws {
        let fixture = HoverFixture()
        let address = NSTextField(frame: CGRect(x: 8, y: 60, width: 200, height: 22))
        address.stringValue = "https://localhost/"
        fixture.window.contentView?.addSubview(address)
        try #require(fixture.window.makeFirstResponder(address))
        let editor = try #require(address.currentEditor())
        editor.selectedRange = NSRange(location: 2, length: 0)
        DeveloperToolbarFirstEdit.apply(address, reduceMotion: true)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(editor.selectedRange == NSRange(location: 0, length: address.stringValue.utf16.count))
        #expect(address.layer?.animation(forKey: DeveloperToolbarSpring.animationKey) == nil)
    }
}
