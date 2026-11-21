import Compression
import Foundation
import Testing
@testable import ParcCore

private struct SafariZipEntry {
    var name: [UInt8]
    var data: Data
    var deflate = true
    var flags: UInt16 = 0
    var method: UInt16?
    var crc: UInt32?
    var declaredSize: Int?
    var descriptor = false
    var unicodeFlag = false
    var claimedOffset: UInt64?

    init(_ name: String, _ data: Data, deflate: Bool = true) {
        self.name = Array(name.utf8)
        self.data = data
        self.deflate = deflate
        unicodeFlag = name.utf8.contains { $0 >= 0x80 }
    }

    init(_ name: String, _ text: String, deflate: Bool = true) {
        self.init(name, Data(text.utf8), deflate: deflate)
    }
}

private struct SafariZipWriter {
    var bytes: [UInt8] = []

    mutating func u16(_ value: UInt16) { append(value) }
    mutating func u32(_ value: UInt32) { append(value) }
    mutating func u64(_ value: UInt64) { append(value) }

    private mutating func append<T: FixedWidthInteger>(_ value: T) {
        for index in 0..<MemoryLayout<T>.size { bytes.append(UInt8(truncatingIfNeeded: value >> (8 * index))) }
    }
}

private let safariCRCTable: [UInt32] = (0..<256).map { seed in
    var value = UInt32(seed)
    for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
    return value
}

private func safariCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data { crc = safariCRCTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    return crc ^ 0xFFFF_FFFF
}

private func safariRawDeflate(_ data: Data) -> Data {
    let capacity = data.count + 4096
    var output = Data(count: capacity)
    let written = output.withUnsafeMutableBytes { target in
        data.withUnsafeBytes { source in
            compression_encode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                      source.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_ZLIB)
        }
    }
    check(written > 0, "The fixture writer can deflate its own test data.")
    output.count = written
    return output
}

private func safariMakeZip(_ entries: [SafariZipEntry], zip64: Bool = false, sharingData: Bool = false) -> Data {
    var archive = SafariZipWriter()
    var central = SafariZipWriter()
    var firstOffset: UInt64 = 0
    for (index, entry) in entries.enumerated() {
        let payload = entry.deflate ? safariRawDeflate(entry.data) : entry.data
        let method = entry.method ?? (entry.deflate ? 8 : 0)
        let crc = entry.crc ?? safariCRC32(entry.data)
        let size = UInt64(entry.declaredSize ?? entry.data.count)
        let flags = entry.flags | (entry.descriptor ? 0x0008 : 0) | (entry.unicodeFlag ? 0x0800 : 0)
        let shared = sharingData && index > 0
        let offset = shared ? firstOffset : UInt64(archive.bytes.count)
        if index == 0 { firstOffset = offset }
        let version: UInt16 = zip64 ? 45 : 20
        if !shared {
        archive.u32(0x0403_4B50)
        archive.u16(version)
        archive.u16(flags)
        archive.u16(method)
        archive.u16(0)
        archive.u16(0x0021)
        archive.u32(entry.descriptor ? 0 : crc)
        archive.u32(entry.descriptor ? 0 : UInt32(payload.count))
        archive.u32(entry.descriptor ? 0 : UInt32(size))
        archive.u16(UInt16(entry.name.count))
        archive.u16(4)
        archive.bytes += entry.name
        archive.u16(0xCAFE)
        archive.u16(0)
        archive.bytes += payload
        if entry.descriptor {
            archive.u32(0x0807_4B50)
            archive.u32(crc)
            archive.u32(UInt32(payload.count))
            archive.u32(UInt32(size))
        }
        }
        central.u32(0x0201_4B50)
        central.u16(0x031E)
        central.u16(version)
        central.u16(flags)
        central.u16(method)
        central.u16(0)
        central.u16(0x0021)
        central.u32(crc)
        central.u32(zip64 ? 0xFFFF_FFFF : UInt32(payload.count))
        central.u32(zip64 ? 0xFFFF_FFFF : UInt32(size))
        central.u16(UInt16(entry.name.count))
        central.u16(zip64 ? 28 : 0)
        central.u16(0)
        central.u16(0)
        central.u16(0)
        central.u32(0)
        central.u32(zip64 ? 0xFFFF_FFFF : UInt32(offset))
        central.bytes += entry.name
        if zip64 {
            central.u16(0x0001)
            central.u16(24)
            central.u64(size)
            central.u64(UInt64(payload.count))
            central.u64(entry.claimedOffset ?? offset)
        }
    }
    let directoryOffset = UInt64(archive.bytes.count)
    archive.bytes += central.bytes
    let directorySize = UInt64(central.bytes.count)
    if zip64 {
        let record = UInt64(archive.bytes.count)
        archive.u32(0x0606_4B50)
        archive.u64(44)
        archive.u16(45)
        archive.u16(45)
        archive.u32(0)
        archive.u32(0)
        archive.u64(UInt64(entries.count))
        archive.u64(UInt64(entries.count))
        archive.u64(directorySize)
        archive.u64(directoryOffset)
        archive.u32(0x0706_4B50)
        archive.u32(0)
        archive.u64(record)
        archive.u32(1)
    }
    archive.u32(0x0605_4B50)
    archive.u16(0)
    archive.u16(0)
    archive.u16(zip64 ? 0xFFFF : UInt16(entries.count))
    archive.u16(zip64 ? 0xFFFF : UInt16(entries.count))
    archive.u32(zip64 ? 0xFFFF_FFFF : UInt32(directorySize))
    archive.u32(zip64 ? 0xFFFF_FFFF : UInt32(directoryOffset))
    archive.u16(0)
    return Data(archive.bytes)
}

