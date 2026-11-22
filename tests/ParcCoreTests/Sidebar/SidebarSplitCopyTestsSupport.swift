import Foundation
import Testing
@testable import ParcCore

@MainActor
enum SidebarSplitCopyTestsSupport {
    enum DragSource: CaseIterable {
        case split, tab, folder, mixed

        var wholeSplits: Bool { self == .split }
    }

    static func write(_ state: BrowserState, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(state).write(to: directory.appendingPathComponent("session.json", isDirectory: false))
    }

    @MainActor final class Fixture {
        let root: URL
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let foreignProfile = BrowserProfile(id: UUID(), name: "Other")
        let here: BrowserSpace, there: BrowserSpace, elsewhere: BrowserSpace
        let folder: BrowserFolder
        let left: BrowserTab, right: BrowserTab, keep: BrowserTab, inside: BrowserTab
        let today: BrowserTab, away: BrowserTab, favA: BrowserTab, favB: BrowserTab, foreignTab: BrowserTab
        let split: BrowserSplitLayout, favorite: BrowserSplitLayout
        let pinned: SidebarContainerLocation, inFolder: SidebarContainerLocation, todayLocation: SidebarContainerLocation
        let therePinned: SidebarContainerLocation, favorites: SidebarContainerLocation, elsewherePinned: SidebarContainerLocation
        let state: BrowserState
        let store: BrowserStore
        let target: SidebarItemsCopy
        let urls: [UUID: String]
        let favURLs: [UUID: String]

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-copy-" + UUID().uuidString)
            let profileID = profile.id, foreignID = foreignProfile.id
            here = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profileID)
            there = BrowserSpace(id: UUID(), name: "There", symbol: "circle", color: "FEDCBA", profileID: profileID)
            elsewhere = BrowserSpace(id: UUID(), name: "Elsewhere", symbol: "circle", color: "123456", profileID: foreignID)
            folder = BrowserFolder(id: UUID(), spaceID: here.id, name: "Folder")
            let hereID = here.id, thereID = there.id
            func tab(_ title: String, kind: TabKind = .pinned, space: UUID? = nil, folder: UUID? = nil) -> BrowserTab {
                let url = "https://saved.invalid/" + title
                return .init(id: UUID(), spaceID: space ?? hereID, profileID: profileID, url: url, title: title,
                             kind: kind, folderID: folder, createdAt: Date(timeIntervalSince1970: 10),
                             lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
            }
            left = tab("Left"); right = tab("Right"); keep = tab("Keep"); inside = tab("Inside", folder: folder.id)
            today = tab("Today", kind: .today); away = tab("Away", space: thereID)
            favA = tab("FavA", kind: .favorite); favB = tab("FavB", kind: .favorite)
            foreignTab = BrowserTab(id: UUID(), spaceID: elsewhere.id, profileID: foreignID, url: "https://saved.invalid/F", title: "F",
                                    kind: .pinned, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                                    savedURL: "https://saved.invalid/F", savedTitle: "F")
            split = BrowserSplitLayout(sidebarAnchorID: left.id, customTitle: "Pair", spaceID: here.id,
                tabIDs: [left.id, right.id], orientation: .vertical, widthFactors: [0.4, 0.6])
            favorite = BrowserSplitLayout(sidebarAnchorID: favA.id, spaceID: here.id, tabIDs: [favA.id, favB.id], widthFactors: [0.5, 0.5])
            var state = BrowserState(profiles: [profile, foreignProfile], spaces: [here, there, elsewhere], activeSpaceID: here.id)
            state.folders = [folder]
            state.tabs = [left, right, keep, inside, today, away, favA, favB, foreignTab]
            state.splitLayouts = [split, favorite]
            pinned = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .pinned)
            inFolder = SidebarContainerLocation(spaceID: here.id, folderID: folder.id, section: .pinned)
            todayLocation = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .today)
            therePinned = SidebarContainerLocation(spaceID: there.id, folderID: nil, section: .pinned)
            favorites = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .favorite, profileID: profileID)
            state.sidebarItemOrder[pinned.key] = [.tab(keep.id), .tab(left.id), .folder(folder.id)]
            state.sidebarItemOrder[inFolder.key] = [.tab(inside.id)]
            state.sidebarItemOrder[therePinned.key] = [.tab(away.id)]
            elsewherePinned = SidebarContainerLocation(spaceID: elsewhere.id, folderID: nil, section: .pinned)
            state.sidebarItemOrder[elsewherePinned.key] = [.tab(foreignTab.id)]
            state.selectedTabIDs = split.tabIDs
            state.selectionBySpace[here.id.uuidString] = split.tabIDs
            self.state = state
            try SidebarSplitCopyTestsSupport.write(state, to: root)
            store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1000) })
            target = SidebarItemsCopy(items: [.split(split.id)], spaceID: here.id, profileID: profile.id, state: store.state)!
            urls = [left.id: "https://live.invalid/left", right.id: "https://live.invalid/right"]
            favURLs = [favA.id: "https://live.invalid/a", favB.id: "https://live.invalid/b"]
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func copyOfSplit(_ id: UUID? = nil) -> SidebarItemsCopy {
            SidebarItemsCopy(items: [.split(id ?? split.id)], spaceID: here.id, profileID: profile.id, state: store.state)!
        }

        func group(_ result: SidebarDuplicateResult) throws -> BrowserSplitLayout {
            guard case .split(let id)? = result.roots.first else { throw Failure() }
            return try #require(store.state.splitLayouts.first { $0.id == id })
        }

        struct Failure: Error {}
    }

    @MainActor final class Items {
        let root: URL
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let foreignProfile = BrowserProfile(id: UUID(), name: "Other")
        let here: BrowserSpace, there: BrowserSpace, elsewhere: BrowserSpace
        let outer: BrowserFolder, nested: BrowserFolder, target: BrowserFolder
        let loose: BrowserTab, today: BrowserTab, favorite: BrowserTab, inOuter: BrowserTab, inNested: BrowserTab
        let pairA: BrowserTab, pairB: BrowserTab, rootA: BrowserTab, rootB: BrowserTab, note: BrowserTab
        let nestedSplit: BrowserSplitLayout, rootSplit: BrowserSplitLayout
        let noteID: URL
        let pinned: SidebarContainerLocation, todayLocation: SidebarContainerLocation, outerLocation: SidebarContainerLocation
        let targetLocation: SidebarContainerLocation, therePinned: SidebarContainerLocation
        let elsewherePinned: SidebarContainerLocation, favorites: SidebarContainerLocation
        let store: BrowserStore
        let initial: BrowserState
        let noteDocs: [UUID: SidebarDocumentReference]

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-copy-" + UUID().uuidString)
            let profileID = profile.id, foreignID = foreignProfile.id
            here = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profileID)
            there = BrowserSpace(id: UUID(), name: "There", symbol: "circle", color: "FEDCBA", profileID: profileID)
            elsewhere = BrowserSpace(id: UUID(), name: "Elsewhere", symbol: "circle", color: "123456", profileID: foreignID)
            outer = BrowserFolder(id: UUID(), spaceID: here.id, name: "Outer")
            nested = BrowserFolder(id: UUID(), spaceID: here.id, name: "Nested", parentID: outer.id, isExpanded: false)
            target = BrowserFolder(id: UUID(), spaceID: here.id, name: "Target")
            let hereID = here.id
            func tab(_ title: String, kind: TabKind = .pinned, folder: UUID? = nil, url: String? = nil) -> BrowserTab {
                let url = url ?? "https://saved.invalid/" + title
                return .init(id: UUID(), spaceID: hereID, profileID: profileID, url: url, title: title, kind: kind, folderID: folder,
                             createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
            }
            noteID = URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")
            loose = tab("Loose"); today = tab("Today", kind: .today); favorite = tab("Favorite", kind: .favorite)
            inOuter = tab("InOuter", folder: outer.id); inNested = tab("InNested", folder: nested.id)
            pairA = tab("PairA", folder: nested.id); pairB = tab("PairB", folder: nested.id)
            rootA = tab("RootA"); rootB = tab("RootB"); note = tab("Note", url: InternalPage.note(noteID).urlString)
            nestedSplit = BrowserSplitLayout(sidebarAnchorID: pairA.id, spaceID: here.id, tabIDs: [pairA.id, pairB.id], widthFactors: [0.5, 0.5])
            rootSplit = BrowserSplitLayout(sidebarAnchorID: rootA.id, customTitle: "Root pair", spaceID: here.id,
                                           tabIDs: [rootA.id, rootB.id], widthFactors: [0.3, 0.7])
            var state = BrowserState(profiles: [profile, foreignProfile], spaces: [here, there, elsewhere], activeSpaceID: here.id)
            state.folders = [outer, nested, target]
            state.tabs = [loose, today, favorite, inOuter, inNested, pairA, pairB, rootA, rootB, note]
            state.splitLayouts = [nestedSplit, rootSplit]
            pinned = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .pinned)
            todayLocation = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .today)
            outerLocation = SidebarContainerLocation(spaceID: here.id, folderID: outer.id, section: .pinned)
            let nestedLocation = SidebarContainerLocation(spaceID: here.id, folderID: nested.id, section: .pinned)
            targetLocation = SidebarContainerLocation(spaceID: here.id, folderID: target.id, section: .pinned)
            therePinned = SidebarContainerLocation(spaceID: there.id, folderID: nil, section: .pinned)
            elsewherePinned = SidebarContainerLocation(spaceID: elsewhere.id, folderID: nil, section: .pinned)
            favorites = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .favorite, profileID: profile.id)
            state.sidebarItemOrder[pinned.key] = [.tab(loose.id), .folder(outer.id), .tab(rootA.id), .tab(note.id), .folder(target.id)]
            state.sidebarItemOrder[outerLocation.key] = [.folder(nested.id), .tab(inOuter.id)]
            state.sidebarItemOrder[nestedLocation.key] = [.tab(inNested.id), .tab(pairA.id)]
            try SidebarSplitCopyTestsSupport.write(state, to: root)
            store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1000) })
            initial = store.state
            noteDocs = [note.id: SidebarDocumentReference(page: .note(noteID), profileID: profile.id) {}]
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func copy(_ items: [SidebarItemReference]) -> SidebarItemsCopy? {
            SidebarItemsCopy(items: items, spaceID: here.id, profileID: profile.id, state: store.state)
        }

        func sources(_ copy: SidebarItemsCopy) -> [UUID: String] { Dictionary(uniqueKeysWithValues: copy.tabs.map { ($0.id, $0.savedURL) }) }

        func documents(_ copy: SidebarItemsCopy) -> [UUID: SidebarDocumentReference] { copy.tabs.contains { $0.id == note.id } ? noteDocs : [:] }

        func can(_ items: [SidebarItemReference], _ destination: SidebarContainerLocation, before: SidebarItemReference? = nil) -> Bool {
            guard let made = copy(items) else { return false }
            return store.canCopySidebarItems(made, to: destination, before: before, destinations: sources(made), documents: documents(made))
        }

        func place(_ items: [SidebarItemReference], _ destination: SidebarContainerLocation,
                   before: SidebarItemReference? = nil) throws -> SidebarDuplicateResult {
            let made = try #require(copy(items))
            return try #require(try store.copySidebarItems(made, to: destination, before: before, destinations: sources(made), documents: documents(made)))
        }

        func children(_ location: SidebarContainerLocation) -> [SidebarItemReference] { SidebarHierarchy.children(in: location, state: store.state) }

        func folderLocation(_ id: UUID, space: UUID? = nil) -> SidebarContainerLocation {
            .init(spaceID: space ?? here.id, folderID: id, section: .pinned)
        }
    }
}
