import Compression
import Foundation
import Testing
@testable import ParcCore

struct SafariBrowsingExportRefusalTests {
    private typealias Support = SafariBrowsingExportTestsSupport

    private let workspace: Support.SafariWorkspace

    init() throws { workspace = try Support.SafariWorkspace() }

    @Test func anExportWithOnlyExtensionsIsNotImportable() {
        #expect(workspace.failure(Support.safariMakeZip([Support.SafariZipEntry("Extensions.json", Support.safariTypedJSON("extensions"))])) == Support.SafariMessages.notExport)
    }

    @Test func aPaymentCardsFileOver16MiBIsRefusedAsTooLarge() {
        let bulky = #"{"metadata":{"data_type":"payment_cards"},"payment_cards":[],"padding":""# + String(repeating: "a", count: 16 << 20) + #""}"#
        #expect(workspace.failure(Support.safariMakeZip([Support.SafariZipEntry("PaymentCards.json", bulky)])) == Support.SafariMessages.tooLarge)
    }

    @Test func aFileThatIsntAZipIsRefusedAsNotASafariExport() {
        #expect(workspace.failure(Data("This is a plain text note, not an archive.".utf8)) == Support.SafariMessages.notExport)
    }

    @Test func anEmptyFileIsRefusedAsNotASafariExport() {
        #expect(workspace.failure(Data()) == Support.SafariMessages.notExport)
    }

    @Test func anEmptyZipIsRefusedAsNotASafariExport() {
        #expect(workspace.failure(Support.safariMakeZip([])) == Support.SafariMessages.notExport)
    }

    @Test func anEncryptedEntryIsRefusedAsDamagedOrUnsupported() {
        var encrypted = Support.SafariZipEntry("History.json", Support.safariHistoryJSON("https://secret.example.com/"))
        encrypted.flags = 0x0001
        #expect(workspace.failure(Support.safariMakeZip([encrypted])) == Support.SafariMessages.damaged)
    }

    @Test func anUnsupportedCompressionMethodIsRefused() {
        var unsupported = Support.SafariZipEntry("Bookmarks.html", Support.safariSampleBookmarks)
        unsupported.method = 12
        #expect(workspace.failure(Support.safariMakeZip([unsupported])) == Support.SafariMessages.damaged)
    }

    @Test func aCRCMismatchIsRefusedAsDamaged() {
        var corrupt = Support.SafariZipEntry("Bookmarks.html", Support.safariSampleBookmarks)
        corrupt.crc = 0x1234_5678
        #expect(workspace.failure(Support.safariMakeZip([corrupt])) == Support.SafariMessages.damaged)
    }

    @Test func aStoredEntryWhoseSizesDisagreeIsRefusedAsDamaged() {
        var shortStored = Support.SafariZipEntry("Passwords.csv", Support.safariPasswordsCSV, deflate: false)
        shortStored.declaredSize = Support.safariPasswordsCSV.utf8.count + 3
        #expect(workspace.failure(Support.safariMakeZip([shortStored])) == Support.SafariMessages.damaged)
    }

    @Test func deflatedDataShorterThanItsDeclaredSizeIsRefusedAsDamaged() {
        var shorter = Support.SafariZipEntry("History.json", Support.safariHistoryJSON("https://short.example.com/"))
        shorter.declaredSize = Support.safariHistoryJSON("https://short.example.com/").utf8.count + 5
        #expect(workspace.failure(Support.safariMakeZip([shorter])) == Support.SafariMessages.damaged)
    }

    @Test func deflatedDataLongerThanItsDeclaredSizeIsRefusedAsDamaged() {
        var longer = Support.SafariZipEntry("History.json", Support.safariHistoryJSON("https://long.example.com/"))
        longer.declaredSize = Support.safariHistoryJSON("https://long.example.com/").utf8.count - 5
        #expect(workspace.failure(Support.safariMakeZip([longer])) == Support.SafariMessages.damaged)
    }