private func safariHistoryJSON(_ address: String, title: String = "Example", padding: Int = 0, metadataLast: Bool = false) -> String {
    let metadata = #""metadata":{"browser_name":"Safari","browser_version":"18.4","data_type" : "history","export_time_usec":1700000000000000,"schema_version":1}"#
    let filler = String(repeating: " ", count: padding)
    let history = #""history":[{"url":"\#(address)","title":"\#(title)","time_usec":1699999999000000,"visit_count":2}]"#
    return metadataLast ? "{\(history),\(filler)\(metadata)}" : "{\(metadata),\(filler)\(history)}"
}

private func safariCorruptJSON() -> SafariZipEntry {
    var entry = SafariZipEntry("Notes.json", #"{"metadata":{"data_type":"notes"}}"#)
    entry.crc = 0x0BAD_F00D
    return entry
}

private func safariTypedJSON(_ type: String) -> String {
    #"{"metadata":{"browser_name":"Safari","browser_version":"18.4","data_type":"\#(type)","export_time_usec":1700000000000000,"schema_version":1},"\#(type)":[]}"#
}

private let safariSampleBookmarks = """
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<HTML>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DT><H3 id="BookmarksBar">Favorites</H3>
<DL><p>
\t<DT><A HREF="https://www.example.com/">Example</A>
</DL><p>
<DT><H3 id="com.apple.ReadingList">Reading List</H3>
<DL><p>
</DL><p>
<DT><A HREF="https://support.example.com/guide/">Guide</A>
</HTML>
"""

private let safariRichBookmarks = """
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<!-- A made-up export with a <DT><A HREF="https://comment.example.com/">hidden</A> link in a comment -->
<HTML>
<H1>Bookmarks</H1>
<DT><H3 id="BookmarksBar">Favorites &amp; Friends</H3>
<DL><p>
\t<DT><A HREF="https://www.example.com/?a=1&amp;b=2" ADD_DATE="1" DATA-NOTE="x>y">Tom &amp; Jerry &lt;3 &quot;quoted&quot; &#39;single&#39; caf&#233; caf&#xE9; &unknown; a&b</A>
\t<dt><a href='https://example.org/single'>  lower case  </a>
\t<DT><A HREF="relative/path">Relative</A>
\t<DT><A HREF="">Empty</A>
\t<DT><A>No address</A>
\t<Dt><h3>Nested</H3>
\t<dL><p>
\t\t<DT><A HREF="https://nested.example.net/">Deep</A>
\t</Dl><p>
\t<DT><H3>Empty Inner</H3>
\t<DT><A HREF="https://after-empty.example.com/">After Empty</A>
</DL><p>
<DT><H3 id="com.apple.ReadingList">Reading List</H3>
<DL><p>
</DL><p>
<DT><A HREF="https://support.example.com/guide/">Guide</A>
<DT><H3>Unclosed</H3>
<DL><p>
\t<DT><A HREF="https://unclosed.example.com/">Inside</A>
</HTML>
"""

private func safariNested(_ folders: Int, leaf: Bool) -> Data {
    var text = "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n"
    for index in 0..<folders { text += "<DT><H3>Level \(index)</H3>\n<DL><p>\n" }
    if leaf { text += "<DT><A HREF=\"https://deep.example.com/\">Deep</A>\n" }
    for _ in 0..<folders { text += "</DL><p>\n" }
    return Data(text.utf8)
}
private let safariPasswordsCSV = "Title,URL,Username,Password,Notes,OTPAuth\nExample,https://example.com/,someone,made-up-secret,,\n"
private let safariDefaultHistory = safariHistoryJSON("https://default.example.com/")
private let safariWorkHistory = safariHistoryJSON("https://work.example.com/", title: #"Notes \"data_type\":\"extensions\""#, metadataLast: true)

private enum SafariMessages {
    static let notExport = "This file doesn’t contain Safari history, bookmarks, passwords or payment cards. Choose the .zip file Safari’s File → Export Browsing Data to File saves."
    static let tooLarge = "Part of this Safari export is too large to import."
    static let damaged = "This Safari export file is damaged or uses a format Parc can’t read."
}

private final class SafariWorkspace {
    let manager = FileManager.default
    let workspace: URL
    let root: URL

    init() throws {
        workspace = manager.temporaryDirectory.appendingPathComponent("SafariBrowsingExportTests-" + UUID().uuidString)
        root = workspace.appendingPathComponent("root", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? manager.removeItem(at: workspace) }

    func save(_ data: Data) throws -> URL {
        let url = workspace.appendingPathComponent("archive-\(UUID().uuidString).zip")
        try data.write(to: url)
        return url
    }

    func open(_ entries: [SafariZipEntry], zip64: Bool = false) throws -> SafariBrowsingExport {
        try SafariBrowsingExport.open(try save(safariMakeZip(entries, zip64: zip64)), temporaryRoot: root)
    }

    func leftovers() -> [String] {
        ((try? manager.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasPrefix("ParcSafariExport-") }
    }

    func failure(_ data: Data) -> String? {
        do {
            _ = try SafariBrowsingExport.open(try save(data), temporaryRoot: root)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func permissions(_ url: URL) -> Int? {
        (try? manager.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
    }

    func contents(_ url: URL) -> Data? { try? Data(contentsOf: url) }

    func files(in directory: URL) -> [String] {
        (manager.enumerator(atPath: directory.path)?.allObjects as? [String] ?? []).sorted()
    }

    func localized() throws -> SafariBrowsingExport {
        try open([
            SafariZipEntry("Verlauf - Arbeit.json", safariWorkHistory),
            SafariZipEntry("Erweiterungen - Arbeit.json", safariTypedJSON("extensions")),
            SafariZipEntry("Verlauf - Köder.json", safariTypedJSON("payment_cards"), deflate: false),
            SafariZipEntry("Verlauf.json", safariDefaultHistory, deflate: false),
            SafariZipEntry("Lesezeichen.html", safariSampleBookmarks),
        ])
    }

    func folderExport() throws -> SafariBrowsingExport {
        try open([
            SafariZipEntry("Safari Export/", Data(), deflate: false),
            SafariZipEntry("Safari Export/A/History - Work.json", safariHistoryJSON("https://first.example.com/")),
            SafariZipEntry("Safari Export/B/History - Work.json", safariHistoryJSON("https://second.example.com/")),
            SafariZipEntry("Safari Export/Bookmarks.html", safariSampleBookmarks, deflate: false),
            SafariZipEntry("Safari Export/Passwords.csv", safariPasswordsCSV),
            SafariZipEntry("Safari Export/Other Passwords.csv", "Title,URL\n"),
            SafariZipEntry("Safari Export/Other.html", "<DT><A HREF=\"https://other.example.com/\">Other</A>"),
        ])
    }

    var traversal: [SafariZipEntry] {
        [
            SafariZipEntry("../History.json", safariHistoryJSON("https://escape.example.com/")),
            SafariZipEntry("/tmp/History.json", safariHistoryJSON("https://absolute.example.com/")),
            SafariZipEntry("Export/../History.json", safariHistoryJSON("https://inner.example.com/")),
            SafariZipEntry("Export\\History.json", safariHistoryJSON("https://backslash.example.com/")),
            SafariZipEntry("__MACOSX/History.json", safariHistoryJSON("https://resource.example.com/")),
            SafariZipEntry("__MACOSX/Safari Export/._Bookmarks.html", safariSampleBookmarks),
            SafariZipEntry("._History.json", safariHistoryJSON("https://appledouble.example.com/")),
            SafariZipEntry(".Passwords.csv", safariPasswordsCSV),
            SafariZipEntry("Export/.hidden/../Bookmarks.html", safariSampleBookmarks),
        ]
    }
}

struct SafariBrowsingExportProfileTests {
    fileprivate let workspace: SafariWorkspace

    init() throws { workspace = try SafariWorkspace() }

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
        #expect(workspace.contents(export.profiles[0].directory.appendingPathComponent("History.json")) == Data(safariDefaultHistory.utf8))
        #expect(workspace.contents(export.profiles[1].directory.appendingPathComponent("History.json")) == Data(safariWorkHistory.utf8))
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
                && export.paymentCardsFile.flatMap(workspace.contents) == Data(safariTypedJSON("payment_cards").utf8))
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
        var latin = SafariZipEntry("History.json", safariHistoryJSON("https://latin.example.com/"))
        latin.name = Array("History - Pers".utf8) + [0xF6] + Array("nlich.json".utf8)
        var cafe = SafariZipEntry("History - Café.json", safariHistoryJSON("https://cafe.example.com/"))
        cafe.unicodeFlag = false
        let export = try workspace.open([
            SafariZipEntry("History - Personal.json", safariHistoryJSON("https://personal.example.com/")),
            SafariZipEntry("History - Work.json", safariHistoryJSON("https://work.example.com/")),
            latin,
            cafe,
        ])
        #expect(export.profiles.map(\.name) == ["Personal", "Work", "Persönlich", "Café"])
        #expect(workspace.contents(export.profiles[1].directory.appendingPathComponent("History.json"))
                == Data(safariHistoryJSON("https://work.example.com/").utf8))
    }

    @Test func aSingleSuffixedHistoryFileNamesItsProfileAndReportsNothingElse() throws {
        let export = try workspace.open([SafariZipEntry("History - Work.json", safariHistoryJSON("https://work.example.com/"))])
        #expect(export.profiles.map(\.name) == ["Work"])
        #expect(export.bookmarks.isEmpty && export.passwordsFile == nil && export.paymentCardsFile == nil
                && !export.includesExtensions && !export.includesPaymentCards)
    }

    @Test func aSingleUnsuffixedHistoryFileIsTheDefaultProfile() throws {
        let export = try workspace.open([SafariZipEntry("History.json", safariHistoryJSON("https://plain.example.com/"))])
        #expect(export.profiles.map(\.name) == [nil])
    }

    @Test func duplicateProfileNamesAreBothKeptInArchiveOrder() throws {
        let export = try workspace.folderExport()
        #expect(export.profiles.map(\.name) == ["Work", "Work"])
        #expect(workspace.contents(export.profiles[1].directory.appendingPathComponent("History.json"))
                == Data(safariHistoryJSON("https://second.example.com/").utf8))
    }

    @Test func withoutADefaultHistoryFileEveryProfileKeepsItsFullNameEvenWithADash() throws {
        let export = try workspace.open([SafariZipEntry("History - Work.json", safariHistoryJSON("https://work.example.com/")),
                                         SafariZipEntry("History - Work - Old.json", safariHistoryJSON("https://old.example.com/"))])
        #expect(export.profiles.map { $0.name } == ["Work", "Work - Old"])
    }

    @Test func withoutAnyHistoryPaymentCardsGetADefaultProfileFolderOfTheirOwn() throws {
        let export = try workspace.open([
            SafariZipEntry("PaymentCards.json", safariTypedJSON("payment_cards")),
            SafariZipEntry("Extensions.json", safariTypedJSON("extensions")),
            SafariZipEntry("Notes.json", #"{"metadata":{"browser_name":"Safari"}}"#),
            SafariZipEntry("Bookmarks.html", safariSampleBookmarks),
        ])
        #expect(export.includesPaymentCards && export.includesExtensions && export.profiles.map(\.name) == [nil])
        #expect(workspace.files(in: export.directory) == ["profile-0", "profile-0/PaymentCards.json"]
                && export.paymentCardsFile == export.profiles[0].directory.appendingPathComponent("PaymentCards.json"))
    }

    @Test func anExportWithOnlyPaymentCardsAndExtensionsImportsItsPaymentCards() throws {
        let export = try workspace.open([SafariZipEntry("PaymentCards.json", safariTypedJSON("payment_cards"), deflate: false),
                                         SafariZipEntry("Extensions.json", safariTypedJSON("extensions"))])
        #expect(export.profiles.count == 1 && export.paymentCardsFile != nil && export.bookmarks.isEmpty
                && export.passwordsFile == nil)
    }
}

struct SafariBrowsingExportFileTests {
    fileprivate let workspace: SafariWorkspace

    init() throws { workspace = try SafariWorkspace() }

    @Test func theFirstBookmarksFileInArchiveOrderIsParsedInMemory() throws {
        let export = try workspace.folderExport()
        #expect(export.bookmarks == (try? SafariBookmarksHTML.parse(Data(safariSampleBookmarks.utf8))))
    }

    @Test func passwordsAreUnpackedIntoTheirOwnFolderExactlyAndPrivately() throws {
        let export = try workspace.folderExport()
        #expect(export.passwordsFile == export.directory.appendingPathComponent("passwords/Passwords.csv"))
        #expect(export.passwordsFile.flatMap(workspace.contents) == Data(safariPasswordsCSV.utf8))
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
            SafariZipEntry("History.json", safariHistoryJSON("https://zip64.example.com/")),
            SafariZipEntry("Bookmarks.html", safariSampleBookmarks, deflate: false),
        ], zip64: true)
        #expect(export.profiles.map(\.name) == [nil]
                && workspace.contents(export.profiles[0].directory.appendingPathComponent("History.json"))
                    == Data(safariHistoryJSON("https://zip64.example.com/").utf8))
        #expect(export.bookmarks.count == 3)
    }

    @Test func entriesWithDataDescriptorsAreReadUsingTheCentralDirectorySizes() throws {
        var described = SafariZipEntry("History.json", safariHistoryJSON("https://descriptor.example.com/"))
        described.descriptor = true
        var describedPasswords = SafariZipEntry("Passwords.csv", safariPasswordsCSV, deflate: false)
        describedPasswords.descriptor = true
        let export = try workspace.open([described, describedPasswords])
        #expect(workspace.contents(export.profiles[0].directory.appendingPathComponent("History.json"))
                == Data(safariHistoryJSON("https://descriptor.example.com/").utf8)
                && export.passwordsFile.flatMap(workspace.contents) == Data(safariPasswordsCSV.utf8))
    }

    @Test func aLargeHistoryWhoseMetadataComesAfterTheFirst64KiBIsRecognisedAndWrittenExactly() throws {
        let history = safariHistoryJSON("https://large.example.com/", padding: 100_000, metadataLast: true)
        let export = try workspace.open([SafariZipEntry("History.json", history)])
        #expect(workspace.contents(export.profiles[0].directory.appendingPathComponent("History.json")) == Data(history.utf8))
    }

    @Test func aLargeHistoryRecognisedFromItsFirstBytesIsWrittenExactly() throws {
        let history = safariHistoryJSON("https://leading.example.com/", padding: 100_000)
        let export = try workspace.open([SafariZipEntry("History.json", history)])
        #expect(workspace.contents(export.profiles[0].directory.appendingPathComponent("History.json")) == Data(history.utf8))
    }

    @Test func entriesParcDoesntUseAreNeverDecompressedWhateverTheirMethod() throws {
        var ignoredMethod = SafariZipEntry("Notes.txt", "made-up notes")
        ignoredMethod.method = 12
        let export = try workspace.open([ignoredMethod, SafariZipEntry("Bookmarks.html", safariSampleBookmarks)])
        #expect(export.bookmarks.count == 3)
    }

    @Test func aDamagedHistoryFileIsSkippedAndCountedWhileTheRestStillImports() throws {
        var lateFailure = SafariZipEntry("History - Work.json", safariHistoryJSON("https://leading.example.com/", padding: 100_000))
        lateFailure.declaredSize = safariHistoryJSON("https://leading.example.com/", padding: 100_000).utf8.count + 1
        let export = try workspace.open([SafariZipEntry("Passwords.csv", safariPasswordsCSV),
                                         SafariZipEntry("History.json", safariDefaultHistory), lateFailure])
        #expect(export.profiles.count == 1 && export.profiles[0].name == nil && export.passwordsFile != nil
                && export.skippedParts == 1)
    }

    @Test func aDamagedJSONFileThatIsntNeededDoesntStopTheImport() throws {
        let export = try workspace.open([SafariZipEntry("History.json", safariDefaultHistory), safariCorruptJSON()])
        #expect(export.profiles.count == 1 && export.skippedParts == 1)
    }

    @Test func aPasswordsFileOfExactly32MiBIsUnpacked() throws {
        let export = try workspace.open([SafariZipEntry("Passwords.csv", String(repeating: "a", count: 33_554_432))])
        #expect(export.passwordsFile.flatMap(workspace.contents)?.count == 33_554_432)
    }

    @Test func safeEntriesAreStillReadNextToIgnoredOnesAndIgnoredEntriesNeverReachTheDisk() throws {
        let export = try workspace.open(workspace.traversal + [SafariZipEntry("Bookmarks.html", safariSampleBookmarks)])
        #expect(export.profiles.isEmpty && export.passwordsFile == nil && export.bookmarks.count == 3)
        #expect((workspace.manager.enumerator(atPath: export.directory.path)?.allObjects as? [String]) ?? ["unreadable"] == [])
    }
}

