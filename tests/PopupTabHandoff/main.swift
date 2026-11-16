@main struct PopupTabHandoffChecks {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        typealias Window = PopupTabHandoff.Candidate<Int>
        typealias Choice = PopupTabHandoff.Choice<Int>
        func choose(private source: Bool = false, _ windows: [Window]) -> Choice {
            PopupTabHandoff.choose(sourceIsPrivate: source, candidates: windows)
        }
        let open = Window(id: 1)
        let blocked = Window(id: 2, admitsHidden: false)
        let minimized = Window(id: 3, isMinimized: true, admitsHidden: false)
        let minimizedUnderSheet = Window(id: 4, isMinimized: true, admitsHidden: false, canRestore: false)
        let otherProfile = Window(id: 5, acceptsTabs: false)
        let privateWindow = Window(id: 6, isPrivate: true, sharesSession: false)
        let otherSession = Window(id: 7, sharesSession: false)

        check(choose([open]) == .existing(1), "An admitted main window takes the popup's request")
        check(choose([blocked]) == .freshWindow, "A main window under a sheet, dialog or security prompt sends the request to a fresh window")
        check(choose([open, blocked]) == .existing(1), "A blocked window gives way to another window that can take the request")
        check(choose([blocked, open]) == .existing(1), "The most recent admitted window wins, as before")
        check(choose([open, Window(id: 8)]) == .existing(8), "With two admitted windows the most recent one is used, unchanged")
        check(choose([]) == .freshWindow, "No main window opens a fresh one")
        check(choose([otherProfile]) == .freshWindow, "A window on another Profile never takes the request")
        check(choose([otherSession]) == .freshWindow, "A window outside the popup's browsing session never takes the request")
        check(choose([minimized]) == .existing(3), "An ordinary minimized window is restored instead of refused")
        check(choose([minimizedUnderSheet]) == .freshWindow, "A minimized window holding a sheet is not restored for nothing")
        check(choose([minimized, open]) == .existing(1), "Window order still decides between a minimized and a visible window")
        check(choose([open, privateWindow]) == .existing(1), "A normal popup never hands off to a private window")
        check(choose(private: true, [open]) == .freshWindow, "A private popup never hands off to a normal window")
        check(choose(private: true, [Window(id: 9, isPrivate: true)]) == .freshWindow,
              "A private popup always gets a new private window, even beside other private windows")
        check(choose(private: true, []) == .freshWindow, "A private popup with no window still gets a new private window")

        func arrival(source: Bool = true, destination: Bool = true, minimized: Bool = false, admits: Bool = true,
                     wait: Bool = true) -> PopupTabHandoff.Arrival {
            PopupTabHandoff.arrival(sourceCurrent: source, destinationCurrent: destination, isMinimized: minimized,
                                    admitsHidden: admits, mayAwaitRestore: wait)
        }
        check(arrival() == .deliver, "A window still admitted after coming forward receives the tab or address")
        check(arrival(admits: false) == .freshWindow, "A window that became blocked while coming forward falls back to a fresh window")
        check(arrival(destination: false) == .freshWindow, "A window that closed or changed Space or Profile during the handoff falls back to a fresh window")
        check(arrival(source: false) == .abandon, "A popup whose original page went away delivers nothing")
        check(arrival(source: false, admits: false) == .abandon, "A vanished origin wins over a fallback window")
        check(arrival(minimized: true, admits: false) == .awaitRestore, "A window still restoring is waited for")
        check(arrival(minimized: true, admits: false, wait: false) == .freshWindow,
              "A window that never finished restoring falls back to a fresh window")
        print("PopupTabHandoff: \(checks) assertions passed")
    }
}
