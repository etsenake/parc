import Foundation

enum DocumentsLibraryReveal {
    enum Target: Hashable {
        case note(URL), easel(UUID)
    }

    static func folder(for target: Target, library: URL) -> URL? {
        guard case .note(let url) = target, !NoteFilePaths.contains(folder: library, item: url) else { return nil }
        return NoteFilePaths.canonical(url).deletingLastPathComponent()
    }

    static func index(of target: Target, in visible: [Target]) -> Int? {
        let wanted = key(target)
        return visible.firstIndex { key($0) == wanted }
    }

    static func clearsQuery(_ query: String, target: Target, visible: [Target]) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && index(of: target, in: visible) == nil
    }

    private static func key(_ target: Target) -> String {
        switch target {
        case .note(let url): return "note:" + NoteFilePaths.key(for: url)
        case .easel(let id): return "easel:" + id.uuidString.lowercased()
        }
    }
}
