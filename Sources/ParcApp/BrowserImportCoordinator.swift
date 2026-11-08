import AppKit
import Combine

/// Bookmarks are read first; remaining data keeps importing after results close.
@MainActor
final class BrowserImportCoordinator {
    enum Stage { case sources, loading, profiles, safariAccess, destination, importing, passwordChoice, safariPasswords, bookmarks, finished }
    struct BookmarkPage {
        let id = UUID()
        let sourceName: String
        let destination: BrowserImportDestination
        var selection: BrowserImportSelection
        var committed = false
        var discarded = false
    }
    let store: BrowserStore
    let originalDestination: BrowserImportDestination
    private weak var window: NSWindow?
    private let ownerIsCurrent: () -> Bool
    private let onboarding: Bool
    private let supportsICloudPasswords: Bool
    var onChange: (() -> Void)?
    private(set) var stage: Stage = .loading
    private(set) var sources: [PCNativeImportSource] = []
    private(set) var source: PCNativeImportSource?
    private(set) var profiles: [PCNativeImportProfile] = []
    private(set) var selectedProfiles = Set<String>()
    private(set) var selectedExtensions: [String: Set<String>] = [:]
    private(set) var importedAdBlockers: [OnboardingDraft.ImportedAdBlocker] = []
    private(set) var bookmarkPages: [BookmarkPage] = []
    private(set) var message = "Finding your browsers…"
    private(set) var warnings: [String] = []
    private(set) var error: String?
    private(set) var destinationChoice = BrowserImportDestinationChoice()
    private(set) var profileTargets: [BrowserImportProfileTarget] = []
    private var skipExistingCookies = true
    private(set) var safariAccessReady = false
    private var requiresSafariAccess = false
    private(set) var checkingSafariAccess = false
    private(set) var restarting = false
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
    private(set) var passwordsOnly = false
    private var passwordStageOffered = false
    private var generation = UUID()
    private var discovery: PCNativeImportDiscovery?
    private var session: PCNativeImportSession?
    private static var detachedImports: [BrowserImportCoordinator] = []
    private var detached = false
    private var onDetachedAdBlockers: (([OnboardingDraft.ImportedAdBlocker]) -> Void)?
    private(set) var hasBackgroundWork = false
    private var backgroundProfiles: [(profile: PCNativeImportProfile, destination: BrowserImportDestination)] = []
    private var backgroundSessions: [UUID: PCNativeImportSession] = [:]
    private var backgroundPending = Set<UUID>()
    /// Each running background session's Parc Profile.
    private var backgroundTargets: [UUID: UUID] = [:]
    /// A chosen password file waits for its Profile's background data.
    private var waitingPasswordFile: (url: URL, destination: BrowserImportDestination, token: UUID)?
    private var startingBackground = false
    /// Background work outlives later choices on screen; only cancel stops it.
    private var backgroundToken = UUID()

    func detach(onAdBlockers: (([OnboardingDraft.ImportedAdBlocker]) -> Void)?) {
        guard hasBackgroundWork, !cancelled else { cancel(); return }
        if let waiting = waitingPasswordFile { passwordFileInBackground = waiting.token }
        else if importingPasswords, let token = passwordRequestID { passwordFileInBackground = token }
        onChange = nil
        onDetachedAdBlockers = onAdBlockers
        if !detached { detached = true; Self.detachedImports.append(self) }
    }

    private func reportBackgroundWarnings(_ lines: [String]) {
        warnings += lines
        if detached { ImportedBrowserDataFailures.add(lines) }
    }

    /// A password file left to import after Next is background work too.
    private var passwordFileInBackground: UUID?
    private var backgroundDataDone = false

    private func finishBackground() {
        backgroundDataDone = true
        guard passwordFileInBackground == nil else { return }
        hasBackgroundWork = false
        if detached {
            onDetachedAdBlockers?(importedAdBlockers)
            onDetachedAdBlockers = nil
            Self.detachedImports.removeAll { $0 === self }
        }
    }
    private var activeDestination: BrowserImportDestination?
    /// Each profile's extensions install after the last profile's data.
    private var pendingExtensions: [(profile: PCNativeImportProfile, destination: BrowserImportDestination, ids: Set<String>)] = []
    private var extensionInstall: PCNativeImportSession?
    private var extensionBatch: UUID?
    private let arcSidebarURL: URL
    private let arcPreferencesURL: URL
    private var queue: [PCNativeImportProfile] = []
    /// Chosen profiles' known Parc destinations; any other gets a Parc Profile
    /// of its name when its turn comes, never one it might not use.
    private var queuedDestinations: [String: BrowserImportDestination] = [:]
    private var usedProfiles = Set<UUID>()
    private var completed = 0
    private var cancelled = false
    private var subscription: AnyCancellable?

