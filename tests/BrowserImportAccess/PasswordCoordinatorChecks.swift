import AppKit

@MainActor
func passwordCoordinatorChecks(store: BrowserStore, destination: BrowserImportDestination,
                               window: NSWindow, safari: PCNativeImportSource,
                               other: PCNativeImportSource) throws -> Int {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), message)
    }
    var current = true
    func make(_ source: PCNativeImportSource = safari, continuing: Bool = true) -> BrowserImportCoordinator {
        let coordinator = BrowserImportCoordinator(store: store, destination: destination,
            window: window, ownerIsCurrent: { current })
        coordinator.discover()
        PCNativeBrowserApplication.sources.removeFirst().complete([source])
        coordinator.select(source); coordinator.loadProfiles()
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(
            profiles: [PCNativeImportProfile("Safari", [.history], .complete)], access: .complete))
        if continuing { coordinator.continueSourceInline() }
        return coordinator
    }
    let wrongSource = make(other)
    expect(wrongSource.stage == .finished && wrongSource.passwordDestination == nil,
           "An unrelated source imports without this password stage")
    wrongSource.cancel()
    let retired = make(continuing: false)
    current = false; retired.continueSourceInline()
    expect(retired.stage == .profiles && retired.passwordDestination == nil, "A retired owner cannot enter the file step")
    current = true; retired.cancel()
    let before = store.state, imports = PCNativeBrowserApplication.imports
    let coordinator = make()
    expect(coordinator.stage == .safariPasswords && coordinator.canImportPasswordFile,
           "Safari goes straight to its own real password stage")
    expect(store.state.profiles == before.profiles && store.state.spaces == before.spaces,
           "The password step writes no Profile or Space")
    expect(coordinator.passwordDestination?.profileID == destination.profileID,
           "The password stage holds the explicit original destination identity")
    expect(PCNativeBrowserApplication.imports == imports && PCNativeBrowserApplication.passwordRequests.isEmpty,
           "Entering the stage does not import any data")
    coordinator.importPasswordFile(URL(string: "https://example.invalid/passwords.csv")!)
    coordinator.importPasswordFile(URL(fileURLWithPath: "/fixture/passwords.txt"))
    expect(PCNativeBrowserApplication.passwordRequests.isEmpty && coordinator.passwordError != nil,
           "Remote URLs and non-CSV files never reach the native file reader")
    let file = URL(fileURLWithPath: "/fixture/Passwords.csv")
    coordinator.importPasswordFile(file)
    let request = PCNativeBrowserApplication.passwordRequests.removeFirst()
    expect(request.url == file && request.window === window &&
           request.path == store.independentEngineProfilePath(for: destination.profileID),
           "The selected file goes only to the exact original Profile and window")
    expect(coordinator.importingPasswords && !coordinator.canImportPasswordFile,
           "An accepted session owns admission until its actual completion")
    coordinator.importPasswordFile(file); coordinator.continueAfterPasswords()
    expect(PCNativeBrowserApplication.passwordRequests.isEmpty && coordinator.stage == .safariPasswords,
           "A duplicate submission or Skip cannot bypass an active native session")
    coordinator.stopPasswordImport()
    expect(request.lease.cancelled && coordinator.importingPasswords,
           "Stop requests cancellation and waits for the actual result")
    request.complete(.init(outcome: .cancelled, importedCount: 1))
    expect(!coordinator.importingPasswords && coordinator.passwordResult?.importedCount == 1 && !coordinator.canRemovePasswordFile,
           "Cancellation preserves confirmed counts without claiming rollback or removal")
    coordinator.importPasswordFile(file)
    let partial = PCNativeBrowserApplication.passwordRequests.removeFirst()
    expect(request.lease.cancelled, "A new explicit file submission revokes the old lease")
    request.complete(.init(outcome: .completed, importedCount: 900, canRemoveSourceFile: true))
    expect(coordinator.importingPasswords && coordinator.passwordResult == nil,
           "A stale prior result cannot finish or grant removal for a replacement request")
    partial.complete(.init(outcome: .partial, importedCount: 2, invalidCount: 1))
    expect(!coordinator.canRemovePasswordFile && coordinator.passwordResult?.invalidCount == 1,
           "Partial imports retain the source for review")
    coordinator.removePasswordFile()
    expect(partial.lease.removalRequests.isEmpty, "A partial result cannot remove the file")
    coordinator.importPasswordFile(file)
    let complete = PCNativeBrowserApplication.passwordRequests.removeFirst()
    complete.complete(.init(outcome: .completed, importedCount: 3, existingCount: 2, canRemoveSourceFile: true))
    expect(coordinator.canRemovePasswordFile && complete.lease.removalRequests.isEmpty,
           "Confirmed success merely permits a later explicit removal decision")
    coordinator.removePasswordFile(); coordinator.removePasswordFile()
    expect(complete.lease.removalRequests.count == 1 && coordinator.removingPasswordFile,
           "One explicit consent sends one original-lease removal request")
    coordinator.continueAfterPasswords()
    expect(coordinator.stage == .safariPasswords, "The owned removal must finish before continuing")
    complete.lease.removalRequests[0](NSError(domain: "fixture", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "The original file changed."]))
    expect(!coordinator.passwordFileRemoved && coordinator.passwordError == "The original file changed.",
           "Removal failure never claims the source was removed")
    coordinator.removePasswordFile()
    expect(complete.lease.removalRequests.count == 2, "A new explicit consent may retry a recoverable removal failure")
    complete.lease.removalRequests[1](nil)
    expect(coordinator.passwordFileRemoved && !coordinator.canRemovePasswordFile,
           "Only actual native success reports file removal")
    coordinator.continueAfterPasswords()
    expect(coordinator.stage == .finished && complete.lease.cancelled && coordinator.passwordRequestID == nil,
           "Continue revokes the file lease and enters actual import completion")
    complete.complete(.init(outcome: .failed))
    expect(coordinator.stage == .finished, "A late callback cannot reopen the finished stage")
    coordinator.cancel()

    let refused = make()
    PCNativeBrowserApplication.rejectsPasswordImport = true
    refused.importPasswordFile(file)
    expect(!refused.importingPasswords && refused.passwordError != nil && refused.canImportPasswordFile,
           "Immediate native refusal leaves an actionable stage without fabricated success")
    PCNativeBrowserApplication.rejectsPasswordImport = false
    refused.importPasswordFile(file)
    let losing = PCNativeBrowserApplication.passwordRequests.removeFirst()
    current = false; losing.complete(.init(outcome: .completed, importedCount: 3, canRemoveSourceFile: true))
    expect(refused.passwordResult == nil && !refused.canRemovePasswordFile,
           "Lost original ownership cannot publish a result or authorize removal")
    refused.cancel(); current = true
    losing.complete(.init(outcome: .completed, importedCount: 3, canRemoveSourceFile: true))
    expect(losing.lease.cancelled && refused.stage == .finished && refused.passwordResult == nil,
           "Close cancels the original session and rejects later completion")

    let skipped = make()
    skipped.continueAfterPasswords()
    expect(skipped.stage == .finished && PCNativeBrowserApplication.passwordRequests.isEmpty,
           "Skip reads no password file")
    expect(store.state.profiles == before.profiles && store.state.spaces == before.spaces && store.state.tabs == before.tabs,
           "Existing-profile password guidance and aggregate callbacks do not mutate sidebar/session models")
    skipped.cancel()
    let ordinary = BrowserImportCoordinator(store: store, destination: destination, window: window, ownerIsCurrent: { current })
    ordinary.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([safari])
    ordinary.select(safari); ordinary.loadProfiles()
    let profile = PCNativeImportProfile("original Safari", [.history], .complete)
    PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
    PCNativeBrowserApplication.acceptsBrowserImport = true; ordinary.continueSourceInline()
    expect(ordinary.stage == .safariPasswords && ordinary.hasBackgroundWork && PCNativeBrowserApplication.browserCompletions.isEmpty
           && ordinary.passwordDestination?.profileID == destination.profileID,
           "Safari offers its password file at once; its data waits so the file has the Profile to itself")
    let safariFile = URL(fileURLWithPath: "/fixture/Passwords.csv")
    ordinary.importPasswordFile(safariFile)
    let safariPasswords = PCNativeBrowserApplication.passwordRequests.removeFirst()
    expect(safariPasswords.path == store.independentEngineProfilePath(for: destination.profileID) && PCNativeBrowserApplication.browserCompletions.isEmpty,
           "The password file imports straight away, before Safari's history")
    safariPasswords.complete(.init(outcome: .completed, importedCount: 3))
    ordinary.continueAfterPasswords()
    expect(ordinary.stage == .finished && ordinary.hasBackgroundWork && PCNativeBrowserApplication.browserCompletions.count == 1,
           "Leaving the password step starts Safari's history in the background")
    expect(PCNativeBrowserApplication.browserRequests.last?.skipExistingCookies == true,
           "Importing into the opened Profile keeps its existing cookies")
    PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
    expect(!ordinary.hasBackgroundWork && PCNativeBrowserApplication.passwordRequests.isEmpty,
           "History finishing ends the background import")
    ordinary.cancel()
    let closing = BrowserImportCoordinator(store: store, destination: destination, window: window, ownerIsCurrent: { current })
    closing.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([safari])
    closing.select(safari); closing.loadProfiles()
    PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
    closing.continueSourceInline()
    closing.importPasswordFile(safariFile)
    let midFile = PCNativeBrowserApplication.passwordRequests.removeFirst()
    closing.detach(onAdBlockers: nil)
    expect(PCNativeBrowserApplication.browserCompletions.isEmpty, "Closing mid-file leaves history waiting for the file")
    midFile.complete(.init(outcome: .cancelled, importedCount: 0))
    expect(PCNativeBrowserApplication.browserCompletions.count == 1 && closing.hasBackgroundWork,
           "Once the file ends, the closed import still brings Safari's history in")
    let following = BrowserImportCoordinator(store: store, destination: destination, window: window, ownerIsCurrent: { current })
    following.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([safari])
    following.select(safari); following.loadProfiles()
    PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
    following.continueSourceInline()
    expect(following.stage == .importing && PCNativeBrowserApplication.browserCompletions.count == 1,
           "A new import waits on the loading button while the last one is still finishing")
    let abandoned = BrowserImportCoordinator(store: store, destination: destination, window: window, ownerIsCurrent: { current })
    abandoned.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([safari])
    abandoned.select(safari); abandoned.loadProfiles()
    PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
    abandoned.continueSourceInline(); abandoned.stopImport()
    expect(abandoned.stage == .finished, "Stop Import ends a waiting import at once")
    PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
    expect(!closing.hasBackgroundWork, "The detached import is released when its history is in")
    expect(following.stage == .safariPasswords && following.passwordDestination?.profileID == destination.profileID,
           "The waiting import then starts by itself")
    expect(abandoned.stage == .finished && PCNativeBrowserApplication.browserCompletions.isEmpty
           && PCNativeBrowserApplication.passwordRequests.isEmpty, "A stopped waiting import never starts later")
    abandoned.cancel()
    following.cancel()
    closing.cancel(); PCNativeBrowserApplication.acceptsBrowserImport = false
    checks += onboardingImportOrderChecks(store: store, destination: destination, window: window, safari: safari)
    checks += setupAccessChecks(store: store, destination: destination, window: window, safari: safari, other: other)
    checks += firefoxPasswordChecks(store: store, destination: destination, window: window)
    checks += try safariExportChecks(window: window, safari: safari)
    return checks
}

