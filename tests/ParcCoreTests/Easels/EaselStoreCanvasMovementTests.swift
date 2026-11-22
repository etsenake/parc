import Foundation
import Testing
@testable import ParcCore

struct EaselStoreCanvasMovementTests {
    @MainActor @Test
    func movingAGroupClampsItsBoundsWithoutChangingSpacing() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let a = EaselItem(kind: .text, frame: .init(x: 10, y: 20, width: 60, height: 50), zIndex: 2, text: "Original")
            let b = EaselItem(kind: .image, frame: .init(x: 100, y: 120, width: 80, height: 50), zIndex: 5, assetID: asset)
            let c = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 300, width: 50, height: 50))
            try session.perform("Add") { $0.items = [a, b, c] }
            let ids: Set<UUID> = [a.id, b.id]
            let edit = EaselGeometryEdit(document: session.document, selection: ids)!
            let move = edit.translated(x: -40, y: -50)
            #expect(move[0].frame.x == 0 && move[1].frame.x == 90, "Group clamp preserves horizontal spacing")
            #expect(move[0].frame.y == 0 && move[1].frame.y == 100, "Group clamp preserves vertical spacing")
            #expect(move.map(\.id) == [a.id, b.id], "Movement retains original identity/order")
        }
    }

    @MainActor @Test
    func movingAGroupMergesCurrentContentAndRoundTrips() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let a = EaselItem(kind: .text, frame: .init(x: 10, y: 20, width: 60, height: 50), zIndex: 2, text: "Original")
            let b = EaselItem(kind: .image, frame: .init(x: 100, y: 120, width: 80, height: 50), zIndex: 5, assetID: asset)
            let c = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 300, width: 50, height: 50))
            try session.perform("Add") { $0.items = [a, b, c] }
            let ids: Set<UUID> = [a.id, b.id]
            let edit = EaselGeometryEdit(document: session.document, selection: ids)!
            let move = edit.translated(x: -40, y: -50)
            try session.perform("Other window") { $0.items[0].text = "Concurrent text"; $0.items[2].color = "#112233" }
            #expect(edit.isCurrent(in: session.document), "Content-only changes preserve geometry lease")
            try session.perform("Move originals") { $0 = edit.applying(move, to: $0)! }
            #expect(session.document.items[0].text == "Concurrent text" && session.document.items[2].color == "#112233", "Original geometry merge preserves latest content and unrelated object")
            #expect(!edit.isCurrent(in: session.document), "Committed move expires its baseline")
            let reopened = try EaselStore(directory: directory).load(session.document.id)
            #expect(reopened.document.items == session.document.items, "Group move persists actual original objects")
        }
    }

    @MainActor @Test
    func undoingAGroupMoveKeepsPriorContentChanges() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let a = EaselItem(kind: .text, frame: .init(x: 10, y: 20, width: 60, height: 50), zIndex: 2, text: "Original")
            let b = EaselItem(kind: .image, frame: .init(x: 100, y: 120, width: 80, height: 50), zIndex: 5, assetID: asset)
            let c = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 300, width: 50, height: 50))
            try session.perform("Add") { $0.items = [a, b, c] }
            let ids: Set<UUID> = [a.id, b.id]
            let edit = EaselGeometryEdit(document: session.document, selection: ids)!
            let move = edit.translated(x: -40, y: -50)
            try session.perform("Other window") { $0.items[0].text = "Concurrent text"; $0.items[2].color = "#112233" }
            try session.perform("Move originals") { $0 = edit.applying(move, to: $0)! }
            try session.undo()
            #expect(session.document.items[0].frame == a.frame && session.document.items[0].text == "Concurrent text", "One undo restores geometry without undoing other-window text")
        }
    }

    @MainActor @Test
    func movingAnOutdatedSelectionIsRefused() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let a = EaselItem(kind: .text, frame: .init(x: 10, y: 20, width: 60, height: 50), zIndex: 2, text: "Original")
            let b = EaselItem(kind: .image, frame: .init(x: 100, y: 120, width: 80, height: 50), zIndex: 5, assetID: asset)
            let c = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 300, width: 50, height: 50))
            try session.perform("Add") { $0.items = [a, b, c] }
            let ids: Set<UUID> = [a.id, b.id]
            let edit = EaselGeometryEdit(document: session.document, selection: ids)!
            let move = edit.translated(x: -40, y: -50)
            try session.perform("Other window") { $0.items[0].text = "Concurrent text"; $0.items[2].color = "#112233" }
            var external = session.document; external.items[1].frame.x += 1
            #expect(!edit.isCurrent(in: external) && edit.applying(move, to: external) == nil, "One moved member refuses whole original group")
            external = session.document; external.items.remove(at: 1)
            #expect(edit.applying(move, to: external) == nil, "Removed selected member is never recreated")
            external = session.document; external.id = UUID()
            #expect(edit.applying(move, to: external) == nil, "Geometry cannot cross documents")
        }
    }

    @MainActor @Test
    func missingIDsCannotStartAGeometryEdit() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let a = EaselItem(kind: .text, frame: .init(x: 10, y: 20, width: 60, height: 50), zIndex: 2, text: "Original")
            let b = EaselItem(kind: .image, frame: .init(x: 100, y: 120, width: 80, height: 50), zIndex: 5, assetID: asset)
            let c = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 300, width: 50, height: 50))
            try session.perform("Add") { $0.items = [a, b, c] }
            #expect(EaselGeometryEdit(document: session.document, selection: [UUID()]) == nil, "Missing IDs refuse admission")
        }
    }

    @Test
    func reverseMarqueeDragsMakeTheSameRectangle() {
            let backwards = EaselCanvasSelection.marquee(from: .init(x: 200, y: 200), to: .init(x: 0, y: 0))
            #expect(backwards == .init(x: 0, y: 0, width: 200, height: 200), "Marquee normalizes reverse drag")
    }

    @MainActor @Test
    func aMarqueeReplacesAddsOrSubtractsItsHits() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let a = EaselItem(kind: .text, frame: .init(x: 10, y: 20, width: 60, height: 50), zIndex: 2, text: "Original")
            let b = EaselItem(kind: .image, frame: .init(x: 100, y: 120, width: 80, height: 50), zIndex: 5, assetID: asset)
            let c = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 300, width: 50, height: 50))
            try session.perform("Add") { $0.items = [a, b, c] }
            let ids: Set<UUID> = [a.id, b.id]
            let backwards = EaselCanvasSelection.marquee(from: .init(x: 200, y: 200), to: .init(x: 0, y: 0))
            #expect(EaselCanvasSelection.selecting(in: backwards, items: session.document.items, original: [c.id], operation: .replace) == ids, "Marquee replaces with original intersecting IDs")
            #expect(EaselCanvasSelection.selecting(in: backwards, items: session.document.items, original: [c.id, UUID()], operation: .add) == [a.id, b.id, c.id], "Shift unions hits and drops unavailable IDs")
            #expect(EaselCanvasSelection.selecting(in: backwards, items: session.document.items, original: [a.id, c.id], operation: .subtract) == [c.id], "Command subtracts hits without toggling unselected objects")
            let empty = EaselRect(x: 0, y: 0, width: 0, height: 0)
            #expect(EaselCanvasSelection.selecting(in: empty, items: session.document.items, original: ids, operation: .replace).isEmpty, "Clicking empty canvas clears only on commit")
        }
    }

    @MainActor @Test
    func duplicatesPreservePayloadSpacingAndStackingWithNewIDs() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let a = EaselItem(kind: .text, frame: .init(x: 10, y: 20, width: 60, height: 50), zIndex: 2, text: "Original")
            let b = EaselItem(kind: .image, frame: .init(x: 100, y: 120, width: 80, height: 50), zIndex: 5, assetID: asset)
            let c = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 300, width: 50, height: 50))
            try session.perform("Add") { $0.items = [a, b, c] }
            let ids: Set<UUID> = [a.id, b.id]
            try session.perform("Other window") { $0.items[0].text = "Concurrent text"; $0.items[2].color = "#112233" }
            let command = EaselObjectCommand(document: session.document, selection: ids)!
            let copies = command.duplicates(in: session.document)!
            #expect(Set(copies.map(\.id)).isDisjoint(with: ids) && Set(copies.map(\.id)).count == 2, "Duplicates have new distinct original-object identities")
            #expect(copies[0].frame.x == a.frame.x + 24 && copies[1].frame.x - copies[0].frame.x == b.frame.x - a.frame.x, "Duplicate keeps relative geometry and existing point offset")
            #expect(copies[1].assetID == asset && copies[0].text == "Concurrent text", "Duplicate carries exact source image/text payload")
            #expect(copies.map(\.zIndex) == [6, 7], "Duplicate selected order is above existing objects")
            try session.perform("Duplicate originals") { $0.items.append(contentsOf: copies) }
            #expect(try! Data(contentsOf: session.assetURL(copies[1].assetID!)) == EaselStoreTestsSupport.png, "Duplicate image references real original asset bytes")
        }
    }

    @MainActor @Test
    func duplicateGroupUndoAndRedoPreserveExactIDs() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let a = EaselItem(kind: .text, frame: .init(x: 10, y: 20, width: 60, height: 50), zIndex: 2, text: "Original")
            let b = EaselItem(kind: .image, frame: .init(x: 100, y: 120, width: 80, height: 50), zIndex: 5, assetID: asset)
            let c = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 300, width: 50, height: 50))
            try session.perform("Add") { $0.items = [a, b, c] }
            let ids: Set<UUID> = [a.id, b.id]
            try session.perform("Other window") { $0.items[0].text = "Concurrent text"; $0.items[2].color = "#112233" }
            let command = EaselObjectCommand(document: session.document, selection: ids)!
            let copies = command.duplicates(in: session.document)!
            try session.perform("Duplicate originals") { $0.items.append(contentsOf: copies) }
            try session.undo(); #expect(session.document.items.count == 3, "Single undo removes complete duplicate group")
            try session.redo(); #expect(Array(session.document.items.suffix(2)).map(\.id) == copies.map(\.id), "Redo restores exact duplicate UUIDs")
        }
    }

    @MainActor @Test
    func aStaleDuplicateCommandRefusesReplacementContent() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let a = EaselItem(kind: .text, frame: .init(x: 10, y: 20, width: 60, height: 50), zIndex: 2, text: "Original")
            let b = EaselItem(kind: .image, frame: .init(x: 100, y: 120, width: 80, height: 50), zIndex: 5, assetID: asset)
            let c = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 300, width: 50, height: 50))
            try session.perform("Add") { $0.items = [a, b, c] }
            let ids: Set<UUID> = [a.id, b.id]
            try session.perform("Other window") { $0.items[0].text = "Concurrent text"; $0.items[2].color = "#112233" }
            let command = EaselObjectCommand(document: session.document, selection: ids)!
            let copies = command.duplicates(in: session.document)!
            try session.perform("Duplicate originals") { $0.items.append(contentsOf: copies) }
            try session.undo()
            try session.redo()
            var external = session.document; external.items[0].text = "Changed after menu"
            #expect(command.duplicates(in: external) == nil, "Stale original-object command cannot copy replacement content")
        }
    }

    @MainActor @Test
    func aFailedDuplicateWriteLeavesTheBoardUnchanged() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory)
            let session = try store.create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let a = EaselItem(kind: .text, frame: .init(x: 10, y: 20, width: 60, height: 50), zIndex: 2, text: "Original")
            let b = EaselItem(kind: .image, frame: .init(x: 100, y: 120, width: 80, height: 50), zIndex: 5, assetID: asset)
            let c = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 300, width: 50, height: 50))
            try session.perform("Add") { $0.items = [a, b, c] }
            let ids: Set<UUID> = [a.id, b.id]
            try session.perform("Other window") { $0.items[0].text = "Concurrent text"; $0.items[2].color = "#112233" }
            let command = EaselObjectCommand(document: session.document, selection: ids)!
            let copies = command.duplicates(in: session.document)!
            try session.perform("Duplicate originals") { $0.items.append(contentsOf: copies) }
            try session.undo()
            try session.redo()
            let beforeFailure = session.document, url = EaselStoreTestsSupport.file(directory, session.document.id)
            try FileManager.default.removeItem(at: url); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            EaselStoreTestsSupport.expectThrows("duplicate write failure") { try session.perform("Duplicate") { $0.items.append(contentsOf: command.duplicates(in: $0)!) } }
            #expect(session.document == beforeFailure, "Failed duplicate does not publish objects or lose original selection target")
        }
    }
}
