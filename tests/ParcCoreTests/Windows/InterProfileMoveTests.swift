import Foundation
import Testing
@testable import ParcCore

struct InterProfileMoveTests {
    struct Fixture {
        var state: BrowserState
        let p: BrowserProfile, q: BrowserProfile
        let s: BrowserSpace, d: BrowserSpace
        let today: BrowserTab, pinned: BrowserTab, g1: BrowserTab, g2: BrowserTab, sibling: BrowserTab
        let d1: BrowserTab, d2: BrowserTab
        let group: BrowserSplitLayout
        let root: SidebarContainerLocation
        let now = Date(timeIntervalSince1970: 99)

        init() {
            let p = BrowserProfile(id: UUID(), name: "Personal"), q = BrowserProfile(id: UUID(), name: "Work")
            let s = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "AABBCC", profileID: p.id)
            let d = BrowserSpace(id: UUID(), name: "Office", symbol: "circle", color: "AABBCC", profileID: q.id)
            func tab(_ space: BrowserSpace, _ kind: TabKind, _ name: String) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://live.invalid/" + name,
                    title: "Live " + name, kind: kind, folderID: nil, createdAt: Date(timeIntervalSince1970: 1),
                    lastAccessed: Date(timeIntervalSince1970: 2), savedURL: "https://saved.invalid/" + name, savedTitle: "Saved " + name)
            }
            var today = tab(s, .today, "today")
            today.referrerID = UUID()
            let pinned = tab(s, .pinned, "pinned"), sibling = tab(s, .pinned, "sibling")
            let g1 = tab(s, .today, "g1"), g2 = tab(s, .today, "g2")
            let d1 = tab(d, .today, "d1"), d2 = tab(d, .today, "d2")
            let group = BrowserSplitLayout(sidebarAnchorID: g1.id, customTitle: "Pair", spaceID: s.id, tabIDs: [g1.id, g2.id],
                                           orientation: .vertical, widthFactors: [0.4, 0.6])
            var state = BrowserState(profiles: [p, q], spaces: [s, d], activeSpaceID: d.id)
            state.tabs = [today, pinned, sibling, g1, g2, d1, d2]
            state.splitLayouts = [group]
            let root = SidebarContainerLocation(spaceID: s.id, folderID: nil, section: .pinned)
            state.sidebarItemOrder[root.key] = [.tab(sibling.id), .tab(pinned.id)]
            state.selectedTabIDs = [d1.id]
            state.selectionBySpace = [s.id.uuidString: [pinned.id], d.id.uuidString: [d1.id]]
            self.state = state
            self.p = p; self.q = q; self.s = s; self.d = d
            self.today = today; self.pinned = pinned; self.sibling = sibling; self.g1 = g1; self.g2 = g2
            self.d1 = d1; self.d2 = d2; self.group = group; self.root = root
        }

        func request(_ source: BrowserTab, target: SplitDropTarget = .insert(1), selection: [UUID]? = nil,
                     layout: BrowserSplitLayout? = nil, home: UUID = UUID(), homes: [UUID: UUID] = [:]) -> ForeignSplitDrop.Request {
            ForeignSplitDrop.Request(source: source, sourceHomeID: home, spaceID: d.id, profileID: q.id,
                selection: selection ?? [d1.id], layout: layout, target: target, orientation: .horizontal, destinationHomeIDs: homes)
        }

        func propose(_ r: ForeignSplitDrop.Request, _ state: BrowserState? = nil) -> BrowserState? {
            ForeignSplitDrop.proposal(r, state: state ?? self.state, now: now, creation: nil)
        }

        func setting(_ index: Int, url: String) -> BrowserState {
            var copy = state
            copy.tabs[index].url = url
            copy.tabs[index].savedURL = url
            return copy
        }

        func groupedDestination() -> (BrowserState, BrowserSplitLayout) {
            var grouped = state
            let layout = BrowserSplitLayout(spaceID: d.id, tabIDs: [d1.id, d2.id], orientation: .horizontal, widthFactors: [0.5, 0.5])
            grouped.splitLayouts.append(layout)
            grouped.selectedTabIDs = layout.tabIDs
            grouped.selectionBySpace[d.id.uuidString] = layout.tabIDs
            return (grouped, layout)
        }
    }

    @Test func anEmptyMoveProceeds() {
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [], destination: UUID(), decision: nil, bypass: false) == .proceed(remembersChoice: false))
    }

    @Test func theSameProfileProceedsWithoutAPrompt() {
        let q = UUID()
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [q], destination: q, decision: nil, bypass: false) == .proceed(remembersChoice: false))
    }

    @Test func multipleSourceProfilesRefuse() {
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [UUID(), UUID()], destination: UUID(), decision: .proceed, bypass: true) == nil)
    }

    @Test func theUnregisteredDefaultAsks() {
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [UUID()], destination: UUID(), decision: nil, bypass: false) == .confirm)
    }

    @Test func aRememberedBypassSkipsTheDialog() {
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [UUID()], destination: UUID(), decision: nil, bypass: true) == .proceed(remembersChoice: false))
    }

    @Test func abortCancels() {
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [UUID()], destination: UUID(), decision: .abort, bypass: true) == .abort)
    }

    @Test func proceedMovesOnce() {
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [UUID()], destination: UUID(), decision: .proceed, bypass: false) == .proceed(remembersChoice: false))
    }

    @Test func alwaysProceedStoresThePreference() {
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [UUID()], destination: UUID(), decision: .alwaysProceed, bypass: false) == .proceed(remembersChoice: true))
    }

    @Test func theSingularPromptNamesTheTabAndSpace() {
        let one = InterProfileMovePrompt(tabCount: 1, spaceName: "Work")
        #expect(one.title == "Move tab to Work?")
        #expect(one.message == "Work uses different data, so you might get logged out or lose your progress in this tab.\n\nThis can't be undone!")
    }

    @Test func thePluralPromptSaysTabs() {
        let many = InterProfileMovePrompt(tabCount: 3, spaceName: "Work")
        #expect(many.title == "Move tabs to Work?")
        #expect(many.message.contains("progress in these tabs."))
    }

    @Test func twentyFourCharactersFit() {
        #expect(InterProfileMovePrompt.displayName("123456789012345678901234") == "123456789012345678901234")
    }

    @Test func truncationTrimsThenAppendsAnEllipsis() {
        #expect(InterProfileMovePrompt.displayName("12345678901234567890123 5") == "12345678901234567890123…")
    }

    @Test func theDialogControlsAreTheRecoveredOnes() {
        #expect(InterProfileMovePrompt.confirmTitle == "Move it")
        #expect(InterProfileMovePrompt.cancelTitle == "Cancel")
        #expect(InterProfileMovePrompt.suppressionTitle == "Don’t ask again")
        #expect(InterProfileMovePrompt.dialogWidth == 455)
    }

    @Test(arguments: [(true, false, InterProfileMoveDecision.proceed), (true, true, .alwaysProceed), (false, true, .abort)])
    func theDialogDecisionMapsFromItsButtons(_ confirmed: Bool, _ suppressed: Bool, _ expected: InterProfileMoveDecision) {
        #expect(InterProfileMovePrompt.decision(confirmed: confirmed, suppressed: suppressed) == expected)
    }

    @Test func anUntitledSpaceUsesSpaceN() {
        var state = BrowserState.initial()
        state.spaces.append(BrowserSpace(id: UUID(), name: "", symbol: "circle", color: "B9B5D4", profileID: state.profiles[0].id))
        #expect(InterProfileMovePrompt(tabCount: 1, destinationSpaceID: state.spaces[1].id, state: state)?.destinationName == "Space 2")
    }

    @Test func aTodayOriginalCrossesProfilesCarryingTheDestinationProfileAndSpace() throws {
        let f = Fixture()
        let moved = try #require(f.propose(f.request(f.today)))
        let live = try #require(moved.tabs.first { $0.id == f.today.id })
        #expect(live.profileID == f.q.id)
        #expect(live.spaceID == f.d.id)
        #expect(live.kind == .today)
        #expect(live.folderID == nil)
    }

    @Test func theOriginalKeepsItsIdentityAddressAndProvenance() throws {
        let f = Fixture()
        let moved = try #require(f.propose(f.request(f.today)))
        let live = try #require(moved.tabs.first { $0.id == f.today.id })
        #expect(live.url == f.today.url)
        #expect(live.title == f.today.title)
        #expect(live.referrerID == f.today.referrerID)
    }

    @Test func theDestinationGroupPublishesWithTheOriginal() throws {
        let f = Fixture()
        let moved = try #require(f.propose(f.request(f.today)))
        #expect(moved.selectedTabIDs == [f.d1.id, f.today.id])
        #expect(moved.splitLayouts.contains { $0.tabIDs == [f.d1.id, f.today.id] && $0.spaceID == f.d.id })
    }

    @Test func aTodayMoveCreatesNoCopy() throws {
        let f = Fixture()
        #expect(try #require(f.propose(f.request(f.today))).tabs.count == f.state.tabs.count)
    }

    @Test func aPinnedOriginalLeavesAFreshHomeInTheSourceProfileWithTheSavedDestination() throws {
        let f = Fixture()
        let home = UUID()
        let saved = try #require(f.propose(f.request(f.pinned, home: home)))
        let copy = try #require(saved.tabs.first { $0.id == home })
        #expect(copy.profileID == f.p.id)
        #expect(copy.spaceID == f.s.id)
        #expect(copy.kind == .pinned)
        #expect(copy.url == f.pinned.savedURL)
        #expect(copy.title == f.pinned.savedTitle)
    }

    @Test func theHomeReplacesTheExactSourceParentSlot() throws {
        let f = Fixture()
        let home = UUID()
        let saved = try #require(f.propose(f.request(f.pinned, home: home)))
        #expect(SidebarHierarchy.children(in: f.root, state: saved) == [.tab(f.sibling.id), .tab(home)])
    }

    @Test func theSourceSpaceRemembersTheHomeNotTheMovedOriginal() throws {
        let f = Fixture()
        let home = UUID()
        let saved = try #require(f.propose(f.request(f.pinned, home: home)))
        #expect(saved.selectionBySpace[f.s.id.uuidString] == [home])
    }

    @Test func theLiveOriginalBecomesDestinationToday() throws {
        let f = Fixture()
        let saved = try #require(f.propose(f.request(f.pinned)))
        #expect(saved.tabs.first { $0.id == f.pinned.id }?.kind == .today)
        #expect(saved.tabs.first { $0.id == f.pinned.id }?.profileID == f.q.id)
    }

    @Test func aCollidingHomeIdentityRefuses() {
        let f = Fixture()
        #expect(f.propose(f.request(f.pinned, home: f.sibling.id)) == nil)
    }

    @Test func aTwoMemberSourceSplitDissolvesAndTheSurvivorIsIntact() throws {
        let f = Fixture()
        let child = try #require(f.propose(f.request(f.g2)))
        #expect(!child.splitLayouts.contains { $0.id == f.group.id })
        #expect(child.tabs.first { $0.id == f.g1.id } == f.g1)
    }

    private func threeMemberSource(_ f: Fixture) -> (BrowserState, UUID) {
        var three = f.state
        let g3 = BrowserTab(id: UUID(), spaceID: f.s.id, profileID: f.p.id, url: "https://live.invalid/g3", title: "g3", kind: .today,
                            folderID: nil, createdAt: .distantPast, lastAccessed: .distantPast, savedURL: "https://live.invalid/g3", savedTitle: "g3")
        three.tabs.append(g3)
        three.splitLayouts[0].tabIDs = [f.g1.id, f.g2.id, g3.id]
        three.splitLayouts[0].widthFactors = [0.2, 0.3, 0.5]
        return (three, g3.id)
    }

    @Test func theSurvivingSourceGroupKeepsItsIdentityAppearanceAndReanchors() throws {
        let f = Fixture()
        let (three, g3) = threeMemberSource(f)
        let moved = try #require(f.propose(f.request(f.g1), three))
        let kept = try #require(moved.splitLayouts.first { $0.id == f.group.id })
        #expect(kept.tabIDs == [f.g2.id, g3])
        #expect(kept.sidebarAnchorID == f.g2.id)
        #expect(kept.customTitle == "Pair")
        #expect(kept.orientation == .vertical)
    }

    @Test func theSurvivingProportionsRenormalize() throws {
        let f = Fixture()
        let (three, _) = threeMemberSource(f)
        let moved = try #require(f.propose(f.request(f.g1), three))
        let kept = try #require(moved.splitLayouts.first { $0.id == f.group.id })
        #expect(abs(kept.widthFactors.reduce(0, +) - 1) < 0.0001)
    }

    @Test func aDropCanJoinAnExistingDestinationGroupKeepingItsIdentity() throws {
        let f = Fixture()
        let (grouped, layout) = f.groupedDestination()
        let joined = try #require(f.propose(f.request(f.today, target: .insert(2), selection: layout.tabIDs, layout: layout), grouped))
        #expect(joined.splitLayouts.first { $0.id == layout.id }?.tabIDs == [f.d1.id, f.d2.id, f.today.id])
    }

    @Test func centerReplacementKeepsTheDisplacedPage() throws {
        let f = Fixture()
        let replaced = try #require(f.propose(f.request(f.today, target: .replace(0))))
        #expect(replaced.selectedTabIDs == [f.today.id])
        #expect(replaced.tabs.contains { $0.id == f.d1.id && $0.archivedAt == nil })
    }

    @Test func aTodayEaselCrossesProfilesAndItsDocumentMovesToTheDestinationStore() throws {
        let f = Fixture()
        let easelID = UUID()
        let easelState = f.setting(0, url: InternalPage.easel(easelID).urlString)
        let moved = try #require(f.propose(f.request(easelState.tabs[0]), easelState))
        #expect(InterProfileMove.documents(moving: [f.today.id], after: moved) == [.easel(easelID)])
    }

    @Test func anEaselWaitingAheadOfThePageMovesWithIt() throws {
        let f = Fixture()
        let easelID = UUID()
        var ahead = f.state
        ahead.tabs[0].openDocumentVisit(.easel(easelID), title: "Board")
        _ = ahead.tabs[0].stepBackFromNote()
        let moved = try #require(f.propose(f.request(ahead.tabs[0]), ahead))
        #expect(InterProfileMove.documents(moving: [f.today.id], after: moved) == [.easel(easelID)])
    }

    @Test func everyEaselInTheTabsHistoryMovesWithItBehindAndAheadOfTheShownNote() throws {
        let f = Fixture()
        let easelID = UUID(), laterEasel = UUID()
        var stacked = f.state
        stacked.tabs[0].openDocumentVisit(.easel(easelID), title: "Board")
        stacked.tabs[0].openDocumentVisit(.note(URL(fileURLWithPath: "/tmp/Parc Notes/Plan.md")), title: "Plan")
        stacked.tabs[0].openDocumentVisit(.easel(laterEasel), title: "Later")
        _ = stacked.tabs[0].stepNoteVisit(by: -1)
        let moved = try #require(f.propose(f.request(stacked.tabs[0]), stacked))
        #expect(InterProfileMove.documents(moving: [f.today.id], after: moved) == [.easel(easelID), .easel(laterEasel)])
    }

    @Test func aHomeAliasLeftInTheSourceProfileKeepsTheEaselThere() throws {
        let f = Fixture()
        var pinnedEasel = f.state
        let url = InternalPage.easel(UUID()).urlString
        pinnedEasel.tabs[1].url = url
        pinnedEasel.tabs[1].savedURL = url
        let split = try #require(f.propose(f.request(pinnedEasel.tabs[1]), pinnedEasel))
        #expect(InterProfileMove.documents(moving: [f.pinned.id], after: split) == nil)
    }

    private func noteURL() -> URL { URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md") }

    @Test func aNoteFileBelongsToNoProfileSoNothingRelocates() throws {
        let f = Fixture()
        let note = f.setting(0, url: InternalPage.note(noteURL()).urlString)
        let moved = try #require(f.propose(f.request(note.tabs[0]), note))
        #expect(InterProfileMove.documents(moving: [f.today.id], after: moved) == [])
    }

    @Test func aNoteAliasLeftBehindNeverBlocksTheMove() throws {
        let f = Fixture()
        var pinnedNote = f.state
        let url = InternalPage.note(noteURL()).urlString
        pinnedNote.tabs[1].url = url
        pinnedNote.tabs[1].savedURL = url
        let noteSplit = try #require(f.propose(f.request(pinnedNote.tabs[1]), pinnedNote))
        #expect(InterProfileMove.documents(moving: [f.pinned.id], after: noteSplit) == [])
        #expect(InterProfileDocumentBlock(moving: [f.pinned.id], before: pinnedNote, after: noteSplit) == nil)
    }

    @Test func aProfileWideFavoriteRefuses() {
        let f = Fixture()
        var favorite = f.state
        favorite.tabs[0].kind = .favorite
        #expect(f.propose(f.request(favorite.tabs[0]), favorite) == nil)
    }

    @Test func theCurrentLiveAddressIsWhatTheDestinationReloads() throws {
        let f = Fixture()
        var navigated = f.state
        navigated.tabs[0].url = "https://live.invalid/next"
        navigated.tabs[0].title = "Next"
        navigated.tabs[0].savedURL = navigated.tabs[0].url
        navigated.tabs[0].savedTitle = navigated.tabs[0].title
        navigated.tabs[0].lastAccessed = Date()
        navigated.tabs[0].isUnread = true
        let reloaded = try #require(f.propose(f.request(f.today), navigated))
        #expect(reloaded.tabs.first { $0.id == f.today.id }?.url == "https://live.invalid/next")
    }

    @Test func changedSavedMetadataRefusesAStaleGesture() {
        let f = Fixture()
        var changed = f.state
        changed.tabs[0].customTitle = "Renamed"
        #expect(f.propose(f.request(f.today), changed) == nil)
    }

    @Test func aChangedParentRefusesAStaleGesture() {
        let f = Fixture()
        var changed = f.state
        changed.tabs[1].folderID = UUID()
        #expect(f.propose(f.request(f.pinned), changed) == nil)
    }

    @Test func aPendingProfileRemovalRefuses() {
        let f = Fixture()
        var removal = f.state
        removal.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: f.q.id, profileName: "Work")]
        #expect(f.propose(f.request(f.today), removal) == nil)
    }

    @Test func aSameSpaceSameProfileDropResolvesThroughTheOrdinaryDrop() {
        let f = Fixture()
        var sameProfile = f.state
        sameProfile.tabs[0].profileID = f.q.id
        sameProfile.tabs[0].spaceID = f.d.id
        #expect(f.propose(f.request(sameProfile.tabs[0]), sameProfile)?.tabs.first { $0.id == f.today.id }?.profileID == f.q.id)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    @Test func aCrossProfileDropStacksOntoAFlatSplit() throws {
        let f = Fixture()
        let (grouped, flat) = f.groupedDestination()
        let stacked = try #require(f.propose(f.request(f.today, target: .stack(0, after: true), selection: flat.tabIDs, layout: flat), grouped))
        let column = try #require(stacked.splitLayouts.first { $0.id == flat.id })
        #expect(column.tabIDs == [f.d1.id, f.today.id, f.d2.id])
        #expect(column.stacks?.slotSizes == [2, 1])
        #expect(column.orientation == .horizontal)
        #expect(stacked.tabs.first { $0.id == f.today.id }?.profileID == f.q.id)
    }

    private func stackedSplit(_ f: Fixture) throws -> (grouped: BrowserState, flat: BrowserSplitLayout, stacked: BrowserState, column: BrowserSplitLayout) {
        let (grouped, flat) = f.groupedDestination()
        let stacked = try #require(f.propose(f.request(f.today, target: .stack(0, after: true), selection: flat.tabIDs, layout: flat), grouped))
        return (grouped, flat, stacked, try #require(stacked.splitLayouts.first { $0.id == flat.id }))
    }

    @Test func aCrossProfileDropJoinsAnExistingStackBelowTheStackedPane() throws {
        let f = Fixture()
        let s = try stackedSplit(f)
        let joined = try #require(f.propose(f.request(f.g1, target: .stack(1, after: true), selection: s.column.tabIDs, layout: s.column), s.stacked))
        let full = try #require(joined.splitLayouts.first { $0.id == s.flat.id })
        #expect(full.tabIDs == [f.d1.id, f.today.id, f.g1.id, f.d2.id])
        #expect(full.stacks?.slotSizes == [3, 1])
    }

    @Test func aFullSplitRefusesAStackDropButStillTakesAReplacement() throws {
        let f = Fixture()
        let s = try stackedSplit(f)
        let joined = try #require(f.propose(f.request(f.g1, target: .stack(1, after: true), selection: s.column.tabIDs, layout: s.column), s.stacked))
        let full = try #require(joined.splitLayouts.first { $0.id == s.flat.id })
        #expect(f.propose(f.request(f.g2, target: .stack(3, after: false), selection: full.tabIDs, layout: full), joined) == nil)
        #expect(f.propose(f.request(f.g2, target: .replace(3), selection: full.tabIDs, layout: full), joined) != nil)
    }

    private struct Errands {
        let other: BrowserSpace
        let tabs: [BrowserTab]
        let pair: BrowserSplitLayout
        let state: BrowserState

        init(_ f: Fixture) {
            let other = BrowserSpace(id: UUID(), name: "Errands", symbol: "circle", color: "AABBCC", profileID: f.p.id)
            let tabs = ["e1", "e2"].map { name in
                BrowserTab(id: UUID(), spaceID: other.id, profileID: f.p.id, url: "https://live.invalid/" + name, title: name, kind: .today,
                           folderID: nil, createdAt: .distantPast, lastAccessed: .distantPast, savedURL: "https://live.invalid/" + name, savedTitle: name)
            }
            let pair = BrowserSplitLayout(spaceID: other.id, tabIDs: tabs.map(\.id), orientation: .vertical, widthFactors: [0.5, 0.5])
            var same = f.state
            same.spaces.append(other)
            same.tabs += tabs
            same.splitLayouts.append(pair)
            self.other = other; self.tabs = tabs; self.pair = pair; self.state = same
        }

        func local(_ f: Fixture, _ source: BrowserTab, _ target: SplitDropTarget, _ layout: BrowserSplitLayout) -> ForeignSplitDrop.Request {
            ForeignSplitDrop.Request(source: source, sourceHomeID: UUID(), spaceID: other.id, profileID: f.p.id,
                selection: layout.tabIDs, layout: layout, target: target, orientation: .vertical, destinationHomeIDs: [:])
        }
    }

    @Test func aSameProfileDropStacksOntoAFlatSplitKeepingItsProfile() throws {
        let f = Fixture()
        let e = Errands(f)
        let row = try #require(f.propose(e.local(f, f.today, .stack(1, after: false), e.pair), e.state))
        let layout = try #require(row.splitLayouts.first { $0.id == e.pair.id })
        #expect(layout.tabIDs == [e.tabs[0].id, f.today.id, e.tabs[1].id])
        #expect(layout.stacks?.slotSizes == [1, 2])
        #expect(layout.orientation == .vertical)
        #expect(row.tabs.first { $0.id == f.today.id }?.profileID == f.p.id)
    }

    @Test func aSameProfileDropJoinsAnExistingStack() throws {
        let f = Fixture()
        let e = Errands(f)
        let row = try #require(f.propose(e.local(f, f.today, .stack(1, after: false), e.pair), e.state))
        let rowLayout = try #require(row.splitLayouts.first { $0.id == e.pair.id })
        let grown = try #require(f.propose(e.local(f, f.g1, .stack(2, after: true), rowLayout), row))
        #expect(grown.splitLayouts.first { $0.id == e.pair.id }?.tabIDs == [e.tabs[0].id, f.today.id, e.tabs[1].id, f.g1.id])
        #expect(grown.splitLayouts.first { $0.id == e.pair.id }?.stacks?.slotSizes == [1, 3])
    }

    @MainActor private final class Store {
        let directory: URL
        let file: URL

        init(_ name: String) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-" + name + "-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            file = directory.appendingPathComponent("session.json")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func open(_ state: BrowserState) throws -> BrowserStore {
            try InterProfileMoveTests.encoder.encode(state).write(to: file)
            return try BrowserStore(directory: directory)
        }

        func breakWrites() throws {
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        }
    }

    @MainActor @Test func aCrossProfileStackDropCommitsThroughTheReloadTransaction() throws {
        let f = Fixture()
        let (grouped, flat) = f.groupedDestination()
        let s = try Store("foreign-stack")
        let store = try s.open(grouped)
        store.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        let r = f.request(f.today, target: .stack(0, after: true), selection: flat.tabIDs, layout: flat)
        var result: Result<Bool, Error>?
        store.moveAcrossProfiles([f.today.id], proposal: { f.propose(r, $0) }) { result = $0 }
        #expect((try? result?.get()) == true)
        let saved = try BrowserStore(directory: s.directory).state.splitLayouts.first { $0.id == flat.id }
        #expect(saved?.tabIDs == [f.d1.id, f.today.id, f.d2.id])
        #expect(saved?.stacks?.slotSizes == [2, 1])
    }

    @MainActor @Test func aSameProfileStackDropCommitsWithoutAReload() throws {
        let f = Fixture()
        let e = Errands(f)
        let s = try Store("same-stack")
        let store = try s.open(e.state)
        var retired = false
        store.requestPageRetirement = { _, _, completion in retired = true; completion(false) }
        #expect(try store.commitForeignSplitDrop([f.today.id]) { f.propose(e.local(f, f.today, .stack(1, after: false), e.pair), $0) })
        #expect(!retired)
        let saved = try BrowserStore(directory: s.directory).state.splitLayouts.first { $0.id == e.pair.id }
        #expect(saved?.tabIDs == [e.tabs[0].id, f.today.id, e.tabs[1].id])
        #expect(saved?.stacks?.slotSizes == [1, 2])
    }

    @Test func aWholeSplitMovesToAnotherProfileAsOneContainer() throws {
        let f = Fixture()
        let from = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.s.id, profileID: f.p.id))
        let to = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.d.id, profileID: f.q.id))
        let move = try #require(SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: to, state: f.state))
        #expect(move.crossesProfiles)
        #expect(move.tabIDs == f.group.tabIDs)
    }

    private func wholeMove(_ f: Fixture) throws -> (move: SidebarSpaceMove, applied: BrowserState, from: SidebarHierarchySnapshot, to: SidebarHierarchySnapshot) {
        let from = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.s.id, profileID: f.p.id))
        let to = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.d.id, profileID: f.q.id))
        let move = try #require(SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: to, state: f.state))
        return (move, try #require(move.applying(to: f.state)), from, to)
    }

    @Test func everyChildCarriesTheDestinationProfile() throws {
        let f = Fixture()
        let w = try wholeMove(f)
        #expect(w.applied.tabs.filter { f.group.tabIDs.contains($0.id) }.allSatisfy { $0.profileID == f.q.id && $0.spaceID == f.d.id })
    }

    @Test func theGroupIDAnchorAppearanceAndProportionsSurvive() throws {
        let f = Fixture()
        let w = try wholeMove(f)
        var expected = f.group
        expected.spaceID = f.d.id
        #expect(w.applied.splitLayouts == [expected])
    }

    @Test func theLiveAddressIsRetainedForTheDestinationReload() throws {
        let f = Fixture()
        let w = try wholeMove(f)
        #expect(w.applied.tabs.first { $0.id == f.g1.id }?.url == f.g1.url)
    }

    @Test func movingToTheSameSpaceRefuses() throws {
        let f = Fixture()
        let w = try wholeMove(f)
        #expect(SidebarSpaceMove(items: [.split(f.group.id)], from: w.from, to: w.from, state: f.state) == nil)
    }

    @Test func aGroupWithAnEaselMovesTheEaselDocumentWithIt() throws {
        let f = Fixture()
        let easelID = UUID()
        var note = f.state
        note.tabs[3].url = InternalPage.easel(easelID).urlString
        let from = try #require(SidebarHierarchySnapshot(state: note, spaceID: f.s.id, profileID: f.p.id))
        let to = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.d.id, profileID: f.q.id))
        let withEasel = try #require(SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: to, state: note)?.applying(to: note))
        #expect(InterProfileMove.documents(moving: Set(f.group.tabIDs), after: withEasel) == [.easel(easelID)])
    }

    @Test func aRemovedDestinationProfileHasNoSnapshot() {
        let f = Fixture()
        var removing = f.state
        removing.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: f.q.id, profileName: "Work")]
        #expect(SidebarHierarchySnapshot(state: removing, spaceID: f.d.id, profileID: f.q.id) == nil)
    }

    private func windowDrop(_ f: Fixture) throws -> (window: SidebarWindowMove, location: SidebarContainerLocation) {
        let location = SidebarContainerLocation(spaceID: f.d.id, folderID: nil, section: .today)
        return (try #require(SidebarWindowMove(items: [.split(f.group.id)], sourceSpaceID: f.s.id, profileID: f.p.id,
            destinationProfileID: f.q.id, to: location, before: .tab(f.d1.id), state: f.state)), location)
    }

    @Test func aWindowDropCrossesProfiles() throws {
        let f = Fixture()
        #expect(try windowDrop(f).window.crossesProfiles)
    }

    @Test func droppedChildrenTakeTheDestinationSectionAndProfile() throws {
        let f = Fixture()
        let dropped = try #require(try windowDrop(f).window.applying(to: f.state))
        #expect(dropped.tabs.filter { f.group.tabIDs.contains($0.id) }.allSatisfy { $0.profileID == f.q.id && $0.spaceID == f.d.id && $0.kind == .today })
    }

    @Test func theDropLandsBeforeTheRequestedDestinationItem() throws {
        let f = Fixture()
        let w = try windowDrop(f)
        let dropped = try #require(w.window.applying(to: f.state))
        #expect(SidebarHierarchy.children(in: w.location, state: dropped).first == .split(f.group.id))
    }

    private func trayDrop(_ f: Fixture) throws -> (BrowserState, SidebarContainerLocation) {
        let tray = SidebarContainerLocation(spaceID: f.d.id, folderID: nil, section: .favorite, profileID: f.q.id)
        let applied = try #require(SidebarWindowMove(items: [.split(f.group.id)], sourceSpaceID: f.s.id, profileID: f.p.id,
            destinationProfileID: f.q.id, to: tray, before: nil, state: f.state)?.applying(to: f.state))
        return (applied, tray)
    }

    @Test func aTrayDropMakesDestinationProfileFavorites() throws {
        let f = Fixture()
        let (toTray, _) = try trayDrop(f)
        #expect(toTray.tabs.filter { f.group.tabIDs.contains($0.id) }.allSatisfy { $0.kind == .favorite && $0.profileID == f.q.id && $0.folderID == nil })
    }

    @Test func theWholeGroupOccupiesOneTraySlot() throws {
        let f = Fixture()
        let (toTray, tray) = try trayDrop(f)
        #expect(SidebarHierarchy.children(in: tray, state: toTray) == [.split(f.group.id)])
    }

    private func favoriteLeaving(_ f: Fixture) throws -> (moved: BrowserState, favorite: BrowserTab, sourceTray: SidebarContainerLocation) {
        var source = f.state
        let favorite = BrowserTab(id: UUID(), spaceID: f.s.id, profileID: f.p.id, url: "https://live.invalid/fav", title: "Fav",
            kind: .favorite, folderID: nil, createdAt: .distantPast, lastAccessed: .distantPast, savedURL: "https://saved.invalid/fav", savedTitle: "Fav")
        let sourceTray = SidebarContainerLocation(spaceID: f.s.id, folderID: nil, section: .favorite, profileID: f.p.id)
        source.tabs.append(favorite)
        source.sidebarItemOrder[sourceTray.key] = [.tab(favorite.id)]
        let location = SidebarContainerLocation(spaceID: f.d.id, folderID: nil, section: .today)
        let moved = try #require(SidebarWindowMove(items: [.tab(favorite.id)], sourceSpaceID: f.s.id, profileID: f.p.id,
            destinationProfileID: f.q.id, to: location, before: nil, state: source)?.applying(to: source))
        return (moved, favorite, sourceTray)
    }

    @Test func aFavoriteBecomesADestinationTodayItem() throws {
        let f = Fixture()
        let r = try favoriteLeaving(f)
        let arrived = try #require(r.moved.tabs.first { $0.id == r.favorite.id })
        #expect(arrived.kind == .today)
        #expect(arrived.profileID == f.q.id)
        #expect(arrived.spaceID == f.d.id)
        #expect(arrived.savedURL == r.favorite.url)
    }

    @Test func theSourceTraySlotIsVacated() throws {
        let f = Fixture()
        let r = try favoriteLeaving(f)
        #expect(SidebarHierarchy.children(in: r.sourceTray, state: r.moved).isEmpty)
    }

    @Test func anImplicitSameProfileDropStillRefusesAnotherProfile() {
        let f = Fixture()
        let location = SidebarContainerLocation(spaceID: f.d.id, folderID: nil, section: .today)
        #expect(SidebarWindowMove(items: [.split(f.group.id)], sourceSpaceID: f.s.id, profileID: f.p.id, to: location, before: nil, state: f.state) == nil)
    }

    @MainActor private final class Transaction {
        let f = Fixture()
        let s: Store
        let store: BrowserStore
        let proposal: (BrowserState) -> BrowserState?
        var result: Result<Bool, Error>?
        var pending: (() -> Bool, (Bool) -> Void)?

        init() throws {
            let f = f
            s = try Store("inter-profile")
            store = try s.open(f.state)
            let r = f.request(f.today)
            proposal = { ForeignSplitDrop.proposal(r, state: $0, now: Date(), creation: nil) }
        }

        func move() { result = nil; store.moveAcrossProfiles([f.today.id], proposal: proposal) { [unowned self] in result = $0 } }
        var succeeded: Bool? { try? result?.get() }
    }

    @MainActor @Test func theDialogPreferenceDefaultsOff() throws {
        let t = try Transaction()
        #expect(!t.store.bypassesInterProfileMoveConfirmation)
    }

    @MainActor @Test func refusedPageConsentPublishesNothing() throws {
        let t = try Transaction()
        var asked: Set<UUID> = []
        t.store.requestPageRetirement = { ids, _, completion in asked = ids; completion(false) }
        t.move()
        #expect(asked == [t.f.today.id])
        #expect(t.succeeded == false)
        #expect(t.store.state == t.f.state)
    }

    @MainActor @Test func theMovedTabIsReservedWhilePagesRetire() throws {
        let t = try Transaction()
        t.store.requestPageRetirement = { _, shouldCommit, completion in t.pending = (shouldCommit, completion) }
        t.move()
        #expect(t.store.retiringTabIDs == [t.f.today.id])
        #expect(t.result == nil)
    }

    @MainActor @Test func approvalDoesNotPublishBeforeEveryPageCloses() throws {
        let t = try Transaction()
        t.store.requestPageRetirement = { _, shouldCommit, completion in t.pending = (shouldCommit, completion) }
        t.move()
        #expect(t.pending?.0() == true)
        #expect(t.store.state == t.f.state)
    }

    @MainActor @Test func theMoveCommitsAfterRetirement() throws {
        let t = try Transaction()
        t.store.requestPageRetirement = { _, shouldCommit, completion in t.pending = (shouldCommit, completion) }
        t.move()
        _ = t.pending?.0()
        t.pending?.1(true)
        #expect(t.succeeded == true)
        #expect(t.store.state.tabs.first { $0.id == t.f.today.id }?.profileID == t.f.q.id)
        #expect(t.store.retiringTabIDs.isEmpty)
    }

    @MainActor @Test func theMovePersistsAtomically() throws {
        let t = try Transaction()
        t.store.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        t.move()
        #expect(try BrowserStore(directory: t.s.directory).state.tabs.first { $0.id == t.f.today.id }?.profileID == t.f.q.id)
    }

    @MainActor @Test func aChangedOriginalAfterTheGestureRefuses() throws {
        let t = try Transaction()
        var edited = t.f.state
        edited.tabs[0].customTitle = "Renamed"
        let stale = try t.s.open(edited)
        stale.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        var result: Result<Bool, Error>?
        stale.moveAcrossProfiles([t.f.today.id], proposal: t.proposal) { result = $0 }
        #expect((try? result?.get()) == false)
        #expect(stale.state == edited)
    }

    @MainActor @Test func aFailedSavePublishesNothing() throws {
        let t = try Transaction()
        t.store.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        try t.s.breakWrites()
        t.move()
        var failed = false
        if case .failure? = t.result { failed = true }
        #expect(failed)
        #expect(t.store.state == t.f.state)
    }

    @MainActor private func emptyFolderMove(_ f: Fixture) -> (state: BrowserState, folder: BrowserFolder, move: SidebarSpaceMove) {
        var state = f.state
        let folder = BrowserFolder(id: UUID(), spaceID: f.s.id, name: "Empty")
        state.folders.append(folder)
        state.sidebarItemOrder[f.root.key]?.append(.folder(folder.id))
        let move = SidebarSpaceMove(items: [.folder(folder.id)],
            from: SidebarHierarchySnapshot(state: state, spaceID: f.s.id, profileID: f.p.id)!,
            to: SidebarHierarchySnapshot(state: state, spaceID: f.d.id, profileID: f.q.id)!, state: state)!
        return (state, folder, move)
    }

    @MainActor @Test func anEmptyFolderNeedsNoDecision() throws {
        let f = Fixture()
        let e = emptyFolderMove(f)
        #expect(e.move.tabIDs.isEmpty)
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [], destination: f.q.id, decision: nil, bypass: false) == .proceed(remembersChoice: false))
    }

    @MainActor @Test func anEmptyFolderMovesAtOnce() throws {
        let f = Fixture()
        let e = emptyFolderMove(f)
        let s = try Store("empty-folder")
        let store = try s.open(e.state)
        var retired = false
        store.requestPageRetirement = { _, _, completion in retired = true; completion(false) }
        var result: Result<Bool, Error>?
        store.moveAcrossProfiles([], proposal: { e.move.applying(to: $0) }) { result = $0 }
        #expect((try? result?.get()) == true)
        #expect(!retired)
        #expect(store.state.folders.first { $0.id == e.folder.id }?.spaceID == f.d.id)
    }

    @MainActor @Test func anOrdinaryRelocationCannotSkipThePageReload() throws {
        let f = Fixture()
        let s = try Store("plain")
        let plain = try s.open(f.state)
        let from = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.s.id, profileID: f.p.id))
        let to = try #require(SidebarHierarchySnapshot(state: f.state, spaceID: f.d.id, profileID: f.q.id))
        let move = try #require(SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: to, state: f.state))
        #expect(try plain.moveSidebarItemsAcrossSpaces(move) == false)
        #expect(plain.state == f.state)
    }

    @MainActor @Test func dontAskAgainStoresThePreference() throws {
        let f = Fixture()
        let s = try Store("remember")
        let plain = try s.open(f.state)
        plain.rememberInterProfileMoveChoice()
        #expect(plain.bypassesInterProfileMoveConfirmation)
    }

    @MainActor private final class Documents {
        let f = Fixture()
        let s: Store
        let noteID = UUID()
        let withNote: BrowserState
        let store: BrowserStore
        let proposal: (BrowserState) -> BrowserState?
        var result: Result<Bool, Error>?
        var relocated: [InternalPage] = []
        var fromProfile: UUID?, toProfile: UUID?
        var reversed = 0
        var retirementCalls = 0
        var editorValid = false
        var pending: (() -> Bool, (Bool) -> Void)?

        init() throws {
            let f = f
            s = try Store("documents")
            var withNote = f.state
            withNote.tabs[0].url = InternalPage.easel(noteID).urlString
            self.withNote = withNote
            store = try s.open(withNote)
            let r = f.request(f.today)
            proposal = { ForeignSplitDrop.proposal(r, state: $0, now: Date(), creation: nil) }
        }

        func installOwner() {
            store.relocateLocalDocuments = { [unowned self] _, pages, a, b in
                relocated = pages; fromProfile = a; toProfile = b
                return { [unowned self] in reversed += 1 }
            }
            store.prepareLocalDocumentRelocation = { [unowned self] ids in
                #expect(ids == [f.today.id])
                return { [unowned self] in editorValid }
            }
        }

        func holdRetirement() {
            store.requestPageRetirement = { [unowned self] _, shouldCommit, completion in retirementCalls += 1; pending = (shouldCommit, completion) }
        }

        func move() { result = nil; store.moveAcrossProfiles([f.today.id], proposal: proposal) { [unowned self] in result = $0 }; }
        var succeeded: Bool? { try? result?.get() }
    }

    @MainActor @Test func aDocumentMoveWithoutItsRelocationOwnerRefuses() throws {
        let d = try Documents()
        d.move()
        #expect(d.succeeded == false)
        #expect(d.store.state == d.withNote)
    }

    @MainActor @Test func anUnfinishedOriginalEditorRefusesBeforeNativePageRetirement() throws {
        let d = try Documents()
        d.installOwner()
        d.holdRetirement()
        d.move()
        #expect(d.succeeded == false)
        #expect(d.retirementCalls == 0)
        #expect(d.relocated.isEmpty)
    }

    @MainActor @Test func aChangedEditorDuringConsentRefusesBeforeUnload() throws {
        let d = try Documents()
        d.installOwner()
        d.holdRetirement()
        d.editorValid = true
        d.move()
        d.editorValid = false
        #expect(d.pending?.0() == false)
    }

    @MainActor @Test func anEditorRefusalLeavesTheOriginalDocumentAndProfileUntouched() throws {
        let d = try Documents()
        d.installOwner()
        d.holdRetirement()
        d.editorValid = true
        d.move()
        d.editorValid = false
        _ = d.pending?.0()
        d.pending?.1(false)
        #expect(d.succeeded == false)
        #expect(d.relocated.isEmpty)
        #expect(d.store.state == d.withNote)
    }

    @MainActor @Test func unchangedOriginalEditorsAdmitTheActualUnload() throws {
        let d = try Documents()
        d.installOwner()
        d.holdRetirement()
        d.editorValid = true
        d.move()
        #expect(d.pending?.0() == true)
    }

    @MainActor @Test func aLateEditorChangeAfterUnloadStillPreventsRelocation() throws {
        let d = try Documents()
        d.installOwner()
        d.holdRetirement()
        d.editorValid = true
        d.move()
        _ = d.pending?.0()
        d.editorValid = false
        d.pending?.1(true)
        #expect(d.succeeded == false)
        #expect(d.relocated.isEmpty)
        #expect(d.store.state == d.withNote)
    }

    @MainActor @Test func documentsRelocateSourceToDestinationBeforePublication() throws {
        let d = try Documents()
        d.installOwner()
        d.editorValid = true
        d.store.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        d.move()
        #expect(d.succeeded == true)
        #expect(d.relocated == [.easel(d.noteID)])
        #expect(d.fromProfile == d.f.p.id)
        #expect(d.toProfile == d.f.q.id)
        #expect(d.reversed == 0)
    }

    @MainActor @Test func aFailedSaveReversesTheDocumentMove() throws {
        let d = try Documents()
        d.installOwner()
        d.editorValid = true
        d.store.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        try d.s.breakWrites()
        d.move()
        #expect(d.reversed == 1)
        #expect(d.store.state == d.withNote)
    }

    @MainActor private final class Mixed {
        let f = Fixture()
        let root: URL
        let easels: EaselStore, targetEasels: EaselStore
        let easel: EaselSession
        let noteFile: URL
        let noteBytes = Data("Original note\n".utf8)
        let store: BrowserStore
        let move: SidebarSpaceMove
        var editorValid = true

        init() throws {
            let f = f
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-mixed-profile-" + UUID().uuidString)
            easels = try EaselStore(directory: root.appendingPathComponent("source/Easels"))
            targetEasels = try EaselStore(directory: root.appendingPathComponent("target/Easels"))
            easel = try easels.create()
            noteFile = root.appendingPathComponent("Parc Notes/Original Note.md")
            try FileManager.default.createDirectory(at: noteFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try noteBytes.write(to: noteFile)
            let browser = EaselItem(kind: .browser, frame: .init(x: 0, y: 0, width: 320, height: 200), url: "https://example.com/embedded")
            try easel.perform("Browser") { $0.items = [browser] }
            var initial = f.state
            for (tabID, page) in [(f.g1.id, InternalPage.note(noteFile)), (f.g2.id, InternalPage.easel(easel.document.id))] {
                let index = initial.tabs.firstIndex { $0.id == tabID }!
                initial.tabs[index].url = page.urlString
                initial.tabs[index].savedURL = page.urlString
            }
            try InterProfileMoveTests.encoder.encode(initial).write(to: root.appendingPathComponent("session.json"))
            store = try BrowserStore(directory: root)
            let from = SidebarHierarchySnapshot(state: initial, spaceID: f.s.id, profileID: f.p.id)!
            let to = SidebarHierarchySnapshot(state: initial, spaceID: f.d.id, profileID: f.q.id)!
            move = SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: to, state: initial)!
            let easelID = easel.document.id, easels = easels, targetEasels = targetEasels
            store.prepareLocalDocumentRelocation = { [unowned self] _ in { self.editorValid } }
            store.requestPageRetirement = { _, validate, complete in complete(validate()) }
            store.relocateLocalDocuments = { _, pages, source, destination in
                #expect(source == f.p.id && destination == f.q.id)
                #expect(pages == [.easel(easelID)])
                try easels.retireSessionForRelocation(easelID)
                let copied = try easels.relocate(easelID, to: targetEasels)
                return { _ = try? targetEasels.relocate(easelID, to: easels); targetEasels.removeAssets(copied) }
            }
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func run() -> Bool? {
            var result: Result<Bool, Error>?
            let move = move
            store.moveAcrossProfiles(Set(move.tabIDs), proposal: { move.applying(to: $0) }) { result = $0 }
            return try? result?.get()
        }
    }

    @MainActor @Test func aDraftRefusalPreservesTheOriginalEaselStoreAndNoteFile() throws {
        let m = try Mixed()
        m.editorValid = false
        #expect(m.run() == false)
        #expect(try m.easels.load(m.easel.document.id) === m.easel)
        #expect(try Data(contentsOf: m.noteFile) == m.noteBytes)
    }

    @MainActor @Test func aMixedNoteAndEaselSplitCommitsItsOriginalRecordsToTheDestinationProfile() throws {
        let m = try Mixed()
        #expect(m.run() == true)
        #expect(m.move.tabIDs.allSatisfy { id in m.store.state.tabs.first { $0.id == id }?.profileID == m.f.q.id })
    }

    @MainActor @Test func theEaselMovesToTheDestinationProfileWithItsSavedContents() throws {
        let m = try Mixed()
        _ = m.run()
        #expect((try? m.easels.load(m.easel.document.id)) == nil)
        #expect(try m.targetEasels.load(m.easel.document.id).document == m.easel.document)
    }

    @MainActor @Test func theNoteFileStaysPutAndTheMovedTabStillPointsAtIt() throws {
        let m = try Mixed()
        _ = m.run()
        #expect(try Data(contentsOf: m.noteFile) == m.noteBytes)
        #expect(m.store.state.tabs.first { $0.id == m.f.g1.id }?.url == InternalPage.note(m.noteFile).urlString)
    }

    @MainActor private final class Rollback {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-shared-rollback-" + UUID().uuidString)
        let source: EaselStore, destination: EaselStore
        let a: EaselSession, b: EaselSession
        let asset: String
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let rollback = LocalDocumentRelocationRollback()
        var attempted = 0

        init() throws {
            source = try EaselStore(directory: root.appendingPathComponent("source"))
            destination = try EaselStore(directory: root.appendingPathComponent("destination"))
            let a = try source.create(), b = try source.create()
            let asset = try a.importPNG(png)
            for session in [a, b] {
                try session.perform("Shared image") { $0.items = [EaselItem(kind: .image, frame: .init(x: 0, y: 0, width: 10, height: 10), assetID: asset)] }
                try source.retireSessionForRelocation(session.document.id)
            }
            self.a = a; self.b = b; self.asset = asset
            let source = source, destination = destination
            for session in [a, b] {
                let id = session.document.id, copied = try source.relocate(id, to: destination)
                rollback.append(reverse: { [unowned self] in
                    attempted += 1
                    do { _ = try destination.relocate(id, to: source); return true } catch { return false }
                }, cleanup: { destination.removeAssets(copied) })
            }
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func blockBsReversal() throws {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("source/documents/" + b.document.id.uuidString.lowercased() + ".json"),
                                                    withIntermediateDirectories: false)
        }
    }

    @MainActor @Test func collectionRollbackAttemptsEveryReversalAfterOneFails() throws {
        let r = try Rollback()
        try r.blockBsReversal()
        r.rollback.run()
        #expect(r.attempted == 2)
    }

    @MainActor @Test func partialRollbackKeepsRestoredAndStillDestinationDocumentsIntact() throws {
        let r = try Rollback()
        try r.blockBsReversal()
        r.rollback.run()
        #expect(try r.source.load(r.a.document.id).document == r.a.document)
        #expect(try r.destination.load(r.b.document.id).document == r.b.document)
    }

    @MainActor @Test func partialRollbackPreservesASharedAssetCopiedByTheReversedDocument() throws {
        let r = try Rollback()
        try r.blockBsReversal()
        r.rollback.run()
        #expect(try r.destination.load(r.b.document.id).assetData(r.asset) == r.png)
    }

    @MainActor @Test func theRollbackCapabilityIsConsumedOnce() throws {
        let r = try Rollback()
        try r.blockBsReversal()
        r.rollback.run()
        r.rollback.run()
        #expect(r.attempted == 2)
    }

    @MainActor @Test func aFullyReversedCollectionRemovesItsCopiedAssetsAfterRestoration() throws {
        let r = try Rollback()
        r.rollback.run()
        #expect(try r.source.load(r.a.document.id).document == r.a.document)
        #expect(!FileManager.default.fileExists(atPath: r.destination.directory.appendingPathComponent("assets/" + r.asset).path))
    }

    @MainActor private final class Relocation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-doc-relocate-" + UUID().uuidString)
        let ex: EaselStore, ey: EaselStore
        let easelID: UUID
        let asset: String
        let copied: [String]

        init() throws {
            ex = try EaselStore(directory: root.appendingPathComponent("X/Easels"))
            ey = try EaselStore(directory: root.appendingPathComponent("Y/Easels"))
            var easel: EaselSession? = try ex.create(title: "Board")
            easelID = easel!.document.id
            let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13] + Array("IHDR".utf8) + Array(repeating: 0, count: 13))
            let asset = try easel!.importPNG(png)
            try easel!.perform("Add image") { $0.items.append(EaselItem(kind: .image, frame: EaselRect(x: 0, y: 0, width: 10, height: 10), assetID: asset)) }
            easel = nil
            self.asset = asset
            copied = try ex.relocate(easelID, to: ey)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func assetExists(_ side: String) -> Bool {
            FileManager.default.fileExists(atPath: root.appendingPathComponent(side + "/Easels/assets/" + asset).path)
        }
    }

    @MainActor @Test func anEaselDocumentMovesWithItsCopiedAssets() throws {
        let r = try Relocation()
        #expect(r.copied == [r.asset])
        #expect((try? r.ex.load(r.easelID)) == nil)
    }

    @MainActor @Test func theDestinationResolvesTheAssetAndTheSourceAssetsStay() throws {
        let r = try Relocation()
        #expect(try r.ey.load(r.easelID).document.items.first?.assetID == r.asset)
        #expect(r.assetExists("X"))
        #expect(r.assetExists("Y"))
    }

    @MainActor @Test func rollbackRemovesOnlyCopiedAssets() throws {
        let r = try Relocation()
        _ = try r.ey.relocate(r.easelID, to: r.ex)
        r.ey.removeAssets(r.copied)
        #expect(!r.assetExists("Y"))
        #expect(r.assetExists("X"))
        #expect(try r.ex.load(r.easelID).document.title == "Board")
    }

    @Test func aSameProfileOtherWindowDropKeepsTheProfileAndJoinsTheOtherSpace() throws {
        let f = Fixture()
        let e = Errands(f)
        let r = ForeignSplitDrop.Request(source: f.today, sourceHomeID: UUID(), spaceID: e.other.id, profileID: f.p.id,
            selection: [e.tabs[0].id], layout: nil, target: .insert(1), orientation: .vertical, destinationHomeIDs: [:])
        var state = f.state
        state.spaces.append(e.other)
        state.tabs.append(e.tabs[0])
        let moved = try #require(f.propose(r, state))
        let live = try #require(moved.tabs.first { $0.id == f.today.id })
        #expect(live.profileID == f.p.id)
        #expect(live.spaceID == e.other.id)
        #expect(live.url == f.today.url)
        #expect(moved.splitLayouts.contains { $0.tabIDs == [e.tabs[0].id, f.today.id] && $0.orientation == .vertical })
    }

    @Test func aSameSpaceOtherWindowDropLeavesTheSourcesSavedHome() throws {
        let f = Fixture()
        var same = f.state
        let home = UUID()
        let r = ForeignSplitDrop.Request(source: f.pinned, sourceHomeID: home, spaceID: f.s.id, profileID: f.p.id,
            selection: [f.sibling.id], layout: nil, target: .insert(0), orientation: .horizontal, destinationHomeIDs: [f.sibling.id: UUID()])
        same.activeSpaceID = f.s.id
        let placed = try #require(f.propose(r, same))
        #expect(placed.tabs.contains { $0.id == home && $0.kind == .pinned && $0.url == f.pinned.savedURL })
        #expect(placed.selectedTabIDs == [f.pinned.id, f.sibling.id])
    }

    @MainActor @Test func aSameProfilePlacementCommitsWithoutAReloadAndPersists() throws {
        let f = Fixture()
        let e = Errands(f)
        let s = try Store("foreign-drop")
        let r = ForeignSplitDrop.Request(source: f.today, sourceHomeID: UUID(), spaceID: e.other.id, profileID: f.p.id,
            selection: [e.tabs[0].id], layout: nil, target: .insert(1), orientation: .vertical, destinationHomeIDs: [:])
        var withErrands = f.state
        withErrands.spaces.append(e.other)
        withErrands.tabs.append(e.tabs[0])
        let store2 = try s.open(withErrands)
        var retired = false
        store2.requestPageRetirement = { _, _, completion in retired = true; completion(false) }
        #expect(try store2.commitForeignSplitDrop([f.today.id]) { ForeignSplitDrop.proposal(r, state: $0, now: Date(), creation: nil) })
        #expect(!retired)
        #expect(try BrowserStore(directory: s.directory).state.tabs.first { $0.id == f.today.id }?.spaceID == e.other.id)
    }

    @MainActor @Test func aProfileChangeCannotSkipTheReloadTransaction() throws {
        let f = Fixture()
        let s = try Store("foreign-cross")
        let store = try s.open(f.state)
        let cross = ForeignSplitDrop.Request(source: f.g1, sourceHomeID: UUID(), spaceID: f.d.id, profileID: f.q.id,
            selection: [f.d1.id], layout: nil, target: .insert(1), orientation: .horizontal, destinationHomeIDs: [:])
        #expect(try store.commitForeignSplitDrop([f.g1.id]) { ForeignSplitDrop.proposal(cross, state: $0, now: Date(), creation: nil) } == false)
    }

    private struct Blocks {
        let f = Fixture()
        let note = InternalPage.easel(UUID()).urlString
        let easel = InternalPage.easel(UUID()).urlString
        let research: BrowserFolder

        init() { research = BrowserFolder(id: UUID(), spaceID: f.s.id, name: "Research") }

        func set(_ id: UUID, _ url: String, title: String? = nil, in state: inout BrowserState) {
            let index = state.tabs.firstIndex { $0.id == id }!
            state.tabs[index].url = url
            state.tabs[index].savedURL = url
            if let title { state.tabs[index].title = title; state.tabs[index].savedTitle = title }
        }

        func alias(_ url: String, _ space: BrowserSpace, _ kind: TabKind, folder: UUID? = nil, archived: Bool = false) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: url, title: "Alias", kind: kind,
                       folderID: folder, createdAt: Date(timeIntervalSince1970: 3), lastAccessed: Date(timeIntervalSince1970: 4),
                       archivedAt: archived ? Date(timeIntervalSince1970: 5) : nil, savedURL: url, savedTitle: "Alias")
        }

        func block(_ items: [SidebarItemReference], _ state: BrowserState) throws -> (InterProfileDocumentBlock?, Bool) {
            let source = try #require(SidebarHierarchySnapshot(state: state, spaceID: f.s.id, profileID: f.p.id))
            let target = try #require(SidebarHierarchySnapshot(state: state, spaceID: f.d.id, profileID: f.q.id))
            let move = try #require(SidebarSpaceMove(items: items, from: source, to: target, state: state))
            let after = move.applying(to: state)
            let refused = after.map { InterProfileMove.documents(moving: Set(move.tabIDs), after: $0) == nil } ?? false
            return (InterProfileDocumentBlock(moving: Set(move.tabIDs), before: state, after: after), refused)
        }

        var clean: BrowserState {
            var state = f.state
            set(f.today.id, note, in: &state)
            return state
        }

        var duplicated: BrowserState {
            var state = clean
            state.folders = [research]
            state.tabs.append(alias(note, f.s, .pinned, folder: research.id))
            return state
        }
    }

    @Test func aBlockedDocumentMoveExplainsInsteadOfAskingForTheDataWarning() {
        let f = Fixture()
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [f.p.id], destination: f.q.id, decision: nil, bypass: false, blocked: true) == .blocked)
    }

    @Test func dontAskAgainStillExplainsABlockedMove() {
        let f = Fixture()
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [f.p.id], destination: f.q.id, decision: nil, bypass: true, blocked: true) == .blocked)
    }

    @Test func aSameDataMoveIsNeverGatedByTheDocumentCheck() {
        let f = Fixture()
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [f.q.id], destination: f.q.id, decision: nil, bypass: false, blocked: true) == .proceed(remembersChoice: false))
    }

    @Test func anUnblockedMoveStillAsksFirst() {
        let f = Fixture()
        #expect(InterProfileMoveGate.resolve(sourceProfiles: [f.p.id], destination: f.q.id, decision: nil, bypass: false, blocked: false) == .confirm)
    }

    @Test func anEaselWithNoOtherEntriesHasNothingToExplainAndStillMoves() throws {
        let b = Blocks()
        let (none, refused) = try b.block([.tab(b.f.today.id)], b.clean)
        #expect(none == nil)
        #expect(!refused)
    }

    @Test func webPagesNeverProduceADocumentExplanation() throws {
        let b = Blocks()
        let (web, refused) = try b.block([.split(b.f.group.id)], b.f.state)
        #expect(web == nil)
        #expect(!refused)
    }

    @Test func aMoveThatNoLongerAppliesExplainsNothing() {
        let f = Fixture()
        #expect(InterProfileDocumentBlock(moving: [f.today.id], before: f.state, after: nil) == nil)
    }

    @Test func aDuplicateInAFolderBlocksTheMoveAndMatchesTheStoresRefusal() throws {
        let b = Blocks()
        let (copy, refused) = try b.block([.tab(b.f.today.id)], b.duplicated)
        #expect(copy != nil)
        #expect(refused)
    }

    @Test func theDuplicateIsPlacedInItsFolderWithTheDestinationNamedInTheTitle() throws {
        let b = Blocks()
        let folder = try #require(try b.block([.tab(b.f.today.id)], b.duplicated).0)
        #expect(folder.places == [.sidebar(.folder("Research"), split: false, otherSpace: nil)])
        #expect(folder.title == "Can’t move to Office")
        #expect(folder.message == "This Easel is still used elsewhere in Home: in the folder “Research”.")
    }

    private func archivedBlock(_ b: Blocks) throws -> (InterProfileDocumentBlock, Bool) {
        var archived = b.f.state
        b.set(b.f.today.id, b.easel, in: &archived)
        archived.tabs.append(b.alias(b.easel, b.f.s, .today, archived: true))
        let (old, refused) = try b.block([.tab(b.f.today.id)], archived)
        return (try #require(old), refused)
    }

    @Test func anArchivedEntryIsReportedAsTheArchive() throws {
        let (archive, refused) = try archivedBlock(Blocks())
        #expect(refused)
        #expect(archive.places == [.archive])
        #expect(archive.message == "This Easel is still used elsewhere in Home: in the Archive.")
    }

    private func joinedPinned(_ b: Blocks) -> BrowserState {
        var joined = b.f.state
        var pinnedNote = joined.tabs.first { $0.id == b.f.pinned.id }!
        pinnedNote.url = b.note
        pinnedNote.savedURL = b.note
        joined.tabs.append(SplitMembership.makeHome(of: pinnedNote, id: UUID(), now: Date(timeIntervalSince1970: 6), activeTabBeforeCreationID: nil))
        b.set(b.f.g1.id, b.note, title: "Plans", in: &joined)
        return joined
    }

    @Test func aPinnedTabShowingAWebPageNamesTheEaselSavedInIt() throws {
        let b = Blocks()
        var away = b.clean
        let index = away.tabs.firstIndex { $0.id == b.f.pinned.id }!
        away.tabs[index].savedURL = b.note
        away.tabs[index].savedTitle = "Plans"
        away.tabs[index].title = "Docs page"
        let (navigated, refused) = try b.block([.tab(b.f.pinned.id)], away)
        #expect(refused)
        #expect(navigated?.message == "The Easel “Plans” is still used elsewhere in Home: in Today.")
    }

    @Test func theSavedSpotAPinnedEasselLeftWhenJoiningASplitBlocksTheMove() throws {
        let b = Blocks()
        let (spot, refused) = try b.block([.split(b.f.group.id)], joinedPinned(b))
        let saved = try #require(spot)
        #expect(refused)
        #expect(saved.places == [.sidebar(.pinned, split: false, otherSpace: nil)])
        #expect(saved.message == "The Easel “Plans” is still used elsewhere in Home: in Pinned.")
    }

    @Test func aCopyInsideAPinnedSplitBlocksTheMove() throws {
        let b = Blocks()
        var pinnedSplit = b.clean
        for id in b.f.group.tabIDs { pinnedSplit.tabs[pinnedSplit.tabs.firstIndex { $0.id == id }!].kind = .pinned }
        b.set(b.f.g2.id, b.note, in: &pinnedSplit)
        let (split, refused) = try b.block([.tab(b.f.today.id)], pinnedSplit)
        let paired = try #require(split)
        #expect(refused)
        #expect(paired.places == [.sidebar(.pinned, split: true, otherSpace: nil)])
        #expect(paired.message == "This Easel is still used elsewhere in Home: in a pinned split.")
    }

    @Test func draggingAPinnedEaselIntoAnotherDatasSplitLeavesItsPinnedSpotBehind() throws {
        let b = Blocks()
        let f = b.f
        var dragged = f.state
        b.set(f.pinned.id, b.note, in: &dragged)
        let request = ForeignSplitDrop.Request(source: try #require(dragged.tab(f.pinned.id)), sourceHomeID: UUID(), spaceID: f.d.id, profileID: f.q.id,
            selection: [f.d1.id], layout: nil, target: .insert(1), orientation: .horizontal, destinationHomeIDs: [:])
        let dropped = ForeignSplitDrop.proposal(request, state: dragged, now: Date(timeIntervalSince1970: 7), creation: nil)
        let behind = try #require(InterProfileDocumentBlock(moving: [f.pinned.id], before: dragged, after: dropped))
        #expect(behind.places == [.leftBehind(.pinned, split: false)])
        #expect(behind.message == "This Easel is still used elsewhere in Home: in the pinned spot it leaves behind.")
    }

    private func spread(_ b: Blocks) -> BrowserState {
        let work = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "AABBCC", profileID: b.f.p.id)
        var shared = b.duplicated
        shared.spaces.append(work)
        shared.tabs.insert(contentsOf: [b.alias(b.note, work, .today), b.alias(b.note, b.f.s, .favorite)], at: shared.tabs.count - 1)
        return shared
    }

    @Test func everyDistinctPlaceIsKeptOnceInAStableOrder() throws {
        let b = Blocks()
        let (many, refused) = try b.block([.tab(b.f.today.id)], spread(b))
        let block = try #require(many)
        #expect(refused)
        #expect(block.places == [.sidebar(.today, split: false, otherSpace: "Work"), .sidebar(.favorites, split: false, otherSpace: nil),
                                 .sidebar(.folder("Research"), split: false, otherSpace: nil)])
    }

    @Test func entriesOutsideTheSourceSpaceNameTheirSpace() throws {
        let b = Blocks()
        let many = try #require(try b.block([.tab(b.f.today.id)], spread(b)).0)
        #expect(many.message == "This Easel is still used elsewhere: in Today in Work, in Favorites and in the folder “Research” in Home.")
    }

    @Test func aLongListStaysShort() throws {
        let b = Blocks()
        var shared = spread(b)
        shared.tabs.append(b.alias(b.note, b.f.s, .today, archived: true))
        #expect(try b.block([.tab(b.f.today.id)], shared).0?.message == "This Easel is still used elsewhere: in Today in Work, in Favorites and 2 more places.")
    }

    private func pairState(_ b: Blocks) -> BrowserState {
        var pair = b.duplicated
        b.set(b.f.g1.id, b.note, title: "Plans", in: &pair)
        b.set(b.f.g2.id, b.easel, title: "Board", in: &pair)
        pair.tabs.removeAll { $0.id == b.f.today.id }
        pair.tabs.append(b.alias(b.easel, b.f.s, .today, archived: true))
        return pair
    }

    @Test func aSplitWithTwoBlockedDocumentsExplainsTheFirstAndCountsTheOther() throws {
        let b = Blocks()
        let (both, refused) = try b.block([.split(b.f.group.id)], pairState(b))
        let first = try #require(both)
        #expect(refused)
        #expect(first.document == InternalPage(urlString: b.note))
        #expect(first.others == [InternalPage(urlString: b.easel)!])
        #expect(first.message == "The Easel “Plans” is still used elsewhere in Home: in the folder “Research”. 1 more Easel is too.")
    }

    @Test func aMultiItemMoveNamesTheOneItemThatBlocksIt() throws {
        let b = Blocks()
        var onlyEasel = pairState(b)
        onlyEasel.tabs.removeAll { $0.folderID == b.research.id }
        let (one, refused) = try b.block([.split(b.f.group.id)], onlyEasel)
        #expect(refused)
        #expect(one?.message == "The Easel “Board” is still used elsewhere in Home: in the Archive.")
    }

    @Test func aNewSpaceThatKeepsSeparateDataIsBlockedTheSameWay() throws {
        let b = Blocks()
        let duplicated = b.duplicated
        let snapshot = try #require(SidebarHierarchySnapshot(state: duplicated, spaceID: b.f.s.id, profileID: b.f.p.id))
        var draft = try #require(SidebarNewSpaceDraft(items: [.tab(b.f.today.id)], from: snapshot, state: duplicated))
        draft.name = "Fresh"
        draft.keepSeparate()
        let fresh = try #require(InterProfileDocumentBlock(moving: Set(draft.tabIDs), before: duplicated, after: draft.applying(to: duplicated)))
        #expect(fresh.message == "This Easel is still used elsewhere in Home: in the folder “Research”.")
    }

    @MainActor private final class DataChange {
        let f = Fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-data-change-block-" + UUID().uuidString)
        let note = InternalPage.easel(UUID()).urlString
        let easel = InternalPage.easel(UUID()).urlString
        let work: BrowserSpace
        let state: BrowserState

        init() throws {
            let f = f
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            work = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "AABBCC", profileID: f.p.id)
            var state = f.state
            state.spaces.append(work)
            let index = state.tabs.firstIndex { $0.id == f.today.id }!
            state.tabs[index].url = note
            state.tabs[index].savedURL = note
            state.tabs[index].title = "Plans"
            state.tabs[index].savedTitle = "Plans"
            self.state = state
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func alias(_ url: String, _ space: BrowserSpace, _ kind: TabKind, archived: Bool = false) -> BrowserTab {
            BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: url, title: "Alias", kind: kind,
                       createdAt: Date(timeIntervalSince1970: 3), lastAccessed: Date(timeIntervalSince1970: 4),
                       archivedAt: archived ? Date(timeIntervalSince1970: 5) : nil, savedURL: url, savedTitle: "Alias")
        }

        func stored(_ state: BrowserState) throws -> BrowserStore {
            try InterProfileMoveTests.encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
            return try BrowserStore(directory: directory)
        }

        func refused(_ store: BrowserStore) -> Bool {
            guard let assignment = store.profileAssignment(f.q.id, toSpace: f.s.id), let after = assignment.proposal(store.state) else { return false }
            return InterProfileMove.documents(moving: assignment.tabIDs, after: after) == nil
        }

        var spread: BrowserState {
            var spread = state
            spread.tabs.append(alias(note, work, .today))
            return spread
        }

        var kept: BrowserState {
            var kept = state
            kept.tabs += [alias(note, f.s, .favorite), alias(note, f.s, .today, archived: true)]
            return kept
        }
    }

    @MainActor @Test func anEaselUsedOnlyInTheChangingSpaceHasNothingToExplain() throws {
        let c = try DataChange()
        let quiet = try c.stored(c.state)
        #expect(quiet.sharingDocumentBlock(forSpace: c.f.s.id, to: .separate) == nil)
        #expect(quiet.sharingDocumentBlock(forSpace: c.f.s.id, to: .share(withSpace: c.f.d.id)) == nil)
        #expect(!c.refused(quiet))
    }

    @MainActor @Test func anEaselOpenInAnotherSpaceOnTheOldDataBlocksKeepSeparate() throws {
        let c = try DataChange()
        let separate = try #require(try c.stored(c.spread).sharingDocumentBlock(forSpace: c.f.s.id, to: .separate))
        #expect(separate.change == .keepSeparate)
        #expect(separate.title == "Can’t keep Home separate")
    }

    @MainActor @Test func anEntryInASpaceSharingTheOldDataIsNamedWithItsSpace() throws {
        let c = try DataChange()
        let separate = try #require(try c.stored(c.spread).sharingDocumentBlock(forSpace: c.f.s.id, to: .separate))
        #expect(separate.message == "The Easel “Plans” is still used elsewhere on Home’s current data: in Today in Work.")
    }

    @MainActor @Test func aFavoriteAndAnArchivedEntryBlockSharingOtherData() throws {
        let c = try DataChange()
        let store = try c.stored(c.kept)
        #expect(store.sharingDocumentBlock(forSpace: c.f.s.id, to: .share(withSpace: c.f.d.id)) != nil)
        #expect(c.refused(store))
    }

    @MainActor @Test func sharingNamesBothSpacesAndKeepsFavoritesAndTheArchiveWithTheOldData() throws {
        let c = try DataChange()
        let share = try #require(try c.stored(c.kept).sharingDocumentBlock(forSpace: c.f.s.id, to: .share(withSpace: c.f.d.id)))
        #expect(share.change == .share(target: "Office"))
        #expect(share.title == "Can’t share Office’s data with Home")
        #expect(share.message == "The Easel “Plans” is still used elsewhere on Home’s current data: in Favorites and in the Archive.")
    }

    @MainActor @Test func aDataChangeExplainsTheFirstDocumentAndCountsTheRest() throws {
        let c = try DataChange()
        var pair = c.spread
        let index = pair.tabs.firstIndex { $0.id == c.f.g1.id }!
        pair.tabs[index].url = c.easel
        pair.tabs[index].savedURL = c.easel
        pair.tabs[index].title = "Board"
        pair.tabs[index].savedTitle = "Board"
        pair.tabs.append(c.alias(c.easel, c.f.s, .today, archived: true))
        #expect(try c.stored(pair).sharingDocumentBlock(forSpace: c.f.s.id, to: .separate)?.message
                == "The Easel “Plans” is still used elsewhere on Home’s current data: in Today in Work. 1 more Easel is too.")
    }

    @MainActor private func loneEasel(_ c: DataChange) -> (kept: BrowserState, after: BrowserState) {
        let kept = c.kept
        var after = kept
        after.tabs[after.tabs.firstIndex { $0.id == c.f.today.id }!].profileID = UUID()
        return (kept, after)
    }

    @MainActor @Test func aLoneEaselStillBlocksADataChangeAndIsNamed() throws {
        let c = try DataChange()
        let (kept, after) = loneEasel(c)
        let lone = try #require(InterProfileDocumentBlock(moving: [c.f.today.id], before: kept, after: after, sharing: .separate))
        #expect(lone.subject == "The Easel “Plans”")
    }

    @MainActor @Test func moveWordingIsUnchangedWhenNoDataChangeIsGiven() throws {
        let c = try DataChange()
        let (kept, after) = loneEasel(c)
        let moved = try #require(InterProfileDocumentBlock(moving: [c.f.today.id], before: kept, after: after))
        #expect(moved.change == .move)
        #expect(moved.subject == "This Easel")
        #expect(moved.title == "Can’t move to Home")
        #expect(moved.message == "This Easel is still used elsewhere in Home: in Favorites and in the Archive.")
    }
}
