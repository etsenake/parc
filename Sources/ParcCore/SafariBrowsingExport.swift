import Compression
import Foundation

struct SafariBrowsingExport {
    struct Profile: Equatable {
        let name: String?
        let directory: URL
    }

    let directory: URL
    let profiles: [Profile]
    let bookmarks: [BrowserImportBookmark]
    let passwordsFile: URL?
    let includesPaymentCards: Bool
    let includesExtensions: Bool
    let skippedParts: Int

    static func open(_ archive: URL, temporaryRoot: URL = FileManager.default.temporaryDirectory) throws -> SafariBrowsingExport {
        let zip = try SafariExportZip(contentsOf: archive)
        var histories: [(stem: String, entry: SafariExportZip.Entry, data: Data?)] = []
        var bookmarksEntry: SafariExportZip.Entry?
        var passwordsEntry: SafariExportZip.Entry?
        var paymentCards = false, extensions = false, skipped = 0, oversized = false
        func attempt<T>(_ body: () throws -> T) -> T? {
            do { return try body() } catch {
                if (error as? CocoaError)?.code == .fileReadTooLarge { oversized = true }
                return nil
            }
        }
        for entry in zip.entries {
            let lowered = entry.name.lowercased()
            if lowered.hasSuffix(".html") {
                if bookmarksEntry == nil { bookmarksEntry = entry }
            } else if lowered.hasSuffix(".csv") {
                if passwordsEntry == nil { passwordsEntry = entry }
            } else if lowered.hasSuffix(".json") {
                guard let classified = attempt({ try zip.classify(entry) }) else { skipped += 1; continue }
                switch classified.type {
                case "history":
                    guard entry.uncompressedSize <= SafariExportZip.historyLimit,
                          histories.count < SafariExportZip.profileLimit else { skipped += 1; oversized = true; continue }
                    histories.append((String(entry.name.dropLast(5)), entry, classified.data))
                case "extensions": extensions = true
                case "payment_cards": paymentCards = true
                default: break
                }
            }
        }
        guard !histories.isEmpty || bookmarksEntry != nil || passwordsEntry != nil else {
            throw skipped == 0 ? SafariExportFailure.notExport : oversized ? SafariExportFailure.tooLarge : SafariExportFailure.damaged
        }
        var bookmarks: [BrowserImportBookmark] = []
        if let entry = bookmarksEntry {
            if entry.uncompressedSize > SafariExportZip.bookmarksLimit {
                skipped += 1; oversized = true
            } else if let html = attempt({ try zip.contents(of: entry) }) {
                if let parsed = try? SafariBookmarksHTML.parse(html) { bookmarks = parsed } else { skipped += 1; oversized = true }
            } else { skipped += 1 }
        }
        var passwords: Data?
        if let entry = passwordsEntry {
            if entry.uncompressedSize > SafariExportZip.passwordsLimit {
                skipped += 1; oversized = true
            } else if let data = attempt({ try zip.contents(of: entry) }) { passwords = data } else { skipped += 1 }
        }
        let directory = temporaryRoot.appendingPathComponent("ParcSafariExport-" + UUID().uuidString, isDirectory: true)
        try makeDirectory(directory)
        do {
            var passwordsFile: URL?
            if let passwords {
                let folder = directory.appendingPathComponent("passwords", isDirectory: true)
                try makeDirectory(folder)
                let file = folder.appendingPathComponent("Passwords.csv")
                try write(passwords, to: file)
                passwordsFile = file
            }
            var profiles: [Profile] = []
            for item in profileOrder(histories.map(\.stem)) {
                let history = histories[item.index]
                guard let contents = history.data ?? attempt({ try zip.contents(of: history.entry) }) else { skipped += 1; continue }
                let folder = directory.appendingPathComponent("profile-\(profiles.count)", isDirectory: true)
                try makeDirectory(folder)
                try write(contents, to: folder.appendingPathComponent("History.json"))
                profiles.append(Profile(name: item.name, directory: folder))
            }
            guard !profiles.isEmpty || !bookmarks.isEmpty || passwordsFile != nil else {
                throw oversized ? SafariExportFailure.tooLarge : SafariExportFailure.damaged
            }
            return SafariBrowsingExport(directory: directory, profiles: profiles, bookmarks: bookmarks,
                                        passwordsFile: passwordsFile, includesPaymentCards: paymentCards,
                                        includesExtensions: extensions, skippedParts: skipped)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func removePasswords() {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("passwords", isDirectory: true))
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func profileOrder(_ stems: [String]) -> [(index: Int, name: String?)] {
        func named(_ text: Substring) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if stems.count > 1, let base = stems.indices.min(by: { stems[$0].count < stems[$1].count }),
           !stems[base].contains(" - ") {
            let prefix = stems[base] + " - "
            if stems.indices.allSatisfy({ $0 == base || stems[$0].hasPrefix(prefix) }) {
                let length = prefix.count
                return [(base, nil)] + stems.indices.filter { $0 != base }.map { ($0, named(stems[$0].dropFirst(length))) }
            }
        }
        return stems.indices.map { index in
            guard let separator = stems[index].range(of: " - ") else { return (index, nil) }
            return (index, named(stems[index][separator.upperBound...]))
        }
    }

    private static func makeDirectory(_ url: URL) throws {
        let failure = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return EINVAL }
            guard mkdir(path, 0o700) == 0 else { return errno }
            guard chmod(path, 0o700) == 0 else { let code = errno; rmdir(path); return code }
            return 0
        }
        guard failure == 0 else { throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO) }
    }

    private static func write(_ data: Data, to url: URL) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        }
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        guard fchmod(descriptor, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(descriptor, raw.baseAddress! + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                offset += written
            }
        }
    }
}

