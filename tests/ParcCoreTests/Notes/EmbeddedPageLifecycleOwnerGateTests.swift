import Foundation
import Testing
@testable import ParcCore

struct EmbeddedPageLifecycleOwnerGateTests {
    @Test func aFreshOwnerAdmitsPagesInputPublicationAndTransfer() {
        let gate = EmbeddedPageOwnerGate()
        #expect(gate.admitsCreation && gate.admitsInput && gate.publishesPages && gate.admitsTransferSnapshot, "a fresh owner admits pages, input, publication and transfer")
    }

    @Test func retirementStartsOnlyOnce() {
        var gate = EmbeddedPageOwnerGate()
        let beganRetirement = gate.beginRetirement()
        #expect(beganRetirement, "retirement starts once")
        let retirementWasRefused = !gate.beginRetirement()
        #expect(retirementWasRefused, "a second retirement is refused while the first is pending")
    }

    @Test func retirementBlocksCreationAndInputButKeepsPublication() {
        var gate = EmbeddedPageOwnerGate()
        _ = gate.beginRetirement()
        #expect(!gate.admitsCreation && !gate.admitsInput && gate.publishesPages, "retirement blocks creation and input, not visibility")
    }

    @Test func aRetiringOwnerCannotBeginATransfer() {
        var gate = EmbeddedPageOwnerGate()
        _ = gate.beginRetirement()
        let transferWasRefused = !gate.beginTransfer(generation: gate.transferGeneration)
        #expect(transferWasRefused, "a retiring owner can't start a window transfer")
    }

    @Test func endingRetirementReadmitsCreation() {
        var gate = EmbeddedPageOwnerGate()
        _ = gate.beginRetirement()
        gate.endRetirement()
        #expect(gate.admitsCreation, "ending retirement reopens the owner")
    }

    @Test func aTransferStartsAtTheCurrentGeneration() {
        var gate = EmbeddedPageOwnerGate()
        let generation = gate.transferGeneration
        let beganTransfer = gate.beginTransfer(generation: generation)
        #expect(beganTransfer, "transfer starts at the current generation")
    }

    @Test func transferSuspendsPublicationInputAndCreation() {
        var gate = EmbeddedPageOwnerGate()
        let generation = gate.transferGeneration
        _ = gate.beginTransfer(generation: generation)
        #expect(gate.isTransferring && !gate.publishesPages && !gate.admitsInput && !gate.admitsCreation, "transfer suspends publication, input and creation")
    }

    @Test func transferCannotStartTwice() {
        var gate = EmbeddedPageOwnerGate()
        let generation = gate.transferGeneration
        _ = gate.beginTransfer(generation: generation)
        let transferWasRefused = !gate.beginTransfer(generation: generation)
        #expect(transferWasRefused, "transfer can't start twice")
    }

    @Test func anOwnerCannotRetireDuringTransfer() {
        var gate = EmbeddedPageOwnerGate()
        let generation = gate.transferGeneration
        _ = gate.beginTransfer(generation: generation)
        let retirementWasRefused = !gate.beginRetirement()
        #expect(retirementWasRefused, "retirement waits for the transfer")
    }

    @Test func finishingATransferAdvancesTheGeneration() {
        var gate = EmbeddedPageOwnerGate()
        let generation = gate.transferGeneration
        _ = gate.beginTransfer(generation: generation)
        gate.finishTransfer()
        #expect(!gate.isTransferring && gate.transferGeneration == generation &+ 1, "finishing advances the generation")
    }

    @Test func aFinishedTransferCannotReplayItsOldSnapshot() {
        var gate = EmbeddedPageOwnerGate()
        let generation = gate.transferGeneration
        _ = gate.beginTransfer(generation: generation)
        gate.finishTransfer()
        let transferWasRefused = !gate.beginTransfer(generation: generation)
        #expect(transferWasRefused, "an old snapshot can't be replayed after finishing")
    }

    @Test func aFreshSnapshotCanBeginTheNextTransfer() {
        var gate = EmbeddedPageOwnerGate()
        let generation = gate.transferGeneration
        _ = gate.beginTransfer(generation: generation)
        gate.finishTransfer()
        let beganTransfer = gate.beginTransfer(generation: gate.transferGeneration)
        #expect(beganTransfer, "a fresh snapshot can begin the next move")
    }

    @Test func disposalDisablesPageAdmissionAndPublication() {
        var gate = EmbeddedPageOwnerGate()
        gate.dispose()
        #expect(gate.isDisposed && !gate.admitsCreation && !gate.publishesPages && !gate.admitsTransferSnapshot, "a disposed owner never admits anything again")
    }

    @Test func aDisposedOwnerRefusesTransfers() {
        var gate = EmbeddedPageOwnerGate()
        gate.dispose()
        let transferWasRefused = !gate.beginTransfer(generation: gate.transferGeneration)
        #expect(transferWasRefused, "a disposed owner refuses transfers")
    }

    @Test func disposalAloneLeavesInputAdmitted() {
        var gate = EmbeddedPageOwnerGate()
        gate.dispose()
        #expect(gate.admitsInput, "input stays a transfer and retirement gate, so disposal alone doesn't flip it")
    }

    @Test func equalValuesHaveEqualFingerprints() {
        struct Layout: Equatable { var x: Int }
        #expect(EmbeddedPageFingerprint(Layout(x: 1)) == EmbeddedPageFingerprint(Layout(x: 1)), "equal values match")
    }

    @Test func unequalValuesHaveUnequalFingerprints() {
        struct Layout: Equatable { var x: Int }
        #expect(EmbeddedPageFingerprint(Layout(x: 1)) != EmbeddedPageFingerprint(Layout(x: 2)), "different values differ")
    }

    @Test func valuesOfDifferentTypesHaveDifferentFingerprints() {
        #expect(EmbeddedPageFingerprint(1) != EmbeddedPageFingerprint("1"), "different types never match")
    }

    @Test func aFingerprintUnwrapsItsOriginalValue() {
        #expect(EmbeddedPageFingerprint(["a": 1]).unwrap([String: Int].self) == ["a": 1], "the value unwraps back")
    }

    @Test func aMissingFingerprintDiffersFromAPresentOne() {
        struct Layout: Equatable { var x: Int }
        let none: EmbeddedPageFingerprint? = nil
        #expect(none != EmbeddedPageFingerprint(Layout(x: 1)), "a missing variant differs from a present one")
    }
}
