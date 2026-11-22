import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteEmojiTestsCatalogTests {
    private let fixture = NoteEmojiTestsSupport.Fixture()
    private var catalog: NoteEmojiCatalog { fixture.catalog }

    @Test
    func missingDataLoadsAsAnEmptyCatalog() {
        let catalog = NoteEmojiCatalog(url: URL(fileURLWithPath: "/nonexistent/emoji.json"), defaults: fixture.defaults)
        #expect(!catalog.isLoaded && catalog.all.isEmpty && catalog.search("smile").isEmpty && catalog.random() == nil, "a missing file is an empty catalog, not a crash")
    }

    @Test
    func malformedDataLoadsAsAnEmptyCatalog() {
        let broken = NoteEmojiCatalog(data: Data("{".utf8), defaults: fixture.defaults)
        #expect(!broken.isLoaded && broken.sections().isEmpty, "broken data is an empty catalog")
    }

    @Test
    func theBundledCatalogLoadsItsUnicodeVersionAndEmoji() {
        #expect(catalog.isLoaded, "the bundled data loads")
        #expect(catalog.all.count > 1800, "every fully-qualified emoji is there, got \(catalog.all.count)")
        #expect(catalog.unicodeVersion == "18.0", "the data names its Unicode version")
    }

    @Test
    func theCatalogUsesUnicodeOrder() {
        #expect(catalog.all.first?.character == "😀", "Unicode order starts with the grinning face")
        #expect(catalog.all.enumerated().allSatisfy { $0.offset == $0.element.order }, "order matches position")
    }

    @Test
    func theCatalogContainsNoDuplicateEmoji() {
        #expect(Set(catalog.all.map(\.character)).count == catalog.all.count, "no emoji appears twice")
    }

    @Test
    func skinToneVariantsFoldIntoTheirBaseEmoji() {
        #expect(!catalog.all.contains { $0.character.unicodeScalars.contains { NoteEmojiSkinTone.modifiers.contains($0.value) } }, "toned variants fold into their base")
    }

    @Test
    func skinToneComponentsAreNotListedOnTheirOwn() {
        #expect(!catalog.all.contains { $0.character == "🏻" }, "skin-tone components are not emoji of their own")
    }

    @Test
    func emojiNamesComeFromUnicode() {
        let grinning = catalog.entry(for: "😀")
        #expect(grinning?.name == "grinning face" && grinning?.displayName == "Grinning face", "names come from Unicode")
    }

    @Test
    func emojiSearchKeywordsComeFromCLDR() {
        let grinning = catalog.entry(for: "😀")
        #expect(grinning?.keywords.contains("happy") == true, "keywords come from CLDR")
    }

    struct LookupCase: Sendable, CustomTestStringConvertible {
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
        LookupCase("unqualified forms find the fully-qualified entry", "❤", "❤️"),
        LookupCase("a toned variant finds its base", "👍🏽", "👍"),
        LookupCase("text that isn't an emoji isn't found", "nope", nil),
    ])
    func catalogEntriesResolveToQualifiedBaseEmoji(example: LookupCase) {
        #expect(catalog.entry(for: example.input)?.character == example.expected)
    }

    @Test
    func browsableSectionsCoverTheWholeCatalogInBarOrder() {
        let sections = catalog.sections()
        #expect(sections.map(\.category) == NoteEmojiCategory.browsable, "every browsable category has emoji, in bar order")
        #expect(sections.first?.emoji.first?.character == "😀", "Smileys & People opens with the grinning face")
        let total = sections.reduce(0) { $0 + $1.emoji.count }
        #expect(total == catalog.all.count, "sections cover every emoji once")
    }

    struct CategoryCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let input: String
        let expected: NoteEmojiCategory

        init(_ testDescription: String, _ input: String, _ expected: NoteEmojiCategory) {
            self.testDescription = testDescription
            self.input = input
            self.expected = expected
        }
    }

    @Test(arguments: [
        CategoryCase("people and body join smileys", "👋", .people),
        CategoryCase("dogs are nature", "🐶", .nature),
        CategoryCase("pizza is food", "🍕", .food),
        CategoryCase("soccer is an activity", "⚽", .activities),
        CategoryCase("cars travel", "🚗", .travel),
        CategoryCase("a light bulb is an object", "💡", .objects),
        CategoryCase("recycling is a symbol", "♻️", .symbols),
        CategoryCase("Canada is a flag", "🇨🇦", .flags),
    ])
    func emojiAppearInTheirExpectedCategory(example: CategoryCase) {
        #expect(catalog.entry(for: example.input)?.category == example.expected)
    }

    @Test
    func categoriesHaveShortDisplayNames() {
        #expect(NoteEmojiCategory.people.displayName == "Smileys & People", "categories have short display names")
    }

    @Test
    func recentsLeadTheBarOutsideTheBrowsableCategories() {
        #expect(NoteEmojiCategory.allCases.first == .recents && !NoteEmojiCategory.browsable.contains(.recents), "Recents lead the bar")
    }

    @Test
    func theFlagsCategoryListsOnlyFlags() {
        let flags = catalog.emoji(in: .flags)
        #expect(flags.count > 250 && flags.allSatisfy { $0.category == .flags }, "a category lists only its emoji")
    }
}
