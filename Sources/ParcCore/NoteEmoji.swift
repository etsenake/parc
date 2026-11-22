import Foundation

package enum NoteEmojiSkinTone: Int, CaseIterable, Codable {
    case none, light, mediumLight, medium, mediumDark, dark

    static let modifiers: ClosedRange<UInt32> = 0x1F3FB...0x1F3FF

    package var modifier: Unicode.Scalar? {
        self == .none ? nil : Unicode.Scalar(Self.modifiers.lowerBound + UInt32(rawValue - 1))
    }

    package var displayName: String {
        switch self {
        case .none: return "Default"
        case .light: return "Light"
        case .mediumLight: return "Medium-Light"
        case .medium: return "Medium"
        case .mediumDark: return "Medium-Dark"
        case .dark: return "Dark"
        }
    }
}

package enum NoteEmojiCategory: String, CaseIterable {
    case recents, custom, people, nature, food, activities, travel, objects, symbols, flags

    static let browsable: [NoteEmojiCategory] = allCases.filter { $0 != .recents && $0 != .custom }

    package var displayName: String {
        switch self {
        case .recents: return "Recents"
        case .custom: return "Custom"
        case .people: return "Smileys & People"
        case .nature: return "Animals & Nature"
        case .food: return "Food & Drink"
        case .activities: return "Activities"
        case .travel: return "Travel & Places"
        case .objects: return "Objects"
        case .symbols: return "Symbols"
        case .flags: return "Flags"
        }
    }

    init(unicodeGroup: String) {
        switch unicodeGroup {
        case "Smileys & Emotion", "People & Body": self = .people
        case "Animals & Nature": self = .nature
        case "Food & Drink": self = .food
        case "Activities": self = .activities
        case "Travel & Places": self = .travel
        case "Objects": self = .objects
        case "Flags": self = .flags
        default: self = .symbols
        }
    }
}

package struct NoteEmoji: Hashable {
    package let character: String
    let name: String
    let keywords: [String]
    let shortcodes: [String]
    let category: NoteEmojiCategory
    package let version: Double
    let skinToneVariants: [String]
    let order: Int

    var supportsSkinTones: Bool { skinToneVariants.count == 5 }

    package var displayName: String { name.prefix(1).uppercased() + name.dropFirst() }

    package var shortcode: String { shortcodes.first ?? NoteEmojiCatalog.shortcode(fromName: name) }

    init(character: String, name: String, keywords: [String], shortcodes: [String], category: NoteEmojiCategory, version: Double, skinToneVariants: [String], order: Int) {
        self.character = character
        self.name = name
        self.keywords = keywords
        self.shortcodes = shortcodes
        self.category = category
        self.version = version
        self.skinToneVariants = skinToneVariants
        self.order = order
    }

    package func character(with tone: NoteEmojiSkinTone) -> String {
        guard tone != .none, supportsSkinTones else { return character }
        return skinToneVariants[tone.rawValue - 1]
    }

    package func tone(of variant: String) -> NoteEmojiSkinTone? {
        if variant == character { return NoteEmojiSkinTone.none }
        return skinToneVariants.firstIndex(of: variant).flatMap { NoteEmojiSkinTone(rawValue: $0 + 1) }
    }
}

