import Foundation

///
@main struct RankingTests {
    static func main() {
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        typealias C = CommandBarRanking.Candidate
        func command(_ title: String, _ extra: [String] = []) -> C { C(archetype: .typeTravel, key: "typeTravel:" + title, texts: [title] + extra) }
        func search(_ terms: String, _ rank: Int) -> C { C(archetype: .chromium, key: CommandBarRowDiff.searchKey(terms), chromiumRank: rank) }
        func page(_ url: String, _ rank: Int, title: String = "") -> C {
            C(archetype: .chromium, key: CommandBarRanking.pageKey(URL(string: url)!, title: title), chromiumRank: rank)
        }
        func tab(_ title: String, _ url: String) -> C {
            C(archetype: .tab, key: CommandBarRanking.pageKey(URL(string: url)!, title: title), texts: [title, URL(string: url)!.host!, url])
        }
        func order(_ candidates: [C], _ query: String) -> [String] {
            CommandBarRanking.rank(candidates, query: query).map { candidates[$0].key }
        }

        expect(CommandBarRanking.match("new eas", ["New Easel"]) == 0.9, "a name starting with the query is a prefix match")
        expect(CommandBarRanking.match("add split", ["Add Right Split"]) == 0.7, "every word starting a word is a word match")
        expect(CommandBarRanking.match("ight", ["Add Right Split"]) == 0.4, "a word inside a word is a weak match")
        expect(CommandBarRanking.match("xyz", ["Add Right Split"]) == 0, "no match")

        //
        let easel = [search("new eas", 0), search("new earth", 1), command("New Easel"), command("New Window"), search("new earth waste services", 2)]
        let easelOrder = order(easel, "new eas")
        expect(easelOrder.prefix(3) == ["typeTravel:New Easel", "search:new eas", "search:new earth"],
               "a Type Travel action named by the query leads, then Chromium's default")
        expect(!easelOrder.contains("typeTravel:New Window"), "an action the query doesn't match is not a result")
        //
        let split = [search("split", 0), search("splitwise", 1), command("Add Right Split"), command("Add Left Split")]
        let splitOrder = order(split, "split")
        expect(splitOrder.first == "search:split", "word-only command matches don't outrank the search")
        expect(splitOrder.contains("typeTravel:Add Right Split") && splitOrder.contains("typeTravel:Add Left Split"), "the split commands still rank in")
        //
        let space = [search("space", 0), command("Focus on", ["Space 1", "Focus on Space 1"])]
        expect(order(space, "space").first == "typeTravel:Focus on", "a contextual target named by the query leads")

        // The extra commands interleave by score instead of trailing every native row.
        let interleaved = order([search("new", 0), search("news", 1), search("new york times", 2), search("new balance", 3),
                                 search("netflix", 4), command("New Easel"), command("New Folder")], "new")
        expect(interleaved[0] == "typeTravel:New Easel" && interleaved[1] == "search:new", "lead then default")
        expect(interleaved.firstIndex(of: "typeTravel:New Folder")! < interleaved.firstIndex(of: "search:netflix")!,
               "a prefix-matched command ranks above weaker suggestions")

        // DedupKey: an open tab and Chromium's row for the same page become one row.
        let merged = [page("https://www.youtube.com/", 0, title: "YouTube"), tab("YouTube", "https://youtube.com")]
        let mergedOrder = CommandBarRanking.rank(merged, query: "you")
        expect(mergedOrder == [1], "the tab replaces Chromium's row for its page")
        let github = [page("https://github.com/etsenake/parc/pulls?q=1", 0, title: "Pull requests"),
                      tab("Pull requests", "https://github.com/etsenake/parc/pulls")]
        expect(CommandBarRanking.rank(github, query: "pull").count == 1, "listed sites dedup by title and host")

        // Caps and the 15-result limit.
        let many = (0..<12).map { command("New Thing \($0)") } + (0..<12).map { search("new \($0)", $0) }
        let capped = CommandBarRanking.rank(many, query: "new")
        expect(capped.count == 13, "five actions and eight Chromium rows")
        expect(capped.filter { many[$0].archetype == .typeTravel }.count == 5, "Type Travel is capped at five")
        let wide = many + (0..<12).map { tab("New tab \($0)", "https://example\($0).com") }
        expect(CommandBarRanking.rank(wide, query: "new").count == 15, "the result stops at the 15")

        // Documents and top domains are ordinary sources.
        let note = C(archetype: .document, key: "document:1", texts: ["Trip plans"])
        expect(order([search("trip", 0), note], "trip").contains("document:1"), "a Note without a tab is a result")
        let tabbed = [note, C(archetype: .tab, key: "document:1", texts: ["Trip plans"])]
        expect(CommandBarRanking.rank(tabbed, query: "trip") == [1], "a Note open in a tab appears once, as its tab")
        let visits: [(url: String, title: String)] = [("https://www.youtube.com/", "YouTube"), ("https://youtube.com/watch?v=1", "A video"),
                                                       ("https://example.com/a", ""), ("ftp://files.example.com/", "")]
        let domains = CommandBarRanking.topDomains(visits)
        expect(domains.map(\.host) == ["youtube.com"], "top domains need two visits and an http(s) page")
        expect(domains.first?.siteName == "YouTube" && domains.first?.url.absoluteString == "https://youtube.com/",
               "a top domain opens its root with the root page's title")
        let domainRank = CommandBarRanking.rank([search("you", 0), C(archetype: .topDomain, key: CommandBarRowDiff.pageKey(domains[0].url), texts: ["youtube.com"]),
                                                 page("https://youtube.com/", 1)], query: "you")
        expect(domainRank == [0, 2], "Chromium's own row for the domain wins over the top-domain row")
        let domainOnly = CommandBarRanking.rank([search("you", 0), C(archetype: .topDomain, key: "page:youtube.com", texts: ["youtube.com"])], query: "you")
        expect(domainOnly == [0, 1], "otherwise the top domain ranks in")
        let githubHome = CommandBarRanking.pageKey(URL(string: "https://github.com/")!, title: "GitHub")
        let covered = CommandBarRanking.rank([C(archetype: .chromium, key: githubHome, chromiumRank: 0, urlKey: "page:github.com"),
                                              C(archetype: .topDomain, key: "page:github.com", texts: ["github.com"])], query: "git")
        expect(covered == [0], "a title-and-host page row still covers its top domain")
        let bumped = order([search("tab", 0), command("Pin Tab"), C(archetype: .typeTravel, key: "typeTravel:Duplicate Tab", texts: ["Duplicate Tab"], bump: 0.1),
                            C(archetype: .typeTravel, key: "typeTravel:Archive", texts: ["Archive"], bump: 1)], "tab")
        expect(bumped.firstIndex(of: "typeTravel:Duplicate Tab")! < bumped.firstIndex(of: "typeTravel:Pin Tab")!,
               "the candidate bump lifts an equally matched action")
        expect(!bumped.contains("typeTravel:Archive"), "a bump never makes an unmatched action a result")
        print("RankingTests: \(count) assertions passed")
    }
}
