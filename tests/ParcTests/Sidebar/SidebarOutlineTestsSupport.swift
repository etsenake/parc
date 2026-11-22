import AppKit
@testable import Parc
@testable import ParcCore

@MainActor
enum SidebarOutlineTestsSupport {
    final class PressCounter { var count = 0 }

    final class TabItem: NSView {
        let counter: PressCounter
        init(_ title: String, _ counter: PressCounter = PressCounter()) {
            self.counter = counter
            super.init(frame: .zero)
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityRoleDescription("Tab")
            setAccessibilityTitle(title)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func accessibilityPerformPress() -> Bool { counter.count += 1; return true }
    }

    final class FolderItem: NSView {
        var toggles = 0
        let counter: PressCounter
        init(_ name: String, expanded: Bool, _ counter: PressCounter = PressCounter()) {
            self.counter = counter
            super.init(frame: .zero)
            setAccessibilityElement(true)
            setAccessibilityRole(.disclosureTriangle)
            setAccessibilityLabel(name)
            setAccessibilityValue(expanded ? 1 : 0)
        }
        required init?(coder: NSCoder) { fatalError() }
        func activate() { toggles += 1 }
        override func accessibilityPerformPress() -> Bool { counter.count += 1; activate(); return true }
    }

    final class SplitItem: NSView {
        let counter: PressCounter
        let tabs: [TabItem]
        init(_ counter: PressCounter = PressCounter()) {
            self.counter = counter
            tabs = [TabItem("Left", counter), TabItem("Right", counter)]
            super.init(frame: .zero)
            tabs.forEach(addSubview)
            setAccessibilityElement(true)
            setAccessibilityRole(.group)
            setAccessibilityLabel("Split View, 2 tabs")
        }
        required init?(coder: NSCoder) { fatalError() }
        override func accessibilityPerformPress() -> Bool { counter.count += 1; return true }
        override func layout() {
            super.layout()
            for (index, tab) in tabs.enumerated() { tab.frame = NSRect(x: CGFloat(index) * bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height) }
        }
    }

    final class FocusOwner: NSView {
        var isPresented = true
        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { super.canBecomeKeyView && isPresented }
    }

    enum Control: Hashable { case header, divider, heading, newTab }

    typealias Slot = SidebarChromeLayout.TablistSlot

    static func same(_ lhs: Any?, _ rhs: AnyObject?) -> Bool { (lhs as AnyObject?) === rhs }

    static func frame(_ view: NSView) -> NSRect { NSAccessibility.screenRect(fromView: view, rect: view.bounds) }

    @MainActor final class Listing {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 240, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        let root = FocusOwner(frame: NSRect(x: 0, y: 0, width: 240, height: 200))
        let scroll = NSScrollView(frame: NSRect(x: 8, y: 0, width: 224, height: 200))
        let outline = SidebarOutlineView()
        let counter = PressCounter()
        let pinnedID = SidebarItemReference.tab(UUID())
        let childID = SidebarItemReference.tab(UUID())
        let splitID = SidebarItemReference.split(UUID())
        let todayID = SidebarItemReference.tab(UUID())
        let workID = UUID()
        let archiveID = UUID()
        let pinned: TabItem
        let folder: FolderItem
        let child: TabItem
        let subfolder: FolderItem
        let split: SplitItem
        let today: TabItem
        let divider = NSBox()
        let clear = ActionButton("↓ Clear")
        let dividerCell = NSView()
        let newTab = ActionButton("New Tab", symbol: "plus")
        var workKey: AnyHashable { AnyHashable(SidebarItemReference.folder(workID)) }
        var archiveKey: AnyHashable { AnyHashable(SidebarItemReference.folder(archiveID)) }
        let header = SidebarOutlineEntry.pinnedHeader(Control.header)

        init() {
            window.isReleasedWhenClosed = false
            window.contentView = root
            root.addSubview(scroll)
            outline.focusOwner = root
            scroll.documentView = outline
            pinned = TabItem("Pinned", counter)
            folder = FolderItem("Work", expanded: true, counter)
            child = TabItem("Child", counter)
            subfolder = FolderItem("Archive", expanded: false, counter)
            split = SplitItem(counter)
            today = TabItem("Today", counter)
            divider.boxType = .separator
            dividerCell.addSubview(divider)
            dividerCell.addSubview(clear)
            reload()
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func entries(folderExpanded: Bool = true, pinned pinnedView: NSView? = nil) -> [SidebarOutlineEntry] {
            var list: [SidebarOutlineEntry] = [
                header,
                .item(pinnedID, content: pinnedView ?? pinned, depth: 0, in: nil),
                .folder(workID, content: folder, depth: 0, in: nil, expanded: folderExpanded, toggle: { [folder] in folder.activate() })]
            if folderExpanded {
                list += [.item(childID, content: child, depth: 1, in: workID),
                         .folder(archiveID, content: subfolder, depth: 1, in: workID, expanded: false, toggle: { [subfolder] in subfolder.activate() })]
            }
            return list + [.item(splitID, content: split, depth: 0, in: nil),
                           SidebarOutlineEntry(key: Control.divider, content: dividerCell, row: Slot.sectionDivider.row),
                           SidebarOutlineEntry(key: Control.newTab, content: newTab, row: Slot.newTab.row),
                           .item(todayID, content: today, depth: 0, in: nil)]
        }

        func layout() {
            outline.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(0, outline.contentHeight))
            outline.layoutSubtreeIfNeeded()
        }

        func reload(_ list: [SidebarOutlineEntry]? = nil) {
            outline.reload(list ?? entries())
            layout()
        }

        var rows: [SidebarOutlineRow] { outline.rows }
        var byKey: [AnyHashable: SidebarOutlineRow] { Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) }) }
        func row(_ key: AnyHashable) -> SidebarOutlineRow { byKey[key]! }
        func cellChildren(_ key: AnyHashable) -> [Any] { byKey[key]?.cell.accessibilityChildren() ?? [] }
        func selectedRows() -> [Any] { outline.accessibilitySelectedRows() ?? [] }
    }
}
