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
        print("NoteClipboardTests passed")
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
        expect(result.blocks.map(\.kind) == [.image, .video, .audio, .file, .pageLink], "files map to blocks: \(result.blocks.map(\.kind))")
        expect(result.blocks[0].props.source == "Attachments/photo.PNG", "images are imported")
        expect(result.blocks[3].props.caption.string == "report.pdf", "files keep their names")
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
