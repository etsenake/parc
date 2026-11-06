import CoreGraphics

///
///
///
///
///
enum SidebarChromeLayout {
    /// SidebarHeaderView's narrow width class starts below 212 points
    ///
    static let narrowWidth: CGFloat = 212

    /// The header stack sits 4 points down; its first row is 40 points tall.
    static let headerTop: CGFloat = 4
    static let navigationRowHeight: CGFloat = 40
    /// The button stack spans 8 + 5 points from the leading edge to 6 from the trailing edge.
    static let navigationLeading: CGFloat = 13
    static let navigationTrailing: CGFloat = 6
    ///
    ///
    static let windowButtonMargin: CGFloat = 4
    /// The command bar container is inset 8 points and pads its 36-point field 2 points down.
    static let fieldInset: CGFloat = 8
    static let fieldTop: CGFloat = headerTop + navigationRowHeight + 2
    static let fieldHeight: CGFloat = 36
    ///
    static let addressFontSize: CGFloat = 13
    ///
    /// leading constraint was not recovered; this places the ink 13.5 points
    ///
    static let addressTextIndent: CGFloat = 12
    /// The header ends below the field; the App Tray follows directly.
    static let headerBottom: CGFloat = fieldTop + fieldHeight
    ///
    /// bottom inset while the App Tray is empty, its empty state dismissed and
    ///
    ///
    static let headerBottomSpacing: CGFloat = 5

    /// The App Tray starts at the header's end and the Space's page follows it
    ///
    /// A collapsed tray takes no height and the header keeps its 5-point
    /// bottom inset unless the Space header shows; the empty state's tray
    /// takes none. In the page the tablist starts at the page's top, or below
    ///
    static func tablistTop(trayHeight: CGFloat, spaceHeader: Bool = false, hasFavorites: Bool = false) -> CGFloat {
        spaceHeader ? SpaceHeader.top(trayHeight: trayHeight, hasFavorites: hasFavorites) + SpaceHeader.height
            : pageTop(trayHeight: trayHeight, spaceHeader: false)
    }

    /// The Space's page (SidebarSpaceViewController's view): directly below a
    /// tray with height, else below the header and its bottom inset.
    static func pageTop(trayHeight: CGFloat, spaceHeader: Bool) -> CGFloat {
        headerBottom + (trayHeight > 0 ? trayHeight : spaceHeader ? 0 : headerBottomSpacing)
    }

    ///
    ///
    ///
    ///
    /// edges with a height of at least 36, its top 8 below the view's top
    ///
    ///
    ///
    ///
    /// view's top.
    enum SpaceHeader {
        static let height: CGFloat = 36
        static let topPadding: CGFloat = 8
        ///
        ///
        ///
        ///
        static let inset: CGFloat = 14
        static let iconSide: CGFloat = 24
        static let spacing: CGFloat = 4
        ///
        static let fontSize: CGFloat = 13

        ///
        ///
        /// `editButtonWidthConstraint` is 24 while it shows, 30 while the
        ///
        ///
        /// after the name stay.
        static let editButtonHeight: CGFloat = 24
        static func editButtonWidth(shown: Bool, editing: Bool) -> CGFloat {
            shown ? (editing ? 30 : 24) : 0
        }

        /// `(isEditing || isHovered) && canShowHeaderButtonsIfPossible`
        ///
        /// ViewState `displayHeaderButtonsWhenPossible`, read as the window
        /// layout's `.spaces` presentation [I].
        static func showsEditButton(editing: Bool, hovered: Bool, canShowHeaderButtons: Bool) -> Bool {
            (editing || hovered) && canShowHeaderButtons
        }

        /// The header's hover sink (`$isHovered.removeDuplicates()`,
        ///
        /// the header becomes hovered and with no delay once it is not
        ///
        /// again, so a pointer that leaves within 0.1 s shows nothing.
        static func editButtonHoverDelay(hovered: Bool) -> Double { hovered ? 0.1 : 0 }
        ///
        ///
        static let editButtonFadeDuration: Double = 0.1

