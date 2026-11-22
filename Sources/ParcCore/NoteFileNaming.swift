import Foundation

package enum NoteFileNaming {
    static let untitled = "Untitled"
    static let maximumComponentBytes = 255
    package static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "webp", "bmp", "svg", "avif"]
    private static let suffixAllowance = 6

    static func sanitizedTitle(_ title: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in title.unicodeScalars {
            switch scalar {
            case "/", ":":
                scalars.append("-")
            case "\u{FFFC}", "\u{FEFF}":
                continue
            default:
                if scalar == "\t" || scalar.properties.isWhitespace {
                    scalars.append(" ")
                } else if scalar.properties.generalCategory == .control {
                    continue
                } else {
                    scalars.append(scalar)
                }
            }
        }
        var result = String(scalars).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        while result.hasPrefix(".") { result = String(result.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return result
    }

    static func sanitizedExtension(_ value: String) -> String {
        let trimmed = value.hasPrefix(".") ? String(value.dropFirst()) : value
        return String(trimmed.unicodeScalars.filter { $0.isASCII && CharacterSet.alphanumerics.contains($0) }.map(Character.init))
            .lowercased()
    }

    static func fileName(base: String, pathExtension: String, suffix: String = "") -> String {
        let extensionBytes = pathExtension.isEmpty ? 0 : pathExtension.utf8.count + 1
        let limit = maximumComponentBytes - extensionBytes - max(suffix.utf8.count, suffixAllowance)
        let stem = truncated(base, toBytes: limit) + suffix
        return pathExtension.isEmpty ? stem : stem + "." + pathExtension
    }

    static func truncated(_ value: String, toBytes limit: Int) -> String {
        guard value.utf8.count > limit else { return value }
        var result = ""
        var bytes = 0
        for character in value {
            let size = character.utf8.count
            if bytes + size > limit { break }
            result.append(character)
            bytes += size
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func candidates(in folder: URL, base: String, pathExtension: String) -> AnySequence<URL> {
        AnySequence(sequence(state: 1) { (index: inout Int) -> URL? in
            defer { index += 1 }
            let suffix = index == 1 ? "" : " \(index)"
            return folder.appendingPathComponent(fileName(base: base, pathExtension: pathExtension, suffix: suffix))
        })
    }

    static func uniqueURL(in folder: URL, base: String, pathExtension: String,
                          isTaken: (URL) -> Bool = NoteFilePaths.itemExists) -> URL {
        for candidate in candidates(in: folder, base: base, pathExtension: pathExtension) where !isTaken(candidate) {
            return candidate
        }
        return folder.appendingPathComponent(fileName(base: base + " " + UUID().uuidString, pathExtension: pathExtension))
    }

    static func renameTarget(for url: URL, to proposed: String) throws -> URL? {
        let folder = url.deletingLastPathComponent()
        let pathExtension = url.pathExtension
        let base = sanitizedTitle(proposed)
        let target: URL
        if base.isEmpty {
            if isUntitled(url.deletingPathExtension().lastPathComponent) { return nil }
            target = uniqueURL(in: folder, base: untitled, pathExtension: pathExtension) {
                NoteFilePaths.itemExists($0) && !NoteFilePaths.isSameFile($0, url)
            }
        } else {
            target = folder.appendingPathComponent(fileName(base: base, pathExtension: pathExtension))
        }
        guard target.lastPathComponent != url.lastPathComponent else { return nil }
        if NoteFilePaths.itemExists(target), !(NoteFilePaths.itemExists(url) && NoteFilePaths.isSameFile(target, url)) {
            throw NoteFileError.nameTaken(target.deletingPathExtension().lastPathComponent)
        }
        return target
    }

    static func isUntitled(_ title: String) -> Bool {
        guard title.hasPrefix(untitled) else { return false }
        let rest = title.dropFirst(untitled.count)
        if rest.isEmpty { return true }
        guard rest.first == " " else { return false }
        let digits = rest.dropFirst()
        return !digits.isEmpty && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber)
    }

    package static func pastedBaseName(at date: Date, isImage: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return (isImage ? "Pasted image " : "Pasted file ") + formatter.string(from: date)
    }
}
