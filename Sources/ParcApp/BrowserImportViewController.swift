import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One import presentation retains its original window through source discovery,
/// native permissions and final bookmark admission. Onboarding embeds this owner;
/// the application menu wraps it in its dedicated import window.
@MainActor
final class BrowserImportViewController: NSViewController {
    var onClose: (() -> Void)?
    var onChange: (() -> Void)?
    var onChooseBookmarks: (() -> Void)?
    var onShowPasswordHelp: (() -> Void)?
    var onHidePasswordHelp: (() -> Void)?
    var importedFileDescription: String? { didSet { if oldValue != importedFileDescription { updateSourcePicker() } } }
    var selectionColor: NSColor = OnboardingSetupPalette.action { didSet { updateSourcePicker(); updateBookmarksPicker(); updatePasswordChoice() } }
    private var sourcePicker: NSHostingView<OnboardingImportSourcePicker>?
    private var bookmarksPicker: NSHostingView<OnboardingImportBookmarksPicker>?
    private var passwordChoice: NSHostingView<OnboardingPasswordChoice>?
    var acceptedICloudPasswordsDestination: BrowserImportDestination? {
        guard !closed, coordinator.stage == .finished else { return nil }
        return coordinator.acceptedICloudPasswordsDestination
    }
    var importedAdBlockers: [OnboardingDraft.ImportedAdBlocker] { coordinator.importedAdBlockers }
    var importReachedCompletion: Bool {
        switch coordinator.stage {
        case .passwordChoice, .safariPasswords, .bookmarks, .finished: return true
        default: return false
        }
    }
    private var onboardingAccess: OnboardingSafariAccessView?
    private var freshStartSelected = false
    var isChoosingSource: Bool { coordinator.stage == .sources || coordinator.isChoosingOnboardingSource }
    private weak var window: NSWindow?
    var embedded: Bool { onboarding }
    var isSafariAccess: Bool { coordinator.stage == .safariAccess }
    var isSafariPasswords: Bool { coordinator.stage == .safariPasswords }
    var canShowPasswordHelp: Bool { !closed && isSafariPasswords && !coordinator.importingPasswords }
    var usesFullSetupColumn: Bool { isSafariAccess || isSafariPasswords }
    var setupAccessory: NSView? { isSafariAccess ? onboardingAccess?.actions : nil }
    var headingText: String { heading.stringValue }
    var message: String { detail.stringValue }
    // The setup owner uses its shared Next control through the import steps;
    // menu-wizard labels do not replace that progression control.
    var nextTitle: String { embedded ? "Next" : next.title }
    private(set) var canAdvance = false
    private(set) var canGoBack = false
    var isImporting: Bool { coordinator.stage == .importing }
    var onRequestRestart: ((BrowserImportRestartIntent, @escaping (String?) -> Void) -> Void)?
    private let root = LayoutView()
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let scroll = NSScrollView()
    private let rows = FlippedStackView()
    private let next = ActionButton("Next")
    private let back = ActionButton("Back")
    private let cancelButton = ActionButton("Maybe Later")
    private let closeControl = ActionButton("", symbol: "xmark")
    private let logo = NSImageView()
    private let destinationView = BrowserImportDestinationView()
    private let accessView = BrowserImportAccessView()
    private let passwordsView = BrowserImportPasswordsView()
    private var passwordPanel: NSOpenPanel?
    private var promptedPasswordRequest: UUID?
    private let onboarding: Bool
    private var accessTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var restartRequest: UUID?
    private let destinationScroll = NSScrollView()
    private var coordinator: BrowserImportCoordinator!
    private var closed = false
    private var queuedSetupCompletion = false

