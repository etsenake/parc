import Foundation
import Testing
@testable import ParcCore

struct SplitStacksTests {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static func close(_ left: [Double], _ right: [Double]) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    private static func stacked(_ ids: [UUID], space: UUID, sizes: [Int], slots: [Double], stacks: [[Double]],
                                orientation: SplitOrientation = .horizontal, title: String? = nil) -> BrowserSplitLayout {
        let value = BrowserSplitStacks(slotSizes: sizes, slotFactors: slots, stackFactors: stacks)
        return BrowserSplitLayout(id: UUID(), sidebarAnchorID: ids.first, customTitle: title, spaceID: space, tabIDs: ids,
                                  orientation: orientation, widthFactors: value.flattenedFactors, stacks: value)
    }

    private static func tabs(_ ids: [UUID], space: UUID, profile: UUID, kind: TabKind = .today, url: String = "https://x.test", title: String = "X") -> [BrowserTab] {
        ids.map { BrowserTab(id: $0, spaceID: space, profileID: profile, url: url, title: title, kind: kind,
                             createdAt: Date(), lastAccessed: Date(), savedURL: url, savedTitle: title) }
    }

    private static let flatJSON = """
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

    private static func flatLayout() -> BrowserSplitLayout {
        BrowserSplitLayout(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
            sidebarAnchorID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!, customTitle: "Pair",
            spaceID: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            tabIDs: [UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!, UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!],
            orientation: .vertical, widthFactors: [0.25, 0.75], stacks: nil)
    }

    @Test func aFlatSplitSavesExactlyTheBytesThePreviousBuildWroteWithNoStacksKey() throws {
        #expect(String(decoding: try Self.encoder.encode(Self.flatLayout()), as: UTF8.self) == Self.flatJSON)
    }

    @Test func thePreviousBuildsFlatSplitReadsBackUnchanged() throws {
        let read = try JSONDecoder().decode(BrowserSplitLayout.self, from: Data(Self.flatJSON.utf8))
        #expect(read == Self.flatLayout())
        #expect(read.stacks == nil)
    }

    @Test func readingAndSavingAFlatSplitIsByteIdentical() throws {
        let read = try JSONDecoder().decode(BrowserSplitLayout.self, from: Data(Self.flatJSON.utf8))
        #expect(String(decoding: try Self.encoder.encode(read), as: UTF8.self) == Self.flatJSON)
    }

    @MainActor private final class FlatSession {
        let root: URL
        let store: BrowserStore
        let first: Data

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-stacks-flat-" + UUID().uuidString)
            let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let a = store.open("https://a.test"), b = store.open("https://b.test"), c = store.open("https://c.test")
            store.setSplit([a, b, c])
            try store.save()
            self.store = store
            first = try Data(contentsOf: root.appendingPathComponent("session.json"))
        }

        deinit { try? FileManager.default.removeItem(at: root) }
    }

    @MainActor @Test func aFlatSplitInTheSessionFileCarriesNoStacksKey() throws {
        let s = try FlatSession()
        let layouts = (try JSONSerialization.jsonObject(with: s.first) as? [String: Any])?["splitLayouts"] as? [[String: Any]] ?? []
        #expect(layouts.count == 1)
        #expect(layouts.allSatisfy { $0["stacks"] == nil })
    }

    @MainActor @Test func aFlatSessionSurvivesAReloadAndSaveByteForByte() throws {
        let s = try FlatSession()
        let reopened = try BrowserStore(directory: s.root, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        try reopened.save()
        #expect(try Data(contentsOf: s.root.appendingPathComponent("session.json")) == s.first)
        #expect(reopened.state.splitLayouts == s.store.state.splitLayouts)
    }

    private struct PreviousBuildLayout: Codable {
        var id: UUID?, sidebarAnchorID: UUID?, customTitle: String?, spaceID: UUID
        var tabIDs: [UUID], orientation: SplitOrientation?, widthFactors: [Double]
    }

    private static let trioSpace = UUID()
    private static let trioIDs = [UUID(), UUID(), UUID()]
    private static func trio() -> BrowserSplitLayout {
        stacked(trioIDs, space: trioSpace, sizes: [1, 2], slots: [0.5, 0.5], stacks: [[1], [0.25, 0.75]], title: "Trio")
    }

    @Test func aStackedSplitSavesItsStacks() throws {
        let json = try JSONSerialization.jsonObject(with: try Self.encoder.encode(Self.trio())) as? [String: Any]
        #expect(json?["stacks"] != nil)
    }

    @Test func widthFactorsStayAValidFlatRowForOlderBuilds() {
        let layout = Self.trio()
        #expect(Self.close(layout.widthFactors, [0.5, 0.125, 0.375]))
        #expect(layout.widthFactors.reduce(0, +) == 1)
    }

    @Test func aStackedSplitReadsBackUnchanged() throws {
        let layout = Self.trio()
        #expect(try JSONDecoder().decode(BrowserSplitLayout.self, from: try Self.encoder.encode(layout)) == layout)
    }

    @Test func anOlderBuildReadsAStackedSplitAsOneFlatRowThatPassesItsOwnChecks() throws {
        let older = try JSONDecoder().decode(PreviousBuildLayout.self, from: try Self.encoder.encode(Self.trio()))
        #expect(older.tabIDs == Self.trioIDs)
        #expect(BrowserSplitLayout.normalized(older.widthFactors, count: 3) != nil)
        #expect(abs(older.widthFactors.reduce(0, +) - 1) < 1e-9)
    }

    @Test func afterAnOlderBuildSavesTheSplitComesBackFlatWithEveryPane() throws {
        let layout = Self.trio()
        let older = try JSONDecoder().decode(PreviousBuildLayout.self, from: try Self.encoder.encode(layout))
        let after = try JSONDecoder().decode(BrowserSplitLayout.self, from: try JSONEncoder().encode(older))
        #expect(after.stacks == nil)
        #expect(after.tabIDs == Self.trioIDs)
        #expect(Self.close(after.widthFactors, layout.widthFactors))
    }

    @MainActor @Test func wholeSessionValidationAcceptsAStackedSplit() throws {
        let profile = BrowserProfile(id: UUID(), name: "Profile")
        let home = BrowserSpace(id: Self.trioSpace, name: "Home", symbol: "circle", color: "000000", profileID: profile.id)
        var state = BrowserState(profiles: [profile], spaces: [home], activeSpaceID: Self.trioSpace)
        state.tabs = Self.tabs(Self.trioIDs, space: Self.trioSpace, profile: profile.id)
        state.splitLayouts = [Self.trio()]
        try BrowserStore.validateSaved(state)
    }

    private static func corruptBase() throws -> (ids: [UUID], flat: BrowserSplitLayout, base: [String: Any]) {
        let ids = [UUID(), UUID(), UUID()]
        let flat = BrowserSplitLayout(spaceID: UUID(), tabIDs: ids, widthFactors: [0.25, 0.25, 0.5])
        return (ids, flat, try JSONSerialization.jsonObject(with: try JSONEncoder().encode(flat)) as! [String: Any])
    }

    struct Corruption: Sendable, CustomTestStringConvertible {
        let reason: String
        var testDescription: String { reason }
        static let all = ["no stack of two or more", "wrong pane count", "a single slot", "a third level", "a negative weight", "a zero weight",
                          "a short stack", "missing slot weights", "an absurd size", "the wrong type", "a flat row that underflows"].map(Corruption.init)

        var stacks: Any {
            switch reason {
            case "no stack of two or more": return ["slotSizes": [1, 1, 1], "slotFactors": [0.3, 0.3, 0.4], "stackFactors": [[1], [1], [1]]]
            case "wrong pane count": return ["slotSizes": [2, 2], "slotFactors": [0.5, 0.5], "stackFactors": [[0.5, 0.5], [0.5, 0.5]]]
            case "a single slot": return ["slotSizes": [3], "slotFactors": [1], "stackFactors": [[0.3, 0.3, 0.4]]]
            case "a third level": return ["slotSizes": [1, 2], "slotFactors": [0.5, 0.5], "stackFactors": [[1], [[0.5], [0.5]]]]
            case "a negative weight": return ["slotSizes": [1, 2], "slotFactors": [-1, 2], "stackFactors": [[1], [0.5, 0.5]]]
            case "a zero weight": return ["slotSizes": [1, 2], "slotFactors": [0.5, 0.5], "stackFactors": [[1], [0, 1]]]
            case "a short stack": return ["slotSizes": [1, 2], "slotFactors": [0.5, 0.5], "stackFactors": [[1], [1]]]
            case "missing slot weights": return ["slotSizes": [1, 2], "slotFactors": [1], "stackFactors": [[1], [0.5, 0.5]]]
            case "an absurd size": return ["slotSizes": [Int.max, 1], "slotFactors": [0.5, 0.5], "stackFactors": [[1], [1]]]
            case "the wrong type": return "garbage"
            default: return ["slotSizes": [1, 2], "slotFactors": [1, 1e-200], "stackFactors": [[1], [1, 1e-200]]]
            }
        }
    }

    @Test(arguments: Corruption.all)
    func corruptStacksLoadAsAFlatSplit(_ corruption: Corruption) throws {
        let (ids, flat, base) = try Self.corruptBase()
        var json = base
        json["stacks"] = corruption.stacks
        let read = try JSONDecoder().decode(BrowserSplitLayout.self, from: try JSONSerialization.data(withJSONObject: json))
        #expect(read.stacks == nil)
        #expect(read.tabIDs == ids)
        #expect(read.widthFactors == flat.widthFactors)
    }

    @Test func validStacksWithUnnormalisedWeightsSettleAndRebuildTheFlatRow() throws {
        var unsettled = try Self.corruptBase().base
        unsettled["stacks"] = ["slotSizes": [2, 1], "slotFactors": [1, 3], "stackFactors": [[2, 2], [5]]]
        unsettled["widthFactors"] = [-1, 0, 7]
        let fixed = try JSONDecoder().decode(BrowserSplitLayout.self, from: try JSONSerialization.data(withJSONObject: unsettled))
        #expect(fixed.stacks == BrowserSplitStacks(slotSizes: [2, 1], slotFactors: [0.25, 0.75], stackFactors: [[0.5, 0.5], [1]]))
        #expect(Self.close(fixed.widthFactors, [0.125, 0.125, 0.75]))
    }

    @Test func weightsThatOnlyNearlySumToOneSettleSoTheRebuiltFlatRowStaysValid() throws {
        var drifting = try Self.corruptBase().base
        drifting["stacks"] = ["slotSizes": [1, 2], "slotFactors": [0.5, 0.5000000009], "stackFactors": [[1], [0.5, 0.5000000009]]]
        let drift = try JSONDecoder().decode(BrowserSplitLayout.self, from: try JSONSerialization.data(withJSONObject: drifting))
        #expect(drift.stacks?.slotSizes == [1, 2])
        #expect(abs(drift.widthFactors.reduce(0, +) - 1) < 1e-12)
        #expect(BrowserSplitLayout.normalized(drift.widthFactors, count: 3) != nil)
    }

    @MainActor @Test func aSessionWithCorruptStacksStillOpensWithThatSplitFlat() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-stacks-corrupt-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (ids, flat, _) = try Self.corruptBase()
        let profile = BrowserProfile(id: UUID(), name: "Profile")
        let home = BrowserSpace(id: flat.spaceID, name: "Home", symbol: "circle", color: "000000", profileID: profile.id)
        var state = BrowserState(profiles: [profile], spaces: [home], activeSpaceID: flat.spaceID)
        state.tabs = Self.tabs(ids, space: flat.spaceID, profile: profile.id)
        state.splitLayouts = [flat]
        state.selectedTabIDs = ids
        state.selectionBySpace = [flat.spaceID.uuidString: ids]
        var session = try JSONSerialization.jsonObject(with: try Self.encoder.encode(state)) as! [String: Any]
        var layouts = session["splitLayouts"] as! [[String: Any]]
        layouts[0]["stacks"] = ["slotSizes": [1, 2], "slotFactors": [0.5, 0.5], "stackFactors": [[1], [[0.5], [0.5]]]]
        session["splitLayouts"] = layouts
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: session).write(to: root.appendingPathComponent("session.json"))
        let store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        #expect(store.state.tabs.map(\.id) == ids)
        #expect(store.state.splitLayouts.count == 1)
        #expect(store.state.splitLayouts[0].tabIDs == ids)
        #expect(store.state.splitLayouts[0].stacks == nil)
    }

    private struct Model {
        let space = UUID(), a = UUID(), b = UUID(), c = UUID(), x = UUID(), y = UUID()
        var pair: BrowserSplitLayout { BrowserSplitLayout(spaceID: space, tabIDs: [a, b], widthFactors: [0.4, 0.6]) }
        var trio: BrowserSplitLayout { pair.insertingIntoStack(x, besidePaneAt: 0, after: true)! }
        var quad: BrowserSplitLayout { trio.insertingIntoStack(y, besidePaneAt: 1, after: true)! }
        var wide: BrowserSplitLayout { SplitStacksTests.stacked([a, b, c], space: space, sizes: [1, 2], slots: [0.3, 0.7], stacks: [[1], [0.25, 0.75]]) }
        var quadStack: BrowserSplitLayout { SplitStacksTests.stacked([a, x, y, b], space: space, sizes: [3, 1], slots: [0.5, 0.5], stacks: [[0.2, 0.3, 0.5], [1]]) }
    }

    @Test func addingBelowAPaneOfAFlatSplitCreatesAStackInThatPanesColumn() {
        let m = Model()
        #expect(m.trio.tabIDs == [m.a, m.x, m.b])
        #expect(m.trio.orientation == .horizontal)
        #expect(m.trio.stacks == BrowserSplitStacks(slotSizes: [2, 1], slotFactors: [0.4, 0.6], stackFactors: [[0.5, 0.5], [1]]))
    }

    @Test func addingAboveAPanePutsTheNewPaneFirstInItsStack() {
        let m = Model()
        let above = m.pair.insertingIntoStack(m.x, besidePaneAt: 1, after: false)
        #expect(above?.tabIDs == [m.a, m.x, m.b])
        #expect(above?.stacks?.slotSizes == [1, 2])
    }

    @Test func aPaneAlreadyInAStackAddsToThatSameStack() {
        let m = Model()
        #expect(m.quad.tabIDs == [m.a, m.x, m.y, m.b])
        #expect(m.quad.stacks?.slotSizes == [3, 1])
        #expect(Self.close(m.quad.stacks!.stackFactors[0], [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }

    @Test func noStackInsertAtFourPanes() {
        #expect(Model().quad.insertingIntoStack(UUID(), besidePaneAt: 0, after: true) == nil)
    }

    @Test func aSinglePageCannotBeStacked() {
        let m = Model()
        #expect(BrowserSplitLayout(spaceID: m.space, tabIDs: [m.a], widthFactors: [1]).insertingIntoStack(m.x, besidePaneAt: 0, after: true) == nil)
    }

    @Test func readingOrderRunsSlotBySlotThenDownEachStack() {
        let m = Model()
        let quad = m.quad
        #expect(quad.position(of: m.y)?.slot == 0)
        #expect(quad.position(of: m.y)?.index == 2)
        #expect(quad.paneID(slot: 1, index: 0) == m.b)
        #expect(quad.slotRange(0) == 0..<3)
        #expect(quad.slotBoundaries == [0, 3, 4])
        #expect(quad.mainRowInsertionIndex(after: m.x) == 3)
        #expect(m.pair.mainRowInsertionIndex(after: m.a) == 1)
        #expect(m.pair.slotBoundaries == [0, 1, 2])
    }

    @Test func aStackLeftWithOnePaneBecomesAnOrdinarySlot() {
        let m = Model()
        var collapsed = m.trio
        collapsed.removePane(at: 1)
        #expect(collapsed.tabIDs == [m.a, m.b])
        #expect(collapsed.stacks == nil)
        #expect(collapsed.widthFactors == [0.4, 0.6])
        #expect(collapsed.orientation == .horizontal)
    }

    @Test func aSplitLeftWithASingleStackedColumnBecomesFlatInTheStacksDirection() {
        let m = Model()
        var column = m.trio
        column.removePane(at: 2)
        #expect(column.tabIDs == [m.a, m.x])
        #expect(column.stacks == nil)
        #expect(column.orientation == .vertical)
        #expect(column.widthFactors == [0.5, 0.5])
    }

    @Test func removingFromAStackOfThreeKeepsAStackOfTwo() {
        let m = Model()
        var smaller = m.quad
        smaller.removePane(at: 0)
        #expect(smaller.tabIDs == [m.x, m.y, m.b])
        #expect(smaller.stacks?.slotSizes == [2, 1])
        #expect(Self.close(smaller.stacks!.stackFactors[0], [0.5, 0.5]))
    }

    @Test func theFocusSuccessorIsThePaneNowAtTheOldReadingOrderIndex() {
        let m = Model()
        #expect(BrowserSplitLayout.focusSuccessor([m.x, m.y, m.b], removedAt: 0) == m.x)
    }

    @Test func aFlatRemovalIsUntouched() {
        let m = Model()
        var flatRemoval = BrowserSplitLayout(spaceID: m.space, tabIDs: [m.a, m.b, m.c], widthFactors: [0.2, 0.3, 0.5])
        flatRemoval.removePane(at: 1)
        #expect(flatRemoval.tabIDs == [m.a, m.c])
        #expect(flatRemoval.widthFactors == [0.2, 0.5])
    }

    @Test func movingAlongTheMainRowMovesThePanesWholeSlot() throws {
        let m = Model()
        let slotMove = try #require(m.wide.movingSlot(of: m.b, by: -1))
        #expect(slotMove.tabIDs == [m.b, m.c, m.a])
        #expect(slotMove.stacks?.slotSizes == [2, 1])
        #expect(slotMove.stacks?.slotFactors == [0.7, 0.3])
        #expect(slotMove.stacks?.stackFactors == [[0.25, 0.75], [1]])
    }

    @Test func aPaneAloneInItsSlotMovesItsSlot() {
        let m = Model()
        #expect(m.wide.movingSlot(of: m.a, by: 1)?.tabIDs == [m.b, m.c, m.a])
        #expect(m.wide.movingSlot(of: m.a, by: -1) == nil)
    }

    @Test func movingAcrossReordersWithinTheStack() throws {
        let m = Model()
        let inner = try #require(m.wide.movingWithinStack(m.c, by: -1))
        #expect(inner.tabIDs == [m.a, m.c, m.b])
        #expect(inner.stacks?.stackFactors == [[1], [0.75, 0.25]])
        #expect(inner.stacks?.slotFactors == [0.3, 0.7])
    }

    @Test func movingAcrossNeedsAStackNeighbour() {
        let m = Model()
        #expect(m.wide.movingWithinStack(m.a, by: 1) == nil)
        #expect(m.wide.movingWithinStack(m.b, by: -1) == nil)
    }

    @Test func convertTransposesBothLevelsAndKeepsReadingOrder() {
        let wide = Model().wide
        let turned = wide.transposed()
        #expect(turned.orientation == .vertical)
        #expect(turned.stacks == wide.stacks)
        #expect(turned.tabIDs == wide.tabIDs)
        #expect(turned.transposed() == wide)
    }

    @Test func expandGivesTheFocusedPaneTheMaximumShareOnBothLevels() throws {
        let m = Model()
        let expanded = try #require(m.wide.expanded(focusing: m.c))
        #expect(expanded.stacks!.slotFactors[1] > 0.999)
        #expect(expanded.stacks!.stackFactors[1][1] > 0.999)
        #expect(expanded.stacks!.stackFactors[0] == [1])
    }

    @Test func aFlatExpandKeepsTodaysFactors() {
        let m = Model()
        #expect(m.pair.expanded(focusing: m.a)?.widthFactors == m.pair.expandedFactors(focusing: m.a))
    }

    @Test func makeAllEqualEvensTheSlotsThenEachStack() {
        #expect(Model().wide.equalized()?.stacks == BrowserSplitStacks(slotSizes: [1, 2], slotFactors: [0.5, 0.5], stackFactors: [[1], [0.5, 0.5]]))
    }

    @Test func aFlatMakeAllEqualKeepsTodaysFactors() {
        let m = Model()
        #expect(BrowserSplitLayout(spaceID: m.space, tabIDs: [m.a, m.b, m.c], widthFactors: [0.2, 0.3, 0.5]).equalized()?.widthFactors
                == BrowserSplitLayout.normalized([1, 1, 1], count: 3))
    }

    @Test func aStackDividerResizesOnlyItsTwoNeighbours() throws {
        let resize = try #require(Model().quadStack.resizingDivider(1, inSlot: 0, leadingShare: 0.5))
        #expect(Self.close(resize.stacks!.stackFactors[0], [0.2, 0.4, 0.4]))
        #expect(resize.stacks!.slotFactors == [0.5, 0.5])
    }

    @Test func aMainRowDividerResizesOnlyItsTwoSlots() throws {
        let quad = Model().quadStack
        let resize = try #require(quad.resizingDivider(0, inSlot: nil, leadingShare: 0.25))
        #expect(Self.close(resize.stacks!.slotFactors, [0.25, 0.75]))
        #expect(resize.stacks!.stackFactors == quad.stacks!.stackFactors)
    }

    @Test(arguments: [(2, 0 as Int?, 0.5), (0, 1, 0.5), (0, 0, 1.0)])
    func dividersThatDoNotExistRefuse(_ divider: Int, _ slot: Int?, _ share: Double) {
        #expect(Model().quadStack.resizingDivider(divider, inSlot: slot, leadingShare: share) == nil)
    }

    @Test func stackAndSlotWeightsNormalise() {
        let quad = Model().quadStack
        #expect(Self.close(quad.resizingStack(0, factors: [1, 1, 2])!.stacks!.stackFactors[0], [0.25, 0.25, 0.5]))
        #expect(quad.resizingSlots([1, 3])!.stacks!.slotFactors == [0.25, 0.75])
    }

    @Test func aProjectionKeepsASurvivingStack() {
        let m = Model()
        var subset = BrowserSplitLayout(id: m.quadStack.id, spaceID: m.space, tabIDs: [m.x, m.y, m.b], widthFactors: [0.3, 0.3, 0.4], stacks: nil)
        subset.restack(from: m.quadStack)
        #expect(subset.stacks?.slotSizes == [2, 1])
        #expect(subset.stacks?.slotFactors == [0.5, 0.5])
    }

    @Test func aReorderedProjectionThatSplitsAStackDropsToFlat() {
        let m = Model()
        var broken = BrowserSplitLayout(id: m.quadStack.id, spaceID: m.space, tabIDs: [m.a, m.b, m.y], widthFactors: [0.3, 0.3, 0.4], stacks: nil)
        broken.restack(from: m.quadStack)
        #expect(broken.stacks == nil)
        #expect(broken.tabIDs == [m.a, m.b, m.y])
        #expect(broken.widthFactors.count == 3)
    }

    @Test func restackingFromAFlatSplitChangesNothing() {
        let m = Model()
        var untouched = BrowserSplitLayout(spaceID: m.space, tabIDs: [m.b, m.a], widthFactors: [0.6, 0.4])
        untouched.restack(from: m.pair)
        #expect(untouched.widthFactors == [0.6, 0.4])
        #expect(untouched.stacks == nil)
    }

    @MainActor private final class Fixture {
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
            layout = SplitStacksTests.stacked(ids, space: space.id, sizes: [1, 2], slots: [0.5, 0.5], stacks: [[1], [0.25, 0.75]],
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
            try SplitStacksTests.encoder.encode(state).write(to: root.appendingPathComponent("session.json"))
            store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        var a: UUID { ids[0] }
        var b: UUID { ids[1] }
        var c: UUID { ids[2] }
    }

    @MainActor @Test func aStackedSplitLoadsAndStaysTheActiveSplit() throws {
        let f = try Fixture("edits")
        #expect(f.store.activeSplitLayout == f.layout)
    }

    @MainActor @Test func movingAlongTheMainRowCommits() throws {
        let f = try Fixture("edits")
        #expect(f.store.moveSplitPane(f.a, offset: 1, expected: f.store.activeSplitLayout!))
    }

    @MainActor @Test func movingALonePaneMovesItsSlotPastTheWholeStack() throws {
        let f = try Fixture("edits")
        _ = f.store.moveSplitPane(f.a, offset: 1, expected: f.store.activeSplitLayout!)
        #expect(f.store.state.selectedTabIDs == [f.b, f.c, f.a])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [2, 1])
    }

    @MainActor @Test func theFirstSlotCannotMoveEarlier() throws {
        let f = try Fixture("edits")
        #expect(!f.store.moveSplitPane(f.a, offset: -1, expected: f.store.activeSplitLayout!))
    }

    @MainActor @Test func movingAcrossReordersTheStackAndTheSelection() throws {
        let f = try Fixture("edits")
        #expect(f.store.moveSplitPaneWithinStack(f.c, offset: -1, expected: f.store.activeSplitLayout!))
        #expect(f.store.state.selectedTabIDs == [f.a, f.c, f.b])
    }

    @MainActor @Test func aLonePaneHasNoStackToMoveIn() throws {
        let f = try Fixture("edits")
        #expect(!f.store.moveSplitPaneWithinStack(f.a, offset: -1, expected: f.store.activeSplitLayout!))
    }

    @MainActor @Test func convertCommitsAndKeepsTheStacksPerpendicular() throws {
        let f = try Fixture("edits")
        let before = f.store.activeSplitLayout!
        #expect(f.store.flipSplitOrientation(expected: before))
        #expect(f.store.activeSplitLayout?.orientation == .vertical)
        #expect(f.store.activeSplitLayout?.stacks == before.stacks)
    }

    @MainActor @Test func theOrientationCommandKeepsTheStacks() throws {
        let f = try Fixture("edits")
        let before = f.store.activeSplitLayout!
        #expect(f.store.setSplitLayout(orientation: .vertical, widthFactors: before.widthFactors))
        #expect(f.store.activeSplitLayout?.orientation == .vertical)
        #expect(f.store.activeSplitLayout?.stacks == before.stacks)
    }

    @MainActor @Test func aFlatResizeCannotFlattenAStackedSplit() throws {
        let f = try Fixture("edits")
        let current = f.store.activeSplitLayout!
        #expect(!f.store.resizeSplit(expected: current, widthFactors: [0.2, 0.3, 0.5]))
        #expect(f.store.activeSplitLayout == current)
    }

    @MainActor @Test func expandCommitsOnBothLevels() throws {
        let f = try Fixture("edits")
        let current = f.store.activeSplitLayout!
        #expect(f.store.resizeSplit(expected: current, resized: current.expanded(focusing: f.b)!))
        #expect(f.store.activeSplitLayout!.stacks!.slotFactors[1] > 0.999)
        #expect(f.store.activeSplitLayout!.stacks!.stackFactors[1][0] > 0.999)
    }

    @MainActor @Test func makeAllEqualCommits() throws {
        let f = try Fixture("edits")
        let current = f.store.activeSplitLayout!
        #expect(f.store.resizeSplit(expected: current, resized: current.equalized()!))
        #expect(f.store.activeSplitLayout?.stacks?.slotFactors == [0.5, 0.5])
        #expect(f.store.activeSplitLayout?.stacks?.stackFactors == [[1], [0.5, 0.5]])
    }

    @MainActor @Test func aStackDividerResizeCommits() throws {
        let f = try Fixture("edits")
        let current = f.store.activeSplitLayout!
        #expect(f.store.resizeSplit(expected: current, resized: current.resizingDivider(0, inSlot: 1, leadingShare: 0.25)!))
        #expect(f.store.activeSplitLayout?.stacks?.stackFactors[1] == [0.25, 0.75])
    }

    @MainActor @Test func aResizeCannotChangeOrientation() throws {
        let f = try Fixture("edits")
        let current = f.store.activeSplitLayout!
        #expect(!f.store.resizeSplit(expected: current, resized: current.transposed()))
    }

    @MainActor @Test func aResizeCannotChangePanesOrSlots() throws {
        let f = try Fixture("edits")
        let current = f.store.activeSplitLayout!
        #expect(!f.store.resizeSplit(expected: current, resized: current.movingSlot(of: f.a, by: 1)!))
    }

    @MainActor @Test func addLeftAndAddRightOnAStackedPaneAddAFullLengthSlotBesideItsWholeStack() throws {
        let f = try Fixture("edits")
        let addRight = SplitPaneInsertion(paneID: f.c, operation: .addAfter, state: f.store.state)
        let addLeft = SplitPaneInsertion(paneID: f.b, operation: .addBefore, state: f.store.state)
        #expect(addRight?.index == 3)
        #expect(addRight?.target == .insert(3))
        #expect(addLeft?.index == 1)
    }

    @MainActor private func splitThisPane(_ f: Fixture) throws -> (insertion: SplitPaneInsertion, id: UUID) {
        let insertion = try #require(SplitPaneInsertion(paneID: f.a, stackingAfter: true, state: f.store.state))
        let id = UUID()
        _ = f.store.insertSplitPane(insertion, tabID: id, navigationURL: URL(string: "https://new.test/"), creation: nil, savedHomeIDs: [:], documents: [:])
        return (insertion, id)
    }

    @MainActor @Test func splitThisPaneTargetsThePanesStack() throws {
        let f = try Fixture("edits")
        let insertion = try #require(SplitPaneInsertion(paneID: f.a, stackingAfter: true, state: f.store.state))
        #expect(insertion.target == .stack(0, after: true))
        #expect(insertion.index == 1)
        #expect(insertion.orientation == .horizontal)
    }

    @MainActor @Test func splitThisPaneCommitsANewPaneThatJoinsTheLonePanesSlotAsANewStack() throws {
        let f = try Fixture("edits")
        let s = try splitThisPane(f)
        #expect(f.store.state.selectedTabIDs == [f.a, s.id, f.b, f.c])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [2, 2])
    }

    @MainActor @Test func splitThisPaneRefusesAtFourPanes() throws {
        let f = try Fixture("edits")
        _ = try splitThisPane(f)
        #expect(SplitPaneInsertion(paneID: f.a, stackingAfter: true, state: f.store.state) == nil)
    }

    @MainActor @Test func todaysAddStillRefusesAtFourPanes() throws {
        let f = try Fixture("edits")
        _ = try splitThisPane(f)
        #expect(SplitPaneInsertion(paneID: f.a, operation: .addAfter, state: f.store.state) == nil)
    }

    @MainActor @Test func separateCommitsOnAStackedPane() throws {
        let f = try Fixture("edits")
        let s = try splitThisPane(f)
        #expect(f.store.separateTabFromSplit(s.id, expected: f.store.activeSplitLayout!, focusedID: s.id))
    }

    @MainActor @Test func separatingCollapsesThatStackBackToOnePane() throws {
        let f = try Fixture("edits")
        let s = try splitThisPane(f)
        _ = f.store.separateTabFromSplit(s.id, expected: f.store.activeSplitLayout!, focusedID: s.id)
        #expect(f.store.state.selectedTabIDs == [s.id])
        #expect(f.store.state.splitLayouts.first?.tabIDs == [f.a, f.b, f.c])
        #expect(f.store.state.splitLayouts.first?.stacks?.slotSizes == [1, 2])
    }

    @MainActor private struct Closed {
        let before: BrowserState
        let undo: ClosedTabsUndo
        var windows: WindowClosedItems

        init(_ f: Fixture, closing ids: [UUID], focused: UUID?, recordWindow: Bool = false) {
            var windows = WindowClosedItems()
            before = f.store.state
            if recordWindow, let id = ids.first, let intent = ClosedItemIntent(ids: [id], state: f.store.state, spaceID: f.space.id, profileID: f.profile.id, focusedTabID: id) {
                f.store.closeTabs(Set(ids))
                windows.record(intent, in: f.store.state)
            } else {
                f.store.closeTabs(Set(ids))
            }
            undo = ClosedTabsUndo(prompt: .clear, ids: Set(ids), spaceID: f.space.id, profileID: f.profile.id, focusedTabID: focused,
                                  before: before, after: f.store.state)!
            self.windows = windows
        }
    }

    @MainActor @Test func closingAStackedPaneCollapsesItsStackAndKeepsTheColumnsShare() throws {
        let f = try Fixture("close")
        _ = Closed(f, closing: [f.c], focused: f.c)
        #expect(f.store.state.selectedTabIDs == [f.a, f.b])
        #expect(f.store.state.splitLayouts.count == 1)
        #expect(f.store.state.splitLayouts[0].stacks == nil)
        #expect(f.store.state.splitLayouts[0].widthFactors == [0.5, 0.5])
    }

    @MainActor @Test func undoRestoresThePaneToItsOldStackWithItsOldShare() throws {
        let f = try Fixture("close")
        let closed = Closed(f, closing: [f.c], focused: f.c)
        #expect(try f.store.undoClosedTabs(closed.undo, shouldCommit: { true }))
        #expect(f.store.state.splitLayouts.first?.tabIDs == [f.a, f.b, f.c])
        #expect(f.store.state.splitLayouts.first?.stacks == f.layout.stacks)
    }

    @MainActor @Test func reopenClosedTabRejoinsTheOldStack() throws {
        let f = try Fixture("close")
        var closed = Closed(f, closing: [f.c], focused: f.c, recordWindow: true)
        let reopened = closed.windows.next(in: f.store.state)!
        #expect(reopened.membership != nil)
        #expect(try f.store.restoreClosedItem(reopened))
        #expect(f.store.state.splitLayouts.first?.tabIDs == [f.a, f.b, f.c])
        #expect(f.store.state.splitLayouts.first?.stacks == f.layout.stacks)
    }

    @MainActor @Test func theSurvivorsCanBeConvertedAfterAClose() throws {
        let f = try Fixture("close")
        _ = Closed(f, closing: [f.b], focused: f.b)
        #expect(f.store.flipSplitOrientation(expected: f.store.activeSplitLayout!))
    }

    @MainActor @Test func afterAConvertTheUndoneCloseRejoinsItsOldMatesSlotInTheNewDirection() throws {
        let f = try Fixture("close")
        let closed = Closed(f, closing: [f.b], focused: f.b)
        _ = f.store.flipSplitOrientation(expected: f.store.activeSplitLayout!)
        #expect(try f.store.undoClosedTabs(closed.undo, shouldCommit: { true }))
        let layout = f.store.state.splitLayouts.first
        #expect(layout?.tabIDs == [f.a, f.b, f.c])
        #expect(layout?.orientation == .vertical)
        #expect(layout?.stacks?.slotSizes == [1, 2])
        #expect(layout?.stacks?.slotFactors == [0.5, 0.5])
    }

    @MainActor @Test func closingTheWholeStackDissolvesTheSplit() throws {
        let f = try Fixture("close")
        _ = Closed(f, closing: [f.b, f.c], focused: nil)
        #expect(f.store.state.splitLayouts.isEmpty)
        #expect(f.store.state.selectedTabIDs == [f.a])
    }

    @MainActor @Test func undoRebuildsTheStackedShapeFromTheDissolvedSplit() throws {
        let f = try Fixture("close")
        let closed = Closed(f, closing: [f.b, f.c], focused: nil)
        #expect(try f.store.undoClosedTabs(closed.undo, shouldCommit: { true }))
        #expect(f.store.state.splitLayouts.first?.tabIDs == [f.a, f.b, f.c])
        #expect(f.store.state.splitLayouts.first?.stacks == f.layout.stacks)
    }

    @MainActor private func closeWhole(_ f: Fixture) -> WindowClosedItems {
        var windows = WindowClosedItems()
        let intent = ClosedItemIntent(ids: Set(f.ids), state: f.store.state, spaceID: f.space.id, profileID: f.profile.id, focusedTabID: f.ids[1])!
        f.store.closeTabs(Set(f.ids))
        windows.record(intent, in: f.store.state)
        return windows
    }

    @MainActor @Test func archivedPanesCarryTheStackedShape() throws {
        let f = try Fixture("whole")
        _ = closeWhole(f)
        let archived = f.store.state.tabs.filter { f.ids.contains($0.id) }
        #expect(archived.allSatisfy { $0.archivedAt != nil && $0.archiveProvenance?.split?.stacks == f.layout.stacks })
    }

    @MainActor @Test func reopeningAClosedStackedSplitRestoresItAsOneGroup() throws {
        let f = try Fixture("whole")
        var windows = closeWhole(f)
        let record = windows.next(in: f.store.state)!
        #expect(record.split?.stacks == f.layout.stacks)
        #expect(try f.store.restoreClosedItem(record))
        #expect(f.store.state.splitLayouts.first?.tabIDs == f.ids)
        #expect(f.store.state.splitLayouts.first?.stacks == f.layout.stacks)
    }

    @MainActor @Test func restoringFromTheArchiveBringsBackTheStackedShape() throws {
        let f = try Fixture("whole")
        f.store.closeTabs(Set(f.ids))
        let restored = f.store.restoreArchivedTab(f.ids[0], destination: .previousSpace(fallbackSpaceID: f.space.id))
        #expect(restored == f.ids)
        #expect(f.store.state.splitLayouts.first?.stacks == f.layout.stacks)
    }

    @MainActor @Test func closingTheLoneColumnLeavesTheStackAsAFlatSplit() throws {
        let f = try Fixture("own-slot")
        _ = Closed(f, closing: [f.a], focused: f.a)
        #expect(f.store.state.splitLayouts.first?.tabIDs == [f.b, f.c])
        #expect(f.store.state.splitLayouts.first?.orientation == .vertical)
        #expect(f.store.state.splitLayouts.first?.stacks == nil)
    }

    @MainActor @Test func aPaneWithoutAnOldStackRejoinsAsItsOwnSlotBesideTheColumnItLeft() throws {
        let f = try Fixture("own-slot")
        let closed = Closed(f, closing: [f.a], focused: f.a)
        #expect(try f.store.undoClosedTabs(closed.undo, shouldCommit: { true }))
        let layout = f.store.state.splitLayouts.first
        #expect(layout?.tabIDs == [f.a, f.b, f.c])
        #expect(layout?.stacks == f.layout.stacks)
        #expect(layout?.orientation == .horizontal)
    }

    @MainActor private func archivedThird(_ f: Fixture) -> BrowserState {
        var state = f.store.state
        let index = state.tabs.firstIndex { $0.id == f.c }!
        state.tabs[index].archivedAt = Date(timeIntervalSince1970: 20)
        return state
    }

    @MainActor @Test func reconcilingAwayAStackedPaneCollapsesItsStack() throws {
        let f = try Fixture("reconcile")
        let layouts = BrowserStore.reconciledSplitLayouts(in: archivedThird(f), activeSpaceID: f.space.id)
        #expect(layouts.first?.tabIDs == [f.a, f.b])
        #expect(layouts.first?.stacks == nil)
        #expect(layouts.first?.widthFactors == [0.5, 0.5])
    }

    @MainActor @Test func reconcilingAnIntactStackedSplitChangesNothing() throws {
        let f = try Fixture("reconcile")
        #expect(BrowserStore.reconciledSplitLayouts(in: f.store.state, activeSpaceID: f.space.id) == f.store.state.splitLayouts)
    }

    @MainActor private final class Copies {
        let f: Fixture
        let urls: [UUID: String]

        init() throws {
            f = try Fixture("copies")
            urls = Dictionary(uniqueKeysWithValues: f.ids.map { ($0, "https://copy.test/" + $0.uuidString) })
        }
    }

    @MainActor @Test func duplicateCarriesTheStacksOntoFreshPaneIdentities() throws {
        let s = try Copies()
        let duplicate = SidebarDuplicateTarget(items: [.split(s.f.layout.id)], spaceID: s.f.space.id, profileID: s.f.profile.id, state: s.f.store.state)!
        let copied = try #require(try s.f.store.duplicateSidebarItems(duplicate, destinations: s.urls))
        let copy = s.f.store.state.splitLayouts.first { $0.id != s.f.layout.id }
        #expect(copy?.stacks == s.f.layout.stacks)
        #expect(copy?.tabIDs == copied.tabIDs)
        #expect(Set(copied.tabIDs).isDisjoint(with: s.f.ids))
    }

    @MainActor @Test func optionDragCopiesCarryTheStacks() throws {
        let s = try Copies()
        let duplicate = SidebarDuplicateTarget(items: [.split(s.f.layout.id)], spaceID: s.f.space.id, profileID: s.f.profile.id, state: s.f.store.state)!
        _ = try s.f.store.duplicateSidebarItems(duplicate, destinations: s.urls)
        let today = SidebarContainerLocation(spaceID: s.f.space.id, folderID: nil, section: .today)
        let target = SidebarItemsCopy(items: [.split(s.f.layout.id)], spaceID: s.f.space.id, profileID: s.f.profile.id, state: s.f.store.state)!
        let result = try s.f.store.copySidebarItems(target, to: today, before: nil, destinations: s.urls)
        #expect(result != nil)
        #expect(s.f.store.state.splitLayouts.filter { $0.stacks == s.f.layout.stacks }.count == 3)
    }

    @MainActor @Test func pinToFolderCopiesCarryTheStacksOntoFreshIDs() throws {
        let profile = BrowserProfile(id: UUID(), name: "Profile")
        let space = BrowserSpace(id: UUID(), name: "Source", symbol: "circle", color: "000000", profileID: profile.id)
        let folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Destination", isExpanded: false)
        let ids = [UUID(), UUID(), UUID()]
        let layout = Self.stacked(ids, space: space.id, sizes: [2, 1], slots: [0.4, 0.6], stacks: [[0.3, 0.7], [1]])
        var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
        state.folders = [folder]
        state.tabs = Self.tabs(ids, space: space.id, profile: profile.id, kind: .pinned, url: "https://p.test", title: "P")
        state.splitLayouts = [layout]
        let source = CommandBarFolderMoveSource(items: [.split(layout.id)], spaceID: space.id, profileID: profile.id, state: state)!
        let move = CommandBarFolderMove.snapshot(source: source, state: state).first { $0.folder.folderID == folder.id }!
        let commandCopy = CommandBarFolderCopy(move: move, destinations: Dictionary(uniqueKeysWithValues: ids.map { ($0, "https://c.test") }),
                                               state: state, now: Date())!
        #expect(commandCopy.groups.count == 1)
        #expect(commandCopy.groups[0].stacks == layout.stacks)
        #expect(Set(commandCopy.groups[0].tabIDs).isDisjoint(with: ids))
    }

    @MainActor private func favoriteSplit(_ f: Fixture) throws -> (favoriteID: UUID, request: FavoriteSplitRequest) {
        let favoriteID = f.store.open("https://favorite.test/", kind: .favorite)
        f.store.setSplit(f.ids)
        let favorite = f.store.state.tabs.first { $0.id == favoriteID }!
        let request = try #require(FavoriteSplitRequest(favorite: favorite, spaceID: f.space.id, selection: f.ids, focusedID: f.b,
                                                        state: f.store.state, homeIDs: [favoriteID: UUID()]))
        return (favoriteID, request)
    }

    @MainActor @Test func aFavoriteJoinsAfterTheFocusedPanesWholeSlot() throws {
        let f = try Fixture("favorite")
        let s = try favoriteSplit(f)
        #expect(s.request.paneIDs == [f.a, f.b, f.c, s.favoriteID])
    }

    @MainActor @Test func aFavoriteJoinsTheStackedSplitAndKeepsTheStackIntact() throws {
        let f = try Fixture("favorite")
        let s = try favoriteSplit(f)
        #expect(try f.store.commitFavoriteSplit(s.request) == s.favoriteID)
        let layout = f.store.activeSplitLayout
        #expect(layout?.tabIDs == [f.a, f.b, f.c, s.favoriteID])
        #expect(layout?.stacks?.slotSizes == [1, 2, 1])
        #expect(Self.close(layout!.stacks!.stackFactors[1], [0.25, 0.75]))
    }

    @MainActor @Test func openInSplitViewStillRefusesAtFourPanes() throws {
        let f = try Fixture("favorite")
        let s = try favoriteSplit(f)
        _ = try f.store.commitFavoriteSplit(s.request)
        #expect(!f.store.insertCommandBarSplit(after: f.b, expectedSelection: f.store.state.selectedTabIDs, tabID: UUID(), newURL: URL(string: "https://pane.test/")))
    }

    @MainActor @Test func commandBarHomesSeeTheMainRowInsertion() throws {
        let f = try Fixture("command-bar")
        #expect(f.store.commandBarSplitHomes(after: f.b, expectedSelection: f.ids, tabID: UUID(), isNew: true) == [])
    }

    @MainActor @Test func openInSplitViewAddsAMainRowSlotAfterTheFocusedPanesStack() throws {
        let f = try Fixture("command-bar")
        let pane = UUID()
        #expect(f.store.insertCommandBarSplit(after: f.b, expectedSelection: f.ids, tabID: pane, newURL: URL(string: "https://pane.test/")))
        #expect(f.store.state.selectedTabIDs == [f.a, f.b, f.c, pane])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [1, 2, 1])
    }

    @MainActor private func withOther(_ f: Fixture) -> (other: UUID, layout: BrowserSplitLayout) {
        let other = f.store.open("https://other.test/")
        f.store.setSplit(f.ids)
        return (other, f.store.activeSplitLayout!)
    }

    @MainActor @Test func aMainRowDropInsideAStackRefuses() throws {
        let f = try Fixture("drops")
        let s = withOther(f)
        #expect(!f.store.dropTabIntoSplit(s.other, expectedSelection: f.ids, expectedLayout: s.layout, target: .insert(2), orientation: .horizontal))
    }

    @MainActor @Test func aDropCannotFlipAStackedSplit() throws {
        let f = try Fixture("drops")
        let s = withOther(f)
        #expect(!f.store.dropTabIntoSplit(s.other, expectedSelection: f.ids, expectedLayout: s.layout, target: .insert(1), orientation: .vertical))
    }

    @MainActor @Test func replacingAStackedPaneKeepsItsSlotStackPositionAndWeights() throws {
        let f = try Fixture("drops")
        let s = withOther(f)
        let replaced = SplitDropTransaction.make(source: s.other, selection: f.ids, layout: s.layout, target: .replace(2),
                                                 orientation: .horizontal, spaceID: f.space.id)
        #expect(replaced?.tabIDs == [f.a, f.b, s.other])
        #expect(replaced?.stacks == s.layout.stacks)
        #expect(replaced?.id == s.layout.id)
    }

    @MainActor @Test func aMainRowDropAtASlotEdgeCommitsAWholeSlot() throws {
        let f = try Fixture("drops")
        let s = withOther(f)
        #expect(f.store.dropTabIntoSplit(s.other, expectedSelection: f.ids, expectedLayout: s.layout, target: .insert(1), orientation: .horizontal))
        #expect(f.store.state.selectedTabIDs == [f.a, s.other, f.b, f.c])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [1, 1, 2])
    }

    @MainActor @Test func aPerpendicularDropStacksTheDroppedTabAbovethePane() throws {
        let f = try Fixture("stack-drop")
        let s = withOther(f)
        #expect(f.store.dropTabIntoSplit(s.other, expectedSelection: f.ids, expectedLayout: s.layout, target: .stack(0, after: false), orientation: .vertical))
        #expect(f.store.state.selectedTabIDs == [s.other, f.a, f.b, f.c])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [2, 2])
        #expect(f.store.activeSplitLayout?.orientation == .horizontal)
    }

    @MainActor @Test func anExternalLinkDropCanStack() throws {
        let f = try Fixture("external")
        let tab = UUID()
        #expect(try f.store.dropExternalURLIntoSplit(URL(string: "https://link.test/")!, tabID: tab, spaceID: f.space.id,
            profileID: f.profile.id, expectedSelection: f.ids, expectedLayout: f.store.activeSplitLayout!,
            target: .stack(2, after: true), orientation: .horizontal, creation: nil))
        #expect(f.store.state.selectedTabIDs == [f.a, f.b, f.c, tab])
        #expect(f.store.activeSplitLayout?.stacks?.slotSizes == [1, 3])
    }

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
        #expect(Self.close(factors, [0.5, 0.25, 0.25]))
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
        #expect(Self.close(partial?.widthFactors ?? [], [0.25, 0.75]))
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
