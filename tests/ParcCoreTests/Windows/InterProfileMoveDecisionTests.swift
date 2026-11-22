import Foundation
import Testing
@testable import ParcCore

struct InterProfileMoveDecisionTests {
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

    @Test func theDialogUsesItsExpectedButtonsAndCheckbox() {
        #expect(InterProfileMovePrompt.confirmTitle == "Move it")
        #expect(InterProfileMovePrompt.cancelTitle == "Cancel")
        #expect(InterProfileMovePrompt.suppressionTitle == "Don’t ask again")
    }

    @Test func theDialogUsesItsExpectedWidth() {
        #expect(InterProfileMovePrompt.dialogWidth == 455)
    }

    struct DecisionCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let confirmed: Bool
        let suppressed: Bool
        let expected: InterProfileMoveDecision
    }

    @Test(arguments: [
        DecisionCase(testDescription: "Move once", confirmed: true, suppressed: false, expected: .proceed),
        DecisionCase(testDescription: "Move and remember", confirmed: true, suppressed: true, expected: .alwaysProceed),
        DecisionCase(testDescription: "Cancel with the checkbox selected", confirmed: false, suppressed: true, expected: .abort),
    ])
    func theDialogDecisionMapsFromItsButtons(_ decision: DecisionCase) {
        #expect(InterProfileMovePrompt.decision(confirmed: decision.confirmed, suppressed: decision.suppressed) == decision.expected)
    }

    @Test func anUntitledSpaceUsesSpaceN() {
        var state = BrowserState.initial()
        state.spaces.append(BrowserSpace(id: UUID(), name: "", symbol: "circle", color: "B9B5D4", profileID: state.profiles[0].id))
        #expect(InterProfileMovePrompt(tabCount: 1, destinationSpaceID: state.spaces[1].id, state: state)?.destinationName == "Space 2")
    }
}
