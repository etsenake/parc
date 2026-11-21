import Foundation
import Testing
@testable import ParcCore

@MainActor
struct OnboardingFavoritesTests {
    let gmail = OnboardingDraft.favoriteChoices[1]
    let figma = OnboardingDraft.favoriteChoices[7]
    let youtube = OnboardingDraft.favoriteChoices[4]

    func freshSelection(_ fixture: PresentationOnboardingFixture) throws -> OnboardingDraft {
        try fixture.loadDraft()
    }

    @Test func newSelectionsEnterAtTheFrontRatherThanCatalogueOrClickOrder() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var selection = try freshSelection(fixture)
        selection.toggleFavorite(gmail)
        selection.toggleFavorite(figma)
        #expect(selection.selectedFavorites.map(\.url) == [figma.url, gmail.url, youtube.url, "https://calendar.google.com"])
    }

    @Test func togglingASelectedAppDeselectsIt() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var selection = try freshSelection(fixture)
        selection.toggleFavorite(gmail)
        selection.toggleFavorite(figma)
        selection.toggleFavorite(gmail)
        #expect(!selection.isFavoriteSelected(gmail))
        #expect(selection.selectedFavorites.map(\.url) == [figma.url, youtube.url, "https://calendar.google.com"])
    }

    @Test func reselectingAnAppMovesItToTheFront() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var selection = try freshSelection(fixture)
        selection.toggleFavorite(gmail)
        selection.toggleFavorite(figma)
        selection.toggleFavorite(gmail)
        selection.toggleFavorite(gmail)
        #expect(selection.selectedFavorites.first?.url == gmail.url)
    }

    @Test func deselectingAMigratedAppRemovesEveryOldAlias() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var selection = try freshSelection(fixture)
        selection.favoriteURLs.insert("https://www.youtube.com")
        selection.toggleFavorite(youtube)
        #expect(!selection.favoriteURLs.contains(youtube.url))
        #expect(!selection.favoriteURLs.contains("https://www.youtube.com"))
    }

    func messySelection(_ fixture: PresentationOnboardingFixture) throws -> OnboardingDraft {
        var selection = try freshSelection(fixture)
        selection.toggleFavorite(gmail)
        selection.toggleFavorite(figma)
        selection.toggleFavorite(gmail)
        selection.toggleFavorite(gmail)
        selection.favoriteURLs.insert("https://www.youtube.com")
        selection.toggleFavorite(youtube)
        selection.toggleFavorite(youtube)
        selection.favoriteURLs.insert("https://github.com")
        selection.favoriteURLs.insert("javascript:alert(1)")
        selection.favoriteOrder?.append(contentsOf: [gmail.url, "javascript:alert(1)"])
        return selection
    }

    @Test func anUnknownCatalogueChoiceCannotMutateTheDraft() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var selection = try messySelection(fixture)
        let prior = selection
        selection.toggleFavorite(.init(id: gmail.id, title: "Forged", url: "https://example.com"))
        #expect(selection == prior)
    }

    @Test func pendingOrderedChoicesResumeWithoutCommittingTabs() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let selection = try messySelection(fixture)
        try selection.save(directory: fixture.root)
        #expect(try fixture.loadDraft() == selection)
    }

    @Test func oldExplicitGitHubChoicesSurviveWhileUnknownURLsAndDuplicateOrderEntriesDoNotCommit() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let selection = try messySelection(fixture)
        try selection.save(directory: fixture.root)
        let resumed = try fixture.loadDraft()
        #expect(resumed.selectedFavorites.map(\.url) == [youtube.url, gmail.url, figma.url, "https://calendar.google.com", "https://github.com"])
    }

    @Test func theRealSessionCommitsTheOrderedFavoritesAndTheirOrderSurvivesRestart() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let selectionRoot = fixture.subdirectory("ordered-favorites")
        let store = try BrowserStore(directory: selectionRoot)
        var selection = try OnboardingDraft.load(directory: selectionRoot, space: store.activeSpace)
        selection.toggleFavorite(gmail)
        selection.toggleFavorite(figma)
        selection.toggleFavorite(gmail)
        selection.toggleFavorite(gmail)
        selection.favoriteURLs.insert("https://www.youtube.com")
        selection.toggleFavorite(youtube)
        selection.toggleFavorite(youtube)
        selection.favoriteURLs.insert("https://github.com")
        selection.favoriteURLs.insert("javascript:alert(1)")
        selection.favoriteOrder?.append(contentsOf: [gmail.url, "javascript:alert(1)"])
        try selection.save(directory: selectionRoot)
        let resumed = try OnboardingDraft.load(directory: selectionRoot, space: store.activeSpace)
        let expectedURLs = [youtube.url, gmail.url, figma.url, "https://calendar.google.com", "https://github.com"]
        try store.completeOnboarding(resumed)
        #expect(store.favorites.map(\.savedURL) == expectedURLs)
        let reopened = try BrowserStore(directory: selectionRoot)
        #expect(reopened.favorites.map(\.savedURL) == expectedURLs)
    }

    @Test func legacyAliasesNormalizeAndDeduplicateWithoutAlteringArbitraryImportedURLs() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let aliasRoot = fixture.subdirectory("existing-alias")
        let store = try BrowserStore(directory: aliasRoot)
        var draft = try OnboardingDraft.load(directory: aliasRoot, space: store.activeSpace)
        draft.favoriteURLs = ["https://www.youtube.com", youtube.url, "https://www.notion.so"]
        draft.favoriteOrder = [youtube.url, "https://www.youtube.com", "https://www.notion.so"]
        #expect(draft.selectedFavorites.map(\.url) == [youtube.url, "https://notion.so"])
        try store.completeOnboarding(draft)
        #expect(store.favorites.map(\.savedURL) == [youtube.url, "https://notion.so"])
    }
}
