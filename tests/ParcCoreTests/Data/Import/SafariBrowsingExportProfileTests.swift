import Compression
import Foundation
import Testing
@testable import ParcCore

struct SafariBrowsingExportProfileTests {
    private typealias Support = SafariBrowsingExportTestsSupport

    private let workspace: Support.SafariWorkspace

    init() throws { workspace = try Support.SafariWorkspace() }

    @Test func historyFilesAreRecognisedByDataTypeAndTheUnsuffixedDefaultProfileComesFirst() throws {
        let export = try workspace.localized()
        #expect(export.profiles.map(\.name) == [nil, "Arbeit"])
    }

    @Test func eachProfilesHistoryIsWrittenToItsOwnNumberedFolder() throws {
        let export = try workspace.localized()
        #expect(export.profiles.map(\.directory) == [0, 1].map { export.directory.appendingPathComponent("profile-\($0)", isDirectory: true) })
    }

    @Test func historyIsWrittenExactlyAsSafariExportedIt() throws {
        let export = try workspace.localized()
        #expect(workspace.contents(export.profiles[0].directory.appendingPathComponent("History.json")) == Data(Support.safariDefaultHistory.utf8))
        #expect(workspace.contents(export.profiles[1].directory.appendingPathComponent("History.json")) == Data(Support.safariWorkHistory.utf8))
    }

    @Test func extensionsAndPaymentCardsAreDetectedByDataTypeWhateverTheFileIsCalled() throws {
        let export = try workspace.localized()
        #expect(export.includesExtensions && export.includesPaymentCards)
    }

    @Test func anExportWithoutAPasswordsFileReportsNoPasswords() throws {
        #expect(try workspace.localized().passwordsFile == nil)
    }

    @Test func theLocalizedBookmarksFileIsReadByItsExtension() throws {
        #expect(try workspace.localized().bookmarks.count == 3)
    }

