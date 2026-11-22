import Foundation
import Testing
@testable import ParcCore

struct NoteFileCodecPathTests {
    @Test func relativeSiblingPathsEncodeSpaces() {
        let folder = NoteFileTestSupport.makeFolder("paths")
        defer { NoteFileTestSupport.remove(folder) }
        #expect(NoteFilePaths.relativePath(from: folder, to: folder.appendingPathComponent("My Note.md")) == "My%20Note.md", "siblings link by encoded name")
    }

    @Test func relativePathsToParentsUseDotDotAndEncodeParentheses() {
        let folder = NoteFileTestSupport.makeFolder("paths")
        defer { NoteFileTestSupport.remove(folder) }
        let deep = folder.appendingPathComponent("Sub/Deeper", isDirectory: true)
        try! FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        #expect(NoteFilePaths.relativePath(from: deep, to: folder.appendingPathComponent("Up (1).md")) == "../../Up%20%281%29.md", "parents link with ../ and encoded parentheses")
    }

    @Test func relativePathsToChildrenKeepReadableLetters() {
        let folder = NoteFileTestSupport.makeFolder("paths")
        defer { NoteFileTestSupport.remove(folder) }
        let deep = folder.appendingPathComponent("Sub/Deeper", isDirectory: true)
        try! FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        #expect(NoteFilePaths.relativePath(from: folder, to: deep.appendingPathComponent("Café #2.md")) == "Sub/Deeper/Café%20%232.md", "children keep readable letters")
    }

    @Test func differentRootsHaveNoRelativePath() {
        #expect(NoteFilePaths.relativePath(from: URL(fileURLWithPath: "/Users/a"), to: URL(fileURLWithPath: "/Volumes/Disk/x.md")) == nil, "different roots don't get relative links")
    }

    @Test func reservedAndInvisibleCharactersAreEncoded() {
        #expect(NoteFilePaths.encodedSegment("a b:c?d\u{00A0}e") == "a%20b%3Ac%3Fd%C2%A0e", "reserved and invisible characters are encoded")
    }

    @Test func missingPathsCanonicalizeTheirExistingPrefix() {
        let unresolved = URL(fileURLWithPath: "/private/var/../var/nothing-here/x.md")
        #expect(NoteFilePaths.canonical(unresolved).path == "/private/var/nothing-here/x.md", "missing paths canonicalize their existing prefix")
    }

