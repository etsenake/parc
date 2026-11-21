import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SplitStacksTests {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static func close(_ left: [Double], _ right: [Double]) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    static func stacked(_ ids: [UUID], space: UUID, sizes: [Int], slots: [Double], stacks: [[Double]],
                        orientation: SplitOrientation = .horizontal, title: String? = nil) -> BrowserSplitLayout {
        let value = BrowserSplitStacks(slotSizes: sizes, slotFactors: slots, stackFactors: stacks)
        return BrowserSplitLayout(id: UUID(), sidebarAnchorID: ids.first, customTitle: title, spaceID: space, tabIDs: ids,
                                  orientation: orientation, widthFactors: value.flattenedFactors, stacks: value)
    }
    @Test static func flatSplitsStayByteIdentical() throws {
        let flat = BrowserSplitLayout(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
            sidebarAnchorID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!, customTitle: "Pair",
            spaceID: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            tabIDs: [UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!, UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!],
            orientation: .vertical, widthFactors: [0.25, 0.75], stacks: nil)
        let previousBuild = """
        {
          "customTitle" : "Pair",
          "id" : "00000000-0000-0000-0000-0000000000C1",
          "orientation" : "vertical",
          "sidebarAnchorID" : "00000000-0000-0000-0000-0000000000B2",
          "spaceID" : "00000000-0000-0000-0000-0000000000A1",
          "tabIDs" : [
            "00000000-0000-0000-0000-0000000000B1",
            "00000000-0000-0000-0000-0000000000B2"
          ],
          "widthFactors" : [
            0.25,
            0.75
          ]
        }
        """
        let written = String(decoding: try encoder.encode(flat), as: UTF8.self)
        #expect(written == previousBuild, "A flat split saves exactly the bytes the previous build wrote, with no stacks key")
        let read = try JSONDecoder().decode(BrowserSplitLayout.self, from: Data(previousBuild.utf8))
        #expect(read == flat && read.stacks == nil, "The previous build's flat split reads back unchanged")
        #expect(String(decoding: try encoder.encode(read), as: UTF8.self) == previousBuild, "Reading and saving a flat split is byte-identical")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-stacks-flat-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let a = store.open("https://a.test"), b = store.open("https://b.test"), c = store.open("https://c.test")
        store.setSplit([a, b, c])
        try store.save()
        let session = root.appendingPathComponent("session.json")
        let first = try Data(contentsOf: session)
        let reopened = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        try reopened.save()
        let second = try Data(contentsOf: session)
        let layouts = (try JSONSerialization.jsonObject(with: first) as? [String: Any])?["splitLayouts"] as? [[String: Any]] ?? []
        #expect(layouts.count == 1 && layouts.allSatisfy { $0["stacks"] == nil }, "A flat split in session.json carries no stacks key")
        #expect(first == second && reopened.state.splitLayouts == store.state.splitLayouts,
                   "A flat session survives a reload and save byte for byte")
    }

    @Test static func stackedSplitsRoundTripAndOlderBuildsReadThemFlat() throws {
        struct PreviousBuildLayout: Codable {
            var id: UUID?, sidebarAnchorID: UUID?, customTitle: String?, spaceID: UUID
            var tabIDs: [UUID], orientation: SplitOrientation?, widthFactors: [Double]
        }
        let space = UUID(), ids = [UUID(), UUID(), UUID()]
        let layout = stacked(ids, space: space, sizes: [1, 2], slots: [0.5, 0.5], stacks: [[1], [0.25, 0.75]], title: "Trio")
        let data = try encoder.encode(layout)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["stacks"] != nil, "A stacked split saves its stacks")
        #expect(close(layout.widthFactors, [0.5, 0.125, 0.375]) && layout.widthFactors.reduce(0, +) == 1,
                   "Width factors stay a valid flat row for older builds")
        let read = try JSONDecoder().decode(BrowserSplitLayout.self, from: data)
        #expect(read == layout, "A stacked split reads back unchanged")

        let older = try JSONDecoder().decode(PreviousBuildLayout.self, from: data)
        #expect(older.tabIDs == ids && BrowserSplitLayout.normalized(older.widthFactors, count: 3) != nil
                   && abs(older.widthFactors.reduce(0, +) - 1) < 1e-9,
                   "An older build reads a stacked split as one flat row that passes its own checks")
        let olderSave = try JSONEncoder().encode(older)
        let afterOlder = try JSONDecoder().decode(BrowserSplitLayout.self, from: olderSave)
        #expect(afterOlder.stacks == nil && afterOlder.tabIDs == ids && close(afterOlder.widthFactors, layout.widthFactors),
                   "After an older build saves, the split comes back flat with every pane")

        let profile = BrowserProfile(id: UUID(), name: "Profile")
        let home = BrowserSpace(id: space, name: "Home", symbol: "circle", color: "000000", profileID: profile.id)
        var state = BrowserState(profiles: [profile], spaces: [home], activeSpaceID: space)
        state.tabs = ids.map { BrowserTab(id: $0, spaceID: space, profileID: profile.id, url: "https://x.test", title: "X",
                                          kind: .today, createdAt: Date(), lastAccessed: Date(), savedURL: "https://x.test", savedTitle: "X") }
        state.splitLayouts = [layout]
        try BrowserStore.validateSaved(state)
        #expect(true, "Whole-session validation accepts a stacked split")
    }

    @Test static func corruptStacksLoadFlat() throws {
        let space = UUID(), ids = [UUID(), UUID(), UUID()]
        let flat = BrowserSplitLayout(spaceID: space, tabIDs: ids, widthFactors: [0.25, 0.25, 0.5])
        let base = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(flat)) as! [String: Any]
        let variants: [(Any, String)] = [
            (["slotSizes": [1, 1, 1], "slotFactors": [0.3, 0.3, 0.4], "stackFactors": [[1], [1], [1]]], "no stack of two or more"),
            (["slotSizes": [2, 2], "slotFactors": [0.5, 0.5], "stackFactors": [[0.5, 0.5], [0.5, 0.5]]], "wrong pane count"),
            (["slotSizes": [3], "slotFactors": [1], "stackFactors": [[0.3, 0.3, 0.4]]], "a single slot"),
            (["slotSizes": [1, 2], "slotFactors": [0.5, 0.5], "stackFactors": [[1], [[0.5], [0.5]]]], "a third level"),
            (["slotSizes": [1, 2], "slotFactors": [-1, 2], "stackFactors": [[1], [0.5, 0.5]]], "a negative weight"),
            (["slotSizes": [1, 2], "slotFactors": [0.5, 0.5], "stackFactors": [[1], [0, 1]]], "a zero weight"),
            (["slotSizes": [1, 2], "slotFactors": [0.5, 0.5], "stackFactors": [[1], [1]]], "a short stack"),
            (["slotSizes": [1, 2], "slotFactors": [1], "stackFactors": [[1], [0.5, 0.5]]], "missing slot weights"),
            (["slotSizes": [Int.max, 1], "slotFactors": [0.5, 0.5], "stackFactors": [[1], [1]]], "an absurd size"),
            ("garbage", "the wrong type"),
            (["slotSizes": [1, 2], "slotFactors": [1, 1e-200], "stackFactors": [[1], [1, 1e-200]]], "a flat row that underflows"),
        ]
        for (stacks, reason) in variants {
            var json = base
            json["stacks"] = stacks
            let read = try JSONDecoder().decode(BrowserSplitLayout.self, from: try JSONSerialization.data(withJSONObject: json))
            #expect(read.stacks == nil && read.tabIDs == ids && read.widthFactors == flat.widthFactors,
                       "Stacks with \(reason) load as a flat split")
        }
        var unsettled = base
        unsettled["stacks"] = ["slotSizes": [2, 1], "slotFactors": [1, 3], "stackFactors": [[2, 2], [5]]]
        unsettled["widthFactors"] = [-1, 0, 7]
        let fixed = try JSONDecoder().decode(BrowserSplitLayout.self, from: try JSONSerialization.data(withJSONObject: unsettled))
        #expect(fixed.stacks == BrowserSplitStacks(slotSizes: [2, 1], slotFactors: [0.25, 0.75], stackFactors: [[0.5, 0.5], [1]])
                   && close(fixed.widthFactors, [0.125, 0.125, 0.75]),
                   "Valid stacks with unnormalised weights settle and rebuild the flat row")

        var drifting = base
        drifting["stacks"] = ["slotSizes": [1, 2], "slotFactors": [0.5, 0.5000000009], "stackFactors": [[1], [0.5, 0.5000000009]]]
        let drift = try JSONDecoder().decode(BrowserSplitLayout.self, from: try JSONSerialization.data(withJSONObject: drifting))
        #expect(drift.stacks?.slotSizes == [1, 2] && abs(drift.widthFactors.reduce(0, +) - 1) < 1e-12
                   && BrowserSplitLayout.normalized(drift.widthFactors, count: 3) != nil,
                   "Weights that only nearly sum to one settle, so the rebuilt flat row stays valid")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-stacks-corrupt-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = BrowserProfile(id: UUID(), name: "Profile")
        let home = BrowserSpace(id: space, name: "Home", symbol: "circle", color: "000000", profileID: profile.id)
        var state = BrowserState(profiles: [profile], spaces: [home], activeSpaceID: space)
        state.tabs = ids.map { BrowserTab(id: $0, spaceID: space, profileID: profile.id, url: "https://x.test", title: "X",
                                          kind: .today, createdAt: Date(), lastAccessed: Date(), savedURL: "https://x.test", savedTitle: "X") }
        state.splitLayouts = [flat]; state.selectedTabIDs = ids; state.selectionBySpace = [space.uuidString: ids]
        var session = try JSONSerialization.jsonObject(with: try encoder.encode(state)) as! [String: Any]
        var layouts = session["splitLayouts"] as! [[String: Any]]
        layouts[0]["stacks"] = ["slotSizes": [1, 2], "slotFactors": [0.5, 0.5], "stackFactors": [[1], [[0.5], [0.5]]]]
        session["splitLayouts"] = layouts
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: session).write(to: root.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        #expect(store.state.tabs.map(\.id) == ids && store.state.splitLayouts.count == 1
                   && store.state.splitLayouts[0].tabIDs == ids && store.state.splitLayouts[0].stacks == nil,
                   "A session with corrupt stacks still opens, with that split flat")
    }

    @Test static func modelEdits() throws {
        let space = UUID(), a = UUID(), b = UUID(), c = UUID(), x = UUID(), y = UUID()
        let pair = BrowserSplitLayout(spaceID: space, tabIDs: [a, b], widthFactors: [0.4, 0.6])
        let trio = pair.insertingIntoStack(x, besidePaneAt: 0, after: true)!
        #expect(trio.tabIDs == [a, x, b] && trio.orientation == .horizontal
                   && trio.stacks == BrowserSplitStacks(slotSizes: [2, 1], slotFactors: [0.4, 0.6], stackFactors: [[0.5, 0.5], [1]]),
                   "Adding below a pane of a flat split creates a stack inside that pane's column")
        let above = pair.insertingIntoStack(x, besidePaneAt: 1, after: false)!
        #expect(above.tabIDs == [a, x, b] && above.stacks?.slotSizes == [1, 2], "Adding above a pane puts the new pane first in its stack")
        let quad = trio.insertingIntoStack(y, besidePaneAt: 1, after: true)!
        #expect(quad.tabIDs == [a, x, y, b] && quad.stacks?.slotSizes == [3, 1]
                   && close(quad.stacks!.stackFactors[0], [1.0 / 3, 1.0 / 3, 1.0 / 3]),
                   "A pane already in a stack adds to that same stack")
        #expect(quad.insertingIntoStack(UUID(), besidePaneAt: 0, after: true) == nil, "No stack insert at four panes")
        #expect(BrowserSplitLayout(spaceID: space, tabIDs: [a], widthFactors: [1]).insertingIntoStack(x, besidePaneAt: 0, after: true) == nil,
                   "A single page can't be stacked")

        #expect(quad.position(of: y)?.slot == 0 && quad.position(of: y)?.index == 2 && quad.paneID(slot: 1, index: 0) == b && quad.slotRange(0) == 0..<3
                   && quad.slotBoundaries == [0, 3, 4] && quad.mainRowInsertionIndex(after: x) == 3
                   && pair.mainRowInsertionIndex(after: a) == 1 && pair.slotBoundaries == [0, 1, 2],
                   "Reading order runs slot by slot, then down each stack")

        var collapsed = trio
        collapsed.removePane(at: 1)
        #expect(collapsed.tabIDs == [a, b] && collapsed.stacks == nil && collapsed.widthFactors == [0.4, 0.6]
                   && collapsed.orientation == .horizontal, "A stack left with one pane becomes an ordinary slot")
        var column = trio
        column.removePane(at: 2)
        #expect(column.tabIDs == [a, x] && column.stacks == nil && column.orientation == .vertical && column.widthFactors == [0.5, 0.5],
                   "A split left with a single stacked column becomes a flat split in the stack's direction")
        var smaller = quad
        smaller.removePane(at: 0)
        #expect(smaller.tabIDs == [x, y, b] && smaller.stacks?.slotSizes == [2, 1] && close(smaller.stacks!.stackFactors[0], [0.5, 0.5]),
                   "Removing from a stack of three keeps a stack of two")
        #expect(BrowserSplitLayout.focusSuccessor(smaller.tabIDs, removedAt: 0) == x,
                   "The focus successor is the pane now at the old reading-order index")
        var flatRemoval = BrowserSplitLayout(spaceID: space, tabIDs: [a, b, c], widthFactors: [0.2, 0.3, 0.5])
        flatRemoval.removePane(at: 1)
        #expect(flatRemoval.tabIDs == [a, c] && flatRemoval.widthFactors == [0.2, 0.5], "A flat removal is untouched")

        let wide = stacked([a, b, c], space: space, sizes: [1, 2], slots: [0.3, 0.7], stacks: [[1], [0.25, 0.75]])
        let slotMove = wide.movingSlot(of: b, by: -1)!
        #expect(slotMove.tabIDs == [b, c, a] && slotMove.stacks?.slotSizes == [2, 1] && slotMove.stacks?.slotFactors == [0.7, 0.3]
                   && slotMove.stacks?.stackFactors == [[0.25, 0.75], [1]], "Moving along the main row moves the pane's whole slot")
        #expect(wide.movingSlot(of: a, by: 1)?.tabIDs == [b, c, a] && wide.movingSlot(of: a, by: -1) == nil,
                   "A pane alone in its slot moves its slot")
        let inner = wide.movingWithinStack(c, by: -1)!
        #expect(inner.tabIDs == [a, c, b] && inner.stacks?.stackFactors == [[1], [0.75, 0.25]] && inner.stacks?.slotFactors == [0.3, 0.7],
                   "Moving across reorders within the stack")
        #expect(wide.movingWithinStack(a, by: 1) == nil && wide.movingWithinStack(b, by: -1) == nil, "Moving across needs a stack neighbour")

        let turned = wide.transposed()
        #expect(turned.orientation == .vertical && turned.stacks == wide.stacks && turned.tabIDs == wide.tabIDs
                   && turned.transposed() == wide, "Convert transposes both levels together and keeps reading order")

        let expanded = wide.expanded(focusing: c)!
        #expect(expanded.stacks!.slotFactors[1] > 0.999 && expanded.stacks!.stackFactors[1][1] > 0.999
                   && expanded.stacks!.stackFactors[0] == [1], "Expand gives the focused pane the maximum share on both levels")
        #expect(pair.expanded(focusing: a)?.widthFactors == pair.expandedFactors(focusing: a), "A flat Expand keeps today's factors")
        let even = wide.equalized()!
        #expect(even.stacks == BrowserSplitStacks(slotSizes: [1, 2], slotFactors: [0.5, 0.5], stackFactors: [[1], [0.5, 0.5]]),
                   "Make All Equal evens the slots, then each stack")
        #expect(BrowserSplitLayout(spaceID: space, tabIDs: [a, b, c], widthFactors: [0.2, 0.3, 0.5]).equalized()?.widthFactors
                   == BrowserSplitLayout.normalized([1, 1, 1], count: 3), "A flat Make All Equal keeps today's factors")
        let quadStack = stacked([a, x, y, b], space: space, sizes: [3, 1], slots: [0.5, 0.5], stacks: [[0.2, 0.3, 0.5], [1]])
        let pairResize = quadStack.resizingDivider(1, inSlot: 0, leadingShare: 0.5)!
        #expect(close(pairResize.stacks!.stackFactors[0], [0.2, 0.4, 0.4]) && pairResize.stacks!.slotFactors == [0.5, 0.5],
                   "A stack divider resizes only its two neighbours")
        let mainResize = quadStack.resizingDivider(0, inSlot: nil, leadingShare: 0.25)!
        #expect(close(mainResize.stacks!.slotFactors, [0.25, 0.75]) && mainResize.stacks!.stackFactors == quadStack.stacks!.stackFactors,
                   "A main-row divider resizes only its two slots")
        #expect(quadStack.resizingDivider(2, inSlot: 0, leadingShare: 0.5) == nil && quadStack.resizingDivider(0, inSlot: 1, leadingShare: 0.5) == nil
                   && quadStack.resizingDivider(0, inSlot: 0, leadingShare: 1) == nil, "Dividers that don't exist refuse")
        #expect(close(quadStack.resizingStack(0, factors: [1, 1, 2])!.stacks!.stackFactors[0], [0.25, 0.25, 0.5])
                   && quadStack.resizingSlots([1, 3])!.stacks!.slotFactors == [0.25, 0.75], "Stack and slot weights normalise")

        var subset = BrowserSplitLayout(id: quadStack.id, spaceID: space, tabIDs: [x, y, b], widthFactors: [0.3, 0.3, 0.4], stacks: nil)
        subset.restack(from: quadStack)
        #expect(subset.stacks?.slotSizes == [2, 1] && subset.stacks?.slotFactors == [0.5, 0.5], "A projection keeps a surviving stack")
        var broken = BrowserSplitLayout(id: quadStack.id, spaceID: space, tabIDs: [a, b, y], widthFactors: [0.3, 0.3, 0.4], stacks: nil)
        broken.restack(from: quadStack)
        #expect(broken.stacks == nil && broken.tabIDs == [a, b, y] && broken.widthFactors.count == 3,
                   "A reordered projection that splits a stack drops to flat")
        var untouched = BrowserSplitLayout(spaceID: space, tabIDs: [b, a], widthFactors: [0.6, 0.4])
        untouched.restack(from: pair)
        #expect(untouched.widthFactors == [0.6, 0.4] && untouched.stacks == nil, "Restacking from a flat split changes nothing")
    }

    static func fixture(_ name: String, orientation: SplitOrientation = .horizontal) throws
        -> (store: BrowserStore, root: URL, profile: BrowserProfile, space: BrowserSpace, ids: [UUID], layout: BrowserSplitLayout) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-stacks-\(name)-" + UUID().uuidString)
        let profile = BrowserProfile(id: UUID(), name: "Profile")
        let space = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "000000", profileID: profile.id)
        let ids = [UUID(), UUID(), UUID()]
        let layout = stacked(ids, space: space.id, sizes: [1, 2], slots: [0.5, 0.5], stacks: [[1], [0.25, 0.75]],
                             orientation: orientation, title: "Trio")
        var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
        state.tabs = ids.enumerated().map { index, id in
            BrowserTab(id: id, spaceID: space.id, profileID: profile.id, url: "https://\(index).test/", title: "T\(index)",
                       kind: .today, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                       savedURL: "https://\(index).test/", savedTitle: "T\(index)")
        }
        state.splitLayouts = [layout]; state.selectedTabIDs = ids
        state.selectionBySpace = [space.id.uuidString: ids]
        state.sidebarItemOrder[SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .today).key] = [.tab(ids[0])]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(state).write(to: root.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        return (store, root, profile, space, ids, layout)
    }

    @Test static func storeEdits() throws {
        let f = try fixture("edits")
        defer { try? FileManager.default.removeItem(at: f.root) }
        let store = f.store, a = f.ids[0], b = f.ids[1], c = f.ids[2]
        #expect(store.activeSplitLayout == f.layout, "A stacked split loads and stays the active split")

        #expect(store.moveSplitPane(a, offset: 1, expected: store.activeSplitLayout!), "Move along the main row commits")
        #expect(store.state.selectedTabIDs == [b, c, a] && store.activeSplitLayout?.stacks?.slotSizes == [2, 1],
                   "Moving a lone pane moves its slot past the whole stack")
        #expect(!store.moveSplitPane(b, offset: -1, expected: store.activeSplitLayout!), "The first slot can't move earlier")
        #expect(store.moveSplitPaneWithinStack(c, offset: -1, expected: store.activeSplitLayout!)
                   && store.state.selectedTabIDs == [c, b, a], "Move across reorders the stack and the selection")
        #expect(!store.moveSplitPaneWithinStack(a, offset: -1, expected: store.activeSplitLayout!), "A lone pane has no stack to move in")

        let beforeFlip = store.activeSplitLayout!
        #expect(store.flipSplitOrientation(expected: beforeFlip), "Convert commits")
        #expect(store.activeSplitLayout?.orientation == .vertical && store.activeSplitLayout?.stacks == beforeFlip.stacks,
                   "Convert keeps the stacks perpendicular")
        #expect(store.setSplitLayout(orientation: .horizontal, widthFactors: store.activeSplitLayout!.widthFactors)
                   && store.activeSplitLayout?.orientation == .horizontal && store.activeSplitLayout?.stacks == beforeFlip.stacks,
                   "The orientation command keeps the stacks")

        let current = store.activeSplitLayout!
        #expect(!store.resizeSplit(expected: current, widthFactors: [0.2, 0.3, 0.5]) && store.activeSplitLayout == current,
                   "A flat resize can't flatten a stacked split")
        #expect(store.resizeSplit(expected: current, resized: current.expanded(focusing: b)!)
                   && store.activeSplitLayout!.stacks!.slotFactors[0] > 0.999 && store.activeSplitLayout!.stacks!.stackFactors[0][1] > 0.999,
                   "Expand commits on both levels")
        #expect(store.resizeSplit(expected: store.activeSplitLayout!, resized: store.activeSplitLayout!.equalized()!)
                   && store.activeSplitLayout?.stacks?.slotFactors == [0.5, 0.5] && store.activeSplitLayout?.stacks?.stackFactors == [[0.5, 0.5], [1]],
                   "Make All Equal commits")
        let equal = store.activeSplitLayout!
        #expect(store.resizeSplit(expected: equal, resized: equal.resizingDivider(0, inSlot: 0, leadingShare: 0.25)!)
                   && store.activeSplitLayout?.stacks?.stackFactors[0] == [0.25, 0.75], "A stack divider resize commits")
        var stranger = store.activeSplitLayout!.transposed()
        #expect(!store.resizeSplit(expected: store.activeSplitLayout!, resized: stranger), "A resize can't change orientation")
        stranger = store.activeSplitLayout!.movingSlot(of: a, by: -1)!
        #expect(!store.resizeSplit(expected: store.activeSplitLayout!, resized: stranger), "A resize can't change panes or slots")

        let addRight = SplitPaneInsertion(paneID: c, operation: .addAfter, state: store.state)
        let addLeft = SplitPaneInsertion(paneID: b, operation: .addBefore, state: store.state)
        #expect(addRight?.index == 2 && addRight?.target == .insert(2) && addLeft?.index == 0,
                   "Add Left and Add Right on a stacked pane add a full-length slot beside its whole stack")
        let insertion = SplitPaneInsertion(paneID: a, stackingAfter: true, state: store.state)!
        #expect(insertion.target == .stack(2, after: true) && insertion.index == 3 && insertion.orientation == .horizontal,
                   "Split This Pane targets the pane's stack")
        let added = UUID()
        #expect(store.insertSplitPane(insertion, tabID: added, navigationURL: URL(string: "https://new.test/"), creation: nil,
                                         savedHomeIDs: [:], documents: [:]), "Split This Pane commits a new pane")
        #expect(store.state.selectedTabIDs == [c, b, a, added] && store.activeSplitLayout?.stacks?.slotSizes == [2, 2],
                   "The new pane joins the lone pane's slot as a new stack")
        #expect(SplitPaneInsertion(paneID: a, stackingAfter: true, state: store.state) == nil, "Split This Pane refuses at four panes")
        let addOperation = SplitPaneInsertion(paneID: a, operation: .addAfter, state: store.state)
        #expect(addOperation == nil, "Today's Add still refuses at four panes")

        #expect(store.separateTabFromSplit(added, expected: store.activeSplitLayout!, focusedID: added),
                   "Separate commits on a stacked pane")
        #expect(store.state.selectedTabIDs == [added] && store.state.splitLayouts.first?.tabIDs == [c, b, a]
                   && store.state.splitLayouts.first?.stacks?.slotSizes == [2, 1], "Separating collapses that stack back to one pane")
    }

    @Test static func closingCollapsesAndUndoRestores() throws {
        do {
            let f = try fixture("close")
            defer { try? FileManager.default.removeItem(at: f.root) }
            let store = f.store, a = f.ids[0], b = f.ids[1], c = f.ids[2]
            var windows = WindowClosedItems()
            let before = store.state
            let intent = ClosedItemIntent(ids: [c], state: store.state, spaceID: f.space.id, profileID: f.profile.id, focusedTabID: c)!
            store.closeTabs([c])
            windows.record(intent, in: store.state)
            let undo = ClosedTabsUndo(prompt: .clear, ids: [c], spaceID: f.space.id, profileID: f.profile.id, focusedTabID: c,
                                      before: before, after: store.state)!
            #expect(store.state.selectedTabIDs == [a, b] && store.state.splitLayouts.count == 1
                       && store.state.splitLayouts[0].stacks == nil && store.state.splitLayouts[0].widthFactors == [0.5, 0.5],
                       "Closing a stacked pane collapses its stack and keeps the column's share")
            #expect(try store.undoClosedTabs(undo, shouldCommit: { true }), "Undo restores the pane")
            #expect(store.state.splitLayouts.first?.tabIDs == [a, b, c] && store.state.splitLayouts.first?.stacks == f.layout.stacks,
                       "Undo puts the pane back in its old stack with its old share")
            store.closeTabs([c])
            let reopened = windows.next(in: store.state)
            #expect(reopened?.membership != nil, "Reopen records the pane's split")
            #expect(try store.restoreClosedItem(reopened!), "Reopen restores the pane")
            #expect(store.state.splitLayouts.first?.tabIDs == [a, b, c] && store.state.splitLayouts.first?.stacks == f.layout.stacks,
                       "Reopen Closed Tab rejoins the old stack")

            let beforeFlip = store.state
            store.closeTabs([b])
            let flipUndo = ClosedTabsUndo(prompt: .clear, ids: [b], spaceID: f.space.id, profileID: f.profile.id, focusedTabID: b,
                                          before: beforeFlip, after: store.state)!
            #expect(store.flipSplitOrientation(expected: store.activeSplitLayout!), "The survivors can be converted after a close")
            #expect(try store.undoClosedTabs(flipUndo, shouldCommit: { true }), "Undo after a convert restores the pane")
            #expect(store.state.splitLayouts.first?.tabIDs == [a, b, c] && store.state.splitLayouts.first?.orientation == .vertical
                       && store.state.splitLayouts.first?.stacks?.slotSizes == [1, 2]
                       && store.state.splitLayouts.first?.stacks?.slotFactors == [0.5, 0.5],
                       "After a convert the pane rejoins its old mate's slot in the new direction, leaving the other slot's share alone")
            #expect(store.flipSplitOrientation(expected: store.state.splitLayouts.first!), "Converting back commits")
            store.setSplit([a, b, c])

            let beforeTwo = store.state
            store.closeTabs([b, c])
            let pairUndo = ClosedTabsUndo(prompt: .clear, ids: [b, c], spaceID: f.space.id, profileID: f.profile.id, focusedTabID: nil,
                                          before: beforeTwo, after: store.state)!
            #expect(store.state.splitLayouts.isEmpty && store.state.selectedTabIDs == [a], "Closing the whole stack dissolves the split")
            #expect(try store.undoClosedTabs(pairUndo, shouldCommit: { true }), "Undo restores both panes")
            #expect(store.state.splitLayouts.first?.tabIDs == [a, b, c] && store.state.splitLayouts.first?.stacks == f.layout.stacks,
                       "Undo rebuilds the stacked shape from the dissolved split")
        }
        do {
            let f = try fixture("whole")
            defer { try? FileManager.default.removeItem(at: f.root) }
            let store = f.store
            var windows = WindowClosedItems()
            let intent = ClosedItemIntent(ids: Set(f.ids), state: store.state, spaceID: f.space.id, profileID: f.profile.id, focusedTabID: f.ids[1])!
            store.closeTabs(Set(f.ids))
            windows.record(intent, in: store.state)
            let archived = store.state.tabs.filter { f.ids.contains($0.id) }
            #expect(archived.allSatisfy { $0.archivedAt != nil && $0.archiveProvenance?.split?.stacks == f.layout.stacks },
                       "Archived panes carry the stacked shape")
            let record = windows.next(in: store.state)!
            #expect(try record.split?.stacks == f.layout.stacks && (try store.restoreClosedItem(record)),
                       "Reopening a closed stacked split restores it as one group")
            #expect(store.state.splitLayouts.first?.tabIDs == f.ids && store.state.splitLayouts.first?.stacks == f.layout.stacks,
                       "The whole group regroups in its full stacked shape")
            store.closeTabs(Set(f.ids))
            let restored = store.restoreArchivedTab(f.ids[0], destination: .previousSpace(fallbackSpaceID: f.space.id))
            #expect(restored == f.ids && store.state.splitLayouts.first?.stacks == f.layout.stacks,
                       "Restoring from the Archive brings back the stacked shape")
        }
        do {
            let f = try fixture("own-slot")
            defer { try? FileManager.default.removeItem(at: f.root) }
            let store = f.store, a = f.ids[0], b = f.ids[1], c = f.ids[2]
            let before = store.state
            store.closeTabs([a])
            let undo = ClosedTabsUndo(prompt: .clear, ids: [a], spaceID: f.space.id, profileID: f.profile.id, focusedTabID: a,
                                      before: before, after: store.state)!
            #expect(store.state.splitLayouts.first?.tabIDs == [b, c] && store.state.splitLayouts.first?.orientation == .vertical
                       && store.state.splitLayouts.first?.stacks == nil, "Closing the lone column leaves the stack as a flat split")
            #expect(try store.undoClosedTabs(undo, shouldCommit: { true }), "Undo restores the lone pane")
            let layout = store.state.splitLayouts.first
            #expect(layout?.tabIDs == [a, b, c] && layout?.stacks == f.layout.stacks && layout?.orientation == .horizontal,
                       "A pane without an old stack rejoins as its own slot beside the column it left")
        }
        do {
            let f = try fixture("reconcile")
            defer { try? FileManager.default.removeItem(at: f.root) }
            var state = f.store.state
            let index = state.tabs.firstIndex { $0.id == f.ids[2] }!
            state.tabs[index].archivedAt = Date(timeIntervalSince1970: 20)
            let layouts = BrowserStore.reconciledSplitLayouts(in: state, activeSpaceID: f.space.id)
            #expect(layouts.first?.tabIDs == [f.ids[0], f.ids[1]] && layouts.first?.stacks == nil && layouts.first?.widthFactors == [0.5, 0.5],
                       "Reconciling away a stacked pane collapses its stack")
            #expect(BrowserStore.reconciledSplitLayouts(in: f.store.state, activeSpaceID: f.space.id) == f.store.state.splitLayouts,
                       "Reconciling an intact stacked split changes nothing")
        }
    }

    @Test static func copiesCarryStacks() throws {
        let f = try fixture("copies")
        defer { try? FileManager.default.removeItem(at: f.root) }
        let store = f.store
        let urls = Dictionary(uniqueKeysWithValues: f.ids.map { ($0, "https://copy.test/" + $0.uuidString) })
        let duplicate = SidebarDuplicateTarget(items: [.split(f.layout.id)], spaceID: f.space.id, profileID: f.profile.id, state: store.state)!
        let copied = try store.duplicateSidebarItems(duplicate, destinations: urls)!
        let copy = store.state.splitLayouts.first { $0.id != f.layout.id }
        #expect(copy?.stacks == f.layout.stacks && copy?.tabIDs == copied.tabIDs && Set(copied.tabIDs).isDisjoint(with: f.ids),
                   "Duplicate carries the stacks onto fresh pane identities")
        let today = SidebarContainerLocation(spaceID: f.space.id, folderID: nil, section: .today)
        let target = SidebarItemsCopy(items: [.split(f.layout.id)], spaceID: f.space.id, profileID: f.profile.id, state: store.state)!
        let result = try store.copySidebarItems(target, to: today, before: nil, destinations: urls)
        #expect(result != nil && store.state.splitLayouts.filter { $0.stacks == f.layout.stacks }.count == 3,
                   "Option-drag copies carry the stacks")

        let profile = BrowserProfile(id: UUID(), name: "Profile")
        let space = BrowserSpace(id: UUID(), name: "Source", symbol: "circle", color: "000000", profileID: profile.id)
        let folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Destination", isExpanded: false)
        let ids = [UUID(), UUID(), UUID()]
        let layout = stacked(ids, space: space.id, sizes: [2, 1], slots: [0.4, 0.6], stacks: [[0.3, 0.7], [1]])
        var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
        state.folders = [folder]
        state.tabs = ids.map { BrowserTab(id: $0, spaceID: space.id, profileID: profile.id, url: "https://p.test", title: "P",
                                          kind: .pinned, createdAt: Date(), lastAccessed: Date(), savedURL: "https://p.test", savedTitle: "P") }
        state.splitLayouts = [layout]
        let source = CommandBarFolderMoveSource(items: [.split(layout.id)], spaceID: space.id, profileID: profile.id, state: state)!
        let move = CommandBarFolderMove.snapshot(source: source, state: state).first { $0.folder.folderID == folder.id }!
        let commandCopy = CommandBarFolderCopy(move: move, destinations: Dictionary(uniqueKeysWithValues: ids.map { ($0, "https://c.test") }),
                                               state: state, now: Date())!
        #expect(commandCopy.groups.count == 1 && commandCopy.groups[0].stacks == layout.stacks
                   && Set(commandCopy.groups[0].tabIDs).isDisjoint(with: ids), "Pin to folder copies carry the stacks onto fresh IDs")
    }

    @Test static func favoritesWindowsAndMoves() throws {
        do {
            let f = try fixture("favorite")
            defer { try? FileManager.default.removeItem(at: f.root) }
            let store = f.store, a = f.ids[0], b = f.ids[1], c = f.ids[2]
            let favoriteID = store.open("https://favorite.test/", kind: .favorite)
            store.setSplit(f.ids)
            let favorite = store.state.tabs.first { $0.id == favoriteID }!
            let request = FavoriteSplitRequest(favorite: favorite, spaceID: f.space.id, selection: f.ids, focusedID: b,
                                               state: store.state, homeIDs: [favoriteID: UUID()])!
            #expect(request.paneIDs == [a, b, c, favoriteID], "A Favorite joins after the focused pane's whole slot")
            #expect(try store.commitFavoriteSplit(request) == favoriteID, "The Favorite joins the stacked split")
            let layout = store.activeSplitLayout
            #expect(layout?.tabIDs == [a, b, c, favoriteID] && layout?.stacks?.slotSizes == [1, 2, 1]
                       && close(layout!.stacks!.stackFactors[1], [0.25, 0.75]), "Joining a Favorite keeps the stack intact")

            let pane = UUID()
            let opened = store.insertCommandBarSplit(after: b, expectedSelection: store.state.selectedTabIDs, tabID: pane,
                                                     newURL: URL(string: "https://pane.test/"))
            #expect(!opened, "Open in Split View still refuses at four panes")
        }
        do {
            let f = try fixture("command-bar")
            defer { try? FileManager.default.removeItem(at: f.root) }
            let store = f.store, a = f.ids[0], b = f.ids[1], c = f.ids[2]
            let pane = UUID()
            #expect(store.commandBarSplitHomes(after: b, expectedSelection: f.ids, tabID: pane, isNew: true) == [],
                       "Command bar homes see the main-row insertion")
            #expect(store.insertCommandBarSplit(after: b, expectedSelection: f.ids, tabID: pane, newURL: URL(string: "https://pane.test/")),
                       "Open in Split View commits")
            #expect(store.state.selectedTabIDs == [a, b, c, pane] && store.activeSplitLayout?.stacks?.slotSizes == [1, 2, 1],
                       "Open in Split View adds a main-row slot after the focused pane's stack")
        }
        do {
            let f = try fixture("drops")
            defer { try? FileManager.default.removeItem(at: f.root) }
            let store = f.store, a = f.ids[0], b = f.ids[1], c = f.ids[2]
            let other = store.open("https://other.test/")
            store.setSplit(f.ids)
            let layout = store.activeSplitLayout!
            #expect(!store.dropTabIntoSplit(other, expectedSelection: f.ids, expectedLayout: layout, target: .insert(2), orientation: .horizontal),
                       "A main-row drop inside a stack refuses")
            #expect(!store.dropTabIntoSplit(other, expectedSelection: f.ids, expectedLayout: layout, target: .insert(1), orientation: .vertical),
                       "A drop can't flip a stacked split")
            let replaced = SplitDropTransaction.make(source: other, selection: f.ids, layout: layout, target: .replace(2),
                                                     orientation: .horizontal, spaceID: f.space.id)
            #expect(replaced?.tabIDs == [a, b, other] && replaced?.stacks == layout.stacks && replaced?.id == layout.id,
                       "Replacing a stacked pane keeps its slot, stack position and weights")
            #expect(store.dropTabIntoSplit(other, expectedSelection: f.ids, expectedLayout: layout, target: .insert(1), orientation: .horizontal),
                       "A main-row drop at a slot edge commits")
            #expect(store.state.selectedTabIDs == [a, other, b, c] && store.activeSplitLayout?.stacks?.slotSizes == [1, 1, 2],
                       "The main-row drop adds a whole slot")
            store.setSplit([a, b, c])
            let back = store.activeSplitLayout
            #expect(back == nil || back?.tabIDs == [a, b, c], "Re-selecting three panes is allowed")
        }
        do {
            let f = try fixture("stack-drop")
            defer { try? FileManager.default.removeItem(at: f.root) }
            let store = f.store, a = f.ids[0], b = f.ids[1], c = f.ids[2]
            let other = store.open("https://other.test/")
            store.setSplit(f.ids)
            #expect(store.dropTabIntoSplit(other, expectedSelection: f.ids, expectedLayout: store.activeSplitLayout!,
                                              target: .stack(0, after: false), orientation: .vertical),
                       "A perpendicular drop commits")
            #expect(store.state.selectedTabIDs == [other, a, b, c] && store.activeSplitLayout?.stacks?.slotSizes == [2, 2]
                       && store.activeSplitLayout?.orientation == .horizontal, "The dropped tab stacks above the pane")
        }
        do {
            let f = try fixture("external")
            defer { try? FileManager.default.removeItem(at: f.root) }
            let store = f.store, b = f.ids[1], c = f.ids[2]
            let tab = UUID()
            #expect(try store.dropExternalURLIntoSplit(URL(string: "https://link.test/")!, tabID: tab, spaceID: f.space.id,
                profileID: f.profile.id, expectedSelection: f.ids, expectedLayout: store.activeSplitLayout!,
                target: .stack(2, after: true), orientation: .horizontal, creation: nil), "An external link drop can stack")
            #expect(store.state.selectedTabIDs == [f.ids[0], b, c, tab] && store.activeSplitLayout?.stacks?.slotSizes == [1, 3],
                       "The link joins the stack below the pane")
        }
        do {
            let f = try fixture("presentation")
            defer { try? FileManager.default.removeItem(at: f.root) }
            let a = f.ids[0], b = f.ids[1], c = f.ids[2]
            var presentation = WindowPresentation(state: f.store.state, ready: true)
            #expect(presentation.splitLayout == f.layout, "A window presents the stacked split")
            presentation.reconcile(f.store.state, available: { $0 != c })
            #expect(presentation.splitLayout?.tabIDs == [a, b] && presentation.splitLayout?.stacks == nil
                       && presentation.splitLayout?.widthFactors == [0.5, 0.5], "A window projection that breaks a stack drops to flat")
            var column = WindowPresentation(state: f.store.state, ready: true)
            column.reconcile(f.store.state, available: { $0 != a })
            #expect(column.splitLayout?.tabIDs == [b, c] && column.splitLayout?.orientation == .vertical
                       && column.splitLayout?.widthFactors == [0.25, 0.75], "A projection onto one stack shows that stack flat")
        }
        do {
            let f = try fixture("cross-space")
            defer { try? FileManager.default.removeItem(at: f.root) }
            let elsewhere = f.store.createSpace(name: "Elsewhere")
            let moved = SplitCrossSpaceAdd.relocated(f.store.state, source: f.ids[2], into: elsewhere, profileID: f.profile.id,
                                                     pane: nil, homeID: nil, now: Date())
            let left = moved?.splitLayouts.first { $0.id == f.layout.id }
            #expect(left?.tabIDs == [f.ids[0], f.ids[1]] && left?.stacks == nil, "A cross-Space move out of a stack collapses it")
        }
    }

    @Test static func arcNestedSplits() throws {
        func document(_ items: [Any], pinned: [String]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["sidebar": ["containers": [["global": [:]], [
                "items": [["P", ["id": "P", "childrenIds": pinned, "data": ["itemContainer": [:]]]]].flatMap { $0 } + items,
                "spaces": ["S", ["id": "S", "title": "Nested", "profile": ["default": true], "containerIDs": ["pinned", "P"]]],
                "topAppsContainerIDs": []]]]])
        }
        func tab(_ id: String) -> [Any] { [id, ["id": id, "data": ["tab": ["savedURL": "https://\(id.lowercased()).test/", "savedTitle": id]]]] }
        func split(_ id: String, _ children: [String], _ orientation: String, _ weights: [Any]) -> [Any] {
            [id, ["id": id, "childrenIds": children, "data": ["splitView": ["layoutOrientation": orientation, "itemWidthFactors": weights]]]]
        }
        var items: [Any] = split("G", ["A", "N"], "horizontal", ["A", 0.4, "N", 0.6]) + split("N", ["B", "C"], "vertical", ["B", 1, "C", 3])
        items += tab("A") + tab("B") + tab("C")
        let nested = try ArcSidebarImport(data: document(items, pinned: ["G"]))
        guard case let .stackedSplit(_, _, tabs, orientation, stacks)? = nested.spaces[0].pinned.first else {
            throw NSError(domain: "Arc nested split stays stacked", code: 1)
        }
        #expect(tabs.map(\.title) == ["A", "B", "C"] && orientation == .horizontal && nested.skippedItemCount == 0
                   && stacks == BrowserSplitStacks(slotSizes: [1, 2], slotFactors: [0.4, 0.6], stackFactors: [[1], [0.25, 0.75]]),
                   "A perpendicular nested Arc split becomes a stack")

        items = split("G", ["A", "N"], "horizontal", ["A", 1, "N", 1]) + split("N", ["B", "C"], "horizontal", ["B", 1, "C", 1])
        items += tab("A") + tab("B") + tab("C")
        let same = try ArcSidebarImport(data: document(items, pinned: ["G"]))
        guard case let .split(_, _, sameTabs, _, factors)? = same.spaces[0].pinned.first else {
            throw NSError(domain: "Arc same-direction split flattens", code: 1)
        }
        #expect(sameTabs.map(\.title) == ["A", "B", "C"] && close(factors, [0.5, 0.25, 0.25]),
                   "A same-direction nested Arc split joins the main row")

        items = split("G", ["A", "N"], "horizontal", []) + split("N", ["B", "M"], "vertical", []) + split("M", ["C", "D"], "horizontal", [])
        items += tab("A") + tab("B") + tab("C") + tab("D")
        let deep = try ArcSidebarImport(data: document(items, pinned: ["G"]))
        guard case let .split(_, _, deepTabs, _, _)? = deep.spaces[0].pinned.first else {
            throw NSError(domain: "Arc third level flattens", code: 1)
        }
        #expect(deepTabs.map(\.title) == ["A", "B", "C", "D"] && deep.skippedItemCount == 0,
                   "A third Arc level flattens without dropping tabs")

        items = split("G", ["A", "N", "E"], "horizontal", []) + split("N", ["B", "C", "D"], "vertical", [])
        items += tab("A") + tab("B") + tab("C") + tab("D") + tab("E")
        let crowded = try ArcSidebarImport(data: document(items, pinned: ["G"]))
        let crowdedTitles = crowded.spaces[0].pinned.flatMap { item -> [String] in
            switch item {
            case .split(_, _, let tabs, _, _), .stackedSplit(_, _, let tabs, _, _): return tabs.map(\.title)
            case .tab(let tab): return [tab.title]
            case .folder: return []
            }
        }
        #expect(crowdedTitles == ["A", "B", "C", "D", "E"], "A nested Arc split over four panes flattens and keeps every tab")

        items = split("G", ["A", "N", "E"], "horizontal", []) + split("N", [], "vertical", []) + tab("A") + tab("E")
        let hollow = try ArcSidebarImport(data: document(items, pinned: ["G"]))
        #expect(hollow.skippedItemCount == 1, "An empty nested Arc split counts as skipped")

        func favorites(_ items: [Any], top: [String]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["sidebar": ["containers": [[
                "items": [["F", ["id": "F", "childrenIds": top, "data": ["itemContainer": [:]]]]].flatMap { $0 } + items,
                "spaces": [], "topAppsContainerIDs": [["default": true], "F"]]]]])
        }
        items = tab("A0") + split("G", ["A", "N"], "horizontal", []) + split("N", ["B", "C"], "vertical", ["B", 1, "C", 3])
        items += tab("A") + tab("B") + tab("C")
        items[1] = ["id": "A0", "data": ["tab": ["savedURL": "https://a.test/", "savedTitle": "A"]]]
        let favoriteArc = try ArcSidebarImport(data: favorites(items, top: ["A0", "G"]))
        let favoriteRoot = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-stacks-arc-fav-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: favoriteRoot) }
        let favoriteStore = try BrowserStore(directory: favoriteRoot, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        _ = try favoriteStore.importArcSidebar(favoriteArc, profiles: [(.standard, "Personal")],
                                               standardProfileID: favoriteStore.state.profiles[0].id)
        let partial = favoriteStore.state.splitLayouts.first
        #expect(partial?.tabIDs.count == 2 && partial?.orientation == .vertical && partial?.stacks == nil
                   && close(partial?.widthFactors ?? [], [0.25, 0.75]),
                   "A stacked Arc Favorite whose first pane already exists keeps the rest stacked the way Arc showed it")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-stacks-arc-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        _ = try store.importArcSidebar(nested, profiles: [(.standard, "Personal")], standardProfileID: store.state.profiles[0].id)
        let imported = store.state.splitLayouts.first
        #expect(imported?.stacks == stacks && imported?.tabIDs.count == 3, "Importing the nested Arc split saves the stack")
    }
}