        ///
        ///
        ///
        ///
        /// StandardWindowState.sidebarContext is .incognito), and true when
        /// the setting showSpaceHeaderOnSingleUnnamedSpaces is on (the
        ///
        /// case 0x4d), when the window has two or more Spaces (the count of
        ///
        /// title (+0x18) or a custom icon (+0x38 ≠ 0xff).
        static func isShown(spaceCount: Int, titled: Bool, customIcon: Bool, privateWindow: Bool,
                            showOnSingleUnnamedSpace: Bool) -> Bool {
            !privateWindow && (showOnSingleUnnamedSpace || spaceCount >= 2 || titled || customIcon)
        }

        ///
        /// only in a menu built for the sidebar (the header's menu passes
        ///
        /// it has no title and no custom icon, that is exactly when the setting
        /// decides the header. "Hide Space Header" while the setting shows it,
        /// else "Show Space Header"; the item flips the setting.
        static func toggleTitle(spaceCount: Int, titled: Bool, customIcon: Bool, showOnSingleUnnamedSpace: Bool) -> String? {
            guard spaceCount == 1, !titled, !customIcon else { return nil }
            return showOnSingleUnnamedSpace ? "Hide Space Header" : "Show Space Header"
        }

        /// An untitled Space's placeholder: "Space " with its 1-based position
        /// in the window's Spaces appended, localized as a whole, or "Space"
        ///
        static func placeholderTitle(position: Int?) -> String {
            position.map { "Space \($0 + 1)" } ?? "Space"
        }

        /// The header's top in the sidebar.
        static func top(trayHeight: CGFloat, hasFavorites: Bool) -> CGFloat {
            pageTop(trayHeight: trayHeight, spaceHeader: true) + (hasFavorites ? 0 : topPadding)
        }

        struct Frames: Equatable {
            var icon: CGRect?
            var title: CGRect
            var editButton: CGRect
        }

        /// The stack's views in a header `width` wide: the icon (hidden
        ///
        /// button `editButtonWidth` wide at the trailing inset, each centred
        /// vertically; the field ends 4 before the button, which NSStackView
        /// keeps arranged at width 0 [C].
        static func frames(width: CGFloat, icon: Bool, titleHeight: CGFloat, editButtonWidth: CGFloat = 0) -> Frames {
            let iconFrame = icon ? CGRect(x: inset, y: (height - iconSide) / 2, width: iconSide, height: iconSide) : nil
            let x = iconFrame.map { $0.maxX + spacing } ?? inset
            let button = CGRect(x: width - inset - editButtonWidth, y: (height - editButtonHeight) / 2,
                                width: editButtonWidth, height: editButtonHeight)
            return Frames(icon: iconFrame,
                          title: CGRect(x: x, y: (height - titleHeight) / 2, width: max(0, button.minX - spacing - x), height: titleHeight),
                          editButton: button)
        }
    }

    /// AppTrayViewController shows AppTrayEmptyStateView whenever the tray has
    ///
    /// topAppsEmptyStateDismissedForProfiles gets AppTrayDisplayMode.onDrag
    ///
    ///
    ///
    /// still's 87 = 82 + 5). Private windows have no tray.
    static func showsAppTrayEmptyState(favorites: Int, dismissed: Bool, privateWindow: Bool) -> Bool {
        favorites == 0 && !dismissed && !privateWindow
    }

    /// The Favorites grid's height, else the empty state's, at least
    ///
    static func appTrayHeight(gridHeight: CGFloat, emptyState: CGFloat?) -> CGFloat {
        gridHeight > 0 ? gridHeight : emptyState.map { max(AppTrayEmptyState.minimumHeight, $0) } ?? 0
    }

    /// AppTrayEmptyStateView's SwiftUI layout, top-left based in a tray of the
    /// sidebar's width: a ZStack aligned top-trailing, padded 8 at the top and
    ///
    ///
    ///
    /// centred: a VStack spaced 4 of the star icon and the title over the
    ///
    ///
    ///
    /// card's top and trailing edges.
    enum AppTrayEmptyState {
        static let minimumHeight: CGFloat = 8 + 47 + 8
        static let inset: CGFloat = 8
        static let bottomInset: CGFloat = 4
        static let padding: CGFloat = 10
        static let spacing: CGFloat = 4
        static let maximumTextWidth: CGFloat = 150
        static let closeSide: CGFloat = 14
        static let closeInset: CGFloat = 8

        struct Frames: Equatable {
            var card, icon, title, subtitle, close: CGRect
        }

