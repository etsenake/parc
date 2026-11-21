import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct RankingTests {

    private typealias C = CommandBarRanking.Candidate
    private func command(_ title: String, _ extra: [String] = []) -> C { C(archetype: .typeTravel, key: "typeTravel:" + title, texts: [title] + extra) }
    private func search(_ terms: String, _ rank: Int) -> C { C(archetype: .chromium, key: CommandBarRowDiff.searchKey(terms), chromiumRank: rank) }
    private func page(_ url: String, _ rank: Int, title: String = "") -> C {
        C(archetype: .chromium, key: CommandBarRanking.pageKey(URL(string: url)!, title: title), chromiumRank: rank)
    }
    private func tab(_ title: String, _ url: String) -> C {
        C(archetype: .tab, key: CommandBarRanking.pageKey(URL(string: url)!, title: title), texts: [title, URL(string: url)!.host!, url])
    }
    private func order(_ candidates: [C], _ query: String) -> [String] {
        CommandBarRanking.rank(candidates, query: query).map { candidates[$0].key }
    }
    private func titled(_ archetype: CommandBarRanking.Archetype, _ url: String, _ title: String, rank: Int = 0) -> C {
        let address = URL(string: url)!
        return C(archetype: archetype, key: CommandBarRanking.pageKey(address, title: title), texts: [title], chromiumRank: rank,
                 urlKey: CommandBarRowDiff.pageKey(address), samePage: title.lowercased() + "\u{0}" + address.host! + address.path)
    }

    @Test func aNameStartingWithTheQueryIsAPrefixMatch() {
        #expect(CommandBarRanking.match("new eas", ["New Easel"]) == 0.9)
    }

    @Test func everyWordStartingAWordIsAWordMatch() {
        #expect(CommandBarRanking.match("add split", ["Add Right Split"]) == 0.7)
    }

    @Test func aWordInsideAWordIsAWeakMatch() {
        #expect(CommandBarRanking.match("ight", ["Add Right Split"]) == 0.4)
    }

    @Test func noMatch() {
        #expect(CommandBarRanking.match("xyz", ["Add Right Split"]) == 0)
    }

    @Test func aTypeTravelActionNamedByTheQueryLeadsThenChromiumDefault() {
        let easel = [search("new eas", 0), search("new earth", 1), command("New Easel"), command("New Window"), search("new earth waste services", 2)]
        let easelOrder = order(easel, "new eas")
        #expect(easelOrder.prefix(3) == ["typeTravel:New Easel", "search:new eas", "search:new earth"])
    }

    @Test func anActionTheQueryDoesnTMatchIsNotAResult() {
        let easel = [search("new eas", 0), search("new earth", 1), command("New Easel"), command("New Window"), search("new earth waste services", 2)]
        let easelOrder = order(easel, "new eas")
        #expect(!easelOrder.contains("typeTravel:New Window"))
    }

    @Test func wordOnlyCommandMatchesDonTOutrankTheSearch() {
        let split = [search("split", 0), search("splitwise", 1), command("Add Right Split"), command("Add Left Split")]
        let splitOrder = order(split, "split")
        #expect(splitOrder.first == "search:split")
    }

    @Test func theSplitCommandsStillRankIn() {
        let split = [search("split", 0), search("splitwise", 1), command("Add Right Split"), command("Add Left Split")]
        let splitOrder = order(split, "split")
        #expect(splitOrder.contains("typeTravel:Add Right Split") && splitOrder.contains("typeTravel:Add Left Split"))
    }

    @Test func aContextualTargetNamedByTheQueryLeads() {
        let space = [search("space", 0), command("Focus on", ["Space 1", "Focus on Space 1"])]
        #expect(order(space, "space").first == "typeTravel:Focus on")
    }

    @Test func leadThenDefault() {
        let interleaved = order([search("new", 0), search("news", 1), search("new york times", 2), search("new balance", 3),
                                 search("netflix", 4), command("New Easel"), command("New Folder")], "new")
        #expect(interleaved[0] == "typeTravel:New Easel" && interleaved[1] == "search:new")
    }

    @Test func aPrefixMatchedCommandRanksAboveWeakerSuggestions() {
        let interleaved = order([search("new", 0), search("news", 1), search("new york times", 2), search("new balance", 3),
                                 search("netflix", 4), command("New Easel"), command("New Folder")], "new")
        #expect(interleaved.firstIndex(of: "typeTravel:New Folder")! < interleaved.firstIndex(of: "search:netflix")!)
    }

    @Test func theTabReplacesChromiumRowForItsPage() {
        let merged = [page("https://www.youtube.com/", 0, title: "YouTube"), tab("YouTube", "https://youtube.com")]
        let mergedOrder = CommandBarRanking.rank(merged, query: "you")
        #expect(mergedOrder == [1])
    }

    @Test func aMergedDefaultRemainsAdmittedWhenChromiumMatchedTextTheLocalScorerCannot() {
        let escaped = [page("https://example.com/hello%20world", 0), search("hello world", 1),
                       tab("A page", "https://example.com/hello%20world")]
        #expect(CommandBarRanking.rank(escaped, query: "hello world").first == 2)
    }

    @Test func theLeadingTypeTravelActionStillPrecedesTheMergedDefault() {
        let commandAndTab = [page("https://archive.org/", 0), search("arc", 1),
                             tab("Archive", "https://archive.org/"), command("Archive Tab")]
        #expect(CommandBarRanking.rank(commandAndTab, query: "arc").prefix(2).elementsEqual([3, 2]))
    }

    @Test func mergingANonDefaultWebsiteDoesNotReplaceAGenuineSearchDefault() {
        let searchDefault = [search("google", 0), page("https://www.google.com/", 1), tab("Google", "https://www.google.com/")]
        #expect(CommandBarRanking.rank(searchDefault, query: "google").first == 0)
    }

    @Test func listedSitesDedupByTitleAndHost() {
        let github = [page("https://github.com/etsenake/parc/pulls?q=1", 0, title: "Pull requests"),
                      tab("Pull requests", "https://github.com/etsenake/parc/pulls")]
        #expect(CommandBarRanking.rank(github, query: "pull").count == 1)
    }

    @Test func signInVisitsThatDifferOnlyInTheirParametersMergeIntoTheOpen() {
        let signIn = "https://fullscript.okta.com/app/UserHome", dashboard = "My Apps Dashboard | Fullscript"
        let reported = [titled(.chromium, signIn + "?fromHome=true&session_hint=AUTHENTICATED", dashboard),
                        titled(.chromium, signIn + "?fromHome=true&session_hint=PENDING", dashboard, rank: 1),
                        titled(.tab, signIn + "?login_hint=someone", dashboard)]
        #expect(CommandBarRanking.rank(reported, query: "fullscript") == [2])
    }

    @Test func theSamePageVisitedTwiceShowsOnce() {
        let signIn = "https://fullscript.okta.com/app/UserHome", dashboard = "My Apps Dashboard | Fullscript"
        let reported = [titled(.chromium, signIn + "?fromHome=true&session_hint=AUTHENTICATED", dashboard),
                        titled(.chromium, signIn + "?fromHome=true&session_hint=PENDING", dashboard, rank: 1),
                        titled(.tab, signIn + "?login_hint=someone", dashboard)]
        #expect(CommandBarRanking.rank(Array(reported.prefix(2)), query: "fullscript") == [0])
    }

    @Test func theOpenTabTakesTheMergedDefaultSPlace() {
        let signIn = "https://fullscript.okta.com/app/UserHome", dashboard = "My Apps Dashboard | Fullscript"
        let mergedDefault = [titled(.chromium, signIn + "?a=1", dashboard), search("my apps", 1), titled(.tab, signIn + "#top", dashboard)]
        #expect(CommandBarRanking.rank(mergedDefault, query: "my apps") == [2, 1])
    }

    @Test func pagesWhoseTitlesDifferStaySeparate() {
        let videos = [titled(.chromium, "https://www.youtube.com/watch?v=1", "First video - YouTube"),
                      titled(.chromium, "https://www.youtube.com/watch?v=2", "Second video - YouTube", rank: 1),
                      titled(.tab, "https://www.youtube.com/watch?v=3", "Third video - YouTube")]
        #expect(CommandBarRanking.rank(videos, query: "video").count == 3)
    }

    @Test func twoOpenTabsOfOnePageBothStaySwitchable() {
        let signIn = "https://fullscript.okta.com/app/UserHome", dashboard = "My Apps Dashboard | Fullscript"
        let twoTabs = [titled(.tab, signIn + "?a=1", dashboard), titled(.tab, signIn + "?a=2", dashboard)]
        #expect(CommandBarRanking.rank(twoTabs, query: "my apps").count == 2)
    }

    @Test func anotherPathIsAnotherPage() {
        let signIn = "https://fullscript.okta.com/app/UserHome", dashboard = "My Apps Dashboard | Fullscript"
        let otherPath = [titled(.chromium, signIn + "?a=1", dashboard), titled(.tab, "https://fullscript.okta.com/app/Other", dashboard)]
        #expect(CommandBarRanking.rank(otherPath, query: "my apps").count == 2)
    }

    @Test func anExactTabStillClaimsEveryRowMergedWithItsPage() {
        let signIn = "https://fullscript.okta.com/app/UserHome", dashboard = "My Apps Dashboard | Fullscript"
        let chained = [titled(.chromium, signIn + "?a=1", dashboard), titled(.chromium, signIn + "?a=2", dashboard, rank: 1),
                       C(archetype: .tab, key: CommandBarRanking.pageKey(URL(string: signIn + "?a=2")!, title: "Renamed"), texts: ["Renamed"],
                         urlKey: CommandBarRowDiff.pageKey(URL(string: signIn + "?a=2")!))]
        #expect(CommandBarRanking.rank(chained, query: "fullscript") == [2])
    }

    @Test func aVisitNeverFoldsOneOpenTabIntoAnother() {
        let signIn = "https://fullscript.okta.com/app/UserHome", dashboard = "My Apps Dashboard | Fullscript"
        let bridged = [titled(.chromium, signIn + "?b=1", dashboard), titled(.tab, signIn + "?a=1", dashboard),
                       titled(.tab, signIn + "?b=1", dashboard)]
        #expect(CommandBarRanking.rank(bridged, query: "my apps").sorted() == [1, 2])
    }

    @Test func aTabThatTookOverOneVisitAlsoTakesItsSameTitledTwin() {
        let signIn = "https://fullscript.okta.com/app/UserHome", dashboard = "My Apps Dashboard | Fullscript"
        let untitledFirst = [C(archetype: .chromium, key: CommandBarRowDiff.pageKey(URL(string: signIn + "?a=1")!), chromiumRank: 0,
                               urlKey: CommandBarRowDiff.pageKey(URL(string: signIn + "?a=1")!)),
                             titled(.chromium, signIn + "?b=1", dashboard, rank: 1), titled(.tab, signIn + "?a=1", dashboard)]
        #expect(CommandBarRanking.rank(untitledFirst, query: "my apps") == [2])
    }

    @Test func aLeadingSiteRowIsNeverFoldedIntoASameTitledPage() {
        let youtube = "youtube\u{0}youtube.com"
        let desktop = C(archetype: .chromium, key: "page:youtube.com/?app=desktop", urlKey: "page:youtube.com/?app=desktop", samePage: youtube)
        let site = C(archetype: .topDomain, key: "page:youtube.com", texts: ["youtube.com"], urlKey: "page:youtube.com", samePage: youtube)
        #expect(CommandBarRanking.rank([desktop, site], query: "youtube.com", leadingPage: "page:youtube.com") == [1, 0])
    }

    @Test func theSiteSOwnRootRowKeepsTheLead() {
        let youtube = "youtube\u{0}youtube.com"
        let desktop = C(archetype: .chromium, key: "page:youtube.com/?app=desktop", urlKey: "page:youtube.com/?app=desktop", samePage: youtube)
        let root = C(archetype: .chromium, key: "page:youtube.com", chromiumRank: 1, urlKey: "page:youtube.com", samePage: youtube)
        #expect(CommandBarRanking.rank([desktop, root], query: "youtube.com", leadingPage: "page:youtube.com") == [1, 0])
    }

    @Test func aTabThatAbsorbsAMatchingVisitTakesItsPlaceEvenWhenIts() {
        let signIn = "https://fullscript.okta.com/app/UserHome", dashboard = "My Apps Dashboard | Fullscript"
        let absorbing = [search("okta dashboard", 0), titled(.chromium, signIn + "?a=1", dashboard, rank: 1), titled(.tab, signIn + "?b=2", dashboard)]
        #expect(CommandBarRanking.rank(absorbing, query: "okta dashboard") == [0, 2])
    }

    @Test func aSiteRowNeverFoldsIntoAPage() {
        let youtube = "youtube\u{0}youtube.com"
        let desktop = C(archetype: .chromium, key: "page:youtube.com/?app=desktop", urlKey: "page:youtube.com/?app=desktop", samePage: youtube)
        let site = C(archetype: .topDomain, key: "page:youtube.com", texts: ["youtube.com"], urlKey: "page:youtube.com", samePage: youtube)
        #expect(CommandBarRanking.rank([desktop, site], query: "youtube.com").count == 2)
    }

    @Test func aTabListedFirstStillTakesTheVisit() {
        let signIn = "https://fullscript.okta.com/app/UserHome", dashboard = "My Apps Dashboard | Fullscript"
        #expect(CommandBarRanking.rank([titled(.tab, signIn + "?a=1", dashboard), titled(.chromium, signIn + "?b=2", dashboard, rank: 1)],
                                      query: "my apps") == [0])
    }

    @Test func aStrongTabKeepsItsOwnScore() {
        let signIn = "https://fullscript.okta.com/app/UserHome", dashboard = "My Apps Dashboard | Fullscript"
        let strong = [search("my apps", 0), search("my apps dashboard", 1), titled(.chromium, signIn + "?a=1", dashboard, rank: 5),
                      titled(.tab, signIn + "?b=2", dashboard)]
        #expect(CommandBarRanking.rank(strong, query: "my apps dashboard") == [0, 3, 1])
    }

    @Test func fiveActionsAndEightChromiumRows() {
        let many = (0..<12).map { command("New Thing \($0)") } + (0..<12).map { search("new \($0)", $0) }
        let capped = CommandBarRanking.rank(many, query: "new")
        #expect(capped.count == 13)
    }

    @Test func typeTravelIsCappedAtFive() {
        let many = (0..<12).map { command("New Thing \($0)") } + (0..<12).map { search("new \($0)", $0) }
        let capped = CommandBarRanking.rank(many, query: "new")
        #expect(capped.filter { many[$0].archetype == .typeTravel }.count == 5)
    }

    @Test func theResultStopsAt15() {
        let many = (0..<12).map { command("New Thing \($0)") } + (0..<12).map { search("new \($0)", $0) }
        let wide = many + (0..<12).map { tab("New tab \($0)", "https://example\($0).com") }
        #expect(CommandBarRanking.rank(wide, query: "new").count == 15)
    }

    @Test func aNoteWithoutATabIsAResult() {
        let note = C(archetype: .document, key: "note:/Trip plans.md", texts: ["Trip plans"])
        #expect(order([search("trip", 0), note], "trip").contains("note:/Trip plans.md"))
    }

    @Test func aNoteOpenInATabAppearsOnceAsItsTab() {
        let note = C(archetype: .document, key: "note:/Trip plans.md", texts: ["Trip plans"])
        let tabbed = [note, C(archetype: .tab, key: "note:/Trip plans.md", texts: ["Trip plans"])]
        #expect(CommandBarRanking.rank(tabbed, query: "trip") == [1])
    }

    @Test func aNoteFileHasOneKeyHoweverItsPathIsSpelled() {
        let noteURL = URL(fileURLWithPath: "/Users/parc-sample/Documents/Parc Notes/Packing.md")
        #expect(CommandBarDocument.noteKey(noteURL) == CommandBarDocument.noteKey(URL(fileURLWithPath: "/Users/parc-sample/Documents/./Parc Notes/Packing.md")))
    }

    @Test func aNoteFileSDocumentKeyIsItsFileKey() {
        let noteURL = URL(fileURLWithPath: "/Users/parc-sample/Documents/Parc Notes/Packing.md")
        let fileNote = CommandBarDocument(kind: .note, id: UUID(), title: "Packing", url: noteURL)
        #expect(fileNote.key == CommandBarDocument.noteKey(noteURL))
    }

    @Test func aNoteWhoseBodyMatchesIsAResult() {
        let noteURL = URL(fileURLWithPath: "/Users/parc-sample/Documents/Parc Notes/Packing.md")
        let fileNote = CommandBarDocument(kind: .note, id: UUID(), title: "Packing", url: noteURL)
        let bodyOnly = C(archetype: .document, key: fileNote.key, texts: ["Packing"], contentScore: CommandBarRanking.noteContentScore)
        #expect(order([search("passport", 0), bodyOnly], "passport").contains(fileNote.key))
    }

    @Test func aTitleMatchOutranksABodyMatch() {
        let noteURL = URL(fileURLWithPath: "/Users/parc-sample/Documents/Parc Notes/Packing.md")
        let fileNote = CommandBarDocument(kind: .note, id: UUID(), title: "Packing", url: noteURL)
        let bodyOnly = C(archetype: .document, key: fileNote.key, texts: ["Packing"], contentScore: CommandBarRanking.noteContentScore)
        let titled = C(archetype: .document, key: "note:/Passport renewal.md", texts: ["Passport renewal"])
        #expect(order([bodyOnly, titled], "passport") == ["note:/Passport renewal.md", fileNote.key])
    }

    @Test func aBodyMatchOnANoteOpenInATabShowsItsTab() {
        let noteURL = URL(fileURLWithPath: "/Users/parc-sample/Documents/Parc Notes/Packing.md")
        let fileNote = CommandBarDocument(kind: .note, id: UUID(), title: "Packing", url: noteURL)
        let bodyOnly = C(archetype: .document, key: fileNote.key, texts: ["Packing"], contentScore: CommandBarRanking.noteContentScore)
        let bodyTab = [bodyOnly, C(archetype: .tab, key: fileNote.key, texts: ["Packing"])]
        #expect(CommandBarRanking.rank(bodyTab, query: "passport") == [1])
    }

    @Test func aNoteMatchingNothingStaysOut() {
        let quiet = C(archetype: .document, key: "note:/Other.md", texts: ["Other"])
        #expect(!order([search("passport", 0), quiet], "passport").contains("note:/Other.md"))
    }

    @Test func topDomainsNeedTwoVisitsAndAnHttpSPage() {
        let visits: [(url: String, title: String)] = [("https://www.youtube.com/", "YouTube"), ("https://youtube.com/watch?v=1", "A video"),
                                                       ("https://example.com/a", ""), ("ftp://files.example.com/", "")]
        let domains = CommandBarRanking.topDomains(visits)
        #expect(domains.map(\.host) == ["youtube.com"])
    }

    @Test func aTopDomainOpensItsRootWithTheRootPageSTitle() {
        let visits: [(url: String, title: String)] = [("https://www.youtube.com/", "YouTube"), ("https://youtube.com/watch?v=1", "A video"),
                                                       ("https://example.com/a", ""), ("ftp://files.example.com/", "")]
        let domains = CommandBarRanking.topDomains(visits)
        #expect(domains.first?.title == "YouTube" && domains.first?.url.absoluteString == "https://youtube.com/")
    }

    @Test func eachPortIsItsOwnSite() {
        let served = CommandBarRanking.topDomains([("http://localhost:3000/a", ""), ("http://localhost:3000/b", "Dashboard"),
                                                   ("http://localhost:8080/", ""), ("http://example.com/", "Old"),
                                                   ("https://www.example.com/", "New"), ("https://example.com/x", ""),
                                                   ("http://[::1]:8080/a", ""), ("http://[::1]:8080/b", "")])
        #expect(served.map(\.host) == ["example.com", "[::1]:8080", "localhost:3000"])
    }

    @Test func aTopDomainKeepsItsPortAndIPv6Brackets() {
        let served = CommandBarRanking.topDomains([("http://localhost:3000/a", ""), ("http://localhost:3000/b", "Dashboard"),
                                                   ("http://localhost:8080/", ""), ("http://example.com/", "Old"),
                                                   ("https://www.example.com/", "New"), ("https://example.com/x", ""),
                                                   ("http://[::1]:8080/a", ""), ("http://[::1]:8080/b", "")])
        #expect(served.first { $0.host == "localhost:3000" }?.url.absoluteString == "http://localhost:3000/"
               && served.first { $0.host == "[::1]:8080" }?.url.absoluteString == "http://[::1]:8080/")
    }

    @Test func aTopDomainFollowsTheLatestVisitSSchemeAndTheLatestRoot() {
        let served = CommandBarRanking.topDomains([("http://localhost:3000/a", ""), ("http://localhost:3000/b", "Dashboard"),
                                                   ("http://localhost:8080/", ""), ("http://example.com/", "Old"),
                                                   ("https://www.example.com/", "New"), ("https://example.com/x", ""),
                                                   ("http://[::1]:8080/a", ""), ("http://[::1]:8080/b", "")])
        #expect(served.first?.url.absoluteString == "https://example.com/" && served.first?.title == "New")
    }

    @Test func aDeeperPageSTitleNeverNamesTheSite() {
        let served = CommandBarRanking.topDomains([("http://localhost:3000/a", ""), ("http://localhost:3000/b", "Dashboard"),
                                                   ("http://localhost:8080/", ""), ("http://example.com/", "Old"),
                                                   ("https://www.example.com/", "New"), ("https://example.com/x", ""),
                                                   ("http://[::1]:8080/a", ""), ("http://[::1]:8080/b", "")])
        #expect(served.first { $0.host == "localhost:3000" }?.title == "")
    }

    @Test func aDeeperDefaultPageHandsTheLeadToItsSite() {
        let okta = URL(string: "https://fullscript.okta.com/app/UserHome?iss=https%3A%2F%2Ffullscript.okta.com&session_hint=AUTHENTICATED")!
        #expect(CommandBarRanking.siteLead(typed: "fullscript.ok", defaultURL: okta).map { [$0.host, $0.page] }
               == ["fullscript.okta.com", "page:fullscript.okta.com"])
    }

    @Test func theWWWPrefixCanLeadToTheRootSite() {
        let page = URL(string: "https://fullscript.okta.com/app/UserHome")!
        #expect(CommandBarRanking.siteLead(typed: "www.fullscript.okta.com", defaultURL: page)?.host == "fullscript.okta.com")
    }

    @Test(arguments: [nil, "file:///local/a"] as [String?])
    func onlyAWebDefaultCanHandOverTheLead(address: String?) {
        #expect(CommandBarRanking.siteLead(typed: "local", defaultURL: address.flatMap(URL.init(string:))) == nil)
    }

    @Test func theLeadKeepsTheDefaultPort() {
        #expect(CommandBarRanking.siteLead(typed: "localhost:30", defaultURL: URL(string: "http://localhost:3000/dashboard")!)?.page
               == "page:localhost:3000")
    }

    @Test func anInternationalSiteLeadsWithTheSameRootKeyAsChromiumOwn() {
        let punycode = CommandBarRanking.siteLead(typed: "münch", defaultURL: URL(string: "https://xn--mnchen-3ya.de/wiki")!)
        #expect(punycode?.host == "münchen.de" && punycode?.page == CommandBarRowDiff.pageKey(URL(string: "https://xn--mnchen-3ya.de/")!))
    }

    @Test func typingJustWwwNamesNoSite() {
        let okta = URL(string: "https://fullscript.okta.com/app/UserHome?iss=https%3A%2F%2Ffullscript.okta.com&session_hint=AUTHENTICATED")!
        #expect(CommandBarRanking.siteLead(typed: "www.", defaultURL: okta) == nil)
    }

    @Test func withoutALeadTheDeeperDefaultFillsInFirstAndTheSiteTrails() {
        let okta = URL(string: "https://fullscript.okta.com/app/UserHome?iss=https%3A%2F%2Ffullscript.okta.com&session_hint=AUTHENTICATED")!
        let oktaDefault = C(archetype: .chromium, key: CommandBarRowDiff.pageKey(okta), chromiumRank: 0, urlKey: CommandBarRowDiff.pageKey(okta))
        let oktaDomain = C(archetype: .topDomain, key: "page:fullscript.okta.com", texts: ["fullscript.okta.com"], urlKey: "page:fullscript.okta.com")
        let suggestions = (1...5).map { search("fullscript.ok \($0)", $0) }
        let redirected = [oktaDefault] + suggestions + [oktaDomain]
        let unled = CommandBarRanking.rank(redirected, query: "fullscript.ok")
        #expect(unled.first == 0 && (unled.firstIndex(of: 6) ?? 0) >= 4)
    }

    @Test func theSiteLeadsAndChromiumDeeperDefaultFollowsIt() {
        let okta = URL(string: "https://fullscript.okta.com/app/UserHome?iss=https%3A%2F%2Ffullscript.okta.com&session_hint=AUTHENTICATED")!
        let oktaDefault = C(archetype: .chromium, key: CommandBarRowDiff.pageKey(okta), chromiumRank: 0, urlKey: CommandBarRowDiff.pageKey(okta))
        let oktaDomain = C(archetype: .topDomain, key: "page:fullscript.okta.com", texts: ["fullscript.okta.com"], urlKey: "page:fullscript.okta.com")
        let suggestions = (1...5).map { search("fullscript.ok \($0)", $0) }
        let redirected = [oktaDefault] + suggestions + [oktaDomain]
        let led = CommandBarRanking.rank(redirected, query: "fullscript.ok", leadingPage: "page:fullscript.okta.com")
        #expect(led.prefix(2).elementsEqual([6, 0]))
    }

    @Test func chromiumOwnRootRowTakesTheLeadWhenItCoversTheSite() {
        let okta = URL(string: "https://fullscript.okta.com/app/UserHome?iss=https%3A%2F%2Ffullscript.okta.com&session_hint=AUTHENTICATED")!
        let oktaDefault = C(archetype: .chromium, key: CommandBarRowDiff.pageKey(okta), chromiumRank: 0, urlKey: CommandBarRowDiff.pageKey(okta))
        let oktaDomain = C(archetype: .topDomain, key: "page:fullscript.okta.com", texts: ["fullscript.okta.com"], urlKey: "page:fullscript.okta.com")
        let rootRow = C(archetype: .chromium, key: "page:fullscript.okta.com", chromiumRank: 3, urlKey: "page:fullscript.okta.com")
        let nativeRoot = CommandBarRanking.rank([oktaDefault, rootRow, oktaDomain], query: "fullscript.ok", leadingPage: "page:fullscript.okta.com")
        #expect(nativeRoot == [1, 0])
    }

    @Test func anOpenTabOnTheSiteRootLeadsAsSwitchToTab() {
        let okta = URL(string: "https://fullscript.okta.com/app/UserHome?iss=https%3A%2F%2Ffullscript.okta.com&session_hint=AUTHENTICATED")!
        let oktaDefault = C(archetype: .chromium, key: CommandBarRowDiff.pageKey(okta), chromiumRank: 0, urlKey: CommandBarRowDiff.pageKey(okta))
        let oktaDomain = C(archetype: .topDomain, key: "page:fullscript.okta.com", texts: ["fullscript.okta.com"], urlKey: "page:fullscript.okta.com")
        let rootRow = C(archetype: .chromium, key: "page:fullscript.okta.com", chromiumRank: 3, urlKey: "page:fullscript.okta.com")
        let rootTab = C(archetype: .tab, key: "page:fullscript.okta.com", texts: ["Okta"], urlKey: "page:fullscript.okta.com")
        #expect(CommandBarRanking.rank([oktaDefault, rootRow, oktaDomain, rootTab], query: "fullscript.ok",
                                      leadingPage: "page:fullscript.okta.com").prefix(2).elementsEqual([3, 0]))
    }

    @Test func withNoRowForTheSiteChromiumDefaultKeepsTheLead() {
        let okta = URL(string: "https://fullscript.okta.com/app/UserHome?iss=https%3A%2F%2Ffullscript.okta.com&session_hint=AUTHENTICATED")!
        let oktaDefault = C(archetype: .chromium, key: CommandBarRowDiff.pageKey(okta), chromiumRank: 0, urlKey: CommandBarRowDiff.pageKey(okta))
        let suggestions = (1...5).map { search("fullscript.ok \($0)", $0) }
        #expect(CommandBarRanking.rank([oktaDefault] + suggestions, query: "fullscript.ok", leadingPage: "page:fullscript.okta.com").first == 0)
    }

    @Test func anExactCommandRanksBeforeTheSiteAndItsDeepPage() {
        let okta = URL(string: "https://fullscript.okta.com/app/UserHome?iss=https%3A%2F%2Ffullscript.okta.com&session_hint=AUTHENTICATED")!
        let oktaDefault = C(archetype: .chromium, key: CommandBarRowDiff.pageKey(okta), chromiumRank: 0, urlKey: CommandBarRowDiff.pageKey(okta))
        let oktaDomain = C(archetype: .topDomain, key: "page:fullscript.okta.com", texts: ["fullscript.okta.com"], urlKey: "page:fullscript.okta.com")
        let commanded = CommandBarRanking.rank([oktaDefault, oktaDomain, command("Fullscript.ok Helper")], query: "fullscript.ok",
                                               leadingPage: "page:fullscript.okta.com")
        #expect(commanded == [2, 1, 0])
    }

    @Test func chromiumOwnRowForTheDomainWinsOverTheTopDomainRow() {
        let visits: [(url: String, title: String)] = [("https://www.youtube.com/", "YouTube"), ("https://youtube.com/watch?v=1", "A video"),
                                                       ("https://example.com/a", ""), ("ftp://files.example.com/", "")]
        let domains = CommandBarRanking.topDomains(visits)
        let domainRank = CommandBarRanking.rank([search("you", 0), C(archetype: .topDomain, key: CommandBarRowDiff.pageKey(domains[0].url), texts: ["youtube.com"]),
                                                 page("https://youtube.com/", 1)], query: "you")
        #expect(domainRank == [0, 2])
    }

    @Test func otherwiseTheTopDomainRanksIn() {
        let domainOnly = CommandBarRanking.rank([search("you", 0), C(archetype: .topDomain, key: "page:youtube.com", texts: ["youtube.com"])], query: "you")
        #expect(domainOnly == [0, 1])
    }

    @Test func aTitleAndHostPageRowStillCoversItsTopDomain() {
        let githubHome = CommandBarRanking.pageKey(URL(string: "https://github.com/")!, title: "GitHub")
        let covered = CommandBarRanking.rank([C(archetype: .chromium, key: githubHome, chromiumRank: 0, urlKey: "page:github.com"),
                                              C(archetype: .topDomain, key: "page:github.com", texts: ["github.com"])], query: "git")
        #expect(covered == [0])
    }

    @Test func aCandidateBumpLiftsAnEquallyMatchedAction() {
        let bumped = order([search("tab", 0), command("Pin Tab"), C(archetype: .typeTravel, key: "typeTravel:Duplicate Tab", texts: ["Duplicate Tab"], bump: 0.1),
                            C(archetype: .typeTravel, key: "typeTravel:Archive", texts: ["Archive"], bump: 1)], "tab")
        #expect(bumped.firstIndex(of: "typeTravel:Duplicate Tab")! < bumped.firstIndex(of: "typeTravel:Pin Tab")!)
    }

    @Test func aBumpNeverMakesAnUnmatchedActionAResult() {
        let bumped = order([search("tab", 0), command("Pin Tab"), C(archetype: .typeTravel, key: "typeTravel:Duplicate Tab", texts: ["Duplicate Tab"], bump: 0.1),
                            C(archetype: .typeTravel, key: "typeTravel:Archive", texts: ["Archive"], bump: 1)], "tab")
        #expect(!bumped.contains("typeTravel:Archive"))
    }

    @Test(arguments: [("google.com", "Google"), ("youtube.com", "YouTube")]) func aMergedWebsiteDefaultKeepsItsRank(host: String, title: String) {
        let website = "https://www.\(host)/"
        let results = [page(website, 0), search(host, 1), tab(title, website)]
        #expect(CommandBarRanking.rank(results, query: host) == [2, 1])
    }

    @Test(arguments: [("google.com", "Google"), ("youtube.com", "YouTube")]) func aPriorSearchCannotDisplaceTheMergedWebsiteDefault(host: String, title: String) {
        let website = "https://www.\(host)/"
        let results = [page(website, 0), search(host, 1), tab(title, website),
                       tab(host + " - Google Search", "https://www.google.com/search?q=" + host)]
        #expect(CommandBarRanking.rank(results, query: host).first == 2)
    }

    @Test(arguments: [
            ("fullscript.ok", "fullscript.okta.com", "fullscript.okta.com"),
            ("Fullscript.OK", "fullscript.okta.com", "Fullscript.OKta.com"),
            ("www.fullscript.ok", "fullscript.okta.com", "www.fullscript.okta.com"),
            ("fullscript.okta.com", "fullscript.okta.com", "fullscript.okta.com"),
            ("fullscript.okta.com/", "fullscript.okta.com", nil), ("fullscript.okta.com/app", "fullscript.okta.com", nil),
            ("w", "fullscript.okta.com", nil), ("www", "fullscript.okta.com", nil), ("www.", "fullscript.okta.com", nil), ("okta", "fullscript.okta.com", nil),
            ("full script", "fullscript.okta.com", nil), ("", "fullscript.okta.com", nil),
            ("localhost:30", "localhost:3000", "localhost:3000"), ("münch", "münchen.de", "münchen.de")
    ] as [(String, String, String?)]) func aHostCompletesOnlyItsLiteralPrefix(typed: String, host: String, expected: String?) {
        #expect(CommandBarRanking.domainCompletion(typed: typed, host: host) == expected)
    }

    @Test(arguments: ["", "/", "/?from=1", "/#top"]) func aRootAlreadyOwnsTheLead(tail: String) {
        let url = URL(string: "https://fullscript.okta.com" + tail)!
        #expect((CommandBarRanking.siteLead(typed: "fullscript.ok", defaultURL: url) != nil) == (tail.count > 1))
    }

    @Test(arguments: ["fullscript.okta.com/", "fullscript.okta.com/app", "okta", "fullscript ok", "https://fullscript.ok"]) func anUnrelatedOrCompleteQueryKeepsTheDefault(typed: String) {
        let url = URL(string: "https://fullscript.okta.com/app/UserHome")!
        #expect(CommandBarRanking.siteLead(typed: typed, defaultURL: url) == nil)
    }
}
