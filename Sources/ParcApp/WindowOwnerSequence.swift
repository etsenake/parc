import Foundation

/// A window-owned operation can run callback-capable cleanup in order only
/// while the original owner remains current. A callback may retire the owner,
/// change key windows or introduce a security reservation synchronously.
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
