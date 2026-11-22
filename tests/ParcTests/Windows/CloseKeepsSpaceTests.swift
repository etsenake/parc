import Foundation
import Testing
@testable import Parc

@MainActor private struct Scene {
    var state: BrowserState
    let home: BrowserSpace
    let elsewhere: BrowserTab
    var window: WindowPresentation
    var tabs: [BrowserTab]

    static func page(_ space: BrowserSpace, _ kind: TabKind = .today, accessed: TimeInterval = 0) -> BrowserTab {
        BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://example.test/", title: "Page", kind: kind,
                   createdAt: Date(timeIntervalSince1970: 0), lastAccessed: Date(timeIntervalSince1970: accessed),
                   savedURL: "https://example.test/", savedTitle: "Page")
    }

    init(kinds: [(TabKind, TimeInterval)], selected: [Int]) {
        var state = BrowserState.initial()
        let home = state.spaces[0]
        let other = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "112233", profileID: home.profileID)
        let elsewhere = Scene.page(other, accessed: 99)
        let tabs = kinds.map { Scene.page(home, $0.0, accessed: $0.1) }
        state.spaces.append(other)
        state.tabs = tabs + [elsewhere]
        state.selectionBySpace[other.id.uuidString] = [elsewhere.id]
        state.selectedTabIDs = selected.map { tabs[$0].id }
        self.state = state
        self.home = home
        self.elsewhere = elsewhere
        self.tabs = tabs
        window = WindowPresentation(state: state, ready: true)
    }

    func archived(_ ids: Set<UUID>) -> BrowserState {
        var next = state
        for index in next.tabs.indices where ids.contains(next.tabs[index].id) && next.tabs[index].kind == .today {
            next.tabs[index].archivedAt = Date(timeIntervalSince1970: 100)
        }
        next.selectedTabIDs.removeAll { ids.contains($0) }
        return next
    }

    mutating func engineSelects(_ id: UUID, state: BrowserState? = nil, closing: Set<UUID> = []) {
        guard window.admitsEngineSelection(of: id, closing: { closing.contains($0) }) else { return }
        _ = window.selectExistingTab(id, state: state ?? self.state, available: { _ in true })
    }

    func decide(_ removing: Set<UUID>) -> FolderRemovalSelection? {
        let space = state.spaces.first { $0.id == window.activeSpaceID }!
        return FolderRemovalSelection.resolve(removing: removing, spaceID: space.id, profileID: space.profileID, state: state,
            selected: window.selectedTabIDs, focused: window.preferredFocusedTabID, referrerPool: window.referrerPool,
            previouslySelectedItemID: window.previouslySelectedItemID, available: { _ in true })
    }
}

@MainActor struct CloseKeepsSpaceTests {
    @Test func closingTheLastTabEmptiesItsOwnSpace() throws {
        let scene = Scene(kinds: [(.today, 0)], selected: [0])
        let decision = try #require(scene.decide([scene.tabs[0].id]))
        #expect(decision.tabIDs.isEmpty && decision.replacementSpaceID == scene.home.id)
    }

    @Test func aSecondSpaceIsNotSelectedWhileTheLastTabIsClosing() {
        var scene = Scene(kinds: [(.today, 0)], selected: [0])
        let last = scene.tabs[0].id
        scene.engineSelects(scene.elsewhere.id, closing: [last])
        #expect(scene.window.activeSpaceID == scene.home.id && scene.window.selectedTabIDs == [last])
    }

    @Test func aSecondSpaceIsNotSelectedAfterTheLastTabCloses() {
        var scene = Scene(kinds: [(.today, 0)], selected: [0])
        scene.window.closePage(scene.tabs[0].id)
        scene.engineSelects(scene.elsewhere.id)
        #expect(!scene.window.selectedTabIDs.contains(scene.elsewhere.id))
        #expect(scene.window.activeSpaceID == scene.home.id)
    }

