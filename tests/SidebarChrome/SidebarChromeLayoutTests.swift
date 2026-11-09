import CoreGraphics

extension SidebarChromeLayout.Toolbar {
    func with(lights: CGRect?) -> Self { var bar = self; bar.windowButtons = lights; return bar }
}

@main struct SidebarChromeLayoutTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarChromeLayout: \(message)") }
    }
    static func separate(_ frames: [CGRect?], _ message: String) {
        let shown = frames.compactMap { $0 }.sorted { $0.minX < $1.minX }
        for (a, b) in zip(shown, shown.dropFirst()) { check(a.maxX <= b.minX + 0.0001, "\(message): \(a) overlaps \(b)") }
    }
    static func main() {
        typealias L = SidebarChromeLayout
        check(L.headerBottom - L.hiddenAddressHeight(toolbar: true, hasPrompt: false, keyboardSearch: false) == L.headerTop + L.navigationRowHeight,
              "Toolbar collapses the hidden URL row before the Space header and Favorites")
        check(L.hiddenAddressHeight(toolbar: false, hasPrompt: false, keyboardSearch: false) == 0,
              "Ordinary sidebar keeps its URL row")
        check(L.hiddenAddressHeight(toolbar: true, hasPrompt: true, keyboardSearch: false) == 0,
              "A real page prompt retains its interactive row")
        check(L.hiddenAddressHeight(toolbar: true, hasPrompt: false, keyboardSearch: true) == 0,
              "Keyboard search retains its interactive row")
        check(L.narrowWidth == 212, "narrow below 212")
        check(L.fieldTop == 46 && L.fieldHeight == 36, "field below the 4 + 40 row and 2-point padding")

        //
        //
        // at 73 and the toggle sits at 77 (1.170 capture: 76.7); 3 × 14 + 2 × 6
        // = 54 before, toggle at 71. Lights and toggle share the row's centre;
        // other extents and heights exercise the generic placement.
        func lights(_ width: CGFloat, _ height: CGFloat = 14) -> CGSize { CGSize(width: width, height: height) }
        let regular = L.toolbar(width: 228, windowButtons: lights(60), showsNavigation: true)
        check(regular.windowButtons == CGRect(x: 13, y: 17, width: 60, height: 14), "lights lead the row at 8 + 5")
        check(regular.reload == CGRect(x: 190, y: 8, width: 32, height: 32), "Reload at width − 38")
        check(regular.forward == CGRect(x: 156, y: 8, width: 32, height: 32), "Forward at width − 72")
        check(regular.back == CGRect(x: 122, y: 8, width: 32, height: 32), "Back at width − 106")
        check(regular.toggle == CGRect(x: 77, y: 8, width: 32, height: 32), "toggle 4 points after the traffic lights")
        check(regular.windowButtons?.midY == regular.toggle?.midY && regular.toggle?.midY == 24, "lights level with the toggle")
        let before26 = L.toolbar(width: 228, windowButtons: lights(54), showsNavigation: true)
        check(before26.windowButtons == CGRect(x: 13, y: 17, width: 54, height: 14) && before26.toggle?.minX == 71
              && before26.back == regular.back, "6-point spacing before macOS 26: toggle at 71")
        check(L.toolbar(width: 228, windowButtons: lights(56), showsNavigation: true).toggle?.minX == 73, "toggle follows wider lights")
        let full = L.toolbar(width: 228, windowButtons: nil, showsNavigation: true)
        check(full.toggle?.minX == 13 && full.windowButtons == nil, "no traffic lights: toggle leads the stack")
        let wide = L.toolbar(width: 500, windowButtons: lights(60), showsNavigation: true)
        check(wide.reload?.minX == 462 && wide.back?.minX == 394 && wide.toggle?.minX == 77, "wide sidebars keep the toggle leading and the rest trailing")
        check(L.toolbar(width: 220, windowButtons: lights(60), showsNavigation: true).reload?.width == 32, "compact keeps regular buttons")

        // A crowded regular row keeps all four controls at the narrow size
        // (Parc adaptation): with 60-point lights, below 217.
        let crowded = L.toolbar(width: 212, windowButtons: lights(56), showsNavigation: true)
        check(crowded.toggle == CGRect(x: 73, y: 10, width: 28, height: 28) && crowded.back?.minX == 122
              && crowded.forward?.minX == 150 && crowded.reload?.minX == 178, "crowded 212 keeps every control at 28 points")
        let crowdedWide = L.toolbar(width: 212, windowButtons: lights(60), showsNavigation: true)
        check(crowdedWide.toggle == CGRect(x: 77, y: 10, width: 28, height: 28) && crowdedWide.reload != nil && crowdedWide.back?.minX == 122,
              "60-point lights at 212 keep the toggle and Reload at 28 points")
        check(L.toolbar(width: 216, windowButtons: lights(60), showsNavigation: true).back?.width == 28
              && L.toolbar(width: 217, windowButtons: lights(60), showsNavigation: true).back?.width == 32, "regular returns at 217 with 60-point lights")
        check(L.toolbar(width: 214, windowButtons: lights(56), showsNavigation: true).back?.width == 32, "regular returns once it fits")

        //
        // and shows More last; Parc's toggle takes the More slot.
        let narrow = L.toolbar(width: 164, windowButtons: lights(54), showsNavigation: true)
        check(narrow.reload == nil, "narrow hides Reload")
        check(narrow.toggle == CGRect(x: 130, y: 10, width: 28, height: 28) && narrow.forward == CGRect(x: 102, y: 10, width: 28, height: 28)
              && narrow.back == CGRect(x: 74, y: 10, width: 28, height: 28), "narrow Back/Forward and the toggle in the More slot")
        check(narrow.windowButtons == before26.windowButtons, "narrow keeps the lights")
        check(L.toolbar(width: 164, windowButtons: lights(56), showsNavigation: true) == narrow.with(lights: CGRect(x: 13, y: 17, width: 56, height: 14)),
              "slightly wider lights fit the narrow row")
        let narrowWide = L.toolbar(width: 164, windowButtons: lights(60), showsNavigation: true)
        check(narrowWide.forward == nil && narrowWide.toggle?.minX == 130 && narrowWide.back?.minX == 102, "with 60-point lights Forward yields before the toggle")
        check(L.toolbar(width: 211, windowButtons: lights(60), showsNavigation: true).forward?.minX == 149, "Forward returns once it fits")
        let narrowToolbarOnly = L.toolbar(width: 164, windowButtons: lights(54), showsNavigation: false)
        check(narrowToolbarOnly.toggle == CGRect(x: 71, y: 10, width: 28, height: 28) && narrowToolbarOnly.back == nil, "content toolbar keeps the toggle leading")
        check(L.toolbar(width: 228, windowButtons: lights(54), showsNavigation: false).reload == nil, "content toolbar owns navigation")

        for width in stride(from: 164.0, through: 500, by: 1) {
            for extent in [nil, 48, 51, 54, 56, 60] as [CGFloat?] {
                for height in [14.0, 16] as [CGFloat] {
                    let leading = extent.map { 13 + $0 + 4 } ?? 13
                    for navigation in [true, false] {
                        let bar = L.toolbar(width: width, windowButtons: extent.map { lights($0, height) }, showsNavigation: navigation)
                        check(bar.toggle != nil, "a pointer control hides or locks the sidebar at \(width)")
                        separate([bar.windowButtons, bar.toggle, bar.back, bar.forward, bar.reload], "toolbar at \(width)")
                        let shown = [bar.toggle, bar.back, bar.forward, bar.reload].compactMap { $0 }
                        check(shown.allSatisfy { $0.minX >= leading }, "controls clear the traffic lights at \(width)")
                        check(shown.allSatisfy { $0.maxX <= width - 6 }, "trailing inset at \(width)")
                        check(navigation == (bar.back != nil), "Back follows the toolbar owner at \(width)")
                        check(bar.windowButtons.map { $0.midY == 24 && $0.minX == 13 } ?? (extent == nil), "lights centred in the row at \(width)")
                    }
                }
            }
        }

        // The App Tray starts where the header ends; an empty tray leaves the
        //
        check(L.headerBottom == 82 && L.tablistTop(trayHeight: 0) == 87, "empty tray: list at 82 + 5")
        check(L.tablistTop(trayHeight: 63) == 145 && L.tablistTop(trayHeight: 118) == 200, "list directly below a 1- or 2-row tray")

        // The empty state: shown in an empty tray until the profile dismisses
        // it, at least 8 + 47 + 8 tall, with the header inset 0 while it shows.
        check(L.showsAppTrayEmptyState(favorites: 0, dismissed: false, privateWindow: false), "an undismissed empty tray shows it")
        check(!L.showsAppTrayEmptyState(favorites: 0, dismissed: true, privateWindow: false)
              && !L.showsAppTrayEmptyState(favorites: 1, dismissed: false, privateWindow: false)
              && !L.showsAppTrayEmptyState(favorites: 0, dismissed: false, privateWindow: true), "dismissed, Favorites or private: none")
        typealias E = L.AppTrayEmptyState
        check(E.minimumHeight == 63, "the tray's empty-state constraint is 8 + 47 + 8")
        check(L.appTrayHeight(gridHeight: 0, emptyState: nil) == 0 && L.appTrayHeight(gridHeight: 63, emptyState: nil) == 63
              && L.appTrayHeight(gridHeight: 118, emptyState: 102) == 118, "Favorites take the grid's height")
        check(L.appTrayHeight(gridHeight: 0, emptyState: 40) == 63 && L.appTrayHeight(gridHeight: 0, emptyState: 102) == 102,
              "the empty state takes its fitting height, at least 63")
        check(L.tablistTop(trayHeight: L.appTrayHeight(gridHeight: 0, emptyState: 102)) == 184
              && L.tablistTop(trayHeight: L.appTrayHeight(gridHeight: 0, emptyState: 40)) == 145
              && L.tablistTop(trayHeight: L.appTrayHeight(gridHeight: 0, emptyState: nil)) == 87,
              "list at 82 + the empty state with no inset, at 145 or lower; 87 once dismissed")
        //
        //
        // Space, a custom icon or showSpaceHeaderOnSingleUnnamedSpaces; never
        //
        typealias H = L.SpaceHeader
        check(!H.isShown(spaceCount: 1, titled: false, customIcon: false, privateWindow: false, showOnSingleUnnamedSpace: false),
              "one untitled Space without an icon: no header")
        check(H.isShown(spaceCount: 2, titled: false, customIcon: false, privateWindow: false, showOnSingleUnnamedSpace: false)
              && H.isShown(spaceCount: 1, titled: true, customIcon: false, privateWindow: false, showOnSingleUnnamedSpace: false)
              && H.isShown(spaceCount: 1, titled: false, customIcon: true, privateWindow: false, showOnSingleUnnamedSpace: false),
              "two Spaces, a title or an icon show it")
        check(H.isShown(spaceCount: 1, titled: false, customIcon: false, privateWindow: false, showOnSingleUnnamedSpace: true),
              "the setting shows it for one untitled Space")
        check(!H.isShown(spaceCount: 3, titled: true, customIcon: true, privateWindow: true, showOnSingleUnnamedSpace: true),
              "never in an incognito window, whatever the setting")
        //
        // icon, titled by the setting.
        check(H.toggleTitle(spaceCount: 1, titled: false, customIcon: false, showOnSingleUnnamedSpace: false) == "Show Space Header"
              && H.toggleTitle(spaceCount: 1, titled: false, customIcon: false, showOnSingleUnnamedSpace: true) == "Hide Space Header",
              "Show Space Header while the setting is off, Hide Space Header while on")
        check([H.toggleTitle(spaceCount: 2, titled: false, customIcon: false, showOnSingleUnnamedSpace: true),
               H.toggleTitle(spaceCount: 1, titled: true, customIcon: false, showOnSingleUnnamedSpace: false),
               H.toggleTitle(spaceCount: 1, titled: false, customIcon: true, showOnSingleUnnamedSpace: false),
               H.toggleTitle(spaceCount: 0, titled: false, customIcon: false, showOnSingleUnnamedSpace: false)].allSatisfy { $0 == nil },
              "no toggle once two Spaces, a title or an icon decide the header")
        check(H.placeholderTitle(position: 0) == "Space 1" && H.placeholderTitle(position: 2) == "Space 3"
              && H.placeholderTitle(position: nil) == "Space", "the \"Space N\" placeholder, or \"Space\"")
        // Placement: no 5-point inset, 8 below the page without Favorites,
        // 36 tall, and the list at its bottom.
        check(H.height == 36 && H.topPadding == 8 && H.inset == 14 && H.iconSide == 24 && H.spacing == 4 && H.fontSize == 13, "header constants")
        check(L.pageTop(trayHeight: 0, spaceHeader: true) == 82 && L.pageTop(trayHeight: 0, spaceHeader: false) == 87,
              "a shown header takes the header inset to 0")
        check(H.top(trayHeight: 0, hasFavorites: false) == 90 && L.tablistTop(trayHeight: 0, spaceHeader: true) == 126,
              "two Spaces, dismissed empty tray: header 90…126, list at 126 (87 without it)")
        check(H.top(trayHeight: 63, hasFavorites: true) == 145 && L.tablistTop(trayHeight: 63, spaceHeader: true, hasFavorites: true) == 181,
              "one Favorites row: header at the tray's end, list at 181")
        check(H.top(trayHeight: 106, hasFavorites: false) == 196 && L.tablistTop(trayHeight: 106, spaceHeader: true) == 232,
              "the empty state: header 8 below it, list at 232")
        check(L.tablistTop(trayHeight: 63, spaceHeader: false, hasFavorites: true) == 145, "a hidden header leaves the list below the tray")
        let iconFrames = H.frames(width: 228, icon: true, titleHeight: 16)
        check(iconFrames.icon == CGRect(x: 14, y: 6, width: 24, height: 24) && iconFrames.title == CGRect(x: 42, y: 10, width: 168, height: 16),
              "icon at the 14-point inset, name 4 after it and 4 before the zero-width edit button")
        let plain = H.frames(width: 164, icon: false, titleHeight: 16)
        check(plain.icon == nil && plain.title == CGRect(x: 14, y: 10, width: 132, height: 16), "no icon: the name leads the stack")
        check(H.frames(width: 20, icon: true, titleHeight: 16).title.width == 0, "a too-narrow header never gives the name a negative width")
        //
        // centred; 0 wide at rest, 24 shown, 30 while the name is edited.
        check(H.editButtonHeight == 24 && H.editButtonWidth(shown: false, editing: false) == 0
              && H.editButtonWidth(shown: false, editing: true) == 0 && H.editButtonWidth(shown: true, editing: false) == 24
              && H.editButtonWidth(shown: true, editing: true) == 30, "edit button widths: 0 hidden, 24 shown, 30 while editing")
        check(iconFrames.editButton == CGRect(x: 214, y: 6, width: 0, height: 24) && plain.editButton == CGRect(x: 150, y: 6, width: 0, height: 24),
              "at rest the button is a zero-width slot at the trailing inset")
        let shown = H.frames(width: 228, icon: true, titleHeight: 16, editButtonWidth: 24)
        check(shown.icon == iconFrames.icon && shown.editButton == CGRect(x: 190, y: 6, width: 24, height: 24)
              && shown.title == CGRect(x: 42, y: 10, width: 144, height: 16), "shown: 190…214, and the name ends 4 before it")
        let editing = H.frames(width: 228, icon: false, titleHeight: 16, editButtonWidth: 30)
        check(editing.editButton == CGRect(x: 184, y: 6, width: 30, height: 24) && editing.title == CGRect(x: 14, y: 10, width: 166, height: 16),
              "editing: 184…214, the name 14…180")
        // (isEditing || isHovered) && canShowHeaderButtonsIfPossible.
        check(!H.showsEditButton(editing: false, hovered: false, canShowHeaderButtons: true), "resting header: no button")
        check(H.showsEditButton(editing: false, hovered: true, canShowHeaderButtons: true)
              && H.showsEditButton(editing: true, hovered: false, canShowHeaderButtons: true), "hover or editing shows it")
        check(!H.showsEditButton(editing: true, hovered: true, canShowHeaderButtons: false)
              && !H.showsEditButton(editing: false, hovered: true, canShowHeaderButtons: false), "never without the header-buttons gate")
        check(H.editButtonHoverDelay(hovered: true) == 0.1 && H.editButtonHoverDelay(hovered: false) == 0 && H.editButtonFadeDuration == 0.1,
              "hover-in waits 0.1 s, hover-out does not; the fade is 0.1 s")

        check(E.textWidth(trayWidth: 228) == 150 && E.textWidth(trayWidth: 164) == 128 && E.textWidth(trayWidth: 20) == 0,
              "text wraps at 150 or the card's padded width")
        let icon = CGSize(width: 17, height: 16), title = CGSize(width: 140, height: 16), subtitle = CGSize(width: 150, height: 30)
        check(E.height(icon: icon, title: title, subtitle: subtitle) == 8 + 10 + 16 + 4 + 16 + 4 + 30 + 10 + 4,
              "8 above, 4 below, 10 around the content, 4 between its parts")
        let empty = E.frames(width: 228, height: 102, icon: icon, title: title, subtitle: subtitle)
        check(empty.card == CGRect(x: 8, y: 8, width: 212, height: 90), "the card inside the 8/8/8/4 insets")
        check(empty.icon == CGRect(x: 105.5, y: 18, width: 17, height: 16) && empty.title == CGRect(x: 44, y: 38, width: 140, height: 16)
              && empty.subtitle == CGRect(x: 39, y: 58, width: 150, height: 30), "icon, title and subtitle centred and stacked 4 apart")
        check(empty.close == CGRect(x: 198, y: 16, width: 14, height: 14), "Dismiss 14 × 14, 8 in from the card's top-trailing corner")
        let tall = E.frames(width: 228, height: 160, icon: icon, title: title, subtitle: subtitle)
        check(tall.icon.minY - tall.card.minY == tall.card.maxY - tall.subtitle.maxY && tall.close.minY == 16,
              "a taller tray centres the content; Dismiss stays at the top")

        // TablistView's outline: 40-point cells, 1-point intercell spacing,
        // 36-point visible rows centred in their cells, 16 per level, 120 below.
        // SidebarTablistTests compares the model with AppKit's own outline.
        typealias S = L.TablistSpan
        check(L.tablistCellHeight == 40 && L.tablistVisibleRowHeight == 36 && L.tablistIntercellSpacing == 1
              && L.tablistIndentation == 16 && L.tablistBottomInset == 120, "outline constants")
        check(L.pinnedHeaderHeight == 2 && L.sectionDividerHeight == 24, "accessory heights")
        let pair = L.tablist([.gap(height: L.pinnedHeaderHeight), .item, .item])
        check(pair.views == [nil, S(minY: 5, height: 36), S(minY: 46, height: 36)], "items after the 2-point pinned header")
        check(pair.height == 3 + 41 + 41 + 120, "rows plus intercell gaps plus the bottom inset")
        check(L.tablist([.item]).views == [S(minY: 2, height: 36)] && L.tablist([]).height == 120, "a lone item and an empty outline")
        check(L.tablist([.accessory(height: 28), .item]).views == [S(minY: 0, height: 28), S(minY: 31, height: 36)], "an accessory first")

        // Insertion cues: the boundary after one visible row is the boundary
        // before the next, in the middle of the intercell gap.
        let outset = L.tablistRowBoundaryOutset
        check(outset == 2.5, "boundaries 2.5 outside a visible row")
        let cue = L.tablist([.gap(height: 2), .item, .item, .accessory(height: 24), .item])
        check(cue.views[1]!.maxY + outset == cue.views[2]!.minY - outset, "after A and before B coincide")
        check(cue.views[1]!.minY - outset == 2.5, "before the first pinned row: between the header and its cell")
        check(cue.views[2]!.maxY + outset == cue.views[3]!.minY - L.tablistIntercellSpacing / 2, "after the last pinned row: above the divider cell")

        // The production row order (SidebarView.render places its views by these slots).
        typealias T = L.TablistSlot
        check(L.tablistSlots(pinnedItems: 2, todayItems: 1, isPrivate: false)
              == [.pinnedHeader, .pinnedItem, .pinnedItem, .sectionDivider, .newTab, .todayItem], "pinned header, items, divider, New Tab, Today")
        check(L.tablistSlots(pinnedItems: 0, todayItems: 1, isPrivate: false)
              == [.pinnedHeader, .sectionDivider, .newTab, .todayItem], "Today items keep the divider without pinned items")
        //
        // pinned row 41 points on and nothing is listed after it.
        check(L.tablistSlots(pinnedItems: 2, todayItems: 0, isPrivate: false)
              == [.pinnedHeader, .pinnedItem, .pinnedItem, .newTab], "an empty Today lists no divider and no hint")
        check(L.tablistSlots(pinnedItems: 0, todayItems: 0, isPrivate: false) == [.pinnedHeader, .newTab], "an empty Space: header and New Tab")
        check(L.tablistSlots(pinnedItems: 0, todayItems: 2, isPrivate: true)
              == [.privateHeading, .newTab, .todayItem, .todayItem], "private windows: heading, New Tab, Today")
        check(L.tablistSlots(pinnedItems: 0, todayItems: 0, isPrivate: true) == [.privateHeading, .newTab], "an empty private window: heading and New Tab")
        check(T.pinnedHeader.row == .gap(height: 2) && T.sectionDivider.row == .accessory(height: 24)
              && [T.pinnedItem, .newTab, .todayItem].allSatisfy { $0.row == .item }
              && T.privateHeading.row == .accessory(height: 36), "each slot's cell")
        let lone = L.tablist(L.tablistSlots(pinnedItems: 1, todayItems: 0, isPrivate: false).map(\.row))
        check(lone.views[2]!.minY - lone.views[1]!.minY == 41, "without Today, New Tab's visible row is the next item's, 41 points on")
        //
        // full-width cell (10 inside Parc's list), a one-pixel border.
        check(L.sectionDividerInset == 10 && L.sectionDividerSpacing == 8, "divider insets and spacing")
        check(L.sectionDividerThickness(scale: 2) == 0.5 && L.sectionDividerThickness(scale: 1) == 1
              && L.sectionDividerThickness(scale: 3) == 2.0 / 3 && L.sectionDividerThickness(scale: 0) == 1,
              "the border is round(0.5 × scale) / scale points")

        //
        // still): outline at 87 with rows header, one pinned tab, separator,
        // New Tab and four Today tabs, 3, 41, 25 and 41-point rows. The model
        // puts the pinned cell at 90 (visible 92), the divider at 131, New Tab
        // at 156 (visible 158) and the Today rows from 197 (visible 199).
        let top = L.tablistTop(trayHeight: 0)
        let captured = L.tablistSlots(pinnedItems: 1, todayItems: 4, isPrivate: false).map(\.row)
        let still = L.tablist(captured)
        check(still.views.compactMap { $0.map { top + $0.minY } } == [92, 131, 158, 199, 240, 281, 322], "the 1.170 sequence")
        let starts = zip(captured, still.views).map { row, span -> CGFloat in
            guard let span else { return 0 }
            return row == .item ? span.minY - (L.tablistCellHeight - L.tablistVisibleRowHeight) / 2 : span.minY
        } + [still.height - L.tablistBottomInset]
        check(zip(starts, starts.dropFirst()).map { $1 - $0 } == [3, 41, 25, 41, 41, 41, 41, 41], "row heights as captured")

        // Dock: the + button 8 from the edge, centred in 50 points.
        check(L.dockTrailingButton(width: 228, height: 800) == CGRect(x: 188, y: 759, width: 32, height: 32), "trailing dock button at width − 40")
        // leftButtonPlaceholder holds the Library entry (HomeBadging.HomeButton):
        // 32 × 32 at x 8, centred; the Space strip runs between the two buttons.
        check(L.dockLeadingButton(height: 800) == CGRect(x: 8, y: 759, width: 32, height: 32), "leading dock button (Library entry) at x 8")
        check(L.dockStrip(width: 228, height: 800) == CGRect(x: 40, y: 750, width: 148, height: 50), "Space strip at 40…width − 40, the dock's height")
        for width: CGFloat in [164, 228, 500] {
            let strip = L.dockStrip(width: width, height: 800)
            check(strip.minX == L.dockLeadingButton(height: 800).maxX && strip.maxX == L.dockTrailingButton(width: width, height: 800).minX,
                  "the strip abuts both dock buttons at \(width)")
        }
        check(L.dockStrip(width: 60, height: 800).width == 0, "a strip narrower than the two buttons collapses to nothing")

        //
        // default width is 228 − 80 = 148 with 2-point insets, 144 available.
        let three = L.dockLayout(width: 148, height: 50, count: 3, focused: nil)
        check(three.items == [21, 55, 89].map { CGRect(x: $0, y: 9, width: 34, height: 32) }, "34-point items centred as a group")
        check(three.contentWidth == 123 && !three.compact, "content width is the items plus the centring offset")
        check(L.dockLayout(width: 148, height: 50, count: 3, focused: 1) == three, "a regular pitch ignores focus")
        check(L.dockLayout(width: 136, height: 50, count: 6, focused: nil).compact == false, "a 22-point pitch stays regular")
        check(L.dockLayout(width: 135, height: 50, count: 6, focused: nil).compact, "below 22 the items become dots")
        let dots = L.dockLayout(width: 148, height: 50, count: 8, focused: nil)
        check(dots.compact && dots.items.allSatisfy { $0.width == 18 } && dots.items.first?.minX == 0 && dots.contentWidth == 144, "compact pitch fills the strip")
        let focused = L.dockLayout(width: 148, height: 50, count: 8, focused: 2)
        check(focused.compact && focused.items[2].width == 22, "the focused item widens to 22")
        check(focused.items.enumerated().allSatisfy { $0.offset == 2 || abs($0.element.width - 122.0 / 7) < 0.0001 }, "the others share the rest")
        check(abs(focused.contentWidth - 144) < 0.0001, "focus keeps the content inside the strip")
        check(L.dockLayout(width: 148, height: 50, count: 8, focused: 8) == dots, "an out-of-range focus is ignored")
        let overflow = L.dockLayout(width: 148, height: 50, count: 20, focused: nil)
        check(overflow.items.allSatisfy { $0.width == 8 } && overflow.items.first?.minX == 0 && overflow.contentWidth == 160, "more Spaces than 8-point pitches scroll")
        let overflowFocused = L.dockLayout(width: 148, height: 50, count: 20, focused: 19)
        check(overflowFocused.items[19].width == 22 && overflowFocused.items[0].width == 8 && overflowFocused.contentWidth == 174, "focus widens overflowing dots")
        check(L.dockLayout(width: 148, height: 20, count: 2, focused: nil).items.allSatisfy { $0.height == 20 && $0.minY == 0 }, "items never exceed the strip height")
        check(L.dockLayout(width: 148, height: 50, count: 0, focused: 0) == .init(items: [], contentWidth: 0, compact: false), "no Spaces")
        for width in stride(from: 30.0, through: 400, by: 7) {
            for itemCount in 1...40 {
                for focus in [nil, 0, itemCount / 2, itemCount - 1] as [Int?] {
                    let dock = L.dockLayout(width: width, height: 50, count: itemCount, focused: focus)
                    let available = width - 4
                    check(dock.items.count == itemCount && dock.items.allSatisfy { $0.minY == 9 && $0.height == 32 }, "rows at \(width)")
                    check(zip(dock.items, dock.items.dropFirst()).allSatisfy { abs($0.maxX - $1.minX) < 0.0001 }, "items abut at \(width)")
                    check(abs(dock.contentWidth - dock.items[itemCount - 1].maxX) < 0.0001, "content ends at the last item at \(width)")
                    let unfocused = dock.items.enumerated().filter { $0.offset != focus || !dock.compact }.map(\.element.width)
                    check(unfocused.allSatisfy { $0 >= 8 && $0 <= 34 && abs($0 - unfocused[0]) < 0.0001 }, "one shared pitch at \(width)")
                    check(dock.compact == (unfocused[0] < 22), "dots exactly below 22 at \(width)")
                    if let focus, dock.compact { check(dock.items[focus].width == 22, "focused dot keeps 22 at \(width)") }
                    if dock.contentWidth <= available + 0.0001 {
                        let lead = dock.items[0].minX, trail = available - dock.items[itemCount - 1].maxX
                        check(lead >= -0.0001 && abs(lead - trail) < 0.0001, "fitting items are centred at \(width)")
                    } else { check(dock.items[0].minX == 0, "overflow starts at the inset at \(width)") }
                }
            }
        }

        //
        typealias P = L.DockItemPresentation
        check(L.dockIconless(hasCustomIcon: false, symbol: "circle.fill"), "default Space sentinel is iconless")
        check(L.dockIconless(hasCustomIcon: false, symbol: "circle"), "staged Space sentinel is iconless")
        check(!L.dockIconless(hasCustomIcon: true, symbol: "circle"), "custom icon overrides the staged sentinel")
        check(!L.dockIconless(hasCustomIcon: false, symbol: "star"), "legacy custom symbols remain visible")
        check(!L.dockShowsSpaces(count: 1, anyCustomIcon: false, creating: false), "one iconless Space is omitted from the dock")
        check(!L.dockShowsSpaces(count: 0, anyCustomIcon: false, creating: false), "no Spaces")
        check(L.dockShowsSpaces(count: 1, anyCustomIcon: true, creating: false), "a lone custom icon remains in the dock")
        check(L.dockShowsSpaces(count: 2, anyCustomIcon: false, creating: false), "two Spaces show the switcher")
        check(L.dockShowsSpaces(count: 1, anyCustomIcon: false, creating: true), "Create Space keeps the collection")
        check(L.dockItemPresentation(compact: false, selection: 1, highlighted: false, dark: false, iconless: true) == P.dot(side: 8, alpha: 1), "selected iconless Space is a full opacity eight point dot")
        check(L.dockItemPresentation(compact: true, selection: 0, highlighted: false, dark: true, iconless: true) == P.dot(side: 8, alpha: 0.35), "compact iconless Space keeps its eight point dot")
        check(L.dockItemPresentation(compact: false, selection: 0, highlighted: true, dark: false, iconless: true) == P.dot(side: 8, alpha: 0.7), "hovered iconless Space uses the highlighted alpha")
        check(L.dockItemPresentation(compact: true, selection: 0, highlighted: false, dark: false) == P.dot(side: 4, alpha: 0.5), "light dot")
        check(L.dockItemPresentation(compact: true, selection: 0, highlighted: false, dark: true) == P.dot(side: 4, alpha: 0.35), "dark dot")
        check(L.dockItemPresentation(compact: true, selection: 1, highlighted: false, dark: false) == P.icon(active: 1, inactive: 0), "a selected dot shows its icon")
        check(L.dockItemPresentation(compact: true, selection: 0, highlighted: true, dark: true) == P.icon(active: 0.7, inactive: 0), "a highlighted dot shows its icon")
        check(L.dockItemPresentation(compact: false, selection: 0, highlighted: false, dark: false) == P.icon(active: 0, inactive: 0.5), "resting icon")
        check(L.dockItemPresentation(compact: false, selection: 0, highlighted: false, dark: true) == P.icon(active: 0, inactive: 0.35), "dark resting icon")
        check(L.dockItemPresentation(compact: false, selection: 0, highlighted: true, dark: false) == P.icon(active: 0.7, inactive: 0), "highlighted icon")
        check(L.dockItemPresentation(compact: false, selection: 1, highlighted: true, dark: false) == P.icon(active: 1, inactive: 0), "selected icon")
        check(L.dockItemPresentation(compact: false, selection: 0.5, highlighted: false, dark: false) == P.icon(active: 0.5, inactive: 0.25), "selection cross-fades the icons")
        print("SidebarChromeLayout: \(count) assertions passed")
    }
}
