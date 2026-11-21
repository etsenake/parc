import Foundation
import Testing
@testable import ParcCore

struct FavoriteActionTests {
    typealias Action = CommandBarFavoriteAction

    struct Fixture {
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let foreign = BrowserProfile(id: UUID(), name: "Other")
        let space: BrowserSpace
        let other: BrowserSpace
        let folder: BrowserFolder
        let first: BrowserTab
        let second: BrowserTab
        let existing: BrowserTab
        let last: BrowserTab
        let state: BrowserState

        init() {
            space = BrowserSpace(id: UUID(), name: "Origin", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            other = BrowserSpace(id: UUID(), name: "Other Space", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            folder = BrowserFolder(id: UUID(), spaceID: space.id, name: "Folder", isExpanded: false)
            func tab(_ kind: TabKind, _ title: String) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: space.id, profileID: profile.id,
                    url: "https://example.test/" + title, title: title, kind: kind,
                    folderID: kind == .pinned ? folder.id : nil,
                    createdAt: Date(timeIntervalSince1970: 100), lastAccessed: Date(timeIntervalSince1970: 100),
                    savedURL: "https://home.test/" + title, savedTitle: "Home " + title)
            }
            first = tab(.today, "First")
            second = tab(.pinned, "Second")
            existing = tab(.favorite, "Existing")
            last = tab(.today, "Last")
            var state = BrowserState(profiles: [profile, foreign], spaces: [space, other], activeSpaceID: space.id)
            state.tabs = [first, existing, second, last]
            state.folders = [folder]
            state.selectedTabIDs = [first.id]
            state.selectionBySpace = [space.id.uuidString: [first.id], other.id.uuidString: [existing.id]]
            self.state = state
        }

        func action(_ ids: [UUID], _ state: BrowserState? = nil) -> Action? {
            Action(items: ids.map(SidebarItemReference.tab), spaceID: space.id, profileID: profile.id, state: state ?? self.state)
        }

        func addAction() -> Action { action([first.id, second.id])! }

        func promoted() -> BrowserState { addAction().applying(to: state)! }

        func removeAction() -> Action {
            Action(items: [.tab(first.id), .tab(second.id)], spaceID: other.id, profileID: profile.id, state: promoted())!
        }
    }

    struct Change: Sendable, CustomTestStringConvertible {
        let name: String
        let apply: @Sendable (inout BrowserState, Fixture) -> Void
        var testDescription: String { name }
    }

    static let expiringChanges: [Change] = [
        Change(name: "an original is replaced by a new incarnation") { state, _ in state.tabs[0].createdAt.addTimeInterval(1) },
        Change(name: "an original moves to another space") { state, fixture in state.tabs[0].spaceID = fixture.other.id },
        Change(name: "an original is reparented") { state, _ in state.tabs[2].folderID = nil },
        Change(name: "an original changes profile") { state, fixture in state.tabs[0].profileID = fixture.foreign.id },
        Change(name: "an original is archived") { state, _ in state.tabs[0].archivedAt = Date() },
        Change(name: "the source is missing") { state, _ in state.tabs.removeFirst() },
        Change(name: "the profile is retired") { state, fixture in state.profiles.removeAll { $0.id == fixture.profile.id } },
        Change(name: "the destination is missing") { state, fixture in state.spaces.removeAll { $0.id == fixture.space.id } },
    ]

    @Test func promotionKeepsTheRecoveredTitleAndOperation() {
        let add = Fixture().addAction()
        #expect(add.title == "Favorite Tab")
        #expect(add.operation == .favorite)
    }

    @Test func theOriginalCollectionOrderIsRetained() {
        let fixture = Fixture()
        #expect(fixture.addAction().tabIDs == [fixture.first.id, fixture.second.id])
    }

    @Test(arguments: ["favorite", "TAB FAVOR"])
    func wordsMatchWithinBounds(query: String) {
        #expect(Fixture().addAction().matches(query: query))
    }

    @Test(arguments: ["", "> favorite", "unfavorite"])
    func noTriggerOrInverseIsInvented(query: String) {
        #expect(!Fixture().addAction().matches(query: query))
    }

    @Test func anEmptyCollectionIsRefused() {
        #expect(Fixture().action([]) == nil)
    }

    @Test func aDuplicateCollectionIsRefused() {
        let fixture = Fixture()
        #expect(fixture.action([fixture.first.id, fixture.first.id]) == nil)
    }

    @Test func mixedMembershipOffersNeitherAction() {
        let fixture = Fixture()
        #expect(fixture.action([fixture.first.id, fixture.existing.id]) == nil)
    }

    @Test func aContainerDoesNotFlattenIntoPageActions() {
        let fixture = Fixture()
        #expect(Action(items: [.folder(fixture.folder.id)], spaceID: fixture.space.id, profileID: fixture.profile.id, state: fixture.state) == nil)
    }

    @Test func promotionAppendsAfterTheExistingFavorites() {
        let fixture = Fixture()
        #expect(fixture.promoted().tabs.filter { $0.kind == .favorite }.map(\.id) == [fixture.existing.id, fixture.first.id, fixture.second.id])
    }