    @Test func theExportIsUnpackedIntoAFreshFolderInsideTheRequestedRoot() throws {
        let export = try workspace.localized()
        #expect(export.directory.deletingLastPathComponent().standardizedFileURL == workspace.root.standardizedFileURL
                && export.directory.lastPathComponent.hasPrefix("ParcSafariExport-"))
    }

    @Test func unpackedFoldersAndFilesArePrivateToTheCurrentUser() throws {
        let export = try workspace.localized()
        #expect(workspace.permissions(export.directory) == 0o700 && workspace.permissions(export.profiles[0].directory) == 0o700)
        #expect(workspace.permissions(export.profiles[1].directory.appendingPathComponent("History.json")) == 0o600)
    }

    @Test func onlyHistoryAndPaymentCardsAreWrittenToDisk() throws {
        let export = try workspace.localized()
        #expect(workspace.files(in: export.directory)
                == ["profile-0", "profile-0/History.json", "profile-0/PaymentCards.json", "profile-1", "profile-1/History.json"])
    }

    @Test func paymentCardsGoBesideTheDefaultProfilesHistoryExactlyAsExportedAndPrivate() throws {
        let export = try workspace.localized()
        #expect(export.paymentCardsFile == export.profiles[0].directory.appendingPathComponent("PaymentCards.json")
                && export.paymentCardsFile.flatMap(workspace.contents) == Data(Support.safariTypedJSON("payment_cards").utf8))
        #expect(export.paymentCardsFile.flatMap(workspace.permissions) == 0o600)
    }

    @Test func removingThePaymentCardsDeletesOnlyTheirFile() throws {
        let export = try workspace.localized()
        export.removePaymentCards()
        #expect(!workspace.manager.fileExists(atPath: export.profiles[0].directory.appendingPathComponent("PaymentCards.json").path)
                && workspace.manager.fileExists(atPath: export.profiles[0].directory.appendingPathComponent("History.json").path))
        export.removePaymentCards()
    }

    @Test func removingTheExportDeletesItsWholeFolder() throws {
        let export = try workspace.localized()
        export.remove()
        #expect(!workspace.manager.fileExists(atPath: export.directory.path))
    }

    @Test func whenEveryHistoryFileHasASuffixEachProfileIsNamedByItInArchiveOrder() throws {
        var latin = Support.SafariZipEntry("History.json", Support.safariHistoryJSON("https://latin.example.com/"))
        latin.name = Array("History - Pers".utf8) + [0xF6] + Array("nlich.json".utf8)
        var cafe = Support.SafariZipEntry("History - Café.json", Support.safariHistoryJSON("https://cafe.example.com/"))
        cafe.unicodeFlag = false
        let export = try workspace.open([
            Support.SafariZipEntry("History - Personal.json", Support.safariHistoryJSON("https://personal.example.com/")),
            Support.SafariZipEntry("History - Work.json", Support.safariHistoryJSON("https://work.example.com/")),
            latin,
            cafe,
        ])
        #expect(export.profiles.map(\.name) == ["Personal", "Work", "Persönlich", "Café"])
        #expect(workspace.contents(export.profiles[1].directory.appendingPathComponent("History.json"))
                == Data(Support.safariHistoryJSON("https://work.example.com/").utf8))
    }

    @Test func aSingleSuffixedHistoryFileNamesItsProfileAndReportsNothingElse() throws {
        let export = try workspace.open([Support.SafariZipEntry("History - Work.json", Support.safariHistoryJSON("https://work.example.com/"))])
        #expect(export.profiles.map(\.name) == ["Work"])
        #expect(export.bookmarks.isEmpty && export.passwordsFile == nil && export.paymentCardsFile == nil
                && !export.includesExtensions && !export.includesPaymentCards)
    }

    @Test func aSingleUnsuffixedHistoryFileIsTheDefaultProfile() throws {
        let export = try workspace.open([Support.SafariZipEntry("History.json", Support.safariHistoryJSON("https://plain.example.com/"))])
        #expect(export.profiles.map(\.name) == [nil])
    }

    @Test func duplicateProfileNamesAreBothKeptInArchiveOrder() throws {
        let export = try workspace.folderExport()
        #expect(export.profiles.map(\.name) == ["Work", "Work"])
        #expect(workspace.contents(export.profiles[1].directory.appendingPathComponent("History.json"))
                == Data(Support.safariHistoryJSON("https://second.example.com/").utf8))
    }

    @Test func withoutADefaultHistoryFileEveryProfileKeepsItsFullNameEvenWithADash() throws {
        let export = try workspace.open([Support.SafariZipEntry("History - Work.json", Support.safariHistoryJSON("https://work.example.com/")),
                                         Support.SafariZipEntry("History - Work - Old.json", Support.safariHistoryJSON("https://old.example.com/"))])
        #expect(export.profiles.map { $0.name } == ["Work", "Work - Old"])
    }

    @Test func withoutAnyHistoryPaymentCardsGetADefaultProfileFolderOfTheirOwn() throws {
        let export = try workspace.open([
            Support.SafariZipEntry("PaymentCards.json", Support.safariTypedJSON("payment_cards")),
            Support.SafariZipEntry("Extensions.json", Support.safariTypedJSON("extensions")),
            Support.SafariZipEntry("Notes.json", #"{"metadata":{"browser_name":"Safari"}}"#),
            Support.SafariZipEntry("Bookmarks.html", Support.safariSampleBookmarks),
        ])
        #expect(export.includesPaymentCards && export.includesExtensions && export.profiles.map(\.name) == [nil])
        #expect(workspace.files(in: export.directory) == ["profile-0", "profile-0/PaymentCards.json"]
                && export.paymentCardsFile == export.profiles[0].directory.appendingPathComponent("PaymentCards.json"))
    }

    @Test func anExportWithOnlyPaymentCardsAndExtensionsImportsItsPaymentCards() throws {
        let export = try workspace.open([Support.SafariZipEntry("PaymentCards.json", Support.safariTypedJSON("payment_cards"), deflate: false),
                                         Support.SafariZipEntry("Extensions.json", Support.safariTypedJSON("extensions"))])
        #expect(export.profiles.count == 1 && export.paymentCardsFile != nil && export.bookmarks.isEmpty
                && export.passwordsFile == nil)
    }
}
