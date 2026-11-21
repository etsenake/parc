import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarPointingHandTests {
    private func event() -> NSEvent {
        NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                               eventNumber: 0, trackingNumber: 0, userData: nil)!
    }

    @MainActor private final class Cursors {
        var set: [NSCursor] = []
    }

    private func cursors(for control: NSView) -> [NSCursor] {
        let cursors = Cursors()
        let record: (NSCursor) -> Void = { cursors.set.append($0) }
        if let button = control as? PointingHandButton { button.setCursor = record }
        if let header = control as? SidebarPinnedHeaderView { header.setCursor = record }
        control.cursorUpdate(with: event())
        return cursors.set
    }

    private func isPointingHand(_ cursors: [NSCursor]) -> Bool { cursors.contains { $0 === NSCursor.pointingHand } }

    @Test func anEnabledSidebarActionButtonShowsThePointingHand() {
        let button = ActionButton()
        button.isEnabled = true
        #expect(isPointingHand(cursors(for: button)))
    }

    @Test func aDisabledSidebarActionButtonDoesNotShowThePointingHand() {
        let button = ActionButton()
        button.isEnabled = false
        #expect(!isPointingHand(cursors(for: button)))
    }

    @Test func anEnabledRowActionButtonShowsThePointingHand() {
        let button = SidebarRowActionButton("Archive Tab")
        button.isEnabled = true
        #expect(isPointingHand(cursors(for: button)))
    }

    @Test func aDisabledRowActionButtonDoesNotShowThePointingHand() {
        let button = SidebarRowActionButton("Archive Tab")
        button.isEnabled = false
        #expect(!isPointingHand(cursors(for: button)))
    }

    @Test func anEnabledResetRegionShowsThePointingHand() {
        let region = SidebarRowResetRegion()
        region.isEnabled = true
        #expect(isPointingHand(cursors(for: region)))
    }

    @Test func aDisabledResetRegionDoesNotShowThePointingHand() {
        let region = SidebarRowResetRegion()
        region.isEnabled = false
        #expect(!isPointingHand(cursors(for: region)))
    }

    @Test func theSpaceHeadersEditButtonShowsThePointingHand() {
        #expect(isPointingHand(cursors(for: SidebarSpaceHeaderEditButton())))
    }

    @Test func aFoldablePinnedHeaderShowsThePointingHand() {
        let header = SidebarPinnedHeaderView(frame: NSRect(x: 0, y: 0, width: 212, height: SidebarPinnedHeaderLayout.height))
        #expect(isPointingHand(cursors(for: header)))
    }

    @Test func anEmptyCardsPinnedLabelDoesNotShowThePointingHand() {
        let header = SidebarPinnedHeaderView(frame: NSRect(x: 0, y: 0, width: 212, height: SidebarPinnedHeaderLayout.height))
        header.update(.init(placeholder: true), fallbacks: [:], animated: false)
        #expect(!isPointingHand(cursors(for: header)))
    }

    @Test func everySidebarControlAsksForCursorUpdatesOverItself() {
        let controls: [NSView] = [ActionButton(), SidebarRowActionButton("Close"), SidebarRowResetRegion(), SidebarSpaceHeaderEditButton()]
        #expect(controls.allSatisfy { control in control.trackingAreas.contains { $0.options.contains(.cursorUpdate) && $0.owner === control } })
    }
}
