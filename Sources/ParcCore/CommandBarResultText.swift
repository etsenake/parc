import Foundation

package enum CommandBarResultText {
    package struct Address: Equatable {
        package let host: String
        package let path: String
        package var text: String { host + path }

        package init(host: String, path: String) {
            self.host = host
            self.path = path
        }
    }

    package static func address(_ url: String) -> Address {
        if isData(url) { return Address(host: "", path: String(url.prefix(dataURLLimit))) }
        guard let parts = split(url) else {
            return Address(host: "", path: readable(url.prefix(pathLimit).prefix { $0 != "?" && $0 != "#" }))
        }
        var path = parts.rest.prefix(pathLimit).prefix { $0 != "?" && $0 != "#" }
        if path.hasSuffix("/") { path = path.dropLast() }
        let host = hostText(parts.authority)
        switch parts.scheme {
        case "http", "https":
            return Address(host: siteHost(host), path: readable(path))
        default:
            let prefix = parts.scheme + "://"
            return host.isEmpty ? Address(host: "", path: prefix + readable(path)) : Address(host: prefix + host, path: readable(path))
        }
    }

    static func displayURL(_ url: String) -> String { address(url).text }

    static let dataURLLimit = 256
    static let pathLimit = 4096

    private static func isData(_ url: String) -> Bool { url.prefix(5).lowercased() == "data:" }

    package static func urlSubtitle(_ url: String) -> String? {
        let shown = address(url)
        let text = shown.host.isEmpty ? shown.text : shown.host
        return text.isEmpty ? nil : "— " + text
    }

    package static func pageTitle(_ title: String, url: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || isAddress(trimmed, of: url) ? nil : title
    }

    package static func pageSubtitle(title: String, url: String) -> String? {
        pageTitle(title, url: url) == nil ? nil : urlSubtitle(url)
    }

    package static func samePageKey(title: String, url: String) -> String? {
        guard !isData(url), pageTitle(title, url: url) != nil else { return nil }
        return title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "\u{0}" + address(url).text
    }

    package static func hostRange(in text: String, url: String) -> NSRange? {
        let shown = address(url)
        guard !shown.host.isEmpty else { return nil }
        let length = (shown.host as NSString).length
        if text == shown.text { return NSRange(location: 0, length: length) }
        if text == "— " + shown.host || text == "— " + shown.text { return NSRange(location: 2, length: length) }
        return nil
    }

    package static func matchRanges(in text: String, query: String) -> [NSRange] {
        let terms = query.split(whereSeparator: \.isWhitespace).prefix(8).map(bareTerm).filter { !$0.isEmpty }
        guard !terms.isEmpty, !text.isEmpty else { return [] }
        let string = text as NSString
        var ranges: [NSRange] = []
        for term in terms {
            var found: [NSRange] = [], location = 0
            while found.count < 16, location < string.length {
                let range = string.range(of: term, options: .caseInsensitive,
                                         range: NSRange(location: location, length: string.length - location))
                guard range.location != NSNotFound, range.length > 0 else { break }
                found.append(range); location = NSMaxRange(range)
            }
            let starts = found.filter { startsWord($0.location, in: string) }
            ranges += starts.isEmpty && (term as NSString).length > 1 ? Array(found.prefix(1)) : starts
        }
        return ranges.sorted { $0.location < $1.location }.reduce(into: []) { merged, range in
            if let last = merged.last, range.location <= NSMaxRange(last) {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else {
                merged.append(range)
            }
        }
    }

    private static func bareTerm(_ term: Substring) -> String {
        var term = term
        for prefix in ["https://", "http://", "www."] where term.lowercased().hasPrefix(prefix) { term = term.dropFirst(prefix.count) }
        return String(term)
    }

    private static func startsWord(_ location: Int, in string: NSString) -> Bool {
        guard location > 0, let scalar = Unicode.Scalar(string.character(at: location - 1)) else { return true }
        return !CharacterSet.alphanumerics.contains(scalar)
    }

    private static func split(_ url: String) -> (scheme: String, authority: Substring, rest: Substring)? {
        let scheme = url.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }
        guard scheme.first?.isLetter == true, url[scheme.endIndex...].hasPrefix("://") else { return nil }
        let remainder = url[url.index(scheme.endIndex, offsetBy: 3)...]
        let authority = remainder.prefix { $0 != "/" && $0 != "?" && $0 != "#" && $0 != "\\" }
        return (scheme.lowercased(), authority, remainder[authority.endIndex...])
    }

    private static func hostText(_ authority: Substring) -> String {
        let host = authority.lastIndex(of: "@").map { authority[authority.index(after: $0)...] } ?? authority
        var text = ""
        for scalar in host.unicodeScalars {
            switch scalar.value {
            case 0x41...0x5A: text.unicodeScalars.append(Unicode.Scalar(UInt8(scalar.value + 0x20)))
            case 0x21..<0x7F: text.unicodeScalars.append(scalar)
            default: text += escaped(scalar)
            }
        }
        return text
    }

    private static func siteHost(_ host: String) -> String {
        host.hasPrefix("www.") && host.dropFirst(4).contains(".") ? String(host.dropFirst(4)) : host
    }

    private static func isAddress(_ title: String, of url: String) -> Bool {
        let lowered = title.lowercased()
        if let parts = split(url), parts.scheme == "http" || parts.scheme == "https" {
            let host = siteHost(hostText(parts.authority))
            var rest = Substring(lowered)
            for prefix in ["https://", "http://"] where rest.hasPrefix(prefix) { rest = rest.dropFirst(prefix.count) }
            return !host.isEmpty && siteHost(String(rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" })) == host
        }
        guard abs(lowered.utf8.count - url.utf8.count) <= 1 else { return false }
        func bare(_ text: String) -> Substring { text.hasSuffix("/") ? text.dropLast() : Substring(text) }
        return bare(lowered) == bare(url.lowercased())
    }

    private static let readableASCII = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$'()*,;:@ ".utf8)
    private static let lookalikes: Set<UInt32> = [0x2800, 0x1F50F, 0x1F510, 0x1F512, 0x1F513]

    private static func showsUnescaped(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.isASCII { return readableASCII.contains(UInt8(scalar.value)) }
        let properties = scalar.properties
        switch properties.generalCategory {
        case .control, .format, .spaceSeparator, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned:
            return false
        default:
            return !properties.isDefaultIgnorableCodePoint && !properties.isNoncharacterCodePoint
                && !properties.isWhitespace && !lookalikes.contains(scalar.value)
        }
    }

    private static func escaped(_ scalar: Unicode.Scalar) -> String {
        String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
    }

    private static func readable(_ text: Substring) -> String {
        let bytes = Array(text.utf8)
        guard bytes.contains(where: { $0 == 0x25 || $0 < 0x20 || $0 >= 0x7F }) else { return String(text) }
        func hex(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 0x30...0x39: return byte - 0x30
            case 0x41...0x46: return byte - 0x37
            case 0x61...0x66: return byte - 0x57
            default: return nil
            }
        }
        func decoded(at index: Int) -> UInt8? {
            guard index + 2 < bytes.count, bytes[index] == 0x25, let high = hex(bytes[index + 1]), let low = hex(bytes[index + 2]) else { return nil }
            return high << 4 | low
        }
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            guard let first = decoded(at: index) else { out.append(bytes[index]); index += 1; continue }
            let length = first < 0x80 ? 1 : first >= 0xF0 ? 4 : first >= 0xE0 ? 3 : first >= 0xC2 ? 2 : 0
            var run = [first], next = index + 3
            while run.count < length, let byte = decoded(at: next), byte & 0xC0 == 0x80 { run.append(byte); next += 3 }
            if run.count == length, let character = String(bytes: run, encoding: .utf8),
               character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first, showsUnescaped(scalar) {
                out += run; index = next
            } else {
                out += bytes[index..<index + 3]; index += 3
            }
        }
        let result = String(decoding: out, as: UTF8.self)
        func unsafe(_ scalar: Unicode.Scalar) -> Bool {
            scalar.isASCII ? scalar.value < 0x20 || scalar.value == 0x7F : !showsUnescaped(scalar)
        }
        guard result.unicodeScalars.contains(where: unsafe) else { return result }
        var safe = ""
        for scalar in result.unicodeScalars {
            if unsafe(scalar) { safe += escaped(scalar) } else { safe.unicodeScalars.append(scalar) }
        }
        return safe
    }

    package static func spokenSubtitle(_ subtitle: String?) -> String {
        guard let subtitle else { return "" }
        return subtitle.hasPrefix("— ") ? String(subtitle.dropFirst(2)) : subtitle
    }

    package static func historyTitle(pageTitle: String, url: String) -> String {
        self.pageTitle(pageTitle, url: url) ?? displayURL(url)
    }

    package static func tabTitle(customTitle: String?, pageTitle: String, url: String) -> String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if let title = self.pageTitle(pageTitle, url: url) { return title }
        return BrowserState.isBlankPage(url) ? "New Tab" : displayURL(url)
    }

    package struct TabCaption: Equatable {
        package let text: String
        package let spoken: String

        package init(text: String, spoken: String) {
            self.text = text
            self.spoken = spoken
        }
        package static let switchToTab = TabCaption(text: "Switch to Tab", spoken: "Switch to Tab")
    }

    package static func tabCaption(isFavorite: Bool, isInActiveSpace: Bool, spaceName: String?, isInSplit: Bool) -> TabCaption {
        if !isFavorite, !isInActiveSpace, let spaceName, !spaceName.isEmpty {
            return TabCaption(text: spaceName, spoken: "Switch to Tab in " + spaceName)
        }
        return isInSplit ? TabCaption(text: "Switch to Split View", spoken: "Switch to Split View") : .switchToTab
    }

    enum NativeKind: Equatable {
        case search
        case history
        case navSuggestion
        case typedURL
        case calculator(answer: String)
    }

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

    package struct NativeRow: Equatable {
        package let title: String
        package let subtitle: String?
        package let symbol: String
        package let isSearch: Bool
    }

    package static func nativeRow(matchType: String?, isSearch: Bool, contents: String, description: String,
                          url: String, input: String, preserveDefault: Bool = false) -> NativeRow? {
        let shown = contents.isEmpty ? displayURL(url) : contents
        let kind = nativeKind(matchType: matchType, isSearch: isSearch, contents: contents, description: description, input: input)
            ?? (preserveDefault ? nativeKind(matchType: nil, isSearch: isSearch, contents: contents, description: description, input: input) : nil)
        switch kind {
        case .search:
            return NativeRow(title: shown, subtitle: nil, symbol: "magnifyingglass", isSearch: true)
        case .history:
            return NativeRow(title: historyTitle(pageTitle: description, url: url),
                             subtitle: pageSubtitle(title: description, url: url), symbol: "clock", isSearch: false)
        case .navSuggestion:
            return NativeRow(title: historyTitle(pageTitle: contents, url: url),
                             subtitle: pageSubtitle(title: contents, url: url), symbol: "globe", isSearch: false)
        case .typedURL:
            return NativeRow(title: shown, subtitle: nil, symbol: "globe", isSearch: false)
        case .calculator(let answer):
            return NativeRow(title: input, subtitle: "= " + answer, symbol: "plus.forwardslash.minus", isSearch: true)
        case nil:
            return nil
        }
    }
}
