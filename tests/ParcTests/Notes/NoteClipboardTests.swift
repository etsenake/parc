import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
final class NoteClipboardRecordingEnvironment: NoteEnvironment {
    let documentURL: URL?
    let isPlainText = false
    let files = IsolatedNoteFiles.make()
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
    func searchNotes(_ query: String, limit: Int) -> [NoteReference] { []  }
    func linkTarget(for note: URL) -> String {
        let folder = documentURL!.deletingLastPathComponent().standardizedFileURL.path + "/"
        let path = note.standardizedFileURL.path
        return path.hasPrefix(folder) ? String(path.dropFirst(folder.count)) : path
    }
    func resolveNoteLink(_ target: String) -> URL? { nil }
}

@MainActor
struct NoteClipboardTests {
    typealias Environment = NoteClipboardRecordingEnvironment

    func image(_ source: String?, kind: NoteBlockKind = .image) -> NoteBlock {
        var block = NoteBlock(kind)
        block.props.source = source
        return block
    }

    @Test(arguments: [
        "# Heading", "## Two\nbody", "- one\n- two", "* star item", "1. first\n2. second", "> quoted", "```swift\nlet x = 1\n```",
        "| a | b |\n|---|---|\n| 1 | 2 |", "Some **bold** text", "Some *italic* words", "See [docs](https://example.com)", "![cat](cat.png)",
        "Use `code` here", "~~gone~~", "- [ ] task", "---", "==highlight==", "a <u>line</u>", "$$\nx^2\n$$",
    ])
    func textThatLooksLikeMarkdownIsRecognised(sample: String) { #expect(NoteClipboard.looksLikeMarkdown(sample)) }

    @Test(arguments: [
        "Hello world", "Price is 5 * 3 * 2", "snake_case_name and other_name", "mail@example.com", "-5 degrees today", "#hashtag", "2024 was a year",
        "Wait... what?", "C:\\Users\\name", "a*b*c", "", "x__y__z",
    ])
    func plainTextIsNotMarkdown(sample: String) { #expect(!NoteClipboard.looksLikeMarkdown(sample)) }

    @Test(arguments: ["https://parc.example/page?q=1", "  http://example.com  \n", "mailto:hi@example.com"])
    func webLinksAreRecognised(text: String) { #expect(NoteClipboard.webURL(in: text) != nil) }

    @Test func wwwGetsHttps() { #expect(NoteClipboard.webURL(in: "www.example.com")?.absoluteString == "https://www.example.com") }

    @Test(arguments: ["https://example.com and more", "ftp://example.com", "https://nodot", "file:///tmp/a.md"])
    func textThatIsNotAWebLinkIsRefused(text: String) { #expect(NoteClipboard.webURL(in: text) == nil) }

    @Test(arguments: [
        ("https://www.youtube.com/watch?v=1", true), ("https://youtu.be/abc", true), ("https://www.google.com/maps/place/x", true),
        ("https://www.google.com/search?q=x", false), ("https://example.com", false), ("https://notyoutube.com/x", false),
    ])
    func onlyKnownSitesEmbed(address: String, embeds: Bool) { #expect(NoteClipboard.isEmbeddable(URL(string: address)!) == embeds) }

    func choose(_ reading: NoteClipboard.Reading, plainOnly: Bool = false, canReadHTML: Bool = true) -> NoteClipboard.Choice {
        NoteClipboard.choose(reading, plainOnly: plainOnly, canReadHTML: canReadHTML)
    }

    var blockReading: NoteClipboard.Reading {
        NoteClipboard.Reading(archive: NoteClipboard.Archive(blocks: [.paragraph("x")], base: nil, inline: true), html: "<b>x</b>", string: "x")
    }

    @Test func parcBlocksWin() { #expect(choose(blockReading) == .blocks) }

    @Test func plainPasteIgnoresBlocks() { #expect(choose(blockReading, plainOnly: true) == .plainText) }

    @Test func finderCopiesPasteFiles() {
        #expect(choose(NoteClipboard.Reading(files: [URL(fileURLWithPath: "/tmp/a.png")], string: "a.png")) == .files)
    }

    @Test func copiedImagesPasteAsImages() {
        #expect(choose(NoteClipboard.Reading(image: Data([1]), imageExtension: "tiff", html: "<img src=\"x.png\">", string: nil,
                                             url: URL(string: "https://example.com/x.png"))) == .image)
    }

    @Test func richTextWithAPictureStaysRich() {
        let reading = NoteClipboard.Reading(image: Data([1]), imageExtension: "png", html: "<p>Caption words</p>", string: "Caption words")
        #expect(choose(reading) == .html)
    }

    @Test func noHTMLReaderFallsBackToText() {
        let reading = NoteClipboard.Reading(image: Data([1]), imageExtension: "png", html: "<p>Caption words</p>", string: "Caption words")
        #expect(choose(reading, canReadHTML: false) == .plainText)
    }

    @Test func webHTMLMapsToBlocks() { #expect(choose(NoteClipboard.Reading(html: "<h1>Title</h1>", string: "Title")) == .html) }

    @Test func aLoneURLOffersTheLinkMenu() { #expect(choose(NoteClipboard.Reading(string: "https://example.com/a")) == .url) }

    @Test func plainPasteSkipsTheLinkMenu() { #expect(choose(NoteClipboard.Reading(string: "https://example.com/a"), plainOnly: true) == .plainText) }

    @Test func aURLCopiedAsRichTextFromAnotherAppIsStillALink() {
        #expect(choose(NoteClipboard.Reading(html: "<span style=\"color: blue\">https://example.com/a.mp3</span>", string: "https://example.com/a.mp3")) == .url)
    }

    @Test func markdownTextParses() { #expect(choose(NoteClipboard.Reading(string: "# Notes\n- one")) == .markdown) }

    @Test func plainWordsStayPlain() { #expect(choose(NoteClipboard.Reading(string: "just words")) == .plainText) }

    @Test func urlOnlyPasteboardsAreLinks() { #expect(choose(NoteClipboard.Reading(url: URL(string: "https://example.com")!)) == .url) }

    @Test func emptyMeansNothing() { #expect(choose(NoteClipboard.Reading()) == .nothing) }

    @Test func plainFilesPastePaths() {
        #expect(NoteClipboard.plainString(NoteClipboard.Reading(files: [URL(fileURLWithPath: "/tmp/a.txt")])) == "/tmp/a.txt")
    }

    @Test func pictureOnlyHTMLHasNoText() { #expect(!NoteClipboard.htmlHasText("<img src=\"a\"><br>&nbsp;")) }

    @Test func htmlWithWordsHasText() { #expect(NoteClipboard.htmlHasText("<style>p{}</style><p>hi</p>")) }

    @Test func aYouTubePageGivenToAVideoBlockPlaysAsAnEmbed() {
        #expect(NoteClipboard.playsAsEmbed(URL(string: "https://www.youtube.com/watch?v=KlwA8U-1wzM")!, kind: .video))
    }

    @Test func aRealVideoFileStaysAVideo() { #expect(!NoteClipboard.playsAsEmbed(URL(string: "https://example.com/clip.mp4")!, kind: .video)) }

    @Test func onlyVideoAndAudioBlocksTurnIntoEmbeds() {
        #expect(!NoteClipboard.playsAsEmbed(URL(string: "https://www.youtube.com/watch?v=KlwA8U-1wzM")!, kind: .image))
    }

    @Test(arguments: [
        ("image/jpeg", NoteBlockKind.image), ("video/mp4; codecs=avc1", .video), ("Audio/MPEG", .audio), ("application/pdf", .pdf),
    ] as [(String, NoteBlockKind)])
    func aServersContentTypeNamesTheMedia(type: String, kind: NoteBlockKind) { #expect(NoteClipboard.mediaKind(forContentType: type) == kind) }

    @Test func webPagesAndMissingTypesOfferNothingExtra() {
        #expect(NoteClipboard.mediaKind(forContentType: "text/html; charset=utf-8") == nil)
        #expect(NoteClipboard.mediaKind(forContentType: nil) == nil)
    }

    var headingPayload: NoteBlock {
        var bold = NoteMarks.plain
        bold.bold = true
        return NoteBlock.heading(2, NoteText(pieces: [("big ", .plain), ("word", bold)]))
    }

    @Test func inlineCopiesArePlainWords() {
        #expect(NoteClipboard.payload(for: [headingPayload], inline: true, base: nil, plainTextFile: false).plainText == "big word")
    }

    @Test func inlineCopiesKeepMarkdownAndBlocks() {
        let inline = NoteClipboard.payload(for: [headingPayload], inline: true, base: nil, plainTextFile: false)
        #expect(inline.archive.inline)
        #expect(inline.markdown != nil)
    }

    @Test func blockCopiesAreMarkdownWithoutATrailingNewline() {
        let blocks = NoteClipboard.payload(for: [.paragraph("one"), .paragraph("two")], inline: false, base: nil, plainTextFile: false)
        #expect(blocks.plainText == blocks.markdown)
        #expect(!blocks.plainText.hasSuffix("\n"))
    }

    @Test func plainTextNotesCopyPlainLines() {
        let plainFile = NoteClipboard.payload(for: [.paragraph("one"), .paragraph("two")], inline: false, base: nil, plainTextFile: true)
        #expect(plainFile.markdown == nil)
        #expect(plainFile.plainText == "one\ntwo")
    }

    @Test func codeCopiesItsSource() {
        #expect(NoteClipboard.payload(for: [NoteBlock(.code, text: "let x = 1")], inline: true, base: nil, plainTextFile: false).plainText == "let x = 1")
    }

    @MainActor struct Board {
        let board = NSPasteboard(name: NSPasteboard.Name("parc.notes.tests.\(UUID().uuidString)"))
        let base = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)
        let payload: NoteClipboard.Payload

        init() {
            payload = NoteClipboard.payload(for: [.paragraph("one"), NoteBlock(.todo, text: "two")], inline: false, base: base, plainTextFile: false, html: "<p>one</p>")
        }

        func finish() { board.releaseGlobally() }
    }

    @Test func writingSucceedsAndDeclaresEveryFlavour() {
        let fixture = Board()
        defer { fixture.finish() }
        #expect(NoteClipboard.write(fixture.payload, to: fixture.board))
        let types = fixture.board.types ?? []
        #expect(types.contains(NoteClipboard.blocksType))
        #expect(types.contains(NoteClipboard.markdownType))
        #expect(types.contains(.string))
        #expect(types.contains(.html))
        #expect(types.contains(.rtf))
    }

    @Test func blocksSurviveTheRoundTripWithTheirSourceFolder() {
        let fixture = Board()
        defer { fixture.finish() }
        _ = NoteClipboard.write(fixture.payload, to: fixture.board)
        let reading = NoteClipboard.read(fixture.board)
        #expect(reading.archive?.blocks.map(\.kind) == [.paragraph, .todo])
        #expect(reading.archive?.base == fixture.base)
        #expect(reading.string == fixture.payload.plainText)
        #expect(reading.html == "<p>one</p>")
    }

    @Test func pastedURLsReadAsLinks() {
        let fixture = Board()
        defer { fixture.finish() }
        fixture.board.clearContents()
        fixture.board.setString("https://example.com/x", forType: .string)
        #expect(choose(NoteClipboard.read(fixture.board)) == .url)
    }

    @Test func brokenArchivesFallBackToText() {
        let fixture = Board()
        defer { fixture.finish() }
        fixture.board.clearContents()
        fixture.board.setData(Data("garbage".utf8), forType: NoteClipboard.blocksType)
        fixture.board.setString("fallback", forType: .string)
        let broken = NoteClipboard.read(fixture.board)
        #expect(broken.archive == nil)
        #expect(choose(broken) == .plainText)
    }

    @Test func imagesDraggedFromAPageBecomeImageBlocks() {
        let fixture = Board()
        defer { fixture.finish() }
        fixture.board.clearContents()
        fixture.board.declareTypes([.URL, NoteClipboard.draggedImageHTMLType], owner: nil)
        fixture.board.setString("https://example.com/cat.jpg", forType: .URL)
        fixture.board.setString("<img src=\"https://example.com/cat.jpg\">", forType: NoteClipboard.draggedImageHTMLType)
        let dragged = NoteClipboard.read(fixture.board)
        #expect(dragged.html?.contains("cat.jpg") == true)
        #expect(choose(dragged) == .html)
    }

    @Test func plainLinesBecomeParagraphs() {
        let blocks = NoteClipboard.plainBlocks("\n\none\r\ntwo\n\n\n\nthree\n\n")
        #expect(blocks.map(\.text.string) == ["one", "two", "", "three"])
        #expect(blocks.allSatisfy { $0.kind == .paragraph })
    }

    @Test func markdownParsesToBlocks() { #expect(!NoteClipboard.markdownBlocks("# Title").isEmpty) }

    func fileBlocks() -> ((blocks: [NoteBlock], failures: [Error]), Environment) {
        let environment = Environment(documentURL: URL(fileURLWithPath: "/tmp/notes/Page.md"))
        let urls = [URL(fileURLWithPath: "/tmp/in/photo.PNG"), URL(fileURLWithPath: "/tmp/in/clip.mov"), URL(fileURLWithPath: "/tmp/in/song.mp3"),
                    URL(fileURLWithPath: "/tmp/in/report.pdf"), URL(fileURLWithPath: "/tmp/notes/Other.md")]
        return (NoteClipboard.blocks(forFiles: urls, environment: environment), environment)
    }

    @Test func filesMapToBlocks() {
        let (result, _) = fileBlocks()
        #expect(result.failures.isEmpty)
        #expect(result.blocks.map(\.kind) == [.image, .video, .audio, .pdf, .pageLink])
    }

    @Test func imagesAreImported() { #expect(fileBlocks().0.blocks[0].props.source == "Attachments/photo.PNG") }

    @Test func pdfsKeepTheirNames() {
        let pdf = fileBlocks().0.blocks[3]
        #expect(pdf.props.alt == "report.pdf")
        #expect(pdf.props.caption.isEmpty)
    }

    @Test func notesBecomePageLinks() {
        let link = fileBlocks().0.blocks[4]
        #expect(link.props.target == "Other.md")
        #expect(link.text.string == "Other")
    }

    @Test func onlyAttachmentsAreCopied() { #expect(fileBlocks().1.imported.count == 4) }

    @Test func pastedImagesBecomeImageBlocks() throws {
        let environment = Environment(documentURL: URL(fileURLWithPath: "/tmp/notes/Page.md"))
        let png = try NoteClipboard.imageBlock(data: Data([0x89]), fileExtension: "png", environment: environment)
        #expect(png.kind == .image)
        #expect(png.props.source == "Attachments/pasted.png")
    }

    let pngBytes = Data([0x89, 0x50, 0x4E, 0x47])

    @Test func base64DataURLsDecode() {
        let decoded = NoteClipboard.decodeDataURL("data:image/png;base64," + pngBytes.base64EncodedString())
        #expect(decoded?.data == pngBytes)
        #expect(decoded?.fileExtension == "png")
    }

    @Test func jpegDataGetsAJpgExtension() { #expect(NoteClipboard.decodeDataURL("data:image/jpeg;base64,/9j/")?.fileExtension == "jpg") }

    @Test(arguments: ["data:text/html,<b>x</b>", "https://example.com/a.png"])
    func onlyMediaDataURLsImport(text: String) { #expect(NoteClipboard.decodeDataURL(text) == nil) }

    func inlineImport() -> ((blocks: [NoteBlock], failures: [Error]), Environment) {
        let environment = Environment(documentURL: URL(fileURLWithPath: "/tmp/notes/Page.md"))
        var web = NoteBlock(.image)
        web.props.source = "https://example.com/dog.png"
        let toggle = NoteBlock(.toggle, text: "Pics", children: [image("data:image/png;base64," + pngBytes.base64EncodedString()), web])
        return (NoteClipboard.importInlineMedia([toggle], environment: environment), environment)
    }

    @Test func inlineImportsSucceed() { #expect(inlineImport().0.failures.isEmpty) }

    @Test func inlineImagesLandInAttachments() { #expect(inlineImport().0.blocks[0].children[0].props.source == "Attachments/pasted.png") }

    @Test func remoteImagesKeepTheirURL() { #expect(inlineImport().0.blocks[0].children[1].props.source == "https://example.com/dog.png") }

    @Test func theDecodedBytesAreWhatIsImported() {
        let (_, environment) = inlineImport()
        #expect(environment.importedData.count == 1)
        #expect(environment.importedData[0].0 == pngBytes)
    }

    @MainActor struct Rebase {
        let environment = Environment(documentURL: URL(fileURLWithPath: "/tmp/notes/sub/Page.md"))
        let image: NoteBlock
        let rebased: [NoteBlock]

        init() {
            var image = NoteBlock(.image)
            image.props.source = "Attachments/cat.png"
            self.image = image
            var link = NoteBlock(.pageLink, text: "Sibling")
            link.props.target = "Sibling.md"
            var web = NoteBlock(.image)
            web.props.source = "https://example.com/dog.png"
            var linked = NoteMarks.plain
            linked.link = "Other.md"
            let text = NoteBlock.paragraph(NoteText(pieces: [("go ", .plain), ("there", linked)]) + .atom(.page(target: "Third.md", title: "Third")))
            let archive = NoteClipboard.Archive(blocks: [image, link, web, text], base: URL(fileURLWithPath: "/tmp/notes", isDirectory: true), inline: false)
            rebased = NoteClipboard.rebase(archive, into: environment)
        }
    }

    @Test func relativeMediaIsCopiedOver() { #expect(Rebase().environment.imported.map(\.path) == ["/tmp/notes/Attachments/cat.png"]) }

    @Test func mediaPointsAtTheNewCopy() { #expect(Rebase().rebased[0].props.source == "Attachments/cat.png") }

    @Test func pageLinksAreRebased() { #expect(Rebase().rebased[1].props.target == "/tmp/notes/Sibling.md") }

    @Test func webMediaIsUntouched() { #expect(Rebase().rebased[2].props.source == "https://example.com/dog.png") }

    @Test func relativeLinksAreRebased() { #expect(Rebase().rebased[3].text.runs().contains { $0.marks.link == "/tmp/notes/Other.md" }) }

    @Test func pageMentionsAreRebased() {
        #expect(Rebase().rebased[3].text.runs().contains { $0.marks.atom == .page(target: "/tmp/notes/Third.md", title: "Third") })
    }

    @Test func theSameFolderNeedsNoRebasing() {
        let fixture = Rebase()
        let same = NoteClipboard.Archive(blocks: [fixture.image], base: URL(fileURLWithPath: "/tmp/notes/sub", isDirectory: true), inline: false)
        #expect(NoteClipboard.rebase(same, into: fixture.environment) == [fixture.image])
    }

    func scrub(_ html: String) -> String { NoteOfflineHTML.scrub(html) }

    @Test func aRemotePictureBecomesItsAltText() {
        #expect(scrub("<p>Hi <img src=\"https://tracker.example/p.gif\" alt=\"Cat &amp; dog\"> there</p>") == "<p>Hi Cat &amp; dog there</p>")
    }

    @Test func altTextCannotSmuggleMarkupBack() { #expect(scrub("<img alt='<b>x</b>' src=//cdn.example/a.png>") == "&lt;b&gt;x&lt;/b&gt;") }

    @Test(arguments: [
        "<img src=\"file:///tmp/a.png\" alt=\"x\">", "<img src=\"Attachments/a%20b.png\">", "<img src=\"data:image/png;base64,AAAA\">",
        "<a href=\"https://example.com\">link</a>", "<p style=\"color: red\">red</p>", "<span data-color=\"red\">x</span>",
        "<video controls></video>", "<br/>", "<!DOCTYPE html>",
    ])
    func localAndHarmlessMarkupStaysAsItIs(html: String) { #expect(scrub(html) == html) }

    @Test func aBareLessThanIsEscaped() { #expect(scrub("<p>1 < 2</p>") == "<p>1 &lt; 2</p>") }

    @Test(arguments: [
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
    ])
    func aHostileMarkupLosesItsRemoteSubresource(html: String) { #expect(!scrub(html).lowercased().contains("x.example")) }

    @Test func aRemoteVideoKeepsItsElement() {
        #expect(scrub("<video src=\"https://x.example/v.mp4\" controls></video>") == "<video controls></video>")
    }

    @Test func aLocalPictureJustLosesItsRemoteExtraSizes() {
        #expect(scrub("<img src=\"a.png\" srcset=\"https://x.example/a2.png 2x\" alt=\"pic\">") == "<img src=\"a.png\" alt=\"pic\">")
    }

    @Test func droppedFramesDoNotSwallowWhatFollows() {
        #expect(scrub("<iframe src=\"https://x.example\">fallback</iframe><p>after</p>") == "<p>after</p>")
    }

    @Test func localCSSImagesStay() {
        let css = "p { color: red; background: url(Attachments/bg.png) }"
        #expect(NoteOfflineHTML.offlineCSS(css) == css)
    }

    @MainActor struct RefusalFolders {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-clipboard-rebase-" + UUID().uuidString, isDirectory: true)
        let source: URL
        let secrets: URL

        init() {
            source = root.appendingPathComponent("Source", isDirectory: true)
            secrets = root.appendingPathComponent("Secrets", isDirectory: true)
            let manager = FileManager.default
            try? manager.createDirectory(at: source.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
            try? manager.createDirectory(at: source.appendingPathComponent(".ssh"), withIntermediateDirectories: true)
            try? manager.createDirectory(at: secrets, withIntermediateDirectories: true)
            try? Data([1]).write(to: source.appendingPathComponent("Attachments/cat.png"))
            try? Data([2]).write(to: secrets.appendingPathComponent("id_rsa"))
            try? Data([3]).write(to: source.appendingPathComponent(".ssh/id_rsa"))
            try? manager.createSymbolicLink(at: source.appendingPathComponent("Attachments/sneaky.png"), withDestinationURL: secrets.appendingPathComponent("id_rsa"))
        }

        func finish() { try? FileManager.default.removeItem(at: root) }

        func imported(base: URL, _ paths: [String]) -> (blocks: [NoteBlock], copied: [String]) {
            let environment = Environment(documentURL: root.appendingPathComponent("Elsewhere/Page.md"))
            let blocks = paths.map { path -> NoteBlock in
                var block = NoteBlock(.file)
                block.props.source = path
                return block
            }
            let rebased = NoteClipboard.rebase(NoteClipboard.Archive(blocks: blocks, base: base, inline: false), into: environment)
            return (rebased, environment.imported.map { $0.lastPathComponent })
        }
    }

    @Test func mediaInsideTheCopiedNotesFolderStillComesAlong() {
        let folders = RefusalFolders()
        defer { folders.finish() }
        #expect(folders.imported(base: folders.source, ["Attachments/cat.png"]).copied == ["cat.png"])
    }

    @Test func mediaClimbingOutOfTheSourceFolderStaysBehind() {
        let folders = RefusalFolders()
        defer { folders.finish() }
        let escapes = folders.imported(base: folders.source, ["../Secrets/id_rsa", "Attachments/../../Secrets/id_rsa"])
        #expect(escapes.copied.isEmpty)
        #expect(escapes.blocks.map(\.props.source) == ["../Secrets/id_rsa", "Attachments/../../Secrets/id_rsa"])
    }

    @Test func aSymlinkPointingOutOfTheFolderIsNotFollowed() {
        let folders = RefusalFolders()
        defer { folders.finish() }
        #expect(folders.imported(base: folders.source, ["Attachments/sneaky.png"]).copied.isEmpty)
    }

    @Test func hiddenFoldersAreNotRaided() {
        let folders = RefusalFolders()
        defer { folders.finish() }
        #expect(folders.imported(base: folders.source, [".ssh/id_rsa"]).copied.isEmpty)
    }

    @Test func aHiddenFolderCannotPoseAsANoteFolder() {
        let folders = RefusalFolders()
        defer { folders.finish() }
        #expect(folders.imported(base: folders.source.appendingPathComponent(".ssh", isDirectory: true), ["id_rsa"]).copied.isEmpty)
    }

    @Test func theDiskRootCannotPoseAsANoteFolder() {
        let folders = RefusalFolders()
        defer { folders.finish() }
        #expect(folders.imported(base: URL(fileURLWithPath: "/", isDirectory: true), [String(folders.secrets.path.dropFirst()) + "/id_rsa"]).copied.isEmpty)
    }

    @Test func theHomeFolderCannotPoseAsANoteFolder() {
        let folders = RefusalFolders()
        defer { folders.finish() }
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(folders.imported(base: home, [".ssh/id_rsa", "Documents/taxes.pdf"]).copied.isEmpty)
    }

    @Test func nothingAboveTheHomeFolderCanEither() {
        let folders = RefusalFolders()
        defer { folders.finish() }
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(folders.imported(base: home.deletingLastPathComponent(), [home.lastPathComponent + "/Documents/taxes.pdf"]).copied.isEmpty)
    }

    @Test func aWebBaseIsNeverANoteFolder() { #expect(NoteClipboard.trustedMediaFolder(URL(string: "https://example.com/notes/")!) == nil) }
}
