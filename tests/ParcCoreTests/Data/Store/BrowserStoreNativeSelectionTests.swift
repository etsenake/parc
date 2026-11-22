import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativeSelectionTests {
    private struct SidebarRows {
        let active = SidebarItemReference.tab(UUID())
        let neighbor = SidebarItemReference.tab(UUID())
        let folder = SidebarItemReference.folder(UUID())
        let split = SidebarItemReference.split(UUID())
        var order: [SidebarItemReference] { [active, neighbor, folder, split] }
    }

    @Test static func modifierSelectionFollowsTheStableSidebarAnchor() {
        let active = SidebarItemReference.tab(UUID()), neighbor = SidebarItemReference.tab(UUID())
        let folder = SidebarItemReference.folder(UUID()), split = SidebarItemReference.split(UUID())
        let order = [active, neighbor, folder, split]
        var selection = SidebarItemSelection()
        selection.select(folder, order: order, active: active, extending: false, toggling: true)
        #expect(selection.items == [active, folder], "Command selection retains active item without activating the target")
        selection.select(split, order: order, active: active, extending: true, toggling: false)
        #expect(selection.items == [active, folder, split], "Shift range uses the stable original-item anchor and retains active item")
        selection.select(neighbor, order: order, active: active, extending: true, toggling: false)
        #expect(selection.items == [active, neighbor, folder], "Reversing range shrinks around the same anchor")
        selection.select(active, order: order, active: active, extending: false, toggling: true)
        #expect(selection.items == [active, neighbor, folder], "Active item remains in a multi-selection")
    }

    @Test static func reconcilingSidebarSelectionDropsCollapsedRows() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection(items: [rows.active, rows.neighbor, rows.folder],
                                             anchor: rows.active, focus: rows.active)
        selection.reconcile(order: [rows.active, rows.split])
        #expect(selection.items.isEmpty && selection.focus == rows.active, "Removed or collapsed rows cannot retain a hidden multi-selection")
    }

    @Test static func aRangeStartsFromTheActiveRowAndExitsWhenOnlyItRemains() {
        let a = SidebarItemReference.tab(UUID()), b = SidebarItemReference.tab(UUID())
        let c = SidebarItemReference.folder(UUID()), d = SidebarItemReference.split(UUID())
        let order = [a, b, c, d]
        var selection = SidebarItemSelection()
        selection.select(b, order: order, active: a, extending: true, toggling: false)
        #expect(selection.items == [a, b], "First range starts at current active item")
        selection.select(b, order: order, active: a, extending: false, toggling: true)
        #expect(selection.items.isEmpty, "Returning to active singleton exits multi-selection")
    }

    @Test static func aStaleTargetCannotEnterSidebarSelection() {
        let a = SidebarItemReference.tab(UUID()), b = SidebarItemReference.tab(UUID())
        let c = SidebarItemReference.folder(UUID()), d = SidebarItemReference.split(UUID())
        let order = [a, b, c, d]
        var selection = SidebarItemSelection()
        selection.select(.tab(UUID()), order: order, active: a, extending: true, toggling: false)
        #expect(selection.items.isEmpty, "Stale target IDs cannot enter selection")
    }

    @Test static func anOffSidebarActivePageDoesNotEnterAMultiSelection() {
        let a = SidebarItemReference.tab(UUID()), b = SidebarItemReference.tab(UUID())
        let c = SidebarItemReference.folder(UUID()), d = SidebarItemReference.split(UUID())
        let order = [a, b, c, d]
        var selection = SidebarItemSelection()
        selection.select(b, order: order, active: .tab(UUID()), extending: false, toggling: true)
        #expect(selection.items.isEmpty && selection.singleItem == b, "An off-outline active page yields genuine singleton activation, never an invisible grant")
        selection.select(a, order: order, active: b, extending: false, toggling: true)
        #expect(selection.items == [a, b] && selection.singleItem == nil, "The next modifier press forms the original native multi-set")
    }

    @Test static func accessibilityShowsTheActiveRowWhenNoOtherRowIsChosen() {
        let rows = SidebarRows()
        let selection = SidebarItemSelection()
        #expect(selection.shown(active: rows.active) == [rows.active], "With nothing chosen the current item is the shown selection")
    }

    @Test static func accessibilityAssignmentShowsASingleRequestedRowAlone() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        let hoisted1 = selection.assign([rows.neighbor], order: rows.order, active: rows.active)
        #expect(hoisted1, "One requested row is accepted")
        #expect(selection.items.isEmpty && selection.singleItem == rows.neighbor && selection.focus == rows.neighbor && selection.anchor == rows.neighbor, "One requested row becomes the single selection without forming a multi-set")
        #expect(selection.shown(active: rows.active) == [rows.neighbor], "A single selection is shown alone, without the current item")
    }

    @Test static func accessibilityMultiSelectionKeepsTheActiveItemInDisplayOrder() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.neighbor], order: rows.order, active: rows.active)
        let hoisted2 = selection.assign([rows.neighbor, rows.split], order: rows.order, active: rows.active)
        #expect(hoisted2, "Two requested rows are accepted")
        #expect(selection.items == [rows.active, rows.neighbor, rows.split] && selection.singleItem == nil && selection.focus == rows.split && selection.anchor == rows.split, "A requested multi-set keeps the current item, in display order, focused on the newcomer")
        #expect(selection.shown(active: rows.active) == [rows.active, rows.neighbor, rows.split], "A multi-set is shown exactly")
    }

    @Test static func accessibilityMultiSelectionCanGrowAndShrinkWithoutDroppingTheActiveRow() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.neighbor, rows.split], order: rows.order, active: rows.active)
        #expect(selection.assign([rows.active, rows.neighbor, rows.folder, rows.split], order: rows.order, active: rows.active) && selection.items == [rows.active, rows.neighbor, rows.folder, rows.split] && selection.focus == rows.folder, "Adding one row grows the multi-set and focuses the added row")
        #expect(selection.assign([rows.neighbor, rows.folder, rows.split], order: rows.order, active: rows.active) && selection.items == [rows.active, rows.neighbor, rows.folder, rows.split], "Leaving the current item out of a multi-set keeps it, as Command-click does")
        #expect(selection.assign([rows.neighbor, rows.folder], order: rows.order, active: rows.active) && selection.items == [rows.active, rows.neighbor, rows.folder], "Dropping another row shrinks the multi-set")
    }

    @Test static func accessibilityRejectsAnEntirelyUnknownSelectionWithoutChangingIt() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.neighbor, rows.split], order: rows.order, active: rows.active)
        let kept = selection
        #expect(!selection.assign([.tab(UUID())], order: rows.order, active: rows.active) && selection == kept, "Rows outside the displayed order are refused and change nothing")
    }

    @Test static func accessibilityDeselectingTheOnlyActiveRowKeepsKeyboardFocus() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        #expect(selection.assign([rows.active], order: rows.order, active: rows.active) && selection.items.isEmpty && selection.singleItem == rows.active
                   && selection.shown(active: rows.active) == [rows.active], "Choosing only the current item returns to it")
        #expect(selection.assign([], order: rows.order, active: rows.active) && selection.singleItem == rows.active && selection.focus == rows.active, "Deselecting the current item while it is all that's chosen keeps keyboard focus")
    }

    @Test static func anEmptyAccessibilitySelectionClearsAMultiSet() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        #expect(selection.assign([rows.neighbor, rows.folder], order: rows.order, active: rows.active) && selection.assign([], order: rows.order, active: rows.active)
                   && selection == SidebarItemSelection(), "An empty request clears a multi-set")
    }

    @Test static func accessibilitySelectionIgnoresUnknownRowsAndAnOffSidebarActivePage() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        #expect(selection.assign([rows.folder, .tab(UUID())], order: rows.order, active: rows.active) && selection.singleItem == rows.folder && selection.items.isEmpty, "Unknown rows in a request are ignored")
        #expect(selection.assign([rows.neighbor, rows.folder], order: rows.order, active: .tab(UUID())) && selection.items == [rows.neighbor, rows.folder], "A current page outside the sidebar never joins a multi-set")
    }

    @Test static func shiftClickRangesFromTheAccessibilityAnchorInEitherDirection() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.folder], order: rows.order, active: rows.active)
        selection.select(rows.split, order: rows.order, active: rows.active, extending: true, toggling: false)
        #expect(selection.items == [rows.active, rows.folder, rows.split], "Shift-click ranges from an accessibility single selection's anchor")
        selection.clear()
        selection.assign([rows.split], order: rows.order, active: rows.active)
        selection.select(rows.folder, order: rows.order, active: rows.active, extending: true, toggling: false)
        #expect(selection.items == [rows.active, rows.folder, rows.split], "Extending upward from an accessibility single selection keeps its anchor")
    }

    @Test static func commandClickAndAccessibilityCanUpdateTheSameMultiSet() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.neighbor], order: rows.order, active: rows.active)
        selection.select(rows.split, order: rows.order, active: rows.active, extending: false, toggling: true)
        #expect(selection.items == [rows.active, rows.split], "Command-click after a single selection builds the usual multi-set from the current item")
        #expect(selection.assign([rows.split], order: rows.order, active: rows.active) && selection.items.isEmpty && selection.singleItem == rows.split, "Taking the current item out of a two-row set leaves the other row as the single selection")
        selection.select(rows.split, order: rows.order, active: rows.active, extending: false, toggling: true)
        #expect(selection.items == [rows.active, rows.split], "Command-click on that row starts again from the current item")
        selection.assign([rows.active, rows.split, rows.neighbor], order: rows.order, active: rows.active)
        #expect(selection.items == [rows.active, rows.neighbor, rows.split] && selection.focus == rows.neighbor, "Accessibility adds to a Command-click multi-set")
        selection.select(rows.folder, order: rows.order, active: rows.active, extending: false, toggling: true)
        #expect(selection.items == [rows.active, rows.neighbor, rows.folder, rows.split], "Command-click adds to an accessibility multi-set")
        selection.select(rows.neighbor, order: rows.order, active: rows.active, extending: true, toggling: false)
        #expect(selection.items == [rows.active, rows.neighbor, rows.folder], "Shift-click ranges from the last Command-clicked anchor")
    }

    @Test static func keyboardNavigationReplacesTheAccessibilitySelection() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.split], order: rows.order, active: rows.active)
        selection.select(rows.folder, order: rows.order, active: rows.active, extending: true, toggling: false)
        #expect(selection.items == [rows.active, rows.folder, rows.split], "Extending upward from an accessibility single selection keeps its anchor")
        selection.select(rows.neighbor, order: rows.order, active: rows.active, extending: false, toggling: false)
        #expect(selection.items.isEmpty && selection.singleItem == rows.neighbor && selection.shown(active: rows.active) == [rows.neighbor], "A plain keyboard move replaces an accessibility selection")
    }

    @Test static func reconcilingAccessibilitySelectionDropsCollapsedRows() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.neighbor, rows.folder], order: rows.order, active: rows.active)
        selection.reconcile(order: [rows.active, rows.split])
        #expect(selection.items.isEmpty && selection.shown(active: rows.active) == [rows.active], "Rows collapsed away from an accessibility multi-set leave it like any other")
    }

    @Test static func reconcilingAnAccessibilityMultiSetTracksTheActiveRowOnlyWhenVisible() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.neighbor, rows.folder], order: rows.order, active: .tab(UUID()))
        selection.reconcile(order: rows.order, active: rows.active)
        #expect(selection.items == [rows.active, rows.neighbor, rows.folder], "A multi-set picks up the current item once its row appears")
        selection.reconcile(order: [rows.active, rows.neighbor, rows.split], active: rows.active)
        #expect(selection.items == [rows.active, rows.neighbor], "Trimming keeps the current item and the rows still shown")
        selection.assign([rows.neighbor, rows.folder], order: rows.order, active: .tab(UUID()))
        selection.reconcile(order: [rows.neighbor, rows.folder, rows.split], active: rows.active)
        #expect(selection.items == [rows.neighbor, rows.folder], "A current item without a row is never added")
    }

    @Test static func reconcilingAccessibilitySelectionNeverInventsAMultiSet() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.reconcile(order: rows.order, active: rows.active)
        #expect(selection.items.isEmpty, "Reconciling never invents a multi-set")
    }

    @Test static func selectAllKeepsOnlyDisplayedRowsAndUsesTheirOrder() {
        let a = SidebarItemReference.tab(UUID()), b = SidebarItemReference.folder(UUID()), c = SidebarItemReference.split(UUID())
        var selection = SidebarItemSelection()
        selection.selectAll(order: [a, b, c, a], active: c)
        #expect(selection.items == [a, b, c], "Select All includes displayed original items once, in display order")
        #expect(selection.focus == c && selection.anchor == a, "Select All retains visible active focus and a stable first-row anchor")
        selection.selectAll(order: [b, c], active: a)
        #expect(selection.items == [b, c] && !selection.items.contains(a), "Select All cannot include hidden/foreign active rows")
    }

    @Test static func selectAllUsesSingletonSelectionAndClearsItForAnEmptySidebar() {
        let a = SidebarItemReference.tab(UUID()), c = SidebarItemReference.split(UUID())
        var selection = SidebarItemSelection()
        selection.selectAll(order: [a], active: c)
        #expect(selection.items.isEmpty && selection.singleItem == a, "Select All of an ordinary singleton uses the ordinary selection path")
        selection.selectAll(order: [], active: a)
        #expect(selection.items.isEmpty && selection.singleItem == nil && selection.focus == nil, "Empty Select All expires previous selection/focus")
    }

    @Test static func copyTargetsPreferValidSelectedRowsOverTheActiveRow() {
        let a = SidebarItemReference.tab(UUID()), b = SidebarItemReference.folder(UUID()), c = SidebarItemReference.split(UUID())
        var copying = SidebarItemSelection()
        #expect(copying.copyTargets(order: [a, b, c], active: c) == [c], "With nothing else chosen, Copy takes the current row")
        #expect(copying.copyTargets(order: [a, b], active: c) == nil, "A current row outside the sidebar, like a Favorite, has nothing to copy")
        copying.select(b, order: [a, b, c], active: nil, extending: false, toggling: false)
        #expect(copying.items.isEmpty && copying.copyTargets(order: [a, b, c], active: c) == [b], "One selected row copies that row")
        #expect(copying.copyTargets(order: [a, c], active: c) == nil, "A selected row that left the sidebar copies nothing")
        copying.select(c, order: [a, b, c], active: a, extending: false, toggling: true)
        #expect(copying.copyTargets(order: [a, b, c], active: a) == [a, c], "A multi-selection still copies every selected row")
    }
}
