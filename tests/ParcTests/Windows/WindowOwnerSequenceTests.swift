import Testing
@testable import Parc

struct WindowOwnerSequenceTests {
    @MainActor private final class Owner {
        var live = true, key = true, secure = true
        var performed: [Int] = []
        func valid() -> Bool { live && key && secure }
    }

    @MainActor @Test func aSequenceThatStaysValidRunsEveryStepAndCompletes() {
        let o = Owner()
        let complete = WindowOwnerSequence.run(while: o.valid, steps: [{ o.performed.append(1) }, { o.performed.append(2) }])
        #expect(complete)
        #expect(o.performed == [1, 2])
    }

    @MainActor @Test func anOwnerThatIsNotKeyRunsNothing() {
        let o = Owner()
        o.key = false
        #expect(!WindowOwnerSequence.run(while: o.valid, steps: [{ o.performed.append(1) }]))
        #expect(o.performed.isEmpty)
    }

    @MainActor @Test func theOwnerLosingKeyMidSequenceStopsAfterTheCurrentStep() {
        let o = Owner()
        let shifted = WindowOwnerSequence.run(while: o.valid, steps: [{ o.performed.append(1); o.key = false }, { o.performed.append(2) }])
        #expect(!shifted)
        #expect(o.performed == [1])
    }

    @MainActor @Test func aSecurityReservationMidSequenceStopsAfterTheCurrentStep() {
        let o = Owner()
        let reserved = WindowOwnerSequence.run(while: o.valid, steps: [{ o.performed.append(1); o.secure = false }, { o.performed.append(2) }])
        #expect(!reserved)
        #expect(o.performed == [1])
    }

    @MainActor @Test func theOwnerRetiringOnTheLastStepReportsIncomplete() {
        let o = Owner()
        let retired = WindowOwnerSequence.run(while: o.valid, steps: [{ o.performed.append(1); o.live = false }])
        #expect(!retired)
        #expect(o.performed == [1])
    }
}
