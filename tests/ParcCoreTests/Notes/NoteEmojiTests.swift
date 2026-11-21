import Foundation
import Testing
@testable import ParcCore

@MainActor final class NoteEmojiTests {
    let url = Bundle.module.url(forResource: "emoji", withExtension: "json", subdirectory: "Fixtures")!
    let suite = "Parc.Notes.EmojiTests." + UUID().uuidString
    let defaults: UserDefaults
    let catalog: NoteEmojiCatalog

    init() {
        defaults = UserDefaults(suiteName: suite)!
        catalog = NoteEmojiCatalog(url: url, defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
    }

    func loading(_ catalog: NoteEmojiCatalog) {
        #expect(catalog.isLoaded, "the bundled data loads")
        #expect(catalog.all.count > 1800, "every fully-qualified emoji is there, got \(catalog.all.count)")
        #expect(catalog.unicodeVersion == "18.0", "the data names its Unicode version")
        #expect(catalog.all.first?.character == "😀", "Unicode order starts with the grinning face")
        #expect(catalog.all.enumerated().allSatisfy { $0.offset == $0.element.order }, "order matches position")
        #expect(Set(catalog.all.map(\.character)).count == catalog.all.count, "no emoji appears twice")
        #expect(!catalog.all.contains { $0.character.unicodeScalars.contains { NoteEmojiSkinTone.modifiers.contains($0.value) } }, "toned variants fold into their base")
        #expect(!catalog.all.contains { $0.character == "🏻" }, "skin-tone components are not emoji of their own")
        let grinning = catalog.entry(for: "😀")
        #expect(grinning?.name == "grinning face" && grinning?.displayName == "Grinning face", "names come from Unicode")
        #expect(grinning?.keywords.contains("happy") == true, "keywords come from CLDR")
        #expect(catalog.entry(for: "❤")?.character == "❤️", "unqualified forms find the fully-qualified entry")
        #expect(catalog.entry(for: "👍🏽")?.character == "👍", "a toned variant finds its base")
        #expect(catalog.entry(for: "nope") == nil, "text that isn't an emoji isn't found")
    }

    func categories(_ catalog: NoteEmojiCatalog) {
        let sections = catalog.sections()
        #expect(sections.map(\.category) == NoteEmojiCategory.browsable, "every browsable category has emoji, in bar order")
        #expect(sections.first?.emoji.first?.character == "😀", "Smileys & People opens with the grinning face")
        #expect(catalog.entry(for: "👋")?.category == .people, "people and body join smileys")
        #expect(catalog.entry(for: "🐶")?.category == .nature, "dogs are nature")
        #expect(catalog.entry(for: "🍕")?.category == .food, "pizza is food")
        #expect(catalog.entry(for: "⚽")?.category == .activities, "soccer is an activity")
        #expect(catalog.entry(for: "🚗")?.category == .travel, "cars travel")
        #expect(catalog.entry(for: "💡")?.category == .objects, "a light bulb is an object")
        #expect(catalog.entry(for: "♻️")?.category == .symbols, "recycling is a symbol")
        #expect(catalog.entry(for: "🇨🇦")?.category == .flags, "Canada is a flag")
        #expect(NoteEmojiCategory.people.displayName == "Smileys & People", "categories have short display names")
        #expect(NoteEmojiCategory.allCases.first == .recents && !NoteEmojiCategory.browsable.contains(.recents), "Recents lead the bar")
        let flags = catalog.emoji(in: .flags)
        #expect(flags.count > 250 && flags.allSatisfy { $0.category == .flags }, "a category lists only its emoji")
        let total = sections.reduce(0) { $0 + $1.emoji.count }
        #expect(total == catalog.all.count, "sections cover every emoji once")
    }

    func search(_ catalog: NoteEmojiCatalog) {
        #expect(catalog.search("").isEmpty && catalog.search("   ").isEmpty, "an empty query finds nothing")
        #expect(catalog.search("smile").first?.character == "😄", "an exact shortcode wins")
        #expect(catalog.search("thumbs up").first?.character == "👍", "an exact name wins")
        #expect(catalog.search("Thumbs Up").first?.character == "👍", "search ignores case")
        #expect(catalog.search(":tada:").first?.character == "🎉", "colons around a shortcode are fine")
        #expect(catalog.search("pinata").first?.character == "🪅", "search ignores accents")
        let heart = catalog.search("heart")
        #expect(heart.first?.character == "❤️", "heart finds the red heart first")
        #expect(heart.count > 20, "heart finds lots of hearts")
        let car = catalog.search("car").map(\.character)
        let police = car.firstIndex(of: "🚓"), carousel = car.firstIndex(of: "🎠")
        #expect(police != nil && carousel != nil && police! < carousel!, "a whole word in the name beats a longer prefix")
        let gri = catalog.search("gri").map(\.character)
        let grinning = gri.firstIndex(of: "😀"), fearful = gri.firstIndex(of: "😨")
        #expect(grinning == 0, "a name prefix comes first")
        if let fearful { #expect(fearful > grinning!, "keyword-only matches trail name prefixes") }
        let prefix = catalog.search("cat").map(\.character)
        let catFace = prefix.firstIndex(of: "🐱"), grinningCat = prefix.firstIndex(of: "😺")
        #expect(catFace != nil && grinningCat != nil && catFace! < grinningCat!, "prefixes rank above inner words")
        #expect(catalog.search("happy").contains("😀".emojiIn(catalog)), "keywords match")
        #expect(catalog.search("tears joy").first?.character == "😂", "every word counts in any order")
        #expect(catalog.search("ca").contains { $0.character == "🇨🇦" }, "flags match their region code")
        #expect(catalog.search("😀").map(\.character) == ["😀"], "searching for an emoji finds it")
        #expect(catalog.search("zzzqqq").isEmpty, "nonsense finds nothing")
        #expect(catalog.search("face", limit: 5).count == 5, "limit caps the results")
        #expect(catalog.search("sweat_smile").first?.character == "😅", "underscored shortcodes match")
        #expect(catalog.search("+1").first?.character == "👍", "symbol shortcodes match")
    }

    func shortcodes(_ catalog: NoteEmojiCatalog) {
        #expect(catalog.emoji(forShortcode: "smile")?.character == "😄", "gemoji aliases resolve")
        #expect(catalog.emoji(forShortcode: ":tada:")?.character == "🎉", "colons are trimmed")
        #expect(catalog.emoji(forShortcode: "+1")?.character == "👍", "+1 is a thumbs up")
        #expect(catalog.emoji(forShortcode: "TADA")?.character == "🎉", "shortcodes ignore case")
        #expect(catalog.emoji(forShortcode: "melting_face")?.character == "🫠", "newer emoji answer to their name")
        #expect(catalog.emoji(forShortcode: "flag_canada")?.character == "🇨🇦", "names become shortcodes")
        #expect(catalog.emoji(forShortcode: "not_a_real_one") == nil, "unknown shortcodes are nil")
        #expect(catalog.emoji(forShortcode: "::") == nil, "bare colons are nil")
        #expect(catalog.entry(for: "😄")?.shortcode == "smile", "an emoji's shortcode is its first alias")
        #expect(catalog.entry(for: "🫠")?.shortcode == "melting_face", "otherwise it's derived from the name")
    }

    func skinTones(_ catalog: NoteEmojiCatalog) {
        let wave = catalog.entry(for: "👋")!
        #expect(wave.supportsSkinTones, "waving hands take skin tones")
        #expect(wave.character(with: .none) == "👋", "no tone keeps the base")
        #expect(wave.character(with: .medium) == "👋🏽", "a tone applies its modifier")
        #expect(wave.character(with: .dark) == "👋🏿", "dark is the last modifier")
        #expect(wave.tone(of: "👋🏼") == .mediumLight && wave.tone(of: "👋") == NoteEmojiSkinTone.none, "variants know their tone")
        let golfer = catalog.entry(for: "🏌️‍♂️")!
        #expect(golfer.character(with: .light) == "🏌🏻‍♂️", "a tone replaces the variation selector")
        let pair = catalog.entry(for: "🧑‍🤝‍🧑")!
        #expect(pair.character(with: .mediumDark) == "🧑🏾‍🤝‍🧑🏾", "both people take the same tone")
        #expect(catalog.entry(for: "🤝")?.character(with: .light) == "🤝🏻", "handshakes take one tone")
        let dog = catalog.entry(for: "🐶")!
        #expect(!dog.supportsSkinTones && dog.character(with: .dark) == "🐶", "dogs ignore skin tones")
        #expect(catalog.applying(.dark, to: "👍🏻") == "👍🏿", "re-toning swaps the modifier")
        #expect(catalog.applying(.none, to: "👍🏻") == "👍", "no tone strips it")
        #expect(catalog.applying(.dark, to: "x") == "x", "non-emoji pass through")
        #expect(catalog.skinTone == .none, "the default tone is none")
        catalog.skinTone = .medium
        #expect(catalog.skinTone == .medium, "the chosen tone sticks")
        #expect(catalog.character(for: wave) == "👋🏽", "the catalog applies the chosen tone")
        #expect(catalog.character(for: dog) == "🐶", "the chosen tone skips emoji without tones")
        catalog.skinTone = .none
        #expect(NoteEmojiSkinTone.light.modifier?.value == 0x1F3FB && NoteEmojiSkinTone.none.modifier == nil, "modifiers map in order")
        let toned = catalog.all.filter(\.supportsSkinTones)
        #expect(toned.count > 300, "hundreds of emoji take tones")
        #expect(toned.allSatisfy { emoji in NoteEmojiSkinTone.allCases.dropFirst().allSatisfy { catalog.entry(for: emoji.character(with: $0)) == emoji } }, "every variant maps back to its base")
    }

    func recents(_ catalog: NoteEmojiCatalog, defaults: UserDefaults) {
        #expect(catalog.recents.isEmpty, "recents start empty")
        catalog.recordUse("😀")
        catalog.recordUse("🎉")
        catalog.recordUse("👋🏽")
        #expect(catalog.recents == ["👋🏽", "🎉", "😀"], "recents put the latest first")
        catalog.recordUse("😀")
        #expect(catalog.recents == ["😀", "👋🏽", "🎉"], "using one again moves it up")
        catalog.recordUse("👋🏿")
        #expect(catalog.recents == ["👋🏿", "😀", "🎉"], "a new tone replaces the old one")
        catalog.recordUse("not emoji")
        #expect(catalog.recents.count == 3, "non-emoji never land in recents")
        #expect(catalog.emoji(in: .recents).map(\.character) == ["👋", "😀", "🎉"], "recents resolve to entries")
        #expect(defaults.stringArray(forKey: NoteEmojiCatalog.recentsKey) == ["👋🏿", "😀", "🎉"], "recents persist under a Parc.Notes key")
        #expect(NoteEmojiCatalog.recentsKey.hasPrefix("Parc.Notes.") && NoteEmojiCatalog.skinToneKey.hasPrefix("Parc.Notes."), "keys are namespaced")
        let reloaded = NoteEmojiCatalog(url: url, defaults: defaults)
        #expect(reloaded.recents == ["👋🏿", "😀", "🎉"], "a fresh catalog reads stored recents")
        for emoji in catalog.all.prefix(NoteEmojiCatalog.recentsLimit + 10) { catalog.recordUse(emoji.character) }
        #expect(catalog.recents.count == NoteEmojiCatalog.recentsLimit, "recents are capped")
        #expect(catalog.recents.first == catalog.all[NoteEmojiCatalog.recentsLimit + 9].character, "the cap drops the oldest")
        catalog.removeRecent(catalog.recents[0])
        #expect(catalog.recents.count == NoteEmojiCatalog.recentsLimit - 1, "one recent can go")
        defaults.set(["😀", "junk", "😀", "🎉"], forKey: NoteEmojiCatalog.recentsKey)
        let tidy = NoteEmojiCatalog(url: url, defaults: defaults)
        #expect(tidy.recents == ["😀", "🎉"], "stored junk and repeats are dropped")
        catalog.clearRecents()
        #expect(catalog.recents.isEmpty && defaults.object(forKey: NoteEmojiCatalog.recentsKey) == nil, "clearing empties recents")
    }

    func randomPicks(_ catalog: NoteEmojiCatalog) throws {
        var generator = SeededGenerator(seed: 7)
        var picks = Set<String>()
        for _ in 0..<50 {
            let pick = try #require(catalog.random(using: &generator), "random finds something")
            #expect(NoteEmojiCatalog.randomCategories.contains(pick.category), "random sticks to expressive categories")
            picks.insert(pick.character)
        }
        #expect(picks.count > 30, "random varies")
        #expect(catalog.random() != nil, "system random works")
    }

    func availability(url: URL, defaults: UserDefaults) {
        let catalog = NoteEmojiCatalog(url: url, defaults: defaults)
        catalog.availability = { $0.version < 15 }
        #expect(catalog.available.allSatisfy { $0.version < 15 } && catalog.available.count < catalog.all.count, "availability filters emoji")
        #expect(!catalog.search("shaking face").contains { $0.character == "🫨" }, "unavailable emoji stay out of search")
        #expect(catalog.emoji(forShortcode: "shaking_face") == nil, "unavailable emoji stay out of shortcodes")
        #expect(catalog.entry(for: "🫨") != nil, "entries still resolve for display names")
        #expect(!catalog.sections().contains { $0.emoji.contains { $0.version >= 15 } }, "sections skip unavailable emoji")
        catalog.availability = nil
        #expect(catalog.available.count == catalog.all.count, "clearing availability restores everything")
    }


    @Test func aMissingFileIsAnEmptyCatalog() {
        let catalog = NoteEmojiCatalog(url: URL(fileURLWithPath: "/nonexistent/emoji.json"))
        #expect(!catalog.isLoaded && catalog.all.isEmpty && catalog.search("smile").isEmpty && catalog.random() == nil, "a missing file is an empty catalog, not a crash")
        let broken = NoteEmojiCatalog(data: Data("{".utf8))
        #expect(!broken.isLoaded && broken.sections().isEmpty, "broken data is an empty catalog")
    }

    @Test func loading() {
        loading(catalog)
    }

    @Test func categories() {
        categories(catalog)
    }

    @Test func search() {
        search(catalog)
    }

    @Test func shortcodes() {
        shortcodes(catalog)
    }

    @Test func skinTones() {
        skinTones(catalog)
    }

    @Test func recents() {
        recents(catalog, defaults: defaults)
    }

    @Test func randomPicks() throws {
        try randomPicks(catalog)
    }

    @Test func availability() {
        availability(url: url, defaults: defaults)
    }

    @Test func missingFile2() {
        aMissingFileIsAnEmptyCatalog()
    }

    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
    }
}

private extension String {
    @MainActor
    func emojiIn(_ catalog: NoteEmojiCatalog) -> NoteEmoji {
        catalog.entry(for: self)!
    }
}