        /// The width the title and subtitle wrap to.
        static func textWidth(trayWidth: CGFloat) -> CGFloat {
            min(maximumTextWidth, max(0, trayWidth - 2 * inset - 2 * padding))
        }

        /// The view's fitting height, before the tray's 63-point minimum.
        static func height(icon: CGSize, title: CGSize, subtitle: CGSize) -> CGFloat {
            inset + 2 * padding + icon.height + spacing + title.height + spacing + subtitle.height + bottomInset
        }

        static func frames(width: CGFloat, height: CGFloat, icon: CGSize, title: CGSize, subtitle: CGSize) -> Frames {
            let card = CGRect(x: inset, y: inset, width: max(0, width - 2 * inset), height: max(0, height - inset - bottomInset))
            let content = icon.height + spacing + title.height + spacing + subtitle.height
            var y = card.midY - content / 2
            func centred(_ size: CGSize) -> CGRect {
                defer { y += size.height + spacing }
                return CGRect(x: card.midX - size.width / 2, y: y, width: size.width, height: size.height)
            }
            let iconFrame = centred(icon), titleFrame = centred(title), subtitleFrame = centred(subtitle)
            let close = CGRect(x: card.maxX - closeInset - closeSide, y: card.minY + closeInset, width: closeSide, height: closeSide)
            return Frames(card: card, icon: iconFrame, title: titleFrame, subtitle: subtitleFrame, close: close)
        }
    }

    //
    //
    //
    //
    // frameOfCellAtColumn:row: moves AppKit's cell 18 points left and widens it
    //
    // so a level-n cell spans 16n to the outline's trailing edge.
    static let tablistIndentation: CGFloat = 16
    static let tablistIntercellSpacing: CGFloat = 1
    static let tablistBottomInset: CGFloat = 120
    ///
    ///
    static let tablistCellHeight: CGFloat = 40
    ///
    /// centred in its cell. Its 8-point horizontal inset is the list's.
    static let tablistVisibleRowHeight: CGFloat = 36
    /// Row boundaries sit in the middle of the intercell gap, 2.5 points
    /// outside an item's visible row, so the insertion cue after one row and
    /// before the next is drawn once.
    static let tablistRowBoundaryOutset: CGFloat = (tablistCellHeight - tablistVisibleRowHeight) / 2 + tablistIntercellSpacing / 2
    ///
    ///
    /// (UnpinnedSectionDividerCellView, which holds the Clear button) is 24
    /// when the outline's state flag at localState + 0x72 is set and
    ///
    /// 24-point divider.
    static let pinnedHeaderHeight: CGFloat = 2
    static let sectionDividerHeight: CGFloat = 24
    ///
    ///
    ///
    /// inside Parc's list, which is already inset 8.
    static let sectionDividerInset: CGFloat = 18 - 8
    static let sectionDividerSpacing: CGFloat = 8
    /// The border's height constraint is round(0.5 × scale) / scale points
    ///
    /// one point at 1x.
    static func sectionDividerThickness(scale: CGFloat) -> CGFloat {
        let scale = max(1, scale)
        return (0.5 * scale).rounded() / scale
    }
    ///
    /// private-window title uses that same accessory cell.
    static let unpinnedHeaderHeight: CGFloat = 36

    /// One outline row of the tablist, in order. Heights are positive, as
    /// NSTableView requires.
    enum TablistRow: Equatable {
        /// A tab, split, folder or the New Tab row: a 40-point cell whose
        /// 36-point visible row is the Parc view. The visible row is
        /// recovered for tabs; the New Tab and folder cells were not traced,
        /// so theirs is Parc's model.
        case item
        /// A cell the Parc view fills edge to edge.
        case accessory(height: CGFloat)
        /// An empty accessory cell with no Parc view.
        case gap(height: CGFloat)

        /// The row's cell; AppKit's row adds the intercell gap below it.
        var cellHeight: CGFloat {
            switch self {
            case .item: tablistCellHeight
            case .accessory(let height), .gap(let height): height
            }
        }

        /// The Parc view's span from the cell's top, nil for a gap.
        var viewSpan: TablistSpan? {
            switch self {
            case .item: TablistSpan(minY: (tablistCellHeight - tablistVisibleRowHeight) / 2, height: tablistVisibleRowHeight)
            case .accessory(let height): TablistSpan(minY: 0, height: height)
            case .gap: nil
            }
        }
    }

