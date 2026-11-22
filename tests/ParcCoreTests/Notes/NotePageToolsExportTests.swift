import Foundation
import Testing
@testable import ParcCore

struct NotePageToolsExportTests {
    struct MarkdownCopy: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let body: String
        let title: String
        let expected: String
    }

    private static let markdownCopies = [
        MarkdownCopy(testDescription: "title and body", body: "Hello\n\n", title: " Trip ", expected: "# Trip\n\nHello\n"),
        MarkdownCopy(testDescription: "body without a title", body: "Hello", title: "", expected: "Hello\n"),
        MarkdownCopy(testDescription: "title without a body", body: "\n", title: "Empty", expected: "# Empty\n"),
    ]

    struct InvalidLink: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let link: String
    }

    private static let invalidLinks = [
        InvalidLink(testDescription: "unsupported scheme", link: "ftp://example.com/a.png"),
        InvalidLink(testDescription: "host without a dot", link: "https://nodot"),
        InvalidLink(testDescription: "plain words", link: "not a link"),
    ]

    @Test(arguments: markdownCopies) func copiedMarkdownIncludesTitleAndBodyWhenPresent(_ example: MarkdownCopy) {
        #expect(NotePageExport.markdownForCopy(body: example.body, title: example.title) == example.expected)
    }

    @Test func exportCollectsEachRelativeAssetOnce() {
        var settings = NotePageSettings()
        settings.cover = NoteCover(source: "Attachments/cover.jpg")
        settings.icon = "Attachments/icon.png"
        var image = NoteBlockProps(); image.source = "Attachments/photo%20one.png"
        var remote = NoteBlockProps(); remote.source = "https://example.com/a.png"
        var absolute = NoteBlockProps(); absolute.source = "/Users/somebody/b.png"
        var sneaky = NoteBlockProps(); sneaky.source = "../outside/c.png"
        var again = NoteBlockProps(); again.source = "Attachments/cover.jpg"
        let item = NoteBlock(.bulletedItem, text: "x", children: [NoteBlock(.image, props: image)])
        let page = NotePage(settings: settings, blocks: [item, NoteBlock(.image, props: remote), NoteBlock(.file, props: absolute),
                                                         NoteBlock(.video, props: sneaky), NoteBlock(.image, props: again)])
        #expect(NotePageExport.relativeAssetSources(in: page) == ["Attachments/cover.jpg", "Attachments/icon.png", "Attachments/photo%20one.png"], "exports copy the cover, image icon and nested media, skipping links, absolute paths, escapes and repeats")
    }

    @Test func anEmojiIconIsNotAnExportAsset() {
        var emojiSettings = NotePageSettings(); emojiSettings.icon = "🌳"
        #expect(NotePageExport.relativeAssetSources(in: NotePage(settings: emojiSettings)).isEmpty, "an emoji icon isn't a file")
    }

    @Test func aMarkdownCopyNeverOverwritesANeighbor() {
        let source = URL(fileURLWithPath: "/tmp/notes/Draft.txt")
        let taken: Set<String> = ["/tmp/notes/Draft.md", "/tmp/notes/Draft 2.md"]
        #expect(NotePageExport.markdownCopyURL(for: source) { taken.contains($0.path) }.path == "/tmp/notes/Draft 3.md", "a Markdown copy never overwrites a neighbour")
    }

    @Test func aMarkdownCopyKeepsItsOriginalNameWhenAvailable() {
        let source = URL(fileURLWithPath: "/tmp/notes/Draft.txt")
        #expect(NotePageExport.markdownCopyURL(for: source) { _ in false }.path == "/tmp/notes/Draft.md", "the copy keeps the name when it can")
    }

    @Test func imageLinksAreTrimmedBeforeValidation() {
        #expect(NotePageExport.validatedLink(" https://example.com/cover.jpg ")?.host == "example.com", "image links trim and validate")
    }

    @Test(arguments: invalidLinks) func invalidImageLinksAreRejected(_ example: InvalidLink) {
        #expect(NotePageExport.validatedLink(example.link) == nil)
    }

    @Test func pastedTitlesFlattenToOneLine() {
        #expect(NotePageExport.flattenedTitle("One\ntwo\r\nthree\tfour") == "One two three four", "pasted titles flatten to one line")
    }

    @Test func imageSourcesAreDistinguishedFromEmoji() {
        #expect(NotePageExport.isImageSource("Attachments/a.HEIC") && !NotePageExport.isImageSource("🌳"), "image icons are told apart from emoji")
    }
}
