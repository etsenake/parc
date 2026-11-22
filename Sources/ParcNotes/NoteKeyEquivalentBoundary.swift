import AppKit

@MainActor
package protocol NoteKeyEquivalentBoundary: NSView {}

extension NSView {
    @MainActor var isInsideNoteKeyEquivalentBoundary: Bool {
        sequence(first: self, next: \.superview).contains { $0 is NoteKeyEquivalentBoundary }
    }
}