@MainActor
package final class NoteEmojiCatalog {
    static let recentsKey = "Parc.Notes.Emoji.Recents"
    static let skinToneKey = "Parc.Notes.Emoji.SkinTone"
    static let recentsLimit = 36
    static let randomCategories: Set<NoteEmojiCategory> = [.people, .nature, .food, .activities, .travel, .objects]

    static var bundledURL: URL? {
        Bundle.main.url(forResource: "emoji", withExtension: "json", subdirectory: "NoteEmoji")
    }

    package static let shared = NoteEmojiCatalog(url: bundledURL)

    private let source: () -> Data?
    private let defaults: UserDefaults
    private lazy var index = Index(data: source())
    private var availableCache: [NoteEmoji]?
    private var recentsCache: [String]?

    package var availability: (@MainActor (NoteEmoji) -> Bool)? {
        didSet { availableCache = nil }
    }

    init(url: URL?, defaults: UserDefaults = .standard) {
        source = { url.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) } }
        self.defaults = defaults
    }

    init(data: Data, defaults: UserDefaults = .standard) {
        source = { data }
        self.defaults = defaults
    }

    var isLoaded: Bool { !index.entries.isEmpty }
    var unicodeVersion: String { index.unicodeVersion }
    var all: [NoteEmoji] { index.entries }

    var available: [NoteEmoji] {
        if let availableCache { return availableCache }
        let entries = index.entries
        let filtered = availability.map { check in entries.filter { check($0) } } ?? entries
        availableCache = filtered
        return filtered
    }

    func emoji(in category: NoteEmojiCategory) -> [NoteEmoji] {
        if category == .recents { return recents.compactMap { entry(for: $0) } }
        return available.filter { $0.category == category }
    }

    package func sections() -> [(category: NoteEmojiCategory, emoji: [NoteEmoji])] {
        var grouped: [NoteEmojiCategory: [NoteEmoji]] = [:]
        for emoji in available { grouped[emoji.category, default: []].append(emoji) }
        return NoteEmojiCategory.browsable.compactMap { category in
            grouped[category].map { (category, $0) }
        }
    }

    package func entry(for character: String) -> NoteEmoji? {
        let index = index
        if let position = index.byCharacter[character] ?? index.byCharacter[Self.unqualified(character)] {
            return index.entries[position]
        }
        return nil
    }

    package func emoji(forShortcode shortcode: String) -> NoteEmoji? {
        let code = Self.fold(shortcode).trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespaces))
        guard !code.isEmpty else { return nil }
        let index = index
        guard let position = index.byShortcode[code] ?? index.byNameCode[code] else { return nil }
        let found = index.entries[position]
        return isAvailable(found) ? found : nil
    }

    package func search(_ query: String, limit: Int = .max) -> [NoteEmoji] {
        let folded = Self.fold(query).trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespacesAndNewlines))
        guard !folded.isEmpty, limit > 0 else { return [] }
        let index = index
        let available = available
        if let exact = index.byCharacter[query.trimmingCharacters(in: .whitespaces)] {
            let found = index.entries[exact]
            if isAvailable(found) { return [found] }
        }
        let spaced = folded.replacingOccurrences(of: "_", with: " ")
        let tokens = Self.words(in: spaced)
        var ranked: [(rank: Int, order: Int, emoji: NoteEmoji)] = []
        for emoji in available {
            if let rank = index.keys[emoji.order].rank(spaced, tokens: tokens) {
                ranked.append((rank, emoji.order, emoji))
            }
        }
        ranked.sort { ($0.rank, $0.order) < ($1.rank, $1.order) }
        return ranked.prefix(limit).map(\.emoji)
    }

    package func random() -> NoteEmoji? {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    func random<Generator: RandomNumberGenerator>(using generator: inout Generator) -> NoteEmoji? {
        let pool = available.filter { Self.randomCategories.contains($0.category) }
        return (pool.isEmpty ? available : pool).randomElement(using: &generator)
    }

    package var skinTone: NoteEmojiSkinTone {
        get { NoteEmojiSkinTone(rawValue: defaults.integer(forKey: Self.skinToneKey)) ?? .none }
        set { defaults.set(newValue.rawValue, forKey: Self.skinToneKey) }
    }

    package func character(for emoji: NoteEmoji) -> String {
        emoji.character(with: skinTone)
    }

    func applying(_ tone: NoteEmojiSkinTone, to character: String) -> String {
        entry(for: character)?.character(with: tone) ?? character
    }

    package var recents: [String] {
        if let recentsCache { return recentsCache }
        let stored = defaults.stringArray(forKey: Self.recentsKey) ?? []
        var seen = Set<String>()
        let valid = stored.filter { item in
            guard let base = recentBase(item) else { return false }
            return seen.insert(base).inserted
        }
        let capped = Array(valid.prefix(Self.recentsLimit))
        recentsCache = capped
        return capped
    }

    package func recordUse(_ character: String) {
        guard let base = recentBase(character) else { return }
        var list = recents.filter { recentBase($0) != base }
        list.insert(character, at: 0)
        list = Array(list.prefix(Self.recentsLimit))
        recentsCache = list
        defaults.set(list, forKey: Self.recentsKey)
    }

    func removeRecent(_ character: String) {
        let base = recentBase(character) ?? character
        let list = recents.filter { (recentBase($0) ?? $0) != base }
        recentsCache = list
        defaults.set(list, forKey: Self.recentsKey)
    }

    func clearRecents() {
        recentsCache = []
        defaults.removeObject(forKey: Self.recentsKey)
    }

    private func recentBase(_ item: String) -> String? {
        if NoteCustomEmojiName.isReference(item) { return item }
        return entry(for: item)?.character
    }

    private func isAvailable(_ emoji: NoteEmoji) -> Bool {
        availability?(emoji) ?? true
    }

    nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    package nonisolated static func unqualified(_ character: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: character.unicodeScalars.filter { $0.value != 0xFE0F })
        return String(scalars)
    }

    nonisolated static func shortcode(fromName name: String) -> String {
        words(in: fold(name).replacingOccurrences(of: "'", with: "")).joined(separator: "_")
    }

    nonisolated static func words(in text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

private struct NoteEmojiFile: Decodable {
    struct Group: Decodable {
        let name: String
        let emoji: [Entry]

        init(name: String, emoji: [Entry]) {
            self.name = name
            self.emoji = emoji
        }
    }
    struct Entry: Decodable {
        let e: String
        let n: String
        let k: [String]?
        let c: [String]?
        let s: [String]?
        let v: Double

        init(e: String, n: String, k: [String]?, c: [String]?, s: [String]?, v: Double) {
            self.e = e
            self.n = n
            self.k = k
            self.c = c
            self.s = s
            self.v = v
        }
    }
    let unicode: String
    let groups: [Group]
}

private struct NoteEmojiSearchKey {
    let name: String
    let nameWords: [String]
    let keywords: [String]
    let keywordWords: [String]
    let shortcodes: [String]
    let shortcodeWords: [String]

    init(_ emoji: NoteEmoji) {
        name = NoteEmojiCatalog.fold(emoji.name)
        nameWords = NoteEmojiCatalog.words(in: name)
        keywords = emoji.keywords.map(NoteEmojiCatalog.fold)
        keywordWords = keywords.flatMap(NoteEmojiCatalog.words(in:))
        shortcodes = emoji.shortcodes.map { NoteEmojiCatalog.fold($0).replacingOccurrences(of: "_", with: " ") }
        shortcodeWords = shortcodes.flatMap(NoteEmojiCatalog.words(in:))
    }

    func rank(_ query: String, tokens: [String]) -> Int? {
        if name == query || shortcodes.contains(query) { return 0 }
        let single = tokens.count == 1 ? tokens[0] : nil
        if single.map({ nameWords.contains($0) }) ?? false { return 1 }
        if name.hasPrefix(query) { return 2 }
        if shortcodes.contains(where: { $0.hasPrefix(query) }) { return 3 }
        if keywords.contains(query) { return 4 }
        if keywords.contains(where: { $0.hasPrefix(query) }) { return 4 }
        if let single {
            if nameWords.contains(where: { $0.hasPrefix(single) }) { return 5 }
            if shortcodeWords.contains(where: { $0.hasPrefix(single) }) { return 6 }
            if keywordWords.contains(where: { $0.hasPrefix(single) }) { return 7 }
        }
        if name.contains(query) { return 8 }
        if shortcodes.contains(where: { $0.contains(query) }) { return 9 }
        if keywords.contains(where: { $0.contains(query) }) { return 10 }
        guard tokens.count > 1 else { return nil }
        let everyTokenMatches = tokens.allSatisfy { token in
            nameWords.contains { $0.hasPrefix(token) } || keywordWords.contains { $0.hasPrefix(token) }
                || shortcodeWords.contains { $0.hasPrefix(token) }
        }
        guard everyTokenMatches else { return nil }
        let allInName = tokens.allSatisfy { token in nameWords.contains { $0.hasPrefix(token) } }
        return allInName ? 11 : 12
    }
}

extension NoteEmojiCatalog {
    fileprivate struct Index {
        let unicodeVersion: String
        let entries: [NoteEmoji]
        let keys: [NoteEmojiSearchKey]
        let byCharacter: [String: Int]
        let byShortcode: [String: Int]
        let byNameCode: [String: Int]

        init(data: Data?) {
            guard let data, let file = try? JSONDecoder().decode(NoteEmojiFile.self, from: data) else {
                unicodeVersion = ""; entries = []; keys = []; byCharacter = [:]; byShortcode = [:]; byNameCode = [:]
                return
            }
            var entries: [NoteEmoji] = []
            var byCharacter: [String: Int] = [:]
            var byShortcode: [String: Int] = [:]
            var byNameCode: [String: Int] = [:]
            for group in file.groups {
                let category = NoteEmojiCategory(unicodeGroup: group.name)
                for item in group.emoji where byCharacter[item.e] == nil {
                    let position = entries.count
                    let variants = item.s?.count == 5 ? item.s! : []
                    let emoji = NoteEmoji(character: item.e, name: item.n, keywords: item.k ?? [], shortcodes: item.c ?? [],
                                          category: category, version: item.v, skinToneVariants: variants, order: position)
                    entries.append(emoji)
                    for form in [item.e] + variants {
                        byCharacter[form] = position
                        let bare = NoteEmojiCatalog.unqualified(form)
                        if byCharacter[bare] == nil { byCharacter[bare] = position }
                    }
                    for code in emoji.shortcodes where byShortcode[code] == nil { byShortcode[code] = position }
                    let nameCode = NoteEmojiCatalog.shortcode(fromName: item.n)
                    if byNameCode[nameCode] == nil { byNameCode[nameCode] = position }
                }
            }
            unicodeVersion = file.unicode
            self.entries = entries
            keys = entries.map(NoteEmojiSearchKey.init)
            self.byCharacter = byCharacter
            self.byShortcode = byShortcode
            self.byNameCode = byNameCode
        }
    }
}
