import AppKit

// Engine publications are inert reference objects, so these tests can assert
// that the exact request survives the production pipeline without a browser,
// a Profile, a network request or a synthetic URL-classification algorithm.
final class PCNativeSearchNavigation {
    let url: URL
    let search: Bool
    let title: String
    let detail: String
    let editText: String
    let matchType: String?
    init(_ url: String, search: Bool = false, title: String = "", detail: String = "", type: String? = "url-what-you-typed") {
        self.url = URL(string: url)!; self.search = search; self.title = title
        self.detail = detail; editText = title; matchType = type
    }
}
final class PCNativeOmniboxExtensionAction {
    let extensionID = "fixture"
    let editText = "keyword"
    let title = "Extension search"
    let detail = "Fixture extension"
    let resultIndex: Int
    init(index: Int) { resultIndex = index }
}
final class PCNativeExtensionAction {
    let identifier = "fixture", name = "Fixture Extension"
    let generation = 0, modelIndex = 0
}
final class PCNativeOmniboxScope {
    let searchHost: String
    var result: PCNativeSearchNavigation?
    var extensionAction: PCNativeOmniboxExtensionAction?
    var isExtension = false
    init(_ host: String) { searchHost = host }
}
enum KeyboardShortcuts { struct MenuCommand { let id: String; let title: String; let group: String } }
enum CommandBarScopeKeyboard { static func matchesPasswords(query: String) -> Bool { false } }

struct TabCandidatesFixture {
    struct State { var tabs: [BrowserTab] = [] }
    struct Store { var state = State(); var retiringTabIDs = Set<UUID>() }
    var store = Store()
    var isPopupWindow = false
    var closingTabIDs = Set<UUID>(), modelRetirementIDs = Set<UUID>(), transferringTabIDs = Set<UUID>()
}

@MainActor final class NavigationFixture {
    struct Table { var selectedRow = 0 }
    struct Site { let host: String }
    var table = Table()
    let input = NSTextField()
    var editState = CommandBarEditState(query: "")
    var addressOnly = false, addressWasEdited = false
    var initialInput = ""
    var currentPageTitle: String?
    var nativeHold = CommandBarNativeHold()
    var nativeHoldDeadline: DispatchWorkItem?
    var snapshotRevision: UInt64 = 0
    var nativeInput = ""
    var nativeError: String?
    var nativeResults: [PCNativeSearchNavigation] = []
    var extensionActions: [PCNativeOmniboxExtensionAction] = []
    var extensionLaunchSnapshot: [PCNativeExtensionAction] = []
    var scopeOffers: [PCNativeOmniboxScope] = []
    var siteScopes: [PCNativeOmniboxScope] = []
    var extensionDisposition: Bool? = true
    var tabs: [BrowserTab] = []
    var documents: [CommandBarDocument] = []
    var topDomainList: [CommandBarRanking.Domain] = []
    var commands: [KeyboardShortcuts.MenuCommand] = []
    var commandSearch: [(title: String, text: String)] = []
    var typedCommands: [CommandBarTypedCommand] = []
    var spaces: [CommandBarSpaceAction] = []
    var folders: [CommandBarFolderAction] = []
    var folderMoves: [CommandBarFolderMove] = []
    var favoriteAction: CommandBarFavoriteAction?
    var favoriteRename: CommandBarFavoriteRenameAction?
    var canPerformTypedCommand: ((CommandBarTypedCommand) -> Bool)?
    var canMoveToFolder: ((CommandBarFolderMove) -> Bool)?
    var canPerformFavorite: ((CommandBarFavoriteAction) -> Bool)?
    var canRenameFavorite: ((CommandBarFavoriteRenameAction) -> Bool)?
    var onMuteAllTabs: ((Bool) -> Bool)?
    var historyRevision: UInt64 = 0
    var historyExcludedURL: String?
    var recentPagesGeneration = 0, topDomainGeneration = 0
    var recentPages: [(url: String, title: String)]?
    var rankedHistory: [CommandBarHistoryScanSkip.Visit] = []
    var lastHistoryScanKey: CommandBarHistoryScanSkip.Key?
    var cachedHistoryVisits: [CommandBarHistoryScanSkip.Visit] = []
    var retainedBackgroundHistory: (result: Result, row: Int)?
    var explicitSelectionID: String?
    var actionsScope = false, isWebsiteScoped = false, scopeInvalidated = false, dismissed = false
    var isScoped: Bool { actionsScope || isWebsiteScoped }
    var unavailableScopeName: String?
    var scopedName = ""
    var sidebarBrowsing = false
    var onSidebarCommit: (() -> Void)?
    var isOwnerValid: (() -> Bool)?
    var results: [Result] = []
    var submitted: (result: Result, disposition: CommandBarSubmission)?
    var lastOpenResultsFingerprint: String?
    var resultPublication = UUID()
    var rebuilds = 0
    static func matchType(of value: PCNativeSearchNavigation) -> String? { value.matchType }
    static func site(of scope: PCNativeOmniboxScope) -> Site? { Site(host: scope.searchHost) }
    func caption(for tab: BrowserTab) -> CommandBarResultText.TabCaption { .switchToTab }
    func dismiss(restoreFocus: Bool) { dismissed = true }
    func submitResult(_ result: Result, disposition: CommandBarSubmission, retainsSelection: Bool) {
        submitted = (result, disposition)
    }
    func publish(_ values: [PCNativeSearchNavigation], input: String) {
        snapshotRevision += 1
        guard nativeHold.accept(input: input, isError: false) else { return }
        nativeInput = input; nativeResults = values
        refreshResults()
    }
}

