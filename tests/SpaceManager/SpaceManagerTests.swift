import AppKit

/// Inert original production cards/list responders. The window is never shown
/// or activated; its key-state accessor is a local stand-in, and keyDown is
/// called directly. No system input dispatch, browser, engine or real profile.
/// The app reports itself active only where a check says so.
@MainActor final class ManagerTestApplication: NSApplication {
    var simulatedActive = false
    override var isActive: Bool { simulatedActive }
}
@MainActor final class ManagerTestWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
    /// Where a check puts the pointer; nil reads the real one.
    var pointer: NSPoint?
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer ?? super.mouseLocationOutsideOfEventStream }
}
/// An enter event for one named tracking area, as AppKit delivers it.
final class AreaEvent: NSEvent {
    var area: NSTrackingArea?
    override var trackingArea: NSTrackingArea? { area }
}
@main @MainActor struct SpaceManagerTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    static func main() {
        precondition(ManagerTestApplication.shared is ManagerTestApplication, "the checks' application is the first")
        let manager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
        let window = ManagerTestWindow(contentRect: manager.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.contentView = manager
        defer { window.contentView = nil }
        var state = BrowserState.initial()
        let space = state.spaces[0]
        func tab(_ name: String) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://example.test/\(name)", title: name,
                kind: .today, createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/\(name)", savedTitle: name)
        }
        let one = tab("one"), two = tab("two")
        state.tabs = [one, two]; state.selectedTabIDs = []
        var available = true, selected: [UUID] = [], cancelled = 0
        manager.ownerValid = { available }
        manager.onClose = { cancelled += 1 }
        manager.configureSidebar = { id, sidebar in
            sidebar.prepareTabActivation = { expected in
                guard available, expected.spaceID == id else { return nil }
                return { guard available else { return false }; selected.append(expected.id); return true }
            }
            sidebar.configureManagementInteraction(ownerValid: { available }, onCancel: { if available { manager.onClose?() } })
        }
        manager.reload(state); manager.layoutSubtreeIfNeeded()
        let sidebar = manager.sidebar(for: space.id)!
        check(sidebar.isSpaceManagement && sidebar.canSelectItems?() == true, "actual manager card installs its input owner")
        check(window.makeFirstResponder(sidebar), "inert list responder accepts focus")
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        sidebar.keyDown(with: key(125))
        check(selected == [two.id], "Down reaches the actual second original tab activation")
        sidebar.keyDown(with: key(126))
        check(selected.last == one.id, "Up reaches the actual first original tab activation")
        sidebar.keyDown(with: key(125, [.shift]))
        check(selected.last == two.id && selected.count == 3, "Shift singleton selection uses the same prepared activation")
        available = false; sidebar.keyDown(with: key(125))
        check(selected.count == 3, "expired manager owner cannot activate by keyboard")
        available = true; sidebar.keyDown(with: key(53))
        check(cancelled == 1, "Escape on the unselected list reaches manager close")
        let first = BrowserFolder(id: UUID(), spaceID: space.id, name: "A")
        let second = BrowserFolder(id: UUID(), spaceID: space.id, name: "B")
        state.folders = [first, second]
        state.splitLayouts = [BrowserSplitLayout(sidebarAnchorID: one.id, spaceID: space.id, tabIDs: [one.id, two.id], widthFactors: [0.5, 0.5])]
        manager.reload(state); manager.layoutSubtreeIfNeeded()
        let rows = descendants(sidebar).filter { $0 is SidebarFolderRow || $0 is SidebarSplitGroupView }
        check(rows.count == 3, "real card includes both folders and its split row")
        let names = rows.flatMap { ($0.accessibilityCustomActions() ?? []).map(\.name) }
        check(!names.contains("Duplicate Selection") && !names.contains("Close Tabs in Selection") && !names.contains("Delete or Archive Selection") && !names.contains("Rename Split View"), "manager AX exposes no unowned selection or split rename actions")
        let folders = rows.compactMap { $0 as? SidebarFolderRow }
        check(folders[0].accessibilityCustomActions()?.first(where: { $0.name == "Add or Remove from Selection" })?.handler?() == true, "actual folder AX selection is implemented")
        check(window.makeFirstResponder(sidebar), "focus actual list after folder selection")
        sidebar.keyDown(with: key(53))
        check(cancelled == 1, "first Escape clears the existing selection: \(cancelled)")
        sidebar.keyDown(with: key(53))
        check(cancelled == 2, "next Escape leaves the manager")
        available = false; sidebar.cancelOperation(nil)
        check(cancelled == 2, "expired owner cannot cancel a replacement context")