@MainActor
private func onboardingImportOrderChecks(store: BrowserStore, destination: BrowserImportDestination,
                                        window: NSWindow, safari: PCNativeImportSource) -> Int {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), message)
    }
    let selected = PCNativeImportedBookmark("selected", title: "Keep", url: URL(string: "https://example.org/setup-keep")!)
    let omitted = PCNativeImportedBookmark("omitted", title: "Leave", url: URL(string: "https://example.org/setup-leave")!)
    PCNativeBrowserApplication.acceptsBrowserImport = true
    defer { PCNativeBrowserApplication.acceptsBrowserImport = false }
    func start(onboarding: Bool = true, iCloudSupported: Bool = false) -> BrowserImportCoordinator {
        let coordinator = BrowserImportCoordinator(store: store, destination: destination,
            window: window, onboarding: onboarding, supportsICloudPasswords: iCloudSupported, ownerIsCurrent: { true })
        PCNativeBrowserApplication.browserCompletions.removeAll()
        coordinator.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([safari])
        if onboarding { coordinator.selectSourceInline(safari) }
        else { coordinator.select(safari); coordinator.loadProfiles() }
        let profile = PCNativeImportProfile("Safari setup", [.history, .bookmarks], .complete)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
        coordinator.continueSourceInline()
        expect(coordinator.stage == .importing, "Selection admits the original source through the real coordinator")
        return coordinator
    }
    func complete(_ bookmarks: [PCNativeImportedBookmark], outcome: PCNativeImportOutcome = .completed) {
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: outcome, bookmarks: bookmarks, warnings: [], error: nil))
        while !PCNativeBrowserApplication.browserCompletions.isEmpty {
            PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        }
    }

    let setup = start(), initialTabs = store.state.tabs
    complete([selected, omitted])
    expect(setup.stage == .bookmarks && !setup.canImportPasswordFile, "Setup shows native bookmark results before Safari password guidance")
    expect(store.state.tabs == initialTabs && PCNativeBrowserApplication.passwordRequests.isEmpty,
           "Showing either choice imports no bookmarks or credentials automatically")
    setup.continueAfterPasswords()
    expect(setup.stage == .bookmarks, "A stale password action cannot skip unaccepted bookmarks")
    expect(setup.bookmarkPages[0].selection.allSelected, "Setup's bookmarks all start ticked")
    setup.toggleBookmark(pageID: setup.bookmarkPages[0].id, id: omitted.identifier)
    let otherSpace = store.createSpace(name: "Another active window")
    store.selectSpace(otherSpace)
    setup.commitBookmarks()
    expect(setup.stage == .safariPasswords && setup.bookmarkPages[0].committed,
           "Accepting selected bookmarks advances to the separate password step")
    expect(PCNativeBrowserApplication.browserCompletions.isEmpty && setup.hasBackgroundWork,
           "Setup's history waits through bookmarks and the password step")
    let imported = store.state.tabs.filter { $0.url == selected.url!.absoluteString }
    expect(imported.count == 1 && imported[0].spaceID == destination.spaceID && imported[0].profileID == destination.profileID,
           "The accepted bookmark retains its original setup destination")
    expect(!store.state.tabs.contains { $0.url == omitted.url!.absoluteString }, "Unselected native bookmarks are left behind")
    expect(setup.passwordDestination == destination && setup.canImportPasswordFile,
           "Password guidance retains that same original Profile after another Space becomes active")
    let acceptedTabs = store.state.tabs
    setup.commitBookmarks()
    expect(store.state.tabs == acceptedTabs && setup.stage == .safariPasswords,
           "A repeated old bookmark action cannot duplicate data or skip passwords")
    setup.continueAfterPasswords()
    expect(setup.stage == .finished && store.state.tabs == acceptedTabs && PCNativeBrowserApplication.passwordRequests.isEmpty,
           "Skipping optional passwords finishes without reopening bookmarks or reading a file")
    expect(PCNativeBrowserApplication.browserCompletions.count == 1, "Leaving setup's password step starts its history")
    setup.cancel()

    let empty = start(); complete([])
    expect(empty.stage == .safariPasswords && empty.bookmarkPages.isEmpty, "No native bookmarks means no empty selection step")
    empty.continueAfterPasswords(); empty.cancel()
    let menu = start(onboarding: false); complete([selected])
    expect(menu.stage == .safariPasswords, "Setup-specific order does not change the dedicated menu wizard")
    menu.continueAfterPasswords()
    expect(menu.stage == .bookmarks, "The menu still offers its unaccepted bookmarks after passwords")
    menu.cancel()
    for outcome: PCNativeImportOutcome in [.completed, .cancelled] {
        let stopped = start(); stopped.stopImport(); complete([selected], outcome: outcome)
        expect(stopped.stage == .bookmarks, "Stopping preserves returned bookmark results even when native completion wins the race")
        stopped.toggleBookmark(pageID: stopped.bookmarkPages[0].id, id: nil)
        stopped.commitBookmarks()
        expect(stopped.stage == .finished && stopped.passwordDestination == nil,
               "Accepting results after Stop cannot start another optional import step")
        stopped.cancel()
    }
    let choice = start(iCloudSupported: true); complete([selected])
    expect(choice.stage == .bookmarks && choice.acceptedICloudPasswordsDestination == nil,
           "The supported iCloud choice still follows actual bookmark selection")
    choice.commitBookmarks()
    expect(choice.stage == .passwordChoice && choice.canChoosePasswordMethod && choice.wantsICloudPasswords && !choice.canImportPasswordFile,
           "Supported setup presents the recommendation before asking for a CSV, without accepting it")
    choice.choosePasswordMethod(installExtension: true)
    expect(choice.wantsICloudPasswords && choice.acceptedICloudPasswordsDestination == nil,
           "Selecting iCloud changes only the pending choice, not its acceptance or destination")
    choice.importPasswordFile(URL(fileURLWithPath: "/fixture/Passwords.csv"))
    expect(PCNativeBrowserApplication.passwordRequests.isEmpty, "A stale upload action cannot import behind the method chooser")
    choice.continueAfterPasswords()
    expect(choice.stage == .passwordChoice, "A stale CSV continuation cannot accept this different choice")
    choice.continuePasswordChoice()
    expect(choice.stage == .finished && choice.acceptedICloudPasswordsDestination == destination,
           "Next accepts only the captured original destination, despite the other active Space")
    expect(PCNativeBrowserApplication.browserCompletions.count == 1, "Choosing iCloud passwords starts Safari's history")
    expect(choice.passwordDestination == nil && !choice.canImportPasswordFile,
           "Choosing the extension omits manual file import")
    choice.choosePasswordMethod(installExtension: false); choice.continuePasswordChoice()
    expect(choice.acceptedICloudPasswordsDestination == destination,
           "A stale row or repeated Next cannot replace the accepted choice")
    choice.cancel()
    expect(choice.acceptedICloudPasswordsDestination == nil, "A cancelled importer cannot supply installation authorization")

    let manual = start(iCloudSupported: true); complete([])
    manual.choosePasswordMethod(installExtension: true); manual.choosePasswordMethod(installExtension: false)
    manual.continuePasswordChoice()
    expect(manual.stage == .safariPasswords && manual.canImportPasswordFile && manual.acceptedICloudPasswordsDestination == nil,
           "Changing back to Manual reaches the real CSV owner without accepting an extension")
    manual.continueAfterPasswords()
    expect(manual.stage == .finished && manual.acceptedICloudPasswordsDestination == nil,
           "Completing Manual cannot install the unselected extension")
    manual.cancel()
    let unchangedMenu = start(onboarding: false, iCloudSupported: true); complete([])
    expect(unchangedMenu.stage == .safariPasswords && !unchangedMenu.canChoosePasswordMethod,
           "OS availability does not add onboarding-only choices to the menu wizard")
    expect(unchangedMenu.setupSkipTitle == nil && !unchangedMenu.canGoBackInSetup,
           "The menu wizard keeps its own buttons")
    unchangedMenu.cancel()

    let skipping = start(); complete([selected, omitted])
    expect(skipping.setupSkipTitle == "Skip for now" && skipping.canGoBackInSetup, "The bookmark picker offers Skip for now and Back")
    let tabsBeforeSkip = store.state.tabs
    skipping.skipInSetup()
    expect(skipping.stage == .safariPasswords && store.state.tabs == tabsBeforeSkip,
           "Skip on bookmarks goes on to Stay logged in without adding bookmarks")
    expect(skipping.setupSkipTitle == "Do this later" && !skipping.canContinueSetupPasswords,
           "Stay logged in offers Do this later and holds Next until a file imports")
    skipping.importPasswordFile(URL(fileURLWithPath: "/fixture/Passwords.csv"))
    let failedFile = PCNativeBrowserApplication.passwordRequests.removeFirst()
    expect(skipping.setupSkipTitle == "Do this later" && !skipping.canSkipInSetup && !skipping.canGoBackInSetup,
           "While a file imports, Do this later stays but waits, and Back is hidden")
    failedFile.complete(.init(outcome: .failed))
    expect(!skipping.canContinueSetupPasswords && skipping.setupSkipTitle == "Do this later",
           "A failed file leaves Next disabled and Do this later in place")
    skipping.goBackInSetup()
    expect(skipping.stage == .bookmarks && !skipping.bookmarkPages[0].skipped && !skipping.bookmarkPages[0].committed,
           "Back from Stay logged in returns to the skipped bookmarks, offered again")
    func keptCount() -> Int { store.state.tabs.filter { $0.url == selected.url!.absoluteString }.count }
    let keptBefore = keptCount()
    skipping.commitBookmarks()
    expect(skipping.stage == .safariPasswords && keptCount() == keptBefore + 1,
           "Adding them after Back adds each once and returns to Stay logged in")
    skipping.importPasswordFile(URL(fileURLWithPath: "/fixture/Passwords.csv"))
    PCNativeBrowserApplication.passwordRequests.removeFirst().complete(.init(outcome: .completed, importedCount: 2))
    expect(skipping.canContinueSetupPasswords && skipping.setupSkipTitle == nil,
           "Once a file imports, Next is enabled and Do this later goes away")
    skipping.goBackInSetup()
    let tabsAfterAdd = store.state.tabs
    let earlierTabs = Set(tabsBeforeSkip.map(\.id))
    func tabs(_ bookmark: PCNativeImportedBookmark) -> [BrowserTab] {
        store.state.tabs.filter { $0.url == bookmark.url!.absoluteString && !earlierTabs.contains($0.id) }
    }
    expect(skipping.stage == .bookmarks && skipping.bookmarkPages[0].committed, "Back shows the bookmarks already added")
    let accepted = skipping.bookmarkPages[0], keptTab = tabs(selected)[0]
    expect(skipping.canChooseBookmarks(accepted) && accepted.selection.selected == [selected.identifier, omitted.identifier],
           "The page already added keeps its ticks and stays editable")
    skipping.toggleBookmark(pageID: accepted.id, id: omitted.identifier)
    expect(store.state.tabs == tabsAfterAdd, "Changing a tick adds or removes nothing before Next")
    skipping.commitBookmarks()
    expect(skipping.stage == .safariPasswords && skipping.canContinueSetupPasswords
               && tabs(omitted).isEmpty && tabs(selected) == [keptTab] && store.state.tabs.count == tabsAfterAdd.count - 1,
           "Next removes just the unticked bookmark and keeps the other in place, passwords kept")
    skipping.goBackInSetup()
    skipping.toggleBookmark(pageID: accepted.id, id: omitted.identifier)
    skipping.commitBookmarks()
    let reticked = store.state.tabs
    expect(tabs(omitted).count == 1 && tabs(selected) == [keptTab] && reticked.count == tabsAfterAdd.count,
           "Ticking it again after Back adds it once")
    skipping.goBackInSetup()
    skipping.toggleBookmark(pageID: accepted.id, id: selected.identifier)
    skipping.skipInSetup()
    expect(skipping.stage == .safariPasswords && skipping.canContinueSetupPasswords && store.state.tabs == reticked,
           "Skip on the page already added keeps what it added")
    skipping.goBackInSetup()
    expect(skipping.bookmarkPages[0].selection.selected == [selected.identifier, omitted.identifier],
           "After Skip, the page's ticks again show what it added")
    for _ in 0..<3 { skipping.commitBookmarks(); skipping.goBackInSetup() }
    expect(store.state.tabs == reticked && skipping.stage == .bookmarks, "Back and Next loops add nothing twice")

    skipping.toggleBookmark(pageID: accepted.id, id: selected.identifier)
    let session = store.directory.appendingPathComponent("session.json")
    let backup = store.directory.appendingPathComponent("prior-session.json")
    try? FileManager.default.moveItem(at: session, to: backup)
    try? FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
    skipping.commitBookmarks()
    expect(skipping.stage == .bookmarks && skipping.error != nil && store.state.tabs == reticked
               && skipping.bookmarkPages[0].selection.selected == [omitted.identifier],
           "A failed save leaves the previous accepted set and the page as edited")
    try? FileManager.default.removeItem(at: session)
    try? FileManager.default.moveItem(at: backup, to: session)
    skipping.commitBookmarks()
    expect(skipping.stage == .safariPasswords && tabs(selected).isEmpty && tabs(omitted).count == 1,
           "Next after the failure applies the edit once")
    skipping.goBackInSetup()
    skipping.toggleBookmark(pageID: accepted.id, id: selected.identifier)
    skipping.commitBookmarks()
    let restoredSet = store.state.tabs
    expect(tabs(selected).count == 1 && tabs(omitted).count == 1, "Both are back, once each")
    skipping.goBackInSetup()
    skipping.skipInSetup()
    expect(skipping.stage == .safariPasswords && skipping.canContinueSetupPasswords && store.state.tabs == restoredSet,
           "Going forward again keeps the imported passwords and adds nothing twice")
    skipping.skipInSetup()
    expect(skipping.stage == .safariPasswords, "A completed file leaves no Do this later to press")
    skipping.continueAfterPasswords()
    expect(skipping.stage == .finished, "Next finishes the import")
    skipping.cancel()

    let declined = start(iCloudSupported: true); complete([])
    expect(declined.stage == .passwordChoice && declined.setupSkipTitle == "Skip for now", "The password choice offers Skip for now")
    declined.choosePasswordMethod(installExtension: false); declined.continuePasswordChoice()
    declined.goBackInSetup()
    expect(declined.stage == .passwordChoice && !declined.wantsICloudPasswords,
           "Back from Stay logged in returns to the choice the user made")
    declined.choosePasswordMethod(installExtension: true)
    declined.skipInSetup()
    expect(declined.stage == .finished && declined.acceptedICloudPasswordsDestination == nil && declined.passwordDestination == nil,
           "Skip on the password choice finishes without the iCloud Passwords extension or a file")
    declined.cancel()

    let returning = start(); let importsBefore = PCNativeBrowserApplication.imports; complete([selected])
    returning.goBackInSetup()
    expect(returning.stage == .profiles && returning.parkedStage == .bookmarks && returning.source === safari
               && returning.canContinueSourceInline && !returning.canGoBackInSetup && returning.setupSkipTitle == nil,
           "Back from bookmarks shows the browser cards with Safari still chosen")
    returning.selectSourceInline(safari); returning.clearSourceInline()
    expect(returning.source === safari && returning.parkedStage == .bookmarks, "The imported browser's choice can't be undone in place")
    returning.continueSourceInline()
    expect(returning.stage == .bookmarks && returning.bookmarkPages.count == 1 && PCNativeBrowserApplication.imports == importsBefore,
           "Next on the same browser returns to its bookmarks without importing again")
    returning.cancel()

    let favorites = start(iCloudSupported: true)
    expect(favorites.hasStartedImportInSetup && !favorites.isRestingInSetup && favorites.setupBackReturnsToSource,
           "A running import has started, waits on no page yet and has no import page behind it")
    expect(!favorites.returnToSourceInSetup() && favorites.stage == .importing,
           "Stepping back to the browser choice leaves a running import running")
    complete([selected])
    expect(favorites.stage == .bookmarks && favorites.isRestingInSetup && favorites.setupBackReturnsToSource,
           "Once read, the import waits on its bookmarks, whose Back leaves the import's pages")
    let importsBeforeReturn = PCNativeBrowserApplication.imports
    expect(favorites.returnToSourceInSetup() && favorites.stage == .profiles && favorites.parkedStage == .bookmarks
               && favorites.source === safari && favorites.hasStartedImportInSetup && !favorites.isRestingInSetup,
           "Back from Favorites shows the browser choice with Safari still chosen and its results kept")
    favorites.continueSourceInline()
    expect(favorites.stage == .bookmarks && favorites.bookmarkPages.count == 1
               && PCNativeBrowserApplication.imports == importsBeforeReturn,
           "Coming forward through Favorites again shows the same bookmarks without importing twice")
    favorites.commitBookmarks()
    expect(favorites.stage == .passwordChoice && !favorites.setupBackReturnsToSource,
           "With bookmarks behind it, Back from the password choice stays on the import's pages")
    favorites.choosePasswordMethod(installExtension: false)
    expect(favorites.returnToSourceInSetup() && favorites.parkedStage == .passwordChoice,
           "Returning to the browser choice from the password choice keeps that page waiting")
    favorites.continueSourceInline()
    expect(favorites.stage == .passwordChoice && !favorites.wantsICloudPasswords,
           "The waiting password choice comes back as it was left")
    favorites.continuePasswordChoice()
    expect(favorites.stage == .safariPasswords && !favorites.setupBackReturnsToSource,
           "Back from Stay logged in returns to the password choice")
    favorites.cancel()

    let unmarked = start(); complete([])
    expect(unmarked.stage == .safariPasswords && unmarked.setupBackReturnsToSource && unmarked.isRestingInSetup,
           "Without bookmarks or the iCloud choice, Back from Stay logged in leaves the import's pages")
    unmarked.importPasswordFile(URL(fileURLWithPath: "/fixture/Passwords.csv"))
    let unmarkedFile = PCNativeBrowserApplication.passwordRequests.removeFirst()
    expect(!unmarked.returnToSourceInSetup() && unmarked.stage == .safariPasswords && unmarked.parkedStage == nil,
           "A password file still importing keeps Stay logged in in place")
    unmarkedFile.complete(.init(outcome: .completed, importedCount: 1))
    expect(unmarked.returnToSourceInSetup() && unmarked.parkedStage == .safariPasswords && unmarked.passwordImportCompleted,
           "Once the file is in, Stay logged in waits behind the browser choice with its result kept")
    unmarked.continueSourceInline()
    expect(unmarked.stage == .safariPasswords && unmarked.canContinueSetupPasswords,
           "Coming back through Favorites shows the imported file, ready for Next")
    unmarked.cancel()
    return checks
}

