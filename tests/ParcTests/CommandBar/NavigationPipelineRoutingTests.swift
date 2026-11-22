import AppKit
import ParcEngine
import Testing
@testable import Parc
@testable import ParcCore

extension NavigationPipelineTests.Fixture {
    func input() throws -> CommandBarInputField {
        try #require(try surface().subviews.compactMap { $0 as? CommandBarInputField }.first)
    }

    func editor() throws -> NSTextView {
        try #require(try input().currentEditor() as? NSTextView)
    }

    func table() throws -> CommandResultsTable {
        try #require(try surface().subviews.compactMap { $0 as? CommandResultsScrollView }.first?.documentView as? CommandResultsTable)
    }

    func scopeOffer() throws -> CommandBarScopeHint? {
        try surface().subviews.compactMap { $0 as? CommandBarScopeHint }.first
    }

    func move(_ command: String) throws {
        let field = try input()
        let textView = try editor()
        #expect(bar.control(field, textView: textView, doCommandBy: NSSelectorFromString(command)))
    }

    func choose(_ text: String) throws {
        for _ in 0...labels().count {
            let row = try table().selectedRow
            if labels().indices.contains(row), labels()[row].contains(text) { return }
            try move("moveDown:")
        }
        Issue.record("no row containing \(text)")
    }
}

extension NavigationPipelineTests {
    @Test @MainActor func asyncRecentPagesKeepTheCurrentAddressFirstWithoutDuplicatingIt() throws {
        let address = "https://example.test/current"
        let fixture = try Fixture(address: address, compact: true)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.bar.updateRecentPages([(address, "Current page"), ("https://example.test/recent", "Recent page")])
        let labels = fixture.labels()
        #expect(labels.count == 2)
        #expect(labels.first?.contains("Current page") == true)
        #expect(labels.last?.contains("Recent page") == true)
    }

    @Test(arguments: [false, true])
    @MainActor func theCompactEmptyEditorLeavesOutLocalDocumentTabs(compact: Bool) throws {
        let noteFile = URL(fileURLWithPath: "/Users/example/Documents/Parc Notes/Example Note.md")
        let web = tab("https://example.com/", title: "Example")
        let note = tab(InternalPage.note(noteFile).urlString, title: "Example Note")
        let fixture = try Fixture(compact: compact, tabs: [web, note])
        defer { fixture.bar.dismiss(restoreFocus: false) }
        #expect(fixture.labels().count == (compact ? 1 : 2))
    }

    @Test(arguments: [false, true])
    @MainActor func passwordManagementBelongsToTheFullPaletteOnly(compact: Bool) throws {
        let fixture = try Fixture(query: "password", compact: compact)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        #expect(fixture.labels().contains { $0.contains("Manage Passwords") } == !compact)
    }

    @Test(arguments: [false, true])
    @MainActor func aTabSuggestionKeepsWebsiteSearchOnBothSurfaces(compact: Bool) throws {
        let fixture = try Fixture(query: "example", compact: compact, tabs: [tab("https://example.com/", title: "Example")])
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish("example", results: [search("example")], scopes: [["host": "example.com"]])
        let offer = try #require(try fixture.scopeOffer())
        #expect(!offer.isHidden)
        #expect(offer.accessibilityLabel() == "Search example.com")
    }

    static let websiteTypes = ["url-what-you-typed", "history-url", "history-title", "navsuggest", "bookmark-title",
                               "navsuggest-personalized", "history-body", "history-embeddings", "future-navigation-type"]

