import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteEmojiTestsRecentsTests {
    private let fixture = NoteEmojiTestsSupport.Fixture()
    private var catalog: NoteEmojiCatalog { fixture.catalog }

    private var defaults: UserDefaults { fixture.defaults }
    private var url: URL { fixture.url }

    @Test
    func recentsStartEmpty() {
        #expect(catalog.recents.isEmpty, "recents start empty")
    }

    @Test
    func recentEmojiAppearNewestFirst() {
        catalog.recordUse("😀")
        catalog.recordUse("🎉")
        catalog.recordUse("👋🏽")
        #expect(catalog.recents == ["👋🏽", "🎉", "😀"], "recents put the latest first")
    }

    @Test
    func usingAnEmojiAgainMovesItToTheFront() {
        catalog.recordUse("😀")
        catalog.recordUse("🎉")
        catalog.recordUse("👋🏽")
        catalog.recordUse("😀")
        #expect(catalog.recents == ["😀", "👋🏽", "🎉"], "using one again moves it up")
    }

    @Test
    func aNewToneReplacesThePreviousRecentTone() {
        catalog.recordUse("😀")
        catalog.recordUse("🎉")
        catalog.recordUse("👋🏽")
        catalog.recordUse("😀")
        catalog.recordUse("👋🏿")
        #expect(catalog.recents == ["👋🏿", "😀", "🎉"], "a new tone replaces the old one")
    }

    @Test
    func nonEmojiStayOutOfRecents() {
        catalog.recordUse("😀")
        catalog.recordUse("🎉")
        catalog.recordUse("👋🏽")
        catalog.recordUse("😀")
        catalog.recordUse("👋🏿")
        catalog.recordUse("not emoji")
        #expect(catalog.recents.count == 3, "non-emoji never land in recents")
    }

    @Test
    func recentsResolveToTheirBaseEntries() {
        catalog.recordUse("😀")
        catalog.recordUse("🎉")
        catalog.recordUse("👋🏽")
        catalog.recordUse("😀")
        catalog.recordUse("👋🏿")
        #expect(catalog.emoji(in: .recents).map(\.character) == ["👋", "😀", "🎉"], "recents resolve to entries")
    }

    @Test
    func recentsPersistAndReloadInOrder() {
        catalog.recordUse("😀")
        catalog.recordUse("🎉")
        catalog.recordUse("👋🏽")
        catalog.recordUse("😀")
        catalog.recordUse("👋🏿")
        #expect(defaults.stringArray(forKey: NoteEmojiCatalog.recentsKey) == ["👋🏿", "😀", "🎉"], "recents persist under a Parc.Notes key")
        let reloaded = NoteEmojiCatalog(url: url, defaults: defaults)
        #expect(reloaded.recents == ["👋🏿", "😀", "🎉"], "a fresh catalog reads stored recents")
    }

    @Test
    func recentsAndSkinToneDefaultsKeysShareANamespace() {
        #expect(NoteEmojiCatalog.recentsKey.hasPrefix("Parc.Notes.") && NoteEmojiCatalog.skinToneKey.hasPrefix("Parc.Notes."), "keys are namespaced")
    }

    @Test
    func theRecentsLimitDropsTheOldestEntries() {
        for emoji in catalog.all.prefix(NoteEmojiCatalog.recentsLimit + 10) { catalog.recordUse(emoji.character) }
        #expect(catalog.recents.count == NoteEmojiCatalog.recentsLimit, "recents are capped")
        #expect(catalog.recents.first == catalog.all[NoteEmojiCatalog.recentsLimit + 9].character, "the cap drops the oldest")
    }

    @Test
    func oneRecentEntryCanBeRemoved() {
        for emoji in catalog.all.prefix(NoteEmojiCatalog.recentsLimit + 10) { catalog.recordUse(emoji.character) }
        catalog.removeRecent(catalog.recents[0])
        #expect(catalog.recents.count == NoteEmojiCatalog.recentsLimit - 1, "one recent can go")
    }

    @Test
    func reloadingRecentsDropsInvalidAndDuplicateEntries() {
        defaults.set(["😀", "junk", "😀", "🎉"], forKey: NoteEmojiCatalog.recentsKey)
        let tidy = NoteEmojiCatalog(url: url, defaults: defaults)
        #expect(tidy.recents == ["😀", "🎉"], "stored junk and repeats are dropped")
    }

    @Test
    func clearingRecentsRemovesThemFromDefaults() {
        catalog.recordUse("😀")
        catalog.recordUse("🎉")
        catalog.recordUse("👋🏽")
        catalog.recordUse("😀")
        catalog.recordUse("👋🏿")
        catalog.clearRecents()
        #expect(catalog.recents.isEmpty && defaults.object(forKey: NoteEmojiCatalog.recentsKey) == nil, "clearing empties recents")
    }
}
