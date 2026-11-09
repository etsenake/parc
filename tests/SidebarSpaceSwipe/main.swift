import AppKit
import ObjectiveC
import QuartzCore

/// Tab and folder rows constructed, counted at NSView's initializer.
@MainActor enum BuiltRows { static var count = 0 }
extension NSView {
    @objc func swipeCountingInit(frame: NSRect) -> NSView {
        if self is SidebarTabRow || self is SidebarFolderRow { MainActor.assumeIsolated { BuiltRows.count += 1 } }
        return swipeCountingInit(frame: frame)
    }
}

/// The source of an in-memory sidebar drag: it holds the drag's move session,
/// as a row does.
@MainActor final class SwipeDragSource: NSView, SidebarItemDragSource { var sidebarDrag: SidebarMoveSession? }

/// A drag over the sidebar built in memory: the session's pasteboard
/// identity and a location the check moves; nothing is posted.
@MainActor final class SwipeDrag: NSObject, @preconcurrency NSDraggingInfo {
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("org.parc.swipe-check.\(UUID().uuidString)"))
    private let source: SwipeDragSource
    private weak var window: NSWindow?
    var location = NSPoint.zero
    init(source: SwipeDragSource, session: SidebarMoveSession, window: NSWindow) {
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

/// A Space swipe's main-thread work on the production SidebarView, with 5, 50
/// and 200 folders and items in each of three Spaces. Phased scroll events
/// built in memory go straight to the sidebar, which selects Spaces the way
/// BrowserWindowController does: it renders the new Space synchronously. The
/// window is off screen and never shown; no browser, engine or posted events.
@main @MainActor struct SidebarSpaceSwipe {
    static func scroll(_ dx: Int32, phase: Int64, at time: CFTimeInterval) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: dx, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.timestamp = UInt64(time * 1_000_000_000)
        return NSEvent(cgEvent: event)!
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

    struct Swipe { var firstFrame = 0.0, frames: [Double] = [], release = 0.0, settle: [Double] = [], settled = true, built = 0, builtInFrames = 0, builtIdle = 0, idleTurn = 0.0 }

    /// Main-thread busy spans between run loop waits, for the spring's frames.
    final class Busy {
        var spans: [Double] = []
        private var start: CFTimeInterval?
        private var observer: CFRunLoopObserver?
        func install() {
            observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue,
                                                          true, 0) { [unowned self] _, activity in
                let now = CACurrentMediaTime()
                if activity == .afterWaiting { self.start = now } else if let start = self.start {
                    self.spans.append(now - start); self.start = nil
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
        func remove() { if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) } }
    }

    /// Delivers waiting events, as the application's event loop does.
    static func deliverEvents() {
        while let event = NSApp.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
    }

    /// Runs the main loop until it has been quiet for 0.4 s (no turn over
    /// 2 ms), as a user pauses between swipes; at most 30 s.
    @discardableResult static func idle() -> Double {
        let busy = Busy(); busy.install()
        let end = Date().addingTimeInterval(30)
        var quietSince = Date()
        while Date() < end, Date().timeIntervalSince(quietSince) < 0.4 {
            let before = busy.spans.count, began = Date()
            deliverEvents()
            RunLoop.main.run(until: began.addingTimeInterval(0.05))
            // A turn that overran the slice ended it before it reported.
            if Date().timeIntervalSince(began) > 0.06 || busy.spans[before...].contains(where: { $0 > 0.002 }) { quietSince = Date() }
        }
        busy.remove()
        return (busy.spans.max() ?? 0) * 1000
    }

    /// The process's physical footprint in MB.
    static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static func main() {
        _ = NSApplication.shared
        method_exchangeImplementations(class_getInstanceMethod(NSView.self, #selector(NSView.init(frame:)))!,
                                       class_getInstanceMethod(NSView.self, #selector(NSView.swipeCountingInit(frame:)))!)
        var report: [String] = []
        let sizes = CommandLine.arguments.dropFirst().compactMap { Int($0) }
        for items in sizes.isEmpty ? [5, 50, 200] : sizes {
            let spaceCount = ProcessInfo.processInfo.environment["SWIPE_SPACES"].flatMap(Int.init) ?? 3
            var state = state(items: items, spaces: spaceCount)
            let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 260, height: 900))
            let window = NSWindow(contentRect: sidebar.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = sidebar
            if ProcessInfo.processInfo.environment["SWIPE_NO_ENGINE"] == nil {
                // The browser window lays its content out with constraints
                // (ParcSplitView.constrain), so it has a layout engine.
                let content = NSView(frame: sidebar.frame)
                window.contentView = content; content.addSubview(sidebar)
                let pane = NSView()
                pane.translatesAutoresizingMaskIntoConstraints = false
                content.addSubview(pane)
                NSLayoutConstraint.activate([pane.leadingAnchor.constraint(equalTo: content.trailingAnchor),
                                             pane.topAnchor.constraint(equalTo: content.topAnchor),
                                             pane.widthAnchor.constraint(equalToConstant: 0), pane.heightAnchor.constraint(equalToConstant: 0)])
            }
            // BrowserWindowController's move lease: the hierarchy it expects,
            // revalidated on every check, and the real move proposal.
            if ProcessInfo.processInfo.environment["SWIPE_NO_LEASES"] == nil { sidebar.prepareSidebarMove = { item in
                let space = state.spaces.first { $0.id == state.activeSpaceID }!
                guard var expected = SidebarHierarchySnapshot(state: state, spaceID: space.id, profileID: space.profileID, includesFavorites: true),
                      SidebarMoveCollection(items: [item], spaceID: space.id, profileID: space.profileID, state: state) != nil else { return nil }
                func undisclosed(_ state: BrowserState) -> SidebarHierarchySnapshot? {
                    var state = state
                    for index in state.folders.indices { state.folders[index].isExpanded = false }
                    return SidebarHierarchySnapshot(state: state, spaceID: expected.spaceID, profileID: expected.profileID, includesFavorites: true)
                }
                let structure = undisclosed(state)
                let valid: () -> Bool = {
                    guard state.activeSpaceID == expected.spaceID, let current = SidebarHierarchySnapshot(
                        state: state, spaceID: expected.spaceID, profileID: expected.profileID, includesFavorites: true) else { return false }
                    if current != expected {
                        guard structure != nil, undisclosed(state) == structure else { return false }
                        expected = current
                    }
                    return true
                }
                return SidebarMoveSession(items: [item], window: window, validate: valid, propose: { location, before in
                    valid() && SidebarHierarchy.moving([item], to: location, before: before, expected: expected, state: state) != nil
                }, commit: { _, _ in false })
            } }
            sidebar.prepareSidebarSpaceMove = { _, id in id == state.activeSpaceID ? nil : { false } }
            sidebar.canSelectSpace = { _, _ in true }
            sidebar.onSelectSpace = { id, _ in
                state.activeSpaceID = id
                sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
            }
            let initial = CACurrentMediaTime()
            sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
            sidebar.layoutSubtreeIfNeeded()
            let renderMs = (CACurrentMediaTime() - initial) * 1000
            if let rounds = ProcessInfo.processInfo.environment["SWIPE_PROFILE_RENDERS"].flatMap(Int.init) {
                // Space switches between kept pages only, for a profiler.
                let began = CACurrentMediaTime()
                for round in 0..<rounds {
                    state.activeSpaceID = state.spaces[round % 2 == 0 ? 1 : 0].id
                    autoreleasepool { sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false) }
                }
                print("\(items): \(rounds) kept-page renders, \(String(format: "%.1f", (CACurrentMediaTime() - began) * 1000 / Double(rounds))) ms each")
                if let hold = ProcessInfo.processInfo.environment["SWIPE_HOLD"].flatMap(Double.init) { Thread.sleep(forTimeInterval: hold) }
                continue
            }
            var counted = BuiltRows.count
            func newRows() -> Int { defer { counted = BuiltRows.count }; return BuiltRows.count - counted }
            // The idle preparation of the other Spaces' pages.
            let preparingTurn = idle()
            let prepared = newRows()
            if ProcessInfo.processInfo.environment["SWIPE_VERBOSE"] != nil { print("  idle before swiping built \(prepared)") }
            func frame(_ body: () -> Void) -> Double {
                let began = CACurrentMediaTime()
                autoreleasepool { body(); sidebar.layoutSubtreeIfNeeded(); window.displayIfNeeded(); CATransaction.flush() }
                return (CACurrentMediaTime() - began) * 1000
            }
            var swipes: [Swipe] = []
            var clock = CACurrentMediaTime()
            // Through every Space and back, one Space a swipe: each first
            // visit and each return.
            for direction: Int32 in Array(repeating: -1, count: spaceCount - 1) + Array(repeating: 1, count: spaceCount - 1) {
                var swipe = Swipe()
                _ = frame { sidebar.scrollWheel(with: scroll(0, phase: 128, at: clock)) }
                clock += 0.008
                _ = frame { sidebar.scrollWheel(with: scroll(4 * direction, phase: 1, at: clock)) }
                for index in 0..<30 {
                    clock += 1.0 / 120
                    let ms = frame { sidebar.scrollWheel(with: scroll(12 * direction, phase: 2, at: clock)) }
                    if index == 0 { swipe.firstFrame = ms } else { swipe.frames.append(ms) }
                }
                swipe.builtInFrames = newRows()
                clock += 1.0 / 120
                swipe.release = frame { sidebar.scrollWheel(with: scroll(0, phase: 4, at: clock)) }
                // The spring's frames, until the page strip is back at rest.
                func moving(_ view: NSView) -> Bool {
                    !CATransform3DIsIdentity(view.layer?.sublayerTransform ?? CATransform3DIdentity) || view.subviews.contains(where: moving)
                }
                let busy = Busy(); busy.install()
                let deadline = Date().addingTimeInterval(1.5)
                while moving(sidebar), Date() < deadline { deliverEvents(); RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 240)) }
                busy.remove()
                swipe.settled = !moving(sidebar)
                swipe.settle = busy.spans.map { $0 * 1000 }
                swipe.built = swipe.builtInFrames + newRows()
                if ProcessInfo.processInfo.environment["SWIPE_VERBOSE"] != nil {
                    print("  swipe \(swipes.count + 1): first \(swipe.firstFrame) release \(swipe.release) settle max \(swipe.settle.max() ?? 0) built tracking \(swipe.builtInFrames) swipe \(swipe.built)")
                }
                swipes.append(swipe)
                swipe.idleTurn = idle()
                swipe.builtIdle = newRows()
                swipes[swipes.count - 1] = swipe
                clock = CACurrentMediaTime()
            }
            // A click on the farthest Space's icon and back, as the dock or a
            // shortcut switches: the kept page shows, or one let go rebuilds.
            // SWIPE_PRESSURE: macOS reports memory pressure first, so the jump
            // finds the pages the sidebar let go and rebuilds one.
            if ProcessInfo.processInfo.environment["SWIPE_PRESSURE"] != nil { sidebar.releaseOffscreenPages(); idle(); _ = newRows() }
            var jumps: [Double] = []
            var jumpBuilt = 0
            for target in spaceCount > 2 ? [spaceCount - 1, 0] : [] {
                let space = state.spaces[target]
                jumps.append(frame { sidebar.onSelectSpace?(space.id, space.profileID) })
                jumpBuilt += newRows()
                idle(); _ = newRows()
            }
            // The shown page's list: a brisk scroll to its end and back, a drag
            // resting at its bottom edge that auto-scrolls it, a collapsed
            // folder springing open under the drag (and closing as the drag
            // leaves), and folders expanding with the rows below sliding or
            // with their children landing out of view.
            var scrollFrames: [Double] = [], dragFrames: [Double] = [], springFrames: [Double] = [], disclosureFrames: [Double] = []
            func shownScroll() -> NSScrollView? {
                var found: NSScrollView?
                func walk(_ view: NSView) {
                    if let strip = view as? SidebarPageStripView, !strip.passesThrough,
                       let scroll = strip.subviews.compactMap({ $0 as? NSScrollView }).first { found = scroll }
                    view.subviews.forEach(walk)
                }
                walk(sidebar)
                return found
            }
            func folderRows(in scroll: NSScrollView) -> [SidebarFolderRow] {
                var rows: [SidebarFolderRow] = []
                func walk(_ view: NSView) { if let row = view as? SidebarFolderRow { rows.append(row) }; view.subviews.forEach(walk) }
                scroll.documentView.map(walk)
                let visible = scroll.contentView.bounds
                return rows.filter { visible.intersects(scroll.contentView.convert($0.bounds, from: $0)) }
                    .sorted { scroll.contentView.convert($0.bounds, from: $0).minY < scroll.contentView.convert($1.bounds, from: $1).minY }
            }
            /// The main thread's turns for `seconds`, as an animation's frames.
            func spans(for seconds: TimeInterval) -> [Double] {
                let busy = Busy(); busy.install()
                let end = Date().addingTimeInterval(seconds)
                while Date() < end { deliverEvents(); RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 240)) }
                busy.remove()
                return busy.spans.map { $0 * 1000 }
            }
            var toggled: Double?
            sidebar.onToggleFolder = { id in
                guard let index = state.folders.firstIndex(where: { $0.id == id }) else { return }
                state.folders[index].isExpanded.toggle()
                toggled = frame { sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false) }
            }
            func toggle(_ id: UUID) -> [Double] {
                toggled = nil
                sidebar.onToggleFolder?(id)
                return [toggled ?? 0] + spans(for: 0.35)
            }
            if let scroll = shownScroll(), let height = scroll.documentView?.frame.height {
                let clip = scroll.contentView
                func scrollTo(_ y: CGFloat) {
                    clip.scroll(to: NSPoint(x: 0, y: min(max(0, y), max(0, height - clip.bounds.height))))
                    scroll.reflectScrolledClipView(clip)
                }
                scrollTo(0); idle()
                var y: CGFloat = 0
                while y < height - clip.bounds.height { y += 60; scrollFrames.append(frame { scrollTo(y) }) }
                while y > 0 { y -= 60; scrollFrames.append(frame { scrollTo(y) }) }
                idle()
                let tab = state.tabs.first { $0.spaceID == state.activeSpaceID && $0.kind == .today }
                if let tab, let session = sidebar.prepareSidebarMove?(.tab(tab.id)) {
                    let source = SwipeDragSource(); source.sidebarDrag = session
                    let drag = SwipeDrag(source: source, session: session, window: window)
                    let edge = sidebar.convert(scroll.bounds, from: scroll)
                    drag.location = sidebar.convert(NSPoint(x: edge.midX, y: edge.maxY - 10), to: nil)
                    _ = sidebar.draggingEntered(drag)
                    for _ in 0..<150 { dragFrames.append(frame { _ = sidebar.draggingUpdated(drag) }) }
                    sidebar.draggingExited(drag)
                    scrollTo(0); idle()
                    if let first = folderRows(in: scroll).first {
                        disclosureFrames += toggle(first.folderID)
                        idle()
                        if let collapsed = folderRows(in: scroll).first(where: { $0.folderID == first.folderID }) {
                            let middle = sidebar.convert(NSPoint(x: collapsed.bounds.midX, y: collapsed.bounds.midY), from: collapsed)
                            drag.location = sidebar.convert(middle, to: nil)
                            toggled = nil
                            let busy = Busy(); busy.install()
                            _ = sidebar.draggingEntered(drag)
                            let end = Date().addingTimeInterval(1.5)
                            while toggled == nil, Date() < end { _ = sidebar.draggingUpdated(drag); RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 60)) }
                            busy.remove()
                            springFrames = [toggled ?? .infinity] + spans(for: 0.35)
                            sidebar.draggingExited(drag)
                            springFrames += [toggled ?? 0] + spans(for: 0.35)
                        }
                        idle()
                        // The top folder expands: every row below it slides.
                        if folderRows(in: scroll).first?.folderID == first.folderID,
                           state.folders.first(where: { $0.id == first.folderID })?.isExpanded == false {
                            disclosureFrames += toggle(first.folderID)
                            idle()
                        }
                    }
                    // The lowest folder in view collapses, then expands with its
                    // child out of view.
                    if let last = folderRows(in: scroll).last {
                        disclosureFrames += toggle(last.folderID); idle()
                        disclosureFrames += toggle(last.folderID); idle()
                    }
                }
            }
            func fmt(_ value: Double) -> String { String(format: "%.1f", value) }
            if ProcessInfo.processInfo.environment["SWIPE_VERBOSE"] != nil {
                for (name, frames) in [("scroll", scrollFrames), ("drag auto-scroll", dragFrames), ("spring-open", springFrames),
                                       ("expand/collapse", disclosureFrames)] where !frames.isEmpty {
                    let sorted = frames.sorted()
                    print("  \(name): \(frames.count) frames, median \(fmt(sorted[sorted.count / 2])) ms, 95th \(fmt(sorted[sorted.count * 95 / 100])) ms, max \(fmt(sorted.last!)) ms")
                }
            }
            let first = swipes.map(\.firstFrame).max() ?? 0
            let steady = swipes.flatMap(\.frames)
            let release = swipes.map(\.release).max() ?? 0
            let settle = swipes.flatMap(\.settle).max() ?? 0
            let builtInFrames = swipes.map(\.builtInFrames).max() ?? 0
            let built = swipes.map(\.built).max() ?? 0
            let builtIdle = swipes.map(\.builtIdle).max() ?? 0
            let idleTurn = max(preparingTurn, swipes.map(\.idleTurn).max() ?? 0)
            let jump = jumps.max() ?? 0
            let memory = footprint()
            let line = "\(items) folders+\(items * 2) items/Space: render \(fmt(renderMs)) ms; swipe first frame \(fmt(first)) ms, "
                + "other frames max \(fmt(steady.max() ?? 0)) ms, release \(fmt(release)) ms, settle frame max \(fmt(settle)) ms; "
                + "far jump \(fmt(jump)) ms; rows built while tracking \(builtInFrames), during the swipe \(built), idle after \(builtIdle) "
                + "(longest idle turn \(fmt(idleTurn)) ms); scroll frame max \(fmt(scrollFrames.max() ?? 0)) ms, "
                + "drag auto-scroll frame max \(fmt(dragFrames.max() ?? 0)) ms, spring-open frame max \(fmt(springFrames.max() ?? 0)) ms, "
                + "expand/collapse frame max \(fmt(disclosureFrames.max() ?? 0)) ms; footprint \(fmt(memory)) MB"
            print(line); report.append(line)
            if ProcessInfo.processInfo.environment["SWIPE_ASSERT"] != nil {
                // Prepared while idle, no swipe builds a row, first visits included.
                precondition(builtInFrames == 0 && built == 0, "\(items): a swipe built rows (\(builtInFrames) tracking, \(built) in all)")
                // Each Space keeps its page: a swipe only moves it, within a frame,
                // and its release and the spring don't lay a page out again.
                precondition(first < 16 && (steady.max() ?? 0) < 16, "\(items): a swipe frame took \(fmt(max(first, steady.max() ?? 0))) ms")
                precondition(settle < 8, "\(items): a spring frame took \(fmt(settle)) ms")
                precondition(release < 50, "\(items): a release took \(fmt(release)) ms")
                precondition(swipes.allSatisfy(\.settled), "\(items): a page didn't spring back to rest")
                precondition(jumpBuilt == 0, "\(items): a jump to a kept Space built \(jumpBuilt) rows")
                // Rows have views only near the visible area: no idle turn, AppKit's
                // layout passes included, and no frame of the list's own motion
                // grows with the list.
                precondition(idleTurn < 8, "\(items): an idle turn took \(fmt(idleTurn)) ms")
                precondition(jump < 50, "\(items): a far jump took \(fmt(jump)) ms")
                for (name, frames) in [("scroll", scrollFrames), ("drag auto-scroll", dragFrames)] {
                    precondition(!frames.isEmpty && frames.max()! < 8, "\(items): a \(name) frame took \(fmt(frames.max() ?? .infinity)) ms")
                }
                // A folder's expand or collapse still rebuilds its page's list.
                for (name, frames) in [("spring-open", springFrames), ("expand/collapse", disclosureFrames)] {
                    precondition(!frames.isEmpty && frames.max()! < 16, "\(items): a \(name) frame took \(fmt(frames.max() ?? .infinity)) ms")
                }
            }
            if let hold = ProcessInfo.processInfo.environment["SWIPE_HOLD"].flatMap(Double.init) {
                print("hold pid \(getpid())"); fflush(stdout); Thread.sleep(forTimeInterval: hold)
            }
            window.contentView = nil
        }
        if let path = ProcessInfo.processInfo.environment["SWIPE_REPORT"] {
            try? report.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
