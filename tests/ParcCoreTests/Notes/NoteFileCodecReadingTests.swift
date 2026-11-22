import Foundation
import Testing
@testable import ParcCore

struct NoteFileCodecReadingTests {
    @Test func theIconComesFromFrontMatter() {
        let note = """
        ---
        icon: "🚀"
        tags: [a, b]
        ---
        # Launch plan

        - [ ] Book the **venue** for [the party](https://example.com)
        > [!NOTE]
        > Bring snake_case_names and `code`
        ![photo](Attachments/a.png)
        """
        let summary = NoteFileSummary.make(fromHead: note, kind: .markdown)
        #expect(summary.icon == "🚀", "the icon comes from front matter")
    }

    @Test func aSummaryRemovesMarkdownFormatting() {
        let note = """
        ---
        icon: "🚀"
        tags: [a, b]
        ---
        # Launch plan

        - [ ] Book the **venue** for [the party](https://example.com)
        > [!NOTE]
        > Bring snake_case_names and `code`
        ![photo](Attachments/a.png)
        """
        let summary = NoteFileSummary.make(fromHead: note, kind: .markdown)
        #expect(summary.snippet == "Launch plan Book the venue for the party Bring snake_case_names and code", "snippets drop Markdown syntax")
    }

    @Test func singleQuotedIconsUnescape() {
        #expect(NoteFileSummary.make(fromHead: "---\nicon: 'It''s'\n---\nBody", kind: .markdown).icon == "It's", "single-quoted icons unescape")
    }

    @Test func anIconCanBeFollowedByAYamlComment() {
        #expect(NoteFileSummary.make(fromHead: "---\nicon: 📚 # books\n---\n", kind: .markdown).icon == "📚", "trailing YAML comments go")
    }

    @Test func unterminatedFrontMatterSuppliesNoIcon() {
        #expect(NoteFileSummary.make(fromHead: "---\n  icon: x\ntitle: y\n", kind: .markdown).icon == nil, "unterminated front matter has no icon")
    }

    @Test func aPlainTextSummaryKeepsItsMarkupVerbatim() {
        #expect(NoteFileSummary.make(fromHead: "---\nicon: x\n---\nhi", kind: .plainText).snippet == "--- icon: x --- hi", "text files are verbatim")
    }

    @Test func aMarkdownSummaryDecodesCharacterReferences() {
        #expect(NoteFileSummary.make(fromHead: "# Testing 123&#32;\nTom &amp; Jerry&#9;", kind: .markdown).snippet == "Testing 123 Tom & Jerry", "character references show as the characters they stand for")
    }

    @Test func anEscapedAmpersandStaysLiteral() {
        #expect(NoteFileSummary.make(fromHead: "\\&amp; and &lt;b&gt;", kind: .markdown).snippet == "&amp; and <b>", "an escaped ampersand stays literal")
    }

