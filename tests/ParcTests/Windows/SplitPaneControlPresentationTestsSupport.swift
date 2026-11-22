import AppKit
import QuartzCore
import Testing
@testable import Parc

enum SplitPaneControlPresentationTestsSupport {
    @MainActor final class ControlWindow: NSWindow {
        var key = true
        var pointer = NSPoint(x: -100, y: -100)
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
        override var isKeyWindow: Bool { key }
    }

    final class FlippedControlHost: NSView { override var isFlipped: Bool { true } }

    final class TrackingEvent: NSEvent {
        var area: NSTrackingArea?
        var location = NSPoint.zero
        var eventWindow: NSWindow?
        override var trackingArea: NSTrackingArea? { area }
        override var locationInWindow: NSPoint { location }
        override var window: NSWindow? { eventWindow }
    }

    final class SeeThroughView: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }

    @MainActor final class ControlFixture {
        let window: ControlWindow
        let host: NSView
        let control: SplitPaneControl
        let background: CALayer
        let glyph: NSImageView
        var actions = 0

        init(kind: SplitPaneControl.Kind = .menu, frame: NSRect = NSRect(x: 20, y: 20, width: 32, height: 24),
             reduceMotion: Bool = false) {
            _ = NSApplication.shared
            window = ControlWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            host = NSView(frame: window.contentView!.bounds)
            window.contentView = host
            control = SplitPaneControl(kind, reduceMotion: { reduceMotion })
            control.frame = frame
            host.addSubview(control)
            control.layoutSubtreeIfNeeded()
            control.updateTrackingAreas()
            background = control.layer!.sublayers!.first!
            glyph = control.subviews.compactMap { $0 as? NSImageView }.first!
            control.actionBlock = { [weak self] in self?.actions += 1 }
            control.appearance = NSAppearance(named: .aqua)
            control.viewDidChangeEffectiveAppearance()
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        var ownedAreas: [NSTrackingArea] {
            control.trackingAreas.filter { $0.owner === control && $0.options == [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeInKeyWindow] }
        }

        var hoverEvent: TrackingEvent {
            let event = TrackingEvent()
            event.area = ownedAreas[0]
            return event
        }

        func setDark(_ dark: Bool) {
            control.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            control.viewDidChangeEffectiveAppearance()
        }

        func press(_ pressed: Bool) { control.cell!.highlight(pressed, withFrame: control.bounds, in: control) }
    }
}
