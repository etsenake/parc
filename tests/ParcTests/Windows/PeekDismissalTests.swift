import Foundation
import Testing
@testable import Parc

struct PeekDismissalTests {
    typealias Owner = PeekDismissalConfirmation
    typealias Reason = Owner.Reason

    private struct Scheduled {
        let delay: TimeInterval
        let item: DispatchWorkItem
    }

    @MainActor private final class Clock {
        var scheduled: [Scheduled] = []
        lazy var owner = PeekDismissalConfirmation { [unowned self] delay, item in scheduled.append(Scheduled(delay: delay, item: item)) }

        func fire(_ index: Int) { scheduled[index].item.perform() }
    }

    struct Context: Sendable, CustomTestStringConvertible {
        let awaiting: Int
        let mediaInput: Bool
        var reason: Reason? { [nil, .escape, .mediaInput][awaiting] }
        var testDescription: String { "awaiting \(String(describing: reason)), media \(mediaInput)" }
        static let all = (0..<3).flatMap { awaiting in [false, true].map { Context(awaiting: awaiting, mediaInput: $0) } }
        var index: Int { [0, 2, 4][awaiting] + (mediaInput ? 1 : 0) }
    }

    private static let matrix: [(Owner.Dismissal, [Reason?])] = [
        (.escape(prefersConfirmation: false), [nil, nil, nil, nil, nil, nil]),
        (.escape(prefersConfirmation: true), [.escape, .escape, nil, nil, nil, nil]),
        (.closeButton, [nil, .mediaInput, nil, nil, nil, nil]),
        (.exit, [nil, .mediaInput, nil, nil, nil, nil]),
        (.background, [nil, .mediaInput, nil, nil, .mediaInput, .mediaInput]),
        (.closeShortcut, [nil, .mediaInput, nil, nil, nil, nil]),
        (.swipe, [nil, .mediaInput, nil, nil, .mediaInput, .mediaInput]),
    ]

    @MainActor @Test(arguments: 0..<7, Context.all)
    func theDismissalReasonMatrix(_ row: Int, _ context: Context) {
        let (mechanism, expected) = Self.matrix[row]
        #expect(Owner.requiredReason(for: mechanism, awaiting: context.reason, mediaInput: context.mediaInput) == expected[context.index])
    }

    @MainActor @Test func aNewOwnerHasNoConfirmationOrAttempt() {
        let clock = Clock()
        #expect(clock.owner.reason == nil)
        #expect(clock.owner.attempts == 0)
    }

    @MainActor @Test func backgroundWhileCapturingStartsHangUp() {
        let clock = Clock()
        #expect(clock.owner.request(.background, mediaInput: true) {} == .mediaInput)
        #expect(clock.owner.attempts == 1)
    }

    @MainActor @Test func aSwipeRetainsThePendingHangUpEvenIfCaptureJustStopped() {
        let clock = Clock()
        _ = clock.owner.request(.background, mediaInput: true) {}
        #expect(clock.owner.request(.swipe, mediaInput: false) {} == .mediaInput)
        #expect(clock.owner.attempts == 2)
    }

    @MainActor @Test func aRepeatedBackgroundDoesNotBecomeConsent() {
        let clock = Clock()
        _ = clock.owner.request(.background, mediaInput: true) {}
        _ = clock.owner.request(.swipe, mediaInput: false) {}
        #expect(clock.owner.request(.background, mediaInput: false) {} == .mediaInput)
        #expect(clock.owner.attempts == 3)
    }

    @MainActor @Test func explicitEscapeConfirmsAPendingHangUpAndClearsState() {
        let clock = Clock()
        _ = clock.owner.request(.background, mediaInput: true) {}
        #expect(clock.owner.request(.escape(prefersConfirmation: true), mediaInput: true) {} == nil)
        #expect(clock.owner.reason == nil)
        #expect(clock.owner.attempts == 0)
    }

