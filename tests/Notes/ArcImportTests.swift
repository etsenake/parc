import AppKit

@main struct ArcNotesImportTests {
    @MainActor static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(condition(), message)
        }
        let pixel = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = pixel.representation(using: .png, properties: [:])!.base64EncodedString()
        let html = """
            <html><head><title>Trip plan</title><link rel="stylesheet" href="https://styles.example.test/a.css"></head><body>
            <h1>Trip</h1><p>Plain <b>bold</b> <i>slanted</i> <u>under</u> <s>struck</s> <a href="https://example.test/">link</a></p>
            <ul><li>One</li><li>Two</li></ul><ol><li>First</li><li>Second</li></ol>
            <p><img src="https://images.example.test/remote.png"></p><p><img src="data:image/png;base64,\(png)"></p>
            <script>document.write("no")</script></body></html>
            """
        let converted = try ArcNoteHTML.convert(html)
        let text = converted.body.text as NSString
        let value = NoteDocumentAppearance.attributedBody(converted.body)
        func attributes(of word: String) -> [NSAttributedString.Key: Any] {
            value.attributes(at: text.range(of: word).location, effectiveRange: nil)
        }
        func paragraph(of word: String) -> NSParagraphStyle? { attributes(of: word)[.paragraphStyle] as? NSParagraphStyle }
        expect(converted.title == "Trip plan", "The Note's title comes from its HTML title")
        expect((attributes(of: "Trip")[.font] as? NSFont)?.pointSize == 32 && paragraph(of: "Trip")?.headerLevel == 1,
               "A heading becomes a Notes Heading 1")
        expect((attributes(of: "bold")[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true
               && (attributes(of: "slanted")[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) == true,
               "Bold and italic survive on the Notes body font")
        expect((attributes(of: "under")[.underlineStyle] as? Int ?? 0) != 0 && (attributes(of: "struck")[.strikethroughStyle] as? Int ?? 0) != 0,
               "Underline and strikethrough survive")
        expect(attributes(of: "link")[.link] as? String == "https://example.test/", "Links survive")
        expect((attributes(of: "Plain")[.font] as? NSFont)?.pointSize == NoteDocumentAppearance.bodyFont.pointSize,
               "Plain text takes the Notes body style")
        expect(paragraph(of: "One")?.textLists.last?.markerFormat == .disc && text.range(of: "\t•\tOne").location != NSNotFound,
               "A bulleted list becomes a Notes bulleted list")
        expect(text.range(of: "\t1.\tFirst").location != NSNotFound && text.range(of: "\t2.\tSecond").location != NSNotFound,
               "A numbered list becomes a numbered Notes list, renumbered")
        expect(converted.body.richText.runs.filter { $0.attributes.image != nil }.count == 1 && converted.droppedImages == 1,
               "An image inside the file comes over; one on the servers is counted, never fetched")
        expect(!converted.body.text.contains("no") || !converted.body.text.contains("document.write"), "Scripts are removed")
        try converted.body.richText.validate(text: converted.body.text)
        checks += 1

        let hostile = """
            <img data-src="data:image/png;base64,AA" src="https://one.example.test/a.png"><img srcset=https://two.example.test/b.png 1x>
            <frame src="https://three.example.test/"><input type=image src="https://four.example.test/c.png">
            <table background="https://five.example.test/d.png"><tr><td background="https://six.example.test/">x</td></tr></table>
            <svg><image href="https://seven.example.test/e.png"/></svg><track src="https://eight.example.test/f.vtt">
            <style>@import "https://nine.example.test/g.css"</style><p style="background:image-set('https://ten.example.test/h.png' 1x)">y</p>
            <p style="color: red" class="note-body">kept</p><a href="javascript:alert(1)">bad</a>
            <style>p { font-weight: bold }</style><img src=https://eleven.example.test/x.png alt=it's>
            <style>@import url(https://twelve.example.test/x.css);
            """
        let (clean, droppedHostile) = ArcNoteHTML.sanitized(hostile)
        expect(clean.range(of: "<[^>]*(example\\.test|javascript)", options: .regularExpression) == nil
               && !clean.contains("twelve.example.test"), "No tag or style sheet left by cleaning names another resource")
        expect(droppedHostile >= 3 && clean.contains("style=\"color: red\"") && clean.contains("class=\"note-body\"")
               && clean.contains("<style>p { font-weight: bold }</style>"),
               "Remote images are counted; harmless inline styles and classes stay")
        let structured = try ArcNoteHTML.convert("""
            <ul><li>Outer<ul><li>Inner</li></ul></li></ul><ul><li><input type="checkbox" checked>Done</li><li><input type="checkbox">Open</li></ul>
            <pre><code>let x = 1</code></pre><p><span style="color: #c00000">red</span> <mark>marked</mark></p>
            """)
        let nested = NoteDocumentAppearance.attributedBody(structured.body), nestedText = structured.body.text as NSString
        func style(_ word: String) -> [NSAttributedString.Key: Any] { nested.attributes(at: nestedText.range(of: word).location, effectiveRange: nil) }
        expect((style("Inner")[.paragraphStyle] as? NSParagraphStyle)?.textLists.count == 2
               && (style("Outer")[.paragraphStyle] as? NSParagraphStyle)?.textLists.count == 1, "A nested list keeps its depth")
        expect(nestedText.range(of: "\u{2611} Done").location != NSNotFound && nestedText.range(of: "\u{2610} Open").location != NSNotFound,
               "Checklist items keep whether they were checked")
        expect((style("let x")[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true, "Code stays monospaced")
        expect(((style("red")[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB)?.redComponent ?? 0) > 0.6
               && style("marked")[.backgroundColor] != nil, "Text colours and highlights stay")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("Arc-Notes-Export-2026-11-08")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let older = Date(timeIntervalSince1970: 1_780_000_000), newer = Date(timeIntervalSince1970: 1_790_000_000)
        for (name, date) in [("Groceries", newer), ("Trip plan", older)] {
            let file = folder.appendingPathComponent(name + ".html")
            try Data(html.utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        }
        let fromFolder = try ArcNotesExport.read(folder)
        expect(fromFolder.map(\.title) == ["Trip plan", "Groceries"] && fromFolder.map(\.modifiedAt) == [older, newer],
               "An unzipped export gives each Note with its last-edit date, oldest first")
        let archive = directory.appendingPathComponent("Arc-Notes-Export-2026-11-08.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--keepParent", folder.path, archive.path]
        try zip.run(); zip.waitUntilExit()
        let fromArchive = try ArcNotesExport.read(archive)
        expect(fromArchive == fromFolder, "The ZIP gives the same Notes and dates as its folder")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
        expect(!leftovers.contains { $0.hasPrefix("ParcArcNotes-") }, "The expanded copy is removed")
        let empty = directory.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        do { _ = try ArcNotesExport.read(empty); preconditionFailure("An empty export must refuse") }
        catch ArcNotesExport.Failure.empty { checks += 1 }
        let other = directory.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: other)
        do { _ = try ArcNotesExport.read(other); preconditionFailure("A non-export file must refuse") }
        catch ArcNotesExport.Failure.unreadable { checks += 1 }

        let store = try NoteStore(directory: directory.appendingPathComponent("Notes"), diskSaveDelay: 0)
        let note = try store.importDocument(title: "Trip plan", body: converted.body, modifiedAt: older)
        let reopened = try NoteStore(directory: directory.appendingPathComponent("Notes"), diskSaveDelay: 0).list()
        expect(reopened == [note] && note.modifiedAt == older && note.createdAt == older,
               "An imported Note is saved with its own last-edit date")
        print("\(checks) Arc Notes import assertions passed; synthetic export only.")
    }
}
