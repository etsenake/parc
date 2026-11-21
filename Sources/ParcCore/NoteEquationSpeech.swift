import Foundation

package enum NoteEquationSpeech {
    package static func label(source: String, error: String?) -> String {
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Empty equation" }
        if let error { return "Equation that won\u{2019}t typeset: \(source). \(error)" }
        return "Equation: \(source)"
    }
}
