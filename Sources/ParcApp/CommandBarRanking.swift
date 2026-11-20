import Foundation

enum CommandBarRanking {
    enum Archetype: Int, Comparable {
        case tab, document, typeTravel, archived, chromium, history, topDomain
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    struct Candidate {
        let archetype: Archetype
        let key: String
        var texts: [String] = []
        var chromiumRank = 0
        var urlKey: String? = nil
        var bump: Double = 0
        var samePage: String? = nil
        var titleScore: Double? = nil
        var contentScore: Double? = nil
    }
    static let limit = 15
    static let noteContentScore = 0.55
    static let caps: [Archetype: Int] = [.tab: 5, .document: 3, .typeTravel: 5, .archived: 3, .chromium: 8, .history: 3, .topDomain: 1]
    static let titleAndHostSites: Set<String> = ["figma.com", "maps.google.com", "notion.so", "app.notion.com", "zoom.us",
        "opentable.com", "zillow.com", "github.com", "app.mode.com", "console.cloud.google.com"]

    static func pageKey(_ url: URL, title: String) -> String {
        let host = (url.host ?? "").lowercased()
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if titleAndHostSites.contains(bare), !title.isEmpty { return "title:\(title.lowercased())@\(bare)" }
        return CommandBarRowDiff.pageKey(url)
    }

    struct Query {
        let text: String
        let words: [String]
        let wordsAreAlphanumeric: Bool
        let asciiText: [UInt8]?
        let asciiWords: [[UInt8]]
        init(_ query: String) {
            text = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            words = text.split(whereSeparator: \.isWhitespace).map(String.init)
            wordsAreAlphanumeric = words.allSatisfy { $0.allSatisfy { $0.isLetter || $0.isNumber } }
            asciiText = text.utf8.allSatisfy { $0 < 0x80 } ? Array(text.utf8) : nil
            asciiWords = asciiText == nil ? [] : words.map { Array($0.utf8) }
        }
    }
    static func match(_ query: String, _ texts: [String]) -> Double { match(Query(query), texts) }
    static func match(_ query: Query, _ texts: [String]) -> Double {
        let q = query.text
        guard !q.isEmpty else { return 0 }
        var best = 0.0
        for raw in texts {
            if let quality = asciiMatch(query, raw) {
                if quality == 1 { return 1 }
                best = max(best, quality); continue
            }
            let text = raw.lowercased()
            if text == q { return 1 }
            if text.hasPrefix(q) { best = max(best, 0.9); continue }
            guard best < 0.7, query.words.allSatisfy({ text.contains($0) }) else { continue }
            if query.wordsAreAlphanumeric, query.words.allSatisfy({ startsWord($0, in: text) }) { best = 0.7 }
            else { best = max(best, 0.4) }
        }
        return best
    }
    private static func asciiMatch(_ query: Query, _ raw: String) -> Double? {
        guard let q = query.asciiText else { return nil }
        var raw = raw
        return raw.withUTF8 { text -> Double? in
            guard text.allSatisfy({ $0 < 0x80 && $0 != 0x0D }) else { return nil }
            func lower(_ byte: UInt8) -> UInt8 { byte >= 0x41 && byte <= 0x5A ? byte | 0x20 : byte }
            func isWord(_ byte: UInt8) -> Bool {
                (byte >= 0x30 && byte <= 0x39) || (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A)
            }
            func matches(_ word: [UInt8], at offset: Int) -> Bool {
                for index in word.indices where lower(text[offset + index]) != word[index] { return false }
                return true
            }
            if text.count >= q.count, matches(q, at: 0) { return text.count == q.count ? 1 : 0.9 }
            var startsWords = query.wordsAreAlphanumeric
            for word in query.asciiWords {
                guard word.count <= text.count else { return 0 }
                var found = false, atStart = false
                for offset in 0...(text.count - word.count) where matches(word, at: offset) {
                    found = true
                    if offset == 0 || !isWord(text[offset - 1]) { atStart = true; break }
                }
                guard found else { return 0 }
                if !atStart { startsWords = false }
            }
            return startsWords ? 0.7 : 0.4
        }
    }
    private static func startsWord(_ word: String, in text: String) -> Bool {
        var previousIsWord = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let isWord = character.isLetter || character.isNumber
            if isWord && !previousIsWord && text[index...].hasPrefix(word) { return true }
            previousIsWord = isWord
            index = text.index(after: index)
        }
        return false
    }