@MainActor
func setupAccessChecks(store: BrowserStore, destination: BrowserImportDestination,
                       window: NSWindow, safari: PCNativeImportSource, other: PCNativeImportSource) -> Int {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), message)
    }
    let restricted = PCNativeImportProfileResult(profiles: [PCNativeImportProfile("Locked", [], .restricted)], access: .restricted)
    func access(_ source: PCNativeImportSource) -> BrowserImportCoordinator {
        let coordinator = BrowserImportCoordinator(store: store, destination: destination, window: window,
            onboarding: true, supportsICloudPasswords: false, ownerIsCurrent: { true })
        coordinator.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([safari, other])
        coordinator.selectSourceInline(source)
        PCNativeBrowserApplication.profiles.removeFirst().complete(restricted)
        coordinator.continueSourceInline()
        return coordinator
    }
    let back = access(safari)
    expect(back.stage == .safariAccess && back.setupSkipTitle == "Do this later" && back.canGoBackInSetup,
           "The Safari access page offers Do this later and Back")
    back.continueSafariWithoutRestarting()
    let pending = PCNativeBrowserApplication.profiles.removeFirst()
    back.goBackInSetup()
    expect(back.stage == .profiles && back.source === safari && back.canContinueSourceInline && pending.lease.cancelled,
           "Back returns to the browser cards with Safari still chosen and stops the access check")
    pending.complete(.init(profiles: [PCNativeImportProfile("Safari", [.history, .bookmarks], .complete)], access: .complete))
    expect(back.stage == .profiles, "A late access check can't move the cards on")
    back.continueSourceInline()
    expect(back.stage == .safariAccess, "Next on the same browser comes back to its access page")
    back.cancel()

    let safariLater = access(safari)
    safariLater.skipInSetup()
    PCNativeBrowserApplication.profiles.removeFirst().complete(restricted)
    expect(safariLater.stage == .safariPasswords && safariLater.passwordDestination == destination,
           "Do this later on Safari still offers its password file, which needs no Full Disk Access")
    safariLater.goBackInSetup()
    expect(safariLater.stage == .safariAccess && safariLater.passwordDestination == nil,
           "Back from Stay logged in returns to the access page that was put off")
    safariLater.cancel()

    let returning = access(safari)
    returning.skipInSetup()
    PCNativeBrowserApplication.profiles.removeFirst().complete(restricted)
    expect(returning.hasStartedImportInSetup && returning.setupBackReturnsToSource,
           "Safari's password page after Do this later counts as a started import")
    expect(returning.returnToSourceInSetup() && returning.stage == .safariAccess
               && !returning.hasStartedImportInSetup && returning.passwordDestination == nil,
           "Back from Favorites returns to the access page that came before it")
    returning.cancel()

    let otherLater = access(other)
    otherLater.skipInSetup()
    PCNativeBrowserApplication.profiles.removeFirst().complete(restricted)
    expect(otherLater.stage == .finished && PCNativeBrowserApplication.passwordRequests.isEmpty,
           "Do this later on another browser with nothing readable ends the import")
    otherLater.cancel()

    let otherNext = access(other), importsBeforeNext = PCNativeBrowserApplication.imports
    otherNext.continueSafariWithoutRestarting()
    PCNativeBrowserApplication.profiles.removeFirst().complete(restricted)
    expect(otherNext.stage == .finished && PCNativeBrowserApplication.passwordRequests.isEmpty
               && PCNativeBrowserApplication.imports == importsBeforeNext,
           "Next on another browser with nothing readable ends the import, as Do this later does")
    otherNext.cancel()

    let none = BrowserImportCoordinator(store: store, destination: destination, window: window,
        onboarding: true, ownerIsCurrent: { true })
    none.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([])
    expect(none.stage == .finished && none.foundNoSources, "Setup leaves its import step out when no browser is found")
    none.cancel()
    return checks
}
