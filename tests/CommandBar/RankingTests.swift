import Foundation

@main struct RankingTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
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

        let easel = [search("new eas", 0), search("new earth", 1), command("New Easel"), command("New Window"), search("new earth waste services", 2)]
        let easelOrder = order(easel, "new eas")
        expect(easelOrder.prefix(3) == ["typeTravel:New Easel", "search:new eas", "search:new earth"],
               "a Type Travel action named by the query leads, then Chromium's default")
        expect(!easelOrder.contains("typeTravel:New Window"), "an action the query doesn't match is not a result")
        let split = [search("split", 0), search("splitwise", 1), command("Add Right Split"), command("Add Left Split")]
        let splitOrder = order(split, "split")
        expect(splitOrder.first == "search:split", "word-only command matches don't outrank the search")
        expect(splitOrder.contains("typeTravel:Add Right Split") && splitOrder.contains("typeTravel:Add Left Split"), "the split commands still rank in")
        let space = [search("space", 0), command("Focus on", ["Space 1", "Focus on Space 1"])]
        expect(order(space, "space").first == "typeTravel:Focus on", "a contextual target named by the query leads")

        let interleaved = order([search("new", 0), search("news", 1), search("new york times", 2), search("new balance", 3),
                                 search("netflix", 4), command("New Easel"), command("New Folder")], "new")
        expect(interleaved[0] == "typeTravel:New Easel" && interleaved[1] == "search:new", "lead then default")
        expect(interleaved.firstIndex(of: "typeTravel:New Folder")! < interleaved.firstIndex(of: "search:netflix")!,
               "a prefix-matched command ranks above weaker suggestions")

        let merged = [page("https://www.youtube.com/", 0, title: "YouTube"), tab("YouTube", "https://youtube.com")]
        let mergedOrder = CommandBarRanking.rank(merged, query: "you")
        expect(mergedOrder == [1], "the tab replaces Chromium's row for its page")

        for (host, title) in [("google.com", "Google"), ("youtube.com", "YouTube")] {
            let website = "https://www.\(host)/"
            let results = [page(website, 0), search(host, 1), tab(title, website)]
            expect(CommandBarRanking.rank(results, query: host) == [2, 1],
                   "\(host) keeps its website default after merging with the open tab")
            let repeated = results + [tab(host + " - Google Search", "https://www.google.com/search?q=" + host)]
            expect(CommandBarRanking.rank(repeated, query: host).first == 2,
                   "an earlier accidental search for \(host) cannot displace its website default")
        }
        let escaped = [page("https://example.com/hello%20world", 0), search("hello world", 1),
                       tab("A page", "https://example.com/hello%20world")]
        expect(CommandBarRanking.rank(escaped, query: "hello world").first == 2,
               "a merged default remains admitted when Chromium matched text the local scorer cannot")
        let commandAndTab = [page("https://archive.org/", 0), search("arc", 1),
                             tab("Archive", "https://archive.org/"), command("Archive Tab")]
        expect(CommandBarRanking.rank(commandAndTab, query: "arc").prefix(2).elementsEqual([3, 2]),
               "the leading Type Travel action still precedes the merged default")
        let searchDefault = [search("google", 0), page("https://www.google.com/", 1), tab("Google", "https://www.google.com/")]
        expect(CommandBarRanking.rank(searchDefault, query: "google").first == 0,
               "merging a non-default website does not replace a genuine search default")
        let github = [page("https://github.com/etsenake/parc/pulls?q=1", 0, title: "Pull requests"),
                      tab("Pull requests", "https://github.com/etsenake/parc/pulls")]
        expect(CommandBarRanking.rank(github, query: "pull").count == 1, "listed sites dedup by title and host")

        func titled(_ archetype: CommandBarRanking.Archetype, _ url: String, _ title: String, rank: Int = 0) -> C {
            let address = URL(string: url)!
            return C(archetype: archetype, key: CommandBarRanking.pageKey(address, title: title), texts: [title], chromiumRank: rank,
                     urlKey: CommandBarRowDiff.pageKey(address), samePage: title.lowercased() + "\u{0}" + address.host! + address.path)
        }
        let signIn = "https://fullscript.okta.com/app/UserHome", dashboard = "My Apps Dashboard | Fullscript"
        let reported = [titled(.chromium, signIn + "?fromHome=true&session_hint=AUTHENTICATED", dashboard),
                        titled(.chromium, signIn + "?fromHome=true&session_hint=PENDING", dashboard, rank: 1),
                        titled(.tab, signIn + "?login_hint=someone", dashboard)]
        expect(CommandBarRanking.rank(reported, query: "fullscript") == [2],
               "sign-in visits that differ only in their parameters merge into the open tab")
        expect(CommandBarRanking.rank(Array(reported.prefix(2)), query: "fullscript") == [0], "the same page visited twice shows once")
        let mergedDefault = [titled(.chromium, signIn + "?a=1", dashboard), search("my apps", 1), titled(.tab, signIn + "#top", dashboard)]
        expect(CommandBarRanking.rank(mergedDefault, query: "my apps") == [2, 1], "the open tab takes the merged default's place")
        let videos = [titled(.chromium, "https://www.youtube.com/watch?v=1", "First video - YouTube"),
                      titled(.chromium, "https://www.youtube.com/watch?v=2", "Second video - YouTube", rank: 1),
                      titled(.tab, "https://www.youtube.com/watch?v=3", "Third video - YouTube")]
        expect(CommandBarRanking.rank(videos, query: "video").count == 3, "pages whose titles differ stay separate")
        let twoTabs = [titled(.tab, signIn + "?a=1", dashboard), titled(.tab, signIn + "?a=2", dashboard)]
        expect(CommandBarRanking.rank(twoTabs, query: "my apps").count == 2, "two open tabs of one page both stay switchable")
        let otherPath = [titled(.chromium, signIn + "?a=1", dashboard), titled(.tab, "https://fullscript.okta.com/app/Other", dashboard)]
        expect(CommandBarRanking.rank(otherPath, query: "my apps").count == 2, "another path is another page")
        let chained = [titled(.chromium, signIn + "?a=1", dashboard), titled(.chromium, signIn + "?a=2", dashboard, rank: 1),
                       C(archetype: .tab, key: CommandBarRanking.pageKey(URL(string: signIn + "?a=2")!, title: "Renamed"), texts: ["Renamed"],
                         urlKey: CommandBarRowDiff.pageKey(URL(string: signIn + "?a=2")!))]
        expect(CommandBarRanking.rank(chained, query: "fullscript") == [2], "an exact tab still claims every row merged with its page")
        let bridged = [titled(.chromium, signIn + "?b=1", dashboard), titled(.tab, signIn + "?a=1", dashboard),
                       titled(.tab, signIn + "?b=1", dashboard)]
        expect(CommandBarRanking.rank(bridged, query: "my apps").sorted() == [1, 2], "a visit never folds one open tab into another")
        let untitledFirst = [C(archetype: .chromium, key: CommandBarRowDiff.pageKey(URL(string: signIn + "?a=1")!), chromiumRank: 0,
                               urlKey: CommandBarRowDiff.pageKey(URL(string: signIn + "?a=1")!)),
                             titled(.chromium, signIn + "?b=1", dashboard, rank: 1), titled(.tab, signIn + "?a=1", dashboard)]
        expect(CommandBarRanking.rank(untitledFirst, query: "my apps") == [2], "a tab that took over one visit also takes its same-titled twin")
        let youtube = "youtube\u{0}youtube.com"
        let desktop = C(archetype: .chromium, key: "page:youtube.com/?app=desktop", urlKey: "page:youtube.com/?app=desktop", samePage: youtube)
        let site = C(archetype: .topDomain, key: "page:youtube.com", texts: ["youtube.com"], urlKey: "page:youtube.com", samePage: youtube)
        expect(CommandBarRanking.rank([desktop, site], query: "youtube.com", leadingPage: "page:youtube.com") == [1, 0],
               "a leading site row is never folded into a same-titled page")
        let root = C(archetype: .chromium, key: "page:youtube.com", chromiumRank: 1, urlKey: "page:youtube.com", samePage: youtube)
        expect(CommandBarRanking.rank([desktop, root], query: "youtube.com", leadingPage: "page:youtube.com") == [1, 0],
               "the site's own root row keeps the lead")
        let absorbing = [search("okta dashboard", 0), titled(.chromium, signIn + "?a=1", dashboard, rank: 1), titled(.tab, signIn + "?b=2", dashboard)]
        expect(CommandBarRanking.rank(absorbing, query: "okta dashboard") == [0, 2],
               "a tab that absorbs a matching visit takes its place even when its own text misses a word")
        expect(CommandBarRanking.rank([desktop, site], query: "youtube.com").count == 2, "a site row never folds into a page")
        expect(CommandBarRanking.rank([titled(.tab, signIn + "?a=1", dashboard), titled(.chromium, signIn + "?b=2", dashboard, rank: 1)],
                                      query: "my apps") == [0], "a tab listed first still takes the visit")
        let strong = [search("my apps", 0), search("my apps dashboard", 1), titled(.chromium, signIn + "?a=1", dashboard, rank: 5),
                      titled(.tab, signIn + "?b=2", dashboard)]
        expect(CommandBarRanking.rank(strong, query: "my apps dashboard") == [0, 3, 1], "a strong tab keeps its own score")

        let many = (0..<12).map { command("New Thing \($0)") } + (0..<12).map { search("new \($0)", $0) }
        let capped = CommandBarRanking.rank(many, query: "new")
        expect(capped.count == 13, "five actions and eight Chromium rows")
        expect(capped.filter { many[$0].archetype == .typeTravel }.count == 5, "Type Travel is capped at five")
        let wide = many + (0..<12).map { tab("New tab \($0)", "https://example\($0).com") }
        expect(CommandBarRanking.rank(wide, query: "new").count == 15, "the result stops at 15")

        let note = C(archetype: .document, key: "document:1", texts: ["Trip plans"])
        expect(order([search("trip", 0), note], "trip").contains("document:1"), "a Note without a tab is a result")
        let tabbed = [note, C(archetype: .tab, key: "document:1", texts: ["Trip plans"])]
        expect(CommandBarRanking.rank(tabbed, query: "trip") == [1], "a Note open in a tab appears once, as its tab")
        let visits: [(url: String, title: String)] = [("https://www.youtube.com/", "YouTube"), ("https://youtube.com/watch?v=1", "A video"),
                                                       ("https://example.com/a", ""), ("ftp://files.example.com/", "")]
        let domains = CommandBarRanking.topDomains(visits)
        expect(domains.map(\.host) == ["youtube.com"], "top domains need two visits and an http(s) page")
        expect(domains.first?.title == "YouTube" && domains.first?.url.absoluteString == "https://youtube.com/",
               "a top domain opens its root with the root page's title")
        let served = CommandBarRanking.topDomains([("http://localhost:3000/a", ""), ("http://localhost:3000/b", "Dashboard"),
                                                   ("http://localhost:8080/", ""), ("http://example.com/", "Old"),
                                                   ("https://www.example.com/", "New"), ("https://example.com/x", ""),
                                                   ("http://[::1]:8080/a", ""), ("http://[::1]:8080/b", "")])
        expect(served.map(\.host) == ["example.com", "[::1]:8080", "localhost:3000"], "each port is its own site")
        expect(served.first { $0.host == "localhost:3000" }?.url.absoluteString == "http://localhost:3000/"
               && served.first { $0.host == "[::1]:8080" }?.url.absoluteString == "http://[::1]:8080/",
               "a top domain keeps its port and IPv6 brackets")
        expect(served.first?.url.absoluteString == "https://example.com/" && served.first?.title == "New",
               "a top domain follows the latest visit's scheme and the latest root title")
        expect(served.first { $0.host == "localhost:3000" }?.title == "", "a deeper page's title never names the site")

        let completions: [(String, String, String?)] = [
            ("fullscript.ok", "fullscript.okta.com", "fullscript.okta.com"),
            ("Fullscript.OK", "fullscript.okta.com", "Fullscript.OKta.com"),
            ("www.fullscript.ok", "fullscript.okta.com", "www.fullscript.okta.com"),
            ("fullscript.okta.com", "fullscript.okta.com", "fullscript.okta.com"),
            ("fullscript.okta.com/", "fullscript.okta.com", nil), ("fullscript.okta.com/app", "fullscript.okta.com", nil),
            ("w", "fullscript.okta.com", nil), ("www", "fullscript.okta.com", nil), ("www.", "fullscript.okta.com", nil), ("okta", "fullscript.okta.com", nil),
            ("full script", "fullscript.okta.com", nil), ("", "fullscript.okta.com", nil),
            ("localhost:30", "localhost:3000", "localhost:3000"), ("münch", "münchen.de", "münchen.de")
        ]
        for (typed, host, expected) in completions {
            expect(CommandBarRanking.domainCompletion(typed: typed, host: host) == expected,
                   "\(typed) completes \(host) to \(expected ?? "nothing")")
        }

        let okta = URL(string: "https://fullscript.okta.com/app/UserHome?iss=https%3A%2F%2Ffullscript.okta.com&session_hint=AUTHENTICATED")!
        expect(CommandBarRanking.siteLead(typed: "fullscript.ok", defaultURL: okta).map { [$0.host, $0.page] }
               == ["fullscript.okta.com", "page:fullscript.okta.com"], "a deeper default page hands the lead to its site")
        expect(CommandBarRanking.siteLead(typed: "www.fullscript.okta.com", defaultURL: okta)?.host == "fullscript.okta.com",
               "typing the www form still leads with the site")
        for url in ["https://fullscript.okta.com/", "https://www.fullscript.okta.com", "http://fullscript.okta.com/"] {
            expect(CommandBarRanking.siteLead(typed: "fullscript.ok", defaultURL: URL(string: url)!) == nil,
                   "\(url): a root default already leads with the site")
        }
        for url in ["https://fullscript.okta.com/?from=1", "https://fullscript.okta.com/#top"] {
            expect(CommandBarRanking.siteLead(typed: "fullscript.ok", defaultURL: URL(string: url)!) != nil,
                   "\(url): a root with a query or fragment is a deeper page")
        }
        for typed in ["fullscript.okta.com/", "fullscript.okta.com/app", "okta", "fullscript ok", "https://fullscript.ok"] {
            expect(CommandBarRanking.siteLead(typed: typed, defaultURL: okta) == nil, "\(typed): Chromium's default keeps the lead")
        }
        expect(CommandBarRanking.siteLead(typed: "fullscript.ok", defaultURL: nil) == nil
               && CommandBarRanking.siteLead(typed: "local", defaultURL: URL(string: "file:///local/a")!) == nil,
               "only a web default can hand over the lead")
        expect(CommandBarRanking.siteLead(typed: "localhost:30", defaultURL: URL(string: "http://localhost:3000/dashboard")!)?.page
               == "page:localhost:3000", "the lead keeps the default's port")
        let punycode = CommandBarRanking.siteLead(typed: "münch", defaultURL: URL(string: "https://xn--mnchen-3ya.de/wiki")!)
        expect(punycode?.host == "münchen.de" && punycode?.page == CommandBarRowDiff.pageKey(URL(string: "https://xn--mnchen-3ya.de/")!),
               "an international site leads with the same root key as Chromium's own root row")
        expect(CommandBarRanking.siteLead(typed: "www.", defaultURL: okta) == nil, "typing just www. names no site")

        let oktaDefault = C(archetype: .chromium, key: CommandBarRowDiff.pageKey(okta), chromiumRank: 0, urlKey: CommandBarRowDiff.pageKey(okta))
        let oktaDomain = C(archetype: .topDomain, key: "page:fullscript.okta.com", texts: ["fullscript.okta.com"], urlKey: "page:fullscript.okta.com")
        let suggestions = (1...5).map { search("fullscript.ok \($0)", $0) }
        let redirected = [oktaDefault] + suggestions + [oktaDomain]
        let unled = CommandBarRanking.rank(redirected, query: "fullscript.ok")
        expect(unled.first == 0 && (unled.firstIndex(of: 6) ?? 0) >= 4,
               "without a lead, the deeper default fills in first and the site trails the suggestions")
        let led = CommandBarRanking.rank(redirected, query: "fullscript.ok", leadingPage: "page:fullscript.okta.com")
        expect(led.prefix(2).elementsEqual([6, 0]), "the site leads and Chromium's deeper default follows it")
        let rootRow = C(archetype: .chromium, key: "page:fullscript.okta.com", chromiumRank: 3, urlKey: "page:fullscript.okta.com")
        let nativeRoot = CommandBarRanking.rank([oktaDefault, rootRow, oktaDomain], query: "fullscript.ok", leadingPage: "page:fullscript.okta.com")
        expect(nativeRoot == [1, 0], "Chromium's own root row takes the lead when it covers the site")
        let rootTab = C(archetype: .tab, key: "page:fullscript.okta.com", texts: ["Okta"], urlKey: "page:fullscript.okta.com")
        expect(CommandBarRanking.rank([oktaDefault, rootRow, oktaDomain, rootTab], query: "fullscript.ok",
                                      leadingPage: "page:fullscript.okta.com").prefix(2).elementsEqual([3, 0]),
               "an open tab on the site's root leads as Switch to Tab")
        expect(CommandBarRanking.rank([oktaDefault] + suggestions, query: "fullscript.ok", leadingPage: "page:fullscript.okta.com").first == 0,
               "with no row for the site, Chromium's default keeps the lead")
        let commanded = CommandBarRanking.rank([oktaDefault, oktaDomain, command("Fullscript.ok Helper")], query: "fullscript.ok",
                                               leadingPage: "page:fullscript.okta.com")
        expect(commanded == [2, 1, 0], "an action named by the query still leads, then the site, then the default")
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
               "a candidate bump lifts an equally matched action")
        expect(!bumped.contains("typeTravel:Archive"), "a bump never makes an unmatched action a result")
        print("RankingTests: \(count) assertions passed")
    }
}
