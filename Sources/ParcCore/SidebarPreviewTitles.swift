import Foundation

struct TidyTitleRule: Equatable {
    enum Match: Equatable {
        case pathEquals(String), pathContainsRegex(String), fragmentEquals(String), fragmentContainsRegex(String)
    }
    enum Title: Equatable { case always(String), removing([String]) }
    var match: Match?
    var title: Title

    func matches(_ url: URL) -> Bool {
        let path = url.path.isEmpty ? "/" : url.path, fragment = url.fragment ?? ""
        switch match {
        case nil: return true
        case .pathEquals(let value): return path == value
        case .fragmentEquals(let value): return fragment == value
        case .pathContainsRegex(let pattern): return TidyTitles.expression(pattern)?.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
        case .fragmentContainsRegex(let pattern): return TidyTitles.expression(pattern)?.firstMatch(in: fragment, range: NSRange(fragment.startIndex..., in: fragment)) != nil
        }
    }
}

enum TidyTitles {
    static func title(for url: URL, title: String, rules: [String: [TidyTitleRule]] = parcRules) -> String? {
        guard var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        guard let rule = rules[host]?.first(where: { $0.matches(url) }) else { return nil }
        let result: String
        switch rule.title {
        case .always(let value): result = value
        case .removing(let patterns):
            result = patterns.reduce(title) { text, pattern in
                guard let expression = expression(pattern) else { return text }
                return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : result
    }

    private static let expressions = NSCache<NSString, NSRegularExpression>()
    static func expression(_ pattern: String) -> NSRegularExpression? {
        if let cached = expressions.object(forKey: pattern as NSString) { return cached }
        guard let compiled = try? NSRegularExpression(pattern: pattern) else { return nil }
        expressions.setObject(compiled, forKey: pattern as NSString)
        return compiled
    }

    private static let notion: [TidyTitleRule] = [
        TidyTitleRule(match: .pathEquals("/"), title: .always("Notion")),
        TidyTitleRule(match: nil, title: .removing(["^\\([0-9]+\\+?\\)\\s", " \\| Notion$"])),
    ]
    static let parcRules: [String: [TidyTitleRule]] = [
        "notion.so": notion, "app.notion.com": notion,
        "figma.com": [
            TidyTitleRule(match: .pathEquals("/"), title: .always("Figma")),
            TidyTitleRule(match: .pathEquals("/files/recent"), title: .always("Recently Viewed")),
            TidyTitleRule(match: .pathContainsRegex("^/(file|files|design|board|proto|slides)/.+"), title: .removing([" – Figma$"])),
        ],
    ]
}

enum RecentPageText {
    enum Provider: String { case notion, figma, linear, confluence }

    static func tidyTitle(_ provider: Provider, url: URL, title: String) -> String {
        switch provider {
        case .notion, .figma: return TidyTitles.title(for: url, title: title) ?? title
        case .linear:
            let tidy = TidyTitles.title(for: url, title: title) ?? title
            guard let id = linearTicketID(url) else { return tidy }
            return (tidy.hasPrefix(id) ? String(tidy.dropFirst(id.count)) : tidy).trimmingCharacters(in: .whitespaces)
        case .confluence:
            let parts = title.components(separatedBy: " - ")
            guard parts.last == "Confluence" else { return TidyTitles.title(for: url, title: title) ?? title }
            return parts.prefix(parts.count - (parts.count > 2 ? 2 : 1)).joined(separator: " - ")
        }
    }

    static func linearTicketID(_ url: URL) -> String? {
        guard url.host?.lowercased().hasSuffix("linear.app") == true else { return nil }
        let components = url.pathComponents
        return components.count == 5 && components[2] == "issue" ? components[3] : nil
    }

    enum RowMenu: Equatable { case copyURL, linearIssue(id: String), none }

    static func rowMenu(_ url: URL) -> RowMenu {
        guard var host = url.host else { return .copyURL }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        switch host {
        case "linear.app":
            let components = url.pathComponents
            return components.count == 5 && components[2] == "issue" ? .linearIssue(id: components[3]) : .copyURL
        case "notion.so":
            return url.lastPathComponent.range(of: "[a-fA-F0-9]{32}$", options: .regularExpression) == nil ? .copyURL : .none
        default:
            return .copyURL
        }
    }

    static func subtitle(url: URL, visitedAt: Date?, now: Date = Date()) -> String {
        let time = visitedAt.map { relativeTime($0, now: now) } ?? ""
        guard let id = linearTicketID(url) else { return time }
        return time.isEmpty ? id : id + " • " + time
    }

    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        if abs(now.timeIntervalSince(date)) < 60 { return "Just now" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func pageIdentity(_ url: URL) -> String? {
        if let id = linearTicketID(url) { return "linear:" + id }
        guard let host = url.host?.lowercased(), host == "notion.so" || host.hasSuffix(".notion.so") || host.hasSuffix(".notion.site"),
              let last = url.pathComponents.last else { return nil }
        let hex = last.suffix(32)
        return hex.count == 32 && hex.allSatisfy(\.isHexDigit) ? "notion:" + hex.lowercased() : nil
    }

    static func deduplicated<Row>(_ rows: [Row], title: (Row) -> String, url: (Row) -> URL) -> [Row] {
        var titles = Set<String>(), identities = Set<String>()
        return rows.filter { row in
            guard titles.insert(title(row)).inserted else { return false }
            guard let identity = pageIdentity(url(row)) else { return true }
            return identities.insert(identity).inserted
        }
    }
}
