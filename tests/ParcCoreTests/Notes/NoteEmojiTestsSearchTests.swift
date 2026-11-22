import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteEmojiTestsSearchTests {
    private let fixture = NoteEmojiTestsSupport.Fixture()
    private var catalog: NoteEmojiCatalog { fixture.catalog }

    @Test(arguments: ["", "   "])
    func aBlankQueryFindsNothing(query: String) {
        #expect(catalog.search(query).isEmpty)
    }

    struct SearchCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let query: String
        let first: String

        init(_ testDescription: String, _ query: String, _ first: String) {
            self.testDescription = testDescription
            self.query = query
            self.first = first
        }
    }

    @Test(arguments: [
        SearchCase("an exact shortcode wins", "smile", "😄"),
        SearchCase("an exact name wins", "thumbs up", "👍"),
        SearchCase("search ignores case", "Thumbs Up", "👍"),
        SearchCase("colons around a shortcode are fine", ":tada:", "🎉"),
        SearchCase("search ignores accents", "pinata", "🪅"),
        SearchCase("underscored shortcodes match", "sweat_smile", "😅"),
        SearchCase("symbol shortcodes match", "+1", "👍"),
    ])
    func emojiSearchRanksTheExpectedMatchFirst(example: SearchCase) {
        #expect(catalog.search(example.query).first?.character == example.first)
    }

    @Test
    func heartRanksTheRedHeartFirst() {
        let heart = catalog.search("heart")
        #expect(heart.first?.character == "❤️", "heart finds the red heart first")
    }

    @Test
    func heartSearchFindsMoreThanTwentyMatches() {
        let heart = catalog.search("heart")
        #expect(heart.count > 20, "heart finds lots of hearts")
    }

    @Test
    func aWholeWordBeatsALongerNamePrefix() {
        let car = catalog.search("car").map(\.character)
        let police = car.firstIndex(of: "🚓"), carousel = car.firstIndex(of: "🎠")
        #expect(police != nil && carousel != nil && police! < carousel!, "a whole word in the name beats a longer prefix")
    }

    @Test
    func aNamePrefixRanksAboveKeywordOnlyMatches() {
        let gri = catalog.search("gri").map(\.character)
        let grinning = gri.firstIndex(of: "😀"), fearful = gri.firstIndex(of: "😨")
        #expect(grinning == 0, "a name prefix comes first")
        if let fearful { #expect(fearful > grinning!, "keyword-only matches trail name prefixes") }
    }

    @Test
    func aPrefixRanksAboveAnInnerWord() {
        let prefix = catalog.search("cat").map(\.character)
        let catFace = prefix.firstIndex(of: "🐱"), grinningCat = prefix.firstIndex(of: "😺")
        #expect(catFace != nil && grinningCat != nil && catFace! < grinningCat!, "prefixes rank above inner words")
    }

    @Test
    func keywordsMatch() {
        #expect(catalog.search("happy").contains(catalog.entry(for: "😀")!), "keywords match")
    }

    @Test
    func allQueryWordsMatchInAnyOrder() {
        #expect(catalog.search("tears joy").first?.character == "😂", "every word counts in any order")
    }

    @Test
    func flagsMatchTheirRegionCode() {
        #expect(catalog.search("ca").contains { $0.character == "🇨🇦" }, "flags match their region code")
    }

    @Test
    func anEmojiSearchFindsThatEmoji() {
        #expect(catalog.search("😀").map(\.character) == ["😀"], "searching for an emoji finds it")
    }

    @Test
    func unmatchedSearchesReturnNothing() {
        #expect(catalog.search("zzzqqq").isEmpty, "nonsense finds nothing")
    }

    @Test
    func theLimitCapsSearchResults() {
        #expect(catalog.search("face", limit: 5).count == 5, "limit caps the results")
    }

    struct ShortcodeCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let input: String
        let expected: String?

        init(_ testDescription: String, _ input: String, _ expected: String?) {
            self.testDescription = testDescription
            self.input = input
            self.expected = expected
        }
    }

    @Test(arguments: [
        ShortcodeCase("gemoji aliases resolve", "smile", "😄"),
        ShortcodeCase("colons are trimmed", ":tada:", "🎉"),
        ShortcodeCase("+1 is a thumbs up", "+1", "👍"),
        ShortcodeCase("shortcodes ignore case", "TADA", "🎉"),
        ShortcodeCase("newer emoji answer to their name", "melting_face", "🫠"),
        ShortcodeCase("names become shortcodes", "flag_canada", "🇨🇦"),
        ShortcodeCase("unknown shortcodes are nil", "not_a_real_one", nil),
        ShortcodeCase("bare colons are nil", "::", nil),
    ])
    func shortcodesResolveToTheExpectedEmoji(example: ShortcodeCase) {
        #expect(catalog.emoji(forShortcode: example.input)?.character == example.expected)
    }

    @Test
    func theFirstAliasBecomesThePrimaryShortcode() {
        #expect(catalog.entry(for: "😄")?.shortcode == "smile", "an emoji's shortcode is its first alias")
    }

    @Test
    func theNameSuppliesTheShortcodeWhenNoAliasExists() {
        #expect(catalog.entry(for: "🫠")?.shortcode == "melting_face", "otherwise it's derived from the name")
    }
}
