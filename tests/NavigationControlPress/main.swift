import AppKit

@MainActor
func run() {
    var count = 0
    func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); count += 1
    }
    func event(_ modifiers: NSEvent.ModifierFlags = [], middle: Bool = false, number: Int = 1) -> NSEvent {
        if middle {
            let source = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                                 mouseCursorPosition: .zero, mouseButton: .center)!
            source.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
            source.setIntegerValueField(.mouseEventNumber, value: Int64(number))
            return NSEvent(cgEvent: source)!
        }
        return NSEvent.mouseEvent(with: .leftMouseDown,
                          location: .zero, modifierFlags: modifiers, timestamp: 1,
                          windowNumber: 0, context: nil, eventNumber: number,
                          clickCount: 1, pressure: 1)!
    }
    let anchor = NSView()
    var actions: [Bool] = []
    var menus = 0
    let interaction = NavigationControlInteraction(activate: { actions.append($0) },
                                                   showHistory: { received in
        expect(received === anchor, "history keeps the original anchor")
        menus += 1
    })
    let normal = NavigationControlPress(event: event(), interaction: interaction)
    expect(normal.hasHistory && !normal.finished, "new interaction is live")
    normal.activate(); normal.activate(); normal.showHistory(from: anchor)
    expect(actions == [false] && menus == 0, "ordinary press commits exactly once")
    expect(normal.finished && !normal.hasHistory, "commit drops captured closures")

    let command = NavigationControlPress(event: event([.command], number: 2), interaction: interaction)
    _ = event([], number: 3) // Later event/modifier state cannot change the captured press.
    command.activate()
    expect(actions == [false, true], "Command is captured at pointer-down")
    let shift = NavigationControlPress(event: event([.shift]), interaction: interaction)
    shift.activate()
    expect(actions.last == false, "Shift alone does not request an alternate destination")
    let commandShift = NavigationControlPress(event: event([.command, .shift]), interaction: interaction)
    commandShift.activate()
    expect(actions.last == true, "Shift does not invert the recovered Command alternate flag")
    let middleEvent = event(middle: true)
    expect(middleEvent.buttonNumber == 2, "isolated middle event has the actual button identity")
    let middle = NavigationControlPress(event: middleEvent, interaction: interaction)
    middle.activate()
    expect(actions.last == true, "middle button requests the alternate action")

    for flags: NSEvent.ModifierFlags in [[], [.command], [.option], [.shift]] {
        let before = actions.count
        let hold = NavigationControlPress(event: event(flags), interaction: interaction)
        hold.showHistory(from: anchor); hold.showHistory(from: anchor); hold.activate()
        expect(actions.count == before, "history consumes release even with a modifier")
        expect(hold.finished && !hold.hasHistory, "history releases the interaction")
    }
    expect(menus == 4, "one menu per physical hold")
    let beforeCancel = actions.count
    let cancelled = NavigationControlPress(event: event([.command]), interaction: interaction)
    cancelled.cancel(); cancelled.activate(); cancelled.showHistory(from: anchor)
    expect(actions.count == beforeCancel && menus == 4, "cancel never dispatches or opens history")
    expect(cancelled.finished && !cancelled.hasHistory, "cancel clears original owner closures")

    var recursive: NavigationControlPress!
    var recursiveCalls = 0
    recursive = NavigationControlPress(event: event(), interaction: .init(activate: { _ in
        recursiveCalls += 1; recursive.activate(); recursive.showHistory(from: anchor)
    }, showHistory: { _ in preconditionFailure("reentrant menu after commit") }))
    recursive.activate()
    expect(recursiveCalls == 1, "consumption precedes reentrant action dispatch")
    var recursiveMenu: NavigationControlPress!
    var recursiveMenus = 0
    recursiveMenu = NavigationControlPress(event: event(), interaction: .init(activate: { _ in
        preconditionFailure("reentrant activation after menu")
    }, showHistory: { _ in
        recursiveMenus += 1; recursiveMenu.activate(); recursiveMenu.showHistory(from: anchor)
    }))
    recursiveMenu.showHistory(from: anchor)
    expect(recursiveMenus == 1, "consumption precedes reentrant menu dispatch")

    let noHistory = NavigationControlPress(event: event(), interaction: .init(activate: { actions.append($0) }))
    expect(!noHistory.hasHistory, "refresh has no history owner")
    noHistory.showHistory(from: anchor)
    expect(!noHistory.finished, "unsupported history cannot consume an ordinary action")
    let beforeRefresh = actions.count; noHistory.activate()
    expect(actions.count == beforeRefresh + 1 && actions.last == false, "ordinary action remains available")

    final class Owner { var invoked = false }
    var original: Owner? = Owner(); weak let capturedOwner = original
    let owned = NavigationControlPress(event: event(), interaction: .init(activate: { [original] _ in
        original?.invoked = true
    }))
    original = nil
    expect(capturedOwner != nil, "the original interaction is retained until resolution")
    owned.cancel()
    expect(capturedOwner == nil, "cancellation releases the original interaction")
    expect(NavigationControlPress.historyHoldDuration == 0.3, "recovered native hold duration")
    print("\(count) navigation press assertions passed; no browser or posted events")
}
MainActor.assumeIsolated { run() }
