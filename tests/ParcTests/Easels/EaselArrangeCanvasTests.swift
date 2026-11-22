import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct EaselArrangeCanvasTests {
    private func box(_ x: Double, z: Int, locked: Bool = false, group: UUID? = nil) -> EaselItem {
        var item = EaselItem(kind: .rectangle, frame: EaselRect(x: x, y: 0, width: 100, height: 100), zIndex: z)
        item.locked = locked ? true : nil
        item.groupID = group
        return item
    }

    @MainActor private func canvas(_ items: [EaselItem]) throws -> (EaselCanvasView, EaselSession) {
        let document = EaselDocument(id: UUID(), title: "Board", createdAt: Date(timeIntervalSince1970: 0),
                                     modifiedAt: Date(timeIntervalSince1970: 0), items: items)
        let session = try EaselSession(inMemory: document, assets: [:])
        return (makeTestEaselCanvas(session: session), session)
    }

    @MainActor @Test
    func selectAllSkipsLockedObjects() throws {
        let a = box(0, z: 1), b = box(200, z: 2), locked = box(400, z: 3, locked: true)
        let (view, _) = try canvas([a, b, locked])
        view.selectAll(nil)
        #expect(view.selection == [a.id, b.id], "Select All leaves locked objects alone")
    }

    @MainActor @Test
    func commandGFirstGoesToTheFindBar() throws {
        let a = box(0, z: 1), b = box(200, z: 2)
        let (view, session) = try canvas([a, b])
        view.selection = [a.id, b.id]
        let commandG = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                              windowNumber: 0, context: nil, characters: "g", charactersIgnoringModifiers: "g",
                                              isARepeat: false, keyCode: 5))
        var findSaw = false
        view.onKeyEquivalent = { _ in findSaw = true; return true }
        #expect(view.performKeyEquivalent(with: commandG) && findSaw, "An open find bar gets ⌘G first")
        #expect(session.document.items.allSatisfy { $0.groupID == nil }, "⌘G for find never groups")
    }

    @MainActor @Test
    func unfocusedCommandGFallsThrough() throws {
        let a = box(0, z: 1), b = box(200, z: 2)
        let (view, session) = try canvas([a, b])
        view.selection = [a.id, b.id]
        let commandG = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                              windowNumber: 0, context: nil, characters: "g", charactersIgnoringModifiers: "g",
                                              isARepeat: false, keyCode: 5))
        #expect(!view.performKeyEquivalent(with: commandG), "Without Easel focus ⌘G falls through to Parc")
        #expect(session.document.items.allSatisfy { $0.groupID == nil }, "Falling through leaves the board alone")
    }

    @MainActor @Test
    func staleSelectionDoesNotClaimEditChords() throws {
        let a = box(0, z: 1), b = box(200, z: 2)
        let (view, session) = try canvas([a, b])
        view.selection = [a.id, b.id]
        view.selection = [UUID()]
        #expect(!view.performChord(.duplicate) && !view.performChord(.toggleLock), "A stale selection lets ⌘D and ⇧⌘L reach Parc")
        #expect(session.document.items.count == 2, "Nothing was duplicated from a stale selection")
    }

    @MainActor @Test
    func aSingleObjectDoesNotClaimTheGroupChord() throws {
        let a = box(0, z: 1), b = box(200, z: 2)
        let (view, _) = try canvas([a, b])
        view.selection = [a.id, b.id]
        view.selection = [a.id]
        #expect(!view.performChord(.group), "One object can't group, so ⌘G stays Find Next")
    }

    @MainActor @Test
    func theGroupChordGroupsTwoSelectedObjects() throws {
        let a = box(0, z: 1), b = box(200, z: 2)
        let (view, session) = try canvas([a, b])
        view.selection = [a.id, b.id]
        #expect(view.performChord(.group), "Two objects claim ⌘G")
        #expect(Set(session.document.items.compactMap(\.groupID)).count == 1, "⌘G grouped the pair")
    }

    @MainActor @Test
    func theDuplicateChordCopiesSelectedObjects() throws {
        let a = box(0, z: 1), b = box(200, z: 2)
        let (view, session) = try canvas([a, b])
        view.selection = [a.id, b.id]
        #expect(view.performChord(.duplicate) && session.document.items.count == 4, "⌘D duplicates the selection")
    }

    @MainActor @Test
    func optionDragMakesOneUndoableCopyAndMove() throws {
        let a = box(0, z: 1), b = box(200, z: 2)
        let (view, session) = try canvas([a, b])
        view.selection = [a.id]
        let before = session.document.items
        #expect(view.beginDuplicateDrag(), "Option-drag makes a copy to drag")
        let copies = view.selection
        #expect(session.document.items.count == 3 && !copies.contains(a.id), "The copy is selected and the original stays")
        let group = view.finishDuplicateDrag()
        #expect(group != nil, "Finishing the drag hands back its undo group")
        view.commit("Move objects", coalescing: group) { document in
            for index in document.items.indices where copies.contains(document.items[index].id) { document.items[index].frame.x += 50 }
        }
        #expect(session.document.items.contains { copies.contains($0.id) && $0.frame.x == 50 }, "The copy lands where it was dropped")
        try session.undo()
        #expect(session.document.items == before && !session.canUndo, "One Undo takes back both the copy and its move")
    }

    @MainActor @Test
    func cancelingOptionDragRestoresTheOriginalSelection() throws {
        let a = box(0, z: 1), b = box(200, z: 2)
        let (view, session) = try canvas([a, b])
        view.selection = [a.id]
        let before = session.document.items
        #expect(view.beginDuplicateDrag(), "A second Option-drag starts")
        view.abandonDuplicateDrag()
        #expect(session.document.items == before, "Cancelling an Option-drag removes the copy")
        #expect(view.selection == [a.id], "Cancelling puts the selection back on the original")
        #expect(!view.performChord(.duplicate) || session.document.items.count == 3, "⌘D after a cancel acts on a real object")
    }

    @MainActor @Test
    func aClickSelectsTheUnlockedGroupMembers() throws {
        let group = UUID()
        let a = box(0, z: 1, group: group), b = box(200, z: 2, group: group), locked = box(400, z: 3, locked: true, group: group)
        let (view, _) = try canvas([a, b, locked])
        #expect(!view.selectForClick(a, extending: false, clickCount: 1), "A single click doesn't enter a group")
        #expect(view.selection == [a.id, b.id], "Clicking a member selects its unlocked group-mates")
    }

    @MainActor @Test
    func aDoubleClickEntersTheGroupForIndividualSelection() throws {
        let group = UUID()
        let a = box(0, z: 1, group: group), b = box(200, z: 2, group: group), locked = box(400, z: 3, locked: true, group: group)
        let (view, _) = try canvas([a, b, locked])
        #expect(view.selectForClick(b, extending: false, clickCount: 2) && view.selection == [b.id], "Double-click enters the group")
        #expect(!view.selectForClick(a, extending: false, clickCount: 1) && view.selection == [a.id], "Inside a group clicks pick members")
    }

    @MainActor @Test
    func selectingAnObjectOutsideLeavesTheEnteredGroup() throws {
        let group = UUID()
        let a = box(0, z: 1, group: group), b = box(200, z: 2, group: group), locked = box(400, z: 3, locked: true, group: group)
        let loose = box(600, z: 4)
        let (view, _) = try canvas([a, b, locked, loose])
        _ = view.selectForClick(b, extending: false, clickCount: 2)
        _ = view.selectForClick(loose, extending: false, clickCount: 1)
        #expect(view.selection == [loose.id] && view.arrangeState.enteredGroup == nil, "Clicking outside leaves the group")
    }

    @MainActor @Test
    func shiftClickCanSelectALockedMemberForUnlocking() throws {
        let group = UUID()
        let a = box(0, z: 1, group: group), b = box(200, z: 2, group: group), locked = box(400, z: 3, locked: true, group: group)
        let loose = box(600, z: 4)
        let (view, _) = try canvas([a, b, locked, loose])
        view.selection = [loose.id]
        _ = view.selectForClick(locked, extending: true, clickCount: 1)
        #expect(view.selection == [loose.id, a.id, b.id, locked.id], "Shift-click on a locked member still picks it for unlocking")
    }

    @MainActor @Test
    func marqueeSelectsUnlockedGroupMembers() throws {
        let group = UUID()
        let a = box(0, z: 1, group: group), b = box(200, z: 2, group: group), locked = box(400, z: 3, locked: true, group: group)
        let (view, _) = try canvas([a, b, locked])
        let marquee = view.marqueeSelection(in: EaselRect(x: -10, y: -10, width: 50, height: 50), items: view.session.document.items,
                                            original: [], operation: .replace)
        #expect(marquee == [a.id, b.id], "A marquee widens to the group but skips its locked member")
    }

}
