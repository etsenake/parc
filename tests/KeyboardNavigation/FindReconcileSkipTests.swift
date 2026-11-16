@main
struct FindReconcileSkipTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        expect(FindReconcileSkip.shouldSkip(isPresented: false),
               "Closed Find with nothing to dismiss is a true no-op skip")
        expect(!FindReconcileSkip.shouldSkip(isPresented: true),
               "Presented Find must keep full reconcile (filter/dismiss/update/layout)")

        print("\(assertions) find reconcile skip assertions passed")
    }
}