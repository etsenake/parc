import Foundation
import Testing
@testable import ParcCore

@MainActor
enum TabCreationProvenanceTestsSupport {
    struct Fixture {
        var state = BrowserState.initial()
        let space: BrowserSpace
        let profile: UUID
        let parent: BrowserTab
        let previous: BrowserTab
        let current: BrowserTab
        let child: BrowserTab

        init() {
            space = state.spaces[0]
            profile = space.profileID
            parent = Self.tab(.pinned, space: space.id, profile: profile)
            previous = Self.tab(space: space.id, profile: profile)
            current = Self.tab(space: space.id, profile: profile)
            child = Self.tab(space: space.id, profile: profile, referrer: current.id)
            state.tabs = [parent, previous, current, child]
            state.selectedTabIDs = [current.id]
            state.selectionBySpace[space.id.uuidString] = [current.id]
        }

        static func tab(_ kind: TabKind = .today, space: UUID, profile: UUID, referrer: UUID? = nil, previous: UUID? = nil) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space, profileID: profile,
                       url: "https://example.test/", title: "Original", kind: kind,
                       createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 1),
                       savedURL: "https://example.test/", savedTitle: "Original",
                       referrerID: referrer, activeTabBeforeCreationID: previous)
        }

        func tab(_ kind: TabKind = .today, referrer: UUID? = nil, previous: UUID? = nil) -> BrowserTab {
            Self.tab(kind, space: space.id, profile: profile, referrer: referrer, previous: previous)
        }

        func choose(_ input: BrowserState? = nil, closing: UUID? = nil, pool: Set<UUID> = [], unavailable: Set<UUID> = []) -> FolderRemovalSelection? {
            let id = closing ?? current.id
            return FolderRemovalSelection.resolve(removing: [id], spaceID: space.id, profileID: profile,
                state: input ?? state, selected: [id], focused: id, referrerPool: pool,
                available: { !unavailable.contains($0) })
        }

        func index(_ id: UUID, in state: BrowserState) -> Int { state.tabs.firstIndex { $0.id == id }! }
    }
}
