import Foundation
import Testing
@testable import ParcCore

struct OnboardingReplayTests {
    let gmail = OnboardingDraft.favoriteChoices[1]
    let youtube = OnboardingDraft.favoriteChoices[4]
    let replayTheme = SpaceTheme.singleColor(ThemeColor(hex: "a1b2c3")!)

    struct Scene {
        let fixture: PresentationOnboardingFixture
        let replayRoot: URL
        let store: BrowserStore
        let original: BrowserSpace
        let other: UUID
        let unnamed: UUID
        let before: BrowserState

        var root: URL { replayRoot }
    }

    @MainActor func scene() throws -> Scene {
        let fixture = try PresentationOnboardingFixture()
        let replayRoot = fixture.subdirectory("replay")
        let store = try BrowserStore(directory: replayRoot)
        var first = try OnboardingDraft.load(directory: replayRoot, space: store.activeSpace)
        first.bookmarks = [.init(title: "Docs", url: "https://example.com/docs")]
        try store.completeOnboarding(first)
        let original = store.activeSpace
        let other = store.createSpace(name: "Work")
        let unnamed = store.createSpace(name: "")
        store.selectSpace(other)
        return Scene(fixture: fixture, replayRoot: replayRoot, store: store, original: original, other: other,
                     unnamed: unnamed, before: store.state)
    }

    private func replayDraft(_ scene: Scene) -> OnboardingDraft {
        var replay = OnboardingDraft(spaceID: scene.original.id, spaceName: "Home", theme: replayTheme)
        replay.favoriteURLs = Set(scene.before.tabs.filter {
            $0.profileID == scene.original.profileID && $0.kind == .favorite && $0.archivedAt == nil
        }.map(\.savedURL))
        replay.toggleFavorite(gmail)
        replay.bookmarks = [.init(title: "Docs again", url: "https://example.com/docs"),
                            .init(title: "Guide", url: "https://example.com/guide")]
        return replay
    }

    @MainActor func theme(in store: BrowserStore, _ id: UUID) -> SpaceTheme? {
        store.state.spaces.first { $0.id == id }?.theme
    }

