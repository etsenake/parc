import Foundation

///
///
///
/// every keystroke, so its first row always matches the field.
struct CommandBarNativeHold: Equatable {
    enum Edit: Equatable {
        /// The displayed answer is already for this input.
        case answered
        /// Keep the displayed rows until this input's answer arrives.
        case hold
        /// Present this input's own rows now, without native rows.
        case present
    }
    private(set) var awaitedInput: String?
    private(set) var displayedInput: String?
    var isHolding: Bool { awaitedInput != nil }

    /// Only a native answer already on screen is worth keeping. A silent or
    /// failed session presents at once, so it never freezes typing.
    mutating func edit(_ input: String, canHold: Bool, scoped: Bool) -> Edit {
        if input == displayedInput { awaitedInput = nil; return .answered }
        guard canHold, displayedInput != nil, scoped || !input.isEmpty else {
            awaitedInput = nil; displayedInput = nil; return .present
        }
        awaitedInput = input
        return .hold
    }
    /// Whether a publication is for the current input (an error always is).
    mutating func accept(input: String, isError: Bool) -> Bool {
        if let awaitedInput, input != awaitedInput, !isError { return false }
        awaitedInput = nil
        displayedInput = isError ? nil : input
        return true
    }
    mutating func end() { awaitedInput = nil }
    mutating func reset() { awaitedInput = nil; displayedInput = nil }

    /// Return with nothing chosen submits this input's own first row, not the
    /// previous answer's default; a row the user chose submits as shown.
    func presentsBeforeSubmitting(explicitSelection: Bool) -> Bool { isHolding && !explicitSelection }
    /// Tab completes only from native rows that answer the current input.
    func nativeRowsAnswer(_ input: String) -> Bool { !isHolding && displayedInput == input }
}
