import Foundation
import Testing
@testable import ParcCore

struct EaselMindMapCopyAndExportTests {
    @MainActor @Test
    func duplicatingTheWholeMapCreatesAValidIndependentMap() throws {
        let (map, _, _) = EaselMindMapTestsSupport.starter()
        let whole = Set(map.items.map(\.id))
        let copy = try #require(EaselArrange.duplicating(whole, in: map), "a map duplicates")
        let settled = EaselMindMap.tidied(copy.document)
        #expect(EaselMindMap.tree(of: settled.items).roots.count == 2, "a duplicated map is its own map")
        #expect(EaselMindMapTestsSupport.nodes(settled).count == 6 && EaselMindMapTestsSupport.branches(settled).count == 4, "the copy keeps every node and branch")
        #expect(EaselMindMapTestsSupport.accepts(settled.items), "a duplicated map is valid")
        #expect(EaselMindMap.tree(of: settled.items).hidden.isEmpty, "nothing is hidden in an open map")
    }

    @Test
    func copyingALoneLeafMakesAPlainObject() throws {
        let (map, _, kids) = EaselMindMapTestsSupport.starter()
        let single = try #require(EaselArrange.duplicating([kids[0]], in: map), "a node duplicates")
        let lone = single.copies.compactMap { EaselMindMapTestsSupport.item($0, in: single.document) }
        #expect(lone.count == 1 && lone[0].mindMap == nil, "a lone copied leaf becomes a plain object")
    }

    @Test
    func copyingASubtreeCreatesAMapWithoutLooseBranches() throws {
        let (map, _, kids) = EaselMindMapTestsSupport.starter()
        guard let leaf = EaselMindMap.template(forChildOf: kids[0], in: map),
              let deep = EaselMindMap.adding(leaf, to: kids[0], in: map) else { Issue.record("a grandchild is added"); return }
        let below = EaselMindMap.tree(of: deep.items).nodes[kids[0]]?.children ?? []
        let grand = try #require(below.first, "the grandchild exists")
        let part = Set([kids[0], grand] + deep.items.filter { EaselMindMap.isBranch($0) && $0.endConnection?.itemID == grand }.map(\.id))
        let partial = try #require(EaselArrange.duplicating(part, in: deep), "part of a map duplicates")
        let pasted = partial.copies.compactMap { EaselMindMapTestsSupport.item($0, in: partial.document) }
        #expect(pasted.filter { $0.kind == .arrow }.allSatisfy { $0.startConnection != nil && $0.endConnection != nil },
               "pasting part of a map leaves no loose branch")
        let top = pasted.first { $0.kind != .arrow && $0.text == EaselMindMapTestsSupport.item(kids[0], in: map)?.text }
        let settledPart = EaselMindMap.tidied(partial.document)
        #expect(top.flatMap { EaselMindMapTestsSupport.item($0.id, in: settledPart) }?.mindMap?.parent == nil, "the pasted top node becomes a root")
        #expect(EaselMindMap.tree(of: settledPart.items).roots.count == 2, "the pasted piece is its own map")
    }

    @Test func mapsExportWithoutCollapsedBranchesAndWithConnectors() {
        let (start, _, kids) = EaselMindMapTestsSupport.starter()
        guard let leaf = EaselMindMap.template(forChildOf: kids[0], in: start),
              let map = EaselMindMap.adding(leaf, to: kids[0], in: start),
              let folded = EaselMindMap.settingCollapsed(true, [kids[0]], in: map) else { Issue.record("a map can fold"); return }
        let open = EaselVectorExport.svg(map.items, art: EaselVectorArt(), title: "Map")
        let closed = EaselVectorExport.svg(folded.items, art: EaselVectorArt(), title: "Map")
        #expect(open.components(separatedBy: "<path").count > closed.components(separatedBy: "<path").count, "exports leave out collapsed branches")
        #expect(EaselMindMapTestsSupport.branches(map).allSatisfy { !EaselVectorExport.element($0, art: EaselVectorArt()).isEmpty }, "branches export as connectors")
    }
}
