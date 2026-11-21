import AppKit
import Testing
@testable import Parc

struct PointerSelectionTests {
    @MainActor private final class Window: NSWindow {
        var key = true
        override var isKeyWindow: Bool { key }

        init() {
            _ = NSApplication.shared
            super.init(contentRect: NSRect(x: 0, y: 0, width: 500, height: 200), styleMask: .borderless,
                       backing: .buffered, defer: false)
            isReleasedWhenClosed = false
        }
    }

    @MainActor private final class Fixture {
        let window = Window()
        let row = CommandResultRowView(frame: NSRect(x: 0, y: 0, width: 500, height: 50))
        let cell = CommandResultCell(title: "Example", detail: "", accessory: "", isTab: false, icon: nil, enabled: true)
        var pressed: [NSEvent.ModifierFlags] = []
        var deletions = 0

        init() {
            cell.frame = row.bounds
            row.addSubview(cell)
            window.contentView?.addSubview(row)
            cell.onDelete = { [weak self] in self?.deletions += 1; return true }
            row.onPress = { [weak self] event in self?.pressed.append(event.modifierFlags); return true }
            row.updateTrackingAreas()
            row.layoutSubtreeIfNeeded()
        }

        var point: NSPoint { row.convert(NSPoint(x: 60, y: 25), to: nil) }

        func event(_ type: NSEvent.EventType, point: NSPoint? = nil, flags: NSEvent.ModifierFlags = [], owner: NSWindow? = nil) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point ?? self.point, modifierFlags: flags, timestamp: 0,
                windowNumber: (owner ?? window).windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
    }

    @Test @MainActor func pointerMovementHighlightsAndRevealsDeletionWithoutSelecting() throws {
        let fixture = Fixture()
        let event = try fixture.event(.mouseMoved)
        fixture.row.mouseMoved(with: event)
        let accessory = try #require(fixture.cell.subviews.compactMap { $0 as? NSButton }.first)
        #expect(fixture.row.isHovered)
        #expect(!accessory.isHidden)
        #expect(!fixture.row.isSelected)
        #expect(fixture.pressed.isEmpty)
    }

    @Test @MainActor func enteringDoesNotHighlightBeforeThePointerMoves() throws {
        let fixture = Fixture()
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: fixture.point, modifierFlags: [],
            timestamp: 0, windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        fixture.row.mouseEntered(with: event)
        #expect(!fixture.row.isHovered)
    }

    @Test @MainActor func aRowPressPreservesOriginalModifiersAndFieldFocus() throws {
        let fixture = Fixture()
        let field = NSTextField(frame: NSRect(x: 0, y: 100, width: 500, height: 30))
        field.stringValue = "space waves"
        fixture.window.contentView?.addSubview(field)
        try #require(fixture.window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        let selection = NSRange(location: 5, length: 6)
        editor.setSelectedRange(selection)
        fixture.row.mouseDown(with: try fixture.event(.leftMouseDown, flags: [.command, .option]))
        #expect(fixture.pressed == [[.command, .option]])
        #expect(fixture.window.firstResponder === editor)
        #expect(editor.selectedRange() == selection)
    }

    @Test @MainActor func deletingDoesNotActivateTheRow() throws {
        let fixture = Fixture()
        fixture.row.mouseMoved(with: try fixture.event(.mouseMoved))
        let accessory = try #require(fixture.cell.subviews.compactMap { $0 as? NSButton }.first)
        let point = accessory.convert(NSPoint(x: 10, y: 10), to: fixture.row.superview)
        let hit = fixture.row.hitTest(point)
        #expect(hit === accessory || hit?.isDescendant(of: accessory) == true)
        accessory.performClick(nil)
        #expect(fixture.deletions == 1)
        #expect(fixture.pressed.isEmpty)
    }

    enum Loss: CaseIterable { case outside, tracking, resign, detach, reuse }

    @Test(arguments: Loss.allCases)
    @MainActor func leavingTheOriginalHoverContextClearsItsHighlight(reason: Loss) throws {
        let fixture = Fixture()
        fixture.row.mouseMoved(with: try fixture.event(.mouseMoved))
        try #require(fixture.row.isHovered)
        switch reason {
        case .outside:
            fixture.row.mouseMoved(with: try fixture.event(.mouseMoved, point: NSPoint(x: -200, y: -200)))
        case .tracking:
            fixture.row.updateTrackingAreas()
        case .resign:
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        case .detach:
            fixture.row.removeFromSuperview()
        case .reuse:
            fixture.row.prepareForReuse()
        }
        #expect(!fixture.row.isHovered)
    }

    enum Refusal: CaseIterable { case nonKey, hidden, otherWindow, reused }

    @Test(arguments: Refusal.allCases)
    @MainActor func aRowCannotDispatchAfterItLosesOwnership(reason: Refusal) throws {
        let fixture = Fixture()
        let other = Window()
        switch reason {
        case .nonKey: fixture.window.key = false
        case .hidden: fixture.row.isHidden = true
        case .otherWindow: break
        case .reused: fixture.row.prepareForReuse()
        }
        let event = try fixture.event(.leftMouseDown, owner: reason == .otherWindow ? other : nil)
        fixture.row.mouseDown(with: event)
        #expect(fixture.pressed.isEmpty)
    }
}
