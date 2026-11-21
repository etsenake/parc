import Foundation

package struct NoteBreadcrumbSegment: Hashable, Sendable {
    package enum Kind: String, Hashable, Sendable {
        case notes, home, volume, folder, note
    }

    package var kind: Kind
    package var name: String
    package var url: URL

    package var isFolder: Bool { kind != .note }

    package init(kind: Kind, name: String, url: URL) {
        self.kind = kind
        self.name = name
        self.url = url
    }
}

package struct NoteBreadcrumbPlaces {
    package var notesFolder: URL?
    package var home: URL
    package var volume: (URL) -> (url: URL, name: String)?
    package var displayName: (URL) -> String

    package static func system(notesFolder: URL?) -> NoteBreadcrumbPlaces {
        NoteBreadcrumbPlaces(notesFolder: notesFolder, home: FileManager.default.homeDirectoryForCurrentUser,
                             volume: NoteBreadcrumb.volume(of:), displayName: NoteBreadcrumb.displayName(of:))
    }
}

package enum NoteBreadcrumb {
    package static let separator = "/"

    package static func trail(for document: URL, places: NoteBreadcrumbPlaces) -> [NoteBreadcrumbSegment] {
        let file = NoteFilePaths.canonical(document)
        let root = self.root(of: file, places: places)
        var segments = [root]
        let rootDepth = root.url.pathComponents.count
        let components = file.deletingLastPathComponent().pathComponents
        if components.count > rootDepth {
            for depth in rootDepth..<components.count {
                let url = URL(fileURLWithPath: NSString.path(withComponents: Array(components[0...depth])), isDirectory: true)
                segments.append(NoteBreadcrumbSegment(kind: .folder, name: places.displayName(url), url: url))
            }
        }
        segments.append(NoteBreadcrumbSegment(kind: .note, name: title(of: file), url: file))
        return segments
    }

    package static func title(of file: URL) -> String {
        let name = file.deletingPathExtension().lastPathComponent
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : name
    }

    package static func text(of trail: [NoteBreadcrumbSegment]) -> String {
        trail.map(\.name).joined(separator: " " + separator + " ")
    }

    private static func root(of file: URL, places: NoteBreadcrumbPlaces) -> NoteBreadcrumbSegment {
        if let notes = places.notesFolder.map(NoteFilePaths.canonical), NoteFilePaths.contains(folder: notes, item: file) {
            return NoteBreadcrumbSegment(kind: .notes, name: places.displayName(notes), url: folderURL(notes))
        }
        let home = NoteFilePaths.canonical(places.home)
        if NoteFilePaths.contains(folder: home, item: file) {
            return NoteBreadcrumbSegment(kind: .home, name: places.displayName(home), url: folderURL(home))
        }
        if let volume = places.volume(file) {
            let url = NoteFilePaths.canonical(volume.url)
            if url.path == "/" || NoteFilePaths.contains(folder: url, item: file) {
                return NoteBreadcrumbSegment(kind: .volume, name: volume.name, url: folderURL(url))
            }
        }
        return NoteBreadcrumbSegment(kind: .volume, name: separator, url: URL(fileURLWithPath: "/", isDirectory: true))
    }

    private static func folderURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path, isDirectory: true)
    }

    package static func volume(of file: URL) -> (url: URL, name: String)? {
        guard let values = try? file.deletingLastPathComponent().resourceValues(forKeys: [.volumeURLKey, .volumeLocalizedNameKey, .volumeNameKey]),
              let url = values.volume else { return nil }
        let name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent
        return (url, name.isEmpty ? separator : name)
    }

    package static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.isEmpty ? url.lastPathComponent : name
    }
}
