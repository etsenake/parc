import Foundation
import Testing
@testable import ParcCore

struct NoteHTMLRoundTripTestsDocumentTests {
    private typealias Fixture = NoteHTMLRoundTripTestsSupport

    private func document() -> String {
        var settings = NotePageSettings()
        settings.icon = "🌿"
        settings.cover = NoteCover(source: "Attachments/cover.jpg", position: 0.25)
        settings.font = .serif
        settings.smallText = true
        settings.fullWidth = true
        settings.properties = [NotePageProperty(key: "Tags", value: .list(["home", "plans"])),
                               NotePageProperty(key: "Done", value: .checkbox(true))]
        let note = NotePage(settings: settings, blocks: Fixture.page)
        return NotePageHTML.document(note, title: "Weekend <plans>", assets: { _ in nil }, embedImages: false)
    }

    private func documentWithEquationArt() -> String {
        return NotePageHTML.document(NotePage(blocks: [Fixture.block(.equation, "E=mc^2"), .paragraph(.atom(.equation("a")))]), title: "",
                                           assets: { _ in nil }, embedImages: false) { tex, display, _ in
            URL(string: "https://math.example/" + (display ? "block" : "inline") + "/" + (tex == "a" ? "a" : "e") + ".svg")
                .map { NoteEquationArt(url: $0) }
        }
    }

    @Test
    func anExportIncludesTheDocumentType() {
        let html = document()
        #expect(html.hasPrefix("<!DOCTYPE html>"), "standalone document")
    }

    @Test
    func aDocumentEscapesItsTitle() {
        let html = document()
        #expect(html.contains("<title>Weekend &lt;plans&gt;</title>") && html.contains("<h1 class=\"page-title\">Weekend &lt;plans&gt;</h1>"), "escaped title")
    }

    @Test
    func pageSettingsBecomeBodyClasses() {
        let html = document()
        #expect(html.contains("class=\"page-font-serif small-text full-width has-cover has-icon\""), "page settings become body classes")
    }

    @Test
    func anEmojiIconExportsAsText() {
        let html = document()
        #expect(html.contains("<div class=\"page-icon\">🌿</div>"), "emoji icon")
    }

    @Test
    func theCoverKeepsItsVerticalPosition() {
        let html = document()
        #expect(html.contains("class=\"page-cover\"") && html.contains("object-position:center 25%"), "cover with position")
    }

    @Test
    func documentFontsStartWithNunito() {
        let html = document()
        #expect(html.contains("--font:\"Nunito\",ui-rounded"), "Nunito-first font stack")
    }

    @Test
    func aDocumentStylesDarkModeAndPrint() {
        let html = document()
        #expect(html.contains("prefers-color-scheme:dark") && html.contains("@media print"), "dark mode and print styles")
    }

    @Test
    func documentTogglesOpenForPrint() {
        let html = document()
        #expect(html.contains("<details open"), "toggles print open in documents")
    }

    @Test
    func equationsExportTheirTeX() {
        let html = document()
        #expect(html.contains("<span class=\"tex\">\\int_0^1 x\\,dx</span>"), "equations show their TeX")
    }

    @Test
    func theTableOfContentsLinksToHeadingAnchors() {
        let html = document()
        #expect(html.contains("id=\"big-title\"") && html.contains("href=\"#big-title\""), "table of contents links to headings")
    }

    @Test
    func documentColorsUseClasses() {
        let html = document()
        #expect(html.contains("class=\"highlight-red\""), "document colours use classes")
    }

    @Test
    func propertiesExportAsChips() {
        let html = document()
        #expect(html.contains("<span class=\"property-chip\">home</span>"), "properties render")
    }

    @Test
    func bookmarksExportAsCards() {
        let html = document()
        #expect(html.contains("class=\"bookmark-card\""), "bookmarks render as cards")
    }

    @Test
    func theExportedStylesheetHasNoComments() {
        let html = document()
        #expect(!html.contains("/*"), "no comments sneak into the CSS")
    }

    @Test
    func anEmptyDocumentTitleBecomesUntitled() {
        let images = documentWithEquationArt()
        #expect(images.contains("<title>Untitled</title>"), "empty titles get a name")
    }

    @Test
    func providedEquationArtReplacesInlineAndDisplayTeX() {
        let images = documentWithEquationArt()
        #expect(images.contains("src=\"https://math.example/block/e.svg\"") && images.contains("src=\"https://math.example/inline/a.svg\""), "equation images replace TeX when given")
    }

    @Test
    func aDocumentImportsItsTableAndCallout() {
        let html = document()
        let reread = NoteHTMLReader.blocks(from: html, baseURL: nil)
        #expect(reread.contains { $0.kind == .table } && reread.contains { $0.kind == .callout && $0.props.icon == "🧭" }, "an exported document reads back in")
    }
}
