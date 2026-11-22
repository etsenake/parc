import AppKit
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarOptionDropTests {
    private final class Source: NSView, SidebarItemDragSource {
        var sidebarDrag: SidebarMoveSession?
    }

    private final class Drag: NSObject, NSDraggingInfo {
        var draggingDestinationWindow: NSWindow?
        var draggingSourceOperationMask: NSDragOperation = [.move, .copy]
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

        deinit { draggingPasteboard.releaseGlobally() }

        func slideDraggedImage(to screenPoint: NSPoint) {}
        nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
        func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass],
                                    searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
        func resetSpringLoading() {}
    }

    @MainActor private final class Fixture {
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let source = Source()
        let drag = Drag()
        let host: NSWindow
        var option = false
        var moves = 0
        var copies = 0

        init(copyable: Bool) throws {
            _ = NSApplication.shared
            host = sidebarTestWindow(containing: sidebar)
            var state = BrowserState.initial()
            let space = try #require(state.spaces.first)
            let pinned = BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID,
                                    url: "https://pinned.invalid", title: "Pinned", kind: .pinned,
                                    createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                                    savedURL: "https://pinned.invalid", savedTitle: "Pinned")
            state.tabs = [pinned]
            sidebar.render(state: state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
            sidebar.layoutSubtreeIfNeeded()
            sidebar.dragModifierFlags = { [weak self] in self?.option == true ? [.option] : [] }
            let newTab = try #require(sidebarDescendants(sidebar).compactMap { $0 as? SidebarNewTabRow }.first)
            let frame = newTab.convert(newTab.bounds, to: sidebar)
            drag.draggingLocation = sidebar.convert(NSPoint(x: frame.midX, y: frame.midY - 6), to: nil)
            drag.draggingDestinationWindow = host
            drag.draggingSourceOperationMask = copyable ? [.move, .copy] : .move
            drag.draggingSource = source
            sidebar.addSubview(source)
            let session = SidebarMoveSession(items: [.tab(pinned.id)], window: host, validate: { true },
                allowsCopy: copyable, propose: { _, _ in true }, commit: { [weak self] _, _ in
                    self?.moves += 1
                    return true
                })
            source.sidebarDrag = session
            drag.draggingPasteboard.clearContents()
            drag.draggingPasteboard.setString(session.identifier.uuidString, forType: SidebarMoveSession.pasteboardType)
            sidebar.prepareCopyDrop = { [weak self] _, _, _, _ in
                { self?.copies += 1; return true }
            }
        }

        deinit { MainActor.assumeIsolated { host.close() } }
    }

    @Test func pressingAndReleasingOptionUpdatesTheProposedOperation() throws {
        let fixture = try Fixture(copyable: true)
        #expect(fixture.sidebar.draggingEntered(fixture.drag) == .move)
        fixture.option = true
        #expect(fixture.sidebar.draggingUpdated(fixture.drag) == .copy)
        fixture.option = false
        #expect(fixture.sidebar.draggingUpdated(fixture.drag) == .move)
    }

    @Test func droppingWithOptionCommitsTheCopy() throws {
        let fixture = try Fixture(copyable: true)
        fixture.option = true

        #expect(fixture.sidebar.performDragOperation(fixture.drag))
        #expect(fixture.copies == 1)
        #expect(fixture.moves == 0)
    }

    @Test(arguments: [false, true])
    func optionNeverFallsBackToMovingWhenTheCopyIsRefused(copyable: Bool) throws {
        let fixture = try Fixture(copyable: copyable)
        fixture.option = true
        if copyable { fixture.sidebar.prepareCopyDrop = { _, _, _, _ in nil } }

        #expect(fixture.sidebar.draggingUpdated(fixture.drag).isEmpty)
        #expect(!fixture.sidebar.performDragOperation(fixture.drag))
        #expect(fixture.moves == 0)
        #expect(fixture.source.sidebarDrag?.ended == false)
    }
}
