import Foundation

enum Place: Equatable { case general, profiles, links, profile(Int) }

@main struct SettingsNavigationTests {
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        var assertions = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            assertions += 1; precondition(value(), message)
        }
        var history = SettingsNavigation<Place>()
        expect(history.current == nil && !history.canGoBack && !history.canGoForward, "A fresh window has no history")
        history.visit(.general)
        history.visit(.general)
        expect(history.entries == [.general], "Reselecting the shown page does not add history")
        history.visit(.profiles)
        history.visit(.profile(1))
        expect(history.previous == .profiles && history.canGoBack && !history.canGoForward, "Drilling into a profile can go back to the list")
        history.moveBack()
        expect(history.current == .profiles && history.next == .profile(1), "Back returns to the list with Forward available")
        history.visit(.links)
        expect(history.entries == [.general, .profiles, .links] && !history.canGoForward, "A new page replaces the forward history")
        history.visit(.profiles)
        history.visit(.profile(2))
        history.moveBack(); history.moveBack()
        history.removeAll(where: { $0 == .profile(2) }, replacingCurrentWith: .profiles)
        expect(history.entries == [.general, .profiles, .links, .profiles] && history.current == .links,
               "A removed profile leaves history without touching the shown page")
        history.moveForward()
        history.visit(.profile(3))
        history.removeAll(where: { $0 == .profile(3) }, replacingCurrentWith: .profiles)
        expect(history.current == .profiles && history.entries.last == .profiles && history.entries.filter { $0 == .profiles }.count == 2,
               "Removing the shown profile returns to the list without a duplicate entry")
        history.replaceCurrent(with: .links)
        expect(history.entries == [.general, .profiles, .links], "Replacing the current page collapses a repeated neighbour")
        expect(history.current == .links && history.canGoBack, "The replaced page stays current")
        print("Settings navigation: \(assertions) assertions passed")
    }
}
