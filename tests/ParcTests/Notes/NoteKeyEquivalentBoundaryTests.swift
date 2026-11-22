import AppKit
import Testing
@testable import ParcNotes

@MainActor
struct NoteKeyEquivalentBoundaryTests {
    final class EmbeddedSurface: NSView, NoteKeyEquivalentBoundary {}

    @MainActor struct Hierarchy {
        let note = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let paragraph = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        let surface = EmbeddedSurface(frame: NSRect(x: 0, y: 60, width: 400, height: 300))
        let canvas: NSView
        let objectStop = NSView(frame: NSRect(x: 10, y: 10, width: 40, height: 40))

        init() {
            canvas = NSView(frame: surface.bounds)
            note.addSubview(paragraph)
            note.addSubview(surface)
            surface.addSubview(canvas)
            canvas.addSubview(objectStop)
        }
    }

    @Test func noteTextKeepsItsOwnKeyEquivalents() {
        let hierarchy = Hierarchy()
        #expect(!hierarchy.note.isInsideNoteKeyEquivalentBoundary)
        #expect(!hierarchy.paragraph.isInsideNoteKeyEquivalentBoundary)
    }

    @Test func theEmbeddedEaselSurfaceOwnsItsChords() {
        #expect(Hierarchy().surface.isInsideNoteKeyEquivalentBoundary)
    }

    @Test func aCanvasInsideAnEaselBlockKeepsItsChordsAwayFromTheNote() {
        #expect(Hierarchy().canvas.isInsideNoteKeyEquivalentBoundary)
    }

    @Test func anObjectStopInsideAnEaselBlockKeepsItsChordsAwayFromTheNote() {
        #expect(Hierarchy().objectStop.isInsideNoteKeyEquivalentBoundary)
    }

    @Test func aViewTakenOutOfTheBlockGoesBackToTheNotesRules() {
        let hierarchy = Hierarchy()
        hierarchy.objectStop.removeFromSuperview()
        #expect(!hierarchy.objectStop.isInsideNoteKeyEquivalentBoundary)
    }
}
