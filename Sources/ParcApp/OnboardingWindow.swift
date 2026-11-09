import AppKit
import UniformTypeIdentifiers
import AVFoundation
import QuartzCore
import SwiftUI

@MainActor
final class OnboardingWindow: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    enum Mode { case firstLaunch, replay(spaceID: UUID, resuming: OnboardingDraft? = nil) }
    private let mode: Mode
    private var isReplay: Bool { if case .replay = mode { return true }; return false }
    /// First launch creates a browser after setup commits; replay applies the
    /// same choices to its originating Space and returns to the existing browser.
    var onComplete: (() throws -> Void)?
    var onCancel: (() -> Void)?
    var onRevealCompleted: (() -> Void)?
    private var draft: OnboardingDraft
    private var isFinishing = false
    private var setupCommitted = false
    private var submittedICloudPasswords = false
    private var isClosed = false
    private var scheduledAdvance: DispatchWorkItem?
    private var musicPlayer: AVAudioPlayer?
    private var accessibilityObserver: NSObjectProtocol?
    private var extensionFailureObserver: NSObjectProtocol?
    private var musicPolicyObservers: [NSObjectProtocol] = []
    private var welcome: NSHostingView<OnboardingWelcomeView>?
    private let welcomeBackdrop = OnboardingBackdrop()
    private var background: NSHostingView<OnboardingBackgroundView>?
    private let setupCard = OnboardingSetupCard(frame: .zero)
    private let readyContent = OnboardingReadyContent(frame: .zero)
    private let confetti = OnboardingConfettiView(frame: .zero)
    private var lastStage: OnboardingDraft.Stage?
    private var transitionDirection: OnboardingExperience.TransitionDirection?
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private let store: BrowserStore
    private var browserImport: BrowserImportViewController?
    private var importFoundNoSources = false
    private var passwordHelp: OnboardingPasswordHelp?
    var onCancelImportRestart: (() -> Void)?
    var hasActiveBrowserImport: Bool { browserImport != nil && !isClosed && !isFinishing }
    var onRequestImportRestart: ((BrowserImportRestartIntent, @escaping (String?) -> Void) -> Void)?
    private let root = LayoutView()
    private var body: OnboardingSetupCard.Column { setupCard.content }
    private let next = OnboardingProgressionControl(frame: .zero)
    /// NewSetupView: `Image(systemName: "arrow.left") + Text(" Back")`, 13 pt medium.
    private let back: ActionButton = {
        let button = ActionButton("Back", symbol: "arrow.left")
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.image = button.image?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        return button
    }()
    private let skip = ActionButton("Skip for now")
    private let progress = NSTextField(labelWithString: "")
    private let persistenceStatus = NSTextField(labelWithString: "")
    private let spaceName = OnboardingSpaceNameField()
    private var spaceField: NSTextField { spaceName.field }
    private var selectedTheme: SpaceTheme
    private let themeEditor: SpaceThemeEditorView
    private let themeChrome: OnboardingThemeEditorChrome
    private let defaultBrowser = DefaultBrowserController.shared
    private var defaultChoice: NSHostingView<OnboardingDefaultBrowserChoice>?
    private var adBlockerHost: NSHostingView<OnboardingAdBlockersChoice>?
    private let favoritePicker = OnboardingFavoritesControl(frame: .zero)
    /// Replay's unsaved light/dark preview: saved on Finish, dropped otherwise.
    private var replayAppearance: AppAppearance?
    private var pendingReplayTheme: SpaceTheme?
    private var replayThemeFrame: DispatchWorkItem?
    /// Replay never removes tabs, so a Favorite the profile already has stays selected.
    private var replayExistingFavorites: Set<String> = []

    init(store: BrowserStore, mode: Mode = .firstLaunch) throws {
        self.store = store
        self.mode = mode
        switch mode {
        case .firstLaunch:
            // Save the initial Space identity before persisting a separate draft.
            try store.save()
            draft = try OnboardingDraft.load(directory: store.directory, space: store.activeSpace)
        case .replay(let spaceID, let resuming):
            let space = store.state.spaces.first { $0.id == spaceID } ?? store.activeSpace
            // Replay never loads or writes onboarding.json. Its draft lives in
            // this controller until Finish applies it to the originating Space.
            let existing = Set(store.state.tabs.filter {
                $0.profileID == space.profileID && $0.kind == .favorite && $0.archivedAt == nil
            }.map { OnboardingDraft.choiceURL(forSaved: $0.savedURL) })
            if let resuming { draft = resuming } else {
                draft = OnboardingDraft(spaceID: space.id, spaceName: space.name, theme: space.theme)
                draft.favoriteURLs = existing
                draft.replayBaseName = space.name
                draft.replayBaseTheme = store.savedTheme(of: space)
            }
            replayExistingFavorites = Set(existing.map(OnboardingDraft.favoriteKey))
        }
        selectedTheme = draft.theme
        themeEditor = SpaceThemeEditorView(theme: draft.theme)
        themeChrome = OnboardingThemeEditorChrome(editor: themeEditor)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.welcomeSize(on: NSScreen.main)), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        if case .replay = mode { window.title = "Replay onboarding" }
        else { window.title = "Welcome to Parc" }
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = false; window.isMovable = false
        window.isMovableByWindowBackground = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenNone]
        window.animationBehavior = .none
        super.init(window: window)
        window.delegate = self
        window.contentView = root
        themeEditor.onPreview = { [weak self] theme in
            guard let self else { return }
            self.selectedTheme = theme
            self.draft.theme = theme; self.persistDraft()
            self.scheduleReplayThemePreview(theme)
            self.applySetupPalette()
        }
        themeEditor.onCommit = { [weak self] theme in
            guard let self else { return }
            self.selectedTheme = theme; self.draft.theme = theme; self.persistDraft()
            self.previewReplayTheme(theme)
            self.applySetupPalette()
        }
        themeEditor.onSetAppearance = { [weak self] appearance in
            guard let self, !self.isClosed, !self.isFinishing, self.draft.stage == .theme,
                  self.window?.attachedSheet == nil else { return }
            if self.isReplay { self.previewReplayAppearance(appearance) } else { AppAppearance.apply(appearance) }
        }
        root.addSubview(setupCard)
        root.addSubview(confetti)
        root.addSubview(persistenceStatus)
        confetti.isHidden = true
        next.actionBlock = { [weak self] in self?.advance() }
        favoritePicker.onToggle = { [weak self] choice in
            guard let self, !self.isClosed, !self.isFinishing,
                  self.draft.stage == .favorites else { return }
            if self.replayExistingFavorites.contains(choice.url), self.draft.isFavoriteSelected(choice) {
                NSSound.beep(); return
            }
            self.draft.toggleFavorite(choice)
            self.persistDraft()
            self.favoritePicker.configure(draft: self.draft, enabled: true)
        }
        back.actionBlock = { [weak self] in
            guard let self, !self.isFinishing,
                  self.window?.attachedSheet == nil, self.passwordHelp?.isPresented != true else { return }
            if let browserImport = self.browserImport { browserImport.goBack(); return }
            if let stage = self.draft.previousStage() { self.transition(to: stage) }
        }
        skip.actionBlock = { [weak self] in self?.skipStep() }
        progress.font = .systemFont(ofSize: 10, weight: .medium); progress.textColor = OnboardingSetupPalette.message; progress.alignment = .center
        persistenceStatus.font = .systemFont(ofSize: 11)
        persistenceStatus.textColor = .systemRed
        persistenceStatus.alignment = .right
        spaceField.stringValue = draft.spaceName
        spaceField.delegate = self
        root.onLayout = { [weak self] in
            guard let self else { return }
            self.background?.frame = self.root.bounds
            self.welcome?.frame = self.root.bounds
            self.passwordHelp?.frame = self.root.bounds
            self.setupCard.frame = OnboardingSetupLayout.frame(in: self.root.bounds)
            self.setupCard.setBoundsSize(OnboardingSetupLayout.size)
            self.setupCard.needsLayout = true
            self.confetti.frame = self.root.bounds
            self.persistenceStatus.frame = NSRect(x: 24, y: self.root.bounds.height - 36,
                width: self.root.bounds.width - 48, height: 22)
        }
        observeMusicPolicy()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.reduceMotion { self.welcomeBackdrop.cancel() }
                    self.render()
                }
            }
        extensionFailureObserver = NotificationCenter.default.addObserver(
            forName: ImportedExtensionFailures.didFail, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dropFailedAdBlockers() }
            }
        render()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present() {
        guard !isClosed else { return }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if draft.stage.isWelcome {
            // An interrupted welcome replays from its beginning; setup resumes.
            startWelcome()
        } else if draft.stage == .bookmarks { beginBrowserImport() }
        if !draft.stage.isWelcome {
            previewReplayTheme(draft.theme)
            if let raw = draft.replayAppearance, let appearance = AppAppearance(rawValue: raw) {
                previewReplayAppearance(appearance)
            }
        }
    }

    func resume() { window?.deminiaturize(nil); window?.makeKeyAndOrderFront(nil) }
    func suspend() {
        guard !isClosed else { return }
        captureDraft(); persistDraft()
        restoreReplayPreview()
        scheduledAdvance?.cancel(); scheduledAdvance = nil
        applyMusicPolicy(.close)
        confetti.stop()
        readyContent.cancelPresentation()
        welcomeBackdrop.cancel()
        welcome?.removeFromSuperview(); welcome = nil
        background?.removeFromSuperview(); background = nil
    }

    /// Every browser window showing the originating Space repaints with the
    /// replay theme; the session keeps the saved theme until Finish.
    private func previewReplayTheme(_ theme: SpaceTheme) {
        replayThemeFrame?.cancel(); replayThemeFrame = nil; pendingReplayTheme = nil
        guard isReplay, !isClosed, !setupCommitted else { return }
        store.previewSpaceTheme(draft.spaceID, theme: theme)
    }

    /// A continuous drag republishes the store at most every 50 ms; the setup
    /// card itself follows every frame.
    private func scheduleReplayThemePreview(_ theme: SpaceTheme) {
        guard isReplay else { return }
        pendingReplayTheme = theme
        guard replayThemeFrame == nil else { return }
        let frame = DispatchWorkItem { [weak self] in
            guard let self, let theme = self.pendingReplayTheme else { return }
            self.previewReplayTheme(theme)
        }
        replayThemeFrame = frame
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: frame)
    }

    private func previewReplayAppearance(_ appearance: AppAppearance) {
        guard isReplay, !isClosed, !setupCommitted else { return }
        AppAppearance.preview(appearance)
        replayAppearance = appearance; draft.replayAppearance = appearance.rawValue
    }

    /// An unfinished replay applies nothing: drop the theme and light/dark
    /// previews, unless something else has replaced them meanwhile.
    private func restoreReplayPreview() {
        guard isReplay, !setupCommitted else { return }
        replayThemeFrame?.cancel(); replayThemeFrame = nil; pendingReplayTheme = nil
        store.endSpaceThemePreview(draft.spaceID)
        if let appearance = replayAppearance { AppAppearance.endPreview(appearance) }
        replayAppearance = nil
    }

    /// Saved before a Safari restart so relaunch reopens this replay at its import.
    func saveReplayForImportRestart() throws {
        guard isReplay, !isClosed, !isFinishing else { throw CocoaError(.userCancelled) }
        captureDraft()
        try draft.save(directory: store.directory, fileName: OnboardingDraft.replayRestartFileName)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isFinishing, sender.attachedSheet == nil else { return false }
        closeBrowserImport(); suspend(); isClosed = true
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        accessibilityObserver = nil
        if let extensionFailureObserver { NotificationCenter.default.removeObserver(extensionFailureObserver) }
        extensionFailureObserver = nil
        for observer in musicPolicyObservers { NotificationCenter.default.removeObserver(observer) }
        musicPolicyObservers = []
        onCancel?()
        return true
    }

    func controlTextDidChange(_ obj: Notification) { draft.spaceName = spaceField.stringValue; persistDraft() }

    private func captureDraft() {
        themeEditor.finishEditing()
        draft.spaceName = spaceField.stringValue; draft.theme = selectedTheme
    }

    private func persistDraft() {
        guard !isReplay else { return }
        do {
            try draft.save(directory: store.directory)
            persistenceStatus.stringValue = ""
        } catch {
            persistenceStatus.stringValue = "Setup couldn’t be saved. Keep this window open and try again."
            persistenceStatus.toolTip = error.localizedDescription
            NSLog("Parc setup draft could not be saved: %@", error.localizedDescription)
        }
    }

    private func startWelcome() {
        scheduledAdvance?.cancel()
        welcome?.removeFromSuperview(); welcome = nil
        background?.removeFromSuperview(); background = nil
        if let window { welcomeBackdrop.start(behind: window, reduceMotion: reduceMotion) }
        applyMusicPolicy(.replay)
        applyMusicPolicy(.startWelcome)
        transition(to: .introAnimation)
        // Welcome-phase advances leave focus unchanged. Rebuilding the host
        // (first present, restart, replay) still has to focus it.
        if let welcome, let window, window.isKeyWindow, window.attachedSheet == nil {
            window.makeFirstResponder(welcome)
        }
    }

    private func transition(to stage: OnboardingDraft.Stage) {
        guard !isFinishing, !isClosed, browserImport == nil else { return }
        scheduledAdvance?.cancel(); scheduledAdvance = nil
        captureDraft()
        let previous = draft.stage
        transitionDirection = OnboardingExperience.direction(from: previous, to: stage)
        draft.stage = stage; persistDraft()
        // The single music cue belongs to the onboarding owner, not a welcome
        // phase. Let it finish naturally while setup continues; close, finish
        // and an explicit replay still stop or replace it.
        applyMusicPolicy(.changeStage)
        if !stage.isWelcome { welcomeBackdrop.welcomeEnded() }
        if stage == .bookmarks { beginBrowserImport() }
        render(from: previous)
        let delay: TimeInterval?
        switch stage {
        case .introAnimation: delay = OnboardingDraft.introDuration
        case .sellIntro: delay = OnboardingDraft.sellDuration
        default: delay = nil
        }
        if let delay {
            let task = DispatchWorkItem { [weak self] in
                guard let self, self.draft.stage == stage, !self.isClosed else { return }
                self.advance()
            }
            scheduledAdvance = task
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
        }
    }

    private func render(from previous: OnboardingDraft.Stage? = nil) {
        let outgoingText = stepTextSnapshot()
        if browserImport?.canShowPasswordHelp != true { dismissPasswordHelp() }
        themeEditor.finishEditing()
        let previousResponder = window?.firstResponder
        let entering = previous ?? lastStage
        let isWelcome = draft.stage.isWelcome
        // UnboxingView owns one background and one window across every stage.
        // Do not turn setup into a smaller, Space-colored dialog.
        if let background {
            background.rootView = OnboardingBackgroundView(reduceMotion: reduceMotion,
                startsSettled: background.rootView.startsSettled)
        } else {
            let host = NSHostingView(rootView: OnboardingBackgroundView(
                reduceMotion: reduceMotion, startsSettled: !isWelcome))
            background = host
            root.addSubview(host, positioned: .below, relativeTo: setupCard)
        }
        applySetupPalette()
        if !draft.stage.isWelcome, let leaving = welcome {
            welcome = nil
            //
            if reduceMotion {
                leaving.removeFromSuperview()
            } else {
                leaving.rootView.isLeaving = true
                leaving.wantsLayer = true
                CATransaction.begin()
                CATransaction.setCompletionBlock { leaving.removeFromSuperview() }
                // Explicit from-values: the hidden card's committed opacity is already 1.
                for (view, from) in [(leaving as NSView, 1.0), (setupCard, 0.0)] {
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = from; fade.toValue = 1 - from
                    fade.duration = 0.2
                    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    view.layer?.add(fade, forKey: "welcomeHandoff")
                }
                leaving.alphaValue = 0
                CATransaction.commit()
            }
        }
        setupCard.isHidden = draft.stage.isWelcome
        if draft.stage.isWelcome {
            back.isHidden = true; skip.isHidden = true; progress.isHidden = true
            next.isHidden = true
            let content = OnboardingWelcomeView(stage: draft.stage, reduceMotion: reduceMotion,
                onContinue: { [weak self] in self?.advance(leavingWelcome: true) })
            if let welcome {
                welcome.rootView = content
            } else {
                let host = NSHostingView(rootView: content)
                self.welcome = host
                root.addSubview(host, positioned: .below, relativeTo: setupCard)
            }
            root.needsLayout = true
            confetti.stop(); confetti.isHidden = true
            restoreFocus(from: entering, previousResponder: previousResponder)
            announceStageIfNeeded(from: entering)
            lastStage = draft.stage
            return
        }
        progress.isHidden = false
        next.isHidden = false
        let themeWasVisible = themeChrome.superview === body
        let retainedImport = draft.stage == .bookmarks ? browserImport?.view : nil
        body.subviews.filter { $0 !== retainedImport }.forEach { $0.removeFromSuperview() }
        defaultChoice = nil
        adBlockerHost = nil
        body.onLayout = nil
        if let browserImport, draft.stage == .bookmarks {
            renderBrowserImport(browserImport)
            animateStepChange(from: outgoingText)
            confetti.stop(); confetti.isHidden = true
            restoreFocus(from: entering, previousResponder: previousResponder)
            announceStageIfNeeded(from: entering)
            lastStage = draft.stage
            return
        }
        let order = draft.visibleSetupOrder()
        let ordinal = order.firstIndex(of: draft.stage.current) ?? 0
        let isReady = draft.stage == .ready
        progress.stringValue = (isReplay ? "Replay · " : "") + (isReady ? "Ready" : "\(ordinal + 1) of \(draft.displayedSetupCount())")
        // Back from the first step after an import that found no browsers
        // would only reopen it and bounce here again.
        back.isHidden = isReady || draft.previousStage() == nil
            || (importFoundNoSources && draft.previousStage()?.current == .bookmarks)
        skip.title = "Skip for now"
        skip.isHidden = ![.theme, .favorites, .bookmarks, .adBlockers].contains(draft.stage.current)
        let canAdvance = browserImport == nil
        next.isEnabled = canAdvance; next.isLoading = false; back.isEnabled = canAdvance; skip.isEnabled = canAdvance
        next.title = isReady ? (isReplay ? "Finish replay" : "Get Started") : "Next"
        if isReady {
            readyContent.attach(store: MembershipCardStore.shared(directory: store.directory, name: NSFullUserName()))
        }
        let title: String
        let subtitle: String
        switch draft.stage.current {
        case .theme:
            title = "Add some flair with a theme."
            subtitle = "Pick a color, any color—add your favorite shade to your new home on the internet."
        case .favorites:
            title = "Choose the apps you use most."
            subtitle = "Select your favorite apps to keep them handy in your sidebar."
        case .defaultBrowser:
            title = "Go steady with Parc?"
            subtitle = "Make Parc your default browser so links open here. We’ll treat your links nicely—you won’t regret it, we promise!"
        case .adBlockers:
            title = "No more ads or trackers."
            subtitle = "We include an ad blocker so you don’t need to worry about invasive trackers or intrusive pop-ups."
        case .ready:
            title = OnboardingExperience.readyTitle(cardName: readyContent.cardName)
            subtitle = OnboardingExperience.readyDescription
        default:
            title = "Treat your bookmarks to an upgrade."
            subtitle = "Bring your browsing from another browser.\nChoose the bookmarks you want to keep in your sidebar."
        }
        setupCard.configure(title: title, subtitle: subtitle,
            font: NSFontManager.shared.convert(OnboardingArtwork.headlineFont, toSize: 35),
            back: back, next: next, skip: skip, progress: progress,
            accessory: draft.stage == .theme ? spaceName : nil,
            accessoryHeight: draft.stage == .theme ? OnboardingThemeEditorLayout.spaceNameHeight : 30)
        var lower: [NSView] = []
        let stage = draft.stage.current
        if stage == .theme {
            if OnboardingThemeEditorLayout.shouldAnimateAppearance(alreadyVisible: themeWasVisible) {
                themeChrome.prepareAppearance(reduceMotion: reduceMotion)
            }
            lower = [themeChrome]
        } else if stage == .favorites {
            favoritePicker.configure(draft: draft, enabled: canAdvance)
            lower = [favoritePicker]
        } else if stage == .defaultBrowser {
            let host = NSHostingView(rootView: defaultBrowserChoices())
            defaultChoice = host
            lower = [host]
        } else if stage == .adBlockers {
            //
            skip.title = "Use all imported ad blockers"
            skip.isHidden = draft.importedAdBlockers.isEmpty
            if draft.adBlockerChoice == nil, let first = draft.importedAdBlockers.first {
                draft.adBlockerChoice = .keep(first.identifier)
                persistDraft()
            }
            let host = NSHostingView(rootView: adBlockerChoices())
            adBlockerHost = host
            lower = [host]
        } else if stage == .ready {
            lower = [readyContent]
        } else {
            let importBrowser = ActionButton("Import from another browser…", symbol: "arrow.down.to.line") { [weak self] in self?.beginBrowserImport() }
            importBrowser.isBordered = true; importBrowser.bezelStyle = .rounded
            importBrowser.isEnabled = browserImport == nil
            lower = [importBrowser]
        }
        lower.forEach { body.addSubview($0) }
        let current = stage
        let adBlockerCount = draft.importedAdBlockers.count
        body.onLayout = { [weak self] in
            guard let self else { return }
            let width = self.body.bounds.width
            let height = self.body.bounds.height
            if current == .theme {
                self.themeChrome.applyFrame(in: self.body.bounds)
            } else if current == .favorites {
                lower[0].frame = self.body.bounds
            } else if current == .defaultBrowser {
                lower[0].frame = NSRect(x: (width - 339) / 2, y: (height - 156) / 2,
                    width: 339, height: 156)
            } else if current == .adBlockers {
                let rows = CGFloat(adBlockerCount + 1)
                let hostHeight = rows * 67 + max(0, rows - 1) * 22
                lower[0].frame = NSRect(x: (width - 339) / 2, y: (height - hostHeight) / 2,
                    width: 339, height: hostHeight)
            } else if current == .bookmarks {
                lower[0].frame = NSRect(x: width / 2 - 150, y: height / 2 - 18, width: 300, height: 36)
            } else {
                lower[0].frame = self.body.bounds
            }
        }
        root.needsLayout = true; body.needsLayout = true
        applySetupPalette()
        if stage == .theme,
           OnboardingThemeEditorLayout.shouldAnimateAppearance(alreadyVisible: themeWasVisible) {
            themeChrome.playAppearance(reduceMotion: reduceMotion)
        }
        animateStepChange(from: outgoingText)
        updateConfetti(from: entering)
        restoreFocus(from: entering, previousResponder: previousResponder)
        announceStageIfNeeded(from: entering)
        lastStage = draft.stage
    }
    private static func welcomeSize(on screen: NSScreen?) -> NSSize {
        guard let screen else { return NSSize(width: 1_280, height: 800) }
        let size = screen.frame.size
        let regular = size.width > 1_280 || size.height > 800
        let reference = regular ? NSSize(width: 1_280, height: 800)
            : NSSize(width: size.width - 72, height: size.height - 72)
        // Keep the recovered dimensions on ordinary screens, but fit unusually
        // narrow displays and available work areas rather than hiding controls.
        return NSSize(width: min(reference.width, screen.visibleFrame.width),
                      height: min(reference.height, screen.visibleFrame.height - 28))
    }

    private func observeMusicPolicy() {
        let center = NotificationCenter.default
        let names: [(Notification.Name, OnboardingExperience.MusicEvent)] = [
            (NSApplication.didResignActiveNotification, .resignActive),
            (NSApplication.didBecomeActiveNotification, .becomeActive),
            (NSApplication.willTerminateNotification, .terminate)
        ]
        for (name, event) in names {
            musicPolicyObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyMusicPolicy(event) }
            })
        }
    }

    func windowDidResignKey(_ notification: Notification) { applyMusicPolicy(.resignKey); updateGrainActivity() }
    func windowDidBecomeKey(_ notification: Notification) { applyMusicPolicy(.becomeKey); updateGrainActivity() }
    func windowDidResignMain(_ notification: Notification) { updateGrainActivity() }
    func windowDidBecomeMain(_ notification: Notification) { updateGrainActivity() }
    private func updateGrainActivity() { setupCard.grainIsActive = ThemeWindowActivity.isActive(window) }

    private func applyMusicPolicy(_ event: OnboardingExperience.MusicEvent) {
        if OnboardingExperience.shouldStopMusic(on: event) {
            musicPlayer?.stop(); musicPlayer = nil
            return
        }
        if OnboardingExperience.shouldPauseOrMute(on: event) {
            musicPlayer?.pause()
            return
        }
        guard OnboardingExperience.shouldStartMusic(on: event) else { return }
        guard musicPlayer == nil else { return }
        if let url = Bundle.main.url(forResource: "intro-music", withExtension: "mp3", subdirectory: "Onboarding") {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = 0.3; player.numberOfLoops = 0
                player.prepareToPlay(); player.play(); musicPlayer = player
            } catch { NSLog("Parc welcome audio could not play: %@", error.localizedDescription) }
        }
    }

    /// The outgoing heading and message, taken before a directed step change
    /// replaces them.
    private func stepTextSnapshot() -> OnboardingSetupCard.TextSnapshot? {
        guard transitionDirection != nil, !draft.stage.isWelcome,
              OnboardingExperience.StepMotion.slidesText(reduceMotion: reduceMotion) else { return nil }
        return setupCard.captureText()
    }

    private func animateStepChange(from outgoingText: OnboardingSetupCard.TextSnapshot?) {
        let direction = transitionDirection
        transitionDirection = nil
        guard let direction, !draft.stage.isWelcome else { return }
        setupCard.animateStepChange(from: outgoingText, direction: direction,
            slides: OnboardingExperience.StepMotion.slidesText(reduceMotion: reduceMotion),
            fades: OnboardingExperience.StepMotion.fadesContent(reduceMotion: reduceMotion))
    }

    ///
    /// window-level overlay does; only a burst still waiting is cancelled.
    private func updateConfetti(from previous: OnboardingDraft.Stage?) {
        if draft.stage != .ready { readyContent.cancelPresentation() }
        guard OnboardingExperience.shouldPlayConfetti(reduceMotion: reduceMotion) else {
            confetti.stop(); confetti.isHidden = true; return
        }
        confetti.isHidden = false
        if draft.stage != .ready { confetti.cancelPending() }
        else if previous != .ready { confetti.fire(after: OnboardingExperience.readyConfettiDelay) }
    }

    ///
    func handleCloseCommand() -> Bool {
        guard passwordHelp?.isPresented == true else { return false }
        dismissPasswordHelp()
        return true
    }

    private func restoreFocus(from previous: OnboardingDraft.Stage?, previousResponder: NSResponder?) {
        if !draft.stage.isWelcome {
            // Back, the step's own controls, Skip, then Next. Hosted SwiftUI
            //
            typealias Segment = (first: NSView, link: (NSView) -> Void)
            func views(_ list: [NSView]) -> [Segment] { list.map { view in (view, { view.nextKeyView = $0 }) } }
            var loop = views(back.isHidden ? [] : [back])
            switch draft.stage.current {
            case .theme:
                loop += views([spaceField])
                loop.append((themeEditor.firstKeyView, { self.themeEditor.chainKeyViews(to: $0) }))
            case .favorites: loop += views([favoritePicker.keyboardView])
            case .defaultBrowser: loop += views(defaultChoice.map { [$0] } ?? [])
            case .adBlockers: loop += views(adBlockerHost.map { [$0] } ?? [])
            case .ready: loop.append((readyContent.firstKeyView, { self.readyContent.chainKeyViews(to: $0) }))
            default:
                if let browserImport {
                    loop += views(BrowserImportFocus.keyViews(in: [browserImport.setupAccessory, browserImport.view].compactMap { $0 }))
                } else {
                    loop += views(body.subviews)
                }
            }
            loop += views((skip.isHidden ? [] : [skip]) + [next.keyboardView])
            for (segment, following) in zip(loop, loop.dropFirst() + loop.prefix(1)) { segment.link(following.first) }
        }
        guard let window, window.isKeyWindow, window.attachedSheet == nil,
              passwordHelp?.isPresented != true, !isFinishing else { return }
        switch OnboardingExperience.focusTarget(entering: draft.stage, from: previous) {
        case .welcome:
            if let welcome { window.makeFirstResponder(welcome) }
        case .spaceName:
            window.makeFirstResponder(spaceField)
        case .next:
            window.makeFirstResponder(next.keyboardView)
        case .unchanged:
            // An import page change can hide the control that had focus (Back
            // on the browser cards); Next takes it then.
            if let view = previousResponder as? NSView, view.window === window, view.acceptsFirstResponder {
                window.makeFirstResponder(view.isHiddenOrHasHiddenAncestor ? next.keyboardView : view)
            }
        }
    }

    private func announceStageIfNeeded(from previous: OnboardingDraft.Stage?) {
        guard previous != draft.stage else { return }
        let element: Any = draft.stage.isWelcome ? (welcome ?? root) : setupCard.heading
        NSAccessibility.post(element: element, notification: .layoutChanged)
    }

    private func applySetupPalette() {
        let palette = ThemeChromePalette(theme: selectedTheme, appearance: root.effectiveAppearance)
        setupCard.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        // NewSetupView's style getter consumes SpaceStyleEditorState.windowTheme;
        // Card reads semantic backgroundExtra (+0xb0), not the window gradient.
        setupCard.themeBackground = selectedTheme.isValid && selectedTheme.primaryColor != nil
            ? palette.backgroundExtra : nil
        setupCard.grainTheme = selectedTheme
        setupCard.grainIsActive = ThemeWindowActivity.isActive(window)
        let backdrop = draft.stage == .bookmarks ? browserImport?.backdrop : nil
        setupCard.backdrop.show(backdrop?.pages ?? [], selected: backdrop?.selected)
        setupCard.importInk = backdrop != nil
        setupCard.textSpansCard = browserImport?.isSafariPasswords == true
        progress.textColor = setupCard.chromeColor
        persistenceStatus.textColor = draft.stage.isWelcome ? .white : .systemRed
        // ProgressionButton's theme getters select maxContrastColor (+0x70)
        // and backgroundExtra (+0xb0). Unthemed setup uses AuthFeature assets.
        let hasTheme = selectedTheme.isValid && selectedTheme.primaryColor != nil
        next.configure(background: hasTheme ? palette.maxContrastColor : OnboardingSetupPalette.action,
                       foreground: hasTheme ? palette.backgroundExtra : .white,
                       reduceMotion: reduceMotion)
        spaceName.updateColors()
        for button in [back, skip] { button.contentTintColor = setupCard.chromeColor }
        for view in body.subviews + setupCard.instructions.subviews {
            if let label = view as? NSTextField, label !== spaceField {
                label.textColor = label === setupCard.heading ? setupCard.titleColor : label === setupCard.message
                    ? setupCard.messageColor : (label.font?.pointSize ?? 14) >= 17 ? OnboardingSetupPalette.title : setupCard.chromeColor
            } else if let button = view as? ActionButton {
                button.contentTintColor = OnboardingSetupPalette.title
            }
        }
    }
    private func advance(leavingWelcome: Bool = false) {
        guard !isFinishing, !isClosed,
              window?.attachedSheet == nil, passwordHelp?.isPresented != true else { return }
        if leavingWelcome {
            if let target = OnboardingExperience.welcomeContinueTarget(from: draft.stage) { transition(to: target) }
            return
        }
        if let browserImport { browserImport.advance(); return }
        if draft.stage == .ready { finish(); return }
        //
        // at once. The shared request starts nothing when Parc is already
        // default or one is in flight, and keeps its outcome for Settings.
        if draft.stage == .defaultBrowser, draft.wantsDefaultBrowser { defaultBrowser.makeDefault() }
        if let next = draft.nextStage() { transition(to: next) }
    }

    private func defaultBrowserChoices() -> OnboardingDefaultBrowserChoice {
        let palette = ThemeChromePalette(theme: selectedTheme, appearance: root.effectiveAppearance)
        return OnboardingDefaultBrowserChoice(selected: draft.wantsDefaultBrowser,
            selectionColor: selectedTheme.primaryColor == nil ? OnboardingSetupPalette.action : palette.maxContrastColor,
            onSelect: { [weak self] choice in
                guard let self, !self.isClosed, !self.isFinishing,
                      self.draft.stage == .defaultBrowser,
                      let window = self.window, window.isKeyWindow, window.attachedSheet == nil else { return }
                self.draft.defaultBrowserChoice = choice
                self.persistDraft()
                self.defaultChoice?.rootView = self.defaultBrowserChoices()
            })
    }

    private func adBlockerChoices() -> OnboardingAdBlockersChoice {
        let palette = ThemeChromePalette(theme: selectedTheme, appearance: root.effectiveAppearance)
        return OnboardingAdBlockersChoice(blockers: draft.importedAdBlockers, choice: draft.adBlockerChoice,
            enabled: true,
            selectionColor: selectedTheme.primaryColor == nil ? OnboardingSetupPalette.action : palette.maxContrastColor,
            onSelect: { [weak self] choice in
                guard let self, !self.isClosed, !self.isFinishing,
                      self.draft.stage == .adBlockers,
                      let window = self.window, window.isKeyWindow, window.attachedSheet == nil else { return }
                self.draft.adBlockerChoice = choice
                self.persistDraft()
                self.adBlockerHost?.rootView = self.adBlockerChoices()
            })
    }

    private func finish() {
        guard !isFinishing, !isClosed, browserImport == nil else { return }
        captureDraft(); persistDraft()
        isFinishing = true; next.isEnabled = false; back.isEnabled = false
        do {
            if !setupCommitted {
                replayThemeFrame?.cancel(); replayThemeFrame = nil
                if isReplay { try store.applyOnboardingReplay(draft) } else { try store.completeOnboarding(draft) }
                setupCommitted = true
                if let appearance = replayAppearance, AppAppearance.current == appearance { AppAppearance.apply(appearance) }
            }
            // Keep the setup window visible if the native browser cannot be
            // created. Retrying is idempotent because completion is persisted.
            guard let onComplete else { throw CocoaError(.featureUnsupported) }
            try onComplete()
            if !submittedICloudPasswords, let profileID = draft.iCloudPasswordsProfileID,
               BrowserImportDestination(spaceID: draft.spaceID, profileID: profileID).isCurrent(in: store.state) {
                submittedICloudPasswords = true
                // This is the accepted setup choice, after successful browser
                // preparation. Native completion outlives the welcome window.
                PCNativeBrowserApplication.installICloudPasswordsExtension(
                    toProfilePath: store.independentEngineProfilePath(for: profileID)) { error in
                        if let error { NSLog("Parc could not install the selected iCloud Passwords extension: %@", error.localizedDescription) }
                    }
            }
            scheduledAdvance?.cancel(); scheduledAdvance = nil
            applyMusicPolicy(.finish)
            confetti.stop()
            readyContent.cancelPresentation()
            welcomeBackdrop.cancel()
            if !isReplay { try? OnboardingDraft.remove(directory: store.directory) }
            if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
            accessibilityObserver = nil
            if let extensionFailureObserver { NotificationCenter.default.removeObserver(extensionFailureObserver) }
            extensionFailureObserver = nil
            for observer in musicPolicyObservers { NotificationCenter.default.removeObserver(observer) }
            musicPolicyObservers = []
            welcome?.removeFromSuperview(); welcome = nil
            background?.removeFromSuperview(); background = nil
            isClosed = true
            // UnboxingManager closes its retained controller directly. Prepare
            // the local browser first, close this owner, then hand back focus.
            // There is no additional closing animation or delayed callback.
            close()
            onRevealCompleted?()
        } catch {
            isFinishing = false; next.isEnabled = true
            back.isEnabled = !setupCommitted
            if setupCommitted, !isReplay { next.title = "Open Parc" }
            if let window {
                let alert = NSAlert(error: error)
                alert.messageText = !isReplay ? "Parc couldn’t finish setup."
                    : setupCommitted ? "Parc couldn’t return to browsing." : "Parc couldn’t apply your onboarding choices."
                alert.beginSheetModal(for: window)
            }
        }
    }

    private func captureBrowserImportResults() {
        guard let importer = browserImport else { return }
        if let profileID = importer.acceptedICloudPasswordsDestination?.profileID {
            draft.iCloudPasswordsProfileID = profileID
        }
        if importer.importReachedCompletion {
            draft.importedAdBlockers = importer.importedAdBlockers.filter {
                !ImportedExtensionFailures.failedIdentifiers.contains($0.identifier)
            }
            settleAdBlockerChoice()
        }
        persistDraft()
    }

    /// Extensions finish after setup moved on; their ad blockers still reach
    /// the ad-blocker step while setup hasn't passed it.
    private func adoptBackgroundAdBlockers(_ blockers: [OnboardingDraft.ImportedAdBlocker]) {
        let order = OnboardingDraft.Stage.setupOrder(includingAdBlockers: true, retaining: draft.stage.current)
        guard !isClosed, !isFinishing, let here = order.firstIndex(of: draft.stage.current),
              let step = order.firstIndex(of: .adBlockers), here <= step else { return }
        draft.importedAdBlockers = blockers.filter { !ImportedExtensionFailures.failedIdentifiers.contains($0.identifier) }
        settleAdBlockerChoice(); persistDraft(); render()
    }

    private func settleAdBlockerChoice() {
        if let kept = draft.adBlockerChoice?.keptIdentifier,
           !draft.importedAdBlockers.contains(where: { $0.identifier == kept }) {
            draft.adBlockerChoice = nil
        }
        if draft.adBlockerChoice == nil, let first = draft.importedAdBlockers.first {
            draft.adBlockerChoice = .keep(first.identifier)
        }
    }

    /// An imported ad blocker whose download later failed isn't offered.
    private func dropFailedAdBlockers() {
        guard !isClosed, !isFinishing else { return }
        let before = draft.importedAdBlockers.count
        draft.importedAdBlockers.removeAll { ImportedExtensionFailures.failedIdentifiers.contains($0.identifier) }
        guard draft.importedAdBlockers.count != before else { return }
        settleAdBlockerChoice()
        persistDraft()
        if draft.stage == .adBlockers { adBlockerHost?.rootView = adBlockerChoices() }
    }

    func closeBrowserImport() {
        dismissPasswordHelp(remove: true)
        let importer = browserImport; browserImport = nil
        importer?.cancel(); importer?.view.removeFromSuperview()
        setupCard.backdrop.show([], selected: nil)
        onCancelImportRestart?()
    }

    private func skipStep() {
        guard !isClosed, !isFinishing,
              window?.attachedSheet == nil, passwordHelp?.isPresented != true else { return }
        if let browserImport {
            // Each import page's skip moves through the import; its end closes it.
            if browserImport.isImporting { browserImport.stopImport() } else { browserImport.skip() }
            return
        }
        if draft.stage == .theme {
            themeEditor.finishEditing()
            draft.theme = selectedTheme
            draft.skipTheme(replayBase: !isReplay ? nil : draft.replayBaseTheme
                ?? store.state.spaces.first { $0.id == draft.spaceID }.map(store.savedTheme(of:)))
            themeEditor.resetTheme(draft.theme)
            selectedTheme = draft.theme; persistDraft()
            previewReplayTheme(draft.theme)
            applySetupPalette()
        } else if draft.stage == .favorites {
            draft.skipFavorites(keeping: isReplay ? replayExistingFavorites : [])
            persistDraft()
        }
        if let next = draft.nextStage() { transition(to: next) }
    }

    func resumeSafariImport(destination: BrowserImportDestination,
                            sourceBundleID: String = "com.apple.Safari") {
        guard !isClosed, !isFinishing, draft.stage == .bookmarks,
              draft.spaceID == destination.spaceID, destination.isCurrent(in: store.state) else { return }
        beginBrowserImport()
        browserImport?.resumeSafariImport(sourceBundleID: sourceBundleID)
    }

    private func beginBrowserImport() {
        guard !isClosed, !isFinishing, draft.stage == .bookmarks,
              browserImport == nil, let window,
              let space = store.state.spaces.first(where: { $0.id == draft.spaceID }) else { return }
        let destination = BrowserImportDestination(spaceID: space.id, profileID: space.profileID)
        draft.iCloudPasswordsProfileID = nil; persistDraft()
        let controller = BrowserImportViewController(store: store, destination: destination, window: window,
            onboarding: true, ownerIsCurrent: { [weak self] in
                guard let self else { return false }
                return !self.isClosed && !self.isFinishing && self.draft.stage == .bookmarks
            })
        controller.onClose = { [weak self, weak controller] in
            guard let self, !self.isClosed, !self.isFinishing else { return }
            if controller?.foundNoSources == true { self.importFoundNoSources = true }
            self.captureBrowserImportResults()
            self.closeBrowserImport()
            if let next = self.draft.nextStage() { self.transition(to: next) }
        }
        controller.onChange = { [weak self, weak controller] in
            guard let self else { return }
            if let direction = controller?.pageDirection { self.transitionDirection = direction }
            self.render()
        }
        controller.onShowPasswordHelp = { [weak self] in self?.showPasswordHelp() }
        controller.onHidePasswordHelp = { [weak self] in self?.dismissPasswordHelp(remove: true) }
        controller.onBackgroundAdBlockers = { [weak self] in self?.adoptBackgroundAdBlockers($0) }
        controller.onRequestRestart = { [weak self] intent, completion in
            guard let self, let restart = self.onRequestImportRestart else {
                completion("Parc could not prepare to restart."); return
            }
            restart(intent, completion)
        }
        browserImport = controller
        controller.start()
    }

    private func showPasswordHelp() {
        guard !isClosed, !isFinishing, browserImport?.canShowPasswordHelp == true,
              window?.attachedSheet == nil else { return }
        let help: OnboardingPasswordHelp
        if let existing = passwordHelp { help = existing }
        else {
            help = OnboardingPasswordHelp(frame: root.bounds)
            help.onDismiss = { [weak self] in self?.setupCard.setAccessibilityHidden(false) }
            passwordHelp = help
            root.addSubview(help, positioned: .above, relativeTo: nil)
        }
        setupCard.setAccessibilityHidden(true)
        help.present()
    }

    private func dismissPasswordHelp(remove: Bool = false) {
        passwordHelp?.dismiss(animated: !remove)
        if remove {
            passwordHelp?.removeFromSuperview()
            passwordHelp = nil
        }
        setupCard.setAccessibilityHidden(false)
    }

    private func renderBrowserImport(_ importer: BrowserImportViewController) {
        let palette = ThemeChromePalette(theme: selectedTheme, appearance: root.effectiveAppearance)
        importer.selectionColor = selectedTheme.primaryColor == nil ? OnboardingSetupPalette.action : palette.maxContrastColor
        next.title = importer.nextTitle; next.isEnabled = importer.canAdvance; next.isLoading = importer.isLoading
        back.isHidden = !importer.canGoBack; back.isEnabled = true
        //
        skip.title = importer.isImporting ? "Stop Import" : importer.skipTitle ?? ""
        skip.isHidden = !importer.isImporting && importer.skipTitle == nil
        skip.isEnabled = importer.isImporting || importer.canSkip
        progress.stringValue = (isReplay ? "Replay · " : "") + "1 of \(draft.displayedSetupCount())"
        progress.isHidden = false; next.isHidden = false
        setupCard.isHidden = false
        setupCard.configure(title: importer.showsSourceCards ? "Get us up\nto speed." : importer.headingText,
            subtitle: importer.message,
            font: NSFontManager.shared.convert(OnboardingArtwork.headlineFont, toSize: 35),
            back: back, next: next, skip: skip, progress: progress, accessory: importer.setupAccessory,
            accessoryHeight: importer.isSafariAccess ? 148 : 30)
        if importer.view.superview !== body { body.addSubview(importer.view) }
        body.onLayout = { [weak self, weak importer] in
            guard let self, let importer else { return }
            let bounds = self.body.bounds
            let target = importer.usesFullSetupColumn ? bounds
                : importer.showsSourceCards ? NSRect(x: (bounds.width - 384) / 2, y: 0, width: 384, height: bounds.height)
                : NSRect(x: (bounds.width - 384) / 2, y: (bounds.height - 430) / 2, width: 384, height: 430)
            BrowserImportGeometry.resizeContent(importer.view, to: target)
        }
        root.needsLayout = true; body.needsLayout = true
        applySetupPalette()
        lastStage = draft.stage
    }
}