    static func rank(_ candidates: [Candidate], query: String, leadingPage: String? = nil) -> [Int] {
        var kept: [String: Int] = [:]
        var lifts: [String: Double] = [:]
        var absorbed: [Int: Double] = [:]
        var pageKeys: [Int: Set<String>] = [:]
        func absorb(_ loser: Int, into winner: Int) {
            let own = candidates[loser].archetype == .chromium ? nativeScore(candidates[loser]) : 0
            let value = max(absorbed[winner] ?? 0, absorbed[loser] ?? 0, own, lifts[candidates[loser].key] ?? 0,
                            candidates[loser].contentScore ?? 0)
            if value > 0 { absorbed[winner] = value }
            pageKeys[winner, default: []].formUnion(pageKeys[loser] ?? [])
        }
        let pages = Set(candidates.filter { $0.archetype != .topDomain }.compactMap(\.urlKey))
        for (index, candidate) in candidates.enumerated() {
            if let lift = candidate.titleScore { lifts[candidate.key] = max(lifts[candidate.key] ?? 0, lift) }
            if candidate.archetype == .topDomain, pages.contains(candidate.key) { continue }
            if let page = candidate.samePage { pageKeys[index] = [page] }
            if let other = kept[candidate.key] {
                if candidates[other].archetype <= candidate.archetype { absorb(index, into: other); continue }
                absorb(other, into: index)
            }
            kept[candidate.key] = index
        }
        var samePages: [String: Int] = [:], merged: [Int: Int] = [:]
        func live(_ index: Int) -> Int { merged[index].map(live) ?? index }
        for index in Set(kept.values).sorted() where candidates[index].archetype != .topDomain && (leadingPage == nil || candidates[index].urlKey != leadingPage) {
            for page in (pageKeys[index] ?? []).sorted() {
                let mine = live(index)
                guard let other = samePages[page].map(live), other != mine else { samePages[page] = mine; continue }
                guard candidates[mine].archetype != .tab || candidates[other].archetype != .tab else { continue }
                let (winner, loser) = candidates[other].archetype <= candidates[mine].archetype ? (other, mine) : (mine, other)
                merged[loser] = winner; absorb(loser, into: winner); samePages[page] = winner
            }
        }
        kept = kept.mapValues(live)
        let defaultIndex = candidates.first(where: { $0.archetype == .chromium && $0.chromiumRank == 0 })
            .flatMap { kept[$0.key] }
        let siteIndex = leadingPage.flatMap { page in
            kept.values.filter { candidates[$0].urlKey == page }
                .min { (candidates[$0].archetype, $0) < (candidates[$1].archetype, $1) }
        }
        let prepared = Query(query)
        var scored: [(index: Int, score: Double, quality: Double)] = []
        for index in Set(kept.values) {
            let candidate = candidates[index]
            let quality = candidate.archetype == .chromium || index == defaultIndex ? 1 : match(prepared, candidate.texts)
            guard quality > 0 || lifts[candidate.key] != nil || absorbed[index] != nil || candidate.contentScore != nil else { continue }
            var score: Double
            switch candidate.archetype {
            case .chromium: score = nativeScore(candidate)
            case .tab: score = 0.95 * quality
            case .typeTravel: score = 0.85 * quality + candidate.bump
            case .document: score = 0.8 * quality
            case .topDomain: score = 0.78 * quality
            case .archived, .history: score = 0
            }
            score = max(score, lifts[candidate.key] ?? 0, absorbed[index] ?? 0, candidate.contentScore ?? 0)
            scored.append((index, score, quality))
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let a = candidates[lhs.index].archetype, b = candidates[rhs.index].archetype
            return a != b ? a < b : lhs.index < rhs.index
        }
        var order: [Int] = []
        var counts: [Archetype: Int] = [:]
        func take(_ index: Int) {
            let archetype = candidates[index].archetype
            guard order.count < limit, !order.contains(index),
                  counts[archetype, default: 0] < caps[archetype, default: limit] else { return }
            counts[archetype, default: 0] += 1; order.append(index)
        }
        if let lead = scored.first(where: { candidates[$0.index].archetype == .typeTravel && $0.quality >= 0.9 }) {
            take(lead.index)
        }
        if let siteIndex { take(siteIndex) }
        if let defaultIndex { take(defaultIndex) }
        for entry in scored { take(entry.index) }
        return order
    }