    @Test func canonicalPathsResolveSymlinkedPrefixes() {
        let folder = NoteFileTestSupport.makeFolder("paths")
        defer { NoteFileTestSupport.remove(folder) }
        let viaVar = URL(fileURLWithPath: folder.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
        #expect(NoteFilePaths.canonical(viaVar).path == folder.path, "symlinked prefixes resolve")
    }

    @Test func aFolderContainsItsNestedItems() {
        let folder = NoteFileTestSupport.makeFolder("paths")
        defer { NoteFileTestSupport.remove(folder) }
        let deep = folder.appendingPathComponent("Sub/Deeper", isDirectory: true)
        try! FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        #expect(NoteFilePaths.contains(folder: folder, item: deep.appendingPathComponent("n.md")), "nested items are inside")
    }

    @Test func aFolderDoesNotContainItself() {
        let folder = NoteFileTestSupport.makeFolder("paths")
        defer { NoteFileTestSupport.remove(folder) }
        #expect(!NoteFilePaths.contains(folder: folder, item: folder), "the folder isn't inside itself")
    }

    @Test func aSubfolderDoesNotContainItsParentItems() {
        let folder = NoteFileTestSupport.makeFolder("paths")
        defer { NoteFileTestSupport.remove(folder) }
        let deep = folder.appendingPathComponent("Sub/Deeper", isDirectory: true)
        try! FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        #expect(!NoteFilePaths.contains(folder: deep, item: folder.appendingPathComponent("n.md")), "parents aren't inside children")
    }

    @Test func aSharedPathPrefixDoesNotImplyContainment() {
        let folder = NoteFileTestSupport.makeFolder("paths")
        defer { NoteFileTestSupport.remove(folder) }
        #expect(!NoteFilePaths.contains(folder: folder.appendingPathComponent("Sub"), item: folder.appendingPathComponent("Subway/n.md")), "a shared prefix isn't containment")
    }

    @Test func theTrashIsRecognized() {
        #expect(NoteFilePaths.isInTrash(URL(fileURLWithPath: "/Users/me/.Trash/n.md")), "the Trash is spotted")
    }

    @Test func anOrdinaryFolderIsNotTheTrash() {
        let folder = NoteFileTestSupport.makeFolder("paths")
        defer { NoteFileTestSupport.remove(folder) }
        #expect(!NoteFilePaths.isInTrash(folder.appendingPathComponent("n.md")), "ordinary folders aren't the Trash")
    }

    @Test func aSymlinkedFolderResolvesToTheRealFile() {
        let folder = NoteFileTestSupport.makeFolder("identity")
        defer { NoteFileTestSupport.remove(folder) }
        let real = folder.appendingPathComponent("Real Folder", isDirectory: true)
        let plan = NoteFileTestSupport.write("plan\n", to: real.appendingPathComponent("Plan.md"))
        let link = folder.appendingPathComponent("Linked", isDirectory: true)
        try! FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let viaLink = link.appendingPathComponent("Plan.md")
        #expect(NoteFilePaths.canonical(viaLink).path == plan.path, "a symlinked folder resolves to the real file")
    }

    @Test func theFirmlinkedDataVolumePathResolvesToTheRealFile() {
        let folder = NoteFileTestSupport.makeFolder("identity")
        defer { NoteFileTestSupport.remove(folder) }
        let real = folder.appendingPathComponent("Real Folder", isDirectory: true)
        let plan = NoteFileTestSupport.write("plan\n", to: real.appendingPathComponent("Plan.md"))
        let viaData = URL(fileURLWithPath: "/System/Volumes/Data" + plan.path)
        #expect(NoteFilePaths.canonical(viaData).path == plan.path, "the firmlinked Data volume path is the same file")
    }

    @Test func alternateSpellingsIdentifyTheSameFile() {
        let folder = NoteFileTestSupport.makeFolder("identity")
        defer { NoteFileTestSupport.remove(folder) }
        let real = folder.appendingPathComponent("Real Folder", isDirectory: true)
        let plan = NoteFileTestSupport.write("plan\n", to: real.appendingPathComponent("Plan.md"))
        let link = folder.appendingPathComponent("Linked", isDirectory: true)
        try! FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let viaVar = URL(fileURLWithPath: plan.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
        let viaLink = link.appendingPathComponent("Plan.md")
        let viaData = URL(fileURLWithPath: "/System/Volumes/Data" + plan.path)
        #expect(NoteFilePaths.sameItem(plan, viaVar) && NoteFilePaths.sameItem(plan, viaLink) && NoteFilePaths.sameItem(plan, viaData), "every spelling of one file is one item")
    }

    @Test func alternateSpellingsOfAFileShareOneKey() {
        let folder = NoteFileTestSupport.makeFolder("identity")
        defer { NoteFileTestSupport.remove(folder) }
        let real = folder.appendingPathComponent("Real Folder", isDirectory: true)
        let plan = NoteFileTestSupport.write("plan\n", to: real.appendingPathComponent("Plan.md"))
        let link = folder.appendingPathComponent("Linked", isDirectory: true)
        try! FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let viaVar = URL(fileURLWithPath: plan.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
        let viaLink = link.appendingPathComponent("Plan.md")
        let viaData = URL(fileURLWithPath: "/System/Volumes/Data" + plan.path)
        #expect(Set([plan, viaVar, viaLink, viaData].map(NoteFilePaths.key(for:))).count == 1, "and has one identity key")
    }

    @Test func aDifferentNameIdentifiesADifferentFile() {
        let folder = NoteFileTestSupport.makeFolder("identity")
        defer { NoteFileTestSupport.remove(folder) }
        let real = folder.appendingPathComponent("Real Folder", isDirectory: true)
        let plan = NoteFileTestSupport.write("plan\n", to: real.appendingPathComponent("Plan.md"))
        #expect(!NoteFilePaths.sameItem(plan, real.appendingPathComponent("Other.md")), "different files stay different")
    }

    @Test(.enabled(if: pathconf(FileManager.default.temporaryDirectory.path, _PC_CASE_SENSITIVE) == 0)) func canonicalPathsUseTheCaseOnDisk() {
        let folder = NoteFileTestSupport.makeFolder("identity")
        defer { NoteFileTestSupport.remove(folder) }
        let real = folder.appendingPathComponent("Real Folder", isDirectory: true)
        let plan = NoteFileTestSupport.write("plan\n", to: real.appendingPathComponent("Plan.md"))
        let shouted = real.appendingPathComponent("PLAN.md")
        #expect(NoteFilePaths.canonical(shouted).lastPathComponent == "Plan.md", "the canonical path takes the case on disk")
        #expect(NoteFilePaths.sameItem(plan, shouted), "a different case names the same file")
    }

    @Test(.enabled(if: pathconf(FileManager.default.temporaryDirectory.path, _PC_CASE_SENSITIVE) == 0)) func missingFilesMatchAcrossCaseAndSymlinks() throws {
        let folder = NoteFileTestSupport.makeFolder("identity")
        defer { NoteFileTestSupport.remove(folder) }
        let real = folder.appendingPathComponent("Real Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = folder.appendingPathComponent("Linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let ghost = real.appendingPathComponent("Ghost.md"), whisper = link.appendingPathComponent("ghost.MD")
        #expect(NoteFilePaths.sameItem(ghost, whisper), "files that don't exist yet still match across case and symlinks")
        #expect(NoteFilePaths.key(for: ghost) == NoteFilePaths.key(for: whisper), "with one key")
    }

    @Test(.enabled(if: pathconf(FileManager.default.temporaryDirectory.path, _PC_CASE_SENSITIVE) == 0)) func aDeletedFileKeepsItsIdentityKey() {
        let folder = NoteFileTestSupport.makeFolder("identity")
        defer { NoteFileTestSupport.remove(folder) }
        let real = folder.appendingPathComponent("Real Folder", isDirectory: true)
        let plan = NoteFileTestSupport.write("plan\n", to: real.appendingPathComponent("Plan.md"))
        let shouted = real.appendingPathComponent("PLAN.md")
        let before = NoteFilePaths.key(for: plan)
        try! FileManager.default.removeItem(at: plan)
        #expect(NoteFilePaths.key(for: shouted) == before, "a deleted file keeps the key it had while it existed")
    }

    @Test func aDirectoryNamedLikeANoteIsNotOpenable() {
        let folder = NoteFileTestSupport.makeFolder("paths")
        defer { NoteFileTestSupport.remove(folder) }
        let archive = folder.appendingPathComponent("Archive.md", isDirectory: true)
        try! FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        #expect(!NoteFilePaths.isOpenableFile(archive), "a folder named like a note isn't a note")
    }

    @Test func aMissingNoteIsNotOpenable() {
        let folder = NoteFileTestSupport.makeFolder("identity")
        defer { NoteFileTestSupport.remove(folder) }
        let real = folder.appendingPathComponent("Real Folder", isDirectory: true)
        #expect(!NoteFilePaths.isOpenableFile(real.appendingPathComponent("Nope.md")), "a missing file isn't openable")
    }

    @Test func aRealNoteCanOpenThroughASymlink() {
        let folder = NoteFileTestSupport.makeFolder("identity")
        defer { NoteFileTestSupport.remove(folder) }
        let real = folder.appendingPathComponent("Real Folder", isDirectory: true)
        NoteFileTestSupport.write("plan\n", to: real.appendingPathComponent("Plan.md"))
        let link = folder.appendingPathComponent("Linked", isDirectory: true)
        try! FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let viaLink = link.appendingPathComponent("Plan.md")
        #expect(NoteFilePaths.isOpenableFile(viaLink), "a real file through a symlink is")
    }
}
