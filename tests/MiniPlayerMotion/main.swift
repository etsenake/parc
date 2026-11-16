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
    precondition(card.frame == NSRect(x: 10, y: 15, width: 75, height: 70), "the layout change lands on the card's frame")
    precondition(unrelated.layer?.animation(forKey: "parc.media.position") == nil, "a view outside the deck and companion moves without animating")
    precondition(card.layer?.animation(forKey: "parc.media.opacity") == nil, "an unchanged opacity is not animated")
    precondition(card.layer?.animation(forKey: "unrelated") != nil, "the card keeps its own unrelated animation")
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        let spring = card.layer?.animation(forKey: "parc.media.position") as? CASpringAnimation
        precondition(spring != nil && companion.layer?.animation(forKey: "parc.media.position") != nil, "the card and its companion move on a spring")
        precondition(backCard.layer?.animation(forKey: "parc.media.opacity") != nil, "the rear card fades")
        let omega = 2 * Double.pi / 0.25
        precondition(abs(spring!.stiffness - omega * omega) < 0.01, "the spring answers in 0.25 seconds")
        precondition(abs(spring!.damping - 1.8 * omega) < 0.01, "the spring is damped at 0.9")
    }
    deck.removeFromSuperview()
    motion.settle()
    precondition(card.layer?.animation(forKey: "parc.media.position") == nil, "settling stops the card's spring")
    precondition(companion.layer?.animation(forKey: "parc.media.position") == nil, "settling stops the companion's spring")
    precondition(backCard.layer?.animation(forKey: "parc.media.opacity") == nil, "settling stops the rear card's fade")
    precondition(card.layer?.animation(forKey: "unrelated") != nil, "settling keeps the card's unrelated animation")
    precondition(unrelated.layer?.animation(forKey: "unrelated") != nil, "settling leaves other views' animations alone")
    precondition(MiniPlayerMotion.hoverOffDelay == 2, "the deck collapses 2 seconds after the pointer leaves")
    print("Mini Player inert motion checks passed")
}

MainActor.assumeIsolated { exitOnFailure(verifyMotion) }
