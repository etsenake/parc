import Foundation
import Testing
@testable import ParcCore

struct CapturePaletteMenuTests {
    let destinations = CaptureFixtures.Destinations()

    var full: CapturePaletteContext { destinations.full }

    @Test func easelDestinationsCarryTheirLastEditForTheSubmenuSubtitle() {
        #expect(destinations.easels.first { $0.id == destinations.travel }?.modifiedAt == Date(timeIntervalSince1970: 900))
    }

    @Test func theMainPaletteListsQuickActionsThenTheEditGroupThenOneRowPerDestinationKind() {
        let main = CapturePaletteMenu.rows(full)
        #expect(main.map(\.id) == ["library", "copy", "save", "message", "edit", "crop", "frame", "retake", "easels", "notes"])
        #expect(main.filter(\.separatorBefore).map(\.id) == ["edit"])
        #expect(main.filter { $0.section == CapturePaletteMenu.sendToTitle }.map(\.id) == ["easels", "notes"])
        #expect(main.filter(\.hasSubmenu).map(\.id) == ["easels", "notes"])
    }

    @Test func theMainPaletteNeverGrowsWithTheNumberOfEaselsOrNotes() {
        let main = CapturePaletteMenu.rows(full)
        #expect(main.count == 10)
        #expect(!main.contains { $0.action.submenu == nil && $0.id.hasPrefix("easel:") })
        #expect(!main.contains { $0.title == "Show More" })
    }

    @Test func nothingIsCheckedBeforeASaveAndTheFirstHighlightSavesToTheLibrary() {
        let main = CapturePaletteMenu.rows(full)
        #expect(main.allSatisfy { !$0.isChecked })
        #expect(CapturePaletteMenu.firstAvailable(in: main) == "library")
    }

    @Test func removeFrameJoinsTheEditGroupOnlyForFramedCaptures() {
        let framed = CapturePaletteMenu.rows(CapturePaletteContext(easels: destinations.easels, framed: true))
        #expect(framed.map(\.id) == ["library", "copy", "save", "message", "edit", "crop", "frame", "removeFrame", "retake", "easels"])
        #expect(framed.first { $0.id == "frame" }?.title == "Edit Portrait Frame")
    }

    @Test func aSavedCaptureShowsACheckedSavedToLibraryRow() throws {
        let saved = CapturePaletteContext(easels: destinations.easels, librarySaved: true)
        let row = try #require(CapturePaletteMenu.rows(saved).first)
        #expect(row.title == "Saved to Library" && row.isChecked)
    }

    @Test func searchMatchesTheCurrentToggleTitle() {
        let saved = CapturePaletteContext(easels: destinations.easels, librarySaved: true)
        #expect(CapturePaletteMenu.rows(saved, query: "saved").map(\.id) == ["library"])
        #expect(CapturePaletteMenu.rows(saved, query: "save to").isEmpty)
    }

