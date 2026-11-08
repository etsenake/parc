import Foundation

///
/// one HTML file per Note named after its title and dated with its last edit
///
/// lastUpdatedAt). The user picks the archive or its unzipped folder; both are
/// only read, and an archive is expanded into a private temporary folder.
enum ArcNotesExport {
    struct Note: Equatable {
        let title: String
        let html: String
        let modifiedAt: Date
    }
    enum Failure: Error, LocalizedError {
        case unreadable, tooLarge, empty
        var errorDescription: String? {
            switch self {
            case .unreadable: return "That file isn’t an Arc Notes export Parc can read."
            case .tooLarge: return "That Arc Notes export is too large to import."
            case .empty: return "That Arc Notes export has no Notes in it."
            }
        }
    }
    static let maximumNotes = 10_000
    static let maximumNoteBytes = 8 * 1024 * 1024
    static let maximumArchiveBytes: Int64 = 1024 * 1024 * 1024
    static let maximumEntries = 20_000

    static func read(_ url: URL) throws -> [Note] {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
        if values.isDirectory == true { return try notes(in: url) }
        guard values.isRegularFile == true, url.pathExtension.lowercased() == "zip" else { throw Failure.unreadable }
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("ParcArcNotes-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: directory) }
        // List first: refuse paths that leave the folder and archives that
        // would expand past the limit before anything is written.
        let listing = try run("/usr/bin/zipinfo", ["-l", url.path])
        var total: Int64 = 0, entries = 0
        let lines = listing.split(separator: "\n")
        // Every entry must be one this check read: zipinfo states the count.
        guard let header = lines.first(where: { $0.contains("number of entries:") }),
              let stated = Int(header.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") else {
            throw Failure.unreadable
        }
        for line in lines where line.range(of: "^[-dlpscb?][-rwxahsStT]{6,9}\\s", options: .regularExpression) != nil {
            // Only plain files and folders; links and devices are refused.
            guard line.first == "-" || line.first == "d" else { throw Failure.unreadable }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 10, let size = Int64(fields[3]) else { throw Failure.unreadable }
            let name = fields[9...].joined(separator: " ")
            guard !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else { throw Failure.unreadable }
            total += size; entries += 1
            guard total <= maximumArchiveBytes, entries <= maximumEntries else { throw Failure.tooLarge }
        }
        guard entries == stated else { throw Failure.unreadable }
        _ = try run("/usr/bin/ditto", ["-x", "-k", url.path, directory.path])
        return try notes(in: directory)
    }

    private static func notes(in directory: URL) throws -> [Note] {
        let files = FileManager.default
        guard let walker = files.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey,
            .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            throw Failure.unreadable
        }
        var result: [Note] = [], total: Int64 = 0
        for case let file as URL in walker {
            if file.lastPathComponent == "__MACOSX" || walker.level >= 3 { walker.skipDescendants() }
            guard file.lastPathComponent != "__MACOSX", ["html", "htm"].contains(file.pathExtension.lowercased()) else { continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? .max) <= maximumNoteBytes else { continue }
            total += Int64(values.fileSize ?? 0)
            guard result.count < maximumNotes, total <= maximumArchiveBytes else { throw Failure.tooLarge }
            let data = try Data(contentsOf: file)
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { continue }
            result.append(Note(title: file.deletingPathExtension().lastPathComponent, html: html,
                               modifiedAt: values.contentModificationDate ?? Date()))
        }
        guard !result.isEmpty else { throw Failure.empty }
        return result.sorted { $0.modifiedAt == $1.modifiedAt ? $0.title < $1.title : $0.modifiedAt < $1.modifiedAt }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: tool); process.arguments = arguments
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.unreadable }
        return String(decoding: data, as: UTF8.self)
    }
}
