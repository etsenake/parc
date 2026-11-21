import AppKit

@MainActor
final class RecordingEnvironment: NoteEnvironment {
    let documentURL: URL?
    let isPlainText = false
    var imported: [URL] = []
    var importedData: [(Data, String)] = []

    init(documentURL: URL) { self.documentURL = documentURL }

    func resolve(_ source: String) -> URL? { nil }
    func importAsset(from url: URL) throws -> String {
        imported.append(url)
        return "Attachments/" + url.lastPathComponent
    }
    func importAsset(data: Data, fileExtension: String, suggestedName: String?) throws -> String {
        importedData.append((data, fileExtension))
        return "Attachments/pasted." + fileExtension
    }
    func searchNotes(_ query: String, limit: Int) -> [NoteReference] { [] }
    func linkTarget(for note: URL) -> String {
        let folder = documentURL!.deletingLastPathComponent().standardizedFileURL.path + "/"
        let path = note.standardizedFileURL.path
        return path.hasPrefix(folder) ? String(path.dropFirst(folder.count)) : path
    }
    func resolveNoteLink(_ target: String) -> URL? { nil }
}

@main @MainActor
struct NoteClipboardTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
        sniffing()
        links()
        choices()
        payloads()
        roundTrip()
        plainLines()
        files()
        rebasing()
        inlineMedia()
        rebaseRefusals()
        asyncImports()
        quitMidCopy()
        failedImportKeepsOriginal()
        crossNotePaste()
        movedMidImport()
        stagedResume()
        asyncReplace()
        offlineRichText()
        print("NoteClipboardTests passed")
    }

    static func wait(_ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    static func folder(_ name: String) -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-clipboard-\(name)-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func note(_ path: URL, _ text: String = "Hello\n") -> NoteFileSession {
        try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: path)
        guard let file = try? NoteFileSession.open(path) else { failTest("\(path.lastPathComponent) opens") }
        return file
    }

    static func stallImports() -> () -> Void {
        let imports = NoteAttachmentImports.shared
        let previous = imports.worker
        let gate = DispatchSemaphore(value: 0)
        imports.worker = NoteFileWorker(label: "parc.tests.stalled-imports." + UUID().uuidString)
        imports.worker.perform({ gate.wait() }) { _ in }
        return {
            gate.signal()
            imports.worker = previous
        }
    }

    static func fileExists(_ source: String?) -> Bool {
        guard let source, let url = URL(string: source), url.isFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func image(_ source: String?, kind: NoteBlockKind = .image) -> NoteBlock {
        var block = NoteBlock(kind)
        block.props.source = source
        return block
    }

    static func bitmapTIFF(side: Int) -> Data {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?.tiffRepresentation ?? Data()
    }

    static func offlineRichText() {
        let scrub = NoteOfflineHTML.scrub
        expect(scrub("<p>Hi <img src=\"https://tracker.example/p.gif\" alt=\"Cat &amp; dog\"> there</p>") == "<p>Hi Cat &amp; dog there</p>",
               "a remote picture becomes its alt text")
        expect(scrub("<img alt='<b>x</b>' src=//cdn.example/a.png>") == "&lt;b&gt;x&lt;/b&gt;", "alt text can't smuggle markup back in")
        for local in ["<img src=\"file:///tmp/a.png\" alt=\"x\">", "<img src=\"Attachments/a%20b.png\">", "<img src=\"data:image/png;base64,AAAA\">",
                      "<a href=\"https://example.com\">link</a>", "<p style=\"color: red\">red</p>", "<span data-color=\"red\">x</span>",
                      "<video controls></video>", "<br/>", "<!DOCTYPE html>", "<p>1 < 2</p>"] {
            let kept = local == "<p>1 < 2</p>" ? "<p>1 &lt; 2</p>" : local
            expect(scrub(local) == kept, "\(local) stays as it is: \(scrub(local))")
        }
        let hostile = [
            "<img src=\"h&#116;tps://x.example/a.png\">", "<img src=\" https://x.example/a.png\">", "<img src=\"java&#x0A;script:x\">",
            "<img src=\"a.png\" srcset=\"https://x.example/a2.png 2x, b.png 1x\">", "<link rel=\"stylesheet\" href=\"https://x.example/s.css\">",
            "<base href=\"https://x.example/\"><img src=\"a.png\">", "<iframe src=\"https://x.example\">fallback</iframe>",
            "<script src=\"https://x.example/s.js\"></script>", "<object data=\"https://x.example/o\"><img src=\"https://x.example/i\"></object>",
            "<embed src=\"https://x.example/e\">", "<video src=\"https://x.example/v.mp4\" poster=\"https://x.example/p.jpg\"></video>",
            "<audio><source src=\"https://x.example/a.mp3\"></audio>", "<svg><image href=\"https://x.example/i.png\"/></svg>",
            "<svg><use xlink:href=\"https://x.example/s.svg#a\"/></svg>", "<table background=\"https://x.example/t.png\"><tr><td>x</td></tr></table>",
            "<style>@import url(https://x.example/s.css); p { background: url('https://x.example/bg.png') }</style>",
            "<style>@import 'https://x.example/s.css';</style>", "<p style=\"background-image:url(&quot;https://x.example/bg.png&quot;)\">x</p>",
            "<p style=\"background:-webkit-image-set('https://x.example/a.png' 1x)\">x</p>", "<p style=\"background:u\\72l(https://x.example/a)\">x</p>",
            "<meta http-equiv=\"refresh\" content=\"0;url=https://x.example\">", "<input type=\"image\" src=\"https://x.example/b.png\">",
            "<!--[if IE]><img src=\"https://x.example/ie.png\"><![endif]-->", "<IMG SRC=\"HTTPS://x.example/a.png\">",
        ]
        for html in hostile {
            let clean = scrub(html)
            expect(!clean.lowercased().contains("x.example"), "\(html) loses its remote subresource: \(clean)")
        }
        expect(scrub("<video src=\"https://x.example/v.mp4\" controls></video>") == "<video controls></video>", "a remote video keeps its element")
        expect(scrub("<img src=\"a.png\" srcset=\"https://x.example/a2.png 2x\" alt=\"pic\">") == "<img src=\"a.png\" alt=\"pic\">",
               "a local picture just loses its remote extra sizes")
        expect(scrub("<iframe src=\"https://x.example\">fallback</iframe><p>after</p>") == "<p>after</p>", "dropped frames don't swallow what follows")
        expect(NoteOfflineHTML.offlineCSS("p { color: red; background: url(Attachments/bg.png) }") == "p { color: red; background: url(Attachments/bg.png) }",
               "local CSS images stay")
    }

    static func rebaseRefusals() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-clipboard-rebase-" + UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let secrets = root.appendingPathComponent("Secrets", isDirectory: true)
        try? FileManager.default.createDirectory(at: source.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: source.appendingPathComponent(".ssh"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: secrets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try? Data([1]).write(to: source.appendingPathComponent("Attachments/cat.png"))
        try? Data([2]).write(to: secrets.appendingPathComponent("id_rsa"))
        try? Data([3]).write(to: source.appendingPathComponent(".ssh/id_rsa"))
        try? FileManager.default.createSymbolicLink(at: source.appendingPathComponent("Attachments/sneaky.png"),
                                                    withDestinationURL: secrets.appendingPathComponent("id_rsa"))
        func media(_ path: String) -> NoteBlock {
            var block = NoteBlock(.file)
            block.props.source = path
            return block
        }
        func imported(base: URL, _ paths: [String]) -> (blocks: [NoteBlock], copied: [String]) {
            let environment = RecordingEnvironment(documentURL: root.appendingPathComponent("Elsewhere/Page.md"))
            let archive = NoteClipboard.Archive(blocks: paths.map(media), base: base, inline: false)
            let blocks = NoteClipboard.rebase(archive, into: environment)
            return (blocks, environment.imported.map { $0.lastPathComponent })
        }
        let fine = imported(base: source, ["Attachments/cat.png"])
        expect(fine.copied == ["cat.png"], "media inside the copied note's folder still comes along")
        let escapes = imported(base: source, ["../Secrets/id_rsa", "Attachments/../../Secrets/id_rsa"])
        expect(escapes.copied.isEmpty, "media climbing out of the source folder with .. stays behind")
        expect(escapes.blocks.map(\.props.source) == ["../Secrets/id_rsa", "Attachments/../../Secrets/id_rsa"], "refused sources are left as written")
        expect(imported(base: source, ["Attachments/sneaky.png"]).copied.isEmpty, "a symlink pointing out of the folder isn't followed")
        expect(imported(base: source, [".ssh/id_rsa"]).copied.isEmpty, "hidden folders aren't raided")
        expect(imported(base: source.appendingPathComponent(".ssh", isDirectory: true), ["id_rsa"]).copied.isEmpty,
               "a hidden folder can't pose as a note folder")
        expect(imported(base: URL(fileURLWithPath: "/", isDirectory: true), [String(secrets.path.dropFirst()) + "/id_rsa"]).copied.isEmpty,
               "the disk root can't pose as a note folder")
        let home = FileManager.default.homeDirectoryForCurrentUser
        expect(imported(base: home, [".ssh/id_rsa", "Documents/taxes.pdf"]).copied.isEmpty, "the home folder can't pose as a note folder")
        expect(imported(base: home.deletingLastPathComponent(), [home.lastPathComponent + "/Documents/taxes.pdf"]).copied.isEmpty,
               "nor can anything above it")
        expect(NoteClipboard.trustedMediaFolder(URL(string: "https://example.com/notes/")!) == nil, "a web base is never a note folder")
    }

    static func asyncImports() {
        let root = folder("imports")
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        let other = root.appendingPathComponent("Other", isDirectory: true)
        for folder in [outside, other.appendingPathComponent("Attachments")] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = outside.appendingPathComponent("Beach.png")
        try? Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]).write(to: photo)
        try? Data([7, 7]).write(to: other.appendingPathComponent("Attachments/cat.png"))
        let file = note(notes.appendingPathComponent("Trip.md"))
        let session = file.page
        let imports = NoteAttachmentImports.shared
        func attachment(_ source: String?) -> Data? {
            guard let source, let path = source.removingPercentEncoding else { return nil }
            return try? Data(contentsOf: notes.appendingPathComponent(path))
        }

        let dropped = NoteClipboard.blocks(forFiles: [photo, outside.appendingPathComponent("Gone.mov")], environment: file.environment)
        let sources = dropped.blocks.compactMap(\.props.source)
        expect(dropped.failures.isEmpty && sources.count == 2, "dropped files become blocks right away")
        expect(sources.allSatisfy { $0.hasPrefix("file://") && imports.isPending($0, in: session) },
               "they point at the originals while the copy runs in the background: \(sources)")
        expect(fileExists(sources[0]) && URL(string: sources[0])?.lastPathComponent == "Beach.png", "so the picture shows up straight away")
        let ids = session.insertBlocks(dropped.blocks, .top(session.page.blocks.count))
        wait { !sources.contains { imports.isPending($0, in: session) } }
        expect(session.page.block(ids[0])?.props.source == "Attachments/Beach.png", "the finished copy becomes the block's source")
        expect(attachment("Attachments/Beach.png") == (try? Data(contentsOf: photo)), "and the copy is byte for byte")
        expect(session.page.block(ids[1])?.props.source == sources[1] && imports.takeFailure(of: sources[1], in: session) != nil,
               "a file that vanished keeps its link and remembers why it didn't copy")
        expect(NoteMediaSource(sources[1], resolve: { file.environment.resolve($0) }).readiness(for: .video, importing: false) == .missing,
               "and reads as missing")
        session.undo()
        expect(session.page.block(ids[0]) == nil, "undo takes the drop back")
        session.redo()
        expect(session.page.block(ids[0])?.props.source == "Attachments/Beach.png", "redo brings back the finished source")

        let small = bitmapTIFF(side: 2)
        guard let pasted = try? NoteClipboard.imageBlock(data: small, fileExtension: "tiff", environment: file.environment),
              let smallSource = pasted.props.source else { failTest("a pasted picture becomes a block") }
        expect(!imports.isPending(smallSource, in: session) && smallSource.hasSuffix(".png"), "a small pasted picture lands right away: \(smallSource)")
        expect(attachment(smallSource)?.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]), "and a TIFF lands as a PNG")

        let big = bitmapTIFF(side: 1200)
        expect(big.count > NoteMediaImport.stagingThreshold, "the big picture is big: \(big.count)")
        guard let bigBlock = try? NoteClipboard.imageBlock(data: big, fileExtension: "tiff", environment: file.environment),
              let bigSource = bigBlock.props.source, let staged = URL(string: bigSource) else { failTest("a big pasted picture becomes a block") }
        expect(NoteAttachments.isStaged(staged) && (try? Data(contentsOf: staged)) == big, "a big paste waits in a temporary file with the real bytes")
        expect(imports.isPending(bigSource, in: session), "while its copy runs in the background")
        session.insertBlocks([bigBlock], .top(session.page.blocks.count))
        session.undo()
        wait { !imports.isPending(bigSource, in: session) }
        guard let bigPath = imports.landedPath(for: bigSource, in: session) else { failTest("the big picture is saved") }
        expect(bigPath.hasSuffix(".png") && attachment(bigPath)?.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]), "a big TIFF lands as a PNG too")
        session.redo()
        wait { session.page.block(bigBlock.id)?.props.source != bigSource }
        expect(session.page.block(bigBlock.id)?.props.source == bigPath, "redoing a paste that finished while undone heals its source")

        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 9, 9])
        let inline = image("data:image/png;base64," + bytes.base64EncodedString())
        let decoded = NoteClipboard.importInlineMedia([inline], environment: file.environment)
        let inlineSource = decoded.blocks[0].props.source
        expect(decoded.failures.isEmpty && attachment(inlineSource) == bytes, "small data URLs land in Attachments straight away")

        let cat = image("Attachments/cat.png")
        let rebased = NoteClipboard.rebase(NoteClipboard.Archive(blocks: [cat], base: other, inline: false), into: file.environment)
        let catSource = rebased[0].props.source
        expect(catSource?.hasPrefix("file://") == true && fileExists(catSource) && imports.isPending(catSource, in: session),
               "media from another note's folder shows from there while it copies")
        session.insertBlocks(rebased, .top(session.page.blocks.count))
        wait { !imports.isPending(catSource, in: session) }
        expect(attachment(session.page.block(rebased[0].id)?.props.source) == Data([7, 7]), "and arrives intact")
        expect(!imports.isPending("Attachments/cat.png", in: session), "ordinary sources aren't imports")
    }

    static func quitMidCopy() {
        let root = folder("quit")
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try? FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let movie = outside.appendingPathComponent("Big Trip.mov")
        try? Data(repeating: 3, count: 2048).write(to: movie)
        let page = root.appendingPathComponent("Notes/Trip.md")
        let file = note(page)
        file.retain()
        let session = file.page
        let imports = NoteAttachmentImports.shared
        let release = stallImports()
        let dropped = NoteClipboard.blocks(forFiles: [movie], environment: file.environment).blocks
        let huge = Data(repeating: 0xAB, count: NoteMediaImport.stagingThreshold + 1)
        guard let pasted = try? NoteClipboard.imageBlock(data: huge, fileExtension: "png", environment: file.environment) else {
            failTest("a huge paste becomes a block")
        }
        session.insertBlocks(dropped + [pasted], .top(session.page.blocks.count))
        let sources = (dropped + [pasted]).compactMap(\.props.source)
        expect(sources.allSatisfy { imports.isPending($0, in: session) }, "both copies are still running")
        file.release()
        guard let text = try? String(contentsOf: page, encoding: .utf8) else { failTest("the note was saved on close") }
        expect(!text.contains("parc-attachment"), "no placeholder token is ever written: \(text)")
        let saved = NoteMarkdown.parse(text).blocks.filter(\.kind.isMedia)
        let environment = NoteFileEnvironment(documentURL: page, isPlainText: false)
        expect(saved.count == 2 && saved.allSatisfy { block in
            guard let url = block.props.source.flatMap(environment.resolve) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }, "the saved note links to files that really exist: \(saved.map(\.props.source))")
        expect(saved.map(\.kind) == [.video, .image], "and keeps what kind of media each one is")
        release()
        wait { !sources.contains { imports.isPending($0, in: session) } }
        guard let after = try? String(contentsOf: page, encoding: .utf8) else { failTest("the note is still there") }
        expect(after == text, "a copy finishing after the note closed leaves the file alone")
        let reopened = note(page, text)
        reopened.retain()
        defer { reopened.release() }
        expect(reopened.page !== session, "reopening gives a fresh session")
        let reopenedSources = reopened.page.page.blocks.compactMap(\.props.source)
        expect(reopenedSources == sources, "the reopened note starts from the working links")
        NoteMediaImport.resume(reopenedSources[0], environment: reopened.environment)
        expect(reopened.page.page.blocks.compactMap(\.props.source) == ["Attachments/Big%20Trip.mov", "Attachments/Pasted%20Image.png"],
               "reopening in the same run picks up the copies that finished meanwhile: \(reopened.page.page.blocks.compactMap(\.props.source))")
        expect((try? Data(contentsOf: page.deletingLastPathComponent().appendingPathComponent("Attachments/Pasted Image.png"))) == huge,
               "the huge paste arrived whole")
    }

    static func failedImportKeepsOriginal() {
        let root = folder("failed")
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appendingPathComponent("Sunset.jpg")
        try? Data([0xFF, 0xD8, 0xFF, 1]).write(to: photo)
        let page = root.appendingPathComponent("Notes/Trip.md")
        let file = note(page)
        try? Data("not a folder".utf8).write(to: page.deletingLastPathComponent().appendingPathComponent("Attachments"))
        let session = file.page
        let imports = NoteAttachmentImports.shared
        let dropped = NoteClipboard.blocks(forFiles: [photo], environment: file.environment)
        guard let source = dropped.blocks.first?.props.source else { failTest("the drop makes a block") }
        session.insertBlocks(dropped.blocks, .top(session.page.blocks.count))
        wait { !imports.isPending(source, in: session) }
        expect(session.page.block(dropped.blocks[0].id)?.props.source == source, "a copy that fails keeps the original link")
        expect(imports.landedPath(for: source, in: session) == nil, "nothing claims to have landed")
        expect(imports.takeFailure(of: source, in: session) != nil, "the failure is remembered once")
        expect(imports.takeFailure(of: source, in: session) == nil, "and only reported once")
        let media = NoteMediaSource(source) { file.environment.resolve($0) }
        expect(media.readiness(for: .image, importing: false) == .ready, "the block still shows the original, not a broken card")
        expect(media.readiness(for: .file, importing: false) == .ready, "even for plain files")
        expect(media.readiness(for: .file, importing: true) == .importing, "files shimmer only while the copy runs")
        expect(media.readiness(for: .pdf, importing: true) == .ready, "PDFs read from the original while the copy runs")
        try? FileManager.default.removeItem(at: photo)
        expect(media.readiness(for: .image, importing: false) == .missing, "it reads as broken only once the original is gone")
        expect(NoteAttachmentError.leftInPlace("Sunset.jpg").errorDescription?.contains("Sunset.jpg") == true, "the heads-up names the file")
    }

    static func crossNotePaste() {
        let root = folder("cross")
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appendingPathComponent("Shared/Beach.png")
        try? FileManager.default.createDirectory(at: photo.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 4, 4, 4])
        try? bytes.write(to: photo)
        let first = note(root.appendingPathComponent("A/Trip.md"))
        let second = note(root.appendingPathComponent("B/Plan.md"))
        let imports = NoteAttachmentImports.shared
        let release = stallImports()
        let dropped = NoteClipboard.blocks(forFiles: [photo], environment: first.environment).blocks
        guard let source = dropped.first?.props.source else { failTest("the drop makes a block") }
        first.page.insertBlocks(dropped, .top(first.page.page.blocks.count))
        let payload = NoteClipboard.payload(for: dropped, inline: false, base: root.appendingPathComponent("A", isDirectory: true), plainTextFile: false)
        guard let data = NoteClipboard.encode(payload.archive), let archive = NoteClipboard.decode(data) else { failTest("the copy round-trips") }
        expect(archive.blocks[0].props.source == source && fileExists(source), "a block copied mid-copy carries a link that works")
        expect(payload.markdown?.contains(source) == true && payload.markdown?.contains("parc-attachment") == false,
               "and so does its Markdown: \(payload.markdown ?? "")")
        let pasted = NoteClipboard.rebase(archive, into: second.environment).map { $0.withFreshIDs() }
        expect(pasted[0].props.source == source && imports.isPending(source, in: second.page), "pasting it into another note starts that note's own copy")
        second.page.insertBlocks(pasted, .top(second.page.page.blocks.count))
        release()
        wait { !imports.isPending(source, in: first.page) && !imports.isPending(source, in: second.page) }
        let secondFolder = root.appendingPathComponent("B", isDirectory: true)
        expect(first.page.page.block(dropped[0].id)?.props.source == "Attachments/Beach.png", "the first note gets its copy")
        expect(second.page.page.block(pasted[0].id)?.props.source == "Attachments/Beach.png", "and the second note gets one too")
        expect((try? Data(contentsOf: secondFolder.appendingPathComponent("Attachments/Beach.png"))) == bytes, "in its own Attachments folder")

        let late = NoteClipboard.rebase(archive, into: second.environment).map { $0.withFreshIDs() }
        second.page.insertBlocks(late, .top(second.page.page.blocks.count))
        wait { second.page.page.block(late[0].id)?.props.source != source }
        expect(second.page.page.block(late[0].id)?.props.source == "Attachments/Beach.png", "pasting the old copy later still lands in Attachments")
        expect(!FileManager.default.fileExists(atPath: secondFolder.appendingPathComponent("Attachments/Beach 2.png").path), "without a duplicate")

        let secret = root.appendingPathComponent("Secrets/id_rsa")
        try? FileManager.default.createDirectory(at: secret.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data([1]).write(to: secret)
        let forged = NoteClipboard.Archive(blocks: [image(secret.absoluteString, kind: .file)], base: nil, inline: false)
        let refused = NoteClipboard.rebase(forged, into: second.environment)
        expect(refused[0].props.source == secret.absoluteString && !imports.isPending(secret.absoluteString, in: second.page),
               "a pasted file link Parc never imported isn't copied anywhere")
    }

    static func movedMidImport() {
        let root = folder("moved")
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appendingPathComponent("Shared/Sunset.png")
        try? FileManager.default.createDirectory(at: photo.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 5, 5, 5])
        try? bytes.write(to: photo)
        let file = note(root.appendingPathComponent("Old/Trip.md"))
        let imports = NoteAttachmentImports.shared
        let release = stallImports()
        let dropped = NoteClipboard.blocks(forFiles: [photo], environment: file.environment).blocks
        guard let source = dropped.first?.props.source else { failTest("the drop makes a block") }
        file.page.insertBlocks(dropped, .top(file.page.page.blocks.count))
        let newFolder = root.appendingPathComponent("New", isDirectory: true)
        try? FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        let destination = newFolder.appendingPathComponent("Trip.md")
        try? FileManager.default.moveItem(at: root.appendingPathComponent("Old/Trip.md"), to: destination)
        file.handle(.moved(destination))
        expect(NoteFilePaths.key(for: file.url) == NoteFilePaths.key(for: destination), "the session follows the note to its new folder")
        release()
        wait { !imports.isPending(source, in: file.page) }
        let landed = file.page.page.block(dropped[0].id)?.props.source
        expect(landed == "Attachments/Sunset.png", "the finished copy is linked from the note's new folder: \(landed ?? "nil")")
        expect((try? Data(contentsOf: newFolder.appendingPathComponent("Attachments/Sunset.png"))) == bytes,
               "and the picture lives in the new folder's Attachments")
        let resolved = landed.flatMap { file.environment.resolve($0) }
        expect(resolved.map { FileManager.default.fileExists(atPath: $0.path) } ?? false, "so the link resolves")
        expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Old/Attachments/Sunset.png").path),
               "and the first copy doesn't linger in the old folder")

        let stranded = root.appendingPathComponent("Old/Attachments/Kept.png")
        try? FileManager.default.createDirectory(at: stranded.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? bytes.write(to: stranded)
        let readOnly = root.appendingPathComponent("Locked/Note.md")
        try? FileManager.default.createDirectory(at: readOnly.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.deletingLastPathComponent().path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.deletingLastPathComponent().path) }
        let fallback = try? NoteAttachmentImports.rebase(stranded, created: true, into: readOnly, discardingOriginal: true)
        expect(fallback == NoteAttachments.Placement(path: "../Old/Attachments/Kept.png", created: true),
               "when the copy can't be made, the link points back to where the picture landed")
        expect(FileManager.default.fileExists(atPath: stranded.path), "and that picture stays put")
        let shared = root.appendingPathComponent("Old/Attachments/Shared.png")
        try? bytes.write(to: shared)
        let kept = try? NoteAttachmentImports.rebase(shared, created: false, into: destination, discardingOriginal: false)
        expect(kept == NoteAttachments.Placement(path: "Attachments/Shared.png", created: true) && FileManager.default.fileExists(atPath: shared.path),
               "a picture this import didn't make is copied, never taken away")
    }

    static func stagedResume() {
        let root = folder("resume")
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(repeating: 0x42, count: 64)
        guard let staged = try? NoteAttachments.stage(bytes, fileExtension: "gif", suggestedName: "Pasted Image") else { failTest("staging works") }
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        let page = root.appendingPathComponent("Notes/Left Open.md")
        let file = note(page, "![](" + staged.absoluteString + ")\n")
        let session = file.page
        guard let source = session.page.blocks.first?.props.source else { failTest("the note has its picture") }
        expect(source == staged.absoluteString, "a note saved mid-copy opens with the temporary link: \(source)")
        NoteMediaImport.resume(source, environment: file.environment)
        expect(NoteAttachmentImports.shared.isPending(source, in: session), "showing it picks the copy back up")
        wait { !NoteAttachmentImports.shared.isPending(source, in: session) }
        expect(session.page.blocks.first?.props.source == "Attachments/Pasted%20Image.gif", "and finishes it into Attachments")
        NoteMediaImport.resume("Attachments/Pasted%20Image.gif", environment: file.environment)
        expect(!NoteAttachmentImports.shared.isPending("Attachments/Pasted%20Image.gif", in: session), "settled sources are left alone")
    }

    static func asyncReplace() {
        let root = folder("replace")
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appendingPathComponent("Pick/Beach.png")
        let sky = root.appendingPathComponent("Pick/Sky.jpg")
        try? FileManager.default.createDirectory(at: photo.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data([0x89, 0x50, 0x4E, 0x47, 5]).write(to: photo)
        try? Data([0xFF, 0xD8, 0xFF, 6]).write(to: sky)
        let page = root.appendingPathComponent("Notes/Trip.md")
        try? FileManager.default.createDirectory(at: page.deletingLastPathComponent().appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        try? Data([1]).write(to: page.deletingLastPathComponent().appendingPathComponent("Attachments/Old.png"))
        let file = note(page, "![](Attachments/Old.png)\n")
        let session = file.page
        let imports = NoteAttachmentImports.shared
        guard let id = session.page.blocks.first?.id else { failTest("the note has a picture") }
        let attachments = page.deletingLastPathComponent().appendingPathComponent("Attachments")

        var release = stallImports()
        do { try NoteMediaImport.replace(id, with: photo, name: "Replace Image", in: session, environment: file.environment) }
        catch { failTest("replace starts: \(error)") }
        guard let source = session.page.block(id)?.props.source else { failTest("the block has a source") }
        expect(source.hasPrefix("file://") && fileExists(source) && imports.isPending(source, in: session),
               "Replace swaps in the picked file right away and copies it in the background")
        expect(!FileManager.default.fileExists(atPath: attachments.appendingPathComponent("Beach.png").path), "nothing was copied on the main thread")
        expect(session.undoActionName == "Replace Image", "it's one undo step")
        release()
        wait { !imports.isPending(source, in: session) }
        expect(session.page.block(id)?.props.source == "Attachments/Beach.png", "the copy lands as the source")
        session.undo()
        expect(session.page.block(id)?.props.source == "Attachments/Old.png", "undo puts the old picture back in one go")
        session.redo()
        expect(session.page.block(id)?.props.source == "Attachments/Beach.png", "redo brings the copied one back")

        release = stallImports()
        do { try NoteMediaImport.replace(id, with: sky, name: "Replace Image", in: session, environment: file.environment) }
        catch { failTest("a second replace starts: \(error)") }
        guard let skySource = session.page.block(id)?.props.source else { failTest("the block has the new source") }
        session.undo()
        release()
        wait { !imports.isPending(skySource, in: session) }
        expect(session.page.block(id)?.props.source == "Attachments/Beach.png", "undoing mid-copy keeps the previous picture")
        session.redo()
        wait { session.page.block(id)?.props.source != skySource }
        expect(session.page.block(id)?.props.source == "Attachments/Sky.jpg", "redo after the copy lands heals to the copied file")

        release = stallImports()
        guard let coverSource = try? NoteMediaImport.source(importing: sky, environment: file.environment, scoped: true) else { failTest("upload starts") }
        session.updateSettings(name: "Change Cover") { $0.cover = NoteCover(source: coverSource, position: 0.5) }
        expect(coverSource.hasPrefix("file://") && imports.isPending(coverSource, in: session), "a cover upload shows the picked file while it copies")
        release()
        wait { !imports.isPending(coverSource, in: session) }
        expect(session.page.settings.cover?.source == "Attachments/Sky.jpg", "the cover settles on the copy")
        session.undo()
        expect(session.page.settings.cover == nil, "undo removes the cover in one step")
        session.redo()
        expect(session.page.settings.cover?.source == "Attachments/Sky.jpg", "redo brings back the copied cover")
    }

    static func sniffing() {
        let markdown = [
            "# Heading", "## Two\nbody", "- one\n- two", "* star item", "1. first\n2. second", "> quoted",
            "```swift\nlet x = 1\n```", "| a | b |\n|---|---|\n| 1 | 2 |", "Some **bold** text", "Some *italic* words",
            "See [docs](https://example.com)", "![cat](cat.png)", "Use `code` here", "~~gone~~", "- [ ] task",
            "---", "==highlight==", "a <u>line</u>", "$$\nx^2\n$$",
        ]
        for sample in markdown { expect(NoteClipboard.looksLikeMarkdown(sample), "looks like Markdown: \(sample.debugDescription)") }
        let plain = [
            "Hello world", "Price is 5 * 3 * 2", "snake_case_name and other_name", "mail@example.com", "-5 degrees today",
            "#hashtag", "2024 was a year", "Wait... what?", "C:\\Users\\name", "a*b*c", "", "x__y__z",
        ]
        for sample in plain { expect(!NoteClipboard.looksLikeMarkdown(sample), "plain text: \(sample.debugDescription)") }
    }

    static func links() {
        expect(NoteClipboard.webURL(in: "https://parc.example/page?q=1") != nil, "https is a link")
        expect(NoteClipboard.webURL(in: "  http://example.com  \n") != nil, "surrounding space is fine")
        expect(NoteClipboard.webURL(in: "www.example.com")?.absoluteString == "https://www.example.com", "www gets https")
        expect(NoteClipboard.webURL(in: "mailto:hi@example.com") != nil, "mailto is a link")
        expect(NoteClipboard.webURL(in: "https://example.com and more") == nil, "sentences aren't links")
        expect(NoteClipboard.webURL(in: "ftp://example.com") == nil, "only web links")
        expect(NoteClipboard.webURL(in: "https://nodot") == nil, "hosts need a dot")
        expect(NoteClipboard.webURL(in: "file:///tmp/a.md") == nil, "file URLs aren't web links")
        expect(NoteClipboard.isEmbeddable(URL(string: "https://www.youtube.com/watch?v=1")!), "YouTube embeds")
        expect(NoteClipboard.isEmbeddable(URL(string: "https://youtu.be/abc")!), "short YouTube embeds")
        expect(NoteClipboard.isEmbeddable(URL(string: "https://www.google.com/maps/place/x")!), "Google Maps embeds")
        expect(!NoteClipboard.isEmbeddable(URL(string: "https://www.google.com/search?q=x")!), "Google search doesn't")
        expect(!NoteClipboard.isEmbeddable(URL(string: "https://example.com")!), "random sites don't embed")
        expect(!NoteClipboard.isEmbeddable(URL(string: "https://notyoutube.com/x")!), "lookalike hosts don't embed")
    }

    static func choices() {
        let archive = NoteClipboard.Archive(blocks: [.paragraph("x")], base: nil, inline: true)
        var reading = NoteClipboard.Reading(archive: archive, html: "<b>x</b>", string: "x")
        expect(NoteClipboard.choose(reading, plainOnly: false, canReadHTML: true) == .blocks, "Parc blocks win")
        expect(NoteClipboard.choose(reading, plainOnly: true, canReadHTML: true) == .plainText, "plain paste ignores blocks")
        reading = NoteClipboard.Reading(files: [URL(fileURLWithPath: "/tmp/a.png")], string: "a.png")
        expect(NoteClipboard.choose(reading, plainOnly: false, canReadHTML: true) == .files, "Finder copies paste files")
        reading = NoteClipboard.Reading(image: Data([1]), imageExtension: "tiff", html: "<img src=\"x.png\">", string: nil,
                                        url: URL(string: "https://example.com/x.png"))
        expect(NoteClipboard.choose(reading, plainOnly: false, canReadHTML: true) == .image, "copied images paste as images")
        reading = NoteClipboard.Reading(image: Data([1]), imageExtension: "png", html: "<p>Caption words</p>", string: "Caption words")
        expect(NoteClipboard.choose(reading, plainOnly: false, canReadHTML: true) == .html, "rich text with a picture stays rich")
        expect(NoteClipboard.choose(reading, plainOnly: false, canReadHTML: false) == .plainText, "no HTML reader falls back to text")
        reading = NoteClipboard.Reading(html: "<h1>Title</h1>", string: "Title")
        expect(NoteClipboard.choose(reading, plainOnly: false, canReadHTML: true) == .html, "web HTML maps to blocks")
        reading = NoteClipboard.Reading(string: "https://example.com/a")
        expect(NoteClipboard.choose(reading, plainOnly: false, canReadHTML: true) == .url, "a lone URL offers the link menu")
        expect(NoteClipboard.choose(reading, plainOnly: true, canReadHTML: true) == .plainText, "plain paste skips the link menu")
        let video = URL(string: "https://www.youtube.com/watch?v=KlwA8U-1wzM")!
        expect(NoteClipboard.playsAsEmbed(video, kind: .video), "a YouTube page given to a video block plays as an embed")
        expect(!NoteClipboard.playsAsEmbed(URL(string: "https://example.com/clip.mp4")!, kind: .video), "a real video file stays a video")
        expect(!NoteClipboard.playsAsEmbed(video, kind: .image), "only video and audio blocks turn into embeds")
        reading = NoteClipboard.Reading(html: "<span style=\"color: blue\">https://example.com/a.mp3</span>", string: "https://example.com/a.mp3")
        expect(NoteClipboard.choose(reading, plainOnly: false, canReadHTML: true) == .url, "a URL copied as rich text from another app is still a link")
        reading = NoteClipboard.Reading(string: "# Notes\n- one")
        expect(NoteClipboard.choose(reading, plainOnly: false, canReadHTML: true) == .markdown, "Markdown text parses")
        reading = NoteClipboard.Reading(string: "just words")
        expect(NoteClipboard.choose(reading, plainOnly: false, canReadHTML: true) == .plainText, "plain words stay plain")
        reading = NoteClipboard.Reading(url: URL(string: "https://example.com")!)
        expect(NoteClipboard.choose(reading, plainOnly: false, canReadHTML: true) == .url, "URL-only pasteboards are links")
        expect(NoteClipboard.choose(NoteClipboard.Reading(), plainOnly: false, canReadHTML: true) == .nothing, "empty means nothing")
        expect(NoteClipboard.plainString(NoteClipboard.Reading(files: [URL(fileURLWithPath: "/tmp/a.txt")])) == "/tmp/a.txt", "plain files paste paths")
        expect(!NoteClipboard.htmlHasText("<img src=\"a\"><br>&nbsp;"), "picture-only HTML has no text")
        expect(NoteClipboard.htmlHasText("<style>p{}</style><p>hi</p>"), "HTML with words has text")
    }

    static func payloads() {
        var bold = NoteMarks.plain
        bold.bold = true
        let heading = NoteBlock.heading(2, NoteText(pieces: [("big ", .plain), ("word", bold)]))
        let inline = NoteClipboard.payload(for: [heading], inline: true, base: nil, plainTextFile: false)
        expect(inline.plainText == "big word", "inline copies are plain words, got \(inline.plainText.debugDescription)")
        expect(inline.archive.inline && inline.markdown != nil, "inline copies keep Markdown and blocks")
        let blocks = NoteClipboard.payload(for: [.paragraph("one"), .paragraph("two")], inline: false, base: nil, plainTextFile: false)
        expect(blocks.plainText == blocks.markdown && !blocks.plainText.hasSuffix("\n"), "block copies are Markdown without a trailing newline")
        let plainFile = NoteClipboard.payload(for: [.paragraph("one"), .paragraph("two")], inline: false, base: nil, plainTextFile: true)
        expect(plainFile.markdown == nil && plainFile.plainText == "one\ntwo", "plain-text notes copy plain lines")
        let code = NoteBlock(.code, text: "let x = 1")
        expect(NoteClipboard.payload(for: [code], inline: true, base: nil, plainTextFile: false).plainText == "let x = 1", "code copies its source")
    }

    static func roundTrip() {
        let board = NSPasteboard(name: NSPasteboard.Name("parc.notes.tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let base = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)
        let payload = NoteClipboard.payload(for: [.paragraph("one"), NoteBlock(.todo, text: "two")], inline: false,
                                            base: base, plainTextFile: false, html: "<p>one</p>")
        expect(NoteClipboard.write(payload, to: board), "writing succeeds")
        let types = board.types ?? []
        expect(types.contains(NoteClipboard.blocksType) && types.contains(NoteClipboard.markdownType)
               && types.contains(.string) && types.contains(.html) && types.contains(.rtf), "every flavour is declared: \(types)")
        let reading = NoteClipboard.read(board)
        expect(reading.archive?.blocks.map(\.kind) == [.paragraph, .todo], "blocks survive the round trip")
        expect(reading.archive?.base == base, "the source folder rides along")
        expect(reading.string == payload.plainText && reading.html == "<p>one</p>", "text and HTML read back")
        board.clearContents()
        board.setString("https://example.com/x", forType: .string)
        expect(NoteClipboard.choose(NoteClipboard.read(board), plainOnly: false, canReadHTML: true) == .url, "pasted URLs read as links")
        board.clearContents()
        board.setData(Data("garbage".utf8), forType: NoteClipboard.blocksType)
        board.setString("fallback", forType: .string)
        let broken = NoteClipboard.read(board)
        expect(broken.archive == nil && NoteClipboard.choose(broken, plainOnly: false, canReadHTML: true) == .plainText, "broken archives fall back to text")
        board.clearContents()
        board.declareTypes([.URL, NoteClipboard.draggedImageHTMLType], owner: nil)
        board.setString("https://example.com/cat.jpg", forType: .URL)
        board.setString("<img src=\"https://example.com/cat.jpg\">", forType: NoteClipboard.draggedImageHTMLType)
        let dragged = NoteClipboard.read(board)
        expect(dragged.html?.contains("cat.jpg") == true, "images dragged from a page carry their markup")
        expect(NoteClipboard.choose(dragged, plainOnly: false, canReadHTML: true) == .html, "images dragged from a page become image blocks")
    }

    static func plainLines() {
        let blocks = NoteClipboard.plainBlocks("\n\none\r\ntwo\n\n\n\nthree\n\n")
        expect(blocks.map(\.text.string) == ["one", "two", "", "three"], "plain lines become paragraphs: \(blocks.map(\.text.string))")
        expect(blocks.allSatisfy { $0.kind == .paragraph }, "plain lines are paragraphs")
        expect(!NoteClipboard.markdownBlocks("# Title").isEmpty, "Markdown parses to blocks")
    }

    static func files() {
        let environment = RecordingEnvironment(documentURL: URL(fileURLWithPath: "/tmp/notes/Page.md"))
        let urls = [URL(fileURLWithPath: "/tmp/in/photo.PNG"), URL(fileURLWithPath: "/tmp/in/clip.mov"),
                    URL(fileURLWithPath: "/tmp/in/song.mp3"), URL(fileURLWithPath: "/tmp/in/report.pdf"),
                    URL(fileURLWithPath: "/tmp/notes/Other.md")]
        let result = NoteClipboard.blocks(forFiles: urls, environment: environment)
        expect(result.failures.isEmpty, "no failures")
        expect(result.blocks.map(\.kind) == [.image, .video, .audio, .pdf, .pageLink], "files map to blocks: \(result.blocks.map(\.kind))")
        expect(result.blocks[0].props.source == "Attachments/photo.PNG", "images are imported")
        expect(result.blocks[3].props.alt == "report.pdf" && result.blocks[3].props.caption.isEmpty, "PDFs keep their names")
        expect(result.blocks[4].props.target == "Other.md" && result.blocks[4].text.string == "Other", "notes become page links")
        expect(environment.imported.count == 4, "only attachments are copied")
        let png = try? NoteClipboard.imageBlock(data: Data([0x89]), fileExtension: "png", environment: environment)
        expect(png?.kind == .image && png?.props.source == "Attachments/pasted.png", "pasted images become image blocks")
    }

    static func inlineMedia() {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let decoded = NoteClipboard.decodeDataURL("data:image/png;base64," + png.base64EncodedString())
        expect(decoded?.data == png && decoded?.fileExtension == "png", "base64 data URLs decode")
        expect(NoteClipboard.decodeDataURL("data:image/jpeg;base64,/9j/")?.fileExtension == "jpg", "JPEG data gets a jpg extension")
        expect(NoteClipboard.decodeDataURL("data:text/html,<b>x</b>") == nil, "only media data URLs import")
        expect(NoteClipboard.decodeDataURL("https://example.com/a.png") == nil, "web sources stay put")
        let environment = RecordingEnvironment(documentURL: URL(fileURLWithPath: "/tmp/notes/Page.md"))
        var image = NoteBlock(.image)
        image.props.source = "data:image/png;base64," + png.base64EncodedString()
        var web = NoteBlock(.image)
        web.props.source = "https://example.com/dog.png"
        let toggle = NoteBlock(.toggle, text: "Pics", children: [image, web])
        let result = NoteClipboard.importInlineMedia([toggle], environment: environment)
        expect(result.failures.isEmpty, "imports succeed")
        expect(result.blocks[0].children[0].props.source == "Attachments/pasted.png", "inline images land in Attachments")
        expect(result.blocks[0].children[1].props.source == "https://example.com/dog.png", "remote images keep their URL")
        expect(environment.importedData.count == 1 && environment.importedData[0].0 == png, "the decoded bytes are what's imported")
    }

    static func rebasing() {
        let environment = RecordingEnvironment(documentURL: URL(fileURLWithPath: "/tmp/notes/sub/Page.md"))
        var image = NoteBlock(.image)
        image.props.source = "Attachments/cat.png"
        var link = NoteBlock(.pageLink, text: "Sibling")
        link.props.target = "Sibling.md"
        var web = NoteBlock(.image)
        web.props.source = "https://example.com/dog.png"
        var linked = NoteMarks.plain
        linked.link = "Other.md"
        let text = NoteBlock.paragraph(NoteText(pieces: [("go ", .plain), ("there", linked)]) + .atom(.page(target: "Third.md", title: "Third")))
        let archive = NoteClipboard.Archive(blocks: [image, link, web, text], base: URL(fileURLWithPath: "/tmp/notes", isDirectory: true), inline: false)
        let rebased = NoteClipboard.rebase(archive, into: environment)
        expect(environment.imported.map(\.path) == ["/tmp/notes/Attachments/cat.png"], "relative media is copied over")
        expect(rebased[0].props.source == "Attachments/cat.png", "media points at the new copy")
        expect(rebased[1].props.target == "/tmp/notes/Sibling.md", "page links are rebased: \(rebased[1].props.target ?? "nil")")
        expect(rebased[2].props.source == "https://example.com/dog.png", "web media is untouched")
        expect(rebased[3].text.runs().contains { $0.marks.link == "/tmp/notes/Other.md" }, "relative links are rebased")
        expect(rebased[3].text.runs().contains { $0.marks.atom == .page(target: "/tmp/notes/Third.md", title: "Third") }, "page mentions are rebased")
        let same = NoteClipboard.Archive(blocks: [image], base: URL(fileURLWithPath: "/tmp/notes/sub", isDirectory: true), inline: false)
        expect(NoteClipboard.rebase(same, into: environment) == [image], "same folder needs no rebasing")
    }
}