    init(store: BrowserStore, destination: BrowserImportDestination, window: NSWindow,
         onboarding: Bool, ownerIsCurrent: @escaping () -> Bool) {
        self.onboarding = onboarding
        self.window = window
        super.init(nibName: nil, bundle: nil)
        view = root
        coordinator = BrowserImportCoordinator(store: store, destination: destination, window: window,
            onboarding: onboarding, ownerIsCurrent: ownerIsCurrent)
        destinationScroll.drawsBackground = false; destinationScroll.borderType = .noBorder
        destinationScroll.hasVerticalScroller = true; destinationScroll.autohidesScrollers = true
        destinationScroll.documentView = destinationView
        coordinator.onChange = { [weak self] in self?.render() }
        passwordsView.usesSetupCard = onboarding
        passwordsView.onChooseFile = { [weak self] in self?.choosePasswordFile() }
        passwordsView.onDropFile = { [weak self] in self?.coordinator.importPasswordFile($0) }
        passwordsView.onHelp = { [weak self] in self?.showPasswordHelp() }
        passwordsView.onContinue = { [weak self] in self?.coordinator.continueAfterPasswords() }
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
        destinationView.onSelect = { [weak self] in self?.coordinator.selectDestination($0) }
        destinationView.onToggleCookies = { [weak self] in self?.coordinator.toggleCookieReplacement() }
        destinationView.onNameChange = { [weak self] name in
            guard let self else { return }
            self.coordinator.setNewProfileName(name)
            self.next.isEnabled = self.coordinator.canStart
        }
        heading.font = .systemFont(ofSize: 26, weight: .bold); heading.textColor = .white
        detail.font = .systemFont(ofSize: 13); detail.textColor = NSColor.white.withAlphaComponent(0.7)
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 12
        rows.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 12, right: 0)
        rows.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = rows
        rows.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        logo.image = ParcBrandMark.image(.borderless) ?? NSApp.applicationIconImage
        logo.imageScaling = .scaleProportionallyUpOrDown; logo.setAccessibilityElement(false)
        closeControl.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        closeControl.setAccessibilityLabel("Close Import")
        closeControl.actionBlock = { [weak self] in self?.requestClose() }
        [heading, detail, scroll, destinationScroll, next, back, cancelButton, logo, accessView, passwordsView, closeControl].forEach(root.addSubview)
        for button in [next, back, cancelButton] {
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.contentTintColor = embedded ? OnboardingSetupPalette.title : .white; button.focusRingType = .default
        }
        next.isBordered = true; next.bezelStyle = .rounded; next.bezelColor = NSColor(parcHex: "8370E9")
        next.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"
        next.actionBlock = { [weak self] in self?.advance() }
        back.actionBlock = { [weak self] in self?.coordinator.back() }
        cancelButton.actionBlock = { [weak self] in
            guard let self else { return }
            if self.coordinator.stage == .importing { self.coordinator.stopImport() }
            else { self.requestClose() }
        }
        root.onLayout = { [weak self] in self?.layout() }
        render()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func start() {
        guard !closed else { return }
        coordinator.discover()
        reconcileAccessTimer()
    }

    func goBack() { freshStartSelected = false; coordinator.back() }
    func stopImport() { coordinator.stopImport() }
    func didChooseBookmarksFile() {
        guard embedded, !closed, isChoosingSource else { return }
        freshStartSelected = true; coordinator.clearOnboardingSource()
    }
    func requestClose() { guard !closed else { return }; onClose?() }

    /// A persisted restart intent never contains source/profile leases. Obtain
    /// new descriptors and stop before any user-approved import submission.
    func resumeSafariImport(sourceBundleID: String = "com.apple.Safari") {
        guard !closed else { return }
        coordinator.discover(resumingSourceBundleID: sourceBundleID)
    }

