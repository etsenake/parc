import Foundation
import Testing
@testable import ParcCore

@MainActor struct EmbeddedPageLifecycleTests {
    @Test func aFreshOwnerAdmitsPagesInputPublicationAndTransfer() {
        var gate = EmbeddedPageOwnerGate()
        #expect(gate.admitsCreation && gate.admitsInput && gate.publishesPages && gate.admitsTransferSnapshot, "a fresh owner admits pages, input, publication and transfer")
        let hoisted9 = gate.beginRetirement()
        #expect(hoisted9, "retirement starts once")
        let hoisted10 = !gate.beginRetirement()
        #expect(hoisted10, "a second retirement is refused while the first is pending")
        #expect(!gate.admitsCreation && !gate.admitsInput && gate.publishesPages, "retirement blocks creation and input, not visibility")
        let hoisted12 = !gate.beginTransfer(generation: gate.transferGeneration)
        #expect(hoisted12, "a retiring owner can't start a window transfer")
        gate.endRetirement()
        #expect(gate.admitsCreation, "ending retirement reopens the owner")
        let generation = gate.transferGeneration
        let hoisted16 = gate.beginTransfer(generation: generation)
        #expect(hoisted16, "transfer starts at the current generation")
        #expect(gate.isTransferring && !gate.publishesPages && !gate.admitsInput && !gate.admitsCreation, "transfer suspends publication, input and creation")
        let hoisted18 = !gate.beginTransfer(generation: generation)
        #expect(hoisted18, "transfer can't start twice")
        let hoisted19 = !gate.beginRetirement()
        #expect(hoisted19, "retirement waits for the transfer")
        gate.finishTransfer()
        #expect(!gate.isTransferring && gate.transferGeneration == generation &+ 1, "finishing advances the generation")
        let hoisted22 = !gate.beginTransfer(generation: generation)
        #expect(hoisted22, "an old snapshot can't be replayed after finishing")
        let hoisted23 = gate.beginTransfer(generation: gate.transferGeneration)
        #expect(hoisted23, "a fresh snapshot can begin the next move")
        gate.finishTransfer()
        gate.dispose()
        #expect(gate.isDisposed && !gate.admitsCreation && !gate.publishesPages && !gate.admitsTransferSnapshot, "a disposed owner never admits anything again")
        let hoisted27 = !gate.beginTransfer(generation: gate.transferGeneration)
        #expect(hoisted27, "a disposed owner refuses transfers")
        #expect(gate.admitsInput, "input stays a transfer and retirement gate, so disposal alone doesn't flip it")
    }

    @Test func equalValuesMatch() {
        struct Layout: Equatable { var x: Int }
        #expect(EmbeddedPageFingerprint(Layout(x: 1)) == EmbeddedPageFingerprint(Layout(x: 1)), "equal values match")
        #expect(EmbeddedPageFingerprint(Layout(x: 1)) != EmbeddedPageFingerprint(Layout(x: 2)), "different values differ")
        #expect(EmbeddedPageFingerprint(1) != EmbeddedPageFingerprint("1"), "different types never match")
        #expect(EmbeddedPageFingerprint(["a": 1]).unwrap([String: Int].self) == ["a": 1], "the value unwraps back")
        let none: EmbeddedPageFingerprint? = nil
        #expect(none != EmbeddedPageFingerprint(Layout(x: 1)), "a missing variant differs from a present one")
    }

    @Test func pagesHiddenPastFourHoursFallAsleep() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = now.addingTimeInterval(-EmbeddedPageSleepPolicy.idleInterval - 1)
        let idle = EmbeddedPageSleepPolicy.Candidate(lastShown: old, shown: false, closing: false, transferring: false,
                                                     editing: false, pendingCreation: false, pages: [.eligible, .eligible])
        #expect(EmbeddedPageSleepPolicy.shouldSleep(idle, now: now), "pages hidden past four hours fall asleep")
        var recent = idle
        recent.lastShown = now.addingTimeInterval(-EmbeddedPageSleepPolicy.idleInterval + 60)
        #expect(!EmbeddedPageSleepPolicy.shouldSleep(recent, now: now), "pages shown within four hours stay awake")
        for change: (inout EmbeddedPageSleepPolicy.Candidate) -> Void in [
            { $0.shown = true }, { $0.closing = true }, { $0.transferring = true }, { $0.editing = true },
            { $0.pendingCreation = true }, { $0.pages = [] }, { $0.pages = [.eligible, .protected] }, { $0.pages = [.unknown] }
        ] {
            var candidate = idle
            change(&candidate)
            #expect(!EmbeddedPageSleepPolicy.shouldSleep(candidate, now: now), "a busy, shown, moving or empty owner never sleeps")
        }
    }
}
