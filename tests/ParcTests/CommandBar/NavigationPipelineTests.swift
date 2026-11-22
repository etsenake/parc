import AppKit
import ParcEngine
import ParcTestSupport
import Testing
@testable import ParcCore
@testable import ParcKit
@testable import ParcNotes
@testable import ParcCommandBar

struct NavigationPipelineTests {
    @MainActor final class Window: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    @MainActor final class Fixture {
        let window: Window
        let native: PCNativeOmnibox
        let bar: CommandBar

        init(query: String = "", address: String? = nil, compact: Bool = false, tabs: [BrowserTab] = [],
             documents: [CommandBarDocument] = []) throws {
            _ = NSApplication.shared
            window = Window(contentRect: NSRect(x: 100, y: 100, width: 880, height: 600), styleMask: .borderless,
                            backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let native = PCNativeOmnibox(profilePath: "test", page: nil, window: nil)
            self.native = native
            let defaults = try #require(TestDefaults("Parc.NavigationPipeline."))
            let files = IsolatedNoteFiles.make()
            let noteIcons = NoteTabIcons(files: files, worker: .inline, clock: files.clock)
            let iconArt = NoteTabIconArt(icons: noteIcons, easels: EaselTabIcons(files: files))
            bar = CommandBar(parent: window, tabs: tabs, history: [], documents: { documents }, currentURL: address,
                profilePath: "test", page: nil, addressOnly: compact, currentPageTitle: "Current page",
                initialEdit: query.isEmpty ? nil : (query, NSRange(location: query.utf16.count, length: 0)),
                shortcuts: KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false),
                privacyDefaults: defaults, makeOmnibox: { _, _, _ in native }, loadFavicon: { _, _, _ in },
                noteIconArt: iconArt)
            bar.present()
        }

        func publish(_ query: String, results: [[String: Any]] = [], extensions: [[String: Any]] = [],
                     scopes: [[String: Any]] = [], error: String? = nil) {
            var message: [String: Any] = ["input": query, "results": results, "extensions": extensions, "scopes": scopes]
            if let error { message["error"] = error }
            _ = native.perform(NSSelectorFromString("parcTestPublish:"), with: message)
        }

        func surface() throws -> PopoverBackgroundView {
            try #require(window.contentView?.subviews.last?.subviews.compactMap { $0 as? PopoverBackgroundView }.first)
        }

