import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteSelectionModelTestsSelectionCoverage {
    private typealias Block = NoteSelectionModelTestsSupport.Layout.Block

    private func navigator(_ blocks: [Block]) -> (NoteSelectionNavigator, NoteSelectionModelTestsSupport.Layout) {
        let layout = NoteSelectionModelTestsSupport.Layout(blocks)
        return (NoteSelectionNavigator(items: layout.items), layout)
    }

    private let a = Block(text: "first"), b = Block(text: "second")

    @MainActor private struct Extension {
        let a = Block(text: "a"), parent = Block(text: "parent")
        let child1: Block, child2: Block
        let x = Block(text: "x")

        init() {
            child1 = Block(text: "c1", depth: 1, parent: parent.id)
            child2 = Block(text: "c2", depth: 1, parent: parent.id)
        }

        var all: [Block] { [a, parent, child1, child2, x] }
    }

    private let extending = Extension()

    @MainActor private struct Layouts {
        let a = Block(text: "a"), columns = Block(role: .layout)
        let left: Block, inLeft: Block, right: Block, inRight: Block
        let z = Block(text: "z")

        init() {
            left = Block(role: .column, depth: 1, parent: columns.id)
            inLeft = Block(text: "left", depth: 2, parent: left.id)
            right = Block(role: .column, depth: 1, parent: columns.id)
            inRight = Block(text: "right", depth: 2, parent: right.id)
        }

        var all: [Block] { [a, columns, left, inLeft, right, inRight, z] }
    }

    private let layouts = Layouts()

    @Test func aRangeCoveringEveryColumnPicksTheColumnList() {
        #expect(navigator(layouts.all).0.blocks(from: layouts.a.id, to: layouts.z.id) == [layouts.a.id, layouts.columns.id, layouts.z.id])
    }

    @Test func aPartialRangeKeepsBlocksNeverALoneColumn() {
        #expect(navigator(layouts.all).0.blocks(from: layouts.inRight.id, to: layouts.z.id) == [layouts.inRight.id, layouts.z.id])
    }

    @Test func coveringEveryColumnsBlocksPicksTheColumnList() {
        #expect(navigator(layouts.all).0.blocks(from: layouts.inLeft.id, to: layouts.inRight.id) == [layouts.columns.id])
    }

    @Test func aColumnAloneIsNeverSelected() {
        #expect(navigator(layouts.all).0.normalized([layouts.left.id]) == [])
    }

    @Test func expandedWalksTheSubtree() {
        #expect(navigator(layouts.all).0.expanded([layouts.columns.id])
                == [layouts.columns.id, layouts.left.id, layouts.inLeft.id, layouts.right.id, layouts.inRight.id])
    }

    @Test func topLevelListsOnlyTopLevelBlocks() {
        #expect(navigator(layouts.all).0.topLevel == [layouts.a.id, layouts.columns.id, layouts.z.id])
    }

    private func toggle(_ id: NoteBlockID, in ids: [NoteBlockID]) -> [NoteBlockID] {
        navigator(extending.all).0.toggling(id, in: ids)
    }

    @Test func commandClickAdds() {
        #expect(toggle(extending.x.id, in: [extending.a.id]) == [extending.a.id, extending.x.id])
    }

    @Test func commandClickRemoves() {
        #expect(toggle(extending.a.id, in: [extending.a.id, extending.x.id]) == [extending.x.id])
    }

    @Test func commandClickOnAChildOfASelectedParentKeepsItsSiblings() {
        #expect(toggle(extending.child1.id, in: [extending.parent.id]) == [extending.child2.id])
    }

    @Test func childrenStayChildrenWithoutTheirParent() {
        #expect(toggle(extending.child1.id, in: [extending.child2.id]) == [extending.child1.id, extending.child2.id])
    }

    @MainActor private struct Marquee {
        let a = Block(text: "a"), parent = Block(text: "parent")
        let child: Block
        let x = Block(text: "x")
        let nav: NoteSelectionNavigator
        let layout: NoteSelectionModelTestsSupport.Layout

        init() {
            child = Block(text: "child", depth: 1, parent: parent.id, x: 26)
            layout = NoteSelectionModelTestsSupport.Layout([a, parent, child, x])
            let parentFrame = layout.items[1].frame, childFrame = layout.items[2].frame
            layout.setFrame(1, CGRect(x: parentFrame.minX, y: parentFrame.minY, width: parentFrame.width, height: childFrame.maxY - parentFrame.minY))
            nav = NoteSelectionNavigator(items: layout.items)
        }

        var parentFrame: CGRect { layout.items[1].frame }
        var childFrame: CGRect { layout.items[2].frame }
    }

    @Test func aParentsOwnRowStopsAtItsFirstChild() {
        let marquee = Marquee()
        #expect(marquee.nav.ownFrame(at: 1).height == marquee.childFrame.minY - marquee.parentFrame.minY)
    }

    @Test func aMarqueeOverTheChildRowPicksTheChildOnly() {
        let marquee = Marquee()
        #expect(marquee.nav.marquee(CGRect(x: 100, y: marquee.childFrame.midY, width: 20, height: 1)) == [marquee.child.id])
    }

    @Test func touchingTheParentRowSelectsTheParentWithItsChildren() {
        let marquee = Marquee()
        let both = CGRect(x: 100, y: marquee.parentFrame.midY - 5, width: 20, height: marquee.childFrame.minY - marquee.parentFrame.midY + 10)
        #expect(marquee.nav.marquee(both) == [marquee.parent.id])
    }

    @Test func aMarginRectangleAloneTouchesNothing() {
        let marquee = Marquee()
        #expect(marquee.nav.marquee(CGRect(x: -80, y: 0, width: 30, height: marquee.layout.items[1].frame.minY + 2)) == [])
    }

    @Test func aMarginRectangleSelectsTheRowsBesideIt() {
        let marquee = Marquee()
        let rect = CGRect(x: -80, y: 0, width: 30, height: marquee.layout.items[1].frame.minY + 2)
        #expect(marquee.nav.marquee(rect, column: 0...400) == [marquee.a.id, marquee.parent.id])
    }
}
