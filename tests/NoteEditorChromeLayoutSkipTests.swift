import CoreGraphics
import Foundation

/// P1-G leftover: note editor layoutDocument skips footer/scroll/format/key-loop
/// chrome only when the geometry fingerprint already matches. Real bounds or
/// error-footer changes still layout. Document height reflow stays separate.
///
/// Mirrors `NoteEditorChromeLayoutSkip` in NoteEditorViewController.swift so
/// this unit stays freestanding; `tests/NoteEditorChromeLayoutSkip/check.py`
/// locks the production copy and call sites.
struct NoteEditorChromeFingerprint: Equatable {
    var width: CGFloat
    var height: CGFloat
    var hasError: Bool
    var stackedError: Bool
}

enum NoteEditorChromeLayoutSkip {
    static func shouldSkip(
        previous: NoteEditorChromeFingerprint?,
        next: NoteEditorChromeFingerprint
    ) -> Bool {
        previous == next
    }
}

@main
struct NoteEditorChromeLayoutSkipTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }

    static func fingerprint(
        width: CGFloat = 700,
        height: CGFloat = 600,
        hasError: Bool = false,
        stackedError: Bool = false
    ) -> NoteEditorChromeFingerprint {
        NoteEditorChromeFingerprint(
            width: width,
            height: height,
            hasError: hasError,
            stackedError: stackedError
        )
    }

    static func main() {
        let settled = fingerprint()
        expect(!NoteEditorChromeLayoutSkip.shouldSkip(previous: nil, next: settled),
               "First layoutDocument apply must run full chrome")
        expect(NoteEditorChromeLayoutSkip.shouldSkip(previous: settled, next: settled),
               "Identical note chrome geometry is a true no-op skip")

        expect(!NoteEditorChromeLayoutSkip.shouldSkip(
            previous: settled, next: fingerprint(width: 701)),
               "Bounds width changes must still layout chrome")
        expect(!NoteEditorChromeLayoutSkip.shouldSkip(
            previous: settled, next: fingerprint(height: 601)),
               "Bounds height changes must still layout chrome")
        expect(!NoteEditorChromeLayoutSkip.shouldSkip(
            previous: settled, next: fingerprint(hasError: true)),
               "Error footer presence must still layout chrome")
        expect(!NoteEditorChromeLayoutSkip.shouldSkip(
            previous: fingerprint(width: 200, hasError: true),
            next: fingerprint(width: 200, hasError: true, stackedError: true)),
               "Narrow stacked-error footer must still layout chrome")
        expect(NoteEditorChromeLayoutSkip.shouldSkip(
            previous: fingerprint(hasError: true, stackedError: true),
            next: fingerprint(hasError: true, stackedError: true)),
               "Identical stacked-error chrome remains a true no-op")

        print("\(assertions) note editor chrome layout skip assertions passed")
    }
}
