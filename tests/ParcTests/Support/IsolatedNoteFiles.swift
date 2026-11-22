import AppKit
import ParcTestSupport
@testable import Parc
@testable import ParcCore
@testable import ParcLibrary
@testable import ParcSidebar

@MainActor
enum IsolatedNoteFiles {
    static func make(clock: NoteFileClock? = nil, worker: NoteFileWorker = .inline, attachmentWorker: NoteFileWorker? = nil) -> NoteFiles {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParcTests-Notes-\(UUID().uuidString)", isDirectory: true)
        var settings = NoteFileSettings(clock: clock ?? NoteEditorManualClock(), worker: worker, hopToMain: { _ in },
                                        trashMover: { _ in throw NoteEditorRealTrashRefused() },
                                        defaults: TestDefaults("Parc.TESTS.Notes.")!,
                                        notesFolders: { [] })
        settings.defaultFolder = { folder }
        settings.attachmentWorker = attachmentWorker ?? worker
        return NoteFiles(settings: settings)
    }
}

extension LibraryView {
    convenience init(isolatingNotesIn store: BrowserStore, kind: Kind, profileID: UUID,
                     spaceManager: (any LibrarySpacesPage)? = nil,
                     reduceMotion: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
                     scheduleReload: (@MainActor (@escaping @MainActor () -> Void) -> Void)? = nil) {
        let files = IsolatedNoteFiles.make()
        let easelIcons = EaselTabIcons(files: files)
        easelIcons.worker = .inline
        self.init(store: store, kind: kind, profileID: profileID,
                  spaceManager: spaceManager ?? SpaceManagerView(frame: .zero), files: files,
                  easelIcons: easelIcons, easelStore: { try EaselStore(directory: $0) },
                  reduceMotion: reduceMotion, scheduleReload: scheduleReload)
    }
}
