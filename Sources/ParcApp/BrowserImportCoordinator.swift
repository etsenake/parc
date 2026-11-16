import AppKit
import Combine

@MainActor
final class BrowserImportCoordinator {
    enum Stage { case sources, loading, profiles, safariAccess, importing, passwordChoice, safariPasswords, bookmarks, finished }
    struct BookmarkPage {
        let id = UUID()
        let sourceName: String
        let destination: BrowserImportDestination
        var selection: BrowserImportSelection
        var committed = false
        var placement = BrowserImportPlacement()
        var accepted: BrowserImportSelection?
        var discarded = false
        var skipped = false
    }
    let store: BrowserStore
    let originalDestination: BrowserImportDestination
    private weak var window: NSWindow?
    private let ownerIsCurrent: () -> Bool
    private let onboarding: Bool
    let supportsICloudPasswords: Bool
    var onChange: (() -> Void)?
    private(set) var stage: Stage = .loading {
        didSet { if stage == .finished && !hasBackgroundWork { reportDataFailure() } }
    }
    private(set) var sources: [PCNativeImportSource] = []
    private(set) var source: PCNativeImportSource?
    private(set) var profiles: [PCNativeImportProfile] = []
    private(set) var selectedProfiles = Set<String>()
    private(set) var importedAdBlockers: [OnboardingDraft.ImportedAdBlocker] = []
    private(set) var bookmarkPages: [BookmarkPage] = []
    private(set) var message = "Finding your browsers…"
    private(set) var warnings: [String] = []
    private(set) var error: String?
    private let skipExistingCookies = true
    private(set) var safariAccessReady = false
    private var requiresSafariAccess = false
    private(set) var checkingSafariAccess = false
    private(set) var restarting = false
    private var restartWaitingToken: UUID?
    var retryRestart: (() -> Void)?
    private(set) var continueAfterSafariRefresh = false
    private(set) var safariAccessError: String?
    private(set) var passwordDestination: BrowserImportDestination?
    private(set) var wantsICloudPasswords = false
    private(set) var acceptedICloudPasswordsDestination: BrowserImportDestination?
    private(set) var passwordResult: PCNativePasswordFileImportResult?
    private(set) var passwordFileName: String?
    private(set) var passwordRequestID: UUID?
    private(set) var importingPasswords = false
    private(set) var removingPasswordFile = false
    private(set) var passwordFileRemoved = false
    private(set) var passwordError: String?
    private var passwordSession: PCNativePasswordFileImportSession?
    private var passwordStageOffered = false
    private var keepsPasswordChoice = false
    private var passwordsWithoutData = false
    private(set) var parkedStage: Stage?
    private(set) var foundNoSources = false
    private var generation = UUID()
    private var discovery: PCNativeImportDiscovery?
    private var session: PCNativeImportSession?
    private static var detachedImports: [BrowserImportCoordinator] = []
    private static var waitingStarts: [() -> Void] = []
    private static var earlierImportRunning: Bool { detachedImports.contains { $0.hasBackgroundWork } }
    private var detached = false
    private var onDetachedAdBlockers: (([OnboardingDraft.ImportedAdBlocker]) -> Void)?
    private(set) var hasBackgroundWork = false
    private var backgroundProfiles: [(profile: PCNativeImportProfile, destination: BrowserImportDestination)] = []
    private var backgroundSessions: [UUID: PCNativeImportSession] = [:]
    private var backgroundPending = Set<UUID>()
    private var startingBackground = false
    private var backgroundDeferred = false
    private var backgroundToken = UUID()

    func detach(onAdBlockers: (([OnboardingDraft.ImportedAdBlocker]) -> Void)?) {
        guard hasBackgroundWork, !cancelled else { cancel(); return }
        onChange = nil
        if !importingPasswords { passwordSession?.cancel(); passwordSession = nil; startDeferredBackground() }
        onDetachedAdBlockers = onAdBlockers
        if !detached { detached = true; Self.detachedImports.append(self) }
    }

    private func reportBackgroundWarnings(_ lines: [String]) { warnings += lines }

    private var dataFailed = false, dataImported = false, dataFailureReported = false
    private func record(_ result: PCNativeImportResult) {
        switch result.outcome {
        case .cancelled: dataImported = true
        case .completed where result.error == nil: dataImported = true
        case .partial: dataImported = true; dataFailed = true
        default: dataFailed = true
        }
    }
    private func failed(_ line: String) { warnings.append(line); dataFailed = true }

    private func reportDataFailure() {
        guard dataFailed, !dataFailureReported else { return }
        dataFailureReported = true
        ImportedBrowserDataFailures.add(dataImported ? .partial : .failed)
    }

    private func finishBackground() {
        hasBackgroundWork = false
        reportDataFailure()
        if detached {
            onDetachedAdBlockers?(importedAdBlockers)
            onDetachedAdBlockers = nil
            Self.detachedImports.removeAll { $0 === self }
            if !Self.earlierImportRunning {
                let starts = Self.waitingStarts; Self.waitingStarts = []
                starts.forEach { $0() }
            }
        }
    }
    private var activeDestination: BrowserImportDestination?
    private var pendingExtensions: [(profile: PCNativeImportProfile, destination: BrowserImportDestination, ids: Set<String>)] = []
    private var extensionInstall: PCNativeImportSession?
    private var extensionBatch: UUID?
    private let arcSidebarURL: URL
    private let arcPreferencesURL: URL
    private var queue: [PCNativeImportProfile] = []
    private var queuedDestinations: [String: BrowserImportDestination] = [:]
    private var usedProfiles = Set<UUID>()
    private var completed = 0
    private var cancelled = false
    private var subscription: AnyCancellable?