private enum SafariExportFailure {
    static var notExport: CocoaError {
        CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey:
            "This file doesn’t contain Safari history, bookmarks or passwords. Choose the .zip file Safari’s File → Export Browsing Data to File saves."])
    }

    static var tooLarge: CocoaError {
        CocoaError(.fileReadTooLarge, userInfo: [NSLocalizedDescriptionKey: "Part of this Safari export is too large to import."])
    }

    static var damaged: CocoaError {
        CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey:
            "This Safari export file is damaged or uses a format Parc can’t read."])
    }
}

private final class SafariExportZip {
    struct Entry {
        let name: String
        let flags: UInt16
        let method: UInt16
        let crc: UInt32
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localOffset: UInt64
    }

    static let archiveLimit: UInt64 = 1 << 30
    static let inflationBudget: UInt64 = 2 << 30
    static let profileLimit = 64
    static let historyLimit: UInt64 = 256 << 20
    static let bookmarksLimit: UInt64 = 64 << 20
    static let passwordsLimit: UInt64 = 1_000 << 10
    static let classifyLimit: UInt64 = 256 << 20
    static let prefixLength = 64 << 10
    static let entryLimit: UInt64 = 10_000

    private static let crcTable: [UInt32] = (0..<256).map { seed in
        var value = UInt32(seed)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    let data: Data
    private(set) var entries: [Entry] = []
    private var inflated: UInt64 = 0

    init(contentsOf url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw SafariExportFailure.notExport }
        guard let size = values.fileSize, UInt64(size) <= Self.archiveLimit else { throw SafariExportFailure.tooLarge }
        data = try Data(contentsOf: url)
        guard UInt64(data.count) <= Self.archiveLimit else { throw SafariExportFailure.tooLarge }
        try readCentralDirectory()
    }

    private func u16(_ offset: Int) -> UInt16 { integer(offset) }
    private func u32(_ offset: Int) -> UInt32 { integer(offset) }
    private func u64(_ offset: Int) -> UInt64 { integer(offset) }

    private func integer<T: FixedWidthInteger>(_ offset: Int) -> T {
        var value: T = 0
        for index in 0..<MemoryLayout<T>.size {
            value |= T(data[data.startIndex + offset + index]) << (8 * index)
        }
        return value
    }

    private func fits(_ offset: UInt64, _ length: UInt64) -> Bool {
        let count = UInt64(data.count)
        return offset <= count && length <= count - offset
    }