    ///
    ///
    ///
    /// lists the divider only while Today has items, in Library cards too,
    ///
    /// row. Parc's private windows show their heading in place of the header,
    /// pinned items and divider.
    enum TablistSlot: Equatable {
        case pinnedHeader, pinnedItem, sectionDivider, privateHeading, newTab, todayItem

        var row: TablistRow {
            switch self {
            case .pinnedHeader: .gap(height: pinnedHeaderHeight)
            case .pinnedItem, .newTab, .todayItem: .item
            case .sectionDivider: .accessory(height: sectionDividerHeight)
            case .privateHeading: .accessory(height: unpinnedHeaderHeight)
            }
        }
    }

    static func tablistSlots(pinnedItems: Int, todayItems: Int, isPrivate: Bool) -> [TablistSlot] {
        let divider: [TablistSlot] = todayItems > 0 ? [.sectionDivider] : []
        let pinned: [TablistSlot] = isPrivate ? [.privateHeading]
            : [.pinnedHeader] + Array(repeating: .pinnedItem, count: pinnedItems) + divider
        return pinned + [.newTab] + Array(repeating: TablistSlot.todayItem, count: todayItems)
    }

    struct TablistSpan: Equatable {
        var minY: CGFloat
        var height: CGFloat
        var maxY: CGFloat { minY + height }
    }

    struct TablistLayout: Equatable {
        /// Each row's Parc view in the list, nil for a gap.
        var views: [TablistSpan?]
        /// The rows, each followed by the intercell gap, plus the bottom inset.
        var height: CGFloat
    }

    /// NSOutlineView rows are the cell plus the intercell spacing below it,
    /// so adjacent items are 41 points apart with 5 points between their
    /// visible rows.
    static func tablist(_ rows: [TablistRow]) -> TablistLayout {
        var y: CGFloat = 0
        var views: [TablistSpan?] = []
        for row in rows {
            views.append(row.viewSpan.map { TablistSpan(minY: y + $0.minY, height: $0.height) })
            y += row.cellHeight + tablistIntercellSpacing
        }
        return TablistLayout(views: views, height: y + tablistBottomInset)
    }

    struct Toolbar: Equatable {
        var windowButtons: CGRect?
        var toggle: CGRect?
        var back: CGRect?
        var forward: CGRect?
        var reload: CGRect?
        /// Developer Mode's chevron "Reload options" button after Reload.
        var reloadOptions: CGRect?
    }

    private enum Control { case toggle, back, forward, reload }
    private struct Arrangement {
        var narrow: Bool
        var leadingToggle: Bool
        var trailing: [Control]
    }

    /// `windowButtons` is the size of the sidebar's own traffic-light stack
    ///
    /// screen. It leads the row, centred like every arranged view of the
    ///
    /// Regular rows use 32-point buttons 2 points apart with the toggle
    /// leading; narrow rows use 28 points without spacing.
    ///
    ///
    /// shows its More menu last. Parc has no More menu, so the toggle takes
    /// that slot and stays the pointer route to hide or lock the sidebar.
    ///
    /// spacing) and 54 before. Parc adaptation: a regular row whose toggle would
    /// crowd Back (below 217 with 60-point lights) keeps every control at the
    /// narrow size, and a crowded narrow row gives up Forward before the toggle.
    ///
    ///
    ///
    ///
    /// reload button behind More; Parc's narrow row keeps its ordinary Reload.
    static func toolbar(width: CGFloat, windowButtons: CGSize?, showsNavigation: Bool,
                        developerReload: Bool = false) -> Toolbar {
        let lights = windowButtons.map {
            CGRect(x: navigationLeading, y: headerTop + (navigationRowHeight - $0.height) / 2, width: $0.width, height: $0.height)
        }
        let leading = lights.map { $0.maxX + windowButtonMargin } ?? navigationLeading
        let navigation: [Control] = showsNavigation ? [.back, .forward, .reload] : []
        var candidates: [Arrangement] = []
        if width >= narrowWidth { candidates.append(Arrangement(narrow: false, leadingToggle: true, trailing: navigation)) }
        if width >= narrowWidth || !showsNavigation {
            candidates.append(Arrangement(narrow: true, leadingToggle: true, trailing: navigation))
        }
        if showsNavigation {
            candidates += [Arrangement(narrow: true, leadingToggle: false, trailing: [.back, .forward, .toggle]),
                           Arrangement(narrow: true, leadingToggle: false, trailing: [.back, .toggle]),
                           Arrangement(narrow: true, leadingToggle: false, trailing: [.toggle])]
        }
        var bar = place(candidates[candidates.count - 1], width: width, leading: leading, developerReload: developerReload)
        for arrangement in candidates.dropLast() {
            let candidate = place(arrangement, width: width, leading: leading, developerReload: developerReload)
            if fits(candidate, arrangement, width: width, leading: leading) { bar = candidate; break }
        }
        bar.windowButtons = lights
        return bar
    }

