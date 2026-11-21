import Testing
@testable import ParcCore

struct SoftwareUpdateSessionTests {
    typealias Choice = SoftwareUpdateSession.Choice

    private func run(_ install: SoftwareUpdateSession.Install?) {
        if case .run(let reply)? = install { reply() }
    }

    private func isPresent(_ found: SoftwareUpdateSession.Found) -> Bool {
        if case .present = found { return true }
        return false
    }

    private func isWait(_ found: SoftwareUpdateSession.Found) -> Bool {
        if case .wait = found { return true }
        return false
    }

    private func dismissedDownload(choices: inout [Choice]) -> SoftwareUpdateSession {
        var session = SoftwareUpdateSession()
        var recorded: [Choice] = []
        _ = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { recorded.append($0) }
        session.choose(.dismiss)?()
        session.dismissed()
        choices = recorded
        return session
    }

    @Test func idleOffersCheckForUpdates() {
        let session = SoftwareUpdateSession()
        #expect(session.phase == .idle)
        #expect(session.menuTitle == "Check for Updates…")
    }

    @Test func aCheckKeepsTheIdleTitle() {
        var session = SoftwareUpdateSession()
        session.beginCheck {}
        #expect(session.phase == .checking)
        #expect(session.menuTitle == "Check for Updates…")
    }

    private func upToDateSession() -> SoftwareUpdateSession {
        var session = SoftwareUpdateSession()
        session.beginCheck {}
        session.upToDate {}
        return session
    }

    @Test func upToDateReturnsToIdle() {
        #expect(upToDateSession().phase == .idle)
    }

    @Test func anUpToDateCheckCannotBeCancelled() {
        var session = upToDateSession()
        #expect(session.cancel() == nil)
    }

    @Test func closingTheUpToDateNoticeAcknowledgesItExactlyOnce() {
        var session = SoftwareUpdateSession()
        var cancelled = 0, acknowledged = 0
        session.beginCheck { cancelled += 1 }
        session.upToDate { acknowledged += 1 }
        session.acknowledge()?()
        session.acknowledge()?()
        #expect(acknowledged == 1)
        #expect(cancelled == 0)
    }

    @Test func aManualCheckShowsTheUpdateWindowForAnUndownloadedUpdate() {
        var session = SoftwareUpdateSession()
        session.beginCheck {}
        let found = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        #expect(isPresent(found))
        #expect(session.phase == .available(version: "1.9.0"))
        #expect(session.menuTitle == "Update Available…")
    }

    @Test func nothingInstallsBeforeItIsDownloaded() {
        var session = SoftwareUpdateSession()
        session.beginCheck {}
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        #expect(session.installAndRelaunch() == nil)
    }

    @Test func downloadAnswersSparkleOnce() {
        var session = SoftwareUpdateSession()
        var choices: [Choice] = []
        session.beginCheck {}
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { choices.append($0) }
        session.choose(.install)?()
        session.choose(.dismiss)?()
        #expect(choices == [.install])
    }

    @Test func downloadingReadsUpdating() {
        var session = SoftwareUpdateSession()
        session.beginDownload {}
        #expect(session.phase == .downloading)
        #expect(session.menuTitle == "Updating…")
    }

    @Test func preparingCannotBeCancelled() {
        var session = SoftwareUpdateSession()
        session.beginDownload {}
        session.beginPreparing()
        #expect(session.phase == .preparing)
        #expect(session.cancel() == nil)
    }

