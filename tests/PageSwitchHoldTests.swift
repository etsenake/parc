/// The outgoing page stays on screen until the incoming page has drawn.
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

    static func main() {
        let a = Pane(), b = Pane(), c = Pane(), d = Pane(), note = Pane()

        var hold = PageSwitchHold<Pane>()
        expect(same(hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true), []),
               "A tab switch parks nothing while the incoming page has not drawn")
        expect(same(hold.held, [a]) && same(hold.waiting, [b]), "The outgoing pane is held over the incoming one")
        expect(same(hold.presented(a), []), "A report from a page nobody waits for ends nothing")
        expect(same(hold.presented(b), [a]) && !hold.isHolding, "The incoming frame parks the outgoing pane")
        expect(same(hold.presented(b), []), "A late second report ends nothing")

        hold = PageSwitchHold<Pane>()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true)
        let first = hold.generation
        expect(same(hold.rearrange(leaving: [b], arriving: [c], drawing: [c], canHold: true), [b]),
               "A pane that arrived under the hold was never seen and parks at once")
        expect(same(hold.held, [a]) && same(hold.waiting, [c]), "The pane on screen stays held for the next page")
        expect(same(hold.expire(first), []) && hold.isHolding, "An earlier cap cannot end a newer switch")
        expect(same(hold.expire(hold.generation), [a]) && !hold.isHolding,
               "A page that never draws releases the switch at the cap")

        hold = PageSwitchHold<Pane>()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true)
        expect(same(hold.rearrange(leaving: [b], arriving: [a], drawing: [a], canHold: true), [b]) && !hold.isHolding,
               "Switching straight back shows the held page, which never left the screen")

        hold = PageSwitchHold<Pane>()
        expect(same(hold.rearrange(leaving: [a], arriving: [note], drawing: [], canHold: true), [a]) && !hold.isHolding,
               "Switching to content that reports no frame is immediate")
        expect(same(hold.rearrange(leaving: [], arriving: [b], drawing: [b], canHold: true), []) && !hold.isHolding,
               "Adding a split pane holds nothing: nothing left the screen")
        expect(same(hold.rearrange(leaving: [a], arriving: [c], drawing: [c], canHold: false), [a]) && !hold.isHolding,
               "A window that cannot hold parks at once")

        hold = PageSwitchHold<Pane>()
        _ = hold.rearrange(leaving: [a, b], arriving: [c, d], drawing: [c, d], canHold: true)
        expect(same(hold.presented(c), []) && hold.isHolding, "A split switch waits for every incoming page")
        expect(same(hold.rearrange(leaving: [c], arriving: [], drawing: [], canHold: true), [c]) && hold.isHolding,
               "An incoming page that drew under the hold still parks at once when it leaves")
        expect(same(hold.presented(d), [a, b]) && !hold.isHolding, "The last incoming frame parks every held pane")

        hold = PageSwitchHold<Pane>()
        _ = hold.rearrange(leaving: [a], arriving: [b], drawing: [b], canHold: true)
        expect(same(hold.rearrange(leaving: [b], arriving: [note], drawing: [], canHold: true), [a, b]) && !hold.isHolding,
               "Leaving for content with no frame ends the hold and parks everything that left")

        print("PASS: \(assertions) page switch hold checks")
    }
}
