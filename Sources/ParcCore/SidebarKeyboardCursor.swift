import Foundation

///
/// of active contents. Crossing either edge clears it; the next arrow enters
/// from the other edge. Typing does not commit this cursor to browser state.
struct SidebarKeyboardCursor {
    private(set) var highlightedID: String?
    init(highlightedID: String?) { self.highlightedID = highlightedID }

    mutating func reconcile(_ ids: [String]) {
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
