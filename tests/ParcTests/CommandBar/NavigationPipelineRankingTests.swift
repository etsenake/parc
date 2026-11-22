import AppKit
import ParcEngine
import Testing
@testable import ParcCore
@testable import ParcCommandBar

extension NavigationPipelineTests {
    private static let profile = UUID()
    private static let okta = "https://fullscript.okta.com/app/UserHome?iss=https%3A%2F%2Ffullscript.okta.com&login_hint=someone%40example.com&session_hint=AUTHENTICATED"
    private static let oktaShown = String(okta.dropFirst("https://".count))
    private static let oktaRoot = "https://fullscript.okta.com/"
    private static let oktaVisits = Array(repeating: (url: okta, title: "Fullscript - My Apps"), count: 40) + [(url: oktaRoot, title: "")]
    private static let dashboardTitle = "My Apps Dashboard | Fullscript"
    private static let suggestions = ["dashboard", "dashboard meaning", "dashboard camera", "dashboard lights",
                                      "dashboard design", "dashboard ui"]

    private func profileTab(_ url: String, title: String, archivedAgo: TimeInterval? = nil) -> BrowserTab {
        BrowserTab(id: UUID(), spaceID: UUID(), profileID: Self.profile, url: url, title: title, kind: .today, folderID: nil,
                   createdAt: Date(), lastAccessed: Date(), archivedAt: archivedAgo.map { Date().addingTimeInterval(-$0) },
                   savedURL: url, savedTitle: title)
    }

    private func visit(_ url: String, _ title: String, daysAgo: Double) -> BrowserHistoryEntry {
        BrowserHistoryEntry(id: UUID(), url: url, title: title, visitedAt: Date().addingTimeInterval(-daysAgo * 86_400),
                            profileID: Self.profile)
    }

    private struct Library {
        let dashboard: BrowserTab
        let archived: BrowserTab
        let pastVisits: [BrowserHistoryEntry]

        var index: CommandBarTitleIndex { build(tabs: [dashboard, archived]) }

        func build(tabs: [BrowserTab], reusing: CommandBarTitleIndex? = nil) -> CommandBarTitleIndex {
            CommandBarTitleIndex.build(profileID: NavigationPipelineTests.profile, historyRevision: 4, tabs: tabs,
                                       history: pastVisits, reusing: reusing)
        }
    }

    private func library() -> Library {
        Library(dashboard: profileTab("https://us.fullscript.com/dashboard", title: Self.dashboardTitle),
                archived: profileTab("https://docs.example.com/q3", title: "Q3 Dashboard Review", archivedAgo: 3 * 86_400 + 5),
                pastVisits: [visit("https://wiki.example.com/dash", "Team dashboard handbook", daysAgo: 40),
                             visit("https://dashboard.example.org/start", "", daysAgo: 50)])
    }

    @MainActor private func dashboardFixture(_ library: Library, index: CommandBarTitleIndex? = nil) throws -> Fixture {
        let fixture = try Fixture(query: "dashboard", tabs: [library.dashboard])
        if let index { fixture.bar.updateTitleIndex(index, historyRemovals: 0) }
        fixture.publish("dashboard", results: Self.suggestions.map(search))
        return fixture
    }

    @Test @MainActor func aMidTitleWordOfAnOpenTabFollowsChromiumsDefaultSearch() throws {
        let fixture = try Fixture(query: "dashboard", tabs: [profileTab("https://news.example/", title: "Morning news"),
                                                              profileTab("https://us.fullscript.com/dashboard", title: Self.dashboardTitle)])
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish("dashboard", results: Self.suggestions.map(search))
        let labels = fixture.labels()
        #expect(labels.first?.contains("dashboard") == true)
        #expect(labels.dropFirst().first?.contains(Self.dashboardTitle) == true)
    }

    @Test @MainActor func anArchivedTabComesBackAsItsOwnRowAndReturnPutsItBack() throws {
        let library = library()
        let fixture = try dashboardFixture(library, index: library.index)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        let row = try #require(fixture.labels().first { $0.contains("Q3 Dashboard Review") })
        #expect(row.contains("3 days ago"))
        var restored: UUID?
        fixture.bar.onRestoreArchived = { restored = $0; return true }
        try fixture.choose("Q3 Dashboard Review")
        try fixture.pressReturn()
        #expect(restored == library.archived.id)
    }

    @Test @MainActor func aPastPageFoundByTitleOpensItsOwnAddress() throws {
        let library = library()
        let fixture = try dashboardFixture(library, index: library.index)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        var opened: String?
        fixture.bar.onNavigate = { input, _ in opened = input }
        try fixture.choose("Team dashboard handbook")
        try fixture.pressReturn()
        #expect(opened == "https://wiki.example.com/dash")
    }

