import Foundation

/// Empty-query command-bar history scan cache.
///
/// Open-bar presentation skip (`CommandBarOpenResultsSkip`) still fingerprints
/// membership before Result rebuild. This helper avoids remapping/sorting the
/// full visit list when the query, `historyRevision`, excluded current URL, and
/// tab-URL identity are unchanged. Closed-bar snapshot gating stays in
/// `CommandBarReconcileInputs`.
enum CommandBarHistoryScanSkip {
    /// Cache key for the empty-query top-N history slice. Typed queries do not
    /// contribute local history rows today; a changed query still misses.
    struct Key: Equatable {
        var query: String
        var historyRevision: UInt64
        var excludedURL: String
        var tabIdentityFingerprint: String
    }

    /// Visit identity used to rebuild Result rows without rescanning history.
    struct Visit: Equatable {
        var url: String
        var title: String
    }

    /// True no-op: identical key reuses the last empty-query history slice.
    /// Typing, historyRevision, excluded-URL, or tab-URL membership changes
    /// must not reuse.
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

    /// Tab URLs only — empty-query history dedupes against open tab URLs.
    static func tabIdentityFingerprint(urls: [String]) -> String {
        urls.joined(separator: "\u{1f}")
    }

    /// Cheap open-bar history membership token: revision plus the current-URL
    /// exclusion used by `commandBarHistory`. Avoids mapping every visit into
    /// the presentation fingerprint on idle refresh ticks.
    static func historyMembershipToken(revision: UInt64, excludedURL: String?) -> String {
        "rev:\(revision)\u{1f}ex:\(excludedURL ?? "-")"
    }

    /// Empty-query history candidates, newest-first, skipping tab URL collisions
    /// and non-http(s) schemes. CommandBar applies the combined empty-query
    /// tab+history row budget (`max(0, 8 - results.count)`) when appending a
    /// prefix of this list so total rows stay at most eight.
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