    @Test func deflatedDataLongerThanDeclaredIsRefusedEvenWhenTheCRCMatchesTheDeclaredPrefix() {
        var longer = Support.SafariZipEntry("Passwords.csv", Support.safariPasswordsCSV)
        longer.declaredSize = Support.safariPasswordsCSV.utf8.count - 1
        longer.crc = Support.safariCRC32(Data(Support.safariPasswordsCSV.utf8).prefix(Support.safariPasswordsCSV.utf8.count - 1))
        #expect(workspace.failure(Support.safariMakeZip([longer])) == Support.SafariMessages.damaged)
    }

    @Test func entriesThatShareTheSameStoredDataAreRefusedAsDamaged() {
        let overlapping = Support.safariMakeZip([Support.SafariZipEntry("History.json", Support.safariDefaultHistory, deflate: false),
                                         Support.SafariZipEntry("History - Work.json", Support.safariDefaultHistory, deflate: false)],
                                        sharingData: true)
        #expect(workspace.failure(overlapping) == Support.SafariMessages.damaged)
    }

    @Test func aZip64EntryClaimingAnOffsetAtTheEndOfTheRangeIsRefusedNotACrash() {
        var farAway = Support.SafariZipEntry("History.json", Support.safariDefaultHistory)
        farAway.claimedOffset = UInt64.max
        #expect(workspace.failure(Support.safariMakeZip([farAway], zip64: true)) == Support.SafariMessages.damaged)
    }

    @Test func aPasswordsFileOver32MiBIsRefusedAsTooLarge() {
        let oversized = String(repeating: "a", count: 33_554_433)
        #expect(workspace.failure(Support.safariMakeZip([Support.SafariZipEntry("Passwords.csv", oversized)])) == Support.SafariMessages.tooLarge)
    }

    @Test func unsafeHiddenAndResourceForkEntriesAreIgnoredEntirely() {
        #expect(workspace.failure(Support.safariMakeZip(workspace.traversal)) == Support.SafariMessages.notExport)
    }

    @Test func anExportWhoseBookmarksExceedTheLimitsIsRefusedAsTooLarge() {
        let tooDeep = Support.safariMakeZip([Support.SafariZipEntry("Bookmarks.html", Support.safariNested(128, leaf: true))])
        #expect(workspace.failure(tooDeep) == Support.SafariMessages.tooLarge)
    }

    enum FailedArchive: String, Sendable, CaseIterable, CustomTestStringConvertible {
        case extensionsOnly = "Extensions only"
        case ignoredEntries = "Ignored traversal and hidden entries"
        case deepBookmarks = "Bookmarks beyond the nesting limit"
        case invalidPasswordSize = "Stored password size disagrees with the data"

        var testDescription: String { rawValue }
    }

    @Test(arguments: FailedArchive.allCases)
    func failedImportsLeaveNoUnpackedFoldersOrPasswordsBehind(_ archive: FailedArchive) throws {
        let entries: [Support.SafariZipEntry]
        switch archive {
        case .extensionsOnly:
            entries = [Support.SafariZipEntry("Extensions.json", Support.safariTypedJSON("extensions"))]
        case .ignoredEntries:
            entries = workspace.traversal
        case .deepBookmarks:
            entries = [Support.SafariZipEntry("Bookmarks.html", Support.safariNested(128, leaf: true))]
        case .invalidPasswordSize:
            var shortStored = Support.SafariZipEntry("Passwords.csv", Support.safariPasswordsCSV, deflate: false)
            shortStored.declaredSize = Support.safariPasswordsCSV.utf8.count + 3
            entries = [shortStored]
        }
        _ = workspace.failure(Support.safariMakeZip(entries))
        let export = try workspace.open([Support.SafariZipEntry("History.json", Support.safariDefaultHistory)])
        export.remove()
        #expect(workspace.leftovers().isEmpty)
    }
}
