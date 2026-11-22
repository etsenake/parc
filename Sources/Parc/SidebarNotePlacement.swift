import Foundation
import ParcCore

struct SidebarNotePlacement: Equatable {
    let destination: SidebarContainerLocation
    let before: SidebarItemReference?

    static func opensNewTab(_ files: [URL], state: BrowserState, profileID: UUID) -> Bool {
        files.contains { file in
            !state.tabs.contains { $0.archivedAt == nil && $0.profileID == profileID && InternalPage(urlString: $0.url) == .note(file) }
        }
    }
}