    private func readCentralDirectory() throws {
        let count = data.count
        guard count >= 22 else { throw SafariExportFailure.notExport }
        var position = count - 22
        let lowest = max(0, count - 65_557)
        var end: Int?
        while position >= lowest {
            if u32(position) == 0x0605_4B50, position + 22 + Int(u16(position + 20)) <= count {
                end = position
                break
            }
            position -= 1
        }
        guard let end else { throw SafariExportFailure.notExport }
        var total = UInt64(u16(end + 10))
        var directorySize = UInt64(u32(end + 12))
        var directoryOffset = UInt64(u32(end + 16))
        if end >= 20, u32(end - 20) == 0x0706_4B50 {
            let record = u64(end - 20 + 8)
            guard fits(record, 56), u32(Int(record)) == 0x0606_4B50 else { throw SafariExportFailure.damaged }
            let start = Int(record)
            guard u32(start + 16) == 0, u32(start + 20) == 0 else { throw SafariExportFailure.damaged }
            total = u64(start + 32)
            directorySize = u64(start + 40)
            directoryOffset = u64(start + 48)
        } else {
            guard u16(end + 4) == 0, u16(end + 6) == 0 else { throw SafariExportFailure.damaged }
        }
        guard total <= Self.entryLimit else { throw SafariExportFailure.tooLarge }
        guard fits(directoryOffset, directorySize) else { throw SafariExportFailure.damaged }
        var cursor = Int(directoryOffset)
        let limit = Int(directoryOffset + directorySize)
        for _ in 0..<total {
            guard cursor + 46 <= limit, u32(cursor) == 0x0201_4B50 else { throw SafariExportFailure.damaged }
            let flags = u16(cursor + 8)
            var compressed = UInt64(u32(cursor + 20))
            var uncompressed = UInt64(u32(cursor + 24))
            var local = UInt64(u32(cursor + 42))
            let nameStart = cursor + 46
            let extraStart = nameStart + Int(u16(cursor + 28))
            let extraEnd = extraStart + Int(u16(cursor + 30))
            let next = extraEnd + Int(u16(cursor + 32))
            guard next <= limit else { throw SafariExportFailure.damaged }
            var field = extraStart
            while field + 4 <= extraEnd {
                let fieldEnd = field + 4 + Int(u16(field + 2))
                guard fieldEnd <= extraEnd else { break }
                if u16(field) == 0x0001 {
                    var value = field + 4
                    func wide(_ current: inout UInt64) throws {
                        guard current == 0xFFFF_FFFF else { return }
                        guard value + 8 <= fieldEnd else { throw SafariExportFailure.damaged }
                        current = u64(value)
                        value += 8
                    }
                    try wide(&uncompressed)
                    try wide(&compressed)
                    try wide(&local)
                }
                field = fieldEnd
            }
            let rawName = data[(data.startIndex + nameStart)..<(data.startIndex + extraStart)]
            if let name = Self.usableName(rawName, utf8: flags & 0x0800 != 0) {
                entries.append(Entry(name: name, flags: flags, method: u16(cursor + 10), crc: u32(cursor + 16),
                                     compressedSize: compressed, uncompressedSize: uncompressed, localOffset: local))
            }
            cursor = next
        }
        var previousEnd: UInt64 = 0
        for entry in entries.sorted(by: { $0.localOffset < $1.localOffset }) {
            guard entry.localOffset >= previousEnd, entry.localOffset <= directoryOffset,
                  directoryOffset - entry.localOffset >= 30,
                  u32(Int(entry.localOffset)) == 0x0403_4B50 else { throw SafariExportFailure.damaged }
            let header = Int(entry.localOffset)
            let start = entry.localOffset + 30 + UInt64(u16(header + 26)) + UInt64(u16(header + 28))
            guard start <= directoryOffset, entry.compressedSize <= directoryOffset - start else { throw SafariExportFailure.damaged }
            previousEnd = start + entry.compressedSize
        }
    }

    private static func usableName(_ raw: Data, utf8 flagged: Bool) -> String? {
        let decoded = String(decoding: raw, as: UTF8.self)
        let name: String
        if decoded.utf8.elementsEqual(raw) {
            name = decoded
        } else {
            guard !flagged, let latin = String(data: raw, encoding: .isoLatin1) else { return nil }
            name = latin
        }
        guard !name.isEmpty, !name.hasPrefix("/"), !name.hasSuffix("/"), !name.contains("\\"), !name.contains("\0") else { return nil }
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains("__MACOSX"),
              let last = components.last, !last.isEmpty, !last.hasPrefix(".") else { return nil }
        return String(last)
    }

