import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreSplitLayoutTests {
    @Test @MainActor static func oneSelectedPageCannotHaveSplitGeometry() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            _ = store.open("https://one.example")
            #expect(!store.setSplitLayout(orientation: .vertical, widthFactors: [1, 1]))
        }
    }

    struct WeightCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let weights: [Double]
        let expected: [Double]
    }

    @Test(arguments: [
        WeightCase(testDescription: "Ordinary proportions", weights: [2, 6], expected: [0.25, 0.75]),
        WeightCase(testDescription: "Maximum finite weights", weights: [.greatestFiniteMagnitude, .greatestFiniteMagnitude], expected: [0.5, 0.5]),
    ])
    @MainActor static func validSplitWeightsNormalizeWithoutOverflow(_ input: WeightCase) throws {
        try BrowserStoreSplitTestsSupport.withTwoSplitTabs { store, _, _ in
            #expect(store.setSplitLayout(orientation: .vertical, widthFactors: input.weights))
            try BrowserStoreTestsSupport.expectFactors(store.activeSplitLayout?.widthFactors, input.expected, "Relative split weights normalize")
        }
    }

    @Test(arguments: [
        [Double](), [1], [1, 1, 1], [0, 1], [-1, 2], [.nan, 1], [.infinity, 1],
        [Double.leastNonzeroMagnitude, Double.greatestFiniteMagnitude],
    ])
    @MainActor static func invalidSplitWeightsDoNotChangeTheSelectionOrLayout(_ weights: [Double]) throws {
        try BrowserStoreSplitTestsSupport.withTwoSplitTabs { store, _, _ in
            let original = store.state
            #expect(!store.setSplitLayout(orientation: .vertical, widthFactors: weights))
            #expect(store.state == original)
        }
    }

    @Test @MainActor static func selectingAChildKeepsTheWholeSplitSelected() throws {
        try BrowserStoreSplitTestsSupport.withTwoSplitTabs { store, first, second in
            store.selectTab(first)
            #expect(store.state.selectedTabIDs == [first, second])
        }
    }

    @Test @MainActor static func closingASplitClearsItsActiveLayout() throws {
        try BrowserStoreSplitTestsSupport.withTwoSplitTabs { store, _, _ in
            store.closeSplit()
            #expect(store.activeSplitLayout == nil)
        }
    }

    @Test @MainActor static func revisitingAnOrderedPaneGroupRestoresItsOwnLayout() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            let third = store.open("https://three.example")
            let fourth = store.open("https://four.example")
            store.setSplit([first, second])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 3])
            let original = store.activeSplitLayout
            store.selectTab(third)
            store.setSplit([third, fourth])
            store.setSplitLayout(orientation: .horizontal, widthFactors: [3, 2])
            store.setSplit([first, second])
            #expect(store.activeSplitLayout == original, "Revisiting an ordered pane group must restore its own geometry")
        }
    }

    @Test @MainActor static func navigatingASplitPanePreservesItsGeometry() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            store.setSplit([first, second])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 3])
            let original = try #require(store.activeSplitLayout)
            store.updateTab(first, title: "Changed page", url: "https://one.example/next")
            #expect(store.activeSplitLayout == original, "Navigation and title updates must not drift divider proportions")
        }
    }

    @Test @MainActor static func aFavoriteSplitSharesOneLayoutAcrossSpacesAndRestart() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let firstSpace = store.activeSpaceID
            let profile = store.activeSpace.profileID
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            store.setSplit([first, second])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 3])
            let original = try #require(store.activeSplitLayout)
            let tray = SidebarContainerLocation(spaceID: firstSpace, folderID: nil, section: .favorite, profileID: profile)
            let snapshot = SidebarHierarchySnapshot(state: store.state, spaceID: firstSpace, profileID: profile, includesFavorites: true)!
            #expect(try store.moveSidebarItem(.split(original.id), to: tray, before: nil, expected: snapshot), "A whole split moves into Favorites")
            #expect(try BrowserStoreTestsSupport.tab(first, in: store).kind == .favorite && (try BrowserStoreTestsSupport.tab(second, in: store)).kind == .favorite, "Every child enters the Favorites container with its split")
            let secondSpace = store.createSpace(name: "Second")
            store.selectTab(first)
            #expect(store.activeSplitLayout?.id == original.id && store.state.selectedTabIDs == [first, second], "Another Space of the Profile shows the same Favorite split")
            store.setSplitLayout(orientation: .horizontal, widthFactors: [4, 1])
            let other = store.activeSplitLayout
            #expect(other?.id == original.id, "Resizing from another Space edits the one Favorite split")
            store.selectSpace(firstSpace)
            #expect(store.activeSplitLayout == other, "A Favorite split has one Profile-wide layout in every Space")
            #expect(store.state.splitLayouts.filter { $0.tabIDs.contains(first) }.count == 1, "The same Favorites form one split, not one per Space")
            try store.save()
            let reopened = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            #expect(reopened.state == store.state, "All stored split layouts and selected panes must survive a restart")
            reopened.selectSpace(secondSpace)
            #expect(reopened.activeSplitLayout == other, "Restoring another Space shows the Favorite split's one layout")
        }
    }

    @Test @MainActor static func twoSavedSplitsInOneSpaceKeepIndependentLayoutsAcrossRestart() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let first = store.open("https://one.example")
            let second = store.open("https://two.example")
            let third = store.open("https://three.example")
            let fourth = store.open("https://four.example")
            store.setSplit([first, second])
            store.setSplitLayout(orientation: .vertical, widthFactors: [1, 3])
            store.selectTab(third)
            store.setSplit([third, fourth])
            store.setSplitLayout(orientation: .horizontal, widthFactors: [3, 2])
            try store.save()
            let reopened = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            reopened.setSplit([third, fourth])
            try BrowserStoreTestsSupport.expectFactors(reopened.activeSplitLayout?.widthFactors, [0.6, 0.4], "A second saved group in one Space must survive restart")
            #expect(reopened.activeSplitLayout?.orientation == .horizontal, "Orientation belongs to the split, not the most recently displayed Space")
        }
    }
}