struct SafariBrowsingExportRefusalTests {
    fileprivate let workspace: SafariWorkspace

    init() throws { workspace = try SafariWorkspace() }

    @Test func anExportWithOnlyExtensionsIsNotImportable() {
        #expect(workspace.failure(safariMakeZip([SafariZipEntry("Extensions.json", safariTypedJSON("extensions"))])) == SafariMessages.notExport)
    }

    @Test func aPaymentCardsFileOver16MiBIsRefusedAsTooLarge() {
        let bulky = #"{"metadata":{"data_type":"payment_cards"},"payment_cards":[],"padding":""# + String(repeating: "a", count: 16 << 20) + #""}"#
        #expect(workspace.failure(safariMakeZip([SafariZipEntry("PaymentCards.json", bulky)])) == SafariMessages.tooLarge)
    }

    @Test func aFileThatIsntAZipIsRefusedAsNotASafariExport() {
        #expect(workspace.failure(Data("This is a plain text note, not an archive.".utf8)) == SafariMessages.notExport)
    }

    @Test func anEmptyFileIsRefusedAsNotASafariExport() {
        #expect(workspace.failure(Data()) == SafariMessages.notExport)
    }

    @Test func anEmptyZipIsRefusedAsNotASafariExport() {
        #expect(workspace.failure(safariMakeZip([])) == SafariMessages.notExport)
    }

