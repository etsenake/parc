import Foundation

/// Which native answer is on screen while typing, and what Return and Tab
/// may act on before the current query's answer arrives.
@main struct NativeHoldTests {
    static func main() {
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        var hold = CommandBarNativeHold()
        expect(hold.edit("n", canHold: true, scoped: false) == .present, "with no native answer on screen there is nothing to keep")
        expect(!hold.isHolding, "a silent or failed session never holds typing")
        expect(hold.accept(input: "n", isError: false), "the first answer is accepted")
        expect(hold.nativeRowsAnswer("n"), "its rows answer the field")

        expect(hold.edit("ne", canHold: true, scoped: false) == .hold, "typing keeps the answer on screen until the next one")
        expect(hold.presentsBeforeSubmitting(explicitSelection: false),
               "Return with nothing chosen first presents this query's own first row")
        expect(!hold.presentsBeforeSubmitting(explicitSelection: true), "a row the user chose submits as shown")
        expect(hold.presentsBeforeSubmitting(explicitSelection: false) && !hold.nativeRowsAnswer("ne"),
               "Tab with nothing chosen also presents first, so it can't enter the previous answer's scope offer")
        expect(!hold.nativeRowsAnswer("ne"), "Tab doesn't complete from the previous answer")
        expect(!hold.accept(input: "n", isError: false), "a late answer for an older query is dropped")
        expect(hold.isHolding, "and the hold continues")
        expect(hold.accept(input: "ne", isError: false), "the current query's answer is accepted")
        expect(!hold.isHolding && hold.nativeRowsAnswer("ne") && !hold.presentsBeforeSubmitting(explicitSelection: false),
               "after it lands, Return and Tab act on its rows")

        expect(hold.edit("ne", canHold: true, scoped: false) == .answered, "a trailing space trims to the answered input")
        expect(hold.edit("", canHold: true, scoped: false) == .present, "the empty query presents its local rows at once")
        _ = hold.accept(input: "", isError: false)
        expect(hold.edit("", canHold: true, scoped: true) == .answered, "an answered empty scope stays")
        expect(hold.edit("wiki", canHold: true, scoped: true) == .hold, "a scope's typed query holds like an ordinary one")

        var failing = CommandBarNativeHold()
        _ = failing.accept(input: "n", isError: false)
        _ = failing.edit("ne", canHold: true, scoped: false)
        expect(failing.accept(input: "zzz", isError: true), "an error always belongs to the current request")
        expect(!failing.isHolding, "an error ends the hold")
        expect(failing.edit("new", canHold: true, scoped: false) == .present,
               "after an error, typing presents at once instead of waiting two seconds per keystroke")

        var closed = CommandBarNativeHold()
        _ = closed.accept(input: "n", isError: false)
        expect(closed.edit("ne", canHold: false, scoped: false) == .present, "no session or no presented panel never holds")
        expect(!closed.nativeRowsAnswer("n"), "presenting drops the old answer")
        print("NativeHoldTests: \(count) assertions passed")
    }
}
