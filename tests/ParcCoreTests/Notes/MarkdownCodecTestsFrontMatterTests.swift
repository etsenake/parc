import Foundation
import Testing
@testable import ParcCore

struct MarkdownCodecTestsFrontMatterTests {
    private static let frontMatter = """
    ---
    icon: 🍎
    cover: "https://example.com/cover.jpg"
    cover-position: 0.25
    font: mono
    small-text: true
    full-width: true
    locked: false
    title: Weekly review
    tags: [work, "deep focus"]
    aliases:
      - Review
      - "2026: week 47"
    rating: 4.5
    due: 2026-11-27
    done: true
    version: "1.0"
    empty:
    meta:
      owner: ada
    # a comment
    script: |
      multi
      line
    ---
    Body text.

    """

    @Test
    func thePageIconAndCoverLoadFromFrontMatter() {
        let settings = NoteMarkdown.parse(Self.frontMatter).settings
        #expect(settings.icon == "🍎" && settings.cover == NoteCover(source: "https://example.com/cover.jpg", position: 0.25), "icon and cover load")
    }

    @Test
    func pageDisplaySettingsLoadFromFrontMatter() {
        let settings = NoteMarkdown.parse(Self.frontMatter).settings
        #expect(settings.font == .mono && settings.smallText && settings.fullWidth && !settings.locked, "page switches load")
    }

    @Test
    func simpleYAMLValuesLoadAsTypedProperties() {
        let settings = NoteMarkdown.parse(Self.frontMatter).settings
        let properties = Dictionary(uniqueKeysWithValues: settings.properties.map { ($0.key, $0.value) })
        #expect(properties["title"] == .text("Weekly review") && properties["tags"] == .list(["work", "deep focus"])
               && properties["aliases"] == .list(["Review", "2026: week 47"]) && properties["rating"] == .number(4.5)
               && properties["due"] == .date("2026-11-27") && properties["done"] == .checkbox(true) && properties["version"] == .text("1.0")
               && properties["empty"] == .text("") && properties["locked"] == .checkbox(false), "simple keys become properties: \(settings.properties)")
    }

    @Test
    func complexYAMLStaysVerbatim() {
        let settings = NoteMarkdown.parse(Self.frontMatter).settings
        #expect(settings.preservedFrontMatter == ["meta:\n  owner: ada", "# a comment", "script: |\n  multi\n  line"], "complex YAML is kept verbatim: \(settings.preservedFrontMatter)")
    }

    @Test
    func theBodyFollowsTheFrontMatter() {
        let page = NoteMarkdown.parse(Self.frontMatter)
        #expect(page.blocks.count == 1 && page.blocks[0].text.string == "Body text.", "the body follows the front matter")
    }

    @Test
    func frontMatterSettingsSurviveAModelRoundTrip() {
        let page = NoteMarkdown.parse(Self.frontMatter)
        NoteMarkdownCheck.checkModelRoundTrip(page, "front matter")
    }

    @Test
    func frontMatterSettlesAfterOneSave() {
        NoteMarkdownCheck.checkStable(Self.frontMatter, "front matter")
    }

    @Test
    func quotedYAMLPropertiesSurviveAModelRoundTrip() {
        var custom = NotePage(blocks: [.paragraph("x")])
        custom.settings.icon = "-"
        custom.settings.properties = [
            NotePageProperty(key: "quoted", value: .text("true")), NotePageProperty(key: "number text", value: .text("42")),
            NotePageProperty(key: "colon", value: .text("a: b")), NotePageProperty(key: "hash", value: .text("a #b")),
            NotePageProperty(key: "list", value: .list(["1", "null", "", "- x", "[y]"])), NotePageProperty(key: "weird key: yes", value: .number(-3)),
            NotePageProperty(key: "multi", value: .text("line\nbreak")), NotePageProperty(key: "blank list", value: .list([])),
            NotePageProperty(key: "when", value: .date("2026-11-20T10:00")),
        ]
        NoteMarkdownCheck.checkModelRoundTrip(custom, "YAML quoting")
    }

    @Test
    func unclosedFrontMatterStartsWithADivider() {
        let notFrontMatter = NoteMarkdown.parse("---\nnot closed\n")
        #expect(notFrontMatter.settings.isDefault && notFrontMatter.blocks.first?.kind == .divider, "unclosed front matter is a thematic break")
    }

    @Test
    func frontMatterWithOnlyAnIconSavesBackExactly() {
        NoteMarkdownCheck.checkExact("---\nicon: 📓\n---\n\n# Journal\n", "icon only")
    }

    @Test
    func aByteOrderMarkDoesNotHideFrontMatter() {
        #expect(NoteMarkdown.parse("\u{FEFF}---\nicon: 📓\n---\nHi\n").settings.icon == "📓", "a byte-order mark doesn't hide front matter")
    }

    struct DividerCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let makeBlocks: @Sendable () -> [NoteBlock]

        init(_ label: String, _ makeBlocks: @escaping @Sendable () -> [NoteBlock]) {
            testDescription = label
            self.makeBlocks = makeBlocks
        }
    }

    private static let leadingDividers = [
        DividerCase("divider pair") { [NoteBlock(.divider), .paragraph("between"), NoteBlock(.divider)] },
        DividerCase("divider before dots") { [NoteBlock(.divider), .paragraph("...")] },
        DividerCase("painted divider pair") {
            var paintedRule = NoteBlock(.divider)
            paintedRule.color = .background(.orange)
            return [paintedRule, NoteBlock(.divider)]
        },
    ]

    @Test(arguments: leadingDividers)
    func aLeadingDividerThatCouldOpenFrontMatterIsIndented(fixture: DividerCase) {
        let page = NotePage(blocks: fixture.makeBlocks())
        #expect(NoteMarkdown.serialize(page).hasPrefix(" ---\n"))
    }

    @Test(arguments: leadingDividers)
    func aLeadingDividerSurvivesAModelRoundTrip(fixture: DividerCase) {
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: fixture.makeBlocks()), fixture.testDescription)
    }
}
