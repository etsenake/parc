import Foundation

enum CommandBarTitleText {
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func runs<S: StringProtocol>(of text: S) -> [[UInt8]] {
        var runs: [[UInt8]] = []
        var current: [UInt8] = []
        for scalar in text.unicodeScalars {
            let value = scalar.value
            let isWord = scalar.isASCII
                ? (0x30...0x39).contains(value) || (0x61...0x7A).contains(value) || (0x41...0x5A).contains(value)
                : scalar.properties.isAlphabetic || scalar.properties.numericType != nil
            if isWord {
                if scalar.isASCII { current.append(UInt8(value) | (value >= 0x41 && value <= 0x5A ? 0x20 : 0)) }
                else { UTF8.encode(scalar) { current.append($0) } }
            } else if !current.isEmpty {
                runs.append(current); current.removeAll(keepingCapacity: true)
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    static func hostLabels(_ host: String?) -> [String] {
        guard var labels = host?.lowercased().split(separator: ".").map(String.init), labels.count > 1 else { return [] }
        labels.removeLast()
        return labels.filter { $0 != "www" }
    }

    static func age(from date: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        func ago(_ count: Int, _ unit: String) -> String { "\(count) \(unit)\(count == 1 ? "" : "s") ago" }
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return ago(Int(seconds / 60), "minute")
        case ..<86_400: return ago(Int(seconds / 3_600), "hour")
        case ..<172_800: return "yesterday"
        case ..<1_209_600: return ago(Int(seconds / 86_400), "day")
        case ..<5_184_000: return ago(Int(seconds / 604_800), "week")
        default: return ago(Int(seconds / 2_592_000), "month")
        }
    }

    static func archivedCaption(archivedAt: Date, now: Date) -> CommandBarResultText.TabCaption {
        let age = age(from: archivedAt, to: now)
        return .init(text: "Archived · " + age, spoken: "Put Back, archived " + age)
    }
}

struct CommandBarTitleQuery {
    static let minimumLength = 3
    let words: [[[UInt8]]]

    init?(_ text: String) {
        var words: [[[UInt8]]] = []
        var length = 0
        for word in CommandBarTitleText.fold(text).split(whereSeparator: \.isWhitespace) {
            let runs = CommandBarTitleText.runs(of: word)
            guard !runs.isEmpty else { continue }
            length += runs.reduce(0) { $0 + $1.count }
            words.append(runs)
        }
        guard length >= Self.minimumLength else { return nil }
        self.words = words
    }
}

struct CommandBarTitleTokens {
    private let bytes: [UInt8]
    private let ends: [Int]
    private let initials: UInt64
    let titleCount: Int
    var count: Int { ends.count }

    init(titles: [String], host: String?) {
        var bytes: [UInt8] = [], ends: [Int] = [], seen = Set<String>()
        for title in titles where !title.isEmpty && seen.insert(title).inserted {
            for run in CommandBarTitleText.runs(of: CommandBarTitleText.fold(title)) {
                bytes += run; ends.append(bytes.count)
            }
        }
        titleCount = ends.count
        for label in CommandBarTitleText.hostLabels(host) {
            for run in CommandBarTitleText.runs(of: label) { bytes += run; ends.append(bytes.count) }
        }
        var initials: UInt64 = 0
        for index in ends.indices where (index == 0 ? 0 : ends[index - 1]) < ends[index] {
            initials |= 1 << UInt64(bytes[index == 0 ? 0 : ends[index - 1]] & 63)
        }
        self.bytes = bytes; self.ends = ends; self.initials = initials
    }

    func mayContain(_ run: [UInt8]) -> Bool {
        guard let first = run.first, !run.contains(where: { $0 >= 0x80 }) else { return true }
        return initials & (1 << UInt64(first & 63)) != 0
    }

    func match(_ word: [[UInt8]], at position: Int) -> Bool? {
        guard position + word.count <= ends.count else { return nil }
        var complete = false
        for (offset, run) in word.enumerated() {
            let index = position + offset
            let start = index == 0 ? 0 : ends[index - 1], length = ends[index] - start
            let last = offset == word.count - 1
            if last && word.count == 1 && run.contains(where: { $0 >= 0x80 }) {
                guard contains(run, from: start, length: length) else { return nil }
            } else {
                guard run.count <= length, last || run.count == length else { return nil }
                for (step, byte) in run.enumerated() where bytes[start + step] != byte { return nil }
            }
            if last { complete = run.count == length }
        }
        return complete
    }

    private func contains(_ run: [UInt8], from start: Int, length: Int) -> Bool {
        guard run.count <= length else { return false }
        outer: for offset in 0...(length - run.count) {
            for (step, byte) in run.enumerated() where bytes[start + offset + step] != byte { continue outer }
            return true
        }
        return false
    }
}

enum CommandBarTitleMatch {
    enum Kind {
        case tab, archived, page
        var lift: Double {
            switch self {
            case .tab: return 0.02
            case .archived: return 0.01
            case .page: return 0
            }
        }
    }
    struct Score: Equatable {
        let strong: Double?
        let weak: Double
        var order: Double { strong ?? weak }
    }
    static let strongLimit = 3

    static func wordsQuery(_ query: String, nativeRowsAnswer: Bool, defaultIsSearch: Bool?) -> CommandBarTitleQuery? {
        guard nativeRowsAnswer, defaultIsSearch == true else { return nil }
        return CommandBarTitleQuery(query)
    }

    static func quality(_ query: CommandBarTitleQuery, _ tokens: CommandBarTitleTokens) -> (value: Double, inTitle: Bool)? {
        guard tokens.count > 0 else { return nil }
        var cursor = -1, inOrder = true, complete = 0, leading = false, titleHits = 0
        for (wordIndex, word) in query.words.enumerated() {
            guard let first = word.first, tokens.mayContain(first) else { return nil }
            var earliest: (position: Int, complete: Bool)?
            var following: (position: Int, complete: Bool)?
            for position in 0..<tokens.count {
                guard let isComplete = tokens.match(word, at: position) else { continue }
                if earliest == nil { earliest = (position, isComplete) }
                if position > cursor { following = (position, isComplete); break }
            }
            guard let hit = following ?? earliest else { return nil }
            if following == nil { inOrder = false }
            if hit.complete { complete += 1 }
            if wordIndex == 0 && hit.position == 0 { leading = true }
            if hit.position < tokens.titleCount { titleHits += 1 }
            cursor = hit.position + word.count - 1
        }
        let words = Double(query.words.count)
        var value = 0.55
        if inOrder { value += 0.15 }
        if leading { value += 0.15 }
        value += 0.1 * Double(complete) / words
        value += 0.05 * min(1, words / Double(max(1, tokens.titleCount)))
        if titleHits == 0 { value -= 0.1 }
        return (min(1, value), titleHits > 0)
    }

    static func boost(lastUsed: Date?, visits: Int, now: Date) -> Double {
        var value = 0.0
        if let lastUsed { value += 0.02 * max(0, 1 - max(0, now.timeIntervalSince(lastUsed)) / 2_592_000) }
        if visits > 0 { value += 0.02 * min(1, log2(Double(visits) + 1) / 5) }
        return value
    }

    static func score(_ query: CommandBarTitleQuery, _ tokens: CommandBarTitleTokens, kind: Kind, lastUsed: Date?,
                      visits: @autoclosure () -> Int, now: Date) -> Score? {
        guard let quality = quality(query, tokens) else { return nil }
        let boost = boost(lastUsed: lastUsed, visits: visits(), now: now)
        return Score(strong: quality.inTitle ? 0.78 + 0.07 * quality.value + boost + kind.lift : nil,
                     weak: 0.45 + 0.05 * quality.value + boost)
    }

    static func resolve(_ entries: [(key: String, score: Score, keepsWeak: Bool)], limit: Int = strongLimit) -> [Double?] {
        var strongKeys = Set<String>()
        for index in entries.indices.filter({ entries[$0].score.strong != nil })
            .sorted(by: { entries[$0].score.order > entries[$1].score.order }) {
            if strongKeys.count < limit { strongKeys.insert(entries[index].key) }
        }
        return entries.map { entry in
            if let strong = entry.score.strong, strongKeys.contains(entry.key) { return strong }
            return entry.keepsWeak ? entry.score.weak : nil
        }
    }
}

final class CommandBarTitleIndex: Sendable {
    struct Stamp: Equatable {
        let profileID: UUID
        let state: UInt64
        let history: UInt64
        let removals: UInt64
    }
    struct Entry {
        let tabID: UUID?
        let title: String
        let pageTitle: String
        let url: String
        let key: String
        let urlKey: String?
        let tokens: CommandBarTitleTokens
        let date: Date
        let visits: Int
    }
    struct Hit {
        let entry: Entry
        let score: CommandBarTitleMatch.Score
    }
    static let archiveWindow = 1_000
    static let historyWindow = 1_000
    static let historyScanLimit = 5_000
    static let hitLimit = 10

    let profileID: UUID
    let historyRevision: UInt64
    let historyRemovals: UInt64
    let archived: [Entry]
    let pages: [Entry]
    private let archivedIDs: Set<UUID>
    private let pageURLs: Set<String>
    private let archiveFingerprint: Int
    private let visitsByKey: [String: Int]

    private init(profileID: UUID, historyRevision: UInt64, historyRemovals: UInt64, archived: [Entry], pages: [Entry],
                 archiveFingerprint: Int, visitsByKey: [String: Int]) {
        self.profileID = profileID; self.historyRevision = historyRevision; self.historyRemovals = historyRemovals
        self.archived = archived; self.pages = pages
        archivedIDs = Set(archived.compactMap(\.tabID))
        pageURLs = Set(pages.map(\.url))
        self.archiveFingerprint = archiveFingerprint; self.visitsByKey = visitsByKey
    }

    func withdrawsEntries(of old: CommandBarTitleIndex) -> Bool {
        old.profileID != profileID || !old.archivedIDs.isSubset(of: archivedIDs) || !old.pageURLs.isSubset(of: pageURLs)
    }

    static func tabKey(url: String, title: String, id: UUID) -> String {
        InternalPage(urlString: url).map {
            $0.noteURL.map(CommandBarDocument.noteKey) ?? "easel:" + ($0.easelID?.uuidString.lowercased() ?? "")
        } ?? URL(string: url).map { CommandBarRanking.pageKey($0, title: title) } ?? "tab:" + id.uuidString
    }

    func visits(forKey key: String) -> Int { visitsByKey[key] ?? 0 }

    static func build(profileID: UUID, historyRevision: UInt64, historyRemovals: UInt64 = 0, tabs: [BrowserTab],
                      history: [BrowserHistoryEntry], reusing previous: CommandBarTitleIndex?) -> CommandBarTitleIndex {
        var fingerprint = 0
        var archivedIndices: [Int] = []
        for index in tabs.indices where tabs[index].profileID == profileID {
            guard let archivedAt = tabs[index].archivedAt else { continue }
            let tab = tabs[index]
            archivedIndices.append(index)
            var hasher = Hasher()
            hasher.combine(tab.id); hasher.combine(archivedAt); hasher.combine(tab.url)
            hasher.combine(tab.title); hasher.combine(tab.customTitle)
            fingerprint &+= hasher.finalize()
        }
        let sameProfile = previous?.profileID == profileID
        let samePages = sameProfile && previous?.historyRevision == historyRevision && previous?.historyRemovals == historyRemovals
        let sameArchive = sameProfile && previous?.archiveFingerprint == fingerprint
        if let previous, samePages, sameArchive { return previous }
        let pagePart = samePages ? (pages: previous?.pages ?? [], visits: previous?.visitsByKey ?? [:])
            : pageEntries(from: history, profileID: profileID)
        let archived = sameArchive ? previous?.archived ?? [] : archivedEntries(tabs, indices: archivedIndices)
        return CommandBarTitleIndex(profileID: profileID, historyRevision: historyRevision, historyRemovals: historyRemovals,
                                    archived: archived,
                                    pages: pagePart.pages, archiveFingerprint: fingerprint, visitsByKey: pagePart.visits)
    }

    private static func archivedEntries(_ tabs: [BrowserTab], indices: [Int]) -> [Entry] {
        indices.sorted { tabs[$0].archivedAt! > tabs[$1].archivedAt! }.prefix(archiveWindow).map { index in
            let tab = tabs[index]
            let title = CommandBarResultText.tabTitle(customTitle: tab.customTitle, pageTitle: tab.title, url: tab.url)
            let url = URL(string: tab.url)
            return Entry(tabID: tab.id, title: title, pageTitle: tab.title, url: tab.url,
                         key: tabKey(url: tab.url, title: tab.title, id: tab.id),
                         urlKey: url.map(CommandBarRowDiff.pageKey),
                         tokens: CommandBarTitleTokens(titles: [title, tab.title], host: url?.host),
                         date: tab.archivedAt!, visits: 0)
        }
    }

    private static func pageEntries(from history: [BrowserHistoryEntry], profileID: UUID) -> (pages: [Entry], visits: [String: Int]) {
        var slots: [String: Int] = [:]
        var visited: [(url: String, title: String, date: Date, visits: Int)] = []
        for visit in BrowserHistoryOrder.newestFirst(history.filter { $0.profileID == profileID }).prefix(historyScanLimit) {
            if let slot = slots[visit.url] {
                visited[slot].visits += 1
                if visited[slot].title.isEmpty { visited[slot].title = visit.title }
            } else if visited.count < historyWindow {
                slots[visit.url] = visited.count
                visited.append((visit.url, visit.title, visit.visitedAt, 1))
            }
        }
        var pages: [Entry] = [], byKey: [String: Int] = [:]
        for page in visited {
            guard let url = URL(string: page.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            let key = CommandBarRanking.pageKey(url, title: page.title)
            if let slot = byKey[key] {
                let kept = pages[slot]
                pages[slot] = Entry(tabID: nil, title: kept.title, pageTitle: kept.pageTitle, url: kept.url, key: key, urlKey: kept.urlKey,
                                    tokens: kept.tokens, date: kept.date, visits: kept.visits + page.visits)
                continue
            }
            byKey[key] = pages.count
            pages.append(Entry(tabID: nil, title: CommandBarResultText.historyTitle(pageTitle: page.title, url: page.url),
                               pageTitle: page.title, url: page.url, key: key, urlKey: CommandBarRowDiff.pageKey(url),
                               tokens: CommandBarTitleTokens(titles: [page.title], host: url.host),
                               date: page.date, visits: page.visits))
        }
        return (pages, byKey.mapValues { pages[$0].visits })
    }

    func search(_ query: CommandBarTitleQuery, now: Date, includesArchive: Bool = true, hiddenPages: Set<String>? = [],
                excludingURLKey excluded: String? = nil) -> (archived: [Hit], pages: [Hit]) {
        var archivedHits: [Hit] = [], pageHits: [Hit] = []
        if includesArchive {
            for entry in archived {
                guard let score = CommandBarTitleMatch.score(query, entry.tokens, kind: .archived, lastUsed: entry.date,
                                                             visits: visits(forKey: entry.key), now: now) else { continue }
                Self.keep(Hit(entry: entry, score: score), in: &archivedHits)
            }
        }
        for entry in hiddenPages == nil ? [] : pages where excluded == nil || entry.urlKey != excluded {
            if hiddenPages?.contains(entry.url) == true { continue }
            guard let score = CommandBarTitleMatch.score(query, entry.tokens, kind: .page, lastUsed: entry.date,
                                                         visits: entry.visits, now: now) else { continue }
            Self.keep(Hit(entry: entry, score: score), in: &pageHits)
        }
        return (archivedHits, pageHits)
    }

    private static func keep(_ hit: Hit, in hits: inout [Hit]) {
        if hits.count == hitLimit {
            guard let last = hits.last, hit.score.order > last.score.order else { return }
            hits.removeLast()
        }
        let position = hits.firstIndex { $0.score.order < hit.score.order } ?? hits.endIndex
        hits.insert(hit, at: position)
    }
}

@MainActor final class CommandBarTitleIndexCache {
    typealias Source = () -> (tabs: [BrowserTab], history: [BrowserHistoryEntry])
    private static let queue = DispatchQueue(label: "org.parc.command-bar.title-index", qos: .userInitiated)
    private(set) var index: CommandBarTitleIndex?
    private var builtStamp: CommandBarTitleIndex.Stamp?
    private var waiting: (stamp: CommandBarTitleIndex.Stamp, source: Source)?
    private var building = false
    var onBuilt: ((CommandBarTitleIndex) -> Void)?

    func index(for stamp: CommandBarTitleIndex.Stamp) -> CommandBarTitleIndex? {
        builtStamp == stamp ? index : nil
    }

    func request(_ stamp: CommandBarTitleIndex.Stamp, source: @escaping Source) {
        guard builtStamp != stamp || building else { return }
        waiting = (stamp, source)
        if !building { start() }
    }

    private func start() {
        guard let next = waiting else { return }
        waiting = nil
        guard builtStamp != next.stamp else { return }
        building = true
        let input = next.source(), previous = index, stamp = next.stamp
        Self.queue.async { [weak self] in
            let built = CommandBarTitleIndex.build(profileID: stamp.profileID, historyRevision: stamp.history,
                                                   historyRemovals: stamp.removals, tabs: input.tabs,
                                                   history: input.history, reusing: previous)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.building = false
                self.index = built; self.builtStamp = stamp
                self.onBuilt?(built)
                self.start()
            }
        }
    }
}
