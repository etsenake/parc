import Foundation

@main
struct EaselStoreTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    @MainActor static func expectThrows(_ message: String, _ body: () throws -> Void) {
        assertions += 1
        do { try body(); fatalError("Expected error: " + message) } catch { }
    }

    @MainActor static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-easel-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
    static let frame = EaselRect(x: 20, y: 30, width: 120, height: 80)

    struct Writes {
        let directory: URL
        let calls: [FileOperation]
        let encodes: Int
        @MainActor func temporaries(_ id: UUID) -> [FileOperation] {
            let documents = file(directory, id).deletingLastPathComponent().standardizedFileURL.path
            return calls.filter { $0.fileName.hasPrefix(".write-") && ($0.path as NSString).deletingLastPathComponent == documents }
        }
        @MainActor func replaces(_ id: UUID) -> Int { Set(temporaries(id).map(\.path)).count }
        @MainActor func offMain(_ id: UUID) -> Bool { !temporaries(id).contains(where: \.onMainThread) }
    }
    @MainActor static func writes(in directory: URL, _ body: () throws -> Void) throws -> Writes {
        FileOperations.install()
        var calls: [FileOperation] = []
        let reads = try ObservedString.reads { calls = try FileOperations.during(directory, body) }
        return Writes(directory: directory, calls: calls, encodes: ObservedString.backgroundEncodes(reads))
    }
    @MainActor static func file(_ directory: URL, _ id: UUID) -> URL {
        directory.appendingPathComponent("documents/" + id.uuidString.lowercased() + ".json")
    }

    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        try roundTripAndIdentity()
        try transactionsAndHistory()
        try validationAndPreservation()
        try corruptionAndVersioning()
        try assetsAndPathSafety()
        try failedSaveDoesNotPublish()
        try deletionAndIsolation()
        try textStylePersistence()
        try coalescedEditingHistory()
        try richTextPersistence()
        try inlineImagePersistence()
        try canvasTransactions()
        try groupResizeTransactions()
        canvasHitAndGuides()
        canvasAnchors()
        try directControls()
        try browserObjectOwnership()
        try browserNavigationMetadata()
        try profileRelocation()
        try persistEncodeOffCallingThread()
        try identicalBytePersistSkip()
        webInputDestinations()
        print("EaselStore: \(assertions) assertions passed (22 test groups)")
    }

    @MainActor static func persistEncodeOffCallingThread() throws {
        try withDirectory { directory in
            let store = try EaselStore(directory: directory, now: { Date(timeIntervalSince1970: 2_000) })
            var created: EaselSession?
            let create = try writes(in: directory) { created = try store.create(title: ObservedString.text("Off-thread board")) }
            let session = created!
            expect(create.encodes == 1, "Create encodes once through the document writer")
            expect(create.replaces(session.document.id) == 1 && create.offMain(session.document.id), "Create encode is off the calling thread")

            let edit = try writes(in: directory) {
                try session.perform("Canvas edit") {
                    $0.items = [EaselItem(kind: .text, frame: frame, text: "Stroke"),
                                EaselItem(kind: .freehand, frame: frame,
                                          points: [.init(x: 0, y: 0), .init(x: 10, y: 20), .init(x: 30, y: 5)])]
                }
            }
            expect(edit.encodes == 1, "Each canvas persist encodes once")
            expect(edit.replaces(session.document.id) == 1 && edit.offMain(session.document.id),
                   "Canvas persist encode is off the calling/MainActor stack")

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let expected = try encoder.encode(session.document)
            let onDisk = try Data(contentsOf: file(directory, session.document.id))
            expect(onDisk == expected, "Persisted JSON bytes match sortedKeys encoder output exactly")

            let undo = try writes(in: directory) {
                try session.perform("Rename") { $0.title = ObservedString.text("Renamed board") }
                try session.undo()
                try session.redo()
            }
            expect(undo.encodes == 3 && undo.replaces(session.document.id) == 3 && undo.offMain(session.document.id),
                   "Undo/redo encode off the calling thread")
            let afterRedo = try Data(contentsOf: file(directory, session.document.id))
            let redoExpected = try encoder.encode(session.document)
            expect(afterRedo == redoExpected, "Undo/redo keep sortedKeys identity with the live document")

            let bytesBeforeSave = try Data(contentsOf: file(directory, session.document.id))
            let save = try writes(in: directory) { try session.save() }
            expect(save.encodes == 1, "Explicit save still encodes off the calling thread")
            expect(save.replaces(session.document.id) == 0,
                   "Explicit save of unchanged sortedKeys bytes skips atomic replace")
            let afterSave = try Data(contentsOf: file(directory, session.document.id))
            let saveExpected = try encoder.encode(session.document)
            expect(afterSave == saveExpected && afterSave == bytesBeforeSave,
                   "Identical-byte save leaves durable sortedKeys payload unchanged")

            let reopened = try EaselStore(directory: directory).load(session.document.id)
            expect(reopened.document == session.document, "Off-thread persist round-trips the exact document")
        }
    }

    @MainActor static func identicalBytePersistSkip() throws {
        try withDirectory { directory in
            let store = try EaselStore(directory: directory, now: { Date(timeIntervalSince1970: 3_000) })
            var created: EaselSession?
            let create = try writes(in: directory) { created = try store.create(title: ObservedString.text("Skip board")) }
            let session = created!
            expect(create.encodes == 1 && create.replaces(session.document.id) == 1,
                   "Create encodes and atomically replaces once")

            let bytesAfterCreate = try Data(contentsOf: file(directory, session.document.id))
            let saves = try writes(in: directory) {
                try session.save()
                try session.save()
            }
            expect(saves.encodes == 2,
                   "Repeated identical saves may still encode off-thread")
            expect(saves.replaces(session.document.id) == 0,
                   "Repeated identical saves do not replace the durable file")
            expect(try! Data(contentsOf: file(directory, session.document.id)) == bytesAfterCreate,
                   "Skipped saves leave the exact on-disk bytes")

            let realEdit = try writes(in: directory) {
                try session.perform("Real edit") {
                    $0.items = [EaselItem(kind: .text, frame: frame, text: "Changed")]
                }
            }
            expect(realEdit.encodes == 1 && realEdit.replaces(session.document.id) == 1,
                   "A real edit encodes and atomically replaces")
            let afterEdit = try Data(contentsOf: file(directory, session.document.id))
            expect(afterEdit != bytesAfterCreate, "Real edit changes durable sortedKeys bytes")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let editExpected = try encoder.encode(session.document)
            expect(afterEdit == editExpected,
                   "Real edit bytes stay sortedKeys-identical to the live document")

            let bytesAfterEdit = afterEdit
            let unchanged = try writes(in: directory) { try session.save() }
            expect(unchanged.replaces(session.document.id) == 0
                       && (try! Data(contentsOf: file(directory, session.document.id))) == bytesAfterEdit,
                   "Save after an edit with no further mutation skips replace")

            let rename = try writes(in: directory) {
                try session.perform("Second edit") { $0.title = ObservedString.text("Skip board renamed") }
            }
            expect(rename.replaces(session.document.id) == 1,
                   "A later distinct document still atomically replaces")
            let renamedExpected = try encoder.encode(session.document)
            expect(try! Data(contentsOf: file(directory, session.document.id)) == renamedExpected,
                   "Distinct persist keeps sortedKeys identity")
        }
    }

    @MainActor static func profileRelocation() throws {
        try withDirectory { directory in
            let source = try EaselStore(directory: directory.appendingPathComponent("source"))
            let destination = try EaselStore(directory: directory.appendingPathComponent("destination"))
            let original = try source.create(title: "Profile transfer")
            let id = original.document.id, asset = try original.importPNG(png)
            let browser = EaselItem(kind: .browser, frame: frame, url: "https://example.com/original")
            let card = EaselItem(kind: .webCard, frame: frame, text: "Original capture", url: "https://example.com/source", assetID: asset, capturedAt: Date(timeIntervalSince1970: 42))
            try original.perform("Seed") { $0.items = [browser, card] }
            _ = try original.recordBrowserNavigation(URL(string: "https://example.com/current")!, itemID: browser.id, expectedURL: browser.url!)
            let saved = original.document
            let originalBytes = try Data(contentsOf: file(source.directory, id))
            let liveChild = original.observeReplacement { $0 != nil }
            expectThrows("a live original child prevents session retirement") { try source.retireSessionForRelocation(id) }
            expect(!original.isClosed && (try! source.load(id)) === original, "refused retirement preserves source session")
            original.removeReplacementObserver(liveChild)
            expectThrows("a still-open editor cannot move by deallocation timing") { _ = try source.relocate(id, to: destination) }
            try source.retireSessionForRelocation(id)
            expect(original.isClosed && !original.canUndo && !original.canRedo, "explicit session retirement revokes history despite a retained old owner")
            let copied = try source.relocate(id, to: destination)
            expect(copied == [asset] && (try? source.load(id)) == nil, "actual document moves after explicit retirement")
            expect(try! Data(contentsOf: file(destination.directory, id)) == originalBytes, "Profile relocation preserves the exact document bytes")
            expectThrows("retained editor cannot recreate the source file") { try original.perform("Late callback") { $0.title = "Wrong profile" } }
            expectThrows("retired navigation cannot rewrite source metadata") { _ = try original.recordBrowserNavigation(URL(string: "https://example.com/stale")!, itemID: browser.id, expectedURL: "https://example.com/current") }
            expectThrows("retired save is refused") { try original.save() }
            expectThrows("retired asset import is refused") { _ = try original.importPNG(png) }
            expectThrows("retired undo is refused") { try original.undo() }
            expectThrows("retired redo is refused") { try original.redo() }
            expect(!FileManager.default.fileExists(atPath: file(source.directory, id).path), "late callbacks leave no source document behind")
            let arrived = try destination.load(id)
            expect(arrived !== original && arrived.document == saved, "destination uses a fresh session with exact identity/current URL/capture provenance")
            expect(try! arrived.assetData(asset) == png, "destination capture resolves the original bytes")
            try destination.retireSessionForRelocation(id)
            _ = try destination.relocate(id, to: source); destination.removeAssets(copied)
            let restored = try source.load(id)
            expect(restored !== original && restored.document == saved, "rollback reopens exact original data through a fresh source session")
            try restored.perform("After rollback") { $0.title = "Writable source" }
            expect(restored.document.title == "Writable source" && original.document == saved, "old retained session stays revoked after rollback")
            try source.retireSessionForRelocation(id)
            let collision = destination.directory.appendingPathComponent("assets/" + asset)
            var other = png; other.append(0)
            try other.write(to: collision)
            expectThrows("destination asset collision cannot silently replace a capture") { _ = try source.relocate(id, to: destination) }
            expect((try! source.load(id)).document.title == "Writable source" && (try? destination.load(id)) == nil,
                   "asset collision preserves source ownership and leaves no destination document")
            expect(try! Data(contentsOf: collision) == other, "collision preserves the preexisting destination asset")
        }
    }

    @MainActor static func roundTripAndIdentity() throws {
        try withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1234)
            let store = try EaselStore(directory: directory, now: { now })
            let session = try store.create(title: "Reading board")
            expect(try! store.list().count == 1, "Created document listed")
            expect(try! store.load(session.document.id) === session, "One live session per document")
            expect(!session.canUndo && !session.canRedo, "New document has no history")
            let asset = try session.importPNG(png)
            let objects = [
                EaselItem(kind: .text, frame: frame, text: "A title"),
                EaselItem(kind: .image, frame: frame, assetID: asset),
                EaselItem(kind: .rectangle, frame: frame, zIndex: 6, color: "#ABCDEF"),
                EaselItem(kind: .circle, frame: frame),
                EaselItem(kind: .arrow, frame: frame, points: [.init(x: 0, y: 0), .init(x: 120, y: 80)]),
                EaselItem(kind: .freehand, frame: frame, points: [.init(x: 0, y: 0), .init(x: 12, y: 40), .init(x: 50, y: 20)]),
                EaselItem(kind: .webCard, frame: frame, text: "Captured page", url: "https://example.com/page", assetID: asset, capturedAt: now),
                EaselItem(kind: .link, frame: frame, text: "Reference", url: "https://example.org/")
            ]
            try session.perform("Add objects") { $0.items = objects }
            let fresh = try EaselStore(directory: directory).load(session.document.id)
            expect(fresh.document == session.document, "All supported object payloads round trip")
            expect(fresh.document.items.map(\.id) == objects.map(\.id), "Object identity and array order persist")
            expect(fresh.document.items[2].zIndex == 6, "Z order persists independently of array order")
            expect(fresh.document.items[4].points == objects[4].points, "Arrow points persist")
            expect(fresh.document.items[6].capturedAt == now, "Capture time persists")
            expect(fresh.document.items[6].assetID == asset, "Capture keeps image reference")
            expect(!fresh.canUndo && !fresh.canRedo, "Undo snapshots are session-local")
            expect(try! Data(contentsOf: fresh.assetURL(asset)) == png, "Asset bytes remain exact")
            let summary = try store.list()[0]
            expect(summary.title == "Reading board" && summary.itemCount == 8, "Summary reflects saved document")
            let text = String(data: try Data(contentsOf: file(directory, session.document.id)), encoding: .utf8)!
            expect(!text.contains("selection") && !text.contains("Firebase"), "Transient selection and vendor state are absent")
        }
    }

    @MainActor static func transactionsAndHistory() throws {
        try withDirectory { directory in
            var tick = Date(timeIntervalSince1970: 100)
            let store = try EaselStore(directory: directory, now: { tick })
            let session = try store.create()
            let original = session.document
            try session.perform("No change") { _ in }
            expect(!session.canUndo, "No-op transaction adds no history")
            tick.addTimeInterval(10)
            try session.perform("Add and rename") {
                $0.title = "Renamed"
                $0.items.append(EaselItem(kind: .text, frame: frame, text: "One"))
                $0.items.append(EaselItem(kind: .text, frame: frame, text: "Two"))
            }
            let committed = session.document
            expect(committed.modifiedAt == tick && committed.createdAt == original.createdAt, "Transaction updates modification time only")
            expect(session.canUndo && !session.canRedo, "Committed transaction enables undo")
            try session.undo()
            expect(session.document.items.isEmpty && session.document.title == original.title, "One undo reverses whole transaction")
            expect(!session.canUndo && session.canRedo, "Undo enables redo")
            let diskAfterUndo = try EaselStore(directory: directory).load(original.id)
            expect(diskAfterUndo.document.items.isEmpty, "Undo is saved durably")
            try session.redo()
            expect(session.document.items == committed.items && session.document.title == committed.title, "Redo restores exact object identities")
            try session.undo()
            try session.perform("Different branch") { $0.title = "Branch" }
            expect(!session.canRedo, "Editing after undo discards redo branch")
            for n in 0..<55 { try session.perform("Rename") { $0.title = "Title \(n)" } }
            var count = 0
            while session.canUndo { try session.undo(); count += 1 }
            expect(count == 50, "Undo history has a bounded count")
        }
    }

    @MainActor static func validationAndPreservation() throws {
        try withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let original = session.document
            let bytes = try Data(contentsOf: file(directory, original.id))
            expectThrows("non-finite geometry") { try session.perform("Bad") { $0.items = [EaselItem(kind: .text, frame: .init(x: .nan, y: 0, width: 1, height: 1))] } }
            expectThrows("negative size") { try session.perform("Bad") { $0.items = [EaselItem(kind: .text, frame: .init(x: 0, y: 0, width: -2, height: 1))] } }
            expectThrows("duplicate ID") { try session.perform("Bad") { let item = EaselItem(kind: .text, frame: frame); $0.items = [item, item] } }
            expectThrows("image requires asset") { try session.perform("Bad") { $0.items = [EaselItem(kind: .image, frame: frame)] } }
            expectThrows("link requires URL") { try session.perform("Bad") { $0.items = [EaselItem(kind: .link, frame: frame)] } }
            expectThrows("javascript URL") { try session.perform("Bad") { $0.items = [EaselItem(kind: .link, frame: frame, url: "javascript:alert(1)")] } }
            expectThrows("file URL") { try session.perform("Bad") { $0.items = [EaselItem(kind: .link, frame: frame, url: "file:///tmp/example")] } }
            expectThrows("arrow requires endpoints") { try session.perform("Bad") { $0.items = [EaselItem(kind: .arrow, frame: frame)] } }
            expectThrows("invalid color") { try session.perform("Bad") { $0.items = [EaselItem(kind: .text, frame: frame, color: "not-a-color")] } }
            expectThrows("blank title") { try session.perform("Bad") { $0.title = " \n " } }
            expectThrows("immutable ID") { try session.perform("Bad") { $0.id = UUID() } }
            expectThrows("immutable creation time") { try session.perform("Bad") { $0.createdAt = .distantPast } }
            expectThrows("version mutation") { try session.perform("Bad") { $0.version = 20 } }
            expectThrows("mutation throwing") { try session.perform("Bad") { $0.title = "Uncommitted"; throw EaselStoreError.tooLarge } }
            expect(session.document == original, "Failed transactions never publish")
            expect(!session.canUndo && !session.canRedo, "Failed transactions add no history")
            expect(try! Data(contentsOf: file(directory, original.id)) == bytes, "Failed validation preserves original file exactly")
        }
    }

    @MainActor static func corruptionAndVersioning() throws {
        try withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let url = file(directory, session.document.id)
            let valid = try Data(contentsOf: url)
            let corrupt = Data("{not valid json".utf8)
            try corrupt.write(to: url)
            expectThrows("corrupt JSON") { _ = try EaselStore(directory: directory).load(session.document.id) }
            expect(try! Data(contentsOf: url) == corrupt, "Corrupt session is not replaced")
            var object = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
            object["version"] = 999
            let future = try JSONSerialization.data(withJSONObject: object)
            try future.write(to: url)
            expectThrows("future version") { _ = try EaselStore(directory: directory).load(session.document.id) }
            expect(try! Data(contentsOf: url) == future, "Future version remains untouched")
            object["version"] = 1
            object["id"] = UUID().uuidString
            try JSONSerialization.data(withJSONObject: object).write(to: url)
            expectThrows("filename/document ID mismatch") { _ = try EaselStore(directory: directory).load(session.document.id) }
            try Data(repeating: 32, count: EaselStore.maximumDocumentBytes + 1).write(to: url)
            expectThrows("oversized document") { _ = try EaselStore(directory: directory).load(session.document.id) }
            let store = try EaselStore(directory: directory)
            let healthy = try store.create(title: "Healthy")
            try Data("{}".utf8).write(to: directory.appendingPathComponent("documents/stray.json"))
            expect(try! store.list().map(\.id) == [healthy.document.id], "One unreadable or stray Easel file does not hide the other Easels")
            try healthy.perform("Shapes") {
                $0.items = [EaselItem(kind: .rectangle, frame: frame), EaselItem(kind: .circle, frame: frame), EaselItem(kind: .text, frame: frame, text: "Kept")]
            }
            let shapes = healthy.document.items
            var duplicated = try JSONSerialization.jsonObject(with: Data(contentsOf: file(directory, healthy.document.id))) as! [String: Any]
            var raw = duplicated["items"] as! [[String: Any]]
            raw[1]["id"] = raw[0]["id"]; raw[2]["id"] = raw[0]["id"]
            duplicated["items"] = raw
            try JSONSerialization.data(withJSONObject: duplicated).write(to: file(directory, healthy.document.id))
            let repaired = try EaselStore(directory: directory).load(healthy.document.id).document
            expect(repaired.items.count == 3 && Set(repaired.items.map(\.id)).count == 3, "Duplicate object IDs on disk are re-IDed instead of rejecting the Easel")
            expect(repaired.items[0].id == shapes[0].id && repaired.items.map(\.kind) == shapes.map(\.kind) && repaired.items[2].text == "Kept",
                   "Repair keeps the first object's ID and every object's content")
            expect(try! EaselStore(directory: directory).load(healthy.document.id).document == repaired, "Duplicate repair is stable across reads")
            var aliased = repaired; aliased.items[1].id = aliased.items[0].id
            let edit = EaselGeometryEdit(document: repaired, selection: [repaired.items[0].id])!
            expect(!edit.isCurrent(in: aliased) || edit.applying(edit.translated(x: 5, y: 5), to: aliased) != nil, "Geometry edits tolerate an aliased document without trapping")
        }
    }

    @MainActor static func assetsAndPathSafety() throws {
        try withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            expectThrows("invalid image carrier") { _ = try session.importPNG(Data("not PNG".utf8)) }
            expectThrows("oversized image") { _ = try session.importPNG(Data(repeating: 0, count: EaselStore.maximumAssetBytes + 1)) }
            let id = try session.importPNG(png)
            expect(id.count == 40 && id.hasSuffix(".png"), "Asset name is generated, not user-supplied")
            expectThrows("path traversal") { _ = try session.assetURL("../outside.png") }
            expectThrows("absolute asset path") { _ = try session.assetURL("/tmp/outside.png") }
            let asset = try session.assetURL(id)
            try FileManager.default.removeItem(at: asset)
            let outside = directory.appendingPathComponent("outside.png")
            try png.write(to: outside)
            try FileManager.default.createSymbolicLink(at: asset, withDestinationURL: outside)
            expectThrows("asset symlink") { _ = try session.assetURL(id) }
            expectThrows("document referencing symlink") { try session.perform("Image") { $0.items = [EaselItem(kind: .image, frame: frame, assetID: id)] } }
            expect(try! Data(contentsOf: outside) == png, "External target was not touched")
            let docs = directory.appendingPathComponent("documents")
            try FileManager.default.moveItem(at: docs, to: directory.appendingPathComponent("original-documents"))
            try FileManager.default.createSymbolicLink(at: docs, withDestinationURL: directory.appendingPathComponent("original-documents"))
            expectThrows("documents directory symlink") { try session.save() }
        }
    }

    @MainActor static func failedSaveDoesNotPublish() throws {
        try withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            try session.perform("Rename") { $0.title = "First" }
            let committed = session.document
            let url = file(directory, committed.id)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            expectThrows("failed atomic save") { try session.perform("Rename") { $0.title = "Never published" } }
            expect(session.document == committed, "I/O failure leaves in-memory document unchanged")
            expectThrows("failed undo save") { try session.undo() }
            expect(session.document == committed && session.canUndo && !session.canRedo, "Failed undo preserves history and document")
            let residual = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            expect(!residual.contains(where: { $0.hasPrefix(".write-") }), "Failed save leaves no transaction temporary")
        }
    }

    @MainActor static func deletionAndIsolation() throws {
        try withDirectory { directory in
            let store = try EaselStore(directory: directory)
            let first = try store.create(title: "First")
            let second = try store.create(title: "Second")
            try first.perform("Edit") { $0.items.append(EaselItem(kind: .text, frame: frame, text: "Private to first")) }
            expect(second.document.items.isEmpty && !second.canUndo, "Documents and undo histories are isolated")
            try store.delete(first.document.id)
            expect(try! store.list().map(\.id) == [second.document.id], "Delete only removes selected document")
            expectThrows("deleted session cannot resurrect") { try first.save() }
            expectThrows("deleted session cannot edit") { try first.perform("Resurrect") { $0.title = "No" } }
            expectThrows("deleted session cannot import") { _ = try first.importPNG(png) }
            expectThrows("load deleted") { _ = try store.load(first.document.id) }
            expect(!first.canUndo && !first.canRedo, "Deletion clears history")
        }
    }
    @MainActor static func textStylePersistence() throws {
        try withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let styles = EaselTextStyle.Family.allCases.flatMap { family in
                EaselTextStyle.Size.allCases.map { EaselTextStyle(family: family, size: $0) }
            }
            try session.perform("Add styles") { document in
                document.items = styles.map { EaselItem(kind: .text, frame: frame, text: "A\n👩🏽‍💻", textStyle: $0) }
            }
            let fresh = try EaselStore(directory: directory).load(session.document.id)
            expect(fresh.document.items.map(\.resolvedTextStyle) == styles, "All twenty styles survive durable reload")
            expect(fresh.document.items.map(\.text) == session.document.items.map(\.text), "Style persistence preserves Unicode and line breaks")
            let url = file(directory, session.document.id)
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            var items = json["items"] as! [[String: Any]]
            for index in items.indices { items[index].removeValue(forKey: "textStyle") }
            json["items"] = items
            try JSONSerialization.data(withJSONObject: json).write(to: url)
            let legacy = try EaselStore(directory: directory).load(session.document.id)
            expect(legacy.document.items.allSatisfy { $0.textStyle == nil && $0.resolvedTextStyle == EaselTextStyle() }, "Existing v1 documents retain clean/body without a migration write")
            items[0]["textStyle"] = ["family": "unknown", "size": "body"]
            json["items"] = items
            try JSONSerialization.data(withJSONObject: json).write(to: url)
            expectThrows("unknown styles are preserved as a load error, never silently normalized") { _ = try EaselStore(directory: directory).load(session.document.id) }
        }
    }

    @MainActor static func coalescedEditingHistory() throws {
        try withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            try session.perform("Add") { $0.items = [EaselItem(kind: .text, frame: frame, text: "")] }
            let group = UUID()
            for text in ["a", "ab", "abc"] {
                try session.perform("Type", coalescing: group) { $0.items[0].text = text }
                let fresh = try EaselStore(directory: directory).load(session.document.id)
                expect(fresh.document.items[0].text == text, "Each coalesced edit still reaches disk")
            }
            try session.undo()
            expect(session.document.items[0].text == "", "One document undo restores typing-run start")
            try session.redo()
            expect(session.document.items[0].text == "abc", "Redo restores the complete typing run")
            try session.perform("Type", coalescing: group) { $0.items[0].text = "abcd" }
            try session.perform("Other window") { $0.title = "From another window" }
            try session.perform("Type", coalescing: group) { $0.items[0].text = "abcde" }
            try session.undo()
            expect(session.document.items[0].text == "abcd" && session.document.title == "From another window", "An intervening transaction breaks coalescing and survives undo")
            try session.undo()
            expect(session.document.items[0].text == "abcd" && session.document.title != "From another window", "Other-window transaction stays independently undoable")
            let beforeFailure = session.document
            expectThrows("failed coalesced transaction") {
                try session.perform("Type", coalescing: group) { $0.items[0].color = "invalid" }
            }
            expect(session.document == beforeFailure && session.canRedo, "Failed coalesced write preserves document and redo branch")
            try session.perform("Style") { $0.items[0].textStyle = EaselTextStyle(family: .fancy, size: .h0) }
            try session.undo()
            expect(session.document.items[0].textStyle == nil && session.document.items[0].text == "abcd", "Style undo preserves text and previous implicit style")
        }
    }

    @MainActor static func inlineImagePersistence() throws {
        try withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let font = EaselRichText.Font(name: "Helvetica", size: 15)
            let image = EaselRichText.Image(data: png, fileType: "public.png", width: 1, height: 1)
            let attributes = EaselRichText.Attributes(font: font, ink: "#252525FF", image: image)
            let rich = EaselRichText(runs: [.init(location: 0, length: 1, attributes: attributes)])
            let item = EaselItem(kind: .text, frame: frame, text: "\u{FFFC}", richText: rich)
            try session.perform("Inline image") { $0.items.append(item) }
            expect(session.document.items[0].id == item.id, "Inline persistence retains original text object identity")
            let reopened = try EaselStore(directory: directory).load(session.document.id)
            expect(reopened.document.items[0].richText == rich, "Inline encoded bytes and range survive actual atomic disk reopen")
            try session.undo(); expect(session.document.items.isEmpty, "Document undo removes the whole accepted original image insertion")
            try session.redo(); expect(session.document.items[0].richText?.runs[0].attributes.image?.data == png, "Document redo restores original bytes")
            var invalid = item; invalid.text = "x"
            expectThrows("Attachment range must be the actual replacement character") { try session.perform("Wrong range") { $0.items = [invalid] } }
            invalid = item; invalid.richText!.runs[0].length = 2; invalid.text = "\u{FFFC}\u{FFFC}"
            expectThrows("One image cannot consume multiple native characters") { try session.perform("Wrong span") { $0.items = [invalid] } }
            invalid = item; invalid.richText!.runs[0].attributes.image!.fileType = "public.url"
            expectThrows("No arbitrary file or URL image carrier") { try session.perform("Unsafe payload") { $0.items = [invalid] } }
            invalid = item; invalid.richText!.runs[0].attributes.image!.width = .infinity
            expectThrows("Invalid inline dimensions refuse atomically") { try session.perform("Invalid size") { $0.items = [invalid] } }
            expect(session.document.items[0] == item, "Rejected attachment edits preserve existing original document")
        }
    }
    @MainActor static func richTextPersistence() throws {
        try withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let ink = EaselRichText.Attributes(font: .init(name: "Helvetica", size: 18), ink: "#194B93FF", underline: 1, link: "https://example.com")
            let text = "A😀B"
            let rich = EaselRichText(runs: [.init(location: 0, length: 1, attributes: ink), .init(location: 1, length: 2, attributes: ink), .init(location: 3, length: 1, attributes: ink)])
            try session.perform("Add rich text") { $0.items = [EaselItem(kind: .text, frame: frame, text: text, richText: rich)] }
            let read = try EaselStore(directory: directory).load(session.document.id)
            expect(read.document.items[0].richText == rich, "Range attributes survive durable document round trip")
            try session.perform("Format selected range") { $0.items[0].richText!.runs[1].attributes.strike = 1 }
            try session.undo()
            expect(session.document.items[0].richText == rich, "Document undo restores exact rich ranges")
            try session.redo()
            expect(session.document.items[0].richText!.runs[1].attributes.strike == 1, "Document redo restores selected range")
            let before = session.document, bytes = try Data(contentsOf: file(directory, before.id))
            expectThrows("split surrogate pair") { try session.perform("Invalid") { $0.items[0].richText!.runs[0].length = 2; $0.items[0].richText!.runs[1].location = 2; $0.items[0].richText!.runs[1].length = 1 } }
            expectThrows("range gap") { try session.perform("Invalid") { $0.items[0].richText!.runs.removeLast() } }
            expectThrows("overflow range") { try session.perform("Invalid") { $0.items[0].richText!.runs[0].length = Int.max } }
            expectThrows("non-finite font") { try session.perform("Invalid") { $0.items[0].richText!.runs[0].attributes.font.size = .infinity } }
            expectThrows("unsafe rich link") { try session.perform("Invalid") { $0.items[0].richText!.runs[0].attributes.link = "file:///private/example" } }
            expectThrows("aliased font axis tags") { try session.perform("Invalid") { $0.items[0].richText!.runs[0].attributes.font.variations = ["1": 1, "01": 2] } }
            expectThrows("signed font axis tag") { try session.perform("Invalid") { $0.items[0].richText!.runs[0].attributes.font.variations = ["+2003265652": 400] } }
            expectThrows("rich ranges on image") { try session.perform("Invalid") { $0.items[0].kind = .rectangle } }
            expect(session.document == before && (try! Data(contentsOf: file(directory, before.id))) == bytes, "Rejected rich mutations preserve published model and original bytes")
            var legacy = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            var items = legacy["items"] as! [[String: Any]]; items[0].removeValue(forKey: "richText"); legacy["items"] = items
            try JSONSerialization.data(withJSONObject: legacy).write(to: file(directory, before.id))
            expect(try! EaselStore(directory: directory).load(before.id).document.items[0].richText == nil, "Legacy text documents decode without migration or invented runs")
        }
    }

    @MainActor static func canvasTransactions() throws {
        try withDirectory { directory in
            let store = try EaselStore(directory: directory)
            let session = try store.create()
            let asset = try session.importPNG(png)
            let a = EaselItem(kind: .text, frame: .init(x: 10, y: 20, width: 60, height: 50), zIndex: 2, text: "Original")
            let b = EaselItem(kind: .image, frame: .init(x: 100, y: 120, width: 80, height: 50), zIndex: 5, assetID: asset)
            let c = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 300, width: 50, height: 50))
            try session.perform("Add") { $0.items = [a, b, c] }
            let ids: Set<UUID> = [a.id, b.id]
            let edit = EaselGeometryEdit(document: session.document, selection: ids)!
            let move = edit.translated(x: -40, y: -50)
            expect(move[0].frame.x == 0 && move[1].frame.x == 90, "Group clamp preserves horizontal spacing")
            expect(move[0].frame.y == 0 && move[1].frame.y == 100, "Group clamp preserves vertical spacing")
            expect(move.map(\.id) == [a.id, b.id], "Movement retains original identity/order")
            try session.perform("Other window") { $0.items[0].text = "Concurrent text"; $0.items[2].color = "#112233" }
            expect(edit.isCurrent(in: session.document), "Content-only changes preserve geometry lease")
            try session.perform("Move originals") { $0 = edit.applying(move, to: $0)! }
            expect(session.document.items[0].text == "Concurrent text" && session.document.items[2].color == "#112233", "Original geometry merge preserves latest content and unrelated object")
            expect(!edit.isCurrent(in: session.document), "Committed move expires its baseline")
            let reopened = try EaselStore(directory: directory).load(session.document.id)
            expect(reopened.document.items == session.document.items, "Group move persists actual original objects")
            try session.undo()
            expect(session.document.items[0].frame == a.frame && session.document.items[0].text == "Concurrent text", "One undo restores geometry without undoing other-window text")
            var external = session.document; external.items[1].frame.x += 1
            expect(!edit.isCurrent(in: external) && edit.applying(move, to: external) == nil, "One moved member refuses whole original group")
            external = session.document; external.items.remove(at: 1)
            expect(edit.applying(move, to: external) == nil, "Removed selected member is never recreated")
            external = session.document; external.id = UUID()
            expect(edit.applying(move, to: external) == nil, "Geometry cannot cross documents")
            expect(EaselGeometryEdit(document: session.document, selection: [UUID()]) == nil, "Missing IDs refuse admission")
            let backwards = EaselCanvasSelection.marquee(from: .init(x: 200, y: 200), to: .init(x: 0, y: 0))
            expect(backwards == .init(x: 0, y: 0, width: 200, height: 200), "Marquee normalizes reverse drag")
            expect(EaselCanvasSelection.selecting(in: backwards, items: session.document.items, original: [c.id], operation: .replace) == ids, "Marquee replaces with original intersecting IDs")
            expect(EaselCanvasSelection.selecting(in: backwards, items: session.document.items, original: [c.id, UUID()], operation: .add) == [a.id, b.id, c.id], "Shift unions hits and drops unavailable IDs")
            expect(EaselCanvasSelection.selecting(in: backwards, items: session.document.items, original: [a.id, c.id], operation: .subtract) == [c.id], "Command subtracts hits without toggling unselected objects")
            let empty = EaselRect(x: 0, y: 0, width: 0, height: 0)
            expect(EaselCanvasSelection.selecting(in: empty, items: session.document.items, original: ids, operation: .replace).isEmpty, "Clicking empty canvas clears only on commit")
            let command = EaselObjectCommand(document: session.document, selection: ids)!
            let copies = command.duplicates(in: session.document)!
            expect(Set(copies.map(\.id)).isDisjoint(with: ids) && Set(copies.map(\.id)).count == 2, "Duplicates have new distinct original-object identities")
            expect(copies[0].frame.x == a.frame.x + 24 && copies[1].frame.x - copies[0].frame.x == b.frame.x - a.frame.x, "Duplicate keeps relative geometry and existing point offset")
            expect(copies[1].assetID == asset && copies[0].text == "Concurrent text", "Duplicate carries exact source image/text payload")
            expect(copies.map(\.zIndex) == [6, 7], "Duplicate selected order is above existing objects")
            try session.perform("Duplicate originals") { $0.items.append(contentsOf: copies) }
            expect(try! Data(contentsOf: session.assetURL(copies[1].assetID!)) == png, "Duplicate image references real original asset bytes")
            try session.undo(); expect(session.document.items.count == 3, "Single undo removes complete duplicate group")
            try session.redo(); expect(Array(session.document.items.suffix(2)).map(\.id) == copies.map(\.id), "Redo restores exact duplicate UUIDs")
            external = session.document; external.items[0].text = "Changed after menu"
            expect(command.duplicates(in: external) == nil, "Stale original-object command cannot copy replacement content")
            let beforeFailure = session.document, url = file(directory, session.document.id)
            try FileManager.default.removeItem(at: url); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            expectThrows("duplicate write failure") { try session.perform("Duplicate") { $0.items.append(contentsOf: command.duplicates(in: $0)!) } }
            expect(session.document == beforeFailure, "Failed duplicate does not publish objects or lose original selection target")
        }
    }

    @MainActor static func groupResizeTransactions() throws {
        try withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(png)
            let text = EaselItem(kind: .text, frame: .init(x: 100, y: 100, width: 100, height: 50), zIndex: 8, text: "Unscaled text", textStyle: .init(family: .fancy, size: .h1))
            let image = EaselItem(kind: .image, frame: .init(x: 300, y: 200, width: 100, height: 50), zIndex: 9, assetID: asset)
            try session.perform("Seed resize") { $0.items = [text, image] }
            let edit = EaselGeometryEdit(document: session.document, selection: [text.id, image.id])!
            expect(edit.bounds == .init(x: 100, y: 100, width: 300, height: 150), "Original group bounds include gaps between members")
            func close(_ a: EaselRect?, _ b: EaselRect) -> Bool {
                guard let a else { return false }
                return zip([a.x, a.y, a.width, a.height], [b.x, b.y, b.width, b.height]).allSatisfy { abs($0 - $1) < 0.000001 }
            }
            let expected: [EaselRect] = [
                .init(x: 120, y: 130, width: 280, height: 120), .init(x: 100, y: 130, width: 320, height: 120),
                .init(x: 120, y: 100, width: 280, height: 180), .init(x: 100, y: 100, width: 320, height: 180),
                .init(x: 100, y: 130, width: 300, height: 120), .init(x: 120, y: 100, width: 280, height: 150),
                .init(x: 100, y: 100, width: 300, height: 180), .init(x: 100, y: 100, width: 320, height: 150)]
            for handle in EaselResizeHandle.allCases {
                let proposal = edit.resized(using: handle, x: 20, y: 30, centered: false)!
                expect(close(EaselGeometryEdit.bounds(of: proposal), expected[handle.rawValue]), "Each control point changes only its original edges: \(handle)")
            }
            let enlarged = edit.resized(using: .bottomRight, x: 150, y: 150, centered: false)!
            expect(enlarged[0].frame == .init(x: 100, y: 100, width: 150, height: 100) && enlarged[1].frame == .init(x: 400, y: 300, width: 150, height: 100), "Original group transform preserves proportional gaps and individual frames")
            expect(enlarged[0].id == text.id && enlarged[1].id == image.id && enlarged[0].textStyle == text.textStyle && enlarged[1].assetID == asset && enlarged.map(\.zIndex) == [8, 9], "Resize preserves identity, text font, image asset and stacking")
            let centered = edit.resized(using: .bottomRight, x: 50, y: 25, centered: true)!
            expect(close(EaselGeometryEdit.bounds(of: centered), .init(x: 50, y: 75, width: 400, height: 200)), "Option grows from the original group center")
            let crossed = edit.resized(using: .left, x: 360, y: 20, centered: false)!
            expect(crossed[0].frame.x == 440 && crossed[1].frame.x == 400 && crossed[0].frame.width == 20 && crossed[0].frame.y == 100, "Crossed left handle reflects original member arrangement and ignores vertical input")
            let centeredCross = edit.resized(using: .right, x: -200, y: 0, centered: true)!
            expect(centeredCross[0].frame.x == 200, "Recovered center-resize crossing flag uses original width, not half-width sign")
            expect(edit.resized(using: .bottomRight, x: 0, y: 0, centered: false) == edit.originals, "Pointer reversal computes from originals without accumulated drift")
            expect(edit.resized(using: .left, x: 300, y: 0, centered: false) == nil, "Zero-width proposal refuses entire group")
            expect(edit.resized(using: .left, x: 299, y: 0, centered: false) == nil, "Sub-point member refuses without individually clamping or distorting spacing")
            expect(edit.resized(using: .topLeft, x: -200, y: -200, centered: false) == nil, "Off-canvas group proposal does not lose original objects beyond the point canvas")
            expect(edit.resized(using: .right, x: .infinity, y: 0, centered: false) == nil, "Nonfinite pointer input refuses before durable mutation")
            try session.perform("Other owner text") { $0.items[0].text = "Concurrent text" }
            try session.perform("Resize original group") { $0 = edit.applying(enlarged, to: $0)! }
            expect(session.document.items[0].text == "Concurrent text" && session.document.items[1].assetID == asset, "Real resize transaction merges current content without replacement")
            let reopened = try EaselStore(directory: directory).load(session.document.id)
            expect(reopened.document.items == session.document.items, "Actual group resize round trips through durable store")
            expect(try! Data(contentsOf: session.assetURL(asset)) == png, "Resize leaves exact source PNG bytes intact")
            try session.undo()
            expect(session.document.items[0].frame == text.frame && session.document.items[0].text == "Concurrent text", "One undo restores all original frames and preserves prior content edit")
            try session.redo(); expect(session.document.items[1].frame == enlarged[1].frame, "One redo restores actual original-image geometry")
            try session.undo()
            var changed = session.document; changed.items[1].frame.width += 1
            expect(edit.applying(enlarged, to: changed) == nil, "Concurrent member resize refuses whole old group proposal")
            let fileURL = file(directory, session.document.id), before = session.document
            try FileManager.default.removeItem(at: fileURL); try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
            expectThrows("group resize save failure") { try session.perform("Resize") { $0 = edit.applying(enlarged, to: $0)! } }
            expect(session.document == before, "Failed group resize preserves all original published frames")
        }
        var freehand = EaselItem(kind: .freehand, frame: .init(x: 100, y: 100, width: 100, height: 100), points: [.init(x: 0, y: 10), .init(x: 100, y: 90)])
        var document = EaselDocument(id: UUID(), title: "Paths", createdAt: Date(), modifiedAt: Date()); document.items = [freehand]
        let reflected = EaselGeometryEdit(document: document, selection: [freehand.id])!.resized(using: .right, x: -150, y: 0, centered: false)!
        expect(reflected[0].points == [.init(x: 50, y: 10), .init(x: 0, y: 90)], "Crossing mirrors normalized freehand points inside their resized original frame")
        freehand.kind = .arrow; document.items = [freehand]
        let arrow = EaselGeometryEdit(document: document, selection: [freehand.id])!.resized(using: .right, x: -150, y: 0, centered: false)!
        expect(arrow[0].points == [.init(x: 0, y: 10), .init(x: 50, y: 90)], "Frame control preserves arrow payload direction while adapting local point size")
        expect(EaselResizeHandle.topLeft.hitRect(in: .init(x: 20, y: 20, width: 10, height: 10)) == .init(x: 10, y: 10, width: 20, height: 20), "Small group retains original corner hit region")
        expect(EaselResizeHandle.right.hitRect(in: .init(x: 20, y: 20, width: 29, height: 100)) == nil, "Edge strip hides below recovered minimum dimensions")
        expect(EaselResizeHandle.top.hitRect(in: .init(x: 20, y: 20, width: 100, height: 30)) == .init(x: 30, y: 15, width: 80, height: 10), "Edge strip spans original edge excluding corner regions")
        let scaledFrame = EaselRect(x: 20, y: 20, width: 100, height: 30)
        expect(EaselResizeHandle.topLeft.hitRect(in: scaledFrame, scale: 2) == .init(x: 15, y: 15, width: 10, height: 10), "Zoomed corners retain a twenty-screen-point target")
        expect(EaselResizeHandle.top.hitRect(in: scaledFrame, scale: 2) == .init(x: 25, y: 17.5, width: 90, height: 5), "Zoomed edge excludes the screen-sized corner targets")
        expect(EaselResizeHandle.top.hitRect(in: scaledFrame, scale: 0.5) == nil, "Edge eligibility uses screen dimensions while zoomed out")
        expect(EaselResizeHandle.topLeft.hitRect(in: scaledFrame, scale: 0) == nil && EaselResizeHandle.left.hitRect(in: scaledFrame, scale: .nan) == nil, "Invalid zoom cannot create nonfinite native targets")
    }

    @MainActor static func canvasHitAndGuides() {
        let r = EaselRect(x: 100, y: 100, width: 100, height: 100)
        let circle = EaselItem(kind: .circle, frame: r)
        expect(!EaselContentHitTest.contains(.init(x: 102, y: 102), item: circle, selected: false), "Unselected ellipse rejects transparent bounding-box corner")
        expect(EaselContentHitTest.contains(.init(x: 150, y: 150), item: circle, selected: false), "Ellipse accepts filled center")
        expect(EaselContentHitTest.contains(.init(x: 102, y: 102), item: circle, selected: true), "Selected shape preserves rectangular manipulation target")
        expect(!EaselContentHitTest.intersects(.init(x: 100, y: 100, width: 4, height: 4), item: circle, selected: false), "Marquee rejects ellipse empty corner")
        expect(EaselContentHitTest.intersects(.init(x: 145, y: 145, width: 10, height: 10), item: circle, selected: false), "Marquee accepts filled ellipse intersection")
        let tiny = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 4, height: 4))
        expect(EaselContentHitTest.contains(.init(x: 90, y: 102), item: tiny, selected: false), "Small object has centered 30-point target")
        expect(!EaselContentHitTest.contains(.init(x: 86, y: 102), item: tiny, selected: false), "Small object target is bounded")
        expect(!EaselContentHitTest.contains(.init(x: 90, y: 102), item: tiny, selected: false, scale: 2), "Minimum target remains screen-scaled")
        let arrow = EaselItem(kind: .arrow, frame: r, points: [.init(x: 0, y: 100), .init(x: 100, y: 0)])
        expect(!EaselContentHitTest.contains(.init(x: 110, y: 110), item: arrow, selected: false), "Arrow rejects empty bounding area")
        expect(EaselContentHitTest.contains(.init(x: 150, y: 160), item: arrow, selected: false), "Arrow uses 30-point round stroke hit region")
        expect(!EaselContentHitTest.intersects(.init(x: 105, y: 105, width: 15, height: 15), item: arrow, selected: false), "Arrow marquee rejects empty bounds")
        expect(EaselContentHitTest.intersects(.init(x: 145, y: 145, width: 10, height: 10), item: arrow, selected: false), "Arrow marquee detects segment crossing without contained endpoint")
        let stroke = EaselItem(kind: .freehand, frame: r, points: [.init(x: 0, y: 0), .init(x: 100, y: 100)])
        expect(!EaselContentHitTest.intersects(.init(x: 145, y: 145, width: 10, height: 10), item: stroke, selected: false), "Original freehand marquee is stored-sample based")
        expect(EaselContentHitTest.intersects(.init(x: 95, y: 95, width: 10, height: 10), item: stroke, selected: false), "Freehand marquee accepts contained original sample")
        expect(EaselContentHitTest.intersects(.init(x: 145, y: 145, width: 10, height: 10), item: stroke, selected: true), "Selected stroke retains group rectangle selection")
        let a = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 60, height: 40))
        let b = EaselItem(kind: .rectangle, frame: .init(x: 180, y: 100, width: 60, height: 40))
        let target = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 100, width: 140, height: 40))
        var doc = EaselDocument(id: UUID(), title: "Guides", createdAt: Date(), modifiedAt: Date(), items: []); doc.items = [a, b, target]
        let edit = EaselGeometryEdit(document: doc, selection: [a.id, b.id])!
        let viewport = EaselRect(x: 0, y: 0, width: 1000, height: 1000)
        func solver() -> EaselAlignmentGuides { .init(edit: edit, items: doc.items, viewport: viewport, canvasWidth: 1000) }
        var guides = solver()
        let aligned = guides.proposal(edit: edit, document: doc, translation: .init(x: 195, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)!
        expect(aligned[0].frame.x == 300 && aligned[1].frame.x == 380, "Guide correction translates original group without changing spacing")
        expect(!guides.lines.isEmpty && aligned.map(\.id) == [a.id, b.id], "Active guides preserve original identities")
        guides = solver()
        let fast = guides.proposal(edit: edit, document: doc, translation: .init(x: 195, y: 0), velocity: .init(x: 1000, y: 0), handle: nil, centered: false, enabled: true)!
        expect(fast[0].frame.x == 295, "Fast motion does not acquire a new horizontal snap")
        let suppressed = guides.proposal(edit: edit, document: doc, translation: .init(x: 195, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: false)!
        expect(suppressed[0].frame.x == 295 && guides.lines.isEmpty, "Command/toggle suppression clears snap state and preserves actual pointer proposal")
        guides = solver(); var changed = doc; changed.items[2].frame.x += 1
        let stale = guides.proposal(edit: edit, document: changed, translation: .init(x: 195, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)!
        expect(stale[0].frame.x == 295 && guides.lines.isEmpty, "A changed target frame cannot retain an old guide")
        var wrong = doc; wrong.id = UUID()
        expect(guides.proposal(edit: edit, document: wrong, translation: .init(x: 195, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true) == nil, "Solver rejects replaced original document")
        let gap = guides.proposal(edit: edit, document: doc, translation: .init(x: 40, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)!
        expect(abs(gap[1].frame.x + gap[1].frame.width - 276) < 0.001, "Adjacent objects acquire recovered 24-point separation")
        let offscreen = EaselRect(x: 0, y: 0, width: 250, height: 1000)
        guides = solver()
        let hidden = guides.proposal(edit: edit, document: doc, translation: .init(x: 195, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true, viewport: offscreen)!
        expect(hidden[0].frame.x == 295 && guides.lines.isEmpty, "Offscreen target does not provide visible guides")
        doc.items[2].frame.height = 600; guides = solver()
        _ = guides.proposal(edit: edit, document: doc, translation: .init(x: 195, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)
        let sticky = guides.proposal(edit: edit, document: doc, translation: .init(x: 191, y: 200), velocity: .init(x: 1000, y: 1000), handle: nil, centered: false, enabled: true)!
        expect(sticky[0].frame.x == 300, "Acquired guide uses perpendicular-travel hysteresis without new-snap velocity gate")
        let released = guides.proposal(edit: edit, document: doc, translation: .init(x: 170, y: 200), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)!
        expect(released[0].frame.x == 270, "Pointer beyond bounded hysteresis releases acquired guide")
        doc.items[2].frame = .init(x: 100, y: 170, width: 300, height: 40); guides = solver()
        let resized = guides.proposal(edit: edit, document: doc, translation: .init(x: 155, y: 0), velocity: .init(x: 0, y: 0), handle: .right, centered: false, enabled: true)!
        expect(abs(EaselGeometryEdit.bounds(of: resized)!.width - 300) < 0.001, "Resize correction goes through original group control point")
        expect(resized[0].id == a.id && resized[1].id == b.id && resized[0].frame.y == 100, "Resize guides preserve exact members and inactive axis")
    }

    @MainActor static func directControls() throws {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.000001 }
        let arrow = EaselItem(kind: .arrow, frame: .init(x: 100, y: 100, width: 100, height: 80),
                              points: [.init(x: 0, y: 0), .init(x: 100, y: 80)])
        var document = EaselDocument(id: UUID(), title: "Direct controls", createdAt: Date(), modifiedAt: Date()); document.items = [arrow]
        let edit = EaselGeometryEdit(document: document, selection: [arrow.id])!
        expect(EaselArrowEndpoint.end.hitRect(in: arrow, scale: 2) == .init(x: 195, y: 175, width: 10, height: 10) &&
               EaselArrowEndpoint.end.hitRect(in: arrow, scale: 0) == nil,
               "Endpoint pointer target retains twenty screen points under magnification and refuses invalid scale")
        let moved = edit.movingEndpoint(.start, x: 150, y: 120)![0]
        expect(moved.id == arrow.id && moved.frame == .init(x: 200, y: 180, width: 50, height: 40), "Endpoint crossing rebases original arrow without replacing identity")
        expect(EaselArrowEndpoint.start.point(in: moved) == .init(x: 250, y: 220) && EaselArrowEndpoint.end.point(in: moved) == .init(x: 200, y: 180), "Crossing preserves actual stationary endpoint and original start/end direction")
        let flat = edit.movingEndpoint(.end, x: 0, y: -80)![0]
        expect(flat.frame.height == 1 && flat.points.map(\.y) == [0, 0], "Flat arrow retains exact rendered endpoints within durable minimum frame")
        let collapsed = edit.movingEndpoint(.end, x: -100, y: -80)![0]
        expect(collapsed.frame.width == 1 && collapsed.frame.height == 1 && collapsed.points[0] == collapsed.points[1], "Coincident endpoint proposal remains representable and reversible from originals")
        expect(edit.movingEndpoint(.end, x: .infinity, y: 0) == nil && edit.movingEndpoint(.start, x: -101, y: 0) == nil, "Unsafe endpoint proposals refuse atomically")
        let endpointTarget = EaselItem(kind: .rectangle, frame: .init(x: 250, y: 220, width: 20, height: 60))
        document.items = [arrow, endpointTarget]
        var endpointGuides = EaselAlignmentGuides(edit: edit, items: document.items,
            viewport: .init(x: 0, y: 0, width: 800, height: 600), canvasWidth: 800)
        let exactEndpoint = endpointGuides.proposal(edit: edit, document: document, translation: .init(x: 70, y: 30),
            velocity: .init(x: 0, y: 0), handle: nil, centered: true, enabled: true, preserveAspect: true, endpoint: .end)![0]
        expect(exactEndpoint == edit.movingEndpoint(.end, x: 70, y: 30)![0], "Endpoint alignment never adopts frame centering or aspect constraints")
        let endpointLine = endpointGuides.lines.first { $0.anchor == .right && $0.coordinate == 270 }!
        expect(endpointLine.targetSegments == [.init(start: .init(x: 270, y: 88), end: .init(x: 270, y: 292))] &&
               endpointLine.anchorSegments == [.init(start: .init(x: 270, y: 100), end: .init(x: 270, y: 210))],
               "Exact endpoint alignment highlights the target extent and actual moving edge separately")
        let nearbyEndpoint = endpointGuides.proposal(edit: edit, document: document, translation: .init(x: 68, y: 30),
            velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true, endpoint: .end)![0]
        expect(nearbyEndpoint == edit.movingEndpoint(.end, x: 68, y: 30)![0] && endpointGuides.lines.isEmpty,
               "Endpoint refuses nonzero correction and retires the previously exact guide")
        _ = endpointGuides.proposal(edit: edit, document: document, translation: .init(x: 70, y: 30),
            velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: false, endpoint: .end)
        expect(endpointGuides.lines.isEmpty, "Command or disabled guides suppress exact endpoint feedback")
        var changedEndpointTarget = document; changedEndpointTarget.items[1].frame.x += 2
        _ = endpointGuides.proposal(edit: edit, document: changedEndpointTarget, translation: .init(x: 70, y: 30),
            velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true, endpoint: .end)
        expect(endpointGuides.lines.isEmpty, "Changed original target cannot supply stale endpoint feedback")
        var polyline = arrow; polyline.points.append(.init(x: 50, y: 50)); document.items = [polyline]
        expect(EaselGeometryEdit(document: document, selection: [arrow.id])!.movingEndpoint(.start, x: 1, y: 1) == nil, "Unsupported multipoint arrow is preserved instead of flattened")
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: "original.png")
        document.items = [image]
        let ie = EaselGeometryEdit(document: document, selection: [image.id])!
        expect(ie.preservesAspect(shift: false, command: false) && !ie.preservesAspect(shift: true, command: true), "Original image policy preserves aspect by default with Command precedence")
        let projected = ie.resizedPreservingAspect(using: .bottomRight, x: 100, y: 0, centering: [])![0]
        expect(near(projected.frame.width, 280) && near(projected.frame.height, 140) && projected.frame.x == 100 && projected.frame.y == 100, "Corner uses orthogonal original-ratio diagonal projection, not max-axis scaling")
        expect(projected.id == image.id && projected.assetID == image.assetID, "Aspect geometry preserves original image identity and pixels")
        let crossing = ie.resizedPreservingAspect(using: .bottomRight, x: -300, y: -180, centering: [])![0]
        expect(near(crossing.frame.width / crossing.frame.height, 2) && crossing.assetID == image.assetID, "Crossing retains original ratio and unmirrored image payload")
        let recovered = ie.resizedPreservingAspect(using: .bottomRight, x: 100, y: -100, centering: [])![0]
        expect(recovered.frame.width > 1 && near(recovered.frame.width / recovered.frame.height, 2), "Aspect correction precedes final durable validation even at a zero-height plain intermediate")
        let side = ie.resizedPreservingAspect(using: .right, x: 100, y: 0, centering: [])![0]
        expect(side.frame == .init(x: 100, y: 75, width: 300, height: 150), "Horizontal edge derives height around the proposed midpoint")
        let top = ie.resizedPreservingAspect(using: .top, x: 0, y: -50, centering: [])![0]
        expect(top.frame == .init(x: 50, y: 50, width: 300, height: 150), "Vertical edge derives width around the proposed midpoint")
        let centered = ie.resizedPreservingAspect(using: .bottomRight, x: 20, y: 50, centering: .both)![0]
        expect(centered.frame == .init(x: 80, y: 90, width: 240, height: 120), "Centered corner derives original-ratio height from width and keeps both centers")
        let xCentered = ie.resizedPreservingAspect(using: .bottomRight, x: 20, y: 50, centering: .horizontal)![0]
        expect(xCentered.frame == .init(x: 80, y: 100, width: 240, height: 120), "One captured horizontal axis preserves opposite vertical edge")
        let yCentered = ie.resizedPreservingAspect(using: .bottomRight, x: 20, y: 50, centering: .vertical)![0]
        expect(near(yCentered.frame.x, 100) && near(yCentered.frame.y, 95) && near(yCentered.frame.width, 220) && near(yCentered.frame.height, 110), "One captured vertical axis preserves opposite horizontal edge")
        var rectangle = image; rectangle.kind = .rectangle; document.items = [rectangle]
        expect(!EaselGeometryEdit(document: document, selection: [rectangle.id])!.preservesAspect(shift: true, command: false), "Single shape retains its actual plain frame control owner")
        var link = image; link.kind = .link; document.items = [link]
        expect(EaselGeometryEdit(document: document, selection: [link.id])!.preservesAspect(shift: false, command: false), "Original link content tag participates in aspect policy")
        let neighbor = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 220, width: 50, height: 60))
        document.items = [image, neighbor]
        var guides = EaselAlignmentGuides(edit: ie, items: document.items,
            viewport: .init(x: 0, y: 0, width: 800, height: 600), canvasWidth: 800)
        let aligned = guides.proposal(edit: ie, document: document, translation: .init(x: 48, y: 24),
            velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: true, preserveAspect: true)![0]
        expect(near(aligned.frame.x + aligned.frame.width, 350) && near(aligned.frame.width / aligned.frame.height, 2), "Aspect corner guide couples both deltas and preserves the original frame ratio")
        expect(guides.lines.contains { $0.anchor == .right && near($0.coordinate, 350) }, "Aspect guide is shown only on the final actual aligned frame")
        guides = EaselAlignmentGuides(edit: ie, items: document.items,
            viewport: .init(x: 0, y: 0, width: 800, height: 600), canvasWidth: 800)
        let intrinsic = guides.proposal(edit: ie, document: document, translation: .init(x: 48, y: 24),
            velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: true,
            preserveAspect: true, aspectGuideRatio: 1)![0]
        expect(near(intrinsic.frame.width, 250.4) && near(intrinsic.frame.width / intrinsic.frame.height, 2), "Shift intrinsic guide ratio affects correction without replacing original frame ratio")
        let second = EaselItem(kind: .rectangle, frame: .init(x: 400, y: 300, width: 100, height: 100))
        document.items = [rectangle, second]
        let group = EaselGeometryEdit(document: document, selection: [rectangle.id, second.id])!
        expect(!group.preservesAspect(shift: false, command: false) && group.preservesAspect(shift: true, command: false), "Generic group Shift forces original group ratio")
        document.items = [image, second]
        expect(EaselGeometryEdit(document: document, selection: [image.id, second.id])!.preservesAspect(shift: false, command: false), "Generic group with original image retains aspect by default")
        try withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(png)
            var realImage = image; realImage.assetID = asset
            try session.perform("Seed controls") { $0.items = [arrow, realImage] }
            let ae = EaselGeometryEdit(document: session.document, selection: [arrow.id])!
            try session.perform("Concurrent color") { $0.items[0].color = "#112233" }
            try session.perform("Endpoint") { $0 = ae.applying([moved], to: $0)! }
            expect(session.document.items[0].color == "#112233" && session.document.items[0].points == moved.points, "Endpoint commit preserves concurrent content while updating only original geometry")
            try session.undo(); expect(session.document.items[0].frame == arrow.frame && session.document.items[0].points == arrow.points, "One undo restores both original endpoint and frame")
            try session.redo()
            let reopened = try EaselStore(directory: directory).load(session.document.id)
            expect(reopened.document.items[0].points == moved.points, "Endpoint direction persists through real disk reopen")
            let liveImage = EaselGeometryEdit(document: session.document, selection: [realImage.id])!
            let target = liveImage.resizedPreservingAspect(using: .bottomRight, x: 100, y: 0, centering: [])!
            try session.perform("Image aspect") { $0 = liveImage.applying(target, to: $0)! }
            expect(try! Data(contentsOf: session.assetURL(asset)) == png && session.document.items[1].assetID == asset, "Real aspect resize leaves original imported image bytes unchanged")
        }
    }

    @MainActor static func canvasAnchors() {
        let viewport = EaselRect(x: 0, y: 0, width: 1000, height: 1000)
        let item = EaselItem(kind: .rectangle, frame: .init(x: 450, y: 100, width: 100, height: 100))
        var doc = EaselDocument(id: UUID(), title: "Original anchors", createdAt: Date(), modifiedAt: Date(), items: [item])
        var edit = EaselGeometryEdit(document: doc, selection: [item.id])!
        func make(_ source: EaselDocument, _ original: EaselGeometryEdit) -> EaselAlignmentGuides {
            .init(edit: original, items: source.items, viewport: viewport, canvasWidth: 1000)
        }
        var guides = make(doc, edit)
        expect(guides.activeAtDragBegin == [.centerX], "Canvas producer captures only exact horizontal center, with no invented vertical canvas anchor")
        let centered = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: true)![0].frame
        expect(centered == .init(x: 430, y: 100, width: 140, height: 130), "Captured canvas center expands horizontal axis only")
        expect(guides.lines.contains { $0.anchor == .centerX && $0.coordinate == 500 }, "Exact fixed center retains real active guide during resize")
        let centerLine = guides.lines.first { $0.anchor == .centerX }!
        expect(centerLine.targetSegments.count == 2 && centerLine.anchorSegments.count == 4 &&
               centerLine.targetSegments[0].end.y < centered.y && centerLine.targetSegments[1].start.y > centered.y + centered.height,
               "Center feedback splits the pale path outside the moving object and supplies four cross-mark segments")
        let command = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false)![0].frame
        expect(command == centered && guides.lines.isEmpty, "Command suppresses correction and lines, not original captured axis centering")
        let option = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: true, enabled: false)![0].frame
        expect(option == .init(x: 430, y: 70, width: 140, height: 160), "Option adds vertical centering to captured horizontal center")
        let released = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false)![0].frame
        expect(released == centered, "Releasing Option resumes exact captured axes from originals")
        expect(guides.matchesCanvas(width: 1000) && !guides.matchesCanvas(width: 1001), "Canvas coordinate owner is exact and cannot silently retarget original anchors")
        let moved = guides.proposal(edit: edit, document: doc, translation: .init(x: 40, y: 20), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: false)![0].frame
        expect(moved == .init(x: 490, y: 120, width: 100, height: 100), "Captured centers do not turn body move into a resize")
        doc.items[0].frame.x += 0.01; edit = EaselGeometryEdit(document: doc, selection: [item.id])!; guides = make(doc, edit)
        expect(!guides.activeAtDragBegin.contains(.centerX), "Nearby center within snap radius is not an exact drag-begin anchor")
        let fresh = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false)![0].frame
        expect(fresh.x == 450.01 && fresh.width == 120, "New gesture recomputes anchors rather than retaining prior canvas session")
        doc.items[0].frame = .init(x: 100, y: 100, width: 100, height: 100)
        edit = EaselGeometryEdit(document: doc, selection: [item.id])!; guides = make(doc, edit)
        let left = guides.proposal(edit: edit, document: doc, translation: .init(x: -55, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)![0].frame
        expect(abs(left.x - 42) < 0.000001, "Canvas left margin is recovered 42/1000 logical width")
        guides = make(doc, edit)
        let right = guides.proposal(edit: edit, document: doc, translation: .init(x: 755, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)![0].frame
        expect(abs(right.x + right.width - 958) < 0.000001, "Canvas right margin is symmetric 42/1000 logical width")
        guides = make(doc, edit)
        let fast = guides.proposal(edit: edit, document: doc, translation: .init(x: -55, y: 0), velocity: .init(x: 1000, y: 0), handle: nil, centered: false, enabled: true)![0].frame
        expect(fast.x == 45 && guides.lines.isEmpty, "Canvas guides share real new-snap velocity policy")
        guides = make(doc, edit)
        let vertical = guides.proposal(edit: edit, document: doc, translation: .init(x: 0, y: -55), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)![0].frame
        expect(vertical.y == 45 && guides.lines.isEmpty, "No speculative top or bottom canvas margin is introduced")
        let neighbor = EaselItem(kind: .rectangle, frame: .init(x: 220, y: 125, width: 100, height: 50))
        doc.items.append(neighbor); guides = make(doc, edit)
        expect(guides.activeAtDragBegin.contains(.centerY) && !guides.activeAtDragBegin.contains(.centerX), "Exact original neighbor center captures vertical axis independently")
        let neighborCentered = guides.proposal(edit: edit, document: doc, translation: .init(x: 10, y: 20), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false)![0].frame
        expect(abs(neighborCentered.x - 100) < 0.000001 && abs(neighborCentered.y - 80) < 0.000001 &&
               abs(neighborCentered.width - 110) < 0.000001 && abs(neighborCentered.height - 140) < 0.000001, "Original neighbor center keeps vertical symmetry without horizontal centering")
        doc.items[1].frame.y += 10
        let snapshot = guides.proposal(edit: edit, document: doc, translation: .init(x: 10, y: 20), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false)![0].frame
        expect(snapshot == neighborCentered, "Drag-begin center remains original geometry policy even when a later target changes")
        guides = make(doc, edit)
        expect(!guides.activeAtDragBegin.contains(.centerY), "Next gesture does not inherit changed neighbor alignment")
        var wrong = doc; wrong.id = UUID()
        expect(guides.proposal(edit: edit, document: wrong, translation: .init(x: 10, y: 20), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false) == nil, "Captured axis cannot cross original document identity")
        doc.items = [item, EaselItem(kind: .rectangle, frame: .init(x: 450, y: 240, width: 100, height: 100))]
        edit = EaselGeometryEdit(document: doc, selection: Set(doc.items.map(\.id)))!; guides = make(doc, edit)
        let group = guides.proposal(edit: edit, document: doc, translation: .init(x: 25, y: 0), velocity: .init(x: 0, y: 0), handle: .right, centered: false, enabled: false)!
        expect(group.allSatisfy { $0.frame.x == 425 && $0.frame.width == 150 } && group.map(\.id) == doc.items.map(\.id), "Captured canvas center transforms exact original group members together")
    }

    @MainActor static func browserObjectOwnership() throws {
        try withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let browser = EaselItem(kind: .browser, frame: frame, url: "https://example.com/authored")
            try session.perform("Add webpage") { $0.items = [browser] }
            expect(try! EaselStore(directory: directory).load(session.document.id).document.items == [browser], "Actual browser object persists original identity and authored URL")
            var live = true
            let guardID = session.observeReplacement { next in
                !live || next?.items.contains { $0.id == browser.id && $0.kind == .browser && $0.url == browser.url } == true
            }
            let original = session.document
            expectThrows("Live page prevents object deletion") { try session.perform("Delete") { $0.items = [] } }
            expectThrows("Live page prevents destructive URL replacement") { try session.perform("URL") { $0.items[0].url = "https://example.org/" } }
            expectThrows("Live page prevents document deletion") { try store.delete(original.id) }
            expectThrows("Undo cannot bypass actual page retirement") { try session.undo() }
            expect(session.document == original && session.canUndo && !session.canRedo, "Refused retirement leaves exact document and history unchanged")
            expect(try! EaselStore(directory: directory).load(original.id).document == original, "Refused retirement leaves durable bytes semantically unchanged")
            try session.perform("Move same page") { $0.items[0].frame.x += 20 }
            expect(session.document.items[0].id == browser.id && session.document.items[0].url == browser.url, "Geometry editing keeps live original identity and URL")
            try session.undo()
            expect(session.document.items == [browser], "Non-destructive undo remains usable while page is live")
            live = false
            try session.undo()
            expect(session.document.items.isEmpty && session.canRedo, "Actual closure permits pending creation undo")
            try session.redo()
            expect(session.document.items == [browser], "Redo restores durable original without inventing live runtime identity")
            session.removeReplacementObserver(guardID)
            live = true
            try store.delete(original.id)
            expect(try! store.list().isEmpty, "Retired observer no longer blocks document deletion")
        }
    }

    @MainActor static func browserNavigationMetadata() throws {
        try withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let item = EaselItem(kind: .browser, frame: frame, url: "https://example.com/start")
            try session.perform("Add webpage") { $0.items.append(item) }
            try session.perform("Move webpage") { $0.items[0].frame.x += 40 }
            let token = session.observeReplacement { next in
                guard let next = next?.items.first(where: { $0.id == item.id && $0.kind == .browser }), let url = next.url else { return false }
                return url == session.document.items[0].url || session.isRecordingBrowserNavigation(item.id, from: session.document.items[0].url!, to: url)
            }
            expect(try! session.recordBrowserNavigation(URL(string: "https://example.com/actual")!, itemID: item.id, expectedURL: item.url!), "Actual URL updates original browser metadata")
            expect(session.document.items[0].id == item.id && session.document.items[0].frame.x == frame.x + 40, "URL observation preserves exact object geometry and identity")
            expect(!session.isRecordingBrowserNavigation(item.id, from: item.url!, to: "https://example.com/actual"), "Navigation admission scope ends after publication")
            expect(try! EaselStore(directory: directory).load(session.document.id).document.items[0].url == "https://example.com/actual", "Real observed URL survives reopen")
            try session.undo()
            expect(session.document.items[0].frame == frame && session.document.items[0].url == "https://example.com/actual", "Canvas Undo preserves latest real page URL without new navigation step")
            try session.redo()
            expect(session.document.items[0].frame.x == frame.x + 40 && session.document.items[0].url == "https://example.com/actual", "Canvas Redo preserves page URL metadata")
            let before = session.document
            expect(!(try! session.recordBrowserNavigation(URL(string: "https://example.com/stale")!, itemID: item.id, expectedURL: item.url!)), "Stale source URL cannot overwrite original item")
            expect(!(try! session.recordBrowserNavigation(URL(string: "file:///tmp/private")!, itemID: item.id, expectedURL: before.items[0].url!)), "Non-web observation is not persisted as an embedded navigation")
            expect(session.document == before, "Rejected observation preserves complete document")
            expectThrows("Direct replacement does not inherit observation approval") { try session.perform("Replace URL") { $0.items[0].url = "https://other.example/" } }
            let refusal = session.observeReplacement { _ in false }
            expectThrows("Another original page owner can refuse metadata publication") { _ = try session.recordBrowserNavigation(URL(string: "https://example.com/refused")!, itemID: item.id, expectedURL: before.items[0].url!) }
            expect(session.document == before, "Refusal keeps original durable state")
            session.removeReplacementObserver(refusal)
            let documentFile = file(directory, session.document.id)
            try FileManager.default.removeItem(at: documentFile)
            try FileManager.default.createDirectory(at: documentFile, withIntermediateDirectories: false)
            expectThrows("Failed URL save does not publish") { _ = try session.recordBrowserNavigation(URL(string: "https://example.com/failed")!, itemID: item.id, expectedURL: before.items[0].url!) }
            expect(session.document == before && !session.isRecordingBrowserNavigation(item.id, from: before.items[0].url!, to: "https://example.com/failed"), "Failed persistence retires approval and preserves original")
            session.removeReplacementObserver(token)
        }
    }
    @MainActor static func webInputDestinations() {
        expect(EaselWebNavigation.address(" example.com/a?x=1#part ")?.absoluteString == "https://example.com/a?x=1#part", "Address authoring supplies recovered HTTPS prefix")
        expect(EaselWebNavigation.address("http://localhost:8000/a")?.absoluteString == "http://localhost:8000/a", "Explicit ordinary URL preserves original scheme, port and path")
        for input in ["", "a b", "javascript:alert(1)", "file:///tmp/a", "https://user:password@example.com", "https://", "https://example.com\nsecret"] {
            expect(EaselWebNavigation.address(input) == nil, "Invalid or credential-bearing address stays unsubmitted")
        }
        for category in EaselWebNavigation.Category.allCases {
            let draft = EaselWebNavigation.Draft(mode: .search, text: "ice + snow & café?", category: category)
            let url = EaselWebNavigation.destination(draft)!
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            expect(components.host == "duckduckgo.com" && components.queryItems?.first(where: { $0.name == "q" })?.value == draft.text, "Search preserves exact query once for every recovered category")
            expect(!url.absoluteString.contains("t=hc") && url.absoluteString.contains("%2B"), "No copied tracking token; literal plus remains data")
        }
        let maps = URLComponents(url: EaselWebNavigation.destination(.init(mode: .search, text: "Edmonton", category: .maps))!, resolvingAgainstBaseURL: false)!
        expect(maps.queryItems?.first(where: { $0.name == "iaxm" })?.value == "maps", "Maps uses the current official provider route")
        expect(maps.queryItems?.contains(where: { $0.name == "ia" }) == false, "Maps does not inherit the historical News vertical")
        expect(EaselWebNavigation.destination(.init(mode: .search, text: "  ")) == nil, "Empty query does not fabricate a destination")
    }

}
