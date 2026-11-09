import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation, PCNativeBrowserApplicationClient {
    private var videoPictureInPictureWindows: [(presenter: PCVideoPiPPresenter, frame: VideoPictureInPictureFrame)] = []

    func createVideoPictureInPictureWindow(videoView: NSView, sourceFrame: NSRect,
        action: @escaping (PCVideoPiPAction, Double) -> Void,
        changed: @escaping () -> Void) -> any PCNativeVideoPiPWindow {
        let presenter = PCVideoPiPPresenter(videoView: videoView, sourceFrame: sourceFrame,
                                            action: action, changed: changed)
        videoPictureInPictureWindows.append((presenter, VideoPictureInPictureFrame(presenter: presenter)))
        return presenter
    }

    func releaseVideoPictureInPictureWindow(_ window: any PCNativeVideoPiPWindow) {
        window.invalidate()
        videoPictureInPictureWindows.removeAll { entry in
            guard entry.presenter === window else { return false }
            entry.frame.invalidate()
            return true
        }
    }

    private var store: BrowserStore!
    private var aboutWindow: AboutParcWindow?
    private var onboarding: OnboardingWindow?
    private var replayCloseInProgress = false
    private struct ReplayWindow {
        let record: BrowserWindowRecord
        let frame: NSRect
        let wasVisible: Bool
        let wasMiniaturized: Bool
        let wasFullScreen: Bool
    }
    private var replayWindow: ReplayWindow?
    private var replayReturnOwner: BrowserWindowController?
    private var replaySessionActive = false
    // Keep these exact owners alive: recreating a popup or a private browser
    // would lose its native context even if its saved tabs looked identical.
    private var hiddenReplayWindows: [BrowserWindowController] = []
    private var deferredReplayTermination: (() -> Void)?
    private var replayRestoreError: Error?
    private var replayRestoreAlert: NSAlert?
    private var browserImport: BrowserImportWindow?
    private var applicationSettings: SettingsWindow?
    private var applicationSettingsProfileID: UUID?
    private var initialBrowserOpened = false
    private var restorationLaunch = WindowRestorationLaunch()
    private var drainingInitialActions = false
    private weak var deferredNoteOwner: BrowserWindowController?
    private var deferredNoteOwnerCreated = false
    private var appKitRestoredWindowIDs = Set<UUID>()
    private var earlyDownloadWindowIDs = Set<UUID>()
    private var pendingAppKitRestorations: [(UUID, (NSWindow?, Error?) -> Void)] = []
    private var appKitRestorationCancelled = false
    private var sessionRestorationInitialized = false
    private var unrestoredWindowRecords: [BrowserWindowRecord] = []
    /// After a crash or an update every saved window comes back; otherwise only
    ///
    private var restoresEveryWindow = false
    private var launchWindowID: UUID?
    private var requiresOnboarding: Bool {
        store != nil && !arguments.contains("--parc-smoke") && !store.state.settings.onboardingComplete
    }
    private var windows: [BrowserWindowController] = []
    private var miniPlayerRefreshPending = false
    private var devToolsWindows: [DevToolsWindowController] = []
    private var pictureInPictureWindows: [PictureInPictureWindowController] = []
    private weak var lastActiveWindow: BrowserWindowController?
    private let pageOwnership = NativePageOwnership()
    private var started = false
    private var historyDeletionObserver: NSObjectProtocol?
    private var terminationInProgress = false
    private var applicationRestart: ApplicationRestart?
    private var restartCompletion: ((String?) -> Void)?
    private var pendingImportResume: BrowserImportRestartIntent?
    /// The import owner whose restart is pending, so another owner cannot cancel it.
    private weak var restartOwner: AnyObject?
    /// The armed restart reopens a saved replay; any other quit discards that draft.
    private var armedReplayRestart = false
    private var quitWarning: ApplicationQuitWarning?
    private var quitWarningApprovalPending = false
    /// Set only while the Quit command's own terminate runs.
    private var quitCommandPending = false
    private var privateWindowCreations: [UUID: PendingBrowserCreation<BrowserWindowController>] = [:]
    private let archiveScheduling = ArchiveScheduling()
    private var pendingURLs: [URL] = []
    private var pendingRelaunches: [NativeRelaunchRequest] = []
    private weak var spacesMenu: NSMenu?
    private weak var windowCommandsMenu: NSMenu?
    private var windowCommandsMenuIsTracking = false
    private final class StayOnTopSelection {
        weak var owner: BrowserWindowController?
        weak var window: NSWindow?
        init(owner: BrowserWindowController, window: NSWindow) { self.owner = owner; self.window = window }
    }
    private var stayOnTopWindow: BrowserWindowController? {
        let candidates = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 } + NSApp.orderedWindows
        for window in candidates {
            if let owner = windows.first(where: { $0.window === window }) { return owner }
        }
        return nil
    }
    private var spacesMenuIsTracking = false
    private var spaceMenuSubscription: AnyCancellable?
    private var registeredSpaceCommandIDs = Set<String>()
    /// What the Spaces menu was last built from. Each window activation asks
    /// for it again, and a rebuild registers every entry anew, each one
    /// refreshing every live shortcut tooltip, so unchanged entries are kept.
    private struct SpacesMenuSource: Equatable {
        weak var owner: BrowserWindowController?
        let activeSpaceID: UUID?
        let spaceIDs: [UUID]
        let names: [String]
        let profileIDs: [UUID]
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.owner === rhs.owner && lhs.activeSpaceID == rhs.activeSpaceID && lhs.spaceIDs == rhs.spaceIDs
                && lhs.names == rhs.names && lhs.profileIDs == rhs.profileIDs
        }
    }
    private var spacesMenuSource: SpacesMenuSource?
    private weak var easelsMenu: NSMenu?
    private weak var splitCommandsMenu: NSMenu?
    private var splitMenuIsTracking = false
    private weak var selectionEditMenu: NSMenu?
    private weak var selectionFileMenu: NSMenu?
    private var selectionMenuIsTracking = false
    private weak var scriptPermissionMenu: NSMenu?
    private var scriptPermissionMenuIsTracking = false
    private let arguments = ProcessInfo.processInfo.arguments
    private var front: BrowserWindowController? {
        let ready = windows.filter(\.hasReadyPresentation)
        return ready.first { $0.window === NSApp.keyWindow || $0.window === NSApp.mainWindow }
            ?? lastActiveWindow.flatMap { candidate in ready.contains { $0 === candidate } ? candidate : nil }
            ?? ready.last
    }

    // Unlike general app commands, Space navigation never falls back to a
    // previously active browser behind Settings, Downloads or another window.
    private var spaceCommandWindow: BrowserWindowController? {
        windows.first { $0.ownsSpaceCommandFocus }
    }

    /// An owned command panel or history chooser can request an operation
    /// that dismisses it and revalidates the same browser before proceeding.
    private var browserWindowCommandOwner: BrowserWindowController? {
        windows.first { $0.ownsWindowCommandFocus && $0.windowCommandSecurityAvailable }
    }

    /// Copy URL also belongs to an owned command panel, but not to a
    /// navigation-history chooser or an unrelated auxiliary window.
    private var browserCopyCommandOwner: BrowserWindowController? {
        windows.first { $0.ownsSpaceCommandFocus && $0.windowCommandSecurityAvailable }
    }

    /// Native input commands require the browser itself to be key.
    private var browserInputCommandWindow: BrowserWindowController? {
        guard let owner = browserWindowCommandOwner, let window = owner.window,
              window.isKeyWindow, PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return nil }
        return owner
    }

    private func scheduleMiniPlayerRefresh() {
        // BrowserWindowController.refreshMiniPlayers gates ordinary chrome
        // ticks when its mini-player source signature is unchanged; window
        // open/close and forced transfer paths still enter here.
        guard !miniPlayerRefreshPending, !terminationInProgress else { return }
        miniPlayerRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.miniPlayerRefreshPending = false
            guard !self.terminationInProgress else { return }
            let owners = self.windows
            guard !owners.isEmpty else { return }
            // Retire invalid sources across every window before any new
            // admission can evict an otherwise live episode.
            owners.forEach { $0.prepareMiniPlayerSourcesForAdmission() }
            for host in owners {
                host.applyMiniPlayers(owners.flatMap { $0.miniPlayerItems(for: host) })
            }
        }
    }

    private var libraryCommandWindow: BrowserWindowController? {
        windows.first { $0.ownsWindowCommandFocus && $0.windowCommandSecurityAvailable }
    }
    private var canCreateNoteWithoutBrowser: Bool {
        started && !terminationInProgress && NSApp.isActive && NSApp.keyWindow == nil
            && !windows.contains(where: { $0.hasReadyPresentation })
    }
    private func performLibraryMenuCommand(_ action: (BrowserWindowController) -> Void) {
        guard let owner = libraryCommandWindow, let original = owner.window else { return }
        let profileID = owner.activeProfileID
        guard owner.prepareLibraryMenuCommand(), owner.window === original,
              owner.activeProfileID == profileID, libraryCommandWindow === owner else { return }
        action(owner)
    }
    private final class EaselMenuSelection {
        weak var owner: BrowserWindowController?
        let profileID: UUID
        let id: UUID
        init(owner: BrowserWindowController, profileID: UUID, id: UUID) {
            self.owner = owner; self.profileID = profileID; self.id = id
        }
    }

    private final class SpaceMenuSelection {
        weak var owner: BrowserWindowController?
        let spaceID: UUID
        let profileID: UUID
        init(owner: BrowserWindowController?, space: BrowserSpace) {
            self.owner = owner; spaceID = space.id; profileID = space.profileID
        }
    }

    private func argument(_ name: String) -> String? {
        if let joined = arguments.first(where: { $0.hasPrefix(name + "=") }) {
            return String(joined.dropFirst(name.count + 1))
        }
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    enum StartupResult { case ready, exit(Int32) }

    func prepare() -> StartupResult {
        var failureExitCode: Int32 = 1
        do {
            let root: URL
            if let path = argument("--parc-profile") { root = URL(fileURLWithPath: path, isDirectory: true) }
            else {
                root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true).appendingPathComponent("Parc", isDirectory: true)
            }
            store = try BrowserStore(directory: root)
            // With session restore off, every tab starts afresh.
            store.tabHistory?.prune(keeping: store.state.settings.restoreSession
                ? Set(store.state.tabs.lazy.filter { $0.archivedAt == nil }.map(\.id)) : [])
            // Deleted history must not come back as an unloaded tab's back/forward
            // entries, nor stay in the visits behind the command bar.
            historyDeletionObserver = NotificationCenter.default.addObserver(
                forName: TopBarColorClient.historyDidDeleteNotification, object: nil, queue: .main
            ) { [weak self] note in
                let deletion = ChromiumHistoryDeletion(userInfo: note.userInfo ?? [:])
                MainActor.assumeIsolated {
                    self?.store?.tabHistory?.removeAll()
                    self?.store?.forgetHistory(deletion)
                }
            }
            store.requestPageRetirement = { [weak self] ids, shouldCommit, completion in
                guard let self else { completion(false); return }
                self.retireNativePages(ids, shouldCommit: shouldCommit, completion: completion)
            }
            store.prepareLocalDocumentRelocation = { [weak self] ids in
                self?.prepareLocalDocumentRelocation(ids)
            }
            store.relocateLocalDocuments = { [weak self] ids, pages, from, to in
                guard let self else { throw CocoaError(.userCancelled) }
                return try self.relocateLocalDocuments(ids, pages: pages, from: from, to: to)
            }
            KeyboardShortcuts.shared.configure(directory: root)
            LiveShortcutToolTip.binder = { view, title, id, requiresBinding in
                KeyboardShortcuts.shared.bindHelp(view, title: title, commandID: id, requiresBinding: requiresBinding)
            }
            LiveShortcutToolTip.resolver = { title, id in KeyboardShortcuts.shared.toolTip(title, for: id) }
            TooltipController.commandShortcut = { KeyboardShortcuts.shared.activeShortcut(for: $0) }
            KeyboardShortcuts.shared.onDiscoveryChange = {
                NotificationCenter.default.post(name: LiveShortcutToolTip.didChange, object: nil)
            }
            AppAppearance.restore()
            buildMenus()
            // Keep dynamic numbered commands live before the user opens a menu.
            // Space-only changes avoid invalidating shortcuts on ordinary page updates.
            spaceMenuSubscription = store.statePublisher.map(\.spaces).removeDuplicates()
                .receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshSpaceCommands() }
            guard let frameworks = Bundle.main.privateFrameworksPath else {
                throw NSError(domain: "Parc", code: 1, userInfo: [NSLocalizedDescriptionKey: "The browser engine is missing from this build."])
            }
            unrestoredWindowRecords = store.state.settings.restoreSession ? store.windowRecords : []
            launchWindowID = unrestoredWindowRecords.first?.id
            beginLaunchContinuity(root: root)
            sessionRestorationInitialized = true
            // Install before engine startup: AppKit may begin restoration while
            // CEF initializes, before Parc can create a native browser owner.
            NotificationCenter.default.addObserver(self, selector: #selector(didFinishRestoringWindows(_:)),
                name: NSApplication.didFinishRestoringWindowsNotification, object: NSApp)
            NotificationCenter.default.addObserver(self, selector: #selector(didEndWindowSheet(_:)),
                name: NSWindow.didEndSheetNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(didChangeWindowKeyContext(_:)),
                name: NSWindow.didResignKeyNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(didChangeWindowKeyContext(_:)),
                name: NSWindow.willCloseNotification, object: nil)
            PCNativeBrowserApplication.setApplicationClient(self)
            NativeMessagingHosts.link(engineRoot: store.independentEngineRoot,
                                      sources: NativeMessagingHosts.sourceDirectories(home: FileManager.default.homeDirectoryForCurrentUser))
            let startup = PCBrowserEngine.start(frameworkPath: frameworks + "/Chromium Embedded Framework.framework", cachePath: store.independentEngineRoot.path)
            switch startup.status {
            case .earlyExit:
                // CEF's singleton handoff and other normal early exits are not
                // errors. Preserve the engine's code without showing browser UI.
                cancelPendingAppKitRestorations()
                return .exit(startup.exitCode)
            case .failed:
                failureExitCode = startup.exitCode
                throw startup.error ?? NSError(domain: "Parc", code: Int(startup.exitCode), userInfo: [NSLocalizedDescriptionKey: "The browser engine could not start."])
            case .ready:
                trace("runtime.application=" + NSStringFromClass(type(of: NSApp)))
                started = true
                pendingImportResume = try? BrowserImportRestartIntent.take(from: root)
                if pendingImportResume?.replay != true { Self.removeReplayRestartDraft(in: root) }
                ProfileRemovalController.shared.configure(store: store)
                // Only a window someone is looking at; otherwise the next one to become key.
                let presentImportFailures = { [weak self] in
                    guard NSApp.isActive, let front = self?.front, front.window?.isKeyWindow == true else { return }
                    front.showImportFailures()
                }
                ImportedExtensionFailures.present = presentImportFailures
                ImportedBrowserDataFailures.present = presentImportFailures
                // Safari's identity for learned FairPlay sites, before any page loads.
                FairPlayIdentityController.shared.start(profilePaths: store.state.profiles.map {
                    store.independentEngineProfilePath(for: $0.id)
                })
                // Only a run that actually started counts: a failed start or a
                // launch handed to an already running Parc leaves the marker.
                LaunchContinuity(running: true, build: Self.buildIdentity).write(in: root)
                resumePendingAppKitRestorations()
                return .ready
            @unknown default:
                throw NSError(domain: "Parc", code: 1, userInfo: [NSLocalizedDescriptionKey: "The browser engine returned an unsupported startup result."])
            }
        } catch {
            cancelPendingAppKitRestorations()
            if arguments.contains("--parc-smoke") {
                FileHandle.standardError.write(Data(("Parc startup failed: " + error.localizedDescription + "\n").utf8))
                return .exit(failureExitCode)
            }
            let alert = NSAlert()
            alert.messageText = "Parc couldn’t start"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
            return .exit(failureExitCode)
        }
    }

    func openInitialWindow() {
        NSApp.finishLaunching()
        AppIconController.shared.configure(directory: store.directory, updatesSystemIdentity: argument("--parc-profile") == nil)
        restorationLaunch.finishLaunch()
        finishInitialLaunchIfReady()
    }

    @objc private func didFinishRestoringWindows(_ notification: Notification) {
        restorationLaunch.finishRestoration()
        finishInitialLaunchIfReady()
    }

    private func finishInitialLaunchIfReady() {
        guard restorationLaunch.mayPresent(terminating: terminationInProgress, cancelled: appKitRestorationCancelled) else { return }
        if requiresOnboarding { showOnboarding() } else { finishInitialBrowserPresentation() }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func resumePendingAppKitRestorations() {
        guard started, !terminationInProgress else { return }
        let restorations = pendingAppKitRestorations
        pendingAppKitRestorations.removeAll()
        for (id, completion) in restorations { restoreBrowserWindow(id: id, completion: completion) }
    }

    private func cancelPendingAppKitRestorations() {
        appKitRestorationCancelled = true
        let restorations = pendingAppKitRestorations
        pendingAppKitRestorations.removeAll()
        for (_, completion) in restorations { completion(nil, nil) }
    }

    func restoreBrowserWindow(id: UUID, completion: @escaping (NSWindow?, Error?) -> Void) {
        guard !appKitRestorationCancelled, store != nil, !requiresOnboarding, store.state.settings.restoreSession else {
            completion(nil, nil); return
        }
        if WindowRestorationLaunch.shouldDeferWindow(engineReady: started, terminating: terminationInProgress) {
            pendingAppKitRestorations.append((id, completion)); return
        }
        guard let record = unrestoredWindowRecords.first(where: { $0.id == id }),
              LaunchContinuity.accepts(record.id, launchWindowID: launchWindowID, everyWindow: restoresEveryWindow),
              !windows.contains(where: { $0.sessionID == id }) else { completion(nil, nil); return }
        do {
            let controller = try makeBrowserWindow(renderInitialSelection: true, showImmediately: false, restoredRecord: record)
            appKitRestoredWindowIDs.insert(id)
            completion(controller.window, nil)
        } catch { completion(nil, error) }
    }

    private func showOnboarding() {
        guard !terminationInProgress, !replayCloseInProgress else { return }
        if let onboarding { onboarding.resume(); return }
        do {
            let controller = try OnboardingWindow(store: store)
            controller.onCancel = { [weak self] in self?.onboarding = nil }
            controller.onComplete = { [weak self, weak controller] in
                guard let self, !self.terminationInProgress else { throw CocoaError(.userCancelled) }
                guard let controller, self.onboarding === controller else { throw CocoaError(.userCancelled) }
                // Prepare the real browser while the welcome owner still holds
                // presentation. Its close callback performs the first reveal.
                _ = try self.makeBrowserWindow(renderInitialSelection: true, showImmediately: false)
            }
            controller.onRevealCompleted = { [weak self] in
                guard let self else { return }
                self.onboarding = nil
                self.finishInitialBrowserPresentation()
            }
            controller.onRequestImportRestart = { [weak self, weak controller] intent, completion in
                guard let self else { completion("This import is no longer available."); return }
                self.requestBrowserImportRestart(intent, ownerIsCurrent: { [weak self, weak controller] in
                    guard let self, let controller else { return false }
                    return self.onboarding === controller && controller.hasActiveBrowserImport
                }, completion: completion)
            }
            controller.onCancelImportRestart = { [weak self] in
                guard let self, !self.terminationInProgress else { return }
                self.cancelApplicationRestart("Restart cancelled.")
            }
            onboarding = controller
            controller.present()
            resumeBrowserImportIfNeeded()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Parc couldn’t restore setup."
            alert.informativeText = "Your browser data has been kept. You can restart setup or quit and try again.\n\n" + error.localizedDescription
            alert.addButton(withTitle: "Restart Setup")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertFirstButtonReturn {
                do { try OnboardingDraft.remove(directory: store.directory); showOnboarding() }
                catch { NSAlert(error: error).runModal() }
            } else { requestApplicationTermination(nil) }
        }
    }

    /// Replay uses the production flow. The ordinary window-close transaction
    /// resolves notes, Settings and page beforeunload before welcome is shown.
    @objc func replayOnboarding(_ sender: Any?) {
        guard let settings = sender as? SettingsWindow,
              started, initialBrowserOpened, !terminationInProgress, !replayCloseInProgress,
              quitWarning == nil, !quitWarningApprovalPending else { return }
        if replayRestoreError != nil { presentReplayRestoreFailure(); return }
        if let onboarding {
            guard settings.attemptClose() else { return }
            onboarding.resume()
            return
        }
        do {
            guard let spaceID = settings.replaySpaceID else { throw BrowserScriptError.missing }
            let original = windows.first(where: { $0.ownsSettings(settings) })
                ?? (settings === applicationSettings ? front : nil)
            guard original != nil || settings === applicationSettings else { throw BrowserScriptError.missing }
            let controller = try makeOnboardingReplay(.replay(spaceID: spaceID))
            guard settings.attemptClose() else { return }
            Self.removeReplayRestartDraft(in: store.directory)
            try startOnboardingReplay(controller, closing: original)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Parc couldn’t replay onboarding."
            if let window = settings.window, window.isVisible, window.attachedSheet == nil { alert.beginSheetModal(for: window) }
            else { alert.runModal() }
        }
    }

    private func startOnboardingReplay(_ controller: OnboardingWindow, closing original: BrowserWindowController?,
                                       onPresented: (() -> Void)? = nil) throws {
        guard !terminationInProgress, !replayCloseInProgress, !replaySessionActive else { throw BrowserScriptError.busy }
        if let original {
            guard windows.contains(where: { $0 === original }), original.hasReadyPresentation,
                  original.window != nil else { throw BrowserScriptError.busy }
        }
        let closesOriginal = original.map { $0.store === store && !$0.isPopupWindow } ?? false
        if closesOriginal, let original {
            guard original.prepareNotesToClose() else { throw CocoaError(.userCancelled) }
            try NoteStore.flushAllSharedDelayedDiskSaves()
        }
        recordWindowSessions()
        persistTabHistory()
        try store.save()
        if closesOriginal, let original, let window = original.window {
            replayWindow = ReplayWindow(record: original.sessionRecord, frame: window.frame,
                                        wasVisible: window.isVisible, wasMiniaturized: window.isMiniaturized,
                                        wasFullScreen: window.styleMask.contains(.fullScreen))
        }
        replayReturnOwner = original
        replaySessionActive = true
        replayCloseInProgress = true
        onboarding = controller
        let finishClose: (Bool) -> Void = { [weak self, weak controller] approved in
            // windowWillClose completes before AppDelegate's onClose removes
            // the original owner. Continue after that notification unwinds.
            DispatchQueue.main.async {
                guard let self, let controller, self.onboarding === controller else { return }
                self.replayCloseInProgress = false
                if !approved {
                    // Cancel means retain this window and cancel replay. A Quit
                    // queued behind the same consent must not immediately ask again.
                    self.deferredReplayTermination = nil
                    self.cancelApplicationRestart("Restart cancelled. Your browser is still open.")
                    self.finishOnboardingReplay()
                } else if self.deferredReplayTermination != nil {
                    // Finish the local close before a global close can touch its
                    // reservation. Restore first so a denied Quit retains a browser.
                    self.finishOnboardingReplay()
                } else {
                    self.hiddenReplayWindows = NSApp.orderedWindows.compactMap { window in
                        self.windows.first { $0.window === window && window.isVisible && !window.isMiniaturized }
                    }
                    self.hiddenReplayWindows.forEach { $0.window?.orderOut(nil) }
                    controller.present()
                    onPresented?()
                }
            }
        }
        // Settings also exists for private browsers and popups. Preserve those
        // exact native owners; only a regular browser is closed and reconstructed.
        if closesOriginal, let original { original.closeForOnboarding(completion: finishClose) }
        else if let original { original.prepareAuxiliaryWindowForOnboarding(completion: finishClose) }
        else { finishClose(true) }
    }

    private func restoreReplayWindow() throws -> BrowserWindowController? {
        guard let saved = replayWindow else {
            if let original = replayReturnOwner,
               let live = windows.first(where: { $0 === original && $0.hasReadyPresentation }) { return live }
            // Application Settings can outlive its browser, and an auxiliary
            // page can close itself while replay is up. Never reconstruct that
            // private/popup context; return to a normal browser instead.
            return try windows.first(where: { $0.store === store && !$0.isPopupWindow && $0.hasReadyPresentation })
                ?? makeBrowserWindow(renderInitialSelection: true, showImmediately: false)
        }
        if let owner = windows.first(where: { $0.sessionID == saved.record.id }) { return owner }
        let owner = try makeBrowserWindow(renderInitialSelection: true, showImmediately: false,
                                          restoredRecord: saved.record)
        owner.window?.setFrame(saved.frame, display: false)
        return owner
    }

    private func makeOnboardingReplay(_ mode: OnboardingWindow.Mode) throws -> OnboardingWindow {
        let controller = try OnboardingWindow(store: store, mode: mode)
        controller.onComplete = { [weak self, weak controller] in
            guard let self, let controller, self.onboarding === controller,
                  !self.terminationInProgress else { throw CocoaError(.userCancelled) }
            guard let browser = try self.restoreReplayWindow() else { throw BrowserScriptError.missing }
            self.lastActiveWindow = browser
        }
        controller.onCancel = { [weak self, weak controller] in
            guard let self, let controller, self.onboarding === controller else { return }
            self.finishOnboardingReplay()
        }
        controller.onRevealCompleted = { [weak self, weak controller] in
            guard let self, let controller, self.onboarding === controller else { return }
            self.finishOnboardingReplay()
        }
        controller.onRequestImportRestart = { [weak self, weak controller] intent, completion in
            guard let self, let controller else { completion("This import is no longer available."); return }
            let directory = self.store.directory
            do { try controller.saveReplayForImportRestart() }
            catch { completion(error.localizedDescription); return }
            // Completed setup has no onboarding gate after relaunch; the replay
            // intent tells the ordinary resume to reopen this saved replay.
            let resumed = BrowserImportRestartIntent(destination: intent.destination, onboarding: false,
                                                     replay: true, sourceBundleID: intent.sourceBundleID)
            self.requestBrowserImportRestart(resumed, owner: controller, ownerIsCurrent: { [weak self, weak controller] in
                guard let self, let controller else { return false }
                return self.onboarding === controller && controller.hasActiveBrowserImport
            }, completion: { failure in
                Self.removeReplayRestartDraft(in: directory)
                completion(failure)
            })
        }
        controller.onCancelImportRestart = { [weak self, weak controller] in
            guard let self, let controller, !self.terminationInProgress,
                  self.restartOwner === controller else { return }
            self.cancelApplicationRestart("Restart cancelled.")
        }
        return controller
    }

    private func finishOnboardingReplay() {
        guard !terminationInProgress else { return }
        let browser: BrowserWindowController
        do {
            guard let restored = try restoreReplayWindow() else { return }
            browser = restored
        } catch {
            replayRestoreError = error
            presentReplayRestoreFailure()
            return
        }
        let saved = replayWindow
        replayWindow = nil
        replayReturnOwner = nil
        replaySessionActive = false
        replayRestoreError = nil
        onboarding?.suspend()
        onboarding = nil
        for owner in hiddenReplayWindows.reversed() where windows.contains(where: { $0 === owner }) {
            owner.window?.orderFront(nil)
        }
        hiddenReplayWindows.removeAll()
        lastActiveWindow = browser
        if let saved, let window = browser.window {
            if saved.wasMiniaturized { window.miniaturize(nil) }
            else if saved.wasVisible {
                window.makeKeyAndOrderFront(nil)
                if saved.wasFullScreen && !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            }
        } else if browser.window?.isMiniaturized != true {
            browser.window?.makeKeyAndOrderFront(nil)
        }
        recordWindowSessions()
        deliverPendingBrowserRequests(to: browser)
        NSApp.activate(ignoringOtherApps: true)
        refreshVisibleActivity()
        let deferred = deferredReplayTermination
        deferredReplayTermination = nil
        deferred?()
    }

    private func presentReplayRestoreFailure() {
        // onCancel runs inside the setup window's close notification. Do not
        // attach the recovery UI to that closing owner or clear its saved record.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.replaySessionActive, let error = self.replayRestoreError,
                  !self.terminationInProgress, self.replayRestoreAlert == nil else { return }
            let alert = NSAlert()
            alert.messageText = "Parc couldn’t restore your browser window."
            alert.informativeText = "Your saved tabs and window are retained. \(error.localizedDescription)"
            alert.addButton(withTitle: "Retry")
            alert.addButton(withTitle: "Quit")
            self.replayRestoreAlert = alert
            let response = alert.runModal()
            self.replayRestoreAlert = nil
            if response == .alertFirstButtonReturn { self.finishOnboardingReplay() }
            else { self.requestApplicationTermination(nil) }
        }
    }

    private func resumeOnboardingAfterCancelledTermination() {
        if replayRestoreError != nil { presentReplayRestoreFailure() }
        else if !replayCloseInProgress { onboarding?.resume() }
    }

    private func finishInitialBrowserPresentation() {
        guard restorationLaunch.mayPresent(terminating: terminationInProgress, cancelled: appKitRestorationCancelled), !initialBrowserOpened, !requiresOnboarding else { return }
        // AppKit resolves original identifiers first. An early synchronous
        // download prompt may have made an empty owner, so it must not suppress
        // the legacy fallback record when AppKit restored no browser windows.
        func regularLaunchOwners() -> [BrowserWindowController] {
            windows.filter { WindowRestorationLaunch.isRegularLaunchOwner(mainStore: $0.store === store,
                                                                           popup: $0.isPopupWindow, ready: $0.hasReadyPresentation) }
        }
        func regularLaunchOwner() -> BrowserWindowController? {
            let eligible = regularLaunchOwners()
            let activeIndex = eligible.firstIndex { $0 === lastActiveWindow }
            let index = WindowRestorationLaunch.preferredOwner(
                keyOrMain: eligible.map { $0.window === NSApp.keyWindow || $0.window === NSApp.mainWindow },
                lastActiveIndex: activeIndex)
            return index.map { eligible[$0] }
        }
        let regular = regularLaunchOwners()
        let hasRestoredWindow = regular.contains { appKitRestoredWindowIDs.contains($0.sessionID) }
        let hasOtherLaunchOwner = regular.contains { !earlyDownloadWindowIDs.contains($0.sessionID) }
        let shouldRestoreFallback = WindowRestorationLaunch.shouldRestoreFallback(hasRestoredOwner: hasRestoredWindow,
                                                                                  hasOtherLaunchOwner: hasOtherLaunchOwner)
        let record = shouldRestoreFallback && store.state.settings.restoreSession ? unrestoredWindowRecords.first : nil
        var fallback: BrowserWindowController?
        if record != nil || regularLaunchOwner() == nil {
            fallback = createStandardWindow(showCommandBar: false, restoring: record)
        }
        let liveFallback = fallback.flatMap { candidate in regularLaunchOwners().contains(where: { $0 === candidate }) ? candidate : nil }
        guard !initialBrowserOpened, let launchOwner = liveFallback ?? regularLaunchOwner() else { return }
        initialBrowserOpened = true
        recordWindowSessions()
        if !hasRestoredWindow { launchOwner.window?.makeKeyAndOrderFront(nil) }
        if let input = argument("--parc-open") { launchOwner.openInput(input) }
        // Test instances only: `--parc-settings=Advanced` (a Pane rawValue)
        // opens Settings so it can be captured without keyboard or menu input.
        if arguments.contains("--parc-smoke"), let name = argument("--parc-settings") {
            launchOwner.showSettings(pane: SettingsWindow.Pane(rawValue: name) ?? .membership)
        }
        deliverPendingBrowserRequests(to: launchOwner)
        if !hasRestoredWindow { NSApp.activate(ignoringOtherApps: true) }
        if restorationLaunch.takeDockReopen() {
            _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        }
        drainInitialActions()
        refreshVisibleActivity()
        //
        // separate 300s/6h clocks. Wake belongs to its update-idle tracker,
        // not Archive: let the continuous clocks resume their own deadlines.
        for job in [ArchiveScheduling.Job.initialArchive, .archive] {
            archiveScheduling.start(job) { [weak self] in
                guard let self, !self.terminationInProgress else { return }
                self.runArchiveSweep()
            }
        }
        for job in [ArchiveScheduling.Job.initialCleanup, .cleanup] {
            archiveScheduling.start(job) { [weak self] in
                guard let self, !self.terminationInProgress else { return }
                self.store.cleanExpiredArchive()
            }
        }
        resumeBrowserImportIfNeeded()
    }

    private func deliverPendingBrowserRequests(to owner: BrowserWindowController) {
        let urls = pendingURLs; pendingURLs.removeAll()
        deliverExternalURLs(urls, preferredOwner: owner)
        let relaunches = pendingRelaunches; pendingRelaunches.removeAll()
        for request in relaunches { handleNativeRelaunch(request) }
    }

    private func refreshVisibleActivity() {
        store.refreshVisibleTabs(windows.reduce(into: Set<UUID>()) { $0.formUnion($1.visibleTabIDsForActivity) })
    }

    private func retireNativePages(_ ids: Set<UUID>, shouldCommit: @escaping () -> Bool,
                                   completion: @escaping (Bool) -> Void) {
        guard !terminationInProgress,
              !windows.contains(where: { $0.hasPendingNativePage(in: ids) }) else { completion(false); return }
        func noteOwners(_ windows: [BrowserWindowController]) -> [ObjectIdentifier: [UUID: NoteEditorViewController]] {
            Dictionary(uniqueKeysWithValues: windows.compactMap { owner in
                let editors = owner.noteEditorsForRetirement(in: ids)
                return editors.isEmpty ? nil : (ObjectIdentifier(owner), editors)
            })
        }
        // Retain the actual original editors through the async decision; pointer
        // identities alone could be recycled after an owner is replaced.
        let originalNoteOwners = noteOwners(windows)
        func notesAreOriginal(_ windows: [BrowserWindowController]) -> Bool {
            let current = noteOwners(windows)
            return Set(current.keys) == Set(originalNoteOwners.keys) && current.allSatisfy { owner, editors in
                editors.mapValues(ObjectIdentifier.init) == originalNoteOwners[owner]?.mapValues(ObjectIdentifier.init)
            }
        }
        guard windows.allSatisfy({ $0.prepareNotesToClose(ids) }),
              notesAreOriginal(windows) else { completion(false); return }
        var pages: [(owner: BrowserWindowController, id: UUID, page: PCNativePage)] = []
        var seen = Set<ObjectIdentifier>()
        for owner in windows {
            for id in ids {
                let attached = owner.nativePage(forTabID: id).map { [$0] } ?? []
                let children = owner.peekPages(forTabID: id) + owner.embeddedEaselPages(forTabID: id)
                if !attached.isEmpty || !children.isEmpty {
                    guard owner.canBeginPageRetirement(id) else { completion(false); return }
                    for page in attached + children {
                        guard seen.insert(ObjectIdentifier(page)).inserted else { completion(false); return }
                        pages.append((owner, id, page))
                    }
                }
            }
        }
        // Reserve the complete shell set before Chromium dispatches any
        // beforeunload. Native page-close notifications must not individually
        // mutate the whole-set saved transaction.
        for entry in pages { entry.owner.beginPageRetirement(entry.id) }
        PCNativeBrowserApplication.requestClosePages(pages.map(\.page), shouldCommit: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.terminationInProgress,
                      notesAreOriginal(self.windows),
                      // A Note can receive edits/IME or fail its delayed save
                      // while another original page awaits beforeunload consent.
                      // Use its real flush barrier again before any unload.
                      self.windows.allSatisfy({ $0.prepareNotesToClose(ids) }),
                      notesAreOriginal(self.windows),
                      !self.windows.contains(where: { $0.hasPendingNativePage(in: ids) }),
                      pages.allSatisfy({ entry in
                          self.windows.contains { $0 === entry.owner } &&
                              entry.owner.canCommitPageRetirement(entry.id, page: entry.page)
                      }) else { return false }
                return shouldCommit()
            }
        }, completion: { [weak self] allowed in
            MainActor.assumeIsolated {
                for entry in pages { entry.owner.finishPageRetirement(entry.id, page: entry.page, closed: allowed) }
                // Native unload completion is asynchronous. Local editors can
                // still change after admission; a late failed draft must keep
                // the saved tree intact even when its web pages already closed.
                let documentsReady = allowed && self.map { owner in
                    !owner.terminationInProgress && notesAreOriginal(owner.windows)
                        && owner.windows.allSatisfy({ $0.prepareNotesToClose(ids) })
                        && notesAreOriginal(owner.windows)
                } == true
                completion(documentsReady)
                if !allowed, let self {
                    // An independent page destruction can cancel preparation.
                    // It is not group success, but its already-closed page must
                    // not be reconstructed from saved navigation. Reentry may
                    // have supplied a new owner/request: preserve those.
                    for entry in pages where entry.page.isClosed && !entry.page.isEmbedded {
                        guard !entry.owner.store.retiringTabIDs.contains(entry.id),
                              !self.windows.contains(where: {
                                  $0.nativePage(forTabID: entry.id) != nil || $0.hasPendingNativePage(in: [entry.id])
                              }) else { continue }
                        entry.owner.store.closeTab(entry.id)
                    }
                }
                for entry in pages { entry.owner.refreshAfterPageRetirement() }
            }
        })
    }

    /// Retain the exact Easel editors while page consent is pending. A changed
    /// editor set or unfinished native composition/pointer gesture refuses the
    /// move before it can discard a draft or publish another Profile's owner.
    private func prepareLocalDocumentRelocation(_ ids: Set<UUID>) -> (() -> Bool)? {
        let model = store
        func editors(_ owners: [BrowserWindowController]) -> [ObjectIdentifier: [UUID: EaselEditorViewController]] {
            Dictionary(uniqueKeysWithValues: owners.filter { $0.store === model }.compactMap { owner in
                let editors = owner.easelEditorsForRelocation(in: ids)
                return editors.isEmpty ? nil : (ObjectIdentifier(owner), editors)
            })
        }
        let original = editors(windows)
        func matches(_ current: [ObjectIdentifier: [UUID: EaselEditorViewController]]) -> Bool {
            Set(current.keys) == Set(original.keys) && current.allSatisfy { owner, values in
                values.mapValues(ObjectIdentifier.init) == original[owner]?.mapValues(ObjectIdentifier.init)
            }
        }
        return { [weak self] in
            guard let self, !self.terminationInProgress, matches(editors(self.windows)) else { return false }
            let originals = original.values.flatMap { $0.values }
            guard originals.allSatisfy({ $0.canPrepareForProfileRelocation }),
                  originals.allSatisfy({ $0.prepareForProfileRelocation() }) else { return false }
            return matches(editors(self.windows))
        }
    }

    /// A cross-Profile move takes its Notes/Easels into the destination
    /// Profile's stores: every original editor closes first (drafts flushed),
    /// then the exact documents move. Returns the reverse move for a failed save.
    private func relocateLocalDocuments(_ ids: Set<UUID>, pages: [InternalPage], from: UUID, to: UUID) throws -> () -> Void {
        let owners = windows.filter { $0.store === store }
        let affected = owners.filter {
            !$0.easelEditorsForRelocation(in: ids).isEmpty || !$0.noteEditorsForRetirement(in: ids).isEmpty
        }
        let restoreEditors: () -> Void = { [weak self] in
            guard let self else { return }
            for owner in affected where self.windows.contains(where: { $0 === owner }) {
                owner.refreshAfterPageRetirement()
            }
        }
        guard owners.allSatisfy({ $0.closeLocalDocumentEditors(ids) }) else {
            restoreEditors(); throw NoteError.changed
        }
        let rollback = LocalDocumentRelocationRollback()
        do {
            for page in pages {
                switch page {
                case .note(let id):
                    let source = try NoteStore.sharedStore(directory: store.notesDirectory(for: from))
                    let destination = try NoteStore.sharedStore(directory: store.notesDirectory(for: to))
                    try source.retireSessionForRelocation(id)
                    try source.relocate(id, to: destination)
                    rollback.append(reverse: {
                        do { try destination.relocate(id, to: source); return true }
                        catch { return false }
                    })
                case .easel(let id):
                    let source = try EaselEditorViewController.sharedStore(directory: store.easelsDirectory(for: from))
                    let destination = try EaselEditorViewController.sharedStore(directory: store.easelsDirectory(for: to))
                    try source.retireSessionForRelocation(id)
                    let copied = try source.relocate(id, to: destination)
                    rollback.append(reverse: {
                        do { _ = try destination.relocate(id, to: source); return true }
                        catch { return false }
                    }, cleanup: { destination.removeAssets(copied) })
                }
            }
        } catch {
            rollback.run()
            restoreEditors()
            throw error
        }
        return {
            rollback.run()
            // Empty/static documents have no native page completion to trigger
            // a render after rollback. Restore their fresh source editors too.
            restoreEditors()
        }
    }

    /// The one other window that could give `requester` the tab now: the
    /// window holding its page, Note or Easel, or a window whose claim has
    /// nothing behind it. A page still being created has no holder yet.
    private func tabHolder(_ id: UUID, for requester: BrowserWindowController) -> BrowserWindowController.TabHolder {
        guard !terminationInProgress, pageOwnership.owner(of: id) != nil,
              let holder = windows.first(where: { $0 !== requester && $0.store === requester.store && $0.claimsTab(id) })
        else { return .none }
        if holder.holdsContent(forTabID: id) { return holder.canMoveContent(id, to: requester) ? .content(holder) : .none }
        return holder.holdsEmptyClaim(id) ? .emptyClaim(holder) : .none
    }

    private func retirementUnavailableReason(_ ids: Set<UUID>) -> String? {
        if windows.contains(where: { $0.hasPendingNativePage(in: ids) }) {
            return "A page is still opening. Wait for it to finish, then try again."
        }
        return nil
    }

    private func runArchiveSweep() {
        let snapshots = windows.map(\.automaticArchiveProtectionSnapshot)
        let protected = snapshots.reduce(into: Set<UUID>()) { $0.formUnion($1.protectedIDs) }
        store.archiveExpiredTabs(protectedTabIDs: protected, currentProtection: { [weak self] in
            guard let self else { return Set(snapshots.flatMap { $0.protectedIDs }) }
            // Re-read actual pages and selections in EVERY physical window
            // immediately before the native transaction unloads anything.
            return self.windows.reduce(into: Set<UUID>()) {
                $0.formUnion($1.automaticArchiveProtectionSnapshot.protectedIDs)
            }
        }) { [weak self] archived in
            if self?.arguments.contains("--parc-diagnostics") == true {
                let unavailable = snapshots.reduce(0) { $0 + $1.unavailable }
                FileHandle.standardError.write(Data("Parc archive: protected=\(protected.count) unavailable=\(unavailable) archived=\(archived.count)\n".utf8))
            }
        }
    }
    @objc private func checkAutoArchive(_ sender: Any?) { refreshVisibleActivity(); runArchiveSweep() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !terminationInProgress, !appKitRestorationCancelled else { return true }
        if !restorationLaunch.canPresent { restorationLaunch.deferDockReopen(); return true }
        if requiresOnboarding || onboarding != nil { showOnboarding() }
        else if !initialBrowserOpened { finishInitialBrowserPresentation() }
        else {
            let state = windows.map { DockReopen.Window(available: $0.canReopenFromDock,
                                                        isMiniaturized: $0.window?.isMiniaturized == true) }
            let last = windows.firstIndex { $0 === lastActiveWindow }
            switch DockReopen.decision(hasKeyWindow: sender.keyWindow != nil, windows: state, lastKeyIndex: last) {
            case .none: break
            case .createWindow: createStandardWindow(showCommandBar: false)
            case .makeKey(let index): windows[index].window?.makeKey()
            case .makeKeyAndOrderFront(let index): windows[index].window?.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard started, !terminationInProgress else { return nil }
        let menu = NSMenu()
        let standard = NSMenuItem(title: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "")
        standard.target = self; menu.addItem(standard)
        let privateWindow = NSMenuItem(title: "New Incognito Window", action: #selector(newIncognitoWindow(_:)), keyEquivalent: "")
        privateWindow.target = self; menu.addItem(privateWindow)
        return menu
    }

    /// Handoff from an iPhone, iPad or another Mac: a web page continues here
    /// when Parc is the default browser and declares the browsing activity
    ///
    /// from another app.
    func application(_ application: NSApplication, willContinueUserActivityWithType userActivityType: String) -> Bool {
        userActivityType == NSUserActivityTypeBrowsingWeb
    }

    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
        guard let url = HandoffActivity.webpageURL(of: userActivity) else { return false }
        self.application(application, open: [url])
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        trace("external.received " + Self.epochMilliseconds())
        guard started, initialBrowserOpened, !requiresOnboarding, onboarding == nil else {
            pendingURLs.append(contentsOf: urls)
            if started, restorationLaunch.canPresent, requiresOnboarding || onboarding != nil { showOnboarding() }
            return
        }
        let queued = pendingURLs + urls; pendingURLs.removeAll()
        deliverExternalURLs(queued, preferredOwner: front)
    }

    private func deliverExternalURLs(_ urls: [URL], preferredOwner: BrowserWindowController?) {
        guard !terminationInProgress else { return }
        for (index, url) in urls.enumerated() {
            let available = store.state.spaces.map { LinkRoutingSpace(id: $0.id, profileID: $0.profileID) }
            let current = front.flatMap { $0.isPopupWindow ? nil : $0.activeSpaceID }
                ?? preferredOwner?.activeSpaceID ?? store.state.activeSpaceID
            guard let decision = store.linkRouting.decision(for: url, spaces: available, currentSpaceID: current),
                  let space = store.state.spaces.first(where: { $0.id == decision.spaceID }) else {
                pendingURLs.append(contentsOf: urls[index...]); return
            }
            do {
                //
                //
                // frontmost window showing its Space, not the oldest one.
                let eligible = windows.filter { $0.canAcceptExternalLink }
                let ordered = NSApp.orderedWindows.compactMap { window in eligible.first { $0.window === window } }
                let regular = ordered + eligible.reversed().filter { candidate in !ordered.contains { $0 === candidate } }
                let missingExplicitSpace = decision.usedUnavailableDestinationFallback &&
                    store.linkRouting.state.rules.contains { rule in
                        guard rule.id == decision.matchedRuleID, case .space = rule.destination else { return false }
                        return true
                    }
                let owner: BrowserWindowController
                let destination: UUID
                if missingExplicitSpace {
                    //
                    // a missing target then uses that window's focused Space.
                    let eligibleIDs = Set(regular.compactMap { $0.window.map(ObjectIdentifier.init) })
                    let selectedID = LinkRoutingUnavailableSpace.firstEligibleWindow(
                        ordered: NSApp.orderedWindows.map(ObjectIdentifier.init), eligible: eligibleIDs)
                    let orderedOwner = regular.first { owner in
                        owner.window.map(ObjectIdentifier.init) == selectedID && selectedID != nil
                    }
                    if let orderedOwner {
                        owner = orderedOwner
                        destination = orderedOwner.activeSpaceID
                    } else {
                        let fallbackID = LinkRoutingUnavailableSpace.newWindowSpace(
                            lastFocused: store.linkRouting.state.recentSpaceIDs.first,
                            available: store.state.spaces.map(\.id))
                        guard let fallback = store.state.spaces.first(where: { $0.id == fallbackID }) else {
                            pendingURLs.append(contentsOf: urls[index...]); return
                        }
                        owner = try makeBrowserWindow(renderInitialSelection: true, preferredProfileID: fallback.profileID)
                        destination = fallback.id
                    }
                } else {
                    owner = try regular.first(where: { $0.activeSpaceID == space.id })
                        ?? preferredOwner.flatMap { $0.canAcceptExternalLink && $0.activeProfileID == space.profileID ? $0 : nil }
                        ?? regular.first(where: { $0.activeProfileID == space.profileID })
                        ?? makeBrowserWindow(renderInitialSelection: true, preferredProfileID: space.profileID)
                    destination = space.id
                }
                guard owner.openExternalURL(url, inSpace: destination) else {
                    pendingURLs.append(contentsOf: urls[index...]); return
                }
                trace("external.opened " + Self.epochMilliseconds())
                lastActiveWindow = owner
                if owner.window?.isMiniaturized == true { owner.window?.deminiaturize(nil) }
                owner.showWindow(nil); owner.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                pendingURLs.append(contentsOf: urls[index...])
                presentWindowCreationError(error); return
            }
        }
    }

    func nativeApplicationRelaunched(arguments: [String], currentDirectory: String) {
        guard !terminationInProgress else { return }
        let request = NativeRelaunchRequest(arguments: arguments,
            currentDirectory: URL(fileURLWithPath: currentDirectory, isDirectory: true))
        guard started, initialBrowserOpened, !requiresOnboarding, onboarding == nil else {
            pendingRelaunches.append(request)
            if started, restorationLaunch.canPresent, requiresOnboarding || onboarding != nil { showOnboarding() }
            return
        }
        handleNativeRelaunch(request)
    }

    private func handleNativeRelaunch(_ request: NativeRelaunchRequest) {
        guard !terminationInProgress else { return }
        if front == nil { createStandardWindow(showCommandBar: false) }
        guard let owner = front, let window = owner.window,
              let binding = PCNativeBrowserApplication.window(forNativeWindow: window),
              binding.window === window, binding.client === owner else { return }
        lastActiveWindow = owner
        if window.isMiniaturized { window.deminiaturize(nil) }
        owner.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        for destination in request.destinations {
            switch destination {
            case .url(let url): application(NSApp, open: [url])
            case .input(let input): owner.openInput(input)
            }
        }
    }

    func saveSession() {
        guard store != nil else { return }
        recordWindowSessions()
        do { try store.save() }
        catch { NSLog("Parc session could not be saved: %@", error.localizedDescription) }
    }

    /// Every live page's back/forward entries, written before Quit closes them.
    private func persistTabHistory() {
        guard let archive = store?.tabHistory else { return }
        windows.forEach { $0.persistTabHistory(all: true) }
        archive.prune(keeping: Set(store.state.tabs.lazy.filter { $0.archivedAt == nil }.map(\.id)))
        archive.flush()
    }

    private var windowSessionRecordScheduled = false
    /// A window's selection, focus and width changes report here several times
    /// per tab switch, and NSApp.orderedWindows is a synchronous WindowServer
    /// round trip, so they coalesce into one record shortly after. Launch,
    /// window creation, saving and quitting still record at once.
    private func scheduleWindowSessionRecord() {
        guard !windowSessionRecordScheduled else { return }
        windowSessionRecordScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.windowSessionRecordScheduled = false
            self.recordWindowSessions()
        }
    }

    /// Windows and lifecycle hook (SIDE16): the main store's standard windows'
    /// records in BrowserWindowRecord.sessionOrder. Quit keeps the records
    /// taken as it began, before closing windows.
    private func recordWindowSessions() {
        guard sessionRestorationInitialized, !terminationInProgress, !replaySessionActive else { return }
        let order = NSApp.orderedWindows
        let standard = windows.filter { $0.store === store && !$0.isPopupWindow && $0.hasReadyPresentation }
        let indices = BrowserWindowRecord.sessionOrder(
            holdsFrameAutosave: standard.map { $0.window?.frameAutosaveName == BrowserWindowController.sharedFrameAutosaveName },
            frontToBack: standard.map { controller in controller.window.flatMap { order.firstIndex(of: $0) } })
        let live = indices.map { standard[$0].sessionRecord }
        store.updateWindowRecords(BrowserWindowRecord.preservingUnrestored(live: live, unrestored: unrestoredWindowRecords))
    }

    func requestApplicationTermination(_ sender: Any?) {
        let fromQuitCommand = quitCommandPending
        quitCommandPending = false
        guard !terminationInProgress, !quitWarningApprovalPending else { return }
        if replayCloseInProgress {
            deferredReplayTermination = { [weak self] in
                self?.quitCommandPending = fromQuitCommand
                self?.requestApplicationTermination(sender)
            }
            return
        }
        guard started else {
            (NSApp as? ParcApplication)?.finishApprovedTermination(sender)
            return
        }
        //
        // ordinary termination. It never stacks another warning sheet.
        if let quitWarning {
            // Retired first, so its cancellation is not a declined Quit (which
            // would also cancel a restart that is asking to terminate now).
            self.quitWarning = nil
            quitWarning.cancel()
            continueApplicationTermination(sender)
            return
        }
        //
        //
        // or a restart terminates without it. The warning never displaces an
        //
        if fromQuitCommand, QuitWarningPreferences.shared.state.isEnabled, let owner = quitWarningOwner,
           let parent = owner.window {
            let warning = ApplicationQuitWarning(preferences: .shared)
            warning.isCurrent = { [weak self, weak owner, weak parent, weak warning] in
                guard let self, let owner, let parent, let warning,
                      self.quitWarning === warning, self.started, !self.terminationInProgress,
                      self.windows.contains(where: { $0 === owner }), owner.window === parent,
                      owner.hasReadyPresentation,
                      parent.attachedSheet == nil || parent.attachedSheet === warning.window else { return false }
                return true
            }
            warning.onDecision = { [weak self, weak warning] approved in
                guard let self, self.quitWarning === warning else { return }
                self.quitWarning = nil
                guard approved else {
                    self.cancelApplicationRestart("Restart cancelled.")
                    self.resumeOnboardingAfterCancelledTermination()
                    return
                }
                self.quitWarningApprovalPending = true
                DispatchQueue.main.async { [weak self] in self?.continueApplicationTermination(sender) }
            }
            quitWarning = warning
            warning.present(in: parent)
            return
        }
        continueApplicationTermination(sender)
    }

    private var quitWarningOwner: BrowserWindowController? {
        let candidates = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 } + NSApp.orderedWindows
        for window in candidates {
            if let owner = windows.first(where: { $0.window === window && $0.hasReadyPresentation }) {
                return owner
            }
        }
        return nil
    }

    private func continueApplicationTermination(_ sender: Any?) {
        quitWarningApprovalPending = false
        guard !terminationInProgress else { return }
        if replayCloseInProgress {
            deferredReplayTermination = { [weak self] in self?.continueApplicationTermination(sender) }
            return
        }
        guard started else {
            (NSApp as? ParcApplication)?.finishApprovedTermination(sender)
            return
        }
        guard windows.allSatisfy({ $0.prepareNotesToClose() }) else {
            cancelApplicationRestart("Restart cancelled. Your notes are still open.")
            resumeOnboardingAfterCancelledTermination()
            return
        }
        do { try NoteStore.flushAllSharedDelayedDiskSaves() }
        catch {
            cancelApplicationRestart("Quit cancelled. A note could not be saved on this Mac.")
            resumeOnboardingAfterCancelledTermination()
            return
        }
        guard applicationSettings?.prepareForTermination() ?? true,
              windows.allSatisfy({ $0.prepareSettingsForTermination() }) else {
            cancelApplicationRestart("Quit cancelled. Air Traffic Control changes could not be saved.")
            resumeOnboardingAfterCancelledTermination()
            return
        }
        recordWindowSessions()
        persistTabHistory()
        let applicationSettingsWasVisible = applicationSettings?.window?.isVisible == true
        terminationInProgress = true
        windows.forEach { $0.prepareForApplicationClose() }
        guard applicationSettings?.attemptClose() ?? true,
              windows.allSatisfy({ $0.closePreparedSettingsForTermination() }) else {
            terminationInProgress = false
            if applicationSettingsWasVisible { applicationSettings?.restoreAfterCancelledOwnerClose() }
            windows.forEach { $0.cancelApplicationClose() }
            resumePendingAppKitRestorations()
            finishInitialLaunchIfReady()
            drainInitialActions()
            cancelApplicationRestart("Quit cancelled. Settings could not be closed.")
            resumeOnboardingAfterCancelledTermination()
            return
        }
        if applicationRestart == nil { browserImport?.close(); onboarding?.closeBrowserImport() }
        let pendingPrivate = Array(privateWindowCreations.values)
        privateWindowCreations.removeAll()
        pendingPrivate.forEach { $0.finish(.failure(BrowserScriptError.cancelled)) }
        // Consent can be declined by an existing replay page. Retain the
        // welcome's view, cue and draft until shutdown is actually approved.
        trace("command.quit")
        saveSession()
        // Current CEF requires an asynchronous terminate override: preserve
        // genuine aggregate consent/drain while its ordinary loop keeps running.
        PCBrowserEngine.requestTermination { [weak self] allowed in
            guard let self else { return }
            if allowed {
                self.cancelPendingAppKitRestorations()
                self.browserImport?.close(); self.onboarding?.closeBrowserImport()
                self.restartCompletion = nil
                if !self.armedReplayRestart { Self.removeReplayRestartDraft(in: self.store.directory) }
                self.finishShutdown()
                (NSApp as? ParcApplication)?.finishApprovedTermination(sender)
            } else {
                self.terminationInProgress = false
                self.resumeOnboardingAfterCancelledTermination()
                if applicationSettingsWasVisible { self.applicationSettings?.restoreAfterCancelledOwnerClose() }
                self.windows.forEach { $0.cancelApplicationClose() }
                self.resumePendingAppKitRestorations()
                self.finishInitialLaunchIfReady()
                self.drainInitialActions()
                self.cancelApplicationRestart("Restart cancelled. Your browser is still open.")
            }
        }
    }

    /// Reads how the previous run on this data ended. Keeps AppKit's window
    ///
    /// restore after an update or a crash.
    private func beginLaunchContinuity(root: URL) {
        let defaults = UserDefaults.standard
        if let domain = Bundle.main.bundleIdentifier,
           defaults.persistentDomain(forName: domain)?["NSQuitAlwaysKeepsWindows"] == nil {
            defaults.set(true, forKey: "NSQuitAlwaysKeepsWindows")
        }
        restoresEveryWindow = LaunchContinuity.restoresEveryWindow(previous: .read(in: root), build: Self.buildIdentity)
    }

    /// This executable's identity: a new build replaces it.
    private static var buildIdentity: String {
        guard let url = Bundle.main.executableURL,
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return "" }
        return "\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)-\(values.fileSize ?? 0)"
    }

    func finishShutdown() {
        //
        if let store, var continuity = LaunchContinuity.read(in: store.directory), continuity.running {
            continuity.running = false
            continuity.write(in: store.directory)
        }
        // Completion can synchronously post AppKit's launch notification. Close
        // the launch gate before resolving callbacks, including unexpected loop
        // returns that did not pass through the approved termination branch.
        cancelPendingAppKitRestorations()
        quitWarningApprovalPending = false
        quitWarning?.cancel()
        onboarding?.suspend()
        archiveScheduling.cancel()
        windows.forEach { $0.shutdownBrowsers() }
        saveSession()
        if started { started = false; PCBrowserEngine.shutdown() }
    }

    @objc func newIncognitoWindow(_ sender: Any?) {
        guard scriptingReady else { return }
        let parent = front?.store.privateParentProfileID ?? front?.activeProfileID ?? store.activeSpace.profileID
        createPrivateWindow(parent: parent) { [weak self] result in
            switch result {
            case .success(let controller): controller.newTab()
            case .failure(let error): self?.presentWindowCreationError(error)
            }
        }
    }

    private func createPrivateWindow(parent: UUID,
        completion: @escaping (Result<BrowserWindowController, Error>) -> Void) {
        guard scriptingReady, store.state.profiles.contains(where: { $0.id == parent }),
              !store.isProfileRemovalPending(parent) else { completion(.failure(BrowserScriptError.busy)); return }
        let path = store.independentEngineProfilePath(for: parent)
        let request = PendingBrowserCreation(completion)
        privateWindowCreations[request.id] = request
        PCNativeBrowserApplication.preparePrivateBrowsing(profilePath: path) { [weak self] error in
            MainActor.assumeIsolated {
                guard request.isPending else { return }
                defer { self?.privateWindowCreations.removeValue(forKey: request.id) }
                guard let self, self.scriptingReady,
                      self.store.state.profiles.contains(where: { $0.id == parent }),
                      !self.store.isProfileRemovalPending(parent),
                      self.store.independentEngineProfilePath(for: parent) == path else {
                    request.finish(.failure(BrowserScriptError.missing)); return
                }
                if let error { request.finish(.failure(error)); return }
                do { request.finish(.success(try self.makeBrowserWindow(renderInitialSelection: true,
                    privateParentProfileID: parent))) }
                catch { request.finish(.failure(error)) }
            }
        }
    }

    private func drainInitialActions() {
        guard !drainingInitialActions else { return }
        drainingInitialActions = true
        defer { drainingInitialActions = false }
        while let action = restorationLaunch.nextAction(initialBrowserOpened: initialBrowserOpened,
                                                         terminating: terminationInProgress || appKitRestorationCancelled) {
            switch action {
            case .newWindow:
                restorationLaunch.completeAction()
                createStandardWindow(showCommandBar: true)
            case .blankWindow:
                restorationLaunch.completeAction()
                createStandardWindow(showCommandBar: false)
            case .newNote(let spaceID, let profileID):
                guard deliverDeferredNewNote(spaceID: spaceID, profileID: profileID) else { return }
                restorationLaunch.completeAction()
            }
        }
    }

    // The queued no-browser request owns its newly created browser. If an
    // auxiliary window or security dialog is key, wait for that same owner;
    // never retarget the request to a different restored window.
    private func deliverDeferredNewNote(spaceID: UUID, profileID: UUID) -> Bool {
        guard NSApp.isActive, NSApp.modalWindow == nil else { return false }
        guard store.state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }),
              !store.isProfileRemovalPending(profileID) else {
            deferredNoteOwner = nil; deferredNoteOwnerCreated = false
            return true
        }
        if deferredNoteOwnerCreated, deferredNoteOwner == nil {
            deferredNoteOwnerCreated = false
            return true // The original owner closed; retire the stale request.
        }
        if !deferredNoteOwnerCreated {
            if NSApp.keyWindow != nil {
                guard let current = libraryCommandWindow, !current.isPopupWindow, !current.isPrivateBrowsing,
                      current.canCreateNote else { return false }
            }
            do {
                let seed = BrowserWindowRecord(sidebarWidth: store.state.settings.sidebarWidth, id: UUID(),
                                               focusedSpaceID: spaceID, selectedTabIDs: [])
                let owner = try makeBrowserWindow(renderInitialSelection: true, preferredProfileID: profileID,
                                                  restoredRecord: seed)
                deferredNoteOwner = owner
                deferredNoteOwnerCreated = true
            } catch { presentWindowCreationError(error); return false }
        }
        guard let owner = deferredNoteOwner else { return false }
        guard windows.contains(where: { $0 === owner }), owner.activeSpaceID == spaceID,
              owner.activeProfileID == profileID else {
            deferredNoteOwner = nil; deferredNoteOwnerCreated = false
            return true
        }
        guard owner === libraryCommandWindow, let original = owner.window,
              owner.canCreateNote, owner.prepareLibraryMenuCommand(), owner.window === original,
              owner.activeSpaceID == spaceID, owner.activeProfileID == profileID,
              libraryCommandWindow === owner else { return false }
        owner.createNote()
        deferredNoteOwner = nil; deferredNoteOwnerCreated = false
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.drainInitialActions() }
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard started, !terminationInProgress else { return }
        windows.forEach { $0.persistTabHistory(all: true) }
        BrowserWindowController.flushCookieStores()
    }

    @objc private func didEndWindowSheet(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.drainInitialActions() }
    }

    @objc private func didChangeWindowKeyContext(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.drainInitialActions() }
    }

    @objc func newWindow(_ sender: Any?) {
        guard started, !terminationInProgress else { return }
        if !initialBrowserOpened { restorationLaunch.deferAction(.newWindow); return }
        createStandardWindow(showCommandBar: true)
    }
    ///
    /// onCreateNewBlankWindow: the same standard window without New Window's
    /// command bar (WindowCreationOptions.showCommandBar).
    @objc func newBlankWindow(_ sender: Any?) {
        guard started, !terminationInProgress else { return }
        if !initialBrowserOpened { restorationLaunch.deferAction(.blankWindow); return }
        createStandardWindow(showCommandBar: false)
    }

    @discardableResult
    private func createStandardWindow(showCommandBar: Bool, restoring record: BrowserWindowRecord? = nil) -> BrowserWindowController? {
        guard started, !terminationInProgress else { return nil }
        if requiresOnboarding || onboarding != nil { showOnboarding(); return nil }
        do {
            let preferredProfileID: UUID?
            if let source = front, source.isPrivateBrowsing {
                guard let context = store.applicationContext(from: source.store, spaceID: source.activeSpaceID),
                      context.spaceID != nil else { throw BrowserScriptError.missing }
                preferredProfileID = context.profileID
            } else { preferredProfileID = nil }
            let controller = try makeBrowserWindow(renderInitialSelection: true, preferredProfileID: preferredProfileID,
                                                   restoredRecord: record)
            if !initialBrowserOpened, record == nil { finishInitialBrowserPresentation() }
            // The retained New Window action always requests a standard window
            // and its command bar. Startup restoration has a separate entry.
            if showCommandBar { controller.newTab() }
            return controller
        } catch {
            presentWindowCreationError(error)
            return nil
        }
    }

    private func makeBrowserWindow(renderInitialSelection: Bool, showImmediately: Bool = true, preferredProfileID: UUID? = nil, nativeRequest: PCNativeWindowRequest? = nil, privateParentProfileID: UUID? = nil, restoredRecord: BrowserWindowRecord? = nil) throws -> BrowserWindowController {
        let ownerStore: BrowserStore
        if let parentID = privateParentProfileID ?? (nativeRequest?.isOffTheRecord == true ? preferredProfileID : nil) {
            guard store.state.profiles.contains(where: { $0.id == parentID }), !store.isProfileRemovalPending(parentID) else { throw BrowserScriptError.missing }
            ownerStore = BrowserStore(privateParentProfileID: parentID,
                engineProfilePath: store.independentEngineProfilePath(for: parentID), directory: store.directory,
                settings: store.state.settings)
            ownerStore.requestPageRetirement = { [weak self] ids, shouldCommit, completion in
                guard let self else { completion(false); return }
                self.retireNativePages(ids, shouldCommit: shouldCommit, completion: completion)
            }
        } else { ownerStore = store }
        let controller = try BrowserWindowController(store: ownerStore, ownership: pageOwnership, renderInitialSelection: renderInitialSelection,
                                                     preferredProfileID: preferredProfileID, nativeWindowRequest: nativeRequest,
                                                     restoredRecord: restoredRecord)
        controller.onMiniPlayerSourceChange = { [weak self] in self?.scheduleMiniPlayerRefresh() }
        controller.downloadCatalog = store
        controller.onSessionRecordChange = { [weak self] in self?.scheduleWindowSessionRecord() }
        controller.onOpenDownloadSource = { [weak self, weak controller] item, url in
            guard let self, let controller, self.windows.contains(where: { $0 === controller }),
                  !self.terminationInProgress, let profile = item.profileID,
                  self.store.state.profiles.contains(where: { $0.id == profile }),
                  !self.store.isProfileRemovalPending(profile) else { return false }
            if let id = item.privateContextID {
                guard let context = PCNativeBrowserApplication.privateDownloadContexts().first(where: { $0.identifier == id && $0.isValid }),
                      context.profilePath == self.store.independentEngineProfilePath(for: profile),
                      let owner = context.sourceWindow?.client as? BrowserWindowController,
                      self.windows.contains(where: { $0 === owner }), owner.isPrivateBrowsing,
                      owner.store.privateParentProfileID == profile else { return false }
                return owner.openDownloadSourceURL(url, profileID: owner.activeProfileID)
            }
            do {
                let owner = !controller.isPrivateBrowsing ? controller :
                    try self.windows.last(where: { !$0.isPrivateBrowsing && $0.canOwnDownloadDialog(for: profile) }) ??
                        self.makeBrowserWindow(renderInitialSelection: true, preferredProfileID: profile)
                return owner.openDownloadSourceURL(url, profileID: profile)
            } catch { self.presentWindowCreationError(error); return false }
        }
        controller.onRequestApplicationSettings = { [weak self, weak controller] pane, shortcutID in
            guard let self, let controller, self.windows.contains(where: { $0 === controller }),
                  controller.hasReadyPresentation, !self.terminationInProgress,
                  let context = self.store.applicationContext(from: controller.store, spaceID: controller.activeSpaceID) else { return }
            self.showApplicationSettings(profileID: context.profileID, pane: pane, shortcutID: shortcutID)
        }
        controller.scriptingAuthorization = { [weak self] in self?.scriptingReady == true }
        controller.retirementUnavailableReason = { [weak self] ids in
            self?.retirementUnavailableReason(ids) ?? (self == nil ? "The browser is closing." : nil)
        }
        var spaceRefreshDeferredForCommandBar = false
        controller.onActivateWindow = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.lastActiveWindow = controller
            if controller.hasCommandBarDuringActivation {
                // Dismissal makes the original browser key before dispatching
                // its selected menu item. Rebuilding Spaces here increments
                // the registry revision and invalidates that very selection.
                spaceRefreshDeferredForCommandBar = true
            } else {
                spaceRefreshDeferredForCommandBar = false
                self.refreshSpaceCommands()
            }
            DispatchQueue.main.async { [weak self] in self?.drainInitialActions() }
            if !controller.isPopupWindow && !controller.isPrivateBrowsing { self.store.linkRouting.noteVisitedSpace(controller.activeSpaceID) }
        }
        controller.onCommandBarDismissalSettled = { [weak self] in
            guard spaceRefreshDeferredForCommandBar else { return }
            spaceRefreshDeferredForCommandBar = false
            self?.refreshSpaceCommands()
        }
        controller.onRequestBrowserTab = { [weak self, weak controller] input in
            guard let self, let controller, !self.terminationInProgress else { return }
            do {
                let destination = try self.windows.last(where: {
                    $0.canAcceptBrowserTab(for: controller.activeProfileID)
                }) ?? self.makeBrowserWindow(renderInitialSelection: true, preferredProfileID: controller.activeProfileID, privateParentProfileID: controller.store.privateParentProfileID)
                destination.showWindow(nil)
                destination.window?.makeKeyAndOrderFront(nil)
                if let input { destination.openInput(input) } else { destination.newTab() }
            } catch { self.presentWindowCreationError(error) }
        }
        controller.resolveSidebarCopyDestinations = { [weak self, weak controller] originals in
            guard let self, let controller, !self.terminationInProgress,
                  controller.store === self.store, self.windows.contains(where: { $0 === controller }) else { return nil }
            var result = SidebarCopySources()
            for original in originals {
                guard self.store.state.tabs.first(where: { $0.id == original.id }) == original,
                      !self.store.isProfileRemovalPending(original.profileID) else { return nil }
                if let page = InternalPage(urlString: original.savedURL) {
                    do {
                        let reference: SidebarDocumentReference
                        switch page {
                        case .note(let id):
                            let notes = try NoteStore.sharedStore(directory: self.store.notesDirectory(for: original.profileID))
                            try notes.validateReference(id)
                            reference = SidebarDocumentReference(page: page, profileID: original.profileID) { try notes.validateReference(id) }
                        case .easel(let id):
                            let easels = try EaselEditorViewController.sharedStore(directory: self.store.easelsDirectory(for: original.profileID))
                            try easels.validateReference(id)
                            reference = SidebarDocumentReference(page: page, profileID: original.profileID) { try easels.validateReference(id) }
                        }
                        result.destinations[original.id] = page.urlString
                        result.documents[original.id] = reference
                        continue
                    } catch { return nil }
                }
                let pages = self.windows.filter { $0.store === self.store }.compactMap { $0.nativePage(forTabID: original.id) }
                guard pages.count <= 1 else { return nil }
                if let page = pages.first {
                    guard !page.isClosed,
                          page.profilePath == self.store.independentEngineProfilePath(for: original.profileID) else { return nil }
                }
                // The original copy helper reads materialized WebContentState.url,
                // then SidebarTab.savedURL. A shared model's last URL is not that owner.
                result.destinations[original.id] = pages.first?.url?.absoluteString ?? original.savedURL
            }
            return result.validates(originals) ? result : nil
        }
        controller.onSplitDragBegan = { [weak self] drag, source in
            guard let self, !self.terminationInProgress else { return }
            for other in self.windows where other !== source && other.store === source.store {
                other.beginForeignSplitDrop(drag, from: source)
            }
        }
        controller.onInterProfileMoveCommitted = { [weak self, weak controller] ids in
            guard let self, let controller else { return }
            for owner in self.windows where owner.store === controller.store { owner.releaseInterProfileClaims(ids) }
        }
        controller.prepareSidebarSpaceMoveOwners = { [weak self, weak controller] ids in
            guard let self, let controller, !self.terminationInProgress,
                  controller.store === self.store, self.windows.contains(where: { $0 === controller }) else { return nil }
            let owners = self.windows.filter { $0.store === self.store }
            let leases = owners.compactMap { $0.prepareSidebarSpaceRelocationOwnership(ids) }
            guard leases.count == owners.count else { return nil }
            let identities = Set(owners.map(ObjectIdentifier.init))
            return { [weak self] in
                guard let self, !self.terminationInProgress,
                      Set(self.windows.filter { $0.store === self.store }.map(ObjectIdentifier.init)) == identities else { return false }
                return leases.allSatisfy { $0() }
            }
        }
        controller.onPrepareLinkRoute = { [weak self, weak controller] route in
            guard let self, let controller, !controller.isPrivateBrowsing, !self.terminationInProgress,
                  let spaceID = UUID(uuidString: route.spaceIdentifier),
                  let space = self.store.state.spaces.first(where: { $0.id == spaceID }),
                  !self.store.isProfileRemovalPending(space.profileID),
                  route.profilePath == self.store.independentEngineProfilePath(for: space.profileID) else { return nil }
            do {
                let eligible = self.windows.filter { $0.canAcceptNativeLinkRoute(profileID: space.profileID) }
                let destination = try eligible.first(where: { $0.activeSpaceID == spaceID })
                    ?? eligible.first(where: { $0 === controller }) ?? eligible.last
                    ?? self.makeBrowserWindow(renderInitialSelection: false, showImmediately: false, preferredProfileID: space.profileID)
                return destination.prepareNativeLinkDestination(profileID: space.profileID)
            } catch { return nil }
        }
        controller.tabHolder = { [weak self] id, requester in self?.tabHolder(id, for: requester) ?? .none }
        controller.onRequestTabTransfer = { [weak self] id, destination, placement in
            guard let self else { return false }
            switch self.tabHolder(id, for: destination) {
            case .content(let source):
                return source.transferTab(id, to: destination, placement: placement)
            case .emptyClaim(let claimer):
                guard claimer.handOverEmptyClaim(id, to: destination) else { destination.refuseTabMove(); return false }
                destination.finishEmptyClaimHandOver(id, placement: placement)
                return true
            case .none:
                destination.refuseTabMove(); return false
            }
        }
        controller.onUntargetedReturn = { [weak self] id, owner, trigger in
            guard let self, !self.terminationInProgress else { return .unneeded }
            let others = self.windows.filter { $0 !== owner && $0.store === owner.store }
            let candidates = others.map {
                PageReparenting.Candidate(windowID: $0.sessionID, displaysPlaceholder: $0.displaysPlaceholder(for: id),
                                          showsPlaceholder: $0.showsPlaceholder(for: id), lastActive: $0.lastActivatedAt,
                                          canReceive: owner.canMoveContent(id, to: $0))
            }
            for chosen in PageReparenting.returnDestinations(candidates, trigger: trigger) {
                guard let destination = others.first(where: { $0.sessionID == chosen }) else { continue }
                if owner.transferTab(id, to: destination, placement: { true }, untargeted: true) { return .started }
                if trigger == .deselected, owner.returnFailed(id) { return .blocked }
            }
            return PageReparenting.unstartedReturn(candidates)
        }
        controller.onReturnUnblocked = { [weak self, weak controller] in
            guard let self, let controller, !self.terminationInProgress else { return }
            for other in self.windows where other.store === controller.store { other.retryHeldReturns() }
        }
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            controller.shutdownBrowsers()
            self?.windows.removeAll { $0 === controller }
            for other in self?.windows ?? [] where other.store === controller.store { other.retryHeldReturns() }
            // Private windows' site colours live only until the last one closes.
            if controller.isPrivateBrowsing, self?.windows.contains(where: \.isPrivateBrowsing) == false {
                TopBarColorClient.privateBrowsing.forgetAll()
                FairPlayIdentityController.shared.forgetPrivateChoices()
            }
            self?.earlyDownloadWindowIDs.remove(controller.sessionID)
            self?.scheduleMiniPlayerRefresh()
            self?.saveSession()
            DispatchQueue.main.async { [weak self] in self?.drainInitialActions() }
        }
        windows.append(controller)
        // Consume only after creation succeeds, before presentation can reenter
        // startup or save a legacy record without an ID alongside its replacement.
        if let restoredRecord, sessionRestorationInitialized,
           let index = unrestoredWindowRecords.firstIndex(of: restoredRecord) {
            unrestoredWindowRecords.remove(at: index)
        }
        recordWindowSessions()
        scheduleMiniPlayerRefresh()
        // Incoming WebContents must arrive before the preflight shell appears;
        // a background disposition must not steal focus or reveal a window.
        if renderInitialSelection && showImmediately { controller.showWindow(nil) }
        return controller
    }

    /// The engine learned a FairPlay site for Safari's identity, whichever page
    /// asked (docs/fairplay-identity.md).
    func nativeApplicationDidLearnSafariIdentity(forSite site: String, profilePath: String, offTheRecord: Bool) {
        FairPlayIdentityController.shared.didLearn(site, profilePath: profilePath, offTheRecord: offTheRecord)
    }
    func nativeApplicationPrivateDownloadDidUpdate(_ update: [String: Any], context: PCNativePrivateDownloadContext) {
        guard update["profilePath"] as? String == context.profilePath else { return }
        store.recordTransientDownload(update, contextID: context.identifier)
        for controller in windows { controller.refreshDownloads() }
    }
    func nativeApplicationPrivateDownloadContextDidInvalidate(_ context: PCNativePrivateDownloadContext) {
        store.retireTransientDownloads(contextID: context.identifier)
        for controller in windows { controller.refreshDownloads() }
    }

    func nativeApplicationDownloadDidUpdate(_ update: [String: Any]) {
        guard update["offTheRecord"] as? Bool != true else { return }
        store.recordDownload(update)
        for controller in windows { controller.refreshDownloads() }
    }

    func nativeDownloadDialogWindow(forProfilePath profilePath: String) -> NSWindow? {
        guard started, !terminationInProgress, !requiresOnboarding, onboarding == nil,
              let profileID = store.profileID(forEnginePath: profilePath),
              store.state.spaces.contains(where: { $0.profileID == profileID }) else { return nil }
        // Rank only exact-profile owners. An unrelated key/main window never
        // becomes the owner of a background extension or restored download.
        let candidates = windows.filter {
            !$0.isPrivateBrowsing && $0.canOwnDownloadDialog(for: profileID) && $0.window?.attachedSheet == nil
        }
        let controller: BrowserWindowController
        if let existing = candidates.first(where: { $0.window === NSApp.keyWindow })
            ?? candidates.first(where: { $0 === lastActiveWindow }) ?? candidates.last {
            controller = existing
        } else {
            var earlyID: UUID?
            do {
                // This synchronous native download prompt cannot wait for
                // AppKit's remaining callbacks. Seed an empty physical owner
                // during restoration so it cannot claim another saved pane.
                let seed: BrowserWindowRecord?
                if !initialBrowserOpened, let space = store.state.spaces.first(where: { $0.profileID == profileID }) {
                    let id = UUID(); earlyID = id; earlyDownloadWindowIDs.insert(id)
                    seed = BrowserWindowRecord(sidebarWidth: store.state.settings.sidebarWidth, id: id,
                                               focusedSpaceID: space.id, selectedTabIDs: [])
                } else { seed = nil }
                controller = try makeBrowserWindow(renderInitialSelection: true, preferredProfileID: profileID,
                                                   restoredRecord: seed)
            } catch {
                if let earlyID { earlyDownloadWindowIDs.remove(earlyID) }
                presentWindowCreationError(error); return nil
            }
        }
        guard controller.canOwnDownloadDialog(for: profileID), let window = controller.window else { return nil }
        if window.isMiniaturized { window.deminiaturize(nil) }
        controller.showWindow(nil)
        return nativeDownloadDialogWindow(window, representsProfilePath: profilePath) ? window : nil
    }

    func nativeDownloadDialogWindow(_ window: NSWindow, representsProfilePath profilePath: String) -> Bool {
        guard started, !terminationInProgress, !requiresOnboarding, onboarding == nil,
              let profileID = store.profileID(forEnginePath: profilePath) else { return false }
        return windows.contains { $0.window === window && $0.canOwnDownloadDialog(for: profileID) }
    }

    func prepareNativeWindow(request: PCNativeWindowRequest) -> (any PCNativeBrowserWindowClient)? {
        let profilePath = request.profilePath
        let kind = request.kind
        guard started, !terminationInProgress, !requiresOnboarding, onboarding == nil,
              let profileID = store.profileID(forEnginePath: profilePath) else { return nil }
        if kind == .developerTools {
            do {
                let controller = try DevToolsWindowController(profilePath: profilePath, source: request.source, request: request)
                controller.onClose = { [weak self, weak controller] in
                    guard let controller else { return }
                    self?.devToolsWindows.removeAll { $0 === controller }
                }
                devToolsWindows.append(controller)
                return controller
            } catch { presentWindowCreationError(error); return nil }
        }
        if kind == .pictureInPicture {
            do {
                let controller = try PictureInPictureWindowController(request: request)
                controller.onClose = { [weak self, weak controller] in
                    guard let controller else { return }
                    self?.pictureInPictureWindows.removeAll { $0 === controller }
                }
                pictureInPictureWindows.append(controller)
                return controller
            } catch { presentWindowCreationError(error); return nil }
        }
        guard kind == .browser || kind == .popup else { return nil }
        do { return try makeBrowserWindow(renderInitialSelection: false, preferredProfileID: profileID, nativeRequest: request) }
        catch { presentWindowCreationError(error); return nil }
    }

    private func presentWindowCreationError(_ error: Error) {
        NSLog("Parc could not create a browser window: %@", error.localizedDescription)
        let alert = NSAlert()
        alert.messageText = "Parc couldn’t open this window"
        alert.informativeText = error.localizedDescription
        if let window = front?.window, window.attachedSheet == nil { alert.beginSheetModal(for: window) }
    }

    @objc private func newTab(_ sender: Any?) {
        //
        // Do not forward a command from the import or its native sheets to the
        // last active browser behind it.
        guard BrowserImportWindow.owning(NSApp.keyWindow) == nil else { return }
        if let education = NSApp.keyWindow?.windowController as? ShortcutEssentialsWindow {
            education.activateCommand("newTab:", event: NSApp.currentEvent)
            return
        }
        front?.newTab()
    }
    @objc private func focusAddress(_ sender: Any?) { trace("command.focusAddress"); front?.focusAddress() }
    @objc private func focusSidebar(_ sender: Any?) { browserInputCommandWindow?.focusSidebar() }
    @objc private func renameCurrentItem(_ sender: Any?) { front?.renameCurrentItem() }
    private func sidebarCommandKind(for action: Selector?) -> SidebarSelectionCommandKind? {
        switch action {
        case #selector(copyCurrentURL): return .copyLinks
        case #selector(copyCurrentURLAsMarkdown): return .copyMarkdown
        case #selector(closeTab): return .close
        case #selector(createFolder): return .newFolder
        default: return nil
        }
    }
    private func validateSidebarCommand(_ item: NSMenuItem) -> Bool? {
        guard let kind = sidebarCommandKind(for: item.action) else { return nil }
        if !selectionMenuIsTracking { item.representedObject = nil }
        if let target = item.representedObject as? SidebarSelectionCommandTarget {
            item.title = target.title
            return target.kind == kind && target.isValid
        }
        guard let owner = front, owner.hasSidebarCommandSelection else { return nil }
        guard let target = owner.prepareSidebarSelectionCommand(kind) else { return false }
        item.representedObject = target; item.title = target.title
        return target.isValid
    }
    /// True means this was a plural intent, including a cancelled/stale one.
    /// Never let a refused selection command fall through to the active page.
    private func performSidebarCommand(_ sender: Any?, kind: SidebarSelectionCommandKind) -> Bool {
        if let target = (sender as? NSMenuItem)?.representedObject as? SidebarSelectionCommandTarget {
            if target.kind == kind { _ = target.perform() }
            return true
        }
        guard let owner = front, owner.hasSidebarCommandSelection else { return false }
        _ = owner.prepareSidebarSelectionCommand(kind)?.perform()
        return true
    }

    /// The settings controller owns Command-W, including when one of its
    /// sheets is key. Never route that command to a browser behind it.
    private func settingsOwning(_ window: NSWindow?) -> SettingsWindow? {
        var current = window
        while let candidate = current {
            if let settings = candidate.windowController as? SettingsWindow { return settings }
            current = candidate.sheetParent ?? candidate.parent
        }
        return nil
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleStayOnTop) {
            guard let selection = item.representedObject as? StayOnTopSelection,
                  let owner = selection.owner, let original = selection.window,
                  windows.contains(where: { $0 === owner }), owner.window === original,
                  owner === stayOnTopWindow, owner.canStayOnTop, !terminationInProgress else { return false }
            item.state = owner.stayOnTop ? .on : .off
            return true
        }
        if item.action == #selector(newWindow) || item.action == #selector(newBlankWindow) {
            return started && !terminationInProgress
        }
        if item.action == #selector(clearToday) {
            guard !terminationInProgress, !requiresOnboarding, onboarding == nil else {
                item.representedObject = nil; return false
            }
            if clearTodayMenuIsTracking {
                return (item.representedObject as? BrowserClearTodayCommand)?.isAvailable == true
            }
            guard let owner = spaceCommandWindow else { item.representedObject = nil; return false }
            return owner.prepareClearTodayMenuItem(item)
        }
        if let action = findAction(for: item.action) {
            guard !terminationInProgress, !requiresOnboarding, onboarding == nil,
                  let owner = spaceCommandWindow else { item.representedObject = nil; return false }
            return owner.prepareFindMenuItem(item, action: action, preservingTarget: findMenuIsTracking)
        }
        if item.action == #selector(exit) {
            item.representedObject = nil
            guard !terminationInProgress, !requiresOnboarding, onboarding == nil,
                  let owner = windows.first(where: { $0.ownsSpaceCommandFocus }) else { return false }
            return owner.prepareExitMenuItem(item)
        }
        if item.action == #selector(toggleFullScreen) {
            item.representedObject = nil
            item.title = "Enter Full Screen"
            guard !terminationInProgress, !requiresOnboarding, onboarding == nil,
                  let owner = windows.first(where: { $0.ownsSpaceCommandFocus }) else { return false }
            return owner.prepareFullscreenMenuItem(item)
        }
        if item.action == #selector(closeWindow) {
            item.representedObject = nil
            guard !terminationInProgress, !requiresOnboarding, onboarding == nil,
                  let owner = windows.first(where: { $0.ownsSpaceCommandFocus }) else { return false }
            return owner.prepareCloseWindowMenuItem(item)
        }
        if let importer = BrowserImportWindow.owning(NSApp.keyWindow) {
            if item.action == #selector(newTab) { return false }
            if item.action == #selector(closeTab) {
                item.title = "Close Import"
                return importer.window?.attachedSheet == nil
            }
            if item.action == #selector(importFromBrowser) { return onboarding == nil }
        }
        if item.action == #selector(closeTab), let settings = settingsOwning(NSApp.keyWindow) {
            item.representedObject = nil
            item.title = "Close Settings"
            return SettingsCloseCommand.isAvailable(window: settings.window, appIsActive: NSApp.isActive)
        }
        if item.action == #selector(importFromBrowser) {
            return started && !terminationInProgress && onboarding == nil && !requiresOnboarding
                && front?.isPrivateBrowsing == false
        }
        if item.action == #selector(closeTab), let onboarding,
           OnboardingCloseCommand.owns(setup: onboarding.window, key: NSApp.keyWindow) {
            item.title = "Close Setup"
            return OnboardingCloseCommand.isAvailable(setup: onboarding.window)
        }
        // Replay leaves a key browser window's own Close Tab in place.
        if requiresOnboarding || onboarding != nil, requiresOnboarding || item.action != #selector(closeTab) {
            return item.action == #selector(newWindow) || item.action == #selector(newBlankWindow)
                || item.action == #selector(about) || item.action == #selector(quitMenu)
        }
        if item.action == WebpageEditCommands.pasteMatchingStyle { return WebpageEditCommands.canPasteMatchingStyle(item) }
        if let appearance = AppAppearance.forSelector(item.action) {
            item.state = appearance == AppAppearance.current ? .on : .off
            return true
        }
        if item.action == #selector(setAsDefaultBrowser) {
            let controller = DefaultBrowserController.shared
            controller.refresh()
            item.title = controller.state.isRequesting ? "Waiting for Default Browser Confirmation…" : "Set as Default Browser"
            return controller.canRequest
        }
        if item.action == #selector(createNote) { return libraryCommandWindow?.canCreateNote ?? canCreateNoteWithoutBrowser }
        if item.action == #selector(createNoteInSplit) { return libraryCommandWindow?.canCreateNoteInSplit ?? false }
        if item.action == #selector(createEasel) { return libraryCommandWindow?.canCreateNote ?? false }
        if item.action == #selector(openEasel) {
            guard let selection = item.representedObject as? EaselMenuSelection,
                  let owner = selection.owner, owner === libraryCommandWindow,
                  owner.activeProfileID == selection.profileID else { return false }
            return owner.canCreateNote
        }
        if item.action == #selector(exportNotes) {
            item.title = libraryCommandWindow?.isExportingNotes == true ? "Exporting Notes…" : "Export Notes…"
            return libraryCommandWindow?.canExportNotes ?? false
        }
        if item.action == #selector(showDocuments) { return libraryCommandWindow?.canCreateNote ?? false }
        if item.action == #selector(newIncognitoWindow) { return scriptingReady }
        if front?.isPrivateBrowsing == true,
           [#selector(createSpace), #selector(createFolder), #selector(createEasel), #selector(editTheme), #selector(togglePin),
            #selector(renameFocusedSpace)].contains(item.action) { return false }
        if let enabled = validateSidebarCommand(item) { return enabled }
        if item.action == #selector(copyCurrentURL) { item.title = "Copy URL" }
        if item.action == #selector(copyCurrentURLAsMarkdown) { item.title = "Copy URL as Markdown" }
        if item.action == #selector(createFolder) { item.title = "New Folder…" }
        if item.action == #selector(copyCurrentURLAsQuote), front?.hasSidebarCommandSelection == true { return false }
        if let action = item.action, let education = NSApp.keyWindow?.windowController as? ShortcutEssentialsWindow,
           ShortcutEssentialsWindow.commandIDs.contains(NSStringFromSelector(action)) {
            return education.canActivateCommand(NSStringFromSelector(action))
        }
        if let command = splitCommand(for: item.action) {
            guard let owner = spaceCommandWindow else { item.representedObject = nil; return false }
            return owner.prepareSplitMenuItem(item, command: command, preservingTarget: splitMenuIsTracking)
        }
        if let expanded = folderDisclosure(for: item.action) {
            guard let owner = spaceCommandWindow else { item.representedObject = nil; return false }
            return owner.prepareFolderDisclosureMenuItem(item, expanded: expanded, preservingTarget: splitMenuIsTracking)
        }
        if item.action == #selector(selectSpace) {
            guard let selection = item.representedObject as? SpaceMenuSelection,
                  let owner = selection.owner, owner === spaceCommandWindow else { return false }
            item.state = selection.spaceID == owner.activeSpaceID ? .on : .off
            return owner.canSelectSpace(selection.spaceID, profileID: selection.profileID)
        }
        if item.action == #selector(nextSpace) { return spaceCommandWindow?.canCycleSpace(forward: true) ?? false }
        if item.action == #selector(previousSpace) { return spaceCommandWindow?.canCycleSpace(forward: false) ?? false }
        if item.action == #selector(openInCurrentSpace) {
            guard let owner = spaceCommandWindow else {
                item.isHidden = true; item.image = nil; item.representedObject = nil
                return false
            }
            return owner.preparePeekOpenMenuItem(item, preservingTarget: clearTodayMenuIsTracking)
        }
        if item.action == #selector(resetTab) { return front?.canResetCurrentTab ?? false }
        if item.action == #selector(resetVisibleSavedTabs) { return front?.canResetVisibleSavedTabs ?? false }
        if item.action == #selector(restoreTab) { return browserWindowCommandOwner?.canRestoreClosedTab ?? false }
        if item.action == #selector(goBackArrow) || item.action == #selector(goForwardArrow) {
            guard let owner = browserInputCommandWindow, owner.window === NSApp.keyWindow,
                  KeyboardShortcuts.permitsArrowNavigation(in: owner.window) else { return false }
            return owner.canPerformNavigation(item.action == #selector(goBackArrow) ? .back : .forward)
        }
        if item.action == #selector(goBack) { return browserInputCommandWindow?.canPerformNavigation(.back) ?? false }
        if item.action == #selector(goForward) { return browserInputCommandWindow?.canPerformNavigation(.forward) ?? false }
        if item.action == #selector(reload) { return browserInputCommandWindow?.canPerformNavigation(.reload) ?? false }
        if item.action == #selector(forceReload) { return browserInputCommandWindow?.canPerformNavigation(.reloadBypassingCache) ?? false }
        if item.action == #selector(stopLoading) { return browserInputCommandWindow?.canPerformNavigation(.stop) ?? false }
        if item.action == #selector(showEssentialShortcuts) { return front != nil }
        if item.action == #selector(newTab), let owner = front, owner.isPopupWindow {
            return owner.window?.isKeyWindow == true && owner.windowCommandSecurityAvailable
        }
        if item.action == #selector(copyCurrentURL) { return browserCopyCommandOwner?.canCopyCurrentURL ?? false }
        if item.action == #selector(openExtensions) { return browserInputCommandWindow?.canOpenExtensionPicker ?? false }
        if item.action == #selector(copyCurrentURLAsMarkdown) { return browserInputCommandWindow?.canCopyCurrentURLAsMarkdown ?? false }
        if item.action == #selector(copyCurrentURLAsQuote) { return browserInputCommandWindow?.canCopyCurrentURLAsQuote ?? false }
        if item.action == #selector(focusSidebar) { return browserInputCommandWindow?.canFocusSidebar ?? false }
        if item.action == #selector(toggleSidebar) { return browserInputCommandWindow != nil }
        if item.action == #selector(zoomIn) || item.action == #selector(zoomOut) || item.action == #selector(actualSize) {
            return browserInputCommandWindow?.canChangePageZoom ?? false
        }
        if item.action == #selector(createSpace) { return browserInputCommandWindow?.canCreateSpaceFromMenu ?? false }
        if item.action == #selector(editTheme) { return browserInputCommandWindow?.canEditThemeFromMenu ?? false }
        if item.action == #selector(togglePin) {
            return browserInputCommandWindow.map {
                !$0.isPrivateBrowsing && !$0.isPopupWindow && $0.canOwnDownloadDialog(for: $0.activeProfileID)
            } ?? false
        }
        if item.action == #selector(renameCurrentItem) { return front?.canRenameCurrentItem ?? false }
        if item.action == #selector(nextTab) { return front?.canSelectAdjacentTab(forward: true) ?? false }
        if item.action == #selector(goToSidebarItem) { return front?.canSelectSidebarItem(number: item.tag) ?? false }
        if item.action == #selector(previousTab) { return front?.canSelectAdjacentTab(forward: false) ?? false }
        if item.action == #selector(cycleTabForward) { return front?.canCycleTabHistory(forward: true) ?? false }
        if item.action == #selector(cycleTabBackward) { return front?.canCycleTabHistory(forward: false) ?? false }
        if item.action == #selector(cycleToNextRecentTab) || item.action == #selector(cycleToPreviousRecentTab) {
            return front?.canShowRecentTabSwitcher ?? false
        }
        if item.action == #selector(downloads) { return libraryCommandWindow?.canShowDownloads ?? false }
        if item.action == #selector(openSpaceManager) { return libraryCommandWindow?.canShowLibrary ?? false }
        if item.action == #selector(viewLibrary) { return libraryCommandWindow.map { $0.canShowLibrary || $0.isPrivateBrowsing && $0.canShowDownloads } ?? false }
        if item.action == #selector(duplicateCurrentItem) { return browserInputCommandWindow?.canDuplicateCurrentItem ?? false }
        if item.action == #selector(revealCurrentTabInSidebar) { return front?.canRevealCurrentTabInSidebar ?? false }
        if item.action == #selector(changeSpaceProfile) {
            guard let target = item.representedObject as? SpaceMenuSelection else { return false }
            return target.owner?.canChangeSpaceProfile(target.spaceID, profileID: target.profileID) == true
        }
        if item.action == #selector(renameFocusedSpace) { return spaceCommandWindow?.canRenameActiveSpace ?? false }
        if item.action == #selector(newProfile) { return spaceCommandWindow?.canCreateProfile ?? false }
        if item.action == #selector(manageExtensions) || item.action == #selector(addExtension)
            || item.action == #selector(history) {
            return browserInputCommandWindow?.canOpenPageInNewTab ?? false
        }
        if item.action == #selector(showReleaseNotes) {
            return BrowserWindowController.releaseNotesURL != nil && browserInputCommandWindow?.canOpenPageInNewTab == true
        }
        if item.action == #selector(captureLibrary) { return libraryCommandWindow?.canShowMedia ?? false }
        if item.action == #selector(archive) || item.action == #selector(clearArchive) {
            return libraryCommandWindow?.canShowLibrary ?? false
        }
        if item.action == #selector(toggleReaderMode) {
            guard let front else {
                item.title = "Enter Reader"
                item.representedObject = nil
                return false
            }
            return front.prepareReaderMenuItem(item)
        }
        if item.action == #selector(toggleScriptPermission) { return front?.prepareScriptPermissionMenuItem(item, preservingTarget: scriptPermissionMenuIsTracking) ?? false }
        if item.action == #selector(toggleArcToolbar) { return spaceCommandWindow?.prepareToolbarMenuItem(item) ?? false }
        if item.action == #selector(toggleDeveloperMode) { return front?.prepareDeveloperModeMenuItem(item) ?? false }
        if item.action == #selector(developerTools) {
            if let tools = devToolsWindows.first(where: { $0.window === NSApp.keyWindow }) {
                item.representedObject = nil
                return tools.canToggleClosed
            }
            return front?.preparePageToolMenuItem(item, tool: .developerTools) ?? false
        }
        if item.action == #selector(toggleFairPlayIdentity) {
            guard let owner = front else { item.representedObject = nil; return false }
            return owner.prepareFairPlayIdentityMenuItem(item)
        }
        if item.action == #selector(castPage) {
            guard let owner = browserInputCommandWindow else { item.representedObject = nil; return false }
            return owner.preparePageToolMenuItem(item, tool: .cast)
        }
        if item.action == #selector(inspectElements) { return front?.preparePageToolMenuItem(item, tool: .inspectElements) ?? false }
        if item.action == #selector(javaScriptConsole) { return front?.preparePageToolMenuItem(item, tool: .javaScriptConsole) ?? false }
        if item.action == #selector(networkInspector) { return front?.preparePageToolMenuItem(item, tool: .networkInspector) ?? false }
        if item.action == #selector(clearBrowsingData) { return front?.preparePageToolMenuItem(item, tool: .clearBrowsingData) ?? false }
        if item.action == #selector(clearCacheAndRefresh) { return front?.preparePageToolMenuItem(item, tool: .clearCacheAndRefresh) ?? false }
        if item.action == #selector(clearCookiesAndRefresh) { return front?.preparePageToolMenuItem(item, tool: .clearCookiesAndRefresh) ?? false }
        if item.action == #selector(capturePage) { return front?.preparePageCaptureMenuItem(item, mode: .region) ?? false }
        if item.action == #selector(captureVisiblePage) { return front?.preparePageCaptureMenuItem(item, mode: .viewport) ?? false }
        if item.action == #selector(captureFullPage) { return front?.preparePageCaptureMenuItem(item, mode: .fullPage) ?? false }
        if item.action == #selector(sharePage) { return browserInputCommandWindow?.canSharePage ?? false }
        if item.action == #selector(printPage) { return front?.canPerformPageTool(.print) ?? false }
        if item.action == #selector(savePage) {
            if let editor = NSApp.keyWindow as? EaselImageExporting { return editor.canExportEaselImage }
            return front?.canExportEaselImage == true || front?.canPerformPageTool(.save) == true
        }
        if item.action == #selector(viewSource) { return front?.canPerformPageTool(.viewSource) ?? false }
        if item.action == #selector(closeTab) {
            item.title = NSApp.keyWindow?.windowController is ShortcutEssentialsWindow ? "Close Shortcuts"
                : devToolsWindows.contains { $0.window === NSApp.keyWindow } ? "Close Developer Tools"
                : pictureInPictureWindows.contains { $0.window === NSApp.keyWindow } ? "Close Picture in Picture"
                : spaceCommandWindow?.closeTabMenuTitle ?? "Close Tab"
            return NSApp.keyWindow?.windowController is ShortcutEssentialsWindow
                || devToolsWindows.contains { $0.window === NSApp.keyWindow }
                || pictureInPictureWindows.contains { $0.window === NSApp.keyWindow }
                || (spaceCommandWindow?.canCloseCurrentTab ?? false)
        }
        return true
    }

    @objc private func exit(_ sender: NSMenuItem) {
        guard !terminationInProgress, !requiresOnboarding, onboarding == nil,
              let command = sender.representedObject as? BrowserExitCommand else { return }
        _ = command.perform()
    }
    @objc private func toggleFullScreen(_ sender: NSMenuItem) {
        guard !terminationInProgress, !requiresOnboarding, onboarding == nil,
              let command = sender.representedObject as? BrowserWindowFullscreenCommand else { return }
        _ = command.perform(sender)
    }
    @objc private func closeWindow(_ sender: NSMenuItem) {
        guard !terminationInProgress, !requiresOnboarding, onboarding == nil,
              let command = sender.representedObject as? BrowserWindowCloseCommand else { return }
        _ = command.perform(sender)
    }
    @objc private func closeTab(_ sender: Any?) {
        if let importer = BrowserImportWindow.owning(NSApp.keyWindow) {
            guard importer.window?.attachedSheet == nil else { return }
            importer.window?.performClose(sender); return
        }
        if let settings = settingsOwning(NSApp.keyWindow) {
            SettingsCloseCommand.perform(window: settings.window, appIsActive: NSApp.isActive, sender: sender)
            return
        }
        if let onboarding, OnboardingCloseCommand.owns(setup: onboarding.window, key: NSApp.keyWindow) {
            guard OnboardingCloseCommand.isAvailable(setup: onboarding.window) else { return }
            if !onboarding.handleCloseCommand() { onboarding.window?.performClose(sender) }
            return
        }
        if requiresOnboarding { return }
        if let education = NSApp.keyWindow?.windowController as? ShortcutEssentialsWindow { education.close(); return }
        if let tools = devToolsWindows.first(where: { $0.window === NSApp.keyWindow }) {
            tools.window?.performClose(sender)
        } else if let pip = pictureInPictureWindows.first(where: { $0.window === NSApp.keyWindow }) {
            pip.requestUserClose()
        } else if let owner = spaceCommandWindow, owner.window?.attachedSheet == nil {
            if !performSidebarCommand(sender, kind: .close), owner.canCloseCurrentTab { owner.closeCurrentTab() }
        }
    }
    @objc private func clearToday(_ sender: NSMenuItem) {
        guard !terminationInProgress, !requiresOnboarding, onboarding == nil,
              let command = sender.representedObject as? BrowserClearTodayCommand else { return }
        _ = command.perform()
    }
    @objc private func resetTab(_ sender: Any?) { front?.resetCurrentTab() }
    @objc private func resetVisibleSavedTabs(_ sender: Any?) { front?.resetVisibleSavedTabs() }
    @objc private func restoreTab(_ sender: Any?) { browserWindowCommandOwner?.restoreClosedTab() }
    @objc private func settings(_ sender: Any?) { front?.showSettings() }
    @objc private func importFromBrowser(_ sender: Any?) {
        if let browserImport { browserImport.window?.makeKeyAndOrderFront(nil); return }
        guard started, !terminationInProgress, onboarding == nil, !requiresOnboarding,
              let original = front, !original.isPrivateBrowsing, original.hasReadyPresentation,
              let parent = original.window, parent.attachedSheet == nil else { return }
        let destination = BrowserImportDestination(spaceID: original.activeSpaceID, profileID: original.activeProfileID)
        presentBrowserImport(destination: destination, original: original, parent: parent)
    }

    private func presentBrowserImport(destination: BrowserImportDestination,
                                      original: BrowserWindowController, parent: NSWindow,
                                      resumingSourceBundleID: String? = nil) {
        guard destination.isCurrent(in: store.state) else { return }
        let controller = BrowserImportWindow(store: store, destination: destination, parent: parent,
            ownerIsCurrent: { [weak self, weak original] in
                guard let self, let original else { return false }
                return !self.terminationInProgress && self.windows.contains { $0 === original }
                    && original.hasReadyPresentation
            })
        controller.onClose = { [weak self, weak original, weak controller] restoreFocus in
            self?.browserImport = nil
            if let self, !self.terminationInProgress { self.cancelApplicationRestart("Restart cancelled.") }
            if let self, !self.terminationInProgress,
               let original, self.windows.contains(where: { $0 === original }), original.hasReadyPresentation,
               let parent = original.window,
               BrowserImportFocus.mayReturn(requested: restoreFocus, appIsActive: NSApp.isActive,
                                            parent: parent, importer: controller?.window, key: NSApp.keyWindow) {
                parent.makeKeyAndOrderFront(nil)
            }
        }
        controller.onRequestRestart = { [weak self, weak controller] intent, completion in
            guard let self else { completion("This import is no longer available."); return }
            self.requestBrowserImportRestart(intent, ownerIsCurrent: { [weak self, weak controller] in
                guard let self, let controller else { return false }
                return self.browserImport === controller && controller.window?.isVisible == true
            }, completion: completion)
        }
        browserImport = controller; controller.present()
        if let bundleID = resumingSourceBundleID { controller.resumeSafariImport(sourceBundleID: bundleID) }
    }

    private static func removeReplayRestartDraft(in directory: URL) {
        try? OnboardingDraft.remove(directory: directory, fileName: OnboardingDraft.replayRestartFileName)
    }

    private func requestBrowserImportRestart(_ intent: BrowserImportRestartIntent, owner: AnyObject? = nil,
                                             ownerIsCurrent: @escaping () -> Bool,
                                             completion: @escaping (String?) -> Void) {
        guard started, !terminationInProgress, !quitWarningApprovalPending,
              applicationRestart == nil, ownerIsCurrent(), intent.destination.isCurrent(in: store.state),
              intent.onboarding == requiresOnboarding else {
            completion("This import is no longer available to restart."); return
        }
        if !intent.replay { Self.removeReplayRestartDraft(in: store.directory) }
        let restart = ApplicationRestart()
        applicationRestart = restart; restartCompletion = completion
        restartOwner = owner; armedReplayRestart = false
        restart.prepare(profileDirectory: argument("--parc-profile").map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }) { [weak self, weak restart] failure in
            guard let self, let restart, self.applicationRestart === restart else { return }
            if let failure { self.cancelApplicationRestart(failure); return }
            guard ownerIsCurrent(), intent.destination.isCurrent(in: self.store.state), !self.terminationInProgress else {
                self.cancelApplicationRestart("This import is no longer available to restart."); return
            }
            do {
                try self.store.save()
                try intent.save(in: self.store.directory)
                try restart.arm()
                self.armedReplayRestart = intent.replay
            } catch { self.cancelApplicationRestart(error.localizedDescription); return }
            self.requestApplicationTermination(nil)
            // An existing system sheet can refuse to begin Quit. Keep the
            // chooser usable and revoke the already registered waiter.
            if !self.terminationInProgress && self.quitWarning == nil && !self.quitWarningApprovalPending {
                self.cancelApplicationRestart("Finish the open dialog before restarting Parc.")
            }
        }
    }

    private func cancelApplicationRestart(_ message: String) {
        guard let restart = applicationRestart else { return }
        applicationRestart = nil; restart.cancel()
        restartOwner = nil; armedReplayRestart = false
        BrowserImportRestartIntent.remove(from: store.directory)
        let callback = restartCompletion; restartCompletion = nil; callback?(message)
    }

    private func resumeBrowserImportIfNeeded() {
        guard let intent = pendingImportResume, started, !terminationInProgress else { return }
        guard intent.destination.isCurrent(in: store.state), intent.onboarding == requiresOnboarding else {
            pendingImportResume = nil
            Self.removeReplayRestartDraft(in: store.directory)
            return
        }
        if intent.onboarding {
            guard let onboarding else { return }
            pendingImportResume = nil
            onboarding.resumeSafariImport(destination: intent.destination, sourceBundleID: intent.sourceBundleID)
        } else if let original = front, let parent = original.window,
                  !original.isPrivateBrowsing, original.hasReadyPresentation {
            pendingImportResume = nil
            if intent.replay, onboarding == nil,
               let space = store.state.spaces.first(where: { $0.id == intent.spaceID && $0.profileID == intent.profileID }),
               let draft = OnboardingDraft.takeReplayRestart(directory: store.directory, space: space),
               let controller = try? makeOnboardingReplay(.replay(spaceID: space.id, resuming: draft)) {
                do {
                    try startOnboardingReplay(controller, closing: original) { [weak controller] in
                        controller?.resumeSafariImport(destination: intent.destination, sourceBundleID: intent.sourceBundleID)
                    }
                } catch { presentWindowCreationError(error) }
            } else {
                presentBrowserImport(destination: intent.destination, original: original, parent: parent,
                                     resumingSourceBundleID: intent.sourceBundleID)
            }
        }
    }
    @objc private func setAsDefaultBrowser(_ sender: Any?) {
        DefaultBrowserController.shared.makeDefault { [weak self] failure in
            guard let self, let failure else { return }
            let alert = NSAlert()
            alert.messageText = "Parc could not become your default browser"
            alert.informativeText = failure
            alert.addButton(withTitle: "OK")
            if let window = self.front?.window, window.attachedSheet == nil {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }

    private func showApplicationSettings(profileID: UUID, pane: SettingsWindow.Pane?, shortcutID: String? = nil) {
        guard !terminationInProgress, !requiresOnboarding, onboarding == nil,
              store.state.profiles.contains(where: { $0.id == profileID }),
              !store.isProfileRemovalPending(profileID) else { return }
        if applicationSettingsProfileID != profileID {
            guard applicationSettings?.window?.attachedSheet == nil else { NSSound.beep(); return }
            if let settings = applicationSettings, !settings.attemptClose() { return }
            applicationSettings = nil
        }
        if applicationSettings == nil {
            // This is application Settings, with no private Space assignment.
            // It survives closing the originating private window.
            let settings = SettingsWindow(store: store, spaceID: nil, applicationProfileID: profileID)
            applicationSettings = settings; applicationSettingsProfileID = profileID
            settings.onMoreSettings = { [weak self, weak settings] spaceID, profileID in
                guard let self, let settings else { return false }
                return self.openApplicationSettingsPage(settings, spaceID: spaceID, profileID: profileID, page: nil)
            }
            settings.onProfileSettingsPage = { [weak self, weak settings] spaceID, profileID, page in
                guard let self, let settings else { return false }
                return self.openApplicationSettingsPage(settings, spaceID: spaceID, profileID: profileID, page: page)
            }
        }
        if shortcutID != nil, applicationSettings?.window?.attachedSheet != nil { return }
        applicationSettings?.refresh()
        if let shortcutID { guard applicationSettings?.showShortcut(shortcutID) == true else { return } }
        else if let pane { applicationSettings?.showPane(pane) }
        applicationSettings?.showWindow(nil); applicationSettings?.window?.makeKeyAndOrderFront(nil)
    }

    private func openApplicationSettingsPage(_ settings: SettingsWindow, spaceID: UUID, profileID: UUID, page: ProfileSettingsPage?) -> Bool {
        guard !terminationInProgress, applicationSettings === settings,
              settings.permitsPage(in: store, spaceID: spaceID, profileID: profileID) else { return false }
        do {
            let eligible = windows.filter {
                !$0.isPrivateBrowsing && $0.canAcceptBrowserTab(for: profileID)
                    && $0.window?.attachedSheet == nil && $0.window?.isMiniaturized == false
            }
            let owner = try eligible.first(where: { $0.activeSpaceID == spaceID }) ?? eligible.last
                ?? makeBrowserWindow(renderInitialSelection: true, showImmediately: false, preferredProfileID: profileID)
            let opened: Bool
            if let page {
                opened = owner.showProfileSettingsPage(page, spaceID: spaceID, profileID: profileID, from: settings)
            } else {
                opened = owner.showAdvancedSettings(spaceID: spaceID, profileID: profileID, from: settings)
            }
            // A newly created real window is always presented, including when
            // a native security gate refuses the page-opening request.
            if owner.window?.isVisible == false { owner.showWindow(nil) }
            return opened
        } catch { presentWindowCreationError(error); return false }
    }
    @objc private func showEssentialShortcuts(_ sender: Any?) { front?.showEssentialShortcuts() }
    @objc private func showReleaseNotes(_ sender: Any?) { browserInputCommandWindow?.openReleaseNotes() }
    @objc private func openExtensions(_ sender: Any?) {
        guard let owner = browserInputCommandWindow, owner.canOpenExtensionPicker else { return }
        owner.openExtensionPicker()
    }
    @objc private func copyCurrentURL(_ sender: Any?) {
        if let education = NSApp.keyWindow?.windowController as? ShortcutEssentialsWindow {
            education.activateCommand("copyCurrentURL:", event: NSApp.currentEvent)
            return
        }
        guard let owner = browserCopyCommandOwner else { return }
        if !performSidebarCommand(sender, kind: .copyLinks) { owner.copyCurrentURL() }
    }
    @objc private func copyCurrentURLAsMarkdown(_ sender: Any?) {
        guard let owner = browserInputCommandWindow else { return }
        if !performSidebarCommand(sender, kind: .copyMarkdown) { owner.copyCurrentURLAsMarkdown() }
    }
    @objc private func copyCurrentURLAsQuote(_ sender: Any?) {
        guard let owner = browserInputCommandWindow, !owner.hasSidebarCommandSelection else { return }
        owner.copyCurrentURLAsQuote()
    }
    /// Reached only when no responder in the chain answers Paste and Match
    /// Style itself; forwards to the engine page view's own selector.
    @objc func pasteAsPlainText(_ sender: Any?) { WebpageEditCommands.pasteMatchingStyle(from: sender) }
    @objc private func toggleArcToolbar(_ sender: NSMenuItem) { spaceCommandWindow?.toggleToolbar(from: sender) }
    @objc private func toggleSidebar(_ sender: Any?) { browserInputCommandWindow?.toggleSidebar() }
    @objc private func goBackArrow(_ sender: Any?) {
        guard let owner = browserInputCommandWindow, owner.window === NSApp.keyWindow,
              KeyboardShortcuts.permitsArrowNavigation(in: owner.window) else { return }
        owner.goBack()
    }
    @objc private func goForwardArrow(_ sender: Any?) {
        guard let owner = browserInputCommandWindow, owner.window === NSApp.keyWindow,
              KeyboardShortcuts.permitsArrowNavigation(in: owner.window) else { return }
        owner.goForward()
    }
    @objc private func goBack(_ sender: Any?) { browserInputCommandWindow?.goBack() }
    @objc private func goForward(_ sender: Any?) { browserInputCommandWindow?.goForward() }
    @objc private func reload(_ sender: Any?) { browserInputCommandWindow?.reload() }
    @objc private func forceReload(_ sender: Any?) { browserInputCommandWindow?.forceReload() }
    @objc private func stopLoading(_ sender: Any?) { browserInputCommandWindow?.stopLoading() }
    private weak var clearTodayCommandsMenu: NSMenu?
    private var clearTodayMenuIsTracking = false
    private weak var findCommandsMenu: NSMenu?
    private var findMenuIsTracking = false
    private func findAction(for selector: Selector?) -> BrowserFindAction? {
        switch selector {
        case #selector(find): return .show
        case #selector(findNext): return .next
        case #selector(findPrevious): return .previous
        case #selector(useSelectionForFind): return .useSelection
        case #selector(findAndReplace): return .replace
        case #selector(jumpToSelection): return .jumpToSelection
        default: return nil
        }
    }
    private func performFindCommand(_ sender: Any?, action: BrowserFindAction) {
        if let command = (sender as? NSMenuItem)?.representedObject as? BrowserFindCommand {
            if command.action == action { _ = command.perform() }; return
        }
        let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
        guard spaceCommandWindow?.prepareFindMenuItem(item, action: action) == true else { return }
        _ = (item.representedObject as? BrowserFindCommand)?.perform()
    }
    @objc private func find(_ sender: Any?) { performFindCommand(sender, action: .show) }
    @objc private func findNext(_ sender: Any?) { performFindCommand(sender, action: .next) }
    @objc private func findPrevious(_ sender: Any?) { performFindCommand(sender, action: .previous) }
    @objc private func useSelectionForFind(_ sender: Any?) { performFindCommand(sender, action: .useSelection) }
    @objc private func findAndReplace(_ sender: Any?) { performFindCommand(sender, action: .replace) }
    @objc private func jumpToSelection(_ sender: Any?) { performFindCommand(sender, action: .jumpToSelection) }
    @objc private func zoomIn(_ sender: Any?) { browserInputCommandWindow?.zoomIn() }
    @objc private func zoomOut(_ sender: Any?) { browserInputCommandWindow?.zoomOut() }
    @objc private func actualSize(_ sender: Any?) { browserInputCommandWindow?.actualSize() }
    @objc private func split(_ sender: Any?) {
        if let education = NSApp.keyWindow?.windowController as? ShortcutEssentialsWindow {
            education.activateCommand("split:", event: NSApp.currentEvent)
            return
        }
        if let item = sender as? NSMenuItem, item.representedObject is BrowserWindowController.SplitCommandTarget {
            performSplitMenuCommand(item)
        } else { front?.toggleSplit() }
    }
    private func folderDisclosure(for action: Selector?) -> Bool? {
        if action == #selector(collapseAllFolders) { return false }
        if action == #selector(expandAllFolders) { return true }
        return nil
    }
    private func performFolderDisclosure(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let target = item.representedObject as? BrowserWindowController.FolderDisclosureTarget else { return }
        target.perform()
    }
    @objc private func collapseAllFolders(_ sender: Any?) { performFolderDisclosure(sender) }
    @objc private func expandAllFolders(_ sender: Any?) { performFolderDisclosure(sender) }

    private func splitCommand(for action: Selector?) -> BrowserWindowController.SplitCommand? {
        guard let action else { return nil }
        switch action {
        case #selector(split): return .addNew
        case #selector(closeSplitPane): return .close
        case #selector(separateSplitPane): return .separate
        case #selector(expandSplitPane): return .expand
        case #selector(nextSplitPane): return .next
        case #selector(previousSplitPane): return .previous
        case #selector(firstSplitPane): return .focus(1)
        case #selector(secondSplitPane): return .focus(2)
        case #selector(thirdSplitPane): return .focus(3)
        case #selector(fourthSplitPane): return .focus(4)
        default: return nil
        }
    }
    private func performSplitMenuCommand(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let target = item.representedObject as? BrowserWindowController.SplitCommandTarget else { return }
        target.perform()
    }
    @objc private func closeSplitPane(_ sender: Any?) { performSplitMenuCommand(sender) }
    @objc private func separateSplitPane(_ sender: Any?) { performSplitMenuCommand(sender) }
    @objc private func expandSplitPane(_ sender: Any?) { performSplitMenuCommand(sender) }
    @objc private func nextSplitPane(_ sender: Any?) { performSplitMenuCommand(sender) }
    @objc private func previousSplitPane(_ sender: Any?) { performSplitMenuCommand(sender) }
    @objc private func firstSplitPane(_ sender: Any?) { performSplitMenuCommand(sender) }
    @objc private func secondSplitPane(_ sender: Any?) { performSplitMenuCommand(sender) }
    @objc private func thirdSplitPane(_ sender: Any?) { performSplitMenuCommand(sender) }
    @objc private func fourthSplitPane(_ sender: Any?) { performSplitMenuCommand(sender) }
    @objc private func togglePin(_ sender: Any?) {
        guard let owner = browserInputCommandWindow, !owner.isPrivateBrowsing, !owner.isPopupWindow,
              owner.canOwnDownloadDialog(for: owner.activeProfileID) else { return }
        owner.togglePinFocusedTab()
    }
    @objc private func nextTab(_ sender: Any?) { front?.selectAdjacentTab(forward: true) }
    @objc private func goToSidebarItem(_ sender: NSMenuItem) { front?.selectSidebarItem(number: sender.tag) }
    @objc private func previousTab(_ sender: Any?) { front?.selectAdjacentTab(forward: false) }
    @objc private func cycleTabForward(_ sender: Any?) { front?.cycleTabHistory(forward: true) }
    @objc private func cycleTabBackward(_ sender: Any?) { front?.cycleTabHistory(forward: false) }
    @objc private func cycleToNextRecentTab(_ sender: Any?) {
        if let education = NSApp.keyWindow?.windowController as? ShortcutEssentialsWindow {
            education.activateCommand("cycleToNextRecentTab:", event: NSApp.currentEvent)
            return
        }
        front?.cycleRecentTab(forward: true)
    }
    @objc private func cycleToPreviousRecentTab(_ sender: Any?) { front?.cycleRecentTab(forward: false) }
    @objc private func nextSpace(_ sender: Any?) { spaceCommandWindow?.cycleSpace(forward: true) }
    @objc private func previousSpace(_ sender: Any?) { spaceCommandWindow?.cycleSpace(forward: false) }
    @objc private func captureLibrary(_ sender: Any?) { showLibrary(.captures) }
    @objc private func history(_ sender: Any?) { browserInputCommandWindow?.openHistoryPage() }
    @objc private func archive(_ sender: Any?) { showLibrary(.archive) }
    @objc private func clearArchive(_ sender: Any?) { performLibraryMenuCommand { $0.clearArchive() } }
    private func showLibrary(_ kind: LibraryView.Kind) { performLibraryMenuCommand { $0.showLibrary(kind) } }
    @objc private func toggleReaderMode(_ sender: NSMenuItem) { front?.toggleReaderMode(from: sender) }
    @objc private func clearBrowsingData(_ sender: NSMenuItem) { front?.performPageTool(from: sender) }
    @objc private func clearCacheAndRefresh(_ sender: NSMenuItem) { front?.performPageTool(from: sender) }
    @objc private func clearCookiesAndRefresh(_ sender: NSMenuItem) { front?.performPageTool(from: sender) }
    @objc private func capturePage(_ sender: NSMenuItem) { front?.capturePage(from: sender) }
    @objc private func captureVisiblePage(_ sender: NSMenuItem) { front?.capturePage(from: sender) }
    @objc private func captureFullPage(_ sender: NSMenuItem) { front?.capturePage(from: sender) }
    @objc private func sharePage(_ sender: Any?) { browserInputCommandWindow?.sharePage() }
    @objc private func setAutomaticAppearance(_ sender: Any?) { setAppAppearance(.automatic) }
    @objc private func setLightAppearance(_ sender: Any?) { setAppAppearance(.light) }
    @objc private func setDarkAppearance(_ sender: Any?) { setAppAppearance(.dark) }
    private func setAppAppearance(_ value: AppAppearance) {
        let previous = AppAppearance.current
        guard AppAppearance.apply(value) else { return }
        spaceCommandWindow?.registerAppearanceUndo(from: previous, to: value)
    }
    @objc private func printPage(_ sender: Any?) { front?.performPageTool(.print) }
    ///
    /// owns `save:`; otherwise an Easel exports and a webpage saves.
    @objc private func savePage(_ sender: Any?) {
        if let editor = NSApp.keyWindow as? EaselImageExporting { return editor.exportEaselImage() }
        if front?.canExportEaselImage == true { front?.exportEaselImage() } else { front?.performPageTool(.save) }
    }
    @objc private func toggleFairPlayIdentity(_ sender: NSMenuItem) { front?.toggleFairPlayIdentity(from: sender) }
    @objc private func castPage(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        browserInputCommandWindow?.performPageTool(from: item)
    }
    @objc private func viewSource(_ sender: Any?) { front?.performPageTool(.viewSource) }
    @objc private func developerTools(_ sender: Any?) {
        if let tools = devToolsWindows.first(where: { $0.window === NSApp.keyWindow }) {
            tools.toggleClosed(sender); return
        }
        if let item = sender as? NSMenuItem { front?.performPageTool(from: item) }
        else { front?.performPageTool(.developerTools) }
    }
    @objc private func inspectElements(_ sender: NSMenuItem) { front?.performPageTool(from: sender) }
    @objc private func javaScriptConsole(_ sender: NSMenuItem) { front?.performPageTool(from: sender) }
    @objc private func networkInspector(_ sender: NSMenuItem) { front?.performPageTool(from: sender) }
    @objc private func toggleScriptPermission(_ sender: NSMenuItem) { front?.toggleScriptPermission(from: sender) }
    @objc private func toggleDeveloperMode(_ sender: NSMenuItem) { front?.toggleDeveloperMode(from: sender) }
    @objc private func captureRenderingMetrics(_ sender: Any?) { front?.captureRenderingMetrics() }
    @objc private func downloads(_ sender: Any?) { performLibraryMenuCommand { $0.showDownloads() } }
    @objc private func createSpace(_ sender: Any?) {
        guard let owner = browserInputCommandWindow, owner.canCreateSpaceFromMenu else { return }
        owner.createSpace()
    }
    @objc private func editTheme(_ sender: Any?) {
        guard let owner = browserInputCommandWindow, owner.canEditThemeFromMenu else { return }
        owner.editTheme()
    }
    @objc private func createFolder(_ sender: Any?) {
        if performSidebarCommand(sender, kind: .newFolder) { return }
        front?.createFolder()
    }
    @objc private func createNote(_ sender: Any?) {
        guard started, !terminationInProgress else { return }
        if !initialBrowserOpened, canCreateNoteWithoutBrowser {
            let space = store.activeSpace
            restorationLaunch.deferAction(.newNote(spaceID: space.id, profileID: space.profileID))
            return
        }
        if canCreateNoteWithoutBrowser {
            guard let owner = createStandardWindow(showCommandBar: false), owner === libraryCommandWindow else { return }
            performLibraryMenuCommand { current in if current === owner { current.createNote() } }
        } else { performLibraryMenuCommand { $0.createNote() } }
    }
    @objc private func createNoteInSplit(_ sender: Any?) { performLibraryMenuCommand { $0.createNote(inSplit: true) } }
    @objc private func exportNotes(_ sender: Any?) {
        performLibraryMenuCommand { owner in
            guard owner.canExportNotes else { return }
            let profile = owner.activeProfileID
            // Include drafts in every original window of this profile.
            guard windows.allSatisfy({ $0.prepareNotesForExport(profileID: profile) }),
                  owner.activeProfileID == profile, libraryCommandWindow === owner,
                  owner.canExportNotes else { return }
            owner.exportNotes()
        }
    }
    @objc private func showDocuments(_ sender: Any?) { performLibraryMenuCommand { $0.showLibrary(.documents) } }
    //
    @objc private func openInCurrentSpace(_ sender: NSMenuItem) {
        _ = (sender.representedObject as? PeekOpenCommand)?.perform()
    }
    @objc private func duplicateCurrentItem(_ sender: Any?) { browserInputCommandWindow?.duplicateCurrentItem() }
    @objc private func revealCurrentTabInSidebar(_ sender: Any?) { front?.revealCurrentTabInSidebar() }
    @objc private func openSpaceManager(_ sender: Any?) { performLibraryMenuCommand { $0.showLibrary(.spaces) } }
    @objc private func viewLibrary(_ sender: Any?) { performLibraryMenuCommand { $0.showLibraryFromEntry(nil) } }
    @objc private func changeSpaceProfile(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? SpaceMenuSelection else { return }
        target.owner?.showChangeProfileMenu(target.spaceID, profileID: target.profileID)
    }
    @objc private func renameFocusedSpace(_ sender: Any?) { spaceCommandWindow?.renameActiveSpace() }
    @objc private func newProfile(_ sender: Any?) { spaceCommandWindow?.newProfile() }
    @objc private func manageExtensions(_ sender: Any?) { browserInputCommandWindow?.openExtensionsPage(addExtension: false) }
    @objc private func addExtension(_ sender: Any?) { browserInputCommandWindow?.openExtensionsPage(addExtension: true) }
    @objc private func createEasel(_ sender: Any?) {
        performLibraryMenuCommand { owner in
            guard owner.canCreateNote else { return }
            do {
                let easels = try EaselEditorViewController.sharedStore(directory: owner.activeEaselsDirectory)
                let session = try easels.create()
                owner.openEasel(id: session.document.id, title: session.document.title)
            } catch { showEaselError(error, owner: owner) }
        }
    }
    @objc private func openEasel(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? EaselMenuSelection,
              let original = selection.owner, original === libraryCommandWindow,
              original.activeProfileID == selection.profileID else { return }
        performLibraryMenuCommand { owner in
            guard owner === original, owner.activeProfileID == selection.profileID,
                  owner.canCreateNote else { return }
            do {
                let store = try EaselEditorViewController.sharedStore(directory: owner.activeEaselsDirectory)
                try store.validateReference(selection.id)
                let session = try store.load(selection.id)
                guard !session.isDeleted, !session.isClosed, owner === libraryCommandWindow,
                      owner.activeProfileID == selection.profileID, owner.canCreateNote else { return }
                owner.openEasel(id: selection.id, title: session.document.title)
            } catch { showEaselError(error, owner: owner) }
        }
    }
    private func showEaselError(_ error: Error, owner: BrowserWindowController) {
        guard owner === libraryCommandWindow, let window = owner.window, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = "Couldn’t open Easels"
        alert.informativeText = error.localizedDescription; alert.beginSheetModal(for: window)
    }
    @objc private func quitMenu(_ sender: Any?) {
        //
        DispatchQueue.main.async { [weak self] in
            self?.quitCommandPending = true
            NSApp.terminate(sender)
            self?.quitCommandPending = false
        }
    }
    @objc private func toggleStayOnTop(_ sender: NSMenuItem) {
        guard validateMenuItem(sender), let selection = sender.representedObject as? StayOnTopSelection,
              let owner = selection.owner else { return }
        owner.toggleStayOnTop()
    }
    @objc private func about(_ sender: Any?) {
        if aboutWindow == nil { aboutWindow = AboutParcWindow() }
        aboutWindow?.present()
    }
    private func trace(_ value: @autoclosure () -> String) {
        if arguments.contains("--parc-smoke") { FileHandle.standardError.write(Data(("Parc test: " + value() + "\n").utf8)) }
    }
    /// Wall-clock milliseconds, comparable with a page's performance.timeOrigin.
    private static func epochMilliseconds() -> String {
        String(format: "%.1f", Date().timeIntervalSince1970 * 1000)
    }
    @objc private func selectSpace(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? SpaceMenuSelection,
              let owner = selection.owner, owner === spaceCommandWindow else { return }
        owner.selectSpaceFromUser(selection.spaceID, profileID: selection.profileID)
    }
    private var stateSpaces: [BrowserSpace] { store.state.spaces }
    private func refreshSpaceCommands() {
        guard !spacesMenuIsTracking, let spacesMenu else { return }
        menuNeedsUpdate(spacesMenu)
    }
    func menuWillOpen(_ menu: NSMenu) {
        if menu === windowCommandsMenu { windowCommandsMenuIsTracking = true }
        if menu === spacesMenu { spacesMenuIsTracking = true }
        if menu === clearTodayCommandsMenu {
            for item in menu.items where item.action == #selector(clearToday) || item.action == #selector(openInCurrentSpace) {
                item.representedObject = nil; item.isEnabled = validateMenuItem(item)
            }
            clearTodayMenuIsTracking = true
        }
        if menu === findCommandsMenu {
            for item in menu.items { item.representedObject = nil; item.isEnabled = validateMenuItem(item) }
            findMenuIsTracking = true
        }
        if menu === selectionEditMenu || menu === selectionFileMenu { selectionMenuIsTracking = true }
        if menu === scriptPermissionMenu { scriptPermissionMenuIsTracking = true }
        if menu === splitCommandsMenu { splitMenuIsTracking = true }
    }
    func menuDidClose(_ menu: NSMenu) {
        if menu === windowCommandsMenu { windowCommandsMenuIsTracking = false }
        if menu === spacesMenu {
            spacesMenuIsTracking = false
            // Tracking must finish before replacing the item whose action AppKit
            // is delivering. The next run-loop turn also catches changes deferred
            // while the original menu targets were frozen.
            DispatchQueue.main.async { [weak self] in self?.refreshSpaceCommands() }
        }
        if menu === clearTodayCommandsMenu { clearTodayMenuIsTracking = false }
        if menu === findCommandsMenu { findMenuIsTracking = false }
        if menu === selectionEditMenu || menu === selectionFileMenu { selectionMenuIsTracking = false }
        if menu === scriptPermissionMenu { scriptPermissionMenuIsTracking = false }
        if menu === splitCommandsMenu { splitMenuIsTracking = false }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === windowCommandsMenu, !windowCommandsMenuIsTracking,
           let item = menu.items.first(where: { $0.action == #selector(toggleStayOnTop) }) {
            let owner = stayOnTopWindow
            if let owner, owner.canStayOnTop, let window = owner.window, !terminationInProgress {
                item.representedObject = StayOnTopSelection(owner: owner, window: window)
                item.isHidden = false
                item.state = owner.stayOnTop ? .on : .off
            } else {
                item.representedObject = nil
                item.isHidden = true
            }
        }
        if menu === selectionEditMenu, !selectionMenuIsTracking {
            for item in menu.items where item.identifier?.rawValue == "ParcWindowUndo"
                || item.identifier?.rawValue == "ParcWindowRedo" {
                let redo = item.identifier?.rawValue == "ParcWindowRedo"
                if let owner = front { owner.configureFolderUndoMenuItem(item, redo: redo) }
                else {
                    item.target = nil; item.representedObject = nil
                    item.action = NSSelectorFromString(redo ? "redo:" : "undo:")
                    item.title = redo ? "Redo" : "Undo"
                }
            }
        }
        if (menu === selectionEditMenu || menu === selectionFileMenu), !selectionMenuIsTracking {
            for item in menu.items {
                if sidebarCommandKind(for: item.action) != nil {
                    item.representedObject = nil
                    _ = validateMenuItem(item)
                }
            }
        }
        if menu === scriptPermissionMenu, !scriptPermissionMenuIsTracking {
            for item in menu.items where item.action == #selector(toggleScriptPermission) {
                item.representedObject = nil
                item.isEnabled = front?.prepareScriptPermissionMenuItem(item, preservingTarget: false) ?? false
            }
        }
        if menu === splitCommandsMenu,
           let item = menu.items.first(where: { $0.action == #selector(toggleFairPlayIdentity) }) {
            item.representedObject = nil
            item.isHidden = !(front?.prepareFairPlayIdentityMenuItem(item) ?? false)
        }
        if menu === splitCommandsMenu {
            // Freeze each command's original pane before menu tracking. A
            // later selection/window change disables it instead of retargeting.
            for item in menu.items {
                if let expanded = folderDisclosure(for: item.action) {
                    item.representedObject = nil
                    item.isEnabled = spaceCommandWindow?.prepareFolderDisclosureMenuItem(item,
                        expanded: expanded, preservingTarget: false) ?? false
                    continue
                }
                guard let command = splitCommand(for: item.action) else { continue }
                item.representedObject = nil
                item.isEnabled = spaceCommandWindow?.prepareSplitMenuItem(item, command: command,
                    preservingTarget: false) ?? false
            }
            return
        }
        if menu === easelsMenu {
            menu.removeAllItems()
            let create = NSMenuItem(title: "New Easel", action: #selector(createEasel), keyEquivalent: "")
            create.target = self; menu.addItem(create); menu.addItem(.separator())
            KeyboardShortcuts.shared.register(create, group: "Easels")
            guard let owner = libraryCommandWindow, owner.canCreateNote else { return }
            let profileID = owner.activeProfileID
            do {
                let rows = try EaselEditorViewController.sharedStore(directory: owner.activeEaselsDirectory).list()
                for row in rows {
                    let entry = NSMenuItem(title: row.title, action: #selector(openEasel), keyEquivalent: "")
                    entry.target = self; entry.representedObject = EaselMenuSelection(owner: owner, profileID: profileID, id: row.id); menu.addItem(entry)
                }
                if rows.isEmpty { let empty = NSMenuItem(title: "Your Easels will appear here", action: nil, keyEquivalent: ""); empty.isEnabled = false; menu.addItem(empty) }
            } catch {
                let failure = NSMenuItem(title: error.localizedDescription, action: nil, keyEquivalent: "")
                failure.isEnabled = false; menu.addItem(failure)
            }
            return
        }
        guard menu === spacesMenu, !spacesMenuIsTracking else { return }
        let owner = spaceCommandWindow
        let spaces = stateSpaces
        let source = SpacesMenuSource(owner: owner, activeSpaceID: owner?.activeSpaceID, spaceIDs: spaces.map(\.id),
                                      names: spaces.map(\.name), profileIDs: spaces.map(\.profileID))
        if source == spacesMenuSource, !menu.items.isEmpty { return }
        spacesMenuSource = source
        menu.removeAllItems()
        // MainMenu 1195/1424/442: New Space…, Edit Theme…, Rename Space (no chord).
        for (title, selector) in [("New Space…", #selector(createSpace)), ("Edit Theme…", #selector(editTheme)),
                                  ("Rename Space", #selector(renameFocusedSpace))] {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            entry.target = self; menu.addItem(entry)
            KeyboardShortcuts.shared.register(entry, group: "Spaces")
        }
        menu.addItem(.separator())
        let changeProfile = NSMenuItem(title: "Change Profile", action: #selector(changeSpaceProfile), keyEquivalent: "")
        changeProfile.target = self
        if let space = spaces.first(where: { $0.id == owner?.activeSpaceID }) {
            changeProfile.representedObject = SpaceMenuSelection(owner: owner, space: space)
        }
        menu.insertItem(changeProfile, at: 3)
        //
        //
        // Space; only the first nine receive Control-digit defaults.
        var numberedIDs = Set<String>()
        for (offset, space) in spaces.enumerated() {
            let entry = NSMenuItem(title: space.name, action: #selector(selectSpace), keyEquivalent: "")
            entry.representedObject = SpaceMenuSelection(owner: owner, space: space)
            entry.target = self; entry.state = space.id == owner?.activeSpaceID ? .on : .off
            menu.addItem(entry)
            let number = offset + 1, bindingID = NumberedTarget.spaceBindingID(offset + 1)
            if NumberedTarget.numbers.contains(number) {
                entry.keyEquivalent = String(number); entry.keyEquivalentModifierMask = .control
            }
            numberedIDs.insert(bindingID)
            KeyboardShortcuts.shared.register(entry, group: "Spaces", bindingID: bindingID, title: space.name)
        }
        KeyboardShortcuts.shared.retireCommands(Array(registeredSpaceCommandIDs.subtracting(numberedIDs)))
        registeredSpaceCommandIDs = numberedIDs
        menu.addItem(.separator())
        for (name, selector, key) in [("Next Space", #selector(nextSpace), "\u{F703}"), ("Previous Space", #selector(previousSpace), "\u{F702}")] {
            let entry = NSMenuItem(title: name, action: selector, keyEquivalent: key)
            entry.keyEquivalentModifierMask = [.command, .option]; entry.target = self; menu.addItem(entry)
            KeyboardShortcuts.shared.register(entry, group: "Spaces")
        }
    }

    private func buildMenus() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            item.submenu = submenu; main.addItem(item)
            return submenu
        }
        func item(_ title: String, _ selector: Selector, _ key: String = "", in menu: NSMenu,
                  modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil, discoverable: Bool = true) {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            entry.keyEquivalentModifierMask = modifiers
            entry.target = target ?? self
            menu.addItem(entry)
            KeyboardShortcuts.shared.register(entry, group: menu.title, discoverable: discoverable)
        }
        func alternate(_ title: String, _ selector: Selector, _ key: String, in menu: NSMenu,
                       modifiers: NSEvent.ModifierFlags, bindingID: String? = nil, equivalentOf: String? = nil) {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            entry.keyEquivalentModifierMask = modifiers; entry.target = self
            entry.isHidden = true; entry.allowsKeyEquivalentWhenHidden = true
            menu.addItem(entry)
            if let equivalentOf { KeyboardShortcuts.shared.registerEquivalent(entry, for: equivalentOf, shortcut: .init(key: key, flags: modifiers)) }
            else { KeyboardShortcuts.shared.register(entry, group: menu.title, bindingID: bindingID, discoverable: false) }
        }
        //
        // Toolbar (1095), Reveal Current Tab (778), Duplicate (566), Reset Tab
        // to Original URL (1348), both Cycle Tab items (871, 172) and both Tab
        // Switcher items (1018, 207); their shortcuts and Actions still work.
        func hideKeepingShortcut(_ menu: NSMenu) {
            menu.items.last?.isHidden = true; menu.items.last?.allowsKeyEquivalentWhenHidden = true
        }
        let app = menu("Parc")
        item("About Parc", #selector(about), in: app)
        app.addItem(.separator())
        item("Settings…", #selector(settings), ",", in: app)
        item("Set as Default Browser", #selector(setAsDefaultBrowser), in: app)
        item("Import from Another Browser…", #selector(importFromBrowser), in: app)
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services; app.addItem(servicesItem); NSApp.servicesMenu = services
        app.addItem(.separator())
        item("Hide Parc", #selector(NSApplication.hide(_:)), "h", in: app, target: NSApp)
        item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", in: app, modifiers: [.command, .option], target: NSApp)
        item("Show All", #selector(NSApplication.unhideAllApplications(_:)), in: app, target: NSApp)
        app.addItem(.separator())
        item("Quit Parc", #selector(quitMenu), "q", in: app)

        let file = menu("File")
        selectionFileMenu = file; file.delegate = self
        item("New Tab", #selector(newTab), "t", in: file)
        // MainMenu 240 (addressBar) sits in File.
        item("Open Command Bar", #selector(focusAddress), "l", in: file)
        item("New Window", #selector(newWindow), "n", in: file)
        item("New Incognito Window", #selector(newIncognitoWindow), "n", in: file, modifiers: [.command, .shift])
        // MainMenu 1485: binding newBlankWindow, Control–Command–N, no priority.
        item("Blank Window", #selector(newBlankWindow), "n", in: file, modifiers: [.command, .control])
        item("New Space…", #selector(createSpace), in: file)
        item("New Profile", #selector(newProfile), in: file)
        item("New Note", #selector(createNote), in: file)
        item("New Note in Split View", #selector(createNoteInSplit), in: file)
        hideKeepingShortcut(file)
        item("New Easel", #selector(createEasel), in: file)
        item("Export Notes…", #selector(exportNotes), in: file)
        file.addItem(.separator())
        item("Close Window", #selector(closeWindow), "w", in: file, modifiers: [.command, .shift])
        item("Archive Tab", #selector(closeTab), "w", in: file)
        item("Reopen Last Closed Tab", #selector(restoreTab), "t", in: file, modifiers: [.command, .shift])
        // Shipped MainMenu order and titles (objects 602, 263/1242, 1207, 901):
        // the page actions close the File menu, after Close Window/Archive Tab.
        file.addItem(.separator())
        item("Share…", #selector(sharePage), in: file)
        item("Capture Portion…", #selector(capturePage), in: file)
        item("Capture Visible Area", #selector(captureVisiblePage), in: file)
        item("Capture Full Page", #selector(captureFullPage), in: file)
        item("Save Page As", #selector(savePage), "s", in: file, modifiers: [.command, .shift])
        item("Print", #selector(printPage), "p", in: file)

        let edit = menu("Edit")
        selectionEditMenu = edit; edit.delegate = self
        for (name, selector, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"),
                                      ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            let entry = NSMenuItem(title: name, action: NSSelectorFromString(selector), keyEquivalent: key)
            if selector == "undo:" { entry.identifier = NSUserInterfaceItemIdentifier("ParcWindowUndo") }
            if selector == "redo:" { entry.identifier = NSUserInterfaceItemIdentifier("ParcWindowRedo") }
            edit.addItem(entry)
            KeyboardShortcuts.shared.register(entry, group: "Edit")
            if selector == "redo:" { edit.addItem(.separator()) }
            if selector == "copy:" {
                item("Copy URL", #selector(copyCurrentURL), "c", in: edit, modifiers: [.command, .shift])
                item("Copy URL as Markdown", #selector(copyCurrentURLAsMarkdown), "c", in: edit, modifiers: [.command, .option, .shift])
                item("Copy URL as Quote", #selector(copyCurrentURLAsQuote), "c", in: edit, modifiers: [.command, .control, .shift])
            }
            if selector == "paste:" {
                // MainMenu object 740 (binding pasteAndMatchStyle, no priority)
                //
                //
                // targeted so native text keeps its own pasteAsPlainText:.
                let style = NSMenuItem(title: "Paste and Match Style", action: WebpageEditCommands.pasteMatchingStyle, keyEquivalent: "v")
                style.keyEquivalentModifierMask = [.command, .shift]
                edit.addItem(style)
                KeyboardShortcuts.shared.register(style, group: "Edit")
                let hidden = NSMenuItem(title: "Paste and Match Style", action: WebpageEditCommands.pasteMatchingStyle, keyEquivalent: "v")
                hidden.keyEquivalentModifierMask = [.command, .option, .shift]
                hidden.isHidden = true; hidden.allowsKeyEquivalentWhenHidden = true
                edit.addItem(hidden)
                KeyboardShortcuts.shared.registerEquivalent(hidden, for: "pasteAsPlainText:",
                                                            shortcut: .init(key: "v", flags: [.command, .option, .shift]))
            }
        }
        edit.addItem(.separator())
        let findMenu = NSMenu(title: "Find"); findMenu.delegate = self; findCommandsMenu = findMenu
        let findRoot = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findRoot.submenu = findMenu; edit.addItem(findRoot)
        // Shipped MainMenu order and tags: 799 (1), 822 (12), 1254 (2), 487 (3),
        // 926 (7), 543 (none). Find and Replace and Jump to Selection are
        // available only while a Note editor owns the responder chain.
        item("Find…", #selector(find), "f", in: findMenu)
        item("Find and Replace", #selector(findAndReplace), "f", in: findMenu, modifiers: [.command, .option])
        item("Find Next", #selector(findNext), "g", in: findMenu)
        item("Find Previous", #selector(findPrevious), "g", in: findMenu, modifiers: [.command, .shift])
        item("Use Selection to Find", #selector(useSelectionForFind), in: findMenu)
        item("Jump to Selection", #selector(jumpToSelection), "j", in: findMenu)
        if let selectAll = edit.items.first(where: { $0.action == #selector(NSText.selectAll(_:)) }) {
            WebpageEditCommands.addTextMenus(to: edit, deleteBefore: selectAll, after: findRoot)
        }

        let view = menu("View")
        splitCommandsMenu = view; view.delegate = self
        AppAppearance.addMenu(to: view, target: self)
        view.addItem(.separator())
        item("Show / Hide Sidebar", #selector(toggleSidebar), "s", in: view)
        item("Show Toolbar", #selector(toggleArcToolbar), "d", in: view, modifiers: [.command, .shift])
        hideKeepingShortcut(view)
        // MainMenu 778 (focusSidebar) sits in View.
        item("Reveal Current Tab", #selector(focusSidebar), " ", in: view, modifiers: [.control])
        hideKeepingShortcut(view)
        view.addItem(.separator())
        item("Stop Loading", #selector(stopLoading), ".", in: view)
        item("Refresh the Page", #selector(reload), "r", in: view)
        item("Force Refresh the Page", #selector(forceReload), "r", in: view, modifiers: [.command, .shift])
        item("Clear Cookies and Refresh", #selector(clearCookiesAndRefresh), in: view)
        view.items.last?.toolTip = "Clear this site's cookies, storage and cached data, then refresh. This may sign you out."
        item("Clear Cache and Refresh", #selector(clearCacheAndRefresh), in: view)
        view.items.last?.toolTip = "Reload this page without using cached resources."
        item("Clear Browsing Data…", #selector(clearBrowsingData), in: view)
        //
        // Center's extension picker (WEB14); a hidden shortcut, not a command.
        alternate("Open Extensions", #selector(openExtensions), "e", in: view, modifiers: .command)
        view.addItem(.separator())
        item("Add Split View", #selector(split), "=", in: view, modifiers: [.control, .shift])
        item("Close this Split Pane", #selector(closeSplitPane), "-", in: view, modifiers: [.control, .shift])
        item("Separate Page from Split View", #selector(separateSplitPane), in: view)
        item("Expand Current Split", #selector(expandSplitPane), in: view)
        //
        // commands for numbered and adjacent pane focus (not tab cycling).
        for (title, selector, key) in [
            ("Switch to Split View 1", #selector(firstSplitPane), "1"),
            ("Switch to Split View 2", #selector(secondSplitPane), "2"),
            ("Switch to Split View 3", #selector(thirdSplitPane), "3"),
            ("Switch to Split View 4", #selector(fourthSplitPane), "4"),
            ("Switch to next Split View", #selector(nextSplitPane), "]"),
            ("Switch to previous Split View", #selector(previousSplitPane), "[")
        ] {
            item(title, selector, key, in: view, modifiers: [.control, .shift])
            view.items.last?.isHidden = true
            view.items.last?.allowsKeyEquivalentWhenHidden = true
        }
        view.addItem(.separator())
        item("Zoom to Actual Size", #selector(actualSize), "0", in: view)
        item("Zoom In", #selector(zoomIn), "+", in: view)
        item("Zoom Out", #selector(zoomOut), "-", in: view)
        alternate("Zoom In", #selector(zoomIn), "=", in: view, modifiers: .command, equivalentOf: "zoomIn:")
        alternate("Zoom Out", #selector(zoomOut), "-", in: view, modifiers: [.command, .shift], equivalentOf: "zoomOut:")
        view.addItem(.separator())
        item("Enter Reader", #selector(toggleReaderMode), in: view)
        item("Cast", #selector(castPage), in: view)
        // Shown only for a site with an identity choice (docs/fairplay-identity.md).
        item("Use Chrome Identity for This Site", #selector(toggleFairPlayIdentity), in: view)
        view.items.last?.toolTip = "Sites that play video through Apple FairPlay offer it only to Safari, so Parc shows them Safari's identity."
        view.items.last?.isHidden = true
        view.addItem(.separator())
        let developer = NSMenu(title: "Developer")
        scriptPermissionMenu = developer; developer.delegate = self
        let developerItem = NSMenuItem(title: "Developer", action: nil, keyEquivalent: "")
        developerItem.submenu = developer; view.addItem(developerItem)
        item("View Source", #selector(viewSource), "u", in: developer, modifiers: [.command, .option])
        item("Developer Tools", #selector(developerTools), "i", in: developer, modifiers: [.command, .option])
        alternate("Developer Tools (Alternate)", #selector(developerTools), "\u{f70f}", in: developer,
                  modifiers: [], bindingID: "developerTools_Alternate")
        item("Inspect Elements", #selector(inspectElements), "c", in: developer, modifiers: [.command, .option])
        item("JavaScript Console", #selector(javaScriptConsole), "j", in: developer, modifiers: [.command, .option])
        item("Network Inspector", #selector(networkInspector), in: developer)
        developer.addItem(.separator())
        item("Allow JavaScript from Apple Events", #selector(toggleScriptPermission), "", in: developer)
        item("Turn on Developer Mode for this site", #selector(toggleDeveloperMode), "d", in: developer, modifiers: [.control])
        if arguments.contains("--parc-diagnostics") {
            item("Capture Rendering Metrics", #selector(captureRenderingMetrics), "p", in: view, modifiers: [.command, .option, .shift])
            item("Check Auto-Archive Now", #selector(checkAutoArchive), in: view)
        }
        view.addItem(.separator())
        item("Enter Full Screen", #selector(toggleFullScreen), "f", in: view, modifiers: [.command, .control])
        //
        // no binding ID, so it stays outside the editable registry.
        let globeFullScreen = NSMenuItem(title: "Toggle Full Screen", action: #selector(toggleFullScreen), keyEquivalent: "f")
        globeFullScreen.keyEquivalentModifierMask = .function; globeFullScreen.target = self
        globeFullScreen.isHidden = true; globeFullScreen.allowsKeyEquivalentWhenHidden = true
        view.addItem(globeFullScreen)
        // Registered for Shortcuts/Actions/custom keys; native Escape retains
        // AppKit text/IME and the original renderer acknowledgment owner.
        item("Exit", #selector(exit), "\u{1b}", in: view, modifiers: [])
        view.items.last?.isHidden = true
        view.items.last?.allowsKeyEquivalentWhenHidden = true
        let spaces = menu("Spaces")
        spacesMenu = spaces; spaces.delegate = self; menuNeedsUpdate(spaces)
        let tabs = menu("Tabs")
        clearTodayCommandsMenu = tabs; tabs.delegate = self
        // MainMenu 959 (newFolder) sits in Tabs.
        item("New Folder…", #selector(createFolder), in: tabs)
        item("Pin / Unpin Tab", #selector(togglePin), "d", in: tabs)
        // MainMenu 566 (duplicate) and 752 (revealTabInSidebar): Tabs, no chord.
        // Duplicate has a binding ID but no arcTypeTravelID: menu/Shortcuts only.
        item("Duplicate", #selector(duplicateCurrentItem), in: tabs, discoverable: false)
        hideKeepingShortcut(tabs)
        item("Reveal Tab in Sidebar", #selector(revealCurrentTabInSidebar), in: tabs)
        // MainMenu 1495 openTabIn: Command-O / Use Both, no Actions identity.
        item("Open Peek in Current Space", #selector(openInCurrentSpace), "o", in: tabs, discoverable: false)
        tabs.items.last?.isHidden = true
        // Validate against the real modal even after an earlier absent context.
        tabs.items.last?.allowsKeyEquivalentWhenHidden = true
        item("Reset Tab to Original URL", #selector(resetTab), in: tabs)
        hideKeepingShortcut(tabs)
        item("Clear Today", #selector(clearToday), "k", in: tabs, modifiers: [.command, .shift])
        item("Reset all tabs in this Space", #selector(resetVisibleSavedTabs), in: tabs)
        //
        // without a default chord. Use the same genuine menu registry owner.
        item("Rename Current Tab…", #selector(renameCurrentItem), in: tabs)
        tabs.items.last?.isHidden = true
        tabs.items.last?.allowsKeyEquivalentWhenHidden = true
        item("Next Tab", #selector(nextTab), "\u{f701}", in: tabs, modifiers: [.command, .option])
        item("Previous Tab", #selector(previousTab), "\u{f700}", in: tabs, modifiers: [.command, .option])
        //
        //
        // the hidden items' equivalents), so they are absent from Shortcuts and
        // their chords reach the page. Saved custom bindings stay in the file.
        if TabSelectionHistory.isEnabled {
            item("Cycle Tab Forward", #selector(cycleTabForward), "\u{f703}", in: tabs, modifiers: [.command, .control])
            hideKeepingShortcut(tabs)
            item("Cycle Tab Backward", #selector(cycleTabBackward), "\u{f702}", in: tabs, modifiers: [.command, .control])
            hideKeepingShortcut(tabs)
        }
        item("Switch to Next Recent Tab", #selector(cycleToNextRecentTab), "\t", in: tabs, modifiers: [.control])
        hideKeepingShortcut(tabs)
        item("Switch to Previous Recent Tab", #selector(cycleToPreviousRecentTab), "\t", in: tabs, modifiers: [.control, .shift])
        hideKeepingShortcut(tabs)
        //
        // nextTab/previousTab on the same positional actions, with symbolic
        // Command–} / Command–{ and no priority.
        alternate("Next Tab (Alternate)", #selector(nextTab), "}", in: tabs, modifiers: .command, bindingID: "nextTab")
        alternate("Previous Tab (Alternate)", #selector(previousTab), "{", in: tabs, modifiers: .command, bindingID: "previousTab")
        // MainMenu 134/164 (collapseAllFolders/expandAllFolders) live in Tabs with
        // no default chord. Keep their real menu identities available to command
        // search and custom shortcuts without conflating them with the newer
        // Collapse Pinned Tabs menu section.
        for (title, selector) in [("Collapse All Folders", #selector(collapseAllFolders)),
                                  ("Expand All Folders", #selector(expandAllFolders))] {
            item(title, selector, in: tabs)
            tabs.items.last?.isHidden = true
            tabs.items.last?.allowsKeyEquivalentWhenHidden = true
        }
        //
        // Command-digit 1…9, binding IDs item1…item9, one switchToTab: action.
        for number in 1...9 {
            let title = number == 9 ? "Go to last Sidebar Item" : "Go to Sidebar Item \(number)"
            let entry = NSMenuItem(title: title, action: #selector(goToSidebarItem), keyEquivalent: String(number))
            entry.keyEquivalentModifierMask = .command; entry.tag = number; entry.target = self
            entry.isHidden = true; entry.allowsKeyEquivalentWhenHidden = true
            tabs.addItem(entry)
            KeyboardShortcuts.shared.register(entry, group: tabs.title, bindingID: NumberedTarget.itemBindingID(number))
        }
        let archiveMenu = menu("Archive")
        // Shipped MainMenu Archive objects 946/361/61/1447: page history
        // navigation opens this menu, above the history/archive views.
        item("Go Back", #selector(goBack), "[", in: archiveMenu)
        alternate("Go Back (Alternate)", #selector(goBackArrow), "\u{f702}", in: archiveMenu,
                  modifiers: .command, bindingID: "goBack_Alternate")
        item("Go Forward", #selector(goForward), "]", in: archiveMenu)
        alternate("Go Forward (Alternate)", #selector(goForwardArrow), "\u{f703}", in: archiveMenu,
                  modifiers: .command, bindingID: "goForward_Alternate")
        archiveMenu.addItem(.separator())
        // MainMenu 1144/935/1171 order and titles.
        item("View History", #selector(history), "y", in: archiveMenu)
        item("View Archive", #selector(archive), in: archiveMenu)
        archiveMenu.addItem(.separator())
        item("Clear Archive", #selector(clearArchive), in: archiveMenu)
        // MainMenu Extensions menu (978/1232): MainMenuAction 75/74.
        let extensions = menu("Extensions")
        item("Manage Extensions…", #selector(manageExtensions), in: extensions)
        item("Add Extension…", #selector(addExtension), in: extensions)
        let easels = menu("Easels")
        easelsMenu = easels; easels.delegate = self
        let window = menu("Window")
        windowCommandsMenu = window; window.delegate = self
        let stayOnTop = NSMenuItem(title: "Stay On Top", action: #selector(toggleStayOnTop), keyEquivalent: "")
        stayOnTop.target = self; stayOnTop.isHidden = true
        window.addItem(stayOnTop)
        let minimize = NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(minimize); NSApp.windowsMenu = window
        KeyboardShortcuts.shared.register(minimize, group: "Window")
        // MainMenu 1726: standard Zoom, no binding ID.
        window.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        window.addItem(.separator())
        // MainMenu Window records 451/150/668/1516: the Library destinations.
        item("Manage Spaces…", #selector(openSpaceManager), in: window)
        item("View Library", #selector(viewLibrary), "l", in: window, modifiers: [.command, .shift])
        item("View Downloads", #selector(downloads), "j", in: window, modifiers: [.command, .shift])
        item("View Media", #selector(captureLibrary), in: window)
        item("View Easels & Notes", #selector(showDocuments), in: window)
        window.addItem(.separator())
        // MainMenu 1732: standard Bring All to Front, no binding ID.
        window.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        let help = menu("Help")
        item("Essential Keyboard Shortcuts", #selector(showEssentialShortcuts), in: help)
        // MainMenu Help order: Release Notes follows Essential Keyboard Shortcuts.
        item("Release Notes", #selector(showReleaseNotes), in: help)
        NSApp.helpMenu = help
        NSApp.mainMenu = main
    }
}

extension AppDelegate: BrowserPrivateScriptFactory {
    func scriptingMakePrivateWindow(completion: @escaping (Result<ParcScriptWindow, Error>) -> Void) {
        guard scriptingReady else { completion(.failure(BrowserScriptError.busy)); return }
        let parent = front?.store.privateParentProfileID ?? front?.activeProfileID ?? store.activeSpace.profileID
        createPrivateWindow(parent: parent) { result in
            completion(result.map { ParcScriptWindow(owner: $0) })
        }
    }
    private var scriptingReady: Bool {
        started && initialBrowserOpened && !terminationInProgress && !requiresOnboarding && onboarding == nil
    }
    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        key == "appleScriptWindows"
    }
    @objc dynamic var appleScriptWindows: [ParcScriptWindow] {
        get {
            guard scriptingReady else { return [] }
            let eligible = windows.filter(\.scriptingAvailable)
            let ordered = NSApp.orderedWindows.compactMap { window in eligible.first { $0.window === window } }
            let remainder = eligible.filter { candidate in !ordered.contains { $0 === candidate } }
            return (ordered + remainder).map { ParcScriptWindow(owner: $0) }
        }
        set {
            guard scriptingReady,
                  acceptScriptInsertion(newValue, existing: appleScriptWindows, id: { $0.identifier },
                    pending: { $0.isPendingInsertion },
                    owned: { wrapper in windows.contains { wrapper.belongs(to: $0) } },
                    consume: { wrapper in
                        guard let owner = windows.first(where: { wrapper.belongs(to: $0) }) else { return false }
                        return wrapper.acceptInsertion(owner: owner)
                    }) else {
                BrowserScriptError.report(BrowserScriptError.unsupported("Moving or replacing scripted windows is not supported.")); return
            }
        }
    }
    override func newScriptingObject(of objectClass: AnyClass, forValueForKey key: String,
                                     withContentsValue contentsValue: Any?, properties: [String: Any]) -> Any? {
        do {
            guard scriptingReady else { throw BrowserScriptError.busy }
            guard objectClass == ParcScriptWindow.self, key == "appleScriptWindows", contentsValue == nil else {
                throw BrowserScriptError.unsupported("Create tabs inside a window or Space. Application-level Little Arc tabs are not supported.")
            }
            let incognito = try scriptWindowCreationIsIncognito(properties)
            let parent = front?.store.privateParentProfileID ?? front?.activeProfileID ?? store.activeSpace.profileID
            let controller = try makeBrowserWindow(renderInitialSelection: true,
                preferredProfileID: parent, privateParentProfileID: incognito ? parent : nil)
            return ParcScriptWindow(owner: controller, pendingInsertion: true)
        } catch {
            BrowserScriptError.report(error); return nil
        }
    }
}
