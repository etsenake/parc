import Foundation
import Testing
@testable import ParcCore

struct SplitStacksProjectionAndImportTests {
    private typealias Fixture = SplitStacksTestsSupport.Fixture

    @MainActor @Test func aWindowPresentsTheStackedSplit() throws {
        let f = try Fixture("presentation")
        let presentation = WindowPresentation(state: f.store.state, ready: true)
        #expect(presentation.splitLayout == f.layout)
    }

    @MainActor @Test func aWindowProjectionThatBreaksAStackDropsToFlat() throws {
        let f = try Fixture("presentation")
        var presentation = WindowPresentation(state: f.store.state, ready: true)
        presentation.reconcile(f.store.state, available: { $0 != f.c })
        #expect(presentation.splitLayout?.tabIDs == [f.a, f.b])
        #expect(presentation.splitLayout?.stacks == nil)
        #expect(presentation.splitLayout?.widthFactors == [0.5, 0.5])
    }

    @MainActor @Test func aProjectionOntoOneStackShowsThatStackFlat() throws {
        let f = try Fixture("presentation")
        var column = WindowPresentation(state: f.store.state, ready: true)
        column.reconcile(f.store.state, available: { $0 != f.a })
        #expect(column.splitLayout?.tabIDs == [f.b, f.c])
        #expect(column.splitLayout?.orientation == .vertical)
        #expect(column.splitLayout?.widthFactors == [0.25, 0.75])
    }

    @MainActor @Test func aCrossSpaceMoveOutOfAStackCollapsesIt() throws {
        let f = try Fixture("cross-space")
        let elsewhere = f.store.createSpace(name: "Elsewhere")
        let moved = SplitCrossSpaceAdd.relocated(f.store.state, source: f.c, into: elsewhere, profileID: f.profile.id,
                                                 pane: nil, homeID: nil, now: Date())
        let left = moved?.splitLayouts.first { $0.id == f.layout.id }
        #expect(left?.tabIDs == [f.a, f.b])
        #expect(left?.stacks == nil)
    }

    private struct Arc {
        static func document(_ items: [Any], pinned: [String]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["sidebar": ["containers": [["global": [:]], [
                "items": [["P", ["id": "P", "childrenIds": pinned, "data": ["itemContainer": [:]]]]].flatMap { $0 } + items,
                "spaces": ["S", ["id": "S", "title": "Nested", "profile": ["default": true], "containerIDs": ["pinned", "P"]]],
                "topAppsContainerIDs": []]]]])
        }

        static func tab(_ id: String) -> [Any] { [id, ["id": id, "data": ["tab": ["savedURL": "https://\(id.lowercased()).test/", "savedTitle": id]]]] }

        static func split(_ id: String, _ children: [String], _ orientation: String, _ weights: [Any]) -> [Any] {
            [id, ["id": id, "childrenIds": children, "data": ["splitView": ["layoutOrientation": orientation, "itemWidthFactors": weights]]]]
        }

