import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcSidebar

private final class DragSource: NSView, SidebarItemDragSource {
    var sidebarDrag: SidebarMoveSession?
}

private final class WindowDrop: NSObject, NSDraggingInfo {
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

@MainActor private final class ManualClock {
    private var now: TimeInterval = 0
    private var pending: [(at: TimeInterval, work: () -> Void)] = []

    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) { pending.append((now + delay, work)) }

    func advance(by seconds: TimeInterval) {
        now += seconds
        while let index = pending.indices.filter({ pending[$0].at <= now }).min(by: { pending[$0].at < pending[$1].at }) {
            pending.remove(at: index).work()
        }
    }
}

@MainActor
struct SidebarWindowClearTests {
    typealias Chrome = SidebarChromeLayout

    @MainActor private final class WindowSidebar {
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let window: SidebarTestWindow
        var state = BrowserState.initial()
        let pinned: BrowserTab
        let clock = ManualClock()
        var cleared = 0

        static func tab(_ name: String, _ kind: TabKind, in space: BrowserSpace) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://example.test/\(name)", title: name,
                       kind: kind, createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/\(name)", savedTitle: name)
        }

        init(handler: Bool = true) {
            window = sidebarTestWindow(containing: sidebar, deferred: false)
            window.applicationActive = true
            let space = state.spaces[0]
            pinned = Self.tab("pinned", .pinned, in: space)
            state.tabs = [pinned, Self.tab("today", .today, in: space), Self.tab("later", .today, in: space)]
            if handler { sidebar.onClearToday = { [weak self] in self?.cleared += 1 } }
            sidebar.fadeClear = { [clock] button, alpha, done in
                button.alphaValue = alpha
                clock.schedule(after: SidebarClearAppearance.revealDuration, done)
            }
            render(state)
        }

        deinit {
            MainActor.assumeIsolated { window.contentView = nil }
        }

        func render(_ state: BrowserState) {
            sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
            sidebar.layoutSubtreeIfNeeded()
        }

        var clear: ActionButton? {
            sidebarDescendants(sidebar).compactMap { $0 as? ActionButton }.first { $0.identifier?.rawValue == "sidebarClear" }
        }

        var section: NSView { clear!.superview! }
        var line: SidebarHairline { section.subviews.compactMap { $0 as? SidebarHairline }.first! }

        func centre(of view: NSView) -> NSPoint {
            section.convert(NSPoint(x: view.frame.midX, y: view.frame.midY), to: section.superview)
        }

        func exposed() -> Bool {
            let clear = self.clear!
            return (section.accessibilityChildren() ?? []).contains { ($0 as AnyObject) === clear || ($0 as AnyObject) === clear.cell }
        }

        func relayout() {
            section.needsLayout = true
            section.layoutSubtreeIfNeeded()
        }

        var reveal: SidebarAreaEvent {
            let event = SidebarAreaEvent()
            event.area = sidebar.trackingAreas.first { $0.owner === sidebar && $0.options.contains(.activeInActiveApp) }
            return event
        }

        func enter() {
            sidebar.updateTrackingAreas()
            window.pointer = sidebar.convert(NSPoint(x: 100, y: 300), to: nil)
            sidebar.mouseEntered(with: reveal)
        }

        func exit() {
            window.pointer = NSPoint(x: -100, y: -100)
            sidebar.mouseExited(with: reveal)
        }

        func fade() {
            clock.advance(by: SidebarClearAppearance.revealDuration)
            relayout()
        }

