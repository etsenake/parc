import Foundation
import Testing
@testable import ParcCore

enum SplitStacksTestsSupport {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func close(_ left: [Double], _ right: [Double]) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    static func stacked(_ ids: [UUID], space: UUID, sizes: [Int], slots: [Double], stacks: [[Double]],
                                orientation: SplitOrientation = .horizontal, title: String? = nil) -> BrowserSplitLayout {
        let value = BrowserSplitStacks(slotSizes: sizes, slotFactors: slots, stackFactors: stacks)
        return BrowserSplitLayout(id: UUID(), sidebarAnchorID: ids.first, customTitle: title, spaceID: space, tabIDs: ids,
                                  orientation: orientation, widthFactors: value.flattenedFactors, stacks: value)
    }

    static func tabs(_ ids: [UUID], space: UUID, profile: UUID, kind: TabKind = .today, url: String = "https://x.test", title: String = "X") -> [BrowserTab] {
        ids.map { BrowserTab(id: $0, spaceID: space, profileID: profile, url: url, title: title, kind: kind,
                             createdAt: Date(), lastAccessed: Date(), savedURL: url, savedTitle: title) }
    }

    @MainActor final class Fixture {
        let store: BrowserStore
        let root: URL
        let profile: BrowserProfile
        let space: BrowserSpace
        let ids: [UUID]
        let layout: BrowserSplitLayout

        init(_ name: String, orientation: SplitOrientation = .horizontal) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-stacks-\(name)-" + UUID().uuidString)
            profile = BrowserProfile(id: UUID(), name: "Profile")
            space = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "000000", profileID: profile.id)
            ids = [UUID(), UUID(), UUID()]
            layout = SplitStacksTestsSupport.stacked(ids, space: space.id, sizes: [1, 2], slots: [0.5, 0.5], stacks: [[1], [0.25, 0.75]],
                                              orientation: orientation, title: "Trio")
            var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
            let spaceID = space.id, profileID = profile.id
            state.tabs = ids.enumerated().map { index, id in
                BrowserTab(id: id, spaceID: spaceID, profileID: profileID, url: "https://\(index).test/", title: "T\(index)",
                           kind: .today, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                           savedURL: "https://\(index).test/", savedTitle: "T\(index)")
            }
            state.splitLayouts = [layout]
            state.selectedTabIDs = ids
            state.selectionBySpace = [space.id.uuidString: ids]
            state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .today).key] = [.tab(ids[0])]
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try SplitStacksTestsSupport.encoder.encode(state).write(to: root.appendingPathComponent("session.json"))
            store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        var a: UUID { ids[0] }
        var b: UUID { ids[1] }
        var c: UUID { ids[2] }
    }
}