        // Space-Management reload fingerprint: title/URL publishes no-op; real
        // membership/order/theme/profile catalog changes still apply.
        var catalog = BrowserState.initial()
        let catalogSpace = catalog.spaces[0]
        let catalogTab = BrowserTab(
            id: UUID(), spaceID: catalogSpace.id, profileID: catalogSpace.profileID,
            url: "https://example.test/catalog", title: "Catalog",
            kind: .today, createdAt: Date(), lastAccessed: Date(),
            savedURL: "https://example.test/catalog", savedTitle: "Catalog")
        catalog.tabs = [catalogTab]
        check(!SpaceManagerReloadSkip.shouldSkip(previous: nil, next: catalog),
              "first apply has no prior fingerprint")
        check(SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: catalog),
              "identical catalog is a true no-op")
        var titled = catalog
        titled.tabs[0].title = "Unrelated live title"
        titled.tabs[0].url = "https://example.test/catalog-live"
        check(SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: titled),
              "live title/URL publishes skip Space Management reload")
        var themed = catalog
        themed.spaces[0].theme = .singleColor(ThemeColor(hex: "112233")!)
        check(!SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: themed),
              "Space theme changes still reload")
        var reordered = catalog
        let extra = BrowserSpace(id: UUID(), name: "Second", symbol: "star.fill",
                                 color: "AABBCC", profileID: catalogSpace.profileID)
        reordered.spaces.append(extra)
        check(!SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: reordered),
              "Space membership/order changes still reload")
        var profiled = catalog
        profiled.profiles[0].name = "Renamed Profile"
        check(!SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: profiled),
              "Profile changes still reload")
        var selectionChanged = catalog
        selectionChanged.selectedTabIDs = [catalogTab.id]
        check(!SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: selectionChanged),
              "Selection changes still reload")

        let fingerprintManager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
        fingerprintManager.ownerValid = { true }
        fingerprintManager.reload(catalog)
        let hosted = fingerprintManager.sidebar(for: catalogSpace.id)!
        fingerprintManager.reload(titled)
        check(fingerprintManager.sidebar(for: catalogSpace.id) === hosted,
              "title/URL publish retains the already-applied Space Management card")
        fingerprintManager.previewTheme(themed.spaces[0].theme, spaceID: catalogSpace.id)
        fingerprintManager.reload(catalog)
        check(fingerprintManager.sidebar(for: catalogSpace.id) === hosted,
              "cancel after theme preview still reapplies through reload")
        fingerprintManager.reload(themed)
        check(fingerprintManager.sidebar(for: catalogSpace.id) != nil,
              "committed Space theme change still reloads Space Management")

        checkCards()
        print("SpaceManager: \(count) assertions passed")
    }

    ///
    /// cards, controls, header rule, divider, Today drops and Clear targets.
    static func checkCards() {
        typealias Layout = SpaceManagementLayout
        check(Layout.cardFrame(index: 0, height: 650) == NSRect(x: 24, y: 48, width: 240, height: 554), "first card: 24 leading, 48 top/bottom, 240 wide")
        check(Layout.cardFrame(index: 2, height: 650).minX == 24 + 2 * 264, "cards sit 24 apart")
        check(Layout.addItemFrame(count: 3, height: 650) == NSRect(x: 24 + 3 * 264, y: 301, width: 48, height: 48),
              "the 48-point add item follows the last card's gap, centred on the height")
        check(Layout.addCircleFrame(count: 3, height: 650) == NSRect(x: 24 + 3 * 264 + 9, y: 310, width: 30, height: 30),
              "the 30-point add circle is centred in its item")
        check(Layout.contentWidth(count: 3) == 24 + 3 * 264 + 48 + 24, "the collection ends 24 after the add item")
        let cardBounds = NSRect(x: 0, y: 0, width: 240, height: 554)
        check(Layout.sidebarFrame(in: cardBounds) == NSRect(x: 0, y: 5, width: 240, height: 505), "the sidebar sits 5 below the top and 44 above the bottom")
        check(Layout.controlsFrame(in: cardBounds) == NSRect(x: 0, y: 515, width: 240, height: 34), "the 34-point controls sit 5 above the bottom")

        var state = BrowserState.initial()
        let first = state.spaces[0]
        func tab(_ name: String, _ kind: TabKind, in space: BrowserSpace) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://example.test/\(name)", title: name,
                kind: kind, createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/\(name)", savedTitle: name)
        }
        let pinned = tab("pinned", .pinned, in: first), today = tab("today", .today, in: first), later = tab("later", .today, in: first)
        state.tabs = [pinned, today, later]
        let manager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 1200, height: 650))
        let window = ManagerTestWindow(contentRect: manager.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.contentView = manager
        defer { window.contentView = nil }
        var cleared: [UUID] = [], clearable = true
        manager.ownerValid = { true }
        manager.configureSidebar = { id, sidebar in
            sidebar.onClearToday = { cleared.append(id) }
            sidebar.canClearToday = { clearable }
        }
        manager.reload(state); manager.layoutSubtreeIfNeeded()
        let sidebar = manager.sidebar(for: first.id)!
        let header = descendants(sidebar).compactMap { $0 as? SidebarSpaceHeaderView }.first!
        check(header.isHidden, "a single unnamed Space's card hides its header, as the window's sidebar does")
        check(window.makeFirstResponder(sidebar), "inert card list accepts focus before renaming")
        check(sidebar.beginSpaceNameEditing(first) { _ in }, "Rename Space enters the card's real header")
        check(!header.isHidden, "renaming reveals the otherwise hidden header")
        let list = descendants(sidebar).compactMap { $0 as? SidebarTabRow }.first!.enclosingScrollView!
        let listTop = { list.frame.minY }
        check(listTop() == header.frame.maxY && header.frame.minY == SidebarChromeLayout.SpaceHeader.topPadding,
              "the revealed header sits its padding below the top with the list after it")
        sidebar.cancelSpaceNameEditing(); sidebar.layoutSubtreeIfNeeded()
        check(header.isHidden && listTop() == 0, "cancelling the rename hides the header again without a catalog change")

        let theme = sidebar.superview as! ThemeRendererView, card = theme.superview!
        check(!theme.drawsMaterial, "a card paints its theme without the behind-window material")
        check(card.frame == Layout.cardFrame(index: 0, height: manager.bounds.height), "the actual card uses the recovered frame")
        check(sidebar.frame == Layout.sidebarFrame(in: card.bounds), "the actual sidebar uses the card's sidebar inset")
        let grip = descendants(card).first { $0.parcTooltip?.label == "Drag to Reorder Space" }
        let more = descendants(card).compactMap { $0 as? NSButton }.first { $0.parcTooltip?.label == "More options" }
        let controls = Layout.controlsFrame(in: card.bounds)
        check(grip?.frame == NSRect(x: 8, y: controls.midY - 14, width: 28, height: 28), "the move handle is a 28-point leading control")
        check(more?.frame == NSRect(x: 240 - 36, y: controls.midY - 14, width: 28, height: 28) && more?.accessibilityLabel() == "Space Options",
              "More options is a 28-point trailing control that keeps its accessible name")
        check(manager.anchor(for: first.id) === more, "a hidden header leaves the card's theme and icon popovers on More")
        // More's keyboard ring follows its 6-point hover fill.
        check(more?.focusRingType == .exterior && more?.focusRingMaskBounds == more?.bounds, "More draws an exterior keyboard ring over its bounds")
        let mask = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 28, pixelsHigh: 28, bitsPerSample: 8, samplesPerPixel: 4,
                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: mask)
        NSColor.black.setFill(); more?.drawFocusRingMask()
        NSGraphicsContext.restoreGraphicsState()
        func maskAlpha(_ x: Int, _ y: Int) -> CGFloat { mask.colorAt(x: x, y: y)!.alphaComponent }
        check(maskAlpha(14, 14) > 0.99 && maskAlpha(14, 0) > 0.99 && maskAlpha(0, 0) < 0.01, "the ring mask fills More with rounded corners")
        check(maskAlpha(1, 1) < 0.3 && maskAlpha(1, 2) > 0.6, "the mask's corners have radius 6, as the hover fill's")
        let add = descendants(manager).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Create a Space" }!
        check(add.frame.size == NSSize(width: 30, height: 30) && add.frame.minX == card.frame.maxX + 24 + 9
              && add.frame.midY == card.frame.midY, "the add circle follows the last card, centred on it")

        let buttons = descendants(sidebar).compactMap { $0 as? ActionButton }
        check(!descendants(sidebar).contains { $0 is SidebarNewTabRow }, "a card has no New Tab row")
        let clear = buttons.first { $0.identifier?.rawValue == "sidebarClear" }!
        check(clear.title == "Clear" && clear.isEnabled && clear.font == NSFont.systemFont(ofSize: 10, weight: .semibold) && clear.image != nil,
              "the card's Clear is the arrow-and-label button")
        //
        check(!clear.isHidden && clear.alphaValue == 1, "a card shows Clear without the pointer over it")
        let section = clear.superview!
        let line = section.subviews.compactMap { $0 as? SidebarHairline }.first!
        let inset = SidebarChromeLayout.sectionDividerInset
        let thickness = SidebarChromeLayout.sectionDividerThickness(scale: window.backingScaleFactor)
        check(!section.subviews.contains { $0 is NSBox }, "the card divider has no separate separator row")
        check(line.frame.height == thickness && abs(line.frame.midY - clear.frame.midY) <= thickness / 2
              && line.frame.maxX == clear.frame.minX - SidebarChromeLayout.sectionDividerSpacing && line.frame.minX == inset,
              "the border runs from the cell's inset to 8 before Clear, on Clear's row")
        clear.sendAction(clear.action, to: clear.target)
        check(cleared == [first.id], "the card's Clear reaches its own Space's handler")
        func rgba(_ color: NSColor?) -> [CGFloat] {
            let c = color!.usingColorSpace(.sRGB)!
            return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { ($0 * 100).rounded() / 100 }
        }
        /// ForegroundTertiary: black or white at 0.3; ForegroundPrimary 0.9 or 0.8.
        func resting(_ color: NSColor?) -> Bool { let v = rgba(color); return v[3] == 0.3 && (v[0] == 0 || v[0] == 1) && v[0] == v[1] && v[1] == v[2] }
        func hovered(_ color: NSColor?) -> Bool { [0.8, 0.9].contains(rgba(color)[3]) }
        check(resting(clear.contentTintColor), "a resting card Clear is ForegroundTertiary")
        let enter = AreaEvent(); clear.mouseEntered(with: enter)
        check(clear.hovered && hovered(clear.contentTintColor), "hovering a card's Clear tints it ForegroundPrimary")
        clear.mouseExited(with: enter)
        check(!clear.hovered && resting(clear.contentTintColor), "leaving restores the resting tint")
        // Another window can take every Today page, or release one, without a
        // card render: the card re-reads canClearToday as the pointer enters it
        // or Clear, and as its window becomes key.
        sidebar.updateTrackingAreas()
        let reveal = AreaEvent()
        reveal.area = sidebar.trackingAreas.first { $0.owner === sidebar && $0.options.contains(.activeInActiveApp) }
        check(reveal.area != nil, "the card sidebar tracks the pointer entering it")
        clearable = false
        sidebar.mouseEntered(with: reveal)
        check(!clear.isEnabled, "with nothing it may clear, the card's Clear is disabled as the window's is without Today tabs")
        clearable = true
        sidebar.mouseEntered(with: enter)
        check(!clear.isEnabled, "another tracking area's entry does not re-read Clear")
        sidebar.mouseEntered(with: reveal)
        check(clear.isEnabled, "Clear re-enables once a Today page is clearable again")
        func windowBecomesKey() { NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window) }
        clearable = false; windowBecomesKey()
        check(!clear.isEnabled, "the window becoming key disables a Clear with nothing to clear")
        // Released while the pointer is already in the card: Clear's own entry
        // re-reads before its hover reads isEnabled.
        clearable = true
        clear.mouseEntered(with: enter)
        check(clear.isEnabled && clear.hovered && hovered(clear.contentTintColor), "entering Clear re-enables it and hovers it at once")
        clearable = false; windowBecomesKey()
        check(!clear.isEnabled && !clear.hovered && resting(clear.contentTintColor), "disabling a hovered Clear drops its ForegroundPrimary tint")
        clear.mouseEntered(with: enter)
        check(!clear.isEnabled && !clear.hovered, "entering a Clear with nothing to clear shows no hover")
        clear.mouseExited(with: enter)
        clearable = true; windowBecomesKey()
        check(clear.isEnabled, "after a release the window becoming key re-enables Clear, for keyboard and VoiceOver")
        clearable = false
        var grown = state; grown.tabs.append(tab("grown", .today, in: first))
        manager.reload(grown); manager.layoutSubtreeIfNeeded()
        let rendered = descendants(sidebar).compactMap { $0 as? ActionButton }.first { $0.identifier?.rawValue == "sidebarClear" }!
        check(rendered !== clear && !rendered.isEnabled, "a render with nothing clearable starts disabled")
        clearable = true
        manager.reload(state); manager.layoutSubtreeIfNeeded()

        //
        // trailing edge: the label extends its 2-point alignment inset past both.
        let todayRow = descendants(sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == today.id }!
        let title = descendants(todayRow).compactMap { $0 as? SidebarChromeLabel }.first { $0.stringValue == "today" }!
        let titleFrame = title.convert(title.bounds, to: todayRow)
        check(titleFrame.minX == SidebarRowAppearance.titleInset - SidebarRowAppearance.titleTextPadding
              && titleFrame.maxX == SidebarRowAppearance.titleTrailingEdge(in: todayRow.bounds, closeVisible: false) + SidebarRowAppearance.titleTextPadding,
              "the idle title label extends 2 past the inset and the trailing edge (\(titleFrame))")
        check(descendants(todayRow).allSatisfy { !($0 is SidebarTitleField) }, "a row builds its rename field for its first rename")
        // The row re-reads its hover from the pointer as its tracking updates.
        window.pointer = todayRow.convert(NSPoint(x: todayRow.bounds.midX, y: todayRow.bounds.midY), to: nil)
        todayRow.updateTrackingAreas(); todayRow.layoutSubtreeIfNeeded()
        let close = descendants(todayRow).compactMap { $0 as? SidebarRowActionButton }.first { $0.accessibilityLabel() == "Archive Tab" }!
        let hoveredTitle = title.convert(title.bounds, to: todayRow)
        check(!close.isHidden && hoveredTitle.maxX == close.frame.minX && hoveredTitle.maxX - SidebarRowAppearance.titleTextPadding < close.frame.minX,
              "a hovered title's text stops 2 before the ×, its frame at the × (\(hoveredTitle), × \(close.frame))")
        check(todayRow.beginTitleEditing("today") { _ in }, "the row's rename begins")
        todayRow.layoutSubtreeIfNeeded()
        let renameField = descendants(todayRow).compactMap { $0 as? SidebarTitleField }.first!
        let editing = renameField.convert(renameField.bounds, to: todayRow)
        check(editing.minX == titleFrame.minX && editing.maxX == todayRow.bounds.width - 8, "renaming edits from the title's frame to 8 inside the row")
        todayRow.cancelTitleEditing()
        window.pointer = nil; todayRow.updateTrackingAreas(); todayRow.layoutSubtreeIfNeeded()
        check(renameField.convert(renameField.bounds, to: todayRow) == title.convert(title.bounds, to: todayRow)
              && renameField.convert(renameField.bounds, to: todayRow) == titleFrame, "after a rename the field keeps the idle title's frame")
        let glyphs = title.bitmapImageRepForCachingDisplay(in: title.bounds)!
        title.cacheDisplay(in: title.bounds, to: glyphs)
        let scale = CGFloat(glyphs.pixelsWide) / title.bounds.width
        let firstInk = (0..<glyphs.pixelsWide).first { x in (0..<glyphs.pixelsHigh).contains { glyphs.colorAt(x: x, y: $0)!.alphaComponent > 0.25 } }!
        check((2...3).contains(CGFloat(firstInk) / scale), "AppKit draws the label's text 2 points in, so ink starts at the inset (\(CGFloat(firstInk) / scale))")

        check(todayRow.beginRename == nil && todayRow.parcTooltip == SidebarTabRow.rowTooltip(today, renameable: false)
              && todayRow.parcTooltip?.style == .label(subtitle: nil),
              "a card's row offers no double-click rename, so its tooltip carries no rename hint")

        checkWindowDivider(state: state, pinned: pinned, resting: resting, hovered: hovered)
        checkNewTabRow(state: state)
        checkNewTabPlaceholder(state: state)
        checkRowTooltips(state: state, pinned: pinned, today: today)
        checkTablistBackground(state: state)

        // Clear's targets: that Space's unarchived Today tabs in its Profile only.
        var archived = tab("archived", .today, in: first); archived.archivedAt = Date()
        let second = BrowserSpace(id: UUID(), name: "Second", symbol: "star.fill", color: "AABBCC", profileID: first.profileID)
        let elsewhere = tab("elsewhere", .today, in: second)
        var otherProfile = tab("other-profile", .today, in: first); otherProfile.profileID = UUID()
        var targets = state; targets.tabs += [archived, elsewhere, otherProfile]
        check(SpaceClearToday.ids(in: targets, spaceID: first.id, profileID: first.profileID) == [today.id, later.id],
              "Clear archives only the card Space's live Today tabs")
        check(SpaceClearToday.ids(in: targets, spaceID: second.id, profileID: second.profileID) == [elsewhere.id],
              "another card's Clear targets its own Space")

        // Without New Tab, Today begins below the divider for drops, or below
        // the last row when no divider is listed.
        final class DragSource: NSView, SidebarItemDragSource { var sidebarDrag: SidebarMoveSession? }
        let source = DragSource(frame: .zero); manager.addSubview(source)
        var commits: [(SidebarContainerLocation, SidebarItemReference?)] = []
        func drop(_ item: UUID, at point: NSPoint) {
            let session = SidebarMoveSession(items: [.tab(item)], window: window, validate: { true },
                propose: { _, _ in true }, commit: { location, before in commits.append((location, before)); return true })
            source.sidebarDrag = session
            let info = CardDrop()
            info.draggingSource = source; info.draggingDestinationWindow = window
            info.draggingPasteboard.clearContents()
            info.draggingPasteboard.setString(session.identifier.uuidString, forType: SidebarMoveSession.pasteboardType)
            info.draggingLocation = sidebar.convert(point, to: nil)
            _ = sidebar.performDragOperation(info)
            info.draggingPasteboard.releaseGlobally()
        }
        let rows = descendants(sidebar).compactMap { $0 as? SidebarTabRow }
        let lastToday = rows.first { $0.tabID == later.id }!, pinnedRow = rows.first { $0.tabID == pinned.id }!
        let below = sidebar.convert(NSPoint(x: lastToday.bounds.midX, y: lastToday.bounds.maxY + 30), from: lastToday)
        drop(later.id, at: below)
        check(commits.count == 1 && commits[0].0.section == .today && commits[0].0.spaceID == first.id && commits[0].1 == nil,
              "a drop below the Today rows lands at the end of Today")
        let onPinned = sidebar.convert(NSPoint(x: pinnedRow.bounds.midX, y: pinnedRow.bounds.minY + 4), from: pinnedRow)
        drop(later.id, at: onPinned)
        check(commits.count == 2 && commits[1].0.section == .pinned, "a drop on the pinned row stays in Pinned")

        //
        // only while Today has items, in cards as in the window's sidebar.
        let extra = tab("extra", .pinned, in: first)
        var todayless = state; todayless.tabs = [pinned, extra]
        manager.reload(todayless); manager.layoutSubtreeIfNeeded()
        check(!descendants(sidebar).contains { ($0 as? ActionButton)?.identifier?.rawValue == "sidebarClear" }
              && !descendants(sidebar).contains { $0 is SidebarHairline },
              "a card with an empty Today has no divider and no Clear")
        func bottom(_ view: NSView) -> CGFloat { view.convert(view.bounds, to: sidebar).maxY }
        let pinnedRows = descendants(sidebar).compactMap { $0 as? SidebarTabRow }.filter { [pinned.id, extra.id].contains($0.tabID) }
        let lastRow = pinnedRows.max { bottom($0) < bottom($1) }!
        drop(extra.id, at: sidebar.convert(NSPoint(x: lastRow.bounds.midX, y: lastRow.bounds.maxY + 30), from: lastRow))
        check(commits.count == 3 && commits[2].0.section == .today && commits[2].0.spaceID == first.id && commits[2].1 == nil,
              "without a divider, a drop below the card's last row lands in Today")
        drop(extra.id, at: sidebar.convert(NSPoint(x: lastRow.bounds.midX, y: lastRow.bounds.maxY - 4), from: lastRow))
        check(commits.count == 4 && commits[3].0.section == .pinned, "without a divider, a drop on the last pinned row stays in Pinned")

        // With no pinned and no Today items the card lists only the 2-point
        // pinned header, so a hidden header leaves a 2.5-point Pinned band.
        //
        let favorite = tab("favorite", .favorite, in: first)
        var empty = state; empty.tabs = [favorite]
        manager.reload(empty); manager.layoutSubtreeIfNeeded()
        let outline = descendants(sidebar).compactMap { $0 as? SidebarOutlineView }.first!
        let headerRow = outline.convert(outline.rows[0].frame, to: sidebar)
        check(header.isHidden && outline.rows.count == 1 && headerRow.height == SidebarChromeLayout.pinnedHeaderHeight + SidebarChromeLayout.tablistIntercellSpacing
              && !descendants(sidebar).contains { $0 is SidebarHairline },
              "an empty card lists only the pinned header, with no divider")
        drop(favorite.id, at: NSPoint(x: sidebar.bounds.midX, y: headerRow.maxY - SidebarChromeLayout.tablistIntercellSpacing / 2 - 0.5))
        drop(favorite.id, at: NSPoint(x: sidebar.bounds.midX, y: headerRow.maxY + 10))
        check(commits.count == 6 && commits[4].0.section == .pinned && commits[5].0.section == .today && commits[5].0.spaceID == first.id,
              "an empty card's Pinned band ends 2.5 points down, at the header's boundary; below it is Today")

        // A card shows no Profile-wide Favorites tray, so with no Favorites the
        // gap above its shown header takes no Favorite drop.
        var trayless = state; trayless.spaces.append(second); trayless.tabs = [pinned]
        manager.reload(trayless); manager.layoutSubtreeIfNeeded()
        let landed = commits.count
        drop(pinned.id, at: NSPoint(x: sidebar.bounds.midX, y: header.frame.minY / 2))
        check(manager.sidebar(for: first.id) === sidebar && !header.isHidden && header.frame.minY > 0 && !commits.dropFirst(landed).contains { $0.0.section == .favorite },
              "a card takes no Favorite drop above its shown header")
        manager.reload(state); manager.layoutSubtreeIfNeeded()
        source.removeFromSuperview()

        // Two Spaces: each card's header shows, as the window's sidebar's does.
        var pair = state; pair.spaces.append(second); pair.tabs.append(elsewhere)
        manager.reload(pair); manager.layoutSubtreeIfNeeded()
        let headers = pair.spaces.map { space in descendants(manager.sidebar(for: space.id)!).compactMap { $0 as? SidebarSpaceHeaderView }.first! }
        check(headers.allSatisfy { !$0.isHidden && $0.frame.minY == SidebarChromeLayout.SpaceHeader.topPadding },
              "with two Spaces every card shows its header its padding below the top")
        check(zip(pair.spaces, headers).allSatisfy { manager.anchor(for: $0.id) === $1 }, "a shown header anchors its card's popovers")
        let secondCard = manager.sidebar(for: second.id)!.superview!.superview!
        check(secondCard.frame == Layout.cardFrame(index: 1, height: manager.bounds.height), "the second card follows one gap later")
        check(add.frame.minX == secondCard.frame.maxX + 24 + 9, "the add circle moves after the last card")
        checkAddPalette()
    }

    /// Runs the main loop for `timeout`, or until `done` holds: fades end
    /// late on a loaded machine.
    static func settle(timeout: TimeInterval = 0.3, until done: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(timeout)
        while !done(), Date() < end { RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.02))) }
    }

    /// The window sidebar's UnpinnedSectionDividerCellView: Clear is hidden at
    /// rest and shows only while the pointer is over the sidebar and Today has
    ///
    ///
    /// cell's insets while Clear is out of the row. An empty Today lists no
    ///
    static func checkWindowDivider(state: BrowserState, pinned: BrowserTab,
                                   resting: (NSColor?) -> Bool, hovered: (NSColor?) -> Bool) {
        typealias Chrome = SidebarChromeLayout
        func clearButton(_ view: SidebarView) -> ActionButton? {
            descendants(view).compactMap { $0 as? ActionButton }.first { $0.identifier?.rawValue == "sidebarClear" }
        }
        let plain = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        plain.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        plain.layoutSubtreeIfNeeded()
        check(clearButton(plain)?.isEnabled == false, "without a Clear handler the window's Clear is disabled")

        var cleared = 0
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        // Backed (never shown), so the fade's completion runs.
        let window = ManagerTestWindow(contentRect: sidebar.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = sidebar
        defer { window.contentView = nil }
        sidebar.onClearToday = { cleared += 1 }
        sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        sidebar.layoutSubtreeIfNeeded()
        let clear = clearButton(sidebar)!, section = clear.superview!
        let line = section.subviews.compactMap { $0 as? SidebarHairline }.first!
        let inset = Chrome.sectionDividerInset, thickness = Chrome.sectionDividerThickness(scale: window.backingScaleFactor)
        func centre(of view: NSView) -> NSPoint { section.convert(NSPoint(x: view.frame.midX, y: view.frame.midY), to: section.superview) }
        // AppKit exposes a button through its cell.
        func exposed() -> Bool { (section.accessibilityChildren() ?? []).contains { ($0 as AnyObject) === clear || ($0 as AnyObject) === clear.cell } }
        func relayout() { section.needsLayout = true; section.layoutSubtreeIfNeeded() }
        check(section.subviews.count == 2 && !section.subviews.contains { $0 is NSBox }, "the window divider is one row: the border and Clear")
        check(clear.isHidden && clear.alphaValue == 0 && clear.isEnabled, "at rest the window's Clear is hidden")
        check(!clear.canBecomeKeyView && !exposed(), "a hidden Clear is no key view and no accessibility child")
        check(section.hitTest(centre(of: clear)) !== clear, "a hidden Clear takes no clicks")
        check(line.frame.minX == inset && line.frame.width == section.bounds.width - 2 * inset && line.frame.height == thickness
              && abs(line.frame.midY - section.bounds.midY) <= thickness / 2, "at rest the border spans the cell's insets, centred")

        // AppKit replaces the sidebar's tracking area as it lays out; each
        // event names the current one.
        var reveal: AreaEvent {
            let event = AreaEvent()
            event.area = sidebar.trackingAreas.first { $0.owner === sidebar && $0.options.contains(.activeInActiveApp) }
            return event
        }
        // The window reports the pointer where each step puts it.
        func enter() { window.pointer = sidebar.convert(NSPoint(x: 100, y: 300), to: nil); sidebar.mouseEntered(with: reveal) }
        func exit() { window.pointer = NSPoint(x: -100, y: -100); sidebar.mouseExited(with: reveal) }
        sidebar.updateTrackingAreas()
        check(reveal.area != nil, "the window sidebar tracks the pointer entering it")
        sidebar.mouseEntered(with: AreaEvent())
        check(clear.isHidden, "another tracking area's entry leaves Clear hidden")
        enter()
        check(!clear.isHidden, "the pointer entering the sidebar unhides Clear before its fade-in")
        settle(timeout: 3) { clear.alphaValue == 1 }; relayout()
        check(clear.alphaValue == 1, "a revealed Clear is opaque after its fade-in")
        check(exposed(), "a revealed Clear is an accessibility child")
        check(clear.refusesFirstResponder && !clear.acceptsFirstResponder && !clear.canBecomeKeyView
              && !SidebarAccessibility.keyViews(in: [section], space: sidebar).contains { $0 === clear },
              "even revealed, Clear is no key view HoverableView is not")
        let width = ceil(clear.intrinsicContentSize.width)
        let pad = clear.cell!.imageRect(forBounds: NSRect(x: 0, y: 0, width: width, height: 20)).minX
        check(pad > 0 && clear.frame.width == width - pad && clear.frame.height == 20 && clear.frame.maxX == section.bounds.width - inset
              && abs(clear.frame.midY - section.bounds.midY) < 0.01, "Clear hugs its arrow, its cell's inset inside the trailing edge")
        check(line.frame.minX == inset && line.frame.maxX == clear.frame.minX - Chrome.sectionDividerSpacing,
              "while Clear shows the border ends 8 before it")
        check(section.hitTest(centre(of: clear)) === clear
              && section.hitTest(section.convert(NSPoint(x: 20, y: section.bounds.midY), to: section.superview)) !== clear,
              "only a revealed Clear's own width takes its clicks")
        check(clear.parcTooltip == TooltipConfiguration("Clear Today tabs", shortcut: .command("clearToday:")) && clear.toolTip == nil
              && clear.accessibilityLabel() == "Clear" && clear.focusRingType == .none,
              "Clear keeps its Parc tooltip and accessible name and draws no keyboard ring")
        check(clear.font == NSFont.systemFont(ofSize: 10, weight: .semibold) && resting(clear.contentTintColor),
              "a revealed Clear the pointer is not on is ForegroundTertiary")
        clear.mouseEntered(with: AreaEvent())
        check(hovered(clear.contentTintColor), "hovering the window's Clear tints it ForegroundPrimary")
        clear.mouseExited(with: AreaEvent())
        clear.sendAction(clear.action, to: clear.target)
        check(cleared == 1, "the window's Clear reaches its handler")
        // VoiceOver presses the button's exposed cell (AppKit answers false
        // although the press runs the action).
        _ = clear.cell?.accessibilityPerformPress()
        check(cleared == 2, "VoiceOver can press a revealed Clear")

        exit(); relayout()
        check(!clear.isHidden && line.frame.maxX == clear.frame.minX - Chrome.sectionDividerSpacing,
              "Clear keeps its place in the row while it fades out")
        settle(timeout: 3) { clear.isHidden }; relayout()
        check(clear.isHidden, "after its fade-out Clear is hidden again")
        check(!exposed() && !clear.canBecomeKeyView && section.hitTest(centre(of: clear)) !== clear,
              "a Clear hidden again takes no clicks, key focus or accessibility")
        check(line.frame.maxX == section.bounds.width - inset, "the border spans the row again")
        enter(); exit(); enter()
        settle(); settle(timeout: 3) { clear.alphaValue == 1 }; relayout()
        check(!clear.isHidden && clear.alphaValue == 1, "re-entering during the fade-out keeps Clear revealed")
        exit(); settle(timeout: 3) { clear.isHidden }; enter()
        check(!clear.isHidden, "entering unhides Clear for its fade-in")
        // Leaving late in the fade-in: the fade-in's completion falls inside
        // the fade-out and must leave Clear to it.
        RunLoop.main.run(until: Date().addingTimeInterval(0.09)); exit()
        _ = RunLoop.main.run(mode: .default, before: .distantPast)
        check(!clear.isHidden, "leaving during the fade-in still fades Clear out")
        settle(timeout: 3) { clear.isHidden }
        check(clear.isHidden, "and hides it when that fade-out ends")
        enter(); settle(timeout: 3) { clear.alphaValue == 1 }
        var grown = state
        grown.tabs.append(BrowserTab(id: UUID(), spaceID: pinned.spaceID, profileID: pinned.profileID, url: "https://example.test/grown",
                                     title: "grown", kind: .today, createdAt: Date(), lastAccessed: Date(),
                                     savedURL: "https://example.test/grown", savedTitle: "grown"))
        sidebar.render(state: grown, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        sidebar.layoutSubtreeIfNeeded()
        let rendered = clearButton(sidebar)!
        check(rendered !== clear && !rendered.isHidden && rendered.alphaValue == 1, "a render while the sidebar is hovered starts Clear revealed")
        exit(); settle(timeout: 3) { rendered.isHidden }
        check(rendered.isHidden, "and leaving hides the rendered Clear")

        var todayless = state; todayless.tabs = [pinned]
        sidebar.render(state: todayless, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        sidebar.layoutSubtreeIfNeeded()
        enter(); settle()
        check(clearButton(sidebar) == nil && !descendants(sidebar).contains { $0 is SidebarHairline },
              "without Today tabs there is no divider and no Clear, even with the sidebar hovered")
        check(!descendants(sidebar).compactMap { $0 as? NSTextField }.contains { $0.stringValue.localizedCaseInsensitiveContains("new tabs appear") },
              "an empty Today shows no placeholder text")
        let pinnedRow = descendants(sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == pinned.id }!
        let newTab = descendants(sidebar).compactMap { $0 as? SidebarNewTabRow }.first!
        func midY(_ view: NSView) -> CGFloat { view.convert(view.bounds, to: sidebar).midY }
        check(abs(midY(newTab) - midY(pinnedRow)) == Chrome.tablistCellHeight + Chrome.tablistIntercellSpacing,
              "New Tab follows the last pinned row 41 points on")
        exit()

        // Without a divider the pinned section ends at New Tab's row.
        final class DragSource: NSView, SidebarItemDragSource { var sidebarDrag: SidebarMoveSession? }
        let source = DragSource(frame: .zero); sidebar.addSubview(source)
        defer { source.removeFromSuperview() }
        var commits: [SidebarContainerLocation] = []
        func drop(at point: NSPoint) {
            let session = SidebarMoveSession(items: [.tab(pinned.id)], window: window, validate: { true },
                propose: { _, _ in true }, commit: { location, _ in commits.append(location); return true })
            source.sidebarDrag = session
            let info = CardDrop()
            info.draggingSource = source; info.draggingDestinationWindow = window
            info.draggingPasteboard.clearContents()
            info.draggingPasteboard.setString(session.identifier.uuidString, forType: SidebarMoveSession.pasteboardType)
            info.draggingLocation = sidebar.convert(point, to: nil)
            _ = sidebar.performDragOperation(info)
            info.draggingPasteboard.releaseGlobally()
        }
        let newTabFrame = newTab.convert(newTab.bounds, to: sidebar)
        drop(at: NSPoint(x: newTabFrame.midX, y: newTabFrame.midY + (sidebar.isFlipped ? -6 : 6)))
        drop(at: NSPoint(x: newTabFrame.midX, y: newTabFrame.midY + (sidebar.isFlipped ? 6 : -6)))
        check(commits.map(\.section) == [.pinned, .today], "New Tab's upper half ends Pinned and its lower half begins Today")
    }

    /// The tablist's empty area: SidebarView's own press/release routing.
    /// A first press would start a real window drag, so only the routing
    /// around it runs here; SidebarTablistBackground's checks cover its choice.
    static func checkTablistBackground(state: BrowserState) {
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let window = ManagerTestWindow(contentRect: sidebar.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.contentView = sidebar
        defer { window.contentView = nil }
        var opened = 0
        sidebar.onNewTab = { opened += 1 }
        sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        sidebar.layoutSubtreeIfNeeded()
        let list = descendants(sidebar).compactMap { $0 as? SidebarOutlineView }.first!
        let clip = list.enclosingScrollView!.contentView
        let rows = list.rows
        check(!rows.isEmpty, "the list has rows to sit below")
        let lastMaxY = list.convert(rows.last!.bounds, from: rows.last!).maxY
        func mouse(_ type: NSEvent.EventType, at point: NSPoint, clicks: Int, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: list.convert(point, to: nil), modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        let below = NSPoint(x: 100, y: lastMaxY + 30)
        let onRow = NSPoint(x: 100, y: list.convert(rows[0].bounds, from: rows[0]).midY)
        sidebar.mouseDown(with: mouse(.leftMouseDown, at: below, clicks: 2))
        check(opened == 0, "the double-click's second press waits for its release")
        sidebar.mouseUp(with: mouse(.leftMouseUp, at: below, clicks: 2))
        check(opened == 1, "a double-click released below the last row opens the new-tab bar")
        sidebar.mouseUp(with: mouse(.leftMouseUp, at: below, clicks: 1))
        sidebar.mouseUp(with: mouse(.leftMouseUp, at: below, clicks: 2, flags: .control))
        sidebar.mouseUp(with: mouse(.leftMouseUp, at: onRow, clicks: 2))
        check(opened == 1, "a single click, a Control double-click and a row's double-click don't")
        clip.mouseUp(with: mouse(.leftMouseUp, at: below, clicks: 2))
        check(opened == 2, "the list's empty-area release reaches SidebarView through the responder chain")
        sidebar.isSpaceManagement = true
        sidebar.mouseUp(with: mouse(.leftMouseUp, at: below, clicks: 2))
        check(opened == 2, "a Library Space card's list isn't the window background")
    }
    ///
    ///
    /// body's double-click rename those hints promise.
    static func checkRowTooltips(state: BrowserState, pinned: BrowserTab, today: BrowserTab) {
        var renamed = pinned; renamed.id = UUID(); renamed.customTitle = "Mine"
        var document = today; document.id = UUID(); document.url = "parc://note/\(UUID().uuidString)"
        var rows = state; rows.tabs += [renamed, document]
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let window = ManagerTestWindow(contentRect: sidebar.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.contentView = sidebar
        defer { window.contentView = nil }
        var activated: [UUID] = [], committed: [String] = []
        sidebar.prepareTabActivation = { tab in { activated.append(tab.id); return true } }
        sidebar.prepareTabRename = { _ in { committed.append($0); return true } }
        sidebar.render(state: rows, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        sidebar.layoutSubtreeIfNeeded()
        func row(_ tab: BrowserTab) -> SidebarTabRow {
            descendants(sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == tab.id }!
        }
        func closeButton(_ row: SidebarTabRow) -> SidebarRowActionButton {
            descendants(row).compactMap { $0 as? SidebarRowActionButton }.first { $0.parcTooltip?.shortcut == .command("closeTab:") }!
        }
        let hinted = TooltipConfiguration.Style.label(subtitle: SidebarTabRow.renameHint)
        check(row(pinned).parcTooltip == TooltipConfiguration("pinned", style: hinted, anchor: .cursor, behavior: .onMouseIdle(delay: 1.5))
              && row(today).parcTooltip?.style == hinted,
              "an unrenamed pinned or Today row shows its title over the rename hint at the pointer after 1.5 s")
        check(row(renamed).parcTooltip?.label == "Mine" && row(renamed).parcTooltip?.style == .label(subtitle: nil),
              "a renamed row shows its custom title without the hint")
        check(row(document).beginRename == nil && row(document).parcTooltip?.style == .label(subtitle: nil),
              "a document row cannot be renamed and shows no hint")
        let child = SidebarTabRow(tab: today, selected: false, speaker: nil, close: { nil }, reset: { nil }, separate: { nil })
        child.beginRename = { true }
        child.compactSplitChild = true
        check(child.parcTooltip == nil, "a split child ChildItemState, has no row tooltip")
        check(closeButton(row(pinned)).parcTooltip?.label == "Close and Keep Pinned"
              && closeButton(row(today)).parcTooltip?.label == "Archive this tab",
              "a pinned row's close deselects and a Today row's archives, each with Close Tab's binding")

        let target = row(today)
        func press(_ type: NSEvent.EventType, clicks: Int, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil),
                modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func click(_ clicks: Int, _ flags: NSEvent.ModifierFlags = []) {
            target.mouseDown(with: press(.leftMouseDown, clicks: clicks, flags))
            target.mouseUp(with: press(.leftMouseUp, clicks: clicks, flags))
        }
        click(1)
        check(activated == [today.id] && !sidebar.isEditingTitle, "a single click selects the row without renaming it")
        click(2, .command)
        check(!sidebar.isEditingTitle, "a modified double-click does not rename")
        let selections = activated.count
        click(2)
        check(sidebar.isEditingTitle && activated.count == selections,
              "a plain double-click on the row body begins its rename instead of selecting again")
        target.cancelTitleEditing()
        check(!sidebar.isEditingTitle && committed.isEmpty, "cancelling the double-click rename commits nothing")
    }

    ///
    /// CellSelectionStateView hover plate, the SidebarBouncyClickCell press
    /// bounce, and no tooltip.
    static func checkNewTabRow(state: BrowserState) {
        let app = NSApp as! ManagerTestApplication
        app.simulatedActive = true
        defer { app.simulatedActive = false }
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let window = ManagerTestWindow(contentRect: sidebar.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.contentView = sidebar
        window.pointer = NSPoint(x: -100, y: -100)
        defer { window.contentView = nil }
        var opened = 0
        sidebar.onNewTab = { opened += 1 }
        sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        sidebar.layoutSubtreeIfNeeded()
        let row = descendants(sidebar).compactMap { $0 as? SidebarNewTabRow }.first!
        let tab = descendants(sidebar).compactMap { $0 as? SidebarTabRow }.first!
        check(row.bounds.size == NSSize(width: tab.bounds.width, height: SidebarChromeLayout.tablistVisibleRowHeight)
              && row.convert(row.bounds, to: sidebar).minX == tab.convert(tab.bounds, to: sidebar).minX,
              "New Tab takes a tab's whole visible row")
        let icon = descendants(row).compactMap { $0 as? NSImageView }.first!
        let title = descendants(row).compactMap { $0 as? SidebarChromeLabel }.first!
        let slot = SidebarRowAppearance.iconSlotFrame(in: row.bounds)
        check(icon.image === SidebarNewTabAppearance.plus && abs(icon.frame.midX - slot.midX) < 0.01 && abs(icon.frame.midY - slot.midY) < 0.01,
              "the plus is centred in the favicon column")
        let span = SidebarRowAppearance.titleLabelSpan(resettable: false,
                                                       trailing: SidebarRowAppearance.titleTrailingEdge(in: row.bounds, closeVisible: false))
        check(title.frame == NSRect(x: span.minX, y: ((row.bounds.height - 18) / 2).rounded(.down), width: span.width, height: 18)
              && title.stringValue == "New Tab" && title.font == .systemFont(ofSize: SidebarRowAppearance.titleFontSize),
              "New Tab's title is the tab title's 14-point label at its inset")
        func colorsFollow() -> Bool {
            title.textColor == SidebarNewTabAppearance.titleColor(dark: row.dark) && title.alphaValue == 1
                && icon.contentTintColor == SidebarNewTabAppearance.plusColor(dark: row.dark)
        }
        check(colorsFollow(), "the title is SidebarForeground and the plus ForegroundSecondary")
        row.dark.toggle()
        check(colorsFollow(), "both follow the theme's darkness")
        check(!icon.isAccessibilityElement() && !title.isAccessibilityElement() && row.button.accessibilityLabel() == "New Tab",
              "VoiceOver reads one New Tab button")
        check(row.button.toolTip == nil && row.toolTip == nil && row.button.parcTooltip == nil && row.parcTooltip == nil,
              "the New Tab cell installs no tooltip")
        check(row.hitTest(row.convert(NSPoint(x: span.minX + 4, y: row.bounds.midY), to: row.superview)) === row.button
              && row.hitTest(row.convert(NSPoint(x: slot.midX, y: row.bounds.midY), to: row.superview)) === row.button,
              "the whole row is the button")
        row.button.sendAction(row.button.action, to: row.button.target)
        check(opened == 1, "New Tab opens a tab")

        let plate = descendants(row).compactMap { $0 as? SidebarRowBackgroundView }.first!
        check(plate.frame == row.bounds && plate.appearanceState.fill == nil, "at rest the plate is clear")
        row.button.mouseEntered(with: AreaEvent())
        let fill = SidebarRowAppearance.color(.hovered, dark: plate.dark).cgColor
        check(plate.appearanceState.fill == .hovered && plate.fillLayer.backgroundColor.map { CFEqual($0, fill) } == true
              && plate.fillLayer.cornerRadius == SidebarRowAppearance.cornerRadius && plate.fillLayer.cornerCurve == .continuous,
              "hovering fills the row with SidebarItemBackground in 12-point continuous corners")
        row.button.mouseExited(with: AreaEvent())
        check(plate.appearanceState.fill == nil, "leaving clears the plate")

        // `.activeInKeyWindow` tracking sends no exit when the window resigns
        // key, as it does for New Tab's own command bar.
        func centre(of view: NSView) -> NSPoint { view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil) }
        func post(_ name: Notification.Name) { NotificationCenter.default.post(name: name, object: window) }
        window.pointer = centre(of: row); row.button.mouseEntered(with: AreaEvent())
        check(plate.appearanceState.fill == .hovered, "the pointer on New Tab lights the plate")
        window.key = false; post(NSWindow.didResignKeyNotification)
        check(plate.appearanceState.fill == nil, "the window resigning key clears the plate without an exit")
        window.key = true; post(NSWindow.didBecomeKeyNotification)
        check(plate.appearanceState.fill == .hovered, "taking key again under the pointer relights it")
        window.key = false; post(NSWindow.didResignKeyNotification)
        window.pointer = NSPoint(x: -100, y: -100)
        window.key = true; post(NSWindow.didBecomeKeyNotification)
        check(plate.appearanceState.fill == nil && !row.button.hovered, "taking key with the pointer gone leaves the plate clear")

        // A render keeps the one row: New Tab moving under a still pointer
        // lights the plate, which AppKit's tracking does not report.
        var todayless = state; todayless.tabs = state.tabs.filter { $0.kind == .pinned }
        sidebar.render(state: todayless, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        sidebar.layoutSubtreeIfNeeded()
        check(descendants(sidebar).compactMap { $0 as? SidebarNewTabRow }.first === row, "renders keep the one New Tab row")
        let emptyTodayPlace = centre(of: row)
        sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        window.pointer = emptyTodayPlace
        sidebar.layoutSubtreeIfNeeded()
        check(centre(of: row) != emptyTodayPlace && plate.appearanceState.fill == nil, "with Today the row sits below the still pointer")
        sidebar.render(state: todayless, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        sidebar.layoutSubtreeIfNeeded()
        check(centre(of: row) == emptyTodayPlace && plate.appearanceState.fill == .hovered,
              "emptying Today moves New Tab under the pointer and lights its plate")
        window.pointer = NSPoint(x: -100, y: -100); row.button.mouseExited(with: AreaEvent())

        func bounce() -> CASpringAnimation? { row.layer?.animation(forKey: SidebarNewTabRow.bounceKey) as? CASpringAnimation }
        row.button.highlight(true)
        let press = bounce()
        let pressed = (press?.toValue as? NSValue)?.caTransform3DValue
        let squeeze = 1 - SidebarNewTabRow.pressScale
        check(press?.keyPath == "transform" && press?.isRemovedOnCompletion == false && press?.fillMode == .forwards
              && pressed?.m11 == 0.992 && pressed?.m22 == 0.992 && pressed?.m33 == 1
              && abs((pressed?.m41 ?? 0) - squeeze * row.bounds.midX) < 1e-9 && abs((pressed?.m42 ?? 0) - squeeze * row.bounds.midY) < 1e-9,
              "a press springs the row to 0.992 about its centre and holds it")
        check(press?.mass == 1 && abs((press?.stiffness ?? 0) - pow(2 * .pi / 0.2, 2)) < 1e-9
              && abs((press?.damping ?? 0) - 4 * .pi * 0.5 / 0.2) < 1e-9 && press?.duration == press?.settlingDuration,
              "the spring has damping ratio 0.5 and response 0.2 and lasts its settling time")
        row.button.highlight(false)
        check(bounce() === press, "a press dragged off or released outside the row keeps it at 0.992")
        row.button.highlight(true)
        check(bounce() === press, "dragging back onto the row changes nothing")
        row.button.highlight(false)
        check(bounce() === press, "only a completed click releases the press")

        let held = row.frame.size
        row.setFrameSize(NSSize(width: held.width + 100, height: held.height))
        row.layoutSubtreeIfNeeded()
        let moved = (bounce()?.toValue as? NSValue)?.caTransform3DValue
        check(bounce()?.isRemovedOnCompletion == false && (bounce()?.fromValue as? NSValue)?.caTransform3DValue.m41 == moved?.m41
              && abs((moved?.m41 ?? 0) - squeeze * row.bounds.midX) < 1e-9,
              "a held press follows the row's centre when the sidebar resizes, without moving")
        row.setFrameSize(held); row.layoutSubtreeIfNeeded()

        let other = BrowserSpace(id: UUID(), name: "Other", symbol: "star.fill", color: "CC3333", profileID: state.spaces[0].profileID)
        var elsewhere = state; elsewhere.spaces.append(other); elsewhere.activeSpaceID = other.id
        sidebar.render(state: elsewhere, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        check(bounce() == nil, "another Space shows its New Tab unpressed")
        sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        sidebar.layoutSubtreeIfNeeded()
        row.button.highlight(true)
        let repressed = bounce()
        check(repressed !== press && repressed?.isRemovedOnCompletion == false, "the next press springs in again")
        check(row.button.sendAction(row.button.action, to: row.button.target), "the completed click sends New Tab's action")
        let release = bounce()
        check(release !== repressed && release?.isRemovedOnCompletion == true
              && (release?.toValue as? NSValue).map { CATransform3DIsIdentity($0.caTransform3DValue) } == true,
              "the completed click springs the row back to identity")
        check(row.layer.map { CATransform3DIsIdentity($0.transform) } == true, "the bounce never changes the layer's own transform")
        sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
        sidebar.layoutSubtreeIfNeeded()
        check(descendants(sidebar).compactMap { $0 as? SidebarNewTabRow }.first === row && bounce() === release,
              "the tab a click opens re-renders the list without cutting the release bounce off")
    }

    ///
    /// with the current plate and shadow and the palette's title colour, and no
    /// sidebar item is current meanwhile; Favorites do not read it.
    static func checkNewTabPlaceholder(state base: BrowserState) {
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let window = ManagerTestWindow(contentRect: sidebar.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false; window.contentView = sidebar
        window.pointer = NSPoint(x: -100, y: -100)
        defer { window.contentView = nil }
        let space = base.spaces.first { $0.id == base.activeSpaceID }!
        func tab(_ name: String, _ kind: TabKind) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://example.test/\(name)", title: name,
                       kind: kind, createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/\(name)", savedTitle: name)
        }
        let single = tab("single", .today), left = tab("left", .today), right = tab("right", .today), favorite = tab("favorite", .favorite)
        var state = base
        state.tabs = [single, left, right, favorite]
        state.splitLayouts = [BrowserSplitLayout(sidebarAnchorID: left.id, spaceID: space.id, tabIDs: [left.id, right.id], widthFactors: [0.5, 0.5])]
        state.selectedTabIDs = [single.id]
        let palette = ThemeChromePalette(theme: .singleColor(ThemeColor(hex: "3366CC")!), appearance: NSAppearance(named: .aqua)!)
        sidebar.palette = palette
        func render(_ state: BrowserState, focused: UUID) {
            sidebar.render(state: state, focusedTabID: focused, loading: [], canBack: false, canForward: false)
            sidebar.layoutSubtreeIfNeeded()
        }
        render(state, focused: single.id)
        let row = descendants(sidebar).compactMap { $0 as? SidebarNewTabRow }.first!
        let plate = descendants(row).compactMap { $0 as? SidebarRowBackgroundView }.first!
        let title = descendants(row).compactMap { $0 as? SidebarChromeLabel }.first!
        let icon = descendants(row).compactMap { $0 as? NSImageView }.first!
        func fill(of id: UUID) -> SidebarRowAppearance.Fill? {
            let tabRow = descendants(sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == id }!
            return descendants(tabRow).compactMap { $0 as? SidebarRowBackgroundView }.first!.appearanceState.fill
        }
        func idle() -> Bool {
            !row.current && plate.appearanceState.fill == nil && !plate.appearanceState.showsShadow
                && title.textColor == SidebarNewTabAppearance.titleColor(dark: row.dark)
                && icon.contentTintColor == SidebarNewTabAppearance.plusColor(dark: row.dark)
        }
        check(idle(), "at rest New Tab is clear, its title SidebarForeground and its plus ForegroundSecondary")
        check(fill(of: single.id) == .current, "the selected tab is the current item")

        sidebar.newTabPlaceholderActive = true
        let current = SidebarRowAppearance.color(.current, dark: row.dark).cgColor
        check(row.current && plate.appearanceState.fill == .current && plate.appearanceState.showsShadow
              && plate.fillLayer.backgroundColor.map { CFEqual($0, current) } == true,
              "the placeholder gives New Tab the current fill and its shadow")
        check(title.textColor == palette.title && icon.contentTintColor == palette.title, "its title and plus take the palette's title colour")
        check(plate.fillLayer.animationKeys() == nil && title.layer?.animationKeys() == nil, "the look switches without a transition")
        row.button.mouseEntered(with: AreaEvent())
        check(plate.appearanceState.hovered && plate.appearanceState.fill == .current, "hovering keeps the current fill over the hover colour")
        row.button.mouseExited(with: AreaEvent())
        check(!sidebar.applyLivePageMetadata(state: state, focusedTabID: single.id, loading: [], canBack: false, canForward: false),
              "a metadata tick does not keep rows built without the placeholder")
        render(state, focused: single.id)
        check(row.current && fill(of: single.id) == nil, "while it holds, the selected tab is not current")
        check(sidebar.applyLivePageMetadata(state: state, focusedTabID: single.id, loading: [], canBack: false, canForward: false),
              "once a render has used it, metadata ticks take the live path again")

        var splitSelected = state; splitSelected.selectedTabIDs = [left.id, right.id]
        func group() -> SidebarSplitGroupView { descendants(sidebar).compactMap { $0 as? SidebarSplitGroupView }.first! }
        render(splitSelected, focused: left.id)
        check(!group().selected && group().rows.allSatisfy { !$0.splitGroupSelected },
              "a selected split is not current and its children lose their group plate")
        sidebar.newTabPlaceholderActive = false
        render(splitSelected, focused: left.id)
        check(group().selected && group().rows.allSatisfy(\.splitGroupSelected), "without it the selected split is current again")

        var favoriteSelected = state; favoriteSelected.selectedTabIDs = [favorite.id]
        sidebar.newTabPlaceholderActive = true
        render(favoriteSelected, focused: favorite.id)
        check(descendants(sidebar).compactMap { $0 as? FavoriteTile }.first?.selected == true, "a selected Favorite keeps its look")

        sidebar.newTabPlaceholderActive = false
        check(idle(), "closing the bar restores New Tab at once")
        render(state, focused: single.id)
        check(fill(of: single.id) == .current, "and the next render makes the selected tab current again")
    }

    /// The add circle takes its own window's Space theme, resolved under the
    /// palette's appearance, and follows appearance changes.
    static func checkAddPalette() {
        func components(_ color: CGColor?) -> [CGFloat] {
            guard let color, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
                  let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil) else { return [] }
            return converted.components ?? []
        }
        func same(_ a: CGColor?, _ b: CGColor?) -> Bool {
            let x = components(a), y = components(b)
            return x.count == 4 && y.count == 4 && zip(x, y).allSatisfy { abs($0 - $1) < 0.002 }
        }
        func fill(_ manager: SpaceManagerView) -> CGColor? {
            let add = descendants(manager).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Create a Space" }
            return add?.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first?.fillColor
        }
        func expected(_ theme: SpaceTheme, _ appearance: NSAppearance) -> CGColor {
            let palette = ThemeChromePalette(theme: theme, appearance: appearance)
            var color = NSColor.clear.cgColor
            (palette.contentAppearance ?? appearance).performAsCurrentDrawingAppearance { color = palette.cutoutColor.cgColor }
            return color
        }
        let light = NSAppearance(named: .aqua)!, dark = NSAppearance(named: .darkAqua)!
        var state = BrowserState.initial()
        var blue = state.spaces[0]; blue.theme = .singleColor(ThemeColor(hex: "3366CC")!)
        var red = BrowserSpace(id: UUID(), name: "Red", symbol: "star.fill", color: "CC3333", profileID: blue.profileID)
        red.theme = .singleColor(ThemeColor(hex: "CC3333")!)
        state.spaces = [blue, red]; state.activeSpaceID = blue.id
        var windows: [NSWindow] = []
        func page(showing id: UUID) -> SpaceManagerView {
            let manager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
            let window = ManagerTestWindow(contentRect: manager.frame, styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false; window.appearance = light; window.contentView = manager
            windows.append(window)
            manager.ownerValid = { true }; manager.windowSpaceID = { id }
            manager.reload(state); manager.layoutSubtreeIfNeeded()
            return manager
        }
        let bluePage = page(showing: blue.id), redPage = page(showing: red.id)
        check(same(fill(bluePage), expected(blue.theme, light)), "the window on the blue Space paints its add circle blue")
        check(same(fill(redPage), expected(red.theme, light)) && !same(fill(redPage), fill(bluePage)),
              "the window on the red Space uses its own Space, not the store's active Space")
        // An unthemed Space's palette is dynamic; it follows the appearance.
        var plain = state; plain.spaces[0].theme = SpaceTheme()
        bluePage.reload(plain); bluePage.layoutSubtreeIfNeeded()
        check(same(fill(bluePage), expected(SpaceTheme(), light)), "an unthemed Space resolves its add circle in Aqua")
        windows[0].appearance = dark; bluePage.layoutSubtreeIfNeeded()
        check(same(fill(bluePage), expected(SpaceTheme(), dark)) && !same(fill(bluePage), expected(SpaceTheme(), light)),
              "an appearance change re-resolves the add circle in Dark Aqua")
        for window in windows { window.contentView = nil }
    }
}

@MainActor private final class CardDrop: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .move
    var draggingLocation = NSPoint.zero
    var draggedImageLocation = NSPoint.zero
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any?
    var draggingSequenceNumber = 1
    var draggingFormation = NSDraggingFormation.default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight = NSSpringLoadingHighlight.none
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}
