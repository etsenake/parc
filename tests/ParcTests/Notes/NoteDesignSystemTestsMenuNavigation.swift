import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteDesignSystemTestsMenuNavigation {
    private init() { NoteEditorFixtures.registerFonts() }

    private func sampleItems() -> [NoteMenuList.Item] {
        [
            .init(id: "text", title: "Text", icon: .glyph("Aa"), section: "Basic blocks"),
            .init(id: "h1", title: "Heading 1", icon: .glyph("H1"), shortcut: "#", section: "Basic blocks", keywords: ["title"]),
            .init(id: "todo", title: "To-do List", icon: .symbol("checkmark.square"), section: "Basic blocks", keywords: ["checkbox", "task"]),
            .init(id: "image", title: "Image", section: "Media", isEnabled: false),
            .init(id: "video", title: "Video", section: "Media"),
            .init(id: "delete", title: "Delete", shortcut: "Delete", separatorBefore: true),
        ]
    }

    private func keyboardList() -> NoteMenuList {
        let list = NoteMenuList(items: sampleItems())
        list.prepare(origin: .keyboard)
        return list
    }

    @Test func sectionsAddHeadersAndSeparators() {
        let list = NoteMenuList(items: sampleItems())
        let rows = NoteTheme.menuRowHeight * 6
        let chrome = NoteTheme.menuHeaderHeight * 2 + NoteTheme.menuSeparatorSlot * 2 + NoteTheme.menuInset * 2
        #expect(list.intrinsicContentSize.height == rows + chrome)
    }

    @Test func pointerMenusOpenWithoutAHighlight() {
        #expect(NoteMenuList(items: sampleItems()).highlightedIndex == nil)
    }

    @Test func keyboardMenusHighlightTheFirstRow() {
        #expect(keyboardList().highlightedIndex == 0)
    }

    @Test func arrowsSkipDisabledRows() {
        let list = keyboardList()
        for _ in 0..<3 { list.moveHighlight(by: 1) }
        #expect(list.highlightedItem?.id == "video")
    }

    @Test func arrowsWrapAround() {
        let list = keyboardList()
        for _ in 0..<5 { list.moveHighlight(by: 1) }
        #expect(list.highlightedIndex == 0)
    }

    @Test func upFromTheTopWrapsToTheBottom() {
        let list = keyboardList()
        list.moveHighlight(by: -1)
        #expect(list.highlightedItem?.id == "delete")
    }

    @Test func returnActivatesTheHighlightedRow() {
        let list = keyboardList()
        list.moveHighlight(by: -1)
        var activated: [String] = []
        list.onActivate = { activated.append($0.id) }
        #expect(list.activateHighlighted())
        #expect(activated == ["delete"])
    }

    @Test func disabledRowsRefuseTheHighlight() {
        let list = keyboardList()
        list.highlightedIndex = 3
        #expect(list.highlightedIndex != 3)
    }

    @Test func keyboardMenusReHighlightTheFirstRowAfterAnUpdate() {
        let list = keyboardList()
        list.highlight(id: "video")
        list.items = sampleItems()
        #expect(list.highlightedIndex == 0)
    }

    @Test func updatesCanKeepTheHighlightedRow() {
        let list = keyboardList()
        list.highlight(id: "video")
        list.setItems(sampleItems(), keepingHighlight: true)
        #expect(list.highlightedItem?.id == "video")
    }

    private func longList() -> NoteMenuList {
        NoteMenuList(items: (0..<40).map { .init(id: "\($0)", title: "Row \($0)") })
    }

    @Test func longMenusCapTheirHeightAndScroll() {
        let long = longList()
        #expect(long.intrinsicContentSize.height == long.maximumHeight)
    }

    @Test func theMaximumHeightIsAdjustable() {
        let long = longList()
        long.maximumHeight = 200
        #expect(long.fittingSize.height == 200)
    }
}
