import Foundation
import Testing
@testable import ParcCore

struct NoteCaptureSnapshotTests {
    var capture: NoteCapture {
        NoteCapture(sourceURL: "https://example.com/long", capturedAt: NoteCaptureTests.date, geometry: NoteCaptureGeometry(NoteCaptureTests.layout),
                    snapshot: "Attachments/Long.pdf")
    }

    @Test func theSnapshotPDFIsWrittenWithTheCaptureAndReadsBack() {
        let block = NoteCapture.block(source: "Attachments/Long.png", title: "Long", capture: capture)
        let text = NoteMarkdown.serialize(NotePage(blocks: [block]))
        #expect(text.contains("snapshot=\"Attachments/Long.pdf\""))
        let read = NoteMarkdown.parse(text).blocks.first
        #expect(read?.props.capture == capture)
        #expect(read?.props.capture?.snapshot == "Attachments/Long.pdf")
        #expect(NoteMarkdown.serialize(NoteMarkdown.parse(text)) == text)
    }

    @Test(arguments: ["", "Attachments/Long.png", "https://example.com/long.pdf"])
    func onlyALocalPDFIsKeptAsTheSnapshot(_ path: String) {
        #expect(NoteCapture(sourceURL: "https://example.com", snapshot: path).snapshot == nil)
    }

    @Test func parcsOwnHTMLKeepsTheSnapshot() {
        let block = NoteCapture.block(source: "Attachments/Long.png", title: "Long", capture: capture)
        let html = NotePageHTML.fragment([block])
        #expect(html.contains("data-snapshot=\"Attachments/Long.pdf\""))
    }
}

@MainActor final class NoteCaptureSnapshotDeliveryTests {
    let folder = NoteFileTestSupport.makeFolder("snapshots")
    let files = NoteFileTestSupport.files(clock: NoteManualClock())
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    func deliver(pdf: Data?) throws -> NoteCaptureDelivery.Result {
        let input = NoteCaptureInput(pngData: png, sourceURL: "https://example.com/long", pageTitle: "Long page",
                                     capturedAt: NoteCaptureTests.date, captureLayout: NoteCaptureTests.layout, snapshotPDF: pdf)
        return try NoteCaptureDelivery.deliver(input, to: .newNote, notesFolder: folder, in: files)
    }

    @Test func aFullPagePDFIsStoredBesideThePictureAndNamedByTheCapture() throws {
        let pdf = CaptureSnapshotFixture.pdf()
        let made = try deliver(pdf: pdf)
        let capture = try #require(NoteMarkdown.parse(NoteFileTestSupport.read(made.note)).blocks.last?.props.capture)
        let snapshot = try #require(capture.snapshot)
        #expect(snapshot.hasPrefix("Attachments/") && snapshot.hasSuffix(".pdf"))
        let stored = made.note.deletingLastPathComponent().appendingPathComponent(snapshot.removingPercentEncoding ?? snapshot)
        #expect(try Data(contentsOf: stored) == pdf)
        let attachments = try FileManager.default.contentsOfDirectory(atPath: NoteAttachments.folder(for: made.note).path)
        #expect(attachments.count == 2)
    }

    @Test(arguments: [nil, Data("%PDF-1.7 broken".utf8)])
    func withoutAReadablePDFTheCaptureKeepsJustItsPicture(_ pdf: Data?) throws {
        let made = try deliver(pdf: pdf)
        let block = try #require(NoteMarkdown.parse(NoteFileTestSupport.read(made.note)).blocks.last)
        #expect(block.props.capture != nil && block.props.capture?.snapshot == nil)
        let attachments = try FileManager.default.contentsOfDirectory(atPath: NoteAttachments.folder(for: made.note).path)
        #expect(attachments.count == 1)
    }
}
