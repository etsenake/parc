import Foundation

struct CommandBarNativeHold: Equatable {
    enum Edit: Equatable {
        case answered
        case hold
        case present
    }
    private(set) var awaitedInput: String?
    private(set) var displayedInput: String?
    var isHolding: Bool { awaitedInput != nil }

    mutating func edit(_ input: String, canHold: Bool, scoped: Bool) -> Edit {
        if input == displayedInput { awaitedInput = nil; return .answered }
        guard canHold, displayedInput != nil, scoped || !input.isEmpty else {
            awaitedInput = nil; displayedInput = nil; return .present
        }
        awaitedInput = input
        return .hold
    }
    mutating func accept(input: String, isError: Bool) -> Bool {
        if let awaitedInput, input != awaitedInput, !isError { return false }
        awaitedInput = nil
        displayedInput = isError ? nil : input
        return true
    }
    mutating func end() { awaitedInput = nil }
    mutating func reset() { awaitedInput = nil; displayedInput = nil }

    func presentsBeforeSubmitting(explicitSelection: Bool) -> Bool { isHolding && !explicitSelection }
    func nativeRowsAnswer(_ input: String) -> Bool { !isHolding && displayedInput == input }
}
