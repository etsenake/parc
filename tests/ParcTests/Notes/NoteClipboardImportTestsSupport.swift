import AppKit
import Foundation
import Testing
@testable import ParcCore

enum NoteClipboardImportTestsSupport {
    @MainActor final class Fixture {
        let clock = NoteEditorManualClock()

        let jobs = NoteFileDeferredJobs()

        let folder: NoteEditorTemporaryFolder

        lazy var files = IsolatedNoteFiles.make(clock: clock, attachmentWorker: NoteFileWorker(deferred: jobs))

        var imports: NoteAttachmentImports { files.attachmentImports }

        var root: URL { folder.url }

        init() throws {
            folder = try NoteEditorTemporaryFolder("clipboard")
        }

        let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

        func note(_ path: URL, _ text: String = "Hello\n") throws -> NoteFileSession {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: path)
            return try files.open(path)
        }

        func fileExists(_ source: String?) -> Bool {
            guard let source, let url = URL(string: source), url.isFileURL else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }

        func image(_ source: String?, kind: NoteBlockKind = .image) -> NoteBlock {
            var block = NoteBlock(kind)
            block.props.source = source
            return block
        }

        func bitmapTIFF(side: Int) -> Data {
            NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?.tiffRepresentation ?? Data()
        }

        func write(_ bytes: Data, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url)
        }

        @MainActor struct Trip {
            let notes: URL
            let photo: URL
            let file: NoteFileSession
            let session: NotePageSession
        }

        func trip() throws -> Trip {
            let outside = root.appendingPathComponent("Outside", isDirectory: true)
            let notes = root.appendingPathComponent("Notes", isDirectory: true)
            let photo = outside.appendingPathComponent("Beach.png")
            try write(Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]), to: photo)
            let file = try note(notes.appendingPathComponent("Trip.md"))
            return Trip(notes: notes, photo: photo, file: file, session: file.page)
        }

        func attachment(_ source: String?, in notes: URL) -> Data? {
            guard let source, let path = source.removingPercentEncoding else { return nil }
            return try? Data(contentsOf: notes.appendingPathComponent(path))
        }
    }
}
