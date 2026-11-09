import Foundation

/// The state behind Parc's updater, free of Sparkle and AppKit: what phase
/// the update is in and which Sparkle reply is waiting. `SoftwareUpdater`
/// feeds it Sparkle's user-driver and delegate callbacks and shows the windows
/// it asks for. Replies are handed back for the caller to run after the
/// mutation, because Sparkle may call straight back into the session.
struct SoftwareUpdateSession {
    typealias Reply = () -> Void

    enum Phase: Equatable {
        case idle
        case checking
        case available(version: String)
        case downloading
        case preparing
        case readyToInstall(version: String)
        case installing
    }

    /// Sparkle's `SPUUserUpdateChoice` values Parc uses.
    enum Choice { case install, dismiss }

    enum Found {
        case present, wait
        /// Restart and Update asked for this resumed update: install it now.
        case install(Reply)
    }

    enum Install {
        case run(Reply)
        /// Sparkle keeps a dismissed downloaded update; a new check resumes it.
        case resume
    }

    /// Only distribution packages carry Sparkle's feed. Without one Sparkle
    /// never starts, and Check for Updates… stays listed but disabled.
    let hasFeed: Bool
    private(set) var phase = Phase.idle
    private var version = ""
    // Taken at most once each.
    private var cancellation: Reply?
    private var choice: ((Choice) -> Void)?
    private var acknowledgement: Reply?
    /// Sparkle's install-now handler: the background download's, or the retry
    /// after a quit was cancelled. Sparkle allows calling it again.
    private var installNow: Reply?
    private var resumable = false
    private var installRequested = false

    ///
    var menuTitle: String {
        switch phase {
        case .available, .readyToInstall: "Update Available…"
        case .downloading, .preparing, .installing: "Updating…"
        case .idle, .checking: "Check for Updates…"
        }
    }

    var menuToolTip: String? { hasFeed ? nil : "Updates are only available in released builds" }

    init(hasFeed: Bool = true) { self.hasFeed = hasFeed }

    mutating func beginCheck(cancellation: @escaping Reply) {
        self.cancellation = cancellation
        phase = .checking
    }

    /// Only a manual check shows the update window; a scheduled find waits
    /// for the banner or the Update Available… menu.
    mutating func found(version: String, downloaded: Bool, userInitiated: Bool,
                        reply: @escaping (Choice) -> Void) -> Found {
        // A manual check replaces the background session that owned the handler.
        installNow = nil
        cancellation = nil
        resumable = false
        self.version = version
        phase = downloaded ? .readyToInstall(version: version) : .available(version: version)
        // Restart and Update stays requested until the update is ready, since
        // a downloaded one may still need preparing.
        if installRequested && downloaded { return .install { reply(.install) } }
        installRequested = false
        choice = reply
        return userInitiated ? .present : .wait
    }

    mutating func upToDate(acknowledgement: @escaping Reply) {
        self.acknowledgement = acknowledgement
        failed()
    }

    mutating func failed() {
        cancellation = nil
        installNow = nil
        resumable = false
        installRequested = false
        settle()
    }

    mutating func beginDownload(cancellation: @escaping Reply) {
        self.cancellation = cancellation
        phase = .downloading
    }

    mutating func beginPreparing() {
        cancellation = nil
        phase = .preparing
    }

    /// Returns the install reply at once when Restart and Update is waiting.
    mutating func ready(reply: @escaping (Choice) -> Void) -> Reply? {
        phase = .readyToInstall(version: version)
        if installRequested {
            installRequested = false
            return { reply(.install) }
        }
        choice = reply
        return nil
    }

    /// `retry` is Sparkle's handler for a quit that hasn't happened yet.
    mutating func beginInstalling(retry: Reply?) {
        installNow = retry
        installRequested = false
        phase = .installing
    }

    ///
    mutating func downloadedInBackground(version: String, install: @escaping Reply) {
        installNow = install
        self.version = version
        phase = .readyToInstall(version: version)
    }

    /// Sparkle ended the session; an unanswered Restart and Update lapses.
    mutating func dismissed() {
        cancellation = nil
        choice = nil
        acknowledgement = nil
        installRequested = false
        settle()
    }

    /// Restart and Update, or the window's Install and Relaunch. Also retries
    /// while installing, if a page cancelled the quit.
    mutating func installAndRelaunch() -> Install? {
        switch phase {
        case .readyToInstall, .installing:
            if let installNow {
                phase = .installing
                return .run(installNow)
            }
            if let reply = choose(.install) { return .run(reply) }
            guard case .readyToInstall = phase, resumable else { return nil }
            installRequested = true
            return .resume
        default:
            return nil
        }
    }

    mutating func choose(_ value: Choice) -> Reply? {
        guard let reply = take(&choice) else { return nil }
        // A dismissed downloaded update stays with Sparkle for the next check.
        if value == .dismiss, case .readyToInstall = phase { resumable = true }
        return { reply(value) }
    }

    mutating func acknowledge() -> Reply? { take(&acknowledgement) }

    mutating func cancel() -> Reply? { take(&cancellation) }

    /// Closing a status window cancels a check or download; a prepared
    /// update stays ready and still installs on quit.
    mutating func statusClosed() -> Reply? {
        switch phase {
        case .checking, .downloading: cancel()
        default: nil
        }
    }

    /// An ended session leaves a downloaded update ready; otherwise idle.
    private mutating func settle() {
        if installNow != nil || resumable {
            phase = .readyToInstall(version: version)
        } else {
            phase = .idle
            installRequested = false
        }
    }

    private func take<Value>(_ value: inout Value?) -> Value? {
        defer { value = nil }
        return value
    }
}
