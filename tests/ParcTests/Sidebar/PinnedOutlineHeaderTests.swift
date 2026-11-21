import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct PinnedOutlineHeaderTests {
    private enum Control: Hashable { case header, divider }

    @MainActor private final class Outline {
        let outline = SidebarOutlineView(frame: NSRect(x: 0, y: 0, width: 212, height: 400))
        let header = NSView()
        let pinnedView = NSView()
        let todayView = NSView()
        let pinnedID = SidebarItemReference.tab(UUID())
        let todayID = SidebarItemReference.tab(UUID())
        var toggles = 0

        func entries(expanded: Bool, pinned: Bool) -> [SidebarOutlineEntry] {
            [.pinnedHeader(Control.header, content: header, expanded: expanded) { [weak self] in self?.toggles += 1 }]
                + (pinned ? [.item(pinnedID, content: pinnedView, depth: 0, in: nil)] : [])
                + [.init(key: Control.divider, content: NSView(), row: SidebarChromeLayout.TablistSlot.sectionDivider.row),
                   .item(todayID, content: todayView, depth: 0, in: nil)]
        }

        func reload(expanded: Bool, pinned: Bool) { outline.reload(entries(expanded: expanded, pinned: pinned)) }
        func row(_ key: AnyHashable) -> SidebarOutlineRow? { outline.rows.first { $0.key == key } }
    }

    @Test func theVisibleHeaderTakesAStandardRowSlotWithoutBecomingASelectableItem() {
        let o = Outline()
        let entry = o.entries(expanded: true, pinned: true)[0]
        #expect(entry.row == .item)
        #expect(entry.content === o.header)
        #expect(!entry.isItem)
    }

    @Test func theHeaderCarriesRealDisclosure() {
        let o = Outline()
        let entry = o.entries(expanded: true, pinned: true)[0]
        #expect(entry.expanded == true)
        #expect(entry.toggle != nil)
        #expect(!entry.expandableWithoutChildren)
    }

    @Test func anOpenPinnedReadsAsDisclosed() {
        let o = Outline()
        o.reload(expanded: true, pinned: true)
        let row = o.row(Control.header)!
        #expect(row.isAccessibilityDisclosed())
        #expect(row.accessibilityDisclosureLevel() == 0)
    }

    @Test func voiceOverCanFoldPinnedFromItsRow() {
        let o = Outline()
        o.reload(expanded: true, pinned: true)
        #expect(o.row(Control.header)!.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilityDisclosed(_:))))
    }

    @Test func settingDisclosingRunsTheSectionToggle() {
        let o = Outline()
        o.reload(expanded: true, pinned: true)
        o.row(Control.header)!.setAccessibilityDisclosed(false)
        #expect(o.toggles == 1)
    }

    @Test func askingForTheCurrentStateDoesNothing() {
        let o = Outline()
        o.reload(expanded: true, pinned: true)
        let row = o.row(Control.header)!
        row.setAccessibilityDisclosed(false)
        row.setAccessibilityDisclosed(true)
        #expect(o.toggles == 1)
    }

    @Test func theHeadersSlotIsExactlyAsTallAsThePinnedRowUnderIt() {
        let o = Outline()
        o.reload(expanded: true, pinned: true)
        let frames = o.outline.rowFrames()
        let slot = SidebarChromeLayout.tablistCellHeight + SidebarChromeLayout.tablistIntercellSpacing
        #expect(frames[Control.header]?.height == slot)
        #expect(frames[o.pinnedID]?.minY == slot)
        #expect(frames[o.pinnedID]?.height == slot)
    }

    @Test func theHeadersViewSitsInTheRowSlotLikeAnItems() {
        let o = Outline()
        o.reload(expanded: true, pinned: true)
        #expect(o.outline.itemFrame(for: Control.header)?.height == o.outline.itemFrame(for: o.pinnedID)?.height)
        #expect(o.outline.itemFrame(for: Control.header)?.minY == SidebarChromeLayout.TablistRow.item.viewSpan?.minY)
    }

    @Test func theHeadersWholeSlotIsReportedForDropsAndMeetsTheNextRow() {
        let o = Outline()
        o.reload(expanded: true, pinned: true)
        let frames = o.outline.rowFrames()
        #expect(o.outline.rowFrame(for: Control.header) == frames[Control.header])
        #expect(o.outline.rowFrame(for: Control.header)!.contains(o.outline.itemFrame(for: Control.header)!))
        #expect(o.outline.rowFrame(for: Control.header)!.maxY == frames[o.pinnedID]!.minY)
    }

    @Test func aFoldedPinnedReadsAsCollapsed() {
        let o = Outline()
        o.reload(expanded: false, pinned: false)
        #expect(!o.row(Control.header)!.isAccessibilityDisclosed())
    }

    @Test func foldingRemovesThePinnedRowsAndKeepsTodayBelowTheHeader() {
        let o = Outline()
        o.reload(expanded: false, pinned: false)
        #expect(o.row(o.pinnedID) == nil)
        #expect(o.outline.rows.map(\.key) == [AnyHashable(Control.header), AnyHashable(Control.divider), AnyHashable(o.todayID)])
    }

    @Test func theFoldedHeaderStillReportsItsFrameForDrops() {
        let o = Outline()
        o.reload(expanded: false, pinned: false)
        let span = SidebarChromeLayout.TablistRow.item.viewSpan!
        #expect(o.outline.itemFrame(for: Control.header) == NSRect(x: 0, y: span.minY, width: 212, height: span.height))
    }

    @Test func unfoldingPushesTodayBackDown() {
        let o = Outline()
        o.reload(expanded: false, pinned: false)
        let collapsed = o.outline.rowFrames()
        o.reload(expanded: true, pinned: true)
        #expect(o.outline.rowFrames()[o.todayID]!.minY > collapsed[o.todayID]!.minY)
    }

    @Test func pinnedRowsStayTheHeadersSiblingsAtLevelZero() {
        let o = Outline()
        o.reload(expanded: true, pinned: true)
        let headerRow = o.row(Control.header)!
        #expect(o.outline.rows.allSatisfy { !($0.accessibilityDisclosedByRow() as AnyObject? === headerRow) })
    }
}
