import Testing
@testable import ParcCore

struct NewSpaceWindowChoiceTests {
    typealias Choice = NewSpaceWindowChoice<Int>

    func window(_ id: Int, privately: Bool = false, popup: Bool = false, minimized: Bool = false, creating: Bool = false)
        -> (id: Int, isPrivate: Bool, isPopup: Bool, isMinimized: Bool, isCreating: Bool) {
        (id, privately, popup, minimized, creating)
    }

    @Test func noWindowsOpensANewRegularWindow() {
        #expect(Choice.choose(from: []) == .openNew)
    }

    @Test func onlyPrivateWindowsOpensANewRegularWindow() {
        #expect(Choice.choose(from: [window(1, privately: true)]) == .openNew)
    }

    @Test func onlyPopupsAndPrivateWindowsOpensANewRegularWindow() {
        #expect(Choice.choose(from: [window(1, popup: true), window(2, privately: true)]) == .openNew)
    }

    @Test func theFrontmostRegularWindowWinsOverPrivateOnes() {
        #expect(Choice.choose(from: [window(1, privately: true), window(2), window(3)]) == .existing(2))
    }

    @Test func popupsAreSkipped() {
        #expect(Choice.choose(from: [window(1, popup: true), window(2)]) == .existing(2))
    }

    @Test func aSingleRegularWindowIsUsed() {
        #expect(Choice.choose(from: [window(7)]) == .existing(7))
    }

    @Test func aMinimizedWindowGivesWayToAVisibleOne() {
        #expect(Choice.choose(from: [window(1, minimized: true), window(2)]) == .existing(2))
    }

    @Test func withEveryRegularWindowMinimizedTheFrontOneIsUsed() {
        #expect(Choice.choose(from: [window(1, minimized: true), window(2, minimized: true)]) == .existing(1))
    }

    @Test func aWindowAlreadyShowingTheFormIsReusedInsteadOfOpeningASecondForm() {
        #expect(Choice.choose(from: [window(1), window(2, creating: true)]) == .existing(2))
    }

    @Test func aPrivateWindowNeverHostsTheForm() {
        #expect(Choice.choose(from: [window(1), window(2, privately: true, creating: true)]) == .existing(1))
    }
}
