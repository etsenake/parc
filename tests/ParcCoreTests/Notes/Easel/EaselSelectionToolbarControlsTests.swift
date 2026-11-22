import Foundation
import Testing
@testable import ParcCore

struct EaselSelectionToolbarControlsTests {
    func plan(_ kinds: [EaselItemKind], editing: Bool = false, locked: Bool = false) -> [[EaselToolbarControl]] {
        EaselSelectionToolbarPlan.groups(for: kinds.map(EaselToolbarSubject.init), editingText: editing, locked: locked)
    }

    @Test
    func rectanglesAndEllipsesShareTheShapeToolbar() {
        #expect(EaselToolbarSubject(.rectangle) == .shape && EaselToolbarSubject(.circle) == .shape, "Rectangles and ellipses share the shape toolbar")
    }

    @Test
    func arrowsUseTheConnectorToolbar() {
        #expect(EaselToolbarSubject(.arrow) == .connector, "Arrows use the connector toolbar")
    }

    @Test
    func drawingsUseTheDrawingToolbar() {
        #expect(EaselToolbarSubject(.freehand) == .drawing, "Doodles, highlights and tape use the drawing toolbar")
    }

    @Test
    func webContentUsesThePageSubject() {
        #expect([EaselItemKind.webCard, .browser, .link].allSatisfy { EaselToolbarSubject($0) == .page }, "Pages, captures and links are page objects")
    }

    @Test
    func codeBlocksLeadWithTheirLanguage() {
        #expect(EaselToolbarSubject(.code) == .code && plan([.code]).first == [.codeLanguage], "Code blocks lead with their language")
    }

    @Test
    func nothingSelectedShowsNoToolbar() {
        #expect(plan([]).isEmpty, "Nothing selected shows no toolbar")
    }

    @Test
    func aSinglePageKeepsItsOwnHeader() {
        #expect(plan([.webCard]).isEmpty && plan([.browser]).isEmpty && plan([.link]).isEmpty, "A single page object keeps its own header instead")
    }

    @Test
    func stickiesOfferColourShapeAndMore() {
        let sticky = plan([.sticky])
        #expect(sticky.first == [.color] && sticky.joined().contains(.stickyShape), "Stickies lead with colour and offer square or wide")
        #expect(sticky.last == [.more], "Every toolbar ends with the ••• menu")
    }

    @Test
    func shapesOfferObjectToolsBeforeTextEditing() {
        let shape = plan([.rectangle])
        #expect(shape == [[.shape], [.color], [.alignment], [.link], [.more]], "Shapes lead with the shape picker, then one style button, alignment and a link")
        #expect(!shape.joined().contains(.bold) && !shape.joined().contains(.textFill), "Shape text formatting waits for editing and fill belongs to the style picker")
    }

    @Test
    func connectorsOfferLabelStyleHeadsAndRouting() {
        let connector = plan([.arrow])
        #expect(connector == [[.connectorLabel], [.color], [.startHead, .endHead], [.routing], [.more]], "Connectors offer a label, one style button for colour, width and dashes, both heads and routing")
    }

    @Test
    func sectionsOfferTitleColourAndMore() {
        let section = plan([.section])
        #expect(section == [[.sectionTitle], [.color], [.more]], "Sections offer a title edit, colour and the ••• menu with their lock and hide options")
    }

    @Test
    func imagesGroupTheirImageTools() {
        #expect(plan([.image]).first == [.crop, .imageMask, .replaceImage, .altText], "Images group crop, mask, replace and alt text")
    }

    @Test
    func drawingsOfferColourAndPattern() {
        #expect(plan([.freehand]).first == [.color, .pattern], "Drawings take colour and width from the style button, plus a tape pattern")
    }

    @Test
    func tablesOfferCellAndTableTools() {
        let table = plan([.table]).joined()
        #expect([.typeface, .textSize, .bold, .strikethrough, .color, .cellFill, .alignment, .mergeCells].allSatisfy(table.contains), "Tables offer typeface, size, bold, strike, text and cell colour, alignment and merge")
    }

    @Test
    func editingACellShowsRangeFormatting() {
        #expect(plan([.table], editing: true).joined().contains(.italic) && !plan([.table], editing: true).joined().contains(.mergeCells), "Editing a cell swaps table tools for range formatting")
    }

    @Test
    func textOffersObjectToolsBeforeEditing() {
        let text = plan([.text]).joined()
        #expect([.typeface, .textSize, .smaller, .larger, .color, .textFill, .alignment, .link].allSatisfy(text.contains), "Text keeps the rail's family, size, fill and link plus colour and alignment")
        #expect(!text.contains(.bold), "Range emphasis waits for text editing, like the rail")
    }

    @Test
    func editingTextOffersRangeFormattingAndSizeSteps() {
        let editing = plan([.text], editing: true).joined()
        #expect([.bold, .italic, .underline, .strikethrough, .paragraph, .link, .textFill].allSatisfy(editing.contains), "Editing adds emphasis, paragraph and link controls")
        #expect(editing.contains(.smaller) && editing.contains(.larger), "Editing keeps the quick size steps beside the size menu")
    }

    @Test
    func aMultiSelectionDoesNotOfferRangeFormatting() {
        #expect(!plan([.text, .text], editing: true).joined().contains(.bold), "Several text objects never show range controls")
    }

