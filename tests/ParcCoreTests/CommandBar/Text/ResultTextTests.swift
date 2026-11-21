import Foundation
import Testing
@testable import ParcCore

struct ResultTextTests {
    typealias Text = CommandBarResultText
    typealias Command = CommandBarCommandPresentation

    static let okta = "https://fullscript.okta.com/app/UserHome?fromHome=true&iss=https%3A%2F%2Ffullscript.okta.com"
        + "&login_hint=someone%40example.com&session_hint=AUTHENTICATED"
    var okta: String { Self.okta }

    @Test(arguments: [
        ("https://www.youtube.com/", "youtube.com"),
        ("https://www.youtube.com/watch?v=49_Ph2Q6uiM", "youtube.com/watch"),
        (ResultTextTests.okta, "fullscript.okta.com/app/UserHome"),
        ("https://Docs.Example.COM/App/UserHome#Section-2", "docs.example.com/App/UserHome"),
        ("http://example.com/a/?", "example.com/a"),
        ("https://example.com//", "example.com/"),
        ("parc://settings/", "parc://settings"),
        ("https://wwwexample.com", "wwwexample.com"),
        ("https://www.com/", "www.com"),
        ("http://localhost:3000/Board?x=1", "localhost:3000/Board"),
        ("https://www.xn--mnchen-3ya.de/Karte", "xn--mnchen-3ya.de/Karte"),
        ("https://xn--6y767205604493046e.example/", "xn--6y767205604493046e.example"),
        ("https://\u{0430}pple.com/", "%D0%B0pple.com"),
        ("https://accounts.google.com@evil.example/login", "evil.example/login"),
        ("http://evil.example\\@google.com/", "evil.example\\@google.com"),
        ("https://a.com/hello%20World%2F%3F%23%25%26%3D%2B", "a.com/hello World%2F%3F%23%25%26%3D%2B"),
        ("https://a.com/caf%C3%A9/%E2%9C%93", "a.com/café/✓"),
        ("https://a.com/x\u{202E}y", "a.com/x%E2%80%AEy"),
        ("https://a.com/%41%62c/%F0%9F%98%80", "a.com/Abc/😀"),
        ("https://\u{212A}ayak.com/", "%E2%84%AAayak.com"),
        ("HTTPS://WWW.Example.com/A", "example.com/A"),
        ("file:///Users/Josh/My%20Doc.PDF?page=2", "file:///Users/Josh/My Doc.PDF"),
        ("mailto:Jo%20Doe@example.com?subject=Hi", "mailto:Jo Doe@example.com"),
    ])
    func displayURLShowsTheReadableHostAndPath(input: String, expected: String) {
        #expect(Text.displayURL(input) == expected)
    }

    @Test func anUppercaseDataURLIsCappedToo() {
        #expect(Text.displayURL("DATA:text/plain," + String(repeating: "a", count: 1_000)).count == Text.dataURLLimit)
    }

    @Test func aHugePathIsBoundedBeforeItIsRead() {
        #expect(Text.displayURL("https://a.com/" + String(repeating: "b", count: 10_000)).count == 6 + Text.pathLimit - 1)
    }

    @Test func aDataURLIsCappedBeforeItIsMeasured() {
        let data = "data:text/plain;base64," + String(repeating: "QUJD", count: 10_000)
        #expect(Text.displayURL(data).count == Text.dataURLLimit)
    }

    @Test(arguments: [
        ("%E2%80%AE", "a right-to-left override"), ("%E2%80%8B", "a zero-width space"),
        ("%C2%A0", "a no-break space"), ("%F0%9F%94%92", "a lock emoji"), ("%E2%A0%80", "a blank braille cell"),
        ("%EF%BB%BF", "a byte order mark"), ("%C3", "a cut-off sequence"), ("%C0%AF", "an overlong slash"),
        ("%00", "a null byte"), ("%0A", "a line feed"),
    ])
    func misleadingEscapedCharactersStayEscaped(escape: String, why: String) {
        #expect(Text.displayURL("https://a.com/x" + escape + "y") == "a.com/x" + escape + "y", Comment(rawValue: why))
    }

