import Foundation

package struct SidebarKeyboardCursor {
    package private(set) var highlightedID: String?
    package init(highlightedID: String?) { self.highlightedID = highlightedID }

    package mutating func reconcile(_ ids: [String]) {
        if let highlightedID, !ids.contains(highlightedID) { self.highlightedID = nil }
    }

    mutating func move(_ delta: Int, in ids: [String]) {
        reconcile(ids)
        guard !ids.isEmpty, delta != 0 else { return }
        guard let highlightedID, let index = ids.firstIndex(of: highlightedID) else {
            self.highlightedID = delta > 0 ? ids.first : ids.last
            return
        }
        let next = index + (delta > 0 ? 1 : -1)
        self.highlightedID = ids.indices.contains(next) ? ids[next] : nil
    }
}