    @Test func aTodayItemSnapshotsItsActualCurrentHome() {
        let fixture = Fixture()
        #expect(fixture.promoted().tabs.first { $0.id == fixture.first.id }?.savedURL == fixture.first.url)
    }

    @Test func anExistingPinHomeSurvivesPromotion() {
        let fixture = Fixture()
        #expect(fixture.promoted().tabs.first { $0.id == fixture.second.id }?.savedURL == fixture.second.savedURL)
    }

    @Test func promotionClearsFolderMembership() {
        let fixture = Fixture()
        let ids = fixture.addAction().tabIDs
        #expect(fixture.promoted().tabs.filter { ids.contains($0.id) }.allSatisfy { $0.folderID == nil })
    }

    @Test func promotionRewritesNeitherSelectionNorReturnMap() {
        let fixture = Fixture()
        let promoted = fixture.promoted()
        #expect(promoted.selectedTabIDs == fixture.state.selectedTabIDs)
        #expect(promoted.selectionBySpace == fixture.state.selectionBySpace)
    }

    @Test func promotionTouchesNeitherFoldersNorHistory() {
        let fixture = Fixture()
        let promoted = fixture.promoted()
        #expect(promoted.folders == fixture.state.folders)
        #expect(promoted.history == fixture.state.history)
    }

    @Test func anAcceptedPayloadCannotRepeatAgainstChangedMembership() {
        let fixture = Fixture()
        let add = fixture.addAction()
        let promoted = fixture.promoted()
        #expect(!add.isCurrent(in: promoted))
        #expect(add.applying(to: promoted) == nil)
    }

    @Test func demotionIsNamedAsTheInverse() {
        let remove = Fixture().removeAction()
        #expect(remove.title == "Unfavorite Tab")
        #expect(remove.operation == .unfavorite)
    }

    @Test func demotionPrependsTheExactOriginalCollection() {
        let fixture = Fixture()
        let demoted = fixture.removeAction().applying(to: fixture.promoted())!
        #expect(demoted.tabs.prefix(2).map(\.id) == [fixture.first.id, fixture.second.id])
    }

    @Test func demotionUsesTheCapturedSpaceAndAnUnpinnedDestination() {
        let fixture = Fixture()
        let demoted = fixture.removeAction().applying(to: fixture.promoted())!
        #expect(demoted.tabs.prefix(2).allSatisfy { $0.kind == .today && $0.spaceID == fixture.other.id && $0.folderID == nil })
    }

    @Test func demotionKeepsTheEstablishedTodaySavedBoundary() {
        let fixture = Fixture()
        let demoted = fixture.removeAction().applying(to: fixture.promoted())!
        #expect(demoted.tabs.first { $0.id == fixture.second.id }?.savedURL == fixture.second.url)
    }

    @Test func demotionLeavesUnrelatedRecordsEqual() {
        let fixture = Fixture()
        let demoted = fixture.removeAction().applying(to: fixture.promoted())!
        #expect(demoted.tabs.first { $0.id == fixture.existing.id } == fixture.existing)
        #expect(demoted.tabs.first { $0.id == fixture.last.id } == fixture.last)
    }

    @Test func demotionNeverNavigatesOrCloses() {
        let fixture = Fixture()
        let demoted = fixture.removeAction().applying(to: fixture.promoted())!
        #expect(demoted.selectedTabIDs == fixture.state.selectedTabIDs)
    }

    @Test func liveOriginalMetadataDoesNotReplaceMembershipIdentity() {
        let fixture = Fixture()
        var changed = fixture.state
        changed.tabs[0].title = "Live title"
        changed.tabs[0].url = "https://redirect.test/"
        #expect(fixture.addAction().isCurrent(in: changed))
    }

    @Test func realCurrentMetadataRemainsAuthoritative() {
        let fixture = Fixture()
        var changed = fixture.state
        changed.tabs[0].url = "https://redirect.test/"
        #expect(fixture.addAction().applying(to: changed)?.tabs.first { $0.id == fixture.first.id }?.savedURL == "https://redirect.test/")
    }

    @Test(arguments: expiringChanges)
    func theActionExpiresWhen(change: Change) {
        let fixture = Fixture()
        var changed = fixture.state
        change.apply(&changed, fixture)
        #expect(!fixture.addAction().isCurrent(in: changed))
    }

    @Test func aSplitPaneCannotBeSilentlyExtracted() {
        let fixture = Fixture()
        var changed = fixture.state
        changed.splitLayouts = [BrowserSplitLayout(spaceID: fixture.space.id, tabIDs: [fixture.first.id, fixture.last.id],
                                                   orientation: .horizontal, widthFactors: [0.5, 0.5])]
        #expect(fixture.action([fixture.first.id], changed) == nil)
    }

    @Test func aWholeSplitKeepsItsSeparateMembershipOwner() {
        let fixture = Fixture()
        var changed = fixture.state
        let layout = BrowserSplitLayout(spaceID: fixture.space.id, tabIDs: [fixture.first.id, fixture.last.id],
                                        orientation: .horizontal, widthFactors: [0.5, 0.5])
        changed.splitLayouts = [layout]
        #expect(Action(items: [.split(layout.id)], spaceID: fixture.space.id, profileID: fixture.profile.id, state: changed) == nil)
    }
}
