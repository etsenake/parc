import Foundation

@main struct CommandRankingTests {
    static func main() {
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        typealias C = CommandBarRanking.Candidate
        func typed(_ kind: CommandBarTypedCommand.Kind) -> C {
            let command = CommandBarTypedCommand(kind: kind)
            return CommandBarRanking.commandCandidate(key: command.id, texts: [command.title], typed: command)
        }
        func menu(_ id: String, _ title: String, group: String) -> C {
            CommandBarRanking.commandCandidate(key: id, texts: [title], menuCommandID: id, menuText: title + " " + group)
        }
        func search(_ terms: String, _ rank: Int) -> C { C(archetype: .chromium, key: CommandBarRowDiff.searchKey(terms), chromiumRank: rank) }
        func tab(_ title: String, _ url: String) -> C {
            C(archetype: .tab, key: CommandBarRanking.pageKey(URL(string: url)!, title: title), texts: [title, URL(string: url)!.host!, url])
        }
        func first(_ candidates: [C], _ query: String) -> String? {
            CommandBarRanking.rank(candidates, query: query).first.map { candidates[$0].key }
        }
        let dark = typed(.appearance(.dark)), light = typed(.appearance(.light))

        let night = [search("night mode", 0), search("night mode iphone", 1), light, dark, tab("Night Mode Tips", "https://example.com/night")]
        expect(first(night, "night mode") == dark.key, "night mode ranks Switch to Dark Mode first")
        expect(CommandBarRanking.match("night mode", dark.texts) == 1, "the trigger phrase is matched whole")

        let clear = menu("clearToday:", "Clear Today", group: "Tabs")
        expect(CommandBarRanking.rank([search("close unpinned tabs", 0), clear], query: "close unpinned tabs").contains(1),
               "a menu command found only by its trigger is kept")

        let exportNotes = menu("exportNotes:", "Export Notes…", group: "File")
        expect(exportNotes.bump == 1.5 * CommandBarMenuItemInfo.bumpWeight, "Export Notes carries its weighted bump")
        expect(0.85 + exportNotes.bump < 0.95, "the largest bump keeps an exact command under an exact tab")
        let notesTab = tab("Notes", "https://example.com/notes")
        expect(first([exportNotes, notesTab], "notes") == notesTab.key, "a bumped word-matched command doesn't pass an exact tab")
        let general = typed(.settingsPane(.general)), links = typed(.settingsPane(.links))
        expect(general.bump > links.bump, "General's 0.6 orders above the other panes' 0.5")
        print("CommandRankingTests: \(count) checks passed")
    }
}
