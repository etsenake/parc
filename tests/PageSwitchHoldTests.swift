import AppKit

@main
struct PageSwitchHoldTests {
    final class Pane {}
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(condition(), message)
    }
    static func same(_ panes: [Pane], _ expected: [Pane]) -> Bool {
        panes.count == expected.count && zip(panes, expected).allSatisfy { $0 === $1 }
    }

    @MainActor static func main() {
        let a = Pane(), b = Pane(), c = Pane(), d = Pane(), e = Pane(), note = Pane()

        var hold = PageSwitchHold<Pane>()
        expect(same(hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 0), []),
               "A tab switch parks nothing while the incoming page has not drawn")
        expect(same(hold.held, [a]) && same(hold.waiting, [b]), "The outgoing pane is held over the incoming one")
        expect(same(hold.presented(a), []), "A report from a page nobody waits for ends nothing")
        expect(same(hold.presented(b), [a]) && !hold.isHolding, "The incoming frame parks the outgoing pane")
        expect(same(hold.presented(b), []), "A late second report ends nothing")

        hold = PageSwitchHold<Pane>()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 10)
        let first = hold.hold
        expect(hold.deadline == 10 + PageSwitchHold<Pane>.cap, "The hold ends a second after it began")
        expect(same(hold.rearrange(leaving: [b], arriving: [c], drawing: [c], canHold: true, now: 10.3), [b]),
               "A pane that arrived under the hold was never seen and parks at once")
        _ = hold.rearrange(leaving: [c], arriving: [d], drawing: [d], canHold: true, now: 10.6)
        _ = hold.rearrange(leaving: [d], arriving: [e], drawing: [e], canHold: true, now: 10.9)
        expect(same(hold.held, [a]) && same(hold.waiting, [e]) && hold.hold == first
               && hold.deadline == 10 + PageSwitchHold<Pane>.cap,
               "Rapid switches keep the same hold and its original deadline")
        expect(same(hold.expire(at: 10.99), []) && hold.isHolding, "The hold lasts until its deadline")
        expect(same(hold.expire(at: 11), [a]) && !hold.isHolding && hold.deadline == nil,
               "A hold that survived several rapid switches ends one second after it began")

        hold = PageSwitchHold<Pane>()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 0)
        expect(same(hold.rearrange(leaving: [b], arriving: [c], drawing: [c], canHold: true, now: 1.2), [a, b])
               && !hold.isHolding, "A switch after the deadline ends the hold even before its timer runs")
        expect(same(hold.rearrange(leaving: [c], arriving: [d], drawing: [d], canHold: true, now: 1.3), [])
               && hold.hold == 2 && hold.deadline == 1.3 + PageSwitchHold<Pane>.cap,
               "The next switch begins a new hold with its own deadline")

        hold = PageSwitchHold<Pane>()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 0)
        expect(same(hold.rearrange(leaving: [b], arriving: [a], drawing: [a], canHold: true, now: 0.1), [b])
               && !hold.isHolding, "Switching straight back shows the held page, which never left the screen")

        hold = PageSwitchHold<Pane>()
        expect(same(hold.rearrange(leaving: [a], arriving: [note], drawing: [], canHold: true, now: 0), [a])
               && !hold.isHolding, "Switching to content that reports no frame is immediate")
        expect(same(hold.rearrange(leaving: [], arriving: [b], drawing: [b], canHold: true, now: 0), [])
               && !hold.isHolding, "Adding a split pane holds nothing: nothing left the screen")
        expect(same(hold.rearrange(leaving: [a], arriving: [c], drawing: [c], canHold: false, now: 0), [a])
               && !hold.isHolding, "A window that cannot hold parks at once")

        hold = PageSwitchHold<Pane>()
        _ = hold.rearrange(leaving: [a, b], arriving: [c, d], drawing: [c, d], canHold: true, now: 0)
        expect(same(hold.presented(c), []) && hold.isHolding, "A split switch waits for every incoming page")
        expect(same(hold.rearrange(leaving: [c], arriving: [], drawing: [], canHold: true, now: 0.1), [c])
               && hold.isHolding, "An incoming page that drew under the hold still parks at once when it leaves")
        expect(same(hold.presented(d), [a, b]) && !hold.isHolding, "The last incoming frame parks every held pane")

        hold = PageSwitchHold<Pane>()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true, now: 0)
        expect(same(hold.rearrange(leaving: [b], arriving: [note], drawing: [], canHold: true, now: 0.1), [a, b])
               && !hold.isHolding, "Leaving for content with no frame ends the hold and parks everything that left")

        let area = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        area.autoresizesSubviews = false
        let page = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        area.addSubview(page)
        HeldPaneLayout.apply(true, to: page)
        expect(page.autoresizingMask == HeldPaneLayout.followsPageArea && page.layer?.zPosition == 1,
               "A held pane draws on top and follows the page area's size")
        area.setFrameSize(NSSize(width: 1000, height: 700))
        page.resize(withOldSuperviewSize: NSSize(width: 800, height: 600))
        expect(abs(page.frame.width - 500) < 1 && abs(page.frame.height - 700) < 1 && abs(page.frame.minX) < 1,
               "One side of a held split grows by its share of the page area")
        HeldPaneLayout.apply(false, to: page)
        expect(page.autoresizingMask == [] && page.layer?.zPosition == 0,
               "Releasing a held pane clears its resizing and stacking")

        print("PASS: \(assertions) page switch hold checks")
    }
}
