import Combine
import Foundation

@MainActor
struct NoteFileSettings {
    typealias MainHop = @Sendable (@escaping @Sendable () -> Void) -> Void
    typealias TrashMover = @Sendable (URL) throws -> URL?

    var clock: NoteFileClock
    var fileWorker: NoteFileWorker
    var indexWorker: NoteFileWorker
    var backlinkWorker: NoteFileWorker
    var attachmentWorker: NoteFileWorker
    var hopToMain: MainHop
    var trashMover: TrashMover
    var defaults: UserDefaults
    var notesFolders: (@MainActor () -> [URL])?
    var autosaveDelay: TimeInterval = 0.6
    var longestAutosaveWait: TimeInterval = 5
    var diskCheckDelay: TimeInterval = 0.12
    var retryDelays: [TimeInterval] = [1, 2, 4, 8, 15, 30, 60]
    var libraryRefreshDelay: TimeInterval = 0.2
    var backlinkFollowDelay: TimeInterval = 1.5
    var backlinkDepartureWindow: TimeInterval = 10
    var easelListingDelay: TimeInterval = 1
    var defaultFolder: @Sendable () -> URL = { NoteLibrary.defaultFolder }

    nonisolated static let mainQueueHop: MainHop = { DispatchQueue.main.async(execute: $0) }

    init(clock: NoteFileClock, worker: NoteFileWorker, hopToMain: @escaping MainHop = NoteFileSettings.mainQueueHop,
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

    static func production() -> NoteFileSettings {
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

    let settings: NoteFileSettings
    package let syncedBlocks: NoteSyncedBlocks
    package let folders: NoteFolderPreferences
    let libraryOpened = PassthroughSubject<NoteLibrary, Never>()
    let emojiChanges = PassthroughSubject<NoteEmojiLibrary, Never>()
    package var newNoteCover: (@MainActor () -> NoteNewCover?)?
    package private(set) lazy var backlinks = NoteBacklinkIndex(files: self)
    package private(set) lazy var attachmentImports = NoteAttachmentImports(files: self)

    var sessions: [String: NoteFileSession] = [:]
    var liveSessions: [ObjectIdentifier: NoteFileSession] = [:]
    var libraries: [String: NoteLibrary] = [:]
    var shallowLibraries: [String: NoteLibrary] = [:]
    var emojiLibraries: [String: NoteEmojiLibrary] = [:]

    convenience init(settings: NoteFileSettings) {
        self.init(settings: settings, syncedBlocks: NoteSyncedBlocks())
    }

    init(settings: NoteFileSettings, syncedBlocks: NoteSyncedBlocks) {
        self.settings = settings
        self.syncedBlocks = syncedBlocks
        folders = NoteFolderPreferences(defaults: settings.defaults, defaultFolder: settings.defaultFolder)
    }

    var clock: NoteFileClock { settings.clock }

    var notesFolders: [URL] { settings.notesFolders?() ?? folders.allFolders }
}