    @Test func aSubtitleLeadsWithAnEmDashAndNamesJustTheSite() {
        #expect(Text.urlSubtitle("https://chatgpt.com/") == "— chatgpt.com")
        #expect(Text.urlSubtitle(okta) == "— fullscript.okta.com")
    }

    @Test func aFileHasNoSiteSoItsPathShowsInTheSubtitle() {
        #expect(Text.urlSubtitle("file:///Users/Josh/Doc.pdf") == "— file:///Users/Josh/Doc.pdf")
    }

    @Test func anEmptyURLHasNoSubtitle() {
        #expect(Text.urlSubtitle("") == nil)
    }

    @Test func aRealTitleSaysWhatThePageIs() {
        #expect(Text.pageTitle("My Apps Dashboard | Fullscript", url: okta) != nil)
    }

    @Test(arguments: ["", "  ", "fullscript.okta.com/app/UserHome?fromHome=true", "https://fullscript.okta.com/app/UserHome",
                      "FULLSCRIPT.OKTA.COM", "www.fullscript.okta.com/app"])
    func aTitleThatIsOnlyTheAddressIsNotATitle(title: String) {
        #expect(Text.pageTitle(title, url: okta) == nil)
    }

    @Test func aOneWordTitleIsStillATitle() {
        #expect(Text.pageTitle("Fullscript", url: okta) != nil)
        #expect(Text.pageTitle("Settings", url: "parc://settings") != nil)
    }

    @Test func anAddressWithASpaceIsStillOnlyTheAddress() {
        #expect(Text.pageTitle("a.com/hello world", url: "https://a.com/hello%20world") == nil)
        #expect(Text.pageTitle("google.com/search?q=new york", url: "https://www.google.com/search?q=new+york") == nil)
    }

    @Test func aTitleNamingItsSiteIsATitle() {
        #expect(Text.pageTitle("A.com is great", url: "https://a.com/") != nil)
    }

    @Test func anInternalPageNamedByItsAddressHasNoTitle() {
        #expect(Text.pageTitle("parc://settings", url: "parc://settings/") == nil)
    }

    @Test func aDataPageKeepsItsTitleAndNeverJoinsAnotherRow() {
        let hugeData = "data:text/html," + String(repeating: "a", count: 2_000_000)
        #expect(Text.pageTitle("Hello", url: hugeData) != nil)
        #expect(Text.samePageKey(title: "Hello", url: hugeData) == nil)
    }

    @Test func aTitledPageNamesItsSite() {
        #expect(Text.pageSubtitle(title: "My Apps Dashboard | Fullscript", url: okta) == "— fullscript.okta.com")
    }

    @Test func anUntitledPageShowsItsAddressOnce() {
        #expect(Text.pageSubtitle(title: "", url: okta) == nil)
    }

