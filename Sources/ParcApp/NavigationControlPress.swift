import AppKit

// Captured at pointer-down, so a delayed press cannot act on a different tab.
struct NavigationControlInteraction {
    var activate: (Bool) -> Void
    var showHistory: ((NSView) -> Void)?
}


// One physical press owns one original navigation interaction. A history menu
// consumes the press before AppKit finishes tracking the button's mouse-up.
@MainActor
final class NavigationControlPress {
    static let historyHoldDuration: TimeInterval = 0.3
    let eventNumber: Int
    let alternate: Bool
    private(set) var finished = false
    private var interaction: NavigationControlInteraction?

    init(event: NSEvent, interaction: NavigationControlInteraction) {
        eventNumber = event.eventNumber
        alternate = event.buttonNumber == 2 || event.modifierFlags.contains(.command)
        self.interaction = interaction
    }
    var hasHistory: Bool { interaction?.showHistory != nil }
    func activate() {
        guard !finished, let interaction else { return }
        finished = true; self.interaction = nil
        interaction.activate(alternate)
    }
    func showHistory(from anchor: NSView) {
        guard !finished, let action = interaction?.showHistory else { return }
        finished = true; interaction = nil
        action(anchor)
    }
    func cancel() { finished = true; interaction = nil }
}