@main struct NavigationPipelineTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var checks = 0, failures = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            if !value() { failures += 1; if failures <= 16 { print("FAIL: " + message) } }
        }
        let profile = UUID(), space = UUID()
        func tab(_ url: String, title: String = "Website") -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space, profileID: profile, url: url, title: title, kind: .today,
                       createdAt: Date(), lastAccessed: Date(), savedURL: url, savedTitle: title)
        }
        func search(_ query: String) -> PCNativeSearchNavigation {
            PCNativeSearchNavigation("https://www.google.com/search?q=" + query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!,
                                     search: true, title: query, type: "search-what-you-typed")
        }
        func compact(_ url: String) -> NavigationFixture {
            let f = NavigationFixture()
            f.addressOnly = true; f.initialInput = url; f.currentPageTitle = "Current page"
            f.editState = CommandBarEditState(query: url)
            return f
        }

        // A pristine compact field displays the selected current URL but ranks
        // zero-query suggestions. Clearing it also ranks zero-query suggestions;
        // the fingerprint must still discard the old URL, without depending on
        // a newer native answer or a change in the provider's error state.
        for providerError in [nil, "Suggestions unavailable"] as [String?] {
            let f = compact("https://current.example/")
            f.nativeError = providerError; f.refreshResults()
            expect(f.results.first?.id == "current-address", "pristine compact field offers the current address first")
            expect(f.results.first?.title == "Current page", "current-address suggestion uses the page title")
            f.submitSelection(.ordinary)
            expect(f.submitted?.result.input == f.initialInput, "pristine Return retains the displayed current address")
            f.submitted = nil
            let rebuilds = f.rebuilds, nativeRevision = f.snapshotRevision
            f.addressWasEdited = true; f.editState.edit(""); f.refreshResults()
            expect(f.rebuilds == rebuilds + 1, "clearing the seeded URL rebuilds despite the same effective empty query")
            expect(f.snapshotRevision == nativeRevision, "cleared-field regression uses no replacement native publication")
            expect(f.results.isEmpty, "clearing with no other suggestions removes the current-address row")
            f.submitSelection(.ordinary)
            expect(f.submitted == nil, "Return after clearing cannot navigate to the deleted URL")
        }

        let recents = compact("https://current.example/")
        recents.historyExcludedURL = recents.initialInput
        recents.refreshResults()
        let beforeRecents = recents.rebuilds
        recents.updateRecentPages([(recents.initialInput, "Current page"), ("https://recent.example/", "Recent page")])
        expect(!recents.editState.query.isEmpty && !recents.addressWasEdited, "recent-page answer arrives while the seed URL remains in the field")
        expect(recents.rebuilds == beforeRecents + 1, "async recents refresh a pristine compact field")
        expect(recents.results.map(\.id) == ["current-address", "history:https://recent.example/"],
               "async recents retain current-address first and exclude its duplicate history row")
        recents.addressWasEdited = true; recents.editState.edit(""); recents.refreshResults()
        expect(recents.results.map(\.id) == ["history:https://recent.example/"], "clearing preserves real recents while removing the seed row")
        recents.submitSelection(.ordinary)
        expect(recents.submitted?.result.input == "https://recent.example/", "Return after clearing selects an actual recent page")

        // Local tabs are URL suggestions in the compact editor, but exact-ID
        // switches in the full palette. Notes, Easels and app commands remain
        // available in that full palette and do not leak into address editing.
        let websiteTab = tab("https://example.com/", title: "Example")
        let note = CommandBarDocument(kind: .note, id: UUID(), title: "Example Note")
        let easel = CommandBarDocument(kind: .easel, id: UUID(), title: "Example Easel")
        for addressOnly in [false, true] {
            let f = NavigationFixture(); f.addressOnly = addressOnly
            f.tabs = [websiteTab, tab(InternalPage.note(note.id).urlString, title: note.title)]
            f.documents = [note, easel]
            f.adoptCommands([.init(id: "copyCurrentURL:", title: "Copy Current URL", group: "Edit")])
            expect(f.commands.isEmpty == addressOnly, "menu adoption distinguishes compact editor from the full palette")
            let commands = f.commandResults(query: "", includesEmpty: true)
            expect(addressOnly ? commands.isEmpty : commands.contains(where: { $0.command != nil }),
                   "compact editor excludes commands while the full action palette retains them")
            expect(addressOnly ? commands.isEmpty : commands.contains(where: { $0.managesPasswords }),
                   "password management remains in the full action palette")
            f.refreshResults()
            expect(f.results.first?.input == (addressOnly ? websiteTab.url : nil), "compact tab candidate owns its URL input")
            expect(f.results.first?.tabID == (addressOnly ? nil : websiteTab.id), "full palette tab candidate retains its exact tab identity")
            expect(f.results.count == (addressOnly ? 1 : 2), "compact empty-query rows exclude local document tabs")
            f.submitSelection(.ordinary)
            expect(f.submitted?.disposition == .ordinary, "ordinary Return retains its destination disposition")
            expect(f.submitted?.result.tabID == (addressOnly ? nil : websiteTab.id), "Return preserves the address-versus-switch intent")
            f.addressWasEdited = true; f.editState.edit("Example"); f.refreshResults()
            expect(f.results.contains(where: { $0.document != nil }) == !addressOnly, "typed compact queries exclude documents while full palette keeps them")
            f.siteScopes = [PCNativeOmniboxScope("example.com")]
            if let row = f.results.firstIndex(where: { $0.url?.absoluteString == websiteTab.url }) {
                f.table.selectedRow = row
                expect(f.selectedScopeOffer === f.siteScopes.first, "URL-backed compact and full tab suggestions retain website search scope")
            } else { expect(false, "website suggestion remains available for scope selection") }
            let request = search("weather tomorrow")
            f.editState.edit("weather tomorrow"); f.publish([request], input: "weather tomorrow")
            expect(f.results.first?.navigation === request, "both surfaces retain the original native search request")
        }

        // Use the shell's real candidate filter: other Spaces in this Profile
        // participate; current, archived, closing, transferring and other
        // Profile tabs cannot replace the native destination.
        var candidates = TabCandidatesFixture()
        let current = tab("https://www.google.com/")
        var anotherSpace = tab(current.url); anotherSpace.spaceID = UUID()
        var anotherProfile = tab(current.url); anotherProfile.profileID = UUID()
        var archived = tab(current.url); archived.archivedAt = Date()
        let closing = tab(current.url), retiring = tab(current.url), transferring = tab(current.url)
        candidates.store.state.tabs = [current, anotherSpace, anotherProfile, archived, closing, retiring, transferring]
        candidates.closingTabIDs = [closing.id]; candidates.store.retiringTabIDs = [retiring.id]
        candidates.transferringTabIDs = [transferring.id]
        expect(candidates.commandBarTabs(profileID: profile, excluding: current.id).map(\.id) == [anotherSpace.id],
               "only the eligible same-Profile tab in another Space participates in dedup")
        candidates.isPopupWindow = true
        expect(candidates.commandBarTabs(profileID: profile, excluding: current.id).isEmpty, "popups cannot switch sidebar tabs")

        // Every native type we previously filtered can be the first provider
        // result. Presentation must not silently promote the next search.
        for type in ["url-what-you-typed", "history-url", "history-title", "navsuggest", "bookmark-title",
                     "navsuggest-personalized", "history-body", "history-embeddings", "future-navigation-type"] {
            for alreadyOpen in [false, true] {
                let f = NavigationFixture(), query = "youtube.com"
                f.editState.edit(query)
                let website = PCNativeSearchNavigation("https://www.youtube.com/", title: query, detail: "YouTube", type: type)
                if alreadyOpen { f.tabs = [tab(website.url.absoluteString, title: "YouTube")] }
                f.siteScopes = [PCNativeOmniboxScope("www.youtube.com")]
                f.publish([website, search(query)], input: query)
                expect(alreadyOpen ? f.results.first?.tabID == f.tabs.first?.id : f.results.first?.navigation === website,
                       "leading \(type), open=\(alreadyOpen), retains the website destination")
                expect(f.selectedScopeOffer === f.siteScopes.first, "leading \(type) retains site search")
                f.submitSelection(.ordinary)
                expect(alreadyOpen ? f.submitted?.result.tabID == f.tabs.first?.id : f.submitted?.result.navigation === website,
                       "Return preserves the \(type) website target")
            }
        }
        // A newer publication can have identical text and URL but different
        // request, scope and completion/deletion identities.
        let updated = NavigationFixture(), query = "youtube.com"
        updated.editState.edit(query)
        let first = PCNativeSearchNavigation("https://www.youtube.com/", title: query)
        updated.siteScopes = [PCNativeOmniboxScope("www.youtube.com")]
        updated.publish([first, search(query)], input: query)
        let initialRebuilds = updated.rebuilds
        updated.refreshResults()
        expect(updated.rebuilds == initialRebuilds, "idle chrome refresh still skips identical state")
        let second = PCNativeSearchNavigation("https://www.youtube.com/", title: query)
        updated.publish([second, search(query)], input: query)
        expect(updated.rebuilds == initialRebuilds + 1, "a new native publication rebuilds even with identical labels")
        expect(updated.results.first?.navigation === second, "the row receives the new original request")
        expect(updated.selectedScopeOffer === updated.siteScopes.first, "same-looking async updates retain site search")
        updated.submitSelection(.ordinary)
        expect(updated.submitted?.result.navigation === second, "Return uses the latest request object")

        let websites = [
            ("google.com", "https://www.google.com/"), ("www.google.com", "https://www.google.com/"),
            ("YouTube.COM", "https://www.youtube.com/"), ("https://youtube.com", "https://www.youtube.com/"),
            ("youtube.com/watch?v=abc", "https://www.youtube.com/watch?v=abc"),
            ("localhost:8080/path", "http://localhost:8080/path"), ("127.0.0.1:8080", "http://127.0.0.1:8080/"),
            ("[::1]:8080", "http://[::1]:8080/"), ("münchen.de", "https://xn--mnchen-3ya.de/"),
            ("example.com/hello world", "https://example.com/hello%20world"),
            ("github.com", "https://github.com/"), ("https://example.com/a?b=1#c", "https://example.com/a?b=1#c")
        ]
        for (query, url) in websites {
            for tabCount in 0...2 {
                let f = NavigationFixture()
                f.editState.edit(query)
                let website = PCNativeSearchNavigation(url, title: "Website")
                f.tabs = (0..<tabCount).map { _ in tab(url) }
                // A previous accidental search must not win merely because
                // its title starts with the exact input.
                f.tabs.append(tab(search(query).url.absoluteString, title: query + " - Google Search"))
                f.topDomainList = CommandBarRanking.topDomains([(url, "Website"), (url, "Website")])
                f.publish([website, search(query)], input: query)
                if tabCount == 0 {
                    expect(f.results.first?.navigation === website, "\(query): native destination without a matching tab")
                } else {
                    expect(f.results.first?.tabID == f.tabs.first?.id, "\(query): \(tabCount) duplicates retain the website default")
                    expect(f.results.first?.navigation == nil, "\(query): Switch to Tab never replays a native request")
                }
                for disposition in [CommandBarSubmission.ordinary, .background, .split] {
                    f.submitSelection(disposition)
                    expect(f.submitted?.result.id == f.results.first?.id && f.submitted?.disposition == disposition,
                           "\(query): modifiers preserve the selected destination")
                }
                if let row = f.results.firstIndex(where: { $0.navigation?.search == true }) {
                    f.table.selectedRow = row; f.explicitSelectionID = f.results[row].id
                    f.submitSelection(.ordinary)
                    expect(f.submitted?.result.navigation?.search == true, "an explicitly selected search remains a search")
                }
            }
        }
        for (url, otherURL) in [
            ("https://www.youtube.com/", "https://www.youtube.com/watch?v=video"),
            ("http://localhost:8080/", "http://localhost:8081/"),
            ("https://example.com/a?q=one", "https://example.com/a?q=two"),
            ("https://example.com/a#one", "https://example.com/a#two")
        ] {
            let f = NavigationFixture(); f.editState.edit(url)
            let website = PCNativeSearchNavigation(url, title: url)
            f.tabs = [tab(otherURL, title: url)]
            f.publish([website, search(url)], input: url)
            expect(f.results.first?.navigation === website, "a different path, port, query or fragment does not consume the website default")
        }
        // Genuine search input is classified by the engine, never guessed by
        // an app-side dot/URL heuristic, including search terms containing dots.
        for query in ["weather tomorrow", "google.com reviews", "version 1.2.3", "name@example.com"] {
            let f = NavigationFixture(); f.editState.edit(query)
            let request = search(query)
            f.tabs = [tab("https://www.google.com/", title: "Google")]
            f.publish([request], input: query)
            expect(f.results.first?.navigation === request, "\(query): native search intent stays intact")
        }
        for type in ["search-suggest-personalized", "future-search-type"] {
            let f = NavigationFixture(); f.editState.edit("weather tomorrow")
            let request = PCNativeSearchNavigation("https://search.example.test/", search: true, title: "weather tomorrow", type: type)
            f.publish([request], input: "weather tomorrow")
            expect(f.results.first?.navigation === request && f.results.first?.isSearch == true,
                   "a leading \(type) keeps its original search request")
        }
        for literal in ["youtube.com", "  https://youtube.com/watch?v=abc  ", "localhost:8080", "weather tomorrow"] {
            let f = NavigationFixture(); f.editState.edit(literal)
            f.nativeError = "Suggestions unavailable"
            f.refreshResults(); f.submitSelection(.ordinary)
            expect(f.submitted?.result.input == literal.trimmingCharacters(in: .whitespacesAndNewlines),
                   "no provider answer: Return sends the current literal input to the real classifier")
        }
        // Return before providers answer must use the current literal input;
        // an explicit selection of an older visible row keeps that intent.
        for disposition in [CommandBarSubmission.ordinary, .background, .split] {
            for explicit in [false, true] {
                let f = NavigationFixture(); f.editState.edit("you")
                let previous = search("you")
                f.publish([previous], input: "you")
                f.editState.edit("youtube.com")
                _ = f.nativeHold.edit("youtube.com", canHold: true, scoped: false)
                if explicit { f.explicitSelectionID = f.results.first?.id }
                f.submitSelection(disposition)
                expect(explicit ? f.submitted?.result.navigation === previous : f.submitted?.result.input == "youtube.com",
                       "pending answer: explicit=\(explicit) preserves the correct Return input")
            }
        }
        // Extension positions share the original native order. They must not
        // lose priority or turn into website navigation while filtering.
        let extensionFirst = NavigationFixture(); extensionFirst.editState.edit("keyword")
        let action = PCNativeOmniboxExtensionAction(index: 0)
        extensionFirst.extensionActions = [action]
        extensionFirst.publish([PCNativeSearchNavigation("https://example.com/", type: "bookmark-title"), search("keyword")], input: "keyword")
        expect(extensionFirst.results.first?.extensionAction === action, "the leading extension action stays first")
        expect(!extensionFirst.results.contains(where: { $0.navigation?.matchType == "bookmark-title" }),
               "non-leading filtered results stay filtered when an extension owns the first position")

        if failures > 0 { print("NavigationPipelineTests: \(failures) failures / \(checks) checks"); exit(1) }
        print("NavigationPipelineTests: \(checks) checks passed")
    }
}
