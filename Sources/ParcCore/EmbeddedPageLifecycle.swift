import Foundation

public struct EmbeddedPageFingerprint: Equatable {
    private let value: Any
    private let matches: (Any) -> Bool

    package init<Value: Equatable>(_ value: Value) {
        self.value = value
        matches = { ($0 as? Value) == value }
    }

    func unwrap<Value>(_ type: Value.Type) -> Value? { value as? Value }

    public static func == (lhs: EmbeddedPageFingerprint, rhs: EmbeddedPageFingerprint) -> Bool { lhs.matches(rhs.value) }
}

package struct EmbeddedPageOwnerGate: Equatable {
    package private(set) var isDisposed = false
    package private(set) var isRetiring = false
    private(set) var activeTransfer: UInt64?
    package private(set) var transferGeneration: UInt64 = 0

    package var isTransferring: Bool { activeTransfer != nil }
    package var admitsCreation: Bool { !isDisposed && !isTransferring && !isRetiring }
    package var admitsPositioning: Bool { admitsCreation }
    package var admitsInput: Bool { !isTransferring && !isRetiring }
    package var publishesPages: Bool { !isDisposed && !isTransferring }
    package var admitsTransferSnapshot: Bool { admitsCreation }

    package init() {}

    package func admitsTransfer(generation: UInt64) -> Bool {
        !isDisposed && !isRetiring && generation == transferGeneration
    }

    @discardableResult
    package mutating func beginRetirement() -> Bool {
        guard !isRetiring, !isTransferring else { return false }
        isRetiring = true
        return true
    }

    package mutating func endRetirement() { isRetiring = false }

    @discardableResult
    package mutating func beginTransfer(generation: UInt64) -> Bool {
        guard !isTransferring, admitsTransfer(generation: generation) else { return false }
        activeTransfer = generation
        return true
    }

    package mutating func finishTransfer() {
        activeTransfer = nil
        transferGeneration &+= 1
    }

    package mutating func dispose() { isDisposed = true }
}

package struct EmbeddedPageSleepPolicy {
    static let idleInterval: TimeInterval = 14_400

    package enum Protection: Equatable { case eligible, protected, unknown }

    package struct Candidate: Equatable {
        var lastShown: Date
        var shown: Bool
        var closing: Bool
        var transferring: Bool
        var editing: Bool
        var pendingCreation: Bool
        var pages: [Protection]

        package init(lastShown: Date, shown: Bool, closing: Bool, transferring: Bool, editing: Bool, pendingCreation: Bool, pages: [Protection]) {
            self.lastShown = lastShown
            self.shown = shown
            self.closing = closing
            self.transferring = transferring
            self.editing = editing
            self.pendingCreation = pendingCreation
            self.pages = pages
        }
    }

    package static func shouldSleep(_ candidate: Candidate, now: Date) -> Bool {
        guard !candidate.shown, !candidate.closing, !candidate.transferring, !candidate.editing,
              !candidate.pendingCreation, !candidate.pages.isEmpty,
              candidate.lastShown < now.addingTimeInterval(-idleInterval) else { return false }
        return candidate.pages.allSatisfy { $0 == .eligible }
    }
}
