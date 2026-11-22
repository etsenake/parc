import Foundation
import Testing
@testable import ParcCore

@MainActor
struct TabCreationProvenanceSourceReceiptsTests {
    private typealias Fixture = TabCreationProvenanceTestsSupport.Fixture

    private struct Routed {
        var f = Fixture()
        let space: BrowserSpace
        var state: BrowserState
        var sourceWindow: WindowPresentation
        var destinationWindow: WindowPresentation
        let linkReceipt: TabCreationProvenance
        let createdReceipt: TabCreationProvenance

        init() {
            space = BrowserSpace(id: UUID(), name: "Routed", symbol: "circle", color: "123456", profileID: f.profile)
            state = f.state
            state.spaces.append(space)
            sourceWindow = WindowPresentation(state: state, ready: true)
            destinationWindow = WindowPresentation(state: state, ready: true)
            linkReceipt = TabCreationProvenance(routedFrom: f.parent.id, openedLink: true, profileID: f.profile, state: state)
            createdReceipt = TabCreationProvenance(routedFrom: f.parent.id, openedLink: false, profileID: f.profile, state: state)
        }
    }

    @Test func anExplicitOriginalReferrerWinsOverTheActiveBefore() {
        let f = Fixture()
        let receipt = TabCreationProvenance(referrerID: f.parent.id, activeTabID: f.previous.id, profileID: f.profile, state: f.state)
        #expect(receipt.referrerID == f.parent.id && receipt.activeTabBeforeCreationID == f.parent.id)
    }

    @Test func ordinaryCreationCapturesTheActualPreviousActiveID() {
        let f = Fixture()
        let ordinary = TabCreationProvenance(referrerID: nil, activeTabID: f.previous.id, profileID: f.profile, state: f.state)
        #expect(ordinary.referrerID == nil && ordinary.activeTabBeforeCreationID == f.previous.id)
    }

    @Test func aTargetProfileCannotAcceptAnotherProfilesReceipt() {
        let f = Fixture()
        let receipt = TabCreationProvenance(referrerID: f.parent.id, activeTabID: f.previous.id, profileID: f.profile, state: f.state)
        #expect(receipt.validated(profileID: UUID(), state: f.state).activeTabBeforeCreationID == nil)
    }

    @Test func aRemovedSourceIsNotResurrectedAtInsertion() {
        let f = Fixture()
        let receipt = TabCreationProvenance(referrerID: f.parent.id, activeTabID: f.previous.id, profileID: f.profile, state: f.state)
        var gone = f.state
        gone.tabs.removeAll { $0.id == f.parent.id }
        #expect(receipt.validated(profileID: f.profile, state: gone).referrerID == nil)
    }

    @Test func aMatchedLinkRecordsItsSourceOnlyAsTheCreatingWindowsActiveItem() {
        let r = Routed()
        #expect(r.linkReceipt.referrerID == nil && r.linkReceipt.activeTabBeforeCreationID == r.f.parent.id)
    }

    @Test func routedCreatedContentsKeepTheirSourceAsReferrer() {
        let r = Routed()
        #expect(r.createdReceipt.referrerID == r.f.parent.id && r.createdReceipt.activeTabBeforeCreationID == r.f.parent.id)
    }

    @Test func routedCreationReplacesTheDestinationPoolWithTheSourceAndChild() {
        var r = Routed()
        var routed = r.f.tab(referrer: r.linkReceipt.referrerID, previous: r.linkReceipt.activeTabBeforeCreationID)
        routed.spaceID = r.space.id
        r.state.tabs.append(routed)
        r.destinationWindow.recordCreation(routed.id, state: r.state)
        #expect(r.destinationWindow.referrerPool == [r.f.parent.id, routed.id])
    }

    @Test func routedCreationLeavesTheSourceWindowsPoolAndSelectionAlone() {
        var r = Routed()
        var routed = r.f.tab(referrer: r.linkReceipt.referrerID, previous: r.linkReceipt.activeTabBeforeCreationID)
        routed.spaceID = r.space.id
        r.state.tabs.append(routed)
        r.destinationWindow.recordCreation(routed.id, state: r.state)
        #expect(r.sourceWindow.referrerPool.isEmpty)
        #expect(r.sourceWindow.selectedTabIDs == [r.f.current.id])
    }

    @Test func sourceSelectionChangesDoNotOverwriteTheDestinationsAcceptedReceipt() {
        var r = Routed()
        var routed = r.f.tab(referrer: r.linkReceipt.referrerID, previous: r.linkReceipt.activeTabBeforeCreationID)
        routed.spaceID = r.space.id
        r.state.tabs.append(routed)
        r.destinationWindow.recordCreation(routed.id, state: r.state)
        r.sourceWindow.recordSelectionForReturn(r.f.previous.id, state: r.state)
        #expect(r.destinationWindow.referrerPool == [r.f.parent.id, routed.id])
    }

    @Test func crossProfileAdoptionNeverImportsEitherSourceIdentity() {
        let r = Routed()
        let foreign = r.createdReceipt.validated(profileID: UUID(), state: r.state)
        #expect(foreign.referrerID == nil && foreign.activeTabBeforeCreationID == nil)
    }

    @Test func aSourceRetiredBeforeAdoptionCannotProduceANewRelationship() {
        var r = Routed()
        r.state.tabs[r.f.index(r.f.parent.id, in: r.state)].archivedAt = Date()
        #expect(r.linkReceipt.validated(profileID: r.f.profile, state: r.state).activeTabBeforeCreationID == nil)
    }

    @Test func aSourceProfileChangeInvalidatesBothStoredIdentities() {
        var r = Routed()
        r.state.tabs[r.f.index(r.f.parent.id, in: r.state)].profileID = UUID()
        #expect(r.createdReceipt.validated(profileID: r.f.profile, state: r.state).activeTabBeforeCreationID == nil)
    }

    @Test func aRoutedPageWithoutASameProfileSourceBorrowsNoDestinationSelection() {
        let r = Routed()
        let unsourced = TabCreationProvenance(routedFrom: nil, openedLink: false, profileID: r.f.profile, state: r.state)
        #expect(unsourced.referrerID == nil && unsourced.activeTabBeforeCreationID == nil)
    }

    @Test func urlOnlyNewWindowCreationDoesNotAdoptAnUnrelatedCurrentSelection() {
        let r = Routed()
        let windowOnly = TabCreationProvenance(referrerID: nil, activeTabID: nil, profileID: r.f.profile, state: r.state)
        #expect(windowOnly.referrerID == nil && windowOnly.activeTabBeforeCreationID == nil)
    }

    @Test func creationIDsRoundTripWithTheSavedRecord() throws {
        let f = Fixture()
        let encoded = try JSONEncoder().encode(f.child)
        #expect(try JSONDecoder().decode(BrowserTab.self, from: encoded) == f.child)
    }

    @Test func oldRecordsDecodeWithoutInventingProvenance() throws {
        let f = Fixture()
        let encoded = try JSONEncoder().encode(f.child)
        var old = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "referrerID")
        old.removeValue(forKey: "activeTabBeforeCreationID")
        let decoded = try JSONDecoder().decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(decoded.referrerID == nil && decoded.activeTabBeforeCreationID == nil)
    }
}