    private static func nativeScore(_ candidate: Candidate) -> Double { 0.8 - 0.03 * Double(candidate.chromiumRank) }

    struct Site: Equatable {
        let host: String
        let root: URL
        init?(_ url: URL) {
            guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  var host = parts.host?.lowercased(), var encoded = parts.percentEncodedHost?.lowercased(),
                  !host.isEmpty else { return nil }
            if host.hasPrefix("www.") { host.removeFirst(4) }
            if encoded.hasPrefix("www.") { encoded.removeFirst(4) }
            var root = URLComponents()
            root.scheme = scheme; root.percentEncodedHost = encoded; root.port = parts.port; root.path = "/"
            guard let rootURL = root.url else { return nil }
            self.host = parts.port.map { "\(host):\($0)" } ?? host
            self.root = rootURL
        }
    }
    static func domainCompletion(typed: String, host: String) -> String? {
        let lowered = typed.lowercased()
        guard !lowered.isEmpty, lowered.count == typed.count, !lowered.contains(where: \.isWhitespace) else { return nil }
        let form = lowered.count > 4 && lowered.hasPrefix("www.") ? "www." + host : host
        guard form.hasPrefix(lowered) else { return nil }
        return typed + form.dropFirst(lowered.count)
    }
    static func siteLead(typed: String, defaultURL: URL?) -> (host: String, page: String)? {
        guard let defaultURL, let site = Site(defaultURL), domainCompletion(typed: typed, host: site.host) != nil else { return nil }
        let page = CommandBarRowDiff.pageKey(site.root)
        return CommandBarRowDiff.pageKey(defaultURL) == page ? nil : (site.host, page)
    }

    struct Domain: Equatable {
        let host: String
        let url: URL
        let title: String
        let visits: Int
    }
    static func topDomains(_ visits: [(url: String, title: String)], minimumVisits: Int = 2) -> [Domain] {
        var counts: [String: (count: Int, root: URL, title: String)] = [:]
        for visit in visits {
            guard let url = URL(string: visit.url), let site = Site(url) else { continue }
            var entry = counts[site.host] ?? (0, site.root, "")
            entry.count += 1
            entry.root = site.root
            if (url.path.isEmpty || url.path == "/"), !visit.title.isEmpty { entry.title = visit.title }
            counts[site.host] = entry
        }
        return counts.compactMap { host, entry in
            entry.count >= minimumVisits ? Domain(host: host, url: entry.root, title: entry.title, visits: entry.count) : nil
        }.sorted { $0.visits != $1.visits ? $0.visits > $1.visits : $0.host < $1.host }
    }
}

struct CommandBarDocument: Equatable {
    enum Kind: Equatable { case note, easel }
    let kind: Kind
    let id: UUID
    let title: String
    var url: URL? = nil
    var icon: String? = nil
    var key: String { url.map(Self.noteKey) ?? (kind == .note ? "note:" : "easel:") + id.uuidString.lowercased() }
    static func noteKey(_ url: URL) -> String { "note:" + url.standardizedFileURL.path }
}
