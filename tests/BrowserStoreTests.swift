import Combine
import Foundation

@main
@MainActor
struct BrowserStoreTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static var assertions = 0

    static func expect(_ condition: @autoclosure () throws -> Bool,
                       _ message: String,
                       file: StaticString = #filePath,
                       line: UInt = #line) throws {
        assertions += 1
        if try !condition() {
            throw Failure(description: "\(file):\(line): \(message)")
        }
    }

    @discardableResult
    static func savedSplit(_ store: BrowserStore, _ ids: [UUID], in location: SidebarContainerLocation) throws -> BrowserSplitLayout {
        store.selectTab(ids[0])
        for id in ids.dropFirst() { store.selectTab(id, extendingSplit: true) }
        guard let group = store.activeSplitLayout, group.tabIDs == ids else { throw Failure(description: "Split was not formed") }
        let snapshot = SidebarHierarchySnapshot(state: store.state, spaceID: store.activeSpaceID,
            profileID: store.activeSpace.profileID, includesFavorites: location.section == .favorite)!
        guard try store.moveSidebarItem(.split(group.id), to: location, before: nil, expected: snapshot),
              let moved = store.state.splitLayouts.first(where: { $0.id == group.id }) else { throw Failure(description: "Split did not move") }
        return moved
    }

    static func expectHome(of original: UUID, in store: BrowserStore, savedURL: String,
                           file: StaticString = #filePath, line: UInt = #line) throws -> BrowserTab {
        let homes = store.state.tabs.filter { $0.id != original && $0.savedURL == savedURL && $0.archivedAt == nil
            && ($0.kind == .pinned || $0.kind == .favorite) }
        try expect(homes.count == 1, "Exactly one fresh saved home holds the original slot", file: file, line: line)
        return homes[0]
    }

    static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-model-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    static func testPublicInternalAddresses() throws {
        let source = "chrome://settings/content/siteDetails?site=https%3A%2F%2Fexample.test%2Fa%3Fx%3D1#privacy"
        let visible = "parc://settings/content/siteDetails?site=https%3A%2F%2Fexample.test%2Fa%3Fx%3D1#privacy"
        try expect(BrowserInternalURL.publicString(source) == visible, "Public projection preserves escaped components")
        try expect(NavigationInput.resolve(source)?.absoluteString == visible, "Legacy Chromium input receives public metadata")
        try expect(NavigationInput.resolve(visible)?.absoluteString == visible, "Typed Parc WebUI routes to the native engine")
        try expect(!InternalPage.isInternal(visible), "Browser WebUI is not an Easel document")
        try expect(NavigationInput.resolve("arc://settings/") == nil, "arc:// is not an accepted scheme alias")
        try expect(NavigationInput.resolve("parc:") == nil, "A hostless public address does not become a search")
        try expect(NavigationInput.resolve("parc://unknown-controller/path")?.host == "unknown-controller", "Actual Chromium controller lookup decides unavailable hosts")
        try expect(BrowserInternalURL.publicString("chrome://easel/not-a-uuid") == "chrome://easel/not-a-uuid", "An unsupported Chromium host cannot acquire an app document identity")
        let network = "https://example.test/?next=chrome://settings/#chrome://flags"
        try expect(BrowserInternalURL.publicString(network) == network, "Embedded URLs and ordinary origins remain untouched")
        try expect(BrowserInternalURL.publicString("chrome-untrusted://example/") == "chrome-untrusted://example/", "Untrusted origins never become privileged public URLs")
        try expect(BrowserInternalURL.publicString(InternalPage.easel(UUID()).urlString).hasPrefix("parc://easel/"), "Typed app documents retain their identity")
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.openResolvedURL(URL(string: source)!, kind: .pinned)
            try expect(store.state.tabs.first { $0.id == id }?.url == visible, "Direct adopted metadata uses the public scheme")
            store.updateTab(id, url: "chrome://flags/#experiment")
            try expect(store.state.tabs.first { $0.id == id }?.url == "parc://flags/#experiment", "Native updates project only the display URL")
            try expect(store.state.tabs.first { $0.id == id }?.savedURL == visible, "Navigation keeps the distinct saved pin destination")
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var old = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var tabs = old["tabs"] as! [[String: Any]]
            let i = tabs.firstIndex { $0["id"] as? String == id.uuidString }!
            tabs[i]["url"] = "chrome://flags/#experiment"; tabs[i]["savedURL"] = source
            old["tabs"] = tabs
            try JSONSerialization.data(withJSONObject: old).write(to: file)
            let reopened = try BrowserStore(directory: directory)
            let restored = reopened.state.tabs.first { $0.id == id }!
            try expect(restored.url == "parc://flags/#experiment" && restored.savedURL == visible, "Legacy sessions migrate current and saved addresses independently")
            try expect(restored.profileID == store.state.tabs.first { $0.id == id }?.profileID && restored.id == id, "Scheme migration preserves original Profile and item identity")
            let again = try BrowserStore(directory: directory)
            try expect(again.state.tabs.first { $0.id == id } == restored, "Migration persists idempotently")
        }
    }

    static func testNavigationMetadataPublication() throws {
        try withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            var publications: [BrowserState] = []
            let subscription = store.statePublisher.dropFirst().sink { publications.append($0) }
            store.updateTab(id, title: "Destination", url: "https://example.test/destination")
            guard let first = publications.first, let tab = first.tabs.first(where: { $0.id == id }) else {
                throw Failure(description: "Metadata callback did not publish the tab")
            }
            try expect(tab.title == "Destination" && tab.savedTitle == tab.title &&
                tab.url == "https://example.test/destination" && tab.savedURL == tab.url,
                "First publication contains the complete Today tab metadata")
            try expect(first.history.last?.url == tab.url && first.history.last?.title == tab.title,
                "History and metadata publish together")
            try expect(publications.count == 1, "Metadata publishes once; identical changed() selection rewrite does not fan out again")
            store.updateTab(id, title: "Updated", url: tab.url)
            try expect(store.state.history.filter { $0.url == tab.url }.count == 1 && store.state.history.last?.title == "Updated",
                "Repeated recent URL updates the existing history title")
            let afterTitle = store.state
            try expect(afterTitle.preservesChromeLayout(relativeTo: first),
                "Title and history ticks keep sidebar membership and selection")
            try expect(afterTitle.preservesSidebarOutline(relativeTo: first),
                "Title ticks keep sidebar outline membership")
            let published = publications.count
            store.updateTab(id, title: "Updated")
            store.updateTab(id, title: "", url: tab.url)
            try expect(publications.count == published && store.state.tabs.first { $0.id == id }?.title == "Updated",
                "Unchanged title and empty title do not copy or publish BrowserState")
            let beforeCustom = store.state
            guard let expected = beforeCustom.tabs.first(where: { $0.id == id }) else {
                throw Failure(description: "Expected tab missing before customTitle")
            }
            _ = try store.saveSidebarTitle(expected, title: "Pinned name")
            try expect(store.state.preservesSidebarOutline(relativeTo: beforeCustom),
                "customTitle keeps outline membership for live cell patch")
            try expect(!store.state.preservesChromeLayout(relativeTo: beforeCustom),
                "customTitle is still a chrome-layout change for window-level live")
            let beforeDownload = store.state
            store.recordDownload(["id": "outline-skip-download", "name": "file.pdf", "isComplete": true])
            try expect(store.state.preservesSidebarOutline(relativeTo: beforeDownload),
                "Download ticks keep outline membership so sidebar skips row rebuild")
            try expect(!store.state.preservesChromeLayout(relativeTo: beforeDownload),
                "Download ticks remain chrome-layout changes for window-level live")
            let afterOutlineStable = store.state
            let extra = store.openResolvedURL(URL(string: "https://example.test/other")!, kind: .today)
            try expect(!store.state.preservesChromeLayout(relativeTo: afterOutlineStable) && extra != id,
                "A new tab is a chrome-layout change")
            try expect(!store.state.preservesSidebarOutline(relativeTo: afterOutlineStable),
                "A new tab is an outline membership change")
            let easelA = InternalPage.easel(UUID()).urlString
            let easelB = InternalPage.easel(UUID()).urlString
            store.updateTab(id, url: easelA)
            let afterEaselA = store.state
            store.updateTab(id, url: easelB)
            try expect(!store.state.preservesChromeLayout(relativeTo: afterEaselA),
                "A different Easel document is a chrome-layout change")
            try expect(!store.state.preservesSidebarOutline(relativeTo: afterEaselA),
                "A different Easel document is an outline membership change")
            let afterEaselB = store.state
            store.updateTab(id, title: "Canvas")
            try expect(store.state.preservesChromeLayout(relativeTo: afterEaselB),
                "Title on the same Easel keeps layout")
            try expect(store.state.preservesSidebarOutline(relativeTo: afterEaselB),
                "Title on the same Easel keeps outline membership")
            withExtendedLifetime(subscription) {}

            let pinned = store.openResolvedURL(URL(string: "https://example.test/home")!, kind: .pinned)
            store.updateTab(pinned, title: "Away", url: "https://example.test/away")
            let pin = store.state.tabs.first { $0.id == pinned }!
            try expect(pin.savedURL == "https://example.test/home" && pin.url == "https://example.test/away",
                "Metadata updates preserve a saved pin destination")

            let privateStore = BrowserStore(privateParentProfileID: store.activeSpace.profileID,
                engineProfilePath: "/disposable", directory: directory, settings: store.state.settings, now: { now })
            let privateID = privateStore.openResolvedURL(URL(string: "https://example.test/private")!, kind: .today)
            privateStore.updateTab(privateID, title: "Private", url: "https://example.test/private-next")
            try expect(privateStore.state.history.isEmpty && privateStore.state.tabs.first { $0.id == privateID }?.savedTitle == "Private",
                "Private metadata stays ephemeral and creates no history")
        }
    }

    static func commandBarEmptyQueryRecents(
        history: [BrowserHistoryEntry], tabURLs: [String], alreadyShown: Int = 0
    ) -> [BrowserHistoryEntry] {
        var results: [BrowserHistoryEntry] = []
        var seen = Set(tabURLs)
        let shown = alreadyShown
        for visit in BrowserHistoryOrder.newestFirst(history) {
            guard shown + results.count < 8 else { break }
            guard seen.insert(visit.url).inserted, let url = URL(string: visit.url),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { continue }
            results.append(visit)
        }
        return results
    }

    static func commandBarEmptyQueryRecentsSorted(
        history: [BrowserHistoryEntry], tabURLs: [String], alreadyShown: Int = 0
    ) -> [BrowserHistoryEntry] {
        var results: [BrowserHistoryEntry] = []
        var seen = Set(tabURLs)
        let shown = alreadyShown
        for visit in history.sorted(by: { $0.visitedAt > $1.visitedAt }) {
            guard shown + results.count < 8 else { break }
            guard seen.insert(visit.url).inserted, let url = URL(string: visit.url),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { continue }
            results.append(visit)
        }
        return results
    }

    static func testHistoryNewestFirstMatchesDateSort() throws {
        let profile = UUID()
        let other = UUID()
        var history: [BrowserHistoryEntry] = []
        for index in 0..<40 {
            let date = Date(timeIntervalSince1970: TimeInterval(index))
            history.append(BrowserHistoryEntry(
                id: UUID(), url: "https://other.test/\(index)", title: "Other \(index)",
                visitedAt: date, profileID: other))
            history.append(BrowserHistoryEntry(
                id: UUID(), url: index % 7 == 0 ? "parc://settings" : "https://example.test/\(index)",
                title: "Visit \(index)", visitedAt: date, profileID: profile))
        }
        history.append(BrowserHistoryEntry(
            id: UUID(), url: "HTTPS://Example.test/cased", title: "Cased",
            visitedAt: Date(timeIntervalSince1970: 40), profileID: profile))
        let profileHistory = history.filter { $0.profileID == profile }
        let sorted = profileHistory.sorted { $0.visitedAt > $1.visitedAt }
        let walked = BrowserHistoryOrder.newestFirst(profileHistory)
        try expect(walked.map(\.id) == sorted.map(\.id),
                   "Newest-first walk keeps sorted-by-date identity and order")
        try expect(walked.map(\.url) == sorted.map(\.url),
                   "Newest-first walk keeps sorted-by-date URLs")
        try expect(BrowserHistoryOrder.isStrictlyChronological(profileHistory),
                   "Unique timestamps stay strictly chronological")

        let tabURLs = ["https://example.test/39", "https://example.test/38"]
        let recents = commandBarEmptyQueryRecents(history: profileHistory, tabURLs: tabURLs, alreadyShown: 2)
        let sortedRecents = commandBarEmptyQueryRecentsSorted(history: profileHistory, tabURLs: tabURLs, alreadyShown: 2)
        try expect(recents.map(\.id) == sortedRecents.map(\.id),
                   "Empty-query recents match the previous sort, skip open tabs, and keep http(s) matching")
        try expect(recents.count == 6, "Remaining empty-query slots stay filled to 8")
        try expect(!recents.contains { $0.url == "parc://settings" }, "Non-web visits stay excluded")
        try expect(recents.contains { $0.url == "HTTPS://Example.test/cased" },
                   "Scheme matching still uses URL() lowercased host checks")

        let tie = Date(timeIntervalSince1970: 100)
        let tied = [
            BrowserHistoryEntry(id: UUID(), url: "https://tie.test/a", title: "A", visitedAt: tie, profileID: profile),
            BrowserHistoryEntry(id: UUID(), url: "https://tie.test/b", title: "B", visitedAt: tie, profileID: profile),
            BrowserHistoryEntry(id: UUID(), url: "https://tie.test/c", title: "C", visitedAt: tie.addingTimeInterval(1), profileID: profile)
        ]
        try expect(!BrowserHistoryOrder.isStrictlyChronological(tied),
                   "Same-second visits are not strictly chronological")
        try expect(BrowserHistoryOrder.newestFirst(tied).map(\.id) == tied.sorted { $0.visitedAt > $1.visitedAt }.map(\.id),
                   "Tied timestamps keep the previous date-desc sort identity and order")
        try expect(commandBarEmptyQueryRecents(history: tied, tabURLs: []).map(\.id)
                    == commandBarEmptyQueryRecentsSorted(history: tied, tabURLs: []).map(\.id),
                   "Empty-query recents keep sort identity when timestamps collide")
    }

    static func testHistoryFileSplit() throws {
        try withDirectory { directory in
            let session = directory.appendingPathComponent("session.json")
            let history = directory.appendingPathComponent("history.jsonl")
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            func records() throws -> Int { try Data(contentsOf: history).split(separator: UInt8(ascii: "\n")).count }
            func inode() throws -> Int {
                (try FileManager.default.attributesOfItem(atPath: history.path)[.systemFileNumber] as? NSNumber)?.intValue ?? -1
            }
            var legacy = BrowserState.initial()
            let profile = legacy.profiles[0].id
            let old = BrowserHistoryEntry(id: UUID(), url: "https://legacy.test/", title: "Legacy",
                                          visitedAt: Date(timeIntervalSince1970: 1_000), profileID: profile)
            legacy.history = [old]
            try encoder.encode(legacy).write(to: session)
            var clock = Date(timeIntervalSince1970: 2_000)
            let store = try BrowserStore(directory: directory, now: { clock })
            try expect(store.state.history == [old], "An inline legacy history loads")
            let tab = store.openResolvedURL(URL(string: "https://split.test/a")!, kind: .today)
            store.updateTab(tab, title: "A", url: "https://split.test/a")
            try store.save()
            let inline = try decoder.decode(BrowserState.self, from: Data(contentsOf: session))
            try expect(inline.history.isEmpty && BrowserHistoryFile.decode(try Data(contentsOf: history)) == store.state.history
                       && store.state.history.first == old, "The next save moves every visit into history.jsonl")

            let beforeVisit = try Data(contentsOf: history), beforeRecords = try records(), file = try inode()
            clock = Date(timeIntervalSince1970: 3_000)
            store.updateTab(tab, title: "B", url: "https://split.test/b")
            try store.save()
            let afterVisit = try Data(contentsOf: history)
            try expect(afterVisit.starts(with: beforeVisit) && (try records()) == beforeRecords + 1 && (try inode()) == file,
                       "A navigation appends one record to the same file and leaves the existing bytes")
            store.updateTab(tab, title: "B retitled", url: "https://split.test/b")
            try store.save()
            try expect((try Data(contentsOf: history)).starts(with: afterVisit) && (try records()) == beforeRecords + 2,
                       "Retitling the newest visit appends its new record")
            let retitled = store.state.history
            try expect(BrowserHistoryFile.decode(try Data(contentsOf: history)) == retitled,
                       "The later record for a visit replaces the earlier one in place")
            let settled = try Data(contentsOf: history)
            store.updateSettings { $0.sidebarWidth = 310 }
            try store.save()
            try expect(try Data(contentsOf: history) == settled && (try inode()) == file,
                       "A settings-only save leaves the history file untouched")
            let reopened = try BrowserStore(directory: directory)
            try expect(reopened.state.history == retitled, "Appended records round-trip")

            store.deleteHistory([old.id], profileID: profile)
            try store.save()
            try expect((try records()) == retitled.count - 1 && (try inode()) != file
                       && BrowserHistoryFile.decode(try Data(contentsOf: history)) == Array(retitled.dropFirst()),
                       "Deleting the oldest visit rewrites the file instead of letting it return")
            let kept = store.state.history

            var torn = try Data(contentsOf: history); torn.append(Data("{\"id\":".utf8))
            try torn.write(to: history)
            try expect(BrowserHistoryFile.decode(torn) == kept, "An append cut short is ignored")

            var downgraded = try decoder.decode(BrowserState.self, from: Data(contentsOf: session))
            let newer = BrowserHistoryEntry(id: UUID(), url: "https://older-build.test/", title: "Inline",
                                            visitedAt: Date(timeIntervalSince1970: 4_000), profileID: profile)
            downgraded.history = [newer]
            try encoder.encode(downgraded).write(to: session)
            let merged = try BrowserStore(directory: directory)
            try expect(merged.state.history == kept + [newer],
                       "Visits an older build kept inline merge after the history file's visits")

            try encoder.encode(downgraded).write(to: session)
            var damaged = Data("not json\n".utf8); damaged.append(try BrowserHistoryFile.encode([kept[0]]))
            try damaged.write(to: history)
            let recovered = try BrowserStore(directory: directory)
            try expect(recovered.state.history == [kept[0], newer], "Unreadable lines are skipped, readable visits kept")
            try recovered.save()
            try expect((try records()) == 2, "The next write rewrites the file without the unreadable line")

            recovered.clearHistory(profileID: profile)
            try recovered.save()
            try expect(recovered.state.history.isEmpty && (try Data(contentsOf: history)).isEmpty,
                       "Clearing history empties the history file")
        }
        try withDirectory { directory in
            let normal = try BrowserStore(directory: directory)
            let parent = normal.activeSpace.profileID
            let privateStore = BrowserStore(privateParentProfileID: parent, engineProfilePath: "/tmp/parc-private-test",
                                            directory: directory, settings: normal.state.settings)
            let tab = privateStore.openResolvedURL(URL(string: "https://private.test/")!, kind: .today)
            privateStore.updateTab(tab, title: "Private", url: "https://private.test/next")
            try privateStore.save()
            try expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(BrowserHistoryFile.name).path),
                       "A private store never writes a history file")
        }
        try withDirectory { directory in
            let history = directory.appendingPathComponent(BrowserHistoryFile.name)
            let unknown = Data("{\"format\":2}\n".utf8)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(BrowserState.initial()).write(to: directory.appendingPathComponent("session.json"))
            try unknown.write(to: history)
            let store = try BrowserStore(directory: directory)
            let tab = store.openResolvedURL(URL(string: "https://future.test/")!, kind: .today)
            store.updateTab(tab, title: "Next", url: "https://future.test/next")
            try store.save()
            try expect(!store.state.history.isEmpty && (try Data(contentsOf: history)) == unknown,
                       "A history file with no readable records is left untouched for the session")
        }
        let visit = { (title: String) in BrowserHistoryEntry(id: UUID(), url: "https://x.test/", title: title,
                                                             visitedAt: Date(timeIntervalSince1970: 0), profileID: UUID()) }
        let a = visit("a"), b = visit("b"), c = visit("c")
        try expect(BrowserHistoryFile.appended(from: [a, b], to: [a, b, c]) == [c], "New visits append")
        try expect(BrowserHistoryFile.appended(from: [a, b], to: [b, c]) == nil,
                   "Dropping the oldest below capacity is a deletion and rewrites")
        try expect(BrowserHistoryFile.appended(from: [a, b, c], to: [a, c]) == nil, "A middle deletion rewrites")
        try expect(BrowserHistoryFile.appended(from: [a, b, c], to: [a, b]) == nil, "Removing the newest rewrites")
        try expect(BrowserHistoryFile.appended(from: [a], to: []) == nil && BrowserHistoryFile.appended(from: [], to: [a]) == [a],
                   "Clearing rewrites; a first visit appends")
    }

    static func testHistoryNewestFirstMatchesISO8601RoundTrip() throws {
        try withDirectory { directory in
            let profile: UUID
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_000) })
            profile = store.activeSpace.profileID
            let first = store.openResolvedURL(URL(string: "https://roundtrip.test/a")!, kind: .today)
            store.updateTab(first, title: "A", url: "https://roundtrip.test/a")
            let second = store.openResolvedURL(URL(string: "https://roundtrip.test/b")!, kind: .today)
            store.updateTab(second, title: "B", url: "https://roundtrip.test/b")
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            let loaded = reopened.state.history.filter { $0.profileID == profile }
            try expect(BrowserHistoryOrder.newestFirst(loaded).map(\.id)
                        == loaded.sorted { $0.visitedAt > $1.visitedAt }.map(\.id),
                       "Reloaded same-second visits keep the previous date-desc sort")
            try expect(commandBarEmptyQueryRecents(history: loaded, tabURLs: []).map(\.url)
                        == commandBarEmptyQueryRecentsSorted(history: loaded, tabURLs: []).map(\.url),
                       "Empty-query recents keep sort identity after ISO-8601 reload")
        }
    }

    static func testHistoryRevisionTracksVisitRecords() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_000) })
            let start = store.historyRevision
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            try expect(store.historyRevision == start, "Opening a tab does not fabricate history")
            store.updateTab(id, title: "A", url: "https://example.test/a")
            try expect(store.historyRevision == start + 1 && store.state.history.last?.url == "https://example.test/a",
                       "A new visit advances historyRevision")
            store.updateTab(id, title: "A", url: "https://example.test/a")
            try expect(store.historyRevision == start + 1, "An unchanged coalesced title does not rewrite history")
            store.updateTab(id, title: "B", url: "https://example.test/a")
            try expect(store.historyRevision == start + 2 && store.state.history.last?.title == "B",
                       "A coalesced title update advances historyRevision")
            store.clearHistory()
            try expect(store.historyRevision == start + 3 && store.state.history.isEmpty,
                       "Clearing visits advances historyRevision")
        }
    }

    static func testNavigationInput() throws {
        try expect(NavigationInput.resolve("   ") == nil, "Blank input must not navigate")
        let direct = NavigationInput.resolve(" https://example.org/path?a=1#section ")
        try expect(direct?.absoluteString == "https://example.org/path?a=1#section",
                   "An explicit HTTPS address must preserve its path, query, and fragment")
        let domain = NavigationInput.resolve("example.org/reference")
        try expect(domain?.scheme == "https" && domain?.host == "example.org"
                   && domain?.path == "/reference", "A bare domain must navigate over HTTPS")

        let query = "stars & galaxies #1 + café / Δ"
        guard let url = NavigationInput.resolve(query),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw Failure(description: "Search text did not produce a URL")
        }
        try expect(components.host == "duckduckgo.com", "Search must use the configured search engine")
        try expect(components.fragment == nil, "A search hash must remain part of the query")
        try expect(components.queryItems?.filter { $0.name == "q" }.count == 1,
                   "Search punctuation must not inject another query parameter")
        try expect(components.queryItems?.first { $0.name == "q" }?.value == query,
                   "Search encoding must round-trip Unicode and reserved characters")
    }

    static func testCorruptFileIsPreserved() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            try store.save()
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            try expect(files.count == 1, "The model must have one identifiable JSON state file")
            guard let file = files.first else { return }
            let corrupt = Data("{\"intentionally incomplete session\":".utf8)
            try corrupt.write(to: file)
            var rejected = false
            do { _ = try BrowserStore(directory: directory) }
            catch { rejected = true }
            try expect(rejected, "A corrupt session must surface an error instead of silently resetting")
            let after = try Data(contentsOf: file)
            try expect(after == corrupt, "Opening a corrupt session must preserve its original bytes")
        }
    }

    static func tab(_ id: UUID, in store: BrowserStore) throws -> BrowserTab {
        guard let value = store.state.tabs.first(where: { $0.id == id }) else {
            throw Failure(description: "Expected tab \(id) to exist")
        }
        return value
    }

    static func expectValidSelection(_ store: BrowserStore) throws {
        let visible = Set(store.visibleTabs.map(\.id))
        try expect(store.state.selectedTabIDs.allSatisfy { visible.contains($0) },
                   "Selection must contain only visible, unarchived tabs in the active profile/Space")
        try expect(Set(store.state.selectedTabIDs).count == store.state.selectedTabIDs.count,
                   "Split selection must not contain duplicate tabs")
    }

    static func testSessionRoundTrip() throws {
        try withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let firstSpace = store.activeSpaceID
            let saved = store.open("https://example.org/start", kind: .pinned)
            let parent = store.createFolder(name: "Research")
            let child = store.createFolder(name: "Articles", parentID: parent)
            store.moveTab(saved, toSpace: firstSpace, folderID: child)
            store.toggleFolder(parent)
            store.updateTab(saved, title: "Current article", url: "https://example.org/article")
            let secondSpace = store.createSpace(name: "Work", color: "AACCEE")
            let profile = store.createProfile(name: "Work profile")
            store.assignProfile(profile, toSpace: secondSpace)
            let first = store.open("https://work.example.org/one")
            let second = store.open("https://work.example.org/two")
            store.setSplit([first, second])
            store.updateSettings { $0.sidebarWidth = 278 }
            store.setAutoArchiveInterval(.sevenDays, for: store.activeSpace.profileID)
            try store.save()
            let expected = store.state
            let reopened = try BrowserStore(directory: directory, now: { date })
            try expect(reopened.state == expected,
                       "A saved session must preserve profiles, Spaces, folders, tabs, ordering, settings, and split selection")
            try expect(try tab(saved, in: reopened).savedURL == "https://example.org/start",
                       "Navigating a pinned tab must preserve its saved destination across a restart")
            let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("session.json").path)
            try expect((permissions[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                       "Session data must be saved with owner-only permissions")
            try expectValidSelection(reopened)
        }
    }

    static func testSessionSaveRoundTripIdentity() throws {
        try withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let tabID = store.open("https://example.org/start", kind: .pinned)
            store.updateTab(tabID, title: "Article", url: "https://example.org/article")
            store.updateSettings { $0.sidebarWidth = 278 }
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            let savedBytes = try Data(contentsOf: file)
            let savedText = String(data: savedBytes, encoding: .utf8)
            try expect(savedText?.hasPrefix("{\n") == true && savedText?.contains("\n  \"") == true,
                       "Existing sessions stay pretty-printed; this is not a format change")
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)
            try expect((permissions[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                       "Off-main replace still uses owner-only permissions")

            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let fromDisk = try decoder.decode(BrowserState.self, from: savedBytes)
            var expected = store.state; expected.windows = store.windowRecords; expected.history = []
            try expect(fromDisk == expected, "Load of the saved file yields the exact persisted BrowserState")
            let savedHistory = BrowserHistoryFile.decode(
                try Data(contentsOf: directory.appendingPathComponent(BrowserHistoryFile.name)))
            try expect(!savedHistory.isEmpty && savedHistory == store.state.history,
                       "Visits persist in history.jsonl, not inline in session.json")

            let compactEncoder = JSONEncoder(); compactEncoder.dateEncodingStrategy = .iso8601
            try compactEncoder.encode(expected).write(to: file)
            let fromCompact = try BrowserStore(directory: directory, now: { date })
            try expect(fromCompact.state == store.state && fromCompact.windowRecords == store.windowRecords,
                       "JSONDecoder does not depend on pretty-printed or sorted keys")
            try fromCompact.save()
            let restored = try decoder.decode(BrowserState.self, from: Data(contentsOf: file))
            try expect(restored == expected,
                       "Re-saving an existing session preserves BrowserState identity")

            store.updateTab(tabID, title: "Live title")
            store.updateTab(tabID, title: "Final title")
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let delayed = try BrowserStore(directory: directory, now: { date })
            try expect(delayed.state.tabs.first { $0.id == tabID }?.title == "Final title",
                       "The 0.25s debounce still writes the last mutation")

            let beforePrivate = try Data(contentsOf: file)
            let privateStore = BrowserStore(privateParentProfileID: store.activeSpace.profileID,
                engineProfilePath: "/disposable", directory: directory, settings: store.state.settings, now: { date })
            let privateID = privateStore.open("https://private.example.test")
            privateStore.updateTab(privateID, title: "Secret")
            try privateStore.save()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            try expect(try Data(contentsOf: file) == beforePrivate,
                       "Ephemeral stores still skip disk")

            let pendingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("parc-session-pending-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: pendingDirectory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: pendingDirectory) }
            let pendingStore = try BrowserStore(directory: pendingDirectory)
            _ = pendingStore.open("https://pending-save.example.org")
            let pendingFile = pendingDirectory.appendingPathComponent("session.json")
            try FileManager.default.createDirectory(at: pendingFile, withIntermediateDirectories: false)
            var settingsFailed = false
            do { _ = try pendingStore.createProfilePersisted(name: "Work") } catch { settingsFailed = true }
            try expect(settingsFailed && pendingStore.persistenceError != nil,
                       "A refused settings commit reports the real failure")
            try expect(pendingStore.state.profiles.count == 1,
                       "A failed settings commit must not publish the profile")
            try FileManager.default.removeItem(at: pendingFile)
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let recovered = try BrowserStore(directory: pendingDirectory)
            try expect(recovered.state.tabs.contains { $0.url == "https://pending-save.example.org" },
                       "A failed settings commit must not drop an already-scheduled session persist")
        }
    }

    static func testProfileSettingsIdenticalBytePersistSkip() throws {
        try withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let file = directory.appendingPathComponent("session.json")
            FileOperations.install()
            let tab = store.open("https://example.org/observed")
            store.updateTab(tab, title: ObservedString.text("Observed session tab"))
            func session(_ body: () throws -> Void) throws -> (encodes: Int, replaces: Int, offMain: Bool, calls: [FileOperation]) {
                var calls: [FileOperation] = []
                let reads = try ObservedString.reads { calls = try FileOperations.during(directory, body) }
                let writes = calls.filter { $0.fileName.hasPrefix(".session-") }
                let occurrences = (try? String(contentsOf: file, encoding: .utf8))
                    .map { $0.components(separatedBy: "Observed session tab").count - 1 } ?? 0
                let encodes = ObservedString.backgroundEncodes(reads)
                return (occurrences > 0 && encodes % occurrences == 0 ? encodes / occurrences : -1,
                        Set(writes.map(\.path)).count, !writes.contains(where: \.onMainThread), calls)
            }

            let width = try session { try store.saveSidebarWidth(278) }
            try expect(width.encodes == 1 && width.replaces == 1,
                       "A settings commit encodes and atomically replaces once")
            try expect(width.offMain, "Settings commit encodes off the calling thread")
            let afterWidth = try Data(contentsOf: file)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var expected = store.state; expected.windows = store.windowRecords; expected.history = []
            try expect(afterWidth == (try encoder.encode(expected)),
                       "Settings commits keep pretty-printed sorted-keys identity")

            let identical = try session {
                try store.save()
                try store.save()
            }
            let identicalChecks = identical.calls.filter { $0.name == "fileExists" && $0.fileName == "session.json" }
            try expect(identical.encodes == 2 && identicalChecks.count == 2 && !identicalChecks.contains(where: \.onMainThread),
                       "Repeated identical saves may still encode off-thread")
            try expect(identical.replaces == 0,
                       "Repeated identical saves do not replace the durable session")
            try expect(try Data(contentsOf: file) == afterWidth,
                       "Skipped saves leave the exact on-disk bytes")

            let restore = try session { try store.saveRestoreSession(false) }
            try expect(restore.encodes == 1 && restore.replaces == 1 && restore.offMain,
                       "A real settings change encodes and atomically replaces")
            let afterRestore = try Data(contentsOf: file)
            expected = store.state; expected.windows = store.windowRecords; expected.history = []
            try expect(afterRestore != afterWidth
                           && afterRestore == (try encoder.encode(expected)),
                       "Distinct settings keep pretty/sorted identity with the live state")

            let unchanged = try session { try store.save() }
            try expect(unchanged.replaces == 0 && (try Data(contentsOf: file)) == afterRestore,
                       "Save after a settings commit with no further mutation skips replace")

            let selection = try session { try store.saveSettingsSelection(pane: "Profiles", profileID: store.state.profiles[0].id) }
            try expect(selection.replaces == 1,
                       "A later distinct settings commit still atomically replaces")
            expected = store.state; expected.windows = store.windowRecords; expected.history = []
            try expect(try Data(contentsOf: file) == (try encoder.encode(expected)),
                       "Distinct settings commit keeps pretty/sorted identity")

            let bytesBeforeDelete = try Data(contentsOf: file)
            try FileManager.default.removeItem(at: file)
            try expect(!FileManager.default.fileExists(atPath: file.path),
                       "Precondition: session file is absent")
            let recreate = try session { try store.save() }
            try expect(FileManager.default.fileExists(atPath: file.path) && recreate.replaces == 1,
                       "Identical bytes still recreate a missing session file")
            try expect(try Data(contentsOf: file) == bytesBeforeDelete,
                       "Recreated session keeps the prior pretty/sorted payload")
            let afterRecreate = try session { try store.save() }
            try expect(afterRecreate.replaces == 0 && (try Data(contentsOf: file)) == bytesBeforeDelete,
                       "After recreate, identical bytes skip replace while the file exists")
            let later = try session { try store.saveSidebarWidth(300) }
            expected = store.state; expected.windows = store.windowRecords; expected.history = []
            try expect(later.replaces == 1 && (try Data(contentsOf: file)) == (try encoder.encode(expected)),
                       "A later settings commit after recreate still atomically replaces")
        }
    }

    static func testSessionSavePendingScheduleCoalesce() throws {
        try withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let tabID = store.open("https://example.org/coalesce")
            store.updateTab(tabID, title: "Coalesce", url: "https://example.org/coalesce/page")
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            let bytesAfterSave = try Data(contentsOf: file)
            FileOperations.install()
            func replaces(_ calls: [FileOperation]) -> [FileOperation] {
                calls.filter { $0.name == "createFile" && $0.fileName.hasPrefix(".session-") }
            }
            func spin(until uptime: TimeInterval) {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: max(0, uptime - ProcessInfo.processInfo.systemUptime)))
            }

            let idle = FileOperations.during(directory) {
                store.selectTab(tabID)
                store.selectTab(tabID)
                store.selectTab(tabID)
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            }
            try expect(replaces(idle).isEmpty && (try Data(contentsOf: file)) == bytesAfterSave,
                       "Debounced identical snapshot does not rewrite durable session bytes")

            let armedAt = ProcessInfo.processInfo.systemUptime
            var lastUnchanged = armedAt
            let edit = FileOperations.during(directory) {
                store.updateSettings { $0.sidebarWidth = 301 }
                spin(until: armedAt + 0.12)
                store.updateSettings { $0.sidebarWidth = 301 }
                store.selectTab(tabID)
                spin(until: armedAt + 0.22)
                lastUnchanged = ProcessInfo.processInfo.systemUptime
                store.selectTab(tabID)
                store.updateSettings { $0.sidebarWidth = 301 }
                spin(until: armedAt + 0.8)
            }
            let writes = replaces(edit)
            try expect(writes.count == 1, "Distinct debounced revision still atomically replaces once")
            let delay = (writes.first?.time ?? 0) - armedAt
            try expect(delay >= 0.25 && (writes.first?.time ?? .infinity) < lastUnchanged + 0.25,
                       "Unchanged mutations while the debounce is pending do not reset it (\(delay) s)")
            let afterEdit = try Data(contentsOf: file)
            try expect(afterEdit != bytesAfterSave, "Distinct persist changes durable bytes")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var expected = store.state; expected.windows = store.windowRecords; expected.history = []
            try expect(afterEdit == (try encoder.encode(expected)),
                       "Distinct persist keeps pretty-printed sorted-keys identity")
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)
            try expect((permissions[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                       "Coalesced path leaves owner-only permissions unchanged")
        }
    }

    static func testSpacesAndProfiles() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let favorite = store.open("https://favorite.example.org", kind: .favorite)
            let pinned = store.open("https://pinned.example.org", kind: .pinned)
            let today = store.open("https://today.example.org")
            let secondSpace = store.createSpace(name: "Second")
            try expect(store.visibleTabs.map(\.id) == [favorite],
                       "Favorites are shared by Spaces using a profile; pinned and Today tabs are Space-local")
            let second = store.open("https://second.example.org")
            store.selectSpace(firstSpace)
            try expect(store.selectedTabID == today, "Returning to a Space must restore its own selection")
            store.selectSpace(secondSpace)
            try expect(store.selectedTabID == second, "Each Space must retain its own selection")

            let profile = store.createProfile(name: "Independent")
            store.assignProfile(profile, toSpace: secondSpace)
            try expect(!store.visibleTabs.contains { $0.id == favorite },
                       "A favorite must not leak into a different profile")
            let firstTab = try tab(pinned, in: store)
            let secondTab = try tab(second, in: store)
            try expect(secondTab.profileID == profile, "Assigning a Space profile must update its ordinary tabs")
            try expect(store.profilePath(for: firstTab) != store.profilePath(for: secondTab),
                       "Independent profiles must use separate engine storage directories")
            try expect(store.profilePath(for: secondTab).hasPrefix(directory.path + "/Profiles/"),
                       "Engine profile storage must remain beneath the isolated application directory")
            try expectValidSelection(store)

            store.selectSpace(firstSpace)
            store.selectTab(today)
            store.moveTab(today, toSpace: secondSpace)
            try expect(!store.state.selectedTabIDs.contains(today),
                       "Moving the selected tab out of a Space must remove it from that Space's selection")
            try expect(try tab(today, in: store).profileID == profile,
                       "A cross-Space move must adopt the destination profile")
            try expectValidSelection(store)
        }
    }

    static func testFreshSessionWhenRestoreDisabled() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let firstSpace = store.activeSpaceID
            let pinned = store.open("https://saved.example.org", kind: .pinned)
            let folder = store.createFolder(name: "Saved work")
            store.moveTab(pinned, toSpace: firstSpace, folderID: folder)
            store.updateTab(pinned, title: "Navigated pin", url: "https://saved.example.org/other")
            let favorite = store.open("https://favorite.example.org", kind: .favorite)
            store.updateTab(favorite, title: "Navigated favorite", url: "https://favorite.example.org/other")
            let firstToday = store.open("https://first.example.org")
            let alreadyArchived = store.open("https://archived.example.org")
            store.closeTab(alreadyArchived)
            let oldArchive = try tab(alreadyArchived, in: store)
            let otherSpace = store.createSpace(name: "Work")
            let otherProfile = store.createProfile(name: "Work")
            store.assignProfile(otherProfile, toSpace: otherSpace)
            let otherToday = store.open("https://work.example.org")
            let otherPin = store.open("https://work-saved.example.org", kind: .pinned)
            store.updateTab(otherPin, title: "Work article", url: "https://work-saved.example.org/article")
            store.setSplit([otherToday, otherPin])
            let otherHome = store.state.tabs.first { $0.kind == .pinned && $0.spaceID == otherSpace && $0.id != otherPin }!.id
            try expect(try tab(otherPin, in: store).kind == .today, "The pinned original joins the new Today split")
            store.recordDownload(["id": "existing-download", "name": "notes.pdf", "isComplete": true])
            store.updateSettings { $0.restoreSession = false; $0.onboardingComplete = true }
            try store.save()
            let saved = store.state

            now.addTimeInterval(3600)
            let reopened = try BrowserStore(directory: directory, now: { now })
            try expect(reopened.state.selectedTabIDs.isEmpty && reopened.state.selectionBySpace.isEmpty,
                       "Disabling session restore must start with no selected page or remembered split in any Space")
            try expect(reopened.state.splitLayouts.isEmpty,
                       "A fresh session must discard its prior split layout")
            try expect(reopened.state.tabs.filter { $0.kind == .today && $0.archivedAt == nil }.isEmpty,
                       "A fresh launch must archive Today tabs across all Spaces and profiles")
            for id in [firstToday, otherToday, otherPin] {
                try expect(try tab(id, in: reopened).archivedAt == now,
                           "Live Today tabs must be recoverably archived at the fresh launch time")
            }
            try expect(try tab(alreadyArchived, in: reopened) == oldArchive,
                       "Previously archived tabs must retain their original contents and archive date")
            for id in [pinned, favorite, otherHome] {
                let value = try tab(id, in: reopened)
                try expect(value.archivedAt == nil && value.url == value.savedURL && value.title == value.savedTitle,
                           "Saved destinations must remain available and reset to their saved page and title")
            }
            try expect(reopened.state.profiles == saved.profiles && reopened.state.spaces == saved.spaces
                       && reopened.state.folders == saved.folders && reopened.activeSpaceID == otherSpace,
                       "A fresh launch must preserve the user's profiles, Spaces, folders, and active Space")
            try expect(reopened.state.history == saved.history && reopened.state.downloads == saved.downloads
                       && reopened.state.settings == saved.settings,
                       "Starting fresh must not clear history, download records, or preferences")
            try expect(Set(reopened.state.recentlyClosedIDs).count == reopened.state.recentlyClosedIDs.count,
                       "Fresh-launch archiving must not duplicate recovery entries")

            let fresh = reopened.state
            let file = directory.appendingPathComponent("session.json")
            let data = try Data(contentsOf: file)
            let oldModificationDate = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: oldModificationDate], ofItemAtPath: file.path)
            now.addTimeInterval(3600)
            let openedAgain = try BrowserStore(directory: directory, now: { now })
            try expect(openedAgain.state == fresh, "A second fresh launch must be idempotent")
            try expect(try Data(contentsOf: file) == data,
                       "Fresh-launch normalization must be persisted before another store reads it")
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            try expect(attributes[.modificationDate] as? Date == oldModificationDate,
                       "An already normalized fresh session must not rewrite its state file")
            openedAgain.restoreArchivedTab(otherToday, destination: .previousSpace(fallbackSpaceID: openedAgain.activeSpaceID))
            try expect(openedAgain.selectedTabID == otherToday && (try tab(otherToday, in: openedAgain)).archivedAt == nil,
                       "Archive restoration recovers a tab archived by the fresh-launch preference")
            try expectValidSelection(openedAgain)
        }
    }

    static func testChangingRestorePreferenceDoesNotCloseCurrentTabs() throws {
        try withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let tabID = store.open("https://current.example.org")
            store.updateSettings { $0.restoreSession = false }
            try expect(store.selectedTabID == tabID && (try tab(tabID, in: store)).archivedAt == nil,
                       "Changing the startup preference must not close tabs during the current session")
            store.updateSettings { $0.restoreSession = true }
            try store.save()
            let expected = store.state
            let reopened = try BrowserStore(directory: directory)
            try expect(reopened.state == expected,
                       "Re-enabling session restore before quitting must retain the current tabs on launch")
        }
    }

    static func testArchivePolicyAndRestore() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.setAutoArchiveInterval(.oneHour, for: store.activeSpace.profileID)
            store.archiveExpiredTabs()
            let expired = store.open("https://expired.example.org")
            let pinned = store.open("https://pinned.example.org", kind: .pinned)
            let favorite = store.open("https://favorite.example.org", kind: .favorite)
            let selected = store.open("https://selected.example.org")
            now.addTimeInterval(2 * 3600)
            store.archiveExpiredTabs()
            try expect(try tab(expired, in: store).archivedAt == now, "Inactive Today tabs must expire at the configured threshold")
            try expect(try tab(pinned, in: store).archivedAt == nil, "Pinned destinations must never auto-archive")
            try expect(try tab(favorite, in: store).archivedAt == nil, "Favorites must never auto-archive")
            try expect(try tab(selected, in: store).archivedAt == nil, "A visible selected tab must not auto-archive")

            store.closeTab(selected)
            try expect(try tab(selected, in: store).archivedAt != nil, "Closing Today must archive it")
            store.restoreArchivedTab(selected, destination: .previousSpace(fallbackSpaceID: store.activeSpaceID))
            try expect(store.selectedTabID == selected && (try tab(selected, in: store)).archivedAt == nil,
                       "Reopen closed tab must restore the same identity and select it")
            store.setAutoArchiveInterval(.never, for: store.activeSpace.profileID)
            let keep = store.open("https://never.example.org")
            _ = store.open("https://active.example.org")
            now.addTimeInterval(40 * 24 * 3600)
            store.archiveExpiredTabs()
            try expect(try tab(keep, in: store).archivedAt == nil, "Never must disable automatic archiving")
            try expectValidSelection(store)
        }
    }

    static func testSavedDestinationsAndSplitLifecycle() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let pinned = store.open("https://example.org/home", kind: .pinned)
            let today = store.open("https://example.org/today")
            store.updateTab(pinned, title: "A different page", url: "https://example.org/other")
            store.setSplit([pinned, today, today, UUID()])
            try expect(store.state.selectedTabIDs == [pinned, today], "Splits must reject unknown or duplicate members")
            let home = try expectHome(of: pinned, in: store, savedURL: "https://example.org/home")
            try expect(home.url == home.savedURL && home.title == home.savedTitle,
                       "The pinned slot keeps a fresh home at its saved page and title")
            try expect(try tab(pinned, in: store).kind == .today && tab(pinned, in: store).url == "https://example.org/other",
                       "The original live page joins the Today split unchanged")
            store.closeTab(today)
            try expect(store.state.selectedTabIDs == [pinned], "Closing a split member must retain the surviving pane")
            store.closeTab(pinned)
            let kept = try tab(home.id, in: store)
            try expect(try tab(pinned, in: store).archivedAt != nil && kept.archivedAt == nil && kept.kind == .pinned
                       && kept.savedURL == home.savedURL && kept.folderID == home.folderID,
                       "Closing the joined original archives it while its saved home stays pinned")
            store.restoreArchivedTab(today, destination: .previousSpace(fallbackSpaceID: store.activeSpaceID))
            store.restoreArchivedTab(pinned, destination: .previousSpace(fallbackSpaceID: store.activeSpaceID))
            store.setSplit([pinned, today])
            store.closeSplit()
            try expect(store.state.selectedTabIDs == [pinned], "Close Split must retain its primary tab")
            try expect(try tab(today, in: store).archivedAt == nil, "Closing a split layout must not archive its other tab")
            store.setSplit([pinned, today])
            store.separateSplitPane(today)
            try expect(store.state.selectedTabIDs == [today] && (try tab(pinned, in: store)).archivedAt == nil,
                       "Separating the focused pane keeps that original selected and preserves its sibling")
            try expectValidSelection(store)
        }
    }

    static func testClosingLastSavedTabDoesNotReselectIt() throws {
        for kind in [TabKind.pinned, .favorite] {
            try withDirectory { directory in
                let store = try BrowserStore(directory: directory)
                let saved = store.open("https://saved.example.org", kind: kind)
                store.updateTab(saved, title: "Current article", url: "https://saved.example.org/article")
                store.closeTab(saved)
                try expect(store.state.selectedTabIDs.isEmpty,
                           "Closing the only \(kind.rawValue) must leave the start view instead of selecting it again")
                try expect(store.visibleTabs.map(\.id) == [saved],
                           "Closing a saved tab must keep its destination in the sidebar")
                let destination = try tab(saved, in: store)
                try expect(destination.archivedAt == nil && destination.url == destination.savedURL
                           && destination.title == destination.savedTitle,
                           "Closing the last saved tab must reset its page without archiving or deleting it")
                store.selectTab(saved)
                try expect(store.selectedTabID == saved, "The saved destination must remain explicitly selectable after closing")
                let other = store.open("https://other.example.org")
                store.selectTab(saved)
                store.closeTab(saved)
                try expect(store.selectedTabID == other,
                           "Closing a selected saved tab must still select an available neighboring tab")
            }
        }
    }

    static func testFoldersAndOrdering() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let first = store.open("https://one.example.org")
            let second = store.open("https://two.example.org")
            store.moveTab(first, toSpace: firstSpace, folderID: child)
            store.moveTab(second, toSpace: firstSpace, folderID: child)
            try expect(try tab(first, in: store).kind == .pinned, "Placing a tab in a folder must pin it")
            store.reorderTab(second, before: first)
            try expect(store.pinnedTabs.map(\.id) == [second, first], "Reordering folder siblings must preserve the requested order")
            let deletion = FolderRemovalTarget(folderID: child, spaceID: firstSpace, profileID: store.activeSpace.profileID, state: store.state)!
            var deleted = false
            store.deleteFolder(deletion, shouldCommit: { true }) { deleted = (try? $0.get()) == true }
            try expect(deleted && (try tab(first, in: store)).archivedAt != nil && !store.state.folders.contains { $0.id == child },
                       "Deleting a nested folder archives its tabs instead of reparenting live pages")
            _ = store.restoreArchivedTab(first, profileID: store.activeSpace.profileID, destination: .previousSpace(fallbackSpaceID: firstSpace))
            try expect(try tab(first, in: store).folderID == nil, "Put Back does not invent a deleted folder")
            let kept = store.open("https://kept.example.org")
            store.moveTab(kept, toSpace: firstSpace, folderID: parent)
            let archiveKept = FolderRemovalTarget(items: [.tab(kept)], spaceID: firstSpace, profileID: store.activeSpace.profileID, state: store.state)!
            store.deleteFolder(archiveKept, shouldCommit: { true }) { _ in }
            try expect(try tab(kept, in: store).archivedAt != nil && store.state.folders.contains { $0.id == parent },
                       "Archiving a tab leaves its folder in place")
            _ = store.restoreArchivedTab(kept, profileID: store.activeSpace.profileID, destination: .previousSpace(fallbackSpaceID: firstSpace))
            try expect(try tab(kept, in: store).archivedAt == nil && tab(kept, in: store).folderID == parent,
                       "Put Back returns a tab archived from a folder to that folder")
            let otherSpace = store.createSpace(name: "Other")
            let foreignFolder = store.createFolder(name: "Other folder")
            let before = try tab(first, in: store)
            store.moveTab(first, toSpace: firstSpace, folderID: foreignFolder)
            try expect(try tab(first, in: store) == before, "A tab must reject a folder belonging to another Space")
            let foreignParent = store.createFolder(name: "Invalid parent", parentID: parent)
            try expect(store.folders.first { $0.id == foreignParent }?.parentID == nil,
                       "Folder creation must not retain a parent from a different Space")
            store.moveTab(first, toSpace: otherSpace, folderID: foreignFolder)
            try expect(try tab(first, in: store).folderID == foreignFolder, "A valid cross-Space folder move must succeed")
            store.setKind(first, .today)
            try expect(try tab(first, in: store).folderID == nil, "Unpinning must detach the tab from its folder")
            try expectValidSelection(store)
        }
    }

    static func testSidebarHierarchyMoves() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let first = store.open("https://one.example.org", kind: .pinned)
            let second = store.open("https://two.example.org", kind: .pinned)
            let parent = store.createFolder(name: "Parent")
            let nested = store.createFolder(name: "Nested", parentID: parent)
            let peer = store.createFolder(name: "Peer")
            let today = store.open("https://today.example.org")
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            @MainActor func batchedMatches() -> Bool {
                let state = store.state, batched = SidebarHierarchy.childrenByContainer(spaceID: space, state: state)
                let locations = [root, SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)]
                    + state.folders.filter { $0.spaceID == space }.map { SidebarContainerLocation(spaceID: space, folderID: $0.id, section: .pinned) }
                return locations.allSatisfy { (batched[$0.key] ?? []) == SidebarHierarchy.children(in: $0, state: state) }
            }
            try expect(SidebarHierarchy.children(in: root, state: store.state) == [.tab(first), .tab(second), .folder(parent), .folder(peer)], "Legacy sessions preserve their prior tab-then-folder order")
            try expect(batchedMatches(), "Every container's children match in one pass, legacy order")
            let original = store.state
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            try expect(try store.moveSidebarItem(.folder(peer), to: root, before: .tab(second), expected: snapshot()), "Folders reorder among tabs in a typed shared container")
            try expect(SidebarHierarchy.children(in: root, state: store.state) == [.tab(first), .folder(peer), .tab(second), .folder(parent)], "Mixed sibling insertion is exact")
            try expect(batchedMatches(), "Every container's children match in one pass, stored mixed order")
            try expect(publications == 1, "The complete move publishes once")
            try expect(store.state.tabs == original.tabs && store.state.selectedTabIDs == original.selectedTabIDs && store.state.history == original.history, "Reordering preserves original pages, selection and history metadata")
            let stale = snapshot()
            let inside = SidebarContainerLocation(spaceID: space, folderID: parent, section: .pinned)
            store.toggleFolder(parent)
            try expect(!(try store.moveSidebarItem(.tab(first), to: inside, before: nil, expected: stale)), "Changed hierarchy/disclosure rejects a stale capability")
            try expect(try store.moveSidebarItem(.tab(first), to: inside, before: .folder(nested), expected: snapshot()), "A tab nests before a folder without replacing either")
            try expect(store.state.folders.first { $0.id == parent }?.isExpanded == true, "A committed drop reveals its destination")
            try expect(SidebarHierarchy.children(in: inside, state: store.state) == [.tab(first), .folder(nested)], "Nested mixed order is durable")
            let beforeCycle = store.state
            try expect(!(try store.moveSidebarItem(.folder(parent), to: .init(spaceID: space, folderID: nested, section: .pinned), before: nil, expected: snapshot())), "A parent cannot move into its descendant")
            try expect(!(try store.moveSidebarItem(.folder(parent), to: inside, before: nil, expected: snapshot())), "A folder cannot become its own parent")
            try expect(store.state == beforeCycle, "Cycle refusal is nonmutating")
            try expect(!(try store.moveSidebarItem(.folder(peer), to: root, before: .folder(peer), expected: snapshot())), "Self-relative insertion is rejected")
            try expect(!(try store.moveSidebarItem(.folder(peer), to: root, before: .tab(UUID()), expected: snapshot())), "A missing destination never becomes append")
            try expect(!(try store.moveSidebarItem(.folder(peer), to: .init(spaceID: space, folderID: nil, section: .today), before: nil, expected: snapshot())), "Folders remain in the pinned hierarchy")
            try expect(!(try store.moveSidebarItem(.tab(second), to: .init(spaceID: UUID(), folderID: nil, section: .pinned), before: nil, expected: snapshot())), "Another Space cannot acquire the source")
            try expect(!(try store.moveSidebarItem(.tab(second), to: .init(spaceID: space, folderID: UUID(), section: .pinned), before: nil, expected: snapshot())), "An expired folder cannot become the root")
            try expect(try store.moveSidebarItem(.tab(today), to: inside, before: .tab(first), expected: snapshot()), "Today can move into a genuine pinned folder")
            try expect(try tab(today, in: store).kind == .pinned && tab(today, in: store).savedURL == "https://today.example.org", "Pinning retains the original live destination")
            try expect(try store.moveSidebarItem(.folder(nested), to: root, before: .folder(peer), expected: snapshot()), "A nested folder can move out to the root")
            try expect(store.state.folders.first { $0.id == nested }?.parentID == nil, "Outdent preserves folder identity")
            store.selectTab(first); store.selectTab(second, extendingSplit: true)
            let group = store.activeSplitLayout!
            let originalGroup = group
            let firstHome = try expectHome(of: first, in: store, savedURL: "https://one.example.org")
            try expect(SidebarHierarchy.children(in: inside, state: store.state) == [.tab(today), .tab(firstHome.id)],
                       "The new Today split leaves the pinned child's fresh home in its folder slot")
            try expect(!(try store.moveSidebarItem(.tab(first), to: root, before: nil, expected: snapshot())), "A split child cannot silently detach through folder drag")
            try expect(try store.moveSidebarItem(.split(group.id), to: inside, before: .tab(today), expected: snapshot()), "The whole split is one movable sidebar item")
            try expect(store.activeSplitLayout == originalGroup && store.state.selectedTabIDs == originalGroup.tabIDs, "Moving preserves container identity, geometry and selected original pages")
            try expect(try tab(first, in: store).folderID == parent && tab(second, in: store).folderID == parent, "All original split children move together")
            try expect(SidebarHierarchy.children(in: inside, state: store.state) == [.split(group.id), .tab(today), .tab(firstHome.id)], "Only the split container appears in the destination order")
            let groupState = store.state
            try expect(try store.moveSidebarItem(.folder(parent), to: .init(spaceID: space, folderID: peer, section: .pinned), before: nil, expected: snapshot()), "A folder subtree containing a split can nest")
            try expect(store.state.tabs == groupState.tabs && store.state.splitLayouts == groupState.splitLayouts, "Subtree nesting preserves every original child record")
            try expect(batchedMatches(), "Every container's children match in one pass, with stored order, nesting and a split")
            let loaded = try BrowserStore(directory: directory)
            try expect(loaded.state.sidebarItemOrder == store.state.sidebarItemOrder && loaded.state.folders == store.state.folders, "Hierarchy ordering and nesting survive reopening the model")
            let stable = store.state, snap = snapshot()
            let session = directory.appendingPathComponent("session.json"), backup = directory.appendingPathComponent("saved.json")
            try FileManager.default.moveItem(at: session, to: backup)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
            var failed = false
            do { _ = try store.moveSidebarItem(.folder(peer), to: root, before: .folder(nested), expected: snap) } catch { failed = true }
            try expect(failed && store.state == stable, "A failed disk commit cannot publish the move")
            try FileManager.default.removeItem(at: session); try FileManager.default.moveItem(at: backup, to: session)
            observation.cancel()
            var corrupted = store.state
            let index = corrupted.folders.firstIndex { $0.id == parent }!
            corrupted.folders[index].parentID = parent
            try expect(SidebarHierarchySnapshot(state: corrupted, spaceID: space, profileID: profile) == nil, "A malformed hierarchy cannot mint a capability")
            try expect(SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: UUID()) == nil, "Wrong-profile snapshots fail before preparing a move")

            let unsaved = store.open("https://split-today.example.org")
            store.selectTab(first); store.selectTab(unsaved, extendingSplit: true)
            let mixedGroup = store.activeSplitLayout!
            let originalIDs = Set(store.state.tabs.map(\.id))
            try expect(try store.moveSidebarItem(.split(mixedGroup.id),
                to: .init(spaceID: space, folderID: nil, section: .today), before: nil,
                expected: snapshot()), "A whole ordinary split moves even when its children retain different saved sections")
            try expect(store.activeSplitLayout == mixedGroup && Set(store.state.tabs.map(\.id)) == originalIDs,
                       "Mixed-section move preserves the original group and every tab identity")
            try expect(store.state.tabs.filter { mixedGroup.tabIDs.contains($0.id) }.allSatisfy {
                $0.kind == .today && $0.folderID == nil
            }, "The explicit destination applies to every original member in one transaction")
        }
    }

    static func testFolderDisclosureOwnership() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let parent = store.createFolder(name: "Parent")
            let child = store.createFolder(name: "Child", parentID: parent)
            let saved = store.open("https://folder.example.org/selected")
            store.moveTab(saved, toSpace: space, folderID: child)
            store.toggleFolder(parent)
            let origin = store.state.folders.filter { $0.spaceID == space }
            let other = store.createSpace(name: "Other window")
            _ = store.createFolder(name: "Leave expanded")
            _ = store.open("https://other.example.org/current")
            let before = store.state
            var publications: [BrowserState] = []
            let observation = store.statePublisher.dropFirst().sink { publications.append($0) }
            try expect(try store.setFoldersExpanded(false, in: space, profileID: profile,
                                                    expectedFolders: origin), "Original Space remains an eligible disclosure owner")
            var expected = before
            for index in expected.folders.indices where expected.folders[index].spaceID == space {
                expected.folders[index].isExpanded = false
            }
            try expect(store.state == expected, "Collapse includes hidden descendants and changes no browsing state or foreign folder")
            try expect(publications == [expected], "Bulk collapse publishes only the complete folder change")
            try expect(store.activeSpaceID == other, "A folder command cannot steal another window's shared store context")
            let collapsed = store.state.folders.filter { $0.spaceID == space }
            try expect(try store.setFoldersExpanded(false, in: space, profileID: profile,
                                                    expectedFolders: collapsed), "Repeated matching disclosure is an idempotent success")
            try expect(publications.count == 1, "No-op disclosure does not publish again")
            try expect(!(try store.setFoldersExpanded(true, in: space, profileID: profile,
                                                       expectedFolders: origin)), "A stale folder snapshot cannot overwrite later disclosure")
            try expect(!(try store.setFoldersExpanded(true, in: space, profileID: UUID(),
                                                       expectedFolders: collapsed)), "Changed Profile ownership rejects before mutation")
            try expect(store.state == expected, "Rejected commands preserve the exact session")
            try expect(try store.setFoldersExpanded(true, in: space, profileID: profile,
                                                    expectedFolders: collapsed), "Expand restores all nested folder disclosure")
            for index in expected.folders.indices where expected.folders[index].spaceID == space {
                expected.folders[index].isExpanded = true
            }
            try expect(store.state == expected, "Expand leaves original tabs, selection, profiles and URL metadata unchanged")
            observation.cancel()
            let reopened = try BrowserStore(directory: directory)
            try expect(reopened.state.folders == expected.folders, "Bulk disclosure is durably saved before success")

            let session = directory.appendingPathComponent("session.json")
            let backup = directory.appendingPathComponent("saved-session.json")
            try FileManager.default.moveItem(at: session, to: backup)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
            var writeFailed = false
            do {
                _ = try store.setFoldersExpanded(false, in: space, profileID: profile,
                    expectedFolders: expected.folders.filter { $0.spaceID == space })
            } catch { writeFailed = true }
            try expect(writeFailed && store.persistenceError != nil, "A refused atomic save reports the real failure")
            try expect(store.state == expected, "Failed persistence never publishes a folder change")
            try FileManager.default.removeItem(at: session)
            try FileManager.default.moveItem(at: backup, to: session)
        }
    }

    static func testFavoriteSelectionAfterProfileReassignment() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalSpace = store.activeSpaceID
            let favorite = store.open("https://favorite.example.org", kind: .favorite)
            let sameProfileSpace = store.createSpace(name: "Same profile")
            let otherProfile = store.createProfile(name: "Other profile")
            store.assignProfile(otherProfile, toSpace: originalSpace)
            store.selectSpace(originalSpace)
            store.selectTab(favorite)
            try expect(store.activeSpaceID == sameProfileSpace,
                       "Selecting a favorite after its origin Space changes profile must choose a Space using the favorite's profile")
            try expectValidSelection(store)
        }
    }

    static func testInvalidRelationshipsAreRejected() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            _ = store.open("https://example.org")
            let folder = store.createFolder(name: "Folder")
            let otherProfile = store.createProfile(name: "Other")
            var valid = store.state
            valid.settings.restoreSession = false
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let file = directory.appendingPathComponent("session.json")
            @MainActor func reject(_ state: BrowserState, _ message: String) throws {
                let data = try encoder.encode(state)
                try data.write(to: file)
                var rejected = false
                do { _ = try BrowserStore(directory: directory) }
                catch { rejected = true }
                try expect(rejected, message)
                try expect(try Data(contentsOf: file) == data, "Invalid relational state must not be overwritten")
            }
            var cycle = valid
            cycle.folders[0].parentID = folder
            try reject(cycle, "A persisted folder cycle must be rejected")
            var orphan = valid
            orphan.tabs[0].folderID = UUID()
            try reject(orphan, "A persisted missing folder reference must be rejected")
            var profileMismatch = valid
            profileMismatch.tabs[0].profileID = otherProfile
            try reject(profileMismatch, "A non-favorite tab must use the profile assigned to its Space")
        }
    }

    static func testBookmarkImportDoesNotNavigate() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let existing = store.open("https://saved.example.org/start", kind: .pinned)
            store.updateTab(existing, title: "Current page", url: "https://saved.example.org/other")
            let current = store.open("https://current.example.org")
            store.updateTab(current, title: "Current", url: "https://current.example.org/article")
            store.setSplit([existing, current])
            let originalTabs = store.state.tabs
            let originalSelection = store.state.selectedTabIDs
            let originalHistory = store.state.history
            let items: [(title: String, url: String)] = [
                ("Already saved", "https://saved.example.org/start"),
                ("Research & notes", "https://new.example.org/research?q=stars#notes"),
                ("Duplicate in the same import", "https://new.example.org/research?q=stars#notes"),
                ("", "http://plain.example.org/reference"),
                ("Script", "javascript:alert(1)"),
                ("Data", "data:text/html,hello"),
                ("Local file", "file:///tmp/private.html"),
                ("Mail", "mailto:someone@example.org"),
                ("Internal", "about:blank"),
                ("Relative", "/not-an-absolute-web-address")
            ]
            store.importBookmarks(items)
            let imported = store.state.tabs.filter { candidate in !originalTabs.contains { $0.id == candidate.id } }
            try expect(imported.count == 2, "Import must deduplicate saved destinations and batch duplicates, admitting only HTTP(S) bookmarks")
            try expect(imported.allSatisfy { $0.kind == .pinned && $0.archivedAt == nil && $0.folderID == nil },
                       "Imported bookmarks must become live saved destinations in the pinned section")
            try expect(imported.allSatisfy { $0.spaceID == store.activeSpaceID && $0.profileID == store.activeSpace.profileID },
                       "Imported bookmarks must belong to the active Space and its profile")
            try expect(imported.first?.savedTitle == "Research & notes"
                       && imported.first?.savedURL == "https://new.example.org/research?q=stars#notes",
                       "Import must preserve supplied bookmark titles, query strings, and fragments")
            try expect(imported.last?.savedTitle == "plain.example.org", "An empty bookmark title must fall back to its host")
            try expect(store.state.selectedTabIDs == originalSelection, "Import must preserve the current tab and split selection")
            try expect(store.state.history == originalHistory, "Importing bookmarks must not create navigation history")
            try expect(Array(store.state.tabs.prefix(originalTabs.count)) == originalTabs,
                       "Import must not navigate, retitle, or otherwise mutate existing tabs")
            let firstImport = store.state.tabs
            store.importBookmarks(items)
            try expect(store.state.tabs == firstImport, "Importing the same bookmark file again must be idempotent")
            try expect(store.state.history == originalHistory && store.state.selectedTabIDs == originalSelection,
                       "A repeated import must also preserve history and selection")
        }
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            store.importBookmarks([("First bookmark", "https://first.example.org")])
            try expect(store.state.selectedTabIDs.isEmpty, "Import into an empty session must not select or open the imported bookmark")
            try expect(store.state.history.isEmpty, "Import into an empty session must not create browsing history")
        }
    }

    static func testNamesColorsAndPreferencesRoundTrip() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalSpace = store.activeSpaceID
            let originalProfile = store.activeSpace.profileID
            let otherProfile = store.createProfile(name: "Untouched")
            store.renameSpace(originalSpace, name: "Research — 夜空")
            store.renameProfile(originalProfile, name: "Personal research")
            store.setSpaceTheme(originalSpace, theme: .singleColor(ThemeColor(hex: "a1b2c3")!))
            try expect(store.activeSpace.theme.primaryColor?.hex == "A1B2C3", "A valid hexadecimal Space color must be normalized")
            for invalid in ["", "123", "1234567", "#112233", "GG1122"] {
                try expect(ThemeColor(hex: invalid) == nil, "Invalid legacy color cannot enter the theme model: \(invalid)")
            }
            store.renameProfile(originalProfile, name: "")
            store.renameProfile(UUID(), name: "Unknown")
            try expect(store.state.profiles.first { $0.id == originalProfile }?.name == "Personal research",
                       "Empty or unknown profile rename requests must not erase an existing name")
            try expect(store.state.profiles.first { $0.id == otherProfile }?.name == "Untouched",
                       "Renaming a profile must not change another profile")
            store.setAutoArchiveInterval(.twentyFourHours, for: originalProfile)
            store.updateSettings {
                $0.sidebarWidth = 265
                $0.searchEngine = "https://www.bing.com/search?q="
                $0.restoreSession = true
                $0.onboardingComplete = true
            }
            try store.save()
            let expected = store.state
            let reopened = try BrowserStore(directory: directory)
            try expect(reopened.state == expected, "Space names, profile names, colors, and preferences must survive a session restart")
            try expect(reopened.activeSpace.name == "Research — 夜空" && reopened.activeSpace.theme.primaryColor?.hex == "A1B2C3",
                       "Unicode Space names and a valid custom color must remain intact")
        }
    }

    static func testThemeColorsAndLinkedPalettes() throws {
        func close(_ actual: ThemeColor?, _ expected: (Double, Double, Double), _ message: String) throws {
            guard let actual else { throw Failure(description: message + " (no color)") }
            try expect(abs(actual.red - expected.0) < 1e-9 && abs(actual.green - expected.1) < 1e-9
                       && abs(actual.blue - expected.2) < 1e-9, message)
        }
        try close(.hsl(hue: 0, saturation: 1, lightness: 0.5), (1, 0, 0), "HSL red reference")
        try close(.hsl(hue: 1.0 / 3, saturation: 1, lightness: 0.5), (0, 1, 0), "HSL green reference")
        try close(.hsl(hue: -1.0 / 3, saturation: 1, lightness: 0.5), (0, 0, 1), "Hue wraps across zero")
        try close(.hsl(hue: 2, saturation: 0.5, lightness: 0.25), (0.375, 0.125, 0.125), "Low-lightness HSL is not HSB")
        try close(.hsl(hue: 0, saturation: 0.5, lightness: 0.75), (0.875, 0.625, 0.625), "High-lightness HSL branch")
        for value in ["000000", "FFFFFF", "808080", "0123AB", "F20B85", "B9B5D4"] {
            let color = ThemeColor(hex: value)!
            let hsl = color.hsl
            try expect(ThemeColor.hsl(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness)?.hex == value,
                       "HSL conversion must preserve an existing color: \(value)")
        }
        try expect(ThemeColor.hsl(hue: .nan, saturation: 1, lightness: 0.5) == nil, "Nonfinite hue is rejected")
        try expect(ThemeColor(red: 1.1, green: 0, blue: 0) == nil, "Out-of-range components are rejected")
        try expect(ThemeColor(hex: "ＡＡ0000") == nil, "Hex input is ASCII, not visually similar Unicode")
        let nearBlack = SpaceTheme(primaryColor: ThemeColor(red: 0.0001, green: 0, blue: 0), colorCount: 3)
        try expect(nearBlack.colors.count == 3, "Floating-point saturation at near-black must not drop linked colors")
        var theme = SpaceTheme(primaryColor: ThemeColor(hex: "FF0000"), colorCount: 2)
        try close(theme.colors.last, (0, 1, 1), "Two complementary colors are red/cyan")
        theme.colorCount = 3
        try close(theme.colors[1], (0, 1, 0.5), "Three-color first companion is 150 degrees")
        try close(theme.colors[2], (0, 0.5, 1), "Three-color second companion is 210 degrees")
        theme.wheel = .analogous
        try close(theme.colors[1], (1, 2.0 / 3, 0), "First analogous companion is 40 degrees")
        try close(theme.colors[2], (1, 0, 2.0 / 3), "Second analogous companion is minus 40 degrees")
        let wide = ThemeColor(red: 0.83, green: 0.17, blue: 0.29, colorSpace: .displayP3)!
        theme.primaryColor = wide
        try expect(theme.colors.first == wide && theme.colors.allSatisfy { $0.colorSpace == .displayP3 },
                   "Linked colors must preserve the primary color space and original component precision")
        theme.setNoise(0.127)
        try expect(theme.noise == 0.15, "Linear noise input uses twenty steps")
        theme.setNoise(0.127, rotating: true)
        try expect(theme.noise == 0.127, "Rotating noise input keeps continuous precision")
        theme.setNoise(.infinity)
        try expect(theme.noise == 0.127, "Invalid gesture values do not corrupt saved modifiers")
        theme.setNoise(3)
        try expect(theme.noise == 1, "Gesture noise clamps to its upper bound")
        theme.appearance = .dark; theme.texture = .denim; theme.intensity = 0.2
        theme.removeColor(); theme.removeColor()
        try expect(theme.colorCount == 1 && theme.primaryColor == wide, "Removing companions retains primary color")
        theme.removeColor()
        try expect(theme.isValid && theme.colors.isEmpty && theme.noise == 0 && theme.intensity == 0.8
                   && theme.texture == .grain && theme.appearance == .dark,
                   "Removing the final color resets modifiers but preserves appearance")
    }

    static func testThemeMigrationPersistenceAndValidation() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalID = store.activeSpaceID
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var spaces = object["spaces"] as! [[String: Any]]
            spaces[0].removeValue(forKey: "theme"); spaces[0]["color"] = "a1b2c3"
            object["spaces"] = spaces
            try JSONSerialization.data(withJSONObject: object).write(to: file)
            let migrated = try BrowserStore(directory: directory)
            try expect(migrated.activeSpaceID == originalID && migrated.activeSpace.theme.primaryColor?.hex == "A1B2C3"
                       && migrated.activeSpace.theme.colorCount == 1,
                       "Legacy Space color migrates without changing identity or RGB values")
            let target = migrated.activeSpaceID
            let other = migrated.createSpace(name: "Other", color: "aabbcc")
            let untouched = migrated.activeSpace.theme
            let theme = SpaceTheme(primaryColor: ThemeColor(red: 0.9, green: 0.3, blue: 0.4, colorSpace: .displayP3),
                                   colorCount: 3, wheel: .analogous, appearance: .dark,
                                   noise: 0.35, intensity: 0.63, texture: .tweed)
            try expect(migrated.setSpaceTheme(target, theme: theme), "Valid theme update targets the captured Space")
            try expect(migrated.activeSpaceID == other && migrated.activeSpace.theme == untouched,
                       "Editing another Space must not switch or recolor the active Space")
            var invalid = theme; invalid.colorCount = 4
            try expect(!migrated.setSpaceTheme(target, theme: invalid), "Unsupported color count is rejected")
            invalid = theme; invalid.noise = .nan
            try expect(!migrated.setSpaceTheme(target, theme: invalid), "Nonfinite modifiers are rejected")
            invalid = theme; invalid.primaryColor = nil
            try expect(!migrated.setSpaceTheme(target, theme: invalid), "Missing primary color is invalid when count is positive")
            try expect(!migrated.setSpaceTheme(UUID(), theme: theme), "Unknown Space is not implicitly created")
            try migrated.save()
            let reopened = try BrowserStore(directory: directory)
            try expect(reopened.state == migrated.state, "All theme components and other Space state survive restart")
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let savedSpaces = saved["spaces"] as! [[String: Any]]
            try expect(savedSpaces.allSatisfy { $0["color"] == nil && $0["theme"] != nil },
                       "Theme is the only persisted source of color state after migration")
            var broken = saved, brokenSpaces = savedSpaces
            var badTheme = brokenSpaces[0]["theme"] as! [String: Any]
            badTheme["intensity"] = 1.1; brokenSpaces[0]["theme"] = badTheme
            broken["spaces"] = brokenSpaces
            let badData = try JSONSerialization.data(withJSONObject: broken)
            try badData.write(to: file)
            var rejected = false
            do { _ = try BrowserStore(directory: directory) } catch { rejected = true }
            try expect(rejected && (try Data(contentsOf: file)) == badData,
                       "Invalid persisted themes surface an error and preserve the original session bytes")
        }
    }

    static func testDownloadLifecycleAndPersistence() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let originalSelection = store.state.selectedTabIDs
            let originalHistory = store.state.history
            let transitions: [(BrowserDownloadStatus, Int64)] = [
                (.pending, 0), (.downloading, 25), (.paused, 25), (.downloading, 50),
                (.failed, 50), (.downloading, 75), (.completed, 100)
            ]
            for (status, received) in transitions {
                store.recordDownload(["id": "transfer-1", "name": "notes.pdf", "path": "/isolated/notes.pdf",
                                      "receivedBytes": NSNumber(value: received), "totalBytes": 100,
                                      "status": status.rawValue])
                try expect(store.state.downloads.count == 1,
                           "A lifecycle update must replace the existing download rather than append a duplicate")
                let item = store.state.downloads[0]
                try expect(item.status == status && item.receivedBytes == received && item.totalBytes == 100,
                           "Download state and byte progress must track the latest native snapshot: \(status)")
                try expect(item.isComplete == (status == .completed) && !item.isCancelled,
                           "Paused or failed downloads must never be described as completed or cancelled")
                try store.save()
                let reopened = try BrowserStore(directory: directory)
                try expect(reopened.state.downloads == store.state.downloads,
                           "Every download lifecycle state must persist across a restart: \(status)")
            }
            store.recordDownload(["id": "transfer-2", "name": "cancelled.zip", "receivedBytes": 12,
                                  "totalBytes": 200, "status": "cancelled"])
            try expect(store.state.downloads.count == 2 && store.state.downloads[1].isCancelled
                       && !store.state.downloads[1].isComplete,
                       "A cancelled transfer must remain distinct from a successful transfer")
            try expect(store.state.selectedTabIDs == originalSelection && store.state.history == originalHistory,
                       "Download events must not navigate or create page history")
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            try expect(reopened.state.downloads == store.state.downloads,
                       "Cancellation and the prior completed transfer must both survive relaunch")
        }
    }

    static func testDownloadLibraryIdentityAndMetadata() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let profile = store.activeSpace.profileID
            let path = store.independentEngineProfilePath(for: profile)
            let selection = store.state.selectedTabIDs
            var snapshot: [String: Any] = ["id": "same-guid", "profilePath": path,
                "name": "report.pdf", "path": "/isolated/report.pdf", "status": "completed",
                "sourceURL": "https://example.test/report.pdf", "startedAt": 1_700_000_000.0,
                "available": true, "itemIdentity": "incarnation-one", "canOpen": true,
                "canReveal": true, "canRemove": true, "canCopyFile": true]
            store.recordDownload(snapshot)
            let original = store.state.downloads[0]
            try expect(original.profileID == profile && original.nativeIdentity == "incarnation-one"
                       && original.canOpen && original.canReveal && original.canRemove && original.canCopyFile,
                       "Library controls must retain the real profile and live item incarnation")
            try expect(original.sourceURL == "https://example.test/report.pdf"
                       && original.startedAt == Date(timeIntervalSince1970: 1_700_000_000),
                       "Source URL and native start time must survive the bridge without a fabricated date")
            try store.save()
            let restored = try BrowserStore(directory: directory).state.downloads[0]
            try expect(restored.sourceURL == original.sourceURL && restored.startedAt == original.startedAt,
                       "Library metadata survives session persistence")
            try expect(restored.nativeIdentity == nil && !restored.canOpen && !restored.canReveal
                       && !restored.canRemove && !restored.canCopyFile,
                       "Restored metadata never grants live file actions")
            snapshot["itemIdentity"] = "incarnation-two"
            store.recordDownload(snapshot)
            try expect(store.state.downloads.count == 1 && store.state.downloads[0].nativeIdentity == "incarnation-two",
                       "The same GUID can receive a new incarnation without making an old row current")
            snapshot["available"] = false
            store.recordDownload(snapshot)
            try expect(store.state.downloads[0].nativeIdentity == nil && !store.state.downloads[0].canCopyFile,
                       "Manager retirement revokes file actions without erasing truthful completion")
            snapshot["profilePath"] = directory.appendingPathComponent("unowned").path
            snapshot["id"] = "unowned"
            store.recordDownload(snapshot)
            try expect(store.state.downloads.count == 1 && store.state.selectedTabIDs == selection,
                       "Unknown profiles are discarded; download updates do not switch pages")
            store.recordDownload(["id": "legacy", "name": "old.pdf", "status": "completed"])
            store.reconcileDownloads(profileID: profile, nativeIDs: [])
            try expect(store.state.downloads.map(\.id) == ["legacy"],
                       "Ready manager history removes only stale records assigned to its original profile")
        }
    }

    static func testLegacyDownloadSessionMigration() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var session = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            session["downloads"] = [
                ["id": "complete", "name": "complete.pdf", "path": "/isolated/complete.pdf",
                 "receivedBytes": 100, "totalBytes": 100, "isComplete": true, "isCancelled": false],
                ["id": "cancelled", "name": "cancelled.pdf", "path": "",
                 "receivedBytes": 50, "totalBytes": 100, "isComplete": false, "isCancelled": true],
                ["id": "active", "name": "active.pdf", "path": "/isolated/active.pdf",
                 "receivedBytes": 50, "totalBytes": 100, "isComplete": false, "isCancelled": false],
                ["id": "pending", "name": "pending.pdf", "path": "",
                 "receivedBytes": 0, "totalBytes": -1, "isComplete": false, "isCancelled": false]
            ]
            try JSONSerialization.data(withJSONObject: session).write(to: file)
            let migrated = try BrowserStore(directory: directory)
            try expect(migrated.state.downloads.map(\.status) == [.completed, .cancelled, .downloading, .pending],
                       "Old sessions without status must retain completion, cancellation, and available progress information")
            try expect(migrated.state.downloads[0].path == "/isolated/complete.pdf"
                       && migrated.state.downloads[2].receivedBytes == 50
                       && migrated.state.downloads[3].totalBytes == -1,
                       "Migration must preserve paths, byte counts, and unknown content lengths")
            try migrated.save()
            let encoded = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let downloads = encoded["downloads"] as! [[String: Any]]
            try expect(downloads[0]["status"] as? String == "completed"
                       && downloads[0]["isComplete"] as? Bool == true
                       && downloads[1]["isCancelled"] as? Bool == true,
                       "Newly saved states must include precise status and retain the original compatibility flags")
            let reopened = try BrowserStore(directory: directory)
            try expect(reopened.state.downloads == migrated.state.downloads,
                       "A migrated session must round-trip without further state changes")
        }
    }

    static func testDownloadFlagsAndExplicitState() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            store.recordDownload(["id": "paused", "isPaused": true, "receivedBytes": 4])
            store.recordDownload(["id": "failed", "isFailed": true, "receivedBytes": 4])
            try expect(store.state.downloads.map(\.status) == [.paused, .failed],
                       "Callback flags must retain pause and failure when the string status is absent")
            store.recordDownload(["id": "failed", "status": "downloading", "isFailed": true, "receivedBytes": 8])
            try expect(store.state.downloads[1].status == .downloading,
                       "The exact native string state must take precedence over a stale compatibility flag")
            store.recordDownload(["id": "failed", "status": "unknown", "isFailed": true, "receivedBytes": 8])
            try expect(store.state.downloads[1].status == .failed,
                       "An unrecognized callback state must fall back to known failure evidence")
        }
    }

    static func expectFactors(_ actual: [Double]?, _ expected: [Double], _ message: String) throws {
        try expect(actual?.count == expected.count, message + " (pane count)")
        guard let actual, actual.count == expected.count else { return }
        try expect(zip(actual, expected).allSatisfy { abs($0 - $1) < 1e-10 }, message)
    }

    static func testSplitLayoutValidation() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            try expect(!store.setSplitLayout(orientation: .vertical, widthFactors: [1, 1]),
                       "A single selected tab must not accept split geometry")
            store.setSplit([first, second])
            try expect(store.setSplitLayout(orientation: .vertical, widthFactors: [2, 6]),
                       "A valid layout must accept positive relative weights")
            try expectFactors(store.activeSplitLayout?.widthFactors, [0.25, 0.75], "Weights must normalize to a unit sum")
            let expected = store.state
            for weights in [[Double](), [1], [1, 1, 1], [0, 1], [-1, 2], [.nan, 1], [.infinity, 1], [Double.leastNonzeroMagnitude, Double.greatestFiniteMagnitude]] {
                try expect(!store.setSplitLayout(orientation: .horizontal, widthFactors: weights),
                           "Invalid, mismatched or unrepresentable weights must be rejected")
                try expect(store.state == expected, "Rejected geometry must not mutate selection or persisted layouts")
            }
            try expect(store.setSplitLayout(orientation: .horizontal,
                widthFactors: [Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude]),
                "Normalization must not overflow when large valid weights have a non-finite raw sum")
            try expectFactors(store.activeSplitLayout?.widthFactors, [0.5, 0.5], "Large equal weights must remain equal")
            store.selectTab(first)
            try expect(store.state.selectedTabIDs == [first, second], "Selecting a typed child retains the whole split")
            store.closeSplit()
            try expect(store.activeSplitLayout == nil, "A dissolved split leaves one normal page")
        }
    }

    static func testSavedSplitLayoutsAcrossSpacesAndRestart() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let firstSpace = store.activeSpaceID
            let profile = store.activeSpace.profileID
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            let third = store.open("https://three.example")
            let fourth = store.open("https://four.example")
            store.setSplit([first, second])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 3])
            let original = store.activeSplitLayout
            store.selectTab(third)
            store.setSplit([third, fourth])
            store.setSplitLayout(orientation: .horizontal, widthFactors: [3, 2])
            store.setSplit([first, second])
            try expect(store.activeSplitLayout == original, "Revisiting an ordered pane group must restore its own geometry")
            store.updateTab(first, title: "Changed page", url: "https://one.example/next")
            try expect(store.activeSplitLayout == original, "Navigation and title updates must not drift divider proportions")
            let tray = SidebarContainerLocation(spaceID: firstSpace, folderID: nil, section: .favorite, profileID: profile)
            let snapshot = SidebarHierarchySnapshot(state: store.state, spaceID: firstSpace, profileID: profile, includesFavorites: true)!
            try expect(try store.moveSidebarItem(.split(original!.id), to: tray, before: nil, expected: snapshot),
                       "A whole split moves into Favorites")
            try expect(try tab(first, in: store).kind == .favorite && tab(second, in: store).kind == .favorite,
                       "Every child enters the Favorites container with its split")
            let secondSpace = store.createSpace(name: "Second")
            store.selectTab(first)
            try expect(store.activeSplitLayout?.id == original?.id && store.state.selectedTabIDs == [first, second],
                       "Another Space of the Profile shows the same Favorite split")
            store.setSplitLayout(orientation: .horizontal, widthFactors: [4, 1])
            let other = store.activeSplitLayout
            try expect(other?.id == original?.id, "Resizing from another Space edits the one Favorite split")
            store.selectSpace(firstSpace)
            try expect(store.activeSplitLayout == other, "A Favorite split has one Profile-wide layout in every Space")
            try expect(store.state.splitLayouts.filter { $0.tabIDs.contains(first) }.count == 1,
                       "The same Favorites form one split, not one per Space")
            try store.save()
            let reopened = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            try expect(reopened.state == store.state, "All stored split layouts and selected panes must survive a restart")
            reopened.selectSpace(secondSpace)
            try expect(reopened.activeSplitLayout == other, "Restoring another Space shows the Favorite split's one layout")
            reopened.selectSpace(firstSpace)
            reopened.setSplit([third, fourth])
            try expectFactors(reopened.activeSplitLayout?.widthFactors, [0.6, 0.4], "A second saved group in one Space must survive restart")
            try expect(reopened.activeSplitLayout?.orientation == .horizontal, "Orientation belongs to the split, not the most recently displayed Space")
        }
    }

    static func testClosingSplitAnchorKeepsSlot() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let todayBox = SidebarContainerLocation(spaceID: store.activeSpaceID, folderID: nil, section: .today)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            let bottom = store.open("https://bottom.example")
            let f = store.open("https://f.example"), e = store.open("https://e.example"), d = store.open("https://d.example")
            let middle = store.open("https://middle.example")
            let c = store.open("https://c.example"), b = store.open("https://b.example"), a = store.open("https://a.example")
            let top = store.open("https://top.example")
            store.selectTab(a); store.selectTab(b, extendingSplit: true); store.selectTab(c, extendingSplit: true)
            let trio = store.activeSplitLayout!
            store.selectTab(d); store.selectTab(e, extendingSplit: true); store.selectTab(f, extendingSplit: true)
            let shown = store.activeSplitLayout!
            try expect(trio.sidebarAnchorID == a && shown.sidebarAnchorID == d
                       && today() == [.tab(top), .split(trio.id), .tab(middle), .split(shown.id), .tab(bottom)],
                       "Two three-pane splits sit between tabs, each filed under its first pane")

            store.closeTab(a)
            let kept = store.state.splitLayouts.first { $0.id == trio.id }
            try expect(kept?.tabIDs == [b, c] && kept?.sidebarAnchorID == b, "The next pane takes over a split that isn't shown")
            try expect(today() == [.tab(top), .split(trio.id), .tab(middle), .split(shown.id), .tab(bottom)],
                       "Closing the anchor pane of a split that isn't shown keeps the split in its slot")
            store.closeTab(b)
            try expect(!store.state.splitLayouts.contains { $0.id == trio.id }
                       && today() == [.tab(top), .tab(c), .tab(middle), .split(shown.id), .tab(bottom)],
                       "Dissolving a split that isn't shown leaves its last pane in the split's slot")

            store.closeTab(d)
            let displayed = store.state.splitLayouts.first { $0.id == shown.id }
            try expect(displayed?.tabIDs == [e, f] && displayed?.sidebarAnchorID == e && store.state.selectedTabIDs == [e, f],
                       "The shown split loses its anchor pane and stays shown")
            try expect(today() == [.tab(top), .tab(c), .tab(middle), .split(shown.id), .tab(bottom)],
                       "Closing the anchor pane of the shown split keeps the split in its slot")
        }
    }

    static func testSplitMembershipContainers() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let todayBox = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)
            let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
            @MainActor func today() -> [SidebarItemReference] { SidebarHierarchy.children(in: todayBox, state: store.state) }
            @MainActor func trayItems() -> [SidebarItemReference] { SidebarHierarchy.children(in: tray, state: store.state) }
            let folder = store.createFolder(name: "Saved")
            let folderBox = SidebarContainerLocation(spaceID: space, folderID: folder, section: .pinned)
            let favorite = store.open("https://fav.example", kind: .favorite)
            let pinned = store.open("https://pin.example", kind: .pinned)
            store.moveTab(pinned, toSpace: space, folderID: folder)
            let t1 = store.open("https://t1.example"), t2 = store.open("https://t2.example")
            try expect(today() == [.tab(t2), .tab(t1)], "Created Today tabs enter at the top")

            store.selectTab(pinned); store.selectTab(t1, extendingSplit: true)
            var group = store.activeSplitLayout!
            let pinnedHome = try expectHome(of: pinned, in: store, savedURL: "https://pin.example")
            try expect(group.tabIDs == [pinned, t1] && group.sidebarAnchorID == t1, "New split anchors at its first ordinary member")
            try expect(today() == [.tab(t2), .split(group.id)], "The new split takes the ordinary member's Today slot")
            try expect(SidebarHierarchy.children(in: folderBox, state: store.state) == [.tab(pinnedHome.id)]
                       && pinnedHome.folderID == folder, "The pinned slot keeps a fresh home in its folder")
            try expect(try tab(pinned, in: store).kind == .today && tab(pinned, in: store).folderID == nil,
                       "The pinned original enters the Today container with its split")
            store.selectTab(favorite, extendingSplit: true)
            group = store.activeSplitLayout!
            let favoriteHome = try expectHome(of: favorite, in: store, savedURL: "https://fav.example")
            try expect(group.tabIDs == [pinned, t1, favorite] && trayItems() == [.tab(favoriteHome.id)],
                       "A Favorite added to a Today split leaves its tray home")
            try expect(try tab(favorite, in: store).kind == .today && today() == [.tab(t2), .split(group.id)],
                       "The Favorite original joins the existing Today container; the split keeps its slot")

            try expect(store.separateTabFromSplit(t1, expected: group, focusedID: pinned), "Separate the anchor")
            group = store.state.splitLayouts.first { $0.id == group.id }!
            try expect(group.sidebarAnchorID == pinned && today() == [.tab(t2), .split(group.id), .tab(t1)],
                       "A departing anchor keeps the split's slot; the child follows the split")
            try expect(store.separateTabFromSplit(favorite, expected: group, focusedID: pinned), "Separate to dissolve")
            try expect(store.activeSplitLayout == nil && today() == [.tab(t2), .tab(pinned), .tab(favorite), .tab(t1)],
                       "Dissolving puts every child at the split's slot in child order")

            let g1 = store.open("https://g1.example", kind: .favorite), g2 = store.open("https://g2.example", kind: .favorite)
            store.selectTab(g1); store.selectTab(g2, extendingSplit: true)
            let saved = store.activeSplitLayout!
            let g1Home = try expectHome(of: g1, in: store, savedURL: "https://g1.example")
            let g2Home = try expectHome(of: g2, in: store, savedURL: "https://g2.example")
            try expect(today().first == .split(saved.id) && trayItems() == [.tab(favoriteHome.id), .tab(g1Home.id), .tab(g2Home.id)],
                       "Two Favorites form a Today split at the top while the tray keeps both homes")
            store.closeTab(g1)
            try expect(today().first == .tab(g2) && store.activeSplitLayout == nil,
                       "Closing a pane dissolves the split into its slot with the survivor")

            let u1 = store.open("https://u1.example"), u2 = store.open("https://u2.example")
            let favoriteSplit = try savedSplit(store, [u1, u2], in: tray)
            store.selectTab(u1)
            let t3 = store.open("https://t3.example")
            store.selectTab(u1); store.selectTab(t3, extendingSplit: true)
            try expect(store.activeSplitLayout?.id == favoriteSplit.id && store.activeSplitLayout?.tabIDs == [u1, u2, t3]
                       && (try tab(t3, in: store)).kind == .favorite, "A Today page added to a Favorite split joins topApps")
            try expect(!trayItems().contains(.tab(t3)) && trayItems().filter { $0 == .split(favoriteSplit.id) }.count == 1,
                       "The Favorite split stays one tray item")
            let q = store.open("https://q.example", kind: .pinned)
            store.selectTab(u1)
            let current = store.state.selectedTabIDs
            try expect(store.insertCommandBarSplit(after: t3, expectedSelection: current, tabID: q),
                       "A pinned command-bar result joins the Favorite split")
            let qHome = try expectHome(of: q, in: store, savedURL: "https://q.example")
            try expect(qHome.kind == .pinned && (try tab(q, in: store)).kind == .favorite && store.state.selectedTabIDs == current + [q],
                       "The pinned result leaves its home and its original enters topApps")
            let secondSpace = store.createSpace(name: "Second")
            store.selectTab(u1)
            try expect(store.activeSpaceID == secondSpace && store.state.selectedTabIDs == current + [q],
                       "The Favorite split with its new members appears in every Space")
            let favoriteGroup = store.activeSplitLayout!
            try expect(store.separateTabFromSplit(q, expected: favoriteGroup, focusedID: u1), "Separate from a Favorite split")
            let trayNow = SidebarHierarchy.children(in: .init(spaceID: secondSpace, folderID: nil, section: .favorite, profileID: profile), state: store.state)
            try expect(trayNow.firstIndex(of: .split(favoriteGroup.id)).map { $0 + 1 } == trayNow.firstIndex(of: .tab(q))
                       && (try tab(q, in: store)).kind == .favorite, "The separated child is a Favorite right after the split tile")
            store.selectSpace(space)

            let v1 = store.open("https://v1.example"), v2 = store.open("https://v2.example")
            let pinnedSplit = try savedSplit(store, [v1, v2], in: folderBox)
            store.selectTab(v1)
            let t4 = store.open("https://t4.example")
            store.selectTab(v1)
            try expect(store.dropTabIntoSplit(t4, expectedSelection: [v1, v2], expectedLayout: store.activeSplitLayout,
                target: .insert(2), orientation: pinnedSplit.orientation), "Drop a Today tab into a pinned split")
            try expect(try tab(t4, in: store).kind == .pinned && tab(t4, in: store).folderID == folder
                       && store.activeSplitLayout?.tabIDs == [v1, v2, t4], "The dropped tab enters the pinned split's folder")

            try store.save()
            let reopened = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            try expect(reopened.state == store.state, "Container membership and slots survive restart")
        }
    }

    static func testSplitMembershipRoutes() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let pinnedRoot = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let todayBox = SidebarContainerLocation(spaceID: space, folderID: nil, section: .today)

            let documentID = UUID()
            let note = store.openNote(id: documentID, title: "Note")!
            store.selectTab(note)
            let todayJoin = UUID()
            try expect(store.commandBarSplitHomes(after: note, expectedSelection: [note], tabID: todayJoin, isNew: true)?.isEmpty == true,
                       "A Today Note does not leave a pinned home beside a new URL")
            store.setKind(note, .pinned)
            let newID = UUID()
            let noteHomes = store.commandBarSplitHomes(after: note, expectedSelection: [note], tabID: newID, isNew: true)!
            try expect(noteHomes.map(\.id) == [note], "The displayed pinned Note needs a home even beside a new URL")
            try expect(SplitMembership.homePlan(noteHomes) { _ in nil } == nil, "A typed home without a live document refuses")
            let reference = SidebarDocumentReference(page: .note(documentID), profileID: profile) { }
            let plan = SplitMembership.homePlan(noteHomes) { _ in [note: reference] }!
            try expect(Set(plan.ids.keys) == [note] && plan.documents.count == 1, "The plan fixes one validated Note home")
            try expect(store.insertCommandBarSplit(after: note, expectedSelection: [note], tabID: newID,
                newURL: URL(string: "https://new.example")!, savedHomeIDs: plan.ids, documents: plan.documents),
                "A lone Note pane splits with a new URL")
            let noteHome = store.state.tabs.first { $0.id == plan.ids[note] }!
            try expect(noteHome.kind == .pinned && noteHome.savedURL == InternalPage.note(documentID).urlString
                       && (try tab(note, in: store)).kind == .today, "The Note joins Today and its alias home stays pinned")

            let p = store.open("https://p.example", kind: .pinned), q = store.open("https://q.example", kind: .pinned)
            let t = store.open("https://t.example")
            _ = store.setWindowPresentation(spaceID: space, selectedTabIDs: [p])
            try expect(store.splitExtensionHomes(q).map(\.id) == [p, q], "Window A's single pinned page also needs a home")
            _ = store.setWindowPresentation(spaceID: space, selectedTabIDs: [t])
            try expect(store.splitExtensionHomes(q).map(\.id) == [q], "Window B plans from its own synchronized selection")

            let a = store.open("https://a.example"), b = store.open("https://b.example")
            store.selectTab(a); store.selectTab(b, extendingSplit: true)
            let pair = store.activeSplitLayout!
            store.setKind(b, .pinned)
            try expect(try tab(a, in: store).kind == .pinned && tab(b, in: store).kind == .pinned
                       && SidebarHierarchy.children(in: pinnedRoot, state: store.state).contains(.split(pair.id)),
                       "Pinning a split pane pins its whole split")
            store.setKind(a, .today)
            try expect(try tab(a, in: store).kind == .today && tab(b, in: store).kind == .today
                       && SidebarHierarchy.children(in: todayBox, state: store.state).contains(.split(pair.id)),
                       "Unpinning a split pane unpins its whole split")

            let w1 = store.open("https://w1.example", kind: .pinned), w2 = store.open("https://w2.example")
            _ = store.setWindowPresentation(spaceID: space, selectedTabIDs: [w1, w2],
                splitLayout: BrowserSplitLayout(spaceID: space, tabIDs: [w1, w2], widthFactors: [0.5, 0.5]))
            let reformed = store.state.splitLayouts.first { $0.tabIDs == [w1, w2] }
            try expect(reformed != nil && (try tab(w1, in: store)).kind == .today
                       && store.state.tabs.contains { $0.kind == .pinned && $0.savedURL == "https://w1.example" && $0.id != w1 },
                       "A window's own split re-forms through the membership owner")

            let x1 = store.open("https://x1.example"), x2 = store.open("https://x2.example"), x3 = store.open("https://x3.example")
            let pinnedSplit = try savedSplit(store, [x1, x2, x3], in: pinnedRoot)
            store.selectTab(x1)
            store.closeTab(x2)
            let afterClose = SidebarHierarchy.children(in: pinnedRoot, state: store.state)
            try expect(store.state.splitLayouts.first { $0.id == pinnedSplit.id }?.tabIDs == [x1, x3]
                       && (try tab(x2, in: store)).kind == .pinned && (try tab(x2, in: store)).archivedAt == nil
                       && afterClose.firstIndex(of: .split(pinnedSplit.id)).map { $0 + 1 } == afterClose.firstIndex(of: .tab(x2)),
                       "A closed pinned pane stays saved and follows its split")

            let f1 = store.open("https://f1.example"), f2 = store.open("https://f2.example"), f3 = store.open("https://f3.example")
            let tray = SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile)
            let favoriteSplit = try savedSplit(store, [f1, f2, f3], in: tray)
            let second = store.createSpace(name: "Second")
            store.selectTab(f1)
            try expect(store.activeSpaceID == second && store.activeSplitLayout?.id == favoriteSplit.id, "The Favorite split shows in Space 2")
            store.closeTab(f2)
            let trayFromSecond = SidebarHierarchy.children(in: .init(spaceID: second, folderID: nil, section: .favorite, profileID: profile), state: store.state)
            try expect(store.state.splitLayouts.first { $0.id == favoriteSplit.id }?.tabIDs == [f1, f3]
                       && trayFromSecond.firstIndex(of: .split(favoriteSplit.id)).map { $0 + 1 } == trayFromSecond.firstIndex(of: .tab(f2)),
                       "Closing a Favorite split pane from another Space removes it from the one split")
            store.selectSpace(space)
            let other = store.createProfile(name: "Other")
            store.relocateLocalDocuments = { ids, pages, from, to in
                try expect(ids.contains(note) && ids.contains(noteHome.id) && pages == [.note(documentID)],
                           "Profile assignment delegates the original Note and alias together")
                try expect(from == profile && to == other, "Profile assignment binds both storage Profiles")
                return {}
            }
            store.assignProfile(other, toSpace: space)
            let kept = store.state.splitLayouts.first { $0.id == favoriteSplit.id }
            try expect(kept?.spaceID == second && kept?.tabIDs == [f1, f3], "A Favorite split survives its storing Space changing Profile")
        }
    }

    static func testLegacyMixedSplitContainerMigration() throws {
        try withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            var state = BrowserState.initial()
            let space = state.activeSpaceID, profile = state.profiles[0].id
            let other = BrowserSpace(id: UUID(), name: "Other", symbol: "circle.fill", color: "B9B5D4", profileID: profile)
            state.spaces.append(other)
            let folder = BrowserFolder(id: UUID(), spaceID: space, name: "Saved")
            state.folders = [folder]
            func make(_ kind: TabKind, _ name: String, folder: UUID? = nil, in spaceID: UUID? = nil) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: spaceID ?? space, profileID: profile, url: "https://\(name).example/now",
                    title: name, kind: kind, folderID: folder, createdAt: now, lastAccessed: now,
                    savedURL: "https://\(name).example", savedTitle: name)
            }
            let today = make(.today, "today"), fav = make(.favorite, "fav"), pin = make(.pinned, "pin", folder: folder.id)
            let anchorFavorite = make(.favorite, "anchor"), stray = make(.today, "stray")
            let x = make(.favorite, "x"), y = make(.favorite, "y")
            state.tabs = [today, fav, pin, anchorFavorite, stray, x, y]
            let trayKey = "favorites:" + profile.uuidString
            state.sidebarItemOrder[trayKey] = [.tab(fav.id), .tab(anchorFavorite.id), .tab(x.id)]
            state.sidebarItemOrder[space.uuidString + ":" + folder.id.uuidString] = [.tab(pin.id)]
            let todayGroup = BrowserSplitLayout(spaceID: space, tabIDs: [today.id, fav.id, pin.id], widthFactors: [0.2, 0.3, 0.5])
            let favoriteAnchored = BrowserSplitLayout(spaceID: space, tabIDs: [anchorFavorite.id, stray.id], widthFactors: [0.5, 0.5])
            let older = BrowserSplitLayout(spaceID: other.id, tabIDs: [x.id, y.id], orientation: .vertical, widthFactors: [0.4, 0.6])
            let newer = BrowserSplitLayout(spaceID: space, tabIDs: [x.id, y.id], widthFactors: [0.7, 0.3])
            state.splitLayouts = [todayGroup, favoriteAnchored, older, newer]
            state.selectedTabIDs = todayGroup.tabIDs
            state.selectionBySpace[other.id.uuidString] = [fav.id]
            state.settings.restoreSession = true
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))

            let store = try BrowserStore(directory: directory, now: { now })
            let originals = Set(state.tabs.map(\.id))
            try expect(originals.isSubset(of: Set(store.state.tabs.filter { $0.archivedAt == nil }.map(\.id))),
                       "Migration keeps every original page live")
            let favHome = try expectHome(of: fav.id, in: store, savedURL: "https://fav.example")
            let pinHome = try expectHome(of: pin.id, in: store, savedURL: "https://pin.example")
            try expect(try tab(fav.id, in: store).kind == .today && tab(pin.id, in: store).kind == .today
                       && tab(pin.id, in: store).folderID == nil, "Children of a Today-anchored group enter Today")
            try expect(store.state.sidebarItemOrder[trayKey]?.first == .tab(favHome.id)
                       && store.state.sidebarItemOrder[space.uuidString + ":" + folder.id.uuidString] == [.tab(pinHome.id)],
                       "Each saved child keeps a fresh home in its exact former slot")
            try expect(store.state.selectionBySpace[other.id.uuidString] == [favHome.id],
                       "Another Space's remembered Favorite follows the saved home")
            try expect(store.activeSplitLayout?.id == todayGroup.id && store.activeSplitLayout?.tabIDs == todayGroup.tabIDs,
                       "The Today group keeps its identity, order and selection")
            try expect(try tab(stray.id, in: store).kind == .favorite
                       && store.state.splitLayouts.contains { $0.id == favoriteAnchored.id && $0.tabIDs == favoriteAnchored.tabIDs },
                       "A Favorite-anchored group stays in the tray and its Today child joins topApps")
            let favoritePairs = store.state.splitLayouts.filter { $0.tabIDs.contains(x.id) }
            try expect(favoritePairs.count == 1 && favoritePairs[0].id == newer.id && favoritePairs[0].widthFactors == newer.widthFactors,
                       "Per-Space copies of the same Favorites become one Profile-wide split")
            try expect(store.state.splitLayouts.allSatisfy { group in
                guard let box = SplitMembership.container(of: group, in: store.state) else { return false }
                return group.tabIDs.allSatisfy { id in store.state.tabs.first { $0.id == id }.map { SplitMembership.conforms($0, to: box) } ?? false }
            }, "Every group's children share their split's container")
            let migrated = store.state
            let again = try BrowserStore(directory: directory, now: { now })
            try expect(again.state == migrated, "The migrated form is persisted and stable on the next restart")
        }
    }

    static func testLegacySharedFavoriteMigration() throws {
        try withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            var state = BrowserState.initial()
            let first = state.activeSpaceID, profile = state.profiles[0].id
            let second = BrowserSpace(id: UUID(), name: "Second", symbol: "circle.fill", color: "B9B5D4", profileID: profile)
            state.spaces.append(second)
            func make(_ kind: TabKind, _ name: String, in spaceID: UUID) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: spaceID, profileID: profile, url: "https://\(name).example", title: name,
                    kind: kind, createdAt: now, lastAccessed: now, savedURL: "https://\(name).example", savedTitle: name)
            }
            let shared = make(.favorite, "shared", in: first), partner = make(.favorite, "partner", in: second.id)
            let t1 = make(.today, "t1", in: first), t2 = make(.today, "t2", in: first)
            let roaming = make(.favorite, "roaming", in: first), t3 = make(.today, "t3", in: first)
            let fillers = (0..<10).map { make(.favorite, "filler\($0)", in: first) }
            state.tabs = [shared, partner, t1, t2, roaming, t3] + fillers
            let mixed = BrowserSplitLayout(customTitle: "Kept title", spaceID: first, tabIDs: [t1.id, shared.id, t2.id], widthFactors: [0.2, 0.3, 0.5])
            let favoriteSplit = BrowserSplitLayout(spaceID: second.id, tabIDs: [shared.id, partner.id], widthFactors: [0.5, 0.5])
            let roamingSplit = BrowserSplitLayout(spaceID: first, tabIDs: [t3.id, roaming.id], widthFactors: [0.5, 0.5])
            state.splitLayouts = [favoriteSplit, mixed, roamingSplit]
            state.selectionBySpace[first.uuidString] = mixed.tabIDs
            state.activeSpaceID = second.id; state.selectedTabIDs = [roaming.id]
            state.settings.restoreSession = true
            let trayFromSecond = SidebarContainerLocation(spaceID: second.id, folderID: nil, section: .favorite, profileID: profile)
            let rootsBefore = SidebarHierarchy.children(in: trayFromSecond, state: state).count
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))

            let store = try BrowserStore(directory: directory, now: { now })
            try expect(store.state.splitLayouts.first { $0.id == favoriteSplit.id }?.tabIDs == [shared.id, partner.id],
                       "The Favorites-container split keeps the shared Favorite")
            let kept = store.state.splitLayouts.first { $0.id == mixed.id }
            try expect(kept?.tabIDs == [t1.id, t2.id] && kept?.customTitle == "Kept title",
                       "The other split keeps its own children, layout and title")
            try expect(try tab(shared.id, in: store).kind == .favorite, "The shared Favorite stays a Favorite")
            let roamingHome = try expectHome(of: roaming.id, in: store, savedURL: "https://roaming.example")
            try expect(store.state.selectedTabIDs == [roamingHome.id] && (try tab(roaming.id, in: store)).kind == .today,
                       "The active selection in another Space follows the moved Favorite's home")
            let rootsAfter = SidebarHierarchy.children(in: trayFromSecond, state: store.state).count
            try expect(rootsBefore == 12 && rootsAfter == rootsBefore, "Migration adds no Favorites root past twelve")
            let again = try BrowserStore(directory: directory, now: { now })
            try expect(again.state == store.state, "The resolved form is persisted and stable")
        }
    }

    static func testSplitPaneChangesPreserveSurvivors() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example", kind: .pinned)
            let third = store.open("https://three.example")
            let replacement = store.open("https://replacement.example")
            store.setSplit([first, third])
            store.setSplitLayout(orientation: .horizontal, widthFactors: [4, 1])
            store.setSplit([first, second, third])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2, 3])
            let firstHome = try expectHome(of: first, in: store, savedURL: "https://one.example")
            let secondHome = try expectHome(of: second, in: store, savedURL: "https://two.example")
            try expect(SidebarHierarchy.children(in: .init(spaceID: store.activeSpaceID, folderID: nil, section: .pinned),
                                                 state: store.state) == [.tab(firstHome.id), .tab(secondHome.id)],
                       "Each pinned member that joins keeps a fresh home in its own slot")
            store.setSplit([first, replacement, third])
            try expectFactors(store.activeSplitLayout?.widthFactors, [1.0/6, 2.0/6, 3.0/6],
                              "Replacing a pane's tab must preserve its position and divider sizes")
            try expect(store.activeSplitLayout?.orientation == .vertical, "Replacing a pane must preserve orientation")
            store.setSplit([first, second, third])
            let originalGroup = store.activeSplitLayout!
            try expect(store.separateTabFromSplit(second, expected: originalGroup, focusedID: first), "Separating a different pane preserves the original focus")
            try expectFactors(store.activeSplitLayout?.widthFactors, [0.25, 0.75], "Separating a pane must proportionally expand surviving panes, replacing any older geometry for the surviving group")
            try expect(store.activeSplitLayout?.orientation == .vertical, "The visible split must win when its surviving group already has an older saved layout")
            try expect(try tab(second, in: store).archivedAt == nil, "Separating a page must leave its tab alive")
            store.selectTab(second, extendingSplit: true)
            try expect(store.activeSplitLayout?.tabIDs == [first, third, second], "Adding a pane must append it to the current saved split")
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 3, 2])
            store.closeTab(second)
            try expectFactors(store.activeSplitLayout?.widthFactors, [0.25, 0.75], "Closing a pane must resize survivors")
            try expect(try tab(second, in: store).archivedAt != nil && tab(secondHome.id, in: store).archivedAt == nil,
                       "The joined original archives as a Today pane while its saved home keeps the bookmark")
            store.closeTab(third)
            try expect(store.state.selectedTabIDs == [first] && store.activeSplitLayout == nil,
                       "Closing the penultimate pane must leave one normal page")
            try expect(store.state.splitLayouts.allSatisfy { !$0.tabIDs.contains(third) },
                       "Archived tabs must be removed from every saved layout")
            store.setSplit([first, replacement])
            store.closeSplit()
            try expect(!store.state.splitLayouts.contains { $0.spaceID == store.activeSpaceID && $0.tabIDs == [first, replacement] },
                       "Closing a split must dissolve its saved layout without closing its pages")
            try expect(try tab(replacement, in: store).archivedAt == nil, "Dissolving a split must preserve its other page")
        }
    }

    static func testSplitLayoutMembershipCleanup() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let firstSpace = store.activeSpaceID
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            let favorite = store.open("https://favorite.example", kind: .favorite)
            store.setSplit([first, second, favorite])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2, 3])
            let favoriteHome = try expectHome(of: favorite, in: store, savedURL: "https://favorite.example")
            try expect(try tab(favorite, in: store).kind == .today && favoriteHome.kind == .favorite,
                       "A Favorite joining a new split enters Today; its fresh home keeps the tray slot")
            let otherSpace = store.createSpace(name: "Other")
            store.moveTab(second, toSpace: otherSpace)
            store.selectSpace(firstSpace)
            try expect(store.state.selectedTabIDs == [first, favorite], "Space restoration must drop a moved pane")
            try expectFactors(store.activeSplitLayout?.widthFactors, [0.25, 0.75], "A moved pane must be removed from its former split's saved geometry")
            let profile = store.createProfile(name: "Separate")
            store.assignProfile(profile, toSpace: firstSpace)
            try expect(store.state.splitLayouts.map(\.tabIDs) == [[first, favorite]]
                       && (try tab(first, in: store)).profileID == profile && (try tab(favorite, in: store)).profileID == profile,
                       "The joined original is an ordinary page of the split and follows its Space's Profile")
            try expect(try tab(favoriteHome.id, in: store).profileID != profile,
                       "The Favorite's saved home stays in its own Profile's tray")
            try store.save()
            _ = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        }
    }

    static func testLegacySplitLayoutMigration() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let firstSpace = store.activeSpaceID
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            store.setSplit([first, second])
            let secondSpace = store.createSpace(name: "Other")
            let third = store.open("https://three.example")
            let fourth = store.open("https://four.example")
            store.setSplit([third, fourth])
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            json.removeValue(forKey: "splitLayouts")
            json["splitWidthFactors"] = [2, 6]
            json["splitIsVertical"] = false
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let reopened = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            try expect(reopened.activeSpaceID == secondSpace && reopened.activeSplitLayout?.orientation == .horizontal,
                       "Legacy sessions must keep their actual previous side-by-side presentation")
            try expectFactors(reopened.activeSplitLayout?.widthFactors, [0.25, 0.75], "Legacy active weights must migrate into the active pane group")
            reopened.selectSpace(firstSpace)
            try expectFactors(reopened.activeSplitLayout?.widthFactors, [0.5, 0.5], "Older inactive split selections must migrate with equal sizes")
            try reopened.save()
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            try expect(saved["splitLayouts"] != nil && saved["splitWidthFactors"] == nil && saved["splitIsVertical"] == nil,
                       "A migrated save must replace unused globals with per-split records")
            let again = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            try expect(again.state == reopened.state, "Split migration must be idempotent")
        }
    }

    static func testLegacyStaleSplitSelectionMigration() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let originalSpace = store.activeSpaceID
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            let third = store.open("https://three.example")
            store.setSplit([first, second, third])
            let otherSpace = store.createSpace(name: "Other")
            store.moveTab(first, toSpace: otherSpace)
            store.closeTab(second)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            json.removeValue(forKey: "splitLayouts")
            json["splitWidthFactors"] = []
            json["splitIsVertical"] = false
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let reopened = try BrowserStore(directory: directory)
            reopened.selectSpace(originalSpace)
            try expect(reopened.state.selectedTabIDs == [third] && reopened.activeSplitLayout == nil,
                       "Legacy inactive selections containing moved or archived tabs must migrate without rejecting an otherwise valid session")
            try reopened.save()
            _ = try BrowserStore(directory: directory)
        }
    }

    static func testInvalidPersistedSplitsArePreserved() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            store.setSplit([first, second])
            try store.save()
            let good = store.state
            let base = good.splitLayouts[0]
            var cases: [[BrowserSplitLayout]] = []
            var invalid = base; invalid.widthFactors = [0, 1]; cases.append([invalid])
            invalid = base; invalid.widthFactors = [1]; cases.append([invalid])
            invalid = base; invalid.widthFactors = [2, 3]; cases.append([invalid])
            invalid = base; invalid.tabIDs = [first, first]; cases.append([invalid])
            invalid = base; invalid.tabIDs = [first, UUID()]; cases.append([invalid])
            invalid = base; invalid.spaceID = UUID(); cases.append([invalid])
            cases.append([base, base])
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let file = directory.appendingPathComponent("session.json")
            for layouts in cases {
                var damaged = good; damaged.splitLayouts = layouts
                let bytes = try encoder.encode(damaged)
                try bytes.write(to: file)
                var rejected = false
                do { _ = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) }) } catch { rejected = true }
                try expect(rejected, "Invalid saved split membership or geometry must reject the session")
                try expect(try Data(contentsOf: file) == bytes, "Rejecting a malformed split must preserve the session for recovery")
            }
        }
    }

    static func testTypedInternalEaselAddresses() throws {
        let id = UUID()
        let canonical = InternalPage.easel(id).urlString
        try expect(canonical == "parc://easel/" + id.uuidString.lowercased(), "Easel routes must use a canonical opaque document ID")
        try expect(InternalPage(urlString: canonical) == .easel(id), "The internal route must round-trip its typed identity")
        try expect(InternalPage.easel(id).sidebarFallbackSymbol == "square.on.square"
                   && InternalPage.note(id).sidebarFallbackSymbol == "note.text"
                   && InternalPage.sidebarFallbackSymbol(urlString: "https://example.org") == "globe",
                   "Easel and Note rows keep distinct still glyphs; web rows keep the globe fallback")
        for address in ["parc://easel/not-a-uuid", "parc://easel/" + id.uuidString + "/more",
                        canonical + "?profile=other", canonical + "#fragment", "parc://user@easel/" + id.uuidString,
                        "parc://easel:88/" + id.uuidString, "parc://other/" + id.uuidString,
                        "https://easel/" + id.uuidString] {
            try expect(InternalPage(urlString: address) == nil, "Internal document routes must reject unsupported components")
        }
        for address in [canonical, "PARC://easel/" + id.uuidString, "parc://easel/not-a-uuid"] {
            try expect(NavigationInput.resolve(address) == nil, "General navigation must never send an internal Parc address to a web engine or search provider")
        }
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let tabID = store.open("https://example.org")
            let before = store.state
            store.navigate(tabID, input: canonical)
            try expect(store.state == before, "A pasted internal route must not mutate a web tab through ordinary navigation")
        }
    }

    static func testEaselTabsAndSavedTitle() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let documentID = UUID()
            let profileID = store.activeSpace.profileID
            let originalSpace = store.activeSpaceID
            _ = store.open("https://already.example")
            let tabID = store.openEasel(id: documentID, title: "Research")!
            let created = try tab(tabID, in: store)
            try expect(created.kind == .today && created.title == "Research" && created.savedTitle == "Research",
                       "A new Easel is a Today tab with its saved title")
            try expect(SidebarHierarchy.children(in: .init(spaceID: originalSpace, folderID: nil, section: .today),
                                                 state: store.state).first == .tab(tabID),
                       "A new Easel enters at the top of Today")
            try expect(created.url == InternalPage.easel(documentID).urlString && created.savedURL == created.url,
                       "The Easel tab must save the typed internal destination")
            try expect(store.state.history.isEmpty, "Opening an Easel must not create a fabricated web history entry")
            store.createSpace(name: "Other")
            let again = store.openEasel(id: documentID, title: "Research")
            try expect(again == tabID && store.activeSpaceID == originalSpace && store.state.tabs.count == 2,
                       "Opening the same profile's Easel again must select its existing tab and Space")
            store.updateEaselTitle(id: documentID, profileID: profileID, title: "Renamed board")
            try expect(try tab(tabID, in: store).title == "Renamed board" && tab(tabID, in: store).savedTitle == "Renamed board",
                       "Document renaming must update both live and saved titles")
            store.setKind(tabID, .pinned)
            store.updateTab(tabID, title: "A web page", url: "https://example.org/reference")
            store.updateEaselTitle(id: documentID, profileID: profileID, title: "Latest board name")
            try expect(try tab(tabID, in: store).title == "A web page" && tab(tabID, in: store).savedTitle == "Latest board name",
                       "Renaming a saved Easel must not overwrite the title of a web page currently occupying that tab")
            store.closeTab(tabID)
            try expect(try tab(tabID, in: store).url == created.savedURL && tab(tabID, in: store).title == "Latest board name"
                       && tab(tabID, in: store).archivedAt == nil && tab(tabID, in: store).kind == .pinned,
                       "Closing a pinned Easel that navigated away resets to the saved document")
            store.closeTab(tabID)
            try expect(try tab(tabID, in: store).archivedAt == nil && tab(tabID, in: store).kind == .pinned
                       && tab(tabID, in: store).url == created.savedURL,
                       "Closing a pinned Easel that is showing the document unloads it in place, like a deselect")
            try expect(store.openEasel(id: documentID, title: "Latest board name") == tabID && (try tab(tabID, in: store)).kind == .pinned,
                       "Opening it again selects the same pinned tab")
            let folder = store.createFolder(name: "Boards")
            store.moveTab(tabID, toSpace: store.activeSpaceID, folderID: folder)
            try expect(try tab(tabID, in: store).folderID == folder && tab(tabID, in: store).kind == .pinned,
                       "An Easel can be pinned into a folder")
            store.closeTab(tabID)
            try expect(try tab(tabID, in: store).archivedAt == nil && tab(tabID, in: store).kind == .pinned
                       && tab(tabID, in: store).folderID == folder,
                       "Closing a folder-pinned Easel keeps it in its folder")
            store.setKind(tabID, .today)
            store.closeTab(tabID)
            try expect(try tab(tabID, in: store).archivedAt != nil, "Closing a Today Easel archives it")
            store.openEasel(id: documentID, title: "Latest board name")
            try expect(try tab(tabID, in: store).kind == .today && tab(tabID, in: store).archivedAt == nil,
                       "Library reopen restores the archived Easel as Today")
            let web = store.open("https://example.org/alongside")
            try savedSplit(store, [tabID, web], in: .init(spaceID: store.activeSpaceID, folderID: nil, section: .pinned))
            store.selectTab(tabID)
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2])
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            try expect(reopened.state == store.state, "A split containing a native Easel and real web tab must persist without a separate window model")
            reopened.closeTab(tabID)
            try expect(try tab(tabID, in: reopened).archivedAt == nil && tab(tabID, in: reopened).kind == .pinned,
                       "Closing a pinned Easel pane unloads it like any pinned tab")
            try expect(reopened.openEasel(id: documentID, title: "Latest board name") == tabID
                       && (try tab(tabID, in: reopened)).kind == .pinned,
                       "Opening it again selects its existing pinned tab")
        }
    }

    static func testEaselProfileDirectoriesAndIdentity() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let documentID = UUID()
            let firstProfile = store.activeSpace.profileID
            let firstID = store.openEasel(id: documentID, title: "Personal")!
            let firstPath = store.activeEaselsDirectory
            try expect(firstPath == URL(fileURLWithPath: store.profilePath(for: tab(firstID, in: store)), isDirectory: true).appendingPathComponent("Easels", isDirectory: true),
                       "Easel storage must live under the same explicit browser profile path")
            let secondSpace = store.createSpace(name: "Work")
            let secondProfile = store.createProfile(name: "Work")
            store.assignProfile(secondProfile, toSpace: secondSpace)
            let secondID = store.openEasel(id: documentID, title: "Work board")!
            try expect(firstID != secondID && store.activeEaselsDirectory != firstPath,
                       "Matching document UUIDs in distinct profiles must remain separate tabs and directories")
            try expect(store.activeEaselsDirectory == store.easelsDirectory(for: secondProfile),
                       "The active Easel directory must follow the active Space's profile")
            store.updateEaselTitle(id: documentID, profileID: secondProfile, title: "Changed work board")
            try expect(try tab(firstID, in: store).savedTitle == "Personal" && tab(secondID, in: store).savedTitle == "Changed work board",
                       "A document's title notification must not rename another profile's same-ID document")
            let before = store.state
            store.updateEaselTitle(id: documentID, profileID: firstProfile, title: "  ")
            try expect(store.state == before, "An empty native title must not erase the pinned destination name")
            try expect(!FileManager.default.fileExists(atPath: firstPath.path), "Path resolution and tab creation must not silently create or copy document files")
        }
    }

    static func testArchivePolicyIsProfileScoped() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstProfile = store.activeSpace.profileID
            let firstSpace = store.activeSpaceID
            try expect(store.autoArchiveInterval(for: firstProfile) == .twelveHours, "New profiles must use the 12-hour Today default")
            store.setAutoArchiveInterval(.twentyFourHours, for: firstProfile)
            let secondProfile = store.createProfile(name: "Second")
            store.assignProfile(secondProfile, toSpace: firstSpace)
            store.updateSettings { $0.sidebarWidth = 260; $0.searchEngine = "https://www.bing.com/search?q=" }
            try expect(store.autoArchiveInterval(for: secondProfile) == .twentyFourHours,
                       "A new Profile inherits the chosen shared default; assignment and unrelated preferences preserve it")
            try expect(store.autoArchiveInterval(for: firstProfile) == .twentyFourHours,
                       "Unrelated settings must preserve the original profile's policy too")
            let secondSpace = store.createSpace(name: "Shared profile")
            store.setAutoArchiveInterval(.sevenDays, for: secondProfile)
            store.selectSpace(firstSpace)
            try expect(store.autoArchiveInterval(for: store.activeSpace.profileID) == .sevenDays,
                       "All Spaces assigned to one profile must share its archive choice")
            store.assignProfile(firstProfile, toSpace: secondSpace)
            store.setAutoArchiveInterval(.thirtyDays, for: firstProfile)
            try expect(store.activeSpaceID == firstSpace && store.autoArchiveInterval(for: secondProfile) == .sevenDays,
                       "Updating an explicitly displayed profile must not depend on whichever Space became active")
            let expected = store.state
            try expect(!store.setAutoArchiveInterval(.never, for: UUID()) && store.state == expected,
                       "A stale or unknown profile target must not change another profile")
            try store.save()
            let reopened = try BrowserStore(directory: directory)
            try expect(reopened.state == expected, "Independent per-profile archive policies must survive restart")
        }
    }

    static func testLegacyArchivePolicyMirrorIsIgnored() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let profile = store.activeSpace.profileID
            store.setAutoArchiveInterval(.sixHours, for: profile)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var settings = json["settings"] as! [String: Any]
            settings["autoArchiveHours"] = 720
            json["settings"] = settings
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let reopened = try BrowserStore(directory: directory)
            try expect(reopened.autoArchiveInterval(for: profile) == .sixHours,
                       "Legacy profile policy must remain authoritative over a stale global mirror")
            reopened.updateSettings { $0.sidebarWidth = 280 }
            try expect(reopened.autoArchiveInterval(for: profile) == .sixHours,
                       "Changing general settings after migration must preserve a hidden older duration")
            try reopened.save()
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            try expect((saved["settings"] as! [String: Any])["autoArchiveHours"] == nil,
                       "New saves must remove the redundant global policy field")
            for interval in [AutoArchiveInterval.never, .oneHour, .sixHours] {
                reopened.setAutoArchiveInterval(interval, for: profile)
                try reopened.save()
                let again = try BrowserStore(directory: directory)
                try expect(again.autoArchiveInterval(for: profile) == interval,
                           "Older supported Parc values must round-trip without silently changing user preference")
            }
            try expect(AutoArchiveInterval.settingsChoices == [.twelveHours, .twentyFourHours, .sevenDays, .thirtyDays],
                       "Normal Settings choices must match the archive menu, excluding hidden and debug cases")
            try expect(AutoArchiveInterval.never.seconds == nil && AutoArchiveInterval.twentyFourHours.seconds == 86400,
                       "Never must be no threshold, and a day must be exactly 86400 seconds")
        }
    }

    static func testInvalidArchivePoliciesPreserveSession() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            for hours in [-1.0, 2.0, 20.0 / 3600, 999.0] {
                var state = store.state
                state.profiles[0].autoArchiveHours = hours
                let bytes = try encoder.encode(state)
                try bytes.write(to: file)
                var rejected = false
                do { _ = try BrowserStore(directory: directory) } catch { rejected = true }
                try expect(rejected, "Invalid or debug-only persisted policies must not become accidental Never or arbitrary timers")
                try expect(try Data(contentsOf: file) == bytes, "Rejecting an invalid archive policy must preserve the existing session file")
            }
        }
    }

    static func testArchiveStartMigrationAndStrictBoundary() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let old = store.open("https://old.example")
            let selected = store.open("https://selected.example")
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            json.removeValue(forKey: "autoArchiveStartedAt")
            var tabs = json["tabs"] as! [[String: Any]]
            for index in tabs.indices { tabs[index].removeValue(forKey: "isUnread") }
            json["tabs"] = tabs
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            now.addTimeInterval(100 * 86400)
            let migrated = try BrowserStore(directory: directory, now: { now })
            try expect(migrated.state.autoArchiveStartedAt == nil && migrated.state.tabs.allSatisfy { !$0.isUnread },
                       "Older Parc sessions must migrate absent start to unset and previously selected tabs to read")
            try expect(migrated.archiveExpiredTabs().isEmpty && migrated.state.autoArchiveStartedAt == now,
                       "The first archive run must initialize the global start gate without immediately closing old tabs")
            let started = now
            try migrated.save()
            now.addTimeInterval(12 * 3600)
            let reopened = try BrowserStore(directory: directory, now: { now })
            try expect(reopened.state.autoArchiveStartedAt == started, "Restart must preserve, not reset, the global archive start")
            try expect(reopened.archiveExpiredTabs().isEmpty, "The start gate uses strict greater-than, not equality")
            now.addTimeInterval(1)
            try expect(reopened.archiveExpiredTabs() == [old], "A read inactive tab older than both gates must expire after the boundary")
            try expect(try tab(selected, in: reopened).archivedAt == nil, "The existing selected-item exemption must remain intact")
            let startAfter = reopened.state.autoArchiveStartedAt
            reopened.refreshVisibleTabs([selected])
            reopened.archiveExpiredTabs()
            try expect(reopened.state.autoArchiveStartedAt == startAfter, "Activity and later sweeps must not reset the persisted start gate")
        }
    }

    static func testVisibleActivityPreventsImmediateArchive() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.setAutoArchiveInterval(.twentyFourHours, for: store.activeSpace.profileID)
            store.archiveExpiredTabs()
            let viewed = store.open("https://viewed.example")
            now.addTimeInterval(48 * 3600)
            store.refreshVisibleTabs([viewed, UUID()])
            let lastViewed = now
            let next = store.open("https://next.example")
            try expect(store.archiveExpiredTabs().isEmpty && (try tab(viewed, in: store)).lastAccessed == lastViewed,
                       "Periodic visible-page refresh must prevent a long-viewed page from expiring immediately after switching away")
            now.addTimeInterval(24 * 3600)
            try expect(store.archiveExpiredTabs().isEmpty, "A tab at exactly the configured inactivity threshold must remain")
            now.addTimeInterval(1)
            try expect(store.archiveExpiredTabs() == [viewed], "A formerly visible page must expire after a full interval without another refresh")
            store.restoreArchivedTab(viewed, destination: .previousSpace(fallbackSpaceID: nil))
            try expect(store.selectedTabID == viewed && (try tab(viewed, in: store)).lastAccessed == now,
                       "Restoring an automatically archived page must reset its activity and select it")
            store.selectTab(next)
            now.addTimeInterval(12 * 3600)
            try expect(store.archiveExpiredTabs().isEmpty, "A restored page must get a fresh full inactivity interval")
        }
    }

    static func testVisibleActivityPersistsWithoutPublishing() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let viewed = store.open("https://activity-only.example")
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }
            let revision = store.stateRevision
            now.addTimeInterval(60)
            store.refreshVisibleTabs([viewed])
            try expect(publications == 0 && store.stateRevision == revision,
                       "Activity-only lastAccessed stamps must not publish BrowserState or bump stateRevision")
            try expect((try tab(viewed, in: store)).lastAccessed == now,
                       "In-memory lastAccessed must still advance for archive eligibility")
            try store.save()
            let reopened = try BrowserStore(directory: directory, now: { now })
            try expect((try tab(viewed, in: reopened)).lastAccessed == now,
                       "Activity-only stamps must still persist into the session file")
            let afterPublish = publications
            now.addTimeInterval(1)
            store.selectTab(viewed)
            try expect(publications > afterPublish,
                       "A real selection publish must still emit after an activity-only stamp")
            try expect((try tab(viewed, in: store)).lastAccessed == now,
                       "Publishing after an activity overlay must keep the stamped access date")
        }
    }

    static func testBatchedMutationPublishesOnce() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 2_000_000_000) })
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }

            publications = 0
            let first = store.openResolvedURL(URL(string: "https://batch.example/a")!, kind: .today)
            try expect(publications == 1, "Opening a URL publishes once after append+place+select")
            try expect(store.state.selectedTabIDs == [first], "Open selects the new tab")

            publications = 0
            let second = store.openResolvedURL(URL(string: "https://batch.example/b")!, kind: .today)
            try expect(publications == 1, "A second open also publishes once")

            publications = 0
            store.setSplit([first, second])
            try expect(publications == 1, "Forming a split publishes once after activate+stamp")
            try expect(store.state.selectedTabIDs == [first, second] && store.activeSplitLayout?.tabIDs == [first, second],
                       "Split end state matches a single activation")

            publications = 0
            store.closeSplit()
            try expect(publications == 1, "Closing a split publishes once after dissolve+stamp")
            try expect(store.state.selectedTabIDs == [first] && store.activeSplitLayout == nil,
                       "Close-split end state keeps the focused pane alone")

            publications = 0
            let space = store.createSpace(name: "Batched")
            try expect(publications == 1, "Creating a Space publishes once after append+select")
            try expect(store.activeSpaceID == space, "Create selects the new Space")

            let other = store.openResolvedURL(URL(string: "https://batch.example/c")!, kind: .today)
            publications = 0
            store.removeTab(other)
            try expect(publications == 1, "Removing a tab publishes once after normalize+stamp")
            try expect(!store.state.tabs.contains { $0.id == other }, "Removed tab is gone from the model")
        }
    }

    static func testIdenticalStateAssignDoesNotPublish() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_100)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let id = store.open("https://identical-assign.example")
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }
            store.updateTab(id, title: "Once", url: "https://identical-assign.example/once")
            try expect(publications == 1, "Distinct metadata publishes once; changed() does not republish")
            let revision = store.stateRevision
            now.addTimeInterval(60)
            store.refreshVisibleTabs([id])
            try expect(publications == 1 && store.stateRevision == revision,
                       "Activity overlay must still avoid publish after an identical-assign gate")
            store.selectTab(id)
            try expect(publications == 1 && store.stateRevision == revision,
                       "Identical selectTab assign must not fan out @Published observers")
            try expect((try tab(id, in: store)).lastAccessed == now,
                       "Activity overlay must remain readable across identical assigns")
        }
    }

    static func testUnreadAndNativeProtectionGates() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let unread = store.open("https://unread.example")
            let protected = store.open("https://media-or-edit.example")
            let ordinary = store.open("https://ordinary.example")
            let selected = store.open("https://selected.example")
            var fixture = store.state
            fixture.tabs[fixture.tabs.firstIndex { $0.id == unread }!].isUnread = true
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(fixture).write(to: directory.appendingPathComponent("session.json"))
            now.addTimeInterval(13 * 3600)
            let loaded = try BrowserStore(directory: directory, now: { now })
            try expect(loaded.archiveExpiredTabs(protectedTabIDs: [protected]) == [ordinary],
                       "Unread pages, native-protected or unknown-content pages, and current selection must survive an otherwise eligible sweep")
            loaded.refreshVisibleTabs([unread])
            try expect(try tab(unread, in: loaded).isUnread, "The timer must not invent an unread-clear action; explicit selection owns it")
            loaded.selectTab(unread)
            try expect(!(try tab(unread, in: loaded).isUnread), "Selecting a page must clear persisted unread state")
            loaded.selectTab(selected)
            try loaded.save()
            let restored = try BrowserStore(directory: directory, now: { now })
            try expect(!(try tab(unread, in: restored).isUnread), "Read state must survive restart")
            now.addTimeInterval(12 * 3600 + 1)
            let expired = Set(restored.archiveExpiredTabs())
            try expect(expired == [unread, protected], "Read and formerly protected pages must become eligible once no protection remains and activity is old")
        }
    }

    static func testArchiveAcrossSpacesAndProfiles() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let firstSpace = store.activeSpaceID
            let short = store.open("https://short.example")
            let secondSpace = store.createSpace(name: "Day-long")
            let profile = store.createProfile(name: "Day-long")
            store.assignProfile(profile, toSpace: secondSpace)
            store.setAutoArchiveInterval(.twentyFourHours, for: profile)
            let long = store.open("https://long.example")
            _ = store.open("https://selected.example")
            now.addTimeInterval(13 * 3600)
            try expect(store.archiveExpiredTabs() == [short], "A background Space must expire by its own profile's shorter duration")
            try expect(store.state.selectionBySpace[firstSpace.uuidString]?.isEmpty == true,
                       "Automatic closure must remove stale remembered selection in inactive Spaces")
            try expect(try tab(long, in: store).archivedAt == nil, "A different profile's longer interval must remain independent")
            now.addTimeInterval(11 * 3600)
            try expect(store.archiveExpiredTabs().isEmpty, "The second profile's exact day boundary must be retained")
            now.addTimeInterval(1)
            try expect(store.archiveExpiredTabs() == [long], "The second profile must expire only beyond its own day threshold")
        }
    }

    static func testArchiveSavedSplitConstituents() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let first = store.open("https://first.example")
            let second = store.open("https://second.example")
            store.setSplit([first, second])
            _ = store.open("https://outside.example")
            now.addTimeInterval(13 * 3600)
            try expect(store.archiveExpiredTabs(protectedTabIDs: [second]).isEmpty,
                       "One protected constituent must keep the saved pane group from partial automatic closure")
            store.refreshVisibleTabs([second])
            try expect(store.archiveExpiredTabs().isEmpty, "A recently active constituent must preserve an otherwise old saved pane group")
            now.addTimeInterval(12 * 3600)
            try expect(store.archiveExpiredTabs().isEmpty, "Every constituent must be strictly older than the interval")
            now.addTimeInterval(1)
            try expect(Set(store.archiveExpiredTabs()) == [first, second], "An entirely inactive unprotected Today pane group must expire together")
            try expect(store.state.splitLayouts.isEmpty, "Expired pane groups must leave no dangling saved geometry")
        }
    }

    static func testArchiveTypedItemsAndMixedGroups() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let first = store.open("https://mixed-today.example")
            let second = store.open("https://mixed-pinned.example")
            store.setSplit([first, second])
            let note = store.openResolvedURL(URL(string: InternalPage.note(UUID()).urlString)!)
            let easel = store.openResolvedURL(URL(string: InternalPage.easel(UUID()).urlString)!)
            let malformed = store.openResolvedURL(URL(string: "parc://note/not-a-document")!)
            let folder = store.createFolder(name: "Saved")
            let nested = store.open("https://saved-child.example")
            store.moveTab(nested, toSpace: store.activeSpaceID, folderID: folder)
            let favorite = store.open("https://favorite.example", kind: .favorite)
            _ = store.open("https://current.example")
            store.moveTab(second, toSpace: store.activeSpaceID, folderID: folder)
            now.addTimeInterval(13 * 3600)
            try expect(store.state.splitLayouts.contains { $0.tabIDs == [first, second] },
                       "The original mixed split is retained by the model before eligibility")
            try expect(Set(store.archiveExpiredTabs()) == [note, easel],
                       "Eligible Note/Easel roots archive; structural/saved/malformed items and a mixed split remain whole")
            try expect([first, second, malformed, nested, favorite].allSatisfy { id in
                store.state.tabs.contains { $0.id == id && $0.archivedAt == nil }
            }, "Automatic archive cannot detach a Today pane from a retained saved sibling")
            try expect(store.state.splitLayouts.contains { $0.tabIDs == [first, second] },
                       "An excluded split keeps its original identity and geometry")
        }
    }

    static func testArchiveOriginalItemRevalidation() throws {
        for change in ["space", "document", "title"] {
            try withDirectory { directory in
                var now = Date(timeIntervalSince1970: 1_800_000_000)
                let store = try BrowserStore(directory: directory, now: { now })
                let source = store.activeSpaceID
                let destination = store.createSpace(name: "Destination")
                store.selectSpace(source)
                let original = store.open("https://original.example")
                _ = store.open("https://current.example")
                store.archiveExpiredTabs()
                now.addTimeInterval(13 * 3600)
                var request: (() -> Bool)?, finish: ((Bool) -> Void)?
                var result: [[UUID]] = []
                store.requestPageRetirement = { ids, validate, complete in
                    if ids == [original] { request = validate; finish = complete }
                }
                store.archiveExpiredTabs(protectedTabIDs: []) { result.append($0) }
                try expect(request != nil && result.isEmpty, "The original item waits for native retirement")
                switch change {
                case "space": store.moveTab(original, toSpace: destination)
                case "document": store.updateTab(original, url: "https://replacement.example")
                default: store.updateTab(original, title: "Updated page title")
                }
                let accepted = request?() == true
                try expect(accepted == (change == "title"),
                           "A changed original \(change) is distinguished from a metadata-only title refresh")
                finish?(accepted)
                finish?(accepted)
                try expect(result == [accepted ? [original] : []] && store.retiringTabIDs.isEmpty,
                           "Original-item revalidation completes once and releases its reservation")
                try expect(((try tab(original, in: store)).archivedAt != nil) == accepted,
                           "Only an unchanged original item follows accepted retirement into Archive")
            }
        }
    }

    static func testArchiveNoOpDoesNotWriteOrReset() throws {
        try withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let selected = store.open("https://selected.example")
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            let original = try Data(contentsOf: file)
            let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)
            try expect(store.archiveExpiredTabs().isEmpty, "No eligible tabs must produce no archived IDs")
            store.refreshVisibleTabs([selected])
            store.setAutoArchiveInterval(.twelveHours, for: store.activeSpace.profileID)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            try expect(attributes[.modificationDate] as? Date == oldDate && (try Data(contentsOf: file)) == original,
                       "No-op checks, identical activity timestamps and unchanged policies must not rewrite the session")
        }
    }

    static func testNativePageAdoption() throws {
        try withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let originalSpace = store.activeSpaceID
            let originalProfile = store.activeSpace.profileID
            let selected = store.open("https://example.org/source")
            let path = store.independentEngineProfilePath(for: originalProfile)
            let legacy = directory.appendingPathComponent("Profiles").appendingPathComponent(originalProfile.uuidString).path
            try expect(path == directory.appendingPathComponent("Chromium-v1").appendingPathComponent(originalProfile.uuidString).path,
                       "Each independent Profile must be an immediate child of its versioned engine root")
            try expect(URL(fileURLWithPath: path).deletingLastPathComponent() == store.independentEngineRoot,
                       "CEF must receive a direct child profile, not a nested path that silently becomes private")
            try expect(store.profileID(forEnginePath: legacy) == nil, "An unversioned profile path must be refused")
            try expect(store.profileID(forEnginePath: path + "/Private") == nil, "An unknown private context must not become a normal profile")
            let unknownState = store.state
            try expect(store.adoptNativePage(url: nil, title: "", profilePath: path + "/Other",
                                            preferredSpaceID: originalSpace, select: true) == nil,
                       "Unknown profile adoption must fail")
            try expect(store.state == unknownState, "Refused adoption must not mutate saved tabs or selection")

            let destination = URL(string: "chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html?x=1#tab")!
            guard let adopted = store.adoptNativePage(url: destination, title: "Extension options", profilePath: path,
                                                      preferredSpaceID: originalSpace, select: false) else {
                throw Failure(description: "A known profile could not adopt its extension page")
            }
            let page = try tab(adopted, in: store)
            try expect(page.url == destination.absoluteString && page.savedURL == destination.absoluteString,
                       "Native adoption must retain an actual engine URL without search resolution")
            try expect(page.title == "Extension options" && page.profileID == originalProfile && page.spaceID == originalSpace,
                       "Native page metadata must belong to its actual profile and compatible Space")
            try expect(store.selectedTabID == selected, "Background adoption must not steal selection")

            let secondSpace = store.createSpace(name: "Second")
            let secondProfile = store.createProfile(name: "Separate")
            store.assignProfile(secondProfile, toSpace: secondSpace)
            store.selectSpace(secondSpace)
            guard let popup = store.adoptNativePage(url: nil, title: "", profilePath: path,
                                                    preferredSpaceID: secondSpace, select: true) else {
                throw Failure(description: "The original profile could not adopt its popup after Space selection changed")
            }
            try expect(try tab(popup, in: store).profileID == originalProfile && store.activeSpaceID == originalSpace,
                       "An opener's profile must not be replaced by the currently selected different profile")
            try expect(store.selectedTabID == popup && (try tab(popup, in: store)).url == "about:blank",
                       "A not-yet-navigated popup must retain its existing blank page record")
            try store.save()
            let restored = try BrowserStore(directory: directory)
            try expect(try tab(adopted, in: restored) == page, "Adopted page metadata must survive session persistence")
        }
    }

    static func testCancelledNativeRetirement() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/form")
            let original = try tab(id, in: store)
            store.closeTab(id)
            let expected = try tab(id, in: store)
            try expect(store.restoreLiveTab(original, replacing: expected), "Cancelled native retirement must restore its exact saved record")
            try expect(try tab(id, in: store) == original && !store.state.recentlyClosedIDs.contains(id),
                       "A cancelled close must not leave its live page in Archive or Recently Closed")
            store.closeTab(id)
            let earlier = try tab(id, in: store)
            store.updateTab(id, title: "Newer edit")
            let edited = store.state
            try expect(!store.restoreLiveTab(original, replacing: earlier), "A stale cancellation must not overwrite later edits")
            try expect(store.state == edited, "Rejected rollback must preserve all newer state")
        }
    }

    static func testNativeRetirementPrecedesSavedMutations() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/unsaved-form")
            let original = try tab(id, in: store)
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, validate, callback in decisions.append((ids, { callback($0 && validate()) })) }
            store.closeTab(id)
            try expect(try tab(id, in: store) == original, "Requesting native close must leave the saved tab unchanged")
            try expect(store.retiringTabIDs == [id] && decisions.count == 1 && decisions[0].0 == [id],
                       "Retirement must identify exactly the page that needs approval")
            try store.save()
            let pending = try BrowserStore(directory: directory)
            try expect(try tab(id, in: pending).archivedAt == nil, "Saving during beforeunload must not persist an unapproved archive")
            decisions.removeFirst().1(false)
            try expect(try tab(id, in: store) == original && store.retiringTabIDs.isEmpty,
                       "Cancelling close must retain the record and clear pending retirement")

            store.closeTab(id)
            decisions.removeFirst().1(true)
            try expect(try tab(id, in: store).archivedAt != nil, "Accepted actual close may archive the saved Today tab")
            store.restoreArchivedTab(id, destination: .previousSpace(fallbackSpaceID: nil))
            store.removeTab(id)
            try expect(store.state.tabs.contains(where: { $0.id == id }), "Removing a record must also wait for native page approval")
            decisions.removeFirst().1(false)
            try expect(store.state.tabs.contains(where: { $0.id == id }), "Cancelling removal must preserve the saved page")

            let secondSpace = store.createSpace(name: "Other")
            let otherProfile = store.createProfile(name: "Other profile")
            store.assignProfile(otherProfile, toSpace: secondSpace)
            if !decisions.isEmpty { decisions.removeFirst().1(true) }
            store.moveTab(id, toSpace: secondSpace)
            try expect(try tab(id, in: store).profileID == original.profileID, "A profile-changing move must not retarget a live document before consent")
            decisions.removeFirst().1(false)
            try expect(try tab(id, in: store).spaceID == original.spaceID, "A cancelled profile-changing move must retain the source Space")

            store.assignProfile(otherProfile, toSpace: original.spaceID)
            try expect(store.state.spaces.first(where: { $0.id == original.spaceID })?.profileID == original.profileID,
                       "Space profile reassignment must wait before changing its profile")
            decisions.removeFirst().1(true)
            try expect(try tab(id, in: store).profileID == otherProfile,
                       "Accepted profile retirement may update saved page ownership")
        }
    }

    static func testRetirementCommitBoundary() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/approval-boundary")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            var results: [Bool] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            store.closeTabs([id]) { results.append($0) }
            requests[0].1(true)
            try expect(results == [false] && (try tab(id, in: store)).archivedAt == nil,
                       "A native completion that skips pre-unload validation must not mutate saved pages")
            try expect(!requests[0].0(), "Completed retirement validators must never authorize later unload")

            store.closeTabs([id]) { results.append($0) }
            try expect(requests[1].0(), "Current retirement must validate immediately before actual unload")
            try expect(!requests[1].0(), "Pre-unload approval must be single-use")
            try expect((try tab(id, in: store)).archivedAt == nil && results == [false],
                       "Validation alone is not evidence that the native page was destroyed")
            store.closeTabs([id]) { results.append($0) }
            try expect(requests.count == 2 && results == [false, false],
                       "A second close must not supersede a transaction already unloading its actual page")
            requests[1].1(true)
            try expect(results == [false, false, true] && (try tab(id, in: store)).archivedAt != nil,
                       "The validated transaction commits after the real close completion")
            requests[1].1(false)
            requests[1].1(true)
            try expect(results == [false, false, true] && store.retiringTabIDs.isEmpty,
                       "Repeated native replies must not repeat model publication or completion")
        }
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/replaced-close")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            var results: [Bool] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            store.closeTabs([id]) { results.append($0) }
            store.removeTab(id)
            try expect(!requests[0].0(), "A superseded preflight must refuse before unloading the page")
            requests[0].1(false)
            try expect(store.retiringTabIDs == [id] && results == [false],
                       "A stale refusal must preserve the newer retirement reservation")
            try expect(requests[1].0(), "The replacement operation must retain its own approval")
            requests[1].1(true)
            try expect(!store.state.tabs.contains { $0.id == id } && store.retiringTabIDs.isEmpty,
                       "Only the current approved operation may remove the page record")
        }
    }

    static func testArchiveValidationPrecedesAnyUnload() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let first = store.open("https://example.org/first-old-page")
            let second = store.open("https://example.org/second-old-page")
            let selected = store.open("https://example.org/current-page")
            _ = store.archiveExpiredTabs()
            now.addTimeInterval(13 * 60 * 60)
            var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
            var results: [[UUID]] = []
            var currentProtection = Set<UUID>()
            var unloads = 0
            store.requestPageRetirement = { ids, validate, completion in requests.append((ids, validate, completion)) }
            store.archiveExpiredTabs(protectedTabIDs: [], currentProtection: { currentProtection }) { results.append($0) }
            try expect(requests[0].0.isSuperset(of: [first, second]), "The native archive preflight must cover both overdue pages")
            currentProtection.insert(first)
            let permitted = requests[0].1()
            if permitted { unloads += requests[0].0.count }
            requests[0].2(permitted)
            try expect(!permitted && unloads == 0 && results == [[]],
                       "Protection added in another window must cancel the whole group before any native unload")
            try expect([first, second].allSatisfy { id in store.state.tabs.contains { $0.id == id && $0.archivedAt == nil } },
                       "A cancelled archive group must preserve every saved live page")

            currentProtection.removeAll()
            store.archiveExpiredTabs(protectedTabIDs: []) { results.append($0) }
            store.selectTab(first)
            try expect(!requests[1].1(), "Selecting an overdue tab while consent is pending must refuse before unload")
            requests[1].2(false)
            try expect(results == [[], []] && (try tab(second, in: store)).archivedAt == nil,
                       "Selecting one member cancels the complete automatic archive transaction")
            store.selectTab(selected)
            now.addTimeInterval(13 * 60 * 60)
            store.archiveExpiredTabs(protectedTabIDs: []) { results.append($0) }
            _ = store.setAutoArchiveInterval(.thirtyDays, for: store.activeSpace.profileID)
            try expect(!requests[2].1(), "Changing archive policy during approval must preserve actual pages")
            requests[2].2(false)
            try expect(results == [[], [], []] && store.retiringTabIDs.isEmpty,
                       "Policy cancellation must finish once and clear reservations")

            _ = store.setAutoArchiveInterval(.twelveHours, for: store.activeSpace.profileID)
            var replaceDuringValidation = false
            store.archiveExpiredTabs(protectedTabIDs: [], currentProtection: {
                if replaceDuringValidation {
                    replaceDuringValidation = false
                    store.closeTab(first)
                }
                return []
            }) { results.append($0) }
            replaceDuringValidation = true
            try expect(!requests[3].1() && requests.count == 5,
                       "Native protection callback reentry must invalidate an older transaction before unload")
            requests[3].2(false)
            try expect(store.retiringTabIDs == [first] && results.count == 4,
                       "Reentrant replacement must keep its own page reservation when the archive is cancelled")
            try expect(requests[4].1(), "The reentrant close retains its own pre-unload validation")
            requests[4].2(true)
            try expect((try tab(first, in: store)).archivedAt != nil && (try tab(second, in: store)).archivedAt == nil,
                       "Only the replacement manual close may retire a page after cancelling the older group")
        }
    }

    static func testProfileChangePreflightRevalidation() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/original-profile")
            let originalProfile = store.activeSpace.profileID
            let spaceID = store.activeSpaceID
            let otherProfile = store.createProfile(name: "Second profile")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            store.assignProfile(otherProfile, toSpace: spaceID)
            let added = store.open("https://example.org/created-during-consent")
            try expect(!requests[0].0(), "A newly created page must invalidate the profile-wide preflight before any page unloads")
            requests[0].1(false)
            try expect(store.activeSpace.profileID == originalProfile && [id, added].allSatisfy { id in
                store.state.tabs.contains { $0.id == id && $0.profileID == originalProfile && $0.archivedAt == nil }
            }, "Cancelled reassignment must preserve all original page ownership")

            let destination = store.createSpace(name: "Destination")
            store.assignProfile(otherProfile, toSpace: destination)
            let folder = store.createFolder(name: "Destination folder")
            store.moveTab(id, toSpace: destination, folderID: folder)
            let moveRequest = requests.last!
            let deletion = FolderRemovalTarget(folderID: folder, spaceID: destination, profileID: store.activeSpace.profileID, state: store.state)!
            store.deleteFolder(deletion, shouldCommit: { true }) { _ in }
            try expect(!moveRequest.0(), "A removed move destination must be rejected before native page unload")
            moveRequest.1(false)
            try expect((try tab(id, in: store)).spaceID == spaceID && (try tab(id, in: store)).profileID == originalProfile,
                       "Invalid move destination must preserve the original page and profile")
        }
    }

    static func testWindowCommandContext() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let firstSpace = store.activeSpaceID
            let first = store.open("https://example.org/window-one")
            let cached = store.open("https://example.org/cached-other-window")
            let cachedBefore = try tab(cached, in: store)
            let secondSpace = store.createSpace(name: "Second window")
            let other = store.open("https://example.org/window-two")
            var snapshots: [BrowserState] = []
            let subscription = store.statePublisher.sink { snapshots.append($0) }
            defer { subscription.cancel() }
            now.addTimeInterval(60)
            try expect(store.setWindowPresentation(spaceID: firstSpace, selectedTabIDs: [first, first, other, UUID()]),
                       "A known window Space must provide its command context")
            try expect(store.selectedTabID == first && store.state.selectedTabIDs == [first],
                       "Window context must deduplicate and exclude pages outside its Space")
            try expect(try tab(cached, in: store) == cachedBefore,
                       "Switching window context must not stamp another window's cached selection")
            try expect(try tab(first, in: store).lastAccessed == now,
                       "Only the initiating window's supplied selection gets an activity stamp")
            try expect(snapshots.dropFirst().allSatisfy { $0.activeSpaceID == firstSpace && $0.selectedTabIDs == [first] },
                       "Window context publication must keep Space and page selection consistent")
            try expect(store.state.selectionBySpace[secondSpace.uuidString] == [other],
                       "Switching command context must retain the outgoing saved selection")
            store.setWindowPresentation(spaceID: firstSpace, selectedTabIDs: [])
            try expect(store.state.selectedTabIDs.isEmpty,
                       "An intentionally empty native window must not restore a cached fallback page")
            let before = store.state
            try expect(!store.setWindowPresentation(spaceID: UUID(), selectedTabIDs: [first]) && store.state == before,
                       "An invalid window Space must leave the model unchanged")
        }
    }

    static func testGroupedNativeClose() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://example.org/first-form")
            let second = store.open("https://example.org/second-form")
            let survivor = store.open("https://example.org/keep")
            store.selectTab(first)
            let ids: Set<UUID> = [first, second]
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            var results: [Bool] = []
            var snapshots: [BrowserState] = []
            let subscription = store.statePublisher.sink { snapshots.append($0) }
            defer { subscription.cancel() }
            store.requestPageRetirement = { requested, validate, callback in decisions.append((requested, { callback($0 && validate()) })) }
            store.closeTabs(ids) { results.append($0) }
            try expect(decisions.count == 1 && decisions[0].0 == ids && store.retiringTabIDs == ids,
                       "Grouped close must reserve all records in one native retirement request")
            try expect(results.isEmpty && ids.allSatisfy { id in store.state.tabs.contains { $0.id == id && $0.archivedAt == nil } },
                       "No group member may archive before the aggregate decision")
            try store.save()
            let pending = try BrowserStore(directory: directory)
            try expect(ids.allSatisfy { id in pending.state.tabs.contains { $0.id == id && $0.archivedAt == nil } },
                       "Saving a pending group must retain every page")
            decisions.removeFirst().1(false)
            try expect(results == [false] && store.retiringTabIDs.isEmpty && snapshots.count == 1,
                       "A refused group must report once and publish no partial closure")
            store.closeTabs(ids) { results.append($0) }
            decisions.removeFirst().1(true)
            try expect(results == [false, true] && store.retiringTabIDs.isEmpty,
                       "An approved group must finish only after the native aggregate result")
            try expect(ids.allSatisfy { id in store.state.tabs.contains { $0.id == id && $0.archivedAt != nil } },
                       "Approved group must archive every requested Today tab")
            try expect(snapshots.dropFirst().allSatisfy { snapshot in
                ids.allSatisfy { id in snapshot.tabs.contains { $0.id == id && $0.archivedAt != nil } }
            }, "Subscribers must never observe one group member closed and another still live")
            try expect(store.selectedTabID == survivor && store.state.recentlyClosedIDs.suffix(2) == [first, second],
                       "Grouped fallback must exclude all retired pages and preserve close history order")
            store.closeTabs([]) { results.append($0) }
            try expect(results == [false, true, true] && decisions.isEmpty,
                       "An empty group succeeds without requesting native retirement")
        }
    }

    static func testNativeArchiveConsentAndRevalidation() throws {
        try withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.open("https://example.org/old-form")
            _ = store.open("https://example.org/selected")
            _ = store.archiveExpiredTabs()
            now.addTimeInterval(13 * 60 * 60)
            var decisions: [(Bool) -> Void] = []
            var results: [[UUID]] = []
            store.requestPageRetirement = { _, validate, completion in decisions.append { completion($0 && validate()) } }
            store.archiveExpiredTabs(protectedTabIDs: []) { results.append($0) }
            try expect(try tab(id, in: store).archivedAt == nil && results.isEmpty,
                       "Automatic archive must wait for the live page's result")
            decisions.removeFirst()(false)
            try expect(results == [[]] && (try tab(id, in: store)).archivedAt == nil,
                       "Cancelled automatic retirement must report no archive and retain the tab")
            store.archiveExpiredTabs(protectedTabIDs: []) { results.append($0) }
            store.selectTab(id)
            decisions.removeFirst()(true)
            try expect(results.last == [] && (try tab(id, in: store)).archivedAt == nil,
                       "A tab selected during consent must be revalidated and remain unarchived")
        }
    }

    static func testTypedSplitDropTransactions() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            let third = store.open("https://three.example")
            let fourth = store.open("https://four.example")
            store.selectTab(first)
            let originalTab = try tab(second, in: store)
            let before = store.state
            try expect(!store.dropTabIntoSplit(second, expectedSelection: [third], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal), "Stale destination selection must reject atomically")
            try expect(store.state == before, "Refusal must not mutate any tab or group")
            try expect(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]), "Sidebar identity must join the original selected page")
            let group = store.activeSplitLayout!
            try expect(group.tabIDs == [first, second] && group.sidebarAnchorID == second,
                "New split keeps ordered children and the original ordinary sidebar anchor")
            let afterTab = try tab(second, in: store)
            try expect(afterTab.url == originalTab.url && afterTab.savedURL == originalTab.savedURL
                && afterTab.kind == originalTab.kind && afterTab.folderID == originalTab.folderID,
                "Joining a split must preserve original child destination and placement")
            store.selectTab(third)
            store.setSplit([third, fourth])
            let other = store.activeSplitLayout!
            store.selectTab(second)
            try expect(store.activeSplitLayout == group && store.state.selectedTabIDs == [first, second],
                "Selecting a child activates its whole typed container")
            try expect(store.dropTabIntoSplit(third, expectedSelection: [first, second], expectedLayout: group,
                target: .insert(1), orientation: .horizontal), "Move an original child from a second group")
            let expanded = store.activeSplitLayout!
            try expect(expanded.id == group.id && expanded.tabIDs == [first, third, second],
                "Insertion retains destination container identity")
            try expect(!store.state.splitLayouts.contains(where: { $0.id == other.id }),
                "The one-child source container dissolves while its surviving tab stays alive")
            try expect(try tab(fourth, in: store).archivedAt == nil, "Source survivor must remain alive")
            let unchanged = store.state
            try expect(!store.dropTabIntoSplit(second, expectedSelection: expanded.tabIDs, expectedLayout: expanded,
                target: .insert(0), orientation: .horizontal), "A member is not a drop source; members reorder through pane Move")
            try expect(store.state == unchanged, "A refused member drop publishes nothing")
            try expect(store.dropTabIntoSplit(fourth, expectedSelection: expanded.tabIDs, expectedLayout: expanded,
                target: .replace(1), orientation: .horizontal), "Typed replacement uses the original tab")
            let replaced = store.activeSplitLayout!
            try expect(replaced.tabIDs == [first, fourth, second] && replaced.id == group.id,
                "Replacement retains destination geometry and identity")
            try expect(try tab(third, in: store).archivedAt == nil, "Displaced page is preserved, not closed")
            try expect(store.separateTabFromSplit(first, expected: replaced), "Explicit child separation succeeds")
            try expect(store.activeSplitLayout?.tabIDs == [fourth, second], "Separation preserves the other original panes")
            try expect(!store.separateTabFromSplit(second, expected: replaced), "A stale group token cannot separate newer state")
            let remaining = store.activeSplitLayout!
            try store.save()
            let restored = try BrowserStore(directory: directory)
            try expect(restored.activeSplitLayout == remaining, "Group identity, ordering, anchor and geometry persist")
            let projected = SidebarSplitItems.groups(in: restored.state, spaceID: restored.activeSpaceID)
            try expect(projected.map(\.id) == [remaining.id], "Sidebar projection emits each typed group exactly once")
            try expect(Set(projected.flatMap(\.tabIDs)).count == projected.flatMap(\.tabIDs).count,
                "A Space cannot assign one tab to two sidebar containers")
            let snapshot = restored.state
            try expect(!restored.dropTabIntoSplit(UUID(), expectedSelection: remaining.tabIDs, expectedLayout: remaining,
                target: .insert(0), orientation: .vertical), "Unknown source identity cannot create a placeholder")
            try expect(restored.state == snapshot, "Unknown source refusal preserves exact state")
            try expect(SplitDropTransaction.make(source: third, selection: remaining.tabIDs, layout: remaining,
                target: .insert(99), orientation: .horizontal, spaceID: restored.activeSpaceID) == nil,
                "Out of range drop targets reject")
            try expect(SplitDropTransaction.make(source: second, selection: remaining.tabIDs, layout: remaining,
                target: .insert(0), orientation: .horizontal, spaceID: restored.activeSpaceID) == nil,
                "A member cannot be dropped into its own group")
            var invalid = remaining; invalid.widthFactors = []
            try expect(SplitDropTransaction.make(source: third, selection: remaining.tabIDs, layout: invalid,
                target: .insert(0), orientation: .horizontal, spaceID: restored.activeSpaceID) == nil,
                "Malformed geometry cannot index outside the original layout")
            let file = directory.appendingPathComponent("session.json")
            var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var layouts = legacy["splitLayouts"] as! [[String: Any]]
            layouts[0].removeValue(forKey: "id"); layouts[0].removeValue(forKey: "sidebarAnchorID")
            var overlap = layouts[0]
            overlap["tabIDs"] = [first.uuidString, second.uuidString]
            overlap["widthFactors"] = [0.5, 0.5]
            layouts.insert(overlap, at: 0); legacy["splitLayouts"] = layouts
            try JSONSerialization.data(withJSONObject: legacy).write(to: file)
            let migrated = try BrowserStore(directory: directory)
            try expect(migrated.state.splitLayouts.count == 1 && migrated.activeSplitLayout?.tabIDs == remaining.tabIDs,
                "Active typed group wins legacy overlapping layout cache membership")
            let migratedID = migrated.activeSplitLayout?.id
            let secondRead = try BrowserStore(directory: directory)
            try expect(secondRead.activeSplitLayout?.id == migratedID,
                "Legacy group identity migration is saved immediately and stable across rereads")
        }
    }

    static func testSidebarMultiSelection() throws {
        let a = SidebarItemReference.tab(UUID()), b = SidebarItemReference.tab(UUID())
        let c = SidebarItemReference.folder(UUID()), d = SidebarItemReference.split(UUID())
        let order = [a, b, c, d]
        var selection = SidebarItemSelection()
        selection.select(c, order: order, active: a, extending: false, toggling: true)
        try expect(selection.items == [a, c], "Command selection retains active item without activating the target")
        selection.select(d, order: order, active: a, extending: true, toggling: false)
        try expect(selection.items == [a, c, d], "Shift range uses the stable original-item anchor and retains active item")
        selection.select(b, order: order, active: a, extending: true, toggling: false)
        try expect(selection.items == [a, b, c], "Reversing range shrinks around the same anchor")
        selection.select(a, order: order, active: a, extending: false, toggling: true)
        try expect(selection.items == [a, b, c], "Active item remains in a multi-selection")
        selection.reconcile(order: [a, d])
        try expect(selection.items.isEmpty && selection.focus == a, "Removed or collapsed rows cannot retain a hidden multi-selection")
        selection.clear()
        selection.select(b, order: order, active: a, extending: true, toggling: false)
        try expect(selection.items == [a, b], "First range starts at current active item")
        selection.select(b, order: order, active: a, extending: false, toggling: true)
        try expect(selection.items.isEmpty, "Returning to active singleton exits multi-selection")
        selection.select(.tab(UUID()), order: order, active: a, extending: true, toggling: false)
        try expect(selection.items.isEmpty, "Stale target IDs cannot enter selection")
        selection.clear()
        selection.select(b, order: order, active: .tab(UUID()), extending: false, toggling: true)
        try expect(selection.items.isEmpty && selection.singleItem == b, "An off-outline active page yields genuine singleton activation, never an invisible grant")
        selection.select(a, order: order, active: b, extending: false, toggling: true)
        try expect(selection.items == [a, b] && selection.singleItem == nil, "The next modifier press forms the original native multi-set")
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example", kind: .pinned)
            let third = store.open("https://three.example", kind: .pinned)
            let parent = store.createFolder(name: "Parent")
            let nested = store.createFolder(name: "Nested", parentID: parent)
            let target = store.createFolder(name: "Target")
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let destination = SidebarContainerLocation(spaceID: space, folderID: target, section: .pinned)
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            let original = store.state
            try expect(try store.moveSidebarItems([.tab(first), .tab(third)], to: destination, before: nil, expected: snapshot()), "Batch moves every original target in one transaction")
            try expect(publications == 1, "Bulk move publishes exactly once")
            try expect(SidebarHierarchy.children(in: destination, state: store.state) == [.tab(first), .tab(third)], "Original selection order is retained")
            try expect(store.state.selectedTabIDs == original.selectedTabIDs && store.state.history == original.history, "Bulk movement does not change page selection/history")
            try expect(try tab(first, in: store).url == tab(first, in: BrowserStore(directory: directory)).url, "Persisted originals retain their URLs")
            let stale = snapshot(); store.toggleFolder(parent)
            let unchanged = store.state
            try expect(!(try store.moveSidebarItems([.tab(first), .tab(second)], to: root, before: nil, expected: stale)), "Stale hierarchy rejects the whole batch")
            try expect(store.state == unchanged, "Stale batch leaves every item untouched")
            try expect(!(try store.moveSidebarItems([.tab(first), .folder(parent)], to: .init(spaceID: space, folderID: nested, section: .pinned), before: nil, expected: snapshot())), "A later cycle rejects the whole proposed batch")
            try expect(store.state == unchanged, "Earlier proposal steps never leak on later refusal")
            try expect(SidebarHierarchy.roots([.folder(parent), .folder(nested)], state: store.state, spaceID: space) == [.folder(parent)], "Selected ancestor owns a selected descendant once")
            try expect(!(try store.moveSidebarItems([.tab(second), .tab(second)], to: destination, before: nil, expected: snapshot())), "Duplicate original IDs reject")
            try expect(!(try store.moveSidebarItems([.tab(first), .tab(third)], to: destination, before: .tab(third), expected: snapshot())), "Selection-relative destination cannot consume one of its own source rows")
            store.selectTab(first); store.selectTab(third, extendingSplit: true)
            let split = store.activeSplitLayout!
            let beforeSplit = store.state
            try expect(try store.moveSidebarItems([.split(split.id), .folder(parent), .folder(nested)], to: root, before: .tab(second), expected: snapshot()), "Whole splits and normalized subtrees move together")
            try expect(store.state.splitLayouts == beforeSplit.splitLayouts && store.state.selectedTabIDs == beforeSplit.selectedTabIDs, "Split identity, geometry and original page focus survive")
            try expect(SidebarHierarchy.children(in: root, state: store.state).prefix(3) == [.split(split.id), .folder(parent), .tab(second)], "Mixed bulk insertion uses the exact typed target order")
            let stable = store.state, expected = snapshot(), file = directory.appendingPathComponent("session.json"), backup = directory.appendingPathComponent("backup.json")
            try FileManager.default.moveItem(at: file, to: backup); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            var failed = false
            do { _ = try store.moveSidebarItems([.split(split.id), .tab(second)], to: destination, before: nil, expected: expected) } catch { failed = true }
            try expect(failed && store.state == stable, "Disk failure preserves every original item and selection")
            try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
            observation.cancel()
        }
    }

    static func testFolderDuplication() throws {
        try withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let parent = store.createFolder(name: "Research")
            let nested = store.createFolder(name: "Articles", parentID: parent)
            let empty = store.createFolder(name: "Empty", parentID: nested)
            let first = store.open("https://example.org/saved", kind: .pinned)
            let splitA = store.open("https://example.org/a")
            let splitB = store.open("https://example.org/b")
            store.moveTab(first, toSpace: space, folderID: parent)
            try savedSplit(store, [splitA, splitB], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(splitA)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.3, 0.7])
            let group = store.activeSplitLayout!
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let inside = SidebarContainerLocation(spaceID: space, folderID: parent, section: .pinned)
            let snap = SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!
            _ = try store.moveSidebarItem(.folder(nested), to: inside, before: .tab(first), expected: snap)
            store.toggleFolder(nested)
            store.updateTab(first, title: "Live title", url: "https://example.org/current")
            let original = store.state
            let target = FolderDuplicateTarget(folderID: parent, spaceID: space, profileID: profile, state: original)!
            let urls = Dictionary(uniqueKeysWithValues: target.tabs.map { ($0.id, $0.id == first ? "https://example.org/live-at-command" : $0.savedURL) })
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            let copy = try store.duplicateFolder(target, destinations: urls)!
            try expect(publications == 1, "Whole duplicate tree publishes once after its save")
            try expect(copy.folderID != parent && Set(copy.tabIDs).isDisjoint(with: Set(target.tabs.map(\.id))), "Copies receive fresh identities")
            try expect(original.tabs.allSatisfy { value in store.state.tabs.contains(value) }, "Original saved tabs remain byte-for-byte values")
            try expect(original.folders.allSatisfy { store.state.folders.contains($0) } && store.state.splitLayouts.contains(group), "Original folder and split identity/geometry remain intact")
            try expect(store.state.selectedTabIDs == original.selectedTabIDs && store.state.activeSpaceID == original.activeSpaceID, "Copy leaves active original page selection unchanged")
            try expect(store.state.history == original.history && store.state.downloads == original.downloads, "Duplication does not fabricate browsing/download history")
            let copiedParent = store.state.folders.first { $0.id == copy.folderID }!
            let copiedNested = store.state.folders.first { $0.parentID == copy.folderID }!
            let copiedEmpty = store.state.folders.first { $0.parentID == copiedNested.id }!
            try expect(copiedParent.name == "Research" && copiedNested.name == "Articles" && copiedEmpty.name == "Empty", "Nested and empty folder names survive without an invented suffix")
            try expect(copiedNested.isExpanded == original.folders.first { $0.id == nested }!.isExpanded, "Collapsed descendant contents and disclosure survive")
            let newTabs = copy.tabIDs.compactMap { id in store.state.tabs.first { $0.id == id } }
            let currentCopy = newTabs.first { $0.folderID == copy.folderID }!
            try expect(currentCopy.url == urls[first] && currentCopy.savedURL == urls[first], "Resolved original page destination becomes the copied saved destination")
            try expect(currentCopy.savedTitle == target.tabs.first { $0.id == first }!.savedTitle, "Saved title is distinct from current page title")
            try expect(newTabs.allSatisfy { $0.profileID == profile && $0.spaceID == space && $0.kind == .pinned && $0.createdAt == date && $0.archivedAt == nil }, "New saved records keep exact Profile/Space and fresh lifecycle metadata")
            let copiedGroup = store.state.splitLayouts.first { $0.id != group.id && Set($0.tabIDs).isSubset(of: Set(copy.tabIDs)) }!
            try expect(copiedGroup.orientation == group.orientation && copiedGroup.widthFactors == group.widthFactors, "Copied split preserves orientation and widths")
            try expect(copiedGroup.sidebarAnchorID == copiedGroup.tabIDs[group.tabIDs.firstIndex(of: group.sidebarAnchorID!)!], "Split anchor maps to the corresponding new child")
            try expect(copy.openTabIDs == copiedGroup.tabIDs && !copy.openTabIDs.contains(currentCopy.id), "Only copied split descendants request background page creation")
            let copiedInside = SidebarContainerLocation(spaceID: space, folderID: copy.folderID, section: .pinned)
            try expect(SidebarHierarchy.children(in: copiedInside, state: store.state) == [.folder(copiedNested.id), .tab(currentCopy.id)], "Mixed folder/tab sibling order survives recursion")
            let siblingRows = SidebarHierarchy.children(in: root, state: store.state)
            try expect(siblingRows.firstIndex(of: .folder(copy.folderID)) == siblingRows.firstIndex(of: .folder(parent))!.advanced(by: 1), "Parc inserts the new root adjacent to its original")
            let loaded = try BrowserStore(directory: directory).state
            try expect(loaded.tabs == store.state.tabs && loaded.folders == store.state.folders
                && loaded.sidebarItemOrder == store.state.sidebarItemOrder
                && Dictionary(uniqueKeysWithValues: loaded.splitLayouts.map { ($0.id, $0) }) == Dictionary(uniqueKeysWithValues: store.state.splitLayouts.map { ($0.id, $0) }),
                "Entire tree and order survive durable model reload; active-group cache ordering is independent")
            let stable = store.state
            try expect(try store.duplicateFolder(target, destinations: urls) == nil, "An old folder capability cannot duplicate after hierarchy changes")
            try expect(store.state == stable, "Stale command has no partial effects")
            let fresh = FolderDuplicateTarget(folderID: parent, spaceID: space, profileID: profile, state: store.state)!
            try expect(try store.duplicateFolder(fresh, destinations: [:]) == nil, "Partial destination set refuses the whole command")
            var wrong = urls; wrong[UUID()] = "https://foreign.example"
            try expect(try store.duplicateFolder(fresh, destinations: wrong) == nil, "Foreign extra destination cannot enter a copy")
            wrong = urls; wrong[first] = "parc://easel/" + UUID().uuidString
            try expect(try store.duplicateFolder(fresh, destinations: wrong) == nil, "Typed Easel document is not duplicated as a second same-document URL")
            try expect(FolderDuplicateTarget(folderID: parent, spaceID: space, profileID: UUID(), state: store.state) == nil, "Foreign Profile cannot acquire folder command")
            var retirementReply: ((Bool) -> Void)?
            store.requestPageRetirement = { _, _, completion in retirementReply = completion }
            store.closeTabs([first]) { _ in }
            try expect(store.retiringTabIDs.contains(first) && (try store.duplicateFolder(fresh, destinations: urls)) == nil,
                "A source waiting for genuine retirement consent cannot be duplicated")
            retirementReply?(false)
            try expect(store.state == stable && store.retiringTabIDs.isEmpty,
                "Refused retirement preserves originals and releases the duplicate guard")
            store.requestPageRetirement = nil
            var corrupt = store.state
            let index = corrupt.folders.firstIndex { $0.id == parent }!
            corrupt.folders[index].parentID = empty
            try expect(FolderDuplicateTarget(folderID: parent, spaceID: space, profileID: profile, state: corrupt) == nil, "Corrupt cycles fail before recursion")
            corrupt = store.state
            corrupt.splitLayouts[0].tabIDs.append(first)
            try expect(FolderDuplicateTarget(folderID: parent, spaceID: space, profileID: profile, state: corrupt) == nil, "Split crossing nested containers refuses instead of flattening")
            let file = directory.appendingPathComponent("session.json"), backup = directory.appendingPathComponent("backup.json")
            try FileManager.default.moveItem(at: file, to: backup)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            var failed = false
            do { _ = try store.duplicateFolder(fresh, destinations: urls) } catch { failed = true }
            try expect(failed && store.state == stable && publications == 1, "Disk refusal leaves all original/new IDs and publication untouched")
            try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
            observation.cancel()
            let emptyTarget = FolderDuplicateTarget(folderID: empty, spaceID: space, profileID: profile, state: store.state)!
            let emptyCopy = try store.duplicateFolder(emptyTarget, destinations: [:])!
            try expect(emptyCopy.tabIDs.isEmpty && emptyCopy.openTabIDs.isEmpty, "Empty folder copy is real without creating a placeholder page")
        }
    }

    static func testSidebarSelectionCommands() throws {
        let a = SidebarItemReference.tab(UUID()), b = SidebarItemReference.folder(UUID()), c = SidebarItemReference.split(UUID())
        var selection = SidebarItemSelection()
        selection.selectAll(order: [a, b, c, a], active: c)
        try expect(selection.items == [a, b, c], "Select All includes displayed original items once, in display order")
        try expect(selection.focus == c && selection.anchor == a, "Select All retains visible active focus and a stable first-row anchor")
        selection.selectAll(order: [b, c], active: a)
        try expect(selection.items == [b, c] && !selection.items.contains(a), "Select All cannot include hidden/foreign active rows")
        selection.selectAll(order: [a], active: c)
        try expect(selection.items.isEmpty && selection.singleItem == a, "Select All of an ordinary singleton uses the ordinary selection path")
        selection.selectAll(order: [], active: a)
        try expect(selection.items.isEmpty && selection.singleItem == nil && selection.focus == nil, "Empty Select All expires previous selection/focus")
        var copying = SidebarItemSelection()
        try expect(copying.copyTargets(order: [a, b, c], active: c) == [c], "With nothing else chosen, Copy takes the current row")
        try expect(copying.copyTargets(order: [a, b], active: c) == nil, "A current row outside the sidebar, like a Favorite, has nothing to copy")
        copying.select(b, order: [a, b, c], active: nil, extending: false, toggling: false)
        try expect(copying.items.isEmpty && copying.copyTargets(order: [a, b, c], active: c) == [b], "One selected row copies that row")
        try expect(copying.copyTargets(order: [a, c], active: c) == nil, "A selected row that left the sidebar copies nothing")
        copying.select(c, order: [a, b, c], active: a, extending: false, toggling: true)
        try expect(copying.copyTargets(order: [a, b, c], active: a) == [a, c], "A multi-selection still copies every selected row")
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Folder")
            let a = store.open("https://example.com/a(b)", kind: .pinned)
            let b = store.open("https://example.com/a(b)", kind: .pinned)
            let c = store.open("https://example.com/c", kind: .today)
            store.updateTab(a, title: "A [label]\nnext")
            store.moveTab(a, toSpace: space, folderID: folder)
            store.moveTab(b, toSpace: space, folderID: folder)
            store.toggleFolder(folder)
            let original = store.state
            let links = FolderLinks.links(in: original, items: [.folder(folder), .tab(a), .tab(c)], spaceID: space, profileID: profile)!
            try expect(links.map(\.tabID) == [a, b, c], "Plural copy includes collapsed folder originals once and preserves distinct same-URL tabs")
            try expect(FolderLinks.text(for: links, format: .plain) == links.map(\.url).joined(separator: "\n"), "Plain plural copy exports one original URL per line")
            try expect(FolderLinks.text(for: links, format: .markdown)?.hasPrefix("[A \\[label\\] next](<https://example.com/a(b)>)") == true, "Plural Markdown uses actual title and safe folder serialization")
            try expect(FolderLinks.links(in: original, items: [.folder(UUID()), .tab(c)], spaceID: space, profileID: profile) == nil, "A stale selected item refuses the whole copy proposal")
            try expect(FolderLinks.links(in: original, items: [.tab(c)], spaceID: space, profileID: UUID()) == nil, "Foreign profile cannot export the original Space")
            try expect(store.state == original, "Preparing copy never mutates original page/model selection")
            store.selectTab(a); store.selectTab(b, extendingSplit: true)
            let split = store.activeSplitLayout!
            let splitLinks = FolderLinks.links(in: store.state, items: [.split(split.id), .tab(c)], spaceID: space, profileID: profile)!
            try expect(splitLinks.map(\.tabID) == [a, b, c], "Plural copy expands the original split children in their existing order")
            try expect(FolderLinks.links(in: store.state, items: [.tab(c)], spaceID: space, profileID: profile)?.map(\.tabID) == [c],
                       "One selected tab copies its own address")
            try expect(FolderLinks.links(in: store.state, items: [.split(split.id)], spaceID: space, profileID: profile)?.map(\.tabID) == [a, b],
                       "One selected split copies all of its pages in pane order")
            var mixed = store.state
            let favorite = mixed.tabs.firstIndex { $0.id == b }!
            mixed.tabs[favorite].kind = .favorite; mixed.tabs[favorite].folderID = nil; mixed.tabs[favorite].spaceID = UUID()
            try expect(FolderLinks.links(in: mixed, items: [.split(split.id)], spaceID: space, profileID: profile)?.map(\.tabID) == [a, b]
                       && FolderLinks.links(in: mixed, tabIDs: split.tabIDs, spaceID: space, profileID: profile).map(\.tabID) == [a, b],
                       "A split row's Favorite from another Space is copied alike from the sidebar and the split menu")
            try expect(FolderLinks.links(in: original, items: [.folder(folder)], spaceID: space, profileID: profile)?.map(\.tabID) == [a, b],
                       "One selected folder copies its contents")
            let documents = [InternalPage.note(UUID()).urlString, InternalPage.easel(UUID()).urlString, "parc://settings/", "about:blank"]
                .map { store.openResolvedURL(URL(string: $0)!) }
            try expect(FolderLinks.links(in: store.state, items: documents.map { .tab($0) } + [.tab(c)], spaceID: space, profileID: profile)?.map(\.tabID) == [c],
                       "Notes, Easels, Parc pages and blank tabs have no address to copy")
            let rich = [FolderLinks.Link(tabID: UUID(), title: "A [label]\nnext", url: "https://example.com/a?x=1&y=2"),
                        FolderLinks.Link(tabID: UUID(), title: " ", url: "https://example.com/\"c\"")]
            try expect(FolderLinks.html(for: rich) == "<meta charset=\"utf-8\"><a href=\"https://example.com/a?x=1&amp;y=2\">A [label] next</a><br>\n"
                       + "<a href=\"https://example.com/&quot;c&quot;\">https://example.com/&quot;c&quot;</a>",
                       "Rich copy links each page title to its address, escaped, falling back to the address")
            try expect(FolderLinks.html(for: []) == nil, "Nothing to copy has no rich flavor")
            let renamed = store.open("https://example.com/renamed", kind: .pinned)
            let named = store.createFolder(name: "Named")
            store.moveTab(renamed, toSpace: space, folderID: named)
            store.updateTab(renamed, title: "Page Title")
            try store.saveSidebarTitle(store.state.tab(renamed)!, title: "  My <Name> & Co  ")
            let renamedLinks = FolderLinks.links(in: store.state, items: [.tab(renamed)], spaceID: space, profileID: profile)!
            try expect(FolderLinks.text(for: renamedLinks, format: .markdown) == "[My <Name> & Co](<https://example.com/renamed>)",
                       "Markdown copies a renamed tab under the name the sidebar shows")
            try expect(FolderLinks.html(for: renamedLinks) == "<meta charset=\"utf-8\"><a href=\"https://example.com/renamed\">My &lt;Name&gt; &amp; Co</a>",
                       "Rich copy links a renamed tab's sidebar name to its address")
            try expect(FolderLinks.text(for: renamedLinks, format: .plain) == "https://example.com/renamed", "Plain copies of a renamed tab stay a bare address")
            try expect(FolderLinks.links(in: store.state, tabIDs: [renamed], spaceID: space, profileID: profile) == renamedLinks
                       && FolderLinks.links(in: store.state, target: FolderLinkTarget(folderID: named, spaceID: space, profileID: profile)) == renamedLinks,
                       "The split menu and a folder's Copy All Links use the same sidebar name")
            try store.saveSidebarTitle(store.state.tab(renamed)!, title: "")
            let unnamed = FolderLinks.links(in: store.state, items: [.tab(renamed)], spaceID: space, profileID: profile)!
            try expect(FolderLinks.text(for: unnamed, format: .markdown) == "[Page Title](<https://example.com/renamed>)",
                       "Clearing the sidebar name falls back to the page title")
        }
    }

    static func testFolderRemovalSelection() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let left = store.open("https://left.example", kind: .pinned)
            let folder = store.createFolder(name: "Delete")
            let current = store.open("https://current.example", kind: .pinned)
            store.moveTab(current, toSpace: space, folderID: folder)
            let right = store.open("https://right.example", kind: .pinned)
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            _ = try store.moveSidebarItem(.folder(folder), to: root, before: .tab(right),
                expected: SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!)
            store.selectTab(current)
            let target = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            @MainActor func resolve(_ selected: [UUID], _ focus: UUID?, unavailable: Set<UUID> = []) -> FolderRemovalSelection? {
                FolderRemovalSelection.resolve(target: target, state: store.state, selected: selected,
                    focused: focus, available: { !unavailable.contains($0) })
            }
            let previous = resolve([current], current)!
            try expect(previous.tabIDs == [left] && previous.focusedTabID == left, "Folder close prefers the original previous item over the newer next item")
            let following = resolve([current], current, unavailable: [left])!
            try expect(following.tabIDs == [right], "Next original item is used when the previous page is owned elsewhere")
            let empty = resolve([current], current, unavailable: [left, right])!
            try expect(empty.tabIDs.isEmpty && empty.focusedTabID == nil, "No available original item yields a genuine empty selection")
            let background = resolve([right], right)!
            try expect(background.tabIDs == [right] && background.focusedTabID == right, "Deleting a background folder retains the original active page")
            try expect(resolve([], nil)?.tabIDs.isEmpty == true, "An unselected original window stays unselected")
            try expect(resolve([current, right], right)?.tabIDs == [right], "An original surviving pane is kept without selecting an unrelated neighbor")
            try expect(resolve([current, right], current)?.focusedTabID == right, "Retired focus falls to the original surviving pane")
            try expect(resolve([current, right], right, unavailable: [right]) == nil, "A surviving page transferred elsewhere refuses the captured decision")
            try expect(resolve([current], right) == nil && resolve([current, current], current) == nil, "Foreign focus and duplicate selection IDs refuse")
            var collapsed = store.state
            collapsed.folders[collapsed.folders.firstIndex { $0.id == folder }!].isExpanded = false
            let collapsedTarget = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: collapsed)!
            try expect(FolderRemovalSelection.resolve(target: collapsedTarget, state: collapsed,
                selected: [current], focused: current, available: { _ in true })?.tabIDs == [left], "Original close anchor survives collapsed folder disclosure")
            var gate: (() -> Bool)?, done: ((Bool) -> Void)?
            store.requestPageRetirement = { _, validator, completion in gate = validator; done = completion }
            var result: Result<Bool, Error>?
            store.deleteFolder(target, selection: previous, shouldCommit: { false }) { result = $0 }
            try expect(gate?() == false, "Original-window refusal stops selection and deletion together")
            done?(false)
            try expect(store.state.selectedTabIDs == [current] && store.folders.contains { $0.id == folder }, "Refused consent preserves original current item and folder")
            store.deleteFolder(target, selection: previous, shouldCommit: { true }) { result = $0 }
            try expect(store.state.selectedTabIDs == [current], "Pending consent does not select the replacement early")
            try expect(gate?() == true, "Confirmed immutable decision passes native retirement")
            done?(true)
            try expect((try? result?.get()) == true && store.state.selectedTabIDs == [left], "One commit removes the folder and selects its captured replacement")
            try expect(store.state.selectionBySpace[space.uuidString] == [left], "Same-Space restart selection commits with folder deletion")
            let loaded = try BrowserStore(directory: directory)
            try expect(loaded.state.selectedTabIDs == [left] && !loaded.folders.contains { $0.id == folder }, "Disk reload sees deletion and replacement together")
        }
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let a = store.open("https://a.example")
            let b = store.open("https://b.example")
            try savedSplit(store, [a, b], in: .init(spaceID: space, folderID: nil, section: .pinned))
            store.selectTab(a); _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.4, 0.6])
            let split = store.activeSplitLayout!
            let folder = store.createFolder(name: "Delete")
            let current = store.open("https://current.example", kind: .pinned)
            store.moveTab(current, toSpace: space, folderID: folder)
            let target = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            let choice = FolderRemovalSelection.resolve(target: target, state: store.state,
                selected: [current], focused: current, available: { _ in true })!
            try expect(choice.tabIDs == split.tabIDs, "An adjacent split is selected as its original complete item")
            try expect(FolderRemovalSelection.resolve(target: target, state: store.state,
                selected: [current], focused: current, available: { $0 != b })?.tabIDs.isEmpty == true,
                "One unavailable split child excludes the entire group")
            var changed = store.state
            changed.tabs[changed.tabs.firstIndex { $0.id == a }!].profileID = UUID()
            try expect(FolderRemovalSelection.resolve(target: target, state: changed,
                selected: [current], focused: current, available: { _ in true }) == nil,
                "A replacement changing profile invalidates the original hierarchy")
            var selection = choice
            selection = FolderRemovalSelection(spaceID: space, profileID: profile, original: [current],
                originalFocus: current, tabIDs: [UUID()], focusedTabID: nil)
            var result: Result<Bool, Error>?
            store.deleteFolder(target, selection: selection, shouldCommit: { true }) { result = $0 }
            try expect((try? result?.get()) == false && store.folders.contains { $0.id == folder }, "Unknown replacement cannot commit deletion")
        }
    }

    static func testFolderDeletion() throws {
        try withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let sibling = store.createFolder(name: "Keep")
            let parent = store.createFolder(name: "Delete")
            let nested = store.createFolder(name: "Nested", parentID: parent)
            let empty = store.createFolder(name: "Empty", parentID: nested)
            let outside = store.open("https://keep.example", kind: .pinned)
            let first = store.open("https://one.example", kind: .pinned)
            let a = store.open("https://a.example")
            let b = store.open("https://b.example")
            store.moveTab(first, toSpace: space, folderID: parent)
            try savedSplit(store, [a, b], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(a)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.3, 0.7])
            let split = store.activeSplitLayout!
            store.toggleFolder(nested)
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let inside = SidebarContainerLocation(spaceID: space, folderID: parent, section: .pinned)
            _ = try store.moveSidebarItem(.folder(nested), to: inside, before: .tab(first),
                expected: SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!)
            let before = store.state
            let rootBefore = SidebarHierarchy.children(in: root, state: before)
            let target = FolderRemovalTarget(folderID: parent, spaceID: space, profileID: profile, state: before)!
            try expect(target.folderIDs == [parent, nested, empty] && Set(target.tabs.map(\.id)) == [first, a, b], "Deletion binds collapsed and empty descendants in original mixed order")
            try expect(FolderRemovalTarget(folderID: parent, spaceID: space, profileID: UUID(), state: before) == nil, "Foreign profile cannot prepare deletion")
            var malformed = before
            malformed.folders[malformed.folders.firstIndex { $0.id == parent }!].parentID = empty
            try expect(FolderRemovalTarget(folderID: parent, spaceID: space, profileID: profile, state: malformed) == nil, "Hierarchy cycles refuse before consent")
            var crossSplit = before
            crossSplit.splitLayouts[0].tabIDs[1] = outside
            try expect(FolderRemovalTarget(folderID: parent, spaceID: space, profileID: profile, state: crossSplit) == nil, "A cross-subtree split cannot borrow an outside page")
            var requested = Set<UUID>(), validate: (() -> Bool)?, finish: ((Bool) -> Void)?
            store.requestPageRetirement = { ids, gate, done in requested = ids; validate = gate; finish = done }
            var results: [Result<Bool, Error>] = []
            store.deleteFolder(target, shouldCommit: { false }) { results.append($0) }
            try expect(requested == [first, a, b] && store.state == before, "Every original descendant page joins retirement before metadata changes")
            try expect(validate?() == false, "Originating-window refusal cancels the whole operation")
            finish?(false)
            try expect((try results.last?.get()) == false && store.state == before, "Refusal preserves folder tree, tabs, selection and order")
            store.deleteFolder(target, shouldCommit: { true }) { results.append($0) }
            finish?(false)
            try expect(store.state == before && (try results.last?.get()) == false, "Native beforeunload refusal does not archive any sibling")
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            store.deleteFolder(target, shouldCommit: { true }) { results.append($0) }
            try expect(validate?() == true && validate?() == false, "Consent authorization is one-shot")
            try expect(store.state == before, "Approved pages must actually finish retiring before saved deletion")
            let done = finish!
            done(true)
            try expect((try results.last?.get()) == true && publications == 1, "Complete deletion publishes once after durable save")
            let after = store.state, resultCount = results.count
            done(true)
            try expect(store.state == after && results.count == resultCount, "Repeated native completion cannot duplicate archives or commits")
            try expect(!store.state.folders.contains { [parent, nested, empty].contains($0.id) } && store.state.folders.contains { $0.id == sibling }, "Only the original subtree folder records are deleted")
            try expect(target.tabs.allSatisfy { original in store.state.tabs.contains { $0.id == original.id && $0.archivedAt == date && $0.folderID == nil && $0.profileID == profile && $0.kind == original.kind && $0.savedURL == original.savedURL } }, "Original saved identities and destinations become archived tabs without fabricated folder archives")
            try expect(store.state.tabs.first { $0.id == outside } == before.tabs.first { $0.id == outside }, "Outside saved tab is byte-for-byte untouched")
            try expect(SidebarHierarchy.children(in: root, state: store.state) == rootBefore.filter { $0 != .folder(parent) }, "Mixed sibling order survives removal without reparenting children")
            try expect(store.state.splitLayouts.isEmpty && store.state.selectedTabIDs.isEmpty, "Retired original split cannot remain visibly selected")
            let archived = store.archivedItems(profileID: profile)
            try expect(archived.count == 2 && archived.contains { $0.tabs.map(\.id) == split.tabIDs && $0.provenance?.split == split }, "Complete split children stay one restorable archive item with original geometry")
            try expect(archived.allSatisfy { $0.provenance?.reason == .manual && $0.provenance?.spaceID == space }, "Archive uses the genuine original Space and manual source")
            try expect(store.state.history == before.history && store.state.downloads == before.downloads, "Folder deletion leaves history/download records intact")
            let loaded = try BrowserStore(directory: directory)
            try expect(loaded.state.tabs == store.state.tabs && loaded.state.folders == store.state.folders && loaded.state.sidebarItemOrder == store.state.sidebarItemOrder, "Durable reload contains the complete archive and hierarchy result")
            _ = store.restoreArchivedTab(a, profileID: profile, destination: .previousSpace(fallbackSpaceID: space))
            try expect(store.state.selectedTabIDs == split.tabIDs && store.activeSplitLayout?.orientation == .vertical && store.activeSplitLayout?.widthFactors == [0.3, 0.7], "Restoring the archived split preserves original page IDs/order and geometry")
            try expect(!store.state.folders.contains { $0.id == parent }, "Restoring tabs does not invent a deleted folder")
            _ = observation
        }
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Pending")
            let tabID = store.open("https://pending.example", kind: .pinned)
            store.moveTab(tabID, toSpace: space, folderID: folder)
            var gate: (() -> Bool)?, done: ((Bool) -> Void)?
            store.requestPageRetirement = { _, validate, completion in gate = validate; done = completion }
            let target = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            var result: Result<Bool, Error>?
            store.deleteFolder(target, shouldCommit: { true }) { result = $0 }
            store.renameFolder(folder, name: "Changed")
            try expect(gate?() == false, "Renamed or structurally changed target invalidates original confirmation")
            done?(false)
            try expect((try result?.get()) == false && store.state.tabs.first { $0.id == tabID }?.archivedAt == nil, "Stale cancellation retains original page and saved tab")
            let current = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            store.deleteFolder(current, shouldCommit: { store.renameFolder(folder, name: "Reentered"); return true }) { result = $0 }
            try expect(gate?() == false, "Reentrant validator cannot authorize a changed subtree")
            done?(false)
            store.requestPageRetirement = nil
            let empty = store.createFolder(name: "Empty")
            let emptyTarget = FolderRemovalTarget(folderID: empty, spaceID: space, profileID: profile, state: store.state)!
            store.deleteFolder(emptyTarget, shouldCommit: { false }) { result = $0 }
            try expect(store.state.folders.contains { $0.id == empty }, "Empty-folder removal still honors original-window cancellation")
            store.deleteFolder(emptyTarget, shouldCommit: { true }) { result = $0 }
            try expect((try result?.get()) == true && !store.state.folders.contains { $0.id == empty }, "Confirmed empty folder uses the same durable transaction")
            let failureTarget = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            let original = store.state
            try FileManager.default.removeItem(at: directory.appendingPathComponent("session.json"))
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("session.json"), withIntermediateDirectories: false)
            store.deleteFolder(failureTarget, shouldCommit: { true }) { result = $0 }
            if case .failure = result {} else { throw Failure(description: "Save failure must report an error") }
            try expect(store.state == original && store.persistenceError != nil, "Failed durable save cannot publish a partial deletion")
        }
    }

    static func testFolderDeletionUndo() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let outer = store.createFolder(name: "Outer")
            let beforeSibling = store.createFolder(name: "Before", parentID: outer)
            let root = store.createFolder(name: "Deleted", parentID: outer)
            let afterSibling = store.createFolder(name: "After", parentID: outer)
            let nested = store.createFolder(name: "Nested", parentID: root)
            let empty = store.createFolder(name: "Empty", parentID: nested)
            let a = store.open("https://a.test"), b = store.open("https://b.test")
            try savedSplit(store, [a, b], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(a)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.25, 0.75])
            let split = store.activeSplitLayout!, originals = store.state
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: originals)!
            let selection = FolderRemovalSelection.resolve(target: target, state: originals,
                selected: [a, b], focused: b, available: { _ in true })!
            var record: FolderDeletionUndo?, result: Result<Bool, Error>?
            store.deleteFolder(target, selection: selection, shouldCommit: { false }, didCommit: { record = $0 }) { result = $0 }
            try expect(record == nil && (try result?.get()) == false, "Cancelled delete cannot register Undo")
            store.deleteFolder(target, selection: selection, shouldCommit: { true }, didCommit: { record = $0 }) { result = $0 }
            let undo = record!
            try expect(undo.focusedTabID == b && undo.groups == [split], "Undo binds original focused pane and split provenance")
            try expect(undo.folders.map(\.id).contains(empty) && store.canUndoFolderDeletion(undo), "Nested empty folder is part of ordinary undo, without folder archive entities")
            let newSibling = store.createFolder(name: "New", parentID: outer)
            store.renameFolder(beforeSibling, name: "Keep current edit")
            let outside = store.open("https://outside.test", kind: .today)
            let outsideRecord = store.state.tabs.first { $0.id == outside }!
            let beforeUndo = store.state
            try expect(try !store.undoFolderDeletion(undo, shouldCommit: { false }), "Original-window refusal leaves Undo retryable")
            try expect(store.state == beforeUndo, "Refused Undo changes no saved state")
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            try expect(try store.undoFolderDeletion(undo, shouldCommit: { true }), "Undo restores exact original group")
            try expect(publications == 1, "Undo publishes one durable targeted transaction")
            try expect(store.state.tabs.first { $0.id == a } == originals.tabs.first { $0.id == a }
                && store.state.tabs.first { $0.id == b } == originals.tabs.first { $0.id == b }, "Original tab identities/content return from unchanged archive afterimages")
            try expect(store.state.splitLayouts.contains(split), "Original split ID, pane order and geometry return")
            try expect(store.state.folders.filter { target.folderIDs.contains($0.id) } == originals.folders.filter { target.folderIDs.contains($0.id) }, "Nested names, parents and expansion return intact")
            try expect(store.state.tabs.first { $0.id == outside } == outsideRecord
                && store.state.folders.first { $0.id == beforeSibling }?.name == "Keep current edit", "Unrelated additions and edits survive Undo")
            let container = SidebarContainerLocation(spaceID: space, folderID: outer, section: .pinned)
            try expect(SidebarHierarchy.children(in: container, state: store.state) == [.folder(beforeSibling), .folder(root), .folder(afterSibling), .folder(newSibling)], "Original sibling anchors restore location without rolling back new siblings")
            try expect(store.state.selectedTabIDs == beforeUndo.selectedTabIDs, "Store Undo does not select pages in other physical windows")
            try expect(!store.canUndoFolderDeletion(undo) && !(try store.undoFolderDeletion(undo, shouldCommit: { true })), "Consumed afterimage cannot duplicate original identities")
            let loaded = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            try expect(loaded.state.tabs == store.state.tabs && loaded.state.folders == store.state.folders
                && loaded.state.splitLayouts == store.state.splitLayouts, "Restored originals persist together")
            store.updateTab(a, title: "New actual title")
            try expect(undo.redoTarget(in: store.state) != nil, "Redo closes current original members after normal title/navigation updates")
            let extra = store.open("https://extra.test", kind: .pinned)
            store.moveTab(extra, toSpace: space, folderID: root)
            try expect(undo.redoTarget(in: store.state) == nil, "Redo never closes newly added descendants")
            _ = observation
        }
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = store.createFolder(name: "Retry")
            let a = store.open("https://retry.test", kind: .pinned)
            store.moveTab(a, toSpace: space, folderID: root)
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: store.state)!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = record!, archived = store.state
            try FileManager.default.removeItem(at: directory.appendingPathComponent("session.json"))
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("session.json"), withIntermediateDirectories: false)
            var failed = false
            do { _ = try store.undoFolderDeletion(undo, shouldCommit: { true }) } catch { failed = true }
            try expect(failed && store.state == archived && store.canUndoFolderDeletion(undo), "Failed durable Undo keeps exact archived state and retry capability")
            try FileManager.default.removeItem(at: directory.appendingPathComponent("session.json")); try store.save()
            _ = store.restoreArchivedTab(a, profileID: profile, destination: .previousSpace(fallbackSpaceID: space))
            try expect(!store.canUndoFolderDeletion(undo), "Independent archive restoration invalidates old group")
            try expect(try !store.undoFolderDeletion(undo, shouldCommit: { true }), "Stale Undo cannot resurrect a folder around an independently restored tab")
            let empty = store.createFolder(name: "Empty")
            let emptyTarget = FolderRemovalTarget(folderID: empty, spaceID: space, profileID: profile, state: store.state)!
            store.deleteFolder(emptyTarget, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            try expect(try store.undoFolderDeletion(record!, shouldCommit: { true }), "Empty ordinary folder Undo is supported")
            try expect(store.state.folders.contains { $0.id == empty }, "Empty folder retains original identity")
        }
    }

    static func testArchivePutBackDestinations() throws {
        for scenario in ["all", "filtered", "missing", "reassigned", "original-moved", "foreign-profile", "no-compatible-space", "recent"] {
            try withDirectory { directory in
                let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
                let originalSpace = store.activeSpaceID, profile = store.activeSpace.profileID
                let a = store.open("https://archive-a.example"), b = store.open("https://archive-b.example")
                store.setSplit([a, b]); _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.35, 0.65])
                let originalSplit = store.activeSplitLayout!
                store.closeTabs([a, b])
                let currentSpace = store.createSpace(name: "Current window")
                let filteredSpace = store.createSpace(name: "Selected filter")
                let otherProfile = store.createProfile(name: "Other profile")
                store.selectSpace(currentSpace)
                if scenario == "reassigned" { store.assignProfile(otherProfile, toSpace: filteredSpace) }
                if scenario == "original-moved" { store.assignProfile(otherProfile, toSpace: originalSpace) }
                let destination: ArchiveRestoreDestination
                let expected: UUID?
                let requestedProfile: UUID
                switch scenario {
                case "filtered":
                    destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: filteredSpace)
                    expected = filteredSpace; requestedProfile = profile
                case "missing":
                    destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: UUID())
                    expected = currentSpace; requestedProfile = profile
                case "reassigned":
                    destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: filteredSpace)
                    expected = currentSpace; requestedProfile = profile
                case "foreign-profile":
                    destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: nil)
                    expected = nil; requestedProfile = otherProfile
                case "no-compatible-space":
                    destination = .putBack(currentSpaceID: UUID(), requestedSpaceID: UUID())
                    expected = nil; requestedProfile = profile
                case "recent":
                    destination = .previousSpace(fallbackSpaceID: currentSpace)
                    expected = originalSpace; requestedProfile = profile
                default:
                    destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: nil)
                    expected = currentSpace; requestedProfile = profile
                }
                let before = store.state
                var publications: [BrowserState] = []
                let observation = store.statePublisher.dropFirst().sink { publications.append($0) }
                let restored = store.restoreArchivedTab(a, profileID: requestedProfile, destination: destination)
                if let expected {
                    try expect(restored == originalSplit.tabIDs && store.activeSpaceID == expected,
                               "Put Back \(scenario) selects the original group in its resolved destination")
                    try expect(!publications.isEmpty && publications.allSatisfy { snapshot in
                        snapshot.tabs.filter { [a, b].contains($0.id) }.allSatisfy { $0.archivedAt == nil && $0.spaceID == expected }
                    }, "Put Back publishes the complete original group without partially restored siblings")
                    let tabs = store.state.tabs.filter { [a, b].contains($0.id) }
                    try expect(tabs.count == 2 && tabs.allSatisfy { $0.spaceID == expected && $0.profileID == profile && $0.archivedAt == nil && $0.archiveProvenance == nil },
                               "Put Back retains original identities/profile and clears only archive metadata")
                    var expectedSplit = originalSplit; expectedSplit.spaceID = expected
                    let restoredLayout = store.activeSplitLayout
                    var restoredShape = restoredLayout; restoredShape?.widthFactors = expectedSplit.widthFactors
                    try expect(restoredShape == expectedSplit && zip(restoredLayout?.widthFactors ?? [], expectedSplit.widthFactors).allSatisfy { abs($0 - $1) < 1e-12 },
                               "Put Back preserves original split order, orientation, ratios and identity")
                    try expect(!store.state.recentlyClosedIDs.contains(a) && !store.state.recentlyClosedIDs.contains(b), "Restored group leaves the recent-closed stack")
                    try store.save()
                    let loaded = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
                    try expect(loaded.state.tabs == store.state.tabs && loaded.state.splitLayouts == store.state.splitLayouts,
                               "Put Back destination persists with the original group")
                } else {
                    try expect(restored.isEmpty && store.state == before && publications.isEmpty,
                               "Invalid Put Back \(scenario) preserves every archived record and selection")
                }
                _ = observation
            }
        }
    }

    static func run() throws {
        try testArchivePutBackDestinations()
        try testFolderDeletionUndo()
        try testFolderRemovalSelection()
        try testFolderDeletion()
        try testFolderDuplication()
        try testSidebarSelectionCommands()
        try testSidebarMultiSelection()
        try testTypedSplitDropTransactions()
        try testNativePageAdoption()
        try testCancelledNativeRetirement()
        try testNativeRetirementPrecedesSavedMutations()
        try testGroupedNativeClose()
        try testRetirementCommitBoundary()
        try testArchiveValidationPrecedesAnyUnload()
        try testProfileChangePreflightRevalidation()
        try testWindowCommandContext()
        try testNativeArchiveConsentAndRevalidation()
        try testPublicInternalAddresses()
        try testNavigationMetadataPublication()
        try testHistoryNewestFirstMatchesDateSort()
        try testHistoryFileSplit()
        try testHistoryNewestFirstMatchesISO8601RoundTrip()
        try testHistoryRevisionTracksVisitRecords()
        try testNavigationInput()
        try testCorruptFileIsPreserved()
        try testSessionRoundTrip()
        try testSessionSaveRoundTripIdentity()
        try testProfileSettingsIdenticalBytePersistSkip()
        try testSessionSavePendingScheduleCoalesce()
        try testFreshSessionWhenRestoreDisabled()
        try testChangingRestorePreferenceDoesNotCloseCurrentTabs()
        try testSpacesAndProfiles()
        try testArchivePolicyAndRestore()
        try testSavedDestinationsAndSplitLifecycle()
        try testClosingLastSavedTabDoesNotReselectIt()
        try testFoldersAndOrdering()
        try testSidebarHierarchyMoves()
        try testFolderDisclosureOwnership()
        try testFavoriteSelectionAfterProfileReassignment()
        try testInvalidRelationshipsAreRejected()
        try testBookmarkImportDoesNotNavigate()
        try testNamesColorsAndPreferencesRoundTrip()
        try testThemeColorsAndLinkedPalettes()
        try testThemeMigrationPersistenceAndValidation()
        try testDownloadLifecycleAndPersistence()
        try testDownloadLibraryIdentityAndMetadata()
        try testLegacyDownloadSessionMigration()
        try testDownloadFlagsAndExplicitState()
        try testSplitLayoutValidation()
        try testSavedSplitLayoutsAcrossSpacesAndRestart()
        try testSplitMembershipContainers()
        try testClosingSplitAnchorKeepsSlot()
        try testLegacyMixedSplitContainerMigration()
        try testSplitMembershipRoutes()
        try testLegacySharedFavoriteMigration()
        try testSplitPaneChangesPreserveSurvivors()
        try testSplitLayoutMembershipCleanup()
        try testLegacySplitLayoutMigration()
        try testInvalidPersistedSplitsArePreserved()
        try testLegacyStaleSplitSelectionMigration()
        try testTypedInternalEaselAddresses()
        try testEaselTabsAndSavedTitle()
        try testEaselProfileDirectoriesAndIdentity()
        try testArchivePolicyIsProfileScoped()
        try testLegacyArchivePolicyMirrorIsIgnored()
        try testInvalidArchivePoliciesPreserveSession()
        try testArchiveStartMigrationAndStrictBoundary()
        try testVisibleActivityPreventsImmediateArchive()
        try testVisibleActivityPersistsWithoutPublishing()
        try testBatchedMutationPublishesOnce()
        try testIdenticalStateAssignDoesNotPublish()
        try testUnreadAndNativeProtectionGates()
        try testArchiveAcrossSpacesAndProfiles()
        try testArchiveSavedSplitConstituents()
        try testArchiveTypedItemsAndMixedGroups()
        try testArchiveOriginalItemRevalidation()
        try testArchiveNoOpDoesNotWriteOrReset()
        print("PASS: \(assertions) BrowserStore assertions")
    }

    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }
}
