import Foundation

package enum EaselIdleSleep {
    package static func isEligible(lastAccessed: @autoclosure () -> Date?, shown: Bool, closing: Bool, transferring: Bool,
                           idleFor: TimeInterval, now: () -> Date = Date.init,
                           settled: @autoclosure () -> Bool) -> Bool {
        guard !shown, !closing, !transferring, let lastAccessed = lastAccessed(),
              lastAccessed < now().addingTimeInterval(-idleFor) else { return false }
        return settled()
    }
}
