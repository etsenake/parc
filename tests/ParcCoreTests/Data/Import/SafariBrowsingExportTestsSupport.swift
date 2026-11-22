import Compression
import Foundation
import Testing
@testable import ParcCore

enum SafariBrowsingExportTestsSupport {
    struct SafariZipEntry {
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

    struct SafariZipWriter {
        var bytes: [UInt8] = []

        mutating func u16(_ value: UInt16) { append(value) }
        mutating func u32(_ value: UInt32) { append(value) }
        mutating func u64(_ value: UInt64) { append(value) }

        private mutating func append<T: FixedWidthInteger>(_ value: T) {
            for index in 0..<MemoryLayout<T>.size { bytes.append(UInt8(truncatingIfNeeded: value >> (8 * index))) }
        }
    }

    static let safariCRCTable: [UInt32] = (0..<256).map { seed in
        var value = UInt32(seed)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func safariCRC32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = safariCRCTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    static func safariRawDeflate(_ data: Data) -> Data {
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

    static func safariMakeZip(_ entries: [SafariZipEntry], zip64: Bool = false, sharingData: Bool = false) -> Data {
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

    static func safariHistoryJSON(_ address: String, title: String = "Example", padding: Int = 0, metadataLast: Bool = false) -> String {
        let metadata = #""metadata":{"browser_name":"Safari","browser_version":"18.4","data_type" : "history","export_time_usec":1700000000000000,"schema_version":1}"#
        let filler = String(repeating: " ", count: padding)
        let history = #""history":[{"url":"\#(address)","title":"\#(title)","time_usec":1699999999000000,"visit_count":2}]"#
        return metadataLast ? "{\(history),\(filler)\(metadata)}" : "{\(metadata),\(filler)\(history)}"
    }

    static func safariCorruptJSON() -> SafariZipEntry {
        var entry = SafariZipEntry("Notes.json", #"{"metadata":{"data_type":"notes"}}"#)
        entry.crc = 0x0BAD_F00D
        return entry
    }

    static func safariTypedJSON(_ type: String) -> String {
        #"{"metadata":{"browser_name":"Safari","browser_version":"18.4","data_type":"\#(type)","export_time_usec":1700000000000000,"schema_version":1},"\#(type)":[]}"#
    }

    static let safariSampleBookmarks = """
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

    static let safariRichBookmarks = """
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

    static func safariNested(_ folders: Int, leaf: Bool) -> Data {
        var text = "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n"
        for index in 0..<folders { text += "<DT><H3>Level \(index)</H3>\n<DL><p>\n" }
        if leaf { text += "<DT><A HREF=\"https://deep.example.com/\">Deep</A>\n" }
        for _ in 0..<folders { text += "</DL><p>\n" }
        return Data(text.utf8)
    }
    static let safariPasswordsCSV = "Title,URL,Username,Password,Notes,OTPAuth\nExample,https://example.com/,someone,made-up-secret,,\n"
    static let safariDefaultHistory = safariHistoryJSON("https://default.example.com/")
    static let safariWorkHistory = safariHistoryJSON("https://work.example.com/", title: #"Notes \"data_type\":\"extensions\""#, metadataLast: true)

    enum SafariMessages {
        static let notExport = "This file doesn’t contain Safari history, bookmarks, passwords or payment cards. Choose the .zip file Safari’s File → Export Browsing Data to File saves."
        static let tooLarge = "Part of this Safari export is too large to import."
        static let damaged = "This Safari export file is damaged or uses a format Parc can’t read."
    }

    final class SafariWorkspace {
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
}
