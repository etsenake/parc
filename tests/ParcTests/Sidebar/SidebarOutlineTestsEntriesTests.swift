import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarOutlineTestsEntriesTests {
    private typealias Support = SidebarOutlineTestsSupport
    private typealias Control = Support.Control
    private typealias Slot = Support.Slot
    private typealias Listing = Support.Listing

    @Test func rowsAbutAndTheOutlineEndsWithTheBottomInset() {
        let l = Listing()
        #expect(l.outline.orientation == .vertical)
        #expect(l.outline.spacing == 0)
        #expect(l.outline.edgeInsets.top == 0)
        #expect(l.outline.edgeInsets.bottom == SidebarChromeLayout.tablistBottomInset)
    }

    @Test func aTabEntryIsAnItemRowKeyedByItsReference() {
        let l = Listing()
        let entry = SidebarOutlineEntry.item(l.childID, content: l.child, depth: 2, in: l.archiveID)
        #expect(entry.key == AnyHashable(l.childID))
        #expect(entry.isItem)
        #expect(entry.row == .item)
        #expect(entry.level == 2)
    }

    @Test func aTabEntryIsDisclosedByItsFoldersRowAndDisclosesNothing() {
        let l = Listing()
        let entry = SidebarOutlineEntry.item(l.childID, content: l.child, depth: 2, in: l.archiveID)
        #expect(entry.disclosedBy == l.archiveKey)
        #expect(entry.expanded == nil)
        #expect(entry.toggle == nil)
    }

    @Test func aRootSplitEntryHasNoLevelAndNoDisclosingRow() {
        let l = Listing()
        let entry = SidebarOutlineEntry.item(l.splitID, content: l.split, depth: 0, in: nil)
        #expect(entry.isItem)
        #expect(entry.level == 0)
        #expect(entry.disclosedBy == nil)
    }

    @Test func aFolderEntryIsAnItemRowKeyedByItsFolderAndPlacedAsATabIs() {
        let l = Listing()
        let entry = SidebarOutlineEntry.folder(l.archiveID, content: l.subfolder, depth: 1, in: l.workID, expanded: false, toggle: {})
        #expect(entry.key == l.archiveKey)
        #expect(entry.isItem)
        #expect(entry.row == .item)
        #expect(entry.level == 1)
        #expect(entry.disclosedBy == l.workKey)
    }

    @Test func aFolderEntryCarriesItsExpandedStateAndToggle() {
        let l = Listing()
        var toggled = 0
        let entry = SidebarOutlineEntry.folder(l.archiveID, content: l.subfolder, depth: 1, in: l.workID, expanded: false, toggle: { toggled += 1 })
        entry.toggle?()
        #expect(entry.expanded == false)
        #expect(toggled == 1)
    }

    @Test func aListControlsEntryIsNoItem() {
        let l = Listing()
        let entry = SidebarOutlineEntry(key: Control.newTab, content: l.newTab, row: .item)
        #expect(!entry.isItem)
        #expect(entry.level == 0)
        #expect(entry.disclosedBy == nil)
    }

    @Test func thePinnedHeaderEntryIsAnEmptyControlRowInItsSlot() {
        let l = Listing()
        #expect(l.header.key == AnyHashable(Control.header))
        #expect(l.header.content == nil)
        #expect(l.header.row == Slot.pinnedHeader.row)
        #expect(!l.header.isItem)
    }

    @Test func thePinnedHeaderEntryIsExpandableWithNoChildrenAndNoToggle() {
        let l = Listing()
        #expect(l.header.expandableWithoutChildren)
        #expect(l.header.expanded == nil)
        #expect(l.header.toggle == nil)
        #expect(l.header.level == 0)
        #expect(l.header.disclosedBy == nil)
    }
}
