import AppKit
import Testing
@testable import ParcNotes

@MainActor
struct NoteZoneCursorTests {
    private final class KeyedWindow: NSWindow {
        var pointer = NSPoint(x: -1000, y: -1000)
        override var isKeyWindow: Bool { true }
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    }

    private final class Owner: NSView {
        let zone = NoteZoneCursor()
        let hot = NSRect(x: 0, y: 0, width: 40, height: 100)
        var updates = 0

        private func cursor(for event: NSEvent) -> NSCursor? {
            hot.contains(convert(event.locationInWindow, from: nil)) ? .pointingHand : nil
        }

        override func cursorUpdate(with event: NSEvent) {
            updates += 1
            _ = zone.cursorUpdate(cursor(for: event), in: self, event: event)
        }

        override func mouseMoved(with event: NSEvent) {
            zone.moved(cursor(for: event), in: self, event: event)
        }
    }

    @MainActor private struct Fixture {
        let window = KeyedWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        let owner = Owner(frame: NSRect(x: 0, y: 0, width: 200, height: 100))

        init() {
            _ = NSApplication.shared
            window.isReleasedWhenClosed = false
            window.contentView = owner
        }

        func windowPoint(x: CGFloat) -> NSPoint { owner.convert(NSPoint(x: x, y: 50), to: nil) }

        func cursorUpdate(x: CGFloat) {
            window.pointer = windowPoint(x: x)
            let event = NSEvent.enterExitEvent(with: .cursorUpdate, location: window.pointer, modifierFlags: [], timestamp: 0,
                                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            owner.cursorUpdate(with: event)
        }

        func move(x: CGFloat) {
            window.pointer = windowPoint(x: x)
            let event = NSEvent.mouseEvent(with: .mouseMoved, location: window.pointer, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            owner.mouseMoved(with: event)
        }
    }

    @Test func leavingTheZoneRefreshesTheCursorOnceWithoutOverlappingAccess() {
        let fixture = Fixture()
        fixture.cursorUpdate(x: 20)
        #expect(fixture.owner.updates == 1)
        fixture.move(x: 120)
        #expect(fixture.owner.updates == 2)
        fixture.move(x: 140)
        #expect(fixture.owner.updates == 2)
    }
}
