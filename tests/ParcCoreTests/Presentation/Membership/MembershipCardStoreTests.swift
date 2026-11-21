import Foundation
import Testing
@testable import ParcCore

struct MembershipCardStoreTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    private var sample: MembershipCardState {
        MembershipCardState(name: "Ada Lovelace", createdAt: date, palette: 2, shape: 1,
                            title: "ARCHITECT", backgroundBlobInfo: Array(1...14) + [1])
    }

    private struct Seed: RandomNumberGenerator {
        var value: UInt64 = 2026

        mutating func next() -> UInt64 {
            value = (value &* 6_364_136_223_846_793_005) &+ 1
            return value
        }
    }

    @MainActor private func store(in directory: PresentationScratch, name: String = "Ada Lovelace") -> (store: MembershipCardStore, url: URL) {
        let url = directory.url.appendingPathComponent("card.json")
        return (MembershipCardStore(url: url, initialName: name, now: { date }), url)
    }

    @Test @MainActor func aNewCardStartsValidWithTheInitialNameAndCreationDate() throws {
        let directory = try PresentationScratch("parc-card")
        defer { directory.remove() }
        let initial = try #require(store(in: directory).store.state)
        #expect(initial.name == "Ada Lovelace")
        #expect(initial.createdAt == date)
        #expect(initial.isValid)
    }

    @Test(arguments: [("Josh", 3), ("Ada Lovelace", 1), ("🪐", 1)])
    func theShapeFollowsTheName(example: (String, Int)) {
        #expect(MembershipCardState.shapeForName(example.0) == example.1)
    }

    @Test @MainActor func openingACardRetainsItsNameDateAndDesign() throws {
        let directory = try PresentationScratch("parc-card")
        defer { directory.remove() }
        let (store, url) = store(in: directory)
        let reopened = MembershipCardStore(url: url, initialName: "Different", now: { date.addingTimeInterval(1) })
        #expect(reopened.state == store.state)
    }

    @MainActor private func regenerateCard() throws -> (MembershipCardState, MembershipCardState) {
        let directory = try PresentationScratch("parc-card")
        defer { directory.remove() }
        let store = store(in: directory).store
        let previous = try #require(store.state)
        try store.regenerate()
        return (previous, try #require(store.state))
    }

    @Test @MainActor func randomizingKeepsTheCardIdentity() throws {
        let (previous, next) = try regenerateCard()
        #expect(next.name == previous.name && next.createdAt == previous.createdAt)
    }

    @Test func randomizingChangesTheArtwork() {
        var generator = Seed()
        let original = sample
        let next = original.regenerated(using: &generator)
        #expect(next.shape != original.shape)
        #expect(next.palette != original.palette)
        #expect(next.backgroundBlobInfo != original.backgroundBlobInfo)
        #expect(next.isValid)
    }

    @Test @MainActor func renamingTrimsTheNameAndKeepsTheRestOfTheDesign() throws {
        let directory = try PresentationScratch("parc-card")
        defer { directory.remove() }
        let store = store(in: directory).store
        let before = try #require(store.state)
        try store.rename("  Josh  ", expected: before)
        let renamed = try #require(store.state)
        #expect(renamed.name == "Josh" && renamed.shape == 3 && renamed.createdAt == date)
        #expect(renamed.title == before.title && renamed.palette == before.palette)
    }

    @Test @MainActor func renamingFromAStaleCardIsRefused() throws {
        let directory = try PresentationScratch("parc-card")
        defer { directory.remove() }
        let store = store(in: directory).store
        let before = try #require(store.state)
        try store.rename("Josh", expected: before)
        #expect(throws: (any Error).self) { try store.rename("Other", expected: before) }
    }

    @Test(arguments: ["", "  ", "One\nTwo", "One\u{2028}Two", "One\u{2029}Two", String(repeating: "a", count: 65)])
    @MainActor func anInvalidNameIsRefusedAndLeavesTheCardUntouched(invalid: String) throws {
        let directory = try PresentationScratch("parc-card")
        defer { directory.remove() }
        let store = store(in: directory).store
        let current = try #require(store.state)
        #expect(throws: (any Error).self) { try store.rename(invalid, expected: current) }
        #expect(store.state == current)
    }

    @Test(arguments: ["\u{2028}", "\u{2029}"])
    func savedTitlesAndNamesMustRemainOnOneLine(separator: String) {
        let initial = sample
        var invalid = initial
        invalid.title = "ONE" + separator + "TWO"
        #expect(!invalid.isValid)
        invalid = initial
        invalid.name = "One" + separator + "Two"
        #expect(!invalid.isValid)
    }

    @Test @MainActor func aFailedWriteLeavesTheFileAndTheStateAsTheyWere() throws {
        let directory = try PresentationScratch("parc-card")
        defer { directory.remove() }
        let (_, url) = store(in: directory)
        let protected = try Data(contentsOf: url)
        let failing = MembershipCardStore(url: url, initialName: "Unused", write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        let state = failing.state
        #expect(throws: (any Error).self) { try failing.regenerate() }
        #expect(try Data(contentsOf: url) == protected)
        #expect(failing.state == state)
    }

    @Test @MainActor func aRefusedExternalReplacementCannotPublishANewDesign() throws {
        let directory = try PresentationScratch("parc-card")
        defer { directory.remove() }
        let (store, url) = store(in: directory)
        let firstData = try Data(contentsOf: url)
        let initial = try #require(store.state)
        try store.rename("Josh", expected: initial)
        let renamed = try #require(store.state)
        try firstData.write(to: url, options: .atomic)
        #expect(throws: (any Error).self) { try store.regenerate() }
        #expect(store.state == renamed)
        store.reload()
        #expect(store.state == initial)
    }

    @Test @MainActor func aCardFromAFutureVersionIsNeverRewritten() throws {
        let directory = try PresentationScratch("parc-card")
        defer { directory.remove() }
        let (store, url) = store(in: directory)
        var future = try #require(store.state)
        future.version = 999
        let futureData = try JSONEncoder().encode(future)
        try futureData.write(to: url)
        let unknown = MembershipCardStore(url: url, initialName: "Ignored")
        #expect(unknown.state == nil && unknown.error != nil)
        #expect(throws: (any Error).self) { try unknown.regenerate() }
        #expect(try Data(contentsOf: url) == futureData)
    }

    @Test @MainActor func aCorruptCardIsPreservedAsItIs() throws {
        let directory = try PresentationScratch("parc-card")
        defer { directory.remove() }
        let (store, url) = store(in: directory)
        try Data("broken".utf8).write(to: url)
        store.reload()
        #expect(store.state == nil)
        #expect(try Data(contentsOf: url) == Data("broken".utf8))
    }

    @Test @MainActor func theSharedStoreIsOwnedOncePerDirectory() throws {
        let directory = try PresentationScratch("parc-card")
        defer { directory.remove() }
        let a = MembershipCardStore.shared(directory: directory.url, name: "Shared")
        let b = MembershipCardStore.shared(directory: directory.url, name: "Different")
        #expect(a === b)
    }

    @Test func everyFallbackPaletteHasANumber() {
        #expect(MembershipCardState.fallbackNumbers.count == 8)
    }
}
