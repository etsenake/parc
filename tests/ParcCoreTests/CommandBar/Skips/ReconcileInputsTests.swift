import Testing
@testable import ParcCore

struct ReconcileInputsTests {
    @Test func aNilCommandBarSkipsEveryReconcileInputSnapshot() {
        var builds = 0
        CommandBarReconcileInputs.withPresentedBar(Optional<Int>.none) { _ in builds += 1 }
        #expect(builds == 0)
    }

    @Test func aPresentedCommandBarBuildsReconcileInputsOnce() {
        var builds = 0
        CommandBarReconcileInputs.withPresentedBar(Optional.some(7)) { _ in builds += 1 }
        #expect(builds == 1)
    }

    @Test func theSameBarInstanceIsPassedIntoReconcile() {
        var received: Int?
        CommandBarReconcileInputs.withPresentedBar(Optional.some(7)) { received = $0 }
        #expect(received == 7)
    }
}
