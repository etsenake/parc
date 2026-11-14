import Foundation

@main struct ResultTextTests {
    static func main() {
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        typealias Text = CommandBarResultText

        expect(Text.displayURL("https://www.youtube.com/") == "youtube.com", "scheme, www and trailing slash go")
        expect(Text.displayURL("https://www.youtube.com/watch?v=49_Ph2Q6uiM") == "youtube.com/watch?v=49_ph2q6uim",
               "the remainder is lowercased")
        expect(Text.displayURL("http://example.com/a/?") == "example.com/a", "one trailing ? then one trailing /")
        expect(Text.displayURL("https://example.com//") == "example.com/", "only one trailing slash is dropped")
        expect(Text.displayURL("parc://settings/") == "parc://settings", "other schemes keep their prefix")
        expect(Text.displayURL("https://wwwexample.com") == "wwwexample.com", "www is only dropped with its dot")
        expect(Text.displayURL("https://www.xn--mnchen-3ya.de/Karte") == "xn--mnchen-3ya.de/karte",
               "a Punycode host stays as written")
        expect(Text.displayURL("https://a.com/hello%20World%2F") == "a.com/hello%20world%2f", "percent escapes stay escaped")
        expect(Text.displayURL("https://xn--6y767205604493046e.example/") == "xn--6y767205604493046e.example",
               "a crafted label is never decoded")
        expect(Text.displayURL("file:///Users/Josh/Doc.PDF") == "file:///Users/Josh/Doc.PDF", "a file path keeps its case")
        let data = "data:text/plain;base64," + String(repeating: "QUJD", count: 10_000)
        expect(Text.displayURL(data).count == Text.dataURLLimit, "a data URL is capped before it is measured")
        expect(Text.urlSubtitle("https://chatgpt.com/") == "— chatgpt.com", "an em dash and a space lead the URL")
        expect(Text.urlSubtitle("") == nil, "an empty URL has no subtitle")
        expect(Text.spokenSubtitle("— chatgpt.com") == "chatgpt.com", "VoiceOver reads the URL without the dash")
        expect(Text.spokenSubtitle("= 4") == "= 4", "other subtitles are read as shown")
        expect(Text.historyTitle(pageTitle: "", url: "https://www.target.com/") == "target.com", "untitled pages show the URL")
        expect(Text.tabTitle(customTitle: "Mine", pageTitle: "Page", url: "https://a.com") == "Mine", "a custom title wins")
        expect(Text.tabTitle(customTitle: "", pageTitle: "Page", url: "https://a.com") == "Page", "then the page title")
        expect(Text.tabTitle(customTitle: nil, pageTitle: "", url: "https://www.a.com/") == "a.com", "then the URL")
        expect(Text.tabTitle(customTitle: nil, pageTitle: "", url: "about:blank") == "New Tab", "a blank page")

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
        expect(row("history-title")?.title == "a.com", "an untitled history match keeps its contents")
        expect(row("navsuggest", description: "A Site") == .init(title: "a.com", subtitle: "— a.com", symbol: "globe", isSearch: false),
               "a navigation suggestion keeps its contents: its type is outside mask 0x430")
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
        expect(Command.symbol(commandID: "toggleArcToolbar:", title: "Hide Toolbar") == "rectangle.topthird.inset.filled",
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
