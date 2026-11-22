import Foundation
import ParcCore

package enum CommandBarTabEligibility {
    package static func tabs(_ tabs: @autoclosure () -> [BrowserTab], profileID: UUID, excluding currentID: UUID?,
                     unavailable: @autoclosure () -> Set<UUID>, isPopupWindow: Bool) -> [BrowserTab] {
        guard !isPopupWindow else { return [] }
        let candidates = tabs()
        let unavailableIDs = unavailable()
        return candidates.filter {
            $0.profileID == profileID && $0.id != currentID && $0.archivedAt == nil && !unavailableIDs.contains($0.id)
        }
    }
}
