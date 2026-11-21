import Foundation

enum EaselCompletionGate {
    enum Action: Equatable { case complete, open, refresh, dismiss }

    static func action(inserted: String?, editedByOne: Bool, panelOpen: Bool) -> Action {
        if let inserted, inserted.count == 1 { return inserted == ":" ? .complete : .open }
        return panelOpen && editedByOne ? .refresh : .dismiss
    }
}