    @Test func anEncryptedEntryIsRefusedAsDamagedOrUnsupported() {
        var encrypted = SafariZipEntry("History.json", safariHistoryJSON("https://secret.example.com/"))
        encrypted.flags = 0x0001
        #expect(workspace.failure(safariMakeZip([encrypted])) == SafariMessages.damaged)
    }

    @Test func anUnsupportedCompressionMethodIsRefused() {
        var unsupported = SafariZipEntry("Bookmarks.html", safariSampleBookmarks)
        unsupported.method = 12
        #expect(workspace.failure(safariMakeZip([unsupported])) == SafariMessages.damaged)
    }

    @Test func aCRCMismatchIsRefusedAsDamaged() {
        var corrupt = SafariZipEntry("Bookmarks.html", safariSampleBookmarks)
        corrupt.crc = 0x1234_5678
        #expect(workspace.failure(safariMakeZip([corrupt])) == SafariMessages.damaged)
    }

    @Test func aStoredEntryWhoseSizesDisagreeIsRefusedAsDamaged() {
        var shortStored = SafariZipEntry("Passwords.csv", safariPasswordsCSV, deflate: false)
        shortStored.declaredSize = safariPasswordsCSV.utf8.count + 3
        #expect(workspace.failure(safariMakeZip([shortStored])) == SafariMessages.damaged)
    }