    @MainActor @Test func aFreshEscapeUsesItsReasonBeforeInspectingCapture() {
        let clock = Clock()
        #expect(clock.owner.request(.escape(prefersConfirmation: true), mediaInput: true) {} == .escape)
        #expect(clock.owner.attempts == 1)
    }

    @MainActor @Test func closeTabConfirmsThePendingEscapePrompt() {
        let clock = Clock()
        _ = clock.owner.request(.escape(prefersConfirmation: true), mediaInput: true) {}
        #expect(clock.owner.request(.closeShortcut, mediaInput: true) {} == nil)
    }

    @MainActor @Test func aNativeUnconfirmedEscapePassesThroughWithoutATimer() {
        let clock = Clock()
        #expect(clock.owner.request(.escape(prefersConfirmation: false), mediaInput: true) {} == nil)
        #expect(clock.scheduled.isEmpty)
    }

    @MainActor @Test func escapeReferenceDurationIsOneSecond() {
        #expect(Reason.escape.duration == 1)
    }

    @MainActor @Test func mediaReferenceDurationIsTenSeconds() {
        #expect(Reason.mediaInput.duration == 10)
    }

    @MainActor @Test func armingSchedulesTheReasonsDuration() {
        let clock = Clock()
        clock.owner.arm(.mediaInput) {}
        #expect(clock.scheduled.map(\.delay) == [10])
    }

    @MainActor @Test func theOwnerIsArmedSynchronously() {
        let clock = Clock()
        clock.owner.arm(.escape) {}
        #expect(clock.owner.reason == .escape)
    }

    @MainActor @Test func expiryClearsStateBeforeNotifyingTheView() {
        let clock = Clock()
        var seen: (Reason?, Int)?
        clock.owner.arm(.escape) { seen = (clock.owner.reason, clock.owner.attempts) }
        clock.fire(0)
        #expect(seen?.0 == nil)
        #expect(seen?.1 == 0)
    }

    @MainActor @Test func expiryIsDeliveredOnce() {
        let clock = Clock()
        var expirations = 0
        clock.owner.arm(.escape) { expirations += 1 }
        clock.fire(0)
        clock.fire(0)
        #expect(expirations == 1)
    }

    @MainActor @Test func aReplacedPendingCallbackIsCancelled() {
        let clock = Clock()
        var stale = 0, fresh = 0
        clock.owner.arm(.escape) { stale += 1 }
        clock.owner.arm(.mediaInput) { fresh += 1 }
        clock.fire(0)
        #expect(stale == 0)
        #expect(clock.owner.reason == .mediaInput)
        clock.fire(1)
        #expect(fresh == 1)
        #expect(clock.owner.reason == nil)
    }

    @MainActor @Test func cancelIsImmediateAndIdempotentAndClearsAttempts() {
        let clock = Clock()
        clock.owner.arm(.escape) {}
        clock.owner.cancel()
        clock.owner.cancel()
        #expect(clock.owner.reason == nil)
        #expect(clock.owner.attempts == 0)
    }

    @MainActor @Test func aCancelledOwnerGetsNoLaterExpiry() {
        let clock = Clock()
        var expirations = 0
        clock.owner.arm(.escape) { expirations += 1 }
        clock.owner.cancel()
        clock.fire(0)
        #expect(expirations == 0)
    }

    @MainActor @Test func aNewGenerationSurvivesCallbackReentrancy() {
        let clock = Clock()
        clock.owner.arm(.escape) { clock.owner.arm(.mediaInput) {} }
        clock.fire(0)
        #expect(clock.owner.reason == .mediaInput)
    }

    @MainActor @Test func theSchedulerDoesNotRetainARetiredOwner() {
        var scheduled: [DispatchWorkItem] = []
        var retiring: PeekDismissalConfirmation? = PeekDismissalConfirmation { _, item in scheduled.append(item) }
        weak let released = retiring
        var stale = 0
        retiring?.arm(.escape) { stale += 1 }
        retiring = nil
        #expect(released == nil)
        scheduled.forEach { $0.perform() }
        #expect(stale == 0)
    }
}
