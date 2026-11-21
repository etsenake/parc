import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor
struct BrowserStoreTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
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
                           sourceLocation: SourceLocation = #_sourceLocation) throws -> BrowserTab {
        let homes = store.state.tabs.filter { $0.id != original && $0.savedURL == savedURL && $0.archivedAt == nil
            && ($0.kind == .pinned || $0.kind == .favorite) }
        #expect(homes.count == 1, "Exactly one fresh saved home holds the original slot", sourceLocation: sourceLocation)
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

    static func tab(_ id: UUID, in store: BrowserStore) throws -> BrowserTab {
        guard let value = store.state.tabs.first(where: { $0.id == id }) else {
            throw Failure(description: "Expected tab \(id) to exist")
        }
        return value
    }

    static func expectValidSelection(_ store: BrowserStore) throws {
        let visible = Set(store.visibleTabs.map(\.id))
        #expect(store.state.selectedTabIDs.allSatisfy { visible.contains($0) }, "Selection must contain only visible, unarchived tabs in the active profile/Space")
        #expect(Set(store.state.selectedTabIDs).count == store.state.selectedTabIDs.count, "Split selection must not contain duplicate tabs")
    }

    static func expectFactors(_ actual: [Double]?, _ expected: [Double], _ message: String) throws {
        #expect(actual?.count == expected.count, Comment(rawValue: message + " (pane count)"))
        guard let actual, actual.count == expected.count else { return }
        #expect(zip(actual, expected).allSatisfy { abs($0 - $1) < 1e-10 }, Comment(rawValue: message))
    }

    @Test static func publicInternalAddresses() throws {
        let source = "chrome://settings/content/siteDetails?site=https%3A%2F%2Fexample.test%2Fa%3Fx%3D1#privacy"
        let visible = "parc://settings/content/siteDetails?site=https%3A%2F%2Fexample.test%2Fa%3Fx%3D1#privacy"
        #expect(BrowserInternalURL.publicString(source) == visible, "Public projection preserves escaped components")
        #expect(NavigationInput.resolve(source)?.absoluteString == visible, "Legacy Chromium input receives public metadata")
        #expect(NavigationInput.resolve(visible)?.absoluteString == visible, "Typed Parc WebUI routes to the native engine")
        #expect(!InternalPage.isInternal(visible), "Browser WebUI is not an Easel document")
        #expect(NavigationInput.resolve("arc://settings/") == nil, "arc:// is not an accepted scheme alias")
        #expect(NavigationInput.resolve("parc:") == nil, "A hostless public address does not become a search")
        #expect(NavigationInput.resolve("parc://unknown-controller/path")?.host == "unknown-controller", "Actual Chromium controller lookup decides unavailable hosts")
        #expect(BrowserInternalURL.publicString("chrome://easel/not-a-uuid") == "chrome://easel/not-a-uuid", "An unsupported Chromium host cannot acquire an app document identity")
        let network = "https://example.test/?next=chrome://settings/#chrome://flags"
        #expect(BrowserInternalURL.publicString(network) == network, "Embedded URLs and ordinary origins remain untouched")
        #expect(BrowserInternalURL.publicString("chrome-untrusted://example/") == "chrome-untrusted://example/", "Untrusted origins never become privileged public URLs")
        #expect(BrowserInternalURL.publicString(InternalPage.easel(UUID()).urlString).hasPrefix("parc://easel/"), "Typed app documents retain their identity")
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.openResolvedURL(URL(string: source)!, kind: .pinned)
            #expect(store.state.tabs.first { $0.id == id }?.url == visible, "Direct adopted metadata uses the public scheme")
            store.updateTab(id, url: "chrome://flags/#experiment")
            #expect(store.state.tabs.first { $0.id == id }?.url == "parc://flags/#experiment", "Native updates project only the display URL")
            #expect(store.state.tabs.first { $0.id == id }?.savedURL == visible, "Navigation keeps the distinct saved pin destination")
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
            #expect(restored.url == "parc://flags/#experiment" && restored.savedURL == visible, "Legacy sessions migrate current and saved addresses independently")
            #expect(restored.profileID == store.state.tabs.first { $0.id == id }?.profileID && restored.id == id, "Scheme migration preserves original Profile and item identity")
            let again = try BrowserStore(directory: directory)
            #expect(again.state.tabs.first { $0.id == id } == restored, "Migration persists idempotently")
        }
    }

    @Test static func noteVisitStackSessions() throws {
        try withDirectory { directory in
            let note = directory.appendingPathComponent("Plan.md"), easel = UUID()
            try Data("# Plan\n".utf8).write(to: note)
            let page: UUID
            do {
                let store = try BrowserStore(directory: directory)
                page = store.open("https://example.test/docs")
                store.updateTab(page, title: "Docs", url: "https://example.test/docs")
                #expect(store.openDocumentOverPage(page, page: .note(note), title: "Plan")
                           && store.openDocumentOverPage(page, page: .easel(easel), title: "Board")
                           && store.stepNoteVisit(page, forward: false), "A page holds a note and an Easel, showing the note")
                try store.save()
            }
            let reopened = try BrowserStore(directory: directory)
            let restored = reopened.state.tab(page)!
            #expect(restored.url == InternalPage.note(note).urlString && restored.noteVisit?.position == 1
                       && restored.noteVisit?.documents.count == 2 && restored.hasVisitStepAhead, "A session restores every document step and where the tab stood")
            #expect(reopened.stepNoteVisit(page, forward: true) && reopened.state.tab(page)?.url == InternalPage.easel(easel).urlString, "Forward after a restart reaches the Easel")
            try reopened.save()

            let file = directory.appendingPathComponent("session.json")
            var saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var tabs = saved["tabs"] as! [[String: Any]]
            let index = tabs.firstIndex { $0["id"] as? String == page.uuidString }!
            let record = tabs[index]["noteVisit"] as! [String: Any]
            #expect((record["note"] as? [String: Any])?["url"] as? String == InternalPage.easel(easel).urlString
                       && record["showsNote"] as? Bool == true, "Older Parc versions still find the shown document in the saved record")
            tabs[index]["noteVisit"] = ["page": record["page"]!, "note": record["note"]!, "showsNote": false]
            saved["tabs"] = tabs
            try JSONSerialization.data(withJSONObject: saved).write(to: file)
            let legacy = try BrowserStore(directory: directory)
            let migrated = legacy.state.tab(page)!.noteVisit!
            #expect(migrated.documents == [.init(url: InternalPage.easel(easel).urlString, title: "Board")]
                       && migrated.position == 0 && !migrated.showsNote && migrated.page.url == "https://example.test/docs", "A session saved with one document step loads as a one-step stack")
        }
    }

    @Test static func localFileOpensTitledByName() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.openResolvedURL(URL(fileURLWithPath: "/Users/me/Desktop/Lease Agreement.pdf"))
            #expect(store.state.tab(id)?.title == "Lease Agreement.pdf", "A local file opens titled by its file name")
            let web = store.openResolvedURL(URL(string: "https://example.test/start")!)
            #expect(store.state.tab(web)?.title == "example.test", "A web page still opens titled by its host")
        }
    }

    @Test static func navigationMetadataPublication() throws {
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
            #expect(tab.title == "Destination" && tab.savedTitle == tab.title &&
                tab.url == "https://example.test/destination" && tab.savedURL == tab.url, "First publication contains the complete Today tab metadata")
            #expect(first.history.last?.url == tab.url && first.history.last?.title == tab.title, "History and metadata publish together")
            #expect(publications.count == 1, "Metadata publishes once; identical changed() selection rewrite does not fan out again")
            store.updateTab(id, title: "Updated", url: tab.url)
            #expect(store.state.history.filter { $0.url == tab.url }.count == 1 && store.state.history.last?.title == "Updated", "Repeated recent URL updates the existing history title")
            let afterTitle = store.state
            #expect(afterTitle.preservesChromeLayout(relativeTo: first), "Title and history ticks keep sidebar membership and selection")
            #expect(afterTitle.preservesSidebarOutline(relativeTo: first), "Title ticks keep sidebar outline membership")
            let published = publications.count
            store.updateTab(id, title: "Updated")
            store.updateTab(id, title: "", url: tab.url)
            #expect(publications.count == published && store.state.tabs.first { $0.id == id }?.title == "Updated", "Unchanged title and empty title do not copy or publish BrowserState")
            let beforeCustom = store.state
            guard let expected = beforeCustom.tabs.first(where: { $0.id == id }) else {
                throw Failure(description: "Expected tab missing before customTitle")
            }
            _ = try store.saveSidebarTitle(expected, title: "Pinned name")
            #expect(store.state.preservesSidebarOutline(relativeTo: beforeCustom), "customTitle keeps outline membership for live cell patch")
            #expect(!store.state.preservesChromeLayout(relativeTo: beforeCustom), "customTitle is still a chrome-layout change for window-level live")
            let beforeDownload = store.state
            store.recordDownload(["id": "outline-skip-download", "name": "file.pdf", "isComplete": true])
            #expect(store.state.preservesSidebarOutline(relativeTo: beforeDownload), "Download ticks keep outline membership so sidebar skips row rebuild")
            #expect(!store.state.preservesChromeLayout(relativeTo: beforeDownload), "Download ticks remain chrome-layout changes for window-level live")
            let afterOutlineStable = store.state
            let extra = store.openResolvedURL(URL(string: "https://example.test/other")!, kind: .today)
            #expect(!store.state.preservesChromeLayout(relativeTo: afterOutlineStable) && extra != id, "A new tab is a chrome-layout change")
            #expect(!store.state.preservesSidebarOutline(relativeTo: afterOutlineStable), "A new tab is an outline membership change")
            let easelA = InternalPage.easel(UUID()).urlString
            let easelB = InternalPage.easel(UUID()).urlString
            store.updateTab(id, url: easelA)
            let afterEaselA = store.state
            store.updateTab(id, url: easelB)
            #expect(!store.state.preservesChromeLayout(relativeTo: afterEaselA), "A different Easel document is a chrome-layout change")
            #expect(!store.state.preservesSidebarOutline(relativeTo: afterEaselA), "A different Easel document is an outline membership change")
            let afterEaselB = store.state
            store.updateTab(id, title: "Canvas")
            #expect(store.state.preservesChromeLayout(relativeTo: afterEaselB), "Title on the same Easel keeps layout")
            #expect(store.state.preservesSidebarOutline(relativeTo: afterEaselB), "Title on the same Easel keeps outline membership")
            withExtendedLifetime(subscription) {}

            let pinned = store.openResolvedURL(URL(string: "https://example.test/home")!, kind: .pinned)
            store.updateTab(pinned, title: "Away", url: "https://example.test/away")
            let pin = store.state.tabs.first { $0.id == pinned }!
            #expect(pin.savedURL == "https://example.test/home" && pin.url == "https://example.test/away", "Metadata updates preserve a saved pin destination")

            let privateStore = BrowserStore(privateParentProfileID: store.activeSpace.profileID,
                engineProfilePath: "/disposable", directory: directory, settings: store.state.settings, now: { now })
            let privateID = privateStore.openResolvedURL(URL(string: "https://example.test/private")!, kind: .today)
            privateStore.updateTab(privateID, title: "Private", url: "https://example.test/private-next")
            #expect(privateStore.state.history.isEmpty && privateStore.state.tabs.first { $0.id == privateID }?.savedTitle == "Private", "Private metadata stays ephemeral and creates no history")
        }
    }

    @Test static func historyNewestFirstMatchesDateSort() throws {
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
        #expect(walked.map(\.id) == sorted.map(\.id), "Newest-first walk keeps sorted-by-date identity and order")
        #expect(walked.map(\.url) == sorted.map(\.url), "Newest-first walk keeps sorted-by-date URLs")
        #expect(BrowserHistoryOrder.isStrictlyChronological(profileHistory), "Unique timestamps stay strictly chronological")

        let tabURLs = ["https://example.test/39", "https://example.test/38"]
        let recents = commandBarEmptyQueryRecents(history: profileHistory, tabURLs: tabURLs, alreadyShown: 2)
        let sortedRecents = commandBarEmptyQueryRecentsSorted(history: profileHistory, tabURLs: tabURLs, alreadyShown: 2)
        #expect(recents.map(\.id) == sortedRecents.map(\.id), "Empty-query recents match the previous sort, skip open tabs, and keep http(s) matching")
        #expect(recents.count == 6, "Remaining empty-query slots stay filled to 8")
        #expect(!recents.contains { $0.url == "parc://settings" }, "Non-web visits stay excluded")
        #expect(recents.contains { $0.url == "HTTPS://Example.test/cased" }, "Scheme matching still uses URL() lowercased host checks")

        let tie = Date(timeIntervalSince1970: 100)
        let tied = [
            BrowserHistoryEntry(id: UUID(), url: "https://tie.test/a", title: "A", visitedAt: tie, profileID: profile),
            BrowserHistoryEntry(id: UUID(), url: "https://tie.test/b", title: "B", visitedAt: tie, profileID: profile),
            BrowserHistoryEntry(id: UUID(), url: "https://tie.test/c", title: "C", visitedAt: tie.addingTimeInterval(1), profileID: profile)
        ]
        #expect(!BrowserHistoryOrder.isStrictlyChronological(tied), "Same-second visits are not strictly chronological")
        #expect(BrowserHistoryOrder.newestFirst(tied).map(\.id) == tied.sorted { $0.visitedAt > $1.visitedAt }.map(\.id), "Tied timestamps keep the previous date-desc sort identity and order")
        #expect(commandBarEmptyQueryRecents(history: tied, tabURLs: []).map(\.id)
                    == commandBarEmptyQueryRecentsSorted(history: tied, tabURLs: []).map(\.id), "Empty-query recents keep sort identity when timestamps collide")
    }

    @Test static func historyFileSplit() throws {
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
            #expect(store.state.history == [old], "An inline legacy history loads")
            let tab = store.openResolvedURL(URL(string: "https://split.test/a")!, kind: .today)
            store.updateTab(tab, title: "A", url: "https://split.test/a")
            try store.save()
            let inline = try decoder.decode(BrowserState.self, from: Data(contentsOf: session))
            #expect(try inline.history.isEmpty && BrowserHistoryFile.decode(try Data(contentsOf: history)) == store.state.history
                       && store.state.history.first == old, "The next save moves every visit into history.jsonl")

            let beforeVisit = try Data(contentsOf: history), beforeRecords = try records(), file = try inode()
            clock = Date(timeIntervalSince1970: 3_000)
            store.updateTab(tab, title: "B", url: "https://split.test/b")
            try store.save()
            let afterVisit = try Data(contentsOf: history)
            #expect(try afterVisit.starts(with: beforeVisit) && (try records()) == beforeRecords + 1 && (try inode()) == file, "A navigation appends one record to the same file and leaves the existing bytes")
            store.updateTab(tab, title: "B retitled", url: "https://split.test/b")
            try store.save()
            #expect(try (try Data(contentsOf: history)).starts(with: afterVisit) && (try records()) == beforeRecords + 2, "Retitling the newest visit appends its new record")
            let retitled = store.state.history
            #expect(BrowserHistoryFile.decode(try Data(contentsOf: history)) == retitled, "The later record for a visit replaces the earlier one in place")
            let settled = try Data(contentsOf: history)
            store.updateSettings { $0.sidebarWidth = 310 }
            try store.save()
            #expect(try Data(contentsOf: history) == settled && (try inode()) == file, "A settings-only save leaves the history file untouched")
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state.history == retitled, "Appended records round-trip")

            store.deleteHistory([old.id], profileID: profile)
            try store.save()
            #expect(try (try records()) == retitled.count - 1 && (try inode()) != file
                       && BrowserHistoryFile.decode(try Data(contentsOf: history)) == Array(retitled.dropFirst()), "Deleting the oldest visit rewrites the file instead of letting it return")
            let kept = store.state.history

            var torn = try Data(contentsOf: history); torn.append(Data("{\"id\":".utf8))
            try torn.write(to: history)
            #expect(BrowserHistoryFile.decode(torn) == kept, "An append cut short is ignored")

            var downgraded = try decoder.decode(BrowserState.self, from: Data(contentsOf: session))
            let newer = BrowserHistoryEntry(id: UUID(), url: "https://older-build.test/", title: "Inline",
                                            visitedAt: Date(timeIntervalSince1970: 4_000), profileID: profile)
            downgraded.history = [newer]
            try encoder.encode(downgraded).write(to: session)
            let merged = try BrowserStore(directory: directory)
            #expect(merged.state.history == kept + [newer], "Visits an older build kept inline merge after the history file's visits")

            try encoder.encode(downgraded).write(to: session)
            var damaged = Data("not json\n".utf8); damaged.append(try BrowserHistoryFile.encode([kept[0]]))
            try damaged.write(to: history)
            let recovered = try BrowserStore(directory: directory)
            #expect(recovered.state.history == [kept[0], newer], "Unreadable lines are skipped, readable visits kept")
            try recovered.save()
            #expect((try records()) == 2, "The next write rewrites the file without the unreadable line")

            recovered.clearHistory(profileID: profile)
            try recovered.save()
            #expect(try recovered.state.history.isEmpty && (try Data(contentsOf: history)).isEmpty, "Clearing history empties the history file")
        }
        try withDirectory { directory in
            let normal = try BrowserStore(directory: directory)
            let parent = normal.activeSpace.profileID
            let privateStore = BrowserStore(privateParentProfileID: parent, engineProfilePath: "/tmp/parc-private-test",
                                            directory: directory, settings: normal.state.settings)
            let tab = privateStore.openResolvedURL(URL(string: "https://private.test/")!, kind: .today)
            privateStore.updateTab(tab, title: "Private", url: "https://private.test/next")
            try privateStore.save()
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(BrowserHistoryFile.name).path), "A private store never writes a history file")
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
            #expect(try !store.state.history.isEmpty && (try Data(contentsOf: history)) == unknown, "A history file with no readable records is left untouched for the session")
        }
        let visit = { (title: String) in BrowserHistoryEntry(id: UUID(), url: "https://x.test/", title: title,
                                                             visitedAt: Date(timeIntervalSince1970: 0), profileID: UUID()) }
        let a = visit("a"), b = visit("b"), c = visit("c")
        #expect(BrowserHistoryFile.appended(from: [a, b], to: [a, b, c]) == [c], "New visits append")
        #expect(BrowserHistoryFile.appended(from: [a, b], to: [b, c]) == nil, "Dropping the oldest below capacity is a deletion and rewrites")
        #expect(BrowserHistoryFile.appended(from: [a, b, c], to: [a, c]) == nil, "A middle deletion rewrites")
        #expect(BrowserHistoryFile.appended(from: [a, b, c], to: [a, b]) == nil, "Removing the newest rewrites")
        #expect(BrowserHistoryFile.appended(from: [a], to: []) == nil && BrowserHistoryFile.appended(from: [], to: [a]) == [a], "Clearing rewrites; a first visit appends")
    }

    @Test static func historyNewestFirstMatchesISO8601RoundTrip() throws {
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
            #expect(BrowserHistoryOrder.newestFirst(loaded).map(\.id)
                        == loaded.sorted { $0.visitedAt > $1.visitedAt }.map(\.id), "Reloaded same-second visits keep the previous date-desc sort")
            #expect(commandBarEmptyQueryRecents(history: loaded, tabURLs: []).map(\.url)
                        == commandBarEmptyQueryRecentsSorted(history: loaded, tabURLs: []).map(\.url), "Empty-query recents keep sort identity after ISO-8601 reload")
        }
    }

    @Test static func historyRevisionTracksVisitRecords() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_000) })
            let start = store.historyRevision
            let id = store.openResolvedURL(URL(string: "https://example.test/start")!, kind: .today)
            #expect(store.historyRevision == start, "Opening a tab does not fabricate history")
            store.updateTab(id, title: "A", url: "https://example.test/a")
            #expect(store.historyRevision == start + 1 && store.state.history.last?.url == "https://example.test/a", "A new visit advances historyRevision")
            store.updateTab(id, title: "A", url: "https://example.test/a")
            #expect(store.historyRevision == start + 1, "An unchanged coalesced title does not rewrite history")
            store.updateTab(id, title: "B", url: "https://example.test/a")
            #expect(store.historyRevision == start + 2 && store.state.history.last?.title == "B", "A coalesced title update advances historyRevision")
            store.clearHistory()
            #expect(store.historyRevision == start + 3 && store.state.history.isEmpty, "Clearing visits advances historyRevision")
        }
    }

    @Test static func navigationInput() throws {
        #expect(NavigationInput.resolve("   ") == nil, "Blank input must not navigate")
        let direct = NavigationInput.resolve(" https://example.org/path?a=1#section ")
        #expect(direct?.absoluteString == "https://example.org/path?a=1#section", "An explicit HTTPS address must preserve its path, query, and fragment")
        let domain = NavigationInput.resolve("example.org/reference")
        #expect(domain?.scheme == "https" && domain?.host == "example.org"
                   && domain?.path == "/reference", "A bare domain must navigate over HTTPS")

        let query = "stars & galaxies #1 + café / Δ"
        guard let url = NavigationInput.resolve(query),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw Failure(description: "Search text did not produce a URL")
        }
        #expect(components.host == "duckduckgo.com", "Search must use the configured search engine")
        #expect(components.fragment == nil, "A search hash must remain part of the query")
        #expect(components.queryItems?.filter { $0.name == "q" }.count == 1, "Search punctuation must not inject another query parameter")
        #expect(components.queryItems?.first { $0.name == "q" }?.value == query, "Search encoding must round-trip Unicode and reserved characters")
    }

    @Test static func corruptFileIsPreserved() throws {
        try withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            try store.save()
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            #expect(files.count == 1, "The model must have one identifiable JSON state file")
            guard let file = files.first else { return }
            let corrupt = Data("{\"intentionally incomplete session\":".utf8)
            try corrupt.write(to: file)
            var rejected = false
            do { _ = try BrowserStore(directory: directory) }
            catch { rejected = true }
            #expect(rejected, "A corrupt session must surface an error instead of silently resetting")
            let after = try Data(contentsOf: file)
            #expect(after == corrupt, "Opening a corrupt session must preserve its original bytes")
        }
    }

    @Test static func sessionRoundTrip() throws {
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
            #expect(reopened.state == expected, "A saved session must preserve profiles, Spaces, folders, tabs, ordering, settings, and split selection")
            #expect(try tab(saved, in: reopened).savedURL == "https://example.org/start", "Navigating a pinned tab must preserve its saved destination across a restart")
            let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("session.json").path)
            #expect((permissions[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Session data must be saved with owner-only permissions")
            try expectValidSelection(reopened)
        }
    }

    @Test static func sessionSaveRoundTripIdentity() throws {
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
            #expect(savedText?.hasPrefix("{\n") == true && savedText?.contains("\n  \"") == true, "Existing sessions stay pretty-printed; this is not a format change")
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect((permissions[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Off-main replace still uses owner-only permissions")

            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let fromDisk = try decoder.decode(BrowserState.self, from: savedBytes)
            var expected = store.state; expected.windows = store.windowRecords; expected.history = []
            #expect(fromDisk == expected, "Load of the saved file yields the exact persisted BrowserState")
            let savedHistory = BrowserHistoryFile.decode(
                try Data(contentsOf: directory.appendingPathComponent(BrowserHistoryFile.name)))
            #expect(!savedHistory.isEmpty && savedHistory == store.state.history, "Visits persist in history.jsonl, not inline in session.json")

            let compactEncoder = JSONEncoder(); compactEncoder.dateEncodingStrategy = .iso8601
            try compactEncoder.encode(expected).write(to: file)
            let fromCompact = try BrowserStore(directory: directory, now: { date })
            #expect(fromCompact.state == store.state && fromCompact.windowRecords == store.windowRecords, "JSONDecoder does not depend on pretty-printed or sorted keys")
            try fromCompact.save()
            let restored = try decoder.decode(BrowserState.self, from: Data(contentsOf: file))
            #expect(restored == expected, "Re-saving an existing session preserves BrowserState identity")

            store.updateTab(tabID, title: "Live title")
            store.updateTab(tabID, title: "Final title")
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let delayed = try BrowserStore(directory: directory, now: { date })
            #expect(delayed.state.tabs.first { $0.id == tabID }?.title == "Final title", "The 0.25s debounce still writes the last mutation")

            let beforePrivate = try Data(contentsOf: file)
            let privateStore = BrowserStore(privateParentProfileID: store.activeSpace.profileID,
                engineProfilePath: "/disposable", directory: directory, settings: store.state.settings, now: { date })
            let privateID = privateStore.open("https://private.example.test")
            privateStore.updateTab(privateID, title: "Secret")
            try privateStore.save()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            #expect(try Data(contentsOf: file) == beforePrivate, "Ephemeral stores still skip disk")

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
            #expect(settingsFailed && pendingStore.persistenceError != nil, "A refused settings commit reports the real failure")
            #expect(pendingStore.state.profiles.count == 1, "A failed settings commit must not publish the profile")
            try FileManager.default.removeItem(at: pendingFile)
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let recovered = try BrowserStore(directory: pendingDirectory)
            #expect(recovered.state.tabs.contains { $0.url == "https://pending-save.example.org" }, "A failed settings commit must not drop an already-scheduled session persist")
        }
    }
}
