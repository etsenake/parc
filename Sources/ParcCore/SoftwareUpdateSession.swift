import Foundation

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

    enum Choice { case install, dismiss }

    enum Found {
        case present, wait
        case install(Reply)
    }

    enum Install {
        case run(Reply)
        case resume
    }

    let hasFeed: Bool
    private(set) var phase = Phase.idle
    private var version = ""
    private var cancellation: Reply?
    private var choice: ((Choice) -> Void)?
    private var acknowledgement: Reply?
    private var installNow: Reply?
    private var resumable = false
    private var installRequested = false

    var menuTitle: String {
        switch phase {
        case .available, .readyToInstall: "Update Available…"
        case .downloading, .preparing, .installing: "Updating…"
        case .idle, .checking: "Check for Updates…"
        }
    }

    var menuToolTip: String? { hasFeed ? nil : "Updates are only available in released builds" }

    var installsWithoutWindow: Bool { installNow != nil }

    init(hasFeed: Bool = true) { self.hasFeed = hasFeed }

    mutating func beginCheck(cancellation: @escaping Reply) {
        self.cancellation = cancellation
        phase = .checking
    }

    mutating func found(version: String, downloaded: Bool, userInitiated: Bool,
                        reply: @escaping (Choice) -> Void) -> Found {
        installNow = nil
        cancellation = nil
        resumable = false
        self.version = version
        phase = downloaded ? .readyToInstall(version: version) : .available(version: version)
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

    mutating func ready(reply: @escaping (Choice) -> Void) -> Reply? {
        phase = .readyToInstall(version: version)
        if installRequested {
            installRequested = false
            return { reply(.install) }
        }
        choice = reply
        return nil
    }

    mutating func beginInstalling(retry: Reply?) {
        installNow = retry
        installRequested = false
        phase = .installing
    }

    mutating func downloadedInBackground(version: String, install: @escaping Reply) {
        installNow = install
        self.version = version
        phase = .readyToInstall(version: version)
    }

    mutating func dismissed() {
        cancellation = nil
        choice = nil
        acknowledgement = nil
        installRequested = false
        settle()
    }

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
        if value == .dismiss, case .readyToInstall = phase { resumable = true }
        return { reply(value) }
    }

    mutating func acknowledge() -> Reply? { take(&acknowledgement) }

    mutating func cancel() -> Reply? { take(&cancellation) }

    mutating func statusClosed() -> Reply? {
        switch phase {
        case .checking, .downloading: cancel()
        default: nil
        }
    }

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
