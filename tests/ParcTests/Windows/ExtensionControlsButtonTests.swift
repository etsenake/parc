import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct ExtensionControlsButtonTests {
    @MainActor private final class ControlWindow: NSWindow {
        var key = true
        override var isKeyWindow: Bool { key }
        init() {
            super.init(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
            isReleasedWhenClosed = false
        }
    }

    private final class SeeThroughView: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }

    @MainActor private final class Hosted {
        let window = ControlWindow()
        let button: ExtensionActionButton

        init(style: ExtensionControlStyle = .sidebar) {
            button = ExtensionActionButton(item: ExtensionControlsSupport.controlItem("a"), style: style)
            button.appearance = NSAppearance(named: .aqua)
            window.contentView?.addSubview(button)
            button.frame = NSRect(origin: .zero, size: style.surfaceSize)
        }

        func install(execute: @escaping (NSView?) -> Void = { _ in }, context: @escaping (NSView) -> Void = { _ in }) {
            button.update(ExtensionControlsSupport.controlItem("a", execute: execute, context: context))
        }

        func hoverAlpha() -> CGFloat { NSColor(cgColor: button.layer!.backgroundColor!)?.alphaComponent ?? 0 }

        func event(_ type: NSEvent.EventType) -> NSEvent {
            let centre = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            return NSEvent.enterExitEvent(with: type, location: centre, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }

        func moveEvent() -> NSEvent {
            let centre = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            return NSEvent.mouseEvent(with: .mouseMoved, location: centre, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        }
    }

    @Test func theDisabledActionFallbackStaysEnabled() {
        let hosted = Hosted()
        #expect(hosted.button.isEnabled)
    }

    @Test func theTooltipReachesTheControlAsAParcTooltip() {
        let hosted = Hosted()
        #expect(hosted.button.parcTooltip?.label == "Title a")
        #expect(hosted.button.toolTip == nil)
    }

    @Test func accessibilityUsesTheActionLabel() {
        #expect(Hosted().button.accessibilityLabel() == "Accessible a")
    }

    @Test func activationDispatchesOnce() {
        let hosted = Hosted()
        var dispatches = 0
        hosted.install(execute: { _ in dispatches += 1 })
        hosted.button.sendClick()
        #expect(dispatches == 1)
    }

    @Test func aCallbackThatInvalidatesTheButtonStillCompletes() {
        let hosted = Hosted()
        var dispatches = 0
        hosted.install(execute: { _ in hosted.button.invalidate(); dispatches += 1 })
        hosted.button.sendClick()
        #expect(dispatches == 1)
    }

    @Test func anInvalidatedButtonCannotDispatchAgain() {
        let hosted = Hosted()
        var dispatches = 0
        hosted.install(execute: { _ in hosted.button.invalidate(); dispatches += 1 })
        hosted.button.sendClick()
        hosted.button.sendClick()
        #expect(dispatches == 1)
    }

    @Test func accessibilityShowMenuReachesTheOriginalContextAction() {
        let hosted = Hosted()
        var menus = 0
        hosted.install(context: { control in menus += control === hosted.button ? 1 : 100 })
        #expect(hosted.button.accessibilityPerformShowMenu())
        #expect(menus == 1)
    }

    @Test func accessibilityPressReachesTheOriginalAction() {
        let hosted = Hosted()
        var dispatches = 0
        hosted.install(execute: { control in dispatches += control === hosted.button ? 1 : 100 })
        #expect(hosted.button.accessibilityPerformPress())
        #expect(dispatches == 1)
    }

    @Test func aHiddenButtonIsUnavailableToAccessibility() {
        let hosted = Hosted()
        hosted.install()
        hosted.button.isHidden = true
        #expect(!hosted.button.isAccessibilityEnabled())
    }

    @Test func accessibilityPressCannotActivateAHiddenButton() {
        let hosted = Hosted()
        var dispatches = 0
        hosted.install(execute: { _ in dispatches += 1 })
        hosted.button.isHidden = true
        #expect(!hosted.button.accessibilityPerformPress())
        #expect(dispatches == 0)
    }

    @Test func accessibilityShowMenuCannotOpenAHiddenButtonsMenu() {
        let hosted = Hosted()
        var menus = 0
        hosted.install(context: { _ in menus += 1 })
        hosted.button.isHidden = true
        #expect(!hosted.button.accessibilityPerformShowMenu())
        #expect(menus == 0)
    }

    @Test func clickingAHiddenButtonCannotActivateIt() {
        let hosted = Hosted()
        var dispatches = 0
        hosted.install(execute: { _ in dispatches += 1 })
        hosted.button.isHidden = true
        hosted.button.sendClick()
        #expect(dispatches == 0)
    }

    @Test func accessibilityPressCannotActivateADisabledButton() {
        let hosted = Hosted()
        hosted.install()
        hosted.button.isEnabled = false
        #expect(!hosted.button.accessibilityPerformPress())
    }

    @Test func accessibilityShowMenuCannotOpenADisabledButtonsMenu() {
        let hosted = Hosted()
        hosted.install()
        hosted.button.isEnabled = false
        #expect(!hosted.button.accessibilityPerformShowMenu())
    }

    @Test func aDetachedButtonCannotDispatch() {
        let hosted = Hosted()
        var dispatches = 0
        hosted.install(execute: { _ in dispatches += 1 })
        hosted.button.removeFromSuperview()
        #expect(!hosted.button.accessibilityPerformPress())
        #expect(!hosted.button.isAccessibilityEnabled())
        #expect(dispatches == 0)
    }

    @Test func theFocusMaskFollowsThePinSurface() {
        let hosted = Hosted()
        #expect(hosted.button.focusRingMaskBounds == hosted.button.bounds)
    }

    @Test func cellTrackingDrivesTheSidebarPressTransform() {
        let hosted = Hosted()
        hosted.button.appearance = NSAppearance(named: .aqua)
        hosted.button.cell!.highlight(true, withFrame: hosted.button.bounds, in: hosted.button)
        #expect(abs((hosted.button.layer?.transform.m11 ?? 0) - 0.95) < 0.00001)
    }

    @Test func cellTrackingDrivesThePressedFill() {
        let hosted = Hosted()
        hosted.button.appearance = NSAppearance(named: .aqua)
        hosted.button.cell!.highlight(true, withFrame: hosted.button.bounds, in: hosted.button)
        #expect(abs(hosted.hoverAlpha() - 0.09) < 0.00001)
    }

    @Test func releasingTheCellRestoresTheTransformAndClearsTheFill() {
        let hosted = Hosted()
        hosted.button.appearance = NSAppearance(named: .aqua)
        hosted.button.cell!.highlight(true, withFrame: hosted.button.bounds, in: hosted.button)
        hosted.button.cell!.highlight(false, withFrame: hosted.button.bounds, in: hosted.button)
        #expect(CATransform3DIsIdentity(hosted.button.layer!.transform))
        #expect(hosted.hoverAlpha() == 0)
    }

    @Test func losingKeyStatusCancelsTheNativePress() {
        let hosted = Hosted()
        hosted.button.cell!.highlight(true, withFrame: hosted.button.bounds, in: hosted.button)
        hosted.window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: hosted.window)
        #expect(CATransform3DIsIdentity(hosted.button.layer!.transform))
        #expect(hosted.button.layer?.animation(forKey: "extensionPress") == nil)
    }

    @Test func aCommandSurfaceCoveringThePinKeepsTheHoverFillOff() {
        let hosted = Hosted()
        let cover = NSView(frame: hosted.button.frame.insetBy(dx: -4, dy: -4))
        hosted.window.contentView?.addSubview(cover)
        hosted.button.mouseEntered(with: hosted.event(.mouseEntered))
        #expect(hosted.hoverAlpha() == 0)
    }

    @Test func movingOutFromUnderTheCoverRestoresTheHoverFill() {
        let hosted = Hosted()
        let cover = NSView(frame: hosted.button.frame.insetBy(dx: -4, dy: -4))
        hosted.window.contentView?.addSubview(cover)
        hosted.button.mouseEntered(with: hosted.event(.mouseEntered))
        cover.removeFromSuperview()
        hosted.button.mouseMoved(with: hosted.moveEvent())
        #expect(abs(hosted.hoverAlpha() - 0.071) < 0.00001)
    }

    @Test func aSeeThroughOverlayLeavesTheHoverFillAlone() {
        let hosted = Hosted()
        hosted.window.contentView?.addSubview(SeeThroughView(frame: hosted.button.frame.insetBy(dx: -4, dy: -4)))
        hosted.button.mouseEntered(with: hosted.event(.mouseEntered))
        #expect(abs(hosted.hoverAlpha() - 0.071) < 0.00001)
    }

    @Test func theToolbarCellDoesNotAcquireTheSidebarPressSpring() {
        let hosted = Hosted(style: .toolbar)
        hosted.button.cell!.highlight(true, withFrame: hosted.button.bounds, in: hosted.button)
        #expect(CATransform3DIsIdentity(hosted.button.layer!.transform))
        #expect(hosted.button.layer?.animation(forKey: "extensionPress") == nil)
        #expect(hosted.hoverAlpha() == 0)
    }

    @Test func appKitAddsNoPressedImageEffect() {
        #expect((Hosted(style: .toolbar).button.cell as? NSButtonCell)?.highlightsBy.isEmpty == true)
    }

    struct PressFillCase: Sendable, CustomTestStringConvertible {
        let style: ExtensionControlStyle
        let expected: Double
        var testDescription: String { "\(style) dark press fill" }

        static let all = [Self(style: .toolbar, expected: 0.13), Self(style: .sidebar, expected: 0.103)]
    }

    @Test(arguments: PressFillCase.all)
    func aLitPinUsesItsStylesDarkPressFill(_ sample: PressFillCase) {
        let style = sample.style
        let expected = sample.expected
        let hosted = Hosted(style: style)
        hosted.button.appearance = NSAppearance(named: .darkAqua)
        hosted.button.activityFill = 1
        #expect(abs(hosted.hoverAlpha() - expected) < 0.00001)
    }
}