    private func requestSafariRestart() {
        guard !closed, let onRequestRestart,
              let source = coordinator.source,
              let bundleID = Bundle(url: source.appURL)?.bundleIdentifier,
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
        //
        // owner bounded to the visible stage; activation also requests a refresh.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSafariAccessIfVisible() }
        }
        accessTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        guard !closed else { return }
        closed = true; restartRequest = nil
        onHidePasswordHelp?()
        passwordPanel?.cancel(nil); passwordPanel = nil
        accessTimer?.invalidate(); accessTimer = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        coordinator.onChange = nil; coordinator.cancel()
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
            scroll.frame = root.bounds.insetBy(dx: 24, dy: 16)
            accessView.frame = root.bounds; passwordsView.frame = root.bounds
            return
        }
        accessView.frame = root.bounds; passwordsView.frame = root.bounds
        closeControl.frame = NSRect(x: width - 48, y: 24, width: 24, height: 24)
        logo.frame = NSRect(x: 30, y: 34, width: 54, height: 47)
        if coordinator.stage == .destination {
            heading.frame = NSRect(x: 28, y: 62, width: width - 56, height: 30)
            destinationScroll.frame = NSRect(x: 28, y: 106, width: width - 56, height: height - 106)
            destinationView.frame = NSRect(x: 0, y: 0, width: destinationScroll.contentSize.width,
                                           height: destinationView.desiredHeight)
        } else if coordinator.stage == .sources {
            heading.frame = NSRect(x: 28, y: 106, width: 290, height: 26)
            detail.frame = NSRect(x: 28, y: 142, width: 260, height: 200)
            scroll.frame = NSRect(x: 335, y: 164, width: 177, height: height - 235)
        } else {
            heading.frame = NSRect(x: 34, y: 36, width: width - 68, height: 66)
            detail.frame = NSRect(x: 34, y: 104, width: width - 68, height: 45)
            scroll.frame = NSRect(x: 34, y: 158, width: width - 68, height: height - 225)
        }
        cancelButton.frame = NSRect(x: coordinator.stage == .sources ? width - 193 : 26, y: height - 66, width: 108, height: 38)
        let nextWidth: CGFloat = coordinator.stage == .sources ? 60 : coordinator.stage == .destination ? 64 : 112
        back.frame = NSRect(x: width - nextWidth - 118, y: height - 66, width: 80, height: 38)
        next.frame = NSRect(x: width - nextWidth - 24, y: height - 66, width: nextWidth, height: 38)
    }

    private func label(_ title: String, secondary: Bool = false) -> NSTextField {
        let view = NSTextField(wrappingLabelWithString: title)
        view.font = .systemFont(ofSize: secondary ? 11 : 13, weight: secondary ? .regular : .medium)
        view.textColor = embedded ? (secondary ? OnboardingSetupPalette.message : OnboardingSetupPalette.title) :
            (secondary ? NSColor.white.withAlphaComponent(0.65) : .white)
        return view
    }
    private func add(_ view: NSView) {
        rows.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
    }
    private func checkbox(_ title: String, selected: Bool, action: @escaping () -> Void) -> ActionButton {
        let button = ActionButton(title, action: action)
        button.setButtonType(.switch); button.state = selected ? .on : .off
        button.contentTintColor = embedded ? OnboardingSetupPalette.title : .white; button.focusRingType = .default
        button.font = .systemFont(ofSize: 13); button.alignment = .left
        return button
    }

    private func render() {
        guard !closed else { return }
        if embedded, coordinator.stage == .finished, coordinator.warnings.isEmpty, coordinator.error == nil {
            // The menu has a results page; setup continues to its next real
            // step. Leave the view update stack before releasing this owner.
            guard !queuedSetupCompletion else { return }
            queuedSetupCompletion = true
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.closed, self.coordinator.stage == .finished else { return }
                self.requestClose()
            }
            return
        }
        let choosingDestination = coordinator.stage == .destination
        let choosingAccess = coordinator.stage == .safariAccess
        let choosingPasswords = coordinator.stage == .safariPasswords
        passwordsView.isHidden = !choosingPasswords
        accessView.isHidden = !choosingAccess || embedded
        onboardingAccess?.isHidden = !choosingAccess
        heading.isHidden = choosingAccess || choosingPasswords
        let destinationProfiles = coordinator.profileTargets.compactMap { target -> BrowserImportDestinationView.Profile? in
            guard let profile = coordinator.store.state.profiles.first(where: { $0.id == target.profileID }) else { return nil }
            let title = profile.id == coordinator.store.defaultProfileID && profile.name == "Default" ?
                "My Existing Parc Profile" : profile.name
            return .init(target: target, title: title)
        }
        destinationView.update(profiles: destinationProfiles, choice: coordinator.destinationChoice, error: coordinator.error,
                               showsCookieReplacement: !coordinator.passwordsOnly)
        destinationScroll.isHidden = !choosingDestination
        scroll.isHidden = choosingDestination || choosingAccess || choosingPasswords
        detail.isHidden = choosingDestination || choosingAccess || choosingPasswords
        let requestedWidth: CGFloat = choosingAccess ? 790 : 580
        let requestedHeight: CGFloat = choosingAccess ? 630 : choosingPasswords ? 630 : choosingDestination ? min(640, max(335, 106 + destinationView.desiredHeight)) : 454
        if !embedded, let window, abs(root.bounds.height - requestedHeight) > 1 || abs(root.bounds.width - requestedWidth) > 1 {
            let top = window.frame.maxY
            window.setContentSize(NSSize(width: requestedWidth, height: requestedHeight))
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
        }
        let origin = scroll.contentView.bounds.origin
        rows.arrangedSubviews.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
        heading.stringValue = "Import from your old browser"
        let choosingSource = isChoosingSource
        sourcePicker?.isHidden = !choosingSource || !embedded
        bookmarksPicker?.isHidden = coordinator.stage != .bookmarks || !embedded
        passwordChoice?.isHidden = coordinator.stage != .passwordChoice
        logo.isHidden = !choosingSource
        heading.font = .systemFont(ofSize: choosingSource || choosingDestination ? 17 : 26, weight: .bold)
        detail.font = .systemFont(ofSize: choosingSource ? 16 : 13)
        detail.stringValue = coordinator.error ?? coordinator.message
        detail.textColor = coordinator.error == nil ? NSColor.white.withAlphaComponent(0.7) : .systemRed
        back.isHidden = coordinator.stage != .profiles
        next.isHidden = false; next.isEnabled = true; next.title = "Next"
        cancelButton.title = coordinator.stage == .importing ? "Stop Import" : "Maybe Later"
        switch coordinator.stage {
        case .loading:
            let progress = NSProgressIndicator(); progress.style = .spinning
            progress.controlSize = .regular; progress.startAnimation(nil); add(progress)
            next.isEnabled = false
        case .sources:
            if embedded {
                scroll.isHidden = true
            } else {
                for source in coordinator.sources {
                    let button = ImportSourceButton(source.displayName, icon: NSWorkspace.shared.icon(forFile: source.appURL.path),
                        selected: coordinator.source === source) { [weak self] in self?.coordinator.select(source) }
                    button.heightAnchor.constraint(equalToConstant: 48).isActive = true; add(button)
                }
            }
            if let source = coordinator.source, !freshStartSelected {
                detail.stringValue = embedded ? "Bring your bookmarks and browsing data from \(source.displayName). You’ll choose what to keep." :
                    "Import what you need from your old browser to get started with Parc.\n\nContinue to choose your \(source.displayName) profiles and see the data they can import."
            }
            next.isEnabled = coordinator.source != nil || (embedded && freshStartSelected)
        case .safariAccess:
            let name = coordinator.source?.displayName ?? "this browser"
            if embedded {
                heading.stringValue = "Import from \(name)."
                detail.stringValue = "To import from \(name), Parc will need Full Disk Access. Feel free to remove access when this step is finished."
                next.isEnabled = !coordinator.continueAfterSafariRefresh && !coordinator.restarting
                onboardingAccess?.update(ready: coordinator.safariAccessReady, checking: coordinator.checkingSafariAccess,
                    continuing: coordinator.continueAfterSafariRefresh, restarting: coordinator.restarting,
                    restartAvailable: onRequestRestart != nil, error: coordinator.safariAccessError ?? coordinator.error,
                    sourceName: name)
            } else {
                next.isHidden = true
                accessView.update(ready: coordinator.safariAccessReady, checking: coordinator.checkingSafariAccess,
                    continuing: coordinator.continueAfterSafariRefresh, restarting: coordinator.restarting,
                    restartAvailable: onRequestRestart != nil, error: coordinator.safariAccessError ?? coordinator.error,
                    sourceName: name)
            }
        case .profiles:
            if embedded { break }
            heading.stringValue = "Make yourself at home"
            for profile in coordinator.profiles {
                let check = checkbox(profile.displayName, selected: coordinator.selectedProfiles.contains(profile.identifier)) { [weak self] in
                    self?.coordinator.selectProfile(profile.identifier)
                }
                check.setButtonType(.radio)
                check.isEnabled = profile.supportedCategories.rawValue != 0; add(check)
                add(label(Self.categories(profile.supportedCategories), secondary: true))
                profile.constraints.forEach { add(label($0, secondary: true)) }
                if coordinator.selectedProfiles.contains(profile.identifier) {
                    for item in profile.extensions {
                        add(checkbox("Add \(item.displayName)", selected: coordinator.selectedExtensions[profile.identifier]?.contains(item.identifier) == true) { [weak self] in
                            self?.coordinator.toggleExtension(item.identifier, profileID: profile.identifier)
                        })
                    }
                }
            }
            if coordinator.canChoosePasswordDestination {
                let passwords = ActionButton("Import exported passwords instead…") { [weak self] in
                    guard let self else { return }
                    if self.embedded { self.coordinator.startInOriginalDestination(passwordsOnly: true) }
                    else { self.coordinator.choosePasswordDestination() }
                }
                passwords.bezelStyle = .rounded; add(passwords)
            }
            next.isEnabled = coordinator.canChooseDestination
        case .destination:
            heading.stringValue = "Which Parc Profile should we import to?"
            next.title = "Import"; next.isEnabled = coordinator.canStart
        case .importing:
            heading.stringValue = "Bringing your browser over"
            add(label("You can approve access and extension permissions here while your data imports.", secondary: true))
            let progress = NSProgressIndicator(); progress.style = .bar; progress.isIndeterminate = true
            progress.startAnimation(nil); add(progress); next.isHidden = true
        case .passwordChoice:
            heading.stringValue = "Autofill your passwords."
            detail.stringValue = "To log into sites without typing your passwords, we recommend you install Apple’s iCloud Passwords Extension.\n\nYou can also manually import your passwords from Safari to Parc, if you’d like!"
            scroll.isHidden = true
            next.isEnabled = coordinator.canChoosePasswordMethod
            updatePasswordChoice()
        case .safariPasswords:
            heading.stringValue = embedded ? "Stay logged in" : "Stay logged in."
            if embedded {
                detail.stringValue = "To manually import passwords from Safari, you’ll have to export them.\n\nOnce imported, your passwords will be encrypted locally on your computer and they’ll never be stored on our servers or shared with anyone else."
            } else {
                detail.stringValue = "Bring your saved Safari passwords with you. They’ll stay in this Parc Profile."
            }
            next.isHidden = !embedded
            next.title = coordinator.passwordResult == nil ? "Skip Passwords" : "Continue"
            next.isEnabled = !coordinator.importingPasswords && !coordinator.removingPasswordFile
            let name = coordinator.store.state.profiles.first { $0.id == coordinator.passwordDestination?.profileID }?.name ?? "Unavailable Profile"
            passwordsView.update(destination: name, canImport: coordinator.canImportPasswordFile,
                busy: coordinator.importingPasswords, removing: coordinator.removingPasswordFile,
                result: coordinator.passwordResult, fileName: coordinator.passwordFileName,
                removed: coordinator.passwordFileRemoved, canRemove: coordinator.canRemovePasswordFile,
                error: coordinator.passwordError)
            schedulePasswordFileConsent()
        case .bookmarks:
            heading.stringValue = embedded ? "Treat your bookmarks to an upgrade." : "Treat your bookmarks to an upgrade"
            next.title = "Add to Parc"
            if embedded {
                detail.stringValue = "We recommend bringing 5 bookmarks to start—it’s easy to import the rest later."
                scroll.isHidden = true
                updateBookmarksPicker()
                break
            }
            for (index, page) in coordinator.bookmarkPages.enumerated() {
                let available = !page.discarded && page.destination.isCurrent(in: coordinator.store.state)
                add(label(page.sourceName + (page.committed ? " · Added" : available ? "" : " · Destination no longer available")))
                func append(_ items: [BrowserImportBookmark], depth: Int) {
                    for item in items {
                        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 5
                        let spacer = NSView(); spacer.widthAnchor.constraint(equalToConstant: CGFloat(depth * 15)).isActive = true
                        row.addArrangedSubview(spacer)
                        if item.url == nil {
                            let disclosure = ActionButton(page.selection.expanded.contains(item.id) ? "▾" : "▸") { [weak self] in
                                self?.coordinator.toggleBookmark(page: index, id: item.id, expansion: true)
                            }
                            disclosure.contentTintColor = embedded ? OnboardingSetupPalette.title : .white; disclosure.setAccessibilityLabel("Expand \(item.title)")
                            disclosure.isEnabled = available && !page.committed
                            disclosure.widthAnchor.constraint(equalToConstant: 15).isActive = true
                            row.addArrangedSubview(disclosure)
                        }
                        let check = checkbox(item.title, selected: page.selection.selected.contains(item.id)) { [weak self] in
                            self?.coordinator.toggleBookmark(page: index, id: item.id, expansion: false)
                        }
                        check.isEnabled = available && !page.committed; row.addArrangedSubview(check); add(row)
                        if page.selection.expanded.contains(item.id) { append(item.children, depth: depth + 1) }
                    }
                }
                append(page.selection.roots, depth: 0)
            }
        case .finished:
            heading.stringValue = coordinator.warnings.isEmpty && coordinator.error == nil ? "Welcome home." : "Import results"
            next.title = "Done"; cancelButton.isHidden = true
        }
        if embedded && choosingSource {
            // Source cards remain in place while their real profile request is
            // pending or a profile is selected. Next alone starts the import.
            scroll.isHidden = true; back.isHidden = true; next.title = "Next"
            next.isEnabled = freshStartSelected || coordinator.canContinueOnboardingSource
            if coordinator.error == nil {
                detail.stringValue = "It’s a bold new internet. Hit the ground running and bring your most important tabs, passwords, history, and bookmarks with you."
            }
            updateSourcePicker()
        }
        cancelButton.isHidden = coordinator.stage == .finished || choosingDestination || choosingAccess || choosingPasswords
        closeControl.keyEquivalent = choosingDestination || choosingAccess || choosingPasswords ? "\u{1b}" : ""
        cancelButton.keyEquivalent = choosingDestination || choosingAccess || choosingPasswords ? "" : "\u{1b}"
        if !choosingDestination && !choosingAccess && !choosingPasswords { coordinator.warnings.forEach { add(label($0, secondary: true)) } }
        canAdvance = !next.isHidden && next.isEnabled
        canGoBack = !back.isHidden && !closed
        if embedded {
            [heading, detail, logo, closeControl, next, back, cancelButton].forEach { $0.isHidden = true }
        }
        reconcileAccessTimer()
        root.needsLayout = true; root.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView)
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
        guard !closed, coordinator.stage == .safariPasswords, let window,
              window.attachedSheet == nil, !coordinator.importingPasswords else { return }
        if embedded {
            onShowPasswordHelp?()
            return
        }
        let alert = NSAlert(); alert.messageText = "Exporting Safari passwords"
        if #available(macOS 15, *) {
            alert.informativeText = "Open Apple’s Passwords app and unlock it yourself. Choose File → Export All Passwords to File, then save the CSV. Return here and choose that file.\n\nThe exported CSV contains readable passwords. Parc can move it to Trash after all supported records have been confirmed. Passkeys and verification codes are not imported."
        } else {
            alert.informativeText = "In Safari, open Settings → Passwords and unlock it yourself. Use the options menu to export passwords, then save the CSV. Return here and choose that file.\n\nThe exported CSV contains readable passwords. Parc can move it to Trash after all supported records have been confirmed. Passkeys and verification codes are not imported."
        }
        alert.addButton(withTitle: "Done")
        alert.beginSheetModal(for: window)
    }

    private func schedulePasswordFileConsent() {
        guard coordinator.canRemovePasswordFile, let token = coordinator.passwordRequestID,
              promptedPasswordRequest != token else { return }
        promptedPasswordRequest = token
        // The original reducer schedules its separate consent action after
        // 600 ms. Parc waits for actual persistence before starting that delay.
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
        //
        // sheet with these strings, not an NSAlert; the file goes to Trash.
        PArcDialog.confirm(in: window, title: "Want us to delete \(coordinator.passwordFileName ?? "Passwords.csv")?",
                          message: "For your security, it’s best to remove this file. Now that you’re done importing, you won’t need it again.",
                          confirm: "Yes, delete", cancel: "I'll do this later") { [weak self] approved in
            guard let self, !self.closed, self.coordinator.passwordRequestID == token,
                  approved, self.coordinator.canRemovePasswordFile else { return }
            self.coordinator.removePasswordFile()
        }
    }

    private func updateSourcePicker() {
        guard embedded, coordinator != nil, isChoosingSource, !closed else { return }
        let choices = coordinator.sources.map { source in
            let selected = !freshStartSelected && coordinator.source === source
            let profiles = selected ? coordinator.profiles.map { profile in
                OnboardingImportSourcePicker.Profile(id: profile.identifier, title: profile.displayName,
                    selected: coordinator.selectedProfiles.contains(profile.identifier),
                    enabled: profile.supportedCategories.rawValue != 0, choose: { [weak self, weak source] in
                        guard let self, let source, self.canChooseInlineSource,
                              self.coordinator.source === source,
                              self.coordinator.profiles.contains(where: { $0 === profile }) else { return }
                        self.coordinator.selectProfile(profile.identifier)
                    })
            } : []
            let profile = selected ? coordinator.profiles.first(where: { coordinator.selectedProfiles.contains($0.identifier) }) : nil
            let options = profile.map { profile in
                profile.extensions.map { item in
                    OnboardingImportSourcePicker.ImportOption(id: item.identifier, title: item.displayName,
                        selected: coordinator.selectedExtensions[profile.identifier]?.contains(item.identifier) == true,
                        toggle: { [weak self, weak source, weak profile] in
                            guard let self, let source, let profile, self.canChooseInlineSource,
                                  self.coordinator.source === source,
                                  self.coordinator.profiles.contains(where: { $0 === profile }) else { return }
                            self.coordinator.toggleExtension(item.identifier, profileID: profile.identifier)
                        })
                }
            } ?? []
            var messages = selected ? coordinator.warnings + (profile?.constraints ?? []) + (coordinator.error.map { [$0] } ?? []) : []
            if selected, coordinator.stage == .profiles, coordinator.profiles.isEmpty, coordinator.error == nil {
                messages.append(coordinator.message)
            }
            let choosePasswords: (() -> Void)? = selected && coordinator.canChoosePasswordDestination ? { [weak self, weak source] in
                guard let self, let source, self.canChooseInlineSource,
                      self.coordinator.source === source else { return }
                self.coordinator.startInOriginalDestination(passwordsOnly: true)
            } : nil
            return OnboardingImportSourcePicker.Source(id: source.identifier, title: source.displayName,
                icon: NSWorkspace.shared.icon(forFile: source.appURL.path),
                iconBackground: OnboardingImportSourcePicker.iconBackground(bundleIdentifier: Bundle(url: source.appURL)?.bundleIdentifier),
                selected: selected, choose: { [weak self, weak source] in
                    guard let self, let source, self.canChooseInlineSource else { return }
                    self.freshStartSelected = false; self.coordinator.selectOnboardingSource(source)
                }, profiles: profiles, loading: selected && coordinator.stage == .loading,
                options: options, messages: messages, choosePasswords: choosePasswords)
        }
        let content = OnboardingImportSourcePicker(sources: choices,
            freshStartSelected: freshStartSelected, selectionColor: selectionColor,
            chooseFreshStart: { [weak self] in
                guard let self, self.canChooseInlineSource else { return }
                self.freshStartSelected = true; self.coordinator.clearOnboardingSource()
            }, chooseFile: { [weak self] in self?.onChooseBookmarks?() }, fileDescription: importedFileDescription)
        if let sourcePicker { sourcePicker.rootView = content; sourcePicker.isHidden = false }
        else { let host = NSHostingView(rootView: content); sourcePicker = host; root.addSubview(host) }
    }

    private var canChooseInlineSource: Bool {
        embedded && !closed && coordinator.isChoosingOnboardingSource
            && window?.isKeyWindow == true && window?.attachedSheet == nil
    }

    private func updateBookmarksPicker() {
        guard embedded, !closed, coordinator?.stage == .bookmarks else { return }
        let pages = coordinator.bookmarkPages.map { page in
            let available = !page.discarded && page.destination.isCurrent(in: coordinator.store.state)
            let status: String? = page.committed ? "Added to Parc" : available ? nil : "Destination no longer available"
            return OnboardingImportBookmarksPicker.Page(id: page.id, title: page.sourceName,
                selection: page.selection, enabled: available && !page.committed, status: status,
                select: { [weak self] itemID in
                    guard let self, self.canChooseInlineBookmarks else { return }
                    self.coordinator.toggleBookmark(pageID: page.id, id: itemID)
                }, expand: { [weak self] itemID in
                    guard let self, self.canChooseInlineBookmarks else { return }
                    self.coordinator.toggleBookmark(pageID: page.id, id: itemID, expansion: true)
                })
        }
        let content = OnboardingImportBookmarksPicker(pages: pages, selectionColor: selectionColor,
            messages: coordinator.warnings + (coordinator.error.map { [$0] } ?? []))
        if let bookmarksPicker { bookmarksPicker.rootView = content; bookmarksPicker.isHidden = false }
        else { let host = NSHostingView(rootView: content); bookmarksPicker = host; root.addSubview(host) }
    }

    private var canChooseInlineBookmarks: Bool {
        embedded && !closed && coordinator.stage == .bookmarks
            && window?.isKeyWindow == true && window?.attachedSheet == nil
    }

    func advance() {
        guard !closed, window?.attachedSheet == nil else { return }
        switch coordinator.stage {
        case .sources:
            if embedded && freshStartSelected { requestClose() }
            else { coordinator.loadProfiles() }
        case .profiles:
            if embedded { coordinator.continueOnboardingSource() }
            else { coordinator.chooseDestination() }
        case .destination:
            guard !destinationView.hasMarkedText else { return }
            coordinator.start()
        case .bookmarks: coordinator.commitBookmarks()
        case .finished: requestClose()
        case .safariAccess:
            if embedded { coordinator.continueSafariWithoutRestarting() }
        case .safariPasswords: coordinator.continueAfterPasswords()
        case .passwordChoice: coordinator.continuePasswordChoice()
        case .loading, .importing: break
        }
    }
    private static func categories(_ value: PCNativeImportCategories) -> String {
        [(1, "History"), (2, "Bookmarks"), (4, "Cookies"), (8, "Passwords"),
         (16, "Autofill"), (32, "Extensions")].compactMap { bit, title in
            value.rawValue & UInt(bit) != 0 ? title : nil
        }.joined(separator: " · ")
    }
}

