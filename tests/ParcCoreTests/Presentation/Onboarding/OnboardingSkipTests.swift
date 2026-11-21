import Foundation
import Testing
@testable import ParcCore

struct OnboardingSkipTests {
    var chosen: SpaceTheme {
        var theme = SpaceTheme.singleColor(ThemeColor(hex: "4C6688")!)
        theme.wheel = .analogous; theme.appearance = .dark; theme.noise = 0.5; theme.intensity = 0.3
        theme.texture = .denim
        return theme
    }

    @Test func skipOnTheThemeStepKeepsOnlyTheWheelAndLightDark() {
        var draft = PresentationOnboardingFixture.draft()
        draft.theme = chosen
        draft.skipTheme(replayBase: nil)
        #expect(draft.theme == SpaceTheme(wheel: .analogous, appearance: .dark))
    }

    @Test func aSkippedThemeIsTheNoColourDefault() {
        var draft = PresentationOnboardingFixture.draft()
        draft.theme = chosen
        draft.skipTheme(replayBase: nil)
        #expect(draft.theme.primaryColor == nil && draft.theme.colorCount == 0 && draft.theme.noise == 0)
        #expect(draft.theme.intensity == 0.8 && draft.theme.texture == .grain && draft.theme.isValid)
    }

    @Test func skipOnFavoritesSelectsNone() {
        var draft = PresentationOnboardingFixture.draft()
        #expect(!draft.selectedFavorites.isEmpty)
        draft.skipFavorites()
        #expect(draft.selectedFavorites.isEmpty)
        #expect(draft.favoriteOrder == [])
    }

    @Test @MainActor func aSkippedFavoritesStepResumesEmptyNotWithTheDefaults() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var draft = try fixture.loadDraft()
        draft.skipFavorites()
        try draft.save(directory: fixture.root)
        #expect(try fixture.loadDraft().selectedFavorites.isEmpty)
    }

    @Test @MainActor func firstLaunchAfterSkippingFavoritesAddsNoFavorites() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        var draft = try fixture.loadDraft()
        draft.skipFavorites()
        try draft.save(directory: fixture.root)
        try fixture.store.completeOnboarding(try fixture.loadDraft())
        #expect(!fixture.store.state.tabs.contains { $0.kind == .favorite })
    }

    @Test func replaySkipRestoresTheThemeTheReplayStartedFrom() {
        let base = SpaceTheme.singleColor(ThemeColor(hex: "a1b2c3")!)
        var replay = OnboardingDraft(spaceID: UUID(), spaceName: "Home", theme: chosen)
        replay.replayBaseTheme = base
        replay.skipTheme(replayBase: base)
        #expect(replay.theme == base)
    }

    @Test func replaySkipKeepsTheProfilesExistingFavoritesSelectedAndDropsNewPicks() {
        var replay = OnboardingDraft(spaceID: UUID(), spaceName: "Home", theme: chosen)
        let existing: Set<String> = ["https://notion.so"]
        replay.favoriteURLs = existing.union(["https://figma.com"])
        replay.skipFavorites(keeping: existing)
        #expect(replay.selectedFavorites.map(\.url) == ["https://notion.so"])
    }
}
