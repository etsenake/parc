import AppKit

private final class EmbeddedSurface: NSView, NoteKeyEquivalentBoundary {}

@main
struct NoteKeyEquivalentBoundaryTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    @MainActor static func main() {
        let note = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let paragraph = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        let surface = EmbeddedSurface(frame: NSRect(x: 0, y: 60, width: 400, height: 300))
        let canvas = NSView(frame: surface.bounds)
        let objectStop = NSView(frame: NSRect(x: 10, y: 10, width: 40, height: 40))
        note.addSubview(paragraph)
        note.addSubview(surface)
        surface.addSubview(canvas)
        canvas.addSubview(objectStop)
        expect(!note.isInsideNoteKeyEquivalentBoundary && !paragraph.isInsideNoteKeyEquivalentBoundary,
               "Note text keeps its own key equivalents")
        expect(surface.isInsideNoteKeyEquivalentBoundary, "The embedded Easel surface owns its chords")
        expect(canvas.isInsideNoteKeyEquivalentBoundary && objectStop.isInsideNoteKeyEquivalentBoundary,
               "A canvas or object stop inside an Easel block keeps ⌘D, ⌘G and ⌘[ away from the note")
        objectStop.removeFromSuperview()
        expect(!objectStop.isInsideNoteKeyEquivalentBoundary, "A view taken out of the block goes back to the note's rules")
        print("NoteKeyEquivalentBoundaryTests passed")
    }
}
