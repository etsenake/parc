import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarOutlineTestsDisclosureTests {
    private typealias Support = SidebarOutlineTestsSupport
    private typealias Control = Support.Control
    private typealias Listing = Support.Listing

    @Test func anExpandedFolderDisclosesAtLevelZero() {
        let l = Listing()
        let work = l.row(l.workKey)
        #expect(work.isAccessibilityDisclosed())
        #expect(work.accessibilityDisclosureLevel() == 0)
    }

    @Test func aFolderDisclosesItsDirectChildRows() {
        let l = Listing()
        let disclosed = (l.row(l.workKey).accessibilityDisclosedRows() as? [Any]) ?? []
        #expect(disclosed.count == 2)
        #expect(Support.same(disclosed[0], l.row(l.childID)))
        #expect(Support.same(disclosed[1], l.row(l.archiveKey)))
    }

    @Test func aChildRowIsDisclosedByItsFolder() {
        let l = Listing()
        let childRow = l.row(l.childID)
        #expect(Support.same(childRow.accessibilityDisclosedByRow(), l.row(l.workKey)))
        #expect(childRow.accessibilityDisclosureLevel() == 1)
    }

    @Test func aCollapsedSubfolderDisclosesNothingAndIsDisclosedByItsParent() {
        let l = Listing()
        let archive = l.row(l.archiveKey)
        #expect(!archive.isAccessibilityDisclosed())
        #expect(((archive.accessibilityDisclosedRows() as? [Any]) ?? []).isEmpty)
        #expect(Support.same(archive.accessibilityDisclosedByRow(), l.row(l.workKey)))
        #expect(archive.accessibilityDisclosureLevel() == 1)
    }

    @Test func aRootTabRowHasNoDisclosure() {
        let l = Listing()
        let pinned = l.row(l.pinnedID)
        #expect(pinned.accessibilityDisclosedByRow() == nil)
        #expect(!pinned.isAccessibilityDisclosed())
        #expect(pinned.accessibilityDisclosureLevel() == 0)
    }

    @Test func aFolderRowTakesAXDisclosingAndATabRowDoesNot() {
        let l = Listing()
        let selector = #selector(NSView.setAccessibilityDisclosed(_:))
        #expect(l.row(l.workKey).isAccessibilitySelectorAllowed(selector))
        #expect(!l.row(l.pinnedID).isAccessibilitySelectorAllowed(selector))
    }

    @Test func withoutAnOwnerAccessibilityCannotSetTheSelection() {
        let l = Listing()
        #expect(!l.row(l.workKey).isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilitySelected(_:))))
        #expect(!l.outline.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilitySelectedRows(_:))))
    }

    @Test func thePinnedHeaderRowIsCollapsedAtLevelZeroAndDisclosesNothing() {
        let l = Listing()
        let headerRow = l.row(Control.header)
        #expect(!headerRow.isAccessibilityDisclosed())
        #expect(headerRow.accessibilityDisclosureLevel() == 0)
        #expect(((headerRow.accessibilityDisclosedRows() as? [Any]) ?? []).isEmpty)
        #expect(headerRow.accessibilityDisclosedByRow() == nil)
        #expect(headerRow.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilityDisclosed(_:))))
    }

    @Test func thePinnedItemsAreTheHeadersSiblings() {
        let l = Listing()
        let headerRow = l.row(Control.header)
        #expect(l.rows.allSatisfy { !Support.same($0.accessibilityDisclosedByRow(), headerRow) })
        #expect(l.row(l.pinnedID).accessibilityDisclosureLevel() == 0)
    }

    @Test func axSelectedRowsAreTheChosenRows() {
        let l = Listing()
        l.outline.select([l.pinnedID, l.todayID])
        let rows = l.selectedRows()
        #expect(rows.count == 2)
        #expect(Support.same(rows[0], l.row(l.pinnedID)))
        #expect(Support.same(rows[1], l.row(l.todayID)))
    }

    @Test func rowsAndCellsReportSelection() {
        let l = Listing()
        l.outline.select([l.pinnedID, l.todayID])
        #expect(l.row(l.pinnedID).isAccessibilitySelected())
        #expect(l.row(l.pinnedID).cell.isAccessibilitySelected())
        #expect(!l.row(l.workKey).isAccessibilitySelected())
    }

    @Test func itemsWithoutAVisibleRowAreNotSelected() {
        let l = Listing()
        l.outline.select([l.pinnedID, .tab(UUID()), .folder(UUID())])
        #expect(l.selectedRows().count == 1)
        #expect(Support.same(l.selectedRows().first, l.row(l.pinnedID)))
    }

    @Test func settingTheCurrentDisclosureDoesNothing() {
        let l = Listing()
        l.row(l.workKey).setAccessibilityDisclosed(true)
        #expect(l.folder.toggles == 0)
    }

    @Test func collapsingTheFolderRowRunsTheFoldersToggleOnce() {
        let l = Listing()
        l.row(l.workKey).setAccessibilityDisclosed(false)
        #expect(l.folder.toggles == 1)
    }

    @Test func aTabRowIgnoresAXDisclosing() {
        let l = Listing()
        l.row(l.pinnedID).setAccessibilityDisclosed(true)
        #expect(l.folder.toggles == 0)
        #expect(l.subfolder.toggles == 0)
    }

    @Test func thePinnedHeaderRowStaysCollapsedWithNoRowsToDisclose() {
        let l = Listing()
        let before = l.rows
        let headerRow = l.row(Control.header)
        headerRow.setAccessibilityDisclosed(true)
        #expect(!headerRow.isAccessibilityDisclosed())
        #expect(((headerRow.accessibilityDisclosedRows() as? [Any]) ?? []).isEmpty)
        #expect(zip(l.rows, before).allSatisfy { $0 === $1 })
        #expect(l.folder.toggles == 0)
    }

    @Test func axDisclosingKeepsTheSelectedRows() {
        let l = Listing()
        l.outline.select([l.pinnedID])
        l.row(l.workKey).setAccessibilityDisclosed(false)
        #expect(l.selectedRows().count == 1)
        #expect(l.row(l.pinnedID).isAccessibilitySelected())
    }

    @Test func onlyRowsInsideTheVisibleAreaAreAXVisibleRows() {
        let l = Listing()
        let visible = l.outline.accessibilityVisibleRows() ?? []
        #expect(!visible.isEmpty)
        #expect(visible.count < l.rows.count)
        #expect(Support.same(visible.first, l.rows.first))
    }

    @Test func scrollingMovesTheVisibleRows() {
        let l = Listing()
        l.scroll.contentView.scroll(to: NSPoint(x: 0, y: l.outline.frame.height - l.scroll.contentView.bounds.height))
        l.scroll.reflectScrolledClipView(l.scroll.contentView)
        let scrolled = l.outline.accessibilityVisibleRows() ?? []
        #expect(Support.same(scrolled.last, l.rows.last))
        #expect(!scrolled.contains { Support.same($0, l.rows.first) })
    }
}
