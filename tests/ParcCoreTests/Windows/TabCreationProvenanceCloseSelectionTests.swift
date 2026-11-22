import Foundation
import Testing
@testable import ParcCore

@MainActor
struct TabCreationProvenanceCloseSelectionTests {
    private typealias Fixture = TabCreationProvenanceTestsSupport.Fixture

    @Test func theWindowPoolIsNotSynthesizedFromPersistedSelection() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        window.recordSelectionForReturn(f.current.id, state: f.state)
        #expect(window.referrerPool.isEmpty)
    }

    @Test func creationWithoutAReferrerReplacesThePool() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        var creationState = f.state
        let first = f.tab(previous: f.current.id), second = f.tab(referrer: f.current.id, previous: f.current.id)
        creationState.tabs += [first, second]
        window.recordCreation(first.id, state: creationState)
        #expect(window.referrerPool == [f.current.id, first.id])
    }

    @Test func creationWithAReferrerExtendsTheExistingPool() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        var creationState = f.state
        let first = f.tab(previous: f.current.id), second = f.tab(referrer: f.current.id, previous: f.current.id)
        creationState.tabs += [first, second]
        window.recordCreation(first.id, state: creationState)
        window.recordCreation(second.id, state: creationState)
        #expect(window.referrerPool == [f.current.id, first.id, second.id])
    }

    @Test func refreshingFocusKeepsTheCreationChain() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        var creationState = f.state
        let first = f.tab(previous: f.current.id), second = f.tab(referrer: f.current.id, previous: f.current.id)
        creationState.tabs += [first, second]
        window.recordCreation(first.id, state: creationState)
        window.recordCreation(second.id, state: creationState)
        window.recordSelectionForReturn(f.current.id, state: creationState)
        #expect(window.referrerPool.count == 3)
        window.recordSelectionForReturn(second.id, state: creationState)
    }

    @Test func selectingAPooledTodayTabKeepsTheCreationChain() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        var creationState = f.state
        let first = f.tab(previous: f.current.id), second = f.tab(referrer: f.current.id, previous: f.current.id)
        creationState.tabs += [first, second]
        window.recordCreation(first.id, state: creationState)
        window.recordCreation(second.id, state: creationState)
        window.recordSelectionForReturn(f.current.id, state: creationState)
        #expect(window.referrerPool.count == 3)
        #expect(window.referrerPool.count == 3)
        window.recordCreation(f.parent.id, state: creationState)
    }

    @Test func recordingAnExistingTabDoesNotDisplaceTheCreationChain() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        var creationState = f.state
        let first = f.tab(previous: f.current.id), second = f.tab(referrer: f.current.id, previous: f.current.id)
        creationState.tabs += [first, second]
        window.recordCreation(first.id, state: creationState)
        window.recordCreation(second.id, state: creationState)
        window.recordSelectionForReturn(f.current.id, state: creationState)
        #expect(window.referrerPool.count == 3)
        #expect(window.referrerPool.count == 3)
        #expect(window.referrerPool.count == 3)
    }

    @Test func selectingAPooledPinnedTabKeepsOnlyThatTab() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        var creationState = f.state
        let pinnedChild = f.tab(.pinned, referrer: f.current.id, previous: f.current.id)
        creationState.tabs.append(pinnedChild)
        window.recordCreation(pinnedChild.id, state: creationState)
        window.recordSelectionForReturn(pinnedChild.id, state: creationState)
        #expect(window.referrerPool == [pinnedChild.id])
    }

    @Test func selectingAnUnrelatedTabClearsThePool() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        var creationState = f.state
        let pinnedChild = f.tab(.pinned, referrer: f.current.id, previous: f.current.id)
        creationState.tabs.append(pinnedChild)
        window.recordCreation(pinnedChild.id, state: creationState)
        window.recordSelectionForReturn(pinnedChild.id, state: creationState)
        window.recordSelectionForReturn(f.previous.id, state: creationState)
        #expect(window.referrerPool.isEmpty)
    }

    @Test func anotherPhysicalWindowNeverReceivesTheChain() {
        let f = Fixture()
        var window = WindowPresentation(state: f.state, ready: true)
        let peer = WindowPresentation(state: f.state, ready: true)
        let first = f.tab(previous: f.current.id)
        var creationState = f.state
        creationState.tabs.append(first)
        window.recordCreation(first.id, state: creationState)
        #expect(peer.referrerPool.isEmpty)
    }

    @Test func anAdjacentGenuineChildWinsOverTheOrdinaryPreviousItem() {
        let f = Fixture()
        #expect(f.choose()?.tabIDs == [f.child.id])
    }

    enum SiblingPool: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case both = "Closing tab and sibling are pooled"
        case empty = "No pooled tabs"
        case siblingOnly = "Only the sibling is pooled"

        var testDescription: String { rawValue }
    }

    @Test(arguments: SiblingPool.allCases)
    func aSubsequentSiblingTakesPriorityOnlyWhenBothTabsArePooled(_ pool: SiblingPool) {
        let f = Fixture()
        var siblings = f.state
        siblings.tabs.removeAll { $0.id == f.child.id }
        let sibling = f.tab(referrer: f.parent.id), unrelated = f.tab()
        siblings.tabs[f.index(f.current.id, in: siblings)].referrerID = f.parent.id
        siblings.tabs += [unrelated, sibling]
        let pooled: Set<UUID> = switch pool {
        case .both: [f.current.id, sibling.id]
        case .empty: []
        case .siblingOnly: [sibling.id]
        }
        let expected = pool == .both ? sibling.id : f.previous.id
        #expect(f.choose(siblings, pool: pooled)?.tabIDs == [expected])
    }

    private func activeBeforeState(_ f: Fixture) -> BrowserState {
        var active = f.state
        active.tabs.removeAll { $0.id == f.child.id }
        active.tabs[f.index(f.current.id, in: active)].activeTabBeforeCreationID = f.parent.id
        return active
    }

    @Test func theOriginalActiveBeforeWinsOverAnUnrelatedAdjacentItem() {
        let f = Fixture()
        let active = activeBeforeState(f)
        #expect(f.choose(active, pool: [f.parent.id])?.tabIDs == [f.parent.id])
    }

    @Test func anUnavailableOriginalActiveBeforeGivesWayToTheAdjacentItem() {
        let f = Fixture()
        let active = activeBeforeState(f)
        #expect(f.choose(active, pool: [f.parent.id], unavailable: [f.parent.id])?.tabIDs == [f.previous.id])
    }

    struct ReturnCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let kind: TabKind
        let differentProfile: Bool
        let returnsToParent: Bool
    }

    @Test(arguments: [
        ReturnCase(testDescription: "Pinned tab in another Space", kind: .pinned, differentProfile: false, returnsToParent: false),
        ReturnCase(testDescription: "Favorite in another Space", kind: .favorite, differentProfile: false, returnsToParent: true),
        ReturnCase(testDescription: "Favorite in another Profile", kind: .favorite, differentProfile: true, returnsToParent: false),
    ])
    func returningToATabRespectsItsSpaceAndProfile(_ destination: ReturnCase) {
        let f = Fixture()
        var active = activeBeforeState(f)
        let otherSpace = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "123456", profileID: f.profile)
        active.spaces.append(otherSpace)
        let parentIndex = f.index(f.parent.id, in: active)
        active.tabs[parentIndex].spaceID = otherSpace.id
        active.tabs[parentIndex].kind = destination.kind
        if destination.differentProfile { active.tabs[parentIndex].profileID = UUID() }
        let expected = destination.returnsToParent ? f.parent.id : f.previous.id
        #expect(f.choose(active, pool: [f.parent.id])?.tabIDs == [expected])
    }

    @Test func returningToACompleteSplitPreservesEveryPane() {
        let f = Fixture()
        var splitState = activeBeforeState(f)
        let partner = f.tab(.pinned)
        splitState.tabs.append(partner)
        splitState.splitLayouts = [BrowserSplitLayout(spaceID: f.space.id, tabIDs: [f.parent.id, partner.id],
                                                      orientation: .vertical, widthFactors: [0.4, 0.6])]
        #expect(f.choose(splitState, pool: [f.parent.id])?.tabIDs == [f.parent.id, partner.id])
    }

    @Test func aSplitWithAnUnavailablePaneCannotBeTheReturnSelection() {
        let f = Fixture()
        var splitState = activeBeforeState(f)
        let partner = f.tab(.pinned)
        splitState.tabs.append(partner)
        splitState.splitLayouts = [BrowserSplitLayout(spaceID: f.space.id, tabIDs: [f.parent.id, partner.id],
                                                      orientation: .vertical, widthFactors: [0.4, 0.6])]
        #expect(f.choose(splitState, pool: [f.parent.id], unavailable: [partner.id])?.tabIDs == [f.previous.id])
    }

    @Test func closingBackgroundItemsPreservesTheExactActiveSelection() throws {
        let f = Fixture()
        let background = try #require(FolderRemovalSelection.resolve(removing: [f.parent.id], spaceID: f.space.id,
            profileID: f.profile, state: f.state, selected: [f.current.id], focused: f.current.id,
            referrerPool: [f.parent.id], available: { _ in true }))
        #expect(background.tabIDs == [f.current.id])
    }

    @Test func aSurvivingOriginalPanePrecedesReturnCandidates() {
        let f = Fixture()
        let surviving = FolderRemovalSelection.resolve(removing: [f.current.id], spaceID: f.space.id, profileID: f.profile,
            state: f.state, selected: [f.current.id, f.previous.id], focused: f.current.id, available: { _ in true })
        #expect(surviving?.tabIDs == [f.previous.id])
    }

    @Test func aSavedCloseAppliesItsReplacementWithoutDeletingTheBookmark() throws {
        let f = Fixture()
        var savedState = f.state
        savedState.tabs[f.index(f.current.id, in: savedState)].kind = .pinned
        let decision = try #require(f.choose(savedState))
        var savedWindow = WindowPresentation(state: savedState, ready: true)
        savedWindow.remove(f.current.id)
        let finished = savedWindow.finishFolderRemoval(decision, state: savedState, available: { _ in true })
        #expect(finished)
        #expect(savedState.tabs.contains { $0.id == f.current.id && $0.archivedAt == nil })
    }

    @Test func aLaterSelectionWinsOverADelayedSavedClose() throws {
        let f = Fixture()
        var savedState = f.state
        savedState.tabs[f.index(f.current.id, in: savedState)].kind = .pinned
        let decision = try #require(f.choose(savedState))
        var newer = WindowPresentation(state: savedState, ready: true)
        _ = newer.selectExistingTab(f.parent.id, state: savedState, available: { _ in true })
        let lateFinish = newer.finishFolderRemoval(decision, state: savedState, available: { _ in true })
        #expect(!lateFinish)
    }
}