    func classify(_ entry: Entry) throws -> (type: String?, data: Data?) {
        if entry.uncompressedSize <= UInt64(Self.prefixLength) {
            let full = try contents(of: entry)
            return (Self.dataType(in: full), full)
        }
        if let type = Self.dataType(in: try prefix(of: entry, length: Self.prefixLength)) { return (type, nil) }
        guard entry.uncompressedSize <= Self.classifyLimit else { return (nil, nil) }
        return (Self.dataType(in: try contents(of: entry)), nil)
    }

    private func spend(_ bytes: UInt64) throws {
        guard bytes <= Self.inflationBudget - inflated else { throw SafariExportFailure.tooLarge }
        inflated += bytes
    }

    func contents(of entry: Entry) throws -> Data {
        let source = try compressedBytes(of: entry)
        try spend(entry.uncompressedSize)
        let output: Data
        if entry.method == 0 {
            guard entry.compressedSize == entry.uncompressedSize else { throw SafariExportFailure.damaged }
            output = Data(source)
        } else {
            let size = Int(entry.uncompressedSize)
            output = Self.inflate(source, capacity: size + 1)
            guard output.count == size else { throw SafariExportFailure.damaged }
        }
        guard Self.crc32(output) == entry.crc else { throw SafariExportFailure.damaged }
        return output
    }

    private func prefix(of entry: Entry, length: Int) throws -> Data {
        let source = try compressedBytes(of: entry)
        try spend(UInt64(length))
        if entry.method == 0 {
            guard entry.compressedSize == entry.uncompressedSize else { throw SafariExportFailure.damaged }
            return Data(source.prefix(length))
        }
        let output = Self.inflate(source, capacity: length)
        guard output.count == length else { throw SafariExportFailure.damaged }
        return output
    }

    private func compressedBytes(of entry: Entry) throws -> Data {
        guard entry.flags & 0x0001 == 0, entry.method == 0 || entry.method == 8 else { throw SafariExportFailure.damaged }
        guard fits(entry.localOffset, 30) else { throw SafariExportFailure.damaged }
        let header = Int(entry.localOffset)
        guard u32(header) == 0x0403_4B50 else { throw SafariExportFailure.damaged }
        let start = entry.localOffset + 30 + UInt64(u16(header + 26)) + UInt64(u16(header + 28))
        guard fits(start, entry.compressedSize) else { throw SafariExportFailure.damaged }
        let lower = data.startIndex + Int(start)
        return data[lower..<(lower + Int(entry.compressedSize))]
    }

    private static func inflate(_ source: Data, capacity: Int) -> Data {
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { target in
            source.withUnsafeBytes { input -> Int in
                guard let destination = target.bindMemory(to: UInt8.self).baseAddress,
                      let origin = input.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destination, capacity, origin, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        output.count = written
        return output
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        crcTable.withUnsafeBufferPointer { table in
            data.withUnsafeBytes { bytes in
                for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    static func dataType(in data: Data) -> String? {
        let key = Array("\"data_type\"".utf8)
        return data.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let bytes = raw.bindMemory(to: UInt8.self)
            func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D }
            var start = 0
            while start + key.count <= bytes.count {
                guard let match = key.withUnsafeBytes({ memmem(base + start, bytes.count - start, $0.baseAddress, key.count) }) else {
                    return nil
                }
                let found = base.distance(to: UnsafeRawPointer(match))
                start = found + 1
                if found > 0, bytes[found - 1] == UInt8(ascii: "\\") { continue }
                var index = found + key.count
                while index < bytes.count, isSpace(bytes[index]) { index += 1 }
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { continue }
                index += 1
                while index < bytes.count, isSpace(bytes[index]) { index += 1 }
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { continue }
                index += 1
                let valueStart = index
                while index < bytes.count, index - valueStart < 64,
                      bytes[index] != UInt8(ascii: "\""), bytes[index] != UInt8(ascii: "\\") { index += 1 }
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { continue }
                return String(decoding: UnsafeBufferPointer(rebasing: bytes[valueStart..<index]), as: UTF8.self)
            }
            return nil
        }
    }
}
