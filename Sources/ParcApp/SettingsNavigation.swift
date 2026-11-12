import Foundation

struct SettingsNavigation<Destination: Equatable> {
    private(set) var entries: [Destination] = []
    private(set) var index = -1

    var current: Destination? { entries.indices.contains(index) ? entries[index] : nil }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index + 1 < entries.count }
    var previous: Destination? { canGoBack ? entries[index - 1] : nil }
    var next: Destination? { canGoForward ? entries[index + 1] : nil }

    mutating func visit(_ destination: Destination) {
        guard current != destination else { return }
        if canGoForward { entries.removeSubrange((index + 1)...) }
        entries.append(destination)
        index = entries.count - 1
    }

    mutating func replaceCurrent(with destination: Destination) {
        guard entries.indices.contains(index) else { visit(destination); return }
        entries[index] = destination
        collapseRepeats()
    }

    mutating func moveBack() { if canGoBack { index -= 1 } }
    mutating func moveForward() { if canGoForward { index += 1 } }

    mutating func removeAll(where shouldRemove: (Destination) -> Bool, replacingCurrentWith fallback: Destination) {
        if let current, shouldRemove(current) { entries[index] = fallback }
        var kept: [Destination] = []
        var keptIndex = -1
        for (offset, entry) in entries.enumerated() where offset == index || !shouldRemove(entry) {
            if offset == index { keptIndex = kept.count }
            kept.append(entry)
        }
        entries = kept
        index = keptIndex
        collapseRepeats()
    }

    private mutating func collapseRepeats() {
        var kept: [Destination] = []
        var keptIndex = -1
        for (offset, entry) in entries.enumerated() {
            if let last = kept.last, last == entry {
                if offset == index { keptIndex = kept.count - 1 }
                continue
            }
            if offset == index { keptIndex = kept.count }
            kept.append(entry)
        }
        entries = kept
        index = keptIndex
    }
}