    @Test func deflatedDataShorterThanItsDeclaredSizeIsRefusedAsDamaged() {
        var shorter = SafariZipEntry("History.json", safariHistoryJSON("https://short.example.com/"))
        shorter.declaredSize = safariHistoryJSON("https://short.example.com/").utf8.count + 5
        #expect(workspace.failure(safariMakeZip([shorter])) == SafariMessages.damaged)
    }

    @Test func deflatedDataLongerThanItsDeclaredSizeIsRefusedAsDamaged() {
        var longer = SafariZipEntry("History.json", safariHistoryJSON("https://long.example.com/"))
        longer.declaredSize = safariHistoryJSON("https://long.example.com/").utf8.count - 5
        #expect(workspace.failure(safariMakeZip([longer])) == SafariMessages.damaged)
    }

    @Test func deflatedDataLongerThanDeclaredIsRefusedEvenWhenTheCRCMatchesTheDeclaredPrefix() {
        var longer = SafariZipEntry("Passwords.csv", safariPasswordsCSV)
        longer.declaredSize = safariPasswordsCSV.utf8.count - 1
        longer.crc = safariCRC32(Data(safariPasswordsCSV.utf8).prefix(safariPasswordsCSV.utf8.count - 1))
        #expect(workspace.failure(safariMakeZip([longer])) == SafariMessages.damaged)
    }

