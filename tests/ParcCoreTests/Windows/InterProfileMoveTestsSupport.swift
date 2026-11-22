import Foundation
import Testing
@testable import ParcCore

enum InterProfileMoveTestsSupport {
    struct Fixture {
        var state: BrowserState
        let p: BrowserProfile, q: BrowserProfile
        let s: BrowserSpace, d: BrowserSpace
        let today: BrowserTab, pinned: BrowserTab, g1: BrowserTab, g2: BrowserTab, sibling: BrowserTab
        let d1: BrowserTab, d2: BrowserTab
        let group: BrowserSplitLayout
        let root: SidebarContainerLocation
        let now = Date(timeIntervalSince1970: 99)

        init() {
            let p = BrowserProfile(id: UUID(), name: "Personal"), q = BrowserProfile(id: UUID(), name: "Work")
            let s = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "AABBCC", profileID: p.id)
            let d = BrowserSpace(id: UUID(), name: "Office", symbol: "circle", color: "AABBCC", profileID: q.id)
            func tab(_ space: BrowserSpace, _ kind: TabKind, _ name: String) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://live.invalid/" + name,
                    title: "Live " + name, kind: kind, folderID: nil, createdAt: Date(timeIntervalSince1970: 1),
                    lastAccessed: Date(timeIntervalSince1970: 2), savedURL: "https://saved.invalid/" + name, savedTitle: "Saved " + name)
            }
            var today = tab(s, .today, "today")
            today.referrerID = UUID()
            let pinned = tab(s, .pinned, "pinned"), sibling = tab(s, .pinned, "sibling")
            let g1 = tab(s, .today, "g1"), g2 = tab(s, .today, "g2")
            let d1 = tab(d, .today, "d1"), d2 = tab(d, .today, "d2")
            let group = BrowserSplitLayout(sidebarAnchorID: g1.id, customTitle: "Pair", spaceID: s.id, tabIDs: [g1.id, g2.id],
                                           orientation: .vertical, widthFactors: [0.4, 0.6])
            var state = BrowserState(profiles: [p, q], spaces: [s, d], activeSpaceID: d.id)
            state.tabs = [today, pinned, sibling, g1, g2, d1, d2]
            state.splitLayouts = [group]
            let root = SidebarContainerLocation(spaceID: s.id, folderID: nil, section: .pinned)
            state.sidebarItemOrder[root.key] = [.tab(sibling.id), .tab(pinned.id)]
            state.selectedTabIDs = [d1.id]
            state.selectionBySpace = [s.id.uuidString: [pinned.id], d.id.uuidString: [d1.id]]
            self.state = state
            self.p = p; self.q = q; self.s = s; self.d = d
            self.today = today; self.pinned = pinned; self.sibling = sibling; self.g1 = g1; self.g2 = g2
            self.d1 = d1; self.d2 = d2; self.group = group; self.root = root
        }

        func request(_ source: BrowserTab, target: SplitDropTarget = .insert(1), selection: [UUID]? = nil,
                     layout: BrowserSplitLayout? = nil, home: UUID = UUID(), homes: [UUID: UUID] = [:]) -> ForeignSplitDrop.Request {
            ForeignSplitDrop.Request(source: source, sourceHomeID: home, spaceID: d.id, profileID: q.id,
                selection: selection ?? [d1.id], layout: layout, target: target, orientation: .horizontal, destinationHomeIDs: homes)
        }

        func propose(_ r: ForeignSplitDrop.Request, _ state: BrowserState? = nil) -> BrowserState? {
            ForeignSplitDrop.proposal(r, state: state ?? self.state, now: now, creation: nil)
        }

        func setting(_ index: Int, url: String) -> BrowserState {
            var copy = state
            copy.tabs[index].url = url
            copy.tabs[index].savedURL = url
            return copy
        }

        func groupedDestination() -> (BrowserState, BrowserSplitLayout) {
            var grouped = state
            let layout = BrowserSplitLayout(spaceID: d.id, tabIDs: [d1.id, d2.id], orientation: .horizontal, widthFactors: [0.5, 0.5])
            grouped.splitLayouts.append(layout)
            grouped.selectedTabIDs = layout.tabIDs
            grouped.selectionBySpace[d.id.uuidString] = layout.tabIDs
            return (grouped, layout)
        }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    struct Errands {
        let other: BrowserSpace
        let tabs: [BrowserTab]
        let pair: BrowserSplitLayout
        let state: BrowserState

        init(_ f: Fixture) {
            let other = BrowserSpace(id: UUID(), name: "Errands", symbol: "circle", color: "AABBCC", profileID: f.p.id)
            let tabs = ["e1", "e2"].map { name in
                BrowserTab(id: UUID(), spaceID: other.id, profileID: f.p.id, url: "https://live.invalid/" + name, title: name, kind: .today,
                           folderID: nil, createdAt: .distantPast, lastAccessed: .distantPast, savedURL: "https://live.invalid/" + name, savedTitle: name)
            }
            let pair = BrowserSplitLayout(spaceID: other.id, tabIDs: tabs.map(\.id), orientation: .vertical, widthFactors: [0.5, 0.5])
            var same = f.state
            same.spaces.append(other)
            same.tabs += tabs
            same.splitLayouts.append(pair)
            self.other = other; self.tabs = tabs; self.pair = pair; self.state = same
        }

        func local(_ f: Fixture, _ source: BrowserTab, _ target: SplitDropTarget, _ layout: BrowserSplitLayout) -> ForeignSplitDrop.Request {
            ForeignSplitDrop.Request(source: source, sourceHomeID: UUID(), spaceID: other.id, profileID: f.p.id,
                selection: layout.tabIDs, layout: layout, target: target, orientation: .vertical, destinationHomeIDs: [:])
        }
    }

    @MainActor final class Store {
        let directory: URL
        let file: URL

        init(_ name: String) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-" + name + "-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            file = directory.appendingPathComponent("session.json")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func open(_ state: BrowserState) throws -> BrowserStore {
            try InterProfileMoveTestsSupport.encoder.encode(state).write(to: file)
            return try BrowserStore(directory: directory)
        }

        func breakWrites() throws {
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        }
    }
}
