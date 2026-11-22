import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteDesignSystemTestsMenuFilteringAndEvents {
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

    private func filtering() -> (NoteMenuList, Counter) {
        let list = keyboardList()
        let counter = Counter()
        list.preferredSizeDidChange = { counter.value += 1 }
        return (list, counter)
    }

    private final class Counter { var value = 0 }

    @Test func keywordsMatch() {
        let (list, _) = filtering()
        list.filterText = "task"
        #expect(list.visibleItems.map(\.id) == ["todo"])
    }

    @Test func filteringReportsANewSize() {
        let (list, counter) = filtering()
        list.filterText = "task"
        #expect(counter.value > 0)
    }

    @Test func theBestMatchIsHighlighted() {
        let (list, _) = filtering()
        list.filterText = "task"
        #expect(list.highlightedItem?.id == "todo")
    }

    @Test func titlePrefixesRankFirst() {
        let (list, _) = filtering()
        list.filterText = "h"
        #expect(list.visibleItems.first?.id == "h1")
    }

    @Test func noResultsActivateNothing() {
        let (list, _) = filtering()
        list.filterText = "zzz"
        #expect(list.visibleItems.isEmpty)
        #expect(!list.activateHighlighted())
    }

    @Test func theFriendlyEmptyRowKeepsItsPlace() {
        let (list, _) = filtering()
        list.filterText = "zzz"
        #expect(list.intrinsicContentSize.height == NoteTheme.menuRowHeight + NoteTheme.menuInset * 2)
    }

    @Test func clearingTheFilterRestoresEverything() {
        let (list, _) = filtering()
        list.filterText = "zzz"
        list.filterText = ""
        #expect(list.visibleItems.count == sampleItems().count)
    }

    @Test func externalFilteringSharesTheRanking() {
        #expect(NoteMenuList.filter(sampleItems(), query: "vid").map(\.id) == ["video"])
    }

    @Test func matchingIgnoresCase() {
        #expect(NoteMenuList.matches(sampleItems()[1], query: "HEADING"))
    }

    @Test func matchingIgnoresAccents() {
        #expect(NoteMenuList.matches(.init(id: "c", title: "Café"), query: "cafe"))
    }

    private func key(_ code: UInt16, _ characters: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private func pointerList() -> NoteMenuList {
        let list = NoteMenuList(items: sampleItems())
        list.prepare(origin: .pointer)
        return list
    }

    @Test func downArrowStartsAtTheTop() {
        let list = pointerList()
        #expect(list.handleKeyDown(key(125)))
        #expect(list.highlightedIndex == 0)
    }

    @Test func moveDownMoves() {
        let list = pointerList()
        _ = list.handleKeyDown(key(125))
        #expect(list.handle(command: #selector(NSResponder.moveDown(_:))))
        #expect(list.highlightedIndex == 1)
    }

    @Test func escapeCancels() {
        let list = pointerList()
        var cancelled = false
        list.onCancel = { cancelled = true }
        #expect(list.handleKeyDown(key(53)))
        #expect(cancelled)
    }

    @Test func typingPassesThroughUnlessTheMenuFilters() {
        #expect(!pointerList().handleKeyDown(key(0, "a")))
    }

    @Test func typingFiltersWhenTheMenuFilters() {
        let list = pointerList()
        list.filtersOnTyping = true
        #expect(list.handleKeyDown(key(9, "v")))
        #expect(list.filterText == "v")
    }

    @Test func deleteTrimsTheFilter() {
        let list = pointerList()
        list.filtersOnTyping = true
        _ = list.handleKeyDown(key(9, "v"))
        #expect(list.handleKeyDown(key(51)))
        #expect(list.filterText.isEmpty)
    }

    @Test func rightArrowOpensASubmenu() {
        let submenu = NoteMenuList(items: [.init(id: "color", title: "Color", hasSubmenu: true)])
        var opened = false
        submenu.onActivate = { _ in opened = true }
        submenu.prepare(origin: .keyboard)
        #expect(submenu.handleKeyDown(key(124)))
        #expect(opened)
    }

    @Test func theListIsAMenu() {
        #expect(NoteMenuList(items: sampleItems()).accessibilityRole() == .menu)
    }

    @Test func rowsAreMenuItems() {
        let rows = NoteMenuList(items: sampleItems()).accessibilityChildren() as? [NSAccessibilityElement]
        #expect(rows?.first?.accessibilityRole() == .menuItem)
    }
}