    @Test func entriesThatShareTheSameStoredDataAreRefusedAsDamaged() {
        let overlapping = safariMakeZip([SafariZipEntry("History.json", safariDefaultHistory, deflate: false),
                                         SafariZipEntry("History - Work.json", safariDefaultHistory, deflate: false)],
                                        sharingData: true)
        #expect(workspace.failure(overlapping) == SafariMessages.damaged)
    }

    @Test func aZip64EntryClaimingAnOffsetAtTheEndOfTheRangeIsRefusedNotACrash() {
        var farAway = SafariZipEntry("History.json", safariDefaultHistory)
        farAway.claimedOffset = UInt64.max
        #expect(workspace.failure(safariMakeZip([farAway], zip64: true)) == SafariMessages.damaged)
    }

    @Test func aPasswordsFileOver32MiBIsRefusedAsTooLarge() {
        let oversized = String(repeating: "a", count: 33_554_433)
        #expect(workspace.failure(safariMakeZip([SafariZipEntry("Passwords.csv", oversized)])) == SafariMessages.tooLarge)
    }

    @Test func unsafeHiddenAndResourceForkEntriesAreIgnoredEntirely() {
        #expect(workspace.failure(safariMakeZip(workspace.traversal)) == SafariMessages.notExport)
    }

    @Test func anExportWhoseBookmarksExceedTheLimitsIsRefusedAsTooLarge() {
        let tooDeep = safariMakeZip([SafariZipEntry("Bookmarks.html", safariNested(128, leaf: true))])
        #expect(workspace.failure(tooDeep) == SafariMessages.tooLarge)
    }

