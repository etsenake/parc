import Compression
import Foundation

private struct FixtureEntry {
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

private struct FixtureWriter {
    var bytes: [UInt8] = []

    mutating func u16(_ value: UInt16) { append(value) }
    mutating func u32(_ value: UInt32) { append(value) }
    mutating func u64(_ value: UInt64) { append(value) }

    private mutating func append<T: FixedWidthInteger>(_ value: T) {
        for index in 0..<MemoryLayout<T>.size { bytes.append(UInt8(truncatingIfNeeded: value >> (8 * index))) }
    }
}

private let crcTable: [UInt32] = (0..<256).map { seed in
    var value = UInt32(seed)
    for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
    return value
}

private func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    return crc ^ 0xFFFF_FFFF
}

private func rawDeflate(_ data: Data) -> Data {
    let capacity = data.count + 4096
    var output = Data(count: capacity)
    let written = output.withUnsafeMutableBytes { target in
        data.withUnsafeBytes { source in
            compression_encode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                      source.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_ZLIB)
        }
    }
    precondition(written > 0, "The fixture writer can deflate its own test data.")
    output.count = written
    return output
}

private func makeZip(_ entries: [FixtureEntry], zip64: Bool = false, sharingData: Bool = false) -> Data {
    var archive = FixtureWriter()
    var central = FixtureWriter()
    var firstOffset: UInt64 = 0
    for (index, entry) in entries.enumerated() {
        let payload = entry.deflate ? rawDeflate(entry.data) : entry.data
        let method = entry.method ?? (entry.deflate ? 8 : 0)
        let crc = entry.crc ?? crc32(entry.data)
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

private func historyJSON(_ address: String, title: String = "Example", padding: Int = 0, metadataLast: Bool = false) -> String {
    let metadata = #""metadata":{"browser_name":"Safari","browser_version":"18.4","data_type" : "history","export_time_usec":1700000000000000,"schema_version":1}"#
    let filler = String(repeating: " ", count: padding)
    let history = #""history":[{"url":"\#(address)","title":"\#(title)","time_usec":1699999999000000,"visit_count":2}]"#
    return metadataLast ? "{\(history),\(filler)\(metadata)}" : "{\(metadata),\(filler)\(history)}"
}

private func corruptJSON() -> FixtureEntry {
    var entry = FixtureEntry("Notes.json", #"{"metadata":{"data_type":"notes"}}"#)
    entry.crc = 0x0BAD_F00D
    return entry
}

private func typedJSON(_ type: String) -> String {
    #"{"metadata":{"browser_name":"Safari","browser_version":"18.4","data_type":"\#(type)","export_time_usec":1700000000000000,"schema_version":1},"\#(type)":[]}"#
}

private let sampleBookmarks = """
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

private let richBookmarks = """
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

private func nested(_ folders: Int, leaf: Bool) -> Data {
    var text = "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n"
    for index in 0..<folders { text += "<DT><H3>Level \(index)</H3>\n<DL><p>\n" }
    if leaf { text += "<DT><A HREF=\"https://deep.example.com/\">Deep</A>\n" }
    for _ in 0..<folders { text += "</DL><p>\n" }
    return Data(text.utf8)
}

@main struct SafariBrowsingExportTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        let manager = FileManager.default
        let workspace = manager.temporaryDirectory.appendingPathComponent("SafariBrowsingExportTests-" + UUID().uuidString)
        let root = workspace.appendingPathComponent("root", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: workspace) }
        let notExport = "This file doesn’t contain Safari history, bookmarks, passwords or payment cards. Choose the .zip file Safari’s File → Export Browsing Data to File saves."
        let tooLarge = "Part of this Safari export is too large to import."
        let damaged = "This Safari export file is damaged or uses a format Parc can’t read."
        var archiveNumber = 0
        func save(_ data: Data) throws -> URL {
            archiveNumber += 1
            let url = workspace.appendingPathComponent("archive-\(archiveNumber).zip")
            try data.write(to: url)
            return url
        }
        func open(_ entries: [FixtureEntry], zip64: Bool = false) throws -> SafariBrowsingExport {
            try SafariBrowsingExport.open(try save(makeZip(entries, zip64: zip64)), temporaryRoot: root)
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

        let defaultHistory = historyJSON("https://default.example.com/")
        let workHistory = historyJSON("https://work.example.com/", title: #"Notes \"data_type\":\"extensions\""#, metadataLast: true)
        let localized = try open([
            FixtureEntry("Verlauf - Arbeit.json", workHistory),
            FixtureEntry("Erweiterungen - Arbeit.json", typedJSON("extensions")),
            FixtureEntry("Verlauf - Köder.json", typedJSON("payment_cards"), deflate: false),
            FixtureEntry("Verlauf.json", defaultHistory, deflate: false),
            FixtureEntry("Lesezeichen.html", sampleBookmarks),
        ])
        expect(localized.profiles.map(\.name) == [nil, "Arbeit"],
               "History files are recognised by their data type, and the unsuffixed default profile comes first.")
        expect(localized.profiles.map(\.directory) == [0, 1].map { localized.directory.appendingPathComponent("profile-\($0)", isDirectory: true) },
               "Each profile's history is written to its own numbered folder.")
        expect(contents(localized.profiles[0].directory.appendingPathComponent("History.json")) == Data(defaultHistory.utf8),
               "The default profile's history is written exactly as Safari exported it.")
        expect(contents(localized.profiles[1].directory.appendingPathComponent("History.json")) == Data(workHistory.utf8),
               "A named profile's history is written exactly as Safari exported it, even with its metadata last.")
        expect(localized.includesExtensions && localized.includesPaymentCards,
               "Extensions and payment cards are detected by their data type whatever the file is called.")
        expect(localized.passwordsFile == nil, "An export without a passwords file reports no passwords.")
        expect(localized.bookmarks.count == 3, "The localized bookmarks file is read by its extension.")
        expect(localized.directory.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
               && localized.directory.lastPathComponent.hasPrefix("ParcSafariExport-"),
               "The export is unpacked into a fresh folder inside the requested temporary root.")
        expect(permissions(localized.directory) == 0o700 && permissions(localized.profiles[0].directory) == 0o700,
               "Unpacked folders are private to the current user.")
        expect(permissions(localized.profiles[1].directory.appendingPathComponent("History.json")) == 0o600,
               "Unpacked history files are private to the current user.")
        let unpacked = (manager.enumerator(atPath: localized.directory.path)?.allObjects as? [String] ?? []).sorted()
        expect(unpacked == ["profile-0", "profile-0/History.json", "profile-0/PaymentCards.json", "profile-1", "profile-1/History.json"],
               "Only history and payment cards are written to disk; bookmarks and extensions are never unpacked.")
        expect(localized.paymentCardsFile == localized.profiles[0].directory.appendingPathComponent("PaymentCards.json")
               && localized.paymentCardsFile.flatMap(contents) == Data(typedJSON("payment_cards").utf8),
               "Payment cards, found by their data type whatever the file is called, go beside the default profile's history exactly as exported.")
        expect(localized.paymentCardsFile.flatMap(permissions) == 0o600, "The unpacked payment cards are private to the current user.")
        localized.removePaymentCards()
        expect(!manager.fileExists(atPath: localized.profiles[0].directory.appendingPathComponent("PaymentCards.json").path)
               && manager.fileExists(atPath: localized.profiles[0].directory.appendingPathComponent("History.json").path),
               "Removing the payment cards deletes only their file.")
        localized.removePaymentCards()
        localized.remove()
        expect(!manager.fileExists(atPath: localized.directory.path), "Removing the export deletes its whole folder.")

        let suffixed = try open([
            FixtureEntry("History - Personal.json", historyJSON("https://personal.example.com/")),
            FixtureEntry("History - Work.json", historyJSON("https://work.example.com/")),
            {
                var entry = FixtureEntry("History.json", historyJSON("https://latin.example.com/"))
                entry.name = Array("History - Pers".utf8) + [0xF6] + Array("nlich.json".utf8)
                return entry
            }(),
            {
                var entry = FixtureEntry("History - Café.json", historyJSON("https://cafe.example.com/"))
                entry.unicodeFlag = false
                return entry
            }(),
        ])
        expect(suffixed.profiles.map(\.name) == ["Personal", "Work", "Persönlich", "Café"],
               "When every history file has a suffix, each profile is named by its suffix in archive order, decoding unflagged names as UTF-8 or Latin-1.")
        expect(contents(suffixed.profiles[1].directory.appendingPathComponent("History.json")) == Data(historyJSON("https://work.example.com/").utf8),
               "Suffixed profiles keep the history that belongs to them.")
        suffixed.remove()

        let single = try open([FixtureEntry("History - Work.json", historyJSON("https://work.example.com/"))])
        expect(single.profiles.map(\.name) == ["Work"], "A single suffixed history file names its profile.")
        expect(single.bookmarks.isEmpty && single.passwordsFile == nil && single.paymentCardsFile == nil
               && !single.includesExtensions && !single.includesPaymentCards,
               "A history-only export reports nothing else.")
        single.remove()

        let plain = try open([FixtureEntry("History.json", historyJSON("https://plain.example.com/"))])
        expect(plain.profiles.map(\.name) == [nil], "A single unsuffixed history file is the default profile.")
        plain.remove()

        let passwordsCSV = "Title,URL,Username,Password,Notes,OTPAuth\nExample,https://example.com/,someone,made-up-secret,,\n"
        let folder = try open([
            FixtureEntry("Safari Export/", Data(), deflate: false),
            FixtureEntry("Safari Export/A/History - Work.json", historyJSON("https://first.example.com/")),
            FixtureEntry("Safari Export/B/History - Work.json", historyJSON("https://second.example.com/")),
            FixtureEntry("Safari Export/Bookmarks.html", sampleBookmarks, deflate: false),
            FixtureEntry("Safari Export/Passwords.csv", passwordsCSV),
            FixtureEntry("Safari Export/Other Passwords.csv", "Title,URL\n"),
            FixtureEntry("Safari Export/Other.html", "<DT><A HREF=\"https://other.example.com/\">Other</A>"),
        ])
        expect(folder.profiles.map(\.name) == ["Work", "Work"], "Exactly duplicate profile names are both kept in archive order.")
        expect(contents(folder.profiles[1].directory.appendingPathComponent("History.json")) == Data(historyJSON("https://second.example.com/").utf8),
               "Files inside a top-level folder are read by their last path component.")
        expect(folder.bookmarks == (try? SafariBookmarksHTML.parse(Data(sampleBookmarks.utf8))),
               "The first bookmarks file in archive order is parsed in memory.")
        expect(folder.passwordsFile == folder.directory.appendingPathComponent("passwords/Passwords.csv"),
               "Passwords are unpacked into their own folder.")
        expect(folder.passwordsFile.flatMap(contents) == Data(passwordsCSV.utf8),
               "The first passwords file in archive order is unpacked exactly.")
        expect(permissions(folder.directory.appendingPathComponent("passwords")) == 0o700,
               "The passwords folder is private to the current user.")
        expect(folder.passwordsFile.flatMap(permissions) == 0o600, "The passwords file is private to the current user.")
        folder.removePasswords()
        expect(!manager.fileExists(atPath: folder.directory.appendingPathComponent("passwords").path)
               && manager.fileExists(atPath: folder.profiles[0].directory.appendingPathComponent("History.json").path),
               "Removing passwords deletes only the passwords folder.")
        folder.removePasswords()
        folder.remove()
        expect(!manager.fileExists(atPath: folder.directory.path), "Removing the export after its passwords deletes the rest.")

        let extras = try open([
            FixtureEntry("PaymentCards.json", typedJSON("payment_cards")),
            FixtureEntry("Extensions.json", typedJSON("extensions")),
            FixtureEntry("Notes.json", #"{"metadata":{"browser_name":"Safari"}}"#),
            FixtureEntry("Bookmarks.html", sampleBookmarks),
        ])
        expect(extras.includesPaymentCards && extras.includesExtensions && extras.profiles.map(\.name) == [nil],
               "Without any history, payment cards get a default profile folder of their own.")
        expect((manager.enumerator(atPath: extras.directory.path)?.allObjects as? [String] ?? []).sorted()
               == ["profile-0", "profile-0/PaymentCards.json"]
               && extras.paymentCardsFile == extras.profiles[0].directory.appendingPathComponent("PaymentCards.json"),
               "Only the payment cards are written; extensions never are.")
        extras.remove()

        let cardsOnly = try open([FixtureEntry("PaymentCards.json", typedJSON("payment_cards"), deflate: false),
                                  FixtureEntry("Extensions.json", typedJSON("extensions"))])
        expect(cardsOnly.profiles.count == 1 && cardsOnly.paymentCardsFile != nil && cardsOnly.bookmarks.isEmpty
               && cardsOnly.passwordsFile == nil, "An export with only payment cards and extensions imports its payment cards.")
        cardsOnly.remove()
        expect(failure(makeZip([FixtureEntry("Extensions.json", typedJSON("extensions"))])) == notExport,
               "An export with only extensions is not importable.")
        let bulkyCards = #"{"metadata":{"data_type":"payment_cards"},"payment_cards":[],"padding":""# + String(repeating: "a", count: 16 << 20) + #""}"#
        expect(failure(makeZip([FixtureEntry("PaymentCards.json", bulkyCards)])) == tooLarge,
               "A payment cards file over 16 MiB is refused as too large.")
        expect(failure(Data("This is a plain text note, not an archive.".utf8)) == notExport, "A file that isn't a ZIP is refused as not a Safari export.")
        expect(failure(Data()) == notExport, "An empty file is refused as not a Safari export.")
        expect(failure(makeZip([])) == notExport, "An empty ZIP is refused as not a Safari export.")

        let zip64 = try open([
            FixtureEntry("History.json", historyJSON("https://zip64.example.com/")),
            FixtureEntry("Bookmarks.html", sampleBookmarks, deflate: false),
        ], zip64: true)
        expect(zip64.profiles.map(\.name) == [nil]
               && contents(zip64.profiles[0].directory.appendingPathComponent("History.json")) == Data(historyJSON("https://zip64.example.com/").utf8),
               "ZIP64 archives with 64-bit central directory fields are read.")
        expect(zip64.bookmarks.count == 3, "ZIP64 archives' bookmarks are read.")
        zip64.remove()

        var described = FixtureEntry("History.json", historyJSON("https://descriptor.example.com/"))
        described.descriptor = true
        var describedPasswords = FixtureEntry("Passwords.csv", passwordsCSV, deflate: false)
        describedPasswords.descriptor = true
        let descriptor = try open([described, describedPasswords])
        expect(contents(descriptor.profiles[0].directory.appendingPathComponent("History.json")) == Data(historyJSON("https://descriptor.example.com/").utf8)
               && descriptor.passwordsFile.flatMap(contents) == Data(passwordsCSV.utf8),
               "Entries written with data descriptors are read using the central directory sizes.")
        descriptor.remove()

        let largeHistory = historyJSON("https://large.example.com/", padding: 100_000, metadataLast: true)
        let large = try open([FixtureEntry("History.json", largeHistory)])
        expect(contents(large.profiles[0].directory.appendingPathComponent("History.json")) == Data(largeHistory.utf8),
               "A large history file whose metadata comes after the first 64 KiB is still recognised and written exactly.")
        large.remove()
        let leadingHistory = historyJSON("https://leading.example.com/", padding: 100_000)
        let leading = try open([FixtureEntry("History.json", leadingHistory)])
        expect(contents(leading.profiles[0].directory.appendingPathComponent("History.json")) == Data(leadingHistory.utf8),
               "A large history file recognised from its first bytes is written exactly.")
        leading.remove()

        var encrypted = FixtureEntry("History.json", historyJSON("https://secret.example.com/"))
        encrypted.flags = 0x0001
        expect(failure(makeZip([encrypted])) == damaged, "An encrypted entry is refused as damaged or unsupported.")
        var unsupported = FixtureEntry("Bookmarks.html", sampleBookmarks)
        unsupported.method = 12
        expect(failure(makeZip([unsupported])) == damaged, "An entry using an unsupported compression method is refused.")
        var ignoredMethod = FixtureEntry("Notes.txt", "made-up notes")
        ignoredMethod.method = 12
        let ignored = try open([ignoredMethod, FixtureEntry("Bookmarks.html", sampleBookmarks)])
        expect(ignored.bookmarks.count == 3, "Entries Parc doesn't use are never decompressed, whatever their method.")
        ignored.remove()
        var corrupt = FixtureEntry("Bookmarks.html", sampleBookmarks)
        corrupt.crc = 0x1234_5678
        expect(failure(makeZip([corrupt])) == damaged, "A CRC mismatch is refused as damaged.")
        var shortStored = FixtureEntry("Passwords.csv", passwordsCSV, deflate: false)
        shortStored.declaredSize = passwordsCSV.utf8.count + 3
        expect(failure(makeZip([shortStored])) == damaged, "A stored entry whose sizes disagree is refused as damaged.")
        var shorter = FixtureEntry("History.json", historyJSON("https://short.example.com/"))
        shorter.declaredSize = historyJSON("https://short.example.com/").utf8.count + 5
        expect(failure(makeZip([shorter])) == damaged, "Deflated data shorter than its declared size is refused as damaged.")
        var longer = FixtureEntry("History.json", historyJSON("https://long.example.com/"))
        longer.declaredSize = historyJSON("https://long.example.com/").utf8.count - 5
        expect(failure(makeZip([longer])) == damaged, "Deflated data longer than its declared size is refused as damaged.")
        var longerPasswords = FixtureEntry("Passwords.csv", passwordsCSV)
        longerPasswords.declaredSize = passwordsCSV.utf8.count - 1
        longerPasswords.crc = crc32(Data(passwordsCSV.utf8).prefix(passwordsCSV.utf8.count - 1))
        expect(failure(makeZip([longerPasswords])) == damaged,
               "Deflated data longer than declared is refused even when the CRC matches the declared prefix.")
        var lateFailure = FixtureEntry("History - Work.json", leadingHistory)
        lateFailure.declaredSize = leadingHistory.utf8.count + 1
        let partly = try open([FixtureEntry("Passwords.csv", passwordsCSV), FixtureEntry("History.json", defaultHistory), lateFailure])
        expect(partly.profiles.count == 1 && partly.profiles[0].name == nil && partly.passwordsFile != nil && partly.skippedParts == 1,
               "A damaged history file is skipped and counted while the rest of the export still imports.")
        partly.remove()
        let unrelated = try open([FixtureEntry("History.json", defaultHistory), corruptJSON()])
        expect(unrelated.profiles.count == 1 && unrelated.skippedParts == 1,
               "A damaged JSON file that isn't needed doesn't stop the import.")
        unrelated.remove()
        let overlapping = makeZip([FixtureEntry("History.json", defaultHistory, deflate: false),
                                   FixtureEntry("History - Work.json", defaultHistory, deflate: false)], sharingData: true)
        expect(failure(overlapping) == damaged, "Entries that share the same stored data are refused as damaged.")
        var farAway = FixtureEntry("History.json", defaultHistory)
        farAway.claimedOffset = UInt64.max
        expect(failure(makeZip([farAway], zip64: true)) == damaged,
               "A ZIP64 entry claiming an offset at the very end of the 64-bit range is refused, not a crash.")
        let dashed = try open([FixtureEntry("History - Work.json", historyJSON("https://work.example.com/")),
                               FixtureEntry("History - Work - Old.json", historyJSON("https://old.example.com/"))])
        expect(dashed.profiles.map { $0.name } == ["Work", "Work - Old"],
               "Without a default history file, every profile keeps its full name, even one containing a dash.")
        dashed.remove()
        expect(leftovers().isEmpty, "Failed imports leave no unpacked folders or passwords behind.")

        let oversized = String(repeating: "a", count: 33_554_433)
        expect(failure(makeZip([FixtureEntry("Passwords.csv", oversized)])) == tooLarge,
               "A passwords file over 32 MiB is refused as too large.")
        let atLimit = try open([FixtureEntry("Passwords.csv", String(repeating: "a", count: 33_554_432))])
        expect(atLimit.passwordsFile.flatMap(contents)?.count == 33_554_432,
               "A passwords file of exactly 32 MiB, far past the old 1,000 KiB cap, is unpacked.")
        atLimit.remove()

        let traversal = [
            FixtureEntry("../History.json", historyJSON("https://escape.example.com/")),
            FixtureEntry("/tmp/History.json", historyJSON("https://absolute.example.com/")),
            FixtureEntry("Export/../History.json", historyJSON("https://inner.example.com/")),
            FixtureEntry("Export\\History.json", historyJSON("https://backslash.example.com/")),
            FixtureEntry("__MACOSX/History.json", historyJSON("https://resource.example.com/")),
            FixtureEntry("__MACOSX/Safari Export/._Bookmarks.html", sampleBookmarks),
            FixtureEntry("._History.json", historyJSON("https://appledouble.example.com/")),
            FixtureEntry(".Passwords.csv", passwordsCSV),
            FixtureEntry("Export/.hidden/../Bookmarks.html", sampleBookmarks),
        ]
        expect(failure(makeZip(traversal)) == notExport, "Unsafe, hidden and resource-fork entries are ignored entirely.")
        let mixed = try open(traversal + [FixtureEntry("Bookmarks.html", sampleBookmarks)])
        expect(mixed.profiles.isEmpty && mixed.passwordsFile == nil && mixed.bookmarks.count == 3,
               "Safe entries are still read next to ignored ones.")
        let mixedFiles = (manager.enumerator(atPath: mixed.directory.path)?.allObjects as? [String]) ?? ["unreadable"]
        expect(mixedFiles.isEmpty, "Ignored entries never reach the disk.")
        mixed.remove()
        expect(leftovers().isEmpty, "Every export folder made by these checks is removed.")

        let sample = try SafariBookmarksHTML.parse(Data(sampleBookmarks.utf8))
        expect(sample == [
            BrowserImportBookmark(id: "safari-export/0", title: "Favorites", url: nil, children: [
                BrowserImportBookmark(id: "safari-export/0.0", title: "Example", url: "https://www.example.com/", children: []),
            ]),
            BrowserImportBookmark(id: "safari-export/1", title: "Reading List", url: nil, children: []),
            BrowserImportBookmark(id: "safari-export/2", title: "Guide", url: "https://support.example.com/guide/", children: []),
        ], "Safari's sample bookmarks keep folders, the empty Reading List and the top-level leaf after folders.")
        expect((try? BrowserImportSelection(roots: sample)) != nil, "Parsed bookmarks are accepted by the import selection.")

        let rich = try SafariBookmarksHTML.parse(Data(richBookmarks.utf8))
        expect(rich.map(\.title) == ["Favorites & Friends", "Reading List", "Guide", "Unclosed"],
               "Top-level folders and leaves keep their order and decoded titles.")
        expect(rich.map(\.id) == ["safari-export/0", "safari-export/1", "safari-export/2", "safari-export/3"],
               "Top-level IDs are their positions.")
        let favorites = rich[0].children
        expect(favorites.map(\.title) == [#"Tom & Jerry <3 "quoted" 'single' café café &unknown; a&b"#, "lower case", "Nested", "Empty Inner", "After Empty"],
               "Entities are decoded, unknown entities are kept and links without a usable address are skipped.")
        expect(favorites.map(\.id) == ["safari-export/0.0", "safari-export/0.1", "safari-export/0.2", "safari-export/0.3", "safari-export/0.4"],
               "Child IDs are dotted index paths over the kept bookmarks.")
        expect(favorites[0].url == "https://www.example.com/?a=1&b=2", "Entities in addresses are decoded and quoted > signs don't end a tag.")
        expect(favorites[1].url == "https://example.org/single", "Single-quoted, lowercase tags are read.")
        expect(favorites[2].children == [BrowserImportBookmark(id: "safari-export/0.2.0", title: "Deep", url: "https://nested.example.net/", children: [])],
               "Mixed-case folder tags nest their bookmarks.")
        expect(favorites[3].url == nil && favorites[3].children.isEmpty, "A folder without its own list is kept empty.")
        expect(rich[1].url == nil && rich[1].children.isEmpty, "The empty Reading List stays an ordinary empty folder.")
        expect(rich[3].children.map(\.url) == ["https://unclosed.example.com/"], "A list missing its final </DL> still keeps its bookmarks.")
        expect(!rich.contains { $0.title == "hidden" }, "Bookmarks inside comments are ignored.")
        expect((try? SafariBookmarksHTML.parse(Data(richBookmarks.utf8))) == rich, "Parsing the same file twice gives the same IDs.")

        let netscape = try SafariBookmarksHTML.parse(Data("<H1>Bookmarks</H1>\n<DL><p>\n<DT><H3>Bar</H3>\n<DL><p>\n<DT><A HREF=\"https://bar.example.com/\">Bar Link</A>\n</DL><p>\n<DT><A HREF=\"https://top.example.com/\">Top</A>\n</DL><p>\n</DL></DL>".utf8))
        expect(netscape.map(\.title) == ["Bar", "Top"] && netscape[0].children.map(\.title) == ["Bar Link"],
               "A wrapping top-level list and stray closing tags don't add or close folders.")

        var latin = Data("<DT><A HREF=\"https://latin.example.com/\">Caf".utf8)
        latin.append(0xE9)
        latin.append(contentsOf: Array("</A>".utf8))
        expect((try? SafariBookmarksHTML.parse(latin))?.map(\.title) == ["Café"], "A bookmarks file that isn't UTF-8 is read as Latin-1.")

        let deepest = try SafariBookmarksHTML.parse(nested(127, leaf: true))
        expect((try? BrowserImportSelection(roots: deepest)) != nil, "A bookmark on the 128th level is accepted by the parser and the import selection.")
        let deepestFolder = try SafariBookmarksHTML.parse(nested(128, leaf: false))
        expect((try? BrowserImportSelection(roots: deepestFolder)) != nil, "A folder on the 128th level is accepted by the parser and the import selection.")
        expect((try? SafariBookmarksHTML.parse(nested(128, leaf: true))) == nil, "Bookmarks nested deeper than 128 levels are refused.")
        expect((try? SafariBookmarksHTML.parse(nested(129, leaf: false))) == nil, "Folders nested deeper than 128 levels are refused.")
        let manyLinks = String(repeating: "<DT><A HREF=\"https://many.example.com/\">Many</A>\n", count: 50_000)
        let many = try SafariBookmarksHTML.parse(Data(manyLinks.utf8))
        expect(many.count == 50_000 && (try? BrowserImportSelection(roots: many)) != nil, "Exactly 50,000 bookmarks are accepted.")
        expect((try? SafariBookmarksHTML.parse(Data((manyLinks + "<DT><H3>One More</H3>").utf8))) == nil, "More than 50,000 bookmarks are refused.")
        let arcLink = try SafariBookmarksHTML.parse(Data("<DT><A HREF=\"arc://space/1\">Arc</A>\n<DT><A HREF=\"https://kept.example.com/\">Kept</A>".utf8))
        expect(arcLink.count == 1 && arcLink[0].url == "https://kept.example.com/",
               "Arc-internal addresses are skipped, since Parc's sidebar can't open them.")
        let tooDeep = makeZip([FixtureEntry("Bookmarks.html", nested(128, leaf: true))])
        expect(failure(tooDeep) == tooLarge, "An export whose bookmarks exceed the limits is refused as too large.")
        expect(leftovers().isEmpty, "Refused exports leave nothing behind.")

        print("\(checks) Safari browsing-export ZIP and bookmarks assertions passed; made-up fixtures only.")
    }
}
