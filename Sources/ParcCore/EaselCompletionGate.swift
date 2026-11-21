import Foundation

package enum EaselCompletionGate {
    package enum Action: Equatable { case complete, open, refresh, dismiss }

    package static func action(inserted: String?, editedByOne: Bool, panelOpen: Bool) -> Action {
        if let inserted, inserted.count == 1 { return inserted == ":" ? .complete : .open }
        return panelOpen && editedByOne ? .refresh : .dismiss
    }
}
