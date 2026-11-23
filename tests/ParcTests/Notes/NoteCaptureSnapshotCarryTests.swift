import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteCaptureSnapshotCarryTests {
    private let importer: NoteClipboardImportTestsSupport.Fixture
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 7, 7, 7])

    init() throws { importer = try NoteClipboardImportTestsSupport.Fixture() }

    static func pdf(width: CGFloat = 1280, height: CGFloat = 19_200) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        context.beginPDFPage(nil)
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func captureBlock(snapshot: String = "Attachments/Long.pdf") -> NoteBlock {
        NoteCapture.block(source: "Attachments/Long.png", title: "Long",
                          capture: NoteCapture(sourceURL: "https://example.com/long", snapshot: snapshot))
    }

    private struct Copied {
        let first: NoteFileSession
        let archive: NoteClipboard.Archive
        let pdf: Data
    }

    private func copyFromFirstNote(writingPDF: Bool = true) throws -> Copied {
        let folder = importer.root.appendingPathComponent("A", isDirectory: true)
        let pdf = Self.pdf()
        try importer.write(png, to: folder.appendingPathComponent("Attachments/Long.png"))
        if writingPDF { try importer.write(pdf, to: folder.appendingPathComponent("Attachments/Long.pdf")) }
        let first = try importer.note(folder.appendingPathComponent("Capture.md"))
        let block = captureBlock()
        first.page.insertBlocks([block], .top(first.page.page.blocks.count))
        let payload = NoteClipboard.payload(for: [block], inline: false, base: folder, plainTextFile: false)
        let encoded = try #require(NoteClipboard.encode(payload.archive))
        let archive = try #require(NoteClipboard.decode(encoded))
        return Copied(first: first, archive: archive, pdf: pdf)
    }

    private func paste(_ archive: NoteClipboard.Archive, into note: NoteFileSession) -> NoteBlockID {
        let pasted = NoteClipboard.rebase(archive, into: note.environment).map { $0.withFreshIDs() }
        note.page.insertBlocks(pasted, .top(note.page.page.blocks.count))
        importer.jobs.runAll()
        return pasted[0].id
    }

    @Test func pastingACaptureIntoANoteInAnotherFolderCopiesItsPDFBesideItsPicture() throws {
        let copied = try copyFromFirstNote()
        let second = try importer.note(importer.root.appendingPathComponent("B/Plan.md"))
        let id = paste(copied.archive, into: second)
        let block = try #require(second.page.page.block(id))
        #expect(block.props.source == "Attachments/Long.png")
        #expect(block.props.capture?.snapshot == "Attachments/Long.pdf")
        let folder = importer.root.appendingPathComponent("B", isDirectory: true)
        #expect(importer.attachment("Attachments/Long.pdf", in: folder) == copied.pdf)
        #expect(importer.attachment("Attachments/Long.png", in: folder) == png)
    }

    @Test func pastingACaptureIntoANoteInTheSameFolderKeepsItsPDF() throws {
        let copied = try copyFromFirstNote()
        let sibling = try importer.note(importer.root.appendingPathComponent("A/Sibling.md"))
        let id = paste(copied.archive, into: sibling)
        #expect(sibling.page.page.block(id)?.props.capture?.snapshot == "Attachments/Long.pdf")
    }

    @Test func aCopyTakenWhileThePDFIsStillImportingCarriesItToo() throws {
        let copied = try copyFromFirstNote()
        let second = try importer.note(importer.root.appendingPathComponent("B/Plan.md"))
        let pending = NoteClipboard.rebase(copied.archive, into: second.environment)
        let snapshot = try #require(pending.first?.props.capture?.snapshot)
        #expect(snapshot.hasPrefix("file://"))
        let third = try importer.note(importer.root.appendingPathComponent("C/Later.md"))
        let id = paste(NoteClipboard.Archive(blocks: pending, base: nil, inline: false), into: third)
        #expect(third.page.page.block(id)?.props.capture?.snapshot == "Attachments/Long.pdf")
        #expect(importer.attachment("Attachments/Long.pdf", in: importer.root.appendingPathComponent("C", isDirectory: true)) == copied.pdf)
    }

    @Test func aLandedImportRewritesTheSnapshotPathTheWayItRewritesThePicture() throws {
        let note = try importer.note(importer.root.appendingPathComponent("A/Capture.md"))
        let picture = importer.root.appendingPathComponent("Elsewhere/Long.png").absoluteString
        let snapshot = importer.root.appendingPathComponent("Elsewhere/Long.pdf").absoluteString
        var block = captureBlock(snapshot: snapshot)
        block.props.source = picture
        note.page.insertBlocks([block], .top(0))
        NoteAttachmentImports.settle([picture: "Attachments/Long.png", snapshot: "Attachments/Long.pdf"], in: note.page)
        let settled = try #require(note.page.page.block(block.id))
        #expect(settled.props.source == "Attachments/Long.png")
        #expect(settled.props.capture?.snapshot == "Attachments/Long.pdf")
    }

    @Test func aSnapshotLandingOnItsOwnLeavesThePictureAlone() throws {
        let note = try importer.note(importer.root.appendingPathComponent("A/Capture.md"))
        let snapshot = importer.root.appendingPathComponent("Elsewhere/Long.pdf").absoluteString
        let block = captureBlock(snapshot: snapshot)
        note.page.insertBlocks([block], .top(0))
        NoteAttachmentImports.settle([snapshot: "Attachments/Long 2.pdf"], in: note.page)
        let settled = try #require(note.page.page.block(block.id))
        #expect(settled.props.source == "Attachments/Long.png")
        #expect(settled.props.capture?.snapshot == "Attachments/Long 2.pdf")
    }
}

