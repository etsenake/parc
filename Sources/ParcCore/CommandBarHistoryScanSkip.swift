import Foundation

enum CommandBarHistoryScanSkip {
    struct Key: Equatable {
        var query: String
        var historyRevision: UInt64
        var excludedURL: String
        var tabIdentityFingerprint: String
    }

    struct Visit: Equatable {
        var url: String
        var title: String
    }

    static func shouldReuse(previous: Key?, next: Key) -> Bool {
        previous == next
    }

    static func key(
        query: String,
        historyRevision: UInt64,
        excludedURL: String?,
        tabURLs: [String]
    ) -> Key {
        Key(
            query: query,
            historyRevision: historyRevision,
            excludedURL: excludedURL ?? "-",
            tabIdentityFingerprint: tabIdentityFingerprint(urls: tabURLs)
        )
    }

    static func tabIdentityFingerprint(urls: [String]) -> String {
        urls.joined(separator: "\u{1f}")
    }

    static func historyMembershipToken(revision: UInt64, excludedURL: String?) -> String {
        "rev:\(revision)\u{1f}ex:\(excludedURL ?? "-")"
    }

    static func emptyQueryVisits(
        rankedURLsAndTitles: [(url: String, title: String)],
        tabURLs: Set<String>,
        limit: Int = 8
    ) -> [Visit] {
        var seen = tabURLs
        var out: [Visit] = []
        out.reserveCapacity(min(limit, rankedURLsAndTitles.count))
        for visit in rankedURLsAndTitles {
            guard out.count < limit else { break }
            guard seen.insert(visit.url).inserted else { continue }
            guard let url = URL(string: visit.url),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { continue }
            out.append(Visit(url: visit.url, title: visit.title))
        }
        return out
    }
}