        static func nested() throws -> ArcSidebarImport {
            var items: [Any] = split("G", ["A", "N"], "horizontal", ["A", 0.4, "N", 0.6]) + split("N", ["B", "C"], "vertical", ["B", 1, "C", 3])
            items += tab("A") + tab("B") + tab("C")
            return try ArcSidebarImport(data: document(items, pinned: ["G"]))
        }
    }

    @Test func aPerpendicularNestedArcSplitBecomesAStack() throws {
        let nested = try Arc.nested()
        guard case let .stackedSplit(_, _, tabs, orientation, stacks)? = nested.spaces[0].pinned.first else {
            Issue.record("Arc nested split should stay stacked")
            return
        }
        #expect(tabs.map(\.title) == ["A", "B", "C"])
        #expect(orientation == .horizontal)
        #expect(nested.skippedItemCount == 0)
        #expect(stacks == BrowserSplitStacks(slotSizes: [1, 2], slotFactors: [0.4, 0.6], stackFactors: [[1], [0.25, 0.75]]))
    }

    @Test func aSameDirectionNestedArcSplitJoinsTheMainRow() throws {
        var items: [Any] = Arc.split("G", ["A", "N"], "horizontal", ["A", 1, "N", 1]) + Arc.split("N", ["B", "C"], "horizontal", ["B", 1, "C", 1])
        items += Arc.tab("A") + Arc.tab("B") + Arc.tab("C")
        let same = try ArcSidebarImport(data: Arc.document(items, pinned: ["G"]))
        guard case let .split(_, _, sameTabs, _, factors)? = same.spaces[0].pinned.first else {
            Issue.record("Arc same-direction split should flatten")
            return
        }
        #expect(sameTabs.map(\.title) == ["A", "B", "C"])
        #expect(SplitStacksTestsSupport.close(factors, [0.5, 0.25, 0.25]))
    }

    @Test func aThirdArcLevelFlattensWithoutDroppingTabs() throws {
        var items: [Any] = Arc.split("G", ["A", "N"], "horizontal", []) + Arc.split("N", ["B", "M"], "vertical", []) + Arc.split("M", ["C", "D"], "horizontal", [])
        items += Arc.tab("A") + Arc.tab("B") + Arc.tab("C") + Arc.tab("D")
        let deep = try ArcSidebarImport(data: Arc.document(items, pinned: ["G"]))
        guard case let .split(_, _, deepTabs, _, _)? = deep.spaces[0].pinned.first else {
            Issue.record("Arc third level should flatten")
            return
        }
        #expect(deepTabs.map(\.title) == ["A", "B", "C", "D"])
        #expect(deep.skippedItemCount == 0)
    }

    @Test func aNestedArcSplitOverFourPanesFlattensAndKeepsEveryTab() throws {
        var items: [Any] = Arc.split("G", ["A", "N", "E"], "horizontal", []) + Arc.split("N", ["B", "C", "D"], "vertical", [])
        items += Arc.tab("A") + Arc.tab("B") + Arc.tab("C") + Arc.tab("D") + Arc.tab("E")
        let crowded = try ArcSidebarImport(data: Arc.document(items, pinned: ["G"]))
        let titles = crowded.spaces[0].pinned.flatMap { item -> [String] in
            switch item {
            case .split(_, _, let tabs, _, _), .stackedSplit(_, _, let tabs, _, _): return tabs.map(\.title)
            case .tab(let tab): return [tab.title]
            case .folder: return []
            }
        }
        #expect(titles == ["A", "B", "C", "D", "E"])
    }

    @Test func anEmptyNestedArcSplitCountsAsSkipped() throws {
        let items: [Any] = Arc.split("G", ["A", "N", "E"], "horizontal", []) + Arc.split("N", [], "vertical", []) + Arc.tab("A") + Arc.tab("E")
        let hollow = try ArcSidebarImport(data: Arc.document(items, pinned: ["G"]))
        #expect(hollow.skippedItemCount == 1)
    }

    @MainActor @Test func aStackedArcFavoriteWhoseFirstPaneAlreadyExistsKeepsTheRestStackedTheWayArcShowedIt() throws {
        func favorites(_ items: [Any], top: [String]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["sidebar": ["containers": [[
                "items": [["F", ["id": "F", "childrenIds": top, "data": ["itemContainer": [:]]]]].flatMap { $0 } + items,
                "spaces": [], "topAppsContainerIDs": [["default": true], "F"]]]]])
        }
        var items: [Any] = Arc.tab("A0") + Arc.split("G", ["A", "N"], "horizontal", []) + Arc.split("N", ["B", "C"], "vertical", ["B", 1, "C", 3])
        items += Arc.tab("A") + Arc.tab("B") + Arc.tab("C")
        items[1] = ["id": "A0", "data": ["tab": ["savedURL": "https://a.test/", "savedTitle": "A"]]]
        let favoriteArc = try ArcSidebarImport(data: favorites(items, top: ["A0", "G"]))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-stacks-arc-fav-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        _ = try store.importArcSidebar(favoriteArc, profiles: [(.standard, "Personal")], standardProfileID: store.state.profiles[0].id)
        let partial = store.state.splitLayouts.first
        #expect(partial?.tabIDs.count == 2)
        #expect(partial?.orientation == .vertical)
        #expect(partial?.stacks == nil)
        #expect(SplitStacksTestsSupport.close(partial?.widthFactors ?? [], [0.25, 0.75]))
    }

    @MainActor @Test func importingTheNestedArcSplitSavesTheStack() throws {
        let nested = try Arc.nested()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-stacks-arc-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        _ = try store.importArcSidebar(nested, profiles: [(.standard, "Personal")], standardProfileID: store.state.profiles[0].id)
        guard case let .stackedSplit(_, _, _, _, stacks)? = nested.spaces[0].pinned.first else {
            Issue.record("Arc nested split should stay stacked")
            return
        }
        let imported = store.state.splitLayouts.first
        #expect(imported?.stacks == stacks)
        #expect(imported?.tabIDs.count == 3)
    }
}
