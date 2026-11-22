import Foundation
import Testing
@testable import ParcCore

struct EmbeddedPageLifecycleSleepPolicyTests {
    struct SleepException: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let change: @Sendable (inout EmbeddedPageSleepPolicy.Candidate) -> Void
    }

    private static let sleepExceptions = [
        SleepException(testDescription: "shown", change: { $0.shown = true }),
        SleepException(testDescription: "closing", change: { $0.closing = true }),
        SleepException(testDescription: "transferring", change: { $0.transferring = true }),
        SleepException(testDescription: "editing", change: { $0.editing = true }),
        SleepException(testDescription: "pending creation", change: { $0.pendingCreation = true }),
        SleepException(testDescription: "no pages", change: { $0.pages = [] }),
        SleepException(testDescription: "protected page", change: { $0.pages = [.eligible, .protected] }),
        SleepException(testDescription: "unknown page", change: { $0.pages = [.unknown] }),
    ]

    @Test func pagesHiddenPastFourHoursFallAsleep() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = now.addingTimeInterval(-EmbeddedPageSleepPolicy.idleInterval - 1)
        let idle = EmbeddedPageSleepPolicy.Candidate(lastShown: old, shown: false, closing: false, transferring: false,
                                                     editing: false, pendingCreation: false, pages: [.eligible, .eligible])
        #expect(EmbeddedPageSleepPolicy.shouldSleep(idle, now: now), "pages hidden past four hours fall asleep")
    }

    @Test func recentlyShownPagesStayAwake() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = now.addingTimeInterval(-EmbeddedPageSleepPolicy.idleInterval - 1)
        let idle = EmbeddedPageSleepPolicy.Candidate(lastShown: old, shown: false, closing: false, transferring: false,
                                                     editing: false, pendingCreation: false, pages: [.eligible, .eligible])
        var recent = idle
        recent.lastShown = now.addingTimeInterval(-EmbeddedPageSleepPolicy.idleInterval + 60)
        #expect(!EmbeddedPageSleepPolicy.shouldSleep(recent, now: now), "pages shown within four hours stay awake")
    }

    @Test(arguments: sleepExceptions) func blockedOwnersStayAwake(_ example: SleepException) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = now.addingTimeInterval(-EmbeddedPageSleepPolicy.idleInterval - 1)
        let idle = EmbeddedPageSleepPolicy.Candidate(lastShown: old, shown: false, closing: false, transferring: false,
                                                     editing: false, pendingCreation: false, pages: [.eligible, .eligible])
        var candidate = idle
        example.change(&candidate)
        #expect(!EmbeddedPageSleepPolicy.shouldSleep(candidate, now: now))
    }
}