    @Test func onePageUnderOtherParametersSharesItsKey() {
        #expect(Text.samePageKey(title: " My Apps Dashboard | Fullscript ", url: okta)
                == Text.samePageKey(title: "my apps dashboard | fullscript", url: "http://www.fullscript.okta.com/app/UserHome/#top"))
    }

    @Test func anotherPathOrNoTitleNeverSharesAKey() {
        #expect(Text.samePageKey(title: "Dash", url: okta) != Text.samePageKey(title: "Dash", url: "https://fullscript.okta.com/app/Other"))
        #expect(Text.samePageKey(title: "", url: okta) == nil)
    }

    @Test func anAddressTitleMarksItsHost() {
        #expect(Text.hostRange(in: "fullscript.okta.com/app/UserHome", url: okta) == NSRange(location: 0, length: 19))
    }

    @Test func aSiteSubtitleMarksItsHost() {
        #expect(Text.hostRange(in: "— fullscript.okta.com", url: okta) == NSRange(location: 2, length: 19))
    }

    @Test func aPageTitleHasNoHost() {
        #expect(Text.hostRange(in: "My Apps Dashboard | Fullscript", url: okta) == nil)
    }

    @Test func aFilePathHasNoHost() {
        #expect(Text.hostRange(in: "— file:///a.pdf", url: "file:///a.pdf") == nil)
    }

    func marks(_ text: String, _ query: String) -> [String] {
        Text.matchRanges(in: text, query: query).map { (text as NSString).substring(with: $0) }
    }

    @Test func aMatchAfterADotStartsAWord() {
        #expect(marks("fullscript.okta.com/app/UserHome", "okta") == ["okta"])
    }

    @Test func eachTypedWordIsMarkedIgnoringCase() {
        #expect(marks("My Apps Dashboard | Fullscript", "my dash") == ["My", "Dash"])
    }

    @Test func aTypedSchemeAndWwwAreIgnored() {
        #expect(marks("fullscript.okta.com", "https://www.fullscript.ok") == ["fullscript.ok"])
    }

    @Test func aLongerMatchInsideAWordIsMarkedOnce() {
        #expect(marks("Fullscript", "script") == ["script"])
    }

    @Test func aSingleLetterIsMarkedOnlyWhereItStartsAWord() {
        #expect(marks("Dashboard", "a").isEmpty)
        #expect(marks("Apps and all", "a") == ["A", "a", "a"])
    }

    @Test func overlappingMarksMerge() {
        #expect(marks("Team Team", "team te") == ["Team", "Team"])
    }

    @Test func aWordAfterAnEmojiStartsAWord() {
        #expect(marks("😀 Dash", "dash") == ["Dash"])
    }

    @Test func thereIsNothingToMarkForAnEmptyTextOrQuery() {
        #expect(marks("Anything", "").isEmpty)
        #expect(marks("", "a").isEmpty)
    }

    @Test func voiceOverReadsTheURLWithoutTheDash() {
        #expect(Text.spokenSubtitle("— chatgpt.com") == "chatgpt.com")
    }

    @Test func otherSubtitlesAreReadAsShown() {
        #expect(Text.spokenSubtitle("= 4") == "= 4")
    }

    @Test func untitledHistoryPagesShowTheURL() {
        #expect(Text.historyTitle(pageTitle: "", url: "https://www.target.com/") == "target.com")
    }

    @Test func aHistoryTitleThatIsOnlyTheAddressShowsTheCleanedAddress() {
        #expect(Text.historyTitle(pageTitle: "fullscript.okta.com/app/UserHome?fromHome=true", url: okta)
                == "fullscript.okta.com/app/UserHome")
    }

    @Test func aCustomTabTitleWins() {
        #expect(Text.tabTitle(customTitle: "Mine", pageTitle: "Page", url: "https://a.com") == "Mine")
    }

    @Test func aTabFallsBackToThePageTitleThenTheURL() {
        #expect(Text.tabTitle(customTitle: "", pageTitle: "Page", url: "https://a.com") == "Page")
        #expect(Text.tabTitle(customTitle: nil, pageTitle: "", url: "https://www.a.com/") == "a.com")
    }

    @Test func aBlankPageIsANewTab() {
        #expect(Text.tabTitle(customTitle: nil, pageTitle: "", url: "about:blank") == "New Tab")
        #expect(Text.tabTitle(customTitle: nil, pageTitle: "about:blank", url: "about:blank") == "New Tab")
    }

    @Test func aTabTitledByItsAddressShowsTheCleanedAddress() {
        #expect(Text.tabTitle(customTitle: nil, pageTitle: "fullscript.okta.com/app/UserHome?x=1", url: okta)
                == "fullscript.okta.com/app/UserHome")
    }

    @Test func anotherSpacesTabNamesThatSpace() {
        let caption = Text.tabCaption(isFavorite: false, isInActiveSpace: false, spaceName: "Work", isInSplit: true)
        #expect(caption == .init(text: "Work", spoken: "Switch to Tab in Work"))
    }

    @Test func aFavoriteBelongsToNoSingleSpace() {
        #expect(Text.tabCaption(isFavorite: true, isInActiveSpace: false, spaceName: "Work", isInSplit: false).text == "Switch to Tab")
    }

    @Test func aSplitMemberInThisSpaceReadsSwitchToSplitView() {
        #expect(Text.tabCaption(isFavorite: false, isInActiveSpace: true, spaceName: "Home", isInSplit: true).text == "Switch to Split View")
    }

    func row(_ type: String?, search: Bool = false, contents: String = "a.com", description: String = "",
             url: String = "https://www.a.com/", input: String = "a") -> Text.NativeRow? {
        Text.nativeRow(matchType: type, isSearch: search, contents: contents, description: description, url: url, input: input)
    }

    @Test(arguments: ["search-what-you-typed", "search-suggest", "search-suggest-entity", "search-history", "search-other-engine"])
    func searchRowsShowTheirQueryOnly(type: String) {
        let entity = row(type, search: true, contents: "New Earth Solutions Inc.", description: "Architectural designer · Ontario")
        #expect(entity == .init(title: "New Earth Solutions Inc.", subtitle: nil, symbol: "magnifyingglass", isSearch: true))
    }

    @Test func aHistoryMatchTakesItsDescriptionThenTheURL() {
        #expect(row("history-url", description: "A Site") == .init(title: "A Site", subtitle: "— a.com", symbol: "clock", isSearch: false))
    }

    @Test func anUntitledHistoryMatchShowsItsAddressOnce() {
        #expect(row("history-title") == .init(title: "a.com", subtitle: nil, symbol: "clock", isSearch: false))
    }

    @Test func aNavigationSuggestionKeepsItsContentsAnAddressOnce() {
        #expect(row("navsuggest", description: "A Site") == .init(title: "a.com", subtitle: nil, symbol: "globe", isSearch: false))
    }

    @Test func theReportedSignInRowNamesItsSiteInsteadOfItsParameters() {
        let signIn = row("history-url", contents: "fullscript.okta.com/app/UserHome?fromHome=true",
                         description: "My Apps Dashboard | Fullscript", url: okta)
        #expect(signIn == .init(title: "My Apps Dashboard | Fullscript", subtitle: "— fullscript.okta.com", symbol: "clock", isSearch: false))
    }

    @Test func anUntitledSignInRowShowsItsHostAndPath() {
        #expect(row("history-url", contents: "fullscript.okta.com/app/UserHome?fromHome=true", url: okta)
                == .init(title: "fullscript.okta.com/app/UserHome", subtitle: nil, symbol: "clock", isSearch: false))
    }

    @Test func aDescriptionThatIsOnlyTheAddressIsNoTitle() {
        #expect(row("history-url", contents: "fullscript.okta.com/app",
                    description: "fullscript.okta.com/app/UserHome?fromHome=true", url: okta)?.subtitle == nil)
    }

    @Test func aTypedURLHasNoSubtitle() {
        #expect(row("url-what-you-typed", description: "")?.subtitle == nil)
    }

    @Test func bookmarkTitlesNeverBecomeRows() {
        #expect(row("bookmark-title", description: "A") == nil)
    }

    @Test(arguments: ["history-body", "history-keyword", "search-suggest-personalized", "search-suggest-infinite",
                      "navsuggest-personalized", "open-tab", "pedal", "url-from-clipboard"])
    func typesOutsideTheResultTypeTableMakeNoRow(type: String) {
        #expect(row(type) == nil)
    }

    @Test func withoutAMatchTypeADescribedMatchReadsLikeHistory() {
        #expect(row(nil, description: "A Site") == row("history-url", description: "A Site"))
    }

    @Test func withoutAMatchTypeAnUndescribedMatchReadsLikeTypedInput() {
        #expect(row(nil, description: "") == row("url-what-you-typed"))
    }

    @Test func withoutAMatchTypeASearchReadsLikeASuggestion() {
        #expect(row(nil, search: true, contents: "hello") == row("search-suggest", search: true, contents: "hello"))
    }

    @Test func aCalculatorAnswerFollowsTheInputTheEngineWasGiven() {
        #expect(row("search-calculator-answer", search: true, contents: "2+2 = 4", input: "2+2")
                == .init(title: "2+2", subtitle: "= 4", symbol: "plus.forwardslash.minus", isSearch: true))
    }

    @Test func severalWordsKeepTheCalculatorAnswer() {
        #expect(Text.calculatorAnswer(contents: "2 + 2 = 4", input: "2 + 2") == "4")
    }

    @Test func oneWordWithoutADigitDropsTheCalculatorAnswer() {
        #expect(Text.calculatorAnswer(contents: "pi = 3.14159", input: "pi") == nil)
    }

    @Test func oneWordWithADigitKeepsTheCalculatorAnswer() {
        #expect(Text.calculatorAnswer(contents: "5ft = 1.524 m", input: "5ft") == "1.524 m")
    }

    @Test func anUntrimmedQueryMissesTheCalculatorAnswer() {
        #expect(Text.calculatorAnswer(contents: "2+2 = 4", input: "2+2 ") == nil)
    }

    @Test(arguments: [
        ("createEasel:", "New Easel", "parc.easel"),
        ("createNote:", "New Note", "parc.note"),
        ("toggleShowToolbar:", "Hide Toolbar", "rectangle.topthird.inset.filled"),
        ("toggleReaderMode:", "Exit Reader", "newspaper"),
        ("closeTab:", "Close Settings", "archivebox"),
        ("showNotesFolder:", "Show Notes Folder", "folder"),
        ("thirdSplitPane:", "Switch to Split View 3", "square.split.2x1"),
    ])
    func commandsShowTheirIcon(commandID: String, title: String, symbol: String) {
        #expect(Command.symbol(commandID: commandID, title: title) == symbol)
    }

    @Test func numberedItemsShowTheArrowIcon() {
        #expect(Command.symbol(commandID: "item3", title: "Go to Sidebar Item 3", group: "Tabs") == "arrow.right")
    }

    @Test func spaceEntriesTakeTheSpacesIcon() {
        #expect(Command.symbol(commandID: "space-1", title: "Personal", group: "Spaces") == "rectangle.portrait.on.rectangle.portrait")
    }

    @Test func sharePageUsesTheTypeTravelTitle() {
        #expect(Command.title(commandID: "sharePage:", title: "Share…") == "Share URL")
    }

    @Test func otherCommandTitlesAreUnchanged() {
        #expect(Command.title(commandID: "createEasel:", title: "New Easel") == "New Easel")
    }

    @Test func everyMenuRegisteredCommandHasAnIcon() throws {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
            directory.deleteLastPathComponent()
        }
        let menus = try String(contentsOf: directory.appendingPathComponent("Sources/ParcApp/AppDelegate.swift"), encoding: .utf8)
        let registered = try NSRegularExpression(pattern: #"(?:item\("[^"]+",\s*|\("[^"]+",\s*)#selector\((?:[A-Z][A-Za-z]*\.)?([a-z][A-Za-z0-9_]*)"#)
        let selectors = registered.matches(in: menus, range: NSRange(menus.startIndex..., in: menus)).map {
            String(menus[Range($0.range(at: 1), in: menus)!])
        }
        #expect(selectors.count > 90)
        for selector in Set(selectors) {
            #expect(Command.symbol(forCommandID: selector + ":") != nil, "\(selector) has no command icon")
        }
    }
}
