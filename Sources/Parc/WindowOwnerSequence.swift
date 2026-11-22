import Foundation

@MainActor
enum WindowOwnerSequence {
    static func run(while ownerIsCurrent: () -> Bool, steps: [() -> Void]) -> Bool {
        for step in steps {
            guard ownerIsCurrent() else { return false }
            step()
        }
        return ownerIsCurrent()
    }
}
