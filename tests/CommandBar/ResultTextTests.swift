import Foundation

@main struct ResultTextTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        typealias Text = CommandBarResultText

        expect(Text.displayURL("https://www.youtube.com/") == "youtube.com", "scheme, www and trailing slash go")
        expect(Text.displayURL("https://www.youtube.com/watch?v=49_Ph2Q6uiM") == "youtube.com/watch", "the query goes")
        let okta = "https://fullscript.okta.com/app/UserHome?fromHome=true&iss=https%3A%2F%2Ffullscript.okta.com"
            + "&login_hint=someone%40example.com&session_hint=AUTHENTICATED"
        expect(Text.displayURL(okta) == "fullscript.okta.com/app/UserHome", "a sign-in page shows its host and path, not its parameters")
        expect(Text.displayURL("https://Docs.Example.COM/App/UserHome#Section-2") == "docs.example.com/App/UserHome",
               "the host is lowercased, the path keeps its capitals and the fragment goes")
        expect(Text.displayURL("http://example.com/a/?") == "example.com/a", "an empty query then one trailing / go")
        expect(Text.displayURL("https://example.com//") == "example.com/", "only one trailing slash is dropped")
        expect(Text.displayURL("parc://settings/") == "parc://settings", "other schemes keep their prefix")
        expect(Text.displayURL("https://wwwexample.com") == "wwwexample.com", "www is only dropped with its dot")
        expect(Text.displayURL("https://www.com/") == "www.com", "www stays when nothing would be left of the site")
        expect(Text.displayURL("http://localhost:3000/Board?x=1") == "localhost:3000/Board", "a port stays with its host")
        expect(Text.displayURL("https://www.xn--mnchen-3ya.de/Karte") == "xn--mnchen-3ya.de/Karte", "a Punycode host stays as written")
        expect(Text.displayURL("https://xn--6y767205604493046e.example/") == "xn--6y767205604493046e.example",
               "a crafted label is never decoded")
        expect(Text.displayURL("https://\u{0430}pple.com/") == "%D0%B0pple.com", "a raw lookalike letter in a host stays escaped")
        expect(Text.displayURL("https://accounts.google.com@evil.example/login") == "evil.example/login",
               "a user name never poses as the host")
        expect(Text.displayURL("http://evil.example\\@google.com/") == "evil.example\\@google.com",
               "a backslash ends the host as browsers read it")
        expect(Text.displayURL("DATA:text/plain," + String(repeating: "a", count: 1_000)).count == Text.dataURLLimit,
               "an uppercase data URL is capped too")
        expect(Text.displayURL("https://a.com/" + String(repeating: "b", count: 10_000)).count == 6 + Text.pathLimit - 1,
               "a huge path is bounded before it is read")
        expect(Text.displayURL("https://a.com/hello%20World%2F%3F%23%25%26%3D%2B") == "a.com/hello World%2F%3F%23%25%26%3D%2B",
               "spaces read plainly while escaped separators and query characters stay escaped")
        expect(Text.displayURL("https://a.com/caf%C3%A9/%E2%9C%93") == "a.com/café/✓", "readable UTF-8 is shown")
        for (escape, why) in [("%E2%80%AE", "a right-to-left override"), ("%E2%80%8B", "a zero-width space"),
                              ("%C2%A0", "a no-break space"), ("%F0%9F%94%92", "a lock emoji"), ("%E2%A0%80", "a blank braille cell"),
                              ("%EF%BB%BF", "a byte order mark"), ("%C3", "a cut-off sequence"), ("%C0%AF", "an overlong slash"),
                              ("%00", "a null byte"), ("%0A", "a line feed")] {
            expect(Text.displayURL("https://a.com/x" + escape + "y") == "a.com/x" + escape + "y", "\(why) stays escaped")
        }
        expect(Text.displayURL("https://a.com/x\u{202E}y") == "a.com/x%E2%80%AEy", "a raw override in a path is escaped")
        expect(Text.displayURL("https://a.com/%41%62c/%F0%9F%98%80") == "a.com/Abc/😀", "plain letters and emoji read plainly")
        expect(Text.displayURL("https://\u{212A}ayak.com/") == "%E2%84%AAayak.com", "a raw Kelvin sign never folds into a k")
        expect(Text.displayURL("HTTPS://WWW.Example.com/A") == "example.com/A", "an uppercase scheme and www are still trimmed")
        expect(Text.displayURL("file:///Users/Josh/My%20Doc.PDF?page=2") == "file:///Users/Josh/My Doc.PDF", "a file path keeps its case")
        expect(Text.displayURL("mailto:Jo%20Doe@example.com?subject=Hi") == "mailto:Jo Doe@example.com", "an address without a host")
        let data = "data:text/plain;base64," + String(repeating: "QUJD", count: 10_000)
        expect(Text.displayURL(data).count == Text.dataURLLimit, "a data URL is capped before it is measured")
        expect(Text.urlSubtitle("https://chatgpt.com/") == "— chatgpt.com", "an em dash and a space lead the URL")
        expect(Text.urlSubtitle(okta) == "— fullscript.okta.com", "a subtitle names just the site")
        expect(Text.urlSubtitle("file:///Users/Josh/Doc.pdf") == "— file:///Users/Josh/Doc.pdf", "a file has no site, so its path shows")
        expect(Text.urlSubtitle("") == nil, "an empty URL has no subtitle")
        expect(Text.pageTitle("My Apps Dashboard | Fullscript", url: okta) != nil, "a real title says what the page is")
        for title in ["", "  ", "fullscript.okta.com/app/UserHome?fromHome=true", "https://fullscript.okta.com/app/UserHome",
                      "FULLSCRIPT.OKTA.COM", "www.fullscript.okta.com/app"] {
            expect(Text.pageTitle(title, url: okta) == nil, "\(title) is only the address")
        }
        expect(Text.pageTitle("Fullscript", url: okta) != nil && Text.pageTitle("Settings", url: "parc://settings") != nil,
               "a one-word title is still a title")
        expect(Text.pageTitle("a.com/hello world", url: "https://a.com/hello%20world") == nil
               && Text.pageTitle("google.com/search?q=new york", url: "https://www.google.com/search?q=new+york") == nil,
               "an address with a space is still only the address")
        expect(Text.pageTitle("A.com is great", url: "https://a.com/") != nil, "a title naming its site is a title")
        expect(Text.pageTitle("parc://settings", url: "parc://settings/") == nil, "an internal page named by its address")
        let hugeData = "data:text/html," + String(repeating: "a", count: 2_000_000)
        expect(Text.pageTitle("Hello", url: hugeData) != nil && Text.samePageKey(title: "Hello", url: hugeData) == nil,
               "a data page keeps its title and never joins another row")
        expect(Text.pageSubtitle(title: "My Apps Dashboard | Fullscript", url: okta) == "— fullscript.okta.com",
               "a titled page names its site")
        expect(Text.pageSubtitle(title: "", url: okta) == nil, "an untitled page shows its address once")
        expect(Text.samePageKey(title: " My Apps Dashboard | Fullscript ", url: okta)
               == Text.samePageKey(title: "my apps dashboard | fullscript", url: "http://www.fullscript.okta.com/app/UserHome/#top"),
               "one page under other parameters shares its key")
        expect(Text.samePageKey(title: "Dash", url: okta) != Text.samePageKey(title: "Dash", url: "https://fullscript.okta.com/app/Other")
               && Text.samePageKey(title: "", url: okta) == nil, "another path or no title never shares a key")
        expect(Text.hostRange(in: "fullscript.okta.com/app/UserHome", url: okta) == NSRange(location: 0, length: 19),
               "an address title marks its host")
        expect(Text.hostRange(in: "— fullscript.okta.com", url: okta) == NSRange(location: 2, length: 19), "a site subtitle marks its host")
        expect(Text.hostRange(in: "My Apps Dashboard | Fullscript", url: okta) == nil, "a page title has no host")
        expect(Text.hostRange(in: "— file:///a.pdf", url: "file:///a.pdf") == nil, "a file path has no host")
        func marks(_ text: String, _ query: String) -> [String] {
            Text.matchRanges(in: text, query: query).map { (text as NSString).substring(with: $0) }
        }
        expect(marks("fullscript.okta.com/app/UserHome", "okta") == ["okta"], "a match after a dot starts a word")
        expect(marks("My Apps Dashboard | Fullscript", "my dash") == ["My", "Dash"], "each typed word is marked, ignoring case")
        expect(marks("fullscript.okta.com", "https://www.fullscript.ok") == ["fullscript.ok"], "a typed scheme and www are ignored")
        expect(marks("Fullscript", "script") == ["script"], "a longer match inside a word is marked once")
        expect(marks("Dashboard", "a").isEmpty && marks("Apps and all", "a") == ["A", "a", "a"],
               "a single letter is marked only where it starts a word")
        expect(marks("Team Team", "team te") == ["Team", "Team"], "overlapping marks merge")
        expect(marks("😀 Dash", "dash") == ["Dash"], "a word after an emoji starts a word")
        expect(marks("Anything", "").isEmpty && marks("", "a").isEmpty, "nothing to mark")
        expect(Text.spokenSubtitle("— chatgpt.com") == "chatgpt.com", "VoiceOver reads the URL without the dash")
        expect(Text.spokenSubtitle("= 4") == "= 4", "other subtitles are read as shown")
        expect(Text.historyTitle(pageTitle: "", url: "https://www.target.com/") == "target.com", "untitled pages show the URL")
        expect(Text.historyTitle(pageTitle: "fullscript.okta.com/app/UserHome?fromHome=true", url: okta) == "fullscript.okta.com/app/UserHome",
               "a title that is only the address shows the cleaned address")
        expect(Text.tabTitle(customTitle: "Mine", pageTitle: "Page", url: "https://a.com") == "Mine", "a custom title wins")
        expect(Text.tabTitle(customTitle: "", pageTitle: "Page", url: "https://a.com") == "Page", "then the page title")
        expect(Text.tabTitle(customTitle: nil, pageTitle: "", url: "https://www.a.com/") == "a.com", "then the URL")
        expect(Text.tabTitle(customTitle: nil, pageTitle: "", url: "about:blank") == "New Tab", "a blank page")
        expect(Text.tabTitle(customTitle: nil, pageTitle: "about:blank", url: "about:blank") == "New Tab", "a blank page named by its URL")
        expect(Text.tabTitle(customTitle: nil, pageTitle: "fullscript.okta.com/app/UserHome?x=1", url: okta)
               == "fullscript.okta.com/app/UserHome", "a tab titled by its address shows the cleaned address")

        let other = Text.tabCaption(isFavorite: false, isInActiveSpace: false, spaceName: "Work", isInSplit: true)
        expect(other == .init(text: "Work", spoken: "Switch to Tab in Work"), "another Space's tab names that Space")
        expect(Text.tabCaption(isFavorite: true, isInActiveSpace: false, spaceName: "Work", isInSplit: false).text == "Switch to Tab",
               "a Favorite belongs to no single Space")
        expect(Text.tabCaption(isFavorite: false, isInActiveSpace: true, spaceName: "Home", isInSplit: true).text == "Switch to Split View",
               "a split member in this Space")

        func row(_ type: String?, search: Bool = false, contents: String = "a.com", description: String = "",
                 url: String = "https://www.a.com/", input: String = "a") -> Text.NativeRow? {
            Text.nativeRow(matchType: type, isSearch: search, contents: contents, description: description, url: url, input: input)
        }
        for type in ["search-what-you-typed", "search-suggest", "search-suggest-entity", "search-history", "search-other-engine"] {
            let entity = row(type, search: true, contents: "New Earth Solutions Inc.", description: "Architectural designer · Ontario")
            expect(entity == .init(title: "New Earth Solutions Inc.", subtitle: nil, symbol: "magnifyingglass", isSearch: true),
                   "\(type) shows its query only")
        }
        expect(row("history-url", description: "A Site") == .init(title: "A Site", subtitle: "— a.com", symbol: "clock", isSearch: false),
               "a history match takes its description, then the URL")
        expect(row("history-title") == .init(title: "a.com", subtitle: nil, symbol: "clock", isSearch: false),
               "an untitled history match shows its address once")
        expect(row("navsuggest", description: "A Site") == .init(title: "a.com", subtitle: nil, symbol: "globe", isSearch: false),
               "a navigation suggestion keeps its contents, an address, once: its type is outside mask 0x430")
        expect(row("history-url", contents: "fullscript.okta.com/app/UserHome?fromHome=true", description: "My Apps Dashboard | Fullscript",
                   url: okta) == .init(title: "My Apps Dashboard | Fullscript", subtitle: "— fullscript.okta.com", symbol: "clock", isSearch: false),
               "the reported sign-in row names its site instead of its parameters")
        expect(row("history-url", contents: "fullscript.okta.com/app/UserHome?fromHome=true", url: okta)
               == .init(title: "fullscript.okta.com/app/UserHome", subtitle: nil, symbol: "clock", isSearch: false),
               "an untitled sign-in row shows its host and path")
        expect(row("history-url", contents: "fullscript.okta.com/app", description: "fullscript.okta.com/app/UserHome?fromHome=true",
                   url: okta)?.subtitle == nil, "a description that is only the address is no title")
        expect(row("url-what-you-typed", description: "")?.subtitle == nil, "a typed URL has no subtitle")
        expect(row("bookmark-title", description: "A") == nil, "bookmark titles never become rows")
        for type in ["history-body", "history-keyword", "search-suggest-personalized", "search-suggest-infinite",
                     "navsuggest-personalized", "open-tab", "pedal", "url-from-clipboard"] {
            expect(row(type) == nil, "\(type) is outside the result type table")
        }
        expect(row(nil, description: "A Site") == row("history-url", description: "A Site"),
               "without a match type a described match reads like history")
        expect(row(nil, description: "") == row("url-what-you-typed"), "and an undescribed one like typed input")
        expect(row(nil, search: true, contents: "hello") == row("search-suggest", search: true, contents: "hello"),
               "and a search like a suggestion")
        expect(row("search-calculator-answer", search: true, contents: "2+2 = 4", input: "2+2")
               == .init(title: "2+2", subtitle: "= 4", symbol: "plus.forwardslash.minus", isSearch: true),
               "a calculator answer follows the input the engine was given")
        expect(Text.calculatorAnswer(contents: "2 + 2 = 4", input: "2 + 2") == "4", "several words keep the answer")
        expect(Text.calculatorAnswer(contents: "pi = 3.14159", input: "pi") == nil, "one word without a digit is dropped")
        expect(Text.calculatorAnswer(contents: "5ft = 1.524 m", input: "5ft") == "1.524 m", "one word with a digit is kept")
        expect(Text.calculatorAnswer(contents: "2+2 = 4", input: "2+2 ") == nil, "an untrimmed query misses the answer")

        typealias Command = CommandBarCommandPresentation
        expect(Command.symbol(commandID: "createEasel:", title: "New Easel") == "scribble.variable", "the Easel symbol")
        expect(Command.symbol(commandID: "toggleShowToolbar:", title: "Hide Toolbar") == "rectangle.topthird.inset.filled",
               "a toggled title keeps its icon")
        expect(Command.symbol(commandID: "toggleReaderMode:", title: "Exit Reader") == "newspaper", "Exit Reader")
        expect(Command.symbol(commandID: "closeTab:", title: "Close Settings") == "archivebox",
               "Archive Tab keeps its icon while it reads Close Settings")
        expect(Command.symbol(commandID: "exportNotes:", title: "Exporting Notes…") == "arrow.down.doc", "Exporting Notes…")
        expect(Command.symbol(commandID: "thirdSplitPane:", title: "Switch to Split View 3") == "square.split.2x1", "split panes")
        expect(Command.symbol(commandID: "item3", title: "Go to Sidebar Item 3", group: "Tabs") == "arrow.right", "numbered items")
        expect(Command.symbol(commandID: "space-1", title: "Personal", group: "Spaces") == "rectangle.portrait.on.rectangle.portrait",
               "Space entries take the Spaces icon")
        expect(Command.title(commandID: "sharePage:", title: "Share…") == "Share URL", "the Type Travel title")
        expect(Command.title(commandID: "createEasel:", title: "New Easel") == "New Easel", "other titles are unchanged")

        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let menus = try! String(contentsOf: repo.appendingPathComponent("Sources/ParcApp/AppDelegate.swift"), encoding: .utf8)
        let registered = try! NSRegularExpression(pattern: #"(?:item\("[^"]+",\s*|\("[^"]+",\s*)#selector\((?:[A-Z][A-Za-z]*\.)?([a-z][A-Za-z0-9_]*)"#)
        let selectors = registered.matches(in: menus, range: NSRange(menus.startIndex..., in: menus)).map {
            String(menus[Range($0.range(at: 1), in: menus)!])
        }
        expect(selectors.count > 90, "the menu scan found the registered commands")
        for selector in Set(selectors) {
            expect(Command.symbol(forCommandID: selector + ":") != nil, "\(selector) has no command icon")
        }
        print("CommandBar result text tests passed (\(count) assertions)")
    }
}