    @Test func aSummaryOmitsSyncedBlockMarkers() {
        #expect(NoteFileSummary.make(fromHead: "<!-- parc synced from=\"Josh%E2%80%99s.md#a\" -->\nShared words\n<!-- /parc synced -->\nAfter",
                                         kind: .markdown).snippet == "Shared words After", "synced block markers stay out of previews")
    }

    @Test func aSummaryOmitsMultilineComments() {
        #expect(NoteFileSummary.make(fromHead: "Before <!-- a\nhidden\nlines --> after", kind: .markdown).snippet == "Before after", "comments spanning lines stay out of previews")
    }

    @Test func aLongSnippetIsClippedWithAnEllipsis() {
        let long = NoteFileSummary.make(fromHead: String(repeating: "word ", count: 100), kind: .markdown).snippet
        #expect(long.count <= NoteFileSummary.snippetLength + 1 && long.hasSuffix("…"), "long snippets are clipped")
    }

    @Test func codeAndTablesContributeTheirTextToASummary() {
        #expect(NoteFileSummary.make(fromHead: "```swift\nlet x = 1\n```\n| a | b |\n|---|---|", kind: .markdown).snippet == "let x = 1 a b", "code and tables read as text")
    }

    @Test func reconcilingBlocksKeepsTheirIdentityAndUsesTheirNewContent() {
        let a = NoteBlock.paragraph("Alpha"), b = NoteBlock.paragraph("Beta"), c = NoteBlock.paragraph("Gamma")
        let old = NotePage(blocks: [a, b, c])
        let fresh = NotePage(blocks: [.paragraph("Alpha"), .paragraph("Beta, edited"), .paragraph("New"), .paragraph("Gamma")])
        let merged = NoteFileReconciler.preservingIdentity(of: old, in: fresh)
        #expect(merged.blocks[0].id == a.id, "unchanged blocks keep their identity")
        #expect(merged.blocks[1].id == b.id, "an edited block in the same spot keeps its identity")
        #expect(merged.blocks[3].id == c.id, "blocks after an insertion keep their identity")
        #expect(Set(merged.blocks.map(\.id)).count == 4, "identities stay unique")
        #expect(merged.blocks.map(\.text.string) == ["Alpha", "Beta, edited", "New", "Gamma"], "the new content wins")
    }

    @Test func aCaretStaysInItsReconciledBlock() {
        let a = NoteBlock.paragraph("Alpha"), b = NoteBlock.paragraph("Beta"), c = NoteBlock.paragraph("Gamma")
        let old = NotePage(blocks: [a, b, c])
        let fresh = NotePage(blocks: [.paragraph("Alpha"), .paragraph("Beta, edited"), .paragraph("New"), .paragraph("Gamma")])
        let merged = NoteFileReconciler.preservingIdentity(of: old, in: fresh)
        let caret = NoteFileReconciler.mapSelection(.caret(NotePosition(b.id, 4)), from: old, to: merged)
        #expect(caret == .caret(NotePosition(b.id, 4)), "the caret stays in its block")
    }

    @Test func aCaretClampsToTheEndOfShorterText() {
        let a = NoteBlock.paragraph("Alpha"), b = NoteBlock.paragraph("Beta"), c = NoteBlock.paragraph("Gamma")
        let old = NotePage(blocks: [a, b, c])
        let fresh = NotePage(blocks: [.paragraph("Alpha"), .paragraph("Beta, edited"), .paragraph("New"), .paragraph("Gamma")])
        let merged = NoteFileReconciler.preservingIdentity(of: old, in: fresh)
        let clamped = NoteFileReconciler.mapSelection(.caret(NotePosition(c.id, 5)), from: old,
                                                      to: NotePage(blocks: [merged.blocks[0], NoteBlock(.paragraph, text: "Ga", id: c.id)]))
        #expect(clamped == .caret(NotePosition(c.id, 2)), "the caret clamps to shorter text")
    }

    @Test func aVanishedBlockHandsTheCaretToItsNeighbor() {
        let a = NoteBlock.paragraph("Alpha"), b = NoteBlock.paragraph("Beta"), c = NoteBlock.paragraph("Gamma")
        let old = NotePage(blocks: [a, b, c])
        let gone = NoteFileReconciler.mapSelection(.caret(NotePosition(c.id, 3)), from: old, to: NotePage(blocks: [.paragraph("Only")]))
        #expect(gone.caret?.offset == 3, "a vanished block hands the caret to its neighbour")
    }

    @Test func blockSelectionsKeepOnlyTheSurvivingBlocks() {
        let a = NoteBlock.paragraph("Alpha"), b = NoteBlock.paragraph("Beta"), c = NoteBlock.paragraph("Gamma")
        let old = NotePage(blocks: [a, b, c])
        #expect(NoteFileReconciler.mapSelection(.blocks([a.id, c.id]), from: old, to: NotePage(blocks: [a])) == .blocks([a.id]), "block selections keep the survivors")
    }
}
