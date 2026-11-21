import AppKit
import Testing
@testable import Parc
@testable import ParcCore

private final class Item: NSView {
    init(_ title: String) {
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityTitle(title)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private enum Kind: Hashable { case header, divider, newTab }

@MainActor
struct SidebarOutlineSelectionTests {
    @MainActor private final class Owner {
        let outline = SidebarOutlineView()
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 240, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        let order: [SidebarItemReference]
        var selection = SidebarItemSelection()
        var requests: [[SidebarItemReference]] = []
        var accepts = true
        var notes: [NSAccessibility.Notification] = []
        var active: SidebarItemReference { order[4] }
        let items: [SidebarOutlineRow]
        let controls: [SidebarOutlineRow]
        let entries: [SidebarOutlineEntry]

        init() {
            window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: NSRect(x: 8, y: 0, width: 224, height: 400))
            scroll.documentView = outline
            window.contentView = scroll
            let ids = (0..<6).map { _ in SidebarItemReference.tab(UUID()) }
            order = ids
            var list: [SidebarOutlineEntry] = [.pinnedHeader(Kind.header)]
            list += ids.prefix(5).map { .item($0, content: Item("row"), depth: 0, in: nil) }
            list += [SidebarOutlineEntry(key: Kind.divider, content: NSView(), row: SidebarChromeLayout.TablistSlot.sectionDivider.row),
                     SidebarOutlineEntry(key: Kind.newTab, content: NSView(), row: SidebarChromeLayout.TablistSlot.newTab.row),
                     .item(ids[5], content: Item("row"), depth: 0, in: nil)]
            entries = list
            outline.reload(list)
            outline.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(0, outline.contentHeight))
            outline.layoutSubtreeIfNeeded()
            items = outline.rows.filter { $0.key.base is SidebarItemReference }
            controls = outline.rows.filter { !($0.key.base is SidebarItemReference) }
            outline.postAccessibilityNotification = { [weak self] _, name in self?.notes.append(name) }
            outline.selectsFromAccessibility = { [weak self] wanted in
                guard let self else { return false }
                requests.append(wanted)
                guard accepts, selection.assign(wanted, order: order, active: active) else { return false }
                outline.select(selection.shown(active: active))
                return true
            }
            outline.select(selection.shown(active: active))
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func shown() -> [SidebarOutlineRow] { (outline.accessibilitySelectedRows() ?? []).compactMap { $0 as? SidebarOutlineRow } }
        func selected(_ expected: [SidebarOutlineRow]) -> Bool { shown().map(ObjectIdentifier.init) == expected.map(ObjectIdentifier.init) }
        var pinned: SidebarOutlineRow { items[0] }
        var work: SidebarOutlineRow { items[1] }
        var child: SidebarOutlineRow { items[2] }
        var archive: SidebarOutlineRow { items[3] }
        var split: SidebarOutlineRow { items[4] }
        var today: SidebarOutlineRow { items[5] }
    }

    private let setRows = #selector(NSView.setAccessibilitySelectedRows(_:))
    private let setRow = #selector(NSView.setAccessibilitySelected(_:))

    @Test func thereAreSixItemRowsAndThreeControlRows() {
        let o = Owner()
        #expect(o.items.count == 6)
        #expect(o.controls.count == 3)
    }

    @Test func withAnOwnerAXSelectedRowsIsSettable() {
        #expect(Owner().outline.isAccessibilitySelectorAllowed(setRows))
    }

    @Test func everyItemRowsAXSelectedIsSettable() {
        let o = Owner()
        #expect(o.items.allSatisfy { $0.isAccessibilitySelectorAllowed(setRow) })
    }

    @Test func headerDividerAndNewTabRowsCannotBeSelected() {
        let o = Owner()
        #expect(o.controls.allSatisfy { !$0.isAccessibilitySelectorAllowed(setRow) })
    }

    @Test func anOwnerThatCannotSelectNowOffersNothingSettable() {
        let o = Owner()
        o.outline.allowsAccessibilitySelection = { false }
        #expect(!o.outline.isAccessibilitySelectorAllowed(setRows))
        #expect(!o.items.contains { $0.isAccessibilitySelectorAllowed(setRow) })
    }

    @Test func withNothingChosenTheCurrentItemsRowIsTheSelection() {
        let o = Owner()
        #expect(o.selected([o.split]))
    }

    @Test func selectingOneRowAsksForThatItemAloneWithoutAMultiSet() {
        let o = Owner()
        o.today.setAccessibilitySelected(true)
        #expect(o.requests.last == [o.order[5]])
        #expect(o.selection.singleItem == o.order[5])
        #expect(o.selection.items.isEmpty)
    }

    @Test func oneSelectedRowIsReportedAloneWithoutTheCurrentItem() {
        let o = Owner()
        o.today.setAccessibilitySelected(true)
        #expect(o.selected([o.today]))
    }

    @Test func oneSelectionChangePostsOneNotification() {
        let o = Owner()
        o.notes = []
        o.today.setAccessibilitySelected(true)
        #expect(o.notes == [.selectedRowsChanged])
    }

    @Test func repeatingTheSameSelectionPostsNothingMore() {
        let o = Owner()
        o.today.setAccessibilitySelected(true)
        o.notes = []
        o.today.setAccessibilitySelected(true)
        o.outline.setAccessibilitySelectedRows([o.today])
        #expect(o.notes.isEmpty)
        #expect(o.selected([o.today]))
    }

    @Test func axSelectedRowsWithOneRowMovesTheSingleSelection() {
        let o = Owner()
        o.outline.setAccessibilitySelectedRows([o.child])
        #expect(o.selected([o.child]))
        #expect(o.selection.singleItem == o.order[2])
    }

    @Test func addingARowBuildsAMultiSetThatKeepsTheCurrentItem() {
        let o = Owner()
        o.outline.setAccessibilitySelectedRows([o.child])
        o.notes = []
        o.outline.setAccessibilitySelectedRows(o.shown() + [o.pinned])
        #expect(o.selection.items == [o.order[0], o.order[2], o.order[4]])
        #expect(o.selected([o.pinned, o.child, o.split]))
        #expect(o.notes == [.selectedRowsChanged])
    }

    @Test func eachAddedRowJoinsTheMultiSetAndTakesItsFocus() {
        let o = Owner()
        o.outline.setAccessibilitySelectedRows([o.child])
        o.outline.setAccessibilitySelectedRows(o.shown() + [o.pinned])
        o.outline.setAccessibilitySelectedRows(o.shown() + [o.work])
        #expect(o.selected([o.pinned, o.work, o.child, o.split]))
        #expect(o.selection.focus == o.order[1])
    }

    @Test func deselectingARowRemovesItFromTheMultiSet() {
        let o = Owner()
        o.outline.setAccessibilitySelectedRows([o.child])
        o.outline.setAccessibilitySelectedRows(o.shown() + [o.pinned])
        o.outline.setAccessibilitySelectedRows(o.shown() + [o.work])
        o.work.setAccessibilitySelected(false)
        #expect(o.requests.last == [o.order[0], o.order[2], o.order[4]])
        #expect(o.selected([o.pinned, o.child, o.split]))
    }

    @Test func theCurrentItemStaysInAMultiSetOfThreeAndNothingIsPosted() {
        let o = Owner()
        o.outline.setAccessibilitySelectedRows([o.child])
        o.outline.setAccessibilitySelectedRows(o.shown() + [o.pinned])
        o.notes = []
        o.split.setAccessibilitySelected(false)
        #expect(o.selected([o.pinned, o.child, o.split]))
        #expect(o.notes.isEmpty)
    }

    @Test func takingTheCurrentItemOutOfATwoRowSetLeavesTheOtherRowAlone() {
        let o = Owner()
        o.outline.setAccessibilitySelectedRows([o.child])
        o.outline.setAccessibilitySelectedRows(o.shown() + [o.pinned])
        o.outline.setAccessibilitySelectedRows([o.child, o.split])
        o.split.setAccessibilitySelected(false)
        #expect(o.selected([o.child]))
        #expect(o.selection.singleItem == o.order[2])
    }

    @Test func deselectingTheCurrentItemsRowWhileItIsUnselectedAsksForNothing() {
        let o = Owner()
        o.outline.setAccessibilitySelectedRows([o.child])
        o.outline.setAccessibilitySelectedRows([o.child, o.split])
        o.split.setAccessibilitySelected(false)
        let before = o.requests.count
        o.split.setAccessibilitySelected(false)
        #expect(o.selected([o.child]))
        #expect(o.requests.count == before)
    }

    @Test func deselectingAnUnselectedRowAsksForNothing() {
        let o = Owner()
        o.outline.setAccessibilitySelectedRows([o.pinned, o.child])
        let asked = o.requests.count
        o.archive.setAccessibilitySelected(false)
        #expect(o.requests.count == asked)
    }

    @Test func controlRowsAndForeignElementsAreRefusedBeforeReachingTheOwner() {
        let o = Owner()
        o.outline.setAccessibilitySelectedRows([o.pinned, o.child])
        let asked = o.requests.count
        for control in o.controls {
            control.setAccessibilitySelected(true)
            control.setAccessibilitySelected(false)
        }
        o.outline.setAccessibilitySelectedRows(o.controls)
        o.outline.setAccessibilitySelectedRows([NSObject(), "row"])
        #expect(o.requests.count == asked)
        #expect(o.selected([o.pinned, o.child, o.split]))
    }

    @Test func controlRowsMixedIntoARequestAreDropped() {
        let o = Owner()
        o.outline.setAccessibilitySelectedRows(o.controls + [o.today])
        #expect(o.requests.last == [o.order[5]])
        #expect(o.selected([o.today]))
    }

    @Test func deselectingTheSingleRowReturnsTheSelectionToTheCurrentItem() {
        let o = Owner()
        o.today.setAccessibilitySelected(true)
        o.today.setAccessibilitySelected(false)
        #expect(o.requests.last == [])
        #expect(o.selected([o.split]))
        #expect(o.selection == SidebarItemSelection())
    }

    @Test func anEmptyAXSelectedRowsClearsAMultiSet() {
        let o = Owner()
        o.outline.setAccessibilitySelectedRows([o.today])
        o.outline.setAccessibilitySelectedRows(o.shown() + [o.child])
        o.outline.setAccessibilitySelectedRows([])
        #expect(o.selected([o.split]))
        #expect(o.selection.items.isEmpty)
    }

    @Test func aRefusingOwnerKeepsTheSelectionAndPostsNothing() {
        let o = Owner()
        o.accepts = false
        o.notes = []
        o.today.setAccessibilitySelected(true)
        o.outline.setAccessibilitySelectedRows([o.pinned, o.today])
        #expect(o.selected([o.split]))
        #expect(o.notes.isEmpty)
    }

    @Test func aBackgroundRefreshKeepsAnAccessibilityMultiSetAndPostsNothing() {
        let o = Owner()
        o.outline.setAccessibilitySelectedRows([o.pinned, o.child])
        o.notes = []
        o.outline.reload(o.entries)
        o.outline.select(o.selection.shown(active: o.active))
        #expect(o.selected([o.pinned, o.child, o.split]))
        #expect(o.notes.isEmpty)
    }

    @Test func aBackgroundRowArrivingAnnouncesOnlyTheRowCount() {
        let o = Owner()
        o.outline.setAccessibilitySelectedRows([o.pinned, o.child])
        o.notes = []
        o.outline.reload(o.entries + [.item(.tab(UUID()), content: Item("Background"), depth: 0, in: nil)])
        o.outline.select(o.selection.shown(active: o.active))
        #expect(o.selected([o.pinned, o.child, o.split]))
        #expect(o.notes == [.rowCountChanged])
    }

    @Test func aHiddenRowIsRefused() {
        let o = Owner()
        let hidden = Item("Hidden")
        hidden.isHidden = true
        o.outline.reload(o.entries + [.item(.tab(UUID()), content: hidden, depth: 0, in: nil)])
        guard let hiddenRow = o.outline.arrangedSubviews.compactMap({ $0 as? SidebarOutlineRow }).first(where: \.isHidden) else {
            Issue.record("the hidden row exists")
            return
        }
        let before = o.requests.count
        hiddenRow.setAccessibilitySelected(true)
        o.outline.setAccessibilitySelectedRows([hiddenRow])
        #expect(o.requests.count == before)
    }

    @Test func aBackgroundRowCanJoinTheMultiSet() {
        let o = Owner()
        let id = SidebarItemReference.tab(UUID())
        o.outline.reload(o.entries + [.item(id, content: Item("Background"), depth: 0, in: nil)])
        guard let extra = o.outline.rows.last else { return }
        let order = o.outline.rows.compactMap { $0.key.base as? SidebarItemReference }
        o.outline.selectsFromAccessibility = { [weak o] wanted in
            guard let o else { return false }
            o.requests.append(wanted)
            guard o.selection.assign(wanted, order: order, active: o.active) else { return false }
            o.outline.select(o.selection.shown(active: o.active))
            return true
        }
        o.outline.setAccessibilitySelectedRows([o.pinned, o.child])
        o.outline.setAccessibilitySelectedRows(o.shown() + [extra])
        #expect(o.selected([o.pinned, o.child, o.split, extra]))
    }

    @Test func aRowThatLeftTheListIsRefused() {
        let o = Owner()
        let id = SidebarItemReference.tab(UUID())
        o.outline.reload(o.entries + [.item(id, content: Item("Background"), depth: 0, in: nil)])
        let extra = o.outline.rows.last!
        o.outline.reload(o.entries)
        let before = o.requests.count
        extra.setAccessibilitySelected(true)
        o.outline.setAccessibilitySelectedRows([extra])
        #expect(o.requests.count == before)
    }
}
