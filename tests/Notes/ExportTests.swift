import AppKit

@main @MainActor struct NoteExportTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(value(), message)
        }
        let id = UUID(), now = Date(timeIntervalSince1970: 1_700_000_000)
        check(NoteExportArchive.filename(title: "  A/B:*C\nD  ", id: id) == "A_B_C_D.html", "Original filename escaping")
        check(NoteExportArchive.filename(title: "../", id: id) == id.uuidString.lowercased() + ".html", "Hidden or path-like name uses original ID")
        check(NoteExportArchive.filename(title: String(repeating: "🌱", count: 200), id: id).utf8.count <= 185, "Unicode filename respects byte budget")
        let rich = NSMutableAttributedString(string: "Bold & <safe> 🌱\nLink", attributes: [.font: NSFont.boldSystemFont(ofSize: 15), .foregroundColor: NSColor.textColor])
        rich.addAttribute(.link, value: "https://example.invalid/?q=a&b=c", range: (rich.string as NSString).range(of: "Link"))
        var note = NoteDocument(id: id, title: "A <title> & note", createdAt: now, modifiedAt: now)
        note.body.text = rich.string; note.body.richText = try EaselRichTextCodec.snapshot(rich)
        var semantic = note
        let semanticText = NSAttributedString(string: "Default", attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: EaselRichTextCodec.noteBodyColor])
        semantic.body.text = semanticText.string; semantic.body.richText = try EaselRichTextCodec.snapshot(semanticText)
        let semanticBefore = semantic
        var darkExport: NoteExportDocument?
        var exportError: Error?
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            do { darkExport = try NoteHTMLExport.document(semantic) } catch { exportError = error }
        }
        if let exportError { throw exportError }
        check(darkExport?.html.contains("color: #000000") == true, "Dark native appearance exports semantic default with readable fixed light ink")
        check(semantic == semanticBefore && semantic.body.richText.runs.first?.attributes.semanticInk == .noteBody, "Export never changes semantic source document")
        let first = try NoteHTMLExport.document(note)
        check(first.id == id && first.modifiedAt == now, "Original document identity and time retained")
        check(first.html.contains("<html") && first.html.contains("&lt;safe&gt;"), "Valid HTML escapes authored text")
        check(first.html.contains("https://example.invalid/"), "Authored link preserved")
        check(first.html.contains("font-weight: bold") || first.html.contains("<b>"), "Native bold formatting retained")
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)!
        image.setColor(.red, atX: 0, y: 0)
        let png = image.representation(using: .png, properties: [:])!
        let inline = EaselRichText.Image(data: png, fileType: "public.png", width: 1, height: 1)
        let attributedImage = NSAttributedString(attachment: EaselImageAttachment(source: inline))
        note.body.text = attributedImage.string; note.body.richText = try EaselRichTextCodec.snapshot(attributedImage)
        let imageExport = try NoteHTMLExport.document(note)
        check(imageExport.html.contains("data:image/png;base64,"), "Image bytes travel with HTML")
        check(!imageExport.html.contains("PARCIMAGE") && !imageExport.html.contains("file:///"), "No private temporary attachment references")
        note.deleted = true
        do { _ = try NoteHTMLExport.document(note); preconditionFailure("Deleted note exported") } catch { checks += 1 }
        var emptyRejected = false
        do { _ = try NoteExportArchive.prepare([]) } catch NoteExportError.empty { emptyRejected = true }
        check(emptyRejected, "Empty export is explicit")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-note-export-component-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let docs = [first, NoteExportDocument(id: UUID(), title: first.title.uppercased(), html: "<p>Second</p>", modifiedAt: now)]
        var archive: NoteExportArchive? = try NoteExportArchive.prepare(docs, now: now)
        let temporary = archive!.file.deletingLastPathComponent()
        check(archive!.suggestedName == "Parc-Notes-Export-2023-11-14-221320.zip", "Parc archive name and stable UTC date")
        let output = root.appendingPathComponent("notes.zip")
        try Data("older result".utf8).write(to: output)
        try archive!.save(to: output)
        let zipData = try Data(contentsOf: output)
        check(zipData.starts(with: [0x50, 0x4b]), "Atomic replacement publishes real ZIP")
        let extracted = root.appendingPathComponent("extracted")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", output.path, "-d", extracted.path]
        try process.run(); process.waitUntilExit()
        check(process.terminationStatus == 0, "System unzip reads exported archive")
        let files = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: [.contentModificationDateKey])
        check(files.count == 2 && Set(files.map(\.lastPathComponent)).count == 2, "Case-colliding titles cannot overwrite notes")
        let exportedText = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        check(exportedText.contains(first.html), "Exact UTF8 HTML survives archive")
        let timesPreserved = try files.allSatisfy { abs((try $0.resourceValues(forKeys: [.contentModificationDateKey])).contentModificationDate!.timeIntervalSince(now)) < 3 }
        check(timesPreserved, "Original modification dates survive ZIP")
        archive = nil
        check(!FileManager.default.fileExists(atPath: temporary.path), "Completed export cleans private temporary content")
        print("PASS: \(checks) Notes export assertions")
    }
}
