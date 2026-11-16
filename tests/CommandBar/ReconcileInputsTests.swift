@main
struct ReconcileInputsTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        var closedBuilds = 0
        CommandBarReconcileInputs.withPresentedBar(Optional<Int>.none) { _ in
            closedBuilds += 1
        }
        expect(closedBuilds == 0, "Nil command bar must skip all reconcile input snapshots")

        var openBuilds = 0
        var received: Int?
        CommandBarReconcileInputs.withPresentedBar(Optional.some(7)) { bar in
            openBuilds += 1
            received = bar
        }
        expect(openBuilds == 1, "Presented command bar must still build reconcile inputs once")
        expect(received == 7, "Presented bar is the same instance passed into reconcile")

        print("\(assertions) command-bar reconcile input gate assertions passed")
    }
}
