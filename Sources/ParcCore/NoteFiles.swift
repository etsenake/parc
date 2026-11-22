import Combine
import Foundation

@MainActor
package struct NoteFileSettings {
    package typealias MainHop = @Sendable (@escaping @Sendable () -> Void) -> Void
    package typealias TrashMover = @Sendable (URL) throws -> URL?

    package var clock: NoteFileClock
    package var fileWorker: NoteFileWorker
    package var indexWorker: NoteFileWorker
    package var backlinkWorker: NoteFileWorker
    package var attachmentWorker: NoteFileWorker
    package var hopToMain: MainHop
    package var trashMover: TrashMover
    package var defaults: UserDefaults
    package var notesFolders: (@MainActor () -> [URL])?
    package var autosaveDelay: TimeInterval = 0.6
    package var longestAutosaveWait: TimeInterval = 5
    package var diskCheckDelay: TimeInterval = 0.12
    package var retryDelays: [TimeInterval] = [1, 2, 4, 8, 15, 30, 60]
    package var libraryRefreshDelay: TimeInterval = 0.2
    package var backlinkFollowDelay: TimeInterval = 1.5
    package var backlinkDepartureWindow: TimeInterval = 10
    package var easelListingDelay: TimeInterval = 1

    package nonisolated static let mainQueueHop: MainHop = { DispatchQueue.main.async(execute: $0) }

    package init(clock: NoteFileClock, worker: NoteFileWorker, hopToMain: @escaping MainHop = NoteFileSettings.mainQueueHop,
                 trashMover: @escaping TrashMover = { try NoteFileIO.moveToTrash($0) }, defaults: UserDefaults = .standard,
                 notesFolders: (@MainActor () -> [URL])? = nil) {
        self.clock = clock
        fileWorker = worker
        indexWorker = worker
        backlinkWorker = worker
        attachmentWorker = worker
        self.hopToMain = hopToMain
        self.trashMover = trashMover
        self.defaults = defaults
        self.notesFolders = notesFolders
    }

    package static func production() -> NoteFileSettings {
        var settings = NoteFileSettings(clock: NoteFileSystemClock.shared, worker: .files)
        settings.indexWorker = .index
        settings.backlinkWorker = NoteFileWorker(label: "org.parc.notes.backlinks", qos: .utility)
        settings.attachmentWorker = NoteFileWorker(label: "org.parc.notes.attachments")
        return settings
    }
}

@MainActor
package final class NoteFiles {
    package static let shared = NoteFiles(settings: .production(), syncedBlocks: .shared)

    package let settings: NoteFileSettings
    package let syncedBlocks: NoteSyncedBlocks
    package let folders: NoteFolderPreferences
    package let libraryOpened = PassthroughSubject<NoteLibrary, Never>()
    package let emojiChanges = PassthroughSubject<NoteEmojiLibrary, Never>()
    package var newNoteCover: (@MainActor () -> NoteNewCover?)?
    package private(set) lazy var backlinks = NoteBacklinkIndex(files: self)
    package private(set) lazy var attachmentImports = NoteAttachmentImports(files: self)

    var sessions: [String: NoteFileSession] = [:]
    var liveSessions: [ObjectIdentifier: NoteFileSession] = [:]
    var libraries: [String: NoteLibrary] = [:]
    var shallowLibraries: [String: NoteLibrary] = [:]
    var emojiLibraries: [String: NoteEmojiLibrary] = [:]

    package convenience init(settings: NoteFileSettings) {
        self.init(settings: settings, syncedBlocks: NoteSyncedBlocks())
    }

    package init(settings: NoteFileSettings, syncedBlocks: NoteSyncedBlocks) {
        self.settings = settings
        self.syncedBlocks = syncedBlocks
        folders = NoteFolderPreferences(defaults: settings.defaults)
    }

    package var clock: NoteFileClock { settings.clock }

    package var notesFolders: [URL] { settings.notesFolders?() ?? folders.allFolders }
}