    private static func metrics(_ arrangement: Arrangement) -> (side: CGFloat, spacing: CGFloat) {
        arrangement.narrow ? (28, 0) : (32, 2)
    }

    static let developerReloadWidth: CGFloat = 19
    static let reloadOptionsWidth: CGFloat = 14

    /// The toggle, Back, Forward and Reload are TranslucentButtons built at
    ///
    ///
    ///
    ///
    /// `.system(size:weight:)` from the per-size table [16, 16, 16, 14, 14, 12]
    ///
    static let navigationGlyphPointSize: CGFloat = 16
    /// The narrow width class resizes every header button to `_28` with a
    ///
    static let narrowNavigationGlyphPointSize: CGFloat = 14
    static func navigationGlyphPointSize(buttonSide: CGFloat) -> CGFloat {
        buttonSide < 32 ? narrowNavigationGlyphPointSize : navigationGlyphPointSize
    }

    private static func place(_ arrangement: Arrangement, width: CGFloat, leading: CGFloat, developerReload: Bool) -> Toolbar {
        let (side, spacing) = metrics(arrangement)
        let y = headerTop + (navigationRowHeight - side) / 2
        var bar = Toolbar()
        var x = width - navigationTrailing
        for control in arrangement.trailing.reversed() {
            if control == .reload, developerReload, !arrangement.narrow {
                // The options button abuts the thin Reload (split-button pair).
                x -= reloadOptionsWidth
                bar.reloadOptions = CGRect(x: x, y: y, width: reloadOptionsWidth, height: side)
                x -= developerReloadWidth
                bar.reload = CGRect(x: x, y: y, width: developerReloadWidth, height: side)
                x -= spacing
                continue
            }
            x -= side
            let frame = CGRect(x: x, y: y, width: side, height: side)
            switch control {
            case .toggle: bar.toggle = frame
            case .back: bar.back = frame
            case .forward: bar.forward = frame
            case .reload: bar.reload = frame
            }
            x -= spacing
        }
        if arrangement.leadingToggle { bar.toggle = CGRect(x: leading, y: y, width: side, height: side) }
        return bar
    }

    private static func fits(_ bar: Toolbar, _ arrangement: Arrangement, width: CGFloat, leading: CGFloat) -> Bool {
        let spacing = metrics(arrangement).spacing
        let frames = [bar.toggle, bar.back, bar.forward, bar.reload.map { $0.union(bar.reloadOptions ?? $0) }]
            .compactMap { $0 }.sorted { $0.minX < $1.minX }
        guard let first = frames.first, let last = frames.last else { return true }
        return first.minX >= leading && last.maxX <= width - navigationTrailing
            && zip(frames, frames.dropFirst()).allSatisfy { $0.maxX + spacing <= $1.minX }
    }

    static let dockHeight: CGFloat = 50
    static let dockButtonSide: CGFloat = 32
    static let dockInset: CGFloat = 8