    @Test @MainActor func anUntitledPastPageShowsItsAddressOnce() throws {
        let library = library()
        let fixture = try dashboardFixture(library, index: library.index)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        let row = try #require(fixture.labels().first { $0.contains("dashboard.example.org/start") })
        #expect(row.components(separatedBy: "dashboard.example.org/start").count == 2)
    }

    @Test @MainActor func aTypedAddressAddsNoTitleRows() throws {
        let library = library()
        let fixture = try Fixture(query: "us.fullscript.com/dash", tabs: [library.dashboard])
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.bar.updateTitleIndex(library.index, historyRemovals: 0)
        fixture.publish("us.fullscript.com/dash", results: [
            ["url": "https://us.fullscript.com/dashboard", "title": "us.fullscript.com/dashboard"],
            search("us.fullscript.com/dash"),
        ])
        var selected: UUID?
        fixture.bar.onSelectTab = { selected = $0 }
        try fixture.pressReturn()
        #expect(selected == library.dashboard.id)
        #expect(!fixture.labels().contains { $0.contains("Q3 Dashboard Review") })
    }

    @Test @MainActor func anIndexArrivingWhileARowIsPickedWaitsInsteadOfMovingRows() throws {
        let library = library()
        let fixture = try dashboardFixture(library)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        try fixture.move("moveDown:")
        let before = fixture.labels()
        fixture.bar.updateTitleIndex(library.index, historyRemovals: 0)
        #expect(fixture.labels() == before)
    }

    @Test @MainActor func aTabThatLeftTheArchiveStopsShowingAtOnceEvenWhileARowIsPicked() throws {
        let library = library()
        let first = library.index
        let fixture = try dashboardFixture(library, index: first)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        try fixture.move("moveDown:")
        #expect(fixture.labels().contains { $0.contains("Q3 Dashboard Review") })
        var restored = library.archived
        restored.archivedAt = nil
        fixture.bar.updateTitleIndex(library.build(tabs: [library.dashboard, restored], reusing: first), historyRemovals: 0)
        #expect(!fixture.labels().contains { $0.contains("Q3 Dashboard Review") })
    }

    @Test @MainActor func deletingHistoryOfUnknownScopeKeepsArchivedRowsButOffersNoPastPages() throws {
        let library = library()
        let fixture = try dashboardFixture(library)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.bar.removedHistoryURLs = { _ in nil }
        fixture.bar.updateTitleIndex(library.index, historyRemovals: 1)
        let labels = fixture.labels()
        #expect(labels.contains { $0.contains("Q3 Dashboard Review") })
        #expect(!labels.contains { $0.contains("Team dashboard handbook") || $0.contains("dashboard.example.org/start") })
    }

    @Test @MainActor func deletingOnePageHidesOnlyThatPage() throws {
        let library = library()
        let fixture = try dashboardFixture(library)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.bar.removedHistoryURLs = { _ in ["https://wiki.example.com/dash"] }
        fixture.bar.updateTitleIndex(library.index, historyRemovals: 1)
        let labels = fixture.labels()
        #expect(!labels.contains { $0.contains("Team dashboard handbook") })
        #expect(labels.contains { $0.contains("dashboard.example.org/start") })
    }

    @MainActor private func typedFixture(_ typed: String, visits: [(url: String, title: String)]? = nil, tabs: [BrowserTab] = [],
                              leading: [[String: Any]] = [], extra: [[String: Any]] = []) throws -> Fixture {
        let fixture = try Fixture(tabs: tabs)
        try fixture.edit(typed)
        fixture.bar.updateTopDomains(CommandBarRanking.topDomains(visits ?? Self.oktaVisits))
        var deep: [String: Any] = ["url": Self.okta, "title": Self.oktaShown, "detail": "Fullscript - My Apps", "type": "history-url"]
        if Self.oktaShown.hasPrefix(typed.lowercased()) { deep["inlineCompletion"] = typed + Self.oktaShown.dropFirst(typed.count) }
        fixture.publish(typed, results: leading + [deep, search(typed)] + (1...4).map { search("\(typed) \($0)") } + extra)
        return fixture
    }

    @Test(arguments: [("fullscript.ok", "fullscript.okta.com"), ("Fullscript.OK", "Fullscript.OKta.com"),
                      ("www.fullscript.ok", "www.fullscript.okta.com"), ("fullscript.okta.com", "fullscript.okta.com")])
    @MainActor func aRedirectedSiteLeadsAndOnlyItsDomainIsFilledIn(typed: String, filled: String) throws {
        let fixture = try typedFixture(typed)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        let labels = fixture.labels()
        #expect(labels.first?.hasPrefix("fullscript.okta.com") == true)
        #expect(labels.dropFirst().first?.contains("Fullscript - My Apps") == true)
        let editor = try fixture.editor()
        #expect(editor.string == filled)
        #expect(editor.selectedRange() == NSRange(location: typed.utf16.count, length: filled.utf16.count - typed.utf16.count))
        var input: String?, navigation: PCNativeSearchNavigation?
        fixture.bar.onNavigate = { input = $0; _ = $1 }
        fixture.bar.onSearchNavigation = { navigation = $0 }
        try fixture.pressReturn()
        #expect(input == Self.oktaRoot)
        #expect(navigation == nil)
    }

