import AppKit
import Testing
@testable import ParcCore
@testable import ParcNotes

@MainActor
@Suite struct NotePropertiesDragTests {
    @MainActor private struct Fixture {
        let folder: NoteEditorTemporaryFolder
        let editor: NotePageEditor
        let view: NotePropertiesView

        init() throws {
            folder = try NoteEditorTemporaryFolder("properties-drag")
            let file = try IsolatedNoteFiles.make().open(try folder.write("Hello\n", to: "Note.md"))
            editor = NotePageEditor(session: file.page, environment: file.environment)
            view = NotePropertiesView(editor: editor)
            view.frame = NSRect(x: 0, y: 0, width: 480, height: 200)
        }

        var rows: [NotePropertyRowView] { view.subviews.compactMap { $0 as? NotePropertyRowView }.sorted { $0.index < $1.index } }

        func press(_ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(NSPoint(x: 10, y: y), to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
    }

    private static let three = ["Status", "Owner", "Due"].map { NotePageProperty(key: $0, value: .text("")) }

    @Test func undoingRowsAwayMidDragDropsTheDragInsteadOfMovingAMissingRow() throws {
        let fixture = try Fixture()
        fixture.view.reload(Self.three)
        let dragged = try #require(fixture.rows.last)
        fixture.view.beginDrag(dragged, event: fixture.press(80))
        fixture.view.continueDrag(event: fixture.press(10))
        fixture.view.reload(Array(Self.three.prefix(1)))
        fixture.view.endDrag()
        #expect(fixture.view.properties.map(\.key) == ["Status"])
        #expect(fixture.rows.count == 1)
        #expect(fixture.editor.session.page.settings.properties.isEmpty)
    }

    @Test func aReloadWithTheSamePropertiesKeepsTheDragGoing() throws {
        let fixture = try Fixture()
        fixture.editor.session.updateSettings(name: "Add") { $0.properties = Self.three }
        fixture.view.reload(Self.three)
        let dragged = try #require(fixture.rows.first)
        fixture.view.beginDrag(dragged, event: fixture.press(10))
        fixture.view.reload(Self.three)
        fixture.view.continueDrag(event: fixture.press(200))
        fixture.view.endDrag()
        #expect(fixture.editor.session.page.settings.properties.map(\.key) == ["Owner", "Due", "Status"])
    }
}
