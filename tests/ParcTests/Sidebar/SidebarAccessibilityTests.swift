import AppKit
import Testing
@testable import Parc

private final class FlippedView: NSView { override var isFlipped: Bool { true } }
private final class KeyLikeWindow: NSWindow { override var isKeyWindow: Bool { true } }

private final class ListStopView: NSView, OffscreenPresenting {
    var presented = true
    var isPresented: Bool { presented }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { presented && super.becomeFirstResponder() }
    override var canBecomeKeyView: Bool { super.canBecomeKeyView && presented }
}

private final class CreationLikeView: NSView {
    let name = NSTextField(string: "name")
    let icon = ActionButton("Icon")
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        name.identifier = .init("name")
        icon.identifier = .init("icon")
        name.frame = .zero
        addSubview(name)
        addSubview(icon)
        needsLayout = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 5, y: 5, width: 26, height: 26)
        name.frame = NSRect(x: 33, y: 8, width: 100, height: 21)
    }
}

@MainActor
struct SidebarAccessibilityTests {
    private func mask(_ view: NSView) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 28, pixelsHigh: 28, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.black.setFill()
        view.drawFocusRingMask()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func names(_ views: [NSView]) -> [String] { views.map { $0.identifier?.rawValue ?? "?" } }

    private func field(_ name: String, _ frame: NSRect, in parent: NSView) -> NSTextField {
        let field = NSTextField(string: name)
        field.frame = frame
        field.identifier = .init(name)
        parent.addSubview(field)
        return field
    }

    @Test func theToggleLabelsFollowTheLockedFloatingPair() {
        #expect(SidebarAccessibility.hideSidebar == "Hide sidebar")
        #expect(SidebarAccessibility.lockSidebar == "Lock sidebar")
    }

    @Test func theNavigationLabels() {
        #expect(SidebarAccessibility.goBack == "Go back")
        #expect(SidebarAccessibility.goForward == "Go forward")
        #expect(SidebarAccessibility.reload == "Reload this page")
    }

    private func configuredSpace(_ name: String = "Home") -> ActionButton {
        let space = ActionButton(name, symbol: "house")
        space.title = ""
        SidebarAccessibility.configureSpace(space, name: name)
        return space
    }

    @Test func anUnconfiguredButtonHasNoneOfTheSpaceValues() {
        let space = ActionButton("Home", symbol: "house")
        space.title = ""
        #expect(space.accessibilityRoleDescription() != "Space")
        #expect(space.accessibilityTitle() != "Home")
        #expect(space.accessibilityIdentifier() != "SidebarDockItem-Home")
    }

    @Test func aSpaceButtonHasItsRoleDescriptionTitleAndIdentifier() {
        let space = configuredSpace()
        #expect(space.accessibilityRoleDescription() == "Space")
        #expect(space.accessibilityTitle() == "Home")
        #expect(space.accessibilityIdentifier() == "SidebarDockItem-Home")
        #expect(space.accessibilityLabel() == "Home")
    }

    @Test func aSpaceButtonTakesNoKeyboardFocusAndDrawsNoRing() {
        let space = configuredSpace()
        #expect(space.refusesFirstResponder)
        #expect(!space.acceptsFirstResponder)
        #expect(space.focusRingType == .none)
    }

    @Test func appKitExposesTheButtonsCellCarryingTheSpaceValues() {
        let space = configuredSpace()
        let exposed = NSAccessibility.unignoredDescendant(of: space) as? NSCell
        #expect(exposed != nil)
        #expect(exposed === space.cell)
        #expect(exposed?.accessibilityRoleDescription() == "Space")
        #expect(exposed?.accessibilityTitle() == "Home")
        #expect(exposed?.accessibilityIdentifier() == "SidebarDockItem-Home")
    }

    @Test func theExposedToggleCellReadsTheCurrentLabel() {
        let labelled = ActionButton("Hide sidebar", symbol: "sidebar.left")
        SidebarAccessibility.label(labelled, SidebarAccessibility.lockSidebar)
        let cell = NSAccessibility.unignoredDescendant(of: labelled) as? NSCell
        #expect(cell?.accessibilityLabel() == "Lock sidebar")
        #expect(labelled.image?.accessibilityDescription == "Lock sidebar")
    }