    @Test(arguments: [("fullscript.okta.com/", true), ("fullscript.okta.com/app", true), ("fullscript.okta.com/app/UserHome?iss", false)])
    @MainActor func pastTheDomainChromiumsDefaultLeadsWithItsOwnCompletionWhenItOffersOne(typed: String, offered: Bool) throws {
        let fixture = try typedFixture(typed)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        #expect(fixture.labels().first?.contains("Fullscript - My Apps") == true)
        #expect(try fixture.editor().string == (offered ? Self.oktaShown : typed))
        var navigation: PCNativeSearchNavigation?
        fixture.bar.onSearchNavigation = { navigation = $0 }
        try fixture.pressReturn()
        #expect(navigation?.url.absoluteString == Self.okta)
    }

    @Test @MainActor func arrowingBetweenTheSiteAndChromiumsRowShowsEachOnesOwnText() throws {
        let fixture = try typedFixture("fullscript.ok")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        try fixture.move("moveDown:")
        #expect(try fixture.editor().string == Self.oktaShown)
        try fixture.move("moveUp:")
        #expect(try fixture.editor().string == "fullscript.okta.com")
        try fixture.move("moveDown:")
        var navigation: PCNativeSearchNavigation?
        fixture.bar.onSearchNavigation = { navigation = $0 }
        try fixture.pressReturn()
        #expect(navigation?.url.absoluteString == Self.okta)
    }

    @Test(arguments: [Self.oktaVisits.count, 0])
    @MainActor func chromiumsOwnRootRowLeadsWithOrWithoutSiteVisits(visits: Int) throws {
        let root: [String: Any] = ["url": Self.oktaRoot, "title": "fullscript.okta.com/", "detail": "Okta", "type": "history-url"]
        let fixture = try typedFixture("fullscript.ok", visits: Array(Self.oktaVisits.prefix(visits)), extra: [root])
        defer { fixture.bar.dismiss(restoreFocus: false) }
        #expect(fixture.labels().dropFirst().first?.contains("Fullscript - My Apps") == true)
        #expect(try fixture.editor().string == "fullscript.okta.com")
        var navigation: PCNativeSearchNavigation?
        fixture.bar.onSearchNavigation = { navigation = $0 }
        try fixture.pressReturn()
        #expect(navigation?.url.absoluteString == Self.oktaRoot)
    }

    @Test @MainActor func aTabAlreadyOnTheSitesRootLeadsAndNeverGainsInlineCompletion() throws {
        let open = profileTab(Self.oktaRoot, title: "Okta")
        let fixture = try typedFixture("fullscript.ok", tabs: [open])
        defer { fixture.bar.dismiss(restoreFocus: false) }
        #expect(fixture.labels().dropFirst().first?.contains("Fullscript - My Apps") == true)
        #expect(try fixture.editor().string == "fullscript.ok")
        var selected: UUID?
        fixture.bar.onSelectTab = { selected = $0 }
        try fixture.pressReturn()
        #expect(selected == open.id)
    }

    @Test @MainActor func withNoRowForTheSiteChromiumsDefaultKeepsTheLeadAndItsCompletion() throws {
        let fixture = try typedFixture("fullscript.ok", visits: [])
        defer { fixture.bar.dismiss(restoreFocus: false) }
        #expect(try fixture.editor().string == Self.oktaShown)
        var navigation: PCNativeSearchNavigation?
        fixture.bar.onSearchNavigation = { navigation = $0 }
        try fixture.pressReturn()
        #expect(navigation?.url.absoluteString == Self.okta)
    }

    @Test @MainActor func aSearchDefaultIsNeverDisplacedByASite() throws {
        let fixture = try typedFixture("fullscript.ok", leading: [search("fullscript.ok things")])
        defer { fixture.bar.dismiss(restoreFocus: false) }
        var navigation: PCNativeSearchNavigation?
        fixture.bar.onSearchNavigation = { navigation = $0 }
        try fixture.pressReturn()
        #expect(navigation?.search == true)
    }

    @Test @MainActor func theLeadBelongsToTheDefaultsOwnSiteNotTheBusiestMatch() throws {
        let busier = Self.oktaVisits + Array(repeating: (url: "https://fullscript.com/", title: "Fullscript"), count: 60)
        let fixture = try typedFixture("fullscript.", visits: busier)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        #expect(fixture.labels().first?.hasPrefix("fullscript.okta.com") == true)
    }