    init(store: BrowserStore, destination: BrowserImportDestination, window: NSWindow, onboarding: Bool = false,
         supportsICloudPasswords: Bool = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)),
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
                    // Let the accepted native session drain and complete; its
                    // lost destination must not erase earlier bookmark results.
                    self.queue = []
                    self.session?.cancel()
                    self.message = "Stopping import because its destination was removed…"
                    self.onChange?()
                } else if self.passwordDestination.map({ !$0.isCurrent(in: self.store.state) }) == true {
                    self.passwordSession?.cancel()
                    self.passwordError = "The selected destination Profile is no longer available."
                    self.onChange?()
                } else if self.stage == .destination {
                    self.refreshDestinations()
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
    static let arcBundleIdentifier = "company.thebrowser.Browser"
    static func isArc(_ source: PCNativeImportSource) -> Bool { source.identifier == arcBundleIdentifier }
    var isArcSource: Bool { source.map(Self.isArc) == true }

    func discover(resumingSourceBundleID: String? = nil) {
        guard isCurrent else { return }
        guard !hasBackgroundWork, stage != .importing && stage != .bookmarks && stage != .passwordChoice && stage != .safariPasswords && !restarting else { return }
        discovery?.cancel(); generation = UUID(); let token = generation
        checkingSafariAccess = false; continueAfterSafariRefresh = false; safariAccessError = nil
        source = nil; sources = []; profiles = []; selectedProfiles = []; selectedExtensions = [:]
        passwordsOnly = false; passwordDestination = nil; passwordStageOffered = false
        wantsICloudPasswords = false; acceptedICloudPasswordsDestination = nil
        safariAccessReady = false; requiresSafariAccess = false
        destinationChoice = BrowserImportDestinationChoice(); profileTargets = []
        extensionBatch = nil
        stage = .loading; message = "Finding your browsers…"; error = nil; onChange?()
        discovery = PCNativeBrowserApplication.availableImportSources { [weak self] sources in
            guard let self, self.isCurrent, self.generation == token else { return }
            let priorities = [Self.arcBundleIdentifier: 0, "com.google.Chrome": 1]
            self.discovery = nil
            self.sources = sources.enumerated().sorted {
                (priorities[$0.element.identifier] ?? 2, $0.offset) < (priorities[$1.element.identifier] ?? 2, $1.offset)
            }.map(\.element)
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

    /// BrowserSelection keeps profile choices below the selected browser, in
    /// setup and the import window alike. Discovery may change while this
    /// screen stays visible; old native leases must not win.
    var isChoosingSourceInline: Bool {
        stage == .sources || stage == .profiles || (stage == .loading && source != nil)
    }

    func selectSourceInline(_ source: PCNativeImportSource) {
        guard isChoosingSourceInline, isCurrent, sources.contains(where: { $0 === source }) else { return }
        if self.source === source && (stage == .loading || (stage == .profiles && error == nil)) { return }
        clearSourceInline(notify: false)
        self.source = source
        loadProfiles(inline: true)
    }

    func clearSourceInline() { clearSourceInline(notify: true) }

    private func clearSourceInline(notify: Bool) {
        guard isChoosingSourceInline, isCurrent else { return }
        generation = UUID(); discovery?.cancel(); discovery = nil
        source = nil; profiles = []; selectedProfiles = []; selectedExtensions = [:]
        requiresSafariAccess = false; safariAccessReady = false
        warnings = []; error = nil; stage = .sources
        message = "Bring your browsing with you."
        if notify { onChange?() }
    }

    var canContinueSourceInline: Bool {
        stage == .profiles && isCurrent && (requiresSafariAccess || canChooseDestination)
    }

    func continueSourceInline() {
        guard canContinueSourceInline else { return }
        if requiresSafariAccess {
            stage = .safariAccess; onChange?()
        } else {
            // The browser's main profile goes into the Parc Profile import was
            // opened from; there is no destination to choose.
            startInOriginalDestination()
        }
    }

    /// An inline choice waits for Next before Safari's access step.
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
        profiles = result.profiles; warnings = result.constraints
        // Every readable profile comes along unless the user unticks it.
        // An unreadable one stays chosen so Full Disk Access can follow.
        let readable = result.profiles.filter { $0.supportedCategories.rawValue != 0 }
        selectedProfiles = Set((readable.isEmpty ? Array(result.profiles.prefix(1)) : readable).map(\.identifier))
        // Every extension found comes along unless the user unticks it.
        selectedExtensions = Dictionary(result.profiles.map { ($0.identifier, Set($0.extensions.map(\.identifier))) },
                                        uniquingKeysWith: { $0.union($1) })
        error = result.error?.localizedDescription
        message = result.profiles.isEmpty ? "No readable profiles were found." : "Choose the profile to bring into Parc."
        // This describes selected-source readability, never a fabricated TCC
        // grant. Missing history or an incomplete result cannot enable Restart.
        safariAccessReady = result.error == nil && result.access == .complete && result.profiles.contains {
            $0.access == .complete && $0.supportedCategories.contains(.history)
        }
    }

    func refreshSafariAccess() {
        guard stage == .safariAccess, !checkingSafariAccess, !restarting,
              isCurrent, let source else { return }
        checkingSafariAccess = true; generation = UUID(); let token = generation
        onChange?()
        discovery = PCNativeBrowserApplication.loadImportSourceProfiles(source) { [weak self] result in
            guard let self, self.isCurrent, self.generation == token,
                  self.stage == .safariAccess, self.source === source, !self.restarting else { return }
            self.discovery = nil; self.checkingSafariAccess = false; self.applyProfiles(result)
            if self.continueAfterSafariRefresh {
                self.continueAfterSafariRefresh = false; self.requiresSafariAccess = false; self.stage = .profiles
            }
            self.onChange?()
        }
    }

    func continueSafariWithoutRestarting() {
        guard stage == .safariAccess, !restarting, isCurrent else { return }
        continueAfterSafariRefresh = true; safariAccessError = nil
        refreshSafariAccess()
    }

    func beginSafariRestart() -> Bool {
        guard stage == .safariAccess, isCurrent, safariAccessReady, !checkingSafariAccess,
              !restarting, source != nil else { return false }
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

    func selectProfile(_ id: String) {
        guard stage == .profiles, isCurrent,
              profiles.contains(where: { $0.identifier == id && $0.supportedCategories.rawValue != 0 }) else { return }
        if selectedProfiles.remove(id) == nil { selectedProfiles.insert(id) }
        onChange?()
    }

    var canChooseDestination: Bool {
        isCurrent && profiles.contains {
            guard selectedProfiles.contains($0.identifier) else { return false }
            var categories = $0.supportedCategories
            if (selectedExtensions[$0.identifier] ?? []).isEmpty { categories.remove(.extensions) }
            return categories.rawValue != 0
        }
    }
    var canStart: Bool {
        stage == .destination && isCurrent && (passwordsOnly || canChooseDestination) && destinationChoice.canSubmit(in: store.state)
    }

    var canChoosePasswordDestination: Bool {
        stage == .profiles && isCurrent && source.map(Self.isSafari) == true
    }

    /// An explicitly exported file does not require access to Safari's history
    /// store. It still requires the same explicit durable destination choice.
    func choosePasswordDestination() {
        guard canChoosePasswordDestination else { return }
        passwordsOnly = true; prepareDestinationChoice()
    }

    func chooseDestination() {
        guard stage == .profiles, canChooseDestination else { return }
        passwordsOnly = false; prepareDestinationChoice()
    }

    /// Both presentations import into the Space and Profile they were opened
    /// from: setup's first one, or the window's. Import must not follow a later
    /// selection elsewhere. Source discovery alone never submits data.
    func startInOriginalDestination(passwordsOnly: Bool = false) {
        guard stage == .profiles, isCurrent,
              passwordsOnly ? canChoosePasswordDestination : canChooseDestination else { return }
        self.passwordsOnly = passwordsOnly
        let target = BrowserImportProfileTarget(profileID: originalDestination.profileID,
                                                spaceID: originalDestination.spaceID)
        guard target.isCurrent(in: store.state) else { return }
        profileTargets = [target]
        destinationChoice = BrowserImportDestinationChoice()
        destinationChoice.select(.existing(target))
        stage = .destination
        start()
    }

    private func prepareDestinationChoice() {
        profileTargets = BrowserImportProfileTarget.choices(in: store.state, original: originalDestination)
        if case .existing(let target) = destinationChoice.option, !profileTargets.contains(target) {
            destinationChoice.invalidate()
        }
        destinationChoice.appeared(); stage = .destination; error = nil; onChange?()
    }

    func selectDestination(_ option: BrowserImportDestinationChoice.Option) {
        guard stage == .destination, isCurrent else { return }
        if case .existing(let target) = option, !profileTargets.contains(target) || !target.isCurrent(in: store.state) { return }
        destinationChoice.select(option); error = nil; onChange?()
    }

    func setNewProfileName(_ name: String) {
        guard stage == .destination, isCurrent, destinationChoice.isNew else { return }
        destinationChoice.newProfileName = name
        // The native field keeps its editor, marked text and selection.
    }

    private func refreshDestinations() {
        let targets = BrowserImportProfileTarget.choices(in: store.state, original: originalDestination)
        if case .existing(let target) = destinationChoice.option, !target.isCurrent(in: store.state) {
            destinationChoice.invalidate(); error = "That destination is no longer available. Choose another Profile."
        }
        profileTargets = targets; onChange?()
    }

    func toggleExtension(_ id: String, profileID: String) {
        guard stage == .profiles, isCurrent, selectedProfiles.contains(profileID),
              let profile = profiles.first(where: { $0.identifier == profileID }),
              profile.extensions.contains(where: { $0.identifier == id }) else { return }
        if !(selectedExtensions[profileID, default: []].insert(id).inserted) {
            selectedExtensions[profileID]?.remove(id)
        }
        onChange?()
    }

    /// Setup lists each extension once; its choice holds in every profile.
    func toggleExtension(_ id: String) {
        guard stage == .profiles, isCurrent else { return }
        let owners = profiles.filter { $0.extensions.contains { $0.identifier == id } }
        guard !owners.isEmpty else { return }
        let selected = owners.allSatisfy { selectedExtensions[$0.identifier]?.contains(id) == true }
        for owner in owners {
            if selected { selectedExtensions[owner.identifier]?.remove(id) }
            else { selectedExtensions[owner.identifier, default: []].insert(id) }
        }
        onChange?()
    }

    /// The browser's default profile goes to the chosen destination; each other
    /// chosen profile goes to a Parc Profile of its own name.
    private var chosenProfiles: [PCNativeImportProfile] {
        let chosen = profiles.filter { profile in
            guard selectedProfiles.contains(profile.identifier) else { return false }
            var categories = profile.supportedCategories
            if (selectedExtensions[profile.identifier] ?? []).isEmpty { categories.remove(.extensions) }
            return categories.rawValue != 0
        }
        guard let primary = chosen.first(where: { $0.directoryName == "Default" }) ?? chosen.first else { return [] }
        return [primary] + chosen.filter { $0 !== primary }
    }

    func start() {
        guard canStart else { return }
        skipExistingCookies = !destinationChoice.replaceExistingCookies
        let chosen = chosenProfiles
        if isArcSource, !passwordsOnly, !chosen.isEmpty { startArc(chosen); return }
        // Resolve/save once at the actual Import action, before native context
        // admission. Radio selection and name editing never create a Profile.
        do { activeDestination = try store.prepareImportDestination(destinationChoice, basedOn: originalDestination) }
        catch { stage = .profiles; self.error = error.localizedDescription; onChange?(); return }
        beginImport()
        passwordDestination = source.map(Self.isSafari) == true ? activeDestination : nil
        if passwordsOnly { activeDestination = nil; importNext(); return }
        queueProfiles(chosen, primaryDestination: activeDestination)
        importNext()
    }

    private func beginImport() {
        stage = .importing; completed = 0; bookmarkPages = []; importedAdBlockers = []; error = nil
        pendingExtensions = []; backgroundProfiles = []; extensionBatch = nil; passwordStageOffered = false
        queue = []; queuedDestinations = [:]; usedProfiles = []
        generation = UUID()
    }

    /// `known` destinations win and the first profile takes the chosen one;
    /// the rest get theirs as they import.
    private func queueProfiles(_ chosen: [PCNativeImportProfile], primaryDestination: BrowserImportDestination?,
                               known: [String: BrowserImportDestination] = [:]) {
        for (index, profile) in chosen.enumerated() {
            guard let destination = known[profile.identifier] ?? (index == 0 ? primaryDestination : nil) else { continue }
            queuedDestinations[profile.identifier] = destination; usedProfiles.insert(destination.profileID)
        }
        queue = chosen
    }

    /// A chosen profile without a known destination reuses an unused Parc
    /// Profile of its name, else gets a new one.
    private func destination(named name: String, excluding used: Set<UUID>) throws -> BrowserImportDestination {
        let state = store.state
        if let profile = state.profiles.first(where: { profile in !used.contains(profile.id)
               && !state.profileRemovals.contains { $0.profileID == profile.id }
               && profile.name.caseInsensitiveCompare(name) == .orderedSame }),
           let target = BrowserImportProfileTarget.choices(in: state, original: originalDestination).first(where: { $0.profileID == profile.id }) {
            var choice = BrowserImportDestinationChoice(); choice.select(.existing(target))
            return try store.prepareImportDestination(choice, basedOn: originalDestination)
        }
        return try store.createImportDestination(name: name, basedOn: originalDestination)
    }

    ///
    /// Profile first; its browser data then imports there as any browser's does.
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
                    standardProfileID: originalDestination.profileID, primary: keyed[0].key, into: destinationChoice)
                var known: [String: BrowserImportDestination] = [:]
                for item in keyed { known[item.profile.identifier] = destinations[item.key] }
                // A chosen Space stays the destination, as it is for any browser.
                if case .existing(let target) = destinationChoice.option, let spaceID = target.spaceID,
                   target.isCurrent(in: store.state) {
                    known[keyed[0].profile.identifier] = BrowserImportDestination(spaceID: spaceID, profileID: target.profileID)
                }
                queueProfiles(chosen, primaryDestination: nil, known: known)
            } else {
                //
                queueProfiles(chosen, primaryDestination: try store.prepareImportDestination(destinationChoice, basedOn: originalDestination))
            }
        } catch {
            // As Chrome's Import does, stay on the destination with the reason.
            // Back on the browser cards with the reason, as Chrome's start does.
            queue = []; queuedDestinations = [:]; stage = .profiles; self.error = error.localizedDescription; onChange?(); return
        }
        importNext()
    }

    private func importNext() {
        guard isCurrent, let window else { cancel(); return }
        guard !queue.isEmpty else {
            startBackground(in: window)
            // Setup accepts bookmarks before offering the separate Safari
            // password step. The menu keeps its existing import sequence.
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
                activeDestination = nil; warnings.append("\(profile.displayName) could not be imported.")
                completed += 1; importNext(); return
            }
        }
        var categories = profile.supportedCategories
        categories.remove(.extensions)
        let extensions = Set(profile.extensions.map(\.identifier)).intersection(selectedExtensions[profile.identifier] ?? [])
        guard categories.rawValue != 0 || !extensions.isEmpty else {
            warnings.append("No data was selected for \(profile.displayName).")
            activeDestination = nil; completed += 1; importNext(); return
        }
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
                self.warnings += result.warnings
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
                } catch { self.warnings.append("Bookmarks: \(error.localizedDescription)") }
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
        hasBackgroundWork = true; startingBackground = true; backgroundDataDone = false
        backgroundToken = UUID(); let token = backgroundToken
        for item in pending {
            var categories = item.profile.supportedCategories
            categories.remove(.bookmarks); categories.remove(.extensions)
            guard categories.rawValue != 0 else { continue }
            guard item.destination.isCurrent(in: store.state) else {
                reportBackgroundWarnings(["\(item.profile.displayName): its destination was removed, so this import stopped."])
                continue
            }
            let id = UUID()
            backgroundPending.insert(id); backgroundTargets[id] = item.destination.profileID
            let lease = PCNativeBrowserApplication.importBrowserData(from: item.profile,
                toProfilePath: store.independentEngineProfilePath(for: item.destination.profileID), in: window,
                categories: categories, skipExistingCookies: skipExistingCookies,
                progress: { _ in }, completion: { [weak self] result in
                    guard let self, self.backgroundToken == token, !self.cancelled,
                          self.backgroundPending.remove(id) != nil else { return }
                    self.backgroundSessions[id] = nil; self.backgroundTargets[id] = nil
                    self.startWaitingPasswordFile()
                    self.reportBackgroundWarnings(result.warnings)
                    if let error = result.error { self.reportBackgroundWarnings(["\(item.profile.displayName): \(error.localizedDescription)"]) }
                    else if result.outcome == .failed { self.reportBackgroundWarnings(["\(item.profile.displayName) could not be imported."]) }
                    self.onChange?()
                    self.backgroundDataFinished()
                })
            if backgroundPending.contains(id) {
                if let lease { backgroundSessions[id] = lease }
                else {
                    backgroundPending.remove(id); backgroundTargets[id] = nil
                    reportBackgroundWarnings(["Parc could not begin the import from \(item.profile.displayName)."])
                }
            }
        }
        startingBackground = false
        backgroundDataFinished()
    }

    private func backgroundDataFinished() {
        guard hasBackgroundWork, !startingBackground, backgroundPending.isEmpty else { return }
        installExtensions()
    }

    ///
    private func installExtensions() {
        let pending = pendingExtensions; pendingExtensions = []
        var requests: [PCNativeImportExtensionRequest] = [], requested: [String: Set<String>] = [:]
        var items: [PCNativeImportExtension] = []
        for item in pending {
            let chosen = item.profile.extensions.filter { item.ids.contains($0.identifier) }
            guard item.destination.isCurrent(in: store.state) else { reportFailedExtensions(chosen.map(\.displayName)); continue }
            let path = store.independentEngineProfilePath(for: item.destination.profileID)
            let ids = item.ids.subtracting(requested[path] ?? [])
            guard !ids.isEmpty else { continue }
            requested[path, default: []].formUnion(ids)
            requests.append(PCNativeImportExtensionRequest(source: item.profile, profilePath: path, extensionIDs: ids))
            items += chosen.filter { ids.contains($0.identifier) }
        }
        guard !requests.isEmpty else { finishBackground(); return }
        let token = backgroundToken, batch = UUID()
        extensionBatch = batch

        extensionInstall = PCNativeBrowserApplication.installImportedExtensions(requests, completion: { [weak self] result in
            // Always ends the background phase, so a detached import is released.
            guard let self, self.backgroundToken == token, !self.cancelled else { return }
            self.extensionInstall = nil
            self.reportFailedExtensions(result.failedNames)
            ImportedExtensionFailures.clearFailed(result.installedIdentifiers)
            let added = result.installedIdentifiers.union(result.installingIdentifiers)
                .subtracting(ImportedExtensionFailures.failedIdentifiers)
            for item in items where added.contains(item.identifier) && OnboardingAdBlocker.isKnown(item.identifier)
                && !self.importedAdBlockers.contains(where: { $0.identifier == item.identifier }) {
                self.importedAdBlockers.append(.init(identifier: item.identifier, displayName: item.displayName))
            }
            self.onChange?()
            self.finishBackground()
        }, backgroundFailures: { [weak self] names in
            ImportedExtensionFailures.recordFailed(items.filter { names.contains($0.displayName) }.map(\.identifier))
            self?.importedAdBlockers.removeAll { ImportedExtensionFailures.failedIdentifiers.contains($0.identifier) }
            // Results still on screen list it; otherwise a browser window does.
            if let self, !self.detached, self.isCurrent, self.extensionBatch == batch {
                self.reportFailedExtensions(names); self.onChange?()
            } else { ImportedExtensionFailures.add(names) }
        })
        if extensionInstall == nil { reportFailedExtensions(items.map(\.displayName)); finishBackground() }
    }

    private func reportFailedExtensions(_ names: [String]) {
        if detached { ImportedExtensionFailures.add(names) }
        for name in names {
            let line = "\(name) couldn’t be added."
            if !warnings.contains(line) { warnings.append(line) }
        }
    }

    private var hasPendingBookmarks: Bool {
        bookmarkPages.contains { !$0.committed && !$0.discarded }
    }

    /// Changes presentation only. Exported credentials are never read until an
    /// explicit file choice; the captured destination and native lease remain
    /// authoritative across both import presentations.
    private func presentPasswordStageIfNeeded() -> Bool {
        guard !passwordStageOffered, let destination = passwordDestination,
              destination.isCurrent(in: store.state) else { return false }
        passwordStageOffered = true
        stage = onboarding && supportsICloudPasswords ? .passwordChoice : .safariPasswords
        // Original setup initializes the recommendation when the included
        // Safari extension-choice path is enabled. Next still owns acceptance.
        wantsICloudPasswords = stage == .passwordChoice
        message = stage == .passwordChoice ? "Choose how to bring your Safari passwords with you." : "Import your exported Safari passwords."
        return true
    }

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
            // Transfer only an accepted pending choice to the setup owner.
            // The installation belongs to finishing setup, never row selection.
            acceptedICloudPasswordsDestination = destination
            passwordDestination = nil; stage = .finished
            message = "Your import has finished."
        } else {
            stage = .safariPasswords; message = "Import your exported Safari passwords."
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
            passwordError = "Choose the CSV file exported by Safari or Passwords."; onChange?(); return
        }
        passwordSession?.cancel(); passwordResult = nil; passwordFileRemoved = false; passwordError = nil
        passwordFileName = url.lastPathComponent; importingPasswords = true
        let token = UUID(); passwordRequestID = token; onChange?()
        // Native import admits one session per Profile; history may still be running there.
        if backgroundTargets.values.contains(destination.profileID) {
            waitingPasswordFile = (url, destination, token); return
        }
        beginPasswordFile(url, destination: destination, token: token, in: window)
    }

    /// Next moves on; the file then imports once that Profile's data is in.
    var passwordFileWaiting: Bool { waitingPasswordFile != nil }

    private func startWaitingPasswordFile() {
        guard let waiting = waitingPasswordFile, !backgroundTargets.values.contains(waiting.destination.profileID) else { return }
        waitingPasswordFile = nil
        // A closed import window leaves the import running; any visible window hosts the file.
        guard waiting.destination.isCurrent(in: store.state),
              let host = (window?.isVisible == true ? window : nil) ?? NSApp.windows.first(where: { $0.isVisible }) ?? window else {
            importingPasswords = false
            passwordError = "The destination closed. Nothing was imported from this file."
            if passwordFileInBackground == waiting.token {
                ImportedBrowserDataFailures.add(["Passwords from \(waiting.url.lastPathComponent) weren’t imported."])
            }
            finishPasswordFileInBackground(waiting.token)
            onChange?(); return
        }
        beginPasswordFile(waiting.url, destination: waiting.destination, token: waiting.token, in: host)
    }

    private func finishPasswordFileInBackground(_ token: UUID) {
        guard passwordFileInBackground == token else { return }
        passwordFileInBackground = nil
        if backgroundDataDone { finishBackground() }
    }

    private func beginPasswordFile(_ url: URL, destination: BrowserImportDestination, token: UUID, in window: NSWindow) {
        passwordSession = PCNativeBrowserApplication.importPasswordFile(url,
            toProfilePath: store.independentEngineProfilePath(for: destination.profileID), in: window) { [weak self] result in
            guard let self else { return }
            if self.passwordFileInBackground == token {
                // Setup moved on or the window closed; a browser window reports failures.
                if result.error != nil { ImportedBrowserDataFailures.add(["Passwords from \(url.lastPathComponent) weren’t imported."]) }
                if self.passwordRequestID != token { self.passwordSession = nil }
                self.finishPasswordFileInBackground(token)
            }
            guard self.isCurrent, self.stage == .safariPasswords, self.passwordRequestID == token else { return }
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
            if passwordFileInBackground == token { ImportedBrowserDataFailures.add(["Passwords from \(url.lastPathComponent) weren’t imported."]) }
            finishPasswordFileInBackground(token)
            onChange?()
        }
    }

    func stopPasswordImport() {
        guard stage == .safariPasswords, importingPasswords else { return }
        if waitingPasswordFile != nil {
            waitingPasswordFile = nil; passwordRequestID = nil; importingPasswords = false
            passwordError = "Nothing was imported from this file."; onChange?(); return
        }
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
        guard stage == .safariPasswords, isCurrent, !importingPasswords || passwordFileWaiting, !removingPasswordFile else { return }
        if let waiting = waitingPasswordFile { passwordFileInBackground = waiting.token } else { passwordSession?.cancel(); passwordSession = nil }
        importingPasswords = false; passwordDestination = nil
        passwordRequestID = nil
        stage = hasPendingBookmarks ? .bookmarks : .finished
        message = hasPendingBookmarks ? "Choose the bookmarks to keep in your sidebar." : "Your import has finished."
        onChange?()
    }

    private func finishSourceFailure(_ failure: String) {
        queue = []; passwordDestination = nil; warnings.append(failure); error = nil
        // Profiles that already imported still get their extensions.
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

    func toggleBookmark(page: Int, id: String, expansion: Bool) {
        guard stage == .bookmarks, isCurrent, bookmarkPages.indices.contains(page), !bookmarkPages[page].committed,
              !bookmarkPages[page].discarded, bookmarkPages[page].destination.isCurrent(in: store.state) else { return }
        if expansion { bookmarkPages[page].selection.toggleExpanded(id) }
        else { bookmarkPages[page].selection.toggle(id) }
        onChange?()
    }

    /// SwiftUI actions keep their exact result-page identity through renders.
    /// They cannot address a later result merely because it reuses an index.
    func toggleBookmark(pageID: UUID, id: String?, expansion: Bool = false) {
        guard stage == .bookmarks, isCurrent,
              let index = bookmarkPages.firstIndex(where: { $0.id == pageID }),
              !bookmarkPages[index].committed, !bookmarkPages[index].discarded,
              bookmarkPages[index].destination.isCurrent(in: store.state) else { return }
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
            for index in bookmarkPages.indices where !bookmarkPages[index].committed && !bookmarkPages[index].discarded {
                let page = bookmarkPages[index]
                guard page.destination.isCurrent(in: store.state) else {
                    warnings.append("\(page.sourceName): its destination Profile or Space was removed; these bookmarks were not added.")
                    bookmarkPages[index].discarded = true
                    continue
                }
                try store.commitImportedBookmarks(page.selection.includedRoots, destination: page.destination)
                bookmarkPages[index].committed = true
            }
            if !(onboarding && presentPasswordStageIfNeeded()) {
                stage = .finished; message = "Your bookmarks are ready in Parc."
            }
            error = nil
        } catch { self.error = error.localizedDescription }
        onChange?()
    }

    func stopImport() {
        guard stage == .importing else { return }
        queue = []; queuedDestinations = [:]; passwordDestination = nil; pendingExtensions = []; backgroundProfiles = []
        guard let session else {
            //
            generation = UUID(); stage = .finished
            message = "Import stopped. Data already imported has been kept."; onChange?(); return
        }
        session.cancel(); message = "Stopping import…"; onChange?()
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true; generation = UUID(); discovery?.cancel(); discovery = nil
        checkingSafariAccess = false; restarting = false; continueAfterSafariRefresh = false
        session?.cancel(); session = nil; activeDestination = nil; subscription = nil; queue = []; queuedDestinations = [:]
        backgroundSessions.values.forEach { $0.cancel() }
        backgroundSessions = [:]; backgroundPending = []; backgroundProfiles = []; backgroundTargets = [:]
        waitingPasswordFile = nil
        extensionInstall?.cancel(); extensionInstall = nil; pendingExtensions = []
        onDetachedAdBlockers = nil; passwordFileInBackground = nil; finishBackground()
        passwordSession?.cancel(); passwordSession = nil; passwordRequestID = nil
        importingPasswords = false; removingPasswordFile = false; passwordDestination = nil
        acceptedICloudPasswordsDestination = nil
        stage = .finished; message = "Import stopped. Data already imported has been kept."; onChange?()
    }
}

