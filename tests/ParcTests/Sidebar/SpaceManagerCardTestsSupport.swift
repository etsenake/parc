import AppKit
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcLibrary
@testable import ParcSidebar

@MainActor
enum SpaceManagerCardTestsSupport {
    final class CardDrop: NSObject, NSDraggingInfo {
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

    final class DragSource: NSView, SidebarItemDragSource {
        var sidebarDrag: SidebarMoveSession?
    }

    typealias Layout = SpaceManagementLayout

    @MainActor final class Cards {
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
}