    @Test func theLastCloseLandsOnTheCurrentSpacesStartPage() throws {
        var scene = Scene(kinds: [(.today, 0)], selected: [0])
        let last = scene.tabs[0].id
        let decision = try #require(scene.decide([last]))
        scene.window.closePage(last)
        scene.engineSelects(scene.elsewhere.id)
        let landed = scene.archived([last])
        scene.window.reconcile(landed) { _ in true }
        #expect(scene.window.finishFolderRemoval(decision, state: landed, available: { _ in true })
                && scene.window.activeSpaceID == scene.home.id && scene.window.selectedTabIDs.isEmpty)
    }

    @Test func theEnginesPickStaysRefusedUntilTheWindowPushesItsOwnChoice() throws {
        var scene = Scene(kinds: [(.today, 0)], selected: [0])
        let last = scene.tabs[0].id
        let decision = try #require(scene.decide([last]))
        scene.window.closePage(last)
        let landed = scene.archived([last])
        scene.window.reconcile(landed) { _ in true }
        _ = scene.window.finishFolderRemoval(decision, state: landed, available: { _ in true })
        #expect(!scene.window.admitsEngineSelection(of: scene.elsewhere.id, closing: { _ in false }))
        scene.window.engineSelectionSynchronized()
        #expect(scene.window.admitsEngineSelection(of: scene.elsewhere.id, closing: { _ in false }))
    }

    @Test func undoBringsTheClosedTabBackIntoTheSameSpace() throws {
        var scene = Scene(kinds: [(.today, 0)], selected: [0])
        let last = scene.tabs[0].id
        let decision = try #require(scene.decide([last]))
        scene.window.closePage(last)
        var landed = scene.archived([last])
        scene.window.reconcile(landed) { _ in true }
        _ = scene.window.finishFolderRemoval(decision, state: landed, available: { _ in true })
        let undo = try #require(ClosedTabsUndo(prompt: .archive, ids: [last], spaceID: scene.home.id, profileID: scene.home.profileID,
                                               focusedTabID: last, before: scene.state, after: landed))
        landed = try #require(undo.restoring(landed))
        #expect(scene.window.finishClosedTabsUndo(undo, state: landed, available: { _ in true })
                && scene.window.activeSpaceID == scene.home.id && scene.window.selectedTabIDs == [last])
    }

    @Test func aLoneSpaceShowsItsStartPageNotAFavoriteTheEnginePicks() throws {
        var only = BrowserState.initial()
        let space = only.spaces[0]
        let lone = Scene.page(space), favorite = Scene.page(space, .favorite, accessed: 99)
        only.tabs = [lone, favorite]
        only.selectedTabIDs = [lone.id]
        var window = WindowPresentation(state: only, ready: true)
        let alone = try #require(FolderRemovalSelection.resolve(removing: [lone.id], spaceID: space.id, profileID: space.profileID, state: only,
            selected: window.selectedTabIDs, focused: window.preferredFocusedTabID, referrerPool: window.referrerPool,
            previouslySelectedItemID: window.previouslySelectedItemID, available: { _ in true }))
        #expect(alone.tabIDs.isEmpty && alone.replacementSpaceID == space.id)
        window.closePage(lone.id)
        if window.admitsEngineSelection(of: favorite.id, closing: { _ in false }) {
            _ = window.selectExistingTab(favorite.id, state: only, available: { _ in true })
        }
        var emptied = only
        emptied.tabs[0].archivedAt = Date(timeIntervalSince1970: 100)
        emptied.selectedTabIDs = []
        #expect(window.finishFolderRemoval(alone, state: emptied, available: { _ in true })
                && window.activeSpaceID == space.id && window.selectedTabIDs.isEmpty)
    }

    @Test func theEnginesPickOfAPaneStillOnScreenIsFollowed() {
        var scene = Scene(kinds: [(.today, 0), (.today, 0)], selected: [0, 1])
        scene.window.closePage(scene.tabs[0].id)
        #expect(scene.window.admitsEngineSelection(of: scene.tabs[1].id, closing: { _ in false }))
        #expect(!scene.window.admitsEngineSelection(of: scene.elsewhere.id, closing: { _ in false }))
    }

    @Test func closingTheLastTodayTabSelectsAPinnedTabInTheSameSpace() throws {
        var scene = Scene(kinds: [(.pinned, 0), (.today, 0)], selected: [1])
        let pinned = scene.tabs[0].id, today = scene.tabs[1].id
        let decision = try #require(scene.decide([today]))
        #expect(decision.tabIDs == [pinned] && decision.replacementSpaceID == scene.home.id)
        scene.window.closePage(today)
        scene.engineSelects(scene.elsewhere.id)
        let landed = scene.archived([today])
        #expect(scene.window.finishFolderRemoval(decision, state: landed, available: { _ in true })
                && scene.window.activeSpaceID == scene.home.id && scene.window.selectedTabIDs == [pinned])
    }

    @Test func closingATabReturnsToTheFavoriteSelectedJustBeforeIt() throws {
        var scene = Scene(kinds: [(.favorite, 0), (.today, 0)], selected: [0])
        let shared = scene.tabs[0].id, opened = scene.tabs[1].id
        _ = scene.window.selectExistingTab(opened, state: scene.state, available: { _ in true })
        scene.window.recordSelectionForReturn(opened, state: scene.state)
        let decision = try #require(scene.decide([opened]))
        #expect(decision.tabIDs == [shared] && decision.replacementSpaceID == scene.home.id)
        let landed = scene.archived([opened])
        scene.window.closePage(opened)
        #expect(scene.window.finishFolderRemoval(decision, state: landed, available: { _ in true })
                && scene.window.activeSpaceID == scene.home.id && scene.window.selectedTabIDs == [shared])
    }

    @Test func clearingTodayEmptiesTheCurrentSpaceAndStaysOnIt() throws {
        var scene = Scene(kinds: [(.today, 2), (.today, 1)], selected: [0])
        let ids = Set(scene.tabs.map(\.id))
        let wiped = try #require(scene.decide(ids))
        #expect(wiped.tabIDs.isEmpty && wiped.replacementSpaceID == scene.home.id)
        for id in ids { scene.window.closePage(id) }
        scene.engineSelects(scene.elsewhere.id)
        let cleared = scene.archived(ids)
        #expect(scene.window.finishFolderRemoval(wiped, state: cleared, available: { _ in true })
                && scene.window.activeSpaceID == scene.home.id && scene.window.selectedTabIDs.isEmpty)
    }

    @Test func aPageClosingItselfHandsOverToATabInItsOwnSpace() throws {
        var scene = Scene(kinds: [(.today, 2), (.today, 1)], selected: [0])
        let closer = scene.tabs[0].id, sibling = scene.tabs[1].id
        let handOver = try #require(scene.decide([closer]))
        scene.window.closePage(closer)
        #expect(scene.window.finishFolderRemoval(handOver, state: scene.state, available: { _ in true }))
        scene.engineSelects(scene.elsewhere.id)
        #expect(scene.window.activeSpaceID == scene.home.id && scene.window.selectedTabIDs == [sibling])
    }

    @Test func theLastPageClosingItselfLeavesItsOwnSpacesStartPage() throws {
        var scene = Scene(kinds: [(.today, 2)], selected: [0])
        let closer = scene.tabs[0].id
        let lastOut = try #require(scene.decide([closer]))
        scene.window.closePage(closer)
        #expect(scene.window.finishFolderRemoval(lastOut, state: scene.state, available: { _ in true })
                && scene.window.activeSpaceID == scene.home.id && scene.window.selectedTabIDs.isEmpty)
    }
}
