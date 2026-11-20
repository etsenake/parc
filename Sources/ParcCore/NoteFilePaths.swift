import Foundation

enum NoteFilePaths {
    private static let segmentCharacters: Set<UInt8> = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$&'*+,;=@".utf8)

    static func canonical(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        var path = standardized.path
        var trailing: [String] = []
        while !path.isEmpty {
            if let resolved = realpath(path, nil) {
                defer { free(resolved) }
                var result = String(cString: resolved)
                for component in trailing.reversed() { result = (result as NSString).appendingPathComponent(component) }
                return URL(fileURLWithPath: result, isDirectory: standardized.hasDirectoryPath)
            }
            if path == "/" { break }
            trailing.append((path as NSString).lastPathComponent)
            path = (path as NSString).deletingLastPathComponent
        }
        return standardized
    }

    static func key(for url: URL) -> String { canonical(url).path }

    static func itemExists(_ url: URL) -> Bool { itemExists(atPath: url.path) }

    static func itemExists(atPath path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    static func isDirectory(_ url: URL) -> Bool {
        var info = stat()
        return stat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    static func isDataless(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_flags & UInt32(SF_DATALESS) != 0
    }

    static func isSameFile(_ first: URL, _ second: URL) -> Bool {
        var a = stat(), b = stat()
        guard stat(first.path, &a) == 0, stat(second.path, &b) == 0 else { return false }
        return a.st_dev == b.st_dev && a.st_ino == b.st_ino
    }

    static func isInTrash(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    static func contains(folder: URL, item: URL) -> Bool {
        let base = canonical(folder).pathComponents
        let inner = canonical(item).pathComponents
        guard inner.count > base.count else { return false }
        let insensitive = !isCaseSensitive(folder)
        return zip(base, inner).allSatisfy { sameComponent($0, $1, caseInsensitive: insensitive) }
    }

    static func relativePath(from directory: URL, to target: URL) -> String? {
        let base = canonical(directory).pathComponents
        let destination = canonical(target).pathComponents
        let insensitive = !isCaseSensitive(directory)
        var common = 0
        while common < base.count, common < destination.count,
              sameComponent(base[common], destination[common], caseInsensitive: insensitive) { common += 1 }
        guard common >= 2 else { return nil }
        let ups = Array(repeating: "..", count: base.count - common)
        let rest = destination[common...].map(encodedSegment)
        let parts = ups + rest
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }

    static func encodedSegment(_ segment: String) -> String {
        var result = ""
        for scalar in segment.unicodeScalars {
            if scalar.isASCII {
                let byte = UInt8(scalar.value)
                if segmentCharacters.contains(byte) { result.unicodeScalars.append(scalar) } else { result += percent(byte) }
                continue
            }
            switch scalar.properties.generalCategory {
            case .control, .format, .spaceSeparator, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned:
                for byte in String(scalar).utf8 { result += percent(byte) }
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func encodedPath(_ components: [String]) -> String {
        components.map(encodedSegment).joined(separator: "/")
    }

    private static func percent(_ byte: UInt8) -> String {
        let digits = Array("0123456789ABCDEF")
        return "%" + String(digits[Int(byte >> 4)]) + String(digits[Int(byte & 0x0F)])
    }

    private static func sameComponent(_ first: String, _ second: String, caseInsensitive: Bool) -> Bool {
        if first == second { return true }
        let a = first.precomposedStringWithCanonicalMapping, b = second.precomposedStringWithCanonicalMapping
        return caseInsensitive ? a.caseInsensitiveCompare(b) == .orderedSame : a == b
    }

    private static func isCaseSensitive(_ url: URL) -> Bool {
        var probe = canonical(url)
        while !itemExists(probe), probe.path != "/" { probe.deleteLastPathComponent() }
        return (try? probe.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?.volumeSupportsCaseSensitiveNames ?? false
    }
}
