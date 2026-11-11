import AppKit

@main @MainActor
struct NoteRetirementTests {
    static func main() throws {
        _ = NSApplication.shared
        var count = 0
        func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            count += 1; if try !value() { throw NSError(domain: message, code: 1) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-note-retirement-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try NoteStore.sharedStore(directory: directory, diskSaveDelay: 0), session = try store.create()
        let editor = try NoteEditorViewController(directory: directory, documentID: session.document.id)
        editor.loadView(); editor.text.localUndo.groupsByEvent = false
        try check(editor.prepareToClose(), "Initial close preparation is allowed")
        let original = session.document
        editor.text.localUndo.beginUndoGrouping()
        editor.text.setMarkedText("漢字", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 0, length: 0))
        try check(editor.text.hasMarkedText(), "Native IME composition begins after initial consent admission")
        try check(editor.prepareToClose(), "Final close barrier commits actual original composition")
        editor.text.localUndo.endUndoGrouping()
        try check(!editor.text.hasMarkedText() && session.document.body.text == "漢字" && session.document.body.id == original.body.id, "Original typed body identity and composed text survive")
        let file = directory.appendingPathComponent(session.document.id.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: file), saved = session.document
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        editor.text.localUndo.beginUndoGrouping()
        editor.text.insertText(" retained draft", replacementRange: NSRange(location: editor.text.string.utf16.count, length: 0))
        editor.text.localUndo.endUndoGrouping()
        try check(!editor.prepareToClose(), "A later unsaved edit refuses final retirement even after earlier admission")
        try check(editor.text.string.hasSuffix(" retained draft") && session.document == saved, "Failure preserves original native draft and durable revision")
        try FileManager.default.removeItem(at: file); try bytes.write(to: file)
        try check(editor.prepareToClose(), "Same original draft remains retryable after storage recovery")
        try check(try NoteStore(directory: directory, diskSaveDelay: 0).load(session.document.id).document.body.text == editor.text.string, "Final retry writes exact original draft to disk")
        print("\(count) native Note retirement assertions passed")
    }
}
