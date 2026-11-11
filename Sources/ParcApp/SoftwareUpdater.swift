import AppKit
import Sparkle

@MainActor final class SoftwareUpdater: NSObject {
    typealias Phase = SoftwareUpdateSession.Phase

    static let shared = SoftwareUpdater()
    static let phaseDidChangeNotification = Notification.Name("ParcSoftwareUpdaterPhaseDidChange")

    var phase: Phase { session.phase }
    var installsWithoutWindow: Bool { session.installsWithoutWindow }

    var automaticallyInstallsUpdates: Bool {
        get { UserDefaults.standard.object(forKey: Self.automaticInstallKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.automaticInstallKey) }
    }
    private static let automaticInstallKey = "ParcAutomaticallyInstallsUpdates"

    var activity: (() -> AutomaticUpdate.Activity?)?
    private var automatic = AutomaticUpdate()

    private var session = SoftwareUpdateSession(hasFeed: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil) {
        didSet {
            if session.phase != oldValue.phase {
                NotificationCenter.default.post(name: Self.phaseDidChangeNotification, object: self)
            }
        }
    }
    private lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
    private var unavailable: Error?
    private var updateWindow: SoftwareUpdateWindow?
    private var statusWindow: SoftwareUpdateStatusWindow?
    private var found: SUAppcastItem?
    private var downloadProgress = SoftwareUpdateDownloadProgress()
    private var pendingDownloadProgress: DispatchWorkItem?

