import Foundation
import Testing
@testable import ParcCore

struct TypedCommandTests {
    typealias Command = CommandBarTypedCommand

    let space = UUID()

    @Test(arguments: [
        (Command.Kind.undo("New Folder…"), "Undo New Folder…"), (.redo("Update Appearance"), "Redo Update Appearance"),
        (.pinToSpace(UUID(), name: "Work"), "Pin to Work"), (.pinToNewFolder, "Pin to New Folder"),
        (.replacePinWithCurrentPage, "Replace Pin with Current Page"), (.duplicateCurrentTab, "Duplicate Current Tab"),
        (.convertSplit(toVertical: true), "Convert to Vertical Split View"),
        (.convertSplit(toVertical: false), "Convert to Horizontal Split View"),
        (.addSplit(.left), "Add Left Split"), (.addSplit(.right), "Add Right Split"),
        (.addSplit(.top), "Add Top Split"), (.addSplit(.bottom), "Add Bottom Split"),
        (.newWebDocument(CommandBarWebDocument.catalog[0]), "New Google Doc"),
        (.searchSettings, "Search Settings"), (.airTrafficControl, "Air Traffic Control"),
    ])
    func recoveredCommandsKeepTheirTitles(kind: Command.Kind, title: String) {
        #expect(Command(kind: kind).title == title)
    }

    @Test func eachCommandHasItsOwnRowIdentity() {
        let kinds: [Command.Kind] = [
            .undo("New Folder…"), .redo("Update Appearance"), .pinToSpace(space, name: "Work"), .pinToNewFolder,
            .replacePinWithCurrentPage, .duplicateCurrentTab, .convertSplit(toVertical: true), .convertSplit(toVertical: false),
            .addSplit(.left), .addSplit(.right), .addSplit(.top), .addSplit(.bottom),
            .newWebDocument(CommandBarWebDocument.catalog[0]), .searchSettings, .airTrafficControl,
        ]
        #expect(Set(kinds.map { Command(kind: $0).id }).count == kinds.count)
    }

    @Test func aRenamedSpaceKeepsItsRowIdentity() {
        #expect(Command(kind: .pinToSpace(space, name: "A")).id == Command(kind: .pinToSpace(space, name: "B")).id)
    }

    @Test func aDifferentUndoStepIsADifferentCommand() {
        #expect(Command(kind: .undo("A")) != Command(kind: .undo("B")))
    }

    @Test func moveFindsPinToSpace() {
        #expect(Command(kind: .pinToSpace(space, name: "Work")).matches(query: "move work"))
    }

    @Test func titleWordsMatch() {
        #expect(Command(kind: .pinToNewFolder).matches(query: "pin new"))
    }

    @Test func airTrafficControlMatchesItsNameAndItsRoutes() {
        #expect(Command(kind: .airTrafficControl).matches(query: "air traffic"))
        #expect(Command(kind: .airTrafficControl).matches(query: "routes"))
    }

    @Test func matchingFoldsCase() {
        #expect(Command(kind: .newWebDocument(CommandBarWebDocument.catalog[5])).matches(query: "NOTION"))
    }

    @Test func anEmptyQueryIsTheProvidersChoiceNotAMatch() {
        #expect(!Command(kind: .searchSettings).matches(query: ""))
    }

    @Test func unrelatedWordsDoNotMatch() {
        #expect(!Command(kind: .searchSettings).matches(query: "split"))
    }

    @Test func menuCommandsTakeTheirCommandBarTitles() {
        #expect(Command.commandBarTitle(forMenuCommand: "toggleSidebar:", menuTitle: "Show / Hide Sidebar") == "Toggle Sidebar")
        #expect(Command.commandBarTitle(forMenuCommand: "resetTab:", menuTitle: "Reset Tab to Original URL") == "Reset Tab")
    }

    @Test func addSplitViewKeepsItsMenuTitleAndTheStackedAddIsNamed() {
        #expect(Command.commandBarTitle(forMenuCommand: "split:", menuTitle: "Add Split View") == "Add Split View")
        #expect(Command(kind: .addVerticalSplit).title == "Add Vertical Split View")
    }

    @Test func newNoteTakesParcsName() {
        #expect(Command.commandBarTitle(forMenuCommand: "createNote:", menuTitle: "New Note") == "New Parc Note")
    }

