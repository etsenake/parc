import Foundation

package enum NoteFilePaths {
    private static let segmentCharacters: Set<UInt8> = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$&'*+,;=@".utf8)

    package static func canonical(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        var path = standardized.path
        var trailing: [String] = []
        while !path.isEmpty {
            if let resolved = realpath(path, nil) {
                defer { free(resolved) }
                var result = throughFirmlinks(String(cString: resolved))
                for component in trailing.reversed() { result = (result as NSString).appendingPathComponent(component) }
                return URL(fileURLWithPath: result, isDirectory: standardized.hasDirectoryPath)
            }
            if path == "/" { break }
            trailing.append((path as NSString).lastPathComponent)
            path = (path as NSString).deletingLastPathComponent
        }
        return standardized
    }

    package static func key(for url: URL) -> String { identityKey(ofCanonicalPath: canonical(url).path) }

    package static func identityKey(ofCanonicalPath path: String) -> String {
        isCaseSensitive(atPath: path) ? path : path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
    }

    package static func sameItem(_ first: URL, _ second: URL) -> Bool {
        let left = first.standardizedFileURL.path, right = second.standardizedFileURL.path
        if left == right { return true }
        let leftNode = NoteFileNode(path: left), rightNode = NoteFileNode(path: right)
        if (leftNode == nil) != (rightNode == nil) { return false }
        if let leftNode, let rightNode, leftNode != rightNode { return false }
        return key(for: first) == key(for: second)
    }

    package static func isOpenableFile(_ url: URL) -> Bool {
        var info = stat()
        return stat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    private static func throughFirmlinks(_ resolved: String) -> String {
        var info = stat()
        guard lstat(resolved, &info) == 0 else { return resolved }
        let isFolder = (info.st_mode & S_IFMT) == S_IFDIR
        let folder = isFolder ? resolved : (resolved as NSString).deletingLastPathComponent
        guard let actual = descriptorPath(ofFolder: folder) else { return resolved }
        return isFolder ? actual : (actual as NSString).appendingPathComponent((resolved as NSString).lastPathComponent)
    }

    private static func descriptorPath(ofFolder folder: String) -> String? {
        let descriptor = open(folder, O_EVTONLY | O_NONBLOCK | O_CLOEXEC | O_DIRECTORY)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return nil }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return path.isEmpty ? nil : path
    }

    package static func itemExists(_ url: URL) -> Bool { itemExists(atPath: url.path) }

    package static func itemExists(atPath path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    package static func isDirectory(_ url: URL) -> Bool {
        var info = stat()
        return stat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    package static func isDataless(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_flags & UInt32(SF_DATALESS) != 0
    }

    package static func isSameFile(_ first: URL, _ second: URL) -> Bool {
        var a = stat(), b = stat()
        guard stat(first.path, &a) == 0, stat(second.path, &b) == 0 else { return false }
        return a.st_dev == b.st_dev && a.st_ino == b.st_ino
    }

    package static func isInTrash(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    package static func contains(folder: URL, item: URL) -> Bool {
        let base = canonical(folder).pathComponents
        let inner = canonical(item).pathComponents
        guard inner.count > base.count else { return false }
        let insensitive = !isCaseSensitive(folder)
        return zip(base, inner).allSatisfy { sameComponent($0, $1, caseInsensitive: insensitive) }
    }

    package static func relativePath(from directory: URL, to target: URL) -> String? {
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

    package static func encodedSegment(_ segment: String) -> String {
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

    package static func encodedPath(_ components: [String]) -> String {
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

    private static func isCaseSensitive(_ url: URL) -> Bool { isCaseSensitive(atPath: canonical(url).path) }

    private static func isCaseSensitive(atPath path: String) -> Bool {
        var probe = path
        while !itemExists(atPath: probe), probe != "/", !probe.isEmpty { probe = (probe as NSString).deletingLastPathComponent }
        return pathconf(probe.isEmpty ? "/" : probe, _PC_CASE_SENSITIVE) == 1
    }
}

package struct NoteFileNode: Hashable, Sendable {
    package var device: UInt64
    package var inode: UInt64

    package init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        device = UInt64(info.st_dev)
        inode = UInt64(info.st_ino)
    }
}

package struct NoteFileIdentity {
    package let path: String
    package let key: String
    package let node: NoteFileNode?

    package init(_ url: URL) {
        path = url.standardizedFileURL.path
        node = NoteFileNode(path: path)
        key = NoteFilePaths.key(for: url)
    }

    package func matches(_ url: URL) -> Bool {
        let other = url.standardizedFileURL.path
        if other == path { return true }
        let otherNode = NoteFileNode(path: other)
        if (node == nil) != (otherNode == nil) { return false }
        if let node, let otherNode, node != otherNode { return false }
        return NoteFilePaths.key(for: url) == key
    }
}
