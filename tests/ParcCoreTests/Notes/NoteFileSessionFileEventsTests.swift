import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteFileSessionFileEventsTests {
    private let fixture = NoteFileSessionTestsSupport.Fixture()

    @Test func anOutsideEditIsNoticedAndReloaded() throws {
        let (url, session) = try fixture.watched()
        defer { session.release() }
        try Data("after\n".utf8).write(to: url, options: .atomic)
        fixture.reload(session)
        #expect(fixture.texts(session) == ["after"])
    }

    @Test func aPlainWriteAfterAnAtomicReplaceIsNoticedToo() throws {
        let (url, session) = try fixture.watched()
        defer { session.release() }
        try Data("after\n".utf8).write(to: url, options: .atomic)
        fixture.reload(session)
        NoteFileTestSupport.write("plain write\n", to: url)
        fixture.reload(session)
        #expect(fixture.texts(session) == ["plain write"])
    }

    @Test func myOwnSavesDoNotBounceBackAsOutsideEdits() throws {
        let (_, session) = try fixture.watched()
        defer { session.release() }
        fixture.setText(session, "typed")
        fixture.clock.advance(1)
        fixture.reload(session)
        #expect(fixture.texts(session) == ["typed"])
        #expect(session.state == .saved)
    }

    @Test func aDeletionEventIsNoticed() throws {
        let (url, session) = try fixture.watched()
        defer { session.release() }
        try FileManager.default.removeItem(at: url)
        session.handle(.deleted)
        fixture.clock.advance(1)
        #expect(session.state == .missing)
    }

    @Test func aFileRecreatedBySomeoneElseIsPickedUp() throws {
        let (url, session) = try fixture.watched()
        defer { session.release() }
        try FileManager.default.removeItem(at: url)
        session.handle(.deleted)
        fixture.clock.advance(1)
        NoteFileTestSupport.write("back again\n", to: url)
        fixture.reload(session)
        #expect(fixture.texts(session) == ["back again"])
        #expect(session.state == .saved)
    }

    @Test func anInPlaceWriteAfterTheFileSteppedOutAndBackIsStillNoticed() throws {
        let url = fixture.file("gap.txt", "one\n")
        let session = try fixture.files.open(url)
        session.retain()
        defer { session.release() }
        let parked = fixture.folder.appendingPathComponent("gap parked.txt")
        #expect(rename(url.path, parked.path) == 0)
        #expect(rename(parked.path, url.path) == 0)
        session.checkDisk()
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("two, written in place\n".utf8))
        try handle.close()
        fixture.reload(session)
        #expect(fixture.texts(session) == ["two, written in place"])
    }
}
