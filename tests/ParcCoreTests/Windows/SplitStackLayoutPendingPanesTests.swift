import Foundation
import Testing
@testable import ParcCore

struct SplitStackLayoutPendingPanesTests {
    private struct Pending {
        let ids = [UUID(), UUID(), UUID()]
        let stacked: BrowserState
        let flat: BrowserState

        init() {
            let profile = BrowserProfile(id: UUID(), name: "Profile")
            let space = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "000000", profileID: profile.id)
            func state(_ layout: BrowserSplitLayout) -> BrowserState {
                var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
                state.tabs = layout.tabIDs.enumerated().map { index, id in
                    BrowserTab(id: id, spaceID: space.id, profileID: profile.id, url: "https://\(index).test/", title: "T\(index)",
                               kind: .today, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                               savedURL: "https://\(index).test/", savedTitle: "T\(index)")
                }
                state.splitLayouts = [layout]
                state.selectedTabIDs = layout.tabIDs
                return state
            }
            let ids = ids
            let value = SplitStackLayoutTestsSupport.stacks([2, 1], [0.5, 0.5], [[0.5, 0.5], [1]])
            stacked = state(BrowserSplitLayout(id: UUID(), spaceID: space.id, tabIDs: ids, orientation: .horizontal,
                                               widthFactors: value.flattenedFactors, stacks: value))
            flat = state(BrowserSplitLayout(spaceID: space.id, tabIDs: [ids[0], ids[1]], orientation: .horizontal, widthFactors: [0.5, 0.5]))
        }
    }

    @Test func aPendingPaneBelowTheLoneColumnRendersInsideThatColumnAfterItsPane() throws {
        let p = Pending()
        let below = try #require(SplitPaneInsertion(paneID: p.ids[2], stackingAfter: true, state: p.stacked))
        #expect(below.index == 3)
        #expect(below.previewLayout?.stacks?.slotSizes == [2, 2])
        #expect(below.previewLayout?.orientation == .horizontal)
    }

    @Test func thePendingStackedPreviewKeepsAValidFlatRow() throws {
        let p = Pending()
        let below = try #require(SplitPaneInsertion(paneID: p.ids[2], stackingAfter: true, state: p.stacked))
        #expect(below.previewFactors.count == 4)
        #expect(abs(below.previewFactors.reduce(0, +) - 1) < 1e-9)
    }

    @Test func aPendingPaneAboveTheTopLeftPaneJoinsItsStackAtTheTop() throws {
        let p = Pending()
        let above = try #require(SplitPaneInsertion(paneID: p.ids[0], stackingAfter: false, state: p.stacked))
        #expect(above.index == 0)
        #expect(above.previewLayout?.stacks?.slotSizes == [3, 1])
    }

    @Test func aPendingMainRowPaneBesideAStackRendersAsItsOwnFullLengthSlot() throws {
        let p = Pending()
        let mainRow = try #require(SplitPaneInsertion(paneID: p.ids[1], operation: .addAfter, state: p.stacked))
        #expect(mainRow.index == 2)
        #expect(mainRow.previewLayout?.stacks?.slotSizes == [2, 1, 1])
    }

    @Test func anAddThatWouldChangeAStackedSplitsDirectionNeverOpensAPendingPane() {
        let p = Pending()
        #expect(SplitPaneInsertion(paneID: p.ids[0], operation: .addBelow, state: p.stacked) == nil)
    }

    @Test func aFlatSplitsPendingPaneKeepsTodaysFlatPreview() throws {
        let p = Pending()
        let flatAdd = try #require(SplitPaneInsertion(paneID: p.ids[1], operation: .addAfter, state: p.flat))
        #expect(flatAdd.previewLayout == nil)
        #expect(SplitStackLayoutTestsSupport.close(flatAdd.previewFactors, [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }

    @Test func stackingAPaneInAFlatSplitPreviewsTheNewStack() throws {
        let p = Pending()
        let flatStack = try #require(SplitPaneInsertion(paneID: p.ids[0], stackingAfter: true, state: p.flat))
        #expect(flatStack.index == 1)
        #expect(flatStack.previewLayout?.stacks?.slotSizes == [2, 1])
    }

    private struct Pictures {
        let items: [RecentTabOrder.Item]
        let ids: [UUID]

        init() {
            var order = RecentTabOrder()
            let profile = BrowserProfile(id: UUID(), name: "Profile")
            let space = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "000000", profileID: profile.id)
            let ids = [UUID(), UUID(), UUID(), UUID()]
            var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
            state.tabs = ids.enumerated().map { index, id in
                BrowserTab(id: id, spaceID: space.id, profileID: profile.id, url: "https://\(index).test/", title: "T\(index)",
                           kind: .today, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                           savedURL: "https://\(index).test/", savedTitle: "T\(index)")
            }
            let value = SplitStackLayoutTestsSupport.stacks([1, 2], [0.5, 0.5], [[1], [0.5, 0.5]])
            state.splitLayouts = [BrowserSplitLayout(id: UUID(), spaceID: space.id, tabIDs: Array(ids.prefix(3)), orientation: .vertical,
                                                     widthFactors: value.flattenedFactors, stacks: value)]
            items = order.items(state: state, selected: [ids[3]], currentSpace: space.id) { _ in true }
            self.ids = ids
        }
    }

    @Test func theTabSwitcherLearnsTheSplitsRealStackedShape() {
        let p = Pictures()
        let split = p.items.first { $0.tabIDs.count == 3 }
        #expect(split?.slotSizes == [1, 2])
        #expect(split?.orientation == .vertical)
    }

    @Test func aSinglePageHasNoStackedShape() {
        let p = Pictures()
        #expect(p.items.first { $0.tabIDs == [p.ids[3]] }?.slotSizes == nil)
    }
}
