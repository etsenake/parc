import Combine
import Foundation
import Testing
@testable import ParcCore

extension ClosedItemsTestsSupport {
    @MainActor
    struct ClosedItemsSplitTests {
        struct SplitSteps {
            let f: Fixture
            let cache = ClosedWindow()

            @MainActor init() throws {
                f = try Fixture(now: { Date(timeIntervalSince1970: 1_900_000_000) })
            }

            func approx(_ left: [Double]?, _ right: [Double]) -> Bool {
                guard let left, left.count == right.count else { return false }
                return zip(left, right).allSatisfy { abs($0 - $1) < 1e-9 }
            }

            @MainActor func split(_ ids: [UUID], _ orientation: SplitOrientation, _ factors: [Double]) -> BrowserSplitLayout {
                f.store.setSplit(ids)
                _ = f.store.setSplitLayout(orientation: orientation, widthFactors: factors)
                return f.store.state.splitLayouts.first { $0.tabIDs == ids }!
            }

            @MainActor func close(_ ids: Set<UUID>, focus: UUID? = nil) {
                let intent = ClosedItemIntent(ids: ids, state: f.store.state, spaceID: f.space, profileID: f.profile, focusedTabID: focus)!
                f.store.closeTabs(ids)
                cache.record(intent, in: f.store.state)
            }

            @MainActor func group(_ id: UUID) -> BrowserSplitLayout? { f.store.state.splitLayouts.first { $0.id == id } }

            @MainActor func reopen(_ expected: [UUID], regroupable: (UUID) -> Bool = { _ in true }) throws {
                let record = try #require(cache.next(in: f.store.state))
                #expect(record.tabIDs == expected)
                #expect(try f.store.restoreClosedItem(record, regroupable: regroupable))
                #expect(cache.consume(record))
            }

            @MainActor func open(_ name: String) -> UUID { f.store.open("https://\(name).invalid") }
        }

        @Test func closingOneOfThreePanesKeepsTheOriginalContainerAndReopenRejoinsItAtItsIndexAndShare() throws {
            let s = try SplitSteps()
            let a = s.open("a"), b = s.open("b"), c = s.open("c")
            let three = s.split([a, b, c], .vertical, [0.2, 0.3, 0.5])
            s.close([b], focus: b)
            #expect(s.group(three.id)?.tabIDs == [a, c])
            let middle = s.cache.next(in: s.f.store.state)?.membership
            #expect(middle?.layout.id == three.id)
            #expect(middle?.layout.tabIDs == [a, b, c])
            #expect(middle?.index == 1)
            #expect(middle?.dissolved == false)
            try s.reopen([b])
            #expect(s.group(three.id)?.tabIDs == [a, b, c])
            #expect(s.group(three.id)?.orientation == .vertical)
            #expect(s.approx(s.group(three.id)?.widthFactors, [0.2, 0.3, 0.5]))
            #expect(s.f.store.state.selectedTabIDs == [a, b, c])
            #expect(s.f.store.state.splitLayouts.filter { $0.tabIDs.contains(b) }.count == 1)
        }

        @Test func closingOneOfTwoPanesDissolvesTheContainerAndReopenRegroupsItWithItsIdentityAndAnchor() throws {
            let s = try SplitSteps()
            let d = s.open("d"), e = s.open("e")
            let pair = s.split([d, e], .vertical, [0.25, 0.75])
            s.close([d], focus: d)
            #expect(s.group(pair.id) == nil)
            #expect(s.cache.next(in: s.f.store.state)?.membership?.dissolved == true)
            try s.reopen([d])
            #expect(s.group(pair.id)?.tabIDs == [d, e])
            #expect(s.group(pair.id)?.orientation == .vertical)
            #expect(s.approx(s.group(pair.id)?.widthFactors, [0.25, 0.75]))
            #expect(s.group(pair.id)?.sidebarAnchorID == pair.sidebarAnchorID)
            #expect(s.f.store.state.selectedTabIDs == [d, e])
            let disk = try BrowserStore(directory: s.f.directory)
            #expect(disk.state.splitLayouts.contains { $0.id == pair.id && $0.tabIDs == [d, e] })
        }

