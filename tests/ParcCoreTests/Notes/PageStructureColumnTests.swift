import Foundation
import Testing
@testable import ParcCore

@MainActor struct PageStructureColumnTests: NoteFixtures {
    @Test func droppingBesideABlockMakesTwoColumns() {
        let session = makeSession([para("a"), para("b"), para("c")])
        session.placeBeside([session.id("b")], target: session.id("a"), side: .right)
        expectOutline(session.page, "columns\n  column\n    p a\n  column\n    p b\np c", "dropping beside a block makes two columns")
    }

    @Test func droppingBesideAColumnBlockAddsAColumn() {
        let session = makeSession([para("a"), para("b"), para("c")])
        session.placeBeside([session.id("b")], target: session.id("a"), side: .right)
        session.placeBeside([session.id("c")], target: session.id("a"), side: .left)
        expectOutline(session.page, "columns\n  column\n    p c\n  column\n    p a\n  column\n    p b", "dropping beside a column block adds a column")
    }

    @Test func columnsStartWithEqualWidths() {
        let session = makeSession([para("a"), para("b"), para("c")])
        session.placeBeside([session.id("b")], target: session.id("a"), side: .right)
        session.placeBeside([session.id("c")], target: session.id("a"), side: .left)
        let group = session.page.blocks[0].id
        #expect(session.page.columnFractions(of: group).map { ($0 * 3).rounded() } == [1, 1, 1], "columns start equal")
    }

    @Test func customColumnWidthsNormalizeToFractions() {
        let session = makeSession([para("a"), para("b"), para("c")])
        session.placeBeside([session.id("b")], target: session.id("a"), side: .right)
        session.placeBeside([session.id("c")], target: session.id("a"), side: .left)
        let group = session.page.blocks[0].id
        session.setColumnWidths(group, [2, 1, 1])
        #expect(session.page.columnFractions(of: group) == [0.5, 0.25, 0.25], "widths normalize to fractions")
    }

    @Test func customColumnWidthsRespectAMinimum() {
        let session = makeSession([para("a"), para("b"), para("c")])
        session.placeBeside([session.id("b")], target: session.id("a"), side: .right)
        session.placeBeside([session.id("c")], target: session.id("a"), side: .left)
        let group = session.page.blocks[0].id
        session.setColumnWidths(group, [100, 1, 1])
        #expect(session.page.columnFractions(of: group).allSatisfy { $0 >= NotePageSession.minimumColumnFraction * 0.9 }, "no column gets squeezed away")
    }

    @Test func aWidthListOfTheWrongLengthIsIgnored() {
        let session = makeSession([para("a"), para("b"), para("c")])
        session.placeBeside([session.id("b")], target: session.id("a"), side: .right)
        session.placeBeside([session.id("c")], target: session.id("a"), side: .left)
        let group = session.page.blocks[0].id
        session.setColumnWidths(group, [100, 1, 1])
        session.setColumnWidths(group, [1, 1])
        #expect(session.page.block(group)!.children[2].props.width != nil, "a width list of the wrong length is ignored")
    }

    @Test func resettingColumnWidthsClearsCustomWidths() {
        let session = makeSession([para("a"), para("b"), para("c")])
        session.placeBeside([session.id("b")], target: session.id("a"), side: .right)
        session.placeBeside([session.id("c")], target: session.id("a"), side: .left)
        let group = session.page.blocks[0].id
        session.setColumnWidths(group, [100, 1, 1])
        session.resetColumnWidths(group)
        #expect(session.page.block(group)!.children.allSatisfy { $0.props.width == nil }, "reset clears custom widths")
    }

    @Test func movingABlockBesideAnotherColumnReordersColumns() {
        let session = makeSession([para("a"), para("b"), para("c")])
        session.placeBeside([session.id("b")], target: session.id("a"), side: .right)
        session.placeBeside([session.id("c")], target: session.id("a"), side: .left)
        session.placeBeside([session.id("b")], target: session.id("c"), side: .left)
        expectOutline(session.page, "columns\n  column\n    p b\n  column\n    p c\n  column\n    p a", "moving a block from one column beside another reshuffles columns")
    }

    @Test func droppingBesideABlockInAFullColumnSetDoesNothing() {
        var crowded = [[para("1")], [para("2")], [para("3")], [para("4")], [para("5")]]
        crowded[0].append(para("6"))
        let full = makeSession([columns(crowded), para("extra")])
        full.placeBeside([full.id("extra")], target: full.id("3"), side: .right)
        expectOutline(full.page, "columns\n  column\n    p 1\n    p 6\n  column\n    p 2\n  column\n    p 3\n  column\n    p 4\n  column\n    p 5\np extra",
                      "a full set of columns refuses one more")
    }

    @Test func droppingBesideANestedBlockAddsAColumnToItsSet() {
        let nested = makeSession([columns([[bullet("x", [bullet("y")])], [para("z")]]), para("w")])
        nested.placeBeside([nested.id("w")], target: nested.id("y"), side: .right)
        #expect(nested.page.blocks[0].children.count == 3 && nested.page.allBlocks().filter { $0.kind == .columns }.count == 1, "dropping beside a nested block in a column adds a column instead of nesting columns")
    }

