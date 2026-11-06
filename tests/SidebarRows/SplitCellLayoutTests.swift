import AppKit

///
@main struct SplitCellLayoutTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
        func rgba(_ color: NSColor) -> [CGFloat] {
            let c = color.usingColorSpace(.sRGB)!
            return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { ($0 * 1000).rounded() / 1000 }
        }
        typealias L = SidebarSplitCellLayout

        // Recovered constants, less the 8-point visible-background inset.
        check(L.containerInset == 4 && L.childPadding == 4 && L.collapseWidth == 60, "Container insets 12, padding 4, collapse 60")
        check(L.childHeight == 28 && L.separatorHeight == 16, "Child height 28, separator 28 − 12")
        check(L.closeSize == 24 && L.closeTrailingInset == 6 && L.extendedTrailingInset == 34, "Close 24 at 14, extended inset 42")
        check(L.infoLeadingInset == 6 && L.infoTitleInset == 36 && L.infoTrailingInset == 18, "Custom info 14 / 24 + 6 / 18")
        check(L.countIconSize == 16 && L.countIconCornerRadius == 4, "Count icon")

        // Two children at rest: equal widths, 4-point gap, 28-point centered.
        let row = NSRect(x: 0, y: 0, width: 212, height: 36)
        let rest = L.layout(in: row, childCount: 2, showsClose: false, pixel: 0.5)
        check(rest.children == [NSRect(x: 4, y: 4, width: 100, height: 28), NSRect(x: 108, y: 4, width: 100, height: 28)], "Rest children")
        check(rest.separators.count == 1 && near(rest.separators[0].minX, 105.75) && rest.separators[0].width == 0.5
              && rest.separators[0].minY == 10 && rest.separators[0].height == 16, "One device pixel separator centered in the gap")
        check(rest.close == nil && rest.infoTitleTrailing == 202, "No Close; custom title ends 10 inside")

        // Hovered with Close: wide children keep their width, the last ends at the extended inset.
        let hovered = L.layout(in: row, childCount: 2, showsClose: true)
        check(hovered.close == NSRect(x: 182, y: 6, width: 24, height: 24), "Split Close 6 inside the trailing edge")
        check(hovered.children[0].width == 100 && hovered.children[1].minX == 108 && hovered.children[1].maxX == 178,
              "Only the last child yields to Close")
        check(near(hovered.separators[0].minX, 105.5), "Separator follows the first child")
        check(hovered.infoTitleTrailing == 164, "Custom title ends 18 before Close")

        // Narrow children (default width ≤ 60) take the extended equal width.
        let narrow = NSRect(x: 0, y: 0, width: 140, height: 36)
        let collapsed = L.layout(in: narrow, childCount: 3, showsClose: true)
        let extended = (140.0 - 4 - 34 - 8) / 3
        check(collapsed.children.allSatisfy { near($0.width, extended) } && near(collapsed.children[2].maxX, 106),
              "Narrow children share the extended width")
        let narrowRest = L.layout(in: narrow, childCount: 3, showsClose: false)
        check(narrowRest.children.allSatisfy { near($0.width, (140.0 - 8 - 8) / 3) } && narrowRest.separators.count == 2,
              "Narrow children at rest share the default width")
        let boundary = L.layout(in: NSRect(x: 0, y: 0, width: 132, height: 36), childCount: 2, showsClose: true)
        check(boundary.children[0].width == (132.0 - 4 - 34 - 4) / 2, "A default width of exactly 60 takes the extended width")
        let wider = L.layout(in: NSRect(x: 0, y: 0, width: 134, height: 36), childCount: 2, showsClose: true)
        check(wider.children[0].width == 61 && wider.children[1].maxX == 100, "Above 60 the first child keeps its default width")
        check(L.layout(in: row, childCount: 0, showsClose: true).children.isEmpty, "No children, no frames")
        check(L.layout(in: row, childCount: 1, showsClose: false).separators.isEmpty, "One child, no separator")

        // Close producers: the current Today split gives Close to its children.
        check(!L.splitHasClose(today: true, current: true, customInfo: false)
              && L.childCloseAvailable(today: true, current: true, customInfo: false), "Current Today split: child Close")
        check(L.splitHasClose(today: true, current: false, customInfo: false)
              && !L.childCloseAvailable(today: true, current: false, customInfo: false), "Other Today split: its own Close")
        check(L.splitHasClose(today: false, current: true, customInfo: false)
              && !L.childCloseAvailable(today: false, current: true, customInfo: false), "Pinned split: its own Close")
        check(L.splitHasClose(today: true, current: true, customInfo: true)
              && !L.childCloseAvailable(today: true, current: true, customInfo: true), "Custom info keeps its own Close")
        // closeButtonAction case 6 and the builder's tooltip mapping.
        check(L.closeAction(today: true, anyChildPresented: true) == .close
              && L.closeAction(today: true, anyChildPresented: false) == .close, "Today split closes")
        check(L.closeAction(today: false, anyChildPresented: true) == .deselect, "Pinned split with a presented child deselects")
        check(L.closeAction(today: false, anyChildPresented: false) == .close, "Pinned split with nothing presented closes")
        check(L.closeTitle(.close, privateWindow: false) == "Archive this item"
              && L.closeTitle(.deselect, privateWindow: false) == "Close this item"
              && L.closeTitle(.close, privateWindow: true) == "Close this item", "Tooltips; private windows never archive")

        // Custom-info producer and default title.
        check(!L.usesCustomInfo(title: nil, hasIcon: false, editing: false)
              && !L.usesCustomInfo(title: "", hasIcon: false, editing: false), "No title or icon: child items")
        check(L.usesCustomInfo(title: "Work", hasIcon: false, editing: false)
              && L.usesCustomInfo(title: nil, hasIcon: true, editing: false)
              && L.usesCustomInfo(title: nil, hasIcon: false, editing: true), "Title, icon or editing: custom info")
        check(L.defaultTitle(count: 3) == "3 Tabs", "Default title")

        // Installed BaseAssets SidebarSeparator and ForegroundSecondary.
        check(rgba(L.separatorColor(dark: false)) == [0, 0, 0, 0.15] && rgba(L.separatorColor(dark: true)) == [1, 1, 1, 0.15],
              "SidebarSeparator light / dark")
        check(rgba(L.customIconTint(dark: false)) == [0, 0, 0, 0.5] && rgba(L.customIconTint(dark: true)) == [1, 1, 1, 0.5],
              "ForegroundSecondary light / dark")
        check(L.countBackgroundAlpha == 0.8, "Count background alpha")

        // The cell's fills come from the shared CellSelectionStateView model.
        let selectedCell = SidebarRowAppearance(current: true, hovered: true)
        check(selectedCell.fill == .current && selectedCell.showsShadow, "Current split takes the current fill and shadow")
        check(SidebarRowAppearance(hovered: true).fill == .hovered, "Hovered split takes SidebarItemBackground")
        check(SidebarRowAppearance(multiSelected: true, hovered: true).fill == .multiSelected, "Multi-selected split")
        check(SidebarRowAppearance(keyDragged: true).fill == .current && !SidebarRowAppearance(keyDragged: true).showsShadow,
              "Dragged split takes the current fill without the shadow")
        print("PASS: \(checks) split cell layout assertions")
    }
}
