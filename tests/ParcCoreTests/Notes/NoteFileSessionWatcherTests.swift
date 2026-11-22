import Foundation
import Testing
@testable import ParcCore

final class NoteFileSessionWatcherTests {
    private let folder = NoteFileTestSupport.makeFolder("watcher")

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    private struct Stamped {
        let url: URL
        let read: NoteFileStamp
    }

    private func stampedFile() throws -> Stamped {
        let url = NoteFileTestSupport.write("first version\n", to: folder.appendingPathComponent("stamped.txt"))
        let read = try #require(NoteFileStamp(path: url.path))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("second, longer version\n".utf8))
        try handle.close()
        return Stamped(url: url, read: read)
    }

    private func listen(_ url: URL, seen: NoteFileSighting) -> [NoteFileWatchEvent] {
        let heard = NoteLockedBox<[NoteFileWatchEvent]>()
        heard.set([])
        let watcher = NoteFileWatcher(url: url, events: { event in heard.set((heard.value ?? []) + [event]) }, saveRequest: { $0(nil) })
        watcher.start(seen: seen)
        _ = watcher.movedPath()
        watcher.stop()
        return heard.value ?? []
    }

    @Test func aWatcherArmedAfterAReadNoticesTheFileMovedOnSinceThatRead() throws {
        let stamped = try stampedFile()
        #expect(listen(stamped.url, seen: .file(stamped.read)).contains(.changed))
    }

    @Test func aWatcherStaysQuietWhenNothingMovedOn() throws {
        let stamped = try stampedFile()
        let current = try #require(NoteFileStamp(path: stamped.url.path))
        #expect(listen(stamped.url, seen: .file(current)).isEmpty)
    }

    @Test func aFileThatVanishedSinceTheReadIsNoticedToo() throws {
        let stamped = try stampedFile()
        let current = try #require(NoteFileStamp(path: stamped.url.path))
        try FileManager.default.removeItem(at: stamped.url)
        #expect(listen(stamped.url, seen: .file(current)).contains(.changed))
    }
}