    @Test func aFullRowRefusesAnExtraColumn() {
        let fullRow = makeSession([columns([[para("1")], [para("2")], [para("3")], [para("4")], [para("5")]]), para("more")])
        fullRow.placeBeside([fullRow.id("more")], target: fullRow.page.blocks[0].id, side: .right)
        #expect(fullRow.page.blocks.count == 2 && fullRow.page.allBlocks().filter { $0.kind == .columns }.count == 1 && !fullRow.canUndo, "a whole row with five columns refuses instead of nesting columns")
    }

    @Test func aColumnInAFullRowRefusesAnotherBesideIt() {
        let fullRow = makeSession([columns([[para("1")], [para("2")], [para("3")], [para("4")], [para("5")]]), para("more")])
        fullRow.placeBeside([fullRow.id("more")], target: fullRow.page.blocks[0].children[2].id, side: .left)
        #expect(fullRow.page.blocks.count == 2 && !fullRow.canUndo, "so does one of its columns")
    }

    @Test func droppingBesideAWholeRowAddsAnEdgeColumn() {
        let pair = makeSession([columns([[para("l")], [para("r")]]), para("new")])
        pair.placeBeside([pair.id("new")], target: pair.page.blocks[0].id, side: .left)
        expectOutline(pair.page, "columns\n  column\n    p new\n  column\n    p l\n  column\n    p r", "dropping beside a whole row adds an edge column")
    }

    @Test func aColumnSetCannotBeDroppedBesideABlock() {
        let refuse = makeSession([columns([[para("x")], [para("y")]]), para("z")])
        refuse.placeBeside([refuse.page.blocks[0].id], target: refuse.id("z"), side: .right)
        #expect(refuse.page.blocks.count == 2, "columns can't be dropped beside a block")
    }

    @Test func movingIntoAColumnUsesTheRequestedIndex() {
        let session = makeSession([columns([[para("a"), para("b")], [para("c")]]), para("d")])
        let right = session.page.blocks[0].children[1].id
        session.moveBlocks([session.id("d")], toColumn: right, at: 0)
        expectOutline(session.page, "columns\n  column\n    p a\n    p b\n  column\n    p d\n    p c", "blocks move into a column at an index")
    }

    @Test func movingIntoAColumnPastItsEndAppends() {
        let session = makeSession([columns([[para("a"), para("b")], [para("c")]]), para("d")])
        let right = session.page.blocks[0].children[1].id
        session.moveBlocks([session.id("d")], toColumn: right, at: 0)
        session.moveBlocks([session.id("a")], toColumn: right, at: 9)
        expectOutline(session.page, "columns\n  column\n    p b\n  column\n    p d\n    p c\n    p a", "a large index appends")
    }

    @Test func movingTheLastBlockOutOfAColumnFoldsTheLayoutAway() {
        let session = makeSession([columns([[para("a"), para("b")], [para("c")]]), para("d")])
        let left = session.page.blocks[0].children[0].id, right = session.page.blocks[0].children[1].id
        session.moveBlocks([session.id("d")], toColumn: right, at: 0)
        session.moveBlocks([session.id("a")], toColumn: right, at: 9)
        session.moveBlocks([session.id("b")], toColumn: right, at: 1)
        expectOutline(session.page, "p d\np b\np c\np a", "emptying a column folds the layout away")
        #expect(!session.page.contains(left), "the empty column is gone")
    }

    @Test func columnsCannotMoveInsideAnotherColumn() {
        let invalid = makeSession([columns([[para("a")], [para("b")]]), columns([[para("c")], [para("d")]])])
        invalid.moveBlocks([invalid.page.blocks[1].id], to: .lastChild(of: invalid.page.blocks[0].children[0].id))
        #expect(invalid.page.blocks.count == 2, "columns can't move inside another column")
    }

    @Test func onlyColumnsCanSitDirectlyInAColumnSet() {
        let invalid = makeSession([columns([[para("a")], [para("b")]]), columns([[para("c")], [para("d")]])])
        invalid.moveBlocks([invalid.id("a")], to: .firstChild(of: invalid.page.blocks[0].id))
        #expect(invalid.page.blocks[0].children.allSatisfy { $0.kind == .column }, "only columns can sit directly in a column set")
    }

