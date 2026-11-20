import Foundation

@main
struct NoteSyncedMarkdownTests {
    typealias Check = MarkdownCheck

    static func main() {
        originalReads()
        copyReads()
        exactRoundTrips()
        modelRoundTrips()
        nestedPlacesRoundTrip()
        unmatchedMarkersStayVerbatim()
        openerAfterTextStaysSynced()
        Check.finish("NoteSyncedMarkdownTests")
    }

    static func originalReads() {
        let page = NoteMarkdown.parse("""
        <!-- parc synced id="k3x9qa" -->

        Weekly goals

        - Ship it

        <!-- parc /synced -->

        After
        """)
        Check.expect(page.blocks.count == 2, "the synced block and the paragraph after it")
        let synced = page.blocks[0]
        Check.expect(synced.kind == .synced && synced.isSyncedOriginal, "the opener makes an original")
        Check.expect(synced.props.anchor == "k3x9qa", "the id is the anchor")
        Check.expect(synced.children.map(\.kind) == [.paragraph, .bulletedItem], "everything between the markers is inside")
        Check.expect(page.blocks[1].text.string == "After", "the closer ends the block")
    }

    static func copyReads() {
        let page = NoteMarkdown.parse("""
        <!-- parc synced from="Project%20plan.md#k3x9qa" -->

        Weekly goals

        <!-- parc /synced -->
        """)
        let synced = page.blocks[0]
        Check.expect(synced.isSyncedCopy, "a from attribute makes a copy")
        Check.expect(synced.props.target == "Project%20plan.md#k3x9qa", "the reference is kept as written")
        Check.expect(synced.children.map(\.text.string) == ["Weekly goals"], "the snapshot reads as ordinary blocks")
    }

    static func exactRoundTrips() {
        Check.checkExact("""
        Before

        <!-- parc synced id="k3x9qa" -->

        Weekly goals

        - Ship it
        - Celebrate

        <!-- parc /synced -->

        After

        """, "an original between paragraphs")
        Check.checkExact("""
        <!-- parc synced from="Other.md#k3x9qa" -->

        ## Snapshot

        <!-- parc /synced -->

        """, "a copy at the top")
        Check.checkExact("""
        <!-- parc synced from="#abc123" -->


        <!-- parc /synced -->

        """, "an empty copy keeps its empty line")
        Check.checkStable("<!-- parc synced id=\"abc123\" -->\n\n<!-- parc /synced -->\n", "one blank line settles on none")
        Check.checkExact("""
        <!-- parc synced id="abc123" -->
        <!-- parc /synced -->

        """, "a block with nothing inside")
    }

    static func modelRoundTrips() {
        var original = NoteBlock(.synced, children: [.paragraph("One"), NoteBlock(.todo, text: "Two"), .paragraph()])
        original.props.anchor = "k3x9qa"
        var copy = NoteBlock(.synced, children: [.heading(2, "Copied"), .paragraph(), .paragraph()])
        copy.props.target = "Folder/My%20note.md#k3x9qa"
        var lone = NoteBlock(.synced, children: [.paragraph()])
        lone.props.anchor = "zz9zz9"
        Check.checkModelRoundTrip(NotePage(blocks: [.paragraph("a"), original, copy, lone, .paragraph("b")]), "originals, copies and empty lines")
        Check.checkModelRoundTrip(NotePage(blocks: [original, original.withFreshIDs()]), "two blocks back to back")
    }

    static func nestedPlacesRoundTrip() {
        var synced = NoteBlock(.synced, children: [.paragraph("Inside"), NoteBlock(.bulletedItem, text: "Item")])
        synced.props.anchor = "k3x9qa"
        let inList = NoteBlock(.bulletedItem, text: "Parent", children: [synced])
        let inToggle = NoteBlock(.toggle, text: "Box", children: [synced.withFreshIDs()])
        let inColumns = NoteBlock(.columns, children: [NoteBlock(.column, children: [.paragraph("Left")]),
                                                       NoteBlock(.column, children: [synced.withFreshIDs()])])
        let inCallout = NoteBlock(.callout, text: "Tip", children: [synced.withFreshIDs()])
        let underText = NoteBlock(.paragraph, text: "Lead", children: [synced.withFreshIDs()])
        for (label, block) in [("list item", inList), ("toggle", inToggle), ("column", inColumns), ("callout", inCallout), ("indent", underText)] {
            Check.checkModelRoundTrip(NotePage(blocks: [block, .paragraph("after")]), "a synced block inside a " + label)
        }
    }

    static func unmatchedMarkersStayVerbatim() {
        Check.checkExact("""
        Text

        <!-- parc synced id="k3x9qa" -->

        More text

        """, "an opener without a closer stays as written")
        let page = NoteMarkdown.parse("Text\n\n<!-- parc /synced -->\n")
        Check.expect(page.blocks.map(\.kind) == [.paragraph, .html], "a lone closer stays as HTML")
        let lone = NoteMarkdown.parse("Text\n<!-- parc synced id=\"k3x9qa\" -->\n")
        Check.expect(lone.blocks[0].props.anchor == nil, "a lone opener never lends its id to the text above")
    }

    static func openerAfterTextStaysSynced() {
        let page = NoteMarkdown.parse("Text\n<!-- parc synced id=\"k3x9qa\" -->\nInside\n<!-- parc /synced -->\n")
        Check.expect(page.blocks.map(\.kind) == [.paragraph, .synced], "an opener hugging the text above still opens a block")
        Check.expect(page.blocks[0].props.anchor == nil, "and the text keeps no id")
        Check.expect(page.blocks.last?.children.map(\.text.string) == ["Inside"], "the hugging content lands inside")
    }
}
