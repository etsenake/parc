import Foundation
import Testing
@testable import ParcCore

enum ExternalSplitDropTestsSupport {
    @MainActor final class Fixture {
        let root: URL
        let store: BrowserStore
        let a: UUID, b: UUID, profile: UUID, space: UUID
        let original: BrowserState
        let group: BrowserSplitLayout
        let receipt: TabCreationProvenance
        let destination = URL(string: "https://external.invalid/path?original=a+b#section")!
        let homeSpace = UUID(), homeID = UUID(), urlID = UUID()
        let now = Date(timeIntervalSince1970: 123456)

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-external-split-" + UUID().uuidString)
            let store = try BrowserStore(directory: root)
            let a = store.openResolvedURL(URL(string: "https://one.invalid")!), b = store.openResolvedURL(URL(string: "https://two.invalid")!)
            store.setSplit([a, b])
            let profile = store.activeSpace.profileID
            let original = store.state
            self.store = store
            self.a = a; self.b = b
            self.profile = profile
            space = store.activeSpaceID
            self.original = original
            group = store.activeSplitLayout!
            receipt = TabCreationProvenance(referrerID: nil, activeTabID: a, profileID: profile, state: original)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        var aIndex: Int { original.tabs.firstIndex { $0.id == a }! }
        var bIndex: Int { original.tabs.firstIndex { $0.id == b }! }
        var tray: SidebarContainerLocation { SidebarContainerLocation(spaceID: space, folderID: nil, section: .favorite, profileID: profile) }
        let pinnedFolderID = UUID(), siblingFolderID = UUID()
        var pinnedContainer: SidebarContainerLocation { SidebarContainerLocation(spaceID: space, folderID: pinnedFolderID, section: .pinned) }

        func commit(_ store: BrowserStore, id: UUID = UUID(), selection: [UUID], layout: BrowserSplitLayout?,
                    target: SplitDropTarget, orientation: SplitOrientation = .horizontal, savedHomeID: UUID? = nil,
                    documents: [UUID: SidebarDocumentReference] = [:]) throws -> Bool {
            try store.dropExternalURLIntoSplit(destination, tabID: id, spaceID: space, profileID: profile,
                expectedSelection: selection, expectedLayout: layout, target: target, orientation: orientation,
                creation: receipt, savedHomeID: savedHomeID, documents: documents)
        }

        func proposal(_ state: BrowserState, _ target: SplitDropTarget, _ selection: [UUID], _ layout: BrowserSplitLayout?,
                      _ orientation: SplitOrientation = .vertical) -> BrowserState? {
            ExternalSplitDrop.proposal(url: destination, tabID: UUID(), state: state, spaceID: space, profileID: profile,
                selection: selection, layout: layout, target: target, orientation: orientation, creation: receipt, now: Date())
        }

        func favoriteProposal(_ state: BrowserState, _ target: SplitDropTarget, _ layout: BrowserSplitLayout? = nil,
                              home: UUID? = nil, useHome: Bool = true) -> BrowserState? {
            ExternalSplitDrop.proposal(url: destination, tabID: urlID, state: state, spaceID: space, profileID: profile,
                selection: state.selectedTabIDs, layout: layout, target: target, orientation: .vertical,
                creation: receipt, now: now, savedHomeID: useHome ? (home ?? homeID) : nil)
        }

        func fourPanes() -> (BrowserState, BrowserSplitLayout) {
            var four = original
            let c = UUID(), d = UUID()
            for extra in [c, d] { var t = original.tabs[0]; t.id = extra; four.tabs.append(t) }
            four.selectedTabIDs = [a, b, c, d]
            var fourGroup = group
            fourGroup.tabIDs = four.selectedTabIDs
            fourGroup.widthFactors = [0.25, 0.25, 0.25, 0.25]
            four.splitLayouts = [fourGroup]
            return (four, fourGroup)
        }

        func favorite() -> BrowserState {
            var favorite = original
            favorite.spaces.append(BrowserSpace(id: homeSpace, name: "Home", symbol: "star", color: "123456", profileID: profile))
            favorite.splitLayouts = []
            favorite.selectedTabIDs = [a]
            favorite.tabs[aIndex].kind = .favorite
            favorite.tabs[aIndex].spaceID = homeSpace
            favorite.tabs[aIndex].savedURL = "https://home.invalid/saved"
            favorite.tabs[aIndex].savedTitle = "Saved home"
            favorite.tabs[aIndex].customTitle = "My Favorite"
            favorite.tabs[aIndex].url = "https://away.invalid/live"
            favorite.tabs[aIndex].title = "Live page"
            favorite.tabs[aIndex].referrerID = b
            favorite.tabs[bIndex].kind = .favorite
            favorite.sidebarItemOrder[tray.key] = [.tab(b), .tab(a)]
            favorite.selectionBySpace[homeSpace.uuidString] = [a]
            return favorite
        }

        func favoriteGroupState() -> (BrowserState, BrowserSplitLayout) {
            var state = favorite()
            state.tabs[bIndex].spaceID = homeSpace
            state.selectedTabIDs = [a, b]
            var trayGroup = group
            trayGroup.spaceID = homeSpace
            trayGroup.customTitle = "Saved group"
            trayGroup.customIcon = .emoji("🌙")
            state.splitLayouts = [trayGroup]
            state.sidebarItemOrder[tray.key] = [.tab(a)]
            return (state, trayGroup)
        }

        func cappedFavorites(_ state: BrowserState) -> BrowserState {
            var capped = state
            let template = capped.tabs[aIndex]
            for i in 0..<11 { var tab = template; tab.id = UUID(); tab.title = "Favorite \(i)"; capped.tabs.append(tab) }
            return capped
        }

        func pinned() -> BrowserState {
            var state = favorite()
            let folder = BrowserFolder(id: pinnedFolderID, spaceID: space, name: "Original folder")
            let sibling = BrowserFolder(id: siblingFolderID, spaceID: space, name: "Sibling", parentID: pinnedFolderID)
            state.folders += [folder, sibling]
            for index in [aIndex, bIndex] {
                state.tabs[index].kind = .pinned
                state.tabs[index].spaceID = space
                state.tabs[index].folderID = pinnedFolderID
            }
            state.sidebarItemOrder[pinnedContainer.key] = [.tab(b), .tab(a), .folder(siblingFolderID)]
            return state
        }

        func session(_ state: BrowserState, _ name: String) throws -> URL {
            let path = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: path.appendingPathComponent("session.json"))
            return path
        }

        func breakWrites(in directory: URL) throws {
            let file = directory.appendingPathComponent("session.json")
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        }
    }
}
