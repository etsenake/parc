import CoreGraphics

enum SidebarChromeLayout {
    static let narrowWidth: CGFloat = 212

    static let headerTop: CGFloat = 4
    static let navigationRowHeight: CGFloat = 40
    static let navigationLeading: CGFloat = 13
    static let navigationTrailing: CGFloat = 6
    static let windowButtonMargin: CGFloat = 4
    static let fieldInset: CGFloat = 8
    static let fieldTop: CGFloat = headerTop + navigationRowHeight + 2
    static let fieldHeight: CGFloat = 36
    static let addressFontSize: CGFloat = 13
    static let addressTextIndent: CGFloat = 12
    static let headerBottom: CGFloat = fieldTop + fieldHeight
    static func hiddenAddressHeight(toolbar: Bool, hasPrompt: Bool, keyboardSearch: Bool) -> CGFloat {
        toolbar && !hasPrompt && !keyboardSearch ? fieldHeight + 2 : 0
    }
    static let headerBottomSpacing: CGFloat = 5

    static func tablistTop(trayHeight: CGFloat, spaceHeader: Bool = false, hasFavorites: Bool = false) -> CGFloat {
        spaceHeader ? SpaceHeader.top(trayHeight: trayHeight, hasFavorites: hasFavorites) + SpaceHeader.height
            : pageTop(trayHeight: trayHeight, spaceHeader: false)
    }

    static func pageTop(trayHeight: CGFloat, spaceHeader: Bool) -> CGFloat {
        headerBottom + (trayHeight > 0 ? trayHeight : spaceHeader ? 0 : headerBottomSpacing)
    }

    enum SpaceHeader {
        static let height: CGFloat = 36
        static let topPadding: CGFloat = 8
        static let inset: CGFloat = 14
        static let iconSide: CGFloat = 24
        static let spacing: CGFloat = 4
        static let fontSize: CGFloat = 13

        static let editButtonHeight: CGFloat = 24
        static func editButtonWidth(shown: Bool, editing: Bool, titleWidth: CGFloat = 0) -> CGFloat {
            shown ? (editing ? max(30, ceil(titleWidth) + 4) : 24) : 0
        }

        static func showsEditButton(editing: Bool, hovered: Bool, canShowHeaderButtons: Bool) -> Bool {
            (editing || hovered) && canShowHeaderButtons
        }

        static func editButtonHoverDelay(hovered: Bool) -> Double { hovered ? 0.1 : 0 }
        static let editButtonFadeDuration: Double = 0.1

        static func isShown(spaceCount: Int, titled: Bool, customIcon: Bool, privateWindow: Bool,
                            showOnSingleUnnamedSpace: Bool) -> Bool {
            !privateWindow && (showOnSingleUnnamedSpace || spaceCount >= 2 || titled || customIcon)
        }

        static func toggleTitle(spaceCount: Int, titled: Bool, customIcon: Bool, showOnSingleUnnamedSpace: Bool) -> String? {
            guard spaceCount == 1, !titled, !customIcon else { return nil }
            return showOnSingleUnnamedSpace ? "Hide Space Header" : "Show Space Header"
        }

        static func placeholderTitle(position: Int?) -> String {
            position.map { "Space \($0 + 1)" } ?? "Space"
        }

        static func top(trayHeight: CGFloat, hasFavorites: Bool) -> CGFloat {
            pageTop(trayHeight: trayHeight, spaceHeader: true) + (hasFavorites ? 0 : topPadding)
        }

        struct Frames: Equatable {
            var icon: CGRect?
            var title: CGRect
            var editButton: CGRect
        }

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

    static func showsAppTrayEmptyState(favorites: Int, dismissed: Bool, privateWindow: Bool) -> Bool {
        favorites == 0 && !dismissed && !privateWindow
    }

    static func appTrayHeight(gridHeight: CGFloat, emptyState: CGFloat?) -> CGFloat {
        gridHeight > 0 ? gridHeight : emptyState.map { max(AppTrayEmptyState.minimumHeight, $0) } ?? 0
    }

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

        static func textWidth(trayWidth: CGFloat) -> CGFloat {
            min(maximumTextWidth, max(0, trayWidth - 2 * inset - 2 * padding))
        }

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

