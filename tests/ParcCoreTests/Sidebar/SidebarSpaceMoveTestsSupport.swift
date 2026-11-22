import Foundation
import Testing
@testable import ParcCore

enum SidebarSpaceMoveTestsSupport {
    struct Fixture {
        var state = BrowserState.initial()

        let source: BrowserSpace

        let destination: BrowserSpace

        let folder: BrowserFolder

        let nested: BrowserFolder

        let a: BrowserTab, b: BrowserTab, c: BrowserTab

        let today: BrowserTab, pinned: BrowserTab, existing: BrowserTab, favorite: BrowserTab

        let group: BrowserSplitLayout

        let from: SidebarHierarchySnapshot

        let to: SidebarHierarchySnapshot

        let move: SidebarSpaceMove

        let expectedGroup: BrowserSplitLayout

        static func location(_ space: UUID, _ parent: UUID?, _ kind: TabKind = .pinned) -> SidebarContainerLocation {
            .init(spaceID: space, folderID: parent, section: kind)
        }

        func location(_ space: UUID, _ parent: UUID?, _ kind: TabKind = .pinned) -> SidebarContainerLocation {
            Self.location(space, parent, kind)
        }

        init() {
            var state = BrowserState.initial()
            let source = state.spaces[0]
            let destination = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "112233", profileID: source.profileID)
            state.spaces.append(destination)
            let folder = BrowserFolder(id: UUID(), spaceID: source.id, name: "Tree", parentID: nil, isExpanded: false)
            let nested = BrowserFolder(id: UUID(), spaceID: source.id, name: "Nested", parentID: folder.id, isExpanded: true)
            func tab(_ space: UUID, _ kind: TabKind, _ parent: UUID? = nil) -> BrowserTab {
                .init(id: UUID(), spaceID: space, profileID: source.profileID, url: "https://example.test/live", title: "Live",
                      kind: kind, folderID: parent, createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 2),
                      savedURL: "https://example.test/saved", savedTitle: "Saved", isMuted: true, isUnread: true)
            }
            let a = tab(source.id, .pinned, nested.id), b = tab(source.id, .pinned, nested.id)
            let c = tab(source.id, .pinned, folder.id), today = tab(source.id, .today), pinned = tab(source.id, .pinned)
            let existing = tab(destination.id, .pinned), favorite = tab(source.id, .favorite)
            state.tabs = [a, b, c, today, pinned, existing, favorite]
            state.folders = [folder, nested]
            let group = BrowserSplitLayout(id: UUID(), sidebarAnchorID: b.id, spaceID: source.id, tabIDs: [a.id, b.id],
                                           orientation: .horizontal, widthFactors: [0.3, 0.7], stacks: nil)
            state.splitLayouts = [group]
            state.activeSpaceID = source.id
            state.selectedTabIDs = group.tabIDs
            state.selectionBySpace = [source.id.uuidString: group.tabIDs, destination.id.uuidString: [existing.id]]
            state.sidebarItemOrder[Self.location(source.id, nil).key] = [.folder(folder.id), .tab(pinned.id)]
            state.sidebarItemOrder[Self.location(source.id, folder.id).key] = [.folder(nested.id), .tab(c.id)]
            state.sidebarItemOrder[Self.location(source.id, nested.id).key] = [.tab(b.id)]
            let from = SidebarHierarchySnapshot(state: state, spaceID: source.id, profileID: source.profileID)!
            let to = SidebarHierarchySnapshot(state: state, spaceID: destination.id, profileID: source.profileID)!
            move = SidebarSpaceMove(items: [.folder(folder.id), .split(group.id), .tab(today.id)], from: from, to: to, state: state)!
            var expectedGroup = group
            expectedGroup.spaceID = destination.id
            self.expectedGroup = expectedGroup
            self.state = state
            self.source = source; self.destination = destination
            self.folder = folder; self.nested = nested
            self.a = a; self.b = b; self.c = c
            self.today = today; self.pinned = pinned; self.existing = existing; self.favorite = favorite
            self.group = group
            self.from = from; self.to = to
        }

        func proposed(_ original: BrowserState, _ roots: [SidebarItemReference]) -> SidebarSpaceMove? {
            guard let from = SidebarHierarchySnapshot(state: original, spaceID: source.id, profileID: source.profileID),
                  let to = SidebarHierarchySnapshot(state: original, spaceID: destination.id, profileID: source.profileID) else { return nil }
            return SidebarSpaceMove(items: roots, from: from, to: to, state: original)
        }

        func encoder() -> JSONEncoder {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return encoder
        }

        func directory(writing state: BrowserState) throws -> URL {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-move-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder().encode(state).write(to: directory.appendingPathComponent("session.json"))
            return directory
        }

        var moved: BrowserState { move.applying(to: state)! }

        struct MixedSections {
            let original: BrowserState
            let proposal: SidebarSpaceMove
            let result: BrowserState
            let kind: TabKind
        }

        func mixedSections(_ anchorKind: TabKind) -> MixedSections {
            var original = state
            original.tabs[0].kind = anchorKind == .pinned ? .today : .pinned
            original.tabs[0].folderID = anchorKind == .pinned ? nil : nested.id
            original.tabs[1].kind = anchorKind
            original.tabs[1].folderID = nil
            original.sidebarItemOrder[location(source.id, nil, .today).key] = [.tab(a.id), .tab(b.id), .tab(today.id)]
            original.sidebarItemOrder[location(source.id, nested.id).key] = [.tab(a.id), .tab(b.id)]
            original.sidebarItemOrder[location(source.id, nil).key] = [.folder(folder.id), .tab(b.id), .tab(pinned.id)]
            let proposal = proposed(original, [.split(group.id)])!
            return MixedSections(original: original, proposal: proposal, result: proposal.applying(to: original)!, kind: anchorKind)
        }

        struct NestedMixed {
            let state: BrowserState
            let outside: BrowserFolder
            let move: SidebarSpaceMove
            let result: BrowserState
        }

        func nestedMixed() -> NestedMixed {
            var nestedMixed = state
            let outside = BrowserFolder(id: UUID(), spaceID: source.id, name: "Stays", parentID: nil, isExpanded: false)
            nestedMixed.folders.append(outside)
            nestedMixed.tabs[0].folderID = outside.id
            nestedMixed.tabs[0].url = InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")).urlString
            nestedMixed.tabs[0].savedURL = nestedMixed.tabs[0].url
            nestedMixed.tabs[1].url = InternalPage.easel(UUID()).urlString
            nestedMixed.tabs[1].savedURL = nestedMixed.tabs[1].url
            nestedMixed.sidebarItemOrder[location(source.id, outside.id).key] = [.tab(a.id)]
            nestedMixed.sidebarItemOrder[location(source.id, nested.id).key] = [.tab(b.id)]
            let nestedMove = proposed(nestedMixed, [.folder(folder.id)])!
            return NestedMixed(state: nestedMixed, outside: outside, move: nestedMove, result: nestedMove.applying(to: nestedMixed)!)
        }
    }
}
