import Foundation

package struct SoftwareUpdateSession {
    package typealias Reply = () -> Void

    package enum Phase: Equatable {
        case idle
        case checking
        case available(version: String)
        case downloading
        case preparing
        case readyToInstall(version: String)
        case installing
    }

    package enum Choice { case install, dismiss }

    package enum Found {
        case present, wait
        case install(Reply)
    }

    package enum Install {
        case run(Reply)
        case resume
    }

    package let hasFeed: Bool
    package private(set) var phase = Phase.idle
    private var version = ""
    private var cancellation: Reply?
    private var choice: ((Choice) -> Void)?
    private var acknowledgement: Reply?
    private var installNow: Reply?
    private var resumable = false
    private var installRequested = false

    package var menuTitle: String {
        switch phase {
        case .available, .readyToInstall: "Update Available…"
        case .downloading, .preparing, .installing: "Updating…"
        case .idle, .checking: "Check for Updates…"
        }
    }

    package var menuToolTip: String? { hasFeed ? nil : "Updates are only available in released builds" }

    package var installsWithoutWindow: Bool { installNow != nil }

    package init(hasFeed: Bool = true) { self.hasFeed = hasFeed }

    package mutating func beginCheck(cancellation: @escaping Reply) {
        self.cancellation = cancellation
        phase = .checking
    }

    package mutating func found(version: String, downloaded: Bool, userInitiated: Bool,
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

    package mutating func upToDate(acknowledgement: @escaping Reply) {
        self.acknowledgement = acknowledgement
        failed()
    }

    package mutating func failed() {
        cancellation = nil
        installNow = nil
        resumable = false
        installRequested = false
        settle()
    }

    package mutating func beginDownload(cancellation: @escaping Reply) {
        self.cancellation = cancellation
        phase = .downloading
    }

    package mutating func beginPreparing() {
        cancellation = nil
        phase = .preparing
    }

    package mutating func ready(reply: @escaping (Choice) -> Void) -> Reply? {
        phase = .readyToInstall(version: version)
        if installRequested {
            installRequested = false
            return { reply(.install) }
        }
        choice = reply
        return nil
    }

    package mutating func beginInstalling(retry: Reply?) {
        installNow = retry
        installRequested = false
        phase = .installing
    }

    package mutating func downloadedInBackground(version: String, install: @escaping Reply) {
        installNow = install
        self.version = version
        phase = .readyToInstall(version: version)
    }

    package mutating func dismissed() {
        cancellation = nil
        choice = nil
        acknowledgement = nil
        installRequested = false
        settle()
    }

    package mutating func installAndRelaunch() -> Install? {
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

    package mutating func choose(_ value: Choice) -> Reply? {
        guard let reply = take(&choice) else { return nil }
        if value == .dismiss, case .readyToInstall = phase { resumable = true }
        return { reply(value) }
    }

    package mutating func acknowledge() -> Reply? { take(&acknowledgement) }

    package mutating func cancel() -> Reply? { take(&cancellation) }

    package mutating func statusClosed() -> Reply? {
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