    @Test @MainActor func theFixtureSpaceUsesItsPlaceholderName() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        #expect(scene.before.spaces.first { $0.id == scene.unnamed }?.title == nil)
    }

    @Test @MainActor func replayStartsFromTheProfilesExistingFavorites() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        var replay = OnboardingDraft(spaceID: scene.original.id, spaceName: "Home", theme: replayTheme)
        replay.favoriteURLs = Set(scene.before.tabs.filter {
            $0.profileID == scene.original.profileID && $0.kind == .favorite && $0.archivedAt == nil
        }.map(\.savedURL))
        #expect(replay.isFavoriteSelected(youtube))
    }

    @Test @MainActor func finishAppliesTheReplaysNameAndTheme() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        try scene.store.applyOnboardingReplay(replayDraft(scene))
        let space = scene.store.state.spaces.first { $0.id == scene.original.id }
        #expect(space?.name == "Home")
        #expect(space?.theme == replayTheme)
    }

    @Test @MainActor func replayNeverRemovesOrReplacesExistingTabs() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        try scene.store.applyOnboardingReplay(replayDraft(scene))
        #expect(scene.before.tabs.allSatisfy(scene.store.state.tabs.contains))
    }

    @Test @MainActor func otherSpacesStayAsTheyWere() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        try scene.store.applyOnboardingReplay(replayDraft(scene))
        let applied = scene.store.state
        #expect(applied.spaces.map(\.id) == scene.before.spaces.map(\.id))
        #expect(applied.spaces.filter { $0.id != scene.original.id } == scene.before.spaces.filter { $0.id != scene.original.id })
    }

    @Test @MainActor func replayKeepsTheActiveSpaceSettingsCompletionMarkerAndEducationGate() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        try scene.store.applyOnboardingReplay(replayDraft(scene))
        let applied = scene.store.state
        #expect(applied.activeSpaceID == scene.other)
        #expect(applied.settings == scene.before.settings)
        #expect(applied.autoArchiveEducationEligible == scene.before.autoArchiveEducationEligible)
    }

    @Test @MainActor func onlyNewlyChosenFavoritesAreAddedAndExistingOnesAreNotDuplicated() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        try scene.store.applyOnboardingReplay(replayDraft(scene))
        let profile = scene.original.profileID
        let favorites = scene.store.state.tabs.filter { $0.profileID == profile && $0.kind == .favorite }
        let prior = scene.before.tabs.filter { $0.profileID == profile && $0.kind == .favorite }
        #expect(favorites.count == prior.count + 1)
        #expect(favorites.filter { $0.savedURL == gmail.url }.count == 1)
        #expect(favorites.filter { $0.savedURL == youtube.url }.count == 1)
    }

    @Test @MainActor func theBookmarkFileAddsNewPinnedTabsWithoutDuplicatingExistingOnes() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        try scene.store.applyOnboardingReplay(replayDraft(scene))
        let pinned = scene.store.state.tabs.filter { $0.spaceID == scene.original.id && $0.kind == .pinned }
        #expect(pinned.map(\.savedURL).sorted() == ["https://example.com/docs", "https://example.com/guide"])
    }

    @Test @MainActor func retryingFinishDoesNotDuplicateTheReplaysAdditions() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        let replay = replayDraft(scene)
        try scene.store.applyOnboardingReplay(replay)
        let applied = scene.store.state
        try scene.store.applyOnboardingReplay(replay)
        #expect(scene.store.state == applied)
    }

    @Test @MainActor func replayChoicesPersistInTheSession() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        try scene.store.applyOnboardingReplay(replayDraft(scene))
        let reopened = try BrowserStore(directory: scene.replayRoot)
        #expect(theme(in: reopened, scene.original.id) == replayTheme)
        #expect(reopened.state.tabs.filter { $0.kind == .favorite && $0.savedURL == gmail.url }.count == 1)
    }

    @Test @MainActor func keepingTheSuggestedNameDoesNotFreezeAPlaceholderTitle() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        var placeholder = OnboardingDraft(spaceID: scene.unnamed, spaceName: "  ", theme: replayTheme)
        placeholder.favoriteURLs = []
        try scene.store.applyOnboardingReplay(placeholder)
        placeholder.spaceName = scene.store.state.spaces.first { $0.id == scene.unnamed }!.name
        try scene.store.applyOnboardingReplay(placeholder)
        #expect(scene.store.state.spaces.first { $0.id == scene.unnamed }?.title == nil)
    }

    @Test @MainActor func thePreviewIsTheSpacesLiveTheme() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        let live = SpaceTheme.singleColor(ThemeColor(hex: "334455")!)
        let later = SpaceTheme.singleColor(ThemeColor(hex: "445566")!)
        #expect(scene.store.previewSpaceTheme(scene.original.id, theme: live))
        #expect(theme(in: scene.store, scene.original.id) == live)
        #expect(scene.store.previewSpaceTheme(scene.original.id, theme: later))
    }

    @Test @MainActor func aSessionWriteDuringThePreviewThenACrashKeepsTheSavedThemeAndTheUnrelatedChange() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        let base = theme(in: scene.store, scene.original.id)!
        let later = SpaceTheme.singleColor(ThemeColor(hex: "445566")!)
        _ = scene.store.previewSpaceTheme(scene.original.id, theme: later)
        scene.store.renameSpace(scene.other, name: "Work, renamed")
        try scene.store.save()
        let crashed = try BrowserStore(directory: scene.replayRoot)
        #expect(theme(in: crashed, scene.original.id) == base)
        #expect(crashed.state.spaces.first { $0.id == scene.other }?.name == "Work, renamed")
        #expect(scene.store.savedTheme(of: scene.store.state.spaces.first { $0.id == scene.original.id }!) == base)
    }

    @Test @MainActor func closingThePreviewEarlyShowsTheSavedThemeAgain() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        let base = theme(in: scene.store, scene.original.id)!
        _ = scene.store.previewSpaceTheme(scene.original.id, theme: SpaceTheme.singleColor(ThemeColor(hex: "445566")!))
        scene.store.endSpaceThemePreview(scene.original.id)
        #expect(theme(in: scene.store, scene.original.id) == base)
        try scene.store.save()
        let closed = try BrowserStore(directory: scene.replayRoot)
        #expect(theme(in: closed, scene.original.id) == base)
    }

    @Test @MainActor func finishSavesTheReplayThemeAndEndsThePreview() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        let live = SpaceTheme.singleColor(ThemeColor(hex: "334455")!)
        #expect(scene.store.previewSpaceTheme(scene.original.id, theme: live))
        var finishing = OnboardingDraft(spaceID: scene.original.id, spaceName: "Home", theme: live)
        finishing.favoriteURLs = []
        try scene.store.applyOnboardingReplay(finishing)
        scene.store.endSpaceThemePreview(scene.original.id)
        let finished = try BrowserStore(directory: scene.replayRoot)
        #expect(theme(in: scene.store, scene.original.id) == live)
        #expect(theme(in: finished, scene.original.id) == live)
    }

    @Test(arguments: [true, false])
    @MainActor func anEditorOpenedBeforeOrDuringThePreviewSavesItsTheme(openedDuringPreview: Bool) throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        let live = SpaceTheme.singleColor(ThemeColor(hex: "334455")!)
        let later = SpaceTheme.singleColor(ThemeColor(hex: "445566")!)
        let external = SpaceTheme.singleColor(ThemeColor(hex: "556677")!)
        _ = try scene.store.saveSpaceTheme(spaceID: scene.original.id, profileID: scene.original.profileID,
                                          previous: theme(in: scene.store, scene.original.id)!, theme: live)
        let before = openedDuringPreview ? later : live
        #expect(scene.store.previewSpaceTheme(scene.original.id, theme: later))
        let change = try scene.store.saveSpaceTheme(spaceID: scene.original.id, profileID: scene.original.profileID,
                                                    previous: before, theme: external)
        let edited = try BrowserStore(directory: scene.replayRoot)
        #expect(change != nil)
        #expect(theme(in: edited, scene.original.id) == external)
        scene.store.endSpaceThemePreview(scene.original.id)
        #expect(theme(in: scene.store, scene.original.id) == external)
    }

    @Test @MainActor func anEditorSavingThePreviewedValueItselfStillPersistsIt() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        let live = SpaceTheme.singleColor(ThemeColor(hex: "334455")!)
        let later = SpaceTheme.singleColor(ThemeColor(hex: "445566")!)
        _ = try scene.store.saveSpaceTheme(spaceID: scene.original.id, profileID: scene.original.profileID,
                                          previous: theme(in: scene.store, scene.original.id)!, theme: live)
        #expect(scene.store.previewSpaceTheme(scene.original.id, theme: later))
        _ = try scene.store.saveSpaceTheme(spaceID: scene.original.id, profileID: scene.original.profileID,
                                          previous: live, theme: later)
        scene.store.endSpaceThemePreview(scene.original.id)
        let sameValue = try BrowserStore(directory: scene.replayRoot)
        #expect(theme(in: sameValue, scene.original.id) == later)
        #expect(theme(in: scene.store, scene.original.id) == later)
    }

    @MainActor func editedElsewhere(_ scene: Scene) throws -> (draft: OnboardingDraft, later: SpaceTheme, external: SpaceTheme, live: SpaceTheme) {
        let live = SpaceTheme.singleColor(ThemeColor(hex: "334455")!)
        let later = SpaceTheme.singleColor(ThemeColor(hex: "445566")!)
        let external = SpaceTheme.singleColor(ThemeColor(hex: "556677")!)
        _ = try scene.store.saveSpaceTheme(spaceID: scene.original.id, profileID: scene.original.profileID,
                                          previous: theme(in: scene.store, scene.original.id)!, theme: later)
        var unchanged = OnboardingDraft(spaceID: scene.original.id, spaceName: "Home", theme: later)
        unchanged.favoriteURLs = []
        unchanged.replayBaseName = "Home"; unchanged.replayBaseTheme = later
        scene.store.renameSpace(scene.original.id, name: "Renamed elsewhere")
        _ = try scene.store.saveSpaceTheme(spaceID: scene.original.id, profileID: scene.original.profileID,
                                          previous: later, theme: external)
        _ = scene.store.previewSpaceTheme(scene.original.id, theme: later)
        return (unchanged, later, external, live)
    }

    @Test @MainActor func anUnchangedReplayNameAndThemeKeepEditsMadeElsewhereDuringReplay() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        let edited = try editedElsewhere(scene)
        try scene.store.applyOnboardingReplay(edited.draft)
        let kept = try BrowserStore(directory: scene.replayRoot)
        #expect(scene.store.state.spaces.first { $0.id == scene.original.id }?.name == "Renamed elsewhere")
        #expect(theme(in: scene.store, scene.original.id) == edited.external)
        #expect(theme(in: kept, scene.original.id) == edited.external)
    }

    @Test @MainActor func aChangedReplayNameAndThemeApply() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        var edited = try editedElsewhere(scene).draft
        let live = SpaceTheme.singleColor(ThemeColor(hex: "334455")!)
        edited.spaceName = "Replay name"; edited.theme = live
        try scene.store.applyOnboardingReplay(edited)
        #expect(scene.store.state.spaces.first { $0.id == scene.original.id }?.name == "Replay name")
        #expect(theme(in: scene.store, scene.original.id) == live)
    }

    @MainActor private func restarting(_ scene: Scene) -> OnboardingDraft {
        var restarting = replayDraft(scene)
        restarting.replayBaseName = scene.original.name
        restarting.replayBaseTheme = theme(in: scene.store, scene.original.id)
        restarting.replayAppearance = "dark"
        restarting.stage = .theme
        return restarting
    }

    @Test @MainActor func theReplayRestartDraftNeverBecomesAFirstLaunchDraft() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        try restarting(scene).save(directory: scene.replayRoot, fileName: OnboardingDraft.replayRestartFileName)
        #expect(!FileManager.default.fileExists(atPath: scene.replayRoot.appendingPathComponent("onboarding.json").path))
    }

    @Test @MainActor func aSavedReplayResumesOnlyForItsOwnSpace() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        try restarting(scene).save(directory: scene.replayRoot, fileName: OnboardingDraft.replayRestartFileName)
        let otherSpace = scene.store.state.spaces.first { $0.id == scene.other }!
        #expect(OnboardingDraft.takeReplayRestart(directory: scene.replayRoot, space: otherSpace) == nil)
    }

    @Test @MainActor func relaunchResumesReplayAtItsImportWithEveryPendingChoiceAndConsumesItOnce() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        let restarting = restarting(scene)
        try restarting.save(directory: scene.replayRoot, fileName: OnboardingDraft.replayRestartFileName)
        let originSpace = scene.store.state.spaces.first { $0.id == scene.original.id }!
        var resumed = OnboardingDraft.takeReplayRestart(directory: scene.replayRoot, space: originSpace)
        #expect(resumed?.stage == .bookmarks)
        resumed?.stage = restarting.stage
        #expect(resumed == restarting)
        #expect(OnboardingDraft.takeReplayRestart(directory: scene.replayRoot, space: originSpace) == nil)
    }

    @Test @MainActor func replayIntentsAreMarkedAndOrdinaryIntentsAreNot() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        let destination = BrowserImportDestination(spaceID: scene.original.id, profileID: scene.original.profileID)
        try BrowserImportRestartIntent(destination: destination, onboarding: false, replay: true).save(in: scene.replayRoot)
        #expect(try BrowserImportRestartIntent.take(from: scene.replayRoot)?.replay == true)
        try BrowserImportRestartIntent(destination: destination, onboarding: false).save(in: scene.replayRoot)
        #expect(try BrowserImportRestartIntent.take(from: scene.replayRoot)?.replay == false)
    }

    @Test @MainActor func anIntentWrittenBeforeReplayRestartsIsNeverAReplayIntent() throws {
        let scene = try scene()
        defer { scene.fixture.remove() }
        try Data(#"{"spaceID":"\#(scene.original.id)","profileID":"\#(scene.original.profileID)","onboarding":false}"#.utf8)
            .write(to: scene.replayRoot.appendingPathComponent("PendingBrowserImportRestart.json"))
        #expect(try BrowserImportRestartIntent.take(from: scene.replayRoot)?.replay == false)
    }

    @Test @MainActor func aFailedReplayWriteRollsBackEveryChoice() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let failureRoot = fixture.subdirectory("replay-write-failure")
        let store = try BrowserStore(directory: failureRoot)
        try store.completeOnboarding(try OnboardingDraft.load(directory: failureRoot, space: store.activeSpace))
        var failing = OnboardingDraft(spaceID: store.activeSpaceID, spaceName: "Must not commit", theme: replayTheme)
        failing.favoriteURLs = [gmail.url]
        let previous = store.state
        let session = failureRoot.appendingPathComponent("session.json")
        try FileManager.default.removeItem(at: session)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.applyOnboardingReplay(failing) }
        #expect(store.state == previous)
    }

    @Test @MainActor func aFavoriteSpelledWithHttpWwwOrATrailingSlashIsNotDuplicated() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let dedupeRoot = fixture.subdirectory("replay-dedupe")
        let first = try BrowserStore(directory: dedupeRoot)
        var setup = try OnboardingDraft.load(directory: dedupeRoot, space: first.activeSpace)
        setup.bookmarks = [.init(title: "Old", url: "https://example.com/old")]
        try first.completeOnboarding(setup)
        let sessionURL = dedupeRoot.appendingPathComponent("session.json")
        try fixture.rewriteDraft(sessionURL) { session in
            var tabs = session["tabs"] as! [[String: Any]]
            for index in tabs.indices {
                if tabs[index]["savedURL"] as? String == "https://youtube.com" { tabs[index]["savedURL"] = "http://www.youtube.com/" }
                if tabs[index]["savedURL"] as? String == "https://example.com/old" { tabs[index]["archivedAt"] = "2023-11-14T22:13:20Z" }
            }
            session["tabs"] = tabs
        }
        let store = try BrowserStore(directory: dedupeRoot)
        let space = store.activeSpace
        #expect(store.state.tabs.contains { $0.savedURL == "http://www.youtube.com/" && $0.kind == .favorite })
        #expect(store.state.tabs.contains { $0.savedURL == "https://example.com/old" && $0.archivedAt != nil })
        var replay = OnboardingDraft(spaceID: space.id, spaceName: space.name, theme: space.theme)
        replay.favoriteURLs = ["https://youtube.com"]
        replay.bookmarks = [.init(title: "Old again", url: "https://example.com/old")]
        try store.applyOnboardingReplay(replay)
        let youtubeTabs = store.state.tabs.filter { $0.kind == .favorite && $0.profileID == space.profileID
            && ($0.savedURL == "https://youtube.com" || $0.savedURL == "http://www.youtube.com/") }
        #expect(youtubeTabs.count == 1)
        let old = store.state.tabs.filter { $0.kind == .pinned && $0.savedURL == "https://example.com/old" }
        #expect(old.count == 2)
        #expect(old.filter { $0.archivedAt == nil }.count == 1)
        #expect(OnboardingDraft.choiceURL(forSaved: "http://www.youtube.com/") == youtube.url)
        #expect(OnboardingDraft.choiceURL(forSaved: "https://example.com/app") == "https://example.com/app")
        var seeded = replay
        seeded.favoriteURLs = [OnboardingDraft.choiceURL(forSaved: "http://www.youtube.com/")]
        #expect(seeded.isFavoriteSelected(youtube))
    }

    @Test @MainActor func firstLaunchKeepsLinksDifferingOnlyByFragmentAndDropsOnlyExactDuplicates() throws {
        let fixture = try PresentationOnboardingFixture()
        defer { fixture.remove() }
        let fragmentRoot = fixture.subdirectory("first-launch-fragments")
        let store = try BrowserStore(directory: fragmentRoot)
        var fragments = try OnboardingDraft.load(directory: fragmentRoot, space: store.activeSpace)
        fragments.bookmarks = [.init(title: "Inbox", url: "https://mail.google.com/mail/#inbox"),
                               .init(title: "Starred", url: "https://mail.google.com/mail/#starred"),
                               .init(title: "Inbox again", url: "https://mail.google.com/mail/#inbox")]
        try store.completeOnboarding(fragments)
        #expect(store.pinnedTabs.map(\.savedURL).sorted()
            == ["https://mail.google.com/mail/#inbox", "https://mail.google.com/mail/#starred"])
    }
}
