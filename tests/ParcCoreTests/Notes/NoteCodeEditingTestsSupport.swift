import Foundation
import Testing
@testable import ParcCore

enum NoteCodeEditingTestsSupport {
    static func check(_ edit: NoteCodeEdit?, on text: String, gives expected: String, caret: Range<Int>, _ message: String) {
        guard let edit else { Issue.record("\(message): no edit"); return }
        let result = edit.applied(to: text)
        if result != expected { Issue.record("\(message): got \(result.debugDescription), wanted \(expected.debugDescription)") }
        if edit.selection != caret { Issue.record("\(message): selection \(edit.selection), wanted \(caret)") }
    }
}
