import Combine
import Foundation
import Testing
@testable import ParcCore

final class NotePendingHops: @unchecked Sendable {
    private let lock = NSLock()
    private var hops: [@Sendable () -> Void] = []

    func add(_ hop: @escaping @Sendable () -> Void) { lock.withLock { hops.append(hop) } }

    func runAll() {
        while let next = lock.withLock({ hops.isEmpty ? nil : hops.removeFirst() }) { next() }
    }
}

@MainActor final class NoteFileSessionTests {
    let clock: NoteManualClock
    let hops: NotePendingHops
    let folder = NoteFileTestSupport.makeFolder("sessions")
    let files: NoteFiles

    init() {
        let clock = NoteManualClock(), hops = NotePendingHops()
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

    @Test func richTextIsNotANote() {
        #expect(throws: NoteFileError.notANote) { _ = try self.open("doc.rtf", "{\\rtf1}") }
    }

    @Test func aMissingFileSaysSo() {
        #expect(throws: NoteFileError.missing) { _ = try self.files.open(self.folder.appendingPathComponent("nowhere.md")) }
    }

    @Test func aGiantFileIsRefused() throws {
        let huge = folder.appendingPathComponent("huge.txt")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(NoteFileText.maximumSize + 1))
        try handle.close()
        #expect(throws: NoteFileError.tooLarge) { _ = try self.files.open(huge) }
    }

    @Test func aBinaryFileIsRefused() {
        let binary = NoteFileTestSupport.write(Data([0x00, 0x01, 0x02, 0xFF, 0x00, 0x7F, 0x13]), to: folder.appendingPathComponent("bin.md"))
        #expect(throws: NoteFileError.unreadable("It doesn’t look like text.")) { _ = try self.files.open(binary) }
    }

