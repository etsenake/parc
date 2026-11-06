import AppKit

///
/// `SplitViewCellState`) and its `SplitViewCellChildrenContainerView`.
///
///
/// frame is that visible background, so every horizontal constant below is
///
struct SidebarSplitCellLayout: Equatable {
    static let cellInset: CGFloat = 8
    ///
    ///
    static let containerInset: CGFloat = 12 - cellInset
    ///
    ///
    static let childPadding: CGFloat = 4
    ///
    static let collapseWidth: CGFloat = 60
    ///
    static let childHeight: CGFloat = 28
    ///
    static let separatorHeight: CGFloat = 16
    /// The cell's own `_closeButton`, a `SidebarCellButton` of 3 × 8 = 24
    ///
    ///
    static let closeSize: CGFloat = 24
    static let closeTrailingInset: CGFloat = 14 - cellInset
    /// While Close shows, the container's extended inset keeps the children
    ///
    ///
    static let closeGap: CGFloat = 4
    static let extendedTrailingInset = closeSize + closeTrailingInset + closeGap
    /// `SplitViewCellCustomInfoView`'s stack uses `HorizontalInsets`
    ///
    ///
    ///
    static let infoLeadingInset: CGFloat = 14 - cellInset
    static let infoTrailingInset: CGFloat = 18
    static let infoIconSlot: CGFloat = 24
    static let infoSpacing: CGFloat = 6
    static var infoTitleInset: CGFloat { infoLeadingInset + infoIconSlot + infoSpacing }
    /// `SplitViewCellItemCountIconView`: at least the 16-point favicon size
    ///
    ///
    static let countIconSize: CGFloat = 16
    static let countIconCornerRadius: CGFloat = 4
    static let countFontSize: CGFloat = 10
    /// A custom icon is drawn at the favicon size (`image(withSize:)` with
    ///
    ///
    /// `SidebarCellConstants.Title.font` (14), as on ordinary rows.
    static let titleFontSize: CGFloat = 14

    var children: [NSRect]
    var separators: [NSRect]
    var close: NSRect?
    /// The custom-info title's trailing edge in the row.
    var infoTitleTrailing: CGFloat

    ///
    /// Close showing, the container's extended inset applies only when the
    /// default width is no more than 60 points; otherwise every child keeps
    /// the default width and only the last ends at the extended inset.
    /// Separator `i` follows child `i`, one device pixel wide, centered in the
    ///
    static func layout(in bounds: NSRect, childCount: Int, showsClose: Bool, pixel: CGFloat = 1) -> SidebarSplitCellLayout {
        let width = bounds.width
        let close = showsClose
            ? NSRect(x: width - closeTrailingInset - closeSize, y: ((bounds.height - closeSize) / 2).rounded(.down),
                     width: closeSize, height: closeSize)
            : nil
        let infoTrailing = (close.map { $0.minX } ?? width + cellInset) - infoTrailingInset
        guard childCount > 0 else { return SidebarSplitCellLayout(children: [], separators: [], close: close, infoTitleTrailing: infoTrailing) }
        let gaps = CGFloat(max(childCount - 1, 0)) * childPadding
        let defaultWidth = (width - 2 * containerInset - gaps) / CGFloat(childCount)
        let trailing = showsClose ? extendedTrailingInset : containerInset
        let extendedWidth = (width - containerInset - trailing - gaps) / CGFloat(childCount)
        let childWidth = showsClose && defaultWidth <= collapseWidth ? extendedWidth : defaultWidth
        let y = ((bounds.height - childHeight) / 2).rounded(.down)
        var x = containerInset
        var children: [NSRect] = []
        for index in 0..<childCount {
            let last = index == childCount - 1
            let w = last && showsClose ? width - trailing - x : childWidth
            children.append(NSRect(x: x, y: y, width: max(0, w), height: childHeight))
            x += w + childPadding
        }
        let separatorY = ((bounds.height - separatorHeight) / 2).rounded(.down)
        let separators = children.dropLast().map {
            NSRect(x: $0.maxX + childPadding / 2 - pixel / 2, y: separatorY, width: pixel, height: separatorHeight)
        }
        return SidebarSplitCellLayout(children: children, separators: separators, close: close, infoTitleTrailing: infoTrailing)
    }

    ///
    ///
    /// pinned split deselects while any child is presented (its children
    ///
    /// otherwise. (A Favorite deselects; Favorites are tiles, not rows.)
    enum CloseAction: Equatable { case deselect, close }
    static func closeAction(today: Bool, anyChildPresented: Bool) -> CloseAction {
        !today && anyChildPresented ? .deselect : .close
    }
    /// The cell builder maps close to `SplitViewCellStrings.archiveTooltip`
    ///
    /// window never archives, so its Close keeps the close wording, as Parc's
    /// private rows say Close Tab.
    static func closeTitle(_ action: CloseAction, privateWindow: Bool) -> String {
        action == .close && !privateWindow ? "Archive this item" : "Close this item"
    }

    /// The cell gets no close configuration only for the current Today split
    ///
    ///
    static func splitHasClose(today: Bool, current: Bool, customInfo: Bool) -> Bool {
        customInfo || !(current && today)
    }

    /// `ChildItemState.closeButtonConfiguration` is set only when the split
    /// gives it up (above); the child's own Close then follows group hover.
    static func childCloseAvailable(today: Bool, current: Bool, customInfo: Bool) -> Bool {
        !customInfo && !splitHasClose(today: today, current: current, customInfo: customInfo)
    }

    ///
    ///
    static func usesCustomInfo(title: String?, hasIcon: Bool, editing: Bool) -> Bool {
        editing || !(title ?? "").isEmpty || hasIcon
    }

    /// `SplitViewCellStrings.defaultTitle(numberOfItems:)` ("%@ Tabs",
    ///
    static func defaultTitle(count: Int) -> String { "\(count) Tabs" }

    ///
    ///
    static func separatorColor(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.15) : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.15)
    }

    ///
    /// installed BaseAssets ForegroundSecondary.
    static func customIconTint(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.5) : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5)
    }

    /// The count icon's background is the palette's `cutoutColor` at 0.8 and
    /// its label the palette's `maxContrastColor` (palette +0x130 and +0x70,
    ///
    static let countBackgroundAlpha: CGFloat = 0.8
}