    @Test(arguments: websiteTypes, [false, true])
    @MainActor func aLeadingWebsiteKeepsItsDestinationAndSiteSearch(type: String, alreadyOpen: Bool) throws {
        let query = "youtube.com"
        let open = tab("https://www.youtube.com/", title: "YouTube")
        let fixture = try Fixture(query: query, tabs: alreadyOpen ? [open] : [])
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish(query, results: [["url": "https://www.youtube.com/", "title": query, "detail": "YouTube", "type": type],
                                         search(query)], scopes: [["host": "www.youtube.com"]])
        let offer = try #require(try fixture.scopeOffer())
        #expect(!offer.isHidden)
        var navigation: URL?, selected: UUID?
        fixture.bar.onSearchNavigation = { navigation = $0.url }
        fixture.bar.onSelectTab = { selected = $0 }
        try fixture.pressReturn()
        #expect(selected == (alreadyOpen ? open.id : nil))
        #expect(navigation == (alreadyOpen ? nil : URL(string: "https://www.youtube.com/")))
    }

    @Test(arguments: ["search-suggest-personalized", "future-search-type"])
    @MainActor func aLeadingSearchOfAnyKindKeepsItsRequest(type: String) throws {
        let fixture = try Fixture(query: "weather tomorrow")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish("weather tomorrow", results: [["url": "https://search.example.test/", "search": true,
                                                        "title": "weather tomorrow", "type": type]])
        var actual: PCNativeSearchNavigation?
        fixture.bar.onSearchNavigation = { actual = $0 }
        try fixture.pressReturn()
        #expect(actual?.search == true)
        #expect(actual?.url == URL(string: "https://search.example.test/"))
    }

    @Test(arguments: [CommandBarSubmission.ordinary, .split, .background], [false, true])
    @MainActor func returnWhileAnAnswerIsPendingUsesTheCorrectInput(disposition: CommandBarSubmission, explicit: Bool) throws {
        let fixture = try Fixture(query: "you")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish("you", results: [search("you")])
        try fixture.edit("youtube.com")
        if explicit { try fixture.move("moveDown:") }
        var received: String?
        fixture.bar.canSplitSelection = { _ in true }
        fixture.bar.onNavigate = { input, _ in received = input }
        fixture.bar.onSearchNavigation = { received = $0.editText }
        fixture.bar.onSplitInput = { input, _ in received = input }
        fixture.bar.onSplitNavigation = { received = $0.editText }
        fixture.bar.onBackgroundInput = { input, _, _, complete in received = input; complete(nil) }
        fixture.bar.onBackgroundNavigation = { navigation, _, complete in received = navigation.editText; complete(nil) }
        let flags: NSEvent.ModifierFlags
        switch disposition {
        case .ordinary: flags = []
        case .split: flags = .option
        case .background: flags = [.command, .option]
        }
        try fixture.pressReturn(flags)
        #expect(received == (explicit ? "you" : "youtube.com"))
    }

    @Test @MainActor func aLeadingExtensionActionStaysFirstAndFiltersTheRest() throws {
        let fixture = try Fixture(query: "keyword")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish("keyword", results: [["url": "https://example.test/", "title": "Bookmarked example", "type": "bookmark-title"],
                                             search("keyword")],
                        extensions: [["index": 0, "title": "Extension search", "detail": "Fixture extension", "editText": "keyword"]])
        let labels = fixture.labels()
        #expect(labels.first?.contains("Extension search") == true)
        #expect(!labels.contains { $0.contains("Bookmarked example") })
    }

    @Test func tabsOfAnotherSpaceAreTheOnlyEligibleSwitchTargets() {
        let profile = UUID(), space = UUID()
        func tab(profile: UUID = profile, space: UUID = space, archived: Bool = false) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space, profileID: profile, url: "https://www.google.com/", title: "Google",
                       kind: .today, folderID: nil, createdAt: .distantPast, lastAccessed: .distantPast,
                       archivedAt: archived ? Date() : nil, savedURL: "https://www.google.com/", savedTitle: "Google")
        }
        let current = tab(), other = tab(space: UUID()), foreign = tab(profile: UUID()), archived = tab(archived: true)
        let closing = tab(), retiring = tab(), transferring = tab()
        let eligible = CommandBarTabEligibility.tabs([current, other, foreign, archived, closing, retiring, transferring],
                                                     profileID: profile, excluding: current.id,
                                                     unavailable: [closing.id, retiring.id, transferring.id])
        #expect(eligible.map(\.id) == [other.id])
    }
}
