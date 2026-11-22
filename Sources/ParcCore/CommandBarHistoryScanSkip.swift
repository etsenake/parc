import Foundation

package enum CommandBarHistoryScanSkip {
    package struct Key: Equatable {
        package var query: String
        package var historyRevision: UInt64
        package var excludedURL: String
        var tabIdentityFingerprint: String

        package init(query: String, historyRevision: UInt64, excludedURL: String, tabIdentityFingerprint: String) {
            self.query = query
            self.historyRevision = historyRevision
            self.excludedURL = excludedURL
            self.tabIdentityFingerprint = tabIdentityFingerprint
        }
    }

    package struct Visit: Equatable {
        package var url: String
        package var title: String

        package init(url: String, title: String) {
            self.url = url
            self.title = title
        }
    }

    package static func shouldReuse(previous: Key?, next: Key) -> Bool {
        previous == next
    }

    package static func key(
        query: String,
        historyRevision: UInt64,
        excludedURL: String?,
        tabURLs: [String],
        tabTitles: [String] = []
    ) -> Key {
        Key(
            query: query,
            historyRevision: historyRevision,
            excludedURL: excludedURL ?? "-",
            tabIdentityFingerprint: tabIdentityFingerprint(urls: tabURLs + tabTitles)
        )
    }

    static func tabIdentityFingerprint(urls: [String]) -> String {
        urls.joined(separator: "\u{1f}")
    }

    package static func historyMembershipToken(revision: UInt64, excludedURL: String?) -> String {
        "rev:\(revision)\u{1f}ex:\(excludedURL ?? "-")"
    }

    package static func emptyQueryVisits(
        rankedURLsAndTitles: [(url: String, title: String)],
        tabURLs: Set<String>,
        tabPages: Set<String> = [],
        samePage: (_ title: String, _ url: String) -> String? = { _, _ in nil },
        limit: Int = 8
    ) -> [Visit] {
        var seen = tabURLs, seenPages = tabPages
        var out: [Visit] = []
        out.reserveCapacity(min(limit, rankedURLsAndTitles.count))
        for visit in rankedURLsAndTitles {
            guard out.count < limit else { break }
            guard seen.insert(visit.url).inserted else { continue }
            guard let url = URL(string: visit.url),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { continue }
            if let page = samePage(visit.title, visit.url), !seenPages.insert(page).inserted { continue }
            out.append(Visit(url: visit.url, title: visit.title))
        }
        return out
    }
}
