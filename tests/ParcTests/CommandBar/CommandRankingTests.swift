import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct CommandRankingTests {

    private typealias C = CommandBarRanking.Candidate
    private func typed(_ kind: CommandBarTypedCommand.Kind) -> C {
        let command = CommandBarTypedCommand(kind: kind)
        return CommandBarRanking.commandCandidate(key: command.id, texts: [command.title], typed: command)
    }
    private func menu(_ id: String, _ title: String, group: String) -> C {
        CommandBarRanking.commandCandidate(key: id, texts: [title], menuCommandID: id, menuText: title + " " + group)
    }
    private func search(_ terms: String, _ rank: Int) -> C { C(archetype: .chromium, key: CommandBarRowDiff.searchKey(terms), chromiumRank: rank) }
    private func tab(_ title: String, _ url: String) -> C {
        C(archetype: .tab, key: CommandBarRanking.pageKey(URL(string: url)!, title: title), texts: [title, URL(string: url)!.host!, url])
    }
    private func first(_ candidates: [C], _ query: String) -> String? {
        CommandBarRanking.rank(candidates, query: query).first.map { candidates[$0].key }
    }

    @Test func nightModeRanksSwitchToDarkModeFirst() {
        let dark = typed(.appearance(.dark)), light = typed(.appearance(.light))
        let night = [search("night mode", 0), search("night mode iphone", 1), light, dark, tab("Night Mode Tips", "https://example.com/night")]
        #expect(first(night, "night mode") == dark.key)
    }

    @Test func theTriggerPhraseIsMatchedWhole() {
        let dark = typed(.appearance(.dark))
        #expect(CommandBarRanking.match("night mode", dark.texts) == 1)
    }

    @Test func aMenuCommandFoundOnlyByItsTriggerIsKept() {
        let clear = menu("clearToday:", "Clear Today", group: "Tabs")
        #expect(CommandBarRanking.rank([search("close unpinned tabs", 0), clear], query: "close unpinned tabs").contains(1))
    }

    @Test func showNotesFolderCarriesItsWeightedBump() {
        let notesFolder = menu("showNotesFolder:", "Show Notes Folder", group: "File")
        #expect(notesFolder.bump == 1.5 * CommandBarMenuItemInfo.bumpWeight)
    }

    @Test func anExactTabRanksAboveABumpedCommand() {
        let notesFolder = menu("showNotesFolder:", "Show Notes Folder", group: "File")
        let notesTab = tab("Notes", "https://example.com/notes")
        #expect(first([notesFolder, notesTab], "notes") == notesTab.key)
    }

    @Test func generalPreferencesRanksAboveLinkPreferences() {
        let general = typed(.settingsPane(.general)), links = typed(.settingsPane(.links))
        #expect(general.bump > links.bump)
    }
}