@MainActor
struct NoteCaptureSnapshotZoomTests {
    private func image() throws -> NoteMediaImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 20, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let frame = try #require(context.makeImage())
        return NoteMediaImage(frames: [frame], delays: [0.1], pointSize: CGSize(width: 10, height: 150), decodedPixels: 300)
    }

    private func snapshotLayers(in layer: CALayer?) -> [NoteCaptureSnapshotLayer] {
        guard let layer else { return [] }
        return (layer as? NoteCaptureSnapshotLayer).map { [$0] } ?? (layer.sublayers ?? []).flatMap(snapshotLayers)
    }

    private func zoom(snapshot: URL?) throws -> NoteMediaZoomOverlay {
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900))
        return NoteMediaZoomOverlay.present(image: try image(), source: nil, snapshot: snapshot, from: NSRect(x: 0, y: 0, width: 64, height: 960),
                                            of: canvas, in: canvas, overlay: canvas)
    }

    @Test func theZoomViewDrawsTheCapturesPDFOverItsPicture() throws {
        let folder = try NoteEditorTemporaryFolder("zoom")
        let url = folder.url.appendingPathComponent("Long.pdf")
        try NoteCaptureSnapshotCarryTests.pdf().write(to: url)
        let overlay = try zoom(snapshot: url)
        overlay.layout()
        let layer = try #require(snapshotLayers(in: overlay.layer).first)
        #expect(layer.url == url)
        #expect(layer.bounds.width > 0)
        #expect(abs(layer.bounds.height / layer.bounds.width - 15) < 0.1)
    }

    @Test func withoutAUsablePDFTheZoomViewShowsThePicture() throws {
        let folder = try NoteEditorTemporaryFolder("zoom")
        let broken = folder.url.appendingPathComponent("Broken.pdf")
        try Data("%PDF-1.7 broken".utf8).write(to: broken)
        #expect(snapshotLayers(in: try zoom(snapshot: nil).layer).isEmpty)
        #expect(snapshotLayers(in: try zoom(snapshot: broken).layer).isEmpty)
    }
}

struct NoteCaptureSnapshotSizeTests {
    private let picture = CGSize(width: 200, height: 3000)
    private let snapshot = CGSize(width: 1280, height: 19_200)

    @Test func aCaptureWithAPDFTakesItsNaturalSizeFromThePDFPage() {
        #expect(NoteMediaLayout.naturalSize(picture: picture, snapshot: snapshot) == snapshot)
        #expect(NoteMediaLayout.naturalSize(picture: picture, snapshot: nil) == picture)
    }

    @Test func aLongCaptureFillsTheColumnLikeAnyCaptureOfAPageThatWide() {
        let natural = NoteMediaLayout.naturalSize(picture: picture, snapshot: snapshot)
        #expect(NoteMediaLayout.displayWidth(fraction: nil, natural: natural, columnWidth: 700) == 700)
        #expect(NoteMediaLayout.displayHeight(width: 700, natural: natural) == 10_500)
        #expect(NoteMediaLayout.displayWidth(fraction: nil, natural: picture, columnWidth: 700) == 200)
    }
}
