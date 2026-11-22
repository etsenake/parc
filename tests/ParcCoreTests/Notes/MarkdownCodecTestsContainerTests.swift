import Foundation
import Testing
@testable import ParcCore

struct MarkdownCodecTestsContainerTests {
    private func blocks(_ source: String) -> [NoteBlock] { NoteMarkdown.parse(source).blocks }

    @Test
    func detailsWithMarkdownBecomeToggles() {
        let toggles = blocks("<details>\n<summary>Closed **bold**</summary>\n\n\nAfter a blank.\n\n</details>\n")
        #expect(toggles.count == 1 && toggles[0].kind == .toggle && !toggles[0].props.expanded && toggles[0].text.marks(at: 8).bold, "details become toggles")
        #expect(toggles[0].children.map(\.kind) == [.paragraph, .paragraph] && toggles[0].children[0].text.isEmpty, "extra blank lines are empty blocks")
    }

    @Test
    func unclosedDetailsStayHTML() {
        let unmatched = blocks("<details>\n<summary>x</summary>\n\nno close\n")
        #expect(unmatched[0].kind == .html && unmatched[1].kind == .paragraph, "an unclosed details stays HTML")
    }

    @Test
    func detailsWithRawContentStayVerbatim() {
        let rawDetails = blocks("<details>\n<summary>x</summary>\nraw body\n</details>\n")
        #expect(rawDetails.count == 1 && rawDetails[0].kind == .html, "details with raw HTML inside stay verbatim")
    }

    @Test
    func togglesKeepTheirHeadingAndEmptyChildren() {
        var heading = NoteBlock.heading(3, "Toggle heading")
        heading.props.toggleable = true
        heading.props.expanded = false
        heading.children = [.paragraph("hidden"), .paragraph()]
        var toggle = NoteBlock(.toggle, text: "Empty child", children: [.paragraph()])
        toggle.color = .text(.orange)
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [heading, toggle, NoteBlock(.toggle)]), "toggles")
    }

    @Test
    func looseBlocksGetTheirOwnColumn() {
        let columns = blocks("::: {.columns}\nloose\n\n::: column\ninside\n:::\n:::\n")[0]
        #expect(columns.kind == .columns && columns.children.count == 2 && columns.children.allSatisfy { $0.kind == .column }, "loose blocks get their own column")
    }

    @Test
    func indentFencesNestUnderThePrecedingBlock() {
        let indented = blocks("Para\n\n::: indent\nkid\n:::\n\n# Head\n::: {.indent}\nunder\n:::\n")
        #expect(indented.count == 2 && indented[0].children.map(\.text.string) == ["kid"] && indented[1].children.map(\.text.string) == ["under"], "an indent fence nests under the block before it")
    }

    @Test
    func anOrphanedIndentGetsAnEmptyParent() {
        let orphan = blocks("::: indent\nalone\n:::\n\n---\n\n::: indent\nafter rule\n:::\n")
        #expect(orphan.map(\.kind) == [.paragraph, .divider, .paragraph] && orphan[0].text.isEmpty && orphan[2].children.first?.text.string == "after rule", "an indent with nothing to hold it gets an empty line as its parent")
    }

    @Test
    func anIndentAfterAListItemNestsInsideIt() {
        let listed = blocks("- item\n\n::: indent\nkid\n:::\n")
        #expect(listed.count == 1 && listed[0].children.first?.text.string == "kid", "an indent after a list item nests in the item")
    }

    @Test
    func colonsSurviveInsideIndentFences() {
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [NoteBlock(.paragraph, text: ":::", children: [.paragraph(":::"), .paragraph("::: indent")]),
                                                            .paragraph("::: indent")]), "colons inside indents")
    }

    @Test
    func unknownDirectivesStayPlainText() {
        let unknown = blocks(":::tip\nDocusaurus\n:::\n")
        #expect(unknown.count == 1 && unknown[0].kind == .paragraph, "unknown directives stay text")
    }

    @Test
    func aCodeFenceInsideAColumnKeepsItsColons() {
        let fenced = blocks("::: column\n```\n:::\n```\n:::\n")[0]
        #expect(fenced.children.first?.children.first?.text.string == ":::", "a fence inside a column keeps its colons")
    }

    @Test
    func columnsKeepWidthsNestingAndEmptyChildren() {
        var left = NoteBlock(.column, children: [.paragraph("left"), NoteBlock(.columns, children: [NoteBlock(.column, children: [.paragraph("deep")])])])
        left.props.width = 1.0 / 3.0
        let right = NoteBlock(.column, children: [.paragraph(), .paragraph("after empty")])
        var grid = NoteBlock(.columns, children: [left, right])
        grid.color = .background(.blue)
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [grid]), "columns")
    }
}
