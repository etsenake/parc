import AppKit

@main @MainActor struct SidebarDockStripTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarDockStrip: \(message)") }
    }
    final class RecordingButton: NSButton {
        var alphaSets: [(value: CGFloat, duration: TimeInterval)] = []
        var moves = 0
        override var alphaValue: CGFloat { didSet { alphaSets.append((alphaValue, NSAnimationContext.current.duration)) } }
        override func viewWillMove(toSuperview newSuperview: NSView?) { super.viewWillMove(toSuperview: newSuperview); moves += 1 }
    }
    static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 0.5 && abs(a.maxX - b.maxX) <= 0.5 && abs(a.minY - b.minY) <= 0.5 && abs(a.maxY - b.maxY) <= 0.5
    }
    static func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.45)) }
    static func sets(_ buttons: [NSButton]) -> [[(value: CGFloat, duration: TimeInterval)]] { buttons.map { ($0 as! RecordingButton).alphaSets } }
    static func reset(_ buttons: [NSButton]) { for button in buttons { (button as! RecordingButton).alphaSets.removeAll() } }
    static func buttons(_ count: Int, from start: Int = 0) -> [NSButton] {
        (start..<start + count).map { index in
            let button = RecordingButton(frame: .zero)
            button.isBordered = false; button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
            button.imagePosition = .imageOnly
            SidebarAccessibility.configureSpace(button, name: "Space \(index)")
            return button
        }
    }
    static func titles(_ children: [Any]?) -> [String] {
        (children ?? []).compactMap { ($0 as AnyObject as? NSAccessibilityProtocol)?.accessibilityTitle() ?? nil }
    }
    static func parts(_ strip: SidebarDockStrip, _ name: String) -> [NSView] {
        strip.documentView!.subviews.filter { $0.identifier?.rawValue == name }
    }
    static func hover(_ strip: SidebarDockStrip, _ index: Int?) {
        let item = index.map { strip.layoutState.items[$0] }
        strip.updateHover(atWindowPoint: item.map { strip.documentView!.convert(NSPoint(x: $0.midX, y: $0.midY), to: nil) })
    }

    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        window.contentView = host
        let strip = SidebarDockStrip(frame: SidebarChromeLayout.dockStrip(width: 228, height: 50))
        host.addSubview(strip)
        strip.dark = false
        let light = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5)
        check(strip.contentInsets.left == 2 && strip.contentInsets.right == 2 && strip.contentInsets.top == 0, "the 0/2/0/2 insets")
        check(strip.horizontalScrollElasticity == .none && strip.verticalScrollElasticity == .none && !strip.drawsBackground, "no elasticity or background")

        let three = buttons(3)
        strip.items = three; strip.selectedIndex = 1
        strip.layoutSubtreeIfNeeded()
        check(strip.frame == NSRect(x: 40, y: 0, width: 148, height: 50), "the strip spans 40…width − 40")
        let regular = SidebarChromeLayout.dockLayout(width: 148, height: 50, count: 3, focused: 1)
        check(strip.layoutState == regular && !regular.compact, "the strip uses the recovered layout")
        check(zip(three, regular.items).allSatisfy { near($0.frame, $1) }, "buttons take their item frames")
        check(three.map(\.alphaValue) == [0.5, 1, 0.5], "selected icon at 1, others at the light resting alpha")
        check(three.allSatisfy { $0.contentTintColor == light }, "ForegroundSecondary tint without a Space colour")
        strip.dark = true; settle()
        check(three.map(\.alphaValue) == [0.35, 1, 0.35], "dark resting alpha")
        strip.dark = false; settle()

        strip.activeTints = [.systemGreen, .systemGreen, .systemGreen]
        strip.iconlessButtons = [ObjectIdentifier(three[1])]
        let iconlessDots = parts(strip, "SidebarDockItemPageIndicator")
        check(three[1].alphaValue == 0 && iconlessDots[1].alphaValue == 1 && iconlessDots[1].frame.width == 8,
              "selected iconless Space uses the eight point dot")
        check(iconlessDots[1].layer?.backgroundColor == light.cgColor, "iconless dot keeps secondary foreground rather than the accent")
        let iconlessCenter = NSPoint(x: three[1].frame.midX, y: three[1].frame.midY)
        check(strip.documentView!.hitTest(iconlessCenter) === three[1], "iconless dot retains the original Space hit target")
        check(titles(strip.accessibilityChildren()) == ["Space 0", "Space 1", "Space 2"], "iconless presentation keeps the Space accessibility owner")
        strip.iconlessButtons = []; strip.activeTints = []

        check(titles(strip.accessibilityChildren()) == ["Space 0", "Space 1", "Space 2"], "Space order left to right")
        check(titles(strip.documentView!.accessibilityChildren()) == ["Space 0", "Space 1", "Space 2"], "document order left to right")
        check(strip.accessibilityChildren()?.count == 3, "backgrounds and dots are not exposed")
        let create = buttons(1, from: 9)[0]
        create.setAccessibilityLabel("Create Space")
        SidebarAccessibility.configureSpace(create, name: "Create Space")
        strip.items = three + [create]; strip.selectedIndex = 3; strip.layoutSubtreeIfNeeded()
        check(titles(strip.accessibilityChildren()) == ["Space 0", "Space 1", "Space 2", "Create Space"], "the creation button comes last")
        check(zip(strip.items, strip.items.dropFirst()).allSatisfy { $0.frame.maxX <= $1.frame.minX + 0.5 }, "items run left to right")
        let moves = (three + [create]).map { ($0 as! RecordingButton).moves }
        strip.items = [three[2], three[0], three[1], create]
        check(titles(strip.accessibilityChildren()) == ["Space 2", "Space 0", "Space 1", "Create Space"], "a reorder updates the order")
        check((three + [create]).map { ($0 as! RecordingButton).moves } == moves && moves.allSatisfy { $0 > 0 },
              "a reorder never removes a button")
        strip.items = three; strip.selectedIndex = 1; strip.layoutSubtreeIfNeeded(); settle()
        check(create.superview == nil, "the creation button leaves with its item")
        check(titles(strip.accessibilityChildren()) == ["Space 0", "Space 1", "Space 2"], "order without the creation button")
        check(zip(three, regular.items).allSatisfy { near($0.frame, $1) }, "frames after the reorder")

        let backgrounds = parts(strip, "SidebarDockItemBackground")
        check(backgrounds.count == 3 && zip(backgrounds, regular.items).allSatisfy { near($0.frame, $1) }, "one background per item")
        check(backgrounds.allSatisfy { $0.layer?.cornerRadius == 6 && $0.layer?.cornerCurve == .continuous }, "radius 6, continuous")
        check(three.allSatisfy { !$0.acceptsFirstResponder } && !create.acceptsFirstResponder, "dock items take no keyboard focus")
        hover(strip, 0); settle()
        check(abs(three[0].alphaValue - 0.7) < 0.001 && three[1].alphaValue == 1, "a hovered item is highlighted")
        check(abs(backgrounds[0].alphaValue - 1) < 0.001 && backgrounds[1].alphaValue < 0.001, "the hovered item's background shows")
        reset(three)
        hover(strip, 0)
        check(sets(three).allSatisfy(\.isEmpty) && abs(backgrounds[0].alphaValue - 1) < 0.001,
              "identical hover identity does not rearrange")
        hover(strip, 2)
        check(zip(backgrounds, regular.items).allSatisfy { near($0.frame, $1) }, "backgrounds stay on their items")
        settle()
        check(backgrounds[0].alphaValue < 0.001 && abs(backgrounds[2].alphaValue - 1) < 0.001, "the backgrounds cross-fade")
        hover(strip, nil); settle()
        check(backgrounds.allSatisfy { $0.alphaValue < 0.001 } && three[0].alphaValue == 0.5, "leaving clears the highlight")
        reset(three)
        hover(strip, nil)
        check(sets(three).allSatisfy(\.isEmpty), "a repeated clear does not rearrange")
        hover(strip, 0); settle()
        strip.superview!.isHidden = true
        check(backgrounds.allSatisfy { $0.alphaValue < 0.001 } && three[0].alphaValue == 0.5, "hiding the sidebar clears the hover")
        strip.superview!.isHidden = false
        check(backgrounds.allSatisfy { $0.alphaValue < 0.001 }, "showing it again in a window that is not key hovers nothing")
        hover(strip, 0); settle()
        strip.setPresented(false)
        check(!strip.isHiddenOrHasHiddenAncestor && backgrounds.allSatisfy { $0.alphaValue < 0.001 } && three[0].alphaValue == 0.5,
              "a dock leaving with an unhidden sidebar clears the hover")
        strip.setPresented(true)
        check(backgrounds.allSatisfy { $0.alphaValue < 0.001 }, "its return in a window that is not key hovers nothing")

        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        strip.activeTints = [nil, red, blue]
        check(three[0].contentTintColor == light && three[1].contentTintColor == red && three[2].contentTintColor == light,
              "the selected Space takes its colour; idle ones keep ForegroundSecondary")
        hover(strip, 2); settle()
        check(three[2].contentTintColor == blue && abs(three[2].alphaValue - 0.7) < 0.001, "a highlighted Space takes its colour")
        hover(strip, nil); settle()
        check(three[2].contentTintColor == light, "the colour leaves with the highlight")

        reset(three)
        strip.selectedIndex = 2
        check(sets(three)[2].map(\.value) == [1] && sets(three)[1].map(\.value) == [0.5] && sets(three)[0].isEmpty,
              "a switch sets only the two changing icons")
        check(sets(three).joined().allSatisfy { $0.duration > 0 } || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              "the switch animates")
        reset(three)
        strip.items = Array(three); strip.activeTints = [nil, red, blue]; strip.dark = false
        strip.needsLayout = true; strip.layoutSubtreeIfNeeded()
        check(sets(three).allSatisfy(\.isEmpty), "the same items, a layout pass and an unchanged style do not snap")
        strip.selectedIndex = 0
        reset(three)
        let extra = buttons(1, from: 3)[0]
        strip.items = three + [extra]; strip.layoutSubtreeIfNeeded()
        check(sets(three).allSatisfy(\.isEmpty), "a new item does not snap the others")
        check(sets([extra])[0].last.map { $0.value == 0.5 && $0.duration == 0 } == true, "a new item takes its style directly")
        settle()
        check(three.map(\.alphaValue) == [1, 0.5, 0.5] && extra.alphaValue == 0.5, "the switch settles")
        strip.items = three; strip.layoutSubtreeIfNeeded(); settle()
        check(extra.superview == nil && zip(three, regular.items).allSatisfy { near($0.frame, $1) }, "the extra item leaves")

        strip.selectedIndex = 2; settle(); reset(three)
        strip.items = Array(three.dropFirst()); strip.layoutSubtreeIfNeeded()
        check(strip.selectedIndex == 1 && sets([three[2]])[0].isEmpty, "the selection follows its item")
        strip.selectedIndex = 1; settle()
        check(sets([three[2]])[0].isEmpty && three[2].alphaValue == 1, "the owner's matching index restyles nothing")
        strip.items = [three[1]]
        check(strip.selectedIndex == nil, "a removed selection leaves none")
        reset(three); strip.selectedIndex = 0
        check(sets([three[1]])[0].map(\.value) == [1]
              && (sets([three[1]])[0].allSatisfy { $0.duration > 0 } || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion),
              "the successor of a removed selection cross-fades")
        settle()

        let eight = buttons(8)
        strip.items = eight; strip.selectedIndex = 3; strip.activeTints = []
        strip.layoutSubtreeIfNeeded(); settle()
        check(three.allSatisfy { $0.superview == nil }, "replaced items leave the strip")
        let compact = strip.layoutState
        check(compact.compact && compact.items[3].width == 22, "dot style and the focused selection")
        check(zip(eight, compact.items).allSatisfy { near($0.frame, $1) }, "compact frames")
        check(eight.enumerated().allSatisfy { $0.offset == 3 ? $0.element.alphaValue == 1 : $0.element.alphaValue == 0 }, "only the selected icon is drawn")
        let dots = parts(strip, "SidebarDockItemPageIndicator")
        check(dots.count == 8 && parts(strip, "SidebarDockItemBackground").count == 8, "one dot and background per item")
        for (index, dot) in dots.enumerated() {
            let item = compact.items[index]
            if index == 3 { check(dot.alphaValue == 0 && dot.frame.width == 8, "the selected item hides its dot"); continue }
            check(dot.alphaValue == 0.5 && dot.frame.size == CGSize(width: 4, height: 4) && abs(dot.frame.midX - item.midX) <= 0.5
                  && abs(dot.frame.midY - item.midY) <= 0.5 && dot.layer?.cornerRadius == 2, "a centred 4-point dot at 0.5")
        }
        check(parts(strip, "SidebarDockItemBackground").allSatisfy { $0.alphaValue == 0 }, "no hover background in the compact style")
        let center = strip.convert(NSPoint(x: compact.items[0].midX, y: compact.items[0].midY), from: strip.documentView)
        check(host.hitTest(strip.convert(center, to: host)) === eight[0], "the dot never takes the Space's click")
        check(eight.allSatisfy { !$0.isHidden && $0.cell?.accessibilityRoleDescription() == "Space" }, "dots keep the Space buttons accessible")
        check(titles(strip.accessibilityChildren()) == (0..<8).map { "Space \($0)" }, "compact order left to right")

        let many = buttons(30)
        strip.items = many; strip.selectedIndex = nil; strip.layoutSubtreeIfNeeded()
        strip.selectedIndex = 29
        let clip = strip.contentView
        check(strip.layoutState.contentWidth > 144 && strip.documentView!.frame.width == strip.layoutState.contentWidth, "overflowing content")
        check(abs(clip.bounds.minX - (strip.layoutState.contentWidth + 2 - 148)) < 0.5, "the last selection scrolls to the end")
        strip.selectedIndex = 0; settle()
        check(abs(clip.bounds.minX + 2) < 0.5, "a later selection scrolls back to the leading inset")
        strip.selectedIndex = 15; settle()
        let middle = strip.layoutState.items[15]
        check(abs(clip.bounds.midX - middle.midX) <= 0.5, "a middle selection is centred (to the backing pixel)")
        hover(strip, 0); settle()
        check(many[0].alphaValue == 0, "an item scrolled out of the strip is not hovered")
        hover(strip, 14); settle()
        check(abs(many[14].alphaValue - 0.7) < 0.001, "a visible compact item shows its icon while hovered")
        hover(strip, nil); settle()

        func sideways() -> NSEvent {
            NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: -3, wheel3: 0)!)!
        }
        var offered = 0
        strip.offerScroll = { _ in offered += 1; return true }
        check(strip.overflows, "thirty Spaces overflow the strip")
        let scrolled = clip.bounds.minX
        strip.scrollWheel(with: sideways()); settle()
        check(offered == 0 && clip.bounds.minX != scrolled, "an overflowing strip scrolls itself sideways")
        strip.items = three; strip.layoutSubtreeIfNeeded(); settle()
        check(!strip.overflows, "three Spaces fit")
        let resting = clip.bounds.origin
        strip.scrollWheel(with: sideways()); settle()
        check(offered == 1 && clip.bounds.origin == resting, "a strip that fits hands the swipe to the pager")
        strip.offerScroll = { _ in false }
        print("SidebarDockStrip: \(count) assertions passed")
    }
}
