import Foundation

@main struct TitleSearchTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        typealias C = CommandBarRanking.Candidate
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let profile = UUID(), here = UUID(), there = UUID()
        func search(_ terms: String, _ rank: Int) -> C { C(archetype: .chromium, key: CommandBarRowDiff.searchKey(terms), chromiumRank: rank) }
        func page(_ url: String, _ rank: Int, title: String = "") -> C {
            C(archetype: .chromium, key: CommandBarRanking.pageKey(URL(string: url)!, title: title), chromiumRank: rank,
              urlKey: CommandBarRowDiff.pageKey(URL(string: url)!))
        }
        func browserTab(_ title: String, _ url: String, archivedAt: Date? = nil, lastAccessed: Date = now) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: there, profileID: profile, url: url, title: title, kind: .today, folderID: nil,
                       createdAt: now.addingTimeInterval(-86_400 * 30), lastAccessed: lastAccessed, archivedAt: archivedAt,
                       savedURL: url, savedTitle: title)
        }
        func visit(_ url: String, _ title: String, _ secondsAgo: Double) -> BrowserHistoryEntry {
            BrowserHistoryEntry(id: UUID(), url: url, title: title, visitedAt: now.addingTimeInterval(-secondsAgo), profileID: profile)
        }
        struct Built {
            var candidates: [C] = []
            var titled: [(index: Int, key: String, score: CommandBarTitleMatch.Score, keepsWeak: Bool)] = []
            mutating func add(_ candidate: C, score: CommandBarTitleMatch.Score?, keepsWeak: Bool) {
                if let score { titled.append((candidates.count, candidate.key, score, keepsWeak)) }
                candidates.append(candidate)
            }
            func resolved() -> [C] {
                var result = candidates
                for (entry, score) in zip(titled, CommandBarTitleMatch.resolve(titled.map { ($0.key, $0.score, $0.keepsWeak) })) {
                    result[entry.index].titleScore = score
                }
                return result
            }
        }
        func tabCandidate(_ tab: BrowserTab, _ query: CommandBarTitleQuery?, into built: inout Built) {
            let url = URL(string: tab.url)!
            let key = CommandBarTitleIndex.tabKey(url: tab.url, title: tab.title, id: tab.id)
            let score = query.flatMap {
                CommandBarTitleMatch.score($0, CommandBarTitleTokens(titles: [tab.title], host: url.host), kind: .tab,
                                           lastUsed: tab.lastAccessed, visits: 0, now: now)
            }
            built.add(C(archetype: .tab, key: key, texts: [tab.title, url.host ?? "", tab.url], urlKey: CommandBarRowDiff.pageKey(url)),
                      score: score, keepsWeak: false)
        }
        func indexHits(_ index: CommandBarTitleIndex, _ query: CommandBarTitleQuery, into built: inout Built) {
            let hits = index.search(query, now: now)
            for hit in hits.archived {
                built.add(C(archetype: .archived, key: hit.entry.key, urlKey: hit.entry.urlKey), score: hit.score, keepsWeak: true)
            }
            for hit in hits.pages {
                built.add(C(archetype: .history, key: hit.entry.key, urlKey: hit.entry.urlKey), score: hit.score, keepsWeak: true)
            }
        }

        expect(CommandBarTitleQuery("da") == nil, "two letters are too short to outrank anything")
        expect(CommandBarTitleQuery("  ||  ") == nil, "punctuation alone is not a title query")
        expect(CommandBarTitleQuery("dashboard")?.words.count == 1, "a word is a title query")
        func quality(_ query: String, _ title: String, host: String? = nil) -> (value: Double, inTitle: Bool)? {
            CommandBarTitleMatch.quality(CommandBarTitleQuery(query)!, CommandBarTitleTokens(titles: [title], host: host))
        }
        expect(quality("dashboard", "My Apps Dashboard | Fullscript")?.inTitle == true, "a word in the middle of a title matches")
        expect(quality("dash", "My Apps Dashboard")?.inTitle == true, "a partly typed word matches the start of a title word")
        expect(quality("ashboard", "My Apps Dashboard") == nil, "the middle of a word is not a title match")
        expect(quality("apps dash", "My Apps Dashboard")!.value > quality("dash apps", "My Apps Dashboard")!.value,
               "words in the title's order score higher")
        expect(quality("my apps", "My Apps Dashboard")!.value > quality("apps dashboard", "My Apps Dashboard")!.value,
               "a title that starts with the query scores higher")
        expect(quality("apps dashboard", "My Apps Dashboard")!.value > quality("apps dash", "My Apps Dashboard")!.value,
               "whole words score higher than partly typed ones")
        expect(quality("apps planner", "My Apps Dashboard") == nil, "every word must be present")
        expect(quality("node.js", "Node.js documentation")?.inTitle == true, "punctuation inside a word matches across title words")
        expect(quality("cafe menu", "Café Menu")?.inTitle == true, "accents and case fold away")
        expect(quality("东京", "东京天气预报")?.inTitle == true, "text without spaces matches inside its run")
        expect(quality("phone手机", "iPhone手机")?.inTitle == true, "mixed-script words match inside a title word")
        let hostOnly = quality("fullscript", "My Apps Dashboard", host: "us.fullscript.com")
        expect(hostOnly?.inTitle == false, "a site name in the address alone is not a title match")
        expect(quality("com", "My Apps Dashboard", host: "us.fullscript.com") == nil, "the top-level domain is not searchable")

        expect(CommandBarTitleMatch.wordsQuery("dashboard", nativeRowsAnswer: true, defaultIsSearch: true) != nil,
               "a search default means the user is typing words")
        expect(CommandBarTitleMatch.wordsQuery("fullscript.com/dash", nativeRowsAnswer: true, defaultIsSearch: false) == nil,
               "a web address default means the user is typing an address")
        expect(CommandBarTitleMatch.wordsQuery("dashboard", nativeRowsAnswer: true, defaultIsSearch: nil) == nil,
               "without Chromium's answer the bar ranks as it always has")
        expect(CommandBarTitleMatch.wordsQuery("dashboard", nativeRowsAnswer: false, defaultIsSearch: true) == nil,
               "an answer for earlier input does not decide the current one")

        let dashboard = browserTab("My Apps Dashboard | Fullscript", "https://us.fullscript.com/dashboard")
        func dashboardResults(_ query: CommandBarTitleQuery?) -> [C] {
            var built = Built()
            for (rank, terms) in ["dashboard", "dashboard meaning", "dashboard camera", "dashboard lights", "dashboard design", "dashboard ui"].enumerated() {
                built.add(search(terms, rank), score: nil, keepsWeak: false)
            }
            tabCandidate(dashboard, query, into: &built)
            return built.resolved()
        }
        let typedWords = CommandBarTitleMatch.wordsQuery("dashboard", nativeRowsAnswer: true, defaultIsSearch: true)
        let before = dashboardResults(nil)
        expect(CommandBarRanking.rank(before, query: "dashboard").firstIndex(of: 6)! >= 5,
               "without title scoring a mid-title word match falls below the visible search suggestions")
        let after = dashboardResults(typedWords)
        let afterOrder = CommandBarRanking.rank(after, query: "dashboard")
        expect(afterOrder.prefix(2).elementsEqual([0, 6]), "a mid-title word match comes right after Chromium's default search")

        var address = Built()
        address.add(page("https://us.fullscript.com/dashboard", 0, title: "My Apps Dashboard | Fullscript"), score: nil, keepsWeak: false)
        address.add(search("us.fullscript.com/dash", 1), score: nil, keepsWeak: false)
        address.add(page("https://us.fullscript.com/dashboard/orders", 2), score: nil, keepsWeak: false)
        tabCandidate(browserTab("Fullscript dash notes", "https://notes.example.com/fullscript"),
                     CommandBarTitleMatch.wordsQuery("us.fullscript.com/dash", nativeRowsAnswer: true, defaultIsSearch: false), into: &address)
        let addressOrder = CommandBarRanking.rank(address.resolved(), query: "us.fullscript.com/dash")
        expect(address.titled.isEmpty, "typing an address adds no title scores")
        expect(addressOrder.prefix(3).elementsEqual([0, 1, 2]), "address results keep leading in Chromium's order")

        let planning = browserTab("Quarterly Planning — Roadmap", "https://docs.example.com/planning",
                                  archivedAt: now.addingTimeInterval(-3 * 86_400))
        let older = browserTab("Planning poker", "https://poker.example.com/", archivedAt: now.addingTimeInterval(-20 * 86_400))
        let openTab = browserTab("Planning board", "https://board.example.com/")
        let otherProfile = BrowserTab(id: UUID(), spaceID: here, profileID: UUID(), url: "https://elsewhere.example.com/",
                                      title: "Planning elsewhere", kind: .today, folderID: nil, createdAt: now, lastAccessed: now,
                                      archivedAt: now, savedURL: "", savedTitle: "")
        let history = [visit("https://docs.example.com/planning", "Quarterly Planning — Roadmap", 4 * 86_400),
                       visit("https://wiki.example.com/q3", "Q3 planning notes", 9 * 86_400),
                       visit("https://www.wiki.example.com/q3", "Q3 planning notes", 8 * 86_400),
                       visit("https://board.example.com/", "Planning board", 60),
                       visit("https://news.example.com/", "Morning news", 30)]
        let index = CommandBarTitleIndex.build(profileID: profile, historyRevision: 1,
                                               tabs: [openTab, planning, older, otherProfile], history: history, reusing: nil)
        expect(index.archived.map(\.tabID) == [planning.id, older.id], "archived tabs of this Profile, most recently archived first")
        expect(index.pages.count == 4, "pages merge duplicate visits by page key")
        expect(index.visits(forKey: CommandBarRanking.pageKey(URL(string: "https://wiki.example.com/q3")!, title: "")) == 2,
               "visits to the same page count together")
        let planningQuery = CommandBarTitleQuery("planning")!
        let hits = index.search(planningQuery, now: now)
        expect(hits.archived.first?.entry.tabID == planning.id, "the archived tab is found by a word in its title")
        expect(hits.archived.first?.entry.url == planning.url, "an archived row keeps its real address for Copy")
        expect(CommandBarTitleText.archivedCaption(archivedAt: planning.archivedAt!, now: now).text == "Archived · 3 days ago",
               "archived rows say when they were archived")
        expect(CommandBarTitleText.archivedCaption(archivedAt: planning.archivedAt!, now: now).spoken == "Put Back, archived 3 days ago",
               "VoiceOver hears the Put Back action")
        expect(index.search(CommandBarTitleQuery("news")!, now: now, excludingURLKey: "page:news.example.com").pages.isEmpty,
               "the current page is not offered again")
        expect(index.search(planningQuery, now: now, includesArchive: false).archived.isEmpty, "the address editor offers no archive rows")
        for (seconds, text) in [(30.0, "just now"), (90, "1 minute ago"), (7_200, "2 hours ago"), (100_000, "yesterday"),
                                (3 * 86_400 + 5, "3 days ago"), (20 * 86_400, "2 weeks ago"), (70 * 86_400, "2 months ago")] {
            expect(CommandBarTitleText.age(from: now.addingTimeInterval(-seconds), to: now) == text, "age reads \(text)")
        }

        var merged = Built()
        merged.add(search("planning", 0), score: nil, keepsWeak: false)
        for rank in 1...5 { merged.add(search("planning \(rank)", rank), score: nil, keepsWeak: false) }
        merged.add(page("https://wiki.example.com/q3", 6, title: "Q3 planning notes"), score: nil, keepsWeak: false)
        merged.add(page("https://docs.example.com/planning", 7), score: nil, keepsWeak: false)
        tabCandidate(openTab, planningQuery, into: &merged)
        indexHits(index, planningQuery, into: &merged)
        let mergedCandidates = merged.resolved()
        let mergedOrder = CommandBarRanking.rank(mergedCandidates, query: "planning")
        let keys = mergedOrder.map { mergedCandidates[$0].key }
        expect(Set(keys).count == keys.count, "the same page never shows twice")
        let boardKey = CommandBarRanking.pageKey(URL(string: openTab.url)!, title: openTab.title)
        expect(mergedOrder.filter { mergedCandidates[$0].key == boardKey }.map { mergedCandidates[$0].archetype } == [.tab],
               "an open tab wins over its archived copy, its past visits and Chromium's row")
        let docsKey = CommandBarRanking.pageKey(URL(string: planning.url)!, title: planning.title)
        expect(mergedOrder.filter { mergedCandidates[$0].key == docsKey }.map { mergedCandidates[$0].archetype } == [.archived],
               "an archived tab wins over Chromium's history row and Parc's past visit")
        let wikiKey = CommandBarRanking.pageKey(URL(string: "https://wiki.example.com/q3")!, title: "")
        expect(mergedOrder.filter { mergedCandidates[$0].key == wikiKey }.map { mergedCandidates[$0].archetype } == [.chromium],
               "Chromium's own row keeps a past page's real request")
        expect(mergedOrder.first == 0, "Chromium's default search stays first")
        let strongest = mergedOrder.prefix(5).map { mergedCandidates[$0].archetype }
        expect(strongest == [.chromium, .tab, .archived, .archived, .chromium],
               "three strong title matches follow the default, then the suggestions")

        var lift = Built()
        lift.add(search("notes", 0), score: nil, keepsWeak: false)
        for rank in 1...5 { lift.add(search("notes \(rank)", rank), score: nil, keepsWeak: false) }
        lift.add(page("https://wiki.example.com/q3", 6, title: "Q3 planning notes"), score: nil, keepsWeak: false)
        indexHits(index, CommandBarTitleQuery("notes")!, into: &lift)
        let liftOrder = CommandBarRanking.rank(lift.resolved(), query: "notes")
        expect(liftOrder.prefix(2).elementsEqual([0, 6]),
               "a past page's title match lifts Chromium's own row for it above the search suggestions")

        let weakOnly = CommandBarTitleMatch.resolve([
            ("a", .init(strong: 0.9, weak: 0.5), false), ("b", .init(strong: 0.88, weak: 0.5), true),
            ("c", .init(strong: 0.86, weak: 0.5), true), ("d", .init(strong: 0.84, weak: 0.5), true),
            ("e", .init(strong: 0.83, weak: 0.4), false), ("a", .init(strong: 0.8, weak: 0.4), true)])
        expect(weakOnly == [0.9, 0.88, 0.86, 0.5, nil, 0.8],
               "at most three pages rise above suggestions; duplicates of a risen page stay with it")

        let manyArchived = (0..<5_000).map { number in
            browserTab("Report \(number) planning", "https://reports.example.com/\(number)",
                       archivedAt: now.addingTimeInterval(-Double(number) * 60))
        }
        let manyVisits = (0..<30_000).map { number in
            visit("https://pages.example.com/\(number % 12_000)", "Page \(number % 12_000) planning", Double(number))
        }
        let large = CommandBarTitleIndex.build(profileID: profile, historyRevision: 2, tabs: manyArchived.shuffled(),
                                               history: manyVisits.reversed(), reusing: nil)
        expect(large.archived.count == CommandBarTitleIndex.archiveWindow, "only the most recent thousand archived tabs are searched")
        expect(large.archived.first?.tabID == manyArchived[0].id && large.archived.last?.tabID == manyArchived[999].id,
               "the archive window holds the newest archived tabs")
        expect(large.pages.count == CommandBarTitleIndex.historyWindow, "only the most recent thousand past pages are searched")
        expect(large.pages.first?.url == "https://pages.example.com/0", "the history window starts at the newest visit")
        expect(large.visits(forKey: "page:pages.example.com/0") == 1, "visit counts come only from the newest visits scanned")
        let largeHits = large.search(planningQuery, now: now)
        expect(largeHits.archived.count == CommandBarTitleIndex.hitLimit && largeHits.pages.count == CommandBarTitleIndex.hitLimit,
               "each keystroke hands at most ten matches of each kind to the ranker")
        var flooded = Built()
        flooded.add(search("planning", 0), score: nil, keepsWeak: false)
        for rank in 1...7 { flooded.add(search("planning \(rank)", rank), score: nil, keepsWeak: false) }
        indexHits(large, planningQuery, into: &flooded)
        let floodedCandidates = flooded.resolved()
        let floodedOrder = CommandBarRanking.rank(floodedCandidates, query: "planning")
        expect(floodedOrder.filter { floodedCandidates[$0].archetype == .archived }.count == 3, "archived rows are capped at three")
        expect(floodedOrder.filter { floodedCandidates[$0].archetype == .history }.count == 3, "past pages are capped at three")
        expect(floodedOrder.prefix(5).filter { floodedCandidates[$0].archetype == .chromium }.count == 2,
               "suggestions still show among the first five rows")
        expect(floodedOrder.count <= CommandBarRanking.limit, "the list still stops at fifteen")

        expect(CommandBarTitleIndex.build(profileID: profile, historyRevision: 2, tabs: manyArchived, history: manyVisits.reversed(),
                                          reusing: large) === large, "unchanged archive and history reuse the built index")
        let deleted = CommandBarTitleIndex.build(profileID: profile, historyRevision: 2, historyRemovals: 1, tabs: manyArchived,
                                                 history: Array(manyVisits.reversed().dropLast(1)), reusing: large)
        expect(deleted !== large && deleted.pages.first?.url == "https://pages.example.com/1" && deleted.withdrawsEntries(of: large),
               "deleting history rebuilds the pages and withdraws the deleted ones")
        expect(!large.withdrawsEntries(of: large), "an unchanged index withdraws nothing")
        let newVisit = CommandBarTitleIndex.build(profileID: profile, historyRevision: 3, tabs: manyArchived,
                                                  history: manyVisits.reversed() + [visit("https://fresh.example.com/", "Fresh planning", -5)],
                                                  reusing: large)
        expect(newVisit !== large && newVisit.pages.first?.url == "https://fresh.example.com/", "a new visit rebuilds the history window")
        var restored = manyArchived
        restored[0].archivedAt = nil
        expect(CommandBarTitleIndex.build(profileID: profile, historyRevision: 3, tabs: restored, history: [], reusing: newVisit)
                .archived.first?.tabID == manyArchived[1].id, "a Put Back tab leaves the archive window")

        let cache = CommandBarTitleIndexCache()
        var delivered: [CommandBarTitleIndex] = []
        cache.onBuilt = { delivered.append($0) }
        let stamp = CommandBarTitleIndex.Stamp(profileID: profile, state: 1, history: 1, removals: 0)
        cache.request(stamp) { ([openTab, planning], history) }
        expect(cache.index(for: stamp) == nil && delivered.isEmpty, "the index builds off the main thread")
        let deadline = Date().addingTimeInterval(10)
        while delivered.isEmpty && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        expect(delivered.count == 1 && cache.index(for: stamp) === delivered[0], "the built index arrives on the main thread")
        expect(delivered[0].archived.map(\.tabID) == [planning.id], "the delivered index holds the archive")
        cache.request(stamp) { preconditionFailure("an already built stamp does not read the store again") }
        expect(delivered.count == 1, "an unchanged stamp is not rebuilt")

        withPutBackStore(now: now) { store, space, profileID, openID, single, members in
            expect(store.restoreArchivedTab(single, destination: .putBack(currentSpaceID: space, requestedSpaceID: nil)) == [single],
                   "Put Back restores an archived row's tab")
            expect(store.state.tab(single)?.archivedAt == nil && store.state.tab(single)?.spaceID == space,
                   "the tab returns to the window's current Space")
            expect(store.state.selectedTabIDs == [single], "the restored tab is selected")
            expect(store.restoreArchivedTab(members[1], destination: .putBack(currentSpaceID: space, requestedSpaceID: nil)) == members,
                   "Put Back from a split member restores the whole split")
            expect(store.state.splitLayouts.contains { $0.tabIDs == members && $0.spaceID == space }, "the split comes back together")

            let start = store.historyRemovalRevision
            store.updateTab(openID, title: "A", url: "https://a.example/")
            store.updateTab(openID, title: "B", url: "https://b.example/")
            expect(store.removedHistoryURLs(profileID: profileID, after: start) == [], "new visits remove nothing")
            let visitsToA = Set(store.state.history.filter { $0.url == "https://a.example/" }.map(\.id))
            store.deleteHistory(visitsToA, profileID: profileID)
            expect(store.removedHistoryURLs(profileID: profileID, after: start) == ["https://a.example/"],
                   "deleting a visit names the page it removed")
            expect(store.removedHistoryURLs(profileID: UUID(), after: start) == [], "another Profile's bar hides nothing")
            store.updateTab(openID, title: "A", url: "https://a.example/")
            store.updateTab(openID, title: "B again", url: "https://b.example/")
            let partial = store.historyRemovalRevision
            let oneVisitToB = Set(store.state.history.filter { $0.url == "https://b.example/" }.prefix(1).map(\.id))
            store.deleteHistory(oneVisitToB, profileID: profileID)
            expect(store.removedHistoryURLs(profileID: profileID, after: partial) == [],
                   "removing one of a page's visits keeps the page while others remain")
            let afterDelete = store.historyRemovalRevision
            store.clearHistory(profileID: profileID)
            expect(store.removedHistoryURLs(profileID: profileID, after: afterDelete) == nil, "clearing history hides every past page")
            expect(store.removedHistoryURLs(profileID: profileID, after: store.historyRemovalRevision) == [],
                   "an index built after the removal hides nothing")
        }
        print("TitleSearchTests: \(count) assertions passed")
    }

    @MainActor static func withPutBackStore(now: Date, _ body: (BrowserStore, UUID, UUID, UUID, UUID, [UUID]) -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-title-search-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                 attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
        let other = BrowserSpace(id: UUID(), name: "There", symbol: "circle", color: "123456", profileID: profile.id)
        let archivedAt = now.addingTimeInterval(-3 * 86_400)
        func tab(_ title: String) -> BrowserTab {
            let url = "https://\(title.lowercased()).example/"
            var tab = BrowserTab(id: UUID(), spaceID: other.id, profileID: profile.id, url: url, title: title, kind: .today,
                                 folderID: nil, createdAt: now.addingTimeInterval(-86_400 * 9), lastAccessed: archivedAt,
                                 archivedAt: archivedAt, savedURL: url, savedTitle: title)
            tab.archiveProvenance = ArchiveProvenance(reason: .automatic, spaceID: other.id, spaceName: other.name)
            return tab
        }
        let single = tab("Single")
        var left = tab("Left"), right = tab("Right")
        let layout = BrowserSplitLayout(spaceID: other.id, tabIDs: [left.id, right.id], widthFactors: [0.5, 0.5])
        let group = UUID()
        for index in [0, 1] {
            var member = index == 0 ? left : right
            member.archiveProvenance?.groupID = group
            member.archiveProvenance?.split = layout
            if index == 0 { left = member } else { right = member }
        }
        let open = BrowserTab(id: UUID(), spaceID: space.id, profileID: profile.id, url: "https://open.example/", title: "Open",
                              kind: .today, folderID: nil, createdAt: now, lastAccessed: now, savedURL: "https://open.example/",
                              savedTitle: "Open")
        var state = BrowserState(profiles: [profile], spaces: [space, other], activeSpaceID: space.id)
        state.tabs = [open, single, left, right]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try! encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        let store = try! BrowserStore(directory: directory, now: { now })
        body(store, space.id, profile.id, open.id, single.id, [left.id, right.id])
    }
}
