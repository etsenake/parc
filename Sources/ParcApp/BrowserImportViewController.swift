import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BrowserImportViewController: NSViewController {
    var onClose: (() -> Void)?
    var onChange: (() -> Void)?
    private(set) var pageDirection: OnboardingExperience.TransitionDirection?
    private var shownPage: BrowserImportCoordinator.Stage?
    private var pendingBack = false
    var onShowPasswordHelp: (() -> Void)?
    var onHidePasswordHelp: (() -> Void)?
    var onBackgroundAdBlockers: (([OnboardingDraft.ImportedAdBlocker]) -> Void)?
    var selectionColor: NSColor = OnboardingSetupPalette.action { didSet { updateSourcePicker(); updateBookmarksPicker(); updatePasswordChoice() } }
    private var sourcePicker: NSHostingView<BrowserImportSourcePicker>?
    private var bookmarksPicker: NSHostingView<OnboardingImportBookmarksPicker>?
    private var passwordChoice: NSHostingView<OnboardingPasswordChoice>?
    var acceptedICloudPasswordsDestination: BrowserImportDestination? {
        guard !closed, coordinator.stage == .finished else { return nil }
        return coordinator.acceptedICloudPasswordsDestination
    }
    var importedAdBlockers: [OnboardingDraft.ImportedAdBlocker] {
        earlierAdBlockers + coordinator.importedAdBlockers.filter { blocker in
            !earlierAdBlockers.contains { $0.identifier == blocker.identifier }
        }
    }
    var importReachedCompletion: Bool {
        if earlierImport || coordinator.parkedStage != nil { return true }
        switch coordinator.stage {
        case .passwordChoice, .safariPasswords, .bookmarks, .finished: return true
        default: return false
        }
    }
    private var onboardingAccess: OnboardingSafariAccessView?
    private var skipSelected = false
    var isChoosingSource: Bool { coordinator.isChoosingSourceInline }
    private weak var window: NSWindow?
    var embedded: Bool { onboarding }
    var isSafariAccess: Bool { coordinator.stage == .safariAccess }
    var isSafariPasswords: Bool { coordinator.stage == .safariPasswords }
    var canShowPasswordHelp: Bool { !closed && isSafariPasswords && !coordinator.importingPasswords }
    var usesFullSetupColumn: Bool { isSafariAccess || isSafariPasswords }
    var setupAccessory: NSView? { isSafariAccess ? onboardingAccess?.actions : nil }
    var headingText: String { heading.stringValue }
    var message: String { detail.stringValue }
    var nextTitle: String { embedded ? "Next" : next.title }
    private(set) var canAdvance = false
    var skipTitle: String? { closed ? nil : coordinator.setupSkipTitle }
    var canSkip: Bool { !closed && coordinator.canSkipInSetup }
    var canGoBack: Bool { !closed && coordinator.canGoBackInSetup }
    var foundNoSources: Bool { coordinator.foundNoSources }
    var isImporting: Bool { coordinator.stage == .importing }
    var isLoading: Bool {
        switch coordinator.stage {
        case .loading, .importing: return true
        case .safariAccess: return coordinator.continueAfterSafariRefresh
        case .safariPasswords: return coordinator.importingPasswords || coordinator.removingPasswordFile
        default: return false
        }
    }
    var onRequestRestart: ((BrowserImportRestartIntent, @escaping (String?) -> Void) -> Void)?
    private let root = LayoutView()
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let next = PArcDialogButton(title: "Next", primary: true, hint: false)
    private let cancelButton = PArcDialogButton(title: "Maybe Later", primary: false, hint: false)
    private let windowBackdrop = BrowserImportBackdrop()
    private let closeControl = ActionButton("", symbol: "xmark")
    private let logo = NSImageView()
    private let accessView = BrowserImportAccessView()
    private let passwordsView = BrowserImportPasswordsView()
    private var passwordPanel: NSOpenPanel?
    private var passwordHelp: OnboardingPasswordHelp?
    private var promptedPasswordRequest: UUID?
    private let onboarding: Bool
    private var accessTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var restartRequest: UUID?
    private var coordinator: BrowserImportCoordinator!
    private let ownerIsCurrent: () -> Bool
    private var earlierImport = false
    private var earlierAdBlockers: [OnboardingDraft.ImportedAdBlocker] = []
    private var lateAdBlockers: (([OnboardingDraft.ImportedAdBlocker]) -> Void)?
    private var closed = false
    private var queuedSetupCompletion = false

    init(store: BrowserStore, destination: BrowserImportDestination, window: NSWindow,
         onboarding: Bool, ownerIsCurrent: @escaping () -> Bool) {
        self.onboarding = onboarding
        self.window = window
        self.ownerIsCurrent = ownerIsCurrent
        super.init(nibName: nil, bundle: nil)
        view = root
        coordinator = makeCoordinator(store: store, destination: destination, window: window)
        passwordsView.usesSetupCard = onboarding
        passwordsView.onChooseFile = { [weak self] in self?.choosePasswordFile() }
        passwordsView.onDropFile = { [weak self] in self?.coordinator.importPasswordFile($0) }
        passwordsView.onHelp = { [weak self] in self?.showPasswordHelp() }
        passwordsView.onContinue = { [weak self] in
            guard let self, !self.helpCoversContent else { return }
            self.coordinator.continueAfterPasswords()
        }
        passwordsView.onStop = { [weak self] in self?.coordinator.stopPasswordImport() }
        passwordsView.onRemoveFile = { [weak self] in self?.confirmPasswordFileRemoval() }
        accessView.onContinue = { [weak self] in self?.coordinator.continueSafariWithoutRestarting() }
        accessView.onRestart = { [weak self] in self?.requestSafariRestart() }
        accessView.onOpenSettings = { [weak self] in self?.openSafariAccessSettings() }
        accessView.onRevealApplication = { [weak self] in self?.revealSafariAccessApplication() }
        if onboarding {
            let access = OnboardingSafariAccessView(frame: .zero)
            access.onOpenSettings = { [weak self] in self?.openSafariAccessSettings() }
            access.onRevealApplication = { [weak self] in self?.revealSafariAccessApplication() }
            access.onRestart = { [weak self] in self?.requestSafariRestart() }
            onboardingAccess = access
            root.addSubview(access)
        }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSafariAccessIfVisible() }
        }
        heading.font = .systemFont(ofSize: 26, weight: .bold); heading.textColor = PArcDialogStyle.popoverTitle
        detail.font = .systemFont(ofSize: 13); detail.textColor = PArcDialogStyle.popoverTitle
        logo.image = ParcBrandMark.image(.borderless) ?? NSApp.applicationIconImage
        logo.imageScaling = .scaleProportionallyUpOrDown; logo.setAccessibilityElement(false)
        closeControl.contentTintColor = PArcDialogStyle.popoverTitle
        closeControl.setAccessibilityLabel("Close Import")
        closeControl.actionBlock = { [weak self] in self?.requestClose() }
        if !onboarding { root.addSubview(windowBackdrop) }
        [heading, detail, next, cancelButton, logo, accessView, passwordsView, closeControl].forEach(root.addSubview)
        next.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"
        next.target = self; next.action = #selector(nextPressed)
        cancelButton.target = self; cancelButton.action = #selector(cancelPressed)
        root.onLayout = { [weak self] in self?.layout() }
        render()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func nextPressed() { advance() }
    @objc private func cancelPressed() {
        if coordinator.stage == .importing { coordinator.stopImport() } else { requestClose() }
    }

    func start() {
        guard !closed else { return }
        coordinator.discover()
        reconcileAccessTimer()
    }

    func stopImport() { coordinator.stopImport() }
    func requestClose() { guard !closed else { return }; onClose?() }

    private func makeCoordinator(store: BrowserStore, destination: BrowserImportDestination,
                                 window: NSWindow) -> BrowserImportCoordinator {
        let made = BrowserImportCoordinator(store: store, destination: destination, window: window,
            onboarding: onboarding, ownerIsCurrent: ownerIsCurrent)
        made.onChange = { [weak self] in self?.render() }
        made.retryRestart = { [weak self] in self?.requestSafariRestart() }
        return made
    }

    func skip() {
        guard !closed, window?.attachedSheet == nil else { return }
        pendingBack = false
        coordinator.skipInSetup()
    }

    func goBack() {
        guard !closed, window?.attachedSheet == nil else { return }
        guard coordinator.canGoBackInSetup else { return }
        pendingBack = true
        coordinator.goBackInSetup()
    }

    private func startOver(with source: PCNativeImportSource) {
        guard let window, let earlier = coordinator else { return }
        earlierImport = true
        earlierAdBlockers = Self.merged(earlierAdBlockers, earlier.importedAdBlockers)
        earlier.onChange = nil
        if earlier.hasBackgroundWork {
            earlier.detach(onAdBlockers: { [self] blockers in
                earlierAdBlockers = Self.merged(earlierAdBlockers, blockers)
                if closed { lateAdBlockers?(importedAdBlockers) }
            })
        } else { earlier.cancel() }
        coordinator = makeCoordinator(store: earlier.store, destination: earlier.originalDestination, window: window)
        coordinator.chooseSourceInline(source, from: earlier.sources)
    }

    private static func merged(_ first: [OnboardingDraft.ImportedAdBlocker],
                               _ second: [OnboardingDraft.ImportedAdBlocker]) -> [OnboardingDraft.ImportedAdBlocker] {
        first + second.filter { blocker in !first.contains { $0.identifier == blocker.identifier } }
    }

    func resumeSafariImport(sourceBundleID: String = "com.apple.Safari") {
        guard !closed else { return }
        coordinator.discover(resumingSourceBundleID: sourceBundleID)
    }

    private func requestSafariRestart() {
        guard !closed, let onRequestRestart,
              let source = coordinator.source,
              let bundleID = BrowserImportCoordinator.isArc(source) ? source.identifier : Bundle(url: source.appURL)?.bundleIdentifier,
              coordinator.beginSafariRestart() else { return }
        let token = UUID(); restartRequest = token
        let intent = BrowserImportRestartIntent(destination: coordinator.originalDestination, onboarding: onboarding,
                                                sourceBundleID: bundleID)
        onRequestRestart(intent) { [weak self] failure in
            guard let self, !self.closed, self.restartRequest == token else { return }
            self.restartRequest = nil; self.coordinator.safariRestartFailed(failure)
        }
    }

    private func refreshSafariAccessIfVisible() {
        guard !closed, window?.isVisible == true, NSApp.isActive,
              coordinator.stage == .safariAccess, !coordinator.restarting else { return }
        coordinator.refreshSafariAccess()
    }

    private func openSafariAccessSettings() {
        guard !closed, coordinator.stage == .safariAccess, !coordinator.restarting else { return }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"),
              NSWorkspace.shared.open(url) else {
            coordinator.reportSafariAccessError("Open System Settings → Privacy & Security → Full Disk Access to add Parc.")
            return
        }
    }

    private func revealSafariAccessApplication() {
        guard !closed, coordinator.stage == .safariAccess, !coordinator.restarting else { return }
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func reconcileAccessTimer() {
        guard !closed, window?.isVisible == true, coordinator.stage == .safariAccess,
              !coordinator.restarting else {
            accessTimer?.invalidate(); accessTimer = nil; return
        }
        guard accessTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSafariAccessIfVisible() }
        }
        accessTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        guard !closed else { return }
        closed = true; restartRequest = nil
        onHidePasswordHelp?(); dismissPasswordHelp(remove: true)
        passwordPanel?.cancel(nil); passwordPanel = nil
        accessTimer?.invalidate(); accessTimer = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        coordinator.onChange = nil
        var forward = onBackgroundAdBlockers
        if earlierImport, let setup = forward {
            lateAdBlockers = setup
            forward = { [self] _ in setup(importedAdBlockers) }
        }
        if coordinator.hasBackgroundWork { coordinator.detach(onAdBlockers: forward) } else { coordinator.cancel() }
        onBackgroundAdBlockers = nil
        onboardingAccess?.actions.removeFromSuperview()
        onChange = nil; onClose = nil; onRequestRestart = nil
        onShowPasswordHelp = nil; onHidePasswordHelp = nil
    }

    private func layout() {
        let width = root.bounds.width, height = root.bounds.height
        if embedded {
            sourcePicker?.frame = root.bounds
            bookmarksPicker?.frame = root.bounds
            passwordChoice?.frame = root.bounds
            onboardingAccess?.frame = root.bounds
            accessView.frame = root.bounds; passwordsView.frame = root.bounds
            return
        }
        accessView.frame = root.bounds; passwordsView.frame = root.bounds
        windowBackdrop.frame = root.bounds; passwordHelp?.frame = root.bounds
        closeControl.frame = NSRect(x: width - 48, y: 24, width: 24, height: 24)
        logo.frame = NSRect(x: 30, y: 34, width: 54, height: 47)
        if showsSourceCards || coordinator.stage == .loading {
            heading.frame = NSRect(x: 28, y: 106, width: 290, height: 26)
            detail.frame = NSRect(x: 28, y: 142, width: 260, height: 200)
        } else {
            heading.frame = NSRect(x: 34, y: 36, width: width - 68, height: 66)
            detail.frame = NSRect(x: 34, y: 104, width: width - 68, height: 45)
        }
        if !embedded {
            sourcePicker?.frame = NSRect(x: 314, y: 100, width: width - 336, height: height - 180)
            bookmarksPicker?.frame = NSRect(x: 34, y: 104, width: width - 68, height: height - 184)
        }
        func place(_ button: PArcDialogButton, right: CGFloat) -> CGFloat {
            button.frame = NSRect(x: right - button.bodyWidth - 0.5, y: height - 64.5, width: button.bodyWidth + 1, height: 38.5)
            return button.isHidden ? right : right - button.bodyWidth - 8
        }
        let right = place(next, right: width - 28)
        if showsSourceCards { _ = place(cancelButton, right: right) }
        else { cancelButton.frame = NSRect(x: 27.5, y: height - 64.5, width: cancelButton.bodyWidth + 1, height: 38.5) }
    }

    var showsSourceCards: Bool {
        switch coordinator.stage {
        case .sources, .profiles, .importing: return true
        case .loading: return coordinator.source != nil
        default: return false
        }
    }
    static let windowIntro = "Import everything you need from your old browser to hit the ground running with Parc."
    static let setupIntro = "It’s a bold new internet. Hit the ground running and bring your most important tabs, passwords, history, and bookmarks with you."

    private func render() {
        guard !closed else { return }
        if coordinator.stage == .finished {
            guard !queuedSetupCompletion else { return }
            queuedSetupCompletion = true
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.closed, self.coordinator.stage == .finished else { return }
                self.requestClose()
            }
            return
        }
        let stage = coordinator.stage
        let choosingAccess = stage == .safariAccess
        let choosingPasswords = stage == .safariPasswords
        let cards = showsSourceCards
        if !canShowPasswordHelp { dismissPasswordHelp() }
        passwordsView.isHidden = !choosingPasswords
        accessView.isHidden = !choosingAccess || embedded
        onboardingAccess?.isHidden = !choosingAccess
        heading.isHidden = choosingAccess || choosingPasswords
        detail.isHidden = choosingAccess || choosingPasswords
        let requestedWidth: CGFloat = choosingAccess ? 790 : 580
        let requestedHeight: CGFloat = choosingAccess ? 630 : choosingPasswords ? 630 : 454
        if !embedded, let window {
            BrowserImportGeometry.resize(window, contentSize: NSSize(width: requestedWidth, height: requestedHeight))
        }
        heading.stringValue = "Import from your old browser"
        bookmarksPicker?.isHidden = stage != .bookmarks
        passwordChoice?.isHidden = stage != .passwordChoice
        logo.isHidden = !(cards || stage == .loading)
        heading.font = .systemFont(ofSize: cards || stage == .loading ? 17 : 26, weight: .bold)
        detail.font = .systemFont(ofSize: cards || stage == .loading ? 16 : 13)
        detail.stringValue = coordinator.error ?? coordinator.message
        next.isHidden = false; next.isEnabled = true; next.title = "Next"
        cancelButton.title = stage == .importing ? "Stop Import" : "Maybe Later"
        if cards || stage == .loading {
            detail.stringValue = coordinator.error ?? (embedded ? Self.setupIntro : Self.windowIntro)
        }
        switch stage {
        case .loading:
            next.isEnabled = false
        case .sources:
            if coordinator.sources.isEmpty { detail.stringValue = coordinator.message }
        case .safariAccess:
            let name = coordinator.source?.displayName ?? "this browser"
            if embedded {
                heading.stringValue = "Import from \(name)."
                detail.stringValue = coordinator.source.map(BrowserImportCoordinator.isSafari) == true
                    ? "To import Safari browser history, Parc will need Full Disk Access. Feel free to remove access when this step is finished."
                    : "To import from \(name), Parc will need Full Disk Access. Feel free to remove access when this step is finished."
                next.isEnabled = !coordinator.continueAfterSafariRefresh && !coordinator.restarting
                onboardingAccess?.update(ready: coordinator.safariAccessReady, checking: coordinator.checkingSafariAccess,
                    continuing: coordinator.continueAfterSafariRefresh, restarting: coordinator.restarting,
                    restartAvailable: onRequestRestart != nil, error: coordinator.safariAccessError ?? coordinator.error)
            } else {
                next.isHidden = true
                accessView.update(ready: coordinator.safariAccessReady, checking: coordinator.checkingSafariAccess,
                    continuing: coordinator.continueAfterSafariRefresh, restarting: coordinator.restarting,
                    restartAvailable: onRequestRestart != nil, error: coordinator.safariAccessError ?? coordinator.error,
                    sourceName: name)
            }
        case .profiles: break
        case .importing:
            next.isEnabled = false
        case .passwordChoice:
            heading.stringValue = "Autofill your passwords."
            detail.stringValue = "To log into sites without typing your passwords, we recommend you install Apple’s iCloud Passwords Extension.\n\nYou can also manually import your passwords from Safari to Parc, if you’d like!"
            next.isEnabled = coordinator.canChoosePasswordMethod
            updatePasswordChoice()
        case .safariPasswords:
            heading.stringValue = "Stay logged in"
            detail.stringValue = (coordinator.supportsICloudPasswords
                ? "To manually import passwords from Safari, you’ll have to export them."
                : "To use your Safari passwords in Parc, you’ll have to export them from Safari.")
                + "\n\nOnce imported, your passwords will be encrypted locally on your computer and they’ll never be stored on our servers or shared with anyone else."
            next.isHidden = !embedded
            next.title = coordinator.passwordResult == nil ? "Skip Passwords" : "Continue"
            next.isEnabled = embedded ? coordinator.canContinueSetupPasswords
                : !coordinator.importingPasswords && !coordinator.removingPasswordFile
            passwordsView.update(canImport: coordinator.canImportPasswordFile,
                busy: coordinator.importingPasswords, removing: coordinator.removingPasswordFile,
                result: coordinator.passwordResult, canRemove: coordinator.canRemovePasswordFile, error: coordinator.passwordError)
            schedulePasswordFileConsent()
        case .bookmarks:
            next.title = "Add to Parc"
            heading.stringValue = "Treat your bookmarks to an upgrade."
            detail.stringValue = ""
            updateBookmarksPicker()
        case .finished: break
        }
        if isChoosingSource {
            next.isEnabled = (embedded && skipSelected) || coordinator.canContinueSourceInline
        }
        if cards { updateSourcePicker() } else { sourcePicker?.isHidden = true }
        updateBackdrop()
        cancelButton.isHidden = choosingAccess || choosingPasswords
        updateCloseKey()
        cancelButton.keyEquivalent = choosingAccess || choosingPasswords ? "" : "\u{1b}"
        next.isLoading = isLoading
        canAdvance = !next.isHidden && next.isEnabled
        if embedded {
            [heading, detail, logo, closeControl, next, cancelButton].forEach { $0.isHidden = true }
        }
        reconcileAccessTimer()
        root.needsLayout = true; root.layoutSubtreeIfNeeded()
        let page: BrowserImportCoordinator.Stage = cards || stage == .loading ? .sources : stage
        pageDirection = shownPage.flatMap { $0 == page ? nil : pendingBack ? .back : .forward }
        if pageDirection != nil { pendingBack = false }
        shownPage = page
        onChange?()
    }

    private func updatePasswordChoice() {
        guard embedded, !closed, coordinator?.stage == .passwordChoice else { return }
        let content = OnboardingPasswordChoice(installExtension: coordinator.wantsICloudPasswords,
            enabled: coordinator.canChoosePasswordMethod, selectionColor: selectionColor) { [weak self] value in
                self?.coordinator.choosePasswordMethod(installExtension: value)
            }
        if let passwordChoice { passwordChoice.rootView = content }
        else {
            let host = NSHostingView(rootView: content)
            passwordChoice = host; root.addSubview(host)
        }
        passwordChoice?.isHidden = false; passwordChoice?.frame = root.bounds
    }

    private func choosePasswordFile() {
        guard !closed, coordinator.canImportPasswordFile, let window,
              window.attachedSheet == nil, passwordPanel == nil else { return }
        let panel = NSOpenPanel(); passwordPanel = panel
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.commaSeparatedText]; panel.prompt = "Import Passwords"
        panel.message = "Choose the password CSV you exported. It will be imported into the selected Parc Profile."
        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            guard let self, !self.closed, self.passwordPanel === panel else { return }
            self.passwordPanel = nil
            guard response == .OK, let url = panel?.url, self.coordinator.canImportPasswordFile else { return }
            self.coordinator.importPasswordFile(url)
        }
    }

    private func showPasswordHelp() {
        guard canShowPasswordHelp, let window, window.attachedSheet == nil else { return }
        if embedded {
            onShowPasswordHelp?()
            return
        }
        let help: OnboardingPasswordHelp
        if let passwordHelp { help = passwordHelp }
        else {
            help = OnboardingPasswordHelp(frame: root.bounds)
            help.onDismiss = { [weak self] in self?.coverContent(false) }
            passwordHelp = help
            root.addSubview(help, positioned: .above, relativeTo: nil)
        }
        help.present()
        coverContent(help.isPresented)
    }

    private func dismissPasswordHelp(remove: Bool = false) {
        passwordHelp?.dismiss(animated: !remove)
        if remove {
            passwordHelp?.removeFromSuperview()
            passwordHelp = nil
        }
    }

    private var helpCoversContent: Bool { passwordHelp?.isPresented == true }

    private func coverContent(_ covered: Bool) {
        guard !closed else { return }
        root.subviews.forEach { if $0 !== passwordHelp { $0.setAccessibilityHidden(covered) } }
        updateCloseKey()
    }

    private func updateCloseKey() {
        let closes = (isSafariAccess || isSafariPasswords) && !helpCoversContent
        closeControl.keyEquivalent = closes ? "\u{1b}" : ""
    }

    private func schedulePasswordFileConsent() {
        guard coordinator.canRemovePasswordFile, let token = coordinator.passwordRequestID,
              promptedPasswordRequest != token else { return }
        promptedPasswordRequest = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.closed, self.coordinator.passwordRequestID == token,
                  self.coordinator.canRemovePasswordFile else { return }
            self.confirmPasswordFileRemoval()
        }
    }

    private func confirmPasswordFileRemoval() {
        guard !closed, coordinator.canRemovePasswordFile, let window,
              window.attachedSheet == nil else { return }
        let token = coordinator.passwordRequestID
        PArcDialog.confirm(in: window, title: "Want us to delete \(coordinator.passwordFileName ?? "Passwords.csv")?",
                          message: "For your security, it’s best to remove this file. Now that you’re done importing, you won’t need it again.",
                          confirm: "Yes, delete", cancel: "I'll do this later") { [weak self] approved in
            guard let self, !self.closed, self.coordinator.passwordRequestID == token,
                  approved, self.coordinator.canRemovePasswordFile else { return }
            self.coordinator.removePasswordFile()
        }
    }

    var backdrop: (pages: [BrowserImportWash], selected: Int?) {
        guard !closed, coordinator != nil else { return ([], nil) }
        let pages = coordinator.sources.map { source in BrowserImportTheme.wash(for: source, icon: Self.icon(source)) }
        let chosen = skipSelected ? nil : coordinator.sources.firstIndex { $0 === coordinator.source }
        return (pages, chosen)
    }

    private func updateBackdrop() {
        guard !embedded else { return }
        let value = backdrop
        windowBackdrop.setPage(fill: PArcDialogStyle.popoverBackground, ink: PArcDialogStyle.popoverTitle,
                               text: showsSourceCards || coordinator.stage == .loading ? 28 / 580...318 / 580 : 0...1)
        windowBackdrop.show(value.pages, selected: value.selected)
    }

    private static func icon(_ source: PCNativeImportSource) -> NSImage {
        BrowserImportCoordinator.isArc(source) ? BrowserImportArcIcon.icon(appURL: source.appURL)
            : NSWorkspace.shared.icon(forFile: source.appURL.path)
    }

    private func updateSourcePicker() {
        guard coordinator != nil, showsSourceCards, !closed else { return }
        let stage = coordinator.stage
        let choices = coordinator.sources.map { source in
            BrowserImportSourcePicker.Source(id: source.identifier, title: source.displayName,
                icon: Self.icon(source),
                iconBackground: BrowserImportSourcePicker.iconBackground(bundleIdentifier: source.identifier),
                selected: !skipSelected && coordinator.source === source, choose: { [weak self, weak source] in
                    guard let self, let source, self.canChooseSource else { return }
                    self.skipSelected = false
                    if self.coordinator.parkedStage == nil { self.coordinator.selectSourceInline(source) }
                    else if self.coordinator.source === source { self.render() }
                    else { self.startOver(with: source) }
                })
        }
        let skip = embedded ? BrowserImportSourcePicker.Skip(selected: skipSelected, choose: { [weak self] in
            guard let self, self.canChooseSource else { return }
            self.skipSelected = true
            if self.coordinator.parkedStage == nil { self.coordinator.clearSourceInline() } else { self.render() }
        }) : nil
        let content = BrowserImportSourcePicker(layout: embedded ? .setup : .window, sources: choices, skip: skip,
            enabled: stage != .importing,
            selectionColor: embedded ? selectionColor : NSColor(parcHex: "5636F4"))
        if let sourcePicker { sourcePicker.rootView = content; sourcePicker.isHidden = false }
        else { let host = NSHostingView(rootView: content); sourcePicker = host; root.addSubview(host) }
    }

    private var canChooseSource: Bool {
        !closed && coordinator.isChoosingSourceInline && window?.isKeyWindow == true && window?.attachedSheet == nil
    }

    private func updateBookmarksPicker() {
        guard !closed, coordinator?.stage == .bookmarks else { return }
        let pages = coordinator.bookmarkPages.map { page in
            OnboardingImportBookmarksPicker.Page(id: page.id, title: page.sourceName, selection: page.selection,
                enabled: coordinator.canChooseBookmarks(page), expandable: coordinator.canShowBookmarks(page),
                select: { [weak self] itemID in
                    guard let self, self.canChooseInlineBookmarks else { return }
                    self.coordinator.toggleBookmark(pageID: page.id, id: itemID)
                }, expand: { [weak self] itemID in
                    guard let self, self.canChooseInlineBookmarks else { return }
                    self.coordinator.toggleBookmark(pageID: page.id, id: itemID, expansion: true)
                })
        }
        let content = OnboardingImportBookmarksPicker(pages: pages, selectionColor: embedded ? selectionColor : NSColor(parcHex: "5636F4"))
        if let bookmarksPicker { bookmarksPicker.rootView = content; bookmarksPicker.isHidden = false }
        else { let host = NSHostingView(rootView: content); bookmarksPicker = host; root.addSubview(host) }
    }

    private var canChooseInlineBookmarks: Bool {
        !closed && coordinator.stage == .bookmarks
            && window?.isKeyWindow == true && window?.attachedSheet == nil
    }

    func advance() {
        guard !closed, window?.attachedSheet == nil else { return }
        pendingBack = false
        switch coordinator.stage {
        case .sources:
            if embedded && skipSelected { requestClose() }
        case .profiles:
            if embedded && skipSelected { requestClose() } else { coordinator.continueSourceInline() }
        case .bookmarks: coordinator.commitBookmarks()
        case .finished: requestClose()
        case .safariAccess:
            if embedded { coordinator.continueSafariWithoutRestarting() }
        case .safariPasswords:
            if !embedded || coordinator.canContinueSetupPasswords { coordinator.continueAfterPasswords() }
        case .passwordChoice: coordinator.continuePasswordChoice()
        case .loading, .importing: break
        }
    }
}
