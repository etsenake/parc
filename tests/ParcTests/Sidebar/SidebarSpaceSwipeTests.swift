import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarSpaceSwipeTests {
    final class DragSource: NSView, SidebarItemDragSource { var sidebarDrag: SidebarMoveSession? }

    @MainActor final class Drag: NSObject, @preconcurrency NSDraggingInfo {
        private let pasteboard = NSPasteboard(name: NSPasteboard.Name("org.parc.swipe-tests.\(UUID().uuidString)"))
        private let source: DragSource
        private weak var window: NSWindow?
        var location = NSPoint.zero
        init(source: DragSource, session: SidebarMoveSession, window: NSWindow) {
            self.source = source; self.window = window
            pasteboard.clearContents()
            pasteboard.setString(session.identifier.uuidString, forType: SidebarMoveSession.pasteboardType)
        }
        deinit { pasteboard.releaseGlobally() }
        var draggingDestinationWindow: NSWindow? { window }
        var draggingSourceOperationMask: NSDragOperation { .move }
        var draggingLocation: NSPoint { location }
        var draggedImageLocation: NSPoint { location }
        var draggedImage: NSImage? { nil }
        var draggingPasteboard: NSPasteboard { pasteboard }
        var draggingSource: Any? { source }
        var draggingSequenceNumber: Int { 1 }
        func slideDraggedImage(to screenPoint: NSPoint) {}
        var draggingFormation: NSDraggingFormation = .default
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                    searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        func resetSpringLoading() {}
    }

    struct Scheduled {
        let interval: TimeInterval
        let mode: RunLoop.Mode
        let timer: Timer
        let body: @MainActor () -> Void
    }

    @MainActor final class Stage {
        var state: BrowserState
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 260, height: 900))
        let window: NSWindow
        var pagerClock: CFTimeInterval = 0
        var scheduled: [Scheduled] = []
        var seen: Set<ObjectIdentifier> = []
        var kept: [NSView] = []
        var eventClock: CFTimeInterval = 100
        var toggled = 0

        init(items: Int = 5, spaces: Int = 4) {
            _ = NSApplication.shared
            state = Self.state(items: items, spaces: spaces)
            window = NSWindow(contentRect: sidebar.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let content = NSView(frame: sidebar.frame)
            window.contentView = content; content.addSubview(sidebar)
            let pane = NSView()
            pane.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(pane)
            NSLayoutConstraint.activate([pane.leadingAnchor.constraint(equalTo: content.trailingAnchor),
                                         pane.topAnchor.constraint(equalTo: content.topAnchor),
                                         pane.widthAnchor.constraint(equalToConstant: 0), pane.heightAnchor.constraint(equalToConstant: 0)])
            sidebar.spacePager.now = { [weak self] in self?.pagerClock ?? 0 }
            sidebar.spacePager.reducesMotion = { false }
            sidebar.preparationClock = { 0 }
            sidebar.secondsSinceInput = { 1000 }
            sidebar.hasPendingEvents = { false }
            sidebar.scheduleTimer = { [weak self] interval, mode, body in
                let timer = Timer(timeInterval: interval, repeats: false) { _ in }
                self?.scheduled.append(Scheduled(interval: interval, mode: mode, timer: timer, body: body))
                return timer
            }
            sidebar.prepareSidebarMove = { [weak self] item in self?.moveSession(item) }
            sidebar.prepareSidebarSpaceMove = { [weak self] _, id in id == self?.state.activeSpaceID ? nil : { false } }
            sidebar.canSelectSpace = { _, _ in true }
            sidebar.onSelectSpace = { [weak self] id, _ in self?.state.activeSpaceID = id; self?.render() }
            sidebar.onToggleFolder = { [weak self] id in
                guard let self, let index = state.folders.firstIndex(where: { $0.id == id }) else { return }
                state.folders[index].isExpanded.toggle()
                toggled += 1
                render()
            }
            render()
            sidebar.layoutSubtreeIfNeeded()
            _ = builtRows()
        }

        static func state(items: Int, spaces: Int) -> BrowserState {
            var state = BrowserState.initial()
            let profile = state.profiles[0].id
            for index in 1..<spaces {
                var space = BrowserSpace(id: UUID(), name: "Space \(index + 1)", symbol: "circle.fill", color: "B9B5D4", profileID: profile)
                space.updateDisplayName(position: index)
                state.spaces.append(space)
            }
            for space in state.spaces {
                for index in 0..<items {
                    let folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Folder \(index)")
                    state.folders.append(folder)
                    let url = "https://example\(index).test/"
                    state.tabs.append(BrowserTab(id: UUID(), spaceID: space.id, profileID: profile, url: url, title: "Pinned \(index)",
                        kind: .pinned, folderID: folder.id, createdAt: Date(), lastAccessed: Date(), savedURL: url, savedTitle: "Pinned \(index)"))
                    state.tabs.append(BrowserTab(id: UUID(), spaceID: space.id, profileID: profile, url: url, title: "Today \(index)",
                        kind: .today, createdAt: Date(), lastAccessed: Date(), savedURL: url, savedTitle: "Today \(index)"))
                }
            }
            return state
        }

        func render() { sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false) }

        func moveSession(_ item: SidebarItemReference) -> SidebarMoveSession? {
            guard let space = state.spaces.first(where: { $0.id == state.activeSpaceID }),
                  let expected = SidebarHierarchySnapshot(state: state, spaceID: space.id, profileID: space.profileID, includesFavorites: true),
                  SidebarMoveCollection(items: [item], spaceID: space.id, profileID: space.profileID, state: state) != nil else { return nil }
            return SidebarMoveSession(items: [item], window: window, validate: { [weak self] in self?.state.activeSpaceID == expected.spaceID },
                                      propose: { [weak self] location, before in
                guard let self else { return false }
                return SidebarHierarchy.moving([item], to: location, before: before, expected: expected, state: state) != nil
            }, commit: { _, _ in false })
        }

        func builtRows() -> Int {
            var built = 0
            func walk(_ view: NSView) {
                if view is SidebarTabRow || view is SidebarFolderRow, seen.insert(ObjectIdentifier(view)).inserted {
                    kept.append(view); built += 1
                }
                view.subviews.forEach(walk)
            }
            walk(window.contentView!)
            return built
        }

        func prepareNeighbours() {
            for _ in 0..<10_000 {
                guard let due = scheduled.first(where: { $0.mode == .default && $0.timer.isValid }) else { return }
                due.timer.invalidate()
                due.body()
            }
        }

        func frame(_ body: () -> Void) {
            body(); sidebar.layoutSubtreeIfNeeded(); window.displayIfNeeded(); CATransaction.flush()
        }

        static func moving(_ view: NSView) -> Bool {
            !CATransform3DIsIdentity(view.layer?.sublayerTransform ?? CATransform3DIdentity) || view.subviews.contains(where: moving)
        }

        func settle() -> Bool {
            for _ in 0..<180 where Self.moving(sidebar) {
                pagerClock += 1.0 / 120
                frame { sidebar.spacePager.tick() }
            }
            return !Self.moving(sidebar)
        }

        func scroll(_ dx: Int32, phase: Int64) -> NSEvent {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: dx, wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.timestamp = UInt64(eventClock * 1_000_000_000)
            return NSEvent(cgEvent: event)!
        }

        func swipe(_ direction: Int32) -> (tracking: Int, settling: Int, settled: Bool) {
            eventClock += 1
            frame { sidebar.scrollWheel(with: scroll(0, phase: 128)) }
            eventClock += 0.008
            frame { sidebar.scrollWheel(with: scroll(4 * direction, phase: 1)) }
            for _ in 0..<30 {
                eventClock += 1.0 / 120
                frame { sidebar.scrollWheel(with: scroll(12 * direction, phase: 2)) }
            }
            let tracking = builtRows()
            eventClock += 1.0 / 120
            frame { sidebar.scrollWheel(with: scroll(0, phase: 4)) }
            let settled = settle()
            return (tracking, builtRows(), settled)
        }

        var activeIndex: Int { state.spaces.firstIndex { $0.id == state.activeSpaceID }! }
    }

    private static let directions: [Int32] = [-1, -1, -1, 1, 1, 1]

    @Test func neighbouringPagesFinishPreparingBeforeASwipe() {
        let s = Stage()
        s.prepareNeighbours()
        #expect(!s.sidebar.isPreparingNeighborPages)
    }

    @Test func swipingAcrossEverySpaceAndBackBuildsNoRows() {
        let s = Stage()
        s.prepareNeighbours(); _ = s.builtRows()
        var visited: [Int] = []
        for direction in Self.directions {
            let swipe = s.swipe(direction)
            #expect(swipe.tracking == 0 && swipe.settling == 0)
            visited.append(s.activeIndex)
            s.prepareNeighbours(); _ = s.builtRows()
        }
        #expect(visited == [1, 2, 3, 2, 1, 0])
    }

    @Test func everySwipedPageSpringsBackToRest() {
        let s = Stage()
        s.prepareNeighbours()
        for direction in Self.directions {
            #expect(s.swipe(direction).settled)
            s.prepareNeighbours()
        }
    }

    @Test(arguments: [3, 0])
    func aJumpToAKeptSpaceBuildsNoRowsAndItsSlideComesToRest(target: Int) {
        let s = Stage()
        s.prepareNeighbours()
        if target == 0 {
            let last = s.state.spaces[3]
            s.frame { s.sidebar.onSelectSpace?(last.id, last.profileID) }
            _ = s.settle(); s.prepareNeighbours()
        }
        _ = s.builtRows()
        let space = s.state.spaces[target]
        s.frame { s.sidebar.onSelectSpace?(space.id, space.profileID) }
        #expect(s.builtRows() == 0)
        #expect(s.settle())
    }

    private func shownScroll(_ sidebar: NSView) -> NSScrollView? {
        var found: NSScrollView?
        func walk(_ view: NSView) {
            if let strip = view as? SidebarPageStripView, !strip.passesThrough,
               let scroll = strip.subviews.compactMap({ $0 as? NSScrollView }).first { found = scroll }
            view.subviews.forEach(walk)
        }
        walk(sidebar)
        return found
    }

    private func folderRows(in scroll: NSScrollView) -> [SidebarFolderRow] {
        var rows: [SidebarFolderRow] = []
        func walk(_ view: NSView) { if let row = view as? SidebarFolderRow { rows.append(row) }; view.subviews.forEach(walk) }
        scroll.documentView.map(walk)
        let visible = scroll.contentView.bounds
        return rows.filter { visible.intersects(scroll.contentView.convert($0.bounds, from: $0)) }
            .sorted { scroll.contentView.convert($0.bounds, from: $0).minY < scroll.contentView.convert($1.bounds, from: $1).minY }
    }

    @Test func aDragHeldOverACollapsedFolderSpringsItOpenAfterTheSpringLoadingDelay() throws {
        let s = Stage()
        s.prepareNeighbours()
        let scroll = try #require(shownScroll(s.sidebar))
        let first = try #require(folderRows(in: scroll).first)
        let folderID = first.folderID
        s.sidebar.onToggleFolder?(folderID)
        s.sidebar.layoutSubtreeIfNeeded()
        #expect(s.state.folders.first { $0.id == folderID }?.isExpanded == false)
        let tab = try #require(s.state.tabs.first { $0.spaceID == s.state.activeSpaceID && $0.kind == .today })
        let session = try #require(s.sidebar.prepareSidebarMove?(.tab(tab.id)))
        let source = DragSource(); source.sidebarDrag = session
        let drag = Drag(source: source, session: session, window: s.window)
        let collapsed = try #require(folderRows(in: scroll).first { $0.folderID == folderID })
        drag.location = s.sidebar.convert(s.sidebar.convert(NSPoint(x: collapsed.bounds.midX, y: collapsed.bounds.midY), from: collapsed), to: nil)
        let before = s.scheduled.count, toggles = s.toggled
        _ = s.sidebar.draggingEntered(drag); _ = s.sidebar.draggingUpdated(drag)
        let delay = (UserDefaults.standard.object(forKey: "com.apple.springing.delay") as? NSNumber)?.doubleValue ?? 0.5
        let springing = s.scheduled[before...].filter { $0.mode == .common && $0.timer.isValid && $0.interval == delay }
        try #require(springing.count == 1)
        #expect(s.toggled == toggles)
        springing[0].timer.invalidate(); springing[0].body()
        #expect(s.toggled == toggles + 1)
        #expect(s.state.folders.first { $0.id == folderID }?.isExpanded == true)
        s.sidebar.draggingExited(drag)
    }
}