    static let tablistIndentation: CGFloat = 16
    static let tablistIntercellSpacing: CGFloat = 1
    static let tablistBottomInset: CGFloat = 120
    static let tablistCellHeight: CGFloat = 40
    static let tablistVisibleRowHeight: CGFloat = 36
    static let tablistRowBoundaryOutset: CGFloat = (tablistCellHeight - tablistVisibleRowHeight) / 2 + tablistIntercellSpacing / 2
    static let pinnedHeaderHeight: CGFloat = 2
    static let sectionDividerHeight: CGFloat = 24
    static let sectionDividerInset: CGFloat = 18 - 8
    static let sectionDividerSpacing: CGFloat = 8
    static func sectionDividerThickness(scale: CGFloat) -> CGFloat {
        let scale = max(1, scale)
        return (0.5 * scale).rounded() / scale
    }
    static let unpinnedHeaderHeight: CGFloat = 36

    enum TablistRow: Equatable {
        case item
        case accessory(height: CGFloat)
        case gap(height: CGFloat)

        var cellHeight: CGFloat {
            switch self {
            case .item: tablistCellHeight
            case .accessory(let height), .gap(let height): height
            }
        }

        var viewSpan: TablistSpan? {
            switch self {
            case .item: TablistSpan(minY: (tablistCellHeight - tablistVisibleRowHeight) / 2, height: tablistVisibleRowHeight)
            case .accessory(let height): TablistSpan(minY: 0, height: height)
            case .gap: nil
            }
        }
    }

    enum TablistSlot: Equatable {
        case pinnedHeader, pinnedSectionHeader, pinnedItem, sectionDivider, privateHeading, newTab, todayItem

        var row: TablistRow {
            switch self {
            case .pinnedHeader: .gap(height: pinnedHeaderHeight)
            case .pinnedSectionHeader, .pinnedItem, .newTab, .todayItem: .item
            case .sectionDivider: .accessory(height: sectionDividerHeight)
            case .privateHeading: .accessory(height: unpinnedHeaderHeight)
            }
        }
    }

    static func tablistSlots(pinnedItems: Int, todayItems: Int, isPrivate: Bool, sectionHeader: Bool = false) -> [TablistSlot] {
        let divider: [TablistSlot] = todayItems > 0 ? [.sectionDivider] : []
        let pinned: [TablistSlot] = isPrivate ? [.privateHeading]
            : [sectionHeader ? .pinnedSectionHeader : .pinnedHeader] + Array(repeating: .pinnedItem, count: pinnedItems) + divider
        return pinned + [.newTab] + Array(repeating: TablistSlot.todayItem, count: todayItems)
    }

    struct TablistSpan: Equatable {
        var minY: CGFloat
        var height: CGFloat
        var maxY: CGFloat { minY + height }
    }

    struct TablistLayout: Equatable {
        var views: [TablistSpan?]
        var height: CGFloat
    }

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
        var reloadOptions: CGRect?
    }

    private enum Control { case toggle, back, forward, reload }
    private struct Arrangement {
        var narrow: Bool
        var leadingToggle: Bool
        var trailing: [Control]
    }

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

    static let navigationGlyphPointSize: CGFloat = 16
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

    static func dockTrailingButton(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: width - dockInset - dockButtonSide, y: height - dockHeight + (dockHeight - dockButtonSide) / 2,
               width: dockButtonSide, height: dockButtonSide)
    }

    static func dockLeadingButton(height: CGFloat) -> CGRect {
        CGRect(x: dockInset, y: height - dockHeight + (dockHeight - dockButtonSide) / 2,
               width: dockButtonSide, height: dockButtonSide)
    }

    static func dockStrip(width: CGFloat, height: CGFloat) -> CGRect {
        let leading = dockLeadingButton(height: height).maxX
        let trailing = dockTrailingButton(width: width, height: height).minX
        return CGRect(x: leading, y: height - dockHeight, width: max(0, trailing - leading), height: dockHeight)
    }

    static let dockContentInset: CGFloat = 2
    static let dockCompactPitch: CGFloat = 22

    struct DockLayout: Equatable {
        var items: [CGRect]
        var contentWidth: CGFloat
        var compact: Bool
    }

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

    static func dockIconless(hasCustomIcon: Bool, symbol: String) -> Bool {
        !hasCustomIcon && (symbol == "circle.fill" || symbol == "circle")
    }

    static func dockShowsSpaces(count: Int, anyCustomIcon: Bool, creating: Bool) -> Bool {
        creating || count > 1 || anyCustomIcon
    }

    enum DockItemPresentation: Equatable {
        case dot(side: CGFloat, alpha: CGFloat)
        case icon(active: CGFloat, inactive: CGFloat)
    }

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
