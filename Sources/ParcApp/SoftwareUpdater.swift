import AppKit
import Sparkle

///
///
/// download silently and leave the install for the sidebar banner or the next
/// quit. The state lives in `SoftwareUpdateSession`; see
/// docs/software-update.md, "Updater API".
@MainActor final class SoftwareUpdater: NSObject {
    typealias Phase = SoftwareUpdateSession.Phase

    static let shared = SoftwareUpdater()
    static let phaseDidChangeNotification = Notification.Name("ParcSoftwareUpdaterPhaseDidChange")

    var phase: Phase { session.phase }

    /// Sparkle's own persisted setting (`SUAutomaticallyUpdate`, on in
    /// Info.plist); the banner's Automatic Updates checkbox.
    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    private var session = SoftwareUpdateSession() {
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
        if disabled {
            unavailable = NSError(domain: "org.parc.Browser.SoftwareUpdater", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Application is not allowed to update."])
            return
        }
        do { try updater.start() } catch { unavailable = error }
    }

    func checkForUpdates() {
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
        return true
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
        } else {
            presentFound()
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
