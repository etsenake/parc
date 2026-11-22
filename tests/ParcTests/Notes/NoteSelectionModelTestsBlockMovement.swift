import CoreGraphics
import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteSelectionModelTestsBlockMovement {
    private typealias Block = NoteSelectionModelTestsSupport.Layout.Block

    private func navigator(_ blocks: [Block]) -> (NoteSelectionNavigator, NoteSelectionModelTestsSupport.Layout) {
        let layout = NoteSelectionModelTestsSupport.Layout(blocks)
        return (NoteSelectionNavigator(items: layout.items), layout)
    }

    private let a = Block(text: "first"), b = Block(text: "second")

    @MainActor private struct Stepping {
        let a = Block(text: "a"), parent = Block(text: "parent")
        let child1: Block, child2: Block, columns = Block(role: .layout)
        let left: Block, inLeft: Block, right: Block, inRight: Block
        let z = Block(text: "z")

        init() {
            child1 = Block(text: "c1", depth: 1, parent: parent.id)
            child2 = Block(text: "c2", depth: 1, parent: parent.id)
            left = Block(role: .column, depth: 1, parent: columns.id)
            inLeft = Block(text: "left", depth: 2, parent: left.id)
            right = Block(role: .column, depth: 1, parent: columns.id)
            inRight = Block(text: "right", depth: 2, parent: right.id)
        }

        var all: [Block] { [a, parent, child1, child2, columns, left, inLeft, right, inRight, z] }
    }

    private let stepping = Stepping()

    private func step(from ids: [NoteBlockID], forward: Bool) -> NoteBlockID? {
        navigator(stepping.all).0.step(from: ids, forward: forward)
    }

    @Test func downGoesToTheNextBlock() {
        #expect(step(from: [stepping.a.id], forward: true) == stepping.parent.id)
    }

    @Test func downSkipsASelectedParentsChildrenAndLayoutContainers() {
        #expect(step(from: [stepping.parent.id], forward: true) == stepping.inLeft.id)
    }

    @Test func upStepsIntoSiblings() {
        #expect(step(from: [stepping.child2.id], forward: false) == stepping.child1.id)
    }

    @Test func upFromBelowColumnsLandsInTheLastColumn() {
        #expect(step(from: [stepping.z.id], forward: false) == stepping.inRight.id)
    }

    @Test func downAtTheEndStays() {
        #expect(step(from: [stepping.z.id], forward: true) == stepping.z.id)
    }

    @Test func upAtTheStartStays() {
        #expect(step(from: [stepping.a.id], forward: false) == stepping.a.id)
    }

    @Test func downFromAMultiSelectionGoesPastTheLastBlock() {
        #expect(step(from: [stepping.a.id, stepping.child1.id], forward: true) == stepping.child2.id)
    }

    @Test func upFromAMultiSelectionAtTheStartStaysOnTheFirst() {
        #expect(step(from: [stepping.a.id, stepping.child1.id], forward: false) == stepping.a.id)
    }

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

    private func extend(_ range: NoteBlockRange, _ steps: [Bool]) -> NoteBlockRange {
        let nav = navigator(extending.all).0
        return steps.reduce(range) { nav.extend($0, forward: $1) }
    }

    private func covering(_ range: NoteBlockRange) -> [NoteBlockID] {
        navigator(extending.all).0.blocks(from: range.anchor, to: range.head)
    }

    @Test func theSelectionExtendsDown() {
        let range = extend(NoteBlockRange(anchor: extending.a.id, head: extending.a.id), [true])
        #expect(range.head == extending.parent.id)
        #expect(covering(range) == [extending.a.id, extending.parent.id])
    }

    @Test func extendingDownSkipsTheParentsChildren() {
        #expect(extend(NoteBlockRange(anchor: extending.a.id, head: extending.a.id), [true, true]).head == extending.x.id)
    }

    @Test func shrinkingUpReturnsToTheParentNotItsLastChild() {
        #expect(extend(NoteBlockRange(anchor: extending.a.id, head: extending.a.id), [true, true, false]).head == extending.parent.id)
    }

    @Test func theSelectionShrinksBackToItsAnchor() {
        let range = extend(NoteBlockRange(anchor: extending.a.id, head: extending.a.id), [true, true, false, false])
        #expect(range.head == extending.a.id)
        #expect(covering(range) == [extending.a.id])
    }

    @Test func theSelectionExtendsUpIntoChildren() {
        let range = extend(NoteBlockRange(anchor: extending.x.id, head: extending.x.id), [false])
        #expect(range.head == extending.child2.id)
        #expect(covering(range) == [extending.child2.id, extending.x.id])
    }

    @Test func reachingTheParentFoldsChildrenIn() {
        let range = extend(NoteBlockRange(anchor: extending.x.id, head: extending.x.id), [false, false, false])
        #expect(range.head == extending.parent.id)
        #expect(covering(range) == [extending.parent.id, extending.x.id])
    }

    @Test func shrinkingDownSkipsTheParentsChildren() {
        #expect(extend(NoteBlockRange(anchor: extending.x.id, head: extending.x.id), [false, false, false, true]).head == extending.x.id)
    }

    @Test func shrinkingStopsAtANestedAnchor() {
        let nested = NoteBlockRange(anchor: extending.child1.id, head: extending.x.id)
        #expect(extend(nested, [false]).head == extending.child1.id)
    }

    @Test func extendingPastTheStartDoesNothing() {
        let edge = NoteBlockRange(anchor: extending.a.id, head: extending.a.id)
        #expect(extend(edge, [false]) == edge)
    }
}
