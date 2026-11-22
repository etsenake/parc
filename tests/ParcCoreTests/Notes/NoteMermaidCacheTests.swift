import Foundation
import Testing
@testable import ParcCore

struct NoteMermaidCacheTests {
    @Test func normalizedLineEndingsShareTheSameRequestAndCacheKey() {
        let light = NoteMermaidTheme.note(dark: false)
        let a = NoteMermaidRequest(source: "graph TD\r\nA-->B", theme: light)
        let b = NoteMermaidRequest(source: "graph TD\nA-->B", theme: light)
        #expect(a.source == "graph TD\nA-->B" && a == b && a.key == b.key, "line endings don't split the cache")
    }

    @Test func differentDiagramSourcesHaveDifferentCacheKeys() {
        let light = NoteMermaidTheme.note(dark: false)
        let a = NoteMermaidRequest(source: "graph TD\r\nA-->B", theme: light)
        #expect(NoteMermaidRequest(source: "graph TD\nA-->C", theme: light).key != a.key, "different sources get different keys")
    }

    @Test func appearanceChangesTheRenderCacheKey() {
        let light = NoteMermaidTheme.note(dark: false)
        let dark = NoteMermaidTheme.note(dark: true)
        let a = NoteMermaidRequest(source: "graph TD\r\nA-->B", theme: light)
        #expect(NoteMermaidRequest(source: "graph TD\nA-->B", theme: dark).key != a.key, "appearance is part of the key")
    }

    @Test func pageFontChangesTheRenderCacheKey() {
        let light = NoteMermaidTheme.note(dark: false)
        let a = NoteMermaidRequest(source: "graph TD\r\nA-->B", theme: light)
        #expect(NoteMermaidRequest(source: "graph TD\nA-->B", theme: .note(dark: false, font: .serif)).key != a.key, "page fonts are part of the key")
    }

    @Test func elementIdentifiersUseTheCacheKeyAndAreCssSafe() {
        let light = NoteMermaidTheme.note(dark: false)
        let a = NoteMermaidRequest(source: "graph TD\r\nA-->B", theme: light)
        #expect(a.elementID == "parc-mermaid-" + a.key, "each drawing gets its own element id")
        #expect(a.elementID.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }, "element ids are CSS-safe")
    }

    @Test func appearanceSharesTheSameLayoutKey() {
        let light = NoteMermaidTheme.note(dark: false)
        let dark = NoteMermaidTheme.note(dark: true)
        let a = NoteMermaidRequest(source: "graph TD\r\nA-->B", theme: light)
        #expect(NoteMermaidRequest(source: "graph TD\nA-->B", theme: dark).layoutKey == a.layoutKey, "light and dark share a layout, so heights hold steady across appearances")
    }

    @Test func smallTextChangesTheLayoutKey() {
        let light = NoteMermaidTheme.note(dark: false)
        let a = NoteMermaidRequest(source: "graph TD\r\nA-->B", theme: light)
        #expect(NoteMermaidRequest(source: "graph TD\nA-->B", theme: .note(dark: false, small: true)).layoutKey != a.layoutKey, "text size changes the layout")
    }

    @Test func differentSourcesChangeTheLayoutKey() {
        let light = NoteMermaidTheme.note(dark: false)
        let a = NoteMermaidRequest(source: "graph TD\r\nA-->B", theme: light)
        #expect(NoteMermaidRequest(source: "graph TD\nA-->C", theme: light).layoutKey != a.layoutKey, "sources change the layout")
    }

    @Test func equalNormalizedRequestsHashTogether() {
        let light = NoteMermaidTheme.note(dark: false)
        let a = NoteMermaidRequest(source: "graph TD\r\nA-->B", theme: light)
        let b = NoteMermaidRequest(source: "graph TD\nA-->B", theme: light)
        #expect(Set([a, b]).count == 1, "equal requests hash together")
    }

    @Test func blankDiagramSourcesHaveNoContent() {
        #expect(NoteMermaid.hasContent(" \n graph") && !NoteMermaid.hasContent(" \n\t "), "blank sources don't draw")
    }

    @Test func diagramFingerprintsAreStableAndDistinguishSources() {
        #expect(NoteMermaid.fingerprint("a") == NoteMermaid.fingerprint("a") && NoteMermaid.fingerprint("a") != NoteMermaid.fingerprint("b"), "fingerprints are stable")
    }

    @Test func aCacheHitReturnsItsValue() {
        var cache = NoteMermaidCache<String>(capacity: 3, costLimit: 100)
        cache.insert("a", for: "a", cost: 10)
        cache.insert("b", for: "b", cost: 10)
        cache.insert("c", for: "c", cost: 10)
        #expect(cache.value(for: "a") == "a", "hits return the value")
    }

    @Test func accessingAnEntryRefreshesItForEviction() {
        var cache = NoteMermaidCache<String>(capacity: 3, costLimit: 100)
        cache.insert("a", for: "a", cost: 10)
        cache.insert("b", for: "b", cost: 10)
        cache.insert("c", for: "c", cost: 10)
        _ = cache.value(for: "a")
        cache.insert("d", for: "d", cost: 10)
        #expect(cache.peek("b") == nil && cache.count == 3, "the least recently used entry goes first")
        #expect(cache.keys == ["c", "a", "d"], "touching an entry refreshes it")
    }

    @Test func insertingOverTheCostLimitEvictsOlderEntries() {
        var cache = NoteMermaidCache<String>(capacity: 3, costLimit: 100)
        cache.insert("a", for: "a", cost: 10)
        cache.insert("b", for: "b", cost: 10)
        cache.insert("c", for: "c", cost: 10)
        _ = cache.value(for: "a")
        cache.insert("d", for: "d", cost: 10)
        cache.insert("big", for: "big", cost: 85)
        #expect(cache.totalCost <= 100 && cache.peek("big") == "big", "cost limits evict old entries but keep the new one")
    }

    @Test func anOversizedEntryCanCacheOnItsOwn() {
        var cache = NoteMermaidCache<String>(capacity: 3, costLimit: 100)
        cache.insert("a", for: "a", cost: 10)
        cache.insert("b", for: "b", cost: 10)
        cache.insert("c", for: "c", cost: 10)
        cache.insert("huge", for: "huge", cost: 500)
        #expect(cache.count == 1 && cache.peek("huge") == "huge", "an oversized entry still caches alone")
    }

    @Test func replacingAnEntryUpdatesItsCost() {
        var cache = NoteMermaidCache<String>(capacity: 3, costLimit: 100)
        cache.insert("huge", for: "huge", cost: 500)
        cache.insert("huge2", for: "huge", cost: 5)
        #expect(cache.totalCost == 5 && cache.peek("huge") == "huge2", "replacing an entry fixes its cost")
    }

    @Test func removingTheLastEntryClearsItsCost() {
        var cache = NoteMermaidCache<String>(capacity: 3, costLimit: 100)
        cache.insert("huge2", for: "huge", cost: 5)
        cache.remove("huge")
        #expect(cache.count == 0 && cache.totalCost == 0, "removing clears the cost")
    }

    @Test func clearingTheCacheRemovesTheEntriesAndTheirCost() {
        var cache = NoteMermaidCache<String>(capacity: 3, costLimit: 100)
        cache.insert("x", for: "x", cost: 1)
        cache.removeAll()
        #expect(cache.count == 0 && cache.totalCost == 0, "clearing empties everything")
    }
}