    struct ColumnGroup: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let values: [Int]
        let count: Int
        let expected: [[Int]]
    }

    private nonisolated static let columnGroups = [
        ColumnGroup(testDescription: "extra blocks go in the first columns", values: [1, 2, 3, 4, 5], count: 2, expected: [[1, 2, 3], [4, 5]]),
        ColumnGroup(testDescription: "equal counts give one block per column", values: [1, 2, 3], count: 3, expected: [[1], [2], [3]]),
        ColumnGroup(testDescription: "columns cannot outnumber blocks", values: [1, 2], count: 5, expected: [[1], [2]]),
    ]

    @Test(arguments: columnGroups) func columnGroupsDivideBlocksWithoutLeavingEmptyColumns(_ example: ColumnGroup) {
        #expect(NotePageSession.columnGroups(example.values, count: example.count) == example.expected)
    }

    @Test func fourSelectedSiblingsCanMakeFourColumns() {
        let session = makeSession([para("a"), bullet("b", [bullet("b1")]), para("c"), para("d"), para("e")])
        let picked = [session.id("a"), session.id("b"), session.id("c"), session.id("d")]
        #expect(session.columnSplitLimit(picked) == 4, "four blocks can make up to four columns")
    }

    @Test func oneBlockCannotBecomeColumns() {
        let session = makeSession([para("a"), bullet("b", [bullet("b1")]), para("c"), para("d"), para("e")])
        #expect(session.columnSplitLimit([session.id("a")]) == 0, "one block can't become columns")
    }

    @Test func blocksAtDifferentLevelsCannotBecomeColumns() {
        let session = makeSession([para("a"), bullet("b", [bullet("b1")]), para("c"), para("d"), para("e")])
        #expect(session.columnSplitLimit([session.id("a"), session.id("b1")]) == 0, "blocks at different levels can't become columns")
    }

    @Test func columnConversionKeepsBlockOrderSelectionAndChildren() {
        let session = makeSession([para("a"), bullet("b", [bullet("b1")]), para("c"), para("d"), para("e")])
        let picked = [session.id("a"), session.id("b"), session.id("c"), session.id("d")]
        session.setSelection(.blocks(picked))
        session.turnIntoColumns(picked, count: 2)
        expectOutline(session.page, "columns\n  column\n    p a\n    ul b\n      ul b1\n  column\n    p c\n    p d\np e",
                      "Turn into 2 columns splits the selection in order, children and all")
        #expect(session.selection == .blocks(picked), "the same blocks stay selected")
        #expect(session.undoActionName == "Turn Into", "it's one Turn Into step")
    }

    @Test func blocksAlreadyInColumnsCannotBecomeColumns() {
        let session = makeSession([para("a"), bullet("b", [bullet("b1")]), para("c"), para("d"), para("e")])
        let picked = [session.id("a"), session.id("b"), session.id("c"), session.id("d")]
        session.setSelection(.blocks(picked))
        session.turnIntoColumns(picked, count: 2)
        #expect(session.columnSplitLimit([session.id("a"), session.id("c")]) == 0, "blocks already in columns can't nest more columns")
    }

    @Test func undoRestoresBlocksAfterColumnConversion() {
        let session = makeSession([para("a"), bullet("b", [bullet("b1")]), para("c"), para("d"), para("e")])
        let picked = [session.id("a"), session.id("b"), session.id("c"), session.id("d")]
        session.setSelection(.blocks(picked))
        session.turnIntoColumns(picked, count: 2)
        session.undo()
        expectOutline(session.page, "p a\nul b\n  ul b1\np c\np d\np e", "undo puts the blocks back")
    }

    @Test func sixBlocksAreLimitedToFiveColumns() {
        let six = makeSession((1...6).map { para(String($0)) })
        let all = six.page.blocks.map(\.id)
        #expect(six.columnSplitLimit(all) == 5, "six blocks still stop at five columns")
    }

    @Test func fiveColumnsShareSixBlocks() {
        let six = makeSession((1...6).map { para(String($0)) })
        let all = six.page.blocks.map(\.id)
        six.turnIntoColumns(all, count: 5)
        #expect(six.page.blocks[0].children.map { $0.children.count } == [2, 1, 1, 1, 1], "five columns share six blocks")
    }

    @Test func convertingBlocksAlreadyInColumnsCannotNestColumns() {
        let six = makeSession((1...6).map { para(String($0)) })
        let all = six.page.blocks.map(\.id)
        six.turnIntoColumns(all, count: 5)
        six.turnIntoColumns([six.id("1"), six.id("2")], count: 2)
        #expect(six.page.allBlocks().filter { $0.kind == .columns }.count == 1, "no columns inside columns")
    }

    @Test func aSelectionContainingColumnsCannotNestThem() {
        let carrying = makeSession([columns([[para("l")], [para("r")]]), para("z")])
        #expect(carrying.columnSplitLimit([carrying.page.blocks[0].id, carrying.id("z")]) == 0, "a selection holding columns can't nest them")
    }

    @Test func plainTextNotesCannotSplitBlocksIntoColumns() {
        let flat = makeSession([para("p"), para("q")])
        flat.isFlat = true
        #expect(flat.columnSplitLimit([flat.id("p"), flat.id("q")]) == 0, "plain-text notes stay flat")
    }

    @Test func columnsCanFormInsideAToggle() {
        let toggle = makeSession([NoteBlock(.toggle, text: "t", children: [para("x"), para("y")])])
        toggle.turnIntoColumns([toggle.id("x"), toggle.id("y")], count: 2)
        let inner = toggle.page.blocks[0].children
        #expect(inner.count == 1 && inner[0].kind == .columns && inner[0].children.map { $0.children.map(\.text.plainText) } == [["x"], ["y"]], "columns can form inside a toggle")
    }
}
