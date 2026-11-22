import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteEmojiTestsAvailabilityAndRandomTests {
    private let fixture = NoteEmojiTestsSupport.Fixture()
    private var catalog: NoteEmojiCatalog { fixture.catalog }

    @Test
    func availabilityFiltersTheVisibleCatalog() {
        catalog.availability = { $0.version < 15 }
        #expect(catalog.available.allSatisfy { $0.version < 15 } && catalog.available.count < catalog.all.count, "availability filters emoji")
    }

    @Test
    func searchSkipsUnavailableEmoji() {
        catalog.availability = { $0.version < 15 }
        #expect(!catalog.search("shaking face").contains { $0.character == "🫨" }, "unavailable emoji stay out of search")
    }

    @Test
    func shortcodeLookupSkipsUnavailableEmoji() {
        catalog.availability = { $0.version < 15 }
        #expect(catalog.emoji(forShortcode: "shaking_face") == nil, "unavailable emoji stay out of shortcodes")
    }

    @Test
    func unavailableEntriesStillResolveForDisplay() {
        catalog.availability = { $0.version < 15 }
        #expect(catalog.entry(for: "🫨") != nil, "entries still resolve for display names")
    }

    @Test
    func sectionsOmitUnavailableEmoji() {
        catalog.availability = { $0.version < 15 }
        #expect(!catalog.sections().contains { $0.emoji.contains { $0.version >= 15 } }, "sections skip unavailable emoji")
    }

    @Test
    func clearingAvailabilityRestoresTheWholeCatalog() {
        catalog.availability = { $0.version < 15 }
        catalog.availability = nil
        #expect(catalog.available.count == catalog.all.count, "clearing availability restores everything")
    }

    private struct SeededGenerator: RandomNumberGenerator {
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

    @Test
    func seededRandomPicksVaryWithinExpressiveCategories() throws {
        var generator = SeededGenerator(seed: 7)
        var picks = Set<String>()
        for _ in 0..<50 {
            let pick = try #require(catalog.random(using: &generator), "random finds something")
            #expect(NoteEmojiCatalog.randomCategories.contains(pick.category), "random sticks to expressive categories")
            picks.insert(pick.character)
        }
        #expect(picks.count > 30, "random varies")
    }

    @Test
    func theSystemRandomGeneratorPicksAnEmoji() {
        #expect(catalog.random() != nil, "system random works")
    }
}
