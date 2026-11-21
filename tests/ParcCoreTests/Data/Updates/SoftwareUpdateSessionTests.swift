import Foundation
import Testing
@testable import ParcCore

struct SoftwareUpdateSessionTests {
    typealias Choice = SoftwareUpdateSession.Choice

    func run(_ install: SoftwareUpdateSession.Install?) {
        if case .run(let reply)? = install { reply() }
    }

    func isPresent(_ found: SoftwareUpdateSession.Found) -> Bool {
        if case .present = found { return true }
        return false
    }

    func isWait(_ found: SoftwareUpdateSession.Found) -> Bool {
        if case .wait = found { return true }
        return false
    }

    func dismissedDownload(_ choices: inout [Choice]) -> SoftwareUpdateSession {
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
        #expect(session.phase == .idle && session.menuTitle == "Check for Updates…")
    }

    @Test func aCheckKeepsTheIdleTitle() {
        var session = SoftwareUpdateSession()
        session.beginCheck {}
        #expect(session.phase == .checking && session.menuTitle == "Check for Updates…")
    }

    @Test func upToDateReturnsToIdleAndTheFinishedCheckCannotBeCancelled() {
        var session = SoftwareUpdateSession()
        session.beginCheck {}
        session.upToDate {}
        #expect(session.phase == .idle)
        let cancelled = session.cancel()
        #expect(cancelled == nil)
    }

    @Test func closingTheNoticeAcknowledgesItExactlyOnce() {
        var session = SoftwareUpdateSession()
        var cancelled = 0
        var acknowledged = 0
        session.beginCheck { cancelled += 1 }
        session.upToDate { acknowledged += 1 }
        session.acknowledge()?()
        session.acknowledge()?()
        #expect(acknowledged == 1 && cancelled == 0)
    }

    @Test func aManualCheckShowsTheUpdateWindowForAnUndownloadedUpdate() {
        var session = SoftwareUpdateSession()
        session.beginCheck {}
        let found = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        #expect(isPresent(found))
        #expect(session.phase == .available(version: "1.9.0") && session.menuTitle == "Update Available…")
    }

