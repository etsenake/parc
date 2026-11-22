import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SidebarMoveCopyTests {
    @MainActor private final class Drag {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
        let location = SidebarContainerLocation(spaceID: UUID(), folderID: nil, section: .pinned)
        var valid = true
        var moves = 0
        var copies = 0

        init() { window.isReleasedWhenClosed = false }

        func session(copy: Bool, items: [SidebarItemReference] = [.split(UUID())]) -> SidebarMoveSession {
            SidebarMoveSession(items: items, window: window, validate: { [self] in valid }, allowsCopy: copy,
                               propose: { _, _ in true }, commit: { [self] _, _ in moves += 1; return true })
        }

        func copy(_ session: SidebarMoveSession, succeeding: Bool = true) -> Bool {
            session.copy { [self] in copies += 1; return succeeding }
        }
    }

    @Test func aMoveOnlySessionNeverRunsACopy() {
        let drag = Drag()
        let session = drag.session(copy: false)
        #expect(!session.allowsCopy)
        #expect(!drag.copy(session))
        #expect(drag.copies == 0)
    }

    @Test func aMoveOnlySessionStaysLiveAfterARefusedCopy() {
        let drag = Drag()
        let session = drag.session(copy: false)
        _ = drag.copy(session)
        #expect(!session.ended)
    }

    @Test func aMoveOnlySessionStillCommitsItsMoveOnce() {
        let drag = Drag()
        let session = drag.session(copy: false)
        #expect(session.move(to: drag.location, before: nil))
        #expect(drag.moves == 1)
        #expect(session.ended)
    }

    @Test func anInvalidSourceRefusesTheCopy() {
        let drag = Drag()
        let session = drag.session(copy: true)
        drag.valid = false
        #expect(!drag.copy(session))
        #expect(drag.copies == 0)
        #expect(!session.ended)
    }

    @Test func aValidCopyRunsOnceAndEndsTheDrag() {
        let drag = Drag()
        let session = drag.session(copy: true)
        #expect(drag.copy(session))
        #expect(drag.copies == 1)
        #expect(session.ended)
    }

    @Test func anEndedSessionCannotCopyAgain() {
        let drag = Drag()
        let session = drag.session(copy: true)
        _ = drag.copy(session)
        #expect(!drag.copy(session))
        #expect(drag.copies == 1)
    }

    @Test func anEndedSessionCannotMove() {
        let drag = Drag()
        let session = drag.session(copy: true)
        _ = drag.copy(session)
        #expect(!session.move(to: drag.location, before: nil))
        #expect(drag.moves == 0)
    }

    @Test func aRefusedCommitStillEndsTheOneShotSession() {
        let drag = Drag()
        let session = drag.session(copy: true)
        #expect(!drag.copy(session, succeeding: false))
        #expect(session.ended)
    }

    @Test(arguments: [
        [SidebarItemReference.tab(UUID())],
        [SidebarItemReference.folder(UUID())],
        [SidebarItemReference.tab(UUID()), .folder(UUID()), .split(UUID())],
    ])
    func aCopyableSessionCopiesOnceWithoutMoving(items: [SidebarItemReference]) {
        let drag = Drag()
        let session = drag.session(copy: true, items: items)
        #expect(drag.copy(session))
        #expect(drag.copies == 1)
        #expect(drag.moves == 0)
        #expect(session.ended)
    }

    @Test func aMoveHandleCapturesItsPreviewUnlessARendererIsSupplied() {
        let drag = Drag()
        let handle = SidebarMoveHandle(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        drag.window.contentView?.addSubview(handle)
        #expect(handle.makeDragImage == nil)
    }

    @Test func aSuppliedRendererProvidesTheDragImage() {
        let drag = Drag()
        let handle = SidebarMoveHandle(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        drag.window.contentView?.addSubview(handle)
        var rendered = 0
        handle.makeDragImage = { rendered += 1; return NSImage(size: NSSize(width: 120, height: 36)) }
        #expect(handle.makeDragImage?()?.size == NSSize(width: 120, height: 36))
        #expect(rendered == 1)
    }
}