    @Test func readyWaitsForThePersonAndCarriesTheFoundVersion() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        session.beginPreparing()
        #expect(session.ready { _ in } == nil)
        #expect(session.phase == .readyToInstall(version: "1.9.0"))
    }

    @Test func installAndRelaunchAnswersTheReadyReplyOnce() {
        var session = SoftwareUpdateSession()
        var choices: [Choice] = []
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { choices.append($0) }
        session.choose(.install)?()
        session.beginPreparing()
        _ = session.ready { choices.append($0) }
        run(session.installAndRelaunch())
        #expect(choices == [.install, .install])
        #expect(session.installAndRelaunch() == nil)
    }

    @Test func installingReadsUpdatingAndSparkleEndingTheSessionReturnsToIdle() {
        var session = SoftwareUpdateSession()
        var cancelled = 0
        session.beginDownload { cancelled += 1 }
        session.beginInstalling(retry: nil)
        #expect(session.phase == .installing)
        #expect(session.menuTitle == "Updating…")
        session.dismissed()
        #expect(session.phase == .idle)
        #expect(cancelled == 0)
    }

    @Test func aSilentDownloadIsReadyForTheBannerWithoutAWindow() {
        var session = SoftwareUpdateSession()
        session.downloadedInBackground(version: "1.9.0") {}
        #expect(session.phase == .readyToInstall(version: "1.9.0"))
        #expect(session.menuTitle == "Update Available…")
        #expect(session.installsWithoutWindow)
    }

    @Test func anUnrelatedSessionEndKeepsTheBackgroundUpdateReady() {
        var session = SoftwareUpdateSession()
        session.downloadedInBackground(version: "1.9.0") {}
        session.dismissed()
        #expect(session.phase == .readyToInstall(version: "1.9.0"))
    }

    @Test func restartAndUpdateRunsSparklesInstallHandler() {
        var session = SoftwareUpdateSession()
        var installed = 0
        session.downloadedInBackground(version: "1.9.0") { installed += 1 }
        run(session.installAndRelaunch())
        #expect(installed == 1)
        #expect(session.phase == .installing)
    }

    @Test func checkingWithADownloadedUpdateShowsTheWindowAndNeedsTheUser() {
        var session = SoftwareUpdateSession()
        session.downloadedInBackground(version: "1.9.0") {}
        let found = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { _ in }
        #expect(isPresent(found))
        #expect(session.phase == .readyToInstall(version: "1.9.0"))
        #expect(!session.installsWithoutWindow)
    }

    @Test func theManualSessionsReplyReplacesTheStaleBackgroundHandler() {
        var session = SoftwareUpdateSession()
        var installed = 0
        var choices: [Choice] = []
        session.downloadedInBackground(version: "1.9.0") { installed += 1 }
        _ = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { choices.append($0) }
        run(session.installAndRelaunch())
        #expect(choices == [.install])
        #expect(installed == 0)
    }

    @Test func aScheduledFindShowsNoWindowAndWaitsForTheMenu() {
        var session = SoftwareUpdateSession()
        var choices: [Choice] = []
        let found = session.found(version: "1.9.0", downloaded: false, userInitiated: false) { choices.append($0) }
        #expect(isWait(found))
        #expect(session.menuTitle == "Update Available…")
        #expect(choices.isEmpty)
    }

    @Test func aScheduledReminderOfADownloadedUpdateShowsNoWindowAndTheBannerInstallsIt() {
        var session = SoftwareUpdateSession()
        var choices: [Choice] = []
        let found = session.found(version: "1.9.0", downloaded: true, userInitiated: false) { choices.append($0) }
        #expect(isWait(found))
        run(session.installAndRelaunch())
        #expect(choices == [.install])
    }

    @Test func closingTheCheckingWindowCancelsTheCheck() {
        var session = SoftwareUpdateSession()
        var cancelled = 0
        session.beginCheck { cancelled += 1 }
        session.statusClosed()?()
        #expect(cancelled == 1)
    }

    @Test func closingTheDownloadWindowCancelsTheDownload() {
        var session = SoftwareUpdateSession()
        var cancelled = 0
        session.beginDownload { cancelled += 1 }
        session.statusClosed()?()
        #expect(cancelled == 1)
    }

    @Test func closingAReadyWindowKeepsTheUpdateReadyForTheBanner() {
        var session = SoftwareUpdateSession()
        var choices: [Choice] = []
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { choices.append($0) }
        session.choose(.install)?()
        session.beginPreparing()
        _ = session.ready { choices.append($0) }
        #expect(session.statusClosed() == nil)
        #expect(session.phase == .readyToInstall(version: "1.9.0"))
        run(session.installAndRelaunch())
        #expect(choices == [.install, .install])
    }

    @Test func remindMeLaterDismissesAnUpdateThatIsNotDownloaded() {
        var session = SoftwareUpdateSession()
        var choices: [Choice] = []
        _ = session.found(version: "2.0.0", downloaded: false, userInitiated: true) { choices.append($0) }
        session.choose(.dismiss)?()
        session.dismissed()
        #expect(choices == [.dismiss])
        #expect(session.phase == .idle)
    }

    @Test func aDismissedDownloadedUpdateStaysReady() {
        var choices: [Choice] = []
        let session = dismissedDownload(choices: &choices)
        #expect(session.phase == .readyToInstall(version: "1.9.0"))
        #expect(session.menuTitle == "Update Available…")
        #expect(!session.installsWithoutWindow)
    }

    @Test func restartAndUpdateResumesADismissedDownloadAndInstallsWithoutAnotherWindow() {
        var recorded: [Choice] = []
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { recorded.append($0) }
        session.choose(.dismiss)?()
        session.dismissed()
        guard case .resume? = session.installAndRelaunch() else { Issue.record("Restart and Update resumes it"); return }
        session.beginCheck {}
        let found = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { recorded.append($0) }
        guard case .install(let install) = found else { Issue.record("The resumed find installs without another window"); return }
        install()
        #expect(recorded == [.dismiss, .install])
    }

    @Test func aNewerUpdateThatIsNotDownloadedAsksFirstAfterResuming() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { _ in }
        session.choose(.dismiss)?()
        session.dismissed()
        _ = session.installAndRelaunch()
        let found = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        #expect(isPresent(found))
        #expect(session.phase == .available(version: "1.9.0"))
    }

    @Test func aResumedUpdateThatStillNeedsPreparingInstallsWhenReady() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { _ in }
        session.choose(.dismiss)?()
        session.dismissed()
        _ = session.installAndRelaunch()
        _ = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { _ in }
        session.beginPreparing()
        #expect(session.ready { _ in } != nil)
    }

    @Test func cancellingTheResumedCheckKeepsTheUpdateReadyAndDoesNotInstallOnTheNextCheck() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { _ in }
        session.choose(.dismiss)?()
        session.dismissed()
        _ = session.installAndRelaunch()
        session.beginCheck {}
        session.statusClosed()?()
        session.dismissed()
        #expect(session.phase == .readyToInstall(version: "1.9.0"))
        let found = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { _ in }
        #expect(isPresent(found))
    }

    @Test func upToDateClearsADismissedUpdate() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { _ in }
        session.choose(.dismiss)?()
        session.dismissed()
        session.beginCheck {}
        session.upToDate {}
        #expect(session.phase == .idle)
        #expect(session.installAndRelaunch() == nil)
    }

    @Test func sparklesInstallHandlerMayBeRetried() {
        var session = SoftwareUpdateSession()
        var installs = 0
        session.downloadedInBackground(version: "1.9.0") { installs += 1 }
        run(session.installAndRelaunch())
        run(session.installAndRelaunch())
        #expect(installs == 2)
        #expect(session.phase == .installing)
    }

    @Test func aCancelledQuitWhileInstallingCanBeRetriedWithoutAWindow() {
        var session = SoftwareUpdateSession()
        var retries = 0
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        session.choose(.install)?()
        session.beginInstalling(retry: { retries += 1 })
        #expect(session.installsWithoutWindow)
        run(session.installAndRelaunch())
        #expect(retries == 1)
        #expect(session.phase == .installing)
    }

    @Test func onceTheAppTerminatedThereIsNothingToRetryOrInstall() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        session.choose(.install)?()
        session.beginInstalling(retry: { })
        session.beginInstalling(retry: nil)
        #expect(session.installAndRelaunch() == nil)
        #expect(!session.installsWithoutWindow)
    }

    @Test func aFailedInstallDropsItsRetryHandler() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        session.choose(.install)?()
        session.beginInstalling(retry: {})
        session.failed()
        session.dismissed()
        #expect(session.phase == .idle)
        #expect(session.installAndRelaunch() == nil)
    }

    @Test func acknowledgingMayRentrantlyDismiss() {
        var session = SoftwareUpdateSession()
        session.upToDate { session.dismissed() }
        session.acknowledge()?()
        #expect(session.phase == .idle)
    }

    @Test func dismissingMayRentrantlyEndTheSession() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in session.dismissed() }
        session.choose(.dismiss)?()
        #expect(session.phase == .idle)
    }

    @Test func cancellingMayRentrantlyReportAFailure() {
        var session = SoftwareUpdateSession()
        session.beginCheck { session.failed() }
        session.cancel()?()
        #expect(session.phase == .idle)
    }

    @Test func aReleasedBuildsCheckForUpdatesHasNoTooltip() {
        let released = SoftwareUpdateSession()
        #expect(released.hasFeed)
        #expect(released.menuToolTip == nil)
    }

    @Test func aBuildWithoutAFeedKeepsCheckForUpdatesAndExplainsWhyItIsDisabled() {
        let local = SoftwareUpdateSession(hasFeed: false)
        #expect(!local.hasFeed)
        #expect(local.menuTitle == "Check for Updates…")
        #expect(local.menuToolTip == "Updates are only available in released builds")
    }
}
