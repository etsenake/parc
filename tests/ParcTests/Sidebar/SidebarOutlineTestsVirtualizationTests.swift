import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarOutlineTestsVirtualizationTests {
    private typealias Support = SidebarOutlineTestsSupport
    private typealias TabItem = Support.TabItem
    private typealias FolderItem = Support.FolderItem
    private typealias Listing = Support.Listing

    @MainActor private final class Long {
        let l = Listing()
        var built = 0
        var released: [AnyHashable] = []
        var rows: [SidebarOutlineRow] { l.outline.rows }

        init() {
            l.outline.releaseContent = { [weak self] key, _ in self?.released.append(key) }
            var long: [SidebarOutlineEntry] = [l.header]
            for index in 0..<60 {
                let key = SidebarItemReference.tab(UUID())
                long.append(index == 40
                    ? .folder(UUID(), depth: 0, in: nil, expanded: false, toggle: {}) { [weak self] in self?.built += 1; return FolderItem("Folder", expanded: false) }
                    : .item(key, depth: index % 2, in: nil) { [weak self] in
                        self?.built += 1
                        let item = TabItem("Row \(index)")
                        item.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Close Tab") { true }])
                        return item
                    })
            }
            l.scroll.contentView.scroll(to: .zero)
            l.scroll.reflectScrolledClipView(l.scroll.contentView)
            l.reload(long)
        }
    }

    @Test func everyRowIsListedBuiltOrNot() {
        let long = Long()
        #expect(long.rows.count == 61)
        #expect((long.l.outline.accessibilityRows() ?? []).count == 61)
    }

    @Test func onlyRowsNearTheVisibleAreaBuildViewsAndJoinTheWindow() {
        let long = Long()
        let attached = long.rows.filter { $0.superview === long.l.outline }
        #expect(long.built > 0)
        #expect(long.built < 20)
        #expect(attached.count == long.built + 1)
    }

    @Test func aRowFarFromTheVisibleAreaHasNoView() {
        let long = Long()
        #expect(long.rows[52].superview == nil)
        #expect(long.rows[52].cell.content == nil)
    }

    @Test func aRowWithoutAViewKeepsItsIndexDepthDisclosureParentAndFrame() {
        let long = Long()
        let far = long.rows[52]
        #expect(far.accessibilityIndex() == 52)
        #expect(far.accessibilityDisclosureLevel() == 1)
        #expect(!far.isAccessibilityDisclosed())
        #expect(Support.same(far.accessibilityParent(), long.l.outline))
        #expect(far.accessibilityFrame() != .zero)
    }

    @Test func aCollapsedFolderRowWithoutAViewIsListedCollapsedItsDisclosureSettable() {
        let long = Long()
        let folderRow = long.rows[41]
        #expect(folderRow.superview == nil)
        #expect(!folderRow.isAccessibilityDisclosed())
        #expect(folderRow.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilityDisclosed(_:))))
    }

    @Test func aRowWithoutAViewIsSelectedLikeAnyOther() {
        let long = Long()
        let far = long.rows[52]
        long.l.outline.select([far.key.base as! SidebarItemReference])
        #expect(far.isAccessibilitySelected())
        #expect((long.l.outline.accessibilitySelectedRows() ?? []).count == 1)
    }

    @Test func askedForItsChildrenARowTakesItsViewWithItsLabelAndActionsAtItsPlaceInTheWindow() {
        let long = Long()
        let far = long.rows[52]
        let content = (far.accessibilityChildren()?.first as? NSView)?.accessibilityChildren()?.first as? TabItem
        #expect(content?.accessibilityTitle() == "Row 51")
        #expect(content?.accessibilityCustomActions()?.first?.name == "Close Tab")
        #expect(far.superview === long.l.outline)
        #expect(content?.window === long.l.window)
    }

    @Test func movingTheAccessibilityFocusToARowWithoutAViewScrollsItInAndBuildsIt() {
        let long = Long()
        let farther = long.rows[58]
        #expect(farther.superview == nil)
        #expect(!long.l.scroll.contentView.bounds.intersects(farther.frame))
        farther.setAccessibilityFocused(true)
        #expect(long.l.scroll.contentView.bounds.contains(farther.frame))
        #expect(farther.superview === long.l.outline)
        #expect(farther.cell.content != nil)
    }

    @Test func rowsTheScrollLeavesFarBehindLetGoOfTheirViews() {
        let long = Long()
        long.rows[58].setAccessibilityFocused(true)
        #expect(long.released.contains(long.rows[1].key))
        #expect(long.rows[1].cell.content == nil)
        #expect(long.rows[1].superview == nil)
    }
}