    @Test(arguments: [EaselItemKind.sticky, .rectangle])
    func editingTextInAStickyOrShapeShowsRangeFormatting(_ kind: EaselItemKind) {
        let words = plan([kind], editing: true)
        #expect(words == [[.color, .highlight], [.bold, .italic, .underline, .strikethrough, .code, .equation], [.paragraph], [.alignment], [.link, .mention], [.more]], "Typing in a sticky or shape swaps object tools for colour, emphasis, lists, alignment and a link")
    }

    @Test
    func connectorLabelsOfferBoldAndStrikethrough() {
        #expect(plan([.arrow], editing: true) == [[.bold, .strikethrough], [.more]], "A connector label only takes bold and strikethrough")
    }

    @Test
    func matchingObjectsKeepTheirToolsAndGainArrangementTools() {
        let stickies = plan([.sticky, .sticky])
        #expect(stickies.first == [.color] && stickies.joined().contains(.stickyShape), "Same-kind selections keep that kind's controls")
        #expect(stickies.contains([.arrange, .tidyUp]) && stickies.contains([.group, .createSection, .lock]), "Several objects add arrange, tidy up, group, section and lock")
    }

    @Test
    func mixedObjectsKeepTheirSharedControls() {
        let mixed = plan([.sticky, .rectangle])
        #expect(mixed.first == [.color, .alignment, .link], "Mixed selections keep only controls every kind shares")
        #expect(!mixed.joined().contains(.shape) && !mixed.joined().contains(.stickyShape), "Kind-only controls leave mixed selections")
    }

    @Test
    func mixedObjectsOfferColourWhenOneAcceptsIt() {
        let partly = plan([.image, .arrow])
        #expect(partly.first == [.color] && partly.contains([.arrange, .tidyUp]) && partly.last == [.more], "Colour stays whenever anything in a mixed selection takes it")
    }

    @Test
    func unrelatedKindsStillOfferArrangement() {
        let unrelated = plan([.image, .code])
        #expect(unrelated.first == [.arrange, .tidyUp] && unrelated.last == [.more], "Kinds with nothing in common still get arrange tools")
    }

    @Test
    func tableColourStaysWithTables() {
        #expect(!plan([.table, .image]).joined().contains(.color), "Table text colour stays with tables on their own")
    }

    @Test
    func multiplePagesCanBeArranged() {
        let pages = plan([.webCard, .link])
        #expect(pages.contains([.arrange, .tidyUp]), "Several page objects can still be arranged together")
    }

    @Test
    func lockedSelectionsOnlyOfferUnlockAndMore() {
        #expect(plan([.sticky], locked: true) == [[.unlock], [.more]], "Locked selections offer only unlock and the ••• menu")
        #expect(plan([.text, .arrow], locked: true) == [[.unlock], [.more]], "Locked groups unlock as one")
    }

    @Test
    func aSelectionUnlocksAsAGroupOnlyWithMatchingGroupIDs() {
        let group = UUID()
        func item(_ groupID: UUID?) -> EaselItem {
            var value = EaselItem(kind: .sticky, frame: EaselRect(x: 0, y: 0, width: 10, height: 10), zIndex: 0)
            value.groupID = groupID
            return value
        }
        #expect(EaselSelectionToolbarPlan.unlocksGroup([item(group), item(group)]), "Members of one group unlock as a group")
        #expect(!EaselSelectionToolbarPlan.unlocksGroup([item(group), item(nil)]), "A loose object beside a group is not one group")
        #expect(!EaselSelectionToolbarPlan.unlocksGroup([item(group), item(UUID())]), "Two groups are not one group")
        #expect(!EaselSelectionToolbarPlan.unlocksGroup([item(group)]), "A single object just unlocks")
    }

    @Test
    func unavailableControlsAndTheirEmptyGroupsAreRemoved() {
        let filtered = EaselSelectionToolbarPlan.available(plan([.rectangle])) { $0 != .shape }
        #expect(filtered.first == [.color], "Controls without a command drop out of their group")
        #expect(!filtered.contains([]), "Emptied groups disappear instead of leaving stray dividers")
    }

    @Test
    func anImageKeepsMoreWhenItsToolsAreUnavailable() {
        #expect(EaselSelectionToolbarPlan.available(plan([.image])) { $0 == .more } == [[.more]], "An image without its tools keeps the ••• menu")
    }

    @Test
    func theFocusChordWorksWithEitherReportedSlash() {
        #expect(EaselChords.command(characters: "?", keyCode: 44, modifiers: [.command, .shift]) == .focusSelectionToolbar, "⇧⌘/ focuses the selection toolbar, typed as a question mark")
        #expect(EaselChords.command(characters: "/", keyCode: 44, modifiers: [.command, .shift]) == .focusSelectionToolbar, "⇧⌘/ also matches when the layout reports the unshifted slash")
    }

    @Test
    func otherSlashChordsDoNotFocusTheToolbar() {
        #expect(EaselChords.command(characters: "/", keyCode: 44, modifiers: [.command]) == nil
               && EaselChords.command(characters: "?", keyCode: 44, modifiers: [.shift]) == nil, "Other slash chords stay Parc's")
    }

    @Test
    func theFocusChordDoesNotTakeAReservedBinding() {
        #expect(EaselChords.reserved.allSatisfy { EaselChords.table[$0] == nil }, "The toolbar chord never takes a reserved Parc chord")
    }
}
