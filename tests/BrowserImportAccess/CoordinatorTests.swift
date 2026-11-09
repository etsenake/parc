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
        expect(coordinator.stage == .profiles && coordinator.canContinueSourceInline, "Continue returns to the profile choice; only Next imports")
        expect(PCNativeBrowserApplication.imports == 0, "No access or resume action imports any data")
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
        let chrome = PCNativeImportSource("com.google.Chrome", chromeURL)
        let chromeImport = BrowserImportCoordinator(store: store, destination: destination, window: window, ownerIsCurrent: { true })
        chromeImport.discover()
        let arc = PCNativeImportSource(BrowserImportCoordinator.arcBundleIdentifier,
                                       try app("Arc", BrowserImportCoordinator.arcBundleIdentifier))
        PCNativeBrowserApplication.sources.removeFirst().complete([safari, chrome, impostor, arc])
        expect(chromeImport.sources.map(\.identifier) == [arc, chrome, safari, impostor].map(\.identifier),
               "Both import flows show Arc, then Chrome, then other browsers in discovery order")
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
        setupChrome.selectSourceInline(chrome)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [unread], access: .restricted))
        expect(setupChrome.stage == .profiles && setupChrome.canContinueSourceInline
                   && setupChrome.selectedProfiles == [unread.identifier],
               "Onboarding keeps restricted Chrome inline so Next can open Full Disk Access")
        setupChrome.continueSourceInline()
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
        expect(noAccess.stage == .profiles && !noAccess.canContinueSourceInline && noAccess.error != nil,
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
        expect(!inline.isChoosingSourceInline, "Initial source discovery is distinct from inline profile loading")
        PCNativeBrowserApplication.sources.removeFirst().complete([impostor, safari])
        inline.selectSourceInline(impostor)
        let replaced = PCNativeBrowserApplication.profiles.removeFirst()
        expect(inline.isChoosingSourceInline && !inline.canContinueSourceInline,
               "Inline source cards remain available while Next waits for genuine profiles")
        inline.selectSourceInline(impostor)
        expect(PCNativeBrowserApplication.profiles.isEmpty, "Selecting the pending source does not repeat discovery")
        inline.selectSourceInline(safari)
        let safariRequest = PCNativeBrowserApplication.profiles.removeFirst()
        expect(replaced.lease.cancelled, "Switching browser cancels the old profile lease")
        replaced.complete(granted)
        expect(inline.profiles.isEmpty && inline.source === safari, "A stale source response cannot fill the new source card")
        safariRequest.complete(restricted)
        expect(inline.stage == .profiles && inline.isChoosingSourceInline && inline.canContinueSourceInline,
               "Selecting restricted Safari stays inline until explicit Next")
        inline.continueSourceInline()
        expect(inline.stage == .safariAccess && !inline.isChoosingSourceInline,
               "Next opens the genuine Safari permission guidance")
        inline.goBackInSetup()
        expect(inline.isChoosingSourceInline && inline.canContinueSourceInline && inline.source === safari,
               "Back from Safari access returns to the browser cards with Safari still chosen")
        expect(!inline.safariAccessReady, "Back does not manufacture Safari access readiness")
        let direct = BrowserImportCoordinator(store: firstLaunchStore, destination: firstLaunchDestination,
            window: window, onboarding: true, ownerIsCurrent: { setupCurrent })
        direct.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([safari])
        direct.selectSourceInline(safari)
        PCNativeBrowserApplication.profiles.removeFirst().complete(restricted)
        direct.continueSourceInline()
        let beforeDirect = PCNativeBrowserApplication.imports
        direct.continueSafariWithoutRestarting()
        PCNativeBrowserApplication.profiles.removeFirst().complete(restricted)
        expect(PCNativeBrowserApplication.imports == beforeDirect + 1 && PCNativeBrowserApplication.browserRequests.last?.profile === partial,
               "As Arc's, Next on Safari access imports what is readable without a second Next on the cards")
        direct.cancel()
        inline.selectSourceInline(impostor)
        let abandoned = PCNativeBrowserApplication.profiles.removeFirst()
        inline.clearSourceInline()
        expect(abandoned.lease.cancelled && inline.stage == .sources && inline.source == nil,
               "Start fresh or an accepted bookmarks file revokes pending browser discovery")
        abandoned.complete(granted)
        expect(inline.profiles.isEmpty && !inline.canContinueSourceInline,
               "A late browser result cannot replace the fresh-start choice")
        inline.selectSourceInline(impostor)
        let firstProfile = PCNativeImportProfile("First", [.history, .extensions], .complete)
        firstProfile.extensions = [PCNativeImportExtension()]
        let secondProfile = PCNativeImportProfile("Second", [.bookmarks], .complete)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [firstProfile, secondProfile], access: .complete))
        expect(inline.selectedProfiles == [firstProfile.identifier, secondProfile.identifier],
               "Profile discovery takes every readable profile")
        let beforeInlineImport = PCNativeBrowserApplication.imports
        setupCurrent = false
        inline.continueSourceInline()
        expect(PCNativeBrowserApplication.imports == beforeInlineImport, "Retired setup rejects import actions")
        setupCurrent = true; PCNativeBrowserApplication.acceptsBrowserImport = true
        inline.continueSourceInline()
        let inlineRequest = PCNativeBrowserApplication.browserRequests.last!
        expect(PCNativeBrowserApplication.imports == beforeInlineImport + 1 && inlineRequest.profile === secondProfile
               && inlineRequest.categories == [.bookmarks],
               "Next reads the bookmarks of the profile that has them first")
        let secondDestination = firstLaunchStore.state.profiles.first { $0.name == "Second" }
        expect(inlineRequest.window === window && secondDestination != nil &&
               inlineRequest.path == firstLaunchStore.independentEngineProfilePath(for: secondDestination!.id),
               "The other profile reads into a Parc Profile of its name, never another window's destination")
        inline.selectSourceInline(safari); inline.clearSourceInline()
        expect(inline.stage == .importing && inline.source === impostor,
               "Inline source controls cannot replace an accepted import")
        inline.cancel(); PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        expect(inline.stage == .finished, "A cancelled inline owner stays retired after native completion")
        checks += try bookmarkCoordinatorChecks(directory: directory, window: window, source: impostor)
        checks += try adBlockerCoordinatorChecks(directory: directory, window: window, source: impostor)
        checks += try backgroundCoordinatorChecks(directory: directory, source: impostor)
        checks += try arcCoordinatorChecks(directory: directory, window: window)
        checks += try profileMappingChecks(directory: directory, window: window)
        checks += try passwordHelpChecks()
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
        coordinator.selectSourceInline(source)
        let profile = PCNativeImportProfile("Chosen profile", [.bookmarks], .complete)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
        PCNativeBrowserApplication.acceptsBrowserImport = true
        coordinator.continueSourceInline()
        let folder = PCNativeImportedBookmark("folder", title: "Reading", children: [
            PCNativeImportedBookmark("first", title: "Same title", url: URL(string: "https://example.org/first")),
            PCNativeImportedBookmark("second", title: "Same title", url: URL(string: "https://example.org/second"))])
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed,
            bookmarks: [folder], warnings: [], error: nil))
        expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages.count == 1, "The native result reaches the actual bookmark stage")
        let pageID = coordinator.bookmarkPages[0].id
        let initial = coordinator.bookmarkPages[0].selection.selected
        expect(coordinator.bookmarkPages[0].selection.allSelected && initial == ["folder", "first", "second"],
               "Every imported bookmark starts ticked")
        expect(coordinator.bookmarkPages[0].sourceName == profile.displayName, "The list section keeps the actual source profile name")
        coordinator.toggleBookmark(pageID: pageID, id: "folder", expansion: true)
        expect(coordinator.bookmarkPages[0].selection.expanded.isEmpty, "The initial top-level folder can collapse independently")
        coordinator.toggleBookmark(pageID: pageID, id: "folder", expansion: true)
        expect(coordinator.bookmarkPages[0].selection.expanded == ["folder"], "The folder label expands the original folder")
        expect(coordinator.bookmarkPages[0].selection.selected == initial, "Expanding cannot select or deselect a subtree")
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
        coordinator.selectSourceInline(source)
        let known = PCNativeImportExtension(identifier: "cjpalhdlnbpafiamejdnhcphjbkeiagm", displayName: "uBlock Origin")
        let unknown = PCNativeImportExtension()
        let profile = PCNativeImportProfile("Extensions", [.history, .extensions], .complete)
        profile.extensions = [known, unknown]
        func run() {
            coordinator.discover()
            PCNativeBrowserApplication.sources.removeFirst().complete([source])
            coordinator.selectSourceInline(source)
            PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
            coordinator.continueSourceInline()
        }
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [profile], access: .complete))
        PCNativeBrowserApplication.acceptsBrowserImport = true
        coordinator.continueSourceInline()
        expect(PCNativeBrowserApplication.browserRequests.last?.categories.contains(.extensions) == false
               && PCNativeBrowserApplication.extensionInstalls.isEmpty,
               "Extensions wait until the profile's data has imported")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .failed, bookmarks: [], warnings: [], error: nil))
        let failing = PCNativeBrowserApplication.extensionInstalls.removeFirst()
        expect(failing.requests.count == 1 && failing.requests[0].source === profile
               && failing.requests[0].extensionIDs == [known.identifier, unknown.identifier]
               && failing.requests[0].profilePath == store.independentEngineProfilePath(for: destination.profileID)
               && coordinator.stage == .finished && coordinator.hasBackgroundWork,
               "Every extension found, including known ad blockers, installs even when other data failed")
        failing.complete(.init(outcome: .failed, failedNames: ["uBlock Origin", "Extension"]))
        expect(coordinator.stage == .finished && coordinator.importedAdBlockers.isEmpty
               && coordinator.warnings.contains("uBlock Origin couldn’t be added.")
               && coordinator.warnings.contains("Extension couldn’t be added."),
               "Extensions that fail are listed and none reaches the ad-blocker step")
        expect(ImportedExtensionFailures.pending.isEmpty && ImportedBrowserDataFailures.take() == .failed,
               "An import whose data all failed says so once, its failed extensions under that one toast")
        run()
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        coordinator.stopImport()
        let stopped = PCNativeBrowserApplication.extensionInstalls.removeFirst()
        expect(!stopped.lease.cancelled, "Foreground Stop cannot cancel background extension work")
        stopped.complete(.init(outcome: .cancelled, installingIdentifiers: [known.identifier]))
        expect(coordinator.stage == .finished && !coordinator.hasBackgroundWork
               && !coordinator.warnings.contains { $0.hasSuffix("couldn’t be added.") },
               "Stop during a running download ends the import at once and reports nothing as failed")
        run()
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        let downloading = PCNativeBrowserApplication.extensionInstalls.removeFirst()
        downloading.complete(.init(outcome: .completed, installedIdentifiers: [unknown.identifier],
                                   installingIdentifiers: [known.identifier]))
        expect(coordinator.stage == .finished
               && coordinator.importedAdBlockers == [.init(identifier: known.identifier, displayName: known.displayName,
                                                           profileIDs: [destination.profileID])],
               "Results appear while a download is still running, and only known ad blockers carry on into setup with their Profile")
        downloading.background(["uBlock Origin"])
        expect(coordinator.warnings.filter { $0 == "uBlock Origin couldn’t be added." }.count == 1
               && ImportedExtensionFailures.pending.contains("uBlock Origin"),
               "A later failure is recorded once and waits for a browser window")
        expect(coordinator.importedAdBlockers.isEmpty && ImportedExtensionFailures.failedIdentifiers.contains(known.identifier),
               "An ad blocker whose download failed isn't offered in setup")
        var repeated = 0
        ImportedExtensionFailures.present = { repeated += 1 }
        downloading.background(["uBlock Origin"])
        expect(coordinator.warnings.filter { $0 == "uBlock Origin couldn’t be added." }.count == 1 && repeated == 0,
               "The same failure is never listed or announced twice")
        ImportedExtensionFailures.present = nil
        run()
        PCNativeBrowserApplication.rejectsExtensionInstall = true
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        PCNativeBrowserApplication.rejectsExtensionInstall = false
        expect(coordinator.stage == .finished && coordinator.warnings.contains("uBlock Origin couldn’t be added.")
               && coordinator.warnings.contains("Extension couldn’t be added."),
               "An install that can't begin lists each extension as a failure")
        coordinator.cancel()
        expect(ImportedExtensionFailures.take() == ["uBlock Origin", "Extension"],
               "With no results page, every failed extension waits for a browser window, once each")
        expect(ImportedBrowserDataFailures.take() == nil, "Imports whose data came in say nothing about it")
        var presented = 0
        ImportedExtensionFailures.present = { presented += 1 }
        downloading.background(["uBlock Origin"])
        ImportedExtensionFailures.add(["uBlock Origin"])
        expect(ImportedExtensionFailures.pending == ["uBlock Origin"] && presented == 2,
               "After the import has closed, a later failure waits for a browser window, once")
        expect(ImportedExtensionFailures.take() == ["uBlock Origin"] && ImportedExtensionFailures.pending.isEmpty,
               "Shown once, it is gone")
        ImportedExtensionFailures.present = nil
        return checks
    }

    @MainActor private static func backgroundCoordinatorChecks(directory: URL, source: PCNativeImportSource) throws -> Int {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(condition(), message)
        }
        let store = try BrowserStore(directory: directory.appendingPathComponent("Background"))
        let destination = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
        var window: NSWindow? = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        var current = true
        var coordinator: BrowserImportCoordinator? = BrowserImportCoordinator(store: store, destination: destination,
            window: window!, onboarding: true, ownerIsCurrent: { current })
        weak let retained = coordinator
        let blocker = PCNativeImportExtension(identifier: "cjpalhdlnbpafiamejdnhcphjbkeiagm", displayName: "uBlock Origin")
        let first = PCNativeImportProfile("background default", [.bookmarks, .history, .extensions], .complete, directory: "Default")
        first.extensions = [blocker]
        let second = PCNativeImportProfile("background second", [.bookmarks, .history], .complete, name: "Other")
        coordinator!.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([source])
        coordinator!.selectSourceInline(source)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [first, second], access: .complete))
        let start = PCNativeBrowserApplication.browserRequests.count
        coordinator!.continueSourceInline()
        expect(PCNativeBrowserApplication.browserRequests[start].categories == [.bookmarks]
               && !store.state.profiles.contains { $0.name == "Other" }, "Bookmarks start first and other destinations are lazy")
        let result = PCNativeImportResult(outcome: .completed, bookmarks: [PCNativeImportedBookmark()], warnings: [], error: nil)
        PCNativeBrowserApplication.browserCompletions.removeFirst()(result)
        expect(PCNativeBrowserApplication.browserRequests.count == start + 2
               && PCNativeBrowserApplication.browserRequests.last!.categories == [.bookmarks], "Every bookmark pass precedes background data")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(result)
        let requests = Array(PCNativeBrowserApplication.browserRequests.suffix(2))
        expect(coordinator!.stage == .bookmarks && coordinator!.hasBackgroundWork
               && PCNativeBrowserApplication.browserCompletions.count == 2
               && requests.allSatisfy { $0.categories == [.history] } && requests[0].path != requests[1].path,
               "Results appear with both profiles importing concurrently into distinct paths")
        var changes = 0, delivered: [OnboardingDraft.ImportedAdBlocker] = []
        coordinator!.onChange = { changes += 1 }
        coordinator!.detach { delivered = $0 }
        current = false; window = nil; coordinator = nil
        expect(retained != nil, "Detached work retains its coordinator after its owner closes")
        let firstCompletion = PCNativeBrowserApplication.browserCompletions.removeFirst()
        let secondCompletion = PCNativeBrowserApplication.browserCompletions.removeFirst()
        secondCompletion(.init(outcome: .failed, bookmarks: [], warnings: ["Some data was unavailable."], error: nil))
        expect(PCNativeBrowserApplication.extensionInstalls.isEmpty && retained!.hasBackgroundWork,
               "Extensions wait for every background profile, regardless of completion order")
        firstCompletion(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        let install = PCNativeBrowserApplication.extensionInstalls.removeFirst()
        expect(retained!.hasBackgroundWork && changes == 0, "Detached extension installation keeps ownership without updating closed views")
        expect(ImportedBrowserDataFailures.pending == nil, "A failed profile is reported only once the whole import is over")
        install.complete(.init(outcome: .partial, installedIdentifiers: [blocker.identifier], failedNames: ["Broken"]))
        expect(retained == nil && delivered == [.init(identifier: blocker.identifier, displayName: blocker.displayName,
                                                      profileIDs: [destination.profileID])]
               && ImportedExtensionFailures.pending.isEmpty && ImportedBrowserDataFailures.take() == .partial,
               "Completion delivers blockers, one partial-import toast that covers its failed extensions, and releases the coordinator")
        install.background([blocker.displayName])
        expect(ImportedExtensionFailures.take() == [blocker.displayName], "Failures arriving after detachment reach the browser window")

        let stopStore = try BrowserStore(directory: directory.appendingPathComponent("StopAfterFailure"))
        let stopWindow = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        let stopping = BrowserImportCoordinator(store: stopStore, destination: BrowserImportDestination(
            spaceID: stopStore.activeSpace.id, profileID: stopStore.activeSpace.profileID), window: stopWindow,
            onboarding: true, ownerIsCurrent: { true })
        let failingProfile = PCNativeImportProfile("stop failing", [.bookmarks], .complete, directory: "Default")
        let stoppedProfile = PCNativeImportProfile("stop later", [.bookmarks], .complete, name: "Later")
        stopping.discover(); PCNativeBrowserApplication.sources.removeFirst().complete([source])
        stopping.selectSourceInline(source)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [failingProfile, stoppedProfile], access: .complete))
        stopping.continueSourceInline()
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .failed, bookmarks: [], warnings: [], error: nil))
        expect(ImportedBrowserDataFailures.pending == nil, "Nothing is said while the import is still running")
        stopping.stopImport()
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .cancelled, bookmarks: [], warnings: [], error: nil))
        expect(stopping.stage == .finished && ImportedBrowserDataFailures.take() == .partial,
               "Stopping after a profile failed says so at once, as a partial import")
        stopping.cancel()
        expect(ImportedBrowserDataFailures.take() == nil, "Closing it afterwards says nothing more")
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
        func begin(_ name: String, sidebar: URL) throws -> (BrowserStore, BrowserImportDestination, BrowserImportCoordinator) {
            let store = try BrowserStore(directory: directory.appendingPathComponent(name))
            let destination = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
            let coordinator = BrowserImportCoordinator(store: store, destination: destination, window: window,
                arcSidebarURL: sidebar, arcPreferencesURL: preferences, ownerIsCurrent: { true })
            coordinator.discover()
            PCNativeBrowserApplication.sources.removeFirst().complete([arc])
            coordinator.select(arc); coordinator.loadProfiles()
            PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [standard, side, empty], access: .complete,
                constraints: ["Encrypted cookies may require macOS Keychain authorization."]))
            return (store, destination, coordinator)
        }
        PCNativeBrowserApplication.acceptsBrowserImport = true
        PCNativeBrowserApplication.browserCompletions = []

        let (stopped, _, stopping) = try begin("ArcStopped", sidebar: sidebar)
        expect(stopping.selectedProfiles == [standard.identifier, side.identifier],
               "Every readable Arc profile imports, as Chrome's do; an unreadable one doesn't")
        expect(stopping.warnings.isEmpty, "The importer's explanations of a profile are never recorded as warnings")
        let spaces = stopped.state.spaces, requests = PCNativeBrowserApplication.browserRequests.count
        stopping.continueSourceInline()
        expect(stopping.stage == .importing, "Next starts Arc's import straight from the profile choice, as Chrome's does")
        stopping.stopImport()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        expect(stopping.stage == .finished && stopped.state.spaces == spaces, "Stop while Arc's sidebar is read adds nothing")
        expect(PCNativeBrowserApplication.browserRequests.count == requests, "A stopped Arc import starts no native import")

        let (store, destination, coordinator) = try begin("ArcImport", sidebar: sidebar)
        coordinator.continueSourceInline()
        wait { PCNativeBrowserApplication.browserRequests.count > requests }
        let work = store.state.spaces.first { $0.title == "Work" }
        expect(work?.profileID == destination.profileID, "The default Arc profile's Spaces join the opened Profile")
        expect(store.state.tabs.contains { $0.spaceID == work?.id && $0.kind == .pinned }, "Arc's pinned tabs come with their Space")
        expect(store.state.tabs.contains { $0.kind == .today && $0.savedURL == "https://example.test/today" }, "Arc's Today tabs come over")
        guard let sideProfile = store.state.profiles.first(where: { $0.name == "Side" }) else {
            preconditionFailure("Arc's other profile becomes a Parc Profile of its name")
        }
        expect(store.state.spaces.contains { $0.title == "Side" && $0.profileID == sideProfile.id }, "Its Spaces join that Profile")
        expect(sideProfile.autoArchiveHours == 720 && store.state.profiles.first { $0.id == destination.profileID }?.autoArchiveHours
               == AutoArchiveInterval.twelveHours.rawValue, "Arc's archive age reaches only the Profile it was set for")
        expect(PCNativeBrowserApplication.browserRequests[requests].profile === standard
               && PCNativeBrowserApplication.browserRequests[requests].path == store.independentEngineProfilePath(for: destination.profileID),
               "The default profile's browser data imports into the opened Profile")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed,
            bookmarks: [PCNativeImportedBookmark("arc bookmark", title: "Docs", url: URL(string: "https://example.test/docs"))],
            warnings: ["fixture warning"], error: nil))
        expect(PCNativeBrowserApplication.browserRequests.count == requests + 3
               && PCNativeBrowserApplication.browserRequests[requests].categories == [.bookmarks]
               && PCNativeBrowserApplication.browserRequests[requests + 1].profile === standard
               && PCNativeBrowserApplication.browserRequests[requests + 2].profile === side
               && PCNativeBrowserApplication.browserRequests[requests + 2].path == store.independentEngineProfilePath(for: sideProfile.id),
               "Each other profile's data imports into its own Parc Profile")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        expect(coordinator.stage == .bookmarks && coordinator.bookmarkPages.first?.destination == destination,
               "Arc's data lands in the opened Space, as Chrome's does")
        expect(coordinator.warnings == ["fixture warning"],
               "The import reports only the native importer's own warnings, as Chrome's does")
        coordinator.cancel()
        expect(ImportedBrowserDataFailures.take() == nil, "A note about skipped records is not a failed import")

        let missing = directory.appendingPathComponent("NoArc/StorableSidebar.json")
        let (fallback, fallbackDestination, unreadable) = try begin("ArcUnreadable", sidebar: missing)
        let before = PCNativeBrowserApplication.browserRequests.count
        unreadable.continueSourceInline()
        wait { PCNativeBrowserApplication.browserRequests.count > before }
        expect(unreadable.warnings.isEmpty, "An unreadable sidebar is not reported; the browser data imports as Chrome's does")
        expect(PCNativeBrowserApplication.browserRequests[before].path == fallback.independentEngineProfilePath(for: fallbackDestination.profileID),
               "Without the sidebar, the default profile's data still imports into the opened Profile")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        let fallbackSide = fallback.state.profiles.first { $0.name == "Side" }
        expect(fallbackSide != nil && PCNativeBrowserApplication.browserRequests.last?.path == fallback.independentEngineProfilePath(for: fallbackSide!.id),
               "Without the sidebar, another profile still gets its own Parc Profile")
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
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
            onboarding: true, arcSidebarURL: sidebar, arcPreferencesURL: preferences, ownerIsCurrent: { true })
        setup.discover()
        PCNativeBrowserApplication.sources.removeFirst().complete([arc])
        setup.selectSourceInline(arc)
        PCNativeBrowserApplication.profiles.removeFirst().complete(.init(profiles: [withExtensions, onlyExtensions], access: .complete))
        let extensionStart = PCNativeBrowserApplication.browserRequests.count
        let installsBefore = PCNativeBrowserApplication.extensionInstalls.count
        setup.continueSourceInline()
        wait { PCNativeBrowserApplication.browserRequests.count > extensionStart }
        PCNativeBrowserApplication.browserCompletions.removeFirst()(.init(outcome: .completed, bookmarks: [], warnings: [], error: nil))
        let sideID = extensionStore.state.profiles.first { $0.name == "Side" }?.id
        expect(PCNativeBrowserApplication.browserRequests.count == extensionStart + 1
               && PCNativeBrowserApplication.extensionInstalls.count == installsBefore + 1 && sideID != nil,
               "A profile with only extensions needs no data import, and one install follows the last profile")
        let together = PCNativeBrowserApplication.extensionInstalls.removeLast()
        expect(together.requests.count == 2
               && together.requests[0].source === withExtensions
               && together.requests[0].extensionIDs == [blocker.identifier, broken.identifier]
               && together.requests[1].source === onlyExtensions
               && together.requests[1].extensionIDs == [blocker.identifier, helper.identifier]
               && together.requests[1].profilePath == extensionStore.independentEngineProfilePath(for: sideID!)
               && setup.stage == .finished && setup.hasBackgroundWork,
               "One install covers every Arc profile's extensions, each into its own Parc Profile")
        together.complete(.init(outcome: .partial, installedIdentifiers: [blocker.identifier, helper.identifier],
                                failedNames: ["Broken"]))
        expect(setup.stage == .finished && setup.warnings.contains("Broken couldn’t be added.")
               && setup.importedAdBlockers == [.init(identifier: blocker.identifier, displayName: blocker.displayName,
                                                     profileIDs: [extensionDestination.profileID, sideID!])],
               "A failure among several is listed with the import's other failures and the rest are added, "
                   + "an ad blocker once with every Profile it went into")
        setup.cancel()
        PCNativeBrowserApplication.acceptsBrowserImport = false
        return checks
    }
}
