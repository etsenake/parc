import Foundation
import Testing
@testable import ParcCore

struct EaselStoreTransactionsTests {
    @MainActor @Test
    func committingATransactionUpdatesOnlyTheModificationTime() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            var tick = Date(timeIntervalSince1970: 100)
            let store = try EaselStore(directory: directory, now: { tick })
            let session = try store.create()
            let original = session.document
            tick.addTimeInterval(10)
            try session.perform("Add and rename") {
                $0.title = "Renamed"
                $0.items.append(EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "One"))
                $0.items.append(EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "Two"))
            }
            let committed = session.document
            #expect(committed.modifiedAt == tick && committed.createdAt == original.createdAt, "Transaction updates modification time only")
        }
    }

    @MainActor @Test
    func undoRevertsTheWholeTransactionAndSavesIt() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            var tick = Date(timeIntervalSince1970: 100)
            let store = try EaselStore(directory: directory, now: { tick })
            let session = try store.create()
            let original = session.document
            tick.addTimeInterval(10)
            try session.perform("Add and rename") {
                $0.title = "Renamed"
                $0.items.append(EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "One"))
                $0.items.append(EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "Two"))
            }
            #expect(session.canUndo && !session.canRedo, "Committed transaction enables undo")
            try session.undo()
            #expect(session.document.items.isEmpty && session.document.title == original.title, "One undo reverses whole transaction")
            #expect(!session.canUndo && session.canRedo, "Undo enables redo")
            let diskAfterUndo = try EaselStore(directory: directory).load(original.id)
            #expect(diskAfterUndo.document.items.isEmpty, "Undo is saved durably")
        }
    }

    @MainActor @Test
    func redoRestoresTheObjectIDsAndTitle() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            var tick = Date(timeIntervalSince1970: 100)
            let store = try EaselStore(directory: directory, now: { tick })
            let session = try store.create()
            tick.addTimeInterval(10)
            try session.perform("Add and rename") {
                $0.title = "Renamed"
                $0.items.append(EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "One"))
                $0.items.append(EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "Two"))
            }
            let committed = session.document
            try session.undo()
            try session.redo()
            #expect(session.document.items == committed.items && session.document.title == committed.title, "Redo restores exact object identities")
        }
    }

    @MainActor @Test
    func editingAfterUndoDiscardsTheRedoBranch() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            var tick = Date(timeIntervalSince1970: 100)
            let store = try EaselStore(directory: directory, now: { tick })
            let session = try store.create()
            tick.addTimeInterval(10)
            try session.perform("Add and rename") {
                $0.title = "Renamed"
                $0.items.append(EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "One"))
                $0.items.append(EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "Two"))
            }
            try session.undo()
            try session.perform("Different branch") { $0.title = "Branch" }
            #expect(!session.canRedo, "Editing after undo discards redo branch")
        }
    }

    enum InvalidEdit: CaseIterable {
        case nonfiniteGeometry, negativeSize, duplicateID, scriptURL, fileURL
        case missingEndpoints, invalidColor, blankTitle, changedID, changedCreationDate, changedVersion, thrownMutation
    }

    @MainActor @Test(arguments: InvalidEdit.allCases)
    func aFailedTransactionDoesNotPublishOrChangeTheFile(_ invalid: InvalidEdit) throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let original = session.document
            let path = EaselStoreTestsSupport.file(directory, original.id)
            let bytes = try Data(contentsOf: path)
            #expect(throws: EaselStoreError.self) {
                try session.perform("Invalid edit") { document in
                    switch invalid {
                    case .nonfiniteGeometry:
                        document.items = [EaselItem(kind: .text, frame: .init(x: .nan, y: 0, width: 1, height: 1))]
                    case .negativeSize:
                        document.items = [EaselItem(kind: .text, frame: .init(x: 0, y: 0, width: -2, height: 1))]
                    case .duplicateID:
                        let item = EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame); document.items = [item, item]
                    case .scriptURL:
                        document.items = [EaselItem(kind: .link, frame: EaselStoreTestsSupport.frame, url: "javascript:alert(1)")]
                    case .fileURL:
                        document.items = [EaselItem(kind: .link, frame: EaselStoreTestsSupport.frame, url: "file:///tmp/example")]
                    case .missingEndpoints:
                        document.items = [EaselItem(kind: .arrow, frame: EaselStoreTestsSupport.frame)]
                    case .invalidColor:
                        document.items = [EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, color: "not-a-color")]
                    case .blankTitle:
                        document.title = " \n "
                    case .changedID:
                        document.id = UUID()
                    case .changedCreationDate:
                        document.createdAt = .distantPast
                    case .changedVersion:
                        document.version = 20
                    case .thrownMutation:
                        document.title = "Uncommitted"; throw EaselStoreError.documentTooLarge
                    }
                }
            }
            #expect(session.document == original)
            #expect(!session.canUndo && !session.canRedo)
            #expect(try Data(contentsOf: path) == bytes)
        }
    }

    @MainActor @Test func inlineImagesPersistAndUndoAsOneStep() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let font = EaselRichText.Font(name: "Helvetica", size: 15)
            let image = EaselRichText.Image(data: EaselStoreTestsSupport.png, fileType: "public.png", width: 1, height: 1)
            let attributes = EaselRichText.Attributes(font: font, ink: "#252525FF", image: image)
            let rich = EaselRichText(runs: [.init(location: 0, length: 1, attributes: attributes)])
            let item = EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "\u{FFFC}", richText: rich)
            try session.perform("Inline image") { $0.items.append(item) }
            #expect(session.document.items[0].id == item.id, "Inline persistence retains original text object identity")
            let reopened = try EaselStore(directory: directory).load(session.document.id)
            #expect(reopened.document.items[0].richText == rich, "Inline encoded bytes and range survive actual atomic disk reopen")
            try session.undo(); #expect(session.document.items.isEmpty, "Document undo removes the whole accepted original image insertion")
            try session.redo(); #expect(session.document.items[0].richText?.runs[0].attributes.image?.data == EaselStoreTestsSupport.png, "Document redo restores original bytes")
            var invalid = item; invalid.text = "x"
            EaselStoreTestsSupport.expectThrows("Attachment range must be the actual replacement character") { try session.perform("Wrong range") { $0.items = [invalid] } }
            invalid = item; invalid.richText!.runs[0].length = 2; invalid.text = "\u{FFFC}\u{FFFC}"
            EaselStoreTestsSupport.expectThrows("One image cannot consume multiple native characters") { try session.perform("Wrong span") { $0.items = [invalid] } }
            invalid = item; invalid.richText!.runs[0].attributes.image!.fileType = "public.url"
            EaselStoreTestsSupport.expectThrows("No arbitrary file or URL image carrier") { try session.perform("Unsafe payload") { $0.items = [invalid] } }
            invalid = item; invalid.richText!.runs[0].attributes.image!.width = .infinity
            EaselStoreTestsSupport.expectThrows("Invalid inline dimensions refuse atomically") { try session.perform("Invalid size") { $0.items = [invalid] } }
            #expect(session.document.items[0] == item, "Rejected attachment edits preserve existing original document")
        }
    }
    @MainActor @Test func richTextRangesPersistAndUndoExactly() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let ink = EaselRichText.Attributes(font: .init(name: "Helvetica", size: 18), ink: "#194B93FF", underline: 1, link: "https://example.com")
            let text = "A😀B"
            let rich = EaselRichText(runs: [.init(location: 0, length: 1, attributes: ink), .init(location: 1, length: 2, attributes: ink), .init(location: 3, length: 1, attributes: ink)])
            try session.perform("Add rich text") { $0.items = [EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: text, richText: rich)] }
            let read = try EaselStore(directory: directory).load(session.document.id)
            #expect(read.document.items[0].richText == rich, "Range attributes survive durable document round trip")
            try session.perform("Format selected range") { $0.items[0].richText!.runs[1].attributes.strike = 1 }
            try session.undo()
            #expect(session.document.items[0].richText == rich, "Document undo restores exact rich ranges")
            try session.redo()
            #expect(session.document.items[0].richText!.runs[1].attributes.strike == 1, "Document redo restores selected range")
            let before = session.document, bytes = try Data(contentsOf: EaselStoreTestsSupport.file(directory, before.id))
            EaselStoreTestsSupport.expectThrows("split surrogate pair") { try session.perform("Invalid") { $0.items[0].richText!.runs[0].length = 2; $0.items[0].richText!.runs[1].location = 2; $0.items[0].richText!.runs[1].length = 1 } }
            EaselStoreTestsSupport.expectThrows("range gap") { try session.perform("Invalid") { $0.items[0].richText!.runs.removeLast() } }
            EaselStoreTestsSupport.expectThrows("overflow range") { try session.perform("Invalid") { $0.items[0].richText!.runs[0].length = Int.max } }
            EaselStoreTestsSupport.expectThrows("non-finite font") { try session.perform("Invalid") { $0.items[0].richText!.runs[0].attributes.font.size = .infinity } }
            EaselStoreTestsSupport.expectThrows("unsafe rich link") { try session.perform("Invalid") { $0.items[0].richText!.runs[0].attributes.link = "file:///private/example" } }
            EaselStoreTestsSupport.expectThrows("aliased font axis tags") { try session.perform("Invalid") { $0.items[0].richText!.runs[0].attributes.font.variations = ["1": 1, "01": 2] } }
            EaselStoreTestsSupport.expectThrows("signed font axis tag") { try session.perform("Invalid") { $0.items[0].richText!.runs[0].attributes.font.variations = ["+2003265652": 400] } }
            EaselStoreTestsSupport.expectThrows("rich ranges on a section") { try session.perform("Invalid") { $0.items[0].kind = .section } }
            #expect(session.document == before && (try! Data(contentsOf: EaselStoreTestsSupport.file(directory, before.id))) == bytes, "Rejected rich mutations preserve published model and original bytes")
            var legacy = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            var items = legacy["items"] as! [[String: Any]]; items[0].removeValue(forKey: "richText"); legacy["items"] = items
            try JSONSerialization.data(withJSONObject: legacy).write(to: EaselStoreTestsSupport.file(directory, before.id))
            #expect(try! EaselStore(directory: directory).load(before.id).document.items[0].richText == nil, "Legacy text documents decode without migration or invented runs")
        }
    }

    @MainActor @Test
    func aNewDocumentHasNoHistory() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            #expect(!session.canUndo && !session.canRedo)
        }
    }

    @MainActor @Test
    func aNoOpTransactionDoesNotAddHistory() throws {
        let date = Date(timeIntervalSince1970: 0)
        let document = EaselDocument(id: UUID(), title: "Board", createdAt: date, modifiedAt: date)
        let session = try EaselSession(inMemory: document, assets: [:])
        try session.perform("No change") { _ in }
        #expect(!session.canUndo, "No-op transaction adds no history")
    }

    @MainActor @Test
    func undoHistoryKeepsOnlyItsMostRecentFiftyEdits() throws {
        let date = Date(timeIntervalSince1970: 0)
        let document = EaselDocument(id: UUID(), title: "Board", createdAt: date, modifiedAt: date)
        let session = try EaselSession(inMemory: document, assets: [:])
        for n in 0..<55 { try session.perform("Rename") { $0.title = "Title \(n)" } }
        var count = 0
        while session.canUndo { try session.undo(); count += 1 }
        #expect(count == 50, "Undo history has a bounded count")
    }
}
