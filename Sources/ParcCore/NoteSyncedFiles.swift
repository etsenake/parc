import Combine
import Foundation

extension NoteSyncedBlocks {
    func useNoteFiles(_ files: NoteFiles) {
        guard !usesNoteFiles else { return }
        usesNoteFiles = true
        opener = { [unowned files] url in
            guard let file = try? files.open(url) else { return nil }
            file.retain()
            return NoteSyncedLease { file.release() }
        }
        originalFinder = { [unowned files] anchor, url in files.library(for: url).notes(withSyncedOriginal: anchor) }
        noteFinder = { [unowned files] anchor, url in files.library(for: url).notes(mentioningSynced: anchor) }
        libraryChanges = { [unowned files] url in files.library(for: url).changes.eraseToAnyPublisher() }
    }
}
