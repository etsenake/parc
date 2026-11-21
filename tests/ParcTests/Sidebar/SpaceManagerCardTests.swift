import AppKit
import Testing
@testable import Parc
@testable import ParcCore

private final class CardDrop: NSObject, NSDraggingInfo {
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
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}

private final class DragSource: NSView, SidebarItemDragSource {
    var sidebarDrag: SidebarMoveSession?
}

@MainActor
struct SpaceManagerCardTests {
    typealias Layout = SpaceManagementLayout

    @MainActor private final class Cards {
        let manager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 1200, height: 650))
        let window: SidebarTestWindow
        var state = BrowserState.initial()
        let first: BrowserSpace
        let pinned: BrowserTab
        let today: BrowserTab
        let later: BrowserTab
        var cleared: [UUID] = []
        var clearable = true
        var commits: [(SidebarContainerLocation, SidebarItemReference?)] = []
        let source = DragSource(frame: .zero)

        static func tab(_ name: String, _ kind: TabKind, in space: BrowserSpace) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://example.test/\(name)", title: name,
                       kind: kind, createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/\(name)", savedTitle: name)
        }

        func tab(_ name: String, _ kind: TabKind) -> BrowserTab { Self.tab(name, kind, in: first) }

        init() {
            window = sidebarTestWindow(containing: manager)
            window.applicationActive = true
            first = state.spaces[0]
            pinned = Self.tab("pinned", .pinned, in: first)
            today = Self.tab("today", .today, in: first)
            later = Self.tab("later", .today, in: first)
            state.tabs = [pinned, today, later]
            manager.ownerValid = { true }
            manager.configureSidebar = { [weak self] id, sidebar in
                sidebar.onClearToday = { [weak self] in self?.cleared.append(id) }
                sidebar.canClearToday = { [weak self] in self?.clearable ?? false }
            }
            manager.reload(state)
            manager.layoutSubtreeIfNeeded()
            manager.addSubview(source)
        }

        deinit {
            MainActor.assumeIsolated { window.contentView = nil }
        }

        var sidebar: SidebarView { manager.sidebar(for: first.id)! }
        var header: SidebarSpaceHeaderView { sidebarDescendants(sidebar).compactMap { $0 as? SidebarSpaceHeaderView }.first! }
        var card: NSView { sidebar.superview!.superview! }
        var clear: ActionButton {
            sidebarDescendants(sidebar).compactMap { $0 as? ActionButton }.first { $0.identifier?.rawValue == "sidebarClear" }!
        }

        func reload(_ state: BrowserState) {
            manager.reload(state)
            manager.layoutSubtreeIfNeeded()
        }

        func drop(_ item: UUID, at point: NSPoint) {
            let session = SidebarMoveSession(items: [.tab(item)], window: window, validate: { true }, propose: { _, _ in true },
                                             commit: { [weak self] location, before in self?.commits.append((location, before)); return true })
            source.sidebarDrag = session
            let info = CardDrop()
            info.draggingSource = source
            info.draggingDestinationWindow = window
            info.draggingPasteboard.clearContents()
            info.draggingPasteboard.setString(session.identifier.uuidString, forType: SidebarMoveSession.pasteboardType)
            info.draggingLocation = sidebar.convert(point, to: nil)
            _ = sidebar.performDragOperation(info)
            info.draggingPasteboard.releaseGlobally()
        }
    }

    private func catalog() -> (BrowserState, BrowserTab, BrowserSpace) {
        var catalog = BrowserState.initial()
        let space = catalog.spaces[0]
        let tab = Cards.tab("catalog", .today, in: space)
        catalog.tabs = [tab]
        return (catalog, tab, space)
    }

    @Test func aFirstApplyHasNoPriorFingerprint() {
        let (catalog, _, _) = catalog()
        #expect(!SpaceManagerReloadSkip.shouldSkip(previous: nil, next: catalog))
    }

    @Test func anIdenticalCatalogIsATrueNoOp() {
        let (catalog, _, _) = catalog()
        #expect(SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: catalog))
    }

    @Test func aLiveTitleAndURLPublishSkipsTheReload() {
        let (catalog, _, _) = catalog()
        var titled = catalog
        titled.tabs[0].title = "Unrelated live title"
        titled.tabs[0].url = "https://example.test/catalog-live"
        #expect(SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: titled))
    }

    @Test func aSpaceThemeChangeStillReloads() {
        let (catalog, _, _) = catalog()
        var themed = catalog
        themed.spaces[0].theme = .singleColor(ThemeColor(hex: "112233")!)
        #expect(!SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: themed))
    }

    @Test func aSpaceMembershipOrOrderChangeStillReloads() {
        let (catalog, _, space) = catalog()
        var reordered = catalog
        reordered.spaces.append(BrowserSpace(id: UUID(), name: "Second", symbol: "star.fill", color: "AABBCC", profileID: space.profileID))
        #expect(!SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: reordered))
    }

    @Test func aProfileChangeStillReloads() {
        let (catalog, _, _) = catalog()
        var profiled = catalog
        profiled.profiles[0].name = "Renamed Profile"
        #expect(!SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: profiled))
    }

    @Test func aSelectionChangeStillReloads() {
        let (catalog, tab, _) = catalog()
        var selectionChanged = catalog
        selectionChanged.selectedTabIDs = [tab.id]
        #expect(!SpaceManagerReloadSkip.shouldSkip(previous: catalog, next: selectionChanged))
    }

    @Test func aTitleAndURLPublishRetainsTheAlreadyAppliedCard() {
        let (catalog, _, space) = catalog()
        var titled = catalog
        titled.tabs[0].title = "Unrelated live title"
        let manager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
        manager.ownerValid = { true }
        manager.reload(catalog)
        let hosted = manager.sidebar(for: space.id)
        manager.reload(titled)
        #expect(manager.sidebar(for: space.id) === hosted)
    }

    @Test func cancellingAThemePreviewStillReappliesThroughReload() {
        let (catalog, _, space) = catalog()
        var themed = catalog
        themed.spaces[0].theme = .singleColor(ThemeColor(hex: "112233")!)
        let manager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
        manager.ownerValid = { true }
        manager.reload(catalog)
        let hosted = manager.sidebar(for: space.id)
        manager.previewTheme(themed.spaces[0].theme, spaceID: space.id)
        manager.reload(catalog)
        #expect(manager.sidebar(for: space.id) === hosted)
    }

    @Test func aCommittedThemeChangeStillReloadsSpaceManagement() {
        let (catalog, _, space) = catalog()
        var themed = catalog
        themed.spaces[0].theme = .singleColor(ThemeColor(hex: "112233")!)
        let manager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
        manager.ownerValid = { true }
        manager.reload(catalog)
        manager.reload(themed)
        #expect(manager.sidebar(for: space.id) != nil)
    }

    @Test func theFirstCardIsTwentyFourInAndFortyEightFromTheTopAndBottom() {
        #expect(Layout.cardFrame(index: 0, height: 650) == NSRect(x: 24, y: 48, width: 240, height: 554))
    }

    @Test func cardsSitTwentyFourApart() {
        let expected: CGFloat = 552
        #expect(Layout.cardFrame(index: 2, height: 650).minX == expected)
    }

    @Test func theAddItemFollowsTheLastCardsGapCentredOnTheHeight() {
        #expect(Layout.addItemFrame(count: 3, height: 650) == NSRect(x: 24 + 3 * 264, y: 301, width: 48, height: 48))
    }

    @Test func theAddCircleIsCentredInItsItem() {
        #expect(Layout.addCircleFrame(count: 3, height: 650) == NSRect(x: 24 + 3 * 264 + 9, y: 310, width: 30, height: 30))
    }

    @Test func theCollectionEndsTwentyFourAfterTheAddItem() {
        let expected: CGFloat = 888
        #expect(Layout.contentWidth(count: 3) == expected)
    }

    @Test func theSidebarSitsFiveBelowTheTopAndFortyFourAboveTheBottom() {
        #expect(Layout.sidebarFrame(in: NSRect(x: 0, y: 0, width: 240, height: 554)) == NSRect(x: 0, y: 5, width: 240, height: 505))
    }

    @Test func theControlsAreThirtyFourPointsAndFiveAboveTheBottom() {
        #expect(Layout.controlsFrame(in: NSRect(x: 0, y: 0, width: 240, height: 554)) == NSRect(x: 0, y: 515, width: 240, height: 34))
    }

    @Test func aSingleUnnamedSpacesCardHidesItsHeader() {
        #expect(Cards().header.isHidden)
    }

    @Test func theInertCardListAcceptsFocusBeforeRenaming() {
        let cards = Cards()
        #expect(cards.window.makeFirstResponder(cards.sidebar))
    }

    @Test func renamingRevealsTheOtherwiseHiddenHeader() {
        let cards = Cards()
        _ = cards.window.makeFirstResponder(cards.sidebar)
        #expect(cards.sidebar.beginSpaceNameEditing(cards.first) { _ in })
        #expect(!cards.header.isHidden)
    }

    @Test func theRevealedHeaderSitsItsPaddingBelowTheTopWithTheListAfterIt() {
        let cards = Cards()
        _ = cards.window.makeFirstResponder(cards.sidebar)
        _ = cards.sidebar.beginSpaceNameEditing(cards.first) { _ in }
        let list = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first!.enclosingScrollView!
        #expect(list.frame.minY == cards.header.frame.maxY)
        #expect(cards.header.frame.minY == SidebarChromeLayout.SpaceHeader.topPadding)
    }

    @Test func cancellingTheRenameHidesTheHeaderAgainWithoutACatalogChange() {
        let cards = Cards()
        _ = cards.window.makeFirstResponder(cards.sidebar)
        _ = cards.sidebar.beginSpaceNameEditing(cards.first) { _ in }
        cards.sidebar.cancelSpaceNameEditing()
        cards.sidebar.layoutSubtreeIfNeeded()
        let list = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first!.enclosingScrollView!
        #expect(cards.header.isHidden)
        #expect(list.frame.minY == 0)
    }

    @Test func aCardPaintsItsThemeWithoutTheBehindWindowMaterial() {
        let cards = Cards()
        let theme = cards.sidebar.superview as! ThemeRendererView
        #expect(!theme.drawsMaterial)
    }

    @Test func theActualCardUsesTheRecoveredFrame() {
        let cards = Cards()
        #expect(cards.card.frame == Layout.cardFrame(index: 0, height: cards.manager.bounds.height))
    }

    @Test func theActualSidebarUsesTheCardsSidebarInset() {
        let cards = Cards()
        #expect(cards.sidebar.frame == Layout.sidebarFrame(in: cards.card.bounds))
    }

    @Test func theMoveHandleIsATwentyEightPointLeadingControl() {
        let cards = Cards()
        let grip = sidebarDescendants(cards.card).first { $0.parcTooltip?.label == "Drag to Reorder Space" }
        let controls = Layout.controlsFrame(in: cards.card.bounds)
        #expect(grip?.frame == NSRect(x: 8, y: controls.midY - 14, width: 28, height: 28))
    }

    @Test func moreOptionsIsATwentyEightPointTrailingControlKeepingItsAccessibleName() {
        let cards = Cards()
        let more = sidebarDescendants(cards.card).compactMap { $0 as? NSButton }.first { $0.parcTooltip?.label == "More options" }
        let controls = Layout.controlsFrame(in: cards.card.bounds)
        #expect(more?.frame == NSRect(x: 240 - 36, y: controls.midY - 14, width: 28, height: 28))
        #expect(more?.accessibilityLabel() == "Space Options")
    }

    @Test func aHiddenHeaderLeavesThePopoversAnchoredOnMore() {
        let cards = Cards()
        let more = sidebarDescendants(cards.card).compactMap { $0 as? NSButton }.first { $0.parcTooltip?.label == "More options" }
        #expect(cards.manager.anchor(for: cards.first.id) === more)
    }

    @Test func moreDrawsAnExteriorKeyboardRingOverItsBounds() {
        let cards = Cards()
        let more = sidebarDescendants(cards.card).compactMap { $0 as? NSButton }.first { $0.parcTooltip?.label == "More options" }
        #expect(more?.focusRingType == .exterior)
        #expect(more?.focusRingMaskBounds == more?.bounds)
    }

    private func focusMaskAlpha(_ cards: Cards) -> (Int, Int) -> CGFloat {
        let more = sidebarDescendants(cards.card).compactMap { $0 as? NSButton }.first { $0.parcTooltip?.label == "More options" }
        let mask = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 28, pixelsHigh: 28, bitsPerSample: 8, samplesPerPixel: 4,
                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: mask)
        NSColor.black.setFill()
        more?.drawFocusRingMask()
        NSGraphicsContext.restoreGraphicsState()
        return { x, y in mask.colorAt(x: x, y: y)!.alphaComponent }
    }

    @Test func theRingMaskFillsMoreWithRoundedCorners() {
        let alpha = focusMaskAlpha(Cards())
        #expect(alpha(14, 14) > 0.99)
        #expect(alpha(14, 0) > 0.99)
        #expect(alpha(0, 0) < 0.01)
    }

    @Test func theMasksCornersHaveRadiusSixAsTheHoverFill() {
        let alpha = focusMaskAlpha(Cards())
        #expect(alpha(1, 1) < 0.3)
        #expect(alpha(1, 2) > 0.6)
    }

    @Test func theAddCircleFollowsTheLastCardCentredOnIt() {
        let cards = Cards()
        let add = sidebarDescendants(cards.manager).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Create a Space" }!
        #expect(add.frame.size == NSSize(width: 30, height: 30))
        #expect(add.frame.minX == cards.card.frame.maxX + 24 + 9)
        #expect(add.frame.midY == cards.card.frame.midY)
    }

    @Test func aCardHasNoNewTabRow() {
        let cards = Cards()
        #expect(!sidebarDescendants(cards.sidebar).contains { $0 is SidebarNewTabRow })
    }

    @Test func theCardsClearIsAnArrowAndLabelButton() {
        let clear = Cards().clear
        #expect(clear.title == "Clear")
        #expect(clear.isEnabled)
        #expect(clear.font == NSFont.systemFont(ofSize: 10, weight: .semibold))
        #expect(clear.image != nil)
    }

    @Test func aCardShowsClearWithoutThePointerOverIt() {
        let clear = Cards().clear
        #expect(!clear.isHidden)
        #expect(clear.alphaValue == 1)
    }

    @Test func theCardDividerHasNoSeparateSeparatorRow() {
        let clear = Cards().clear
        #expect(!clear.superview!.subviews.contains { $0 is NSBox })
    }

    @Test func theBorderRunsFromTheCellsInsetToEightBeforeClearOnClearsRow() {
        let cards = Cards()
        let clear = cards.clear
        let section = clear.superview!
        let line = section.subviews.compactMap { $0 as? SidebarHairline }.first!
        let thickness = SidebarChromeLayout.sectionDividerThickness(scale: cards.window.backingScaleFactor)
        #expect(line.frame.height == thickness)
        #expect(abs(line.frame.midY - clear.frame.midY) <= thickness / 2)
        #expect(line.frame.maxX == clear.frame.minX - SidebarChromeLayout.sectionDividerSpacing)
        #expect(line.frame.minX == SidebarChromeLayout.sectionDividerInset)
    }

    @Test func theCardsClearReachesItsOwnSpacesHandler() {
        let cards = Cards()
        let clear = cards.clear
        clear.sendAction(clear.action, to: clear.target)
        #expect(cards.cleared == [cards.first.id])
    }

    private func revealEvent(_ cards: Cards) -> SidebarAreaEvent {
        cards.sidebar.updateTrackingAreas()
        let event = SidebarAreaEvent()
        event.area = cards.sidebar.trackingAreas.first { $0.owner === cards.sidebar && $0.options.contains(.activeInActiveApp) }
        return event
    }

    private func rgba(_ color: NSColor?) -> [CGFloat] {
        let c = color!.usingColorSpace(.sRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { ($0 * 100).rounded() / 100 }
    }

    private func resting(_ color: NSColor?) -> Bool {
        let v = rgba(color)
        return v[3] == 0.3 && (v[0] == 0 || v[0] == 1) && v[0] == v[1] && v[1] == v[2]
    }

    private func hovered(_ color: NSColor?) -> Bool { [0.8, 0.9].contains(rgba(color)[3]) }

    @Test func aRestingCardClearIsForegroundTertiary() {
        #expect(resting(Cards().clear.contentTintColor))
    }

    @Test func hoveringACardsClearTintsItForegroundPrimary() {
        let cards = Cards()
        cards.sidebar.mouseEntered(with: revealEvent(cards))
        let clear = cards.clear
        clear.mouseEntered(with: SidebarAreaEvent())
        #expect(clear.hovered)
        #expect(hovered(clear.contentTintColor))
    }

    @Test func leavingRestoresTheRestingTint() {
        let cards = Cards()
        cards.sidebar.mouseEntered(with: revealEvent(cards))
        let clear = cards.clear
        let event = SidebarAreaEvent()
        clear.mouseEntered(with: event)
        clear.mouseExited(with: event)
        #expect(!clear.hovered)
        #expect(resting(clear.contentTintColor))
    }

    @Test func theCardSidebarTracksThePointerEnteringIt() {
        let cards = Cards()
        #expect(revealEvent(cards).area != nil)
    }

    @Test func withNothingToClearTheCardsClearIsDisabled() {
        let cards = Cards()
        let reveal = revealEvent(cards)
        cards.clearable = false
        cards.sidebar.mouseEntered(with: reveal)
        #expect(!cards.clear.isEnabled)
    }

    @Test func anotherTrackingAreasEntryDoesNotRereadClear() {
        let cards = Cards()
        let reveal = revealEvent(cards)
        cards.clearable = false
        cards.sidebar.mouseEntered(with: reveal)
        cards.clearable = true
        cards.sidebar.mouseEntered(with: SidebarAreaEvent())
        #expect(!cards.clear.isEnabled)
    }

    @Test func clearReenablesOnceATodayPageIsClearableAgain() {
        let cards = Cards()
        let reveal = revealEvent(cards)
        cards.clearable = false
        cards.sidebar.mouseEntered(with: reveal)
        cards.clearable = true
        cards.sidebar.mouseEntered(with: reveal)
        #expect(cards.clear.isEnabled)
    }

    private func becomeKey(_ cards: Cards) {
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: cards.window)
    }

    @Test func theWindowBecomingKeyDisablesAClearWithNothingToClear() {
        let cards = Cards()
        cards.clearable = false
        becomeKey(cards)
        #expect(!cards.clear.isEnabled)
    }

    @Test func enteringClearReenablesAndHoversItAtOnce() {
        let cards = Cards()
        cards.clearable = false
        becomeKey(cards)
        cards.clearable = true
        cards.clear.mouseEntered(with: SidebarAreaEvent())
        #expect(cards.clear.isEnabled)
        #expect(cards.clear.hovered)
        #expect(hovered(cards.clear.contentTintColor))
    }

    @Test func disablingAHoveredClearDropsItsForegroundPrimaryTint() {
        let cards = Cards()
        cards.clear.mouseEntered(with: SidebarAreaEvent())
        cards.clearable = false
        becomeKey(cards)
        #expect(!cards.clear.isEnabled)
        #expect(!cards.clear.hovered)
        #expect(resting(cards.clear.contentTintColor))
    }

    @Test func enteringAClearWithNothingToClearShowsNoHover() {
        let cards = Cards()
        cards.clearable = false
        becomeKey(cards)
        cards.clear.mouseEntered(with: SidebarAreaEvent())
        #expect(!cards.clear.isEnabled)
        #expect(!cards.clear.hovered)
    }

    @Test func afterAReleaseTheWindowBecomingKeyReenablesClear() {
        let cards = Cards()
        cards.clearable = false
        becomeKey(cards)
        cards.clearable = true
        becomeKey(cards)
        #expect(cards.clear.isEnabled)
    }

    @Test func aRenderWithNothingClearableStartsDisabled() {
        let cards = Cards()
        let before = cards.clear
        cards.clearable = false
        var grown = cards.state
        grown.tabs.append(cards.tab("grown", .today))
        cards.reload(grown)
        let rendered = cards.clear
        #expect(rendered !== before)
        #expect(!rendered.isEnabled)
    }

    @Test func theIdleTitleLabelExtendsTwoPastTheInsetAndTheTrailingEdge() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        let title = sidebarDescendants(row).compactMap { $0 as? SidebarChromeLabel }.first { $0.stringValue == "today" }!
        let frame = title.convert(title.bounds, to: row)
        #expect(frame.minX == SidebarRowAppearance.titleInset - SidebarRowAppearance.titleTextPadding)
        #expect(frame.maxX == SidebarRowAppearance.titleTrailingEdge(in: row.bounds, closeVisible: false) + SidebarRowAppearance.titleTextPadding)
    }

    @Test func aRowBuildsItsRenameFieldForItsFirstRename() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        #expect(sidebarDescendants(row).allSatisfy { !($0 is SidebarTitleField) })
    }

    @Test func aHoveredTitlesTextStopsTwoBeforeTheCloseWithItsFrameAtTheClose() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        let title = sidebarDescendants(row).compactMap { $0 as? SidebarChromeLabel }.first { $0.stringValue == "today" }!
        cards.window.pointer = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        row.updateTrackingAreas()
        row.layoutSubtreeIfNeeded()
        let close = sidebarDescendants(row).compactMap { $0 as? SidebarRowActionButton }.first { $0.accessibilityLabel() == "Archive Tab" }!
        let frame = title.convert(title.bounds, to: row)
        #expect(!close.isHidden)
        #expect(frame.maxX == close.frame.minX)
        #expect(frame.maxX - SidebarRowAppearance.titleTextPadding < close.frame.minX)
    }

    @Test func renamingEditsFromTheTitlesFrameToEightInsideTheRow() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        let title = sidebarDescendants(row).compactMap { $0 as? SidebarChromeLabel }.first { $0.stringValue == "today" }!
        let titleFrame = title.convert(title.bounds, to: row)
        #expect(row.beginTitleEditing("today") { _ in })
        row.layoutSubtreeIfNeeded()
        let field = sidebarDescendants(row).compactMap { $0 as? SidebarTitleField }.first!
        let editing = field.convert(field.bounds, to: row)
        #expect(editing.minX == titleFrame.minX)
        #expect(editing.maxX == row.bounds.width - 8)
    }

    @Test func afterARenameTheFieldKeepsTheIdleTitlesFrame() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        let title = sidebarDescendants(row).compactMap { $0 as? SidebarChromeLabel }.first { $0.stringValue == "today" }!
        let titleFrame = title.convert(title.bounds, to: row)
        _ = row.beginTitleEditing("today") { _ in }
        row.layoutSubtreeIfNeeded()
        let field = sidebarDescendants(row).compactMap { $0 as? SidebarTitleField }.first!
        row.cancelTitleEditing()
        cards.window.pointer = nil
        row.updateTrackingAreas()
        row.layoutSubtreeIfNeeded()
        #expect(field.convert(field.bounds, to: row) == title.convert(title.bounds, to: row))
        #expect(field.convert(field.bounds, to: row) == titleFrame)
    }

    @Test func appKitDrawsTheLabelsTextTwoPointsInSoInkStartsAtTheInset() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        let title = sidebarDescendants(row).compactMap { $0 as? SidebarChromeLabel }.first { $0.stringValue == "today" }!
        let glyphs = title.bitmapImageRepForCachingDisplay(in: title.bounds)!
        title.cacheDisplay(in: title.bounds, to: glyphs)
        let scale = CGFloat(glyphs.pixelsWide) / title.bounds.width
        let firstInk = (0..<glyphs.pixelsWide).first { x in (0..<glyphs.pixelsHigh).contains { glyphs.colorAt(x: x, y: $0)!.alphaComponent > 0.25 } }!
        #expect((2...3).contains(CGFloat(firstInk) / scale))
    }

    @Test func aCardsRowOffersNoDoubleClickRenameSoItsTooltipCarriesNoHint() {
        let cards = Cards()
        let row = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == cards.today.id }!
        #expect(row.beginRename == nil)
        #expect(row.parcTooltip == SidebarTabRow.rowTooltip(cards.today, renameable: false))
        #expect(row.parcTooltip?.style == .label(subtitle: nil))
    }

    private func withExtras(_ cards: Cards) -> (BrowserTab, BrowserTab, BrowserState) {
        var archived = cards.tab("archived", .today)
        archived.archivedAt = Date()
        let second = BrowserSpace(id: UUID(), name: "Second", symbol: "star.fill", color: "AABBCC", profileID: cards.first.profileID)
        let elsewhere = Cards.tab("elsewhere", .today, in: second)
        var otherProfile = cards.tab("other-profile", .today)
        otherProfile.profileID = UUID()
        var targets = cards.state
        targets.tabs += [archived, elsewhere, otherProfile]
        return (elsewhere, archived, targets)
    }

    @Test func clearArchivesOnlyTheCardSpacesLiveTodayTabs() {
        let cards = Cards()
        let (_, _, targets) = withExtras(cards)
        #expect(SpaceClearToday.ids(in: targets, spaceID: cards.first.id, profileID: cards.first.profileID) == [cards.today.id, cards.later.id])
    }

    @Test func anotherCardsClearTargetsItsOwnSpace() {
        let cards = Cards()
        let (elsewhere, _, targets) = withExtras(cards)
        #expect(SpaceClearToday.ids(in: targets, spaceID: elsewhere.spaceID, profileID: elsewhere.profileID) == [elsewhere.id])
    }

    @Test func aDropBelowTheTodayRowsLandsAtTheEndOfToday() {
        let cards = Cards()
        let rows = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }
        let lastToday = rows.first { $0.tabID == cards.later.id }!
        cards.drop(cards.later.id, at: cards.sidebar.convert(NSPoint(x: lastToday.bounds.midX, y: lastToday.bounds.maxY + 30), from: lastToday))
        #expect(cards.commits.count == 1)
        #expect(cards.commits[0].0.section == .today)
        #expect(cards.commits[0].0.spaceID == cards.first.id)
        #expect(cards.commits[0].1 == nil)
    }

    @Test func aDropOnThePinnedRowStaysInPinned() {
        let cards = Cards()
        let rows = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }
        let pinnedRow = rows.first { $0.tabID == cards.pinned.id }!
        cards.drop(cards.later.id, at: cards.sidebar.convert(NSPoint(x: pinnedRow.bounds.midX, y: pinnedRow.bounds.minY + 4), from: pinnedRow))
        #expect(cards.commits.count == 1)
        #expect(cards.commits[0].0.section == .pinned)
    }

    private func todayless(_ cards: Cards) -> BrowserTab {
        let extra = cards.tab("extra", .pinned)
        var state = cards.state
        state.tabs = [cards.pinned, extra]
        cards.reload(state)
        return extra
    }

    @Test func aCardWithAnEmptyTodayHasNoDividerAndNoClear() {
        let cards = Cards()
        _ = todayless(cards)
        #expect(!sidebarDescendants(cards.sidebar).contains { ($0 as? ActionButton)?.identifier?.rawValue == "sidebarClear" })
        #expect(!sidebarDescendants(cards.sidebar).contains { $0 is SidebarHairline })
    }

    @Test func withoutADividerADropBelowTheCardsLastRowLandsInToday() {
        let cards = Cards()
        let extra = todayless(cards)
        let rows = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.filter { [cards.pinned.id, extra.id].contains($0.tabID) }
        let lastRow = rows.max { $0.convert($0.bounds, to: cards.sidebar).maxY < $1.convert($1.bounds, to: cards.sidebar).maxY }!
        cards.drop(extra.id, at: cards.sidebar.convert(NSPoint(x: lastRow.bounds.midX, y: lastRow.bounds.maxY + 30), from: lastRow))
        #expect(cards.commits.count == 1)
        #expect(cards.commits[0].0.section == .today)
        #expect(cards.commits[0].0.spaceID == cards.first.id)
        #expect(cards.commits[0].1 == nil)
    }

    @Test func withoutADividerADropOnTheLastPinnedRowStaysInPinned() {
        let cards = Cards()
        let extra = todayless(cards)
        let rows = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.filter { [cards.pinned.id, extra.id].contains($0.tabID) }
        let lastRow = rows.max { $0.convert($0.bounds, to: cards.sidebar).maxY < $1.convert($1.bounds, to: cards.sidebar).maxY }!
        cards.drop(extra.id, at: cards.sidebar.convert(NSPoint(x: lastRow.bounds.midX, y: lastRow.bounds.maxY - 4), from: lastRow))
        #expect(cards.commits.count == 1)
        #expect(cards.commits[0].0.section == .pinned)
    }

    private func emptyCard(_ cards: Cards) -> (NSRect, BrowserTab) {
        let favorite = cards.tab("favorite", .favorite)
        var empty = cards.state
        empty.tabs = [favorite]
        cards.reload(empty)
        let outline = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarOutlineView }.first!
        return (outline.convert(outline.rows[0].frame, to: cards.sidebar), favorite)
    }

    @Test func anEmptyCardListsOnlyItsPinnedHeaderWithNoDivider() {
        let cards = Cards()
        let (headerRow, _) = emptyCard(cards)
        let outline = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarOutlineView }.first!
        #expect(cards.header.isHidden)
        #expect(outline.rows.count == 1)
        #expect(headerRow.height == SidebarChromeLayout.tablistCellHeight + SidebarChromeLayout.tablistIntercellSpacing)
        #expect(!sidebarDescendants(cards.sidebar).contains { $0 is SidebarHairline })
    }

    @Test func theEmptyCardsPinnedHeaderIsAPlainLabelThatLeavesClicksToTheCard() {
        let cards = Cards()
        _ = emptyCard(cards)
        let pinnedHeader = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarPinnedHeaderView }.first
        #expect(pinnedHeader?.content.placeholder == true)
        #expect(pinnedHeader?.accessibilityRole() == .staticText)
        #expect(pinnedHeader?.hitTest(NSPoint(x: 5, y: 5)) == nil)
    }

    @Test(arguments: [(2.0, true), (0.5, true)])
    func anEmptyCardsWholePinnedHeaderTakesPinnedDrops(fraction: Double, pinned: Bool) {
        let cards = Cards()
        let (headerRow, favorite) = emptyCard(cards)
        cards.drop(favorite.id, at: NSPoint(x: cards.sidebar.bounds.midX, y: fraction == 2 ? headerRow.minY + 2 : headerRow.midY))
        #expect(cards.commits.count == 1)
        #expect((cards.commits[0].0.section == .pinned) == pinned)
    }

    @Test func belowAnEmptyCardsPinnedHeaderIsToday() {
        let cards = Cards()
        let (headerRow, favorite) = emptyCard(cards)
        cards.drop(favorite.id, at: NSPoint(x: cards.sidebar.bounds.midX, y: headerRow.maxY + 10))
        #expect(cards.commits.count == 1)
        #expect(cards.commits[0].0.section == .today)
        #expect(cards.commits[0].0.spaceID == cards.first.id)
    }

    @Test func aCardTakesNoFavoriteDropAboveItsShownHeader() {
        let cards = Cards()
        let second = BrowserSpace(id: UUID(), name: "Second", symbol: "star.fill", color: "AABBCC", profileID: cards.first.profileID)
        var trayless = cards.state
        trayless.spaces.append(second)
        trayless.tabs = [cards.pinned]
        cards.reload(trayless)
        let header = cards.header
        cards.drop(cards.pinned.id, at: NSPoint(x: cards.sidebar.bounds.midX, y: header.frame.minY / 2))
        #expect(cards.manager.sidebar(for: cards.first.id) === cards.sidebar)
        #expect(!header.isHidden)
        #expect(header.frame.minY > 0)
        #expect(!cards.commits.contains { $0.0.section == .favorite })
    }

    @Test func withTwoSpacesEveryCardShowsItsHeaderItsPaddingBelowTheTop() {
        let cards = Cards()
        let second = BrowserSpace(id: UUID(), name: "Second", symbol: "star.fill", color: "AABBCC", profileID: cards.first.profileID)
        var pair = cards.state
        pair.spaces.append(second)
        pair.tabs.append(Cards.tab("elsewhere", .today, in: second))
        cards.reload(pair)
        let headers = pair.spaces.map { space in sidebarDescendants(cards.manager.sidebar(for: space.id)!).compactMap { $0 as? SidebarSpaceHeaderView }.first! }
        #expect(headers.allSatisfy { !$0.isHidden && $0.frame.minY == SidebarChromeLayout.SpaceHeader.topPadding })
        #expect(zip(pair.spaces, headers).allSatisfy { cards.manager.anchor(for: $0.id) === $1 })
    }

    @Test func theSecondCardFollowsOneGapLaterAndTheAddCircleMovesAfterIt() {
        let cards = Cards()
        let second = BrowserSpace(id: UUID(), name: "Second", symbol: "star.fill", color: "AABBCC", profileID: cards.first.profileID)
        var pair = cards.state
        pair.spaces.append(second)
        pair.tabs.append(Cards.tab("elsewhere", .today, in: second))
        cards.reload(pair)
        let secondCard = cards.manager.sidebar(for: second.id)!.superview!.superview!
        let add = sidebarDescendants(cards.manager).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Create a Space" }!
        #expect(secondCard.frame == Layout.cardFrame(index: 1, height: cards.manager.bounds.height))
        #expect(add.frame.minX == secondCard.frame.maxX + 24 + 9)
    }
}
