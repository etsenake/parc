import AppKit

@main @MainActor struct PinnedOutlineHeaderTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    enum Control: Hashable { case header, divider }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        var toggles = 0
        let header = NSView(), pinnedView = NSView(), todayView = NSView()
        let pinnedID = SidebarItemReference.tab(UUID()), todayID = SidebarItemReference.tab(UUID())
        func entries(expanded: Bool, pinned: Bool) -> [SidebarOutlineEntry] {
            [.pinnedHeader(Control.header, content: header, expanded: expanded) { toggles += 1 }]
                + (pinned ? [.item(pinnedID, content: pinnedView, depth: 0, in: nil)] : [])
                + [.init(key: Control.divider, content: NSView(), row: SidebarChromeLayout.TablistSlot.sectionDivider.row),
                   .item(todayID, content: todayView, depth: 0, in: nil)]
        }
        let entry = entries(expanded: true, pinned: true)[0]
        check(entry.row == .accessory(height: SidebarChromeLayout.pinnedSectionHeaderHeight) && entry.content === header && !entry.isItem,
              "the visible header is a content row in its own slot, not a selectable item")
        check(entry.expanded == true && entry.toggle != nil && !entry.expandableWithoutChildren, "the header carries real disclosure")

        let outline = SidebarOutlineView(frame: NSRect(x: 0, y: 0, width: 212, height: 400))
        outline.reload(entries(expanded: true, pinned: true))
        func row(_ key: AnyHashable) -> SidebarOutlineRow? { outline.rows.first { $0.key == key } }
        let headerRow = row(Control.header)!
        check(headerRow.isAccessibilityDisclosed() && headerRow.accessibilityDisclosureLevel() == 0, "an open Pinned reads as disclosed")
        check(headerRow.isAccessibilitySelectorAllowed(#selector(NSView.setAccessibilityDisclosed(_:))), "VoiceOver can fold Pinned from its row")
        headerRow.setAccessibilityDisclosed(false)
        check(toggles == 1, "setting AXDisclosing runs the section toggle")
        headerRow.setAccessibilityDisclosed(true)
        check(toggles == 1, "asking for the current state does nothing")
        let frames = outline.rowFrames()
        check(frames[Control.header]?.height == 27 && frames[pinnedID]?.minY == 27, "pinned rows begin under the 26-point header")

        outline.reload(entries(expanded: false, pinned: false))
        check(!row(Control.header)!.isAccessibilityDisclosed(), "a folded Pinned reads as collapsed")
        check(row(pinnedID) == nil && outline.rows.map(\.key) == [AnyHashable(Control.header), AnyHashable(Control.divider), AnyHashable(todayID)],
              "folding removes the pinned rows and keeps Today below the header")
        check(outline.itemFrame(for: Control.header) == NSRect(x: 0, y: 0, width: 212, height: 26),
              "the folded header still reports its frame for drops")
        let collapsedFrames = outline.rowFrames()
        outline.reload(entries(expanded: true, pinned: true))
        check(outline.rowFrames()[todayID]!.minY > collapsedFrames[todayID]!.minY, "unfolding pushes Today back down")
        check(outline.rows.allSatisfy { !($0.accessibilityDisclosedByRow() as AnyObject? === headerRow) },
              "pinned rows stay the header's siblings at level 0")
        print("Pinned outline header checks passed: \(count)")
    }
}
