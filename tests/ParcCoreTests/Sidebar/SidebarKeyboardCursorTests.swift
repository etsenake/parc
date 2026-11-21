import Testing
@testable import ParcCore

struct SidebarKeyboardCursorTests {
    private let ids = ["favorite", "split", "today"]

    private func cursor(on id: String?) -> SidebarKeyboardCursor {
        SidebarKeyboardCursor(highlightedID: id)
    }

    @Test func downHighlightsTheNextIdentity() {
        var cursor = cursor(on: "split")
        cursor.move(1, in: ids)
        #expect(cursor.highlightedID == "today")
    }

    @Test func downFromTheLastItemCrossesToNoHighlight() {
        var cursor = cursor(on: "today")
        cursor.move(1, in: ids)
        #expect(cursor.highlightedID == nil)
    }

    @Test func downFromNoHighlightEntersTheFirstItem() {
        var cursor = cursor(on: nil)
        cursor.move(1, in: ids)
        #expect(cursor.highlightedID == "favorite")
    }

    @Test func upFromTheFirstItemCrossesToNoHighlight() {
        var cursor = cursor(on: "favorite")
        cursor.move(-1, in: ids)
        #expect(cursor.highlightedID == nil)
    }

    @Test func upFromNoHighlightEntersTheLastItem() {
        var cursor = cursor(on: nil)
        cursor.move(-1, in: ids)
        #expect(cursor.highlightedID == "today")
    }

    @Test func reorderingKeepsTheStableIdentity() {
        var cursor = cursor(on: "today")
        cursor.reconcile(["today", "favorite", "split"])
        #expect(cursor.highlightedID == "today")
    }

    @Test func nextUsesTheActualRefreshedOrder() {
        var cursor = cursor(on: "today")
        cursor.reconcile(["today", "favorite", "split"])
        cursor.move(1, in: ["today", "favorite", "split"])
        #expect(cursor.highlightedID == "favorite")
    }

    @Test func aRemovedHighlightNeverChangesToAnotherItem() {
        var cursor = cursor(on: "favorite")
        cursor.reconcile(["split", "today"])
        #expect(cursor.highlightedID == nil)
    }

    @Test func reenteringAfterRemovalRespectsTheDirection() {
        var cursor = cursor(on: "favorite")
        cursor.reconcile(["split", "today"])
        cursor.move(-1, in: ["split", "today"])
        #expect(cursor.highlightedID == "today")
    }

    @Test func noMovementPreservesTheHighlight() {
        var cursor = cursor(on: "today")
        cursor.move(0, in: ids)
        #expect(cursor.highlightedID == "today")
    }

    @Test(arguments: [1, -1])
    func anEmptyListClearsARetiredIdentity(direction: Int) {
        var cursor = cursor(on: "today")
        cursor.move(direction, in: [])
        #expect(cursor.highlightedID == nil)
    }

    @Test(arguments: [1, -1])
    func anEmptyListCannotAcquireATarget(direction: Int) {
        var cursor = cursor(on: nil)
        cursor.move(direction, in: [])
        #expect(cursor.highlightedID == nil)
    }

    @Test func aOneItemListEnters() {
        var cursor = cursor(on: nil)
        cursor.move(1, in: ["only"])
        #expect(cursor.highlightedID == "only")
    }

    @Test func aOneItemListStillHasTheSentinel() {
        var cursor = cursor(on: "only")
        cursor.move(1, in: ["only"])
        #expect(cursor.highlightedID == nil)
    }
}
