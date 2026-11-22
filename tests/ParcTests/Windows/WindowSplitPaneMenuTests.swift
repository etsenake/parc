import AppKit
import Testing
@testable import Parc

@MainActor
struct WindowSplitPaneMenuTests {
    @Test func theFirstBlankPaneHasAnAddAndMoveButNoLinksToCopy() throws {
        let fixture = try SplitResizeCommandAvailabilityTests.Fixture()
        let anchor = NSView()
        let pane = try #require(fixture.owner.panes[fixture.ids[0]])
        pane.addSubview(anchor)
        var presented: NSMenu?
        fixture.owner.presentSplitPaneMenu = { menu, view in
            #expect(view === anchor)
            presented = menu
        }

        fixture.owner.showSplitPaneMenu(fixture.ids[0], from: anchor)

        let menu = try #require(presented)
        #expect(menu.item(withTitle: "Move Left")?.isEnabled == false)
        #expect(menu.item(withTitle: "Move Right")?.isEnabled == true)
        #expect(menu.item(withTitle: "Add Below This Pane")?.isEnabled == true)
        #expect(menu.item(withTitle: "Copy Links")?.isEnabled == false)
    }

    @Test func aPendingInsertionPreventsAnotherPaneMenu() throws {
        let fixture = try SplitResizeCommandAvailabilityTests.Fixture()
        let anchor = NSView()
        let pane = try #require(fixture.owner.panes[fixture.ids[0]])
        pane.addSubview(anchor)
        fixture.owner.splitInsertion = try fixture.pendingPane()
        fixture.owner.presentSplitPaneMenu = { _, _ in Issue.record("Presented while an insertion was pending") }

        fixture.owner.showSplitPaneMenu(fixture.ids[0], from: anchor)
    }
}