    @Test func aFolderNamedLikeANoteIsNotOpened() throws {
        let archive = folder.appendingPathComponent("Archive.md", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        #expect(throws: NoteFileError.notANote) { _ = try self.files.open(archive) }
    }

    @Test func everyPathToAFileSharesOneSession() throws {
        let url = file("Shared.md", "Hello\n")
        let first = try files.open(url)
        let viaVar = URL(fileURLWithPath: url.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
        #expect(try files.open(viaVar) === first)
        #expect(files.session(for: viaVar) === first)
    }

    @Test func eachFileEnvironmentKeepsItsOwnSessions() throws {
        let url = file("Shared.md", "Hello\n")
        let elsewhere = NoteFileTestSupport.files(clock: clock)
        #expect(try elsewhere.open(url) !== files.open(url))
    }

    @Test func theTitleIsTheFileName() throws {
        #expect(try open("Shared.md", "Hello\n").title == "Shared")
    }

    @Test func aFreshSessionIsSaved() throws {
        #expect(try open("Shared.md", "Hello\n").state == .saved)
    }

    @Test func theEnvironmentIsAFileEnvironmentForTheNote() throws {
        let url = file("Shared.md", "Hello\n")
        let session = try files.open(url)
        let environment = try #require(session.environment as? NoteFileEnvironment)
        #expect(environment.documentURL == url)
        #expect(environment.files === files)
    }

    @Test func aSymlinkedFolderSharesTheSession() throws {
        let book = file("Shelf/Book.md", "Words\n")
        let alias = folder.appendingPathComponent("Shelf Alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder.appendingPathComponent("Shelf", isDirectory: true))
        #expect(try files.open(alias.appendingPathComponent("Book.md")) === files.open(book))
    }

    @Test func theFirmlinkedDataVolumePathSharesTheSession() throws {
        let book = file("Shelf/Book.md", "Words\n")
        #expect(try files.open(URL(fileURLWithPath: "/System/Volumes/Data" + book.path)) === files.open(book))
    }

    @Test(.enabled(if: pathconf(FileManager.default.temporaryDirectory.path, _PC_CASE_SENSITIVE) == 0))
    func aDifferentCaseSharesTheSession() throws {
        let book = file("Shelf/Book.md", "Words\n")
        #expect(try files.open(folder.appendingPathComponent("Shelf/BOOK.md")) === files.open(book))
    }

    @Test(.enabled(if: pathconf(FileManager.default.temporaryDirectory.path, _PC_CASE_SENSITIVE) == 0))
    func aDeletedNoteIsStillFoundAndReopenedByAnySpelling() throws {
        let book = file("Shelf/Book.md", "Words\n")
        let original = try files.open(book)
        try FileManager.default.removeItem(at: book)
        original.checkDisk()
        #expect(files.session(for: folder.appendingPathComponent("Shelf/BOOK.md")) === original)
        #expect(try files.open(folder.appendingPathComponent("Shelf/book.md")) === original)
    }

    @Test func crlfAndAMissingFinalNewlineAreKept() throws {
        let session = try open("windows.txt", "one\r\ntwo")
        #expect(texts(session) == ["one", "two"])
        setText(session, block: 1, "deux")
        try session.flush()
        #expect(NoteFileTestSupport.read(session.url) == "one\r\ndeux")
    }

    @Test func utf16WithItsBOMIsWrittenBack() throws {
        let wide = NoteFileTestSupport.write(Data([0xFF, 0xFE] + Array("añ\nb\n".data(using: .utf16LittleEndian)!)), to: folder.appendingPathComponent("wide.txt"))
        let session = try files.open(wide)
        #expect(texts(session) == ["añ", "b"])
        setText(session, block: 1, "bé")
        try session.flush()
        #expect(NoteFileTestSupport.bytes(wide) == [0xFF, 0xFE] + Array("añ\nbé\n".data(using: .utf16LittleEndian)!))
    }

    @Test func theUTF8BOMIsKept() throws {
        let marked = NoteFileTestSupport.write(Data([0xEF, 0xBB, 0xBF] + Array("x\n".utf8)), to: folder.appendingPathComponent("bom.txt"))
        let session = try files.open(marked)
        setText(session, "y")
        try session.flush()
        #expect(NoteFileTestSupport.bytes(marked) == [0xEF, 0xBB, 0xBF] + Array("y\n".utf8))
    }

    @Test func legacyTextStaysInItsEncoding() throws {
        let old = NoteFileTestSupport.write(Data([0x63, 0x61, 0x66, 0xE9, 0x0A]), to: folder.appendingPathComponent("legacy.txt"))
        let session = try files.open(old)
        #expect(texts(session) == ["café"])
        setText(session, "café!")
        try session.flush()
        #expect(NoteFileTestSupport.bytes(old) == [0x63, 0x61, 0x66, 0xE9, 0x21, 0x0A])
    }

    @Test func textTheLegacyEncodingCannotHoldUpgradesToUTF8() throws {
        let old = NoteFileTestSupport.write(Data([0x63, 0x61, 0x66, 0xE9, 0x0A]), to: folder.appendingPathComponent("legacy.txt"))
        let session = try files.open(old)
        setText(session, "café 🙂")
        try session.flush()
        #expect(NoteFileTestSupport.read(old) == "café 🙂\n")
        #expect(session.format.encoding == .utf8)
    }

    @Test func aFinalNewlineIsNotAPhantomEmptyLine() throws {
        #expect(texts(try open("lines.txt", "a\nb\n")) == ["a", "b"])
    }

    @Test func savingKeepsTheFinalNewline() throws {
        let session = try open("lines.txt", "a\nb\n")
        session.page.edit("Add") { $0.blocks.append(.paragraph(NoteText("c"))) }
        try session.flush()
        #expect(NoteFileTestSupport.read(session.url) == "a\nb\nc\n")
    }

    @Test func selectionChangesAreNotEdits() throws {
        let session = try open("README.md", "# Readme\n")
        session.page.setSelection(.caret(NotePosition(session.page.page.blocks[0].id, 2)))
        #expect(session.state == .saved)
    }

    @Test func anEditIsUnsavedUntilTheAutosave() throws {
        let session = try open("README.md", "# Readme\n")
        setText(session, "changed")
        #expect(session.state == .unsaved)
    }

    @Test func anUneditedFileIsNeverTouched() throws {
        let original = "#   Readme\n* messy   list\n\n\n\nTrailing spaces   \n"
        let url = file("README.md", original)
        let stamp = Date(timeIntervalSince1970: 1_500_000_000)
        NoteFileTestSupport.setModified(url, stamp)
        let inode = NoteFileTestSupport.inode(url)
        let session = try files.open(url)
        session.retain()
        setText(session, "changed")
        session.page.undo()
        clock.advance(10)
        try files.flushAll()
        session.release()
        #expect(NoteFileTestSupport.read(url) == original)
        #expect(NoteFileTestSupport.modified(url) == stamp)
        #expect(NoteFileTestSupport.inode(url) == inode)
    }

    @Test func typingKeepsPushingTheAutosaveBack() throws {
        let session = try open("typing.txt", "start\n")
        setText(session, "s1")
        clock.advance(0.3)
        setText(session, "s2")
        clock.advance(0.5)
        #expect(NoteFileTestSupport.read(session.url) == "start\n")
        #expect(session.state == .unsaved)
    }

    @Test func aPauseInTypingSaves() throws {
        let session = try open("typing.txt", "start\n")
        setText(session, "s2")
        clock.advance(0.6)
        #expect(NoteFileTestSupport.read(session.url) == "s2\n")
        #expect(session.state == .saved)
    }

    @Test func savingIsAnnounced() throws {
        let session = try open("typing.txt", "start\n")
        var states: [NoteFileSaveState] = []
        let watch = session.$state.sink { states.append($0) }
        defer { watch.cancel() }
        setText(session, "s2")
        clock.advance(0.6)
        #expect(states.contains(.saving))
    }

    @Test func nonStopTypingStillSavesWithinTheLongestWait() throws {
        let session = try open("typing.txt", "start\n")
        for step in 0..<11 {
            setText(session, "burst \(step)")
            clock.advance(0.5)
        }
        #expect(NoteFileTestSupport.read(session.url).hasPrefix("burst"))
    }

    @Test func flushWritesRightAway() throws {
        let session = try open("typing.txt", "start\n")
        setText(session, "flushed")
        try session.flush()
        #expect(NoteFileTestSupport.read(session.url) == "flushed\n")
        #expect(session.state == .saved)
    }

    @Test func nothingStaleFiresAfterAFlush() throws {
        let session = try open("typing.txt", "start\n")
        setText(session, "flushed")
        try session.flush()
        #expect(!clock.hasPending)
    }

    @Test func savingKeepsPermissions() throws {
        let url = file("private.txt", "secret\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let session = try files.open(url)
        setText(session, "still secret")
        try session.flush()
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
    }

    @Test func aSymlinkOpensTheRealFile() throws {
        let target = file("target.md", "Target\n")
        let link = folder.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(try files.open(link).url == target)
    }

    @Test func savingThroughASymlinkKeepsTheLinkAndWritesTheTarget() throws {
        let target = file("target.md", "Target\n")
        let link = folder.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let linked = try files.open(link)
        setText(linked, "Through the link")
        try linked.flush()
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
        #expect(NoteFileTestSupport.read(target).contains("Through the link"))
    }

    @Test func renamesAreSanitizedAndKeepTheExtension() throws {
        let session = try open("Draft.md", "Words\n")
        let original = session.url
        let renamed = try session.rename(to: "  Plans/ideas: 2027 ")
        #expect(renamed.lastPathComponent == "Plans-ideas- 2027.md")
        #expect(!NoteFilePaths.itemExists(original) && NoteFilePaths.itemExists(renamed))
    }

    @Test func theSessionRegistryAndEnvironmentFollowARename() throws {
        let session = try open("Draft.md", "Words\n")
        let original = session.url
        let renamed = try session.rename(to: "Plans")
        #expect(session.url == renamed)
        #expect(files.session(for: renamed) === session && files.session(for: original) == nil)
        #expect(session.environment.documentURL == renamed)
    }

    @Test func listenersHearAboutARename() throws {
        let session = try open("Draft.md", "Words\n")
        var moves: [URL] = []
        let watch = session.urlChanges.sink { moves.append($0) }
        defer { watch.cancel() }
        let renamed = try session.rename(to: "Plans")
        #expect(moves == [renamed])
    }

    @Test func aRenameOntoATakenNameIsRefusedAndChangesNothing() throws {
        let session = try open("Draft.md", "Words\n")
        file("Taken.md", "Other\n")
        #expect(throws: NoteFileError.nameTaken("Taken")) { _ = try session.rename(to: "Taken") }
        #expect(session.url.lastPathComponent == "Draft.md")
    }

    @Test func caseOnlyRenamesWork() throws {
        let session = try open("Plans.md", "Words\n")
        #expect(try session.rename(to: "plans").lastPathComponent == "plans.md")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains("plans.md"))
    }

    @Test func renamesCannotHideTheFile() throws {
        #expect(try open("Draft.md", "Words\n").rename(to: "...secret").lastPathComponent == "secret.md")
    }

    @Test func anEmptyTitleBecomesAFreshUntitled() throws {
        let session = try open("Draft.md", "Words\n")
        file("Untitled.md", "")
        #expect(try session.rename(to: "   ").lastPathComponent == "Untitled 2.md")
    }

    @Test func anUntitledNoteStaysPutWhenClearedAgain() throws {
        let session = try open("Draft.md", "Words\n")
        let untitled = try session.rename(to: "")
        #expect(try session.rename(to: "") == untitled)
    }

    @Test func longTitlesAreTruncatedToFit() throws {
        let long = try open("Draft.md", "Words\n").rename(to: String(repeating: "长", count: 200))
        #expect(long.lastPathComponent.utf8.count <= 255 && NoteFilePaths.itemExists(long))
    }

    @Test func savingAfterARenameWritesTheRenamedFile() throws {
        let session = try open("Draft.md", "Words\n")
        let original = session.url
        let renamed = try session.rename(to: "Plans")
        setText(session, "Saved after renames")
        try session.flush()
        #expect(NoteFileTestSupport.read(renamed).contains("Saved after renames"))
        #expect(!NoteFilePaths.itemExists(original))
    }

    @Test func outsideEditsReload() throws {
        let session = try open("outside.txt", "one\ntwo\n")
        NoteFileTestSupport.write("zero\none\ntwo\n", to: session.url)
        session.checkDisk()
        #expect(texts(session) == ["zero", "one", "two"])
        #expect(session.state == .saved)
    }

    @Test func theCaretStaysNearWhereItWasAcrossAReload() throws {
        let session = try open("outside.txt", "one\ntwo\n")
        let two = session.page.page.blocks[1].id
        session.page.setSelection(.caret(NotePosition(two, 2)))
        NoteFileTestSupport.write("zero\none\ntwo\n", to: session.url)
        session.checkDisk()
        #expect(session.page.selection == .caret(NotePosition(two, 2)))
    }

    @Test func aReloadIsNotWrittenBack() throws {
        let session = try open("outside.txt", "one\n")
        NoteFileTestSupport.write("zero\none\n", to: session.url)
        let before = NoteFileTestSupport.modified(session.url)
        session.checkDisk()
        clock.advance(10)
        #expect(NoteFileTestSupport.modified(session.url) == before)
    }

    @Test func aCleanReloadStartsAFreshHistory() throws {
        let session = try open("outside.txt", "one\n")
        NoteFileTestSupport.write("zero\none\n", to: session.url)
        session.checkDisk()
        #expect(!session.page.canUndo)
    }

    @Test func checkingAnUnchangedFileChangesNothing() throws {
        let session = try open("outside.txt", "one\n")
        session.checkDisk()
        #expect(texts(session) == ["one"])
        #expect(session.state == .saved)
    }

    @Test func localAndOutsideEditsConflict() throws {
        let (_, session) = try conflicted()
        #expect(session.state == .conflict)
        #expect(session.conflictingText == "theirs")
        #expect(texts(session) == ["mine"])
    }

    @Test func autosaveNeverOverwritesDuringAConflict() throws {
        let (url, session) = try conflicted()
        setText(session, "mine, still typing")
        clock.advance(30)
        #expect(NoteFileTestSupport.read(url) == "theirs\n")
    }

    @Test func flushRefusesToPickASideInAConflict() throws {
        let (_, session) = try conflicted()
        #expect(throws: NoteFileError.conflict) { try session.flush() }
    }

    @Test func keepingMineOverwrites() throws {
        let (url, session) = try conflicted()
        session.resolveConflict(keepMine: true)
        #expect(NoteFileTestSupport.read(url) == "mine\n")
        #expect(session.state == .saved)
    }

    @Test func takingTheirsReloadsAndLeavesTheFileAlone() throws {
        let (url, session) = try conflicted()
        session.resolveConflict(keepMine: false)
        #expect(texts(session) == ["theirs"])
        #expect(session.state == .saved)
        #expect(NoteFileTestSupport.read(url) == "theirs\n")
    }

    @Test func undoAfterTakingTheirsBringsMineBackAndSavesIt() throws {
        let (url, session) = try conflicted()
        session.resolveConflict(keepMine: false)
        session.page.undo()
        #expect(texts(session) == ["mine"])
        clock.advance(1)
        #expect(NoteFileTestSupport.read(url) == "mine\n")
    }

    @Test func identicalOutsideTextIsNotAConflict() throws {
        let session = try open("conflict.txt", "base\n")
        setText(session, "converged")
        NoteFileTestSupport.write("converged\n", to: session.url)
        session.checkDisk()
        #expect(session.state == .saved)
    }

    @Test func aSaveDoesNotClobberAnOutsideEditItHadNotSeen() throws {
        let session = try open("race.txt", "start\n")
        setText(session, "local")
        NoteFileTestSupport.write("sneaky\n", to: session.url)
        clock.advance(1)
        #expect(NoteFileTestSupport.read(session.url) == "sneaky\n")
        #expect(session.state == .conflict)
    }

    @Test func aDeletionIsNoticedAndTheTextStaysInMemory() throws {
        let session = try open("doomed.txt", "keep me\n")
        try FileManager.default.removeItem(at: session.url)
        session.checkDisk()
        #expect(session.state == .missing)
        #expect(texts(session) == ["keep me"])
    }

    @Test func anUntouchedMissingNoteIsNotRecreated() throws {
        let session = try open("doomed.txt", "keep me\n")
        try FileManager.default.removeItem(at: session.url)
        session.checkDisk()
        try session.flush()
        clock.advance(5)
        #expect(!NoteFilePaths.itemExists(session.url))
    }

    @Test func editingAMissingNoteRecreatesIt() throws {
        let session = try open("doomed.txt", "keep me\n")
        try FileManager.default.removeItem(at: session.url)
        session.checkDisk()
        setText(session, "brought back")
        clock.advance(1)
        #expect(NoteFileTestSupport.read(session.url) == "brought back\n")
        #expect(session.state == .saved)
    }

    @Test func aFileThatReappearsIsPickedUp() throws {
        let session = try open("doomed.txt", "keep me\n")
        try FileManager.default.removeItem(at: session.url)
        session.checkDisk()
        NoteFileTestSupport.write("reborn elsewhere\n", to: session.url)
        session.checkDisk()
        #expect(texts(session) == ["reborn elsewhere"])
        #expect(session.state == .saved)
    }

    @Test func puttingBackAnUntouchedNoteRewritesItJustAsItWas() throws {
        let url = file("Boomerang.md", "# Still here\nkeep me\n")
        let session = try files.open(url)
        try FileManager.default.removeItem(at: url)
        session.checkDisk()
        try session.restore()
        #expect(NoteFileTestSupport.read(url) == "# Still here\nkeep me\n")
        #expect(session.state == .saved && !session.isMissing)
    }

    @Test func aPutBackNoteIsWatchedAgain() throws {
        let url = file("Boomerang.md", "# Still here\nkeep me\n")
        let session = try files.open(url)
        session.retain()
        defer { session.release() }
        try FileManager.default.removeItem(at: url)
        session.checkDisk()
        try session.restore()
        NoteFileTestSupport.write("# Still here\nedited in another app\n", to: url)
        reload(session)
        #expect(texts(session) == ["Still here", "edited in another app"])
    }

    @Test func puttingBackKeepsUnsavedEdits() throws {
        let session = try open("Edited.txt", "base\n")
        setText(session, "unsaved words")
        try FileManager.default.removeItem(at: session.url)
        session.checkDisk()
        clock.advance(5)
        try session.restore()
        #expect(NoteFileTestSupport.read(session.url) == "unsaved words\n")
        #expect(session.state == .saved && !session.hasUnsavedChanges)
    }

    @Test func puttingBackRebuildsMissingFolders() throws {
        let nested = file("Shelf/Deep/Book.md", "On the shelf\n")
        let session = try files.open(nested)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Shelf"))
        session.checkDisk()
        try session.restore()
        #expect(NoteFileTestSupport.read(nested) == "On the shelf\n")
        #expect(session.state == .saved)
    }

    func squatted() throws -> (URL, NoteFileSession) {
        let taken = file("Taken.md", "mine\n")
        let session = try files.open(taken)
        try FileManager.default.removeItem(at: taken)
        session.checkDisk()
        return (taken, session)
    }

    @Test func aDifferentFileInTheOldSpotStopsPuttingItBack() throws {
        let (taken, session) = try squatted()
        NoteFileTestSupport.write("someone else's\n", to: taken)
        #expect(throws: NoteFileError.occupied("Taken.md")) { try session.restore() }
        #expect(NoteFileTestSupport.read(taken) == "someone else's\n")
        #expect(texts(session) == ["mine"])
        #expect(session.state == .missing)
    }

    @Test func aFolderInTheOldSpotStopsPuttingItBack() throws {
        let (taken, session) = try squatted()
        try FileManager.default.createDirectory(at: taken, withIntermediateDirectories: false)
        #expect(throws: NoteFileError.occupied("Taken.md")) { try session.restore() }
    }

    @Test func anIdenticalFileInTheOldSpotIsPickedBackUpWithoutRewriting() throws {
        let (taken, session) = try squatted()
        NoteFileTestSupport.write("mine\n", to: taken)
        let twin = NoteFileStamp(path: taken.path)
        try session.restore()
        #expect(session.state == .saved)
        #expect(NoteFileStamp(path: taken.path) == twin)
    }

    @Test func anOutsideMoveIsFollowed() throws {
        let session = try open("wanderer.md", "Roaming\n")
        var moves: [URL] = []
        let watch = session.urlChanges.sink { moves.append($0) }
        defer { watch.cancel() }
        let destination = folder.appendingPathComponent("Moved/wanderer.md")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: session.url, to: destination)
        session.handle(.relocated(destination.path))
        clock.advance(1)
        #expect(session.url == destination)
        #expect(moves == [destination])
        #expect(files.session(for: destination) === session)
    }

    @Test func aPresenterMoveRenamesTheNote() throws {
        let session = try open("wanderer.md", "Roaming\n")
        let renamed = folder.appendingPathComponent("Renamed in Finder.md")
        try FileManager.default.moveItem(at: session.url, to: renamed)
        session.handle(.moved(renamed))
        #expect(session.title == "Renamed in Finder")
    }

    @Test func movingToTheTrashCountsAsDeletion() throws {
        let session = try open("wanderer.md", "Roaming\n")
        let original = session.url
        let trashed = try trashFolder().appendingPathComponent("wanderer.md")
        try FileManager.default.moveItem(at: original, to: trashed)
        session.handle(.moved(trashed))
        #expect(session.state == .missing)
        #expect(session.url == original)
    }

    func trashing() throws -> (URL, NoteFileSession, NoteFiles) {
        let trash = try trashFolder()
        let files = NoteFileTestSupport.files(clock: clock, trashMover: { url in
            let target = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        })
        let doomed = file("Trash me.md", "bye\n")
        let session = try files.open(doomed)
        setText(session, "last words")
        try files.trash(doomed)
        return (trash, session, files)
    }

    @Test func trashingSavesTheLatestTextFirst() throws {
        let (trash, _, _) = try trashing()
        #expect(NoteFileTestSupport.read(trash.appendingPathComponent("Trash me.md")) == "last words\n")
    }

    @Test func aTrashedOpenNoteKnowsItIsGoneAndIsNotRecreated() throws {
        let (_, session, _) = try trashing()
        #expect(session.state == .missing)
        clock.advance(5)
        #expect(!NoteFilePaths.itemExists(session.url))
    }

    @Test func flushAllSavesEverySession() throws {
        let a = try open("a.txt", "a\n")
        let b = try open("b.txt", "b\n")
        setText(a, "a2")
        setText(b, "b2")
        try files.flushAll()
        #expect(NoteFileTestSupport.read(a.url) == "a2\n")
        #expect(NoteFileTestSupport.read(b.url) == "b2\n")
    }

    @Test func aSessionStaysWhileAnEditorStillHoldsIt() throws {
        let a = try open("a.txt", "a\n")
        a.retain()
        a.retain()
        a.release()
        #expect(files.session(for: a.url) === a)
    }

    @Test func theLastReleaseFlushesAndDropsTheSession() throws {
        let a = try open("a.txt", "a\n")
        a.retain()
        setText(a, "a3")
        a.release()
        #expect(NoteFileTestSupport.read(a.url) == "a3\n")
        #expect(files.session(for: a.url) == nil)
    }

    @Test func reopeningAfterTheLastReleaseMakesAFreshSessionWithTheSavedText() throws {
        let a = try open("a.txt", "a\n")
        a.retain()
        setText(a, "a3")
        a.release()
        let reopened = try files.open(a.url)
        #expect(reopened !== a)
        #expect(texts(reopened) == ["a3"])
    }

    @Test func aLateEditOnAReleasedSessionSavesWithoutStealingTheNewerSessionsSpot() throws {
        let a = try open("a.txt", "a\n")
        a.retain()
        a.release()
        let reopened = try files.open(a.url)
        setText(a, "edited after the last release")
        clock.advance(1)
        #expect(NoteFileTestSupport.read(a.url) == "edited after the last release\n")
        #expect(files.session(for: a.url) === reopened)
    }

    @Test func aRevivedSessionRegistersAgainAndSaves() throws {
        let lonely = try open("lonely.txt", "x\n")
        lonely.retain()
        lonely.release()
        setText(lonely, "revived")
        #expect(files.session(for: lonely.url) === lonely)
        clock.advance(1)
        #expect(NoteFileTestSupport.read(lonely.url) == "revived\n")
    }

    @Test func aConflictedSessionStaysAliveAfterItsLastRelease() throws {
        let (url, session) = try conflicted("stuck.txt")
        session.retain()
        session.release()
        #expect(files.session(for: url) === session)
    }

    @Test func aMarkdownCopyGetsAFreshNameAndHoldsTheText() throws {
        file("Turn me.md", "existing")
        let copy = try open("Turn me.txt", "Line one\nLine two\n").saveMarkdownCopy()
        #expect(copy.lastPathComponent == "Turn me 2.md")
        #expect(NoteFileTestSupport.read(copy).contains("Line one") && NoteFileTestSupport.read(copy).hasSuffix("\n"))
    }

    @Test func savingAMarkdownCopyLeavesTheTextFileUntouched() throws {
        let session = try open("Turn me.txt", "Line one\nLine two\n")
        _ = try session.saveMarkdownCopy()
        #expect(NoteFileTestSupport.read(session.url) == "Line one\nLine two\n")
    }

    @Test func anOutsideEditIsNoticedAndReloaded() throws {
        let (url, session) = try watched()
        defer { session.release() }
        try Data("after\n".utf8).write(to: url, options: .atomic)
        reload(session)
        #expect(texts(session) == ["after"])
    }

    @Test func aPlainWriteAfterAnAtomicReplaceIsNoticedToo() throws {
        let (url, session) = try watched()
        defer { session.release() }
        try Data("after\n".utf8).write(to: url, options: .atomic)
        reload(session)
        NoteFileTestSupport.write("plain write\n", to: url)
        reload(session)
        #expect(texts(session) == ["plain write"])
    }

    @Test func myOwnSavesDoNotBounceBackAsOutsideEdits() throws {
        let (_, session) = try watched()
        defer { session.release() }
        setText(session, "typed")
        clock.advance(1)
        reload(session)
        #expect(texts(session) == ["typed"])
        #expect(session.state == .saved)
    }

    @Test func aDeletionEventIsNoticed() throws {
        let (url, session) = try watched()
        defer { session.release() }
        try FileManager.default.removeItem(at: url)
        session.handle(.deleted)
        clock.advance(1)
        #expect(session.state == .missing)
    }

    @Test func aFileRecreatedBySomeoneElseIsPickedUp() throws {
        let (url, session) = try watched()
        defer { session.release() }
        try FileManager.default.removeItem(at: url)
        session.handle(.deleted)
        clock.advance(1)
        NoteFileTestSupport.write("back again\n", to: url)
        reload(session)
        #expect(texts(session) == ["back again"])
        #expect(session.state == .saved)
    }

    func evicted() throws -> NoteFileSession {
        let session = try open("evicted.txt", "base\n")
        setText(session, "mine")
        try FileManager.default.removeItem(at: session.url)
        session.checkDisk()
        return session
    }

    @Test func aFileThatVanishesUnderUnsavedEditsShowsAsMissingAndIsNotRecreated() throws {
        let session = try evicted()
        #expect(session.state == .missing)
        #expect(texts(session) == ["mine"])
        clock.advance(5)
        #expect(!NoteFilePaths.itemExists(session.url))
    }

    @Test func aFileThatReturnsAsItWasKeepsAndSavesTheUnsavedEdits() throws {
        let session = try evicted()
        NoteFileTestSupport.write("base\n", to: session.url)
        session.checkDisk()
        #expect(texts(session) == ["mine"])
        clock.advance(1)
        #expect(NoteFileTestSupport.read(session.url) == "mine\n")
        #expect(session.state == .saved)
    }

    @Test func aFileThatReturnsDifferentWhileEditsAreUnsavedIsAConflict() throws {
        let session = try evicted()
        NoteFileTestSupport.write("someone else's\n", to: session.url)
        session.checkDisk()
        #expect(session.state == .conflict)
        #expect(texts(session) == ["mine"])
        #expect(session.conflictingText == "someone else's")
        clock.advance(5)
        #expect(NoteFileTestSupport.read(session.url) == "someone else's\n")
    }

    @Test func anExplicitFlushPutsUnsavedEditsBack() throws {
        let session = try evicted()
        try session.flush()
        #expect(NoteFileTestSupport.read(session.url) == "mine\n")
    }

    @Test func anAutosaveRacingAMoveFollowsTheFile() throws {
        let session = try open("Racer.md", "Original\n")
        let original = session.url
        setText(session, "Edited on the way")
        let destination = folder.appendingPathComponent("Racer moved.md")
        try FileManager.default.moveItem(at: original, to: destination)
        clock.advance(2)
        #expect(!NoteFilePaths.itemExists(original))
        #expect(session.url == destination)
        #expect(NoteFileTestSupport.read(destination).contains("Edited on the way"))
        #expect(session.state == .saved)
    }

    @Test func anAutosaveRacingAMoveToTheTrashDoesNotRecreateTheFile() throws {
        let session = try open("Racer.md", "Original\n")
        let original = session.url
        setText(session, "Last words before the Trash")
        try FileManager.default.moveItem(at: original, to: try trashFolder().appendingPathComponent("Racer.md"))
        clock.advance(5)
        #expect(!NoteFilePaths.itemExists(original))
        #expect(session.state == .missing)
        #expect(texts(session) == ["Last words before the Trash"])
    }

    @Test func aFlushRacingAMoveWritesWhereTheFileWent() throws {
        let session = try open("Flushed.md", "Before\n")
        let original = session.url
        setText(session, "After")
        let elsewhere = folder.appendingPathComponent("Flushed elsewhere.md")
        try FileManager.default.moveItem(at: original, to: elsewhere)
        try session.flush()
        #expect(!NoteFilePaths.itemExists(original))
        #expect(NoteFileTestSupport.read(elsewhere).contains("After"))
        #expect(session.url == elsewhere)
    }

    func askToSave(_ session: NoteFileSession) throws -> (answered: Bool, error: Error?) {
        let presenter = try #require(session.presenter)
        let reply = NoteLockedBox<Error?>()
        presenter.savePresentedItemChanges? { error in reply.set(.some(error)) }
        hops.runAll()
        return (reply.value != nil, reply.value ?? nil)
    }

    func busyNote(_ text: String = "Fresh words") throws -> (URL, NoteFileSession) {
        let url = file("Shared draft.md", "Old words\n")
        let session = try files.open(url)
        session.retain()
        setText(session, text)
        return (url, session)
    }

    @Test func aSaveRequestIsAnswered() throws {
        let (_, session) = try busyNote()
        defer { session.release() }
        let busy = try askToSave(session)
        #expect(busy.answered)
        #expect(busy.error == nil)
    }

    @Test func aSaveRequestReallySavesAndTheNoteKnowsIt() throws {
        let (url, session) = try busyNote("Saved while busy")
        defer { session.release() }
        _ = try askToSave(session)
        #expect(NoteFileTestSupport.read(url) == "Saved while busy\n")
        #expect(session.state == .saved)
    }

    @Test func aSavedRequestLeavesTheAutosaveNothingToDo() throws {
        let (url, session) = try busyNote()
        defer { session.release() }
        _ = try askToSave(session)
        clock.advance(1)
        #expect(NoteFileTestSupport.read(url) == "Fresh words\n")
        #expect(session.state == .saved)
    }

    func refusedSave() throws -> (URL, NoteFileSession, (answered: Bool, error: Error?)) {
        let (url, session) = try busyNote("Mine")
        NoteFileTestSupport.write("Theirs\n", to: url)
        return (url, session, try askToSave(session))
    }

    @Test func aSaveThatCannotHappenIsStillAnswered() throws {
        let (_, session, refused) = try refusedSave()
        defer { session.resolveConflict(keepMine: false); session.release() }
        #expect(refused.answered)
    }

    @Test func aRefusedSaveAnswersWithTheReasonInsteadOfAFakeSuccess() throws {
        let (_, session, refused) = try refusedSave()
        defer { session.resolveConflict(keepMine: false); session.release() }
        #expect(refused.error as? NoteFileError == .conflict)
    }

    @Test func aRefusedSaveLeavesTheirWordsAndShowsTheConflict() throws {
        let (url, session, _) = try refusedSave()
        defer { session.resolveConflict(keepMine: false); session.release() }
        #expect(NoteFileTestSupport.read(url) == "Theirs\n")
        #expect(session.state == .conflict)
    }

    @Test func anOpenNotePresentsItsFile() throws {
        let session = try open("Visitor.txt", "hi\n")
        session.retain()
        defer { session.release() }
        #expect(NoteFileTestSupport.isPresented(session.url))
    }

    @Test func theLastReleaseStopsPresentingTheFile() throws {
        let session = try open("Visitor.txt", "hi\n")
        session.retain()
        session.release()
        #expect(!NoteFileTestSupport.isPresented(session.url))
    }

    @Test func aLateEditPresentsTheFileUntilItIsSaved() throws {
        let session = try open("Visitor.txt", "hi\n")
        session.retain()
        session.release()
        setText(session, "back for more")
        #expect(NoteFileTestSupport.isPresented(session.url))
        clock.advance(1)
        #expect(NoteFileTestSupport.read(session.url) == "back for more\n")
        #expect(!NoteFileTestSupport.isPresented(session.url))
    }

    func stubborn() throws -> (URL, URL, NoteFileSession) {
        let locked = folder.appendingPathComponent("Locked", isDirectory: true)
        let session = try open("Locked/Stubborn.txt", "start\n")
        session.retain()
        setText(session, "kept safe")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        return (locked, session.url, session)
    }

    func unlock(_ locked: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
    }

    @Test func flushAllNamesTheNoteThatCannotBeSaved() throws {
        let (locked, _, session) = try stubborn()
        defer { unlock(locked); session.release() }
        #expect(throws: NoteFileError.unsaved(["Stubborn"])) { try self.files.flushAll() }
    }

    @Test func aSessionThatCannotSaveStaysAliveAndSaysTheSaveFailed() throws {
        let (locked, url, session) = try stubborn()
        defer { unlock(locked) }
        session.release()
        #expect(files.session(for: url) === session)
        guard case .failed = session.state else {
            Issue.record("expected a failed save, got \(session.state)")
            return
        }
    }

    @Test func anUnattendedSessionKeepsRetryingAndLetsGoOnceItSaves() throws {
        let (locked, url, session) = try stubborn()
        defer { unlock(locked) }
        session.release()
        clock.advance(1.5)
        #expect(NoteFileTestSupport.read(url) == "start\n")
        unlock(locked)
        clock.advance(5)
        #expect(NoteFileTestSupport.read(url) == "kept safe\n")
        #expect(files.session(for: url) == nil)
        #expect(!NoteFileTestSupport.isPresented(url))
    }

    func contested() throws -> (URL, NoteFileSession) {
        let url = file("Contested.md", "Base\n")
        let session = try files.open(url)
        session.retain()
        setText(session, "My take")
        NoteFileTestSupport.write("Their take\n", to: url)
        session.checkDisk()
        session.release()
        return (url, session)
    }

    @Test func anUnresolvedConflictWaitsForTheNextEditor() throws {
        let (url, session) = try contested()
        let again = try files.open(url)
        #expect(again === session && again.state == .conflict)
    }

    @Test func atQuitAnUnattendedConflictKeepsMyWordsInACopyAndCloses() throws {
        let (url, _) = try contested()
        try files.flushAll()
        #expect(NoteFileTestSupport.read(folder.appendingPathComponent("Contested (your version).md")).contains("My take"))
        #expect(NoteFileTestSupport.read(url) == "Their take\n")
        #expect(files.session(for: url) == nil)
        #expect(!NoteFileTestSupport.isPresented(url))
    }

    @Test func anInPlaceWriteAfterTheFileSteppedOutAndBackIsStillNoticed() throws {
        let url = file("gap.txt", "one\n")
        let session = try files.open(url)
        session.retain()
        defer { session.release() }
        let parked = folder.appendingPathComponent("gap parked.txt")
        #expect(rename(url.path, parked.path) == 0)
        #expect(rename(parked.path, url.path) == 0)
        session.checkDisk()
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("two, written in place\n".utf8))
        try handle.close()
        reload(session)
        #expect(texts(session) == ["two, written in place"])
    }
}

final class NoteFileWatcherTests {
    let folder = NoteFileTestSupport.makeFolder("watcher")

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    struct Stamped {
        let url: URL
        let read: NoteFileStamp
    }

    func stampedFile() throws -> Stamped {
        let url = NoteFileTestSupport.write("first version\n", to: folder.appendingPathComponent("stamped.txt"))
        let read = try #require(NoteFileStamp(path: url.path))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("second, longer version\n".utf8))
        try handle.close()
        return Stamped(url: url, read: read)
    }

    func listen(_ url: URL, seen: NoteFileSighting) -> [NoteFileWatchEvent] {
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

    @Test func theOccupiedErrorSaysWhatIsWrong() {
        #expect(NoteFileError.occupied("Taken.md").localizedDescription == "Something else is already called “Taken.md” there. Move or rename it, then try again.")
    }

    @Test func theUnsavedErrorReadsInWordsPeopleCanActOn() {
        #expect(NoteFileError.unsaved(["Stubborn"]).localizedDescription == "Parc couldn’t save “Stubborn” yet. Open it to sort things out.")
    }
}