    func start(disabled: Bool) {
        guard session.hasFeed else { return }
        if disabled {
            unavailable = NSError(domain: "org.parc.Browser.SoftwareUpdater", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Application is not allowed to update."])
            return
        }
        if UserDefaults.standard.object(forKey: "SUAutomaticallyUpdate") as? Bool == false {
            automaticallyInstallsUpdates = false
            UserDefaults.standard.removeObject(forKey: "SUAutomaticallyUpdate")
        }
        do { try updater.start() } catch { unavailable = error; return }
        observeAway()
        scheduleAutomaticCheck()
    }

    private typealias AwayEvent = (reason: AutomaticUpdate.Away, began: Bool)
    private static let workspaceEvents: [Notification.Name: AwayEvent] = [
        NSWorkspace.willSleepNotification: (.sleep, true),
        NSWorkspace.didWakeNotification: (.sleep, false),
        NSWorkspace.screensDidSleepNotification: (.displaySleep, true),
        NSWorkspace.screensDidWakeNotification: (.displaySleep, false),
    ]
    private static let distributedEvents: [Notification.Name: AwayEvent] = [
        Notification.Name("com.apple.screensaver.didstart"): (.screenSaver, true),
        Notification.Name("com.apple.screensaver.didstop"): (.screenSaver, false),
        Notification.Name("com.apple.screenIsLocked"): (.screenLock, true),
        Notification.Name("com.apple.screenIsUnlocked"): (.screenLock, false),
    ]

    private func observeAway() {
        for name in Self.workspaceEvents.keys {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(awayChanged(_:)), name: name, object: nil)
        }
        for name in Self.distributedEvents.keys {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(awayChanged(_:)), name: name,
                                                                object: nil, suspensionBehavior: .deliverImmediately)
        }
    }

    @objc private func awayChanged(_ notification: Notification) {
        guard let event = Self.workspaceEvents[notification.name] ?? Self.distributedEvents[notification.name] else { return }
        if event.began {
            automatic.began(event.reason, at: ProcessInfo.processInfo.systemUptime)
        } else {
            automatic.ended(event.reason)
        }
    }

    private func scheduleAutomaticCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + AutomaticUpdate.delay) { [weak self] in
            MainActor.assumeIsolated { self?.automaticCheck() }
        }
    }

    private func automaticCheck() {
        scheduleAutomaticCheck()
        guard installsWithoutWindow, let activity = activity?(),
              automatic.allows(activity, at: ProcessInfo.processInfo.systemUptime),
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed) else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "HEAD"
        Task { [weak self, request] in
            let status = (try? await URLSession.shared.data(for: request).1 as? HTTPURLResponse)?.statusCode
            guard let self, let status, (200..<300).contains(status), let activity = self.activity?(),
                  automatic.allows(activity, at: ProcessInfo.processInfo.systemUptime) else { return }
            installAndRelaunch()
        }
    }

    func checkForUpdates() {
        guard session.hasFeed else { return }
        if let unavailable { showError(unavailable); return }
        updater.checkForUpdates()
    }

    func installAndRelaunch() {
        switch session.installAndRelaunch() {
        case .run(let reply)?: reply()
        case .resume?: updater.checkForUpdates()
        case nil: break
        }
    }

    private func presentFound() {
        guard let item = found else { return }
        let ready = if case .readyToInstall = phase { true } else { false }
        closeUpdateWindow()
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let window = SoftwareUpdateWindow(style: .update(
            prompt: "You have v\(current).\nWould you like to download\nv\(item.displayVersionString) (\(item.versionString)) now?",
            action: ready ? "Install and Relaunch" : "Download", title: item.title, notes: item.itemDescription))
        window.onPrimary = { [weak self] in self?.session.choose(.install)?() }
        window.onSecondary = { [weak self] in
            self?.closeUpdateWindow()
            self?.session.choose(.dismiss)?()
        }
        window.onClose = { [weak self] in
            self?.updateWindow = nil
            self?.session.choose(.dismiss)?()
        }
        updateWindow = window
        window.present()
    }

    private func status() -> SoftwareUpdateStatusWindow {
        if let statusWindow { return statusWindow }
        let window = SoftwareUpdateStatusWindow()
        window.onAction = { [weak self] in
            guard let self else { return }
            if case .readyToInstall = phase { installAndRelaunch() } else { session.cancel()?() }
        }
        window.onClose = { [weak self] in
            self?.cancelDownloadProgressRefresh()
            self?.statusWindow = nil
            self?.session.statusClosed()?()
        }
        statusWindow = window
        window.present()
        return window
    }

    private func closeStatus() {
        cancelDownloadProgressRefresh()
        statusWindow?.dismiss()
        statusWindow = nil
    }

    private func closeUpdateWindow() {
        updateWindow?.dismiss()
        updateWindow = nil
    }

    private func showError(_ error: Error) {
        var content = PArcDialog.Content(title: "Update error!", message: error.localizedDescription)
        content.secondary = "Download manually"
        if PArcDialog(content).runModal() == .secondary,
           let url = URL(string: "https://github.com/etsenake/parc-releases/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension SoftwareUpdater: NSMenuItemValidation {
    @objc func checkForUpdates(_ sender: Any?) { checkForUpdates() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.title = session.menuTitle
        menuItem.toolTip = session.menuToolTip
        return session.hasFeed
    }
}

extension SoftwareUpdater: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        session.beginCheck(cancellation: cancellation)
        status().show(status: "Checking for updates...", action: "Cancel", progress: nil)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        closeStatus()
        found = appcastItem
        switch session.found(version: appcastItem.displayVersionString, downloaded: state.stage != .notDownloaded,
                             userInitiated: state.userInitiated, reply: { reply($0 == .install ? .install : .dismiss) }) {
        case .present: presentFound()
        case .wait: break
        case .install(let install): install()
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        closeStatus()
        closeUpdateWindow()
        session.upToDate(acknowledgement: acknowledgement)
        let window = SoftwareUpdateWindow(style: .upToDate)
        window.onPrimary = { [weak self] in
            self?.closeUpdateWindow()
            self?.session.acknowledge()?()
        }
        window.onClose = { [weak self] in
            self?.updateWindow = nil
            self?.session.acknowledge()?()
        }
        updateWindow = window
        window.present()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        closeStatus()
        closeUpdateWindow()
        session.failed()
        showError(error)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        closeUpdateWindow()
        cancelDownloadProgressRefresh()
        session.beginDownload(cancellation: cancellation)
        downloadProgress = SoftwareUpdateDownloadProgress()
        status().show(status: "Downloading...", action: "Cancel", progress: nil)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        guard phase == .downloading else { return }
        downloadProgress.expect(expectedContentLength)
        scheduleDownloadProgressRefresh()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        guard phase == .downloading else { return }
        downloadProgress.receive(length)
        scheduleDownloadProgressRefresh()
    }

    private func scheduleDownloadProgressRefresh() {
        guard pendingDownloadProgress == nil, statusWindow != nil else { return }
        let refresh = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingDownloadProgress = nil
                guard self.phase == .downloading else { return }
                let display = self.downloadProgress.display
                self.statusWindow?.show(status: display.text, action: "Cancel", progress: display.fraction,
                                       widthTemplate: display.widthTemplate)
            }
        }
        pendingDownloadProgress = refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: refresh)
    }

    private func cancelDownloadProgressRefresh() {
        pendingDownloadProgress?.cancel()
        pendingDownloadProgress = nil
    }

    func showDownloadDidStartExtractingUpdate() {
        cancelDownloadProgressRefresh()
        session.beginPreparing()
        status().show(status: "Preparing…", action: "Cancel", progress: nil, enabled: false)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        statusWindow?.show(status: "Preparing…", action: "Cancel", progress: progress, enabled: false)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if let install = session.ready(reply: { reply($0 == .install ? .install : .dismiss) }) {
            install()
            return
        }
        statusWindow?.show(status: "Ready to Install", action: "Install and Relaunch", progress: 1)
        NSApp.requestUserAttention(.informationalRequest)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        session.beginInstalling(retry: applicationTerminated ? nil : retryTerminatingApplication)
        closeUpdateWindow()
        status().show(status: "Installing update... ", action: "Install and Relaunch", progress: 1, enabled: false)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        if let window = updateWindow?.window ?? statusWindow?.window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        switch phase {
        case .preparing: status().show(status: "Preparing…", action: "Cancel", progress: nil, enabled: false)
        case .installing: status().show(status: "Installing update... ", action: "Install and Relaunch", progress: 1, enabled: false)
        default: presentFound()
        }
    }

    func dismissUpdateInstallation() {
        found = nil
        closeStatus()
        closeUpdateWindow()
        session.dismissed()
    }
}

extension SoftwareUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        session.downloadedInBackground(version: item.displayVersionString, install: immediateInstallHandler)
        return true
    }
}
