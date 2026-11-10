import AppKit
import Sparkle

///
///
/// download silently and leave the install for the sidebar banner, the next
/// quit or a time the Mac is away (`AutomaticUpdate`). The state lives in
/// `SoftwareUpdateSession`; see docs/software-update.md, "Updater API".
@MainActor final class SoftwareUpdater: NSObject {
    typealias Phase = SoftwareUpdateSession.Phase

    static let shared = SoftwareUpdater()
    static let phaseDidChangeNotification = Notification.Name("ParcSoftwareUpdaterPhaseDidChange")

    var phase: Phase { session.phase }
    var installsWithoutWindow: Bool { session.installsWithoutWindow }

    ///
    /// whether a downloaded update installs by itself while the Mac is away.
    /// Sparkle's silent download (`SUAutomaticallyUpdate`) stays on either way.
    var automaticallyInstallsUpdates: Bool {
        get { UserDefaults.standard.object(forKey: Self.automaticInstallKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.automaticInstallKey) }
    }
    private static let automaticInstallKey = "ParcAutomaticallyInstallsUpdates"

    /// What a restart would interrupt, from the app's windows and downloads.
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
    /// The update Sparkle reported, kept until its session ends so a
    /// scheduled find can be shown when the user asks for it.
    private var found: SUAppcastItem?
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0

    /// A disposable profile shares this app's bundle identifier, defaults and
    /// Sparkle installer with the installed Parc, so it never updates itself;
    ///
    func start(disabled: Bool) {
        guard session.hasFeed else { return }
        if disabled {
            unavailable = NSError(domain: "org.parc.Browser.SoftwareUpdater", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Application is not allowed to update."])
            return
        }
        // The checkbox used to turn off Sparkle's download, which nothing else
        // can turn back on; carry that choice over to automatic installs.
        if UserDefaults.standard.object(forKey: "SUAutomaticallyUpdate") as? Bool == false {
            automaticallyInstallsUpdates = false
            UserDefaults.standard.removeObject(forKey: "SUAutomaticallyUpdate")
        }
        do { try updater.start() } catch { unavailable = error; return }
        observeAway()
    }

    ///
    /// saver active and screen locked.
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
        // AppKit holds distributed notices while Parc isn't active, which
        // would delay a lock made from another app until Parc is next used.
        for name in Self.distributedEvents.keys {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(awayChanged(_:)), name: name,
                                                                object: nil, suspensionBehavior: .deliverImmediately)
        }
    }

    @objc private func awayChanged(_ notification: Notification) {
        guard let event = Self.workspaceEvents[notification.name] ?? Self.distributedEvents[notification.name] else { return }
        if !event.began {
            automatic.ended(event.reason)
        } else if let due = automatic.began(event.reason, at: ProcessInfo.processInfo.systemUptime) {
            scheduleAutomaticCheck(due)
        }
    }

    /// Awake time: the wait stops while the Mac sleeps.
    private func scheduleAutomaticCheck(_ due: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + AutomaticUpdate.delay) { [weak self] in
            MainActor.assumeIsolated { self?.automaticCheck(due: due) }
        }
    }

    private func automaticCheck(due: TimeInterval) {
        guard let next = automatic.checkFired(due: due, at: ProcessInfo.processInfo.systemUptime) else { return }
        scheduleAutomaticCheck(next)
        guard let activity = activity?(), AutomaticUpdate.allows(activity),
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed) else { return }
        //
        // 60-second timeout), so the restored pages can load again.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "HEAD"
        Task { [weak self, request] in
            let status = (try? await URLSession.shared.data(for: request).1 as? HTTPURLResponse)?.statusCode
            // Only if the Mac has stayed away since this check.
            guard let self, let status, (200..<300).contains(status), automatic.nextCheck == next,
                  let activity = self.activity?(), AutomaticUpdate.allows(activity) else { return }
            installAndRelaunch()
        }
    }

    func checkForUpdates() {
        guard session.hasFeed else { return }
        if let unavailable { showError(unavailable); return }
        updater.checkForUpdates()
    }

    /// Restart and Update: install the downloaded update now and relaunch.
    func installAndRelaunch() {
        switch session.installAndRelaunch() {
        case .run(let reply)?: reply()
        case .resume?: updater.checkForUpdates()
        case nil: break
        }
    }

    private func presentFound() {
        guard let item = found else { return }
        // Also true when a window closed at Ready to Install is reopened.
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
            self?.statusWindow = nil
            self?.session.statusClosed()?()
        }
        statusWindow = window
        window.present()
        return window
    }

    private func closeStatus() {
        statusWindow?.dismiss()
        statusWindow = nil
    }

    private func closeUpdateWindow() {
        updateWindow?.dismiss()
        updateWindow = nil
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Update error!"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Download manually")
        if alert.runModal() == .alertSecondButtonReturn,
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
        // Info.plist enables automatic checks, so Sparkle never asks.
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
        session.beginDownload(cancellation: cancellation)
        expectedLength = 0
        receivedLength = 0
        status().show(status: "Downloading...", action: "Cancel", progress: nil)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
        showDownloadProgress()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        showDownloadProgress()
    }

    private func showDownloadProgress() {
        let total = max(expectedLength, receivedLength)
        let bytes = { (count: UInt64) in ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: .file) }
        statusWindow?.show(status: "\(bytes(receivedLength)) of \(bytes(total))", action: "Cancel",
                           progress: total > 0 ? Double(receivedLength) / Double(total) : nil)
    }

    func showDownloadDidStartExtractingUpdate() {
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
        // Install and Relaunch in the update window skips Ready to Install.
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
        // A status window closed mid-way reopens at its step, not the offer.
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
    ///
    /// still installs the update when Parc quits.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        session.downloadedInBackground(version: item.displayVersionString, install: immediateInstallHandler)
        return true
    }
}
