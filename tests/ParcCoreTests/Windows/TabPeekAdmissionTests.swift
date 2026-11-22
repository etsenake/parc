import Foundation
import Testing
@testable import ParcCore

struct TabPeekAdmissionTests {
    private static func plan(_ edit: (inout TabPeekCandidate) -> Void) -> Result<TabPeekPlan, TabPeekRefusal> {
        var candidate = TabPeekCandidate(tabID: TabPeekTestsSupport.id, page: .live("page-a"))
        edit(&candidate)
        return TabPeekAdmission.plan(candidate)
    }

    @Test func aLiveTabPresentsItsOwnPage() {
        #expect(Self.plan { _ in } == .success(.present("page-a")))
    }

    @Test func anUnloadedTabLoadsStraightIntoThePeek() {
        #expect(Self.plan { $0.page = .unloaded(loadable: true); $0.holder = .nobody } == .success(.load))
    }

    @Test func anUnloadedTabClaimedHereLoadsToo() {
        #expect(Self.plan { $0.page = .unloaded(loadable: true) } == .success(.load))
    }

    @Test func aTabWithNoAddressCannotLoad() {
        #expect(Self.plan { $0.page = .unloaded(loadable: false) } == .failure(.unloadable))
    }

    @Test func aPageStillBeingCreatedIsLeftAlone() {
        #expect(Self.plan { $0.page = .creating } == .failure(.busy))
    }

    @Test func aFailedPageOpensNormallyNotInPeek() {
        #expect(Self.plan { $0.page = .failed } == .failure(.failed))
    }

    @Test func aClosedPageCannotBeShown() {
        #expect(Self.plan { $0.page = .closed } == .failure(.closed))
    }

    @Test func aPageInAnotherWindowMovesHereThroughTheTransferFirst() {
        #expect(Self.plan { $0.holder = .elsewhere(movable: true) } == .success(.moveHere))
    }

    @Test func aPageAnotherWindowCannotGiveUpIsRefused() {
        #expect(Self.plan { $0.holder = .elsewhere(movable: false) } == .failure(.heldElsewhere))
    }

    @Test func aTabAlreadyOnScreenIsNotPeeked() {
        #expect(Self.plan { $0.onScreen = true } == .failure(.onScreen))
    }

    @Test func aClosingOrMovingTabIsRefused() {
        #expect(Self.plan { $0.busy = true } == .failure(.busy))
    }

    @Test func anInternalPageThatIsNotANoteOrEaselIsRefused() {
        #expect(Self.plan { $0.content = .unsupported } == .failure(.unsupported))
    }

    @Test func anOpenNoteOrEaselPresentsItsOwnEditor() {
        #expect(Self.plan { $0.content = .document; $0.page = .live("document") } == .success(.present("document")))
    }

    @Test func aNoteOrEaselThatIsNotOpenYetOpensStraightIntoThePeek() {
        #expect(Self.plan { $0.content = .document; $0.page = .unloaded(loadable: true) } == .success(.load))
    }

    @Test func aNoteOrEaselThatFailedToOpenOpensNormally() {
        #expect(Self.plan { $0.content = .document; $0.page = .failed } == .failure(.failed))
    }

    @Test func aNoteOrEaselAlreadyOnScreenIsNotPeeked() {
        #expect(Self.plan { $0.content = .document; $0.onScreen = true } == .failure(.onScreen))
    }

    @Test func aNoteOrEaselNeedsAPageToFloatOver() {
        #expect(Self.plan { $0.content = .document; $0.parentCanHost = false } == .failure(.parent))
    }

    @Test func aNoteOrEaselInAnotherWindowMovesHereThroughTheTransferFirst() {
        #expect(Self.plan { $0.content = .document; $0.holder = .elsewhere(movable: true) } == .success(.moveHere))
    }

    @Test func aNoteOrEaselReplacesAShownPeek() {
        #expect(Self.plan { $0.content = .document; $0.shown = .peek(canClose: true) } == .success(.replaceShown))
    }

    @Test func aShownPeekIsNeverClosedForAPagePeekCannotShow() {
        #expect(Self.plan { $0.content = .unsupported; $0.shown = .peek(canClose: true) } == .failure(.unsupported))
    }

