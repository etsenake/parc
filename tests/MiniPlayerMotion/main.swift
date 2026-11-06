import AppKit

@MainActor
func verifyMotion() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    root.wantsLayer = true
    let deck = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    let card = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
    let backCard = NSView(frame: NSRect(x: 5, y: 5, width: 45, height: 45))
    let companion = NSView(frame: NSRect(x: 100, y: 0, width: 50, height: 50))
    let unrelated = NSView(frame: NSRect(x: 0, y: 100, width: 50, height: 50))
    [deck, card, backCard, companion, unrelated].forEach { $0.wantsLayer = true }
    deck.addSubview(backCard); deck.addSubview(card); root.addSubview(deck); root.addSubview(companion); root.addSubview(unrelated)
    window.contentView = root
    let independent = CABasicAnimation(keyPath: "opacity")
    independent.fromValue = 0.2; independent.toValue = 1; independent.duration = 10
    card.layer?.add(independent, forKey: "unrelated")
    unrelated.layer?.add(independent, forKey: "unrelated")
    let motion = MiniPlayerMotion()
    motion.layout(in: root, deck: deck, companion: companion, animated: true) {
        card.frame = NSRect(x: 10, y: 15, width: 75, height: 70)
        backCard.alphaValue = 0.4
        companion.frame.origin.x = 110
        unrelated.frame.origin.x = 10
    }
    precondition(card.frame == NSRect(x: 10, y: 15, width: 75, height: 70))
    precondition(unrelated.layer?.animation(forKey: "parc.media.position") == nil)
    precondition(card.layer?.animation(forKey: "parc.media.opacity") == nil)
    precondition(card.layer?.animation(forKey: "unrelated") != nil)
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        let spring = card.layer?.animation(forKey: "parc.media.position") as? CASpringAnimation
        precondition(spring != nil && companion.layer?.animation(forKey: "parc.media.position") != nil)
        precondition(backCard.layer?.animation(forKey: "parc.media.opacity") != nil)
        let omega = 2 * Double.pi / 0.25
        precondition(abs(spring!.stiffness - omega * omega) < 0.01)
        precondition(abs(spring!.damping - 1.8 * omega) < 0.01)
    }
    deck.removeFromSuperview()
    motion.settle()
    precondition(card.layer?.animation(forKey: "parc.media.position") == nil)
    precondition(companion.layer?.animation(forKey: "parc.media.position") == nil)
    precondition(backCard.layer?.animation(forKey: "parc.media.opacity") == nil)
    precondition(card.layer?.animation(forKey: "unrelated") != nil)
    precondition(unrelated.layer?.animation(forKey: "unrelated") != nil)
    precondition(MiniPlayerMotion.hoverOffDelay == 2)
    print("Mini Player inert motion checks passed")
}

MainActor.assumeIsolated { verifyMotion() }