/// Native button tracking, keyboard activation and radio accessibility with the
/// observed source-row composition. Detailed hover/motion comparison is separate.
@MainActor
private final class ImportSourceButton: NSButton {
    private let sourceIcon: NSImage
    private let activate: () -> Void
    init(_ title: String, icon: NSImage, selected: Bool, action: @escaping () -> Void) {
        sourceIcon = icon; activate = action
        super.init(frame: .zero)
        self.title = title; setButtonType(.radio); state = selected ? .on : .off
        isBordered = false; focusRingType = .default
        target = self; self.action = #selector(choose)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func choose() { activate() }
    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 1, dy: 1)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 15, yRadius: 15)
        NSColor.white.withAlphaComponent(isHighlighted ? 0.22 : 0.12).setFill(); shape.fill()
        (state == .on ? NSColor(parcHex: "5636F4") : NSColor.white.withAlphaComponent(0.1)).setStroke()
        shape.lineWidth = state == .on ? 2 : 1; shape.stroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: bounds.width - 49, y: 2))
        separator.line(to: NSPoint(x: bounds.width - 49, y: bounds.height - 2))
        NSColor.white.withAlphaComponent(0.12).setStroke(); separator.stroke()
        sourceIcon.draw(in: NSRect(x: bounds.width - 37, y: (bounds.height - 24) / 2, width: 24, height: 24))
        let radio = NSRect(x: 17, y: (bounds.height - 14) / 2, width: 14, height: 14)
        NSColor.white.setFill(); NSBezierPath(ovalIn: radio).fill()
        if state == .on {
            NSColor(parcHex: "684AF5").setFill(); NSBezierPath(ovalIn: radio.insetBy(dx: 3, dy: 3)).fill()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7)]
        let text = title.uppercased() as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(in: NSRect(x: 45, y: (bounds.height - size.height) / 2,
                            width: max(0, bounds.width - 99), height: size.height), withAttributes: attributes)
    }
}