    @Test func aTabFromAnotherSpaceIsRefused() {
        #expect(Self.plan { $0.inActiveSpace = false } == .failure(.space))
    }

    @Test func aTabFromAnotherProfileIsRefused() {
        #expect(Self.plan { $0.profileMatches = false } == .failure(.profile))
    }

    @Test func thereMustBeAPageToFloatOver() {
        #expect(Self.plan { $0.parentCanHost = false } == .failure(.parent))
    }

    @Test func aBusyWindowRefuses() {
        #expect(Self.plan { $0.windowAdmits = false } == .failure(.window))
    }

    @Test func askingAgainForTheShownTabIsANoOp() {
        let id = TabPeekTestsSupport.id
        #expect(Self.plan { $0.windowAdmits = false; $0.shown = .tab(id, canClose: false) } == .success(.alreadyShown))
    }

    @Test func aShownPeekIsReplaced() {
        #expect(Self.plan { $0.shown = .peek(canClose: true) } == .success(.replaceShown))
    }

    @Test func anotherTabsPeekIsReplaced() {
        #expect(Self.plan { $0.shown = .tab(UUID(), canClose: true) } == .success(.replaceShown))
    }

    @Test func aPeekThatCannotCloseNowKeepsItsPlace() {
        #expect(Self.plan { $0.shown = .peek(canClose: false) } == .failure(.peekBusy))
    }

    @Test func aShownPeekIsNeverClosedForATabThatCannotOpenAnyway() {
        #expect(Self.plan { $0.shown = .peek(canClose: true); $0.page = .closed } == .failure(.closed))
    }

    @Test func theMenuOffersOpenInPeekForALiveTab() {
        #expect(TabPeekAdmission.offers(TabPeekCandidate(tabID: TabPeekTestsSupport.id, page: .live("page-a"))))
    }

    @Test func theMenuDoesNotOfferTheTabAlreadyInPeek() {
        var offered = TabPeekCandidate(tabID: TabPeekTestsSupport.id, page: .live("page-a"))
        offered.shown = .tab(TabPeekTestsSupport.id, canClose: true)
        #expect(!TabPeekAdmission.offers(offered))
    }

    @Test func theMenuDoesNotOfferARefusedTab() {
        var offered = TabPeekCandidate(tabID: TabPeekTestsSupport.id, page: .live("page-a"))
        offered.onScreen = true
        #expect(!TabPeekAdmission.offers(offered))
    }

    enum DeferredPlan: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case moveHere = "Move the page here"
        case replaceShown = "Replace the shown Peek"
        case alreadyShown = "Peek already shown"

        var testDescription: String { rawValue }
        var plan: TabPeekPlan {
            switch self {
            case .moveHere: .moveHere
            case .replaceShown: .replaceShown
            case .alreadyShown: .alreadyShown
            }
        }
    }

    @Test(arguments: DeferredPlan.allCases)
    func anotherWindowOrPeekMustBeResolvedBeforeStartingASession(_ deferred: DeferredPlan) {
        #expect(TabPeekSession(tabID: TabPeekTestsSupport.id, plan: deferred.plan) == nil)
    }

    @Test func theShownPeekClosesFirst() {
        let candidate = TabPeekCandidate(tabID: TabPeekTestsSupport.id, page: .live("page-a"), shown: .peek(canClose: true))
        #expect(TabPeekAdmission.plan(candidate) == .success(.replaceShown))
    }

    @Test func onceItIsGoneTheTabsPageOpensInTheSinglePeek() {
        let candidate = TabPeekCandidate(tabID: TabPeekTestsSupport.id, page: .live("page-a"), shown: .none)
        #expect(TabPeekAdmission.plan(candidate) == .success(.present("page-a")))
    }

    @Test func anotherTabsPeekReturnsFirst() {
        let candidate = TabPeekCandidate(tabID: TabPeekTestsSupport.id, page: .unloaded(loadable: true), shown: .tab(UUID(), canClose: true))
        #expect(TabPeekAdmission.plan(candidate) == .success(.replaceShown))
    }
}