        @Test func twoOfFourPanesClosedReopenAtTheirAdjustedIndexesAndRestoreOrderAndRatios() throws {
            let s = try SplitSteps()
            let f = s.open("f"), g = s.open("g"), h = s.open("h"), i = s.open("i")
            let four = s.split([f, g, h, i], .horizontal, [0.1, 0.2, 0.3, 0.4])
            s.close([g, h], focus: h)
            #expect(s.group(four.id)?.tabIDs == [f, i])
            try s.reopen([h])
            #expect(s.group(four.id)?.tabIDs == [f, h, i])
            try s.reopen([g])
            #expect(s.group(four.id)?.tabIDs == [f, g, h, i])
            #expect(s.approx(s.group(four.id)?.widthFactors, [0.1, 0.2, 0.3, 0.4]))
        }

        @Test func twoOfThreeClosedTogetherDissolveAndRegroupWithTheSurvivorThenRejoin() throws {
            let s = try SplitSteps()
            let j = s.open("j"), k = s.open("k"), l = s.open("l")
            let trio = s.split([j, k, l], .horizontal, [0.5, 0.25, 0.25])
            s.close([k, l], focus: l)
            #expect(s.group(trio.id) == nil)
            try s.reopen([l])
            #expect(s.group(trio.id)?.tabIDs == [j, l])
            #expect(s.approx(s.group(trio.id)?.widthFactors, [2.0 / 3, 1.0 / 3]))
            try s.reopen([k])
            #expect(s.group(trio.id)?.tabIDs == [j, k, l])
            #expect(s.approx(s.group(trio.id)?.widthFactors, [0.5, 0.25, 0.25]))
        }

        @Test func aRefusedSurvivorLeavesThePaneAlone() throws {
            let s = try SplitSteps()
            let m = s.open("m"), n = s.open("n")
            let owned = s.split([m, n], .horizontal, [0.5, 0.5])
            s.close([n], focus: n)
            try s.reopen([n], regroupable: { $0 != m })
            #expect(s.group(owned.id) == nil)
            #expect(s.f.store.state.selectedTabIDs == [n])
        }

        @Test func aSurvivorShownInAnotherWindowRejoinsTheSplitWithItsGeometry() throws {
            let s = try SplitSteps()
            let shownElsewhere = NativePageOwnership(), thisWindow = UUID(), otherWindow = UUID()
            let survivor = s.open("survivor"), returning = s.open("returning")
            let shared = s.split([survivor, returning], .vertical, [0.4, 0.6])
            s.close([returning], focus: returning)
            #expect(shownElsewhere.claim(survivor, owner: otherWindow, page: "survivor-page"))
            try s.reopen([returning], regroupable: { id in
                shownElsewhere.canUse(id, owner: thisWindow) || (shownElsewhere.isClaimed(id) && shownElsewhere.claimSnapshot(id).transfer == nil)
            })
            #expect(s.group(shared.id)?.tabIDs == [survivor, returning])
            #expect(s.approx(s.group(shared.id)?.widthFactors, [0.4, 0.6]))
        }

        @Test func regroupingNeverStealsAPaneFromANewerGroup() throws {
            let s = try SplitSteps()
            let o = s.open("o"), p = s.open("p"), q = s.open("q")
            let left = s.split([o, p], .horizontal, [0.5, 0.5])
            s.close([p], focus: p)
            let other = s.split([o, q], .horizontal, [0.4, 0.6])
            try s.reopen([p])
            #expect(s.group(left.id) == nil)
            #expect(s.group(other.id)?.tabIDs == [o, q])
            #expect(s.f.store.state.selectedTabIDs == [p])
        }