    init(store: BrowserStore, destination: BrowserImportDestination, window: NSWindow, onboarding: Bool = false,
         supportsICloudPasswords: Bool = ICloudPasswordsSupport.connects(),
         arcSidebarURL: URL = ArcSidebarSnapshot.defaultURL,
         arcPreferencesURL: URL = ArcSidebarSnapshot.preferencesURL,
         ownerIsCurrent: @escaping () -> Bool) {
        self.store = store; originalDestination = destination; self.window = window
        self.arcSidebarURL = arcSidebarURL; self.arcPreferencesURL = arcPreferencesURL
        self.onboarding = onboarding
        self.supportsICloudPasswords = supportsICloudPasswords
        self.ownerIsCurrent = ownerIsCurrent
        subscription = store.statePublisher.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.cancelled else { return }
                if !self.isCurrent {
                    self.cancel()
                } else if self.activeDestination.map({ !$0.isCurrent(in: self.store.state) }) == true {
                    self.queue = []
                    self.session?.cancel()
                    self.message = "Stopping import because its destination was removed…"
                    self.onChange?()
                } else if self.passwordDestination.map({ !$0.isCurrent(in: self.store.state) }) == true {
                    self.passwordSession?.cancel()
                    self.passwordError = "The destination Space is no longer available."
                    self.onChange?()
                } else if self.stage == .bookmarks {
                    self.onChange?()
                }
            }
        }
    }

    private var isCurrent: Bool {
        !cancelled && (detached || (window != nil && ownerIsCurrent())) && !store.isEphemeral
            && originalDestination.isCurrent(in: store.state)
    }

    static func isSafari(_ source: PCNativeImportSource) -> Bool {
        Bundle(url: source.appURL)?.bundleIdentifier == "com.apple.Safari"
    }
    static func keychainNote(for source: PCNativeImportSource) -> String? {
        guard !isSafari(source), !firefoxFamily.keys.contains(source.identifier) else { return nil }
        let name = source.displayName
        return "macOS may ask to let Parc use \(name)’s Safe Storage key. It unlocks the bookmarks, passwords and cookies \(name) keeps encrypted."
    }
    static let arcBundleIdentifier = "company.thebrowser.Browser"
    static func isArc(_ source: PCNativeImportSource) -> Bool { source.identifier == arcBundleIdentifier }
    var isArcSource: Bool { source.map(Self.isArc) == true }
    static let firefoxFamily: [String: BrowserPasswordExport] = ["org.mozilla.firefox": .firefox, "app.zen-browser.zen": .zen]
    static func passwordExport(for source: PCNativeImportSource) -> BrowserPasswordExport? {
        isSafari(source) ? .safari : firefoxFamily[source.identifier]
    }
    var passwordExport: BrowserPasswordExport? { source.flatMap(Self.passwordExport) }
    var offersICloudPasswordChoice: Bool { supportsICloudPasswords && passwordExport == .safari }

    func discover(resumingSourceBundleID: String? = nil) {
        guard isCurrent else { return }
        guard !hasBackgroundWork, stage != .importing && stage != .bookmarks && stage != .passwordChoice && stage != .safariPasswords && !restarting,
              parkedStage == nil else { return }
        discovery?.cancel(); generation = UUID(); let token = generation
        foundNoSources = false
        checkingSafariAccess = false; continueAfterSafariRefresh = false; safariAccessError = nil
        source = nil; sources = []; profiles = []; selectedProfiles = []
        passwordDestination = nil; passwordStageOffered = false
        wantsICloudPasswords = false; acceptedICloudPasswordsDestination = nil
        safariAccessReady = false; requiresSafariAccess = false
        extensionBatch = nil
        stage = .loading; message = "Finding your browsers…"; error = nil; onChange?()
        discovery = PCNativeBrowserApplication.availableImportSources { [weak self] sources in
            guard let self, self.isCurrent, self.generation == token else { return }
            let priorities = [Self.arcBundleIdentifier: 0, "com.google.Chrome": 1]
            self.discovery = nil
            self.sources = sources.enumerated().sorted {
                (priorities[$0.element.identifier] ?? 2, $0.offset) < (priorities[$1.element.identifier] ?? 2, $1.offset)
            }.map(\.element)
            if self.onboarding && sources.isEmpty {
                self.foundNoSources = true; self.stage = .finished
                self.message = "No supported browsers were found."; self.onChange?(); return
            }
            self.stage = .sources
            self.message = sources.isEmpty ? "No supported browsers were found." : "Bring your browsing with you."
            if let bundleID = resumingSourceBundleID {
                guard let source = sources.first(where: {
                    Bundle(url: $0.appURL)?.bundleIdentifier == bundleID || (Self.isArc($0) && bundleID == Self.arcBundleIdentifier)
                }) else {
                    self.error = "The selected browser is no longer available. Choose an installed browser to continue."
                    self.onChange?(); return
                }
                self.source = source; self.loadProfiles()
            } else { self.onChange?() }
        }
    }

    func select(_ source: PCNativeImportSource) {
        guard stage == .sources, sources.contains(where: { $0 === source }), isCurrent else { return }
        self.source = source; error = nil; onChange?()
    }

    var isChoosingSourceInline: Bool {
        stage == .sources || stage == .profiles || (stage == .loading && source != nil)
    }

    func selectSourceInline(_ source: PCNativeImportSource) {
        guard isChoosingSourceInline, isCurrent, parkedStage == nil, sources.contains(where: { $0 === source }) else { return }
        if self.source === source && (stage == .loading || (stage == .profiles && error == nil)) { return }
        clearSourceInline(notify: false)
        self.source = source
        loadProfiles(inline: true)
    }

    func clearSourceInline() { clearSourceInline(notify: true) }

    private func clearSourceInline(notify: Bool) {
        guard isChoosingSourceInline, isCurrent, parkedStage == nil else { return }
        generation = UUID(); discovery?.cancel(); discovery = nil
        source = nil; profiles = []; selectedProfiles = []
        requiresSafariAccess = false; safariAccessReady = false
        warnings = []; error = nil; stage = .sources
        message = "Bring your browsing with you."
        if notify { onChange?() }
    }

    var canContinueSourceInline: Bool {
        stage == .profiles && isCurrent && (parkedStage != nil || requiresSafariAccess || hasImportableSelection)
    }

    func chooseSourceInline(_ source: PCNativeImportSource, from sources: [PCNativeImportSource]) {
        guard stage == .loading, discovery == nil, isCurrent, sources.contains(where: { $0 === source }) else { return }
        self.sources = sources; stage = .sources; message = "Bring your browsing with you."
        selectSourceInline(source)
    }

    func continueSourceInline() {
        guard canContinueSourceInline else { return }
        if let parked = parkedStage {
            parkedStage = nil; stage = parked; onChange?(); return
        }
        if requiresSafariAccess {
            stage = .safariAccess; onChange?()
        } else {
            startInOriginalDestination()
        }
    }

    func loadProfiles(inline: Bool = false) {
        guard stage == .sources, let source, isCurrent else { return }
        generation = UUID(); let token = generation
        stage = .loading; message = "Finding your \(source.displayName) profiles…"; onChange?()
        discovery = PCNativeBrowserApplication.loadImportSourceProfiles(source) { [weak self] result in
            guard let self, self.isCurrent, self.generation == token, self.source === source else { return }
            self.discovery = nil; self.applyProfiles(result)
            self.requiresSafariAccess = result.access == .restricted
            self.stage = self.requiresSafariAccess && !self.onboarding && !inline ? .safariAccess : .profiles
            self.onChange?()
        }
    }

    private func applyProfiles(_ result: PCNativeImportProfileResult) {
        profiles = result.profiles; warnings = []
        let readable = result.profiles.filter { $0.supportedCategories.rawValue != 0 }
        selectedProfiles = Set((readable.isEmpty ? Array(result.profiles.prefix(1)) : readable).map(\.identifier))
        error = result.error?.localizedDescription
        message = result.profiles.isEmpty ? "No readable profiles were found." : "Bring your browsing with you."
        safariAccessReady = result.error == nil && result.access == .complete && result.profiles.contains {
            $0.access == .complete && $0.supportedCategories.contains(.history)
        }
    }

    func refreshSafariAccess() {
        guard stage == .safariAccess, !checkingSafariAccess, !restarting, restartWaitingToken == nil,
              isCurrent, let source else { return }
        checkingSafariAccess = true; generation = UUID(); let token = generation
        onChange?()
        discovery = PCNativeBrowserApplication.loadImportSourceProfiles(source) { [weak self] result in
            guard let self, self.isCurrent, self.generation == token,
                  self.stage == .safariAccess, self.source === source, !self.restarting else { return }
            self.discovery = nil; self.checkingSafariAccess = false; self.applyProfiles(result)
            if self.continueAfterSafariRefresh {
                self.continueAfterSafariRefresh = false; self.requiresSafariAccess = false; self.stage = .profiles
                if self.onboarding { self.continueSetupAfterSafariAccess(); return }
            }
            self.onChange?()
        }
    }

    func continueSafariWithoutRestarting() {
        guard stage == .safariAccess, !restarting, isCurrent else { return }
        restartWaitingToken = nil
        continueAfterSafariRefresh = true; safariAccessError = nil
        refreshSafariAccess()
    }

    private func continueSetupAfterSafariAccess() {
        if hasImportableSelection { startInOriginalDestination(); return }
        if passwordExport != nil {
            let keepsChoice = keepsPasswordChoice
            beginImport(); keepsPasswordChoice = keepsChoice
            passwordDestination = originalDestination; passwordsWithoutData = true
            _ = presentPasswordStageIfNeeded()
        } else {
            stage = .finished; message = "Your import has finished."
        }
        onChange?()
    }

    func beginSafariRestart() -> Bool {
        guard stage == .safariAccess, isCurrent, safariAccessReady, !checkingSafariAccess,
              !restarting, source != nil else { return false }
        if Self.earlierImportRunning {
            guard restartWaitingToken == nil else { return false }
            let token = UUID(); restartWaitingToken = token
            safariAccessError = "Finishing your last import…"; onChange?()
            Self.waitingStarts.append { [weak self] in
                guard let self, self.restartWaitingToken == token else { return }
                self.restartWaitingToken = nil; self.safariAccessError = nil; self.onChange?()
                guard self.isCurrent, self.stage == .safariAccess else { return }
                self.retryRestart?()
            }
            return false
        }
        restarting = true; continueAfterSafariRefresh = false; error = nil; safariAccessError = nil
        generation = UUID(); discovery?.cancel(); discovery = nil
        onChange?(); return true
    }

    func safariRestartFailed(_ message: String?) {
        guard isCurrent, stage == .safariAccess, restarting else { return }
        restarting = false; safariAccessError = message ?? "Restart was cancelled. You can continue without restarting."
        onChange?()
    }

    func reportSafariAccessError(_ message: String) {
        guard isCurrent, stage == .safariAccess, !restarting else { return }
        safariAccessError = message; onChange?()
    }

    var hasImportableSelection: Bool { isCurrent && !chosenProfiles.isEmpty }

    func startInOriginalDestination() {
        guard stage == .profiles, isCurrent, hasImportableSelection else { return }
        if Self.earlierImportRunning {
            generation = UUID(); let token = generation
            stage = .importing; error = nil; message = "Finishing your last import…"; onChange?()
            Self.waitingStarts.append { [weak self] in
                guard let self, self.isCurrent, self.generation == token, self.stage == .importing else { return }
                self.stage = .profiles; self.startInOriginalDestination()
            }
            return
        }
        let chosen = chosenProfiles
        if isArcSource { startArc(chosen); return }
        beginImport()
        passwordDestination = passwordExport == nil ? nil : originalDestination
        queueProfiles(chosen, primaryDestination: originalDestination)
        importNext()
    }

    private var chosenProfiles: [PCNativeImportProfile] {
        let chosen = profiles.filter { profile in
            var categories = profile.supportedCategories
            if profile.extensions.isEmpty { categories.remove(.extensions) }
            return selectedProfiles.contains(profile.identifier) && categories.rawValue != 0
        }
        guard let primary = chosen.first(where: { $0.directoryName == "Default" }) ?? chosen.first else { return [] }
        return [primary] + chosen.filter { $0 !== primary }
    }

    private func beginImport() {
        stage = .importing; completed = 0; bookmarkPages = []; importedAdBlockers = []; error = nil
        dataFailed = false; dataImported = false; dataFailureReported = false
        pendingExtensions = []; backgroundProfiles = []; extensionBatch = nil; passwordStageOffered = false
        keepsPasswordChoice = false; passwordsWithoutData = false; parkedStage = nil
        queue = []; queuedDestinations = [:]; usedProfiles = []; activeDestination = nil
        generation = UUID()
    }

    private func queueProfiles(_ chosen: [PCNativeImportProfile], primaryDestination: BrowserImportDestination?,
                               known: [String: BrowserImportDestination] = [:]) {
        for (index, profile) in chosen.enumerated() {
            guard let destination = known[profile.identifier] ?? (index == 0 ? primaryDestination : nil) else { continue }
            queuedDestinations[profile.identifier] = destination; usedProfiles.insert(destination.profileID)
        }
        queue = chosen
    }

    private func destination(named name: String, excluding used: Set<UUID>) throws -> BrowserImportDestination {
        let state = store.state
        if let profile = state.profiles.first(where: { profile in !used.contains(profile.id)
               && !state.profileRemovals.contains { $0.profileID == profile.id }
               && profile.name.caseInsensitiveCompare(name) == .orderedSame }),
           let target = BrowserImportProfileTarget.choices(in: state, original: originalDestination).first(where: { $0.profileID == profile.id }) {
            return try store.prepareImportDestination(target, basedOn: originalDestination)
        }
        return try store.createImportDestination(name: name, basedOn: originalDestination)
    }

    private func startArc(_ chosen: [PCNativeImportProfile]) {
        beginImport(); passwordDestination = nil
        let token = generation
        message = "Importing \(chosen[0].displayName)…"; onChange?()
        let url = arcSidebarURL, preferencesURL = arcPreferencesURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try ArcSidebarSnapshot.read(url, preferences: preferencesURL) }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.importArcSidebar(result, profiles: chosen, token: token) }
            }
        }
    }

    private func importArcSidebar(_ result: Result<(ArcSidebarImport, [String: Any]), Error>,
                                  profiles chosen: [PCNativeImportProfile], token: UUID) {
        guard isCurrent, generation == token, stage == .importing else { return }
        let keyed = chosen.map { (profile: $0, key: ArcSidebarImport.profileKey(directory: $0.directoryName)) }
        do {
            if case .success((var arc, let preferences)) = result {
                arc.autoArchiveHours = ArcSidebarImport.autoArchiveHours(preferences: preferences, profiles: keyed.map(\.key))
                let destinations = try store.importArcSidebar(arc, profiles: keyed.map { ($0.key, $0.profile.displayName) },
                    standardProfileID: originalDestination.profileID, primary: keyed[0].key, into: originalDestination.profileID)
                var known: [String: BrowserImportDestination] = [:]
                for item in keyed { known[item.profile.identifier] = destinations[item.key] }
                known[keyed[0].profile.identifier] = originalDestination
                queueProfiles(chosen, primaryDestination: nil, known: known)
            } else {
                queueProfiles(chosen, primaryDestination: originalDestination)
            }
        } catch {
            queue = []; queuedDestinations = [:]; stage = .profiles; self.error = error.localizedDescription; onChange?(); return
        }
        importNext()
    }

    private func importNext() {
        guard isCurrent, let window else { cancel(); return }
        guard !queue.isEmpty else {
            if passwordDestination?.isCurrent(in: store.state) == true { hasBackgroundWork = true; backgroundDeferred = true }
            else { startBackground(in: window) }
            if !(onboarding && hasPendingBookmarks), presentPasswordStageIfNeeded() {
                onChange?(); return
            }
            stage = hasPendingBookmarks ? .bookmarks : .finished
            message = hasPendingBookmarks ? "Choose the bookmarks to keep in your sidebar." : "Your import has finished."
            onChange?(); return
        }
        let profile = queue.removeFirst(), token = generation
        if let known = queuedDestinations.removeValue(forKey: profile.identifier) {
            activeDestination = known
        } else {
            do {
                activeDestination = try destination(named: profile.displayName, excluding: usedProfiles)
                usedProfiles.insert(activeDestination!.profileID)
            } catch {
                activeDestination = nil; failed("\(profile.displayName) could not be imported.")
                completed += 1; importNext(); return
            }
        }
        var categories = profile.supportedCategories
        categories.remove(.extensions)
        let extensions = Set(profile.extensions.map(\.identifier))
        guard let destination = activeDestination, destination.isCurrent(in: store.state) else {
            finishSourceFailure("The selected destination is no longer available."); return
        }
        if !extensions.isEmpty { pendingExtensions.append((profile, destination, extensions)) }
        backgroundProfiles.append((profile, destination))
        guard categories.contains(.bookmarks) else { activeDestination = nil; completed += 1; importNext(); return }
        categories = [.bookmarks]
        message = "Importing \(profile.displayName)…"; onChange?()
        session = PCNativeBrowserApplication.importBrowserData(from: profile,
            toProfilePath: store.independentEngineProfilePath(for: destination.profileID), in: window,
            categories: categories, skipExistingCookies: skipExistingCookies,
            progress: { [weak self] event in
                guard let self, self.isCurrent, self.generation == token,
                      destination.isCurrent(in: self.store.state) else { return }
                self.message = event.message ?? "Importing \(profile.displayName)…"
                self.onChange?()
            }, completion: { [weak self] result in
                guard let self, self.isCurrent, self.generation == token else { return }
                self.session = nil; self.activeDestination = nil
                guard destination.isCurrent(in: self.store.state) else {
                    self.finishSourceFailure("\(profile.displayName): its destination was removed, so this import stopped.")
                    return
                }
                self.warnings += result.warnings; self.record(result)
                if let error = result.error { self.warnings.append("\(profile.displayName): \(error.localizedDescription)") }
                if result.outcome == .failed && result.error == nil {
                    self.warnings.append("\(profile.displayName) could not be imported.")
                }
                do {
                    if !result.bookmarks.isEmpty {
                        let selection = try BrowserImportSelection(roots: Self.bookmarks(result.bookmarks),
                            expandsTopFolders: self.onboarding)
                        self.bookmarkPages.append(BookmarkPage(sourceName: profile.displayName,
                                                              destination: destination, selection: selection))
                    }
                } catch { self.failed("Bookmarks: \(error.localizedDescription)") }
                self.completed += 1
                if result.outcome == .cancelled {
                    self.queue = []; self.pendingExtensions = []; self.backgroundProfiles = []; self.passwordDestination = nil
                    self.message = "Import stopped. Data already imported has been kept."
                    self.stage = self.bookmarkPages.isEmpty ? .finished : .bookmarks; self.onChange?()
                } else { self.importNext() }
            })
        if session == nil {
            activeDestination = nil; queue = []
            finishSourceFailure("Parc could not begin the import from \(profile.displayName).")
        }
    }

    private func startBackground(in window: NSWindow) {
        let pending = backgroundProfiles; backgroundProfiles = []
        hasBackgroundWork = true; startingBackground = true
        backgroundToken = UUID(); let token = backgroundToken
        for item in pending {
            var categories = item.profile.supportedCategories
            categories.remove(.bookmarks); categories.remove(.extensions)
            guard categories.rawValue != 0 else { continue }
            guard item.destination.isCurrent(in: store.state) else {
                dataFailed = true
                reportBackgroundWarnings(["\(item.profile.displayName): its destination was removed, so this import stopped."])
                continue
            }
            let id = UUID()
            backgroundPending.insert(id)
            let lease = PCNativeBrowserApplication.importBrowserData(from: item.profile,
                toProfilePath: store.independentEngineProfilePath(for: item.destination.profileID), in: window,
                categories: categories, skipExistingCookies: skipExistingCookies,
                progress: { _ in }, completion: { [weak self] result in
                    guard let self, self.backgroundToken == token, !self.cancelled,
                          self.backgroundPending.remove(id) != nil else { return }
                    self.backgroundSessions[id] = nil
                    self.reportBackgroundWarnings(result.warnings); self.record(result)
                    if let error = result.error { self.reportBackgroundWarnings(["\(item.profile.displayName): \(error.localizedDescription)"]) }
                    else if result.outcome == .failed { self.reportBackgroundWarnings(["\(item.profile.displayName) could not be imported."]) }
                    self.onChange?()
                    self.backgroundDataFinished()
                })
            if backgroundPending.contains(id) {
                if let lease { backgroundSessions[id] = lease }
                else {
                    backgroundPending.remove(id); dataFailed = true
                    reportBackgroundWarnings(["Parc could not begin the import from \(item.profile.displayName)."])
                }
            }
        }
        startingBackground = false
        backgroundDataFinished()
    }

    private func startDeferredBackground() {
        guard backgroundDeferred, !cancelled else { return }
        backgroundDeferred = false
        guard let host = (window?.isVisible == true ? window : nil) ?? NSApp.windows.first(where: { $0.isVisible }) ?? window else {
            if !backgroundProfiles.isEmpty { dataFailed = true }
            reportBackgroundWarnings(backgroundProfiles.map { "\($0.profile.displayName) could not be imported." })
            backgroundProfiles = []; reportFailedExtensions(pendingExtensions.flatMap { item in
                item.profile.extensions.filter { item.ids.contains($0.identifier) }.map(\.displayName) },
                announcing: !dataFailed)
            pendingExtensions = []; finishBackground(); return
        }
        startBackground(in: host)
    }

    private func backgroundDataFinished() {
        guard hasBackgroundWork, !startingBackground, backgroundPending.isEmpty else { return }
        installExtensions()
    }

    private func installExtensions() {
        let pending = pendingExtensions; pendingExtensions = []
        var requests: [PCNativeImportExtensionRequest] = [], requested: [String: Set<String>] = [:]
        var items: [PCNativeImportExtension] = [], destinations: [String: [UUID]] = [:]
        for item in pending {
            let chosen = item.profile.extensions.filter { item.ids.contains($0.identifier) }
            guard item.destination.isCurrent(in: store.state) else {
                reportFailedExtensions(chosen.map(\.displayName), announcing: !dataFailed); continue
            }
            let path = store.independentEngineProfilePath(for: item.destination.profileID)
            let ids = item.ids.subtracting(requested[path] ?? [])
            guard !ids.isEmpty else { continue }
            requested[path, default: []].formUnion(ids)
            requests.append(PCNativeImportExtensionRequest(source: item.profile, profilePath: path, extensionIDs: ids))
            items += chosen.filter { ids.contains($0.identifier) }
            for id in ids where !(destinations[id]?.contains(item.destination.profileID) ?? false) {
                destinations[id, default: []].append(item.destination.profileID)
            }
        }
        guard !requests.isEmpty else { finishBackground(); return }
        let token = backgroundToken, batch = UUID()
        extensionBatch = batch

        extensionInstall = PCNativeBrowserApplication.installImportedExtensions(requests, completion: { [weak self] result in
            guard let self, self.backgroundToken == token, !self.cancelled else { return }
            self.extensionInstall = nil
            self.reportFailedExtensions(result.failedNames, announcing: !self.dataFailed)
            ImportedExtensionFailures.clearFailed(result.installedIdentifiers)
            let added = result.installedIdentifiers.union(result.installingIdentifiers)
                .subtracting(ImportedExtensionFailures.failedIdentifiers)
            for item in items where added.contains(item.identifier) && OnboardingAdBlocker.isKnown(item.identifier) {
                let profiles = destinations[item.identifier] ?? []
                if let index = self.importedAdBlockers.firstIndex(where: { $0.identifier == item.identifier }) {
                    let known = self.importedAdBlockers[index].profileIDs ?? []
                    let merged = known + profiles.filter { !known.contains($0) }
                    self.importedAdBlockers[index].profileIDs = merged.isEmpty ? nil : merged
                } else {
                    self.importedAdBlockers.append(.init(identifier: item.identifier, displayName: item.displayName,
                        profileIDs: profiles.isEmpty ? nil : profiles))
                }
            }
            self.onChange?()
            self.finishBackground()
        }, backgroundFailures: { [weak self] names in
            ImportedExtensionFailures.recordFailed(items.filter { names.contains($0.displayName) }.map(\.identifier))
            self?.importedAdBlockers.removeAll { ImportedExtensionFailures.failedIdentifiers.contains($0.identifier) }
            if let self, !self.detached, self.isCurrent, self.extensionBatch == batch {
                self.reportFailedExtensions(names, announcing: !self.dataFailed); self.onChange?()
            } else { ImportedExtensionFailures.add(names) }
        })
        if extensionInstall == nil { reportFailedExtensions(items.map(\.displayName), announcing: !dataFailed); finishBackground() }
    }

    private func reportFailedExtensions(_ names: [String], announcing: Bool = true) {
        var seen = Set(warnings)
        let fresh = names.filter { seen.insert("\($0) couldn’t be added.").inserted }
        if announcing, !fresh.isEmpty { ImportedExtensionFailures.add(fresh) }
        warnings += fresh.map { "\($0) couldn’t be added." }
    }

    private var hasPendingBookmarks: Bool {
        bookmarkPages.contains { !$0.committed && !$0.discarded && !$0.skipped }
    }

    private func presentPasswordStageIfNeeded() -> Bool {
        guard !passwordStageOffered, let destination = passwordDestination,
              destination.isCurrent(in: store.state) else { return false }
        passwordStageOffered = true
        stage = onboarding && offersICloudPasswordChoice ? .passwordChoice : .safariPasswords
        if !keepsPasswordChoice { wantsICloudPasswords = stage == .passwordChoice }
        message = stage == .passwordChoice ? "Choose how to bring your Safari passwords with you." : passwordFileMessage
        return true
    }

    private var passwordFileMessage: String { "Import your exported \((passwordExport ?? .safari).browserName) passwords." }

    var canChoosePasswordMethod: Bool {
        stage == .passwordChoice && isCurrent && passwordDestination?.isCurrent(in: store.state) == true
    }

    func choosePasswordMethod(installExtension: Bool) {
        guard canChoosePasswordMethod else { return }
        wantsICloudPasswords = installExtension; onChange?()
    }

    func continuePasswordChoice() {
        guard canChoosePasswordMethod, let destination = passwordDestination else { return }
        if wantsICloudPasswords {
            acceptedICloudPasswordsDestination = destination
            passwordSession?.cancel(); passwordSession = nil; passwordRequestID = nil
            passwordDestination = nil; stage = .finished; startDeferredBackground()
            message = "Your import has finished."
        } else {
            stage = .safariPasswords; message = passwordFileMessage
        }
        onChange?()
    }

    var canImportPasswordFile: Bool {
        stage == .safariPasswords && isCurrent && !importingPasswords && !removingPasswordFile
            && passwordDestination?.isCurrent(in: store.state) == true
    }
    var canRemovePasswordFile: Bool {
        canImportPasswordFile && !passwordFileRemoved && passwordSession != nil
            && passwordResult?.canRemoveSourceFile == true
    }

    func importPasswordFile(_ url: URL) {
        guard canImportPasswordFile, let destination = passwordDestination, let window else { return }
        guard url.isFileURL, url.pathExtension.lowercased() == "csv" else {
            passwordError = (passwordExport ?? .safari).wrongFileMessage; onChange?(); return
        }
        passwordSession?.cancel(); passwordResult = nil; passwordFileRemoved = false; passwordError = nil
        passwordFileName = url.lastPathComponent; importingPasswords = true
        let token = UUID(); passwordRequestID = token; onChange?()
        passwordSession = PCNativeBrowserApplication.importPasswordFile(url,
            toProfilePath: store.independentEngineProfilePath(for: destination.profileID), in: window) { [weak self] result in
            if let self, self.detached { self.passwordSession?.cancel(); self.passwordSession = nil; self.startDeferredBackground() }
            guard let self, self.isCurrent, self.stage == .safariPasswords, self.passwordRequestID == token else { return }
            self.importingPasswords = false; self.passwordResult = result
            if !destination.isCurrent(in: self.store.state) {
                self.passwordSession?.cancel(); self.passwordSession = nil
                self.passwordError = "The destination closed. Confirmed passwords remain saved; the file has been kept."
            } else { self.passwordError = result.error?.localizedDescription }
            self.onChange?()
        }
        if passwordSession == nil {
            importingPasswords = false
            passwordError = "Another import may be active, or this file or destination is unavailable. Nothing was imported."
            onChange?()
        }
    }

    func stopPasswordImport() {
        guard stage == .safariPasswords, importingPasswords else { return }
        passwordSession?.cancel(); passwordError = "Stopping import. Already saved passwords will be kept."; onChange?()
    }

    func removePasswordFile() {
        guard canRemovePasswordFile, let session = passwordSession, let token = passwordRequestID else { return }
        removingPasswordFile = true; passwordError = nil; onChange?()
        session.removeSourceFile { [weak self] error in
            guard let self, self.isCurrent, self.stage == .safariPasswords, self.passwordRequestID == token else { return }
            self.removingPasswordFile = false; self.passwordError = error?.localizedDescription
            self.passwordFileRemoved = error == nil; self.onChange?()
        }
    }

    func continueAfterPasswords() {
        guard stage == .safariPasswords, isCurrent, !importingPasswords, !removingPasswordFile else { return }
        passwordSession?.cancel(); passwordSession = nil; passwordDestination = nil
        passwordRequestID = nil; startDeferredBackground()
        stage = hasPendingBookmarks ? .bookmarks : .finished
        message = hasPendingBookmarks ? "Choose the bookmarks to keep in your sidebar." : "Your import has finished."
        onChange?()
    }

    private func finishSourceFailure(_ failure: String) {
        queue = []; passwordDestination = nil; failed(failure); error = nil
        if !pendingExtensions.isEmpty || !backgroundProfiles.isEmpty { importNext(); return }
        stage = bookmarkPages.isEmpty ? .finished : .bookmarks
        message = bookmarkPages.isEmpty ? "Import stopped. Data already imported has been kept." :
            "Choose the bookmarks already read from your other profiles."
        onChange?()
    }

    private static func bookmarks(_ originals: [PCNativeImportedBookmark]) throws -> [BrowserImportBookmark] {
        var count = 0
        func convert(_ original: PCNativeImportedBookmark, depth: Int) throws -> BrowserImportBookmark {
            guard depth <= 128, count < 50_000 else { throw CocoaError(.fileReadCorruptFile) }
            count += 1
            return BrowserImportBookmark(id: original.identifier, title: original.title,
                url: original.url?.absoluteString,
                children: try original.children.map { try convert($0, depth: depth + 1) })
        }
        return try originals.map { try convert($0, depth: 0) }
    }

    func canShowBookmarks(_ page: BookmarkPage) -> Bool {
        !page.discarded && page.destination.isCurrent(in: store.state)
    }

    func canChooseBookmarks(_ page: BookmarkPage) -> Bool { (onboarding || !page.committed) && canShowBookmarks(page) }

    func toggleBookmark(page: Int, id: String, expansion: Bool) {
        guard stage == .bookmarks, isCurrent, bookmarkPages.indices.contains(page),
              expansion ? canShowBookmarks(bookmarkPages[page]) : canChooseBookmarks(bookmarkPages[page]) else { return }
        if expansion { bookmarkPages[page].selection.toggleExpanded(id) }
        else { bookmarkPages[page].selection.toggle(id) }
        onChange?()
    }

    func toggleBookmark(pageID: UUID, id: String?, expansion: Bool = false) {
        guard stage == .bookmarks, isCurrent,
              let index = bookmarkPages.firstIndex(where: { $0.id == pageID }),
              expansion ? canShowBookmarks(bookmarkPages[index]) : canChooseBookmarks(bookmarkPages[index]) else { return }
        if let id {
            if expansion { bookmarkPages[index].selection.toggleExpanded(id) }
            else { bookmarkPages[index].selection.toggle(id) }
        } else if !expansion { bookmarkPages[index].selection.toggleAll() }
        else { return }
        onChange?()
    }

    func commitBookmarks() {
        guard stage == .bookmarks, isCurrent else { return }
        do {
            var indices: [Int] = []
            for index in bookmarkPages.indices where (onboarding || !bookmarkPages[index].committed) && !bookmarkPages[index].discarded {
                let page = bookmarkPages[index]
                guard page.destination.isCurrent(in: store.state) else {
                    if !page.committed {
                        failed("\(page.sourceName): its destination Space was removed; these bookmarks were not added.")
                    }
                    bookmarkPages[index].discarded = true
                    continue
                }
                indices.append(index)
            }
            let placements = indices.isEmpty ? [] : try store.commitImportedBookmarks(indices.map { index in
                let page = bookmarkPages[index]
                return (page.selection.includedRoots, page.destination, page.placement)
            })
            for (index, placement) in zip(indices, placements) {
                bookmarkPages[index].committed = true; bookmarkPages[index].placement = placement
                var accepted = bookmarkPages[index].selection
                let spaceID = bookmarkPages[index].destination.spaceID
                for (sourceID, written) in placement.tabs where !accepted.selected.contains(sourceID)
                    && store.state.containsTab(written.id, where: { $0.archivedAt == nil && $0.spaceID == spaceID }) {
                    accepted.toggle(sourceID)
                }
                bookmarkPages[index].accepted = accepted; bookmarkPages[index].selection = accepted
            }
            if !(onboarding && presentPasswordStageIfNeeded()) {
                stage = .finished; message = "Your bookmarks are ready in Parc."; startDeferredBackground()
            }
            error = nil
        } catch { self.error = error.localizedDescription }
        onChange?()
    }

    var passwordImportCompleted: Bool { passwordResult?.outcome == .completed }

    var setupSkipTitle: String? {
        guard onboarding else { return nil }
        switch stage {
        case .safariAccess: return "Do this later"
        case .bookmarks, .passwordChoice: return "Skip for now"
        case .safariPasswords: return passwordImportCompleted ? nil : "Do this later"
        default: return nil
        }
    }

    var canSkipInSetup: Bool {
        guard setupSkipTitle != nil, isCurrent else { return false }
        switch stage {
        case .safariAccess: return !restarting && !continueAfterSafariRefresh
        case .safariPasswords: return !importingPasswords && !removingPasswordFile
        default: return true
        }
    }

    var canContinueSetupPasswords: Bool {
        stage == .safariPasswords && passwordImportCompleted && !importingPasswords && !removingPasswordFile
    }

    func skipInSetup() {
        guard canSkipInSetup else { return }
        switch stage {
        case .safariAccess:
            continueSafariWithoutRestarting()
        case .bookmarks:
            for index in bookmarkPages.indices {
                if let accepted = bookmarkPages[index].accepted { bookmarkPages[index].selection = accepted }
                else { bookmarkPages[index].skipped = true }
            }
            error = nil
            if !presentPasswordStageIfNeeded() {
                stage = .finished; message = "Your import has finished."; startDeferredBackground()
            }
            onChange?()
        case .passwordChoice, .safariPasswords:
            wantsICloudPasswords = false; acceptedICloudPasswordsDestination = nil
            passwordSession?.cancel(); passwordSession = nil; passwordDestination = nil; passwordRequestID = nil
            startDeferredBackground()
            stage = .finished; message = "Your import has finished."
            onChange?()
        default: break
        }
    }

    var canGoBackInSetup: Bool {
        guard onboarding, isCurrent else { return false }
        switch stage {
        case .safariAccess: return !restarting
        case .bookmarks, .passwordChoice: return true
        case .safariPasswords: return !importingPasswords && !removingPasswordFile
        default: return false
        }
    }

    func goBackInSetup() {
        guard canGoBackInSetup else { return }
        switch stage {
        case .safariAccess:
            restartWaitingToken = nil
            generation = UUID(); discovery?.cancel(); discovery = nil
            checkingSafariAccess = false; continueAfterSafariRefresh = false
            safariAccessError = nil; requiresSafariAccess = !safariAccessReady
            stage = .profiles; message = "Bring your browsing with you."
        case .bookmarks:
            park()
        case .safariPasswords where offersICloudPasswordChoice:
            keepsPasswordChoice = true; stage = .passwordChoice
        case .passwordChoice, .safariPasswords:
            keepsPasswordChoice = true
            if !bookmarkPages.isEmpty {
                passwordStageOffered = false
                for index in bookmarkPages.indices { bookmarkPages[index].skipped = false }
                stage = .bookmarks
            } else if passwordsWithoutData {
                returnToSafariAccess()
            } else {
                park()
            }
        default: return
        }
        error = nil; onChange?()
    }

    var hasStartedImportInSetup: Bool {
        if parkedStage != nil { return true }
        switch stage {
        case .importing, .passwordChoice, .safariPasswords, .bookmarks: return true
        default: return false
        }
    }

    var isRestingInSetup: Bool {
        parkedStage == nil && (stage == .bookmarks || stage == .passwordChoice || stage == .safariPasswords)
    }

    var setupBackReturnsToSource: Bool {
        switch stage {
        case .safariAccess: return false
        case .safariPasswords where offersICloudPasswordChoice: return false
        case .passwordChoice, .safariPasswords: return bookmarkPages.isEmpty
        default: return true
        }
    }

    @discardableResult
    func returnToSourceInSetup() -> Bool {
        guard onboarding, isCurrent, parkedStage == nil, !importingPasswords, !removingPasswordFile else { return false }
        switch stage {
        case .bookmarks: park()
        case .passwordChoice, .safariPasswords:
            keepsPasswordChoice = true
            if passwordsWithoutData && bookmarkPages.isEmpty { returnToSafariAccess() } else { park() }
        default: return false
        }
        error = nil; onChange?()
        return true
    }

    private func returnToSafariAccess() {
        passwordSession?.cancel(); passwordSession = nil; passwordRequestID = nil
        passwordStageOffered = false; passwordDestination = nil
        requiresSafariAccess = true; stage = .safariAccess
    }

    private func park() {
        parkedStage = stage; stage = .profiles; message = "Bring your browsing with you."
    }

    func stopImport() {
        guard stage == .importing else { return }
        queue = []; queuedDestinations = [:]; passwordDestination = nil; pendingExtensions = []; backgroundProfiles = []
        guard let session else {
            generation = UUID(); stage = .finished
            message = "Import stopped. Data already imported has been kept."; onChange?(); return
        }
        session.cancel(); message = "Stopping import…"; onChange?()
    }

    func cancel() {
        guard !cancelled else { return }
        if session != nil || !backgroundSessions.isEmpty { dataImported = true }
        cancelled = true; generation = UUID(); discovery?.cancel(); discovery = nil; restartWaitingToken = nil
        checkingSafariAccess = false; restarting = false; continueAfterSafariRefresh = false
        session?.cancel(); session = nil; activeDestination = nil; subscription = nil; queue = []; queuedDestinations = [:]
        backgroundSessions.values.forEach { $0.cancel() }
        backgroundSessions = [:]; backgroundPending = []; backgroundProfiles = []; backgroundDeferred = false
        extensionInstall?.cancel(); extensionInstall = nil; pendingExtensions = []
        onDetachedAdBlockers = nil; finishBackground()
        passwordSession?.cancel(); passwordSession = nil; passwordRequestID = nil
        importingPasswords = false; removingPasswordFile = false; passwordDestination = nil
        acceptedICloudPasswordsDestination = nil
        stage = .finished; message = "Import stopped. Data already imported has been kept."; onChange?()
    }
}

