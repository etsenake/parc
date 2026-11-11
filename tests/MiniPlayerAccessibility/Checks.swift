import AppKit

@main @MainActor struct MiniPlayerAccessibilityChecks {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError(message) }
    }
    static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let deck = MiniPlayerDeck(frame: NSRect(x: 0, y: 0, width: 212, height: 200))
        window.contentView = deck
        let page = PCNativePage(), state = PCNativeMediaState(identifier: "one")
        state.title = "First"; state.canToggleCamera = true; state.canToggleMicrophone = true
        page.mediaState = state
        let first = MiniPlayerItem(page: page, state: state, icon: nil, host: MiniPlayerHostLease(window), valid: { true }, reveal: {})
        let otherPage = PCNativePage(), otherState = PCNativeMediaState(identifier: "two")
        otherState.title = "Second"; otherPage.mediaState = otherState
        let second = MiniPlayerItem(page: otherPage, state: otherState, icon: nil, host: MiniPlayerHostLease(window), valid: { true }, reveal: {})
        deck.update([first, second]); deck.layoutSubtreeIfNeeded()
        func button(_ label: String) -> ActionButton {
            guard let found = descendants(deck).compactMap({ $0 as? ActionButton }).first(where: { $0.accessibilityLabel() == label }) else {
                fatalError("missing label: \(label)")
            }
            return found
        }
        let expand = button("Show All Mini Players (2)")
        func checkName(_ control: ActionButton, _ name: String) {
            let tooltip = name.contains("Camera") ? "Toggle Camera" : name.contains("Microphone") ? "Toggle Microphone" : name
            check(control.parcTooltip?.label == tooltip && control.toolTip == nil && control.accessibilityHelp() == tooltip
                  && control.accessibilityLabel() == name && control.cell?.accessibilityLabel() == name
                  && control.image?.accessibilityDescription == name,
                  "button, cell and image agree on \(name); the tooltip and help say \(tooltip)")
        }
        checkName(expand, "Show All Mini Players (2)")
        check(expand.isAccessibilityExpanded() == false && expand.cell?.isAccessibilityExpanded() == false,
              "collapsed state is exposed on button and cell")
        expand.actionBlock?(); deck.layoutSubtreeIfNeeded()
        checkName(expand, "Collapse Mini Players")
        check(expand.isAccessibilityExpanded() && expand.cell?.isAccessibilityExpanded() == true,
              "expanded state is exposed on button and cell")
        for name in ["Pause", "Turn Camera On", "Unmute Microphone", "Mute Tab"] {
            let control = button(name)
            checkName(control, name)
        }
        let volumeButton = button("Adjust Tab Volume")
        check(volumeButton.isAccessibilityExpanded() == false && volumeButton.cell?.isAccessibilityExpanded() == false,
              "volume button initially reports collapsed")
        volumeButton.actionBlock?(); deck.layoutSubtreeIfNeeded()
        check(volumeButton.isAccessibilityExpanded() && volumeButton.cell?.isAccessibilityExpanded() == true,
              "volume button and exposed cell report expanded")
        volumeButton.actionBlock?(); deck.layoutSubtreeIfNeeded()
        check(volumeButton.isAccessibilityExpanded() == false && volumeButton.cell?.isAccessibilityExpanded() == false,
              "volume button and exposed cell report collapsed")
        state.playing = false; state.cameraOn = true; state.microphoneOn = true; state.muted = true
        deck.update([first, second]); deck.layoutSubtreeIfNeeded()
        for name in ["Play", "Turn Camera Off", "Mute Microphone", "Unmute Tab"] {
            let control = button(name)
            checkName(control, name)
        }
        let unmuteControls = descendants(deck).compactMap { $0 as? ActionButton }
            .filter { $0.accessibilityLabel() == "Unmute Tab" && !$0.isHidden }
        check(unmuteControls.count == 1, "muted volume control describes the unmute action")
        unmuteControls.forEach { checkName($0, "Unmute Tab") }
        expand.actionBlock?(); deck.layoutSubtreeIfNeeded()
        state.playing = true; page.mediaState = nil
        deck.update([first, second]); deck.layoutSubtreeIfNeeded()
        let row = descendants(deck).first { view in
            String(describing: type(of: view)) == "MiniPlayerRow" && descendants(view).contains {
                ($0 as? ActionButton)?.accessibilityLabel() == "Back to Tab — First"
            }
        }!
        let firstPause = descendants(row).compactMap { $0 as? ActionButton }
            .first { $0.accessibilityLabel() == "Pause" }!
        firstPause.actionBlock?(); deck.layoutSubtreeIfNeeded()
        let error = descendants(deck).compactMap { $0 as? NSTextField }
            .first { $0.stringValue == "This media is no longer available." }
        check(error != nil && error?.isHidden == false && error?.isHiddenOrHasHiddenAncestor == false,
              "failed collapsed action exposes its error")
        check(expand.accessibilityLabel() == "Collapse Mini Players", "failed action expands the deck")
        page.mediaState = state; firstPause.actionBlock?(); deck.layoutSubtreeIfNeeded()
        check(error?.isHidden == true, "an action on media that is back clears its error")
        page.mediaState = nil; firstPause.actionBlock?(); deck.layoutSubtreeIfNeeded()
        check(error?.isHidden == false && error?.isHiddenOrHasHiddenAncestor == false,
              "failed action in expanded deck exposes its error")
        deck.update([first]); deck.layoutSubtreeIfNeeded()
        page.mediaState = state; firstPause.actionBlock?(); deck.layoutSubtreeIfNeeded()
        check(error?.isHidden == true, "an action on media that is back clears its error")
        page.mediaState = nil; firstPause.actionBlock?(); deck.layoutSubtreeIfNeeded()
        check(error?.isHidden == false && error?.isHiddenOrHasHiddenAncestor == false,
              "failed action in a single player exposes its error")
        window.close()
        print("Mini Player accessibility label checks passed")
    }
}
