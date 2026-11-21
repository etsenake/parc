import AppKit
import ParcCore
import UniformTypeIdentifiers
import AVFoundation
import QuartzCore
import SwiftUI

@MainActor
final class OnboardingWindow: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    enum Mode { case firstLaunch, replay(spaceID: UUID, resuming: OnboardingDraft? = nil) }
    private let mode: Mode
    private var isReplay: Bool { if case .replay = mode { return true }; return false }
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
    private let themePreview = ThemeRendererView(frame: .zero)
    private var appearanceObservation: NSKeyValueObservation?
    private let readyContent = OnboardingReadyContent(frame: .zero)
    private let confetti = OnboardingConfettiView(frame: .zero)
    private var lastStage: OnboardingDraft.Stage?
    private var transitionDirection: OnboardingExperience.TransitionDirection?
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private let store: BrowserStore
    private var browserImport: BrowserImportViewController?
    private var importFoundNoSources = false
    private var importHadStarted = false
    private var importInterrupted = false
    private var counterPage: OnboardingExperience.CounterPage?
    private var counterText = ""
    private var passwordHelp: OnboardingPasswordHelp?
    var onCancelImportRestart: (() -> Void)?
    var hasActiveBrowserImport: Bool { browserImport != nil && !isClosed && !isFinishing }
    var onRequestImportRestart: ((BrowserImportRestartIntent, @escaping (String?) -> Void) -> Void)?
    private let root = LayoutView()
    private var body: OnboardingSetupCard.Column { setupCard.content }
    private let next = OnboardingProgressionControl(frame: .zero)
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
    private var windowFrameStep: OnboardingWindowFrameStep?
    private var replayAppearance: AppAppearance?
    private var pendingReplayTheme: SpaceTheme?
    private var replayThemeFrame: DispatchWorkItem?
    private var replayExistingFavorites: Set<String> = []

    init(store: BrowserStore, mode: Mode = .firstLaunch) throws {
        self.store = store
        self.mode = mode
        switch mode {
        case .firstLaunch:
            try store.save()
            draft = try OnboardingDraft.load(directory: store.directory, space: store.activeSpace)
        case .replay(let spaceID, let resuming):
            let space = store.state.spaces.first { $0.id == spaceID } ?? store.activeSpace
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
        window.title = "Welcome to Parc"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = false; window.isMovable = false
        window.isMovableByWindowBackground = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenNone]
        window.animationBehavior = .none
        super.init(window: window)
        SetupExtensionChanges.beginSetupRun()
        window.delegate = self
        window.contentView = root
        themePreview.drawsMaterial = false
        setupCard.chrome.themeSurface = themePreview
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.applySetupPalette() }
        }
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
            self.applySetupPalette()
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
            switch OnboardingExperience.importBack(on: self.draft.stage, holdingImport: self.browserImport != nil,
                                                   returnsToSource: self.browserImport?.backReturnsToSource ?? true) {
            case .importPage: self.browserImport?.goBack()
            case .importSource:
                self.browserImport?.returnToSource()
                self.transition(to: .bookmarks)
            case .favorites: self.transition(to: .favorites)
            case .previousStage:
                self.captureWindowFrame()
                if let stage = self.draft.previousStage() { self.transition(to: stage) }
            }
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
            startWelcome()
        } else if draft.stage == .bookmarks { beginBrowserImport() }
        if !draft.stage.isWelcome {
            previewReplayTheme(draft.theme)
            if let raw = draft.replayAppearance, let appearance = AppAppearance(rawValue: raw) {
                previewReplayAppearance(appearance)
            }
        }
    }

    func resume() {
        window?.deminiaturize(nil); window?.makeKeyAndOrderFront(nil)
        guard !isClosed, !isFinishing, browserImport == nil, !draft.stage.isWelcome,
              importInterrupted || draft.stage == .bookmarks else { return }
        if draft.stage == .bookmarks { beginBrowserImport(); render() } else { transition(to: .bookmarks) }
    }
    func suspend() {
        guard !isClosed else { return }
        captureDraft(); persistDraft()
        restoreReplayPreview()
        scheduledAdvance?.cancel(); scheduledAdvance = nil
        applyMusicPolicy(.close)
        confetti.stop()
        readyContent.cancelPresentation()
        windowFrameStep?.end()
        welcomeBackdrop.cancel()
        welcome?.removeFromSuperview(); welcome = nil
        background?.removeFromSuperview(); background = nil
    }

    private func previewReplayTheme(_ theme: SpaceTheme) {
        replayThemeFrame?.cancel(); replayThemeFrame = nil; pendingReplayTheme = nil
        guard isReplay, !isClosed, !setupCommitted else { return }
        store.previewSpaceTheme(draft.spaceID, theme: theme)
    }

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

    private func restoreReplayPreview() {
        guard isReplay, !setupCommitted else { return }
        replayThemeFrame?.cancel(); replayThemeFrame = nil; pendingReplayTheme = nil
        store.endSpaceThemePreview(draft.spaceID)
        if let appearance = replayAppearance { AppAppearance.endPreview(appearance) }
        replayAppearance = nil
    }

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
            try draft.savedForResume(importInProgress: browserImport != nil || importInterrupted)
                .save(directory: store.directory)
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
        if let welcome, let window, window.isKeyWindow, window.attachedSheet == nil {
            window.makeFirstResponder(welcome)
        }
    }

    private func transition(to stage: OnboardingDraft.Stage) {
        guard !isFinishing, !isClosed, browserImport == nil || stage.holdsImport else { return }
        scheduledAdvance?.cancel(); scheduledAdvance = nil
        captureDraft()
        if stage != .favorites { importInterrupted = false }
        let previous = draft.stage
        transitionDirection = OnboardingExperience.direction(from: previous, to: stage)
        draft.stage = stage; persistDraft()
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
            if reduceMotion {
                leaving.removeFromSuperview()
            } else {
                leaving.rootView.isLeaving = true
                leaving.wantsLayer = true
                CATransaction.begin()
                CATransaction.setCompletionBlock { leaving.removeFromSuperview() }
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
        let retainedImport = draft.stage.showsImport ? browserImport?.view : nil
        let retainedFrame = draft.stage == .windowFrame ? windowFrameStep : nil
        if retainedFrame == nil { windowFrameStep?.end() }
        body.subviews.filter { $0 !== retainedImport && $0 !== retainedFrame }.forEach { $0.removeFromSuperview() }
        defaultChoice = nil
        adBlockerHost = nil
        body.onLayout = nil
        if let browserImport, draft.stage.showsImport {
            renderBrowserImport(browserImport)
            animateStepChange(from: outgoingText)
            confetti.stop(); confetti.isHidden = true
            restoreFocus(from: entering, previousResponder: previousResponder)
            announceStageIfNeeded(from: entering)
            lastStage = draft.stage
            return
        }
        let isReady = draft.stage == .ready
        progress.stringValue = stepCounterText()
        back.isHidden = isReady || draft.previousStage() == nil
            || (importFoundNoSources && draft.previousStage()?.current == .bookmarks)
        skip.title = "Skip for now"
        skip.isHidden = ![.theme, .windowFrame, .favorites, .bookmarks, .adBlockers].contains(draft.stage.current)
        let canAdvance = browserImport == nil || draft.stage == .favorites
        next.isEnabled = canAdvance; next.isLoading = false; back.isEnabled = canAdvance; skip.isEnabled = canAdvance
        next.title = isReady ? "Get Started" : "Next"
        if isReady {
            readyContent.attach(store: MembershipCardStore.shared(directory: store.directory, name: NSFullUserName()))
        }
        let title: String
        let subtitle: String
        switch draft.stage.current {
        case .theme:
            title = "Add some flair with a theme."
            subtitle = "Pick a color, any color—add your favorite shade to your new home on the internet."
        case .windowFrame:
            title = "Find your frame."
            subtitle = "Turn the crank to make the frame around your pages thinner or thicker. You can change it later in Settings."
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
        } else if stage == .windowFrame {
            let step = frameStep()
            if entering != .windowFrame || step.superview !== body {
                step.begin(value: draft.windowFrameValue(saved: WindowFramePreferences.shared.state.thickness))
            }
            lower = [step]
        } else if stage == .favorites {
            favoritePicker.configure(draft: draft, enabled: canAdvance)
            lower = [favoritePicker]
        } else if stage == .defaultBrowser {
            let host = NSHostingView(rootView: defaultBrowserChoices())
            defaultChoice = host
            lower = [host]
        } else if stage == .adBlockers {
            skip.title = "Use all imported ad blockers"
            skip.isHidden = draft.importedAdBlockers.isEmpty
            let shown = draft.adBlockerChoice
            settleAdBlockerChoice()
            if draft.adBlockerChoice != shown { persistDraft() }
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
        lower.filter { $0.superview !== body }.forEach { body.addSubview($0) }
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
                let hostHeight = OnboardingAdBlockersChoice.height(blockerCount: adBlockerCount)
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

    private func updateConfetti(from previous: OnboardingDraft.Stage?) {
        if draft.stage != .ready { readyContent.cancelPresentation() }
        guard OnboardingExperience.shouldPlayConfetti(reduceMotion: reduceMotion) else {
            confetti.stop(); confetti.isHidden = true; return
        }
        confetti.isHidden = false
        if draft.stage != .ready { confetti.cancelPending() }
        else if previous != .ready { confetti.fire(after: OnboardingExperience.readyConfettiDelay) }
    }

    func handleCloseCommand() -> Bool {
        guard passwordHelp?.isPresented == true else { return false }
        dismissPasswordHelp()
        return true
    }

    private func restoreFocus(from previous: OnboardingDraft.Stage?, previousResponder: NSResponder?) {
        if !draft.stage.isWelcome {
            typealias Segment = (first: NSView, link: (NSView) -> Void)
            func views(_ list: [NSView]) -> [Segment] { list.map { view in (view, { view.nextKeyView = $0 }) } }
            var loop = views(back.isHidden ? [] : [back])
            switch draft.stage.current {
            case .theme:
                loop += views([spaceField])
                loop.append((themeEditor.firstKeyView, { self.themeEditor.chainKeyViews(to: $0) }))
            case .windowFrame: loop += views(windowFrameStep?.keyboardView.map { [$0] } ?? [])
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
        let palette = ThemeChromePalette(theme: selectedTheme, appearance: NSApp.effectiveAppearance)
        let hasTheme = selectedTheme.isValid && selectedTheme.primaryColor != nil
        setupCard.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        setupCard.themeTextColor = hasTheme ? palette.title : nil
        spaceName.themeTextColor = setupCard.themeTextColor
        themeChrome.appearance = NSApp.effectiveAppearance
        themePreview.appearance = NSApp.effectiveAppearance
        themePreview.theme = selectedTheme
        setupCard.themeBackground = selectedTheme.isValid && selectedTheme.primaryColor != nil
            ? palette.backgroundExtra : nil
        setupCard.grainTheme = nil
        setupCard.grainIsActive = ThemeWindowActivity.isActive(window)
        let backdrop = draft.stage.showsImport ? browserImport?.backdrop : nil
        setupCard.backdrop.show(backdrop?.pages ?? [], selected: backdrop?.selected)
        setupCard.importInk = backdrop != nil
        setupCard.textSpansCard = draft.stage.showsImport && browserImport?.isSafariPasswords == true
        progress.textColor = setupCard.chromeColor
        persistenceStatus.textColor = draft.stage.isWelcome ? .white : .systemRed
        next.configure(background: hasTheme ? palette.maxContrastColor : OnboardingSetupPalette.action,
                       foreground: hasTheme ? palette.backgroundExtra : .white,
                       reduceMotion: reduceMotion)
        spaceName.updateColors()
        windowFrameStep?.apply(theme: selectedTheme, appearance: NSApp.effectiveAppearance, reduceMotion: reduceMotion)
        for button in [back, skip] { button.contentTintColor = setupCard.chromeColor }
        for view in body.subviews + setupCard.instructions.subviews {
            if let label = view as? NSTextField, label !== spaceField {
                label.textColor = label === setupCard.heading ? setupCard.titleColor : label === setupCard.message
                    ? setupCard.messageColor : (label.font?.pointSize ?? 14) >= 17 ? setupCard.titleColor : setupCard.chromeColor
            } else if let button = view as? ActionButton {
                button.contentTintColor = setupCard.titleColor
            }
        }
    }
    private func stepCounterText() -> String {
        guard draft.stage != .ready else { return "Ready" }
        let held = browserImport?.hasStartedImport == true ? browserImport : nil
        let page = OnboardingExperience.CounterPage(stage: draft.stage, importPage: held?.setupPage,
                                                    importStarted: held != nil)
        guard page != counterPage, draft.stage != .continuedImport || page.importPage != nil else { return counterText }
        counterPage = page
        if draft.stage == .continuedImport, let shown = held?.setupPage { draft.recordImportPage(shown) }
        let steps = draft.stage == .bookmarks && held == nil ? 0
            : draft.importSteps(current: held?.setupPage, ahead: held?.setupPagesAhead ?? [])
        counterText = "\(draft.displayedStepNumber(importSteps: steps)) of \(draft.displayedSetupCount(importSteps: steps))"
        return counterText
    }

    private func advance(leavingWelcome: Bool = false) {
        guard !isFinishing, !isClosed,
              window?.attachedSheet == nil, passwordHelp?.isPresented != true else { return }
        if leavingWelcome {
            if let target = OnboardingExperience.welcomeContinueTarget(from: draft.stage) { transition(to: target) }
            return
        }
        switch OnboardingExperience.importNext(on: draft.stage, holdingImport: browserImport != nil,
                                               started: browserImport?.hasStartedImport == true,
                                               skippingImport: browserImport?.skipIsSelected == true) {
        case .importPage: browserImport?.advance(); return
        case .favorites: transition(to: .favorites); return
        case .nextStage: break
        }
        if draft.stage == .ready { finish(); return }
        captureWindowFrame()
        if draft.stage == .defaultBrowser, draft.wantsDefaultBrowser { defaultBrowser.makeDefault() }
        advanceStage()
    }

    private func advanceStage() {
        guard let next = draft.nextStage(continuingImport: browserImport != nil) else { return }
        if next == .continuedImport { browserImport?.resumeAfterFavorites() }
        transition(to: next)
    }

    private func defaultBrowserChoices() -> OnboardingDefaultBrowserChoice {
        let palette = ThemeChromePalette(theme: selectedTheme, appearance: NSApp.effectiveAppearance)
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
        let palette = ThemeChromePalette(theme: selectedTheme, appearance: NSApp.effectiveAppearance)
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
                applyWindowFrameChoice()
                if let appearance = replayAppearance, AppAppearance.current == appearance { AppAppearance.apply(appearance) }
            }
            guard let onComplete else { throw CocoaError(.featureUnsupported) }
            try onComplete()
            if !submittedICloudPasswords, let profileID = draft.iCloudPasswordsProfileID,
               case let destination = BrowserImportDestination(spaceID: draft.spaceID, profileID: profileID),
               destination.isCurrent(in: store.state) {
                submittedICloudPasswords = true
                SetupExtensionChanges.addICloudPasswords(to: destination, store: store)
            }
            applyAdBlockerChoice()
            scheduledAdvance?.cancel(); scheduledAdvance = nil
            applyMusicPolicy(.finish)
            confetti.stop()
            readyContent.cancelPresentation()
            windowFrameStep?.end()
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
            close()
            onRevealCompleted?()
        } catch {
            isFinishing = false; next.isEnabled = true
            back.isEnabled = !setupCommitted
            if setupCommitted { next.title = "Open Parc" }
            if let window {
                ParcDialog.inform(in: window, .init(error: error, title: setupCommitted ? "Parc couldn’t open the browser." : "Parc couldn’t finish setup."),
                                 queued: true)
            }
        }
    }

    private func frameStep() -> OnboardingWindowFrameStep {
        if let windowFrameStep { return windowFrameStep }
        let step = OnboardingWindowFrameStep(frame: .zero)
        step.onCommit = { [weak self] value in
            guard let self, !self.isClosed, !self.isFinishing, self.draft.stage == .windowFrame,
                  self.draft.windowFrameThickness != nil || value != self.windowFrameStep?.startValue else { return }
            self.draft.chooseWindowFrame(value)
            self.persistDraft()
        }
        step.onKept = { [weak self] in
            guard let self, !self.isClosed, self.draft.stage == .windowFrame else { return }
            self.restoreFocus(from: self.draft.stage, previousResponder: self.next.keyboardView)
        }
        step.onCrankChange = { [weak self] in
            guard let self, !self.isClosed, self.draft.stage == .windowFrame else { return }
            self.restoreFocus(from: self.draft.stage, previousResponder: self.window?.firstResponder)
        }
        windowFrameStep = step
        step.apply(theme: selectedTheme, appearance: NSApp.effectiveAppearance, reduceMotion: reduceMotion)
        return step
    }

    private func captureWindowFrame() {
        guard draft.stage == .windowFrame, let step = windowFrameStep, step.superview === body,
              draft.windowFrameThickness != nil || step.chosenValue != step.startValue else { return }
        draft.chooseWindowFrame(step.chosenValue)
        persistDraft()
    }

    private func applyWindowFrameChoice() {
        guard let thickness = draft.windowFrameThickness else { return }
        do { try WindowFramePreferences.shared.setThickness(thickness) } catch {
            NSLog("Parc could not save the chosen window frame: %@", error.localizedDescription)
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

    private func adoptBackgroundAdBlockers(_ blockers: [OnboardingDraft.ImportedAdBlocker]) {
        let order = OnboardingDraft.Stage.setupOrder(includingAdBlockers: true, retaining: draft.stage.current)
        guard !isClosed, !isFinishing, let here = order.firstIndex(of: draft.stage.current),
              let step = order.firstIndex(of: .adBlockers), here <= step else { return }
        draft.importedAdBlockers = blockers.filter { !ImportedExtensionFailures.failedIdentifiers.contains($0.identifier) }
        settleAdBlockerChoice(); persistDraft(); render()
    }

    private func settleAdBlockerChoice() {
        draft.adBlockerChoice = draft.stage == .adBlockers
            ? .settled(draft.adBlockerChoice, for: draft.importedAdBlockers) : nil
    }

    private func applyAdBlockerChoice() {
        guard let choice = draft.adBlockerChoice,
              let space = store.state.spaces.first(where: { $0.id == draft.spaceID }) else { return }
        draft.adBlockerChoice = nil
        SetupExtensionChanges.apply(choice, to: draft.importedAdBlockers,
                                    in: BrowserImportDestination(spaceID: space.id, profileID: space.profileID), store: store)
    }

    private func dropFailedAdBlockers() {
        guard !isClosed, !isFinishing else { return }
        let before = draft.importedAdBlockers.count
        draft.importedAdBlockers.removeAll { ImportedExtensionFailures.failedIdentifiers.contains($0.identifier) }
        guard draft.importedAdBlockers.count != before else { return }
        let order = OnboardingDraft.Stage.setupOrder(includingAdBlockers: true, retaining: draft.stage.current)
        if let here = order.firstIndex(of: draft.stage.current), let step = order.firstIndex(of: .adBlockers),
           here <= step { settleAdBlockerChoice() }
        persistDraft()
        if draft.stage == .adBlockers { render() }
    }

    func closeBrowserImport() {
        if browserImport != nil && draft.stage == .favorites { importInterrupted = true }
        releaseBrowserImport()
        if draft.stage == .continuedImport { draft.stage = .bookmarks }
    }

    private func releaseBrowserImport() {
        dismissPasswordHelp(remove: true)
        let importer = browserImport; browserImport = nil
        importer?.cancel(); importer?.view.removeFromSuperview()
        setupCard.backdrop.show([], selected: nil)
        onCancelImportRestart?()
    }

    private func skipStep() {
        guard !isClosed, !isFinishing,
              window?.attachedSheet == nil, passwordHelp?.isPresented != true else { return }
        if let browserImport, draft.stage.showsImport {
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
        } else if draft.stage == .windowFrame {
            draft.skipWindowFrame()
            persistDraft()
        } else if draft.stage == .adBlockers {
            draft.adBlockerChoice = .keepAll
        }
        advanceStage()
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
        importHadStarted = false; importInterrupted = false
        draft.iCloudPasswordsProfileID = nil; draft.importPages = []; persistDraft()
        let controller = BrowserImportViewController(store: store, destination: destination, window: window,
            onboarding: true, ownerIsCurrent: { [weak self] in
                guard let self else { return false }
                return !self.isClosed && !self.isFinishing && self.draft.stage.holdsImport
            })
        controller.onClose = { [weak self, weak controller] in
            guard let self, !self.isClosed, !self.isFinishing else { return }
            if controller?.foundNoSources == true { self.importFoundNoSources = true }
            if self.draft.stage == .bookmarks { self.draft.importPages = [] }
            self.captureBrowserImportResults()
            self.releaseBrowserImport()
            if self.draft.stage == .favorites { self.persistDraft(); self.render() } else { self.advanceStage() }
        }
        controller.onChange = { [weak self, weak controller] in
            guard let self, let controller else { return }
            let started = controller.hasStartedImport, wasStarted = self.importHadStarted
            self.importHadStarted = started
            switch OnboardingExperience.importChange(on: self.draft.stage, started: started,
                                                     wasStarted: wasStarted, resting: controller.isResting) {
            case .showFavorites:
                self.draft.importPages = []
                self.transition(to: .favorites); return
            case .returnToSource:
                if controller.returnToSource() { return }
            case .show:
                if let direction = controller.pageDirection { self.transitionDirection = direction }
            case .showInPlace: break
            case .hold: return
            }
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
            help = OnboardingPasswordHelp.install(in: root) { [weak self] in self?.setupCard.setAccessibilityHidden(false) }
            passwordHelp = help
        }
        setupCard.setAccessibilityHidden(true)
        help.export = browserImport?.passwordExport ?? .safari
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
        let palette = ThemeChromePalette(theme: selectedTheme, appearance: NSApp.effectiveAppearance)
        importer.selectionColor = selectedTheme.primaryColor == nil ? OnboardingSetupPalette.action : palette.maxContrastColor
        let startedBeforeFavorites = draft.stage == .bookmarks && importer.hasStartedImport
        next.title = importer.nextTitle
        next.isEnabled = startedBeforeFavorites || importer.canAdvance
        next.isLoading = !startedBeforeFavorites && importer.isLoading
        let leavesForFavorites = draft.stage == .continuedImport && importer.backReturnsToSource
        back.isHidden = leavesForFavorites ? importer.isSafariPasswords && !importer.canGoBack : !importer.canGoBack
        back.isEnabled = true
        skip.title = importer.isImporting ? "Stop Import" : importer.skipTitle ?? ""
        skip.isHidden = !importer.isImporting && importer.skipTitle == nil
        skip.isEnabled = importer.isImporting || importer.canSkip
        progress.stringValue = stepCounterText()
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