    /// SidebarDockView's trailing (+) button: 32 × 32, 8 points from the edge,
    /// centred in the 50-point dock.
    static func dockTrailingButton(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: width - dockInset - dockButtonSide, y: height - dockHeight + (dockHeight - dockButtonSide) / 2,
               width: dockButtonSide, height: dockButtonSide)
    }

    /// SidebarDockView's leftButtonPlaceholder, which holds the Library entry
    /// (HomeBadging.HomeButton): 32 × 32, 8 points from the leading edge,
    /// centred in the 50-point dock.
    static func dockLeadingButton(height: CGFloat) -> CGRect {
        CGRect(x: dockInset, y: height - dockHeight + (dockHeight - dockButtonSide) / 2,
               width: dockButtonSide, height: dockButtonSide)
    }

    /// The Space strip between the two dock buttons: 40…width − 40 at the
    /// dock's full height.
    static func dockStrip(width: CGFloat, height: CGFloat) -> CGRect {
        let leading = dockLeadingButton(height: height).maxX
        let trailing = dockTrailingButton(width: width, height: height).minX
        return CGRect(x: leading, y: height - dockHeight, width: max(0, trailing - leading), height: dockHeight)
    }

    ///
    ///
    static let dockContentInset: CGFloat = 2
    /// Pitches below 22 use the compact (dot) style; the focused item keeps 22.
    static let dockCompactPitch: CGFloat = 22

    struct DockLayout: Equatable {
        /// Item frames in the scrolled document, which starts after the leading inset.
        var items: [CGRect]
        ///
        var contentWidth: CGFloat
        var compact: Bool
    }

    ///
    /// `width` × `height` without a drag or drop proposal: pitch =
    /// clamp((width − 4) ÷ count, 8, 34), at most 32 tall, centred vertically.
    /// Below a 22 pitch the focused item is 22 wide and the others share the
    /// rest, at least 8 each. Items that fit are centred; wider content scrolls.
    static func dockLayout(width: CGFloat, height: CGFloat, count: Int, focused: Int?) -> DockLayout {
        guard count > 0 else { return DockLayout(items: [], contentWidth: 0, compact: false) }
        let available = width - 2 * dockContentInset
        var pitch = max(8, min(available / CGFloat(count), 34))
        let widened = max(dockCompactPitch, pitch)
        let focused = focused.flatMap { (0..<count).contains($0) ? $0 : nil }
        if widened != pitch, focused != nil { pitch = max(8, (available - widened) / CGFloat(count - 1)) }
        let side = min(height, dockButtonSide), y = (height - side) / 2
        var x: CGFloat = 0
        var items = (0..<count).map { index -> CGRect in
            let item = CGRect(x: x, y: y, width: index == focused ? widened : pitch, height: side)
            x = item.maxX
            return item
        }
        let offset = available > x ? (available - x) / 2 : 0
        if offset > 0 { items = items.map { $0.offsetBy(dx: offset, dy: 0) } }
        return DockLayout(items: items, contentWidth: x + offset, compact: pitch < dockCompactPitch)
    }

    /// Parc's default and staged Space records use filled and outline circle
    /// sentinels respectively; a real custom icon or legacy symbol remains an icon.
    static func dockIconless(hasCustomIcon: Bool, symbol: String) -> Bool {
        !hasCustomIcon && (symbol == "circle.fill" || symbol == "circle")
    }

    ///
    /// Space (Library and + only). The switcher appears once there are two
    /// Spaces, a custom icon, or a Create Space item.
    static func dockShowsSpaces(count: Int, anyCustomIcon: Bool, creating: Bool) -> Bool {
        creating || count > 1 || anyCustomIcon
    }

    enum DockItemPresentation: Equatable {
        /// SidebarDockItemView's pageIndicator, a centred circle.
        case dot(side: CGFloat, alpha: CGFloat)
        /// The active and inactive icon views' alpha values.
        case icon(active: CGFloat, inactive: CGFloat)
    }

    ///
    /// compact item is a 4-point dot at the resting alpha (0.35 in Dark Aqua,
    /// else 0.5). Otherwise the icons cross-fade: the active one from 0.7 when
    /// highlighted (else 0) to 1 with the selection, the inactive one from the
    /// resting alpha (0 when highlighted) to 0. Icon-less `circleFilled`
    /// Spaces use an 8-point dot in both layouts, with the same selection fade.
    static func dockItemPresentation(compact: Bool, selection: CGFloat, highlighted: Bool, dark: Bool,
                                     iconless: Bool = false) -> DockItemPresentation {
        let resting: CGFloat = dark ? 0.35 : 0.5
        if iconless {
            let base: CGFloat = highlighted ? 0.7 : resting
            return .dot(side: 8, alpha: base + (1 - base) * selection)
        }
        if compact, selection <= 0, !highlighted { return .dot(side: 4, alpha: resting) }
        let active: CGFloat = highlighted ? 0.7 : 0, inactive = highlighted ? 0 : resting
        guard selection > 0 else { return .icon(active: active, inactive: inactive) }
        return .icon(active: active + (1 - active) * selection, inactive: (1 - selection) * inactive)
    }
}