        func edit(_ query: String) throws {
            let input = try #require(try surface().subviews.compactMap { $0 as? CommandBarInputField }.first)
            input.stringValue = query
            if let editor = input.currentEditor() as? NSTextView {
                editor.string = query
                editor.setSelectedRange(NSRange(location: query.utf16.count, length: 0))
            }
            bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: input))
        }

        func labels() -> [String] {
            let table = NSTableView()
            return (0..<bar.numberOfRows(in: table)).compactMap { row in
                (bar.tableView(table, viewFor: nil, row: row) as? CommandResultCell)?.accessibilityLabel()
            }
        }

        func submit(_ flags: NSEvent.ModifierFlags = [], row: Int = 0) throws {
            let view = try #require(bar.tableView(NSTableView(), rowViewForRow: row) as? CommandResultRowView)
            let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
            #expect(view.onPress?(event) == true)
        }

        func pressReturn(_ flags: NSEvent.ModifierFlags = []) throws {
            let table = try #require(try surface().subviews.compactMap { $0 as? CommandResultsScrollView }.first?.documentView as? CommandResultsTable)
            let event = CommandBarTestSupport.keyEvent(36, flags)
            #expect(table.onKey?(event) == true)
        }
    }

    func tab(_ url: String, title: String = "Website") -> BrowserTab {
        BrowserTab(id: UUID(), spaceID: UUID(), profileID: UUID(), url: url, title: title, kind: .today,
                   createdAt: .distantPast, lastAccessed: .distantPast, savedURL: url, savedTitle: title)
    }

    func search(_ query: String) -> [String: Any] {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        return ["url": "https://search.example.test/?q=" + escaped, "search": true, "title": query]
    }

    @Test(arguments: [nil, "Suggestions unavailable"] as [String?])
    @MainActor func aPristineCompactFieldOpensItsCurrentAddress(providerError: String?) throws {
        let address = "https://example.test/current"
        let fixture = try Fixture(address: address, compact: true)
        fixture.publish("", error: providerError)
        var received: String?
        fixture.bar.onNavigate = { received = $0; _ = $1 }
        #expect(fixture.labels().first?.contains("Current page") == true)
        try fixture.pressReturn()
        #expect(received == address)
    }

    @Test @MainActor func clearingTheAddressCannotReopenItOnReturn() throws {
        let fixture = try Fixture(address: "https://example.test/current", compact: true)
        defer { fixture.bar.dismiss(restoreFocus: false) }
        var received: String?
        fixture.bar.onNavigate = { received = $0; _ = $1 }
        try fixture.edit("")
        #expect(fixture.labels().isEmpty)
        try fixture.pressReturn()
        #expect(received == nil)
    }

    @Test @MainActor func clearingASeededAddressLeavesActualRecentPages() throws {
        let fixture = try Fixture(address: "https://example.test/current", compact: true)
        fixture.bar.updateRecentPages([("https://example.test/recent", "Recent page")])
        var received: String?
        fixture.bar.onNavigate = { received = $0; _ = $1 }
        try fixture.edit("")
        try fixture.pressReturn()
        #expect(received == "https://example.test/recent")
    }

    @Test(arguments: [false, true])
    @MainActor func anOpenTabIsSwitchedToInThePaletteAndNavigatedInTheEditor(compact: Bool) throws {
        let open = tab("https://example.test/open")
        let fixture = try Fixture(compact: compact, tabs: [open])
        var navigated: String?
        var selected: UUID?
        fixture.bar.onNavigate = { navigated = $0; _ = $1 }
        fixture.bar.onSelectTab = { selected = $0 }
        try fixture.pressReturn()
        #expect(navigated == (compact ? open.url : nil))
        #expect(selected == (compact ? nil : open.id))
    }

    @Test(arguments: [false, true])
    @MainActor func theCompactEditorLeavesDocumentActionsOut(compact: Bool) throws {
        let id = UUID()
        let document = CommandBarDocument(kind: .easel, id: id, title: "Quarterly Plan", url: nil)
        let fixture = try Fixture(query: "quarterly", compact: compact, documents: [document])
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.bar.onOpenDocument = { _ in }
        #expect(fixture.labels().contains { $0.contains("Quarterly Plan") } == !compact)
    }

    static let websites = [
        ("google.com", "https://www.google.com/"), ("YouTube.COM", "https://www.youtube.com/"),
        ("https://youtube.com", "https://www.youtube.com/"), ("youtube.com/watch?v=abc", "https://www.youtube.com/watch?v=abc"),
        ("localhost:8080/path", "http://localhost:8080/path"), ("127.0.0.1:8080", "http://127.0.0.1:8080/"),
        ("[::1]:8080", "http://[::1]:8080/"), ("münchen.de", "https://xn--mnchen-3ya.de/"),
        ("example.com/hello world", "https://example.com/hello%20world"),
        ("github.com", "https://github.com/"), ("https://example.com/a?b=1#c", "https://example.com/a?b=1#c"),
    ]

    @Test(arguments: websites, [0, 1, 2])
    @MainActor func theProviderWebsiteDefaultKeepsItsOriginalDestination(website: (String, String), count: Int) throws {
        let (query, url) = website
        let opened = (0..<count).map { _ in tab(url) }
        let accidental = tab("https://search.example.test/?q=" + query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!,
                             title: query + " – Search")
        let fixture = try Fixture(query: query, tabs: opened + [accidental])
        fixture.publish(query, results: [["url": url, "title": "Website"], search(query)])
        var navigation: PCNativeSearchNavigation?, selected: UUID?
        fixture.bar.onSearchNavigation = { navigation = $0 }
        fixture.bar.onSelectTab = { selected = $0 }
        try fixture.pressReturn()
        #expect(selected == opened.first?.id)
        #expect(navigation?.url == (opened.isEmpty ? URL(string: url) : nil))
    }

    @Test(arguments: [
        ("https://www.youtube.com/", "https://www.youtube.com/watch?v=video"),
        ("http://localhost:8080/", "http://localhost:8081/"),
        ("https://example.com/a?q=one", "https://example.com/a?q=two"),
        ("https://example.com/a#one", "https://example.com/a#two"),
    ])
    @MainActor func aDifferentDestinationDoesNotConsumeTheNativeDefault(url: String, other: String) throws {
        let fixture = try Fixture(query: url, tabs: [tab(other, title: url)])
        fixture.publish(url, results: [["url": url, "title": url], search(url)])
        var actual: URL?
        fixture.bar.onSearchNavigation = { actual = $0.url }
        try fixture.pressReturn()
        #expect(actual == URL(string: url))
    }

    @Test(arguments: ["weather tomorrow", "google.com reviews", "version 1.2.3", "name@example.com"])
    @MainActor func aNativeSearchStaysASearch(query: String) throws {
        let fixture = try Fixture(query: query, tabs: [tab("https://www.google.com/", title: "Google")])
        fixture.publish(query, results: [search(query)])
        var actual: PCNativeSearchNavigation?
        fixture.bar.onSearchNavigation = { actual = $0 }
        try fixture.pressReturn()
        #expect(actual?.search == true)
        #expect(actual?.editText == query)
    }

    @Test(arguments: ["youtube.com", "  https://youtube.com/watch?v=abc  ", "localhost:8080", "weather tomorrow"])
    @MainActor func anUnavailableProviderLeavesTheCurrentLiteralQuery(query: String) throws {
        let fixture = try Fixture(query: query)
        let literal = query.trimmingCharacters(in: .whitespacesAndNewlines)
        fixture.publish(literal, error: "Suggestions unavailable")
        var submitted: String?
        fixture.bar.onNavigate = { submitted = $0; _ = $1 }
        try fixture.pressReturn()
        #expect(submitted == literal)
    }

    @Test @MainActor func aNewPublicationReplacesAnIdenticalLookingRowsRequest() throws {
        let fixture = try Fixture(query: "search words")
        let result = search("search words")
        fixture.publish("search words", results: [result])
        fixture.publish("search words", results: [result])
        var actual: PCNativeSearchNavigation?
        fixture.bar.onSearchNavigation = { actual = $0 }
        try fixture.pressReturn()
        #expect(actual?.revision == 2)
    }

    @Test(arguments: [CommandBarSubmission.ordinary, .split, .background])
    @MainActor func resultModifiersKeepTheNativeNavigation(disposition: CommandBarSubmission) throws {
        let fixture = try Fixture(query: "example.test")
        let url = URL(string: "https://example.test/")!
        fixture.publish("example.test", results: [["url": url.absoluteString, "title": "Example"]])
        var actual: URL?
        fixture.bar.onSearchNavigation = { actual = $0.url }
        fixture.bar.canSplitSelection = { _ in true }
        fixture.bar.onSplitNavigation = { actual = $0.url }
        fixture.bar.onBackgroundNavigation = { request, valid, complete in
            if valid() { actual = request.url }
            complete(nil)
        }
        let flags: NSEvent.ModifierFlags
        switch disposition {
        case .ordinary: flags = []
        case .split: flags = .option
        case .background: flags = [.command, .option]
        }
        try fixture.submit(flags)
        #expect(actual == url)
        fixture.bar.dismiss(restoreFocus: false)
    }

    @Test @MainActor func aDeepProviderDefaultCanLeadWithItsVisitedSite() throws {
        let fixture = try Fixture(query: "example.test")
        let root = URL(string: "https://example.test/")!
        fixture.bar.updateTopDomains(CommandBarRanking.topDomains([(root.absoluteString, ""), ("https://example.test/another", "")]))
        fixture.publish("example.test", results: [["url": "https://example.test/deep", "title": "Deep page"]])
        var actual: String?
        fixture.bar.onNavigate = { actual = $0; _ = $1 }
        try fixture.pressReturn()
        #expect(actual == root.absoluteString)
    }
}

