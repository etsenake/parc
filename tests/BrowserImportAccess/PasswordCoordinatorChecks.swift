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
    func make(_ source: PCNativeImportSource = safari) -> BrowserImportCoordinator {
        let coordinator = BrowserImportCoordinator(store: store, destination: destination,
            window: window, ownerIsCurrent: { current })
        coordinator.discover()
        PCNativeBrowserApplication.sources.removeFirst().complete([source])
        coordinator.select(source); coordinator.loadProfiles()
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [], access: .restricted))
        if coordinator.stage == .safariAccess {
            coordinator.continueSafariWithoutRestarting()
            PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [], access: .restricted))
        }
        return coordinator
    }
    let wrongSource = make(other)
    expect(!wrongSource.canChoosePasswordDestination, "A display name cannot expose Safari CSV guidance")
    wrongSource.choosePasswordDestination()
    expect(wrongSource.stage == .profiles, "An unrelated source cannot enter this password stage")
    wrongSource.cancel()
    let coordinator = make()
    let before = store.state
    expect(coordinator.canChoosePasswordDestination && !coordinator.canChooseDestination,
           "Explicit exported credentials do not require Safari history/profile access")
    coordinator.choosePasswordDestination()
    expect(coordinator.passwordsOnly && coordinator.stage == .destination && !coordinator.canStart,
           "The file route requires a separate explicit destination")
    expect(!coordinator.destinationChoice.replaceExistingCookies, "The file route does not replace cookies")
    guard let target = coordinator.profileTargets.first(where: { $0.profileID == destination.profileID }) else { fatalError("Missing fixture destination") }
    coordinator.selectDestination(.existing(target))
    expect(coordinator.canStart, "An original existing destination can admit the file stage")
    expect(store.state.profiles == before.profiles && store.state.spaces == before.spaces,
           "Choosing the existing destination writes no Profile or Space")
    coordinator.start()
    expect(coordinator.stage == .safariPasswords && coordinator.canImportPasswordFile,
           "The file route has its own real password stage")
    expect(coordinator.passwordDestination?.profileID == destination.profileID,
           "The password stage holds the explicit original destination identity")
    expect(PCNativeBrowserApplication.imports == 0 && PCNativeBrowserApplication.passwordRequests.isEmpty,
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

    let refused = make(); refused.choosePasswordDestination(); refused.selectDestination(.existing(target)); refused.start()
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

    let skipped = make(); skipped.choosePasswordDestination(); skipped.selectDestination(.existing(target)); skipped.start()
    skipped.continueAfterPasswords()
    expect(skipped.stage == .finished && PCNativeBrowserApplication.passwordRequests.isEmpty,
           "Skip needs no file access and never invokes native import")
    expect(store.state.profiles == before.profiles && store.state.spaces == before.spaces && store.state.tabs == before.tabs,
           "Existing-profile password guidance and aggregate callbacks do not mutate sidebar/session models")
    skipped.cancel()
    let ordinary = BrowserImportCoordinator(store: store, destination: destination, window: window, ownerIsCurrent: { current })
    ordinary.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([safari])
    ordinary.select(safari); ordinary.loadProfiles()
    let profile = PCNativeImportProfile("original Safari", [.history], .complete)
    PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
    ordinary.chooseDestination(); ordinary.selectDestination(.existing(target))
    PCNativeBrowserApplication.acceptsBrowserImport = true; ordinary.start()
    expect(ordinary.stage == .importing && !ordinary.hasBackgroundWork && PCNativeBrowserApplication.browserCompletions.count == 1,
           "Safari imports whole in the foreground, so its password file can use the same destination next")
    PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
    expect(ordinary.stage == .safariPasswords && ordinary.passwordDestination?.profileID == target.profileID,
           "Actual source completion then offers optional exported passwords to the same durable destination")
    ordinary.continueAfterPasswords()
    expect(ordinary.stage == .finished && PCNativeBrowserApplication.passwordRequests.isEmpty,
           "The optional post-import file stage can be skipped without another native data operation")
    ordinary.cancel(); PCNativeBrowserApplication.acceptsBrowserImport = false
    checks += onboardingImportOrderChecks(store: store, destination: destination, window: window, safari: safari)
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
        coordinator.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([safari])
        if onboarding { coordinator.selectSourceInline(safari) }
        else { coordinator.select(safari); coordinator.loadProfiles() }
        let profile = PCNativeImportProfile("Safari setup", [.history, .bookmarks], .complete)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
        if onboarding { coordinator.continueSourceInline() }
        else {
            coordinator.chooseDestination()
            coordinator.selectDestination(.existing(.init(profileID: destination.profileID, spaceID: destination.spaceID)))
            coordinator.start()
        }
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
    unchangedMenu.cancel()
    return checks
}