@MainActor
enum ImportedBrowserDataFailures {
    enum Outcome { case partial, failed }
    private(set) static var pending: Outcome?
    static var present: (() -> Void)?
    static func add(_ outcome: Outcome) {
        pending = pending.map { $0 == .failed && outcome == .failed ? .failed : .partial } ?? outcome
        present?()
    }
    static func take() -> Outcome? { defer { pending = nil }; return pending }
    static func restore(_ outcome: Outcome) { if pending == nil { pending = outcome } }
}

@MainActor
enum ImportedExtensionFailures {
    struct Names: Equatable {
        var added: [String] = []
        var removed: [String] = []
        var isEmpty: Bool { added.isEmpty && removed.isEmpty }
    }
    static let didFail = Notification.Name("ParcImportedExtensionsDidFail")
    private(set) static var pending = Names()
    private(set) static var failedIdentifiers = Set<String>()
    static var present: (() -> Void)?
    static func clearFailed(_ identifiers: Set<String>) { failedIdentifiers.subtract(identifiers) }
    static func recordFailed(_ identifiers: [String]) {
        failedIdentifiers.formUnion(identifiers)
        NotificationCenter.default.post(name: didFail, object: nil)
    }
    static func add(_ names: [String]) { record(Names(added: names)) }
    static func addRemovals(_ names: [String]) { record(Names(removed: names)) }
    static func take() -> Names { defer { pending = Names() }; return pending }
    static func restore(_ names: Names) {
        pending = Names(added: names.added + pending.added.filter { !names.added.contains($0) },
                        removed: names.removed + pending.removed.filter { !names.removed.contains($0) })
    }
    private static func record(_ names: Names) {
        for name in names.added where !pending.added.contains(name) { pending.added.append(name) }
        for name in names.removed where !pending.removed.contains(name) { pending.removed.append(name) }
        present?()
    }
}