    @Test @MainActor func aLocalServersLeadKeepsItsPort() throws {
        let fixture = try Fixture()
        defer { fixture.bar.dismiss(restoreFocus: false) }
        try fixture.edit("localhost:30")
        fixture.bar.updateTopDomains(CommandBarRanking.topDomains([("http://localhost:3000/a", ""), ("http://localhost:3000/b", "")]
            + Array(repeating: ("http://localhost:8080/", "Other"), count: 5)))
        fixture.publish("localhost:30", results: [
            ["url": "http://localhost:3000/dashboard", "title": "localhost:3000/dashboard", "type": "history-url"],
            search("localhost:30"),
        ])
        var input: String?
        fixture.bar.onNavigate = { input = $0; _ = $1 }
        try fixture.pressReturn()
        #expect(input == "http://localhost:3000/")
    }

    private var signIn: String {
        "https://fullscript.okta.com/app/UserHome?fromHome=true&iss=https%3A%2F%2Ffullscript.okta.com"
            + "&login_hint=someone%40example.com&session_hint=AUTHENTICATED"
    }

    @Test @MainActor func aSignInPageShowsOnceNamesItsSiteAndKeepsItsFullAddress() throws {
        let fixture = try Fixture(query: "my apps")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        let pending = signIn.replacingOccurrences(of: "AUTHENTICATED", with: "PENDING")
        fixture.publish("my apps", results: [
            search("my apps"),
            ["url": signIn, "title": String(signIn.dropFirst(8)), "detail": Self.dashboardTitle, "type": "history-url"],
            ["url": pending, "title": "fullscript.okta.com/app/UserHome", "detail": Self.dashboardTitle, "type": "history-url"],
        ])
        let pages = fixture.labels().filter { $0.contains(Self.dashboardTitle) }
        #expect(pages.count == 1)
        #expect(pages.first?.contains("fullscript.okta.com") == true)
        var navigation: PCNativeSearchNavigation?
        fixture.bar.onSearchNavigation = { navigation = $0 }
        try fixture.choose(Self.dashboardTitle)
        try fixture.pressReturn()
        #expect(navigation?.url.absoluteString == signIn)
    }

    @Test @MainActor func anOpenTabForTheSignInPageKeepsItsSwitchRow() throws {
        let open = profileTab("https://fullscript.okta.com/app/UserHome?fromHome=true", title: Self.dashboardTitle)
        let fixture = try Fixture(query: "my apps", tabs: [open])
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish("my apps", results: [
            search("my apps"),
            ["url": signIn, "title": String(signIn.dropFirst(8)), "detail": Self.dashboardTitle, "type": "history-url"],
        ])
        #expect(fixture.labels().filter { $0.contains(Self.dashboardTitle) }.count == 1)
        var selected: UUID?
        fixture.bar.onSelectTab = { selected = $0 }
        try fixture.choose(Self.dashboardTitle)
        try fixture.pressReturn()
        #expect(selected == open.id)
    }

    @Test @MainActor func anUntitledVisitShowsItsHostAndPathOnceAndKeepsItsAddress() throws {
        let fixture = try Fixture(query: "fullscript.okta.com/app")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish("fullscript.okta.com/app", results: [
            ["url": signIn, "title": String(signIn.dropFirst(8)), "type": "history-url"], search("fullscript.okta.com/app"),
        ])
        let first = try #require(fixture.labels().first)
        #expect(first.contains("fullscript.okta.com/app/UserHome"))
        #expect(!first.contains("fromHome"))
        var navigation: PCNativeSearchNavigation?
        fixture.bar.onSearchNavigation = { navigation = $0 }
        try fixture.pressReturn()
        #expect(navigation?.url.absoluteString == signIn)
    }

    @Test @MainActor func recentsDropSignInRepeatsOfTheOpenTabAndKeepDifferentVideos() throws {
        let open = profileTab("https://fullscript.okta.com/app/UserHome?fromHome=true", title: Self.dashboardTitle)
        let fixture = try Fixture(tabs: [open])
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.bar.updateRecentPages([
            (signIn, Self.dashboardTitle), (signIn + "&again=1", Self.dashboardTitle),
            ("https://fullscript.okta.com/app/Other?x=1", ""),
            ("https://www.youtube.com/watch?v=1", "First video - YouTube"),
            ("https://www.youtube.com/watch?v=2", "Second video - YouTube"),
        ])
        let labels = fixture.labels()
        #expect(labels.count == 4)
        #expect(labels[0].contains(Self.dashboardTitle))
        #expect(labels[1].contains("fullscript.okta.com/app/Other"))
        #expect(labels[2].contains("First video - YouTube") && labels[2].contains("youtube.com"))
        #expect(labels[3].contains("Second video - YouTube"))
    }
}
