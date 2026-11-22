import Foundation
import Testing
@testable import ParcCore

@MainActor
struct TabCreationProvenanceTodayPlacementTests {
    @MainActor final class Placement {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store: BrowserStore
        let profile: UUID
        let space: UUID
        let older: UUID
        let newer: UUID

        init() throws {
            store = try BrowserStore(directory: directory)
            profile = store.activeSpace.profileID
            space = store.activeSpaceID
            older = store.open("https://older.example")
            newer = store.open("https://newer.example")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func today(_ state: BrowserState? = nil) -> [SidebarItemReference] {
            SidebarHierarchy.children(in: SidebarContainerLocation(spaceID: space, folderID: nil, section: .today),
                                      state: state ?? store.state)
        }

        func creationFrom(_ referrer: UUID?) -> TabCreationProvenance {
            TabCreationProvenance(referrerID: referrer, activeTabID: store.state.selectedTabIDs.first,
                                  profileID: profile, state: store.state)
        }

        func linked(_ id: UUID, referrer: UUID, spaceID: UUID? = nil) -> BrowserTab {
            BrowserTab(id: id, spaceID: spaceID ?? space, profileID: profile,
                       url: "https://linked.example/", title: "Linked", kind: .today, createdAt: Date(), lastAccessed: Date(),
                       savedURL: "https://linked.example/", savedTitle: "Linked", referrerID: referrer, activeTabBeforeCreationID: referrer)
        }

        func adopt(_ url: String, creation: TabCreationProvenance, insertion: TodayInsertion? = nil) -> UUID {
            let path = store.independentEngineProfilePath(for: profile)
            if let insertion {
                return store.adoptNativePage(url: URL(string: url), title: "Routed", profilePath: path, preferredSpaceID: space,
                                             select: false, creation: creation, insertion: insertion)!
            }
            return store.adoptNativePage(url: URL(string: url), title: "Adopted", profilePath: path, preferredSpaceID: space,
                                         select: false, creation: creation)!
        }
    }

    @Test func aTabWithoutAReferrerEntersAtTheTopOfToday() throws {
        let p = try Placement()
        #expect(p.today() == [.tab(p.newer), .tab(p.older)])
    }

    @Test func linkedTabsFollowTheirReferrerAndItsEarlierRunInCreationOrder() throws {
        let p = try Placement()
        let childA = p.store.open("https://child-a.example", creation: p.creationFrom(p.newer))
        let childB = p.store.open("https://child-b.example", creation: p.creationFrom(p.newer))
        #expect(p.today() == [.tab(p.newer), .tab(childA), .tab(childB), .tab(p.older)])
        let grandchild = p.store.open("https://grandchild.example", creation: p.creationFrom(childA))
        #expect(p.today() == [.tab(p.newer), .tab(childA), .tab(grandchild), .tab(childB), .tab(p.older)])
    }

    @Test func aPinnedReferrerStartsTheScanAtTheTopOfTodayAfterItsEarlierChildren() throws {
        let p = try Placement()
        let pinnedSource = p.store.open("https://pinned-source.example", kind: .pinned)
        #expect(!p.today().contains(.tab(pinnedSource)))
        let a = p.store.open("https://from-pinned-a.example", creation: p.creationFrom(pinnedSource))
        let b = p.store.open("https://from-pinned-b.example", creation: p.creationFrom(pinnedSource))
        #expect(Array(p.today().prefix(3)) == [.tab(a), .tab(b), .tab(p.newer)])
    }

    @Test func aReferrerOutsideThisTodayListDoesNotMoveTheTabBelowUnrelatedItems() throws {
        let p = try Placement()
        var spaced = p.store.state
        let elsewhere = BrowserSpace(id: UUID(), name: "Elsewhere", symbol: "circle", color: "123456", profileID: p.profile)
        spaced.spaces.append(elsewhere)
        let otherTab = UUID(), foreignSpaceChild = UUID()
        spaced.tabs.append(p.linked(otherTab, referrer: p.newer, spaceID: elsewhere.id))
        spaced.tabs.append(p.linked(foreignSpaceChild, referrer: otherTab))
        SidebarHierarchy.placingCreatedTab(foreignSpaceChild, insertion: .automatic, in: &spaced)
        #expect(p.today(spaced).first == .tab(foreignSpaceChild))
    }

    @Test func aSplitPaneReferrerPlacesTheTabAfterItsWholeSplitItem() throws {
        let p = try Placement()
        var spaced = p.store.state
        let splitLayout = BrowserSplitLayout(sidebarAnchorID: p.newer, spaceID: p.space, tabIDs: [p.newer, p.older],
                                             orientation: .vertical, widthFactors: [0.5, 0.5])
        spaced.splitLayouts = [splitLayout]
        let fromSplit = UUID()
        spaced.tabs.append(p.linked(fromSplit, referrer: p.older))
        SidebarHierarchy.placingCreatedTab(fromSplit, insertion: .automatic, in: &spaced)
        let order = p.today(spaced)
        #expect(order.firstIndex(of: .tab(fromSplit)) == order.firstIndex(of: .split(splitLayout.id)).map { $0 + 1 })
    }

    @Test func theScanStopsAtTheFirstItemNotOpenedFromTheReferrer() throws {
        let p = try Placement()
        let childA = p.store.open("https://child-a.example", creation: p.creationFrom(p.newer))
        let grandchild = p.store.open("https://grandchild.example", creation: p.creationFrom(childA))
        var spaced = p.store.state
        let beforeSplit = UUID()
        spaced.tabs.append(p.linked(beforeSplit, referrer: grandchild))
        SidebarHierarchy.placingCreatedTab(beforeSplit, insertion: .automatic, in: &spaced)
        let order = p.today(spaced)
        #expect(order.firstIndex(of: .tab(beforeSplit)) == order.firstIndex(of: .tab(grandchild)).map { $0 + 1 })
    }

