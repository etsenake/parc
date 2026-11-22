import ParcCore

enum CommandBarTabEligibility {
    static func tabs(_ tabs: [BrowserTab], profileID: UUID, excluding currentID: UUID?, unavailable: Set<UUID>) -> [BrowserTab] {
        tabs.filter {
            $0.profileID == profileID && $0.id != currentID && $0.archivedAt == nil && !unavailable.contains($0.id)
        }
    }
}
