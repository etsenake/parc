import Foundation
import Testing
@testable import ParcCore

struct ExternalSplitDropWebLinksTests {
    private typealias Fixture = ExternalSplitDropTestsSupport.Fixture

    @MainActor @Test func replacingAPanePutsTheNewTabInThatPane() throws {
        let f = try Fixture()
        let id = UUID()
        #expect(try f.commit(f.store, id: id, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal))
        #expect(f.store.state.selectedTabIDs == [f.a, id])
    }

    @MainActor @Test func replacingAPaneLeavesTheDisplacedPageUntouched() throws {
        let f = try Fixture()
        #expect(try f.commit(f.store, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal))
        #expect(f.store.state.tabs.first { $0.id == f.b } == f.original.tabs.first { $0.id == f.b })
    }

    @MainActor @Test func theDroppedLinkBecomesANewTodayTabWithTheLiteralAddress() throws {
        let f = try Fixture()
        let id = UUID()
        #expect(try f.commit(f.store, id: id, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal))
        let new = try #require(f.store.state.tabs.first { $0.id == id })
        #expect(new.url == f.destination.absoluteString)
        #expect(new.savedURL == new.url)
        #expect(new.kind == .today)
    }

    @MainActor @Test func theDroppedLinkRemembersWhichTabWasActive() throws {
        let f = try Fixture()
        let id = UUID()
        #expect(try f.commit(f.store, id: id, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal))
        let new = try #require(f.store.state.tabs.first { $0.id == id })
        #expect(new.referrerID == nil)
        #expect(new.activeTabBeforeCreationID == f.a)
        #expect(new.profileID == f.profile)
    }

    @MainActor @Test func replacingAPaneKeepsTheGroupIdentityAndWidths() throws {
        let f = try Fixture()
        #expect(try f.commit(f.store, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal))
        #expect(f.store.activeSplitLayout?.id == f.group.id)
        #expect(f.store.activeSplitLayout?.widthFactors == f.group.widthFactors)
    }

    @MainActor @Test func theNewTabAndItsPaneSurviveAReload() throws {
        let f = try Fixture()
        let id = UUID()
        #expect(try f.commit(f.store, id: id, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal))
        let reopened = try BrowserStore(directory: f.root)
        #expect(reopened.state.tabs.contains { $0.id == id })
        #expect(reopened.activeSplitLayout?.tabIDs == [f.a, id])
    }

    @MainActor private func staleFixture() throws -> Fixture {
        let f = try Fixture()
        _ = try f.commit(f.store, selection: [f.a, f.b], layout: f.group, target: .replace(1), orientation: .horizontal)
        return f
    }

    @MainActor @Test func aStaleSelectionRefusesTheDrop() throws {
        let f = try staleFixture()
        #expect(try !f.commit(f.store, selection: [f.a, f.b], layout: f.group, target: .insert(1), orientation: .horizontal))
    }

    @MainActor @Test func aRefusedDropPublishesNothing() throws {
        let f = try staleFixture()
        let before = f.store.state
        _ = try f.commit(f.store, selection: [f.a, f.b], layout: f.group, target: .insert(1), orientation: .horizontal)
        #expect(f.store.state == before)
    }

    @Test(arguments: ["javascript:alert(1)", "parc://note/one", "file:///tmp/example", "data:text/plain,hello", "relative",
                      "https://user:secret@example.invalid", " https://example.invalid", "https://example.invalid\n"])
    func unownedSchemesAndCredentialsAreNotLinks(_ payload: String) {
        #expect(ExternalSplitDrop.url(payload) == nil)
    }

    @Test func aLiteralWebAddressIsAccepted() {
        let url = URL(string: "https://external.invalid/path?original=a+b#section")!
        #expect(ExternalSplitDrop.url(url.absoluteString) == url)
    }

    @MainActor @Test func insertingKeepsTheOriginalPairAroundTheNewPane() throws {
        let f = try Fixture()
        let inserted = try #require(f.proposal(f.original, .insert(1), [f.a, f.b], f.group))
        #expect(inserted.selectedTabIDs.count == 3)
        #expect(inserted.selectedTabIDs.first == f.a)
        #expect(inserted.selectedTabIDs.last == f.b)
    }

    @MainActor @Test func insertingUsesTheRequestedOrientation() throws {
        let f = try Fixture()
        let inserted = try #require(f.proposal(f.original, .insert(1), [f.a, f.b], f.group))
        #expect(inserted.splitLayouts.first?.orientation == .vertical)
    }

    @MainActor @Test func aLinkOnTheBottomBandOfASideBySidePaneStacksBelowIt() throws {
        let f = try Fixture()
        let stacked = try #require(f.proposal(f.original, .stack(0, after: true), [f.a, f.b], f.group, .horizontal))
        #expect(stacked.selectedTabIDs.count == 3)
        #expect(stacked.selectedTabIDs.first == f.a)
        #expect(stacked.selectedTabIDs.last == f.b)
        #expect(stacked.splitLayouts.first?.id == f.group.id)
        #expect(stacked.splitLayouts.first?.orientation == .horizontal)
        #expect(stacked.splitLayouts.first?.stacks?.slotSizes == [2, 1])
    }

    @MainActor @Test func insertingIntoAFullSplitIsRefused() throws {
        let f = try Fixture()
        let (four, fourGroup) = f.fourPanes()
        #expect(f.proposal(four, .insert(1), four.selectedTabIDs, fourGroup) == nil)
    }

    @MainActor @Test func replacingAtCapacityIsStillAvailable() throws {
        let f = try Fixture()
        let (four, fourGroup) = f.fourPanes()
        #expect(f.proposal(four, .replace(2), four.selectedTabIDs, fourGroup)?.selectedTabIDs.count == 4)
    }

    @MainActor @Test func stackingAtFourPanesIsRefused() throws {
        let f = try Fixture()
        let (four, fourGroup) = f.fourPanes()
        #expect(f.proposal(four, .stack(2, after: true), four.selectedTabIDs, fourGroup, .horizontal) == nil)
    }
}