    @Test func explicitTopPlacementKeepsProvenanceButIgnoresTheReferrerRun() throws {
        let p = try Placement()
        let routedTop = p.adopt("https://routed.example", creation: p.creationFrom(p.newer), insertion: .top)
        #expect(p.today().first == .tab(routedTop))
        #expect(p.store.state.tabs.first { $0.id == routedTop }?.referrerID == p.newer)
    }

    @Test func nativeBackgroundAdoptionUsesTheSameReferrerPlacementWithoutChangingSelection() throws {
        let p = try Placement()
        let childB = p.store.open("https://child-b.example", creation: p.creationFrom(p.newer))
        let selection = p.store.state.selectedTabIDs
        let adopted = p.adopt("https://adopted.example", creation: p.creationFrom(childB))
        #expect(p.today().firstIndex(of: .tab(adopted)) == p.today().firstIndex(of: .tab(childB)).map { $0 + 1 })
        #expect(p.store.state.selectedTabIDs == selection)
    }

    @Test func closingAModalSourcedTabReturnsToItsSourceNotItsTodayNeighbour() throws {
        let p = try Placement()
        let pinnedSource = p.store.open("https://pinned-source.example", kind: .pinned)
        let childA = p.store.open("https://child-a.example", creation: p.creationFrom(p.newer))
        var window = WindowPresentation(state: p.store.state, ready: true)
        p.store.selectTab(childA)
        let fromModal = p.store.open("https://from-modal.example", creation: p.creationFrom(pinnedSource))
        window.recordCreation(fromModal, state: p.store.state)
        #expect(window.referrerPool == [pinnedSource, fromModal])
        let decision = FolderRemovalSelection.resolve(removing: [fromModal], spaceID: p.space, profileID: p.profile,
            state: p.store.state, selected: [fromModal], focused: fromModal, referrerPool: window.referrerPool,
            available: { _ in true })
        #expect(decision?.tabIDs == [pinnedSource])
    }

    @Test func aCrossProfileRoutedPageTakesTheTopWithoutEitherSourceIdentity() throws {
        let p = try Placement()
        let childA = p.store.open("https://child-a.example", creation: p.creationFrom(p.newer))
        p.store.selectTab(childA)
        let receipt = TabCreationProvenance(routedFrom: nil, openedLink: true, profileID: p.profile, state: p.store.state)
        let crossProfile = p.adopt("https://cross-profile.example", creation: receipt, insertion: .top)
        let crossTab = try #require(p.store.state.tabs.first { $0.id == crossProfile })
        #expect(p.today().first == .tab(crossProfile) && crossTab.referrerID == nil && crossTab.activeTabBeforeCreationID == nil)
    }

    @Test func aCrossProfileRoutedPageLeavesNoCreationChain() throws {
        let p = try Placement()
        let childA = p.store.open("https://child-a.example", creation: p.creationFrom(p.newer))
        p.store.selectTab(childA)
        let receipt = TabCreationProvenance(routedFrom: nil, openedLink: true, profileID: p.profile, state: p.store.state)
        let crossProfile = p.adopt("https://cross-profile.example", creation: receipt, insertion: .top)
        var destination = WindowPresentation(state: p.store.state, ready: true)
        destination.recordSelectionForReturn(childA, state: p.store.state)
        destination.recordCreation(crossProfile, state: p.store.state)
        destination.recordSelectionForReturn(crossProfile, state: p.store.state)
        #expect(destination.referrerPool.isEmpty)
    }

    @Test func closingACrossProfileRoutedPageDoesNotReturnToTheOtherSource() throws {
        let p = try Placement()
        let childA = p.store.open("https://child-a.example", creation: p.creationFrom(p.newer))
        p.store.selectTab(childA)
        let receipt = TabCreationProvenance(routedFrom: nil, openedLink: true, profileID: p.profile, state: p.store.state)
        let crossProfile = p.adopt("https://cross-profile.example", creation: receipt, insertion: .top)
        var destination = WindowPresentation(state: p.store.state, ready: true)
        destination.recordSelectionForReturn(childA, state: p.store.state)
        destination.recordCreation(crossProfile, state: p.store.state)
        destination.recordSelectionForReturn(crossProfile, state: p.store.state)
        let crossReturn = FolderRemovalSelection.resolve(removing: [crossProfile], spaceID: p.space, profileID: p.profile,
            state: p.store.state, selected: [crossProfile], focused: crossProfile, referrerPool: destination.referrerPool,
            available: { _ in true })
        #expect(crossReturn?.tabIDs != [childA])
    }

    @Test func aMatchedLinkTakesTheTopAndRecordsOnlyItsActiveBeforeSource() throws {
        let p = try Placement()
        let source = p.store.open("https://from-pinned-a.example")
        let receipt = TabCreationProvenance(routedFrom: source, openedLink: true, profileID: p.profile, state: p.store.state)
        let openedLink = p.adopt("https://opened-link.example", creation: receipt, insertion: .top)
        let tab = try #require(p.store.state.tabs.first { $0.id == openedLink })
        #expect(p.today().first == .tab(openedLink) && tab.referrerID == nil && tab.activeTabBeforeCreationID == source)
    }

    @Test func creationPlacementIsPartOfTheDurableTodayOrder() throws {
        let p = try Placement()
        _ = p.store.open("https://child-a.example", creation: p.creationFrom(p.newer))
        _ = p.adopt("https://routed.example", creation: p.creationFrom(p.newer), insertion: .top)
        try p.store.save()
        let reloaded = try BrowserStore(directory: p.directory)
        #expect(p.today(reloaded.state) == p.today())
    }
}
