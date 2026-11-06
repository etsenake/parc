import Foundation

@main struct SavedTabResetEligibilityTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        // These are reference contract cases, not navigation canonicalization.
        let equivalent: [(String, String)] = [
            ("https://example.test/home", "https://example.test/home"),
            ("http://example.test/home", "https://example.test/home"),
            ("https://www.example.test/home", "https://example.test/home"),
            ("https://WWW.Example.test/HOME?Mode=FULL", "https://example.test/home?mode=full"),
            ("https://example.test/home#section", "https://example.test/home#other"),
            ("https://example.test/home/", "https://example.test/home"),
            ("https://example.test/", "https://example.test"),
            ("https://example.test/home#", "https://example.test/home"),
            ("https://example.test/home?utm_source=mail&x=1", "https://example.test/home?x=1"),
            ("https://example.test/home?x=1&UTM_CAMPAIGN=MAIL", "https://example.test/home?x=1"),
            ("https://example.test/home?empty=&flag&x=1", "https://example.test/home?x=1"),
            ("https://example.test/home?utm_source=mail&empty=", "https://example.test/home"),
            ("https://example.test/home?", "https://example.test/home"),
            ("https://example.test/home/#!/route/", "https://example.test/home/#!/route"),
            ("//www.example.test/home", "https://example.test/home"),
            ("www.example.test/home", "https://example.test/home"),
        ]
        for (left, right) in equivalent {
            check(!SavedTabURLComparison.isAway(current: URL(string: left), saved: URL(string: right)), "Equivalent: \(left) versus \(right)")
            check(!SavedTabURLComparison.isAway(current: URL(string: right), saved: URL(string: left)), "Symmetric equivalence: \(right)")
        }
        let distinct: [(String, String)] = [
            ("https://example.test/home", "https://example.test/other"),
            ("https://example.test/home", "https://other.test/home"),
            ("https://example.test/home?x=1", "https://example.test/home?x=2"),
            ("https://example.test/home?a=1&b=2", "https://example.test/home?b=2&a=1"),
            ("https://example.test/home?x=1&x=1", "https://example.test/home?x=1"),
            ("https://example.test/home?gclid=id", "https://example.test/home"),
            ("https://example.test/home?utm=keep", "https://example.test/home"),
            ("https://example.test/home?flag=%20", "https://example.test/home"),
            ("https://example.test/home//", "https://example.test/home"),
            ("https://example.test/home/#!/route", "https://example.test/home#!/route"),
            ("https://example.test/home#!/one", "https://example.test/home#!/two"),
            ("https://example.test/home#!/route//", "https://example.test/home#!/route"),
            ("https://example.test/home#!", "https://example.test/home"),
            ("https://example.test:443/home", "https://example.test/home"),
            ("https://person:secret@example.test/home", "https://example.test/home"),
            ("https://www.www.example.test/home", "https://example.test/home"),
            ("ftp://example.test/home", "https://example.test/home"),
            ("https://example.test/home?x=%61", "https://example.test/home?x=a"),
            ("www.example.test/home/", "https://example.test/home"),
        ]
        for (left, right) in distinct {
            check(SavedTabURLComparison.isAway(current: URL(string: left), saved: URL(string: right)), "Distinct: \(left) versus \(right)")
            check(SavedTabURLComparison.isAway(current: URL(string: right), saved: URL(string: left)), "Symmetric difference: \(right)")
        }
        check(!SavedTabURLComparison.isAway(current: nil, saved: URL(string: "https://example.test")), "Missing current metadata has no away verdict")
        check(!SavedTabURLComparison.isAway(current: URL(string: "https://example.test"), saved: nil), "Missing home has no away verdict")

        let now = Date(timeIntervalSince1970: 1000)
        var state = BrowserState.initial()
        let profile = state.profiles[0].id, space = state.activeSpaceID
        let saved = "http://WWW.Example.test/Home/?utm_source=Mail#Saved"
        var tab = BrowserTab(id: UUID(), spaceID: space, profileID: profile,
            url: "https://example.test/home#current", title: "Live", kind: .pinned,
            createdAt: now, lastAccessed: now, savedURL: saved, savedTitle: "Saved", customTitle: "Mine")
        let unchanged = tab
        check(tab.resetDestination == nil, "Pinned equivalent home has no Reset")
        tab.kind = .favorite
        check(tab.resetDestination == nil, "Favorite shares exact same predicate")
        tab.url = "https://example.test/other?utm_source=Current"
        check(tab.resetDestination?.absoluteString == saved, "Reset returns untouched original saved URL")
        check(tab.url == "https://example.test/other?utm_source=Current", "Eligibility never mutates current navigation")
        tab.kind = .today
        check(tab.resetDestination == nil, "Today never gains saved Reset")
        tab.kind = .pinned; tab.archivedAt = now
        check(tab.resetDestination == nil, "Archived item cannot Reset")
        tab.archivedAt = nil; tab.url = "parc://note/" + UUID().uuidString
        check(tab.resetDestination == nil, "Local current document excluded")
        tab.url = "https://example.test/other"; tab.savedURL = "parc://easel/" + UUID().uuidString
        check(tab.resetDestination == nil, "Local saved document excluded")
        tab.savedURL = "example.test/home"
        check(tab.resetDestination == nil, "Stored destination still requires actual scheme")
        tab = unchanged; state.tabs = [tab]; state.selectedTabIDs = [tab.id]
        state.settings.restoreSession = true
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SavedReset-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: directory, now: { now })
        let before = store.state
        store.resetDormantSavedTab(store.state.tabs[0])
        check(store.state == before, "Unclaimed equivalent dormant item is untouched")
        store.updateTab(tab.id, title: "Different", url: "https://example.test/other")
        let away = store.state.tabs.first { $0.id == tab.id }!
        store.resetDormantSavedTab(away)
        let reset = store.state.tabs.first { $0.id == tab.id }!
        check(reset.url == saved && reset.savedURL == saved, "Dormant reset preserves exact original destination")
        check(reset.id == tab.id && reset.profileID == profile && reset.customTitle == "Mine", "Reset preserves original identity and custom title")
        check(store.state.selectedTabIDs == before.selectedTabIDs, "Reset leaves original selection intact")
        store.resetDormantSavedTab(away)
        check(store.state.tabs.first { $0.id == tab.id } == reset, "Old snapshot cannot reset a replacement state")

        //
        // become a new Today tab at the top of Today; the pinned item returns home.
        let today = store.openResolvedURL(URL(string: "https://today.test/")!)
        store.updateTab(tab.id, title: "Away", url: "https://example.test/away")
        let pinned = store.state.tabs.first { $0.id == tab.id }!
        let selection = store.state.selectedTabIDs, separated = UUID()
        check(!store.separateFromPinnedTab(away, todayID: separated, title: "Away"), "A stale pinned snapshot cannot separate")
        check(store.separateFromPinnedTab(pinned, todayID: separated, title: "Away page"), "A navigated-away pinned tab separates")
        let moved = store.state.tabs.first { $0.id == separated }!
        let home = store.state.tabs.first { $0.id == tab.id }!
        check(moved.kind == .today && moved.url == "https://example.test/away" && moved.title == "Away page"
              && moved.savedURL == moved.url && moved.customTitle == nil && moved.referrerID == nil
              && moved.spaceID == space && moved.profileID == profile, "The live page's URL and title become a plain Today tab")
        check(home.url == saved && home.title == "Saved" && home.kind == .pinned && home.customTitle == "Mine"
              && home.savedURL == saved && home.folderID == pinned.folderID, "The pinned item keeps its identity and returns home")
        let todayItems = SidebarHierarchy.children(in: .init(spaceID: space, folderID: nil, section: .today), state: store.state)
        check(todayItems == [.tab(separated), .tab(today)], "The separated tab enters the top of Today")
        check(store.state.selectedTabIDs == selection, "Separation leaves selection to the window")
        check(!store.separateFromPinnedTab(home, todayID: UUID(), title: ""), "A pinned item at home has nothing to separate")
        check(!store.separateFromPinnedTab(moved, todayID: UUID(), title: ""), "A Today tab has no pinned home")
        store.updateTab(tab.id, url: "https://example.test/again")
        let again = store.state.tabs.first { $0.id == tab.id }!
        check(!store.separateFromPinnedTab(again, todayID: separated, title: ""), "An existing identity is never reused")
        store.setSplit([tab.id, today])
        check(!store.separateFromPinnedTab(again, todayID: UUID(), title: ""), "A split child has no reset target to separate")
        print("\(checks) saved-tab Reset URL-equivalence and separation assertions passed (no browser)")
    }
}
