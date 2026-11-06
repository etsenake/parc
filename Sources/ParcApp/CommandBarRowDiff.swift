import AppKit

///
/// returns early when the row keys and trailing accessories are unchanged;
/// otherwise it applies
/// `newKeys.difference(from: oldKeys)` as unanimated removals and insertions
///
/// options 0). Surviving rows keep their row views. Parc also reloads the cell
/// of a surviving row whose displayed content changed, because its keys can
/// outlive a title, shortcut, availability or deletion change.
struct CommandBarRowDiff: Equatable {
    struct Row: Equatable {
        let id: String
        let content: String
    }
    private(set) var removals = IndexSet()
    private(set) var insertions = IndexSet()
    /// New indices of surviving rows whose content changed.
    private(set) var changed = IndexSet()
    var isEmpty: Bool { removals.isEmpty && insertions.isEmpty && changed.isEmpty }

    init(old: [Row], new: [Row]) {
        for change in new.map(\.id).difference(from: old.map(\.id)) {
            switch change {
            case let .remove(offset, _, _): removals.insert(offset)
            case let .insert(offset, _, _): insertions.insert(offset)
            }
        }
        var oldIndex = 0
        for newIndex in new.indices where !insertions.contains(newIndex) {
            while removals.contains(oldIndex) { oldIndex += 1 }
            guard old.indices.contains(oldIndex) else { break }
            if old[oldIndex].content != new[newIndex].content { changed.insert(newIndex) }
            oldIndex += 1
        }
    }

    ///
    ///
    static func keepsSelection(at row: Int, old: [String], new: [String]) -> Bool {
        old.indices.contains(row) && new.indices.contains(row) && old[row] == new[row]
    }

    ///
    ///
    /// destination also carries the typed text (Google's `oq=`), so keying on
    /// it would replace every suggestion on each keystroke.
    static func searchKey(_ terms: String) -> String {
        "search:" + terms.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    static func pageKey(_ url: URL) -> String {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased() else { return "page:" + url.absoluteString }
        var host = (parts.host ?? "").lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var key = ["http", "https"].contains(scheme) ? host : scheme + "://" + host
        if let port = parts.port { key += ":\(port)" }
        key += parts.percentEncodedPath == "/" ? "" : parts.percentEncodedPath
        if let query = parts.percentEncodedQuery { key += "?" + query }
        if let fragment = parts.percentEncodedFragment { key += "#" + fragment }
        return "page:" + key
    }
}

extension NSTableView {
    func apply(_ diff: CommandBarRowDiff) {
        if !diff.removals.isEmpty || !diff.insertions.isEmpty {
            beginUpdates()
            if !diff.removals.isEmpty { removeRows(at: diff.removals, withAnimation: []) }
            if !diff.insertions.isEmpty { insertRows(at: diff.insertions, withAnimation: []) }
            endUpdates()
        }
        if !diff.changed.isEmpty {
            reloadData(forRowIndexes: diff.changed, columnIndexes: IndexSet(integer: 0))
        }
    }
}
