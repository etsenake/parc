import Foundation

@main
struct SoftwareUpdateSessionTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(value(), message)
    }

    static func main() {
        manualCheckUpToDate()
        manualCheckDownloadAndInstall()
        backgroundDownloadWaitsForBanner()
        scheduledFindWaitsForTheUser()
        closingWindows()
        dismissedDownloadStaysReady()
        cancelledQuitCanRetry()
        repliesMayReenterTheSession()
        buildsWithoutAFeed()
        print("SoftwareUpdateSessionTests: \(checks) checks passed")
    }

    static func manualCheckUpToDate() {
        var session = SoftwareUpdateSession()
        check(session.phase == .idle && session.menuTitle == "Check for Updates…", "Idle offers Check for Updates…")
        var cancelled = 0, acknowledged = 0
        session.beginCheck { cancelled += 1 }
        check(session.phase == .checking && session.menuTitle == "Check for Updates…", "A check keeps the idle title")
        session.upToDate { acknowledged += 1 }
        check(session.phase == .idle, "Up to date returns to idle")
        check(session.cancel() == nil, "The finished check can no longer be cancelled")
        session.acknowledge()?()
        session.acknowledge()?()
        check(acknowledged == 1 && cancelled == 0, "Closing the notice acknowledges it exactly once")
    }

    static func manualCheckDownloadAndInstall() {
        var session = SoftwareUpdateSession()
        var choices: [SoftwareUpdateSession.Choice] = []
        session.beginCheck {}
        check(isPresent(session.found(version: "1.9.0", downloaded: false, userInitiated: true) { choices.append($0) }),
              "A manual check shows the update window")
        check(session.phase == .available(version: "1.9.0") && session.menuTitle == "Update Available…",
              "An update not yet downloaded is available")
        check(session.installAndRelaunch() == nil, "Nothing installs before it is downloaded")
        session.choose(.install)?()
        session.choose(.dismiss)?()
        check(choices == [.install], "Download answers Sparkle once")
        var cancelled = 0
        session.beginDownload { cancelled += 1 }
        check(session.phase == .downloading && session.menuTitle == "Updating…", "Downloading reads Updating…")
        session.beginPreparing()
        check(session.phase == .preparing && session.cancel() == nil, "Preparing can't be cancelled")
        check(session.ready { choices.append($0) } == nil, "Ready waits for the person")
        check(session.phase == .readyToInstall(version: "1.9.0"), "Ready carries the found version")
        run(session.installAndRelaunch())
        check(choices == [.install, .install], "Install and Relaunch answers the ready reply")
        check(session.installAndRelaunch() == nil, "A second Install and Relaunch does nothing")
        session.beginInstalling(retry: nil)
        check(session.phase == .installing && session.menuTitle == "Updating…", "Installing reads Updating…")
        session.dismissed()
        check(session.phase == .idle && cancelled == 0, "Sparkle ending the session returns to idle")
    }

    static func backgroundDownloadWaitsForBanner() {
        var session = SoftwareUpdateSession()
        var installed = 0
        session.downloadedInBackground(version: "1.9.0") { installed += 1 }
        check(session.phase == .readyToInstall(version: "1.9.0") && session.menuTitle == "Update Available…",
              "A silent download is ready for the banner")
        check(session.installsWithoutWindow, "Its install handler installs without a window")
        session.dismissed()
        check(session.phase == .readyToInstall(version: "1.9.0"), "An unrelated session end keeps the background update ready")
        run(session.installAndRelaunch())
        check(installed == 1 && session.phase == .installing, "Restart and Update runs Sparkle's install handler")

        var replaced = SoftwareUpdateSession()
        var choices: [SoftwareUpdateSession.Choice] = []
        replaced.downloadedInBackground(version: "1.9.0") { installed += 1 }
        check(isPresent(replaced.found(version: "1.9.0", downloaded: true, userInitiated: true) { choices.append($0) }),
              "Checking with a downloaded update shows the window")
        check(replaced.phase == .readyToInstall(version: "1.9.0"), "A downloaded find is ready to install")
        check(!replaced.installsWithoutWindow, "A find waiting in its window needs the user")
        run(replaced.installAndRelaunch())
        check(choices == [.install] && installed == 1, "The manual session's reply replaces the stale background handler")
    }

    static func scheduledFindWaitsForTheUser() {
        var session = SoftwareUpdateSession()
        var choices: [SoftwareUpdateSession.Choice] = []
        check(isWait(session.found(version: "1.9.0", downloaded: false, userInitiated: false) { choices.append($0) }),
              "A scheduled find shows no window")
        check(session.menuTitle == "Update Available…" && choices.isEmpty, "It waits for the Update Available… menu")
        check(isWait(session.found(version: "1.9.0", downloaded: true, userInitiated: false) { choices.append($0) }),
              "A scheduled reminder of a downloaded update shows no window")
        run(session.installAndRelaunch())
        check(choices == [.install], "The banner installs it through Sparkle's reply")
    }

    static func closingWindows() {
        var session = SoftwareUpdateSession()
        var cancelled = 0
        session.beginCheck { cancelled += 1 }
        session.statusClosed()?()
        check(cancelled == 1, "Closing the checking window cancels the check")
        session.beginDownload { cancelled += 1 }
        session.statusClosed()?()
        check(cancelled == 2, "Closing the download window cancels the download")
        var choices: [SoftwareUpdateSession.Choice] = []
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { choices.append($0) }
        session.choose(.install)?()
        session.beginPreparing()
        _ = session.ready { choices.append($0) }
        check(session.statusClosed() == nil && session.phase == .readyToInstall(version: "1.9.0"),
              "Closing a ready window keeps the update ready")
        run(session.installAndRelaunch())
        check(choices == [.install, .install], "The banner can still install after the window closed")
        _ = session.found(version: "2.0.0", downloaded: false, userInitiated: true) { choices.append($0) }
        session.choose(.dismiss)?()
        session.dismissed()
        check(choices == [.install, .install, .dismiss] && session.phase == .idle,
              "Remind me Later dismisses an update that isn't downloaded")
    }

    static func dismissedDownloadStaysReady() {
        // Sparkle keeps a dismissed downloaded update, and installs it on quit
        // once it is installing; the banner must stay and can resume it.
        var session = SoftwareUpdateSession()
        var choices: [SoftwareUpdateSession.Choice] = []
        _ = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { choices.append($0) }
        session.choose(.dismiss)?()
        session.dismissed()
        check(session.phase == .readyToInstall(version: "1.9.0") && session.menuTitle == "Update Available…",
              "A dismissed downloaded update stays ready")
        check(!session.installsWithoutWindow, "Resuming it opens a check, so it isn't installed automatically")
        guard case .resume? = session.installAndRelaunch() else { return check(false, "Restart and Update resumes it") }
        session.beginCheck {}
        guard case .install(let install) = session.found(version: "1.9.0", downloaded: true, userInitiated: true,
                                                         reply: { choices.append($0) }) else {
            return check(false, "The resumed find installs without another window")
        }
        install()
        check(choices == [.dismiss, .install], "The resumed update installs")

        var preparing = SoftwareUpdateSession()
        _ = preparing.found(version: "1.9.0", downloaded: true, userInitiated: true) { choices.append($0) }
        preparing.choose(.dismiss)?()
        preparing.dismissed()
        _ = preparing.installAndRelaunch()
        guard case .present = preparing.found(version: "1.9.0", downloaded: false, userInitiated: true,
                                              reply: { choices.append($0) }) else {
            return check(false, "A newer update that isn't downloaded asks first")
        }
        check(preparing.phase == .available(version: "1.9.0"), "It is available, not installing")

        var downloaded = SoftwareUpdateSession()
        _ = downloaded.found(version: "1.9.0", downloaded: true, userInitiated: true) { choices.append($0) }
        downloaded.choose(.dismiss)?()
        downloaded.dismissed()
        _ = downloaded.installAndRelaunch()
        _ = downloaded.found(version: "1.9.0", downloaded: true, userInitiated: true) { _ in }
        downloaded.beginPreparing()
        check(downloaded.ready { choices.append($0) } != nil, "A resumed update that still needs preparing installs when ready")

        var cancelled = SoftwareUpdateSession()
        _ = cancelled.found(version: "1.9.0", downloaded: true, userInitiated: true) { _ in }
        cancelled.choose(.dismiss)?()
        cancelled.dismissed()
        _ = cancelled.installAndRelaunch()
        cancelled.beginCheck {}
        cancelled.statusClosed()?()
        cancelled.dismissed()
        check(cancelled.phase == .readyToInstall(version: "1.9.0"), "Cancelling the resumed check keeps the update ready")
        guard case .present = cancelled.found(version: "1.9.0", downloaded: true, userInitiated: true, reply: { _ in }) else {
            return check(false, "A cancelled Restart and Update doesn't install on the next check")
        }

        var stale = SoftwareUpdateSession()
        _ = stale.found(version: "1.9.0", downloaded: true, userInitiated: true) { _ in }
        stale.choose(.dismiss)?()
        stale.dismissed()
        stale.beginCheck {}
        stale.upToDate {}
        check(stale.phase == .idle && stale.installAndRelaunch() == nil, "Up to date clears a dismissed update")
    }

    static func cancelledQuitCanRetry() {
        var session = SoftwareUpdateSession()
        var installs = 0
        session.downloadedInBackground(version: "1.9.0") { installs += 1 }
        run(session.installAndRelaunch())
        run(session.installAndRelaunch())
        check(installs == 2 && session.phase == .installing, "Sparkle's install handler may be retried")

        var manual = SoftwareUpdateSession()
        var retries = 0
        _ = manual.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        manual.choose(.install)?()
        manual.beginInstalling(retry: { retries += 1 })
        check(manual.installsWithoutWindow, "A cancelled quit's retry installs without a window")
        run(manual.installAndRelaunch())
        check(retries == 1 && manual.phase == .installing, "A cancelled quit while installing can be retried")
        manual.beginInstalling(retry: nil)
        check(manual.installAndRelaunch() == nil, "Once the app terminated there is nothing to retry")
        check(!manual.installsWithoutWindow, "Nor anything to install")

        var failing = SoftwareUpdateSession()
        _ = failing.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        failing.choose(.install)?()
        failing.beginInstalling(retry: {})
        failing.failed()
        failing.dismissed()
        check(failing.phase == .idle && failing.installAndRelaunch() == nil, "A failed install drops its retry handler")
    }

    static func run(_ install: SoftwareUpdateSession.Install?) {
        if case .run(let reply)? = install { reply() }
    }

    static func isPresent(_ found: SoftwareUpdateSession.Found) -> Bool {
        if case .present = found { return true }
        return false
    }

    static func isWait(_ found: SoftwareUpdateSession.Found) -> Bool {
        if case .wait = found { return true }
        return false
    }

    static func repliesMayReenterTheSession() {
        // Sparkle can end the session from inside a reply; the session must
        // not be mid-mutation when the reply runs.
        var session = SoftwareUpdateSession()
        session.upToDate { session.dismissed() }
        session.acknowledge()?()
        check(session.phase == .idle, "Acknowledging may synchronously dismiss")
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in session.dismissed() }
        session.choose(.dismiss)?()
        check(session.phase == .idle, "Dismissing may synchronously end the session")
        session.beginCheck { session.failed() }
        session.cancel()?()
        check(session.phase == .idle, "Cancelling may synchronously report a failure")
    }

    static func buildsWithoutAFeed() {
        let released = SoftwareUpdateSession()
        check(released.hasFeed && released.menuToolTip == nil, "A released build's Check for Updates… has no tooltip")
        let local = SoftwareUpdateSession(hasFeed: false)
        check(!local.hasFeed && local.menuTitle == "Check for Updates…", "A build without a feed keeps Check for Updates…")
        check(local.menuToolTip == "Updates are only available in released builds", "Its tooltip says why it is disabled")
    }
}
