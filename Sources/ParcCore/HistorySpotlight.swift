import CryptoKit
import Foundation

package struct HistorySpotlightItem: Equatable {
    package var url: String
    package var title: String
    package var site: String
    package var lastVisit: Date
    package var visits: Int

    package init(url: String, title: String, site: String, lastVisit: Date, visits: Int) {
        self.url = url
        self.title = title
        self.site = site
        self.lastVisit = lastVisit
        self.visits = visits
    }
}

package enum HistorySpotlight {
    package static let format = Data("parc-history-1".utf8)

    package static func site(of address: String) -> String? {
        guard let parts = URLComponents(string: address),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") && host.count > 4 ? String(host.dropFirst(4)) : host
    }

    package static func items(from history: [BrowserHistoryEntry]) -> [String: HistorySpotlightItem] {
        var items: [String: HistorySpotlightItem] = [:]
        var titledAt: [String: Date] = [:]
        var rejected = Set<String>()
        for visit in history where !rejected.contains(visit.url) {
            if items[visit.url] == nil {
                guard let site = site(of: visit.url) else { rejected.insert(visit.url); continue }
                items[visit.url] = HistorySpotlightItem(url: visit.url, title: "", site: site,
                                                        lastVisit: visit.visitedAt, visits: 0)
            }
            items[visit.url]!.visits += 1
            if visit.visitedAt > items[visit.url]!.lastVisit { items[visit.url]!.lastVisit = visit.visitedAt }
            let title = visit.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, titledAt[visit.url].map({ visit.visitedAt >= $0 }) ?? true {
                items[visit.url]!.title = title
                titledAt[visit.url] = visit.visitedAt
            }
        }
        for (url, item) in items where item.title.isEmpty { items[url]!.title = item.site }
        return items
    }

    package static func changes(from indexed: [String: HistorySpotlightItem],
                        to current: [String: HistorySpotlightItem]) -> (upserts: [HistorySpotlightItem], removals: [String]) {
        let upserts = current.values.filter { indexed[$0.url] != $0 }.sorted { $0.url < $1.url }
        let removals = indexed.keys.filter { current[$0] == nil }.sorted()
        return (upserts, removals)
    }

    package static func clientState(for items: [String: HistorySpotlightItem]) -> Data {
        var hash = SHA256()
        for url in items.keys.sorted() {
            let item = items[url]!
            let line = [item.url, item.title, item.site, String(item.lastVisit.timeIntervalSince1970.bitPattern),
                        String(item.visits)].joined(separator: "\u{0}") + "\n"
            hash.update(data: Data(line.utf8))
        }
        return format + Data(hash.finalize())
    }
}
