import Foundation

///
///
enum CommandBarResultText {
    ///
    /// trailing "?" and then one trailing "/" dropped, then "https://" or else
    /// "http://", then a leading "www.", and the remainder lowercased. Other
    /// schemes keep their prefix. Punycode hosts and percent escapes stay as
    /// written, so Chromium's spoofing protections hold. Parc keeps a file
    /// path's case and caps a data URL before it is measured.
    static func displayURL(_ url: String) -> String {
        var text = Substring(url.hasPrefix("data:") ? String(url.prefix(dataURLLimit)) : url)
        if text.hasSuffix("?") { text = text.dropLast() }
        if text.hasSuffix("/") { text = text.dropLast() }
        if text.hasPrefix("https://") {
            text = text.dropFirst(8)
        } else if text.hasPrefix("http://") {
            text = text.dropFirst(7)
        }
        if text.hasPrefix("www.") { text = text.dropFirst(4) }
        return url.hasPrefix("file:") ? String(text) : text.lowercased()
    }

    /// A data URL is cut to this many characters before any row measures it.
    static let dataURLLimit = 256

    ///
    ///
    ///
    static func urlSubtitle(_ url: String) -> String? {
        let display = displayURL(url)
        return display.isEmpty ? nil : "— " + display
    }

    /// The subtitle as VoiceOver reads it: the URL itself, without the dash.
    static func spokenSubtitle(_ subtitle: String?) -> String {
        guard let subtitle else { return "" }
        return subtitle.hasPrefix("— ") ? String(subtitle.dropFirst(2)) : subtitle
    }

    ///
    /// history or bookmark match's description when it is non-empty and its
    ///
    static func historyTitle(pageTitle: String, url: String) -> String {
        pageTitle.isEmpty ? displayURL(url) : pageTitle
    }

    /// An open tab's title: its custom title, else its page title, else the
    ///
    static func tabTitle(customTitle: String?, pageTitle: String, url: String) -> String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if !pageTitle.isEmpty { return pageTitle }
        return BrowserState.isBlankPage(url) ? "New Tab" : displayURL(url)
    }

    ///
    /// Space's name, else Switch to Split View for a split member, else Switch
    /// to Tab. Favorites belong to no single Space.
    struct TabCaption: Equatable {
        let text: String
        let spoken: String
        static let switchToTab = TabCaption(text: "Switch to Tab", spoken: "Switch to Tab")
    }

    static func tabCaption(isFavorite: Bool, isInActiveSpace: Bool, spaceName: String?, isInSplit: Bool) -> TabCaption {
        if !isFavorite, !isInActiveSpace, let spaceName, !spaceName.isEmpty {
            return TabCaption(text: spaceName, spoken: "Switch to Tab in " + spaceName)
        }
        return isInSplit ? TabCaption(text: "Switch to Split View", spoken: "Switch to Split View") : .switchToTab
    }

    ///
    ///
    enum NativeKind: Equatable {
        /// Query only, no description (search-what-you-typed, suggestions,
        /// entity suggestions, search history, other engines).
        case search
        /// The page title, else contents, then the URL subtitle.
        case history
        /// Contents, then the URL subtitle.
        case navSuggestion
        /// Contents and nothing else.
        case typedURL
        /// The typed input, then "= answer".
        case calculator(answer: String)
    }

    ///
    ///
    /// never become candidates. A calculator match survives only when its
    /// contents read "<input> = <answer>" and the input is not one word without
    /// a digit. Without a match type, a search keeps its query, a description
    /// marks a history match and anything else is typed input.
    static func nativeKind(matchType: String?, isSearch: Bool, contents: String, description: String, input: String) -> NativeKind? {
        guard let matchType else {
            return isSearch ? .search : description.isEmpty ? .typedURL : .history
        }
        switch matchType {
        case "search-what-you-typed", "search-suggest", "search-suggest-entity", "search-history", "search-other-engine":
            return .search
        case "history-url", "history-title":
            return .history
        case "navsuggest":
            return .navSuggestion
        case "url-what-you-typed":
            return .typedURL
        case "search-calculator-answer":
            return calculatorAnswer(contents: contents, input: input).map { .calculator(answer: $0) }
        default:
            return nil
        }
    }

    static func calculatorAnswer(contents: String, input: String) -> String? {
        let prefix = input + " = "
        guard !input.isEmpty, contents.hasPrefix(prefix) else { return nil }
        if input.split(separator: " ").count < 2, !input.contains(where: \.isNumber) { return nil }
        let answer = String(contents.dropFirst(prefix.count))
        return answer.isEmpty ? nil : answer
    }

    struct NativeRow: Equatable {
        let title: String
        let subtitle: String?
        let symbol: String
        /// Search glyphs stay off the selected row's icon tile.
        let isSearch: Bool
    }

    /// One Chromium match as a row. Only history, bookmark and history-title
    ///
    /// mask `0x430`: indices 4, 5 and 10); navigation suggestions keep their
    /// contents. History and navigation suggestions add the URL subtitle
    ///
    static func nativeRow(matchType: String?, isSearch: Bool, contents: String, description: String,
                          url: String, input: String) -> NativeRow? {
        let shown = contents.isEmpty ? displayURL(url) : contents
        switch nativeKind(matchType: matchType, isSearch: isSearch, contents: contents, description: description, input: input) {
        case .search:
            return NativeRow(title: shown, subtitle: nil, symbol: "magnifyingglass", isSearch: true)
        case .history:
            return NativeRow(title: description.isEmpty ? shown : description, subtitle: urlSubtitle(url), symbol: "clock", isSearch: false)
        case .navSuggestion:
            return NativeRow(title: shown, subtitle: urlSubtitle(url), symbol: "globe", isSearch: false)
        case .typedURL:
            return NativeRow(title: shown, subtitle: nil, symbol: "globe", isSearch: false)
        case .calculator(let answer):
            //
            return NativeRow(title: input, subtitle: "= " + answer, symbol: "plus.forwardslash.minus", isSearch: true)
        case nil:
            return nil
        }
    }
}