    @Test func failedImportsLeaveNoUnpackedFoldersOrPasswordsBehind() throws {
        _ = workspace.failure(safariMakeZip([SafariZipEntry("Extensions.json", safariTypedJSON("extensions"))]))
        _ = workspace.failure(safariMakeZip(workspace.traversal))
        _ = workspace.failure(safariMakeZip([SafariZipEntry("Bookmarks.html", safariNested(128, leaf: true))]))
        var shortStored = SafariZipEntry("Passwords.csv", safariPasswordsCSV, deflate: false)
        shortStored.declaredSize = safariPasswordsCSV.utf8.count + 3
        _ = workspace.failure(safariMakeZip([shortStored]))
        let export = try workspace.open([SafariZipEntry("History.json", safariDefaultHistory)])
        export.remove()
        #expect(workspace.leftovers().isEmpty)
    }
}

struct SafariBookmarksHTMLTests {
    @Test func theSampleKeepsFoldersTheEmptyReadingListAndTheTopLevelLeaf() throws {
        let sample = try SafariBookmarksHTML.parse(Data(safariSampleBookmarks.utf8))
        #expect(sample == [
            BrowserImportBookmark(id: "safari-export/0", title: "Favorites", url: nil, children: [
                BrowserImportBookmark(id: "safari-export/0.0", title: "Example", url: "https://www.example.com/", children: []),
            ]),
            BrowserImportBookmark(id: "safari-export/1", title: "Reading List", url: nil, children: []),
            BrowserImportBookmark(id: "safari-export/2", title: "Guide", url: "https://support.example.com/guide/", children: []),
        ])
        #expect((try? BrowserImportSelection(roots: sample)) != nil)
    }

    func rich() throws -> [BrowserImportBookmark] { try SafariBookmarksHTML.parse(Data(safariRichBookmarks.utf8)) }

    @Test func topLevelFoldersAndLeavesKeepTheirOrderAndDecodedTitles() throws {
        let rich = try rich()
        #expect(rich.map(\.title) == ["Favorites & Friends", "Reading List", "Guide", "Unclosed"])
        #expect(rich.map(\.id) == ["safari-export/0", "safari-export/1", "safari-export/2", "safari-export/3"])
    }

    @Test func entitiesAreDecodedUnknownOnesKeptAndLinksWithoutAUsableAddressSkipped() throws {
        let favorites = try rich()[0].children
        #expect(favorites.map(\.title) == [#"Tom & Jerry <3 "quoted" 'single' café café &unknown; a&b"#, "lower case", "Nested", "Empty Inner", "After Empty"])
        #expect(favorites.map(\.id) == ["safari-export/0.0", "safari-export/0.1", "safari-export/0.2", "safari-export/0.3", "safari-export/0.4"])
    }

    @Test func addressesAreDecodedAndQuotedGreaterThanSignsDontEndATag() throws {
        #expect(try rich()[0].children[0].url == "https://www.example.com/?a=1&b=2")
    }

    @Test func singleQuotedLowercaseTagsAreRead() throws {
        #expect(try rich()[0].children[1].url == "https://example.org/single")
    }

    @Test func mixedCaseFolderTagsNestTheirBookmarks() throws {
        #expect(try rich()[0].children[2].children
                == [BrowserImportBookmark(id: "safari-export/0.2.0", title: "Deep", url: "https://nested.example.net/", children: [])])
    }

    @Test func aFolderWithoutItsOwnListIsKeptEmpty() throws {
        let folder = try rich()[0].children[3]
        #expect(folder.url == nil && folder.children.isEmpty)
    }

    @Test func theEmptyReadingListStaysAnOrdinaryEmptyFolder() throws {
        let readingList = try rich()[1]
        #expect(readingList.url == nil && readingList.children.isEmpty)
    }

    @Test func aListMissingItsFinalCloseStillKeepsItsBookmarks() throws {
        #expect(try rich()[3].children.map(\.url) == ["https://unclosed.example.com/"])
    }

    @Test func bookmarksInsideCommentsAreIgnored() throws {
        #expect(!(try rich()).contains { $0.title == "hidden" })
    }

    @Test func parsingTheSameFileTwiceGivesTheSameIDs() throws {
        #expect((try? SafariBookmarksHTML.parse(Data(safariRichBookmarks.utf8))) == (try rich()))
    }

    @Test func aWrappingTopLevelListAndStrayClosingTagsDontAddOrCloseFolders() throws {
        let netscape = try SafariBookmarksHTML.parse(Data("<H1>Bookmarks</H1>\n<DL><p>\n<DT><H3>Bar</H3>\n<DL><p>\n<DT><A HREF=\"https://bar.example.com/\">Bar Link</A>\n</DL><p>\n<DT><A HREF=\"https://top.example.com/\">Top</A>\n</DL><p>\n</DL></DL>".utf8))
        #expect(netscape.map(\.title) == ["Bar", "Top"] && netscape[0].children.map(\.title) == ["Bar Link"])
    }

    @Test func aBookmarksFileThatIsntUTF8IsReadAsLatin1() {
        var latin = Data("<DT><A HREF=\"https://latin.example.com/\">Caf".utf8)
        latin.append(0xE9)
        latin.append(contentsOf: Array("</A>".utf8))
        #expect((try? SafariBookmarksHTML.parse(latin))?.map(\.title) == ["Café"])
    }

    @Test func aBookmarkOnThe128thLevelIsAccepted() throws {
        let deepest = try SafariBookmarksHTML.parse(safariNested(127, leaf: true))
        #expect((try? BrowserImportSelection(roots: deepest)) != nil)
    }

    @Test func aFolderOnThe128thLevelIsAccepted() throws {
        let deepest = try SafariBookmarksHTML.parse(safariNested(128, leaf: false))
        #expect((try? BrowserImportSelection(roots: deepest)) != nil)
    }

    @Test func bookmarksNestedDeeperThan128LevelsAreRefused() {
        #expect((try? SafariBookmarksHTML.parse(safariNested(128, leaf: true))) == nil)
    }

    @Test func foldersNestedDeeperThan128LevelsAreRefused() {
        #expect((try? SafariBookmarksHTML.parse(safariNested(129, leaf: false))) == nil)
    }

    @Test func exactly50000BookmarksAreAccepted() throws {
        let links = String(repeating: "<DT><A HREF=\"https://many.example.com/\">Many</A>\n", count: 50_000)
        let many = try SafariBookmarksHTML.parse(Data(links.utf8))
        #expect(many.count == 50_000 && (try? BrowserImportSelection(roots: many)) != nil)
    }

    @Test func moreThan50000BookmarksAreRefused() {
        let links = String(repeating: "<DT><A HREF=\"https://many.example.com/\">Many</A>\n", count: 50_000)
        #expect((try? SafariBookmarksHTML.parse(Data((links + "<DT><H3>One More</H3>").utf8))) == nil)
    }

    @Test func arcInternalAddressesAreSkippedSinceParcsSidebarCantOpenThem() throws {
        let arcLink = try SafariBookmarksHTML.parse(Data("<DT><A HREF=\"arc://space/1\">Arc</A>\n<DT><A HREF=\"https://kept.example.com/\">Kept</A>".utf8))
        #expect(arcLink.count == 1 && arcLink[0].url == "https://kept.example.com/")
    }
}
