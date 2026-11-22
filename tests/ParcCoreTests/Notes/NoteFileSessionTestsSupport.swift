import Foundation
import Testing
@testable import ParcCore

enum NoteFileSessionTestsSupport {
    @MainActor final class Fixture {
        let clock: NoteManualClock
        private let hops: PendingHops
        let folder = NoteFileTestSupport.makeFolder("sessions")
        let files: NoteFiles

        init() {
            let clock = NoteManualClock(), hops = PendingHops()
            self.clock = clock
            self.hops = hops
            files = NoteFileTestSupport.files(clock: clock, hopToMain: { hops.add($0) })
        }

        deinit {
            NoteFileTestSupport.remove(folder)
        }

        @discardableResult
        func file(_ name: String, _ text: String) -> URL {
            NoteFileTestSupport.write(text, to: folder.appendingPathComponent(name))
        }

        func open(_ name: String, _ text: String) throws -> NoteFileSession {
            try files.open(file(name, text))
        }

        func setText(_ session: NoteFileSession, block index: Int = 0, _ text: String) {
            let id = session.page.page.blocks[index].id
            session.page.edit("Typing", kind: .text) { $0.update(id) { $0.text = NoteText(text) } }
        }

        func texts(_ session: NoteFileSession) -> [String] { session.page.page.blocks.map(\.text.string) }

        func trashFolder() throws -> URL {
            let trash = folder.appendingPathComponent(".Trash", isDirectory: true)
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            return trash
        }

        func reload(_ session: NoteFileSession) {
            session.handle(.changed)
            clock.advance(1)
        }

        func watched() throws -> (URL, NoteFileSession) {
            let url = file("watched.txt", "before\n")
            let session = try files.open(url)
            session.retain()
            return (url, session)
        }

        func conflicted(_ name: String = "conflict.txt") throws -> (URL, NoteFileSession) {
            let url = file(name, "base\n")
            let session = try files.open(url)
            setText(session, "mine")
            NoteFileTestSupport.write("theirs\n", to: url)
            session.checkDisk()
            return (url, session)
        }

        func askToSave(_ session: NoteFileSession) throws -> (answered: Bool, error: Error?) {
            let presenter = try #require(session.presenter)
            let reply = NoteLockedBox<Error?>()
            presenter.savePresentedItemChanges? { error in reply.set(.some(error)) }
            hops.runAll()
            return (reply.value != nil, reply.value ?? nil)
        }

        private final class PendingHops: @unchecked Sendable {
            private let lock = NSLock()
            private var hops: [@Sendable () -> Void] = []

            func add(_ hop: @escaping @Sendable () -> Void) { lock.withLock { hops.append(hop) } }

            func runAll() {
                while let next = lock.withLock({ hops.isEmpty ? nil : hops.removeFirst() }) { next() }
            }
        }
    }
}
