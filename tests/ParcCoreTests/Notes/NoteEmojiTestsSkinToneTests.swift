import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteEmojiTestsSkinToneTests {
    private let fixture = NoteEmojiTestsSupport.Fixture()
    private var catalog: NoteEmojiCatalog { fixture.catalog }

    @Test
    func aWavingHandSupportsSkinTones() {
        let wave = catalog.entry(for: "👋")!
        #expect(wave.supportsSkinTones, "waving hands take skin tones")
    }

    struct ToneCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let emoji: String
        let tone: NoteEmojiSkinTone
        let expected: String

        init(_ testDescription: String, _ emoji: String, _ tone: NoteEmojiSkinTone, _ expected: String) {
            self.testDescription = testDescription
            self.emoji = emoji
            self.tone = tone
            self.expected = expected
        }
    }

    @Test(arguments: [
        ToneCase("no tone keeps the base", "👋", .none, "👋"),
        ToneCase("a tone applies its modifier", "👋", .medium, "👋🏽"),
        ToneCase("dark is the last modifier", "👋", .dark, "👋🏿"),
        ToneCase("a tone replaces the variation selector", "🏌️‍♂️", .light, "🏌🏻‍♂️"),
        ToneCase("both people take the same tone", "🧑‍🤝‍🧑", .mediumDark, "🧑🏾‍🤝‍🧑🏾"),
        ToneCase("handshakes take one tone", "🤝", .light, "🤝🏻"),
    ])
    func tonedEmojiUseTheExpectedCharacterSequence(example: ToneCase) {
        #expect(catalog.entry(for: example.emoji)?.character(with: example.tone) == example.expected)
    }

    @Test
    func tonedAndUntonedCharactersReportTheirTone() {
        let wave = catalog.entry(for: "👋")!
        #expect(wave.tone(of: "👋🏼") == .mediumLight && wave.tone(of: "👋") == NoteEmojiSkinTone.none, "variants know their tone")
    }

    @Test
    func emojiWithoutSkinToneSupportIgnoreTheTone() {
        let dog = catalog.entry(for: "🐶")!
        #expect(!dog.supportsSkinTones && dog.character(with: .dark) == "🐶", "dogs ignore skin tones")
    }

    struct RetoneCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let emoji: String
        let tone: NoteEmojiSkinTone
        let expected: String

        init(_ testDescription: String, _ emoji: String, _ tone: NoteEmojiSkinTone, _ expected: String) {
            self.testDescription = testDescription
            self.emoji = emoji
            self.tone = tone
            self.expected = expected
        }
    }

    @Test(arguments: [
        RetoneCase("re-toning swaps the modifier", "👍🏻", .dark, "👍🏿"),
        RetoneCase("no tone strips it", "👍🏻", .none, "👍"),
        RetoneCase("non-emoji pass through", "x", .dark, "x"),
    ])
    func applyingAToneReplacesOrRemovesTheExistingTone(example: RetoneCase) {
        #expect(catalog.applying(example.tone, to: example.emoji) == example.expected)
    }

    @Test
    func theDefaultSkinToneIsNone() {
        #expect(catalog.skinTone == .none, "the default tone is none")
    }

    @Test
    func theSelectedSkinToneSticks() {
        catalog.skinTone = .medium
        #expect(catalog.skinTone == .medium, "the chosen tone sticks")
    }

    @Test
    func theCatalogAppliesItsChosenToneToSupportedEmoji() {
        let wave = catalog.entry(for: "👋")!
        catalog.skinTone = .medium
        #expect(catalog.character(for: wave) == "👋🏽", "the catalog applies the chosen tone")
    }

    @Test
    func theCatalogSkipsToningUnsupportedEmoji() {
        let dog = catalog.entry(for: "🐶")!
        catalog.skinTone = .medium
        #expect(catalog.character(for: dog) == "🐶", "the chosen tone skips emoji without tones")
    }

    @Test
    func skinToneModifiersUseUnicodeOrder() {
        #expect(NoteEmojiSkinTone.light.modifier?.value == 0x1F3FB && NoteEmojiSkinTone.none.modifier == nil, "modifiers map in order")
    }

    @Test
    func hundredsOfEmojiSupportSkinTones() {
        let toned = catalog.all.filter(\.supportsSkinTones)
        #expect(toned.count > 300, "hundreds of emoji take tones")
    }

    @Test
    func everyTonedVariantMapsBackToItsBase() {
        let toned = catalog.all.filter(\.supportsSkinTones)
        #expect(toned.allSatisfy { emoji in NoteEmojiSkinTone.allCases.dropFirst().allSatisfy { catalog.entry(for: emoji.character(with: $0)) == emoji } }, "every variant maps back to its base")
    }
}
