import Foundation
@testable import ParcCore

@MainActor
enum IsolatedNoteFiles {
    static func make() -> NoteFiles {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParcTests-Notes-\(UUID().uuidString)", isDirectory: true)
        var settings = NoteFileSettings(clock: NoteEditorManualClock(), worker: .inline, hopToMain: { _ in },
                                        trashMover: { _ in throw NoteEditorRealTrashRefused() },
                                        defaults: UserDefaults(suiteName: "Parc.TESTS.Notes.\(UUID().uuidString)")!,
                                        notesFolders: { [] })
        settings.defaultFolder = { folder }
        return NoteFiles(settings: settings)
    }
}