/// Data failures outlive a detached import so a browser window can report them.
@MainActor
enum ImportedBrowserDataFailures {
    static let didFail = Notification.Name("ParcImportedBrowserDataDidFail")
    private(set) static var pending: [String] = []
    static func add(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        for line in lines where !pending.contains(line) { pending.append(line) }
        NotificationCenter.default.post(name: didFail, object: nil)
    }
    static func take() -> [String] { defer { pending = [] }; return pending }
}

/// Imported extensions that failed in the background after their import's
/// results closed, waiting for a browser window to say so.
@MainActor
enum ImportedExtensionFailures {
    static let didFail = Notification.Name("ParcImportedExtensionsDidFail")
    private(set) static var pending: [String] = []
    /// Setup's ad-blocker step leaves these out.
    private(set) static var failedIdentifiers = Set<String>()
    static var present: (() -> Void)?
    static func clearFailed(_ identifiers: Set<String>) { failedIdentifiers.subtract(identifiers) }
    static func recordFailed(_ identifiers: [String]) {
        failedIdentifiers.formUnion(identifiers)
        NotificationCenter.default.post(name: didFail, object: nil)
    }
    static func add(_ names: [String]) {
        for name in names where !pending.contains(name) { pending.append(name) }
        present?()
    }
    static func take() -> [String] { defer { pending = [] }; return pending }
    /// Kept for the next window when this one couldn't show them.
    static func restore(_ names: [String]) { pending = names + pending.filter { !names.contains($0) } }
}

///
///
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

    ///
    /// each Parc Profile keeps its own archive setting.
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
