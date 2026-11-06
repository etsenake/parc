import AppKit
import Combine

/// The chooser owns one native import at a time. Each continuation is tied to
/// the original window, source profile and durable local destination.
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
    private var activeDestination: BrowserImportDestination?
    private var queue: [PCNativeImportProfile] = []
    private var completed = 0
    private var cancelled = false
    private var subscription: AnyCancellable?

    init(store: BrowserStore, destination: BrowserImportDestination, window: NSWindow, onboarding: Bool = false,
         supportsICloudPasswords: Bool = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)),
         ownerIsCurrent: @escaping () -> Bool) {
        self.store = store; originalDestination = destination; self.window = window
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
                    self.queue = []; self.session?.cancel()
                    self.message = "Stopping import because its destination was removed…"; self.onChange?()
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
        !cancelled && window != nil && ownerIsCurrent() && !store.isEphemeral
            && originalDestination.isCurrent(in: store.state)
    }

    static func isSafari(_ source: PCNativeImportSource) -> Bool {
        Bundle(url: source.appURL)?.bundleIdentifier == "com.apple.Safari"
    }

    func discover(resumingSourceBundleID: String? = nil) {
        guard isCurrent else { return }
        guard stage != .importing && stage != .bookmarks && stage != .passwordChoice && stage != .safariPasswords && !restarting else { return }
        discovery?.cancel(); generation = UUID(); let token = generation
        checkingSafariAccess = false; continueAfterSafariRefresh = false; safariAccessError = nil
        source = nil; sources = []; profiles = []; selectedProfiles = []; selectedExtensions = [:]
        passwordsOnly = false; passwordDestination = nil; passwordStageOffered = false
        wantsICloudPasswords = false; acceptedICloudPasswordsDestination = nil
        safariAccessReady = false; requiresSafariAccess = false
        destinationChoice = BrowserImportDestinationChoice(); profileTargets = []
        stage = .loading; message = "Finding your browsers…"; error = nil; onChange?()
        discovery = PCNativeBrowserApplication.availableImportSources { [weak self] sources in
            guard let self, self.isCurrent, self.generation == token else { return }
            self.discovery = nil; self.sources = sources; self.stage = .sources
            self.message = sources.isEmpty ? "No supported browsers were found." : "Bring your browsing with you."
            if let bundleID = resumingSourceBundleID {
                guard let source = sources.first(where: {
                    Bundle(url: $0.appURL)?.bundleIdentifier == bundleID
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

    /// Setup keeps profile choices below the selected browser. Discovery may
    /// change while this screen stays visible; old native leases must not win.
    var isChoosingOnboardingSource: Bool {
        onboarding && (stage == .sources || stage == .profiles || (stage == .loading && source != nil))
    }

    func selectOnboardingSource(_ source: PCNativeImportSource) {
        guard isChoosingOnboardingSource, isCurrent, sources.contains(where: { $0 === source }) else { return }
        if self.source === source && (stage == .loading || (stage == .profiles && error == nil)) { return }
        clearOnboardingSource(notify: false)
        self.source = source
        loadProfiles()
    }

    func clearOnboardingSource() { clearOnboardingSource(notify: true) }

    private func clearOnboardingSource(notify: Bool) {
        guard isChoosingOnboardingSource, isCurrent else { return }
        generation = UUID(); discovery?.cancel(); discovery = nil
        source = nil; profiles = []; selectedProfiles = []; selectedExtensions = [:]
        requiresSafariAccess = false; safariAccessReady = false
        warnings = []; error = nil; stage = .sources
        message = "Bring your browsing with you."
        if notify { onChange?() }
    }

    var canContinueOnboardingSource: Bool {
        onboarding && stage == .profiles && isCurrent && (requiresSafariAccess || canChooseDestination)
    }

    func continueOnboardingSource() {
        guard canContinueOnboardingSource else { return }
        if requiresSafariAccess {
            stage = .safariAccess; onChange?()
        } else { startInOriginalDestination() }
    }

    func loadProfiles() {
        guard stage == .sources, let source, isCurrent else { return }
        generation = UUID(); let token = generation
        stage = .loading; message = "Finding your \(source.displayName) profiles…"; onChange?()
        discovery = PCNativeBrowserApplication.loadImportSourceProfiles(source) { [weak self] result in
            guard let self, self.isCurrent, self.generation == token, self.source === source else { return }
            self.discovery = nil; self.applyProfiles(result)
            self.requiresSafariAccess = result.access == .restricted
            self.stage = self.requiresSafariAccess && !self.onboarding ? .safariAccess : .profiles
            self.onChange?()
        }
    }

    private func applyProfiles(_ result: PCNativeImportProfileResult) {
        profiles = result.profiles; warnings = result.constraints
        let readable = result.profiles.first { $0.supportedCategories.rawValue != 0 } ?? result.profiles.first
        selectedProfiles = Set(readable.map { [$0.identifier] } ?? [])
        selectedExtensions.removeAll(); error = result.error?.localizedDescription
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
        // The parent wizard submits exactly one immutable source descriptor.
        selectedProfiles = [id]; onChange?()
    }

    var canChooseDestination: Bool {
        isCurrent && selectedProfiles.count == 1 && profiles.contains {
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

    /// Setup already owns its first Space and Profile. Unlike the menu wizard,
    /// its Import action must not create a second destination or follow the
    /// currently selected Space. Source discovery alone never submits data.
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

    func toggleCookieReplacement() {
        guard stage == .destination, isCurrent, !passwordsOnly else { return }
        destinationChoice.toggleCookieReplacement(); onChange?()
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

    func back() {
        guard stage == .profiles, !restarting else { return }
        stage = .sources; profiles = []; selectedProfiles = []; warnings = []; error = nil; onChange?()
    }

    func start() {
        guard canStart else { return }
        // Resolve/save once at the actual Import action, before native context
        // admission. Radio selection and name editing never create a Profile.
        do { activeDestination = try store.prepareImportDestination(destinationChoice, basedOn: originalDestination) }
        catch { self.error = error.localizedDescription; onChange?(); return }
        skipExistingCookies = !destinationChoice.replaceExistingCookies
        queue = profiles.filter { selectedProfiles.contains($0.identifier) && $0.supportedCategories.rawValue != 0 }
        stage = .importing; completed = 0; bookmarkPages = []; importedAdBlockers = []; error = nil
        generation = UUID()
        passwordDestination = source.map(Self.isSafari) == true ? activeDestination : nil
        passwordStageOffered = false
        if passwordsOnly { queue = []; activeDestination = nil }
        importNext()
    }

    private func importNext() {
        guard isCurrent, let window else { cancel(); return }
        guard !queue.isEmpty else {
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
        var categories = profile.supportedCategories
        let extensions = Set(profile.extensions.map(\.identifier)).intersection(selectedExtensions[profile.identifier] ?? [])
        let submittedAdBlockers = profile.extensions.compactMap { item -> OnboardingDraft.ImportedAdBlocker? in
            guard extensions.contains(item.identifier), OnboardingAdBlocker.isKnown(item.identifier) else { return nil }
            return .init(identifier: item.identifier, displayName: item.displayName)
        }
        if extensions.isEmpty { categories.remove(.extensions) }
        guard categories.rawValue != 0 else {
            warnings.append("No data was selected for \(profile.displayName).")
            completed += 1; importNext(); return
        }
        guard let destination = activeDestination, destination.isCurrent(in: store.state) else {
            finishSourceFailure("The selected destination is no longer available."); return
        }
        message = "Importing \(profile.displayName)…"; onChange?()
        session = PCNativeBrowserApplication.importBrowserData(from: profile,
            toProfilePath: store.independentEngineProfilePath(for: destination.profileID), in: window,
            categories: categories, allowedExtensionIDs: extensions, skipExistingCookies: skipExistingCookies,
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
                if result.outcome != .failed {
                    for item in submittedAdBlockers where !self.importedAdBlockers.contains(where: { $0.identifier == item.identifier }) {
                        self.importedAdBlockers.append(item)
                    }
                }
                do {
                    if !result.bookmarks.isEmpty {
                        let selection = try BrowserImportSelection(roots: Self.bookmarks(result.bookmarks),
                            historyVisitCounts: self.onboarding ? result.historyVisitCounts.mapValues(\.intValue) : nil)
                        self.bookmarkPages.append(BookmarkPage(sourceName: profile.displayName,
                                                              destination: destination, selection: selection))
                    }
                } catch { self.warnings.append("Bookmarks: \(error.localizedDescription)") }
                self.completed += 1
                if result.outcome == .cancelled {
                    self.queue = []; self.passwordDestination = nil
                    self.message = "Import stopped. Data already imported has been kept."
                    self.stage = self.bookmarkPages.isEmpty ? .finished : .bookmarks; self.onChange?()
                } else { self.importNext() }
            })
        if session == nil {
            activeDestination = nil; queue = []
            finishSourceFailure("Parc could not begin the import from \(profile.displayName).")
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
        passwordSession = PCNativeBrowserApplication.importPasswordFile(url,
            toProfilePath: store.independentEngineProfilePath(for: destination.profileID), in: window) { [weak self] result in
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
        passwordRequestID = nil
        stage = hasPendingBookmarks ? .bookmarks : .finished
        message = hasPendingBookmarks ? "Choose the bookmarks to keep in your sidebar." : "Your import has finished."
        onChange?()
    }

    private func finishSourceFailure(_ failure: String) {
        queue = []; passwordDestination = nil; warnings.append(failure); error = nil
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
        queue = []; passwordDestination = nil
        session?.cancel(); message = "Stopping import…"; onChange?()
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true; generation = UUID(); discovery?.cancel(); discovery = nil
        checkingSafariAccess = false; restarting = false; continueAfterSafariRefresh = false
        session?.cancel(); session = nil; activeDestination = nil; subscription = nil; queue = []
        passwordSession?.cancel(); passwordSession = nil; passwordRequestID = nil
        importingPasswords = false; removingPasswordFile = false; passwordDestination = nil
        acceptedICloudPasswordsDestination = nil
        stage = .finished; message = "Import stopped. Data already imported has been kept."; onChange?()
    }
}
