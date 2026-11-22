import Foundation
import Testing
@testable import ParcCore

struct SplitStacksPersistenceTests {
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
        #expect(String(decoding: try SplitStacksTestsSupport.encoder.encode(Self.flatLayout()), as: UTF8.self) == Self.flatJSON)
    }

    @Test func thePreviousBuildsFlatSplitReadsBackUnchanged() throws {
        let read = try JSONDecoder().decode(BrowserSplitLayout.self, from: Data(Self.flatJSON.utf8))
        #expect(read == Self.flatLayout())
        #expect(read.stacks == nil)
    }

    @Test func readingAndSavingAFlatSplitIsByteIdentical() throws {
        let read = try JSONDecoder().decode(BrowserSplitLayout.self, from: Data(Self.flatJSON.utf8))
        #expect(String(decoding: try SplitStacksTestsSupport.encoder.encode(read), as: UTF8.self) == Self.flatJSON)
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
        SplitStacksTestsSupport.stacked(trioIDs, space: trioSpace, sizes: [1, 2], slots: [0.5, 0.5], stacks: [[1], [0.25, 0.75]], title: "Trio")
    }

    @Test func aStackedSplitSavesItsStacks() throws {
        let json = try JSONSerialization.jsonObject(with: try SplitStacksTestsSupport.encoder.encode(Self.trio())) as? [String: Any]
        #expect(json?["stacks"] != nil)
    }

    @Test func widthFactorsStayAValidFlatRowForOlderBuilds() {
        let layout = Self.trio()
        #expect(SplitStacksTestsSupport.close(layout.widthFactors, [0.5, 0.125, 0.375]))
        #expect(layout.widthFactors.reduce(0, +) == 1)
    }

    @Test func aStackedSplitReadsBackUnchanged() throws {
        let layout = Self.trio()
        #expect(try JSONDecoder().decode(BrowserSplitLayout.self, from: try SplitStacksTestsSupport.encoder.encode(layout)) == layout)
    }

    @Test func anOlderBuildReadsAStackedSplitAsOneFlatRowThatPassesItsOwnChecks() throws {
        let older = try JSONDecoder().decode(PreviousBuildLayout.self, from: try SplitStacksTestsSupport.encoder.encode(Self.trio()))
        #expect(older.tabIDs == Self.trioIDs)
        #expect(BrowserSplitLayout.normalized(older.widthFactors, count: 3) != nil)
        #expect(abs(older.widthFactors.reduce(0, +) - 1) < 1e-9)
    }

    @Test func afterAnOlderBuildSavesTheSplitComesBackFlatWithEveryPane() throws {
        let layout = Self.trio()
        let older = try JSONDecoder().decode(PreviousBuildLayout.self, from: try SplitStacksTestsSupport.encoder.encode(layout))
        let after = try JSONDecoder().decode(BrowserSplitLayout.self, from: try JSONEncoder().encode(older))
        #expect(after.stacks == nil)
        #expect(after.tabIDs == Self.trioIDs)
        #expect(SplitStacksTestsSupport.close(after.widthFactors, layout.widthFactors))
    }

    @MainActor @Test func wholeSessionValidationAcceptsAStackedSplit() throws {
        let profile = BrowserProfile(id: UUID(), name: "Profile")
        let home = BrowserSpace(id: Self.trioSpace, name: "Home", symbol: "circle", color: "000000", profileID: profile.id)
        var state = BrowserState(profiles: [profile], spaces: [home], activeSpaceID: Self.trioSpace)
        state.tabs = SplitStacksTestsSupport.tabs(Self.trioIDs, space: Self.trioSpace, profile: profile.id)
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
        #expect(SplitStacksTestsSupport.close(fixed.widthFactors, [0.125, 0.125, 0.75]))
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
        state.tabs = SplitStacksTestsSupport.tabs(ids, space: flat.spaceID, profile: profile.id)
        state.splitLayouts = [flat]
        state.selectedTabIDs = ids
        state.selectionBySpace = [flat.spaceID.uuidString: ids]
        var session = try JSONSerialization.jsonObject(with: try SplitStacksTestsSupport.encoder.encode(state)) as! [String: Any]
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
}
