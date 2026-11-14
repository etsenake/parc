import Foundation

@main
@MainActor
struct OnboardingTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-onboarding-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_700_000_000) })
        try store.save()
        var draft = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(draft.selectedFavorites.map(\.url) == ["https://youtube.com", "https://calendar.google.com"],
                     "Fresh setup preserves the original two initially selected apps and order")
        precondition(OnboardingDraft.favoriteChoices.map(\.id) ==
            ["twitter", "gmail", "gcal", "spotify", "youtube", "notion", "slack", "figma", "outlook"],
            "The setup grid is the nine-item subset, not all TopApp cases")
        draft.spaceName = "Personal"
        draft.stage = .bookmarks
        draft.iCloudPasswordsProfileID = store.activeSpace.profileID
        draft.favoriteURLs = [OnboardingDraft.favoriteChoices[0].url]
        draft.bookmarks = [.init(title: "Docs", url: "https://example.com/docs"),
                           .init(title: "Duplicate", url: "https://example.com/docs"),
                           .init(title: "Invalid", url: "javascript:alert(1)")]
        try draft.save(directory: root)
        let resumed = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(resumed == draft, "The stage and pending imported values must resume exactly")
        precondition(resumed.iCloudPasswordsProfileID == store.activeSpace.profileID,
                     "An accepted extension choice resumes with its original destination, not the active Profile")
        precondition(!store.state.settings.onboardingComplete && store.state.tabs.isEmpty,
                     "A draft must not commit setup or open tabs")
        let draftFile = root.appendingPathComponent("onboarding.json")
        var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: draftFile)) as! [String: Any]
        legacy.removeValue(forKey: "defaultBrowserChoice")
        legacy.removeValue(forKey: "iCloudPasswordsProfileID")
        legacy.removeValue(forKey: "favoriteOrder")
        legacy.removeValue(forKey: "importedAdBlockers")
        legacy.removeValue(forKey: "adBlockerChoice")
        legacy["stage"] = 3
        try JSONSerialization.data(withJSONObject: legacy).write(to: draftFile)
        let migrated = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(migrated.stage == .bookmarks && migrated.wantsDefaultBrowser,
                     "Old introduction drafts resume at real import setup without changing system defaults")
        precondition(migrated.iCloudPasswordsProfileID == nil,
                     "An older draft never invents extension installation authorization")
        precondition(migrated.selectedFavorites.map(\.url) == [OnboardingDraft.favoriteChoices[0].url],
                     "A missing order preserves old explicit choices, not new defaults")
        legacy["stage"] = 4
        try JSONSerialization.data(withJSONObject: legacy).write(to: draftFile)
        let legacyTheme = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(legacyTheme.stage == .theme,
                     "Existing theme drafts must not decode as another screen")
        draft.stage = .defaultBrowser; draft.defaultBrowserChoice = false
        try draft.save(directory: root)
        let optedOut = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(!optedOut.wantsDefaultBrowser && optedOut.stage.next == .ready,
                     "An explicit No survives restart without blocking setup")
        precondition(OnboardingDraft.Stage.sellCompleted.next == .bookmarks
            && OnboardingDraft.Stage.bookmarks.previous == nil
            && OnboardingDraft.Stage.favorites.previous == .bookmarks
            && OnboardingDraft.Stage.theme.next == .windowFrame
            && OnboardingDraft.Stage.windowFrame.next == .defaultBrowser
            && OnboardingDraft.Stage.windowFrame.previous == .theme
            && OnboardingDraft.Stage.defaultBrowser.previous == .windowFrame
            && OnboardingDraft.Stage.ready.next == nil,
            "Setup navigation must not use persisted integer arithmetic or replay the welcome on Back")
        precondition(OnboardingDraft.Stage.setupOrder == [.bookmarks, .favorites, .theme, .windowFrame, .defaultBrowser, .ready]
            && OnboardingDraft.Stage.setupOrder(includingAdBlockers: true) ==
                [.bookmarks, .favorites, .theme, .windowFrame, .adBlockers, .defaultBrowser, .ready],
            "The frame step follows theme, and ad blockers sit between it and default browser")
        precondition(OnboardingDraft.Stage.adBlockers.rawValue == 9 && OnboardingDraft.Stage.windowFrame.rawValue == 10
            && OnboardingDraft.Stage.theme.rawValue == 4 && OnboardingDraft.Stage.defaultBrowser.rawValue == 8
            && !OnboardingDraft.Stage.windowFrame.isWelcome,
            "The frame step appends a new persisted tag without renumbering saved drafts")
        var framed = draft
        framed.stage = .theme
        precondition(framed.nextStage() == .windowFrame && framed.windowFrameThickness == nil
            && framed.windowFrameValue(saved: 10) == 10 && framed.windowFrameValue(saved: 6) == 6,
            "Theme continues to the frame step, which starts from the saved thickness")
        framed.stage = .windowFrame
        framed.importedAdBlockers = [.init(identifier: OnboardingAdBlocker.uBlockOrigin, displayName: "uBlock Origin")]
        precondition(framed.nextStage() == .defaultBrowser && framed.previousStage() == .theme
            && framed.visibleSetupOrder().firstIndex(of: .windowFrame) == 3 && framed.displayedSetupCount() == 5,
            "The frame step is the fourth counted step and Back returns to theme")
        framed.importedAdBlockers = []
        precondition(framed.nextStage() == .adBlockers, "The ad-blocker step follows the frame step when shown")
        framed.chooseWindowFrame(4)
        try framed.save(directory: root)
        let resumedFrame = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(resumedFrame.stage == .windowFrame && resumedFrame.windowFrameThickness == 4
            && resumedFrame.windowFrameValue(saved: 10) == 4,
            "A chosen thickness and the frame stage resume after restart")
        framed.chooseWindowFrame(40)
        precondition(framed.windowFrameThickness == 13, "A chosen thickness stays inside the range")
        framed.skipWindowFrame()
        precondition(framed.windowFrameThickness == nil && framed.windowFrameValue(saved: 7) == 7,
            "Skip keeps whatever thickness is already saved")
        var frameJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: draftFile)) as! [String: Any]
        frameJSON["windowFrameThickness"] = 99
        try JSONSerialization.data(withJSONObject: frameJSON).write(to: draftFile)
        let rangedFrame = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(rangedFrame.windowFrameThickness == nil,
            "An out-of-range saved thickness is dropped rather than applied")
        frameJSON.removeValue(forKey: "windowFrameThickness")
        try JSONSerialization.data(withJSONObject: frameJSON).write(to: draftFile)
        let olderFrame = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(olderFrame.windowFrameThickness == nil && olderFrame.stage == .windowFrame,
            "Drafts saved before the frame step decode without a chosen thickness")
        let ublock = OnboardingDraft.ImportedAdBlocker(
            identifier: "cjpalhdlnbpafiamejdnhcphjbkeiagm", displayName: "uBlock Origin")
        let setupProfile = store.activeSpace.profileID, sideProfile = UUID()
        let adGuard = OnboardingDraft.ImportedAdBlocker(identifier: "bgnkhhnnamicmpeenaelnjfhikgbkllg",
            displayName: "AdGuard AdBlocker", profileIDs: [setupProfile, sideProfile])
        var blocked = draft
        blocked.stage = .windowFrame
        precondition(blocked.nextStage() == .adBlockers && blocked.displayedSetupCount() == 6,
                     "With no ad blocker imported, allSteps includes the YES/NO ad-blocker step")
        blocked.importedAdBlockers = [ublock]
        precondition(blocked.nextStage() == .defaultBrowser && !blocked.visibleSetupOrder().contains(.adBlockers)
            && blocked.displayedSetupCount() == 5,
                     "uBlock Origin alone is already the default choice, so the step is omitted; Ready is not in the total")
        blocked.importedAdBlockers = [ublock, adGuard]
        blocked.adBlockerChoice = .keep(ublock.identifier)
        precondition(blocked.nextStage() == .adBlockers && blocked.visibleSetupOrder().contains(.adBlockers),
                     "Any other imported blocker continues into the setup step")
        blocked.stage = .adBlockers
        precondition(blocked.nextStage() == .defaultBrowser && blocked.previousStage() == .windowFrame,
                     "Ad-blocker setup continues to the default-browser step and returns to the frame step")
        blocked.stage = .defaultBrowser
        precondition(blocked.previousStage() == .adBlockers,
                     "Back from default browser returns to ad blockers while they remain included")
        blocked.importedAdBlockers = [ublock]
        precondition(blocked.previousStage() == .windowFrame && !blocked.visibleSetupOrder().contains(.adBlockers),
                     "A blocker set of only uBlock Origin omits the step without changing the remaining order")
        blocked.stage = .adBlockers
        precondition(blocked.visibleSetupOrder().contains(.adBlockers) && blocked.nextStage() == .defaultBrowser,
                     "The current ad-blocker step is retained until Next or Back leaves it")
        blocked.importedAdBlockers = [ublock, adGuard]
        try blocked.save(directory: root)
        let resumedBlockers = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(resumedBlockers.importedAdBlockers == [ublock, adGuard]
            && resumedBlockers.adBlockerChoice == .keep(ublock.identifier),
                     "Imported blockers, their Profiles and the pending keep choice resume")
        blocked.importedAdBlockers.append(.init(identifier: "not-a-known-blocker", displayName: "Unknown"))
        blocked.adBlockerChoice = .keep("not-a-known-blocker")
        try blocked.save(directory: root)
        let filteredBlockers = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(filteredBlockers.importedAdBlockers == [ublock, adGuard] && filteredBlockers.adBlockerChoice == nil,
                     "Unknown extension IDs cannot invent the ad-blocker step or keep choice")
        blocked.importedAdBlockers = [ublock]
        blocked.adBlockerChoice = OnboardingDraft.AdBlockerChoice.none
        try blocked.save(directory: root)
        let noneChoice = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(noneChoice.adBlockerChoice == OnboardingDraft.AdBlockerChoice.none,
                     "Don't-block-ads survives restart until setup finishes")
        blocked.adBlockerChoice = .uBlock
        try blocked.save(directory: root)
        let misplacedYes = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(misplacedYes.adBlockerChoice == nil,
                     "YES belongs only to the layout shown when nothing was imported")
        blocked.importedAdBlockers = []
        try blocked.save(directory: root)
        let yesChoice = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(yesChoice.adBlockerChoice == .uBlock, "YES survives restart")
        var olderBlocker = try JSONSerialization.jsonObject(with: Data(contentsOf: draftFile)) as! [String: Any]
        olderBlocker["importedAdBlockers"] = [["identifier": ublock.identifier, "displayName": ublock.displayName]]
        olderBlocker["adBlockerChoice"] = ["keep": ["_0": ublock.identifier]]
        try JSONSerialization.data(withJSONObject: olderBlocker).write(to: draftFile)
        let olderBlockers = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(olderBlockers.importedAdBlockers == [ublock] && olderBlockers.importedAdBlockers[0].profileIDs == nil
            && olderBlockers.adBlockerChoice == .keep(ublock.identifier),
                     "Drafts saved before Profiles were recorded still decode")
        typealias Choice = OnboardingDraft.AdBlockerChoice
        precondition(Choice.settled(nil, for: []) == .uBlock && Choice.settled(Choice.none, for: []) == Choice.none
            && Choice.settled(.keep(ublock.identifier), for: []) == .uBlock
            && Choice.settled(nil, for: [ublock, adGuard]) == .keep(ublock.identifier)
            && Choice.settled(.uBlock, for: [ublock, adGuard]) == .keep(ublock.identifier)
            && Choice.settled(.keep(adGuard.identifier), for: [ublock, adGuard]) == .keep(adGuard.identifier)
            && Choice.settled(Choice.none, for: [ublock, adGuard]) == Choice.none,
                     "The step opens on YES or the first imported blocker and keeps a choice that still has its row")
        var placed = ublock
        placed.profileIDs = [setupProfile]
        precondition(Choice.none.plan(for: [placed, adGuard], setupProfileID: setupProfile)
            == .init(removals: [setupProfile: [ublock.identifier, adGuard.identifier], sideProfile: [adGuard.identifier]],
                     installProfileID: nil),
                     "Don't block ads removes every imported blocker from each Profile it went into")
        precondition(Choice.keep(ublock.identifier).plan(for: [placed, adGuard], setupProfileID: setupProfile)
            == .init(removals: [setupProfile: [adGuard.identifier], sideProfile: [adGuard.identifier]], installProfileID: nil)
            && Choice.keep(adGuard.identifier).plan(for: [placed, adGuard], setupProfileID: setupProfile)
            == .init(removals: [setupProfile: [ublock.identifier]], installProfileID: nil),
                     "Keeping one blocker removes the others in each Profile")
        precondition(Choice.uBlock.plan(for: [], setupProfileID: setupProfile)
            == .init(removals: [:], installProfileID: setupProfile)
            && Choice.none.plan(for: [], setupProfileID: setupProfile) == .init(removals: [:], installProfileID: nil),
                     "YES installs uBlock into the setup Space's Profile; NO changes nothing")
        precondition(Choice.keepAll.plan(for: [placed, adGuard], setupProfileID: setupProfile)
            == .init(removals: [:], installProfileID: nil)
            && Choice.keepAll.plan(for: [], setupProfileID: setupProfile) == .init(removals: [:], installProfileID: nil),
                     "Use all imported ad blockers leaves every one installed, though the step preselected the first")
        blocked.importedAdBlockers = [ublock, adGuard]
        blocked.adBlockerChoice = .keepAll
        try blocked.save(directory: root)
        let keptAll = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(keptAll.adBlockerChoice == .keepAll
            && Choice.settled(.keepAll, for: [ublock, adGuard]) == .keep(ublock.identifier),
                     "Keep-all survives restart; returning to the step selects its first row again")
        blocked.stage = .defaultBrowser
        blocked.importedAdBlockers = [ublock]
        blocked.adBlockerChoice = .keep(adGuard.identifier)
        try blocked.save(directory: root)
        let choiceAfterStep = try OnboardingDraft.load(directory: root, space: store.activeSpace)
        precondition(choiceAfterStep.adBlockerChoice == .keep(adGuard.identifier),
                     "A choice made at the step stands after restart even if its kept blocker later failed")
        blocked.stage = .adBlockers
        precondition(Choice.keep("pkehgijcmpdhfbdbbnkijodmdjhbjlgp").plan(for: [placed, adGuard], setupProfileID: setupProfile)
            == .init(removals: [setupProfile: [ublock.identifier, adGuard.identifier], sideProfile: [adGuard.identifier]],
                     installProfileID: nil),
                     "Keeping a blocker whose download later failed still removes the others")
        precondition(Choice.none.plan(for: [ublock], setupProfileID: setupProfile)
            == .init(removals: [setupProfile: [ublock.identifier]], installProfileID: nil),
                     "An older draft's blocker without Profiles is removed from the setup Space's Profile")
        blocked.importedAdBlockers = []
        blocked.adBlockerChoice = nil
        blocked.stage = .defaultBrowser
        try blocked.save(directory: root)
        let profile = store.state.profiles
        draft.stage = .ready
        try store.completeOnboarding(draft)
        let committed = store.state
        precondition(committed.settings.onboardingComplete && store.activeSpace.name == "Personal")
        precondition(store.favorites.count == 1 && store.pinnedTabs.count == 1,
                     "Commit must reject duplicate/invalid imports")
        precondition(committed.profiles == profile, "Setup must preserve profile/archive policy")
        try store.completeOnboarding(draft)
        precondition(store.state == committed, "Retry must not duplicate setup")
        let reopened = try BrowserStore(directory: root)
        precondition(reopened.state.settings.onboardingComplete && reopened.activeSpace.name == "Personal"
                     && reopened.favorites.count == 1 && reopened.pinnedTabs.count == 1
                     && reopened.state.profiles == profile,
                     "Completion and selected setup must persist together")
        try OnboardingDraft.remove(directory: root)

        let selectionRoot = root.appendingPathComponent("ordered-favorites")
        let selectionStore = try BrowserStore(directory: selectionRoot)
        var selection = try OnboardingDraft.load(directory: selectionRoot, space: selectionStore.activeSpace)
        let gmail = OnboardingDraft.favoriteChoices[1], figma = OnboardingDraft.favoriteChoices[7]
        let youtube = OnboardingDraft.favoriteChoices[4]
        selection.toggleFavorite(gmail)
        selection.toggleFavorite(figma)
        precondition(selection.selectedFavorites.map(\.url) ==
            [figma.url, gmail.url, youtube.url, "https://calendar.google.com"],
            "New selections enter at the front rather than catalogue or click order")
        selection.toggleFavorite(gmail)
        precondition(!selection.isFavoriteSelected(gmail)
            && selection.selectedFavorites.map(\.url) == [figma.url, youtube.url, "https://calendar.google.com"])
        selection.toggleFavorite(gmail)
        precondition(selection.selectedFavorites.first?.url == gmail.url,
                     "Reselecting an app moves it to the front")
        selection.favoriteURLs.insert("https://www.youtube.com")
        selection.toggleFavorite(youtube)
        precondition(!selection.favoriteURLs.contains(youtube.url)
            && !selection.favoriteURLs.contains("https://www.youtube.com"),
            "Deselecting a migrated app removes every old alias")
        selection.toggleFavorite(youtube)
        selection.favoriteURLs.insert("https://github.com")
        selection.favoriteURLs.insert("javascript:alert(1)")
        selection.favoriteOrder?.append(contentsOf: [gmail.url, "javascript:alert(1)"])
        let priorSelection = selection
        selection.toggleFavorite(.init(id: gmail.id, title: "Forged", url: "https://example.com"))
        precondition(selection == priorSelection, "An unknown catalogue choice cannot mutate the draft")
        try selection.save(directory: selectionRoot)
        let resumedSelection = try OnboardingDraft.load(directory: selectionRoot, space: selectionStore.activeSpace)
        precondition(resumedSelection == selection, "Pending ordered choices resume without committing tabs")
        let expectedURLs = [youtube.url, gmail.url, figma.url, "https://calendar.google.com", "https://github.com"]
        precondition(resumedSelection.selectedFavorites.map(\.url) == expectedURLs,
                     "Old explicit GitHub choices survive; unknown URLs and duplicate order entries do not commit")
        try selectionStore.completeOnboarding(resumedSelection)
        precondition(selectionStore.favorites.map(\.savedURL) == expectedURLs,
                     "The real session commits the ordered Favorites, not catalogue order")
        let selectionReopened = try BrowserStore(directory: selectionRoot)
        precondition(selectionReopened.favorites.map(\.savedURL) == expectedURLs,
                     "Favorite ordering survives session restart")

        let aliasRoot = root.appendingPathComponent("existing-alias")
        let aliasStore = try BrowserStore(directory: aliasRoot)
        var aliasDraft = try OnboardingDraft.load(directory: aliasRoot, space: aliasStore.activeSpace)
        aliasDraft.favoriteURLs = ["https://www.youtube.com", youtube.url, "https://www.notion.so"]
        aliasDraft.favoriteOrder = [youtube.url, "https://www.youtube.com", "https://www.notion.so"]
        precondition(aliasDraft.selectedFavorites.map(\.url) == [youtube.url, "https://notion.so"],
                     "Legacy aliases normalize and deduplicate without altering arbitrary imported URLs")
        try aliasStore.completeOnboarding(aliasDraft)
        precondition(aliasStore.favorites.map(\.savedURL) == [youtube.url, "https://notion.so"])

        let failureRoot = root.appendingPathComponent("write-failure")
        let failureStore = try BrowserStore(directory: failureRoot)
        var failingDraft = try OnboardingDraft.load(directory: failureRoot, space: failureStore.activeSpace)
        failingDraft.spaceName = "Must not commit"
        failingDraft.favoriteURLs = [OnboardingDraft.favoriteChoices[1].url]
        let previous = failureStore.state
        try FileManager.default.createDirectory(at: failureRoot.appendingPathComponent("session.json"), withIntermediateDirectories: false)
        do {
            try failureStore.completeOnboarding(failingDraft)
            preconditionFailure("A non-writable session destination must fail")
        } catch {
            precondition(failureStore.state == previous, "A failed atomic write must roll back all setup")
        }
        try Self.checkReplay(root: root)
        try Self.checkSkip(root: root)
        try Self.checkExperience()
        print("Onboarding draft, commit, retry, restart, rollback, replay and skip checks passed")
    }

    static func checkSkip(root: URL) throws {
        let skipRoot = root.appendingPathComponent("skip")
        let store = try BrowserStore(directory: skipRoot)
        try store.save()
        var draft = try OnboardingDraft.load(directory: skipRoot, space: store.activeSpace)
        var chosen = SpaceTheme.singleColor(ThemeColor(hex: "4C6688")!)
        chosen.wheel = .analogous; chosen.appearance = .dark; chosen.noise = 0.5; chosen.intensity = 0.3
        chosen.texture = .denim
        draft.theme = chosen
        draft.skipTheme(replayBase: nil)
        precondition(draft.theme == SpaceTheme(wheel: .analogous, appearance: .dark),
                     "Skip on the theme step keeps only the wheel and light/dark")
        precondition(draft.theme.primaryColor == nil && draft.theme.colorCount == 0 && draft.theme.noise == 0
            && draft.theme.intensity == 0.8 && draft.theme.texture == .grain && draft.theme.isValid,
            "Skipped theme is the no-colour default")

        precondition(!draft.selectedFavorites.isEmpty, "Fixture starts with the default Favorites")
        draft.skipFavorites()
        precondition(draft.selectedFavorites.isEmpty && draft.favoriteOrder == [], "Skip on Favorites selects none")
        try draft.save(directory: skipRoot)
        let resumed = try OnboardingDraft.load(directory: skipRoot, space: store.activeSpace)
        precondition(resumed.selectedFavorites.isEmpty, "A skipped Favorites step resumes empty, not with the defaults")
        try store.completeOnboarding(resumed)
        precondition(!store.state.tabs.contains { $0.kind == .favorite },
                     "First launch after skipping Favorites adds no Favorites")

        let base = SpaceTheme.singleColor(ThemeColor(hex: "a1b2c3")!)
        var replay = OnboardingDraft(spaceID: store.activeSpace.id, spaceName: "Home", theme: chosen)
        replay.replayBaseTheme = base
        replay.skipTheme(replayBase: base)
        precondition(replay.theme == base, "Replay Skip restores the theme the replay started from")
        let existing: Set<String> = ["https://notion.so"]
        replay.favoriteURLs = existing.union(["https://figma.com"])
        replay.skipFavorites(keeping: existing)
        precondition(replay.selectedFavorites.map(\.url) == ["https://notion.so"],
                     "Replay Skip keeps the profile's existing Favorites selected and drops new picks")
    }

    static func checkReplayDedupe(root: URL) throws {
        let dedupeRoot = root.appendingPathComponent("replay-dedupe")
        let first = try BrowserStore(directory: dedupeRoot)
        var setup = try OnboardingDraft.load(directory: dedupeRoot, space: first.activeSpace)
        setup.bookmarks = [.init(title: "Old", url: "https://example.com/old")]
        try first.completeOnboarding(setup)
        let sessionURL = dedupeRoot.appendingPathComponent("session.json")
        var session = try JSONSerialization.jsonObject(with: Data(contentsOf: sessionURL)) as! [String: Any]
        var tabs = session["tabs"] as! [[String: Any]]
        for index in tabs.indices {
            if tabs[index]["savedURL"] as? String == "https://youtube.com" { tabs[index]["savedURL"] = "http://www.youtube.com/" }
            if tabs[index]["savedURL"] as? String == "https://example.com/old" { tabs[index]["archivedAt"] = "2023-11-14T22:13:20Z" }
        }
        session["tabs"] = tabs
        try JSONSerialization.data(withJSONObject: session).write(to: sessionURL)
        let store = try BrowserStore(directory: dedupeRoot)
        let space = store.activeSpace
        precondition(store.state.tabs.contains { $0.savedURL == "http://www.youtube.com/" && $0.kind == .favorite }
            && store.state.tabs.contains { $0.savedURL == "https://example.com/old" && $0.archivedAt != nil },
            "Fixture has a differently spelled Favorite and an archived pinned tab")
        var replay = OnboardingDraft(spaceID: space.id, spaceName: space.name, theme: space.theme)
        replay.favoriteURLs = ["https://youtube.com"]
        replay.bookmarks = [.init(title: "Old again", url: "https://example.com/old")]
        try store.applyOnboardingReplay(replay)
        let youtube = store.state.tabs.filter { $0.kind == .favorite && $0.profileID == space.profileID
            && ($0.savedURL == "https://youtube.com" || $0.savedURL == "http://www.youtube.com/") }
        precondition(youtube.count == 1, "A Favorite spelled with http, www or a trailing slash is not duplicated")
        let old = store.state.tabs.filter { $0.kind == .pinned && $0.savedURL == "https://example.com/old" }
        precondition(old.count == 2 && old.filter { $0.archivedAt == nil }.count == 1,
                     "An archived pinned tab doesn't block adding the bookmark again")
        let choiceYouTube = OnboardingDraft.favoriteChoices[4]
        precondition(OnboardingDraft.choiceURL(forSaved: "http://www.youtube.com/") == choiceYouTube.url
            && OnboardingDraft.choiceURL(forSaved: "https://example.com/app") == "https://example.com/app",
            "Existing Favorites seed the grid under the commit's comparison")
        var seeded = replay; seeded.favoriteURLs = [OnboardingDraft.choiceURL(forSaved: "http://www.youtube.com/")]
        precondition(seeded.isFavoriteSelected(choiceYouTube), "An http://www.youtube.com/ Favorite shows YouTube selected")

        let fragmentRoot = root.appendingPathComponent("first-launch-fragments")
        let fragmentStore = try BrowserStore(directory: fragmentRoot)
        var fragments = try OnboardingDraft.load(directory: fragmentRoot, space: fragmentStore.activeSpace)
        fragments.bookmarks = [.init(title: "Inbox", url: "https://mail.google.com/mail/#inbox"),
                               .init(title: "Starred", url: "https://mail.google.com/mail/#starred"),
                               .init(title: "Inbox again", url: "https://mail.google.com/mail/#inbox")]
        try fragmentStore.completeOnboarding(fragments)
        precondition(fragmentStore.pinnedTabs.map(\.savedURL).sorted()
            == ["https://mail.google.com/mail/#inbox", "https://mail.google.com/mail/#starred"],
            "First launch keeps links differing only by fragment and drops only exact duplicates")
    }

    static func theme(in store: BrowserStore, _ id: UUID) -> SpaceTheme? {
        store.state.spaces.first { $0.id == id }?.theme
    }

    static func checkReplay(root: URL) throws {
        let replayRoot = root.appendingPathComponent("replay")
        let store = try BrowserStore(directory: replayRoot)
        var first = try OnboardingDraft.load(directory: replayRoot, space: store.activeSpace)
        first.bookmarks = [.init(title: "Docs", url: "https://example.com/docs")]
        try store.completeOnboarding(first)
        let original = store.activeSpace
        let other = store.createSpace(name: "Work")
        let unnamed = store.createSpace(name: "")
        store.selectSpace(other)
        let before = store.state
        precondition(before.spaces.first { $0.id == unnamed }?.title == nil, "Fixture Space uses its placeholder name")

        let gmail = OnboardingDraft.favoriteChoices[1], youtube = OnboardingDraft.favoriteChoices[4]
        let replayTheme = SpaceTheme.singleColor(ThemeColor(hex: "a1b2c3")!)
        var replay = OnboardingDraft(spaceID: original.id, spaceName: "Home", theme: replayTheme)
        replay.favoriteURLs = Set(before.tabs.filter {
            $0.profileID == original.profileID && $0.kind == .favorite && $0.archivedAt == nil
        }.map(\.savedURL))
        precondition(replay.isFavoriteSelected(youtube), "Replay starts from the profile's existing Favorites")
        replay.toggleFavorite(gmail)
        replay.bookmarks = [.init(title: "Docs again", url: "https://example.com/docs"),
                            .init(title: "Guide", url: "https://example.com/guide")]
        try store.applyOnboardingReplay(replay)

        let applied = store.state
        let space = applied.spaces.first { $0.id == original.id }
        precondition(space?.name == "Home" && space?.theme == replayTheme, "Finish applies the replay's name and theme")
        precondition(before.tabs.allSatisfy(applied.tabs.contains), "Replay never removes or replaces existing tabs")
        precondition(applied.spaces.map(\.id) == before.spaces.map(\.id)
            && applied.spaces.filter { $0.id != original.id } == before.spaces.filter { $0.id != original.id },
            "Other Spaces stay as they were")
        precondition(applied.activeSpaceID == other && applied.settings == before.settings
            && applied.autoArchiveEducationEligible == before.autoArchiveEducationEligible,
            "Replay keeps the active Space, settings, completion marker and first-setup education gate")
        let favorites = applied.tabs.filter { $0.profileID == original.profileID && $0.kind == .favorite }
        let priorFavorites = before.tabs.filter { $0.profileID == original.profileID && $0.kind == .favorite }
        precondition(favorites.count == priorFavorites.count + 1
            && favorites.filter { $0.savedURL == gmail.url }.count == 1
            && favorites.filter { $0.savedURL == youtube.url }.count == 1,
            "Only newly chosen Favorites are added; existing ones are not duplicated")
        let pinned = applied.tabs.filter { $0.spaceID == original.id && $0.kind == .pinned }
        precondition(pinned.map(\.savedURL).sorted() == ["https://example.com/docs", "https://example.com/guide"],
            "The bookmark file adds new pinned tabs without duplicating existing ones")

        try store.applyOnboardingReplay(replay)
        precondition(store.state == applied, "Retrying Finish does not duplicate the replay's additions")
        let reopened = try BrowserStore(directory: replayRoot)
        precondition(theme(in: reopened, original.id) == replayTheme
            && reopened.state.tabs.filter { $0.kind == .favorite && $0.savedURL == gmail.url }.count == 1,
            "Replay choices persist in the session")

        var placeholder = OnboardingDraft(spaceID: unnamed, spaceName: "  ", theme: replayTheme)
        placeholder.favoriteURLs = []
        try store.applyOnboardingReplay(placeholder)
        placeholder.spaceName = store.state.spaces.first { $0.id == unnamed }!.name
        try store.applyOnboardingReplay(placeholder)
        precondition(store.state.spaces.first { $0.id == unnamed }?.title == nil,
                     "Keeping the suggested name does not freeze a placeholder title")

        let base = theme(in: store, original.id)!
        let live = SpaceTheme.singleColor(ThemeColor(hex: "334455")!)
        let later = SpaceTheme.singleColor(ThemeColor(hex: "445566")!)
        let external = SpaceTheme.singleColor(ThemeColor(hex: "556677")!)
        precondition(store.previewSpaceTheme(original.id, theme: live)
            && theme(in: store, original.id) == live, "The preview is the Space's live theme")
        precondition(store.previewSpaceTheme(original.id, theme: later), "A second pick replaces the preview")
        store.renameSpace(other, name: "Work, renamed")
        try store.save()
        let crashed = try BrowserStore(directory: replayRoot)
        precondition(theme(in: crashed, original.id) == base
            && crashed.state.spaces.first { $0.id == other }?.name == "Work, renamed",
            "A session write during the preview, then a crash, keeps the saved theme and the unrelated change")
        precondition(store.savedTheme(of: store.state.spaces.first { $0.id == original.id }!) == base)
        store.endSpaceThemePreview(original.id)
        precondition(theme(in: store, original.id) == base, "Closing early shows the saved theme again")
        try store.save()
        let closedEarly = try BrowserStore(directory: replayRoot)
        precondition(theme(in: closedEarly, original.id) == base)

        precondition(store.previewSpaceTheme(original.id, theme: live))
        var finishing = OnboardingDraft(spaceID: original.id, spaceName: "Home", theme: live)
        finishing.favoriteURLs = []
        try store.applyOnboardingReplay(finishing)
        store.endSpaceThemePreview(original.id)
        let finished = try BrowserStore(directory: replayRoot)
        precondition(theme(in: store, original.id) == live && theme(in: finished, original.id) == live,
            "Finish saves the replay theme and ends the preview")

        for before in [live, later] {
            precondition(store.previewSpaceTheme(original.id, theme: later))
            let change = try store.saveSpaceTheme(spaceID: original.id, profileID: original.profileID,
                                                  previous: before, theme: external)
            let edited = try BrowserStore(directory: replayRoot)
            precondition(change != nil && theme(in: edited, original.id) == external,
                         "An editor opened before (saved) or during (live) the preview saves its theme")
            store.endSpaceThemePreview(original.id)
            precondition(theme(in: store, original.id) == external, "Ending a replaced preview leaves the editor's theme")
            _ = try store.saveSpaceTheme(spaceID: original.id, profileID: original.profileID,
                                         previous: external, theme: live)
        }
        precondition(store.previewSpaceTheme(original.id, theme: later))
        _ = try store.saveSpaceTheme(spaceID: original.id, profileID: original.profileID, previous: live, theme: later)
        store.endSpaceThemePreview(original.id)
        let sameValue = try BrowserStore(directory: replayRoot)
        precondition(theme(in: sameValue, original.id) == later && theme(in: store, original.id) == later,
            "An editor saving the previewed value itself still persists it")

        var unchanged = OnboardingDraft(spaceID: original.id, spaceName: "Home", theme: later)
        unchanged.favoriteURLs = []
        unchanged.replayBaseName = "Home"; unchanged.replayBaseTheme = later
        store.renameSpace(original.id, name: "Renamed elsewhere")
        _ = try store.saveSpaceTheme(spaceID: original.id, profileID: original.profileID, previous: later, theme: external)
        precondition(store.previewSpaceTheme(original.id, theme: later))
        try store.applyOnboardingReplay(unchanged)
        let keptElsewhere = try BrowserStore(directory: replayRoot)
        precondition(store.state.spaces.first { $0.id == original.id }?.name == "Renamed elsewhere"
            && theme(in: store, original.id) == external && theme(in: keptElsewhere, original.id) == external,
            "Unchanged replay name and theme keep edits made elsewhere during replay")
        unchanged.spaceName = "Replay name"; unchanged.theme = live
        try store.applyOnboardingReplay(unchanged)
        precondition(store.state.spaces.first { $0.id == original.id }?.name == "Replay name"
            && theme(in: store, original.id) == live, "Changed replay name and theme apply")

        var restarting = replay
        restarting.replayBaseName = original.name; restarting.replayBaseTheme = base
        restarting.replayAppearance = "dark"
        restarting.stage = .theme
        try restarting.save(directory: replayRoot, fileName: OnboardingDraft.replayRestartFileName)
        precondition(!FileManager.default.fileExists(atPath: replayRoot.appendingPathComponent("onboarding.json").path),
                     "The replay restart draft never becomes a first-launch draft")
        let otherSpace = store.state.spaces.first { $0.id == other }!
        precondition(OnboardingDraft.takeReplayRestart(directory: replayRoot, space: otherSpace) == nil,
                     "A saved replay resumes only for its own Space")
        try restarting.save(directory: replayRoot, fileName: OnboardingDraft.replayRestartFileName)
        let originSpace = store.state.spaces.first { $0.id == original.id }!
        var resumed = OnboardingDraft.takeReplayRestart(directory: replayRoot, space: originSpace)
        precondition(resumed?.stage == .bookmarks, "Relaunch resumes replay at its import")
        resumed?.stage = restarting.stage
        precondition(resumed == restarting, "Every pending replay choice survives the restart")
        precondition(OnboardingDraft.takeReplayRestart(directory: replayRoot, space: originSpace) == nil,
                     "The saved replay is consumed once")

        let destination = BrowserImportDestination(spaceID: original.id, profileID: original.profileID)
        try BrowserImportRestartIntent(destination: destination, onboarding: false, replay: true).save(in: replayRoot)
        let marked = try BrowserImportRestartIntent.take(from: replayRoot)
        precondition(marked?.replay == true, "Replay intents are marked")
        try BrowserImportRestartIntent(destination: destination, onboarding: false).save(in: replayRoot)
        let ordinary = try BrowserImportRestartIntent.take(from: replayRoot)
        precondition(ordinary?.replay == false, "Ordinary intents are not")
        try Data(#"{"spaceID":"\#(original.id)","profileID":"\#(original.profileID)","onboarding":false}"#.utf8)
            .write(to: replayRoot.appendingPathComponent("PendingBrowserImportRestart.json"))
        let legacy = try BrowserImportRestartIntent.take(from: replayRoot)
        precondition(legacy?.replay == false, "An intent written before replay restarts is never a replay intent")

        try Self.checkReplayDedupe(root: root)

        let failureRoot = root.appendingPathComponent("replay-write-failure")
        let failureStore = try BrowserStore(directory: failureRoot)
        try failureStore.completeOnboarding(try OnboardingDraft.load(directory: failureRoot, space: failureStore.activeSpace))
        var failing = OnboardingDraft(spaceID: failureStore.activeSpaceID, spaceName: "Must not commit", theme: replayTheme)
        failing.favoriteURLs = [gmail.url]
        let previous = failureStore.state
        let session = failureRoot.appendingPathComponent("session.json")
        try FileManager.default.removeItem(at: session)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
        do {
            try failureStore.applyOnboardingReplay(failing)
            preconditionFailure("A non-writable session destination must fail")
        } catch {
            precondition(failureStore.state == previous, "A failed replay write rolls back every choice")
        }
    }

    static func checkExperience() throws {
        precondition(OnboardingExperience.readyTitle(cardName: "Ada Lovelace") == "Welcome to Parc, Ada Lovelace",
                     "Finished-step title interpolates the membership-card name")
        precondition(OnboardingExperience.readyTitle(cardName: "  ") == "Welcome to Parc",
                     "An empty card name does not invent a comma")
        precondition(OnboardingExperience.readyDescription.contains("Parc Card")
                     && OnboardingExperience.readyDescription.contains("upgraded internet"),
                     "Finished-step description is the recovered last-step copy")
        precondition(OnboardingExperience.shouldPlayConfetti(reduceMotion: false)
                     && !OnboardingExperience.shouldPlayConfetti(reduceMotion: true),
                     "Confetti is the inverse of Reduce Motion")
        precondition(OnboardingExperience.readyConfettiDelay == 0.4, "Confetti waits 0.4 s into the finished step")
        precondition(OnboardingExperience.direction(from: .defaultBrowser, to: .ready) == .forward
                     && OnboardingExperience.direction(from: .ready, to: .defaultBrowser) == .back
                     && OnboardingExperience.direction(from: .theme, to: .adBlockers) == .forward
                     && OnboardingExperience.direction(from: .adBlockers, to: .defaultBrowser) == .forward
                     && OnboardingExperience.direction(from: .adBlockers, to: .theme) == .back
                     && OnboardingExperience.direction(from: .theme, to: .theme) == nil
                     && OnboardingExperience.direction(from: .theme, to: .windowFrame) == .forward
                     && OnboardingExperience.direction(from: .windowFrame, to: .theme) == .back
                     && OnboardingExperience.direction(from: .windowFrame, to: .adBlockers) == .forward
                     && OnboardingExperience.direction(from: .defaultBrowser, to: .windowFrame) == .back,
                     "Setup TransitionDirection is back/forward from step order")
        precondition(OnboardingExperience.direction(from: .sellCompleted, to: .bookmarks) == nil
                     && OnboardingExperience.direction(from: .introAnimation, to: .bookmarks) == nil
                     && OnboardingExperience.direction(from: .bookmarks, to: .introAnimation) == .back,
                     "The first setup card appears in place after welcome; returning to welcome stays back")
        typealias Motion = OnboardingExperience.StepMotion
        precondition(Motion.offset == 400
                     && Motion.offsets(.forward) == (400, -400) && Motion.offsets(.back) == (-400, 400),
                     "Forward text comes from +400 and leaves to -400; back mirrors it")
        precondition(Motion.titleSpring == .init(response: 0.4, dampingFraction: 0.8)
                     && Motion.messageSpring == .init(response: 0.5, dampingFraction: 0.8),
                     "Title springs 0.4/0.8 and the message 0.5/0.8")
        precondition(abs(Motion.titleSpring.stiffness - 246.74) < 0.01 && abs(Motion.titleSpring.damping - 25.133) < 0.001
                     && abs(Motion.messageSpring.stiffness - 157.91) < 0.01 && abs(Motion.messageSpring.damping - 20.106) < 0.001,
                     "SwiftUI response/damping convert to unit-mass stiffness (2π/response)² and damping 4πζ/response")
        precondition(Motion.contentFadeDuration == 0.5 && Motion.enabledFadeDuration == 0.12,
                     "Content crossfades over the default 0.5 s spring; Next's enabled state fades over 0.12 s")
        precondition(Motion.slidesText(reduceMotion: false) && !Motion.slidesText(reduceMotion: true)
                     && Motion.fadesContent(reduceMotion: true) && Motion.fadesEnabledState(reduceMotion: true),
                     "Reduce Motion drops the 400 pt slides but keeps the fades")
        precondition(OnboardingExperience.shouldStartMusic(on: .startWelcome)
                     && !OnboardingExperience.shouldStartMusic(on: .changeStage)
                     && !OnboardingExperience.shouldStartMusic(on: .resignKey),
                     "Music starts only with welcome")
        for event: OnboardingExperience.MusicEvent in [.changeStage, .resignKey, .resignActive, .becomeKey, .becomeActive] {
            precondition(!OnboardingExperience.shouldPauseOrMute(on: event)
                         && !OnboardingExperience.shouldStopMusic(on: event),
                         "Focus/stage changes do not mute or stop the cue: \(event)")
        }
        for event: OnboardingExperience.MusicEvent in [.close, .finish, .terminate, .replay] {
            precondition(OnboardingExperience.shouldStopMusic(on: event), "Owner teardown stops music: \(event)")
        }
        precondition(!OnboardingExperience.authFeatureOnboardingPerformsHaptics,
                     "AuthFeature onboarding has no recovered haptic producer")
        precondition(!OnboardingExperience.welcomeShowsContent(stage: .introAnimation, reduceMotion: false)
                     && OnboardingExperience.welcomeShowsContent(stage: .sellIntro, reduceMotion: false)
                     && OnboardingExperience.welcomeShowsContent(stage: .sellCompleted, reduceMotion: false),
                     "The welcome's first phase builds no logo, headline or arrow, so their timers start with sellIntro")
        precondition(OnboardingExperience.welcomeShowsContent(stage: .introAnimation, reduceMotion: true)
                     && !OnboardingExperience.welcomeShowsContent(stage: .bookmarks, reduceMotion: true),
                     "Reduce Motion shows the settled headline and arrow from the first phase, never in setup")
        for stage: OnboardingDraft.Stage in [.introAnimation, .sellIntro, .sellCompleted] {
            precondition(OnboardingExperience.welcomeContinueTarget(from: stage) == .bookmarks,
                         "One press on the welcome arrow leaves for the first setup step: \(stage)")
        }
        for stage: OnboardingDraft.Stage in [.bookmarks, .theme, .ready] {
            precondition(OnboardingExperience.welcomeContinueTarget(from: stage) == nil,
                         "A late welcome press after setup began does nothing: \(stage)")
        }
        precondition(OnboardingDraft.Stage.introAnimation.next == .sellIntro
                     && OnboardingDraft.Stage.sellIntro.next == .sellCompleted,
                     "Timed welcome phases still step one at a time")
        precondition(OnboardingExperience.focusTarget(entering: .theme, from: .favorites) == .spaceName
                     && OnboardingExperience.focusTarget(entering: .theme, from: .theme) == .unchanged
                     && OnboardingExperience.focusTarget(entering: .ready, from: .defaultBrowser) == .next
                     && OnboardingExperience.focusTarget(entering: .windowFrame, from: .theme) == .next
                     && OnboardingExperience.focusTarget(entering: .introAnimation, from: nil) == .welcome
                     && OnboardingExperience.focusTarget(entering: .sellIntro, from: .introAnimation) == .unchanged
                     && OnboardingExperience.focusTarget(entering: .introAnimation, from: .introAnimation) == .unchanged
                     && OnboardingExperience.focusTarget(entering: .introAnimation, from: .sellCompleted) == .unchanged,
                     "Focus returns to space name, Next, or welcome rather than rerendering the same control")
    }
}
