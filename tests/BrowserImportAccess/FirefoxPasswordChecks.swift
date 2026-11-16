import AppKit

@MainActor
func firefoxPasswordChecks(store: BrowserStore, destination: BrowserImportDestination, window: NSWindow) -> Int {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), message)
    }
    let firefox = PCNativeImportSource("org.mozilla.firefox", URL(fileURLWithPath: "/fixture/Firefox.app"))
    expect(BrowserImportCoordinator.passwordExport(for: firefox) == .firefox,
           "Firefox is recognised by its bundle identifier for the password file step")
    let zen = PCNativeImportSource("app.zen-browser.zen", URL(fileURLWithPath: "/fixture/Zen.app"))
    expect(BrowserImportCoordinator.passwordExport(for: zen) == .zen
           && BrowserPasswordExport.zen.wrongFileMessage == "Choose the passwords.csv file exported by Zen.",
           "Zen, built on Firefox, gets the same password file step with its own name")
    expect(BrowserImportCoordinator.keychainNote(for: zen) == nil && BrowserImportCoordinator.keychainNote(for: firefox) == nil,
           "Firefox-family imports never mention a Chromium Keychain key")
    PCNativeBrowserApplication.acceptsBrowserImport = true
    defer { PCNativeBrowserApplication.acceptsBrowserImport = false }
    func start(onboarding: Bool, source chosen: PCNativeImportSource? = nil) -> BrowserImportCoordinator {
        let source = chosen ?? firefox
        let coordinator = BrowserImportCoordinator(store: store, destination: destination, window: window,
            onboarding: onboarding, supportsICloudPasswords: true, ownerIsCurrent: { true })
        PCNativeBrowserApplication.browserCompletions.removeAll()
        coordinator.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([source])
        if onboarding { coordinator.selectSourceInline(source) }
        else { coordinator.select(source); coordinator.loadProfiles() }
        let profile = PCNativeImportProfile("default-release", [.history, .bookmarks], .complete, name: "Firefox")
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
        coordinator.continueSourceInline()
        return coordinator
    }
    func complete(_ bookmarks: [PCNativeImportedBookmark]) {
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: bookmarks, warnings: [], error: nil))
    }

    let setup = start(onboarding: true)
    expect(setup.setupPage == .progress && setup.setupPagesAhead == [.bookmarks, .passwordFile],
           "While Firefox reads, setup expects its bookmarks and its password file")
    complete([PCNativeImportedBookmark("kept", title: "Kept", url: URL(string: "https://example.org/firefox-kept")!)])
    expect(setup.setupPage == .bookmarks && setup.setupPagesAhead == [.passwordFile],
           "Firefox's password file stays ahead of its bookmarks page")
    expect(setup.stage == .bookmarks && setup.passwordDestination == destination,
           "Setup keeps Firefox's bookmarks first and holds the original Profile for its password file")
    setup.commitBookmarks()
    expect(setup.stage == .safariPasswords && !setup.offersICloudPasswordChoice && !setup.wantsICloudPasswords,
           "Firefox goes straight to its password file, never Safari's iCloud Passwords choice")
    expect(setup.passwordExport == .firefox && setup.canImportPasswordFile
           && setup.message == "Import your exported Firefox passwords.",
           "The password file step knows it is helping with a Firefox export")
    expect(setup.hasBackgroundWork && PCNativeBrowserApplication.browserCompletions.isEmpty,
           "Firefox's history waits so the password file has the Profile to itself")
    setup.importPasswordFile(URL(fileURLWithPath: "/fixture/passwords.txt"))
    expect(PCNativeBrowserApplication.passwordRequests.isEmpty
           && setup.passwordError == "Choose the passwords.csv file exported by Firefox.",
           "A wrong file is refused with Firefox's own file name")
    setup.goBackInSetup()
    expect(setup.stage == .bookmarks, "Back from Firefox's password file returns to its bookmarks")
    setup.commitBookmarks()
    expect(setup.stage == .safariPasswords, "Accepting the bookmarks again returns to the password file")
    let file = URL(fileURLWithPath: "/fixture/passwords.csv")
    setup.importPasswordFile(file)
    let request = PCNativeBrowserApplication.passwordRequests.removeFirst()
    expect(request.url == file && request.path == store.independentEngineProfilePath(for: destination.profileID),
           "Firefox's export goes to the original Profile through the same native password importer")
    request.complete(.init(outcome: .completed, importedCount: 4, canRemoveSourceFile: true))
    expect(setup.canContinueSetupPasswords && setup.canRemovePasswordFile,
           "A confirmed Firefox import can continue and offer to move the export to the Trash")
    setup.continueAfterPasswords()
    expect(setup.stage == .finished && PCNativeBrowserApplication.browserCompletions.count == 1,
           "Leaving the password file starts Firefox's history")
    setup.cancel()

    let empty = start(onboarding: true); complete([])
    expect(empty.stage == .safariPasswords && empty.setupBackReturnsToSource,
           "With no bookmarks Firefox's password file is the first page and Back returns to the browser choice")
    expect(empty.setupPage == .passwordFile && empty.setupPagesAhead.isEmpty,
           "Without bookmarks the password file is the only import page counted")
    empty.goBackInSetup()
    expect(empty.stage == .profiles && empty.parkedStage == .safariPasswords,
           "Back parks Firefox's password file behind the browser cards")
    empty.continueSourceInline()
    expect(empty.stage == .safariPasswords && empty.parkedStage == nil, "Next returns to the parked password file")
    empty.cancel()

    let menu = start(onboarding: false); complete([])
    expect(menu.stage == .safariPasswords && !menu.canChoosePasswordMethod,
           "The menu import offers Firefox's password file too")
    menu.continueAfterPasswords()
    expect(menu.stage == .finished && PCNativeBrowserApplication.passwordRequests.isEmpty,
           "Skipping Firefox's passwords reads no file")
    menu.cancel()
    PCNativeBrowserApplication.browserCompletions.removeAll()
    let ordered = start(onboarding: false)
    complete([PCNativeImportedBookmark("menu", title: "Menu", url: URL(string: "https://example.org/firefox-menu")!)])
    expect(ordered.stage == .safariPasswords, "The menu import asks for Firefox's password file before its bookmarks")
    ordered.continueAfterPasswords()
    expect(ordered.stage == .bookmarks, "Firefox's bookmarks follow the password file in the menu import")
    ordered.cancel()
    PCNativeBrowserApplication.browserCompletions.removeAll()

    let locked = BrowserImportCoordinator(store: store, destination: destination, window: window,
        onboarding: true, supportsICloudPasswords: true, ownerIsCurrent: { true })
    locked.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([firefox])
    locked.selectSourceInline(firefox)
    let unreadable = PCNativeImportProfileResult(profiles: [PCNativeImportProfile("locked", [], .restricted)], access: .restricted)
    PCNativeBrowserApplication.profiles.removeFirst().complete(unreadable)
    locked.continueSourceInline()
    expect(locked.stage == .safariAccess, "Firefox files macOS withholds lead to the access page")
    locked.continueSafariWithoutRestarting()
    PCNativeBrowserApplication.profiles.removeFirst().complete(unreadable)
    expect(locked.stage == .safariPasswords && locked.passwordDestination == destination && !locked.offersICloudPasswordChoice,
           "Continuing with nothing readable still offers Firefox's password file, which needs no extra access")
    locked.goBackInSetup()
    expect(locked.stage == .safariAccess, "Back from that password file returns to the access page")
    locked.cancel()
    PCNativeBrowserApplication.browserCompletions.removeAll()

    let zenSetup = start(onboarding: true, source: zen)
    expect(zenSetup.setupPage == .progress && zenSetup.setupPagesAhead == [.bookmarks, .passwordFile],
           "Zen counts the same bookmarks and password file pages as Firefox")
    zenSetup.cancel()
    PCNativeBrowserApplication.browserCompletions.removeAll()
    return checks
}
