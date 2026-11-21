import Testing
@testable import ParcCore

struct FindReconcileSkipTests {
    @Test func closedFindWithNothingToDismissIsATrueNoOpSkip() {
        #expect(FindReconcileSkip.shouldSkip(isPresented: false))
    }

    @Test func presentedFindKeepsTheFullReconcile() {
        #expect(!FindReconcileSkip.shouldSkip(isPresented: true))
    }
}
