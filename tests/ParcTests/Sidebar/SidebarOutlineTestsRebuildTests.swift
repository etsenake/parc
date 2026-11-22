import AppKit
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarOutlineTestsRebuildTests {
    private typealias Support = SidebarOutlineTestsSupport
    private typealias TabItem = Support.TabItem
    private typealias Control = Support.Control
    private typealias Slot = Support.Slot
    private typealias Listing = Support.Listing

    private func walk(_ element: Any, _ seen: inout [ObjectIdentifier: Int]) {
        guard let object = element as? NSObject else { return }
        seen[ObjectIdentifier(object), default: 0] += 1
        let children = (object as? NSView)?.accessibilityChildren() ?? (object as? NSCell)?.accessibilityChildren()
            ?? (object as? NSAccessibilityElement)?.accessibilityChildren() ?? []
        for child in children { walk(child, &seen) }
    }

    @Test func everyItemElementIsExposedExactlyOnce() {
        let l = Listing()
        var seen: [ObjectIdentifier: Int] = [:]
        walk(l.outline, &seen)
        for item in [l.pinned, l.folder, l.child, l.subfolder, l.split, l.today] + l.split.tabs as [NSView] {
            #expect(seen[ObjectIdentifier(item)] == 1)
        }
        #expect(seen.values.allSatisfy { $0 == 1 })
        #expect(seen[ObjectIdentifier(l.clear.cell!)] == 1)
    }

    @Test func contentsKeepEveryEntrysViewAndThePinnedHeaderHasNone() {
        let l = Listing()
        #expect(l.outline.contents.count == 8)
        #expect(l.outline.contents.first === l.pinned)
        #expect(l.outline.contents.last === l.today)
    }

    @Test func rowsSurviveARebuildUnderTheSameKey() {
        let l = Listing()
        let pinnedRow = l.row(l.pinnedID)
        let workRow = l.row(l.workKey)
        l.reload(l.entries(folderExpanded: false, pinned: TabItem("Pinned", l.counter)))
        #expect(l.rows.count == 7)
        #expect(l.rows[1] === pinnedRow)
        #expect(l.rows[2] === workRow)
    }

    @Test func thePinnedHeaderRowSurvivesARebuildCollapsedAndSettable() {
        let l = Listing()
        let headerRow = l.row(Control.header)
        l.reload(l.entries(folderExpanded: false))
        #expect(l.rows[0] === headerRow)
        #expect(!headerRow.isAccessibilityDisclosed())
        #expect(headerRow.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilityDisclosed(_:))))
    }

    @Test func collapsingThePinnedHeaderChangesNothing() {
        let l = Listing()
        let headerRow = l.row(Control.header)
        l.reload(l.entries(folderExpanded: false))
        headerRow.setAccessibilityDisclosed(false)
        #expect(!headerRow.isAccessibilityDisclosed())
        #expect(l.rows.count == 7)
    }

    @Test func aKeptRowsCellTakesTheNewElement() {
        let l = Listing()
        let rebuilt = TabItem("Pinned", l.counter)
        l.reload(l.entries(folderExpanded: false, pinned: rebuilt))
        #expect(Support.same(l.rows[1].cell.accessibilityChildren()?.first, rebuilt))
        #expect(l.pinned.superview == nil)
    }

    @Test func rowsThatLeftTheListLeaveTheWindowWithTheirElements() {
        let l = Listing()
        let childRow = l.row(l.childID)
        let archiveRow = l.row(l.archiveKey)
        l.reload(l.entries(folderExpanded: false))
        #expect(childRow.superview == nil)
        #expect(archiveRow.superview == nil)
        #expect(l.child.window == nil)
    }

    @Test func theCollapsedFolderDisclosesNothing() {
        let l = Listing()
        let workRow = l.row(l.workKey)
        l.reload(l.entries(folderExpanded: false))
        #expect(!workRow.isAccessibilityDisclosed())
        #expect(((workRow.accessibilityDisclosedRows() as? [Any]) ?? []).isEmpty)
    }

    @Test func indicesFollowTheRebuiltOrder() {
        let l = Listing()
        l.reload(l.entries(folderExpanded: false))
        #expect(l.rows.enumerated().allSatisfy { $0.element.accessibilityIndex() == $0.offset })
    }

    @Test func selectionCarriesOverToKeptRows() {
        let l = Listing()
        l.outline.select([l.pinnedID])
        l.reload(l.entries(folderExpanded: false))
        #expect(l.selectedRows().count == 1)
        #expect(l.row(l.pinnedID).isAccessibilitySelected())
    }

    @Test func clearingTheSelectionClearsEveryRow() {
        let l = Listing()
        l.outline.select([l.pinnedID])
        l.outline.select([])
        #expect(l.selectedRows().isEmpty)
        #expect(!l.row(l.pinnedID).isAccessibilitySelected())
    }

    @Test func aHiddenEntrysRowIsNoElementAndTakesNoSpace() {
        let l = Listing()
        let heading = NSTextField(labelWithString: "Incognito Tabs")
        heading.isHidden = true
        l.reload([l.header, .init(key: Control.heading, content: heading, row: Slot.privateHeading.row),
                  SidebarOutlineEntry(key: Control.newTab, content: l.newTab, row: Slot.newTab.row)])
        let hiddenRow = l.outline.arrangedSubviews.first { ($0 as? SidebarOutlineRow)?.key == AnyHashable(Control.heading) }
        #expect(l.rows.count == 2)
        #expect(hiddenRow?.isAccessibilityElement() == false)
        #expect(l.rows[1].frame.minY == 3)
    }

    @Test func duplicateKeysNeverShareARow() {
        let l = Listing()
        l.reload([.item(l.pinnedID, content: TabItem("A"), depth: 0, in: nil), .item(l.pinnedID, content: TabItem("B"), depth: 0, in: nil)])
        #expect(l.rows.count == 2)
        #expect(l.rows[0] !== l.rows[1])
    }

    @Test func theOutlineIsUnfocusedUntilItsStopIsFirstResponder() {
        #expect(!Listing().outline.isAccessibilityFocused())
    }

    @Test func theStopsFocusIsTheOutlinesFocus() {
        let l = Listing()
        l.window.makeFirstResponder(l.root)
        #expect(l.window.firstResponder === l.root)
        #expect(l.outline.isAccessibilityFocused())
    }

    @Test func aStopThatCannotBecomeKeyNeverFocusesTheOutline() {
        let l = Listing()
        l.window.makeFirstResponder(l.root)
        l.root.isPresented = false
        #expect(l.window.firstResponder === l.root)
        #expect(!l.outline.isAccessibilityFocused())
    }

    @Test func aHiddenListIsNeverFocused() {
        let l = Listing()
        l.window.makeFirstResponder(l.root)
        l.scroll.isHidden = true
        #expect(!l.outline.isAccessibilityFocused())
    }

    @Test func aListOfControlsOnlyIsNeverFocused() {
        let l = Listing()
        l.window.makeFirstResponder(l.root)
        l.reload([l.header, SidebarOutlineEntry(key: Control.newTab, content: l.newTab, row: Slot.newTab.row)])
        #expect(l.outline.rows.count == 2)
        #expect(!l.outline.isAccessibilityFocused())
    }

    @Test func anEmptyListIsNeverFocusedAndKeepsOnlyItsColumn() {
        let l = Listing()
        l.window.makeFirstResponder(l.root)
        l.reload([])
        #expect(!l.outline.isAccessibilityFocused())
        #expect(l.outline.rows.isEmpty)
        #expect((l.outline.accessibilityChildren() ?? []).count == 1)
    }
}