enum ArcSidebarSnapshot {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Arc/StorableSidebar.json")
    }
    static var preferencesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/company.thebrowser.Browser.plist")
    }
    static let maximumSize = 64 * 1024 * 1024

    static func read(_ source: URL, preferences: URL) throws -> (ArcSidebarImport, [String: Any]) {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("ParcArcImport-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: directory) }
        let copy = directory.appendingPathComponent("StorableSidebar.json")
        func stamp() throws -> [FileAttributeKey: AnyHashable] {
            let attributes = try files.attributesOfItem(atPath: source.path)
            guard (attributes[.size] as? Int ?? .max) <= maximumSize else { throw CocoaError(.fileReadTooLarge) }
            return attributes.filter { [.size, .modificationDate, .systemFileNumber].contains($0.key) }
                .compactMapValues { $0 as? AnyHashable }
        }
        for attempt in 0..<5 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.2) }
            let before = try stamp()
            try? files.removeItem(at: copy)
            try files.copyItem(at: source, to: copy)
            guard try stamp() == before else { continue }
            let arc = try ArcSidebarImport(data: Data(contentsOf: copy))
            let settings = directory.appendingPathComponent("Preferences.plist")
            guard let size = (try? files.attributesOfItem(atPath: preferences.path))?[.size] as? Int, size <= maximumSize,
                  (try? files.copyItem(at: preferences, to: settings)) != nil,
                  let data = try? Data(contentsOf: settings),
                  let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return (arc, [:]) }
            return (arc, values)
        }
        throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "Arc kept changing its sidebar. Try again in a moment."])
    }
}

enum BrowserPasswordExport: Equatable {
    case safari, firefox, zen
    var browserName: String {
        switch self {
        case .safari: return "Safari"
        case .firefox: return "Firefox"
        case .zen: return "Zen"
        }
    }
    var wrongFileMessage: String {
        self == .safari ? "Choose the CSV file exported by Safari or Passwords."
            : "Choose the passwords.csv file exported by \(browserName)."
    }
}
