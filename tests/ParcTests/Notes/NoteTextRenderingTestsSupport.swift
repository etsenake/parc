import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

enum NoteTextRenderingTestsSupport {
    @MainActor struct Fixture {
        init() { NoteEditorFixtures.useMathFont() }

        func roundTrip(_ text: NoteText, in presentation: NoteTextPresentation = NoteTextPresentation()) {
            let attributed = NoteTextRendering.attributedString(text, presentation)
            #expect(attributed.length == text.length)
            #expect(NoteTextRendering.noteText(from: attributed) == text)
        }

        func makeTextView(_ presentation: NoteTextPresentation, width: CGFloat) -> NSTextView {
            let view = NSTextView(usingTextLayoutManager: false)
            view.textContainer?.replaceLayoutManager(NoteLayoutManager())
            view.textContainerInset = .zero
            view.textContainer?.lineFragmentPadding = 0
            view.textContainer?.widthTracksTextView = true
            view.isVerticallyResizable = false
            view.frame = NSRect(x: 0, y: 0, width: width, height: 400)
            view.isRichText = true
            view.typingAttributes = NoteTextRendering.typingAttributes(.plain, presentation)
            return view
        }
    }
}
