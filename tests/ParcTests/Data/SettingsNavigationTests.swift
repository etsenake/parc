import Testing
@testable import Parc

struct SettingsNavigationTests {
    enum Place: Equatable { case general, profiles, links, profile(Int) }

    private static func history(_ visits: [Place]) -> SettingsNavigation<Place> {
        var history = SettingsNavigation<Place>()
        for place in visits { history.visit(place) }
        return history
    }

    @Test func aFreshWindowHasNoHistory() {
        let history = SettingsNavigation<Place>()
        #expect(history.current == nil)
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test func reselectingTheShownPageAddsNoHistory() {
        #expect(Self.history([.general, .general]).entries == [.general])
    }

    @Test func drillingIntoAProfileCanGoBackToTheList() {
        let history = Self.history([.general, .profiles, .profile(1)])
        #expect(history.previous == .profiles)
        #expect(history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test func backReturnsToTheListWithForwardAvailable() {
        var history = Self.history([.general, .profiles, .profile(1)])
        history.moveBack()
        #expect(history.current == .profiles)
        #expect(history.next == .profile(1))
    }

    @Test func aNewPageReplacesTheForwardHistory() {
        var history = Self.history([.general, .profiles, .profile(1)])
        history.moveBack()
        history.visit(.links)
        #expect(history.entries == [.general, .profiles, .links])
        #expect(!history.canGoForward)
    }

    @Test func aRemovedProfileLeavesHistoryWithoutTouchingTheShownPage() {
        var history = Self.history([.general, .profiles, .links, .profiles, .profile(2)])
        history.moveBack()
        history.moveBack()
        history.removeAll(where: { $0 == .profile(2) }, replacingCurrentWith: .profiles)
        #expect(history.entries == [.general, .profiles, .links, .profiles])
        #expect(history.current == .links)
    }

    @Test func removingTheShownProfileReturnsToTheListWithoutADuplicateEntry() {
        var history = Self.history([.general, .profiles, .links, .profiles, .profile(3)])
        history.removeAll(where: { $0 == .profile(3) }, replacingCurrentWith: .profiles)
        #expect(history.current == .profiles)
        #expect(history.entries.last == .profiles)
        #expect(history.entries.filter { $0 == .profiles }.count == 2)
    }

    @Test func replacingTheCurrentPageCollapsesARepeatedNeighbour() {
        var history = Self.history([.general, .profiles, .links, .profiles])
        history.replaceCurrent(with: .links)
        #expect(history.entries == [.general, .profiles, .links])
    }

    @Test func theReplacedPageStaysCurrent() {
        var history = Self.history([.general, .profiles, .links, .profiles])
        history.replaceCurrent(with: .links)
        #expect(history.current == .links)
        #expect(history.canGoBack)
    }
}
