import Foundation

struct EmbeddedPageFingerprint: Equatable {
    private let value: Any
    private let matches: (Any) -> Bool

    init<Value: Equatable>(_ value: Value) {
        self.value = value
        matches = { ($0 as? Value) == value }
    }

    func unwrap<Value>(_ type: Value.Type) -> Value? { value as? Value }

    static func == (lhs: EmbeddedPageFingerprint, rhs: EmbeddedPageFingerprint) -> Bool { lhs.matches(rhs.value) }
}

struct EmbeddedPageOwnerGate: Equatable {
    private(set) var isDisposed = false
    private(set) var isRetiring = false
    private(set) var activeTransfer: UInt64?
    private(set) var transferGeneration: UInt64 = 0

    var isTransferring: Bool { activeTransfer != nil }
    var admitsCreation: Bool { !isDisposed && !isTransferring && !isRetiring }
    var admitsPositioning: Bool { admitsCreation }
    var admitsInput: Bool { !isTransferring && !isRetiring }
    var publishesPages: Bool { !isDisposed && !isTransferring }
    var admitsTransferSnapshot: Bool { admitsCreation }

    func admitsTransfer(generation: UInt64) -> Bool {
        !isDisposed && !isRetiring && generation == transferGeneration
    }

    @discardableResult
    mutating func beginRetirement() -> Bool {
        guard !isRetiring, !isTransferring else { return false }
        isRetiring = true
        return true
    }

    mutating func endRetirement() { isRetiring = false }

    @discardableResult
    mutating func beginTransfer(generation: UInt64) -> Bool {
        guard !isTransferring, admitsTransfer(generation: generation) else { return false }
        activeTransfer = generation
        return true
    }

    mutating func finishTransfer() {
        activeTransfer = nil
        transferGeneration &+= 1
    }

    mutating func dispose() { isDisposed = true }
}

struct EmbeddedPageSleepPolicy {
    static let idleInterval: TimeInterval = 14_400

    enum Protection: Equatable { case eligible, protected, unknown }

    struct Candidate: Equatable {
        var lastShown: Date
        var shown: Bool
        var closing: Bool
        var transferring: Bool
        var editing: Bool
        var pendingCreation: Bool
        var pages: [Protection]
    }

    static func shouldSleep(_ candidate: Candidate, now: Date) -> Bool {
        guard !candidate.shown, !candidate.closing, !candidate.transferring, !candidate.editing,
              !candidate.pendingCreation, !candidate.pages.isEmpty,
              candidate.lastShown < now.addingTimeInterval(-idleInterval) else { return false }
        return candidate.pages.allSatisfy { $0 == .eligible }
    }
}
