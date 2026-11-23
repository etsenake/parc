import Foundation

package struct NoteCaptureInput {
    let pngData: Data
    let sourceURL: String
    let pageTitle: String
    let capturedAt: Date
    let captureLayout: EaselCaptureLayout?

    package init(pngData: Data, sourceURL: String, pageTitle: String, capturedAt: Date, captureLayout: EaselCaptureLayout?) {
        self.pngData = pngData
        self.sourceURL = sourceURL
        self.pageTitle = pageTitle
        self.capturedAt = capturedAt
        self.captureLayout = captureLayout
    }

    var capture: NoteCapture {
        NoteCapture(sourceURL: sourceURL, capturedAt: capturedAt, geometry: captureLayout.flatMap { $0.isValid ? NoteCaptureGeometry($0) : nil })
    }
}

enum NoteCaptureDeliveryError: Error, LocalizedError, Equatable {
    case plainText(String), locked(String), empty

    var errorDescription: String? {
        switch self {
        case .plainText(let name): return "“\(name)” is a plain-text note, so it can’t hold images."
        case .locked(let name): return "“\(name)” is locked or read-only, so the capture wasn’t added."
        case .empty: return "The capture has no image to add."
        }
    }
}

@MainActor
package enum NoteCaptureDelivery {
    package struct Result: Equatable {
        package let note: URL
        package let block: NoteBlockID
        let title: String

        init(note: URL, block: NoteBlockID, title: String) {
            self.note = note
            self.block = block
            self.title = title
        }
    }

    static let editName = "Add Capture"

    package static func deliver(_ input: NoteCaptureInput, to target: CaptureNoteTarget, notesFolder: URL) throws -> Result {
        try deliver(input, to: target, notesFolder: notesFolder, in: .shared)
    }

    static func deliver(_ input: NoteCaptureInput, to target: CaptureNoteTarget, notesFolder: URL, in files: NoteFiles) throws -> Result {
        guard !input.pngData.isEmpty else { throw NoteCaptureDeliveryError.empty }
        let note: URL
        var created = false
        switch target {
        case .newNote:
            note = try files.createNote(in: notesFolder, title: input.pageTitle)
            created = true
        case .note(let url):
            guard NoteFilePaths.isOpenableFile(url) else { throw NoteFileError.missing }
            note = url
        }
        do {
            return try insert(input, into: note, in: files)
        } catch {
            if created { try? FileManager.default.removeItem(at: note) }
            throw error
        }
    }

    static func insert(_ input: NoteCaptureInput, into note: URL, in files: NoteFiles) throws -> Result {
        let file = try files.open(note)
        file.retain()
        defer { file.release() }
        let session = file.page
        guard file.kind == .markdown else { throw NoteCaptureDeliveryError.plainText(file.title) }
        guard !session.isReadOnly, !session.page.settings.locked else { throw NoteCaptureDeliveryError.locked(file.title) }
        let path = try NoteAttachments.placeData(input.pngData, fileExtension: "png", suggestedName: input.pageTitle,
                                                into: file.url, date: input.capturedAt).path
        let block = NoteCapture.block(source: path, title: input.pageTitle, capture: input.capture)
        guard insert(block, into: session) else { throw NoteCaptureDeliveryError.locked(file.title) }
        return Result(note: file.url, block: block.id, title: file.title)
    }

    @discardableResult
    static func insert(_ block: NoteBlock, into session: NotePageSession) -> Bool {
        let caret = session.selection.caret?.block
        var inserted = false
        session.edit(editName, selection: .blocks([block.id])) { page in
            inserted = place(block, in: &page, caret: caret)
        }
        return inserted && session.page.block(block.id) != nil
    }

    static func place(_ block: NoteBlock, in page: inout NotePage, caret: NoteBlockID?) -> Bool {
        if NoteCaptureInsertion.replacesEmptyParagraph(caret, in: page), let caret {
            return page.insert([block], .before(caret)) && page.remove(caret) != nil
        }
        if caret == nil, page.blocks.count == 1, NoteCaptureInsertion.replacesEmptyParagraph(page.blocks.first?.id, in: page),
           let only = page.blocks.first?.id {
            return page.insert([block], .before(only)) && page.remove(only) != nil
        }
        return page.insert([block], NoteCaptureInsertion.placement(in: page, caret: caret))
    }
}
