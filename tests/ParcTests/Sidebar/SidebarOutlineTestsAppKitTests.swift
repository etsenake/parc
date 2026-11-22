import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarOutlineTestsAppKitTests {
    private final class StockSource: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        static let header = "header" as NSString
        static let tab = "tab" as NSString
        var asked = 0
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { item == nil ? 2 : 0 }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { index == 0 ? Self.header : Self.tab }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? NSString) == Self.header }
        func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool { asked += 1; return true }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? { NSView() }
    }

    @MainActor private final class Stock {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let outline = NSOutlineView()
        let source = StockSource()
        typealias Get = @convention(c) (NSObject, Selector, NSString) -> Unmanaged<AnyObject>?
        typealias Settable = @convention(c) (NSObject, Selector, NSString) -> Bool
        typealias Put = @convention(c) (NSObject, Selector, AnyObject, NSString) -> Void

        init() {
            window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            let column = NSTableColumn(identifier: .init("item"))
            outline.addTableColumn(column)
            outline.outlineTableColumn = column
            outline.dataSource = source
            outline.delegate = source
            scroll.documentView = outline
            window.contentView = scroll
            outline.reloadData()
            outline.layoutSubtreeIfNeeded()
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        var rows: [NSObject] {
            (outline.perform(NSSelectorFromString("accessibilityRows"))?.takeUnretainedValue() as? NSArray)?.compactMap { $0 as? NSObject } ?? []
        }

        func send<T>(_ object: NSObject, _ name: String, as type: T.Type) -> T { unsafeBitCast(object.method(for: NSSelectorFromString(name)), to: type) }

        func value(_ row: NSObject, _ name: String) -> Any? {
            send(row, "accessibilityAttributeValue:", as: Get.self)(row, NSSelectorFromString("accessibilityAttributeValue:"), name as NSString)?.takeUnretainedValue()
        }

        func settable(_ row: NSObject) -> Bool {
            send(row, "accessibilityIsAttributeSettable:", as: Settable.self)(row, NSSelectorFromString("accessibilityIsAttributeSettable:"), "AXDisclosing")
        }
    }

    @Test func appKitListsTheChildlessExpandableHeaderCollapsedWithAXDisclosingSettableAndATabRowNot() {
        let stock = Stock()
        let rows = stock.rows
        #expect(rows.count == 2)
        #expect((stock.value(rows[0], "AXDisclosing") as? Bool) == false)
        #expect(stock.settable(rows[0]))
        #expect(((stock.value(rows[0], "AXDisclosedRows") as? [Any]) ?? [0]).isEmpty)
        #expect(!stock.settable(rows[1]))
    }

    @Test func settingAXDisclosingAsksTheDelegateAndLeavesTheChildlessHeaderCollapsed() {
        let stock = Stock()
        let rows = stock.rows
        stock.send(rows[0], "accessibilitySetValue:forAttribute:", as: Stock.Put.self)(rows[0], NSSelectorFromString("accessibilitySetValue:forAttribute:"),
                                                                                          NSNumber(value: true), "AXDisclosing")
        #expect(stock.source.asked > 0)
        #expect(!stock.outline.isItemExpanded(StockSource.header))
        #expect(stock.outline.numberOfRows == 2)
        #expect((stock.value(rows[0], "AXDisclosing") as? Bool) == false)
    }
}
