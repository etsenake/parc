import Combine
import Foundation

extension NoteSyncedBlocks {
    func useNoteFiles() {
        guard !usesNoteFiles else { return }
        usesNoteFiles = true
        opener = { url in
            guard let file = try? NoteFileSession.open(url) else { return nil }
            file.retain()
            return NoteSyncedLease { file.release() }
        }
        originalFinder = { anchor, url in NoteLibrary.library(for: url).notes(withSyncedOriginal: anchor) }
        noteFinder = { anchor, url in NoteLibrary.library(for: url).notes(mentioningSynced: anchor) }
        libraryChanges = { url in NoteLibrary.library(for: url).changes.eraseToAnyPublisher() }
    }
}
