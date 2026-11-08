import AppKit

@main struct BrowserImportAccessTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(condition(), message)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        func app(_ name: String, _ bundleID: String) throws -> URL {
            let url = directory.appendingPathComponent(name + ".app")
            try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundleID,
                "CFBundleName": name, "CFBundlePackageType": "APPL"], format: .xml, options: 0)
            try plist.write(to: url.appendingPathComponent("Contents/Info.plist")); return url
        }
        let safariURL = try app("Fixture Safari", "com.apple.Safari")
        let otherURL = try app("Safari", "test.not-safari")
        let safari = PCNativeImportSource("fresh Safari lease", safariURL)
        let impostor = PCNativeImportSource("Safari", otherURL)
        expect(BrowserImportCoordinator.isSafari(safari), "Safari is attributed by the actual app bundle")
        expect(!BrowserImportCoordinator.isSafari(impostor), "Display names do not select Safari")
        let store = try BrowserStore(directory: directory.appendingPathComponent("Parc"))
        let destination = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
        let original = store.state
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        var current = true
        let coordinator = BrowserImportCoordinator(store: store, destination: destination, window: window, ownerIsCurrent: { current })
        let partial = PCNativeImportProfile("partial", [.bookmarks], .restricted)
        let complete = PCNativeImportProfile("complete", [.history, .bookmarks], .complete)
        let restricted = PCNativeImportProfileResult(profiles: [partial], access: .restricted)
        let granted = PCNativeImportProfileResult(profiles: [complete], access: .complete)
        coordinator.discover()
        let old = PCNativeBrowserApplication.sources.removeFirst()
        coordinator.discover(resumingSourceBundleID: "com.apple.Safari")
        expect(old.lease.cancelled, "Resume cancels ordinary discovery")
        old.complete([impostor])
        expect(coordinator.stage == .loading && coordinator.sources.isEmpty, "An old source callback cannot replace restart discovery")
        PCNativeBrowserApplication.sources.removeFirst().complete([impostor, safari])
        let selected = PCNativeBrowserApplication.profiles.removeFirst()
        expect(selected.source === safari, "Resume obtains the actual newly discovered Safari token")
        selected.complete(restricted)
        expect(coordinator.stage == .safariAccess, "Restricted Safari appears before any destination selection")
        expect(!coordinator.safariAccessReady && !coordinator.beginSafariRestart(), "Unreadable history cannot enable Restart")
        expect(coordinator.destinationChoice.option == nil, "Access guidance never picks a destination")
        coordinator.refreshSafariAccess(); coordinator.refreshSafariAccess()
        expect(PCNativeBrowserApplication.profiles.count == 1, "Repeated polling has only one outstanding discovery")
        let first = PCNativeBrowserApplication.profiles.removeFirst()
        first.complete(.init(profiles: [complete], access: .restricted))
        expect(!coordinator.safariAccessReady, "A partial aggregate result is not permission success")
        coordinator.refreshSafariAccess()
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [partial], access: .complete))
        expect(!coordinator.safariAccessReady, "No readable History capability means Restart remains disabled")
        coordinator.refreshSafariAccess()
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [complete], access: .complete,
            error: NSError(domain: "fixture", code: 1)))
        expect(!coordinator.safariAccessReady, "A failed discovery cannot enable Restart")
        coordinator.refreshSafariAccess()
        PCNativeBrowserApplication.profiles.removeFirst().complete(granted)
        expect(coordinator.safariAccessReady && coordinator.stage == .safariAccess, "Readiness does not auto-advance")
        expect(coordinator.beginSafariRestart(), "Ready Safari starts one owned restart request")
        expect(!coordinator.beginSafariRestart(), "A duplicate Restart is rejected")
        coordinator.refreshSafariAccess(); coordinator.continueSafariWithoutRestarting()
        expect(PCNativeBrowserApplication.profiles.isEmpty && coordinator.restarting, "Restart owns the stage; polling and Continue cannot race it")
        coordinator.safariRestartFailed("Quit was cancelled.")
        expect(!coordinator.restarting && coordinator.safariAccessError == "Quit was cancelled.", "Refused shutdown restores the original guidance")
        coordinator.refreshSafariAccess()
        PCNativeBrowserApplication.profiles.removeFirst().complete(granted)
        expect(coordinator.safariAccessError == "Quit was cancelled.", "Polling does not erase the actionable restart failure")
        coordinator.refreshSafariAccess()
        let continuation = PCNativeBrowserApplication.profiles.removeFirst()
        coordinator.continueSafariWithoutRestarting()
        expect(coordinator.continueAfterSafariRefresh && PCNativeBrowserApplication.profiles.isEmpty, "Continue joins the current fresh discovery")
        continuation.complete(restricted)
        expect(coordinator.stage == .profiles && coordinator.selectedProfiles == [partial.identifier], "Continue keeps only the actual currently readable source profile")
        expect(coordinator.safariAccessError == nil && !coordinator.restarting, "Explicit Continue clears prior restart failure")
        coordinator.chooseDestination()
        expect(coordinator.stage == .destination && !coordinator.canStart, "Destination remains a separate explicit choice")
        expect(PCNativeBrowserApplication.imports == 0, "No access, resume or destination-entry action imports any data")
        expect(store.state.profiles == original.profiles && store.state.spaces == original.spaces && store.state.tabs == original.tabs,
               "Guidance and restart preparation never write Profiles, Spaces or tabs")

        let missing = BrowserImportCoordinator(store: store, destination: destination, window: window, ownerIsCurrent: { true })
        missing.discover(resumingSourceBundleID: "com.apple.Safari")
        PCNativeBrowserApplication.sources.removeFirst().complete([impostor])
        expect(missing.stage == .sources && missing.source == nil && missing.error != nil, "Missing Safari returns to the actual installed-source chooser")
        expect(PCNativeBrowserApplication.profiles.isEmpty, "A similarly named application cannot be resumed")
        missing.select(impostor); missing.loadProfiles()
        PCNativeBrowserApplication.profiles.removeFirst().complete(restricted)
        expect(missing.stage == .safariAccess, "Restricted Chromium-family sources use Full Disk Access guidance")
        let chromeURL = try app("Google Chrome", "com.google.Chrome")
        let chrome = PCNativeImportSource("Google Chrome", chromeURL)
        let chromeImport = BrowserImportCoordinator(store: store, destination: destination, window: window, ownerIsCurrent: { true })
        chromeImport.discover()
        PCNativeBrowserApplication.sources.removeFirst().complete([chrome])
        chromeImport.select(chrome); chromeImport.loadProfiles()
        PCNativeBrowserApplication.profiles.removeFirst().complete(restricted)
        expect(chromeImport.stage == .safariAccess && chromeImport.selectedProfiles == [partial.identifier],
               "Restricted Chrome opens Full Disk Access instead of claiming there is no profile")
        chromeImport.cancel()
        let unread = PCNativeImportProfile("Default", [], .restricted)
        let setupChrome = BrowserImportCoordinator(store: store, destination: destination,
            window: window, onboarding: true, ownerIsCurrent: { true })
        setupChrome.discover()
        PCNativeBrowserApplication.sources.removeFirst().complete([chrome])
        setupChrome.selectOnboardingSource(chrome)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [unread], access: .restricted))
        expect(setupChrome.stage == .profiles && setupChrome.canContinueOnboardingSource
                   && setupChrome.selectedProfiles == [unread.identifier],
               "Onboarding keeps restricted Chrome inline so Next can open Full Disk Access")
        setupChrome.continueOnboardingSource()
        expect(setupChrome.stage == .safariAccess, "Next opens Full Disk Access for unreadable Chrome files")
        setupChrome.cancel()
        let resumeChrome = BrowserImportCoordinator(store: store, destination: destination,
            window: window, onboarding: true, ownerIsCurrent: { true })
        resumeChrome.discover(resumingSourceBundleID: "com.google.Chrome")
        PCNativeBrowserApplication.sources.removeFirst().complete([safari, chrome])
        expect(PCNativeBrowserApplication.profiles.removeFirst().source === chrome,
               "Restart after Full Disk Access resumes the original Chrome source, not Safari")
        resumeChrome.cancel()
        missing.discover(resumingSourceBundleID: "com.apple.Safari")
        PCNativeBrowserApplication.sources.removeFirst().complete([])
        expect(missing.source == nil && missing.profiles.isEmpty && missing.selectedProfiles.isEmpty,
               "Rediscovery discards every old opaque source/profile token")
        missing.cancel()

        let loss = BrowserImportCoordinator(store: store, destination: destination, window: window, ownerIsCurrent: { current })
        loss.discover(resumingSourceBundleID: "com.apple.Safari")
        PCNativeBrowserApplication.sources.removeFirst().complete([safari])
        PCNativeBrowserApplication.profiles.removeFirst().complete(restricted)
        loss.refreshSafariAccess()
        let stale = PCNativeBrowserApplication.profiles.removeFirst()
        current = false; stale.complete(granted)
        expect(!loss.safariAccessReady && !loss.beginSafariRestart(), "Lost original owner rejects discovery and restart")
        loss.cancel()
        expect(stale.lease.cancelled && loss.stage == .finished, "Cancellation revokes pending discovery")
        current = true; stale.complete(granted)
        expect(loss.stage == .finished && !loss.safariAccessReady, "Late callbacks cannot resurrect a cancelled stage")
        let noAccess = BrowserImportCoordinator(store: store, destination: destination, window: window, ownerIsCurrent: { true })
        noAccess.discover(resumingSourceBundleID: "com.apple.Safari")
        PCNativeBrowserApplication.sources.removeFirst().complete([safari])
        PCNativeBrowserApplication.profiles.removeFirst().complete(restricted)
        noAccess.continueSafariWithoutRestarting()
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [], access: .restricted,
            error: NSError(domain: "fixture", code: 2)))
        expect(noAccess.stage == .profiles && !noAccess.canChooseDestination && noAccess.error != nil,
               "Continue with no readable data exposes the actual failure without an import or fabricated profile")
        noAccess.cancel()
        expect(PCNativeBrowserApplication.imports == 0, "All checks stayed outside native import execution")
        checks += try passwordCoordinatorChecks(store: store, destination: destination, window: window, safari: safari, other: impostor)
        // The inline first-launch owner admits into its captured first Profile,
        // even if unrelated model selection changes before the Import action.
        let firstLaunchStore = try BrowserStore(directory: directory.appendingPathComponent("FirstLaunch"))
        let firstLaunchDestination = BrowserImportDestination(spaceID: firstLaunchStore.activeSpace.id,
            profileID: firstLaunchStore.activeSpace.profileID)
        var setupCurrent = true
        let setup = BrowserImportCoordinator(store: firstLaunchStore, destination: firstLaunchDestination,
            window: window, ownerIsCurrent: { setupCurrent })
        let importsBeforeSetup = PCNativeBrowserApplication.imports
        setup.startInOriginalDestination()
        expect(PCNativeBrowserApplication.imports == importsBeforeSetup, "Setup cannot import before source/profile discovery")
        setup.discover()
        PCNativeBrowserApplication.sources.removeFirst().complete([impostor])
        setup.select(impostor); setup.loadProfiles()
        let selectedProfile = PCNativeImportProfile("original source profile", [.history, .bookmarks], .complete)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [selectedProfile], access: .complete))
        expect(PCNativeBrowserApplication.imports == importsBeforeSetup, "Choosing a browser and discovering its profile never submits an import")
        let otherSpace = firstLaunchStore.createSpace(name: "Other window")
        let otherProfile = firstLaunchStore.createProfile(name: "Other Profile")
        firstLaunchStore.assignProfile(otherProfile, toSpace: otherSpace)
        firstLaunchStore.selectSpace(otherSpace)
        let stateBeforeImport = firstLaunchStore.state
        setupCurrent = false; setup.startInOriginalDestination()
        expect(PCNativeBrowserApplication.imports == importsBeforeSetup, "A retired setup owner cannot submit an import")
        setupCurrent = true; PCNativeBrowserApplication.acceptsBrowserImport = true
        setup.startInOriginalDestination()
        expect(PCNativeBrowserApplication.imports == importsBeforeSetup + 1 && setup.stage == .importing,
               "Only the explicit setup Import action admits the selected source")
        let setupRequest = PCNativeBrowserApplication.browserRequests.last!
        expect(setupRequest.profile === selectedProfile && setupRequest.window === window,
               "The source descriptor and consent window stay with the original setup owner")
        expect(setupRequest.path == firstLaunchStore.independentEngineProfilePath(for: firstLaunchDestination.profileID),
               "Import cannot follow the unrelated active Profile")
        expect(setupRequest.skipExistingCookies && !setupRequest.categories.contains(.extensions),
               "Setup preserves existing cookies and never installs extensions with the profile data")
        expect(firstLaunchStore.state.profiles == stateBeforeImport.profiles && firstLaunchStore.state.spaces == stateBeforeImport.spaces,
               "First-launch import creates no extra destination Profile or Space")
        setup.startInOriginalDestination()
        expect(PCNativeBrowserApplication.imports == importsBeforeSetup + 1, "A duplicate setup Import cannot admit a second session")
        let completion = PCNativeBrowserApplication.browserCompletions.removeFirst()
        setup.cancel()
        completion(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        expect(setup.stage == .finished && setup.bookmarkPages.isEmpty, "Late native completion cannot reopen a closed setup")
        PCNativeBrowserApplication.acceptsBrowserImport = false
        let inline = BrowserImportCoordinator(store: firstLaunchStore, destination: firstLaunchDestination,
            window: window, onboarding: true, ownerIsCurrent: { setupCurrent })
        inline.discover()
        expect(!inline.isChoosingOnboardingSource, "Initial source discovery is distinct from inline profile loading")
        PCNativeBrowserApplication.sources.removeFirst().complete([impostor, safari])
        inline.selectOnboardingSource(impostor)
        let replaced = PCNativeBrowserApplication.profiles.removeFirst()
        expect(inline.isChoosingOnboardingSource && !inline.canContinueOnboardingSource,
               "Inline source cards remain available while Next waits for genuine profiles")
        inline.selectOnboardingSource(impostor)
        expect(PCNativeBrowserApplication.profiles.isEmpty, "Selecting the pending source does not repeat discovery")
        inline.selectOnboardingSource(safari)
        let safariRequest = PCNativeBrowserApplication.profiles.removeFirst()
        expect(replaced.lease.cancelled, "Switching browser cancels the old profile lease")
        replaced.complete(granted)
        expect(inline.profiles.isEmpty && inline.source === safari, "A stale source response cannot fill the new source card")
        safariRequest.complete(restricted)
        expect(inline.stage == .profiles && inline.isChoosingOnboardingSource && inline.canContinueOnboardingSource,
               "Selecting restricted Safari stays inline until explicit Next")
        inline.continueOnboardingSource()
        expect(inline.stage == .safariAccess && !inline.isChoosingOnboardingSource,
               "Next opens the genuine Safari permission guidance")
        inline.continueSafariWithoutRestarting()
        PCNativeBrowserApplication.profiles.removeFirst().complete(restricted)
        expect(inline.isChoosingOnboardingSource && inline.canContinueOnboardingSource,
               "Explicit Continue retains readable Safari data without pretending access is granted")
        expect(!inline.safariAccessReady, "Continue does not manufacture Safari access readiness")
        inline.selectOnboardingSource(impostor)
        let abandoned = PCNativeBrowserApplication.profiles.removeFirst()
        inline.clearOnboardingSource()
        expect(abandoned.lease.cancelled && inline.stage == .sources && inline.source == nil,
               "Start fresh or an accepted bookmarks file revokes pending browser discovery")
        abandoned.complete(granted)
        expect(inline.profiles.isEmpty && !inline.canContinueOnboardingSource,
               "A late browser result cannot replace the fresh-start choice")
        inline.selectOnboardingSource(impostor)
        let firstProfile = PCNativeImportProfile("First", [.history, .extensions], .complete)
        firstProfile.extensions = [PCNativeImportExtension()]
        let secondProfile = PCNativeImportProfile("Second", [.bookmarks], .complete)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [firstProfile, secondProfile], access: .complete))
        expect(inline.selectedProfiles == [firstProfile.identifier]
               && inline.selectedExtensions[firstProfile.identifier] == ["extension"],
               "Profile discovery selects one readable profile and every extension found")
        inline.toggleExtension("extension")
        expect(inline.selectedExtensions[firstProfile.identifier]?.isEmpty == true, "Setup can untick an extension")
        inline.selectProfile(secondProfile.identifier)
        expect(inline.selectedProfiles == [secondProfile.identifier], "Inline radios select exactly one real profile")
        let beforeInlineImport = PCNativeBrowserApplication.imports
        setupCurrent = false
        inline.continueOnboardingSource(); inline.selectProfile(firstProfile.identifier)
        expect(PCNativeBrowserApplication.imports == beforeInlineImport && inline.selectedProfiles == [secondProfile.identifier],
               "Retired setup rejects both selection and import actions")
        setupCurrent = true; PCNativeBrowserApplication.acceptsBrowserImport = true
        inline.continueOnboardingSource()
        let inlineRequest = PCNativeBrowserApplication.browserRequests.last!
        expect(PCNativeBrowserApplication.imports == beforeInlineImport + 1 && inlineRequest.profile === secondProfile,
               "Next submits only the profile selected inside the original source card")
        expect(!inlineRequest.categories.contains(.extensions) && inlineRequest.window === window &&
               inlineRequest.path == firstLaunchStore.independentEngineProfilePath(for: firstLaunchDestination.profileID),
               "Another profile's extension choice and another window's destination cannot leak into setup import")
        inline.selectOnboardingSource(safari); inline.clearOnboardingSource()
        expect(inline.stage == .importing && inline.source === impostor,
               "Inline source controls cannot replace an accepted import")
        inline.cancel(); PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        expect(inline.stage == .finished, "A cancelled inline owner stays retired after native completion")
        checks += try bookmarkCoordinatorChecks(directory: directory, window: window, source: impostor)
        checks += try adBlockerCoordinatorChecks(directory: directory, window: window, source: impostor)
        checks += try arcCoordinatorChecks(directory: directory, window: window)
        PCNativeBrowserApplication.acceptsBrowserImport = false
        print("\(checks) import owner/access/password assertions passed; isolated source fixtures only.")
    }

    @MainActor private static func bookmarkCoordinatorChecks(directory: URL, window: NSWindow,
                                                             source: PCNativeImportSource) throws -> Int {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(condition(), message)
        }
        // BrowserStore's ISO8601 format persists whole seconds. Freeze the real
        // injectable clock at that precision for exact before/after equality.
        let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let store = try BrowserStore(directory: directory.appendingPathComponent("BookmarkSelection"), now: { date })
        let destination = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
        var current = true
        let coordinator = BrowserImportCoordinator(store: store, destination: destination, window: window,
            onboarding: true, ownerIsCurrent: { current })
        coordinator.discover()
        PCNativeBrowserApplication.sources.removeFirst().complete([source])
        coordinator.selectOnboardingSource(source)
        let profile = PCNativeImportProfile("Chosen profile", [.bookmarks], .complete)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
        PCNativeBrowserApplication.acceptsBrowserImport = true
        coordinator.continueOnboardingSource()
        let folder = PCNativeImportedBookmark("folder", title: "Reading", children: [
            PCNativeImportedBookmark("first", title: "Same title", url: URL(string: "https://example.org/first")),
            PCNativeImportedBookmark("second", title: "Same title", url: URL(string: "https://example.org/second"))])
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed,
            bookmarks: [folder], warnings: [], error: nil,
            historyVisitCounts: ["https://example.org/first": 12]))
        expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages.count == 1, "The native result reaches the actual bookmark stage")
        let pageID = coordinator.bookmarkPages[0].id
        let initial = coordinator.bookmarkPages[0].selection.selected
        expect(initial == ["first"] && !coordinator.bookmarkPages[0].selection.allSelected,
               "The actual source history reaches setup's bookmark recommendation")
        expect(coordinator.bookmarkPages[0].sourceName == profile.displayName, "The list section keeps the actual source profile name")
        coordinator.toggleBookmark(pageID: pageID, id: "folder", expansion: true)
        expect(coordinator.bookmarkPages[0].selection.expanded.isEmpty, "The initial top-level folder can collapse independently")
        coordinator.toggleBookmark(pageID: pageID, id: "folder", expansion: true)
        expect(coordinator.bookmarkPages[0].selection.expanded == ["folder"], "The folder label expands the original folder")
        expect(coordinator.bookmarkPages[0].selection.selected == initial, "Expanding cannot select or deselect a subtree")
        coordinator.toggleBookmark(pageID: pageID, id: "folder")
        expect(coordinator.bookmarkPages[0].selection.allSelected, "The folder circle selects all descendants after a partial recommendation")
        coordinator.toggleBookmark(pageID: pageID, id: "folder")
        expect(coordinator.bookmarkPages[0].selection.selected.isEmpty, "The folder circle deselects the complete source subtree")
        expect(coordinator.bookmarkPages[0].selection.expanded == ["folder"], "Selection leaves expansion alone")
        coordinator.toggleBookmark(pageID: pageID, id: "second")
        expect(coordinator.bookmarkPages[0].selection.selected == ["second"], "Duplicate titles retain distinct selection identities")
        coordinator.toggleBookmark(pageID: UUID(), id: nil)
        expect(coordinator.bookmarkPages[0].selection.selected == ["second"], "An unrelated or stale result page cannot address this tree")
        coordinator.toggleBookmark(pageID: pageID, id: nil, expansion: true)
        expect(coordinator.bookmarkPages[0].selection.selected == ["second"], "The virtual root cannot convert expansion into selection")
        current = false
        coordinator.toggleBookmark(pageID: pageID, id: nil)
        coordinator.toggleBookmark(page: 0, id: "folder", expansion: true)
        coordinator.commitBookmarks()
        expect(coordinator.bookmarkPages[0].selection.selected == ["second"] && coordinator.bookmarkPages[0].selection.expanded == ["folder"],
               "Retiring the original owner rejects old and new selection entry points")
        expect(coordinator.stage == .bookmarks && !coordinator.bookmarkPages[0].committed, "Retired ownership cannot commit the pending result")
        current = true
        coordinator.toggleBookmark(pageID: pageID, id: nil)
        expect(coordinator.bookmarkPages[0].selection.selected == ["folder", "first", "second"], "Select All restores every source descendant")
        coordinator.toggleBookmark(pageID: pageID, id: nil)
        expect(coordinator.bookmarkPages[0].selection.selected.isEmpty, "A second Select All clears the same tree")
        coordinator.toggleBookmark(pageID: pageID, id: "second")
        let otherSpace = store.createSpace(name: "Other window")
        store.selectSpace(otherSpace)
        coordinator.commitBookmarks()
        expect(coordinator.stage == .finished && coordinator.bookmarkPages[0].committed, "Explicit acceptance commits the real selected tree")
        let imported = store.state.tabs.filter { $0.url == "https://example.org/second" }
        expect(imported.count == 1 && imported[0].spaceID == destination.spaceID && imported[0].profileID == destination.profileID,
               "The result never follows another window's current Space or Profile")
        expect(!store.state.tabs.contains { $0.url == "https://example.org/first" }, "Unselected descendants do not become tabs")
        expect(imported[0].folderID != nil && store.state.folders.contains { $0.id == imported[0].folderID && $0.name == "Reading" },
               "A selected leaf retains its original ancestor structure")
        let tabs = store.state.tabs, folders = store.state.folders
        coordinator.commitBookmarks(); coordinator.toggleBookmark(pageID: pageID, id: nil)
        expect(store.state.tabs == tabs && store.state.folders == folders && coordinator.bookmarkPages[0].selection.selected == ["second"],
               "Repeated acceptance and obsolete controls cannot duplicate or change a completed result")
        let restored = try BrowserStore(directory: directory.appendingPathComponent("BookmarkSelection"), now: { date })
        expect(restored.state.tabs == tabs && restored.state.folders == folders, "Accepted bookmarks persist through the actual store")
        coordinator.cancel()
        return checks
    }

    @MainActor private static func adBlockerCoordinatorChecks(directory: URL, window: NSWindow,
                                                              source: PCNativeImportSource) throws -> Int {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(condition(), message)
        }
        let store = try BrowserStore(directory: directory.appendingPathComponent("AdBlockerImport"))
        let destination = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
        let current = true
        let coordinator = BrowserImportCoordinator(store: store, destination: destination, window: window,
            onboarding: true, ownerIsCurrent: { current })
        coordinator.discover()
        PCNativeBrowserApplication.sources.removeFirst().complete([source])
        coordinator.selectOnboardingSource(source)
        let known = PCNativeImportExtension(identifier: "cjpalhdlnbpafiamejdnhcphjbkeiagm", displayName: "uBlock Origin")
        let unknown = PCNativeImportExtension()
        let profile = PCNativeImportProfile("Extensions", [.history, .extensions], .complete)
        profile.extensions = [known, unknown]
        func run() {
            coordinator.discover()
            PCNativeBrowserApplication.sources.removeFirst().complete([source])
            coordinator.selectOnboardingSource(source)
            PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
            coordinator.continueOnboardingSource()
        }
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
        expect(coordinator.selectedExtensions[profile.identifier] == [known.identifier, unknown.identifier],
               "Every extension found starts selected")
        PCNativeBrowserApplication.acceptsBrowserImport = true
        coordinator.continueOnboardingSource()
        expect(PCNativeBrowserApplication.browserRequests.last?.categories.contains(.extensions) == false
               && PCNativeBrowserApplication.extensionInstalls.isEmpty,
               "Extensions wait for their consent until the profile's data has imported")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .failed, bookmarks: [], warnings: [], error: nil))
        let skipped = PCNativeBrowserApplication.extensionInstalls.removeFirst()
        expect(skipped.requests.count == 1 && skipped.requests[0].source === profile
               && skipped.requests[0].extensionIDs == [known.identifier, unknown.identifier]
               && skipped.requests[0].profilePath == store.independentEngineProfilePath(for: destination.profileID)
               && coordinator.stage == .importing,
               "Every selected extension, including known ad blockers, is offered in one consent")
        skipped.complete(.init(outcome: .cancelled))
        expect(coordinator.stage == .finished && coordinator.importedAdBlockers.isEmpty
               && !coordinator.warnings.contains { $0.hasSuffix("couldn’t be added.") },
               "Skipping the consent adds nothing and reports no failure")
        run()
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        coordinator.stopImport()
        let stopped = PCNativeBrowserApplication.extensionInstalls.removeFirst()
        expect(stopped.lease.cancelled, "Stop withdraws a pending extension consent")
        stopped.complete(.init(outcome: .cancelled))
        expect(coordinator.stage == .finished && coordinator.message == "Import stopped. Data already imported has been kept.",
               "A stopped extension install ends the import like any other stop")
        run()
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        PCNativeBrowserApplication.extensionInstalls.removeFirst().complete(.init(outcome: .completed,
            installedIdentifiers: [known.identifier, unknown.identifier]))
        expect(coordinator.importedAdBlockers == [.init(identifier: known.identifier, displayName: known.displayName)],
               "Only known ad blockers that were actually installed continue into setup")
        run()
        PCNativeBrowserApplication.rejectsExtensionInstall = true
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        PCNativeBrowserApplication.rejectsExtensionInstall = false
        expect(coordinator.stage == .finished && coordinator.warnings.contains("uBlock Origin couldn’t be added.")
               && coordinator.warnings.contains("Extension couldn’t be added."),
               "An install that can't begin lists each extension as a failure")
        coordinator.cancel()
        return checks
    }

    @MainActor private static func arcCoordinatorChecks(directory: URL, window: NSWindow) throws -> Int {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(condition(), message)
        }
        func wait(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(10)
            while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        }
        let sidebar = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../Fixtures/ArcSidebar/StorableSidebar.json").standardizedFileURL
        let arc = PCNativeImportSource(BrowserImportCoordinator.arcBundleIdentifier,
                                       directory.appendingPathComponent("Arc", isDirectory: true))
        let standard = PCNativeImportProfile("arc standard", [.history, .bookmarks], .complete, name: "Person 1", directory: "Default")
        let side = PCNativeImportProfile("arc side", [.history], .complete, name: "Side", directory: "Profile 1")
        let empty = PCNativeImportProfile("arc empty", [], .restricted, name: "Locked", directory: "Profile 3")
        let preferences = directory.appendingPathComponent("ArcPreferences.plist")
        try PropertyListSerialization.data(fromPropertyList: ["autoArchiveTimeThresholdsPerProfile":
            #"{"thresholds":[{"custom":{"_0":{"directoryBasename":"Profile 1","machineID":"M"}}},"thirtyDays"]}"#],
            format: .binary, options: 0).write(to: preferences)
        let exportFolder = directory.appendingPathComponent("Arc-Notes-Export")
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        let noteDate = Date(timeIntervalSince1970: 1_785_000_000)
        for name in ["Trip plan", "Groceries"] {
            let file = exportFolder.appendingPathComponent(name + ".html")
            try Data("<p>\(name)</p>".utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: noteDate], ofItemAtPath: file.path)
        }
        let converter: BrowserImportCoordinator.ArcNoteConverter = { _ in (nil, NoteBody(), 0) }
        let noCache = directory.appendingPathComponent("NoFirestore")
        let cachedConverter: BrowserImportCoordinator.ArcCachedNoteConverter = { _ in (nil, NoteBody(), 0) }
        func begin(_ name: String, sidebar: URL, cache: URL? = nil) throws -> (BrowserStore, BrowserImportDestination, BrowserImportCoordinator) {
            let store = try BrowserStore(directory: directory.appendingPathComponent(name))
            let destination = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
            let coordinator = BrowserImportCoordinator(store: store, destination: destination, window: window,
                arcSidebarURL: sidebar, arcPreferencesURL: preferences, arcNoteConverter: converter,
                arcCachedNoteConverter: cachedConverter, arcNotesCacheURL: cache ?? noCache,
                arcAuthStateURL: directory.appendingPathComponent("NoAuthState.json"), ownerIsCurrent: { true })
            coordinator.discover()
            PCNativeBrowserApplication.sources.removeFirst().complete([arc])
            coordinator.select(arc); coordinator.loadProfiles()
            PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [standard, side, empty], access: .complete))
            return (store, destination, coordinator)
        }
        PCNativeBrowserApplication.acceptsBrowserImport = true
        PCNativeBrowserApplication.browserCompletions = []

        let (stopped, _, stopping) = try begin("ArcStopped", sidebar: sidebar)
        expect(stopping.selectedProfiles == [standard.identifier, side.identifier], "Every readable Arc profile is selected")
        stopping.selectProfile(side.identifier)
        expect(stopping.selectedProfiles == [standard.identifier], "Arc profiles toggle individually")
        stopping.selectProfile(side.identifier); stopping.selectProfile(empty.identifier)
        expect(stopping.selectedProfiles == [standard.identifier, side.identifier], "An unreadable profile cannot be chosen")
        let spaces = stopped.state.spaces, requests = PCNativeBrowserApplication.browserRequests.count
        stopping.chooseDestination()
        expect(stopping.stage == .importing && stopping.destinationChoice.option == nil, "Arc imports without a single destination step")
        stopping.stopImport()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        expect(stopping.stage == .finished && stopped.state.spaces == spaces, "Stop while Arc's sidebar is read adds nothing")
        expect(PCNativeBrowserApplication.browserRequests.count == requests, "A stopped Arc import starts no native import")

        let (store, destination, coordinator) = try begin("ArcImport", sidebar: sidebar)
        coordinator.chooseDestination()
        wait { PCNativeBrowserApplication.browserRequests.count > requests }
        let profileNamed = { (name: String) in store.state.profiles.first { $0.name == name } }
        let work = store.state.spaces.first { $0.title == "Work" }
        expect(work?.profileID == destination.profileID, "Arc's standard Spaces join the window's Profile")
        expect(store.state.tabs.contains { $0.spaceID == work?.id && $0.kind == .pinned }, "Arc's pinned tabs come with their Space")
        guard let sideProfile = profileNamed("Side") else { preconditionFailure("Arc's other profile becomes a Parc Profile") }
        expect(sideProfile.autoArchiveHours == 720 && store.state.profiles.first { $0.id == destination.profileID }?.autoArchiveHours
               == AutoArchiveInterval.twelveHours.rawValue, "Arc's archive age reaches only the Profile it was set for")
        expect(store.state.tabs.contains { $0.kind == .today && $0.savedURL == "https://example.test/today" }, "Arc's Today tabs come over")
        expect(store.state.spaces.contains { $0.title == "Side" && $0.profileID == sideProfile.id }, "A custom profile's Space joins its Profile")
        expect(PCNativeBrowserApplication.browserRequests[requests].profile === standard
               && PCNativeBrowserApplication.browserRequests[requests].path == store.independentEngineProfilePath(for: destination.profileID),
               "Arc's standard browser data imports into the window's Profile")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        expect(PCNativeBrowserApplication.browserRequests.count == requests + 2
               && PCNativeBrowserApplication.browserRequests[requests + 1].profile === side
               && PCNativeBrowserApplication.browserRequests[requests + 1].path == store.independentEngineProfilePath(for: sideProfile.id),
               "Each Arc profile's browser data imports into its own Parc Profile")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: ["fixture warning"], error: nil))
        expect(coordinator.stage == .finished, "The Arc import finishes after its last profile")
        expect(coordinator.warnings.contains("fixture warning")
               && coordinator.warnings.contains("Favorites from a Profile that wasn't imported were left out."),
               "Native and sidebar warnings both reach the result")
        expect(coordinator.warnings.contains(BrowserImportCoordinator.arcNotesReminder)
               && coordinator.warnings.contains(BrowserImportCoordinator.arcEaselsNote),
               "Without a Notes export the result says how to bring Notes over, and why Easels stay")
        expect(coordinator.canChooseArcNotesExport, "The result offers the Notes export")
        coordinator.chooseArcNotesExport(exportFolder)
        wait { !coordinator.importingArcNotes }
        let library = try NoteStore.sharedStore(directory: store.notesDirectory(for: destination.profileID)).list()
        expect(Set(library.map(\.title)) == ["Trip plan", "Groceries"] && library.allSatisfy { $0.modifiedAt == noteDate },
               "Notes from the export join the window's Profile with their last-edit dates")
        expect(coordinator.warnings.contains("2 Arc Notes came over from your export.")
               && !coordinator.warnings.contains(BrowserImportCoordinator.arcNotesReminder) && !coordinator.canChooseArcNotesExport,
               "The result reports the Notes and drops the reminder")
        coordinator.cancel()

        let (early, earlyDestination, earlyImport) = try begin("ArcNotesFirst", sidebar: sidebar)
        let earlyStart = PCNativeBrowserApplication.browserRequests.count
        earlyImport.chooseArcNotesExport(exportFolder)
        expect(earlyImport.arcNotesExportURL == exportFolder, "The Arc profile step takes a Notes export")
        earlyImport.chooseDestination()
        wait { PCNativeBrowserApplication.browserRequests.count > earlyStart }
        let earlyNotes = try NoteStore.sharedStore(directory: early.notesDirectory(for: earlyDestination.profileID)).list()
        expect(earlyNotes.count == 2 && !earlyImport.warnings.contains(BrowserImportCoordinator.arcNotesReminder),
               "A chosen export's Notes come over before the browser data")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        expect(earlyImport.stage == .finished, "The import finishes after the Notes and both profiles")
        earlyImport.cancel()
        let (again, againDestination, againImport) = try begin("ArcNotesFirst", sidebar: sidebar)
        againImport.chooseArcNotesExport(exportFolder)
        let againStart = PCNativeBrowserApplication.browserRequests.count
        againImport.chooseDestination()
        wait { PCNativeBrowserApplication.browserRequests.count > againStart }
        let againNotes = try NoteStore.sharedStore(directory: again.notesDirectory(for: againDestination.profileID)).list()
        expect(againNotes.count == 2
               && againImport.warnings.contains("2 Arc Notes were already in Parc."), "Importing the same export twice adds no copies")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        againImport.cancel()

        let firestore = directory.appendingPathComponent("Firestore")
        try FileManager.default.createDirectory(at: firestore, withIntermediateDirectories: true)
        let cachedFields: [String: FirestoreCache.Value] = ["id": .string("N9"), "creatorID": .string("me"),
            "title": .map(["value": .string("Cached"), "lastUpdatedAt": .timestamp(noteDate)]),
            "data": .map(["scratchpad": .map(["rootBlocks": .array([.string("B")]), "blocks": .map(["B": .map([
                "text": .string("hello"), "properties": .array([]), "lastUpdatedAt": .timestamp(noteDate)])])])])]
        let older = noteDate.addingTimeInterval(-3600)
        var olderTrip = cachedFields
        olderTrip["id"] = .string("N8"); olderTrip["title"] = .map(["value": .string("Trip plan"), "lastUpdatedAt": .timestamp(older)])
        olderTrip["data"] = .map(["scratchpad": .map(["rootBlocks": .array([.string("B")]), "blocks": .map(["B": .map([
            "text": .string("old"), "properties": .array([]), "lastUpdatedAt": .timestamp(older)])])])])
        try FirestoreFixture.log([(1, [("doc/N9", FirestoreFixture.document("documents/N9", cachedFields, updated: noteDate)),
                                       ("doc/N8", FirestoreFixture.document("documents/N8", olderTrip, updated: older))])])
            .write(to: firestore.appendingPathComponent("000001.log"))
        let (cachedStore, cachedDestination, cachedImport) = try begin("ArcCache", sidebar: sidebar, cache: firestore)
        let cachedStart = PCNativeBrowserApplication.browserRequests.count
        cachedImport.chooseDestination()
        wait { PCNativeBrowserApplication.browserRequests.count > cachedStart }
        let cachedNotes = try NoteStore.sharedStore(directory: cachedStore.notesDirectory(for: cachedDestination.profileID)).list()
        expect(Set(cachedNotes.map(\.title)) == ["Cached", "Trip plan"] && cachedNotes.first { $0.title == "Cached" }?.modifiedAt == noteDate,
               "Without an export, Notes come from Arc's offline copy")
        expect(cachedImport.warnings.contains { $0.hasPrefix("2 Arc Notes came from the copy Arc keeps on this Mac,")
               && $0.hasSuffix(BrowserImportCoordinator.arcNotesAdvice) }
               && !cachedImport.warnings.contains(BrowserImportCoordinator.arcNotesReminder),
               "The result says the Notes came from the offline copy and how to bring them all over")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        expect(cachedImport.canChooseArcNotesExport, "An export can still be added after Notes came from the offline copy")
        cachedImport.chooseArcNotesExport(exportFolder)
        wait { !cachedImport.importingArcNotes }
        let afterExport = try NoteStore.sharedStore(directory: cachedStore.notesDirectory(for: cachedDestination.profileID)).list()
        expect(cachedImport.warnings.contains("2 Arc Notes came from the copy Arc keeps on this Mac,"
               + " which can miss Notes this Mac never opened and recent edits made elsewhere.")
               && cachedImport.warnings.contains("1 Arc Note came over from your export.")
               && cachedImport.warnings.contains("1 Arc Note was updated from your export."),
               "The export's Notes join, an older offline copy is updated, and the advice to make an export goes")
        expect(afterExport.count == 3 && afterExport.filter { $0.title == "Trip plan" }.count == 1
               && afterExport.first { $0.title == "Trip plan" }?.modifiedAt == noteDate,
               "An offline copy and its exported version don't become two Notes")
        cachedImport.cancel()

        let (removed, _, removing) = try begin("ArcRemoved", sidebar: sidebar)
        let removedStart = PCNativeBrowserApplication.browserRequests.count
        removing.chooseDestination()
        wait { PCNativeBrowserApplication.browserRequests.count > removedStart }
        let sideSpace = removed.state.spaces.first { $0.title == "Side" }!
        var deleted = false
        removed.deleteSpace(SpaceDeletionTarget(spaceID: sideSpace.id, state: removed.state)!, documents: [:],
            shouldCommit: { true }, didCommit: { _ in }, completion: { deleted = (try? $0.get()) == true })
        wait { deleted }
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        expect(deleted && removing.stage == .finished && PCNativeBrowserApplication.browserRequests.count == removedStart + 1
               && removing.warnings.contains("Side: its Parc Space or Profile was removed, so it wasn’t imported."),
               "A removed destination skips only that Arc profile and the import still finishes")
        removing.cancel()

        let missing = directory.appendingPathComponent("NoArc/StorableSidebar.json")
        let (fallback, fallbackDestination, unreadable) = try begin("ArcUnreadable", sidebar: missing)
        let before = PCNativeBrowserApplication.browserRequests.count
        unreadable.chooseDestination()
        wait { PCNativeBrowserApplication.browserRequests.count > before }
        expect(unreadable.warnings.contains { $0.hasPrefix("Arc’s Spaces couldn’t be read") }, "An unreadable sidebar is reported")
        expect(PCNativeBrowserApplication.browserRequests[before].path == fallback.independentEngineProfilePath(for: fallbackDestination.profileID),
               "Without the sidebar, Arc's standard data still imports into the window's Profile")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        let created = fallback.state.profiles.first { $0.name == "Side" }
        expect(created != nil && PCNativeBrowserApplication.browserRequests.last?.path == fallback.independentEngineProfilePath(for: created!.id),
               "Without the sidebar, another Arc profile still gets its own Parc Profile")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        expect(unreadable.stage == .finished, "The fallback import finishes")
        unreadable.cancel()

        let blocker = PCNativeImportExtension(identifier: "cjpalhdlnbpafiamejdnhcphjbkeiagm", displayName: "uBlock Origin")
        let broken = PCNativeImportExtension(identifier: "broken", displayName: "Broken")
        let helper = PCNativeImportExtension(identifier: "helper", displayName: "Helper")
        let withExtensions = PCNativeImportProfile("arc ext standard", [.history, .extensions], .complete,
                                                   name: "Person 1", directory: "Default")
        withExtensions.extensions = [blocker, broken]
        let onlyExtensions = PCNativeImportProfile("arc ext side", [.extensions], .complete, name: "Side", directory: "Profile 1")
        onlyExtensions.extensions = [blocker, helper]
        let extensionStore = try BrowserStore(directory: directory.appendingPathComponent("ArcExtensions"))
        let extensionDestination = BrowserImportDestination(spaceID: extensionStore.activeSpace.id,
                                                            profileID: extensionStore.activeSpace.profileID)
        let setup = BrowserImportCoordinator(store: extensionStore, destination: extensionDestination, window: window,
            onboarding: true, arcSidebarURL: sidebar, arcPreferencesURL: preferences, arcNoteConverter: converter,
            arcCachedNoteConverter: cachedConverter, arcNotesCacheURL: noCache,
            arcAuthStateURL: directory.appendingPathComponent("NoAuthState.json"), ownerIsCurrent: { true })
        setup.discover()
        PCNativeBrowserApplication.sources.removeFirst().complete([arc])
        setup.selectOnboardingSource(arc)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [withExtensions, onlyExtensions], access: .complete))
        expect(setup.selectedExtensions[withExtensions.identifier] == [blocker.identifier, broken.identifier]
               && setup.selectedExtensions[onlyExtensions.identifier] == [blocker.identifier, helper.identifier],
               "Setup selects every extension of every Parc profile")
        setup.toggleExtension(blocker.identifier)
        expect(setup.selectedExtensions.values.allSatisfy { !$0.contains(blocker.identifier) },
               "An extension listed once unticks in every profile that has it")
        setup.selectProfile(onlyExtensions.identifier)
        setup.toggleExtension(blocker.identifier)
        setup.selectProfile(onlyExtensions.identifier)
        expect(setup.selectedExtensions.values.allSatisfy { $0.contains(blocker.identifier) },
               "A profile switched off and on again keeps the choice made meanwhile")
        let extensionStart = PCNativeBrowserApplication.browserRequests.count
        let installsBefore = PCNativeBrowserApplication.extensionInstalls.count
        setup.continueOnboardingSource()
        wait { PCNativeBrowserApplication.browserRequests.count > extensionStart }
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        let sideID = extensionStore.state.profiles.first { $0.name == "Side" }?.id
        expect(PCNativeBrowserApplication.browserRequests.count == extensionStart + 1
               && PCNativeBrowserApplication.extensionInstalls.count == installsBefore + 1 && sideID != nil,
               "A profile with only extensions needs no data import, and one consent follows the last profile")
        let together = PCNativeBrowserApplication.extensionInstalls.removeLast()
        expect(together.window === window && together.requests.count == 2
               && together.requests[0].source === withExtensions
               && together.requests[0].extensionIDs == [blocker.identifier, broken.identifier]
               && together.requests[1].source === onlyExtensions
               && together.requests[1].extensionIDs == [blocker.identifier, helper.identifier]
               && together.requests[1].profilePath == extensionStore.independentEngineProfilePath(for: sideID!)
               && setup.message == "Adding your extensions…",
               "One consent covers every Arc profile's extensions, each into its own Parc Profile")
        together.complete(.init(outcome: .partial, installedIdentifiers: [blocker.identifier, helper.identifier],
                                failedNames: ["Broken"]))
        expect(setup.stage == .finished && setup.warnings.contains("Broken couldn’t be added.")
               && setup.importedAdBlockers == [.init(identifier: blocker.identifier, displayName: blocker.displayName)],
               "A failure among several is listed with the import's other failures and the rest are added")
        setup.cancel()
        PCNativeBrowserApplication.acceptsBrowserImport = false
        return checks
    }
}
