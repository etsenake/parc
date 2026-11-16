import AppKit

@main @MainActor struct Checks {
    static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let deck = MiniPlayerDeck(frame: NSRect(x: 0, y: 0, width: 212, height: 200))
        window.contentView = deck
        func item(_ id: String) -> MiniPlayerItem {
            let page = PCNativePage(), state = PCNativeMediaState(identifier: id)
            page.mediaState = state
            return MiniPlayerItem(page: page, state: state, icon: nil,
                                  host: MiniPlayerHostLease(window), valid: { true }, reveal: {})
        }
        let first = item("first"), second = item("second")
        func row(_ id: String) -> NSView {
            descendants(deck).first { view in
                String(describing: type(of: view)) == "MiniPlayerRow" && descendants(view).contains {
                    ($0 as? ActionButton)?.accessibilityLabel() == "Back to Tab — \(id)"
                }
            }!
        }
        deck.update([first, second]); deck.layoutSubtreeIfNeeded()
        let retainedSecond = row("second")
        deck.update([second]); deck.layoutSubtreeIfNeeded()
        deck.update([first, second]); deck.layoutSubtreeIfNeeded()
        precondition(row("second") === retainedSecond, "remaining row retains identity")
        precondition(row("first").frame.minY > row("second").frame.minY,
                     "returning earlier admission is in front")
        let expand = descendants(deck).compactMap { $0 as? ActionButton }
            .first { $0.parcTooltip?.label.hasPrefix("Show All Mini Players") == true }!
        expand.actionBlock?(); deck.layoutSubtreeIfNeeded()
        let chain = SidebarAccessibility.keyViews(in: [deck], space: deck)
        SidebarAccessibility.link(chain, within: deck, exit: nil)
        let firstIndex = chain.firstIndex { $0 === row("first") }!
        let secondIndex = chain.firstIndex { $0 === row("second") }!
        precondition(firstIndex < secondIndex, "expanded static chain follows admission order")
        precondition(secondIndex > 0 && chain[secondIndex - 1].nextKeyView === row("second"),
                     "expanded chain is relinked")
        window.close()
        print("Mini Player admission order check passed")
    }
}