        @Test func aGroupedSurvivorSkipsRegroupingEvenForTwoUngroupedReturningPanes() throws {
            let s = try SplitSteps()
            let o1 = s.open("o1"), o2 = s.open("o2"), o3 = s.open("o3"), o4 = s.open("o4")
            let skippedTrio = s.split([o1, o2, o3], .horizontal, [1, 1, 1])
            s.close([o2, o3], focus: o3)
            let elsewhere = s.split([o1, o4], .horizontal, [0.5, 0.5])
            try s.reopen([o3])
            #expect(s.group(skippedTrio.id) == nil)
            #expect(s.f.store.state.selectedTabIDs == [o3])
            try s.reopen([o2])
            #expect(s.group(skippedTrio.id) == nil)
            #expect(s.f.store.state.selectedTabIDs == [o2])
            #expect(s.group(elsewhere.id)?.tabIDs == [o1, o4])
        }

        @Test func aFourPaneContainerRefusesInsertionAndThePaneReturnsAlone() throws {
            let s = try SplitSteps()
            let r = s.open("r"), sPane = s.open("s"), t = s.open("t"), u = s.open("u"), v = s.open("v")
            let full = s.split([r, sPane, t], .horizontal, [1, 1, 1])
            s.close([sPane], focus: sPane)
            s.f.store.setSplit([r, t, u, v])
            #expect(s.group(full.id)?.tabIDs == [r, t, u, v])
            try s.reopen([sPane])
            #expect(s.group(full.id)?.tabIDs == [r, t, u, v])
            #expect(s.f.store.state.selectedTabIDs == [sPane])
        }

        @Test func fewerThanTwoExistingOriginalChildrenReturnsThePaneAlone() throws {
            let s = try SplitSteps()
            let w = s.open("w"), x = s.open("x")
            let lone = s.split([w, x], .horizontal, [0.5, 0.5])
            s.close([x], focus: x)
            s.close([w], focus: w)
            let skipped = try #require(s.cache.next(in: s.f.store.state))
            #expect(skipped.tabIDs == [w])
            #expect(skipped.membership == nil)
            #expect(s.cache.consume(skipped))
            try s.reopen([x])
            #expect(s.group(lone.id) == nil)
            #expect(s.f.store.state.selectedTabIDs == [x])
        }

        @Test func aChangedSplitContainerRecordsNoRegrouping() throws {
            let s = try SplitSteps()
            let y = s.open("y"), z = s.open("z"), zz = s.open("zz")
            let checked = s.split([y, z, zz], .horizontal, [1, 1, 1])
            let intent = ClosedItemIntent(ids: [z], state: s.f.store.state, spaceID: s.f.space, profileID: s.f.profile, focusedTabID: z)!
            s.f.store.closeTabs([z])
            var replaced = s.f.store.state
            replaced.splitLayouts[replaced.splitLayouts.firstIndex { $0.id == checked.id }!].id = UUID()
            #expect(intent.membership(of: z, in: replaced) == nil)
        }

        @Test func aMatchingSplitContainerRecordsTheOriginalPaneIndex() throws {
            let s = try SplitSteps()
            let y = s.open("y"), z = s.open("z"), zz = s.open("zz")
            _ = s.split([y, z, zz], .horizontal, [1, 1, 1])
            let intent = ClosedItemIntent(ids: [z], state: s.f.store.state, spaceID: s.f.space, profileID: s.f.profile, focusedTabID: z)!
            s.f.store.closeTabs([z])
            #expect(intent.membership(of: z, in: s.f.store.state)?.index == 1)
        }

        @Test func anyReopenOrderRebuildsTheOriginalPaneOrderAndRatiosOfAReorderedContainer() throws {
            let s = try SplitSteps()
            let p1 = s.open("p1"), p2 = s.open("p2"), p3 = s.open("p3")
            let reordered = s.split([p1, p3, p2], .horizontal, [0.5, 0.2, 0.3])
            s.close([p3, p2], focus: p2)
            #expect(s.group(reordered.id) == nil)
            try s.reopen([p3])
            #expect(s.group(reordered.id)?.tabIDs == [p1, p3])
            try s.reopen([p2])
            #expect(s.group(reordered.id)?.tabIDs == [p1, p3, p2])
            #expect(s.approx(s.group(reordered.id)?.widthFactors, [0.5, 0.2, 0.3]))
        }
    }
}