    @Test func labellingATitledButtonLeavesOtherButtonsLabelsAlone() {
        func titled(_ title: String) -> NSButton {
            let button = NSButton(frame: .zero)
            button.setButtonType(.momentaryChange); button.isBordered = false
            button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "")
            button.image = nil; button.title = title
            return button
        }
        let labelled = titled("Stop"), other = titled("Done")
        SidebarAccessibility.label(labelled, SidebarAccessibility.reload)
        #expect(other.cell?.accessibilityLabel() == "Done")
    }

    @Test func labellingAButtonLeavesItsSharedArtworkAlone() throws {
        let shared = try #require(NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Hide sidebar"))
        let button = ActionButton("Hide sidebar", symbol: "sidebar.left")
        button.image = shared
        SidebarAccessibility.label(button, SidebarAccessibility.lockSidebar)
        #expect(shared.accessibilityDescription == "Hide sidebar")
        #expect(button.image?.accessibilityDescription == "Lock sidebar")
    }

    @Test func anEmptyNameFallsBackToUntitledSpace() {
        let untitled = ActionButton("", symbol: "house")
        SidebarAccessibility.configureSpace(untitled, name: "")
        #expect(untitled.accessibilityTitle() == "Untitled Space")
        #expect(untitled.accessibilityIdentifier() == "SidebarDockItem-Untitled Space")
    }

    @Test func existingActionButtonUsersKeepNoRing() {
        #expect(ActionButton("Downloads", symbol: "arrow.down.circle").focusRingType == .none)
    }

    private func ringed() -> ActionButton {
        let button = ActionButton("Hide sidebar", symbol: "sidebar.left")
        button.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        button.focusRingCornerRadius = 5
        return button
    }

    @Test func aRadiusEnablesTheKeyboardRingOverTheButtonBounds() {
        let button = ringed()
        #expect(button.focusRingType == .exterior)
        #expect(button.focusRingMaskBounds == button.bounds)
    }

    @Test func theMaskCornerIsRoundedAndTheMaskFillsTheButtonToItsEdge() {
        let bitmap = mask(ringed())
        #expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1)
        #expect((bitmap.colorAt(x: 14, y: 14)?.alphaComponent ?? 0) > 0.9)
        #expect((bitmap.colorAt(x: 14, y: 0)?.alphaComponent ?? 0) > 0.9)
    }

    @Test func clearingTheRadiusRemovesTheRing() {
        let button = ringed()
        button.focusRingCornerRadius = nil
        #expect(button.focusRingType == .none)
    }

    private func navigation() -> NavigationControlButton {
        let navigation = NavigationControlButton(SidebarAccessibility.goBack, symbol: "arrow.left", history: true)
        navigation.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        return navigation
    }

    @Test func navigationButtonsKeepTheExteriorRingByDefault() {
        let n = navigation()
        #expect(n.focusRingType == .exterior)
        #expect(n.focusRingCornerRadius == nil)
    }

    @Test func theSidebarsNavigationRingCoversTheBoundsWithRoundedCorners() {
        let n = navigation()
        n.focusRingCornerRadius = 5
        let bitmap = mask(n)
        #expect(n.focusRingType == .exterior)
        #expect(n.focusRingMaskBounds == n.bounds)
        #expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1)
        #expect((bitmap.colorAt(x: 14, y: 14)?.alphaComponent ?? 0) > 0.9)
        #expect((bitmap.colorAt(x: 14, y: 0)?.alphaComponent ?? 0) > 0.9)
    }

    @MainActor private final class Region {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 240, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        let sidebar = FlippedView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        let region = FlippedView(frame: NSRect(x: 0, y: 40, width: 240, height: 300))

        init() {
            window.isReleasedWhenClosed = false
            window.contentView = root
            root.addSubview(sidebar)
            sidebar.addSubview(region)
        }

        deinit { MainActor.assumeIsolated { window.close() } }
    }

    @Test func keyViewsRunRowsTopToBottomLeadingFirstConvertingUnflippedHostsKeepingDisabledControlsAndExcludingLabelsAndSpaces() {
        let r = Region()
        _ = field("trailing", NSRect(x: 120, y: 0, width: 40, height: 20), in: r.region)
        _ = field("leading", NSRect(x: 10, y: 2, width: 40, height: 20), in: r.region)
        r.region.addSubview(NSTextField(labelWithString: "label"))
        let disabledLabel = NSTextField(labelWithString: "disabled label")
        disabledLabel.isEnabled = false
        r.region.addSubview(disabledLabel)
        let grid = NSView(frame: NSRect(x: 0, y: 40, width: 240, height: 60))
        r.region.addSubview(grid)
        _ = field("lower", NSRect(x: 10, y: 0, width: 40, height: 20), in: grid)
        _ = field("upper", NSRect(x: 10, y: 40, width: 40, height: 20), in: grid)
        let refusing = ActionButton("Space")
        refusing.frame = NSRect(x: 0, y: 200, width: 20, height: 20)
        SidebarAccessibility.configureSpace(refusing, name: "Space")
        r.region.addSubview(refusing)
        let disabled = ActionButton("Clear")
        disabled.frame = NSRect(x: 0, y: 240, width: 40, height: 20)
        disabled.identifier = .init("disabled")
        disabled.isEnabled = false
        r.region.addSubview(disabled)
        let order = SidebarAccessibility.keyViews(in: [r.region], space: r.sidebar)
        #expect(!disabled.acceptsFirstResponder)
        #expect(names(order) == ["leading", "trailing", "upper", "lower", "disabled"])
    }

    @Test func beforeItsLayoutTheCreationViewsChildrenSortBySubviewIndex() {
        let r = Region()
        let list = ListStopView(frame: NSRect(x: 0, y: 0, width: 240, height: 360))
        r.sidebar.addSubview(list)
        let creation = CreationLikeView(frame: NSRect(x: 0, y: 100, width: 240, height: 60))
        list.addSubview(creation)
        #expect(names(SidebarAccessibility.keyViews(in: [creation], space: r.sidebar)) == ["name", "icon"])
    }

    @Test func theKeyViewChainRunsLeadingFavoritesListStopListControlsByLaidOutFramesThenTheDock() {
        let r = Region()
        let list = ListStopView(frame: NSRect(x: 0, y: 0, width: 240, height: 360))
        r.sidebar.addSubview(list)
        let header = ActionButton("Hide sidebar")
        header.identifier = .init("header")
        let dock = ActionButton("Space actions")
        dock.identifier = .init("dock")
        let favorites = FlippedView(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        list.addSubview(favorites)
        _ = field("favorite", NSRect(x: 0, y: 0, width: 40, height: 20), in: favorites)
        let rows = FlippedView(frame: NSRect(x: 0, y: 40, width: 240, height: 40))
        list.addSubview(rows)
        _ = field("row", NSRect(x: 0, y: 0, width: 40, height: 20), in: rows)
        let creation = CreationLikeView(frame: NSRect(x: 0, y: 100, width: 240, height: 60))
        list.addSubview(creation)
        list.identifier = .init("list")
        let chain = SidebarAccessibility.keyViewChain(leading: [header], favorites: favorites, list: list, regions: [rows, creation], trailing: [dock], space: r.sidebar)
        #expect(names(chain) == ["header", "favorite", "list", "row", "icon", "name", "dock"])
    }

    @MainActor private final class Linked {
        let r = Region()
        let list = ListStopView(frame: NSRect(x: 0, y: 0, width: 240, height: 360))
        let outside: NSTextField
        let page: NSTextField
        let entering: NSTextField
        let first: NSTextField
        let hidden: NSTextField
        let last: NSTextField

        func field(_ name: String, _ frame: NSRect, in parent: NSView) -> NSTextField {
            let field = NSTextField(string: name)
            field.frame = frame
            field.identifier = .init(name)
            parent.addSubview(field)
            return field
        }

        init() {
            r.sidebar.addSubview(list)
            outside = NSTextField(string: "outside")
            outside.frame = NSRect(x: 0, y: 380, width: 40, height: 20)
            r.root.addSubview(outside)
            page = NSTextField(string: "page")
            page.frame = NSRect(x: 60, y: 380, width: 40, height: 20)
            r.root.addSubview(page)
            entering = NSTextField(string: "entering")
            entering.frame = NSRect(x: 120, y: 380, width: 40, height: 20)
            r.root.addSubview(entering)
            first = NSTextField(string: "first")
            first.frame = NSRect(x: 0, y: 0, width: 40, height: 20)
            list.addSubview(first)
            hidden = NSTextField(string: "hidden")
            hidden.frame = NSRect(x: 0, y: 30, width: 40, height: 20)
            hidden.isHidden = true
            list.addSubview(hidden)
            last = NSTextField(string: "last")
            last.frame = NSRect(x: 0, y: 60, width: 40, height: 20)
            list.addSubview(last)
            last.nextKeyView = outside
            entering.nextKeyView = list
        }
    }

    @Test func theChainIsLinkedInOrderAndTheLastElementKeepsTheWindowLoopsWayOn() {
        let l = Linked()
        SidebarAccessibility.link([l.first, l.hidden, l.list, l.last], within: l.list, exit: nil)
        #expect(l.first.nextKeyView === l.hidden)
        #expect(l.hidden.nextKeyView === l.list)
        #expect(l.list.nextKeyView === l.last)
        #expect(l.last.nextKeyView === l.outside)
    }

    @Test func theWindowLoopsLinkIntoTheListStopsViewEntersAtTheChainsStart() {
        let l = Linked()
        SidebarAccessibility.link([l.first, l.hidden, l.list, l.last], within: l.list, exit: nil)
        #expect(l.entering.nextKeyView === l.first)
        #expect(l.entering.nextValidKeyView === l.first)
    }

    @Test func tabSkipsAHiddenMemberAndStopsAtTheList() {
        let l = Linked()
        SidebarAccessibility.link([l.first, l.hidden, l.list, l.last], within: l.list, exit: nil)
        #expect(l.list.canBecomeKeyView)
        #expect(l.first.nextValidKeyView === l.list)
        #expect(l.list.nextValidKeyView === l.last)
    }

    @Test func relinkingANewOrderMovesTheWayOnToTheNewLastElement() {
        let l = Linked()
        SidebarAccessibility.link([l.first, l.hidden, l.list, l.last], within: l.list, exit: nil)
        SidebarAccessibility.link([l.last, l.list, l.first], within: l.list, exit: nil)
        #expect(l.last.nextKeyView === l.list)
        #expect(l.list.nextKeyView === l.first)
        #expect(l.first.nextKeyView === l.outside)
    }

    @Test func theWindowOwnersExitReplacesTheWindowLoopsLink() {
        let l = Linked()
        SidebarAccessibility.link([l.first, l.hidden, l.list, l.last], within: l.list, exit: nil)
        SidebarAccessibility.link([l.last, l.list, l.first], within: l.list, exit: l.page)
        #expect(l.first.nextKeyView === l.page)
    }

    @Test func aRemovedFormerMemberIsNotTakenAsTheWayOut() {
        let l = Linked()
        let removed = l.field("removed", NSRect(x: 0, y: 90, width: 40, height: 20), in: l.list)
        let tail = l.field("tail", NSRect(x: 0, y: 120, width: 40, height: 20), in: l.list)
        SidebarAccessibility.link([l.first, removed, l.last, tail], within: l.list, exit: nil)
        tail.nextKeyView = nil
        removed.removeFromSuperview()
        SidebarAccessibility.link([l.first, l.last, tail], within: l.list, exit: nil)
        #expect(tail.nextKeyView == nil)
        #expect(l.first.nextKeyView === l.last)
    }

    @Test func anExitSetLaterIsUsedOnTheNextLink() {
        let l = Linked()
        let tail = l.field("tail", NSRect(x: 0, y: 120, width: 40, height: 20), in: l.list)
        SidebarAccessibility.link([l.first, l.last, tail], within: l.list, exit: nil)
        SidebarAccessibility.link([l.first, l.last, tail], within: l.list, exit: l.page)
        #expect(tail.nextKeyView === l.page)
        #expect(l.first.nextValidKeyView === l.last)
    }

    @Test func anOutsideLinkIntoAFormerFirstMemberMovesToTheNewStart() {
        let l = Linked()
        let tail = l.field("tail", NSRect(x: 0, y: 120, width: 40, height: 20), in: l.list)
        let formerEntry = l.field("formerEntry", NSRect(x: 0, y: 150, width: 40, height: 20), in: l.list)
        SidebarAccessibility.link([formerEntry, l.first, l.last, tail], within: l.list, exit: l.page)
        l.entering.nextKeyView = formerEntry
        SidebarAccessibility.link([l.first, formerEntry, l.last, tail], within: l.list, exit: l.page)
        #expect(l.entering.nextKeyView === l.first)
        #expect(l.first.previousKeyView === l.entering)
        #expect(l.first.nextKeyView === formerEntry)
        #expect(formerEntry.nextKeyView === l.last)
    }

    @Test func aHiddenSidebarsControlsAreNoKeyViews() {
        let l = Linked()
        l.list.isHidden = true
        #expect(!l.first.canBecomeKeyView)
        #expect(!l.last.canBecomeKeyView)
        #expect(!l.list.canBecomeKeyView)
    }

    @Test func theWayOutSkipsAHiddenPreparedListsLinks() {
        let l = Linked()
        let owner = FlippedView(frame: NSRect(x: 0, y: 200, width: 240, height: 120))
        l.r.root.addSubview(owner)
        let start = l.field("start", NSRect(x: 0, y: 0, width: 40, height: 20), in: owner)
        let end = l.field("end", NSRect(x: 50, y: 0, width: 40, height: 20), in: owner)
        let prepared = FlippedView(frame: NSRect(x: 0, y: 30, width: 240, height: 40))
        owner.addSubview(prepared)
        prepared.isHidden = true
        l.field("prepared", NSRect(x: 0, y: 0, width: 40, height: 20), in: prepared).nextKeyView = l.outside
        l.field("shown", NSRect(x: 0, y: 80, width: 40, height: 20), in: owner).nextKeyView = l.page
        SidebarAccessibility.link([start, end], within: owner, exit: nil, skipping: { $0.isHidden })
        #expect(start.nextKeyView === end)
        #expect(end.nextKeyView === l.page)
    }

    @Test func withoutSkippingTheHiddenListsLinkWouldBeTheWayOut() {
        let l = Linked()
        let owner = FlippedView(frame: NSRect(x: 0, y: 200, width: 240, height: 120))
        l.r.root.addSubview(owner)
        let start = l.field("start", NSRect(x: 0, y: 0, width: 40, height: 20), in: owner)
        let end = l.field("end", NSRect(x: 50, y: 0, width: 40, height: 20), in: owner)
        let prepared = FlippedView(frame: NSRect(x: 0, y: 30, width: 240, height: 40))
        owner.addSubview(prepared)
        prepared.isHidden = true
        l.field("prepared", NSRect(x: 0, y: 0, width: 40, height: 20), in: prepared).nextKeyView = l.outside
        SidebarAccessibility.link([start, end], within: owner, exit: nil)
        #expect(end.nextKeyView === l.outside)
    }

    @Test func theResizeStripIsNotAnAccessibilityElementAndIsAbsentFromTheTree() {
        let r = Region()
        let container = NSView(frame: r.root.bounds)
        container.setAccessibilityElement(true)
        container.setAccessibilityRole(.group)
        let strip = SidebarResizeRegionView(frame: SidebarResizeRegionView.frame(trailing: NSRect(x: 0, y: 0, width: 228, height: 400), in: r.root.bounds))
        let toggle = NSButton(title: "Hide sidebar", target: nil, action: nil)
        container.addSubview(strip)
        container.addSubview(toggle)
        r.root.addSubview(container)
        let children = container.accessibilityChildren() as? [NSObject] ?? []
        #expect(!strip.isAccessibilityElement())
        #expect([nil, .unknown].contains(strip.accessibilityRole()))
        #expect(!children.contains { $0 === strip })
        #expect(children.contains { $0 === toggle || $0 === toggle.cell })
        #expect(strip.accessibilityHitTest(NSPoint(x: strip.frame.midX, y: strip.frame.midY)).map { $0 as AnyObject !== strip } ?? true)
    }

    @MainActor private final class Header {
        let browser = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 900, height: 600),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 600))
        let address = ActionButton("Address", symbol: "magnifyingglass")
        let lights = WindowStandardButtons()
        let back = ActionButton(SidebarAccessibility.goBack, symbol: "arrow.left")
        let forward = ActionButton(SidebarAccessibility.goForward, symbol: "arrow.right")
        let reload = ActionButton(SidebarAccessibility.reload, symbol: "arrow.clockwise")
        let footer = ActionButton("Space actions", symbol: "ellipsis")
        let headerToggle = ActionButton(SidebarAccessibility.hideSidebar, symbol: "sidebar.left")

        init() {
            browser.isReleasedWhenClosed = false
            let surface = NSView(frame: sidebar.bounds)
            surface.addSubview(address)
            sidebar.addSubview(surface)
            for view in [lights, back, forward, reload, footer, headerToggle] { sidebar.addSubview(view) }
            browser.contentView?.addSubview(sidebar)
        }

        deinit { MainActor.assumeIsolated { browser.close() } }

        func owner(_ element: Any) -> NSView? { (element as? NSView) ?? (element as? NSCell)?.controlView }
        var header: [NSView] { [lights, headerToggle, back, forward, reload] }
    }

    @Test func appKitAloneListsTheContentSurfaceFirst() {
        let h = Header()
        #expect((h.sidebar.accessibilityChildren() ?? []).first.flatMap(h.owner) === h.address)
    }

    @Test func reorderingKeepsEveryElement() {
        let h = Header()
        let natural = h.sidebar.accessibilityChildren() ?? []
        let ordered = SidebarAccessibility.headerFirst(natural, header: h.header)
        #expect(h.lights.buttons.count == 3)
        #expect(ordered.count == natural.count)
    }

    @Test func lightsToggleBackForwardReloadThenTheRestInSubviewOrder() {
        let h = Header()
        let ordered = SidebarAccessibility.headerFirst(h.sidebar.accessibilityChildren() ?? [], header: h.header)
        #expect(ordered.compactMap(h.owner) == h.lights.buttons + [h.headerToggle, h.back, h.forward, h.reload, h.address, h.footer])
    }

    @Test func theTreeOpensWithAXCloseButtonAndAXMinimizeButton() {
        let h = Header()
        let ordered = SidebarAccessibility.headerFirst(h.sidebar.accessibilityChildren() ?? [], header: h.header)
        #expect(ordered.prefix(2).compactMap { $0 as? NSCell }.map { $0.accessibilitySubrole() } == [.closeButton, .minimizeButton])
    }

    @Test func theTrafficLightsAreNoKeyboardStops() {
        let h = Header()
        #expect(h.lights.buttons.allSatisfy { $0.refusesFirstResponder && !$0.acceptsFirstResponder && !$0.canBecomeKeyView })
        #expect(SidebarAccessibility.keyViews(in: [h.lights], space: h.sidebar).isEmpty)
    }

    @Test func withoutItsLightsTheHeaderLeadsWithTheToggle() {
        let h = Header()
        _ = h.lights.buttons
        h.lights.isHidden = true
        let ordered = SidebarAccessibility.headerFirst(h.sidebar.accessibilityChildren() ?? [], header: h.header)
        #expect(ordered.first.flatMap(h.owner) === h.headerToggle)
    }

    @Test func aNarrowHeaderOrdersItsVisibleControlsByFrame() {
        let h = Header()
        h.back.frame.origin.x = 70
        h.forward.frame.origin.x = 104
        h.headerToggle.frame.origin.x = 138
        h.reload.isHidden = true
        #expect(SidebarAccessibility.laidOut([h.headerToggle, h.back, h.forward, h.reload]) == [h.back, h.forward, h.headerToggle])
    }

    @Test func aNarrowHeadersTreeFollowsTheFrames() {
        let h = Header()
        h.back.frame.origin.x = 70
        h.forward.frame.origin.x = 104
        h.headerToggle.frame.origin.x = 138
        h.reload.isHidden = true
        let narrow = SidebarAccessibility.laidOut([h.headerToggle, h.back, h.forward, h.reload])
        let tree = SidebarAccessibility.headerFirst(h.sidebar.accessibilityChildren() ?? [], header: [h.lights] + narrow)
        #expect(Array(tree.compactMap(h.owner).prefix(6)) == h.lights.buttons + [h.back, h.forward, h.headerToggle])
    }

    @Test func aBackPointerRecordsTheLastViewLinkedAndIsNotClearedWhenThatViewLinksElsewhere() {
        let (first, second, member, elsewhere) = (NSView(), NSView(), NSView(), NSView())
        first.nextKeyView = member
        second.nextKeyView = member
        #expect(member.previousKeyView === second)
        second.nextKeyView = elsewhere
        #expect(member.previousKeyView === second)
        #expect(first.nextKeyView === member)
    }

    @MainActor private final class Offscreen {
        let browser = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 900, height: 600),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let page = NSTextField(string: "page")
        let pageEnd = NSTextField(string: "end")
        let container: NSView
        let sidebar: ListStopView
        let headerToggle = ActionButton(SidebarAccessibility.hideSidebar, symbol: "sidebar.left")
        let address = NSTextField(string: "address")

        init() {
            browser.isReleasedWhenClosed = false
            browser.contentView = content
            page.frame = NSRect(x: 300, y: 300, width: 200, height: 22)
            content.addSubview(page)
            pageEnd.frame = NSRect(x: 300, y: 200, width: 200, height: 22)
            content.addSubview(pageEnd)
            container = NSView(frame: SidebarPresentationFrame.locked.rect(width: 228, in: content.bounds))
            content.addSubview(container)
            sidebar = ListStopView(frame: container.bounds)
            container.addSubview(sidebar)
            headerToggle.frame = NSRect(x: 76, y: 7, width: 32, height: 32)
            address.frame = NSRect(x: 8, y: 46, width: 212, height: 36)
            sidebar.addSubview(headerToggle)
            sidebar.addSubview(address)
        }

        deinit { MainActor.assumeIsolated { browser.close() } }

        func exposed(_ view: NSView) -> AnyObject? { NSAccessibility.unignoredDescendant(of: view) as AnyObject? }

        func listed(_ elements: [Any]?, _ view: NSView) -> Bool {
            NSAccessibility.unignoredChildren(from: elements ?? []).contains { $0 as AnyObject === exposed(view) }
        }

        func hits(_ point: NSPoint) -> (view: Bool, element: Bool) {
            let view = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
            let element = browser.accessibilityHitTest(browser.convertPoint(toScreen: point)) as AnyObject?
            return (view.map { $0 === address || $0.isDescendant(of: address) } == true, element != nil && element === exposed(address))
        }

        func hide() { container.frame = SidebarPresentationFrame.hidden.rect(width: 228, in: content.bounds) }
        var addressCentre: NSPoint { address.convert(NSPoint(x: address.bounds.midX, y: address.bounds.midY), to: nil) }
        func forward(from view: NSView) -> [NSView] { Array(sequence(first: view) { $0.nextValidKeyView }.prefix(8).dropFirst()) }
        func backward(from view: NSView) -> [NSView] { Array(sequence(first: view) { $0.previousValidKeyView }.prefix(8).dropFirst()) }
        func inside(_ views: [NSView]) -> Bool { views.contains { $0.isDescendant(of: container) } }
    }

    @Test func lockedPointerAndAccessibilityHitTestsReachTheAddress() {
        let o = Offscreen()
        let locked = o.hits(o.addressCentre)
        #expect(locked.view)
        #expect(locked.element)
    }

    @Test func theHiddenSidebarIsUnhiddenAndWhollyOutsideTheContent() {
        let o = Offscreen()
        o.hide()
        #expect(!o.container.isHidden)
        #expect(o.container.frame.maxX < 0)
        #expect(o.address.convert(o.address.bounds, to: nil).maxX < 0)
    }

    @Test func itsControlsStayInTheWindowsAccessibilityChildrenAndNavigationOrder() {
        let o = Offscreen()
        o.hide()
        #expect(o.listed(o.browser.accessibilityChildren(), o.headerToggle))
        #expect(o.listed(o.browser.accessibilityChildren(), o.address))
        let navigation = o.browser.perform(#selector(NSWindow.accessibilityChildrenInNavigationOrder))?.takeUnretainedValue() as? [Any]
        #expect(o.listed(navigation, o.address))
    }

    @Test func theirAccessibilityFramesLieLeftOfTheWindow() {
        let o = Offscreen()
        o.hide()
        let element = o.exposed(o.address) as? NSAccessibilityElementProtocol
        #expect((element?.accessibilityFrame().maxX ?? .infinity) <= o.browser.frame.minX)
    }

    @Test func hiddenNeitherHitTestReachesThemWhereTheyWereOrWhereTheyAre() {
        let o = Offscreen()
        let lockedPoint = o.addressCentre
        o.hide()
        let formerPlace = o.hits(lockedPoint)
        let offScreen = o.hits(o.addressCentre)
        #expect(!formerPlace.view)
        #expect(!formerPlace.element)
        #expect(!offScreen.view)
        #expect(!offScreen.element)
    }

    @Test func anOffScreenFieldsVisibleRectIsNotEmpty() {
        let o = Offscreen()
        o.hide()
        #expect(!o.address.visibleRect.isEmpty)
        #expect(!o.address.bounds.contains(o.address.visibleRect))
    }

    @Test func aSelfClippingViewsVisibleRectIsItsBounds() {
        let o = Offscreen()
        let clipping = NSView(frame: NSRect(x: 600, y: 100, width: 100, height: 28))
        clipping.clipsToBounds = true
        o.content.addSubview(clipping)
        #expect(clipping.visibleRect == clipping.bounds)
    }

    @Test func anOffScreenFieldTakesFocus() {
        let o = Offscreen()
        o.hide()
        #expect(o.browser.makeFirstResponder(o.address))
        #expect(o.browser.firstResponder is NSTextView)
    }

    @Test func appKitsComputedLoopIncludesTheOffScreenField() {
        let o = Offscreen()
        o.hide()
        _ = o.browser.makeFirstResponder(nil)
        o.browser.recalculateKeyViewLoop()
        #expect(o.forward(from: o.page).contains { $0 === o.address })
    }

    private func chain(_ o: Offscreen) -> [NSView] {
        let gate = NSView()
        o.sidebar.addSubview(gate)
        return [gate, o.headerToggle, o.address, o.sidebar]
    }

    @Test func unbypassedTabReachesTheOffScreenChainPastItsGate() {
        let o = Offscreen()
        o.hide()
        o.browser.recalculateKeyViewLoop()
        let c = chain(o)
        SidebarAccessibility.link(c, within: o.sidebar, exit: nil)
        #expect(o.forward(from: o.page).contains { $0 === o.address })
        #expect(!c[0].canBecomeKeyView)
    }

    @Test func withoutAnExitTheChainsEndKeepsTheComputedLoopsWayOn() {
        let o = Offscreen()
        o.hide()
        o.browser.recalculateKeyViewLoop()
        SidebarAccessibility.link(chain(o), within: o.sidebar, exit: nil)
        #expect(o.sidebar.nextKeyView.map { !$0.isDescendant(of: o.container) } == true)
        #expect(o.sidebar.nextValidKeyView != nil)
    }

    @Test func bypassedWithoutAnExitTabAndShiftTabPassTheHiddenChain() {
        let o = Offscreen()
        o.hide()
        o.browser.recalculateKeyViewLoop()
        let c = chain(o)
        o.sidebar.presented = false
        SidebarAccessibility.link(c, within: o.sidebar, exit: nil, bypassed: true)
        #expect(!o.inside(o.forward(from: o.page) + o.backward(from: o.page) + o.forward(from: o.pageEnd) + o.backward(from: o.pageEnd)))
    }

    @Test func theWindowOwnersWayInAndOut() {
        let o = Offscreen()
        o.hide()
        o.browser.recalculateKeyViewLoop()
        let c = chain(o)
        SidebarAccessibility.link(c, within: o.sidebar, exit: nil)
        o.pageEnd.nextKeyView = c[0]
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page)
        #expect([o.headerToggle, o.address].contains { $0 === o.pageEnd.nextValidKeyView })
        #expect(o.sidebar.nextValidKeyView === o.page)
        #expect(o.page.previousValidKeyView === o.sidebar)
    }

    @Test func bypassedTabAndShiftTabPassTheHiddenChainAndRelinkingKeepsTheBypass() {
        let o = Offscreen()
        o.hide()
        o.browser.recalculateKeyViewLoop()
        let c = chain(o)
        SidebarAccessibility.link(c, within: o.sidebar, exit: nil)
        o.pageEnd.nextKeyView = c[0]
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page)
        o.sidebar.presented = false
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page, bypassed: true)
        #expect(o.pageEnd.nextValidKeyView === o.page)
        #expect(o.page.previousValidKeyView === o.pageEnd)
        #expect(!o.inside(o.forward(from: o.page) + o.backward(from: o.page) + o.forward(from: o.pageEnd)))
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page, bypassed: true)
        #expect(o.pageEnd.nextValidKeyView === o.page)
        #expect(o.page.previousValidKeyView === o.pageEnd)
    }

    @Test func presentingItAgainRestoresTheChainBehindItsWayInAndTheWayBackToItsEnd() {
        let o = Offscreen()
        o.hide()
        o.browser.recalculateKeyViewLoop()
        let c = chain(o)
        o.pageEnd.nextKeyView = c[0]
        o.sidebar.presented = false
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page, bypassed: true)
        o.sidebar.presented = true
        SidebarAccessibility.link(c, within: o.sidebar, exit: o.page)
        #expect([o.headerToggle, o.address].contains { $0 === o.pageEnd.nextValidKeyView })
        #expect(o.page.previousValidKeyView === o.sidebar)
        #expect(o.address.nextKeyView === o.sidebar)
        #expect(o.sidebar.previousKeyView === o.address)
    }

    @Test func anOffScreenFieldKeepsFocus() {
        let o = Offscreen()
        #expect(o.browser.makeFirstResponder(o.address))
        #expect((o.browser.firstResponder as? NSText)?.delegate === o.address)
    }

    @Test func hiddenTheListTakesNoFocus() {
        let o = Offscreen()
        o.sidebar.presented = false
        _ = o.browser.makeFirstResponder(o.sidebar)
        #expect(o.browser.firstResponder === o.browser)
    }

    @Test func aPresentedSidebarsViewsMayTakeRestoredFocus() {
        let o = Offscreen()
        #expect(SavedFocus.mayReturn(to: o.address, in: o.browser))
        #expect(SavedFocus.mayReturn(to: o.sidebar, in: o.browser))
    }

    @Test func aSidebarThatIsNotPresentedTakesNoRestoredFocus() {
        let o = Offscreen()
        _ = o.browser.makeFirstResponder(o.address)
        let editor = o.browser.firstResponder as? NSTextView
        o.sidebar.presented = false
        #expect(!SavedFocus.mayReturn(to: o.address, in: o.browser))
        #expect(!SavedFocus.mayReturn(to: o.headerToggle, in: o.browser))
        #expect(!SavedFocus.mayReturn(to: o.sidebar, in: o.browser))
        #expect(editor.map { $0.isDescendant(of: o.address) && !SavedFocus.mayReturn(to: $0, in: o.browser) } == true)
    }

    @Test func thePageMayTakeRestoredFocusAndNoOtherWindowMay() {
        let o = Offscreen()
        #expect(SavedFocus.mayReturn(to: o.page, in: o.browser))
        #expect(!SavedFocus.mayReturn(to: o.page, in: nil))
        #expect(!SavedFocus.mayReturn(to: o.page, in: NSWindow()))
    }

    @Test func hidingTheContainerGivesItsFocusToTheWindowAndLeavesBothTrees() {
        let o = Offscreen()
        _ = o.browser.makeFirstResponder(o.address)
        o.container.isHidden = true
        #expect(o.browser.firstResponder === o.browser)
        #expect(!SavedFocus.mayReturn(to: o.address, in: o.browser))
        #expect(!o.listed(o.browser.accessibilityChildren(), o.address))
        #expect(!o.address.canBecomeKeyView)
    }

    @Test func hiddenTheSelectionActionLeavesThePagesFocus() {
        let o = Offscreen()
        o.sidebar.presented = false
        #expect(o.browser.makeFirstResponder(o.page))
        o.sidebar.focusIfPresented()
        #expect((o.browser.firstResponder as? NSText)?.delegate === o.page)
    }

    @Test func presentedTheListStopTakesFocus() {
        let o = Offscreen()
        _ = o.browser.makeFirstResponder(o.page)
        o.sidebar.focusIfPresented()
        #expect(o.browser.firstResponder === o.sidebar)
    }

    @Test func aWindowThatIsNotKeyRevealsNothing() {
        let o = Offscreen()
        var reveals = 0
        #expect(o.sidebar.presentsForEditing(reveal: { reveals += 1 }))
        #expect(reveals == 0)
    }

    @Test func noEditWhileHidden() {
        let o = Offscreen()
        var reveals = 0
        o.sidebar.presented = false
        #expect(!o.sidebar.presentsForEditing(reveal: { reveals += 1 }))
        #expect(reveals == 0)
    }

    @MainActor private final class KeyLike {
        let window = KeyLikeWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let renamed = ListStopView(frame: NSRect(x: 0, y: 0, width: 228, height: 300))
        var reveals = 0

        init() {
            window.isReleasedWhenClosed = false
            window.contentView?.addSubview(renamed)
        }

        deinit { MainActor.assumeIsolated { window.close() } }
    }

    @Test func inMotionAndStillPresentedTheOwnersRevealRunsAndSettlesItFirst() {
        let k = KeyLike()
        #expect(k.renamed.presentsForEditing(reveal: { k.reveals += 1 }))
        #expect(k.reveals == 1)
    }

    @Test func hiddenTheOwnerFloatsItInAndTheEditBegins() {
        let k = KeyLike()
        k.renamed.presented = false
        #expect(k.renamed.presentsForEditing(reveal: { k.reveals += 1; k.renamed.presented = true }))
        #expect(k.reveals == 1)
    }

    @Test func anOwnerThatCannotRevealItRefusesTheEdit() {
        let k = KeyLike()
        k.renamed.presented = false
        #expect(!k.renamed.presentsForEditing(reveal: { k.reveals += 1 }))
        #expect(k.reveals == 1)
    }

    @Test func withoutAnOwnerItStaysRefused() {
        let k = KeyLike()
        k.renamed.presented = false
        #expect(!k.renamed.presentsForEditing(reveal: nil))
    }
}