extension NavigationPipelineTests {
    @Test(arguments: [(true, "space waves"), (false, "space")])
    @MainActor func wrappingBetweenResultsKeepsTheFieldAndItsProviderQuery(up: Bool, visible: String) throws {
        let fixture = try Fixture(query: "space")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish("space", results: [
            ["url": "https://search.example.test/?q=space", "search": true, "title": "space"],
            ["url": "https://example.test/waves", "title": "Waves", "editText": "space waves", "inlineCompletion": "space waves"],
        ])
        let surface = try fixture.surface()
        let field = try #require(surface.subviews.compactMap { $0 as? CommandBarInputField }.first)
        let editor = try #require(field.currentEditor() as? NSTextView)
        let table = try #require(surface.subviews.compactMap { $0 as? CommandResultsScrollView }.first?.documentView as? CommandResultsTable)
        if !up {
            #expect(fixture.bar.control(field, textView: editor, doCommandBy: NSSelectorFromString("moveUp:")))
        }
        let command = NSSelectorFromString(up ? "moveUp:" : "moveDown:")
        #expect(fixture.bar.control(field, textView: editor, doCommandBy: command))
        #expect(table.selectedRow == (up ? 1 : 0))
        #expect(editor.string == visible)
        #expect(editor.selectedRange() == NSRange(location: 5, length: visible.utf16.count - 5))
        #expect(fixture.window.firstResponder === editor)
    }

    @Test @MainActor func markedTextDoesNotNavigateTheResultTable() throws {
        let fixture = try Fixture(query: "space")
        defer { fixture.bar.dismiss(restoreFocus: false) }
        fixture.publish("space", results: [search("space")])
        let surface = try fixture.surface()
        let field = try #require(surface.subviews.compactMap { $0 as? CommandBarInputField }.first)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!fixture.bar.control(field, textView: editor, doCommandBy: NSSelectorFromString("moveDown:")))
        #expect(editor.hasMarkedText())
    }
}
