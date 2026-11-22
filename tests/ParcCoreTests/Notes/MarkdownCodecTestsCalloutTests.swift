import Foundation
import Testing
@testable import ParcCore

struct MarkdownCodecTestsCalloutTests {
    typealias SourceCase = MarkdownCodecTestsSupport.SourceCase

    private func blocks(_ source: String) -> [NoteBlock] { NoteMarkdown.parse(source).blocks }

    @Test
    func aBarePlainCalloutWritesParcsComment() {
        let plain = NoteBlock(.callout, text: "No icon, no colour")
        let plainText = NoteMarkdown.serialize(NotePage(blocks: [plain]))
        #expect(plainText == "> [!NOTE]\n> No icon, no colour <!-- parc -->\n", "a bare plain callout still carries Parc's comment")
    }

    @Test
    func aBarePlainCalloutSurvivesAModelRoundTrip() {
        let plain = NoteBlock(.callout, text: "No icon, no colour")
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [plain]), "plain callout without icon or colour")
    }

    @Test
    func aPlainCalloutStartingWithInlineHTMLRoundTrips() {
        var plainUnderlined = NoteBlock(.callout, text: NoteText("under", marks: NoteMarks(underline: true)) + NoteText(" lined"))
        plainUnderlined.children = [NoteBlock(.bulletedItem, text: "item")]
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [plainUnderlined]), "plain callout opening with inline HTML")
    }

    @Test
    func anEmptyPlainCalloutWithAListRoundTrips() {
        let plainEmpty = NoteBlock(.callout, children: [NoteBlock(.bulletedItem, text: "item")])
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [plainEmpty]), "empty plain callout with a list")
    }

    @Test
    func aPlainCalloutKeepsItsIcon() {
        var plainIcon = NoteBlock(.callout, text: "Lit")
        plainIcon.props.icon = "🔥"
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [plainIcon]), "plain callout with an icon")
    }

    @Test
    func aPlainCalloutKeepsItsFold() {
        var plainFolded = NoteBlock(.callout, text: "Folded", children: [.paragraph("inside")])
        plainFolded.props.toggleable = true
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [plainFolded]), "folding plain callout")
    }

    @Test(arguments: [
        SourceCase("GitHub NOTE", "> [!NOTE]\n> Useful information.\n"),
        SourceCase("GitHub NOTE without text", "> [!NOTE]\n>\n> - only a list\n"),
        SourceCase("GitHub NOTE with a body", "> [!NOTE]\n> Two\\\n> lines\n>\n> Second paragraph.\n"),
    ])
    func gitHubNotesSaveBackExactly(fixture: SourceCase) {
        NoteMarkdownCheck.checkExact(fixture.markdown, fixture.testDescription)
    }

    @Test
    func aGitHubNoteKeepsItsAlertType() {
        let note = NoteMarkdown.parse("> [!NOTE]\n> Useful information.\n")
        #expect(note.blocks[0].props.alert == "NOTE", "a GitHub NOTE loads as a note alert")
    }

    @Test
    func editingAGitHubNoteDoesNotAddAComment() {
        var note = NoteMarkdown.parse("> [!NOTE]\n> Useful information.\n")
        note.blocks[0].text = NoteText("Edited information.")
        #expect(NoteMarkdown.serialize(note) == "> [!NOTE]\n> Edited information.\n", "editing a GitHub NOTE's text adds no comment")
    }

    @Test
    func aCustomGitHubNoteIconWritesTheAlertFlag() {
        var note = NoteMarkdown.parse("> [!NOTE]\n> Useful information.\n")
        note.blocks[0].text = NoteText("Edited information.")
        #expect(NoteMarkdown.serialize(note) == "> [!NOTE]\n> Edited information.\n", "editing a GitHub NOTE's text adds no comment")
        note.blocks[0].props.icon = "🌳"
        let restyled = NoteMarkdown.serialize(note)
        #expect(restyled == "> [!NOTE]\n> Edited information. <!-- parc alert icon=\"🌳\" -->\n", "a picked icon is saved with the alert flag")
    }

    @Test
    func aGitHubNoteKeepsItsCustomIcon() {
        var note = NoteMarkdown.parse("> [!NOTE]\n> Useful information.\n")
        note.blocks[0].text = NoteText("Edited information.")
        #expect(NoteMarkdown.serialize(note) == "> [!NOTE]\n> Edited information.\n", "editing a GitHub NOTE's text adds no comment")
        note.blocks[0].props.icon = "🌳"
        NoteMarkdownCheck.checkModelRoundTrip(note, "GitHub NOTE with a picked icon")
    }

    @Test
    func aGitHubNoteKeepsItsColorWithNoIcon() {
        var note = NoteMarkdown.parse("> [!NOTE]\n> Useful information.\n")
        note.blocks[0].text = NoteText("Edited information.")
        note.blocks[0].props.icon = ""
        note.blocks[0].color = .background(.pink)
        NoteMarkdownCheck.checkModelRoundTrip(note, "GitHub NOTE with its icon removed and a picked colour")
    }

    @Test
    func aGitHubNoteKeepsItsAnchor() {
        var anchored = NoteBlock(.callout, text: "Linked")
        anchored.props.alert = "NOTE"
        anchored.props.anchor = "n0te22"
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [anchored]), "GitHub NOTE with a block anchor")
    }

    @Test
    func emptyGitHubNotesStayDistinctFromPlainCallouts() {
        var empty = NoteBlock(.callout)
        empty.props.alert = "NOTE"
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [empty, NoteBlock(.callout)]), "empty GitHub NOTE beside an empty plain callout")
    }

    @Test(arguments: [
        SourceCase("titled callout continued by block HTML", "> [!tip]- T\n>     <summary>S</summary> x\n"),
        SourceCase("GitHub alert title continued by block HTML", "> [!TIP] T\n>     <div>x\n"),
        SourceCase("empty GitHub alert title continued by block HTML", "> [!TIP] <!-- parc -->\n>     <div>x\n"),
        SourceCase("kept GitHub note continued by a pre tag", "> [!NOTE] Hi <!-- parc alert -->\n>     <pre>x\n"),
    ])
    func calloutsWithHTMLContinuationsSettleAfterOneSave(fixture: SourceCase) {
        NoteMarkdownCheck.checkStable(fixture.markdown, fixture.testDescription)
    }

    @Test
    func calloutsKeepChildrenStartingWithBlockHTML() {
        var tipped = NoteBlock(.callout, text: "Title", children: [.paragraph(.atom(.raw("<div>")) + NoteText(" body"))])
        tipped.props.alert = "TIP"
        var plain = NoteBlock(.callout, children: [.paragraph(.atom(.raw("<details>")) + NoteText(" body"))])
        plain.props.icon = "💡"
        var titled = NoteBlock(.callout, text: "Why", children: [.paragraph(.atom(.raw("<summary>")) + NoteText(" body"))])
        titled.props.alert = "faq"
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [tipped, plain, titled]), "callouts whose first child opens with block HTML")
    }

    @Test
    func gitHubWarningsLoadAsCallouts() {
        let alert = blocks("> [!WARNING]\n> Watch out.\n>\n> Second.\n")[0]
        #expect(alert.kind == .callout && alert.props.alert == "WARNING" && alert.text.string == "Watch out." && alert.children.count == 1, "GitHub alerts become callouts")
    }

    @Test
    func aHandWrittenGitHubNoteLoadsAsAnAlert() {
        let note = blocks("> [!NOTE]\n> Hi\n")[0]
        #expect(note.props.alert == "NOTE" && note.props.icon == nil && note.color == nil, "a hand-written GitHub NOTE is a note alert")
    }

    @Test
    func aParcCommentMakesAPlainCallout() {
        let plain = blocks("> [!NOTE]\n> Hi <!-- parc -->\n")[0]
        #expect(plain.props.alert == nil && plain.text.string == "Hi" && plain.props.icon == nil, "Parc's comment marks a plain callout")
    }

    @Test
    func aPlainCalloutStaysPlainWithACustomIcon() {
        let iconic = blocks("> [!NOTE]\n> Hi <!-- parc icon=\"🔥\" -->\n")[0]
        #expect(iconic.props.alert == nil && iconic.props.icon == "🔥", "a plain callout's icon comment keeps it plain")
    }

    @Test
    func theAlertFlagPreservesAGitHubNoteWithACustomIcon() {
        let kept = blocks("> [!NOTE]\n> Hi <!-- parc alert icon=\"🌳\" -->\n")[0]
        #expect(kept.props.alert == "NOTE" && kept.props.icon == "🌳", "the alert flag keeps a restyled GitHub NOTE a note")
    }

    @Test
    func obsidianCalloutsKeepTheirTitlesAndFolds() {
        let obsidian = blocks("> [!tip]+ Title here\n> Body line\n")[0]
        #expect(obsidian.props.alert == "tip" && obsidian.props.toggleable && obsidian.props.expanded && obsidian.text.string == "Title here"
               && obsidian.children.first?.text.string == "Body line", "Obsidian titles and folds load")
    }

    @Test
    func anAttributeLineLeavesCalloutTextEmpty() {
        let empty = blocks("> [!NOTE]\n> <!-- parc icon=\"🔥\" -->\n>\n> Child paragraph.\n")[0]
        #expect(empty.text.isEmpty && empty.props.icon == "🔥" && empty.children.count == 1, "an attribute line marks empty callout text")
    }

    @Test
    func alertMarkersMustOpenTheQuote() {
        let quote = blocks("> Not [!NOTE] a callout\n")[0]
        #expect(quote.kind == .quote, "the marker must open the quote")
    }

    @Test
    func aColoredCalloutWithAnIconRoundTrips() {
        var callout = NoteBlock(.callout, text: "Body *text*", children: [.paragraph("child"), NoteBlock(.bulletedItem, text: "item")])
        callout.props.icon = "💡"
        callout.color = .background(.gray)
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [callout]), "default callout")
    }

    @Test
    func aTitledCalloutKeepsItsFold() {
        var callout = NoteBlock(.callout, text: "Body *text*", children: [.paragraph("child"), NoteBlock(.bulletedItem, text: "item")])
        callout.props.icon = "💡"
        callout.color = .background(.gray)
        callout.props.alert = "abstract"
        callout.props.toggleable = true
        callout.props.expanded = false
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [callout]), "titled callout")
    }

    @Test
    func aTitledCalloutCanHaveEmptyText() {
        var callout = NoteBlock(.callout, text: "Body *text*", children: [.paragraph("child"), NoteBlock(.bulletedItem, text: "item")])
        callout.props.icon = "💡"
        callout.color = .background(.gray)
        callout.props.alert = "abstract"
        callout.props.toggleable = true
        callout.props.expanded = false
        callout.text = NoteText()
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [callout]), "titled callout without title")
    }

    @Test
    func anAlertCalloutCanHaveEmptyText() {
        var callout = NoteBlock(.callout, text: "Body *text*", children: [.paragraph("child"), NoteBlock(.bulletedItem, text: "item")])
        callout.props.icon = "💡"
        callout.color = .background(.gray)
        callout.props.toggleable = true
        callout.props.expanded = false
        callout.text = NoteText()
        callout.props.alert = "IMPORTANT"
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [callout]), "empty alert text")
    }

    @Test
    func emptyQuotesSurviveAModelRoundTrip() {
        let bare = NoteBlock(.quote, children: [.paragraph("first child")])
        NoteMarkdownCheck.checkModelRoundTrip(NotePage(blocks: [bare, NoteBlock(.quote), NoteBlock(.callout)]), "empty quotes")
    }
}
