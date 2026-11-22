import Foundation
import Testing
@testable import ParcCore

struct EaselStoreDocumentPersistenceTests {
    @MainActor @Test func damagedStackNumbersAreRepairedInPaintOrder() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            try session.perform("Stack") {
                $0.items = [EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "Top"), EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "Bottom"),
                            EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "Middle")]
            }
            var raw = try JSONSerialization.jsonObject(with: Data(contentsOf: EaselStoreTestsSupport.file(directory, session.document.id))) as! [String: Any]
            var items = raw["items"] as! [[String: Any]]
            items[0]["zIndex"] = Int.max; items[1]["zIndex"] = Int.min; items[2]["zIndex"] = 7
            raw["items"] = items
            try JSONSerialization.data(withJSONObject: raw).write(to: EaselStoreTestsSupport.file(directory, session.document.id))
            let loaded = try EaselStore(directory: directory).load(session.document.id).document
            #expect(loaded.items.map(\.text) == ["Top", "Bottom", "Middle"], "Stack repair keeps every object in place")
            #expect(loaded.items.map(\.zIndex) == [2, 0, 1], "Giant stack numbers are renumbered in their original paint order")
            #expect((loaded.items.map(\.zIndex).max() ?? 0) + 1 == 3, "Adding on top of a repaired Easel can't overflow")
            let calm = EaselStore.repairingStackOrder(session.document)
            #expect(calm == session.document, "Ordinary stack numbers are left alone")
        }
    }

    @MainActor @Test func boardObjectFieldsSurviveASaveAndReopen() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory)
            let session = try store.create()
            var diamond = EaselItem(kind: .rectangle, frame: EaselStoreTestsSupport.frame, text: "Plan")
            diamond.shape = .diamond; diamond.fill = "#3D8FC4"; diamond.fillOpacity = 0.4
            diamond.strokeWidth = 4; diamond.strokeDash = .dashed; diamond.groupID = UUID()
            diamond.locked = true; diamond.rotation = 15
            diamond.textStyle = EaselTextStyle(alignment: .center)
            var sticky = EaselItem(kind: .sticky, frame: EaselStoreTestsSupport.frame, zIndex: 1, text: "Idea")
            sticky.fill = "#E8B53A"
            var section = EaselItem(kind: .section, frame: EaselRect(x: 0, y: 0, width: 600, height: 400), zIndex: 2, text: "Research")
            section.fill = "#4F9A6E"; section.fillOpacity = 0.16
            var arrow = EaselItem(kind: .arrow, frame: EaselStoreTestsSupport.frame, zIndex: 3, points: [.init(x: 0, y: 0), .init(x: 120, y: 80)])
            arrow.startHead = .circle; arrow.endHead = .triangle; arrow.routing = .elbow
            arrow.startConnection = EaselConnection(itemID: diamond.id, side: .right)
            arrow.endConnection = EaselConnection(itemID: sticky.id, side: nil)
            arrow.endConnection?.anchor = EaselPoint(x: 0.25, y: 1)
            arrow.text = "yes"; arrow.labelPosition = 0.3; arrow.labelBackground = true
            arrow.waypoints = [EaselPoint(x: 60, y: 10)]
            diamond.flipHorizontal = true; diamond.flipVertical = false
            var junction = EaselItem(kind: .rectangle, frame: EaselStoreTestsSupport.frame, zIndex: 4)
            junction.shape = .summingJunction
            var highlight = EaselItem(kind: .freehand, frame: EaselStoreTestsSupport.frame, zIndex: 5, points: [.init(x: 0, y: 0), .init(x: 9, y: 9)])
            highlight.brush = .highlighter; highlight.attachedTo = sticky.id
            var tape = EaselItem(kind: .freehand, frame: EaselStoreTestsSupport.frame, zIndex: 6, points: [.init(x: 0, y: 0), .init(x: 9, y: 0)])
            tape.brush = .washi; tape.pattern = "candy-stripe"
            var solid = arrow; solid.id = UUID(); solid.zIndex = 7; solid.endHead = .solidArrow; solid.startHead = .erdZeroOrMore
            try session.perform("Add board objects") { $0.items += [diamond, sticky, section, arrow, junction, highlight, tape, solid] }
            let reopened = try EaselStore(directory: directory).load(session.document.id)
            #expect(reopened.document.items == [diamond, sticky, section, arrow, junction, highlight, tape, solid], "Board object fields survive a save and reopen")
            #expect(highlight.resolvedBrush == .highlighter && junction.resolvedBrush == .marker && arrow.resolvedLabelPosition == 0.3, "Brush and label helpers read stored values with defaults")
            #expect(diamond.resolvedShape == .diamond && diamond.isLocked && diamond.resolvedRotation == 15, "Shape helpers read the stored outline, lock and rotation")
            let circle = EaselItem(kind: .circle, frame: EaselStoreTestsSupport.frame)
            let plain = EaselItem(kind: .rectangle, frame: EaselStoreTestsSupport.frame)
            #expect(circle.resolvedShape == .ellipse && plain.resolvedShape == .rectangle && sticky.resolvedShape == nil, "Legacy rectangles and circles keep their outlines")
            let legacyArrow = EaselItem(kind: .arrow, frame: EaselStoreTestsSupport.frame, points: [.init(x: 0, y: 0), .init(x: 4, y: 4)])
            #expect(legacyArrow.resolvedStartHead == .none && legacyArrow.resolvedEndHead == .arrow && legacyArrow.resolvedRouting == .straight, "Legacy arrows keep one arrowhead at the end and a straight line")
            #expect(EaselItemKind.allCases.filter(\.holdsText) == [.text, .rectangle, .circle, .sticky], "Text lives in text, shapes and stickies")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let legacy = String(decoding: try encoder.encode(plain), as: UTF8.self)
            for key in ["shape", "fill", "fillOpacity", "strokeWidth", "strokeDash", "startHead", "endHead", "routing",
                        "startConnection", "endConnection", "groupID", "locked", "rotation"] {
                #expect(!legacy.contains("\"" + key + "\""), "Unused board fields stay out of saved bytes: \(key)")
            }
            let style = String(decoding: try encoder.encode(EaselTextStyle()), as: UTF8.self)
            #expect(!style.contains("alignment"), "Unused text alignment stays out of saved bytes")
        }
    }

    enum InvalidBoardItem: CaseIterable {
        case fillColor, fillOpacity, negativeStrokeWidth, overwideStroke, nonfiniteRotation, rotationPastATurn
        case circleOutline, shapeArrowhead, shapeRouting, shapeConnection, shapeLabel, shapeBends, shapeBrush
        case tapePath, outsideAnchor, outsideLabel, selfAttachment, selfConnection
    }

    @MainActor @Test(arguments: InvalidBoardItem.allCases)
    func anInvalidBoardObjectDoesNotChangeTheDocument(_ invalid: InvalidBoardItem) throws {
        let target = EaselItem(kind: .rectangle, frame: EaselStoreTestsSupport.frame)
        var object = EaselItem(kind: .rectangle, frame: EaselStoreTestsSupport.frame, zIndex: 1)
        switch invalid {
        case .fillColor:
            object.fill = "blue"
        case .fillOpacity:
            object.fillOpacity = 1.5
        case .negativeStrokeWidth:
            object.strokeWidth = -1
        case .overwideStroke:
            object.strokeWidth = 100
        case .nonfiniteRotation:
            object.rotation = .nan
        case .rotationPastATurn:
            object.rotation = 720
        case .circleOutline:
            object.kind = .circle
            object.shape = .star
        case .shapeArrowhead:
            object.endHead = .triangle
        case .shapeRouting:
            object.routing = .curved
        case .shapeConnection:
            object.startConnection = EaselConnection(itemID: target.id)
        case .shapeLabel:
            object.labelPosition = 0.5
        case .shapeBends:
            object.waypoints = [EaselPoint(x: 1, y: 1)]
        case .shapeBrush:
            object.brush = .highlighter
        case .tapePath:
            object.kind = .freehand
            object.points = [.init(x: 0, y: 0), .init(x: 1, y: 1)]
            object.pattern = "../escape"
        case .outsideAnchor:
            object.kind = .arrow
            object.points = [.init(x: 0, y: 0), .init(x: 1, y: 1)]
            object.endConnection = EaselConnection(itemID: target.id, anchor: EaselPoint(x: 1.5, y: 0))
        case .outsideLabel:
            object.kind = .arrow
            object.points = [.init(x: 0, y: 0), .init(x: 1, y: 1)]
            object.labelPosition = 2
        case .selfAttachment:
            object.attachedTo = object.id
        case .selfConnection:
            object.kind = .arrow
            object.points = [.init(x: 0, y: 0), .init(x: 1, y: 1)]
            object.endConnection = EaselConnection(itemID: object.id)
        }
        let date = Date(timeIntervalSince1970: 0)
        let before = EaselDocument(id: UUID(), title: "Board", createdAt: date, modifiedAt: date, items: [target])
        let session = try EaselSession(inMemory: before, assets: [:])
        #expect(throws: EaselStoreError.self) {
            try session.perform("Add invalid object") { $0.items.append(object) }
        }
        #expect(session.document == before && !session.canUndo)
    }

    @Test func rectanglesSavedBeforeBoardStylesKeepTheirOriginalOutline() throws {
        let decoded = try JSONDecoder().decode(EaselItem.self, from: Data(##"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","kind":"rectangle","frame":{"x":1,"y":2,"width":3,"height":4},"zIndex":0,"text":"","color":"#252525","points":[]}"##.utf8))
        #expect(decoded.shape == nil && decoded.fill == nil && decoded.rotation == nil && decoded.resolvedShape == .rectangle, "Easels saved before board objects decode unchanged")
    }

    @MainActor @Test
    func documentsAndTheirAssetsRoundTripThroughAFreshStore() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1234)
            let store = try EaselStore(directory: directory, now: { now })
            let session = try store.create(title: "Reading board")
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let objects = [
                EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "A title"),
                EaselItem(kind: .image, frame: EaselStoreTestsSupport.frame, assetID: asset),
                EaselItem(kind: .rectangle, frame: EaselStoreTestsSupport.frame, zIndex: 6, color: "#ABCDEF"),
                EaselItem(kind: .circle, frame: EaselStoreTestsSupport.frame),
                EaselItem(kind: .arrow, frame: EaselStoreTestsSupport.frame, points: [.init(x: 0, y: 0), .init(x: 120, y: 80)]),
                EaselItem(kind: .freehand, frame: EaselStoreTestsSupport.frame, points: [.init(x: 0, y: 0), .init(x: 12, y: 40), .init(x: 50, y: 20)]),
                EaselItem(kind: .webCard, frame: EaselStoreTestsSupport.frame, text: "Captured page", url: "https://example.com/page", assetID: asset, capturedAt: now),
                EaselItem(kind: .link, frame: EaselStoreTestsSupport.frame, text: "Reference", url: "https://example.org/")
            ]
            try session.perform("Add objects") { $0.items = objects }
            let fresh = try EaselStore(directory: directory).load(session.document.id)
            #expect(fresh.document == session.document, "All supported object payloads round trip")
            #expect(fresh.document.items.map(\.id) == objects.map(\.id), "Object identity and array order persist")
            #expect(fresh.document.items[2].zIndex == 6, "Z order persists independently of array order")
            #expect(fresh.document.items[4].points == objects[4].points, "Arrow points persist")
            #expect(fresh.document.items[6].capturedAt == now, "Capture time persists")
            #expect(fresh.document.items[6].assetID == asset, "Capture keeps image reference")
            #expect(try! Data(contentsOf: fresh.assetURL(asset)) == EaselStoreTestsSupport.png, "Asset bytes remain exact")
        }
    }

    @MainActor @Test
    func undoHistoryDoesNotCarryOverIntoAFreshSession() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1234)
            let store = try EaselStore(directory: directory, now: { now })
            let session = try store.create(title: "Reading board")
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let objects = [
                EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "A title"),
                EaselItem(kind: .image, frame: EaselStoreTestsSupport.frame, assetID: asset),
                EaselItem(kind: .rectangle, frame: EaselStoreTestsSupport.frame, zIndex: 6, color: "#ABCDEF"),
                EaselItem(kind: .circle, frame: EaselStoreTestsSupport.frame),
                EaselItem(kind: .arrow, frame: EaselStoreTestsSupport.frame, points: [.init(x: 0, y: 0), .init(x: 120, y: 80)]),
                EaselItem(kind: .freehand, frame: EaselStoreTestsSupport.frame, points: [.init(x: 0, y: 0), .init(x: 12, y: 40), .init(x: 50, y: 20)]),
                EaselItem(kind: .webCard, frame: EaselStoreTestsSupport.frame, text: "Captured page", url: "https://example.com/page", assetID: asset, capturedAt: now),
                EaselItem(kind: .link, frame: EaselStoreTestsSupport.frame, text: "Reference", url: "https://example.org/")
            ]
            try session.perform("Add objects") { $0.items = objects }
            let fresh = try EaselStore(directory: directory).load(session.document.id)
            #expect(!fresh.canUndo && !fresh.canRedo, "Undo snapshots are session-local")
        }
    }

    @MainActor @Test
    func listingUsesTheSavedTitleAndObjectCount() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1234)
            let store = try EaselStore(directory: directory, now: { now })
            let session = try store.create(title: "Reading board")
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let objects = [
                EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "A title"),
                EaselItem(kind: .image, frame: EaselStoreTestsSupport.frame, assetID: asset),
                EaselItem(kind: .rectangle, frame: EaselStoreTestsSupport.frame, zIndex: 6, color: "#ABCDEF"),
                EaselItem(kind: .circle, frame: EaselStoreTestsSupport.frame),
                EaselItem(kind: .arrow, frame: EaselStoreTestsSupport.frame, points: [.init(x: 0, y: 0), .init(x: 120, y: 80)]),
                EaselItem(kind: .freehand, frame: EaselStoreTestsSupport.frame, points: [.init(x: 0, y: 0), .init(x: 12, y: 40), .init(x: 50, y: 20)]),
                EaselItem(kind: .webCard, frame: EaselStoreTestsSupport.frame, text: "Captured page", url: "https://example.com/page", assetID: asset, capturedAt: now),
                EaselItem(kind: .link, frame: EaselStoreTestsSupport.frame, text: "Reference", url: "https://example.org/")
            ]
            try session.perform("Add objects") { $0.items = objects }
            let summary = try store.list()[0]
            #expect(summary.title == "Reading board" && summary.itemCount == 8, "Summary reflects saved document")
        }
    }

    @MainActor @Test
    func savedDocumentsOmitTransientSelectionAndVendorState() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1234)
            let store = try EaselStore(directory: directory, now: { now })
            let session = try store.create(title: "Reading board")
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let objects = [
                EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "A title"),
                EaselItem(kind: .image, frame: EaselStoreTestsSupport.frame, assetID: asset),
                EaselItem(kind: .rectangle, frame: EaselStoreTestsSupport.frame, zIndex: 6, color: "#ABCDEF"),
                EaselItem(kind: .circle, frame: EaselStoreTestsSupport.frame),
                EaselItem(kind: .arrow, frame: EaselStoreTestsSupport.frame, points: [.init(x: 0, y: 0), .init(x: 120, y: 80)]),
                EaselItem(kind: .freehand, frame: EaselStoreTestsSupport.frame, points: [.init(x: 0, y: 0), .init(x: 12, y: 40), .init(x: 50, y: 20)]),
                EaselItem(kind: .webCard, frame: EaselStoreTestsSupport.frame, text: "Captured page", url: "https://example.com/page", assetID: asset, capturedAt: now),
                EaselItem(kind: .link, frame: EaselStoreTestsSupport.frame, text: "Reference", url: "https://example.org/")
            ]
            try session.perform("Add objects") { $0.items = objects }
            let text = String(data: try Data(contentsOf: EaselStoreTestsSupport.file(directory, session.document.id)), encoding: .utf8)!
            #expect(!text.contains("selection") && !text.contains("Firebase"), "Transient selection and vendor state are absent")
        }
    }

    @MainActor @Test
    func aBoardCannotSaveThroughADocumentsDirectorySymlink() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let docs = directory.appendingPathComponent("documents")
            try FileManager.default.moveItem(at: docs, to: directory.appendingPathComponent("original-documents"))
            try FileManager.default.createSymbolicLink(at: docs, withDestinationURL: directory.appendingPathComponent("original-documents"))
            EaselStoreTestsSupport.expectThrows("documents directory symlink") { try session.save() }
        }
    }

    @MainActor @Test
    func aFailedSaveLeavesTheDocumentUnchangedAndNoTemporaryFile() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            try session.perform("Rename") { $0.title = "First" }
            let committed = session.document
            let url = EaselStoreTestsSupport.file(directory, committed.id)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            EaselStoreTestsSupport.expectThrows("failed atomic save") { try session.perform("Rename") { $0.title = "Never published" } }
            #expect(session.document == committed, "I/O failure leaves in-memory document unchanged")
            let residual = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            #expect(!residual.contains(where: { $0.hasPrefix(".write-") }), "Failed save leaves no transaction temporary")
        }
    }

    @MainActor @Test
    func aFailedUndoSaveKeepsTheDocumentAndHistory() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            try session.perform("Rename") { $0.title = "First" }
            let committed = session.document
            let url = EaselStoreTestsSupport.file(directory, committed.id)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            EaselStoreTestsSupport.expectThrows("failed undo save") { try session.undo() }
            #expect(session.document == committed && session.canUndo && !session.canRedo, "Failed undo preserves history and document")
        }
    }

    @MainActor @Test
    func editingOneDocumentDoesNotChangeAnotherOrItsHistory() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory)
            let first = try store.create(title: "First")
            let second = try store.create(title: "Second")
            try first.perform("Edit") { $0.items.append(EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "Private to first")) }
            #expect(second.document.items.isEmpty && !second.canUndo, "Documents and undo histories are isolated")
        }
    }

    @MainActor @Test
    func deletingADocumentKeepsOtherDocuments() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory)
            let first = try store.create(title: "First")
            let second = try store.create(title: "Second")
            try first.perform("Edit") { $0.items.append(EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "Private to first")) }
            try store.delete(first.document.id)
            #expect(try! store.list().map(\.id) == [second.document.id], "Delete only removes selected document")
        }
    }

    @MainActor @Test
    func aDeletedSessionCannotBeReopenedOrResurrected() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory)
            let first = try store.create(title: "First")
            try first.perform("Edit") { $0.items.append(EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "Private to first")) }
            try store.delete(first.document.id)
            EaselStoreTestsSupport.expectThrows("deleted session cannot resurrect") { try first.save() }
            EaselStoreTestsSupport.expectThrows("deleted session cannot edit") { try first.perform("Resurrect") { $0.title = "No" } }
            EaselStoreTestsSupport.expectThrows("deleted session cannot import") { _ = try first.importPNG(EaselStoreTestsSupport.png) }
            EaselStoreTestsSupport.expectThrows("load deleted") { _ = try store.load(first.document.id) }
            #expect(!first.canUndo && !first.canRedo, "Deletion clears history")
        }
    }
    @MainActor @Test
    func anOpenDocumentReturnsItsExistingSession() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory)
            let session = try store.create()
            #expect(try store.load(session.document.id) === session)
        }
    }
}