    @Test func parcNoteFindsItByItsTitleAndItsOwnTriggersStillWork() {
        let noteSearch = Command.commandBarSearchText(forMenuCommand: "createNote:")
        let title = Command.commandBarTitle(forMenuCommand: "createNote:", menuTitle: "New Note")
        #expect((title + " " + noteSearch).lowercased().contains("parc note"))
        #expect(noteSearch.contains("Scratchpad"))
    }

    @Test func theBorrowedAliasIsGoneFromSearchAndRankingText() {
        let noteSearch = Command.commandBarSearchText(forMenuCommand: "createNote:")
        let words = (noteSearch + " " + Command.rankingPhrases(forMenuCommand: "createNote:").joined(separator: " ")).lowercased()
        #expect(!words.split(separator: " ").contains("arc"))
    }

    @Test func otherMenuTitlesAreUnchanged() {
        #expect(Command.commandBarTitle(forMenuCommand: "newTab:", menuTitle: "New Tab") == "New Tab")
    }

    @Test func theCatalogHasElevenRecoveredDocumentTypes() {
        #expect(CommandBarWebDocument.catalog.count == 11)
    }

    @Test func confluenceUsesMakePage() {
        #expect(CommandBarWebDocument.catalog.map(\.url).contains("https://make.page"))
    }

    @Test func noEngagementOffersNoDocument() {
        #expect(CommandBarWebDocument.available(visitedHosts: []).isEmpty)
    }

    @Test func driveEngagementOffersItsThreeTypesInOrder() {
        #expect(CommandBarWebDocument.available(visitedHosts: ["drive.google.com"]).map(\.title) == ["Google Doc", "Google Sheet", "Google Slide"])
    }

    @Test func subdomainsCountAsEngagement() {
        #expect(CommandBarWebDocument.available(visitedHosts: ["team.figma.com"]).map(\.title) == ["Figma Document", "FigJam"])
    }

    @Test func aSuffixThatIsNotASubdomainDoesNotCount() {
        #expect(CommandBarWebDocument.available(visitedHosts: ["notfigma.com"]).isEmpty)
    }