    @Test func nothingInstallsBeforeItIsDownloaded() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        let install = session.installAndRelaunch()
        #expect(install == nil)
    }

    @Test func downloadAnswersSparkleOnce() {
        var session = SoftwareUpdateSession()
        var choices: [Choice] = []
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { choices.append($0) }
        session.choose(.install)?()
        session.choose(.dismiss)?()
        #expect(choices == [.install])
    }

    @Test func downloadingReadsUpdatingAndPreparingCannotBeCancelled() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        session.choose(.install)?()
        session.beginDownload {}
        #expect(session.phase == .downloading && session.menuTitle == "Updating…")
        session.beginPreparing()
        let cancelled = session.cancel()
        #expect(session.phase == .preparing && cancelled == nil)
    }

    @Test func readyWaitsForThePersonAndCarriesTheFoundVersion() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        session.choose(.install)?()
        session.beginPreparing()
        let ready = session.ready { _ in }
        #expect(ready == nil)
        #expect(session.phase == .readyToInstall(version: "1.9.0"))
    }

    @Test func installAndRelaunchAnswersTheReadyReplyOnceThenDoesNothing() {
        var session = SoftwareUpdateSession()
        var choices: [Choice] = []
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { choices.append($0) }
        session.choose(.install)?()
        session.beginPreparing()
        _ = session.ready { choices.append($0) }
        run(session.installAndRelaunch())
        #expect(choices == [.install, .install])
        let again = session.installAndRelaunch()
        #expect(again == nil)
    }

    @Test func installingReadsUpdatingAndSparkleEndingTheSessionReturnsToIdle() {
        var session = SoftwareUpdateSession()
        var cancelled = 0
        session.beginDownload { cancelled += 1 }
        session.beginInstalling(retry: nil)
        #expect(session.phase == .installing && session.menuTitle == "Updating…")
        session.dismissed()
        #expect(session.phase == .idle && cancelled == 0)
    }

    @Test func aSilentDownloadIsReadyForTheBannerAndInstallsWithoutAWindow() {
        var session = SoftwareUpdateSession()
        session.downloadedInBackground(version: "1.9.0") {}
        #expect(session.phase == .readyToInstall(version: "1.9.0") && session.menuTitle == "Update Available…")
        #expect(session.installsWithoutWindow)
    }

    @Test func anUnrelatedSessionEndKeepsTheBackgroundUpdateReadyAndRestartRunsSparklesInstallHandler() {
        var session = SoftwareUpdateSession()
        var installed = 0
        session.downloadedInBackground(version: "1.9.0") { installed += 1 }
        session.dismissed()
        #expect(session.phase == .readyToInstall(version: "1.9.0"))
        run(session.installAndRelaunch())
        #expect(installed == 1 && session.phase == .installing)
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
        #expect(choices == [.install] && installed == 0)
    }

    @Test func aScheduledFindShowsNoWindowAndWaitsForTheMenu() {
        var session = SoftwareUpdateSession()
        var choices: [Choice] = []
        let found = session.found(version: "1.9.0", downloaded: false, userInitiated: false) { choices.append($0) }
        #expect(isWait(found))
        #expect(session.menuTitle == "Update Available…" && choices.isEmpty)
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

    @Test func closingAReadyWindowKeepsTheUpdateReadyAndTheBannerCanStillInstall() {
        var session = SoftwareUpdateSession()
        var choices: [Choice] = []
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { choices.append($0) }
        session.choose(.install)?()
        session.beginPreparing()
        _ = session.ready { choices.append($0) }
        let closed = session.statusClosed()
        #expect(closed == nil && session.phase == .readyToInstall(version: "1.9.0"))
        run(session.installAndRelaunch())
        #expect(choices == [.install, .install])
    }

    @Test func remindMeLaterDismissesAnUpdateThatIsntDownloaded() {
        var session = SoftwareUpdateSession()
        var choices: [Choice] = []
        _ = session.found(version: "2.0.0", downloaded: false, userInitiated: true) { choices.append($0) }
        session.choose(.dismiss)?()
        session.dismissed()
        #expect(choices == [.dismiss] && session.phase == .idle)
    }

    @Test func aDismissedDownloadedUpdateStaysReadyAndIsNotInstalledAutomatically() {
        var choices: [Choice] = []
        let session = dismissedDownload(&choices)
        #expect(session.phase == .readyToInstall(version: "1.9.0") && session.menuTitle == "Update Available…")
        #expect(!session.installsWithoutWindow)
    }

    @Test func restartAndUpdateResumesItAndTheResumedFindInstallsWithoutAnotherWindow() {
        var session = SoftwareUpdateSession()
        var choices: [Choice] = []
        _ = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { choices.append($0) }
        session.choose(.dismiss)?()
        session.dismissed()
        guard case .resume? = session.installAndRelaunch() else {
            Issue.record("Restart and Update resumes it")
            return
        }
        session.beginCheck {}
        guard case .install(let install) = session.found(version: "1.9.0", downloaded: true, userInitiated: true,
                                                         reply: { choices.append($0) }) else {
            Issue.record("The resumed find installs without another window")
            return
        }
        install()
        #expect(choices == [.dismiss, .install])
    }

    @Test func aNewerUpdateThatIsntDownloadedAsksFirst() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { _ in }
        session.choose(.dismiss)?()
        session.dismissed()
        _ = session.installAndRelaunch()
        guard case .present = session.found(version: "1.9.0", downloaded: false, userInitiated: true, reply: { _ in }) else {
            Issue.record("A newer update that isn't downloaded asks first")
            return
        }
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
        let ready = session.ready { _ in }
        #expect(ready != nil)
    }

    @Test func cancellingTheResumedCheckKeepsTheUpdateReadyAndTheNextCheckDoesNotInstall() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { _ in }
        session.choose(.dismiss)?()
        session.dismissed()
        _ = session.installAndRelaunch()
        session.beginCheck {}
        session.statusClosed()?()
        session.dismissed()
        #expect(session.phase == .readyToInstall(version: "1.9.0"))
        guard case .present = session.found(version: "1.9.0", downloaded: true, userInitiated: true, reply: { _ in }) else {
            Issue.record("A cancelled Restart and Update doesn't install on the next check")
            return
        }
    }

    @Test func upToDateClearsADismissedUpdate() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: true, userInitiated: true) { _ in }
        session.choose(.dismiss)?()
        session.dismissed()
        session.beginCheck {}
        session.upToDate {}
        let install = session.installAndRelaunch()
        #expect(session.phase == .idle && install == nil)
    }

    @Test func sparklesInstallHandlerMayBeRetried() {
        var session = SoftwareUpdateSession()
        var installs = 0
        session.downloadedInBackground(version: "1.9.0") { installs += 1 }
        run(session.installAndRelaunch())
        run(session.installAndRelaunch())
        #expect(installs == 2 && session.phase == .installing)
    }

    @Test func aCancelledQuitWhileInstallingCanBeRetriedWithoutAWindow() {
        var session = SoftwareUpdateSession()
        var retries = 0
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        session.choose(.install)?()
        session.beginInstalling(retry: { retries += 1 })
        #expect(session.installsWithoutWindow)
        run(session.installAndRelaunch())
        #expect(retries == 1 && session.phase == .installing)
    }

    @Test func onceTheAppTerminatedThereIsNothingToRetryOrInstall() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        session.choose(.install)?()
        session.beginInstalling(retry: nil)
        let install = session.installAndRelaunch()
        #expect(install == nil)
        #expect(!session.installsWithoutWindow)
    }

    @Test func aFailedInstallDropsItsRetryHandler() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in }
        session.choose(.install)?()
        session.beginInstalling(retry: {})
        session.failed()
        session.dismissed()
        let install = session.installAndRelaunch()
        #expect(session.phase == .idle && install == nil)
    }

    @Test func acknowledgingMaySynchronouslyDismiss() {
        var session = SoftwareUpdateSession()
        session.upToDate { session.dismissed() }
        session.acknowledge()?()
        #expect(session.phase == .idle)
    }

    @Test func dismissingMaySynchronouslyEndTheSession() {
        var session = SoftwareUpdateSession()
        _ = session.found(version: "1.9.0", downloaded: false, userInitiated: true) { _ in session.dismissed() }
        session.choose(.dismiss)?()
        #expect(session.phase == .idle)
    }

    @Test func cancellingMaySynchronouslyReportAFailure() {
        var session = SoftwareUpdateSession()
        session.beginCheck { session.failed() }
        session.cancel()?()
        #expect(session.phase == .idle)
    }

    @Test func aReleasedBuildsCheckForUpdatesHasNoTooltip() {
        let released = SoftwareUpdateSession()
        #expect(released.hasFeed && released.menuToolTip == nil)
    }

    @Test func aBuildWithoutAFeedKeepsCheckForUpdatesAndSaysWhyItIsDisabled() {
        let local = SoftwareUpdateSession(hasFeed: false)
        #expect(!local.hasFeed && local.menuTitle == "Check for Updates…")
        #expect(local.menuToolTip == "Updates are only available in released builds")
    }
}
