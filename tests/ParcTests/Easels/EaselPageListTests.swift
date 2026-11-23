import AppKit
import Foundation
import Testing
@testable import ParcNotes
@testable import ParcEasels

@MainActor
struct EaselPageListTests {
    private func page(_ number: Int) -> EaselPageSwitcher.Row {
        EaselPageSwitcher.Row(id: UUID(), name: "Page \(number)", isDivider: false, isCurrent: number == 0, objectCount: 0)
    }

    private func point(row index: Int) -> NSPoint {
        NSPoint(x: 40, y: NoteTheme.menuInset + (CGFloat(index) + 0.5) * NoteTheme.menuRowHeight)
    }

    @Test func pagesDisappearingWhileTheMouseIsDownDoNotCrashTheList() {
        let switcher = EaselPageSwitcher()
        let rows = (0..<5).map(page)
        let list = EaselPageListView(rows: rows, switcher: switcher)
        list.pointerDown(at: point(row: 4), clickCount: 1)
        list.update(rows: Array(rows.prefix(2)))
        list.pointerDragged(to: NSPoint(x: 40, y: point(row: 4).y + 1))
        list.pointerUp(at: point(row: 1))
        #expect(list.rows.count == 2)
    }

    @Test func aRenameStaysOnItsPageWhenAnEarlierPageIsRemoved() {
        let switcher = EaselPageSwitcher()
        let rows = (0..<3).map(page)
        let list = EaselPageListView(rows: rows, switcher: switcher)
        list.pointerDown(at: point(row: 1), clickCount: 2)
        #expect(list.renamingIndex == 1)
        list.update(rows: Array(rows.dropFirst()))
        #expect(list.renamingIndex == 0)
    }

    @Test func aRenameEndsWhenItsPageIsRemoved() {
        let switcher = EaselPageSwitcher()
        let rows = (0..<3).map(page)
        let list = EaselPageListView(rows: rows, switcher: switcher)
        list.pointerDown(at: point(row: 1), clickCount: 2)
        list.update(rows: [rows[0], rows[2]])
        #expect(list.renamingIndex == nil)
    }
}