        func revealed() -> WindowSidebar {
            enter()
            fade()
            return self
        }
    }

    private func resting(_ color: NSColor?) -> Bool {
        let c = color!.usingColorSpace(.sRGB)!
        let v = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { ($0 * 100).rounded() / 100 }
        return v[3] == 0.3 && (v[0] == 0 || v[0] == 1) && v[0] == v[1] && v[1] == v[2]
    }

    private func hovered(_ color: NSColor?) -> Bool {
        let c = color!.usingColorSpace(.sRGB)!
        return [0.8, 0.9].contains((c.alphaComponent * 100).rounded() / 100)
    }

    @Test func withoutAClearHandlerTheWindowsClearIsDisabled() {
        #expect(WindowSidebar(handler: false).clear?.isEnabled == false)
    }

    @Test func theWindowDividerIsOneRowOfBorderAndClear() {
        let s = WindowSidebar()
        #expect(s.section.subviews.count == 2)
        #expect(!s.section.subviews.contains { $0 is NSBox })
    }

    @Test func atRestTheWindowsClearIsHidden() {
        let clear = WindowSidebar().clear!
        #expect(clear.isHidden)
        #expect(clear.alphaValue == 0)
        #expect(clear.isEnabled)
    }

    @Test func aHiddenClearIsNoKeyViewAndNoAccessibilityChild() {
        let s = WindowSidebar()
        #expect(!s.clear!.canBecomeKeyView)
        #expect(!s.exposed())
    }

    @Test func aHiddenClearTakesNoClicks() {
        let s = WindowSidebar()
        #expect(s.section.hitTest(s.centre(of: s.clear!)) !== s.clear)
    }

    @Test func atRestTheBorderSpansTheCellsInsetsCentred() {
        let s = WindowSidebar()
        let thickness = Chrome.sectionDividerThickness(scale: s.window.backingScaleFactor)
        #expect(s.line.frame.minX == Chrome.sectionDividerInset)
        #expect(s.line.frame.width == s.section.bounds.width - 2 * Chrome.sectionDividerInset)
        #expect(s.line.frame.height == thickness)
        #expect(abs(s.line.frame.midY - s.section.bounds.midY) <= thickness / 2)
    }

    @Test func theWindowSidebarTracksThePointerEnteringIt() {
        let s = WindowSidebar()
        s.sidebar.updateTrackingAreas()
        #expect(s.reveal.area != nil)
    }

    @Test func anotherTrackingAreasEntryLeavesClearHidden() {
        let s = WindowSidebar()
        s.sidebar.updateTrackingAreas()
        s.sidebar.mouseEntered(with: SidebarAreaEvent())
        #expect(s.clear!.isHidden)
    }

    @Test func thePointerEnteringTheSidebarUnhidesClearBeforeItsFadeIn() {
        let s = WindowSidebar()
        s.enter()
        #expect(!s.clear!.isHidden)
    }

    @Test func aRevealedClearIsOpaqueAfterItsFadeIn() {
        let clear = WindowSidebar().revealed().clear!
        #expect(!clear.isHidden)
        #expect(clear.alphaValue == 1)
    }

    @Test func aRevealedClearIsAnAccessibilityChild() {
        #expect(WindowSidebar().revealed().exposed())
    }

    @Test func evenRevealedClearIsNoKeyView() {
        let s = WindowSidebar().revealed()
        let clear = s.clear!
        #expect(clear.refusesFirstResponder)
        #expect(!clear.acceptsFirstResponder)
        #expect(!clear.canBecomeKeyView)
        #expect(!SidebarAccessibility.keyViews(in: [s.section], space: s.sidebar).contains { $0 === clear })
    }

    @Test func clearHugsItsArrowItsCellsInsetInsideTheTrailingEdge() {
        let s = WindowSidebar().revealed()
        let clear = s.clear!
        let width = ceil(clear.intrinsicContentSize.width)
        let pad = clear.cell!.imageRect(forBounds: NSRect(x: 0, y: 0, width: width, height: 20)).minX
        #expect(pad > 0)
        #expect(clear.frame.width == width - pad)
        #expect(clear.frame.height == 20)
        #expect(clear.frame.maxX == s.section.bounds.width - Chrome.sectionDividerInset)
        #expect(abs(clear.frame.midY - s.section.bounds.midY) < 0.01)
    }

    @Test func whileClearShowsTheBorderEndsEightBeforeIt() {
        let s = WindowSidebar().revealed()
        #expect(s.line.frame.minX == Chrome.sectionDividerInset)
        #expect(s.line.frame.maxX == s.clear!.frame.minX - Chrome.sectionDividerSpacing)
    }

    @Test func onlyARevealedClearsOwnWidthTakesItsClicks() {
        let s = WindowSidebar().revealed()
        #expect(s.section.hitTest(s.centre(of: s.clear!)) === s.clear)
        #expect(s.section.hitTest(s.section.convert(NSPoint(x: 20, y: s.section.bounds.midY), to: s.section.superview)) !== s.clear)
    }

    @Test func clearKeepsItsTooltipAccessibleNameAndNoKeyboardRing() {
        let clear = WindowSidebar().revealed().clear!
        #expect(clear.parcTooltip == TooltipConfiguration("Clear Today tabs", shortcut: .command("clearToday:")))
        #expect(clear.toolTip == nil)
        #expect(clear.accessibilityLabel() == "Clear")
        #expect(clear.focusRingType == .none)
    }

    @Test func aRevealedClearThePointerIsNotOnIsForegroundTertiary() {
        let clear = WindowSidebar().revealed().clear!
        #expect(clear.font == NSFont.systemFont(ofSize: 10, weight: .semibold))
        #expect(resting(clear.contentTintColor))
    }

    @Test func hoveringTheWindowsClearTintsItForegroundPrimary() {
        let clear = WindowSidebar().revealed().clear!
        clear.mouseEntered(with: SidebarAreaEvent())
        #expect(hovered(clear.contentTintColor))
    }

    @Test func theWindowsClearReachesItsHandler() {
        let s = WindowSidebar().revealed()
        let clear = s.clear!
        clear.sendAction(clear.action, to: clear.target)
        #expect(s.cleared == 1)
    }

    @Test func voiceOverCanPressARevealedClear() {
        let s = WindowSidebar().revealed()
        _ = s.clear!.cell?.accessibilityPerformPress()
        #expect(s.cleared == 1)
    }

    @Test func clearKeepsItsPlaceInTheRowWhileItFadesOut() {
        let s = WindowSidebar().revealed()
        s.exit()
        s.relayout()
        #expect(!s.clear!.isHidden)
        #expect(s.line.frame.maxX == s.clear!.frame.minX - Chrome.sectionDividerSpacing)
    }

    @Test func clearIsStillShownJustBeforeItsFadeOutEnds() {
        let s = WindowSidebar().revealed()
        s.exit()
        s.clock.advance(by: SidebarClearAppearance.revealDuration / 2)
        #expect(!s.clear!.isHidden)
    }

    @Test func afterItsFadeOutClearIsHiddenAgain() {
        let s = WindowSidebar().revealed()
        s.exit()
        s.fade()
        #expect(s.clear!.isHidden)
        #expect(s.clear!.alphaValue == 0)
    }

    @Test func aClearHiddenAgainTakesNoClicksKeyFocusOrAccessibility() {
        let s = WindowSidebar().revealed()
        s.exit()
        s.fade()
        #expect(!s.exposed())
        #expect(!s.clear!.canBecomeKeyView)
        #expect(s.section.hitTest(s.centre(of: s.clear!)) !== s.clear)
    }

    @Test func afterClearFadesOutTheBorderSpansTheRowAgain() {
        let s = WindowSidebar().revealed()
        s.exit()
        s.fade()
        #expect(s.line.frame.maxX == s.section.bounds.width - Chrome.sectionDividerInset)
    }

    @Test func reenteringDuringTheFadeOutKeepsClearRevealed() {
        let s = WindowSidebar().revealed()
        s.exit()
        s.enter()
        s.fade()
        #expect(!s.clear!.isHidden)
        #expect(s.clear!.alphaValue == 1)
    }

    @Test func leavingDuringTheFadeInStillFadesClearOut() {
        let s = WindowSidebar()
        s.enter()
        s.clock.advance(by: SidebarClearAppearance.revealDuration * 0.9)
        s.exit()
        #expect(!s.clear!.isHidden)
        s.fade()
        #expect(s.clear!.isHidden)
    }

    @Test func aRenderWhileTheSidebarIsHoveredStartsClearRevealed() {
        let s = WindowSidebar().revealed()
        let before = s.clear!
        var grown = s.state
        grown.tabs.append(WindowSidebar.tab("grown", .today, in: grown.spaces[0]))
        s.render(grown)
        let rendered = s.clear!
        #expect(rendered !== before)
        #expect(!rendered.isHidden)
        #expect(rendered.alphaValue == 1)
    }

    @Test func leavingHidesTheClearARenderStartedRevealed() {
        let s = WindowSidebar().revealed()
        var grown = s.state
        grown.tabs.append(WindowSidebar.tab("grown", .today, in: grown.spaces[0]))
        s.render(grown)
        let rendered = s.clear!
        s.exit()
        s.fade()
        #expect(rendered.isHidden)
    }

    private func withoutToday(_ s: WindowSidebar) {
        var todayless = s.state
        todayless.tabs = [s.pinned]
        s.render(todayless)
    }

    @Test func withoutTodayTabsThereIsNoDividerAndNoClearEvenWhenHovered() {
        let s = WindowSidebar()
        withoutToday(s)
        s.enter()
        #expect(s.clear == nil)
        #expect(!sidebarDescendants(s.sidebar).contains { $0 is SidebarHairline })
    }

    @Test func anEmptyTodayShowsNoPlaceholderText() {
        let s = WindowSidebar()
        withoutToday(s)
        #expect(!sidebarDescendants(s.sidebar).compactMap { $0 as? NSTextField }.contains { $0.stringValue.localizedCaseInsensitiveContains("new tabs appear") })
    }

    @Test func newTabFollowsTheLastPinnedRowFortyOnePointsOn() {
        let s = WindowSidebar()
        withoutToday(s)
        let pinnedRow = sidebarDescendants(s.sidebar).compactMap { $0 as? SidebarTabRow }.first { $0.tabID == s.pinned.id }!
        let newTab = sidebarDescendants(s.sidebar).compactMap { $0 as? SidebarNewTabRow }.first!
        func midY(_ view: NSView) -> CGFloat { view.convert(view.bounds, to: s.sidebar).midY }
        #expect(abs(midY(newTab) - midY(pinnedRow)) == Chrome.tablistCellHeight + Chrome.tablistIntercellSpacing)
    }

    @Test func newTabsUpperHalfEndsPinnedAndItsLowerHalfBeginsToday() {
        let s = WindowSidebar()
        withoutToday(s)
        let source = DragSource(frame: .zero)
        s.sidebar.addSubview(source)
        var commits: [SidebarContainerLocation] = []
        func drop(at point: NSPoint) {
            let session = SidebarMoveSession(items: [.tab(s.pinned.id)], window: s.window, validate: { true }, propose: { _, _ in true },
                                             commit: { location, _ in commits.append(location); return true })
            source.sidebarDrag = session
            let info = WindowDrop()
            info.draggingSource = source
            info.draggingDestinationWindow = s.window
            info.draggingPasteboard.clearContents()
            info.draggingPasteboard.setString(session.identifier.uuidString, forType: SidebarMoveSession.pasteboardType)
            info.draggingLocation = s.sidebar.convert(point, to: nil)
            _ = s.sidebar.performDragOperation(info)
            info.draggingPasteboard.releaseGlobally()
        }
        let newTab = sidebarDescendants(s.sidebar).compactMap { $0 as? SidebarNewTabRow }.first!
        let frame = newTab.convert(newTab.bounds, to: s.sidebar)
        drop(at: NSPoint(x: frame.midX, y: frame.midY + (s.sidebar.isFlipped ? -6 : 6)))
        drop(at: NSPoint(x: frame.midX, y: frame.midY + (s.sidebar.isFlipped ? 6 : -6)))
        source.removeFromSuperview()
        #expect(commits.map(\.section) == [.pinned, .today])
    }
}
