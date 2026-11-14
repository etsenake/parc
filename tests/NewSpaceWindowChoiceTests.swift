import Foundation

@main struct NewSpaceWindowChoiceTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    static func main() {
        typealias Choice = NewSpaceWindowChoice<Int>
        func w(_ id: Int, privately: Bool = false, popup: Bool = false, minimized: Bool = false, creating: Bool = false)
            -> (id: Int, isPrivate: Bool, isPopup: Bool, isMinimized: Bool, isCreating: Bool) {
            (id, privately, popup, minimized, creating)
        }
        check(Choice.choose(from: []) == .openNew, "No windows opens a new regular window")
        check(Choice.choose(from: [w(1, privately: true)]) == .openNew, "Only private windows opens a new regular window")
        check(Choice.choose(from: [w(1, popup: true), w(2, privately: true)]) == .openNew, "Only popups and private windows opens a new regular window")
        check(Choice.choose(from: [w(1, privately: true), w(2), w(3)]) == .existing(2), "Frontmost regular window wins over private ones")
        check(Choice.choose(from: [w(1, popup: true), w(2)]) == .existing(2), "Popups are skipped")
        check(Choice.choose(from: [w(7)]) == .existing(7), "A single regular window is used")
        check(Choice.choose(from: [w(1, minimized: true), w(2)]) == .existing(2), "A minimized window gives way to a visible one")
        check(Choice.choose(from: [w(1, minimized: true), w(2, minimized: true)]) == .existing(1), "With every regular window minimized, the front one is used")
        check(Choice.choose(from: [w(1), w(2, creating: true)]) == .existing(2), "A window already showing the form is reused instead of opening a second form")
        check(Choice.choose(from: [w(1), w(2, privately: true, creating: true)]) == .existing(1), "A private window never hosts the form")
        print("NewSpaceWindowChoiceTests: \(checks) assertions passed")
    }
}