    @Test func theEaselSubmenuLeadsWithNewEaselThenEveryEaselByLatestSidebarActivityInThisProfile() {
        let menu = CapturePaletteMenu.submenu(.easels, context: full)
        #expect(menu.map(\.id) == ["newEasel", destinations.easelRow(destinations.design), destinations.easelRow(destinations.travel),
                                   destinations.easelRow(destinations.research)])
        #expect(menu.first?.section == nil)
        #expect(menu.dropFirst().allSatisfy { $0.section == CapturePaletteMenu.recentTitle })
    }

    @Test func theNoteSubmenuLeadsWithNewNoteThenNotesInCatalogRecencyOrder() {
        let menu = CapturePaletteMenu.submenu(.notes, context: full)
        #expect(menu.map(\.id) == [CaptureNoteTarget.newNote.id, destinations.notes[0].id, destinations.notes[1].id])
        #expect(menu[1].title == "Recipes")
        #expect(menu.dropFirst().map(\.id) == CaptureNoteDestination.ranked(destinations.notes).map(\.id))
    }

    @Test func noEaselsMeansJustNewEaselWithNoEmptyHeader() {
        let menu = CapturePaletteMenu.submenu(.easels, context: CapturePaletteContext())
        #expect(menu.map(\.id) == ["newEasel"])
        #expect(menu[0].section == nil)
    }

    @Test func submenuSearchFiltersItsOwnKindCaseInsensitively() {
        #expect(CapturePaletteMenu.submenu(.easels, context: full, query: "TRA").map(\.id) == [destinations.easelRow(destinations.travel)])
    }

    @Test func submenuSearchCanStillReachNewNote() {
        #expect(CapturePaletteMenu.submenu(.notes, context: full, query: "new").map(\.id) == [CaptureNoteTarget.newNote.id])
    }

    @Test func filteredSubmenusDropTheirHeaders() {
        #expect(CapturePaletteMenu.submenu(.easels, context: full, query: "re").allSatisfy { $0.section == nil })
    }

    @Test func searchRunsAcrossActionsThenEaselsThenNotesKeepingTheirOrder() {
        let context = CapturePaletteContext(easels: destinations.easels, notes: destinations.notes, framed: true, notesAvailable: true)
        let results = CapturePaletteMenu.rows(context, query: "re")
        #expect(results.map(\.id) == ["removeFrame", "retake", destinations.easelRow(destinations.research), destinations.recipesNote.id])
        #expect(results.filter { $0.id.hasPrefix("easel:") || $0.id.hasPrefix("note:") }.map(\.subtitle) == ["Easel", "Note"])
        #expect(results.allSatisfy { $0.section == nil && !$0.separatorBefore })
    }

    @Test func searchSkipsTheSubmenuRowsThemselves() {
        #expect(CapturePaletteMenu.rows(full, query: "e").allSatisfy { !$0.hasSubmenu })
    }

    @Test func searchReachesNewEaselAndNewNoteDirectly() {
        #expect(CapturePaletteMenu.rows(full, query: "new").map(\.id) == ["newEasel", CaptureNoteTarget.newNote.id])
    }

    @Test func literalSpacesAndMissesStayEmpty() {
        #expect(CapturePaletteMenu.rows(full, query: " research").isEmpty)
        #expect(CapturePaletteMenu.rows(full, query: "zzzz").isEmpty)
    }

    @Test func privateCapturesKeepLibraryAndOutputsButHaveNoSendToSection() {
        let context = CapturePaletteContext(easels: destinations.easels, notes: destinations.notes, easelsAvailable: false, notesAvailable: false)
        #expect(CapturePaletteMenu.rows(context).map(\.id) == ["library", "copy", "save", "message", "edit", "crop", "frame", "retake"])
        #expect(CapturePaletteMenu.rows(context, query: "re").map(\.id) == ["retake"])
        #expect(CapturePaletteMenu.submenu(.easels, context: context).isEmpty)
        #expect(CapturePaletteMenu.submenu(.notes, context: context).isEmpty)
    }

    @Test func withoutALibraryDestinationThereIsNoLibraryRowOrEaselSubmenuAndHighlightFallsToCopy() {
        let rows = CapturePaletteMenu.rows(CapturePaletteContext(easels: destinations.easels, libraryAvailable: false))
        #expect(!rows.contains { $0.id == "library" || $0.id == "easels" })
        #expect(CapturePaletteMenu.firstAvailable(in: rows) == "copy")
    }

    @Test func aBusyPaletteDisablesEveryRowAndHighlightsNothing() {
        let busy = CapturePaletteMenu.rows(CapturePaletteContext(easels: destinations.easels, notesAvailable: true, busy: true))
        #expect(busy.allSatisfy { !$0.isEnabled })
        #expect(CapturePaletteMenu.firstAvailable(in: busy) == nil)
    }

    @Test func unavailableMessagesIsTheOnlySkippedRow() {
        let rows = CapturePaletteMenu.rows(CapturePaletteContext(messageAvailable: false))
        #expect(rows.filter { !$0.isEnabled }.map(\.id) == ["message"])
    }

    @Test func renamingAnEaselKeepsItsExactUUIDHighlighted() {
        let renamed = CapturePaletteContext(easels: destinations.easels.map {
            $0.id == destinations.travel ? CaptureEaselDestination(id: destinations.travel, title: "Trips", lastActive: $0.lastActive) : $0
        })
        let rows = CapturePaletteMenu.submenu(.easels, context: renamed)
        let travelRow = destinations.easelRow(destinations.travel)
        #expect(CapturePaletteMenu.retainedHighlight(travelRow, in: rows) == travelRow)
        #expect(rows.contains { $0.title == "Trips" })
    }

    @Test func aRowThatBecameUnavailableLosesTheHighlight() {
        let rows = CapturePaletteMenu.rows(CapturePaletteContext(messageAvailable: false))
        #expect(CapturePaletteMenu.retainedHighlight("message", in: rows) == nil)
    }

    @Test func aDeletedEaselIsNeverSubstitutedInTheHighlight() {
        let rows = CapturePaletteMenu.submenu(.easels, context: full)
        #expect(CapturePaletteMenu.retainedHighlight("easel:" + UUID().uuidString, in: rows) == nil)
    }

    @Test func newSearchTextHighlightsTheFirstAvailableResult() {
        let rows = CapturePaletteMenu.rows(CapturePaletteContext(messageAvailable: false))
        #expect(CapturePaletteMenu.firstAvailable(in: rows.filter { $0.id == "message" || $0.id == "save" }) == "save")
    }

    @Test func noResultsMeansNoOutputSelection() {
        #expect(CapturePaletteMenu.firstAvailable(in: []) == nil)
    }

    @Test func easelRowsKeepTheirExactUUID() throws {
        let travel = try #require(destinations.easels.first { $0.id == destinations.travel })
        let document = CapturePaletteDocument(travel)
        #expect(document.id == destinations.easelRow(destinations.travel))
        #expect(document.kind == .easel)
        #expect(document.target == .easel(destinations.travel))
    }

    @Test func noteRowsKeepTheCatalogsExactFileIdentity() {
        let document = CapturePaletteDocument(destinations.recipesNote)
        #expect(document.id == destinations.recipesNote.id)
        #expect(document.target == .note(destinations.recipes))
    }
}
