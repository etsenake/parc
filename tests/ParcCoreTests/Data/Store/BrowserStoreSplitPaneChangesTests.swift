import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSplitPaneChangesTests {
    @MainActor
    private static func withSavedPaneTrio(
        _ body: (BrowserStore, UUID, UUID, UUID) throws -> Void
    ) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example", kind: .pinned)
            let third = store.open("https://three.example")
            store.setSplit([first, third])
            store.setSplitLayout(orientation: .horizontal, widthFactors: [4, 1])
            store.setSplit([first, second, third])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2, 3])
            try body(store, first, second, third)
        }
    }

    @Test @MainActor static func joiningPinnedPanesPreservesTheirOriginalSavedSlots() throws {
        try withSavedPaneTrio { store, first, second, _ in
            let firstHome = try BrowserStoreTestsSupport.expectHome(of: first, in: store, savedURL: "https://one.example")
            let secondHome = try BrowserStoreTestsSupport.expectHome(of: second, in: store, savedURL: "https://two.example")
            #expect(SidebarHierarchy.children(in: .init(spaceID: store.activeSpaceID, folderID: nil, section: .pinned),
                state: store.state) == [.tab(firstHome.id), .tab(secondHome.id)])
        }
    }

    @Test @MainActor static func replacingASplitPanePreservesOrientationAndProportions() throws {
        try withSavedPaneTrio { store, first, _, third in
            let replacement = store.open("https://replacement.example")
            store.selectTab(first)
            store.setSplit([first, replacement, third])
            try BrowserStoreTestsSupport.expectFactors(store.activeSplitLayout?.widthFactors, [1.0/6, 2.0/6, 3.0/6],
                "Replacing a pane's tab must preserve its position and divider sizes")
            #expect(store.activeSplitLayout?.orientation == .vertical)
        }
    }

    @Test @MainActor static func separatingAPaneOverridesAnOlderLayoutForTheSurvivors() throws {
        try withSavedPaneTrio { store, first, second, _ in
            let original = try #require(store.activeSplitLayout)
            #expect(store.separateTabFromSplit(second, expected: original, focusedID: first))
            try BrowserStoreTestsSupport.expectFactors(store.activeSplitLayout?.widthFactors, [0.25, 0.75],
                "The visible layout replaces any older geometry for the surviving group")
            #expect(store.activeSplitLayout?.orientation == .vertical)
            #expect(try BrowserStoreTestsSupport.tab(second, in: store).archivedAt == nil)
        }
    }

    @Test @MainActor static func extendingASavedSplitAppendsTheNewPane() throws {
        try withSavedPaneTrio { store, first, second, third in
            let original = try #require(store.activeSplitLayout)
            try #require(store.separateTabFromSplit(second, expected: original, focusedID: first))
            store.selectTab(second, extendingSplit: true)
            #expect(store.activeSplitLayout?.tabIDs == [first, third, second])
        }
    }

    @Test @MainActor static func closingAPaneResizesSurvivorsAndArchivesOnlyTheOriginal() throws {
        try withSavedPaneTrio { store, first, second, third in
            let secondHome = try BrowserStoreTestsSupport.expectHome(of: second, in: store, savedURL: "https://two.example")
            store.setSplit([first, third, second])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 3, 2])
            store.closeTab(second)
            try BrowserStoreTestsSupport.expectFactors(store.activeSplitLayout?.widthFactors, [0.25, 0.75], "Closing a pane must resize survivors")
            #expect(try BrowserStoreTestsSupport.tab(second, in: store).archivedAt != nil
                && (try BrowserStoreTestsSupport.tab(secondHome.id, in: store)).archivedAt == nil)
        }
    }

    @Test @MainActor static func closingThePenultimatePaneLeavesOneNormalPageAndCleansSavedLayouts() throws {
        try withSavedPaneTrio { store, first, second, third in
            store.closeTab(second)
            store.closeTab(third)
            #expect(store.state.selectedTabIDs == [first] && store.activeSplitLayout == nil)
            #expect(store.state.splitLayouts.allSatisfy { !$0.tabIDs.contains(third) })
        }
    }

    @Test @MainActor static func dissolvingASplitRemovesItsLayoutWithoutClosingTheOtherPage() throws {
        try BrowserStoreSplitTestsSupport.withTwoSplitTabs { store, first, second in
            store.closeSplit()
            #expect(!store.state.splitLayouts.contains { $0.spaceID == store.activeSpaceID && $0.tabIDs == [first, second] })
            let retained = try BrowserStoreTestsSupport.tab(second, in: store)
            #expect(retained.archivedAt == nil)
        }
    }

    @Test @MainActor static func movingAPaneToAnotherSpaceRemovesItFromTheFormerSplitAndGeometry() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let firstSpace = store.activeSpaceID
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            let favorite = store.open("https://favorite.example", kind: .favorite)
            store.setSplit([first, second, favorite])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2, 3])
            let otherSpace = store.createSpace(name: "Other")
            store.moveTab(second, toSpace: otherSpace)
            store.selectSpace(firstSpace)
            #expect(store.state.selectedTabIDs == [first, favorite], "Space restoration must drop a moved pane")
            try BrowserStoreTestsSupport.expectFactors(store.activeSplitLayout?.widthFactors, [0.25, 0.75], "A moved pane must be removed from its former split's saved geometry")
        }
    }

    @Test @MainActor static func changingTheSplitsSpaceProfileLeavesTheFavoriteHomeInTheOriginalProfile() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let firstSpace = store.activeSpaceID
            let first = store.open("https://one.example")
            let favorite = store.open("https://favorite.example", kind: .favorite)
            store.setSplit([first, favorite])
            let favoriteHome = try BrowserStoreTestsSupport.expectHome(of: favorite, in: store, savedURL: "https://favorite.example")
            #expect(try BrowserStoreTestsSupport.tab(favorite, in: store).kind == .today && favoriteHome.kind == .favorite, "A Favorite joining a new split enters Today; its fresh home keeps the tray slot")
            let profile = store.createProfile(name: "Separate")
            store.assignProfile(profile, toSpace: firstSpace)
            #expect(try store.state.splitLayouts.map(\.tabIDs) == [[first, favorite]]
                       && (try BrowserStoreTestsSupport.tab(first, in: store)).profileID == profile && (try BrowserStoreTestsSupport.tab(favorite, in: store)).profileID == profile, "The joined original is an ordinary page of the split and follows its Space's Profile")
            #expect(try BrowserStoreTestsSupport.tab(favoriteHome.id, in: store).profileID != profile, "The Favorite's saved home stays in its own Profile's tray")
            try store.save()
            _ = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        }
    }

    @Test @MainActor static func legacySplitLayoutMigration() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let firstSpace = store.activeSpaceID
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            store.setSplit([first, second])
            let secondSpace = store.createSpace(name: "Other")
            let third = store.open("https://three.example")
            let fourth = store.open("https://four.example")
            store.setSplit([third, fourth])
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            json.removeValue(forKey: "splitLayouts")
            json["splitWidthFactors"] = [2, 6]
            json["splitIsVertical"] = false
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let reopened = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            #expect(reopened.activeSpaceID == secondSpace && reopened.activeSplitLayout?.orientation == .horizontal, "Legacy sessions must keep their actual previous side-by-side presentation")
            try BrowserStoreTestsSupport.expectFactors(reopened.activeSplitLayout?.widthFactors, [0.25, 0.75], "Legacy active weights must migrate into the active pane group")
            reopened.selectSpace(firstSpace)
            try BrowserStoreTestsSupport.expectFactors(reopened.activeSplitLayout?.widthFactors, [0.5, 0.5], "Older inactive split selections must migrate with equal sizes")
            try reopened.save()
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            #expect(saved["splitLayouts"] != nil && saved["splitWidthFactors"] == nil && saved["splitIsVertical"] == nil, "A migrated save must replace unused globals with per-split records")
            let again = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            #expect(again.state == reopened.state, "Split migration must be idempotent")
        }
    }

    @Test @MainActor static func legacyStaleSplitSelectionMigration() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let originalSpace = store.activeSpaceID
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            let third = store.open("https://three.example")
            store.setSplit([first, second, third])
            let otherSpace = store.createSpace(name: "Other")
            store.moveTab(first, toSpace: otherSpace)
            store.closeTab(second)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            json.removeValue(forKey: "splitLayouts")
            json["splitWidthFactors"] = []
            json["splitIsVertical"] = false
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let reopened = try BrowserStore(directory: directory)
            reopened.selectSpace(originalSpace)
            #expect(reopened.state.selectedTabIDs == [third] && reopened.activeSplitLayout == nil, "Legacy inactive selections containing moved or archived tabs must migrate without rejecting an otherwise valid session")
            try reopened.save()
            _ = try BrowserStore(directory: directory)
        }
    }

    enum SplitDamage: CaseIterable {
        case zeroWeight, missingWeight, unnormalized, repeatedTab, missingTab, missingSpace, repeatedLayout
    }

    @Test(arguments: SplitDamage.allCases)
    @MainActor static func anInvalidPersistedSplitIsRejectedAndTheSessionIsPreserved(_ damage: SplitDamage) throws {
        try BrowserStoreSplitTestsSupport.withTwoSplitTabs { store, first, _ in
            try store.save()
            var state = store.state
            var layout = try #require(state.splitLayouts.first)
            switch damage {
            case .zeroWeight: layout.widthFactors = [0, 1]
            case .missingWeight: layout.widthFactors = [1]
            case .unnormalized: layout.widthFactors = [2, 3]
            case .repeatedTab: layout.tabIDs = [first, first]
            case .missingTab: layout.tabIDs = [first, UUID()]
            case .missingSpace: layout.spaceID = UUID()
            case .repeatedLayout: break
            }
            state.splitLayouts = damage == .repeatedLayout ? [layout, layout] : [layout]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let bytes = try encoder.encode(state)
            let file = store.directory.appendingPathComponent("session.json")
            try bytes.write(to: file)

            #expect(throws: (any Error).self) { try BrowserStore(directory: store.directory) }
            #expect(try Data(contentsOf: file) == bytes)
        }
    }
}
