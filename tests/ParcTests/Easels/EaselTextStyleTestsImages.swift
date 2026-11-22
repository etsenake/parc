import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

struct EaselTextStyleTestsImages {
    @MainActor @Test
    func pngImportPreservesItsOriginalBytes() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let source = try EaselTextAttachments.image(data: png)
        #expect(source.data == png && source.fileType == "public.png", "Native inline image preserves actual original PNG bytes")
    }

    struct ImageFormat: CustomTestStringConvertible {
        let format: NSBitmapImageRep.FileType
        let fileType: String
        var testDescription: String { fileType }
    }

    @MainActor @Test(arguments: [
        ImageFormat(format: .jpeg, fileType: "public.jpeg"),
        ImageFormat(format: .tiff, fileType: "public.tiff"),
    ])
    func imageImportPreservesTheOriginalEncodedBytes(_ image: ImageFormat) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 6, bitsPerPixel: 24)!
        bitmap.bitmapData!.initialize(repeating: 128, count: 12); bitmap.size = NSSize(width: 2, height: 2)
        let original = bitmap.representation(using: image.format, properties: [:])!
        let imported = try EaselTextAttachments.image(data: original)
        #expect(imported.data == original && imported.fileType == image.fileType, "Supported image import preserves the actual JPEG/TIFF bytes")
    }

    @MainActor @Test
    func imageCopyKeepsTheOriginalUTF16Range() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let source = try EaselTextAttachments.image(data: png)
        let text = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed("before\n", style: .init(), color: "#252525"))
        text.append(EaselTextAttachments.character(source, attributes: [:]))
        text.append(EaselTextAppearance.attributed("\nafter", style: .init(), color: "#252525"))
        let payload = try EaselStyledText.capture(text, style: .init(), color: "#252525")
        #expect(payload.richText?.runs.first(where: { $0.attributes.image != nil })?.location == 7, "Inline image stays in its original UTF-16 text range")
    }

    @MainActor @Test
    func copyingAnInlineImageOffersLosslessClipboardRepresentations() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let source = try EaselTextAttachments.image(data: png)
        let text = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed("before\n", style: .init(), color: "#252525"))
        text.append(EaselTextAttachments.character(source, attributes: [:]))
        text.append(EaselTextAppearance.attributed("\nafter", style: .init(), color: "#252525"))
        let payload = try EaselStyledText.capture(text, style: .init(), color: "#252525")
        try payload.write(to: board)
        #expect(board.data(forType: .rtfd) != nil && board.data(forType: .rtf) == nil, "Copy advertises real attachment-preserving RTFD")
        #expect(board.string(forType: .string) == "before\n\nafter", "Plain copy carries words without an orphan object-replacement character")
        #expect(try! EaselStyledText.read(from: board) == payload, "Private range carrier preserves encoded image and styled text exactly")
    }

    @MainActor @Test
    func rtfdImportPreservesTheOriginalInlineImage() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let source = try EaselTextAttachments.image(data: png)
        let text = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed("before\n", style: .init(), color: "#252525"))
        text.append(EaselTextAttachments.character(source, attributes: [:]))
        text.append(EaselTextAppearance.attributed("\nafter", style: .init(), color: "#252525"))
        let payload = try EaselStyledText.capture(text, style: .init(), color: "#252525")
        try payload.write(to: board)
        let rtfd = board.data(forType: .rtfd)!
        board.clearContents(); board.setData(rtfd, forType: .rtfd)
        let decoded = try EaselStyledText.read(from: board)!
        #expect(decoded.text == payload.text && decoded.richText?.runs.contains(where: { $0.attributes.image != nil }) == true, "External native RTFD really imports its inline image")
        let encoded = decoded.richText!.runs.first(where: { $0.attributes.image != nil })!.attributes.image!
        #expect(encoded.data == png, "RTFD retains the attachment's actual original encoded PNG")
    }

    @MainActor @Test
    func plainPasteFromRtfdKeepsOnlyTheWords() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let source = try EaselTextAttachments.image(data: png)
        let text = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed("before\n", style: .init(), color: "#252525"))
        text.append(EaselTextAttachments.character(source, attributes: [:]))
        text.append(EaselTextAppearance.attributed("\nafter", style: .init(), color: "#252525"))
        let payload = try EaselStyledText.capture(text, style: .init(), color: "#252525")
        try payload.write(to: board)
        let rtfd = board.data(forType: .rtfd)!
        board.clearContents(); board.setData(rtfd, forType: .rtfd)
        #expect(try! EaselStyledText.plainText(from: board) == "before\n\nafter", "Explicit plain paste extracts words from RTFD without importing pixels")
    }

    @MainActor @Test
    func resizingTheContainerRecomputesTheImageCellSize() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let source = try EaselTextAttachments.image(data: png)
        let cell = EaselImageAttachment(source: .init(data: png, fileType: "public.png", width: 400, height: 200)).attachmentCell as! EaselImageAttachmentCell
        let container = NSTextContainer(containerSize: NSSize(width: 260, height: 1000))
        cell.textContainer = container
        #expect(cell.cellSize() == NSSize(width: 260, height: 160), "Original attachment cell fits both dimensions into width minus 60 and reserves full line width")
        container.size.width = 160
        #expect(cell.cellSize() == NSSize(width: 160, height: 110), "Text-container resizing recomputes from original image size")
        #expect(source.data == png, "Layout-only NSImage size changes leave encoded bytes untouched")
    }

    @MainActor @Test
    func nativeImageInsertionReplacesTheSelection() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("one two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original); view.setSelectedRange(NSRange(location: 4, length: 3))
        view.localUndo.beginUndoGrouping(); #expect(try! view.insertImage(png), "Native image authoring accepts original selected range"); view.localUndo.endUndoGrouping()
        #expect(view.string == "one \n\u{FFFC}\n" && view.selectedRange() == NSRange(location: 7, length: 0), "Image replaces selected text and adds original paragraph boundaries")
        #expect(view.typingAttributes[.attachment] == nil, "Following typing cannot accidentally duplicate the image")
    }

    @MainActor @Test
    func nativeUndoAndRedoRestoreTheImageTransaction() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("one two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original); view.setSelectedRange(NSRange(location: 4, length: 3))
        view.localUndo.beginUndoGrouping(); _ = try view.insertImage(png); view.localUndo.endUndoGrouping()
        let inserted = try EaselRichTextCodec.snapshot(view.attributedString())
        view.undo(nil); #expect(view.attributedString().isEqual(to: original) && view.selectedRange() == NSRange(location: 4, length: 3), "One native undo restores original text and selection")
        view.redo(nil); #expect(try! EaselRichTextCodec.snapshot(view.attributedString()) == inserted, "Redo restores exact image bytes and paragraph structure")
    }

    @MainActor @Test
    func copyingASelectedImageRebasesItsAttachmentRange() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("one two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original); view.setSelectedRange(NSRange(location: 4, length: 3))
        view.localUndo.beginUndoGrouping(); _ = try view.insertImage(png); view.localUndo.endUndoGrouping()
        view.setSelectedRange(NSRange(location: 5, length: 1))
        let selected = try view.selectedPayload()!
        #expect(selected.text == "\u{FFFC}" && selected.richText?.runs.first?.attributes.image?.data == png, "Selected image copy rebases its real attachment range")
    }

    @MainActor @Test
    func deletingASelectedImageIsUndoable() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("one two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original); view.setSelectedRange(NSRange(location: 4, length: 3))
        view.localUndo.beginUndoGrouping(); _ = try view.insertImage(png); view.localUndo.endUndoGrouping()
        view.setSelectedRange(NSRange(location: 5, length: 1))
        view.localUndo.beginUndoGrouping(); view.deleteBackward(nil); view.localUndo.endUndoGrouping()
        #expect(!EaselTextAttachments.hasImages(view.attributedString()), "Native Delete removes just the selected attachment character")
        view.undo(nil); #expect(EaselTextAttachments.hasImages(view.attributedString()), "Native Delete undo restores the original attachment")
    }

    @MainActor @Test
    func imageInsertionRefusesAnActiveComposition() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("one two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original); view.setSelectedRange(NSRange(location: 4, length: 3))
        view.localUndo.beginUndoGrouping(); _ = try view.insertImage(png); view.localUndo.endUndoGrouping()
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        view.localUndo.beginUndoGrouping(); view.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let composition = view.attributedString()
        #expect(try! !view.insertImage(png) && view.hasMarkedText() && view.attributedString().isEqual(to: composition), "Inline image admission cannot replace an active native composition")
        view.finishComposition(); view.localUndo.endUndoGrouping()
    }

    @MainActor @Test
    func corruptImageInsertionPreservesTheEditor() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("one two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original); view.setSelectedRange(NSRange(location: 4, length: 3))
        view.localUndo.beginUndoGrouping(); _ = try view.insertImage(png); view.localUndo.endUndoGrouping()
        view.setSelectedRange(NSRange(location: 0, length: 0))
        let untouched = view.attributedString()
        #expect(throws: (any Error).self, "Corrupt image cannot mutate original selection") { _ = try view.insertImage(Data("bad".utf8)) }
        #expect(view.attributedString().isEqual(to: untouched), "Rejected image leaves editor and existing attachments intact")
    }

    @MainActor @Test
    func aDirectoryAttachmentIsRefused() throws {
        let unsafe = NSTextAttachment(fileWrapper: FileWrapper(directoryWithFileWrappers: [:]))
        #expect(throws: (any Error).self, "Directory attachment is not followed as an external file") { _ = try EaselTextAttachments.source(unsafe) }
    }

    @MainActor @Test
    func pastingAPngInsertsAnInlineImage() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("one two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original); view.setSelectedRange(NSRange(location: 4, length: 3))
        board.clearContents(); board.setData(png, forType: .png)
        view.localUndo.beginUndoGrouping(); #expect(view.pasteContent(from: board), "Ordinary native PNG paste reaches actual inline image authoring"); view.localUndo.endUndoGrouping()
    }

    @MainActor @Test
    func pastingALocalImageRetainsBytesAfterDeletingTheSource() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("one two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original); view.setSelectedRange(NSRange(location: 4, length: 3))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-inline-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("original.png"); try png.write(to: file)
        board.clearContents(); board.setString(file.absoluteString, forType: .fileURL)
        view.localUndo.beginUndoGrouping(); #expect(view.pasteContent(from: board), "A real local image file pastes into the original native text range"); view.localUndo.endUndoGrouping()
        try FileManager.default.removeItem(at: file)
        #expect(try! EaselRichTextCodec.snapshot(view.attributedString()).runs.contains(where: { $0.attributes.image?.data == png }), "Inline file import retains bytes after source file deletion")
    }

    @MainActor @Test
    func pastingADirectoryPreservesRichText() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("one two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original); view.setSelectedRange(NSRange(location: 4, length: 3))
        view.localUndo.beginUndoGrouping(); _ = try view.insertImage(png); view.localUndo.endUndoGrouping()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-inline-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        board.clearContents(); board.setString(directory.absoluteString, forType: .fileURL)
        let beforeDirectory = view.attributedString()
        #expect(!view.pasteContent(from: board) && view.attributedString().isEqual(to: beforeDirectory), "Directory paste is refused without mutating rich text")
    }

    @MainActor @Test
    func selectedImageExportWritesItsOriginalBytesAsRtfd() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        view.isRichText = true; view.isEditable = true; view.allowsUndo = true; view.localUndo.groupsByEvent = false
        let original = EaselTextAppearance.attributed("one two", style: .init(), color: "#252525")
        view.textStorage!.setAttributedString(original); view.setSelectedRange(NSRange(location: 4, length: 3))
        view.localUndo.beginUndoGrouping(); _ = try view.insertImage(png); view.localUndo.endUndoGrouping()
        view.setSelectedRange(NSRange(location: 0, length: view.attributedString().length))
        #expect(view.writablePasteboardTypes.contains(.rtfd) && !view.writablePasteboardTypes.contains(.rtf), "Native selected-text export advertises the lossless attachment format")
        board.clearContents(); board.declareTypes([.rtfd], owner: nil)
        #expect(view.writeSelection(to: board, type: .rtfd), "Native Services/drag writer serializes the actual selected range as RTFD")
        #expect(try! EaselStyledText.read(from: board)?.richText?.runs.contains(where: { $0.attributes.image?.data == png }) == true, "Native selected-range RTFD export retains original image bytes")
    }
}