    @Test func onePaneOffersEveryEdgeAndTheStackedAdd() {
        #expect(Command.splitCommands(paneCount: 1, vertical: false).map(\.title)
                == ["Add Left Split", "Add Right Split", "Add Top Split", "Add Bottom Split", "Add Vertical Split View"])
    }

    @Test func aHorizontalSplitOffersRightLeftAndConvert() {
        #expect(Command.splitCommands(paneCount: 2, vertical: false).map(\.title)
                == ["Add Right Split", "Add Left Split", "Convert to Vertical Split View"])
    }

    @Test func aVerticalSplitOffersTopBottomStackedAndConvert() {
        #expect(Command.splitCommands(paneCount: 3, vertical: true).map(\.title)
                == ["Add Top Split", "Add Bottom Split", "Add Vertical Split View", "Convert to Horizontal Split View"])
    }

    @Test func aFullSplitAddsNothing() {
        #expect(Command.splitCommands(paneCount: 4, vertical: true).map(\.title) == ["Convert to Horizontal Split View"])
    }

    @Test func noPaneMeansNoSplitCommand() {
        #expect(Command.splitCommands(paneCount: 0, vertical: false).isEmpty)
    }

    @Test func settingsPaneTitlesComeInOrder() {
        #expect(Command.SettingsPane.allCases.map(\.title) == ["Settings", "Open General Preferences", "Open Space Preferences",
            "Edit Keyboard Shortcuts", "Open Link Preferences", "Open App Icon", "Open Advanced Preferences"])
    }

    @Test func paneTriggerPhrasesMatch() {
        #expect(Command(kind: .settingsPane(.shortcuts)).matches(query: "hotkeys"))
        #expect(Command(kind: .settingsPane(.general)).matches(query: "autofill"))
        #expect(Command(kind: .settingsPane(.account)).matches(query: "membership"))
    }

    @Test func wordsForTheExcludedMiniBrowserWindowAreNotOffered() {
        #expect(!Command(kind: .settingsPane(.links)).matches(query: "little arc"))
    }

    @Test func recoveredPaneBumpsAreKeptAndNoneIsInvented() {
        #expect(Command(kind: .settingsPane(.general)).candidateBump == 0.6)
        #expect(Command(kind: .settingsPane(.links)).candidateBump == 0.5)
        #expect(Command(kind: .searchSettings).candidateBump == nil)
    }

    @Test func aiAndStaffPanesAreExcluded() {
        #expect(!Command.SettingsPane.allCases.contains { $0.title.contains("Max") || $0.title.contains("Staff") })
    }

    @Test func appearanceCommandsHaveTitlesAndTriggers() {
        #expect(Command(kind: .appearance(.dark)).title == "Switch to Dark Mode")
        #expect(Command(kind: .appearance(.dark)).matches(query: "night"))
        #expect(Command(kind: .appearance(.automatic)).title == "Switch to Automatic Appearance")
    }

    @Test func copyParcInfoHasItsTitleIconAndMatchesTheOldName() {
        #expect(Command(kind: .copyAppInfo).title == "Copy Parc Info")
        #expect(Command(kind: .copyAppInfo).symbol == "list.clipboard")
        #expect(Command(kind: .copyAppInfo).matches(query: "copy arc info"))
    }

    @Test func revealParcDataHasItsTitleAndBump() {
        #expect(Command(kind: .revealAppData).title == "Reveal Parc Data")
        #expect(Command(kind: .revealAppData).candidateBump == 0.1)
    }

    @Test func portraitCaptureHasItsTitleIconTriggersAndNoBump() {
        #expect(Command(kind: .capturePortrait).title == "Capture in Portrait Mode")
        #expect(Command(kind: .capturePortrait).symbol == "camera.macro")
        #expect(Command(kind: .capturePortrait).matches(query: "screenshot"))
        #expect(Command(kind: .capturePortrait).candidateBump == nil)
    }

    @Test func taskManagerHasItsTitleIconAndTriggers() {
        #expect(Command(kind: .openTaskManager).title == "Open Task Manager")
        #expect(Command(kind: .openTaskManager).symbol == "exclamationmark.triangle")
        #expect(Command(kind: .openTaskManager).matches(query: "cpu"))
        #expect(Command(kind: .openTaskManager).matches(query: "memory"))
    }

    @Test func duplicateSpaceNamesShowTheirPosition() {
        let foreignPin = Command(kind: .pinToSpace(space, name: "Work", position: 3))
        #expect(foreignPin.title == "Pin to Work")
        #expect(foreignPin.detail == "Space 3")
        #expect(!foreignPin.matches(query: "pin personal"))
    }

    @Test func aUniqueSpaceNameShowsNoLabel() {
        #expect(Command(kind: .pinToSpace(space, name: "Work")).detail.isEmpty)
    }

    @Test func profileStaysAHiddenKeywordForSpacePreferences() {
        #expect(Command(kind: .settingsPane(.profiles)).matches(query: "profile"))
    }

    @Test func menuItemBumpsAreKept() {
        #expect(CommandBarMenuItemInfo.candidateBump(forMenuCommand: "toggleSidebar:") == 0.5)
        #expect(CommandBarMenuItemInfo.candidateBump(forMenuCommand: "showNotesFolder:") == 1.5)
        #expect(CommandBarMenuItemInfo.candidateBump(forMenuCommand: "newTab:") == nil)
    }

    @Test func menuItemsKeepTheirSearchTriggers() {
        #expect(CommandBarMenuItemInfo.searchText(forMenuCommand: "clearToday:").contains("Close Unpinned Tabs"))
        #expect(CommandBarMenuItemInfo.searchText(forMenuCommand: "showReleaseNotes:").contains("Changelog"))
        #expect(Command.commandBarSearchText(forMenuCommand: "createEasel:").contains("Mood Board"))
    }

    @Test func shareTakesTheTypeTravelTitle() {
        #expect(Command.commandBarTitle(forMenuCommand: "sharePage:", menuTitle: "Share…") == "Share URL")
    }

    @Test func theLargestBumpCannotLiftAnExactCommandOverAnExactTab() {
        #expect(CommandBarMenuItemInfo.rankingBump(1.5) < 0.95 - 0.85)
    }
}
