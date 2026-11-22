import Compression
import Foundation
import Testing
@testable import ParcCore

struct SafariBrowsingExportFileTests {
    private typealias Support = SafariBrowsingExportTestsSupport

    private let workspace: Support.SafariWorkspace

    init() throws { workspace = try Support.SafariWorkspace() }

    @Test func theFirstBookmarksFileInArchiveOrderIsParsedInMemory() throws {
        let export = try workspace.folderExport()
        #expect(export.bookmarks == (try? SafariBookmarksHTML.parse(Data(Support.safariSampleBookmarks.utf8))))
    }

    @Test func passwordsAreUnpackedIntoTheirOwnFolderExactlyAndPrivately() throws {
        let export = try workspace.folderExport()
        #expect(export.passwordsFile == export.directory.appendingPathComponent("passwords/Passwords.csv"))
        #expect(export.passwordsFile.flatMap(workspace.contents) == Data(Support.safariPasswordsCSV.utf8))
        #expect(workspace.permissions(export.directory.appendingPathComponent("passwords")) == 0o700)
        #expect(export.passwordsFile.flatMap(workspace.permissions) == 0o600)
    }

    @Test func removingPasswordsDeletesOnlyThePasswordsFolder() throws {
        let export = try workspace.folderExport()
        export.removePasswords()
        #expect(!workspace.manager.fileExists(atPath: export.directory.appendingPathComponent("passwords").path)
                && workspace.manager.fileExists(atPath: export.profiles[0].directory.appendingPathComponent("History.json").path))
        export.removePasswords()
    }

    @Test func removingTheExportAfterItsPasswordsDeletesTheRest() throws {
        let export = try workspace.folderExport()
        export.removePasswords()
        export.remove()
        #expect(!workspace.manager.fileExists(atPath: export.directory.path))
    }

    @Test func zip64ArchivesWithSixtyFourBitCentralDirectoryFieldsAreRead() throws {
        let export = try workspace.open([
            Support.SafariZipEntry("History.json", Support.safariHistoryJSON("https://zip64.example.com/")),
            Support.SafariZipEntry("Bookmarks.html", Support.safariSampleBookmarks, deflate: false),
        ], zip64: true)
        #expect(export.profiles.map(\.name) == [nil]
                && workspace.contents(export.profiles[0].directory.appendingPathComponent("History.json"))
                    == Data(Support.safariHistoryJSON("https://zip64.example.com/").utf8))
        #expect(export.bookmarks.count == 3)
    }

    @Test func entriesWithDataDescriptorsAreReadUsingTheCentralDirectorySizes() throws {
        var described = Support.SafariZipEntry("History.json", Support.safariHistoryJSON("https://descriptor.example.com/"))
        described.descriptor = true
        var describedPasswords = Support.SafariZipEntry("Passwords.csv", Support.safariPasswordsCSV, deflate: false)
        describedPasswords.descriptor = true
        let export = try workspace.open([described, describedPasswords])
        #expect(workspace.contents(export.profiles[0].directory.appendingPathComponent("History.json"))
                == Data(Support.safariHistoryJSON("https://descriptor.example.com/").utf8)
                && export.passwordsFile.flatMap(workspace.contents) == Data(Support.safariPasswordsCSV.utf8))
    }

    struct LargeHistory: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let address: String
        let metadataLast: Bool
    }

    @Test(arguments: [
        LargeHistory(testDescription: "Metadata after 64 KiB", address: "https://large.example.com/", metadataLast: true),
        LargeHistory(testDescription: "Metadata at the start", address: "https://leading.example.com/", metadataLast: false),
    ])
    func aLargeHistoryIsRecognisedAndWrittenExactly(_ input: LargeHistory) throws {
        let history = Support.safariHistoryJSON(input.address, padding: 100_000, metadataLast: input.metadataLast)
        let export = try workspace.open([Support.SafariZipEntry("History.json", history)])
        #expect(workspace.contents(export.profiles[0].directory.appendingPathComponent("History.json")) == Data(history.utf8))
    }

    @Test func entriesParcDoesntUseAreNeverDecompressedWhateverTheirMethod() throws {
        var ignoredMethod = Support.SafariZipEntry("Notes.txt", "made-up notes")
        ignoredMethod.method = 12
        let export = try workspace.open([ignoredMethod, Support.SafariZipEntry("Bookmarks.html", Support.safariSampleBookmarks)])
        #expect(export.bookmarks.count == 3)
    }

    @Test func aDamagedHistoryFileIsSkippedAndCountedWhileTheRestStillImports() throws {
        var lateFailure = Support.SafariZipEntry("History - Work.json", Support.safariHistoryJSON("https://leading.example.com/", padding: 100_000))
        lateFailure.declaredSize = Support.safariHistoryJSON("https://leading.example.com/", padding: 100_000).utf8.count + 1
        let export = try workspace.open([Support.SafariZipEntry("Passwords.csv", Support.safariPasswordsCSV),
                                         Support.SafariZipEntry("History.json", Support.safariDefaultHistory), lateFailure])
        #expect(export.profiles.count == 1 && export.profiles[0].name == nil && export.passwordsFile != nil
                && export.skippedParts == 1)
    }

    @Test func aDamagedJSONFileThatIsntNeededDoesntStopTheImport() throws {
        let export = try workspace.open([Support.SafariZipEntry("History.json", Support.safariDefaultHistory), Support.safariCorruptJSON()])
        #expect(export.profiles.count == 1 && export.skippedParts == 1)
    }

    @Test func aPasswordsFileOfExactly32MiBIsUnpacked() throws {
        let export = try workspace.open([Support.SafariZipEntry("Passwords.csv", String(repeating: "a", count: 33_554_432))])
        #expect(export.passwordsFile.flatMap(workspace.contents)?.count == 33_554_432)
    }

    @Test func safeEntriesAreStillReadNextToIgnoredOnesAndIgnoredEntriesNeverReachTheDisk() throws {
        let export = try workspace.open(workspace.traversal + [Support.SafariZipEntry("Bookmarks.html", Support.safariSampleBookmarks)])
        #expect(export.profiles.isEmpty && export.passwordsFile == nil && export.bookmarks.count == 3)
        #expect((workspace.manager.enumerator(atPath: export.directory.path)?.allObjects as? [String]) ?? ["unreadable"] == [])
    }
}
