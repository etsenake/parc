import Foundation
import Testing
@testable import ParcCore

struct EaselBoardFeaturesReplaceTests {
    @Test
    func findIncludesLockedObjectsAndCardTitles() {
        let section = EaselBoardFeaturesTestsSupport.item(.section, "Ideas and ideas", x: 0, y: 0)
        let pinned = EaselBoardFeaturesTestsSupport.locked(EaselBoardFeaturesTestsSupport.item(.sticky, "ideas", x: 0, y: 300))
        let card = EaselBoardFeaturesTestsSupport.item(.link, "ideas.example", x: 300, y: 0)
        let board = EaselBoardFeaturesTestsSupport.document([section, pinned, card])
        let matches = EaselFinder.matches(of: "ideas", in: board)
        #expect(matches.count == 4, "locked objects and cards are still found")
    }

    @Test
    func replaceAllChangesWhatItCanAndCountsSkips() {
        let section = EaselBoardFeaturesTestsSupport.item(.section, "Ideas and ideas", x: 0, y: 0)
        let pinned = EaselBoardFeaturesTestsSupport.locked(EaselBoardFeaturesTestsSupport.item(.sticky, "ideas", x: 0, y: 300))
        let card = EaselBoardFeaturesTestsSupport.item(.link, "ideas.example", x: 300, y: 0)
        let board = EaselBoardFeaturesTestsSupport.document([section, pinned, card])
        let matches = EaselFinder.matches(of: "ideas", in: board)
        let outcome = EaselFinder.replace(matches, with: "Plans", in: board)
        #expect(outcome.count == 2 && outcome.touched == [section.id], "Replace All changes only what it can")
        #expect(outcome.skippedLocked == 1 && outcome.skippedReadOnly == 1 && outcome.skipped == 2, "skipped matches are counted by reason")
        #expect(outcome.document.items.first { $0.id == section.id }?.text == "Plans and Plans", "every match in one object is replaced")
        #expect(outcome.document.items.first { $0.id == pinned.id }?.text == "ideas", "locked objects keep their text")
    }

    @Test
    func replacingOneMatchLeavesOthersAlone() {
        let section = EaselBoardFeaturesTestsSupport.item(.section, "Ideas and ideas", x: 0, y: 0)
        let pinned = EaselBoardFeaturesTestsSupport.locked(EaselBoardFeaturesTestsSupport.item(.sticky, "ideas", x: 0, y: 300))
        let card = EaselBoardFeaturesTestsSupport.item(.link, "ideas.example", x: 300, y: 0)
        let board = EaselBoardFeaturesTestsSupport.document([section, pinned, card])
        let matches = EaselFinder.matches(of: "ideas", in: board)
        let single = EaselFinder.replace([matches[1]], with: "x", in: board)
        #expect(single.document.items.first { $0.id == section.id }?.text == "Ideas and x", "Replace changes only the given match")
    }

    @Test
    func replacingTextWithItselfChangesNothing() {
        let section = EaselBoardFeaturesTestsSupport.item(.section, "Ideas and ideas", x: 0, y: 0)
        let pinned = EaselBoardFeaturesTestsSupport.locked(EaselBoardFeaturesTestsSupport.item(.sticky, "ideas", x: 0, y: 300))
        let card = EaselBoardFeaturesTestsSupport.item(.link, "ideas.example", x: 300, y: 0)
        let board = EaselBoardFeaturesTestsSupport.document([section, pinned, card])
        let matches = EaselFinder.matches(of: "ideas", in: board)
        let same = EaselFinder.replace([matches[0]], with: "Ideas", in: board)
        #expect(same.count == 0 && same.document == board && same.skipped == 0, "replacing text with itself changes nothing and skips nothing")
    }

    @Test
    func replaceabilityExposesWhyAnObjectCannotChange() {
        let pinned = EaselBoardFeaturesTestsSupport.locked(EaselBoardFeaturesTestsSupport.item(.sticky, "ideas", x: 0, y: 300))
        let card = EaselBoardFeaturesTestsSupport.item(.link, "ideas.example", x: 300, y: 0)
        #expect(EaselFinder.replaceability(of: pinned) == .locked && EaselFinder.replaceability(of: card) == .readOnly,
               "locked objects and card titles report why they can't change")
    }

    @Test
    func replacingRichTextKeepsItsFormatting() {
        var sticky = EaselBoardFeaturesTestsSupport.item(.sticky, "Hello world", x: 0, y: 0)
        sticky.richText = EaselRichText(runs: [
            .init(location: 0, length: 6, attributes: EaselBoardFeaturesTestsSupport.attributes("#000000FF")),
            .init(location: 6, length: 5, attributes: EaselBoardFeaturesTestsSupport.attributes("#FF0000FF", bold: true)),
        ])
        let board = EaselBoardFeaturesTestsSupport.document([sticky])
        let outcome = EaselFinder.replace(EaselFinder.matches(of: "world", in: board), with: "everyone", in: board)
        let next = outcome.document.items[0]
        #expect(next.text == "Hello everyone", "plain text follows the replacement")
        #expect(next.richText?.runs.count == 2 && next.richText?.runs[1].length == 8, "the replacement keeps the formatting it replaced")
        #expect(next.richText?.runs[1].attributes.ink == "#FF0000FF", "the replacement takes the first replaced character's colour")
        #expect((try? next.richText?.validate(text: next.text)) != nil, "replaced rich text stays valid")
    }

    @Test
    func deletingAcrossRunsKeepsTheFormattingOnBothSides() {
        var sticky = EaselBoardFeaturesTestsSupport.item(.sticky, "Hello world", x: 0, y: 0)
        sticky.richText = EaselRichText(runs: [
            .init(location: 0, length: 6, attributes: EaselBoardFeaturesTestsSupport.attributes("#000000FF")),
            .init(location: 6, length: 5, attributes: EaselBoardFeaturesTestsSupport.attributes("#FF0000FF", bold: true)),
        ])
        let board = EaselBoardFeaturesTestsSupport.document([sticky])
        let spanning = EaselFinder.replace(EaselFinder.matches(of: "o w", in: board), with: "", in: board).document.items[0]
        #expect(spanning.text == "Hellorld" && spanning.richText?.runs.map(\.length) == [4, 4], "deleting across runs keeps both sides")
        #expect((try? spanning.richText?.validate(text: spanning.text)) != nil, "deleting across runs stays valid")
    }

    @Test
    func deletingARunMergesMatchingNeighbours() {
        var merged = EaselBoardFeaturesTestsSupport.item(.text, "aXb", x: 0, y: 0)
        merged.richText = EaselRichText(runs: [
            .init(location: 0, length: 1, attributes: EaselBoardFeaturesTestsSupport.attributes("#000000FF")),
            .init(location: 1, length: 1, attributes: EaselBoardFeaturesTestsSupport.attributes("#00FF00FF")),
            .init(location: 2, length: 1, attributes: EaselBoardFeaturesTestsSupport.attributes("#000000FF")),
        ])
        let collapsed = EaselFinder.replace(EaselFinder.matches(of: "X", in: EaselBoardFeaturesTestsSupport.document([merged]), options: NoteFindOptions(matchCase: true)),
                                            with: "", in: EaselBoardFeaturesTestsSupport.document([merged])).document.items[0]
        #expect(collapsed.richText?.runs.count == 1 && collapsed.richText?.runs[0].length == 2, "neighbouring runs with the same look merge")
    }

    @Test
    func replacingTextAfterEmojiRespectsCharacterBoundaries() {
        let emoji = EaselBoardFeaturesTestsSupport.item(.text, "👋 hi 👋", x: 0, y: 0)
        let waved = EaselFinder.replace(EaselFinder.matches(of: "hi", in: EaselBoardFeaturesTestsSupport.document([emoji])), with: "hello", in: EaselBoardFeaturesTestsSupport.document([emoji]))
        #expect(waved.document.items[0].text == "👋 hello 👋", "offsets after emoji stay on character boundaries")
    }

    @Test
    func replacementLeavesTheWholeObjectWhenItCannotChangeOneMatch() {
        var text = EaselBoardFeaturesTestsSupport.item(.text, "ab\u{FFFC}ab", x: 0, y: 0)
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13])
        var picture = EaselBoardFeaturesTestsSupport.attributes("#000000FF")
        picture.image = .init(data: png, fileType: "public.png", width: 10, height: 10)
        text.richText = EaselRichText(runs: [
            .init(location: 0, length: 2, attributes: EaselBoardFeaturesTestsSupport.attributes("#000000FF")),
            .init(location: 2, length: 1, attributes: picture),
            .init(location: 3, length: 2, attributes: EaselBoardFeaturesTestsSupport.attributes("#000000FF")),
        ])
        let board = EaselBoardFeaturesTestsSupport.document([text])
        let swallowing = EaselFindMatch(itemID: text.id, part: .text, range: 1..<4)
        let plain = EaselFindMatch(itemID: text.id, part: .text, range: 0..<1)
        let refused = EaselFinder.replace([plain, swallowing], with: "x", in: board)
        #expect(refused.count == 0 && refused.touched.isEmpty && refused.skippedOther == 2,
               "if one match in an object can't change, the whole object is left alone and reported")
        #expect(refused.document == board, "a refused object keeps every character")
    }

    @Test
    func replacementRefusesOutOfRangeMatches() {
        var text = EaselBoardFeaturesTestsSupport.item(.text, "ab\u{FFFC}ab", x: 0, y: 0)
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13])
        var picture = EaselBoardFeaturesTestsSupport.attributes("#000000FF")
        picture.image = .init(data: png, fileType: "public.png", width: 10, height: 10)
        text.richText = EaselRichText(runs: [
            .init(location: 0, length: 2, attributes: EaselBoardFeaturesTestsSupport.attributes("#000000FF")),
            .init(location: 2, length: 1, attributes: picture),
            .init(location: 3, length: 2, attributes: EaselBoardFeaturesTestsSupport.attributes("#000000FF")),
        ])
        let board = EaselBoardFeaturesTestsSupport.document([text])
        let outside = EaselFindMatch(itemID: text.id, part: .text, range: 0..<99)
        #expect(EaselFinder.replace([outside], with: "x", in: board).skippedOther == 1, "out-of-range matches are refused")
    }

    @Test
    func replacementDeduplicatesMatches() {
        var text = EaselBoardFeaturesTestsSupport.item(.text, "ab\u{FFFC}ab", x: 0, y: 0)
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13])
        var picture = EaselBoardFeaturesTestsSupport.attributes("#000000FF")
        picture.image = .init(data: png, fileType: "public.png", width: 10, height: 10)
        text.richText = EaselRichText(runs: [
            .init(location: 0, length: 2, attributes: EaselBoardFeaturesTestsSupport.attributes("#000000FF")),
            .init(location: 2, length: 1, attributes: picture),
            .init(location: 3, length: 2, attributes: EaselBoardFeaturesTestsSupport.attributes("#000000FF")),
        ])
        let board = EaselBoardFeaturesTestsSupport.document([text])
        let plain = EaselFindMatch(itemID: text.id, part: .text, range: 0..<1)
        let twice = [plain, plain]
        #expect(EaselFinder.replace(twice, with: "z", in: board).count == 1, "the same match listed twice replaces once")
    }

    @Test
    func replacementRefusesOverlappingMatches() {
        var text = EaselBoardFeaturesTestsSupport.item(.text, "ab\u{FFFC}ab", x: 0, y: 0)
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13])
        var picture = EaselBoardFeaturesTestsSupport.attributes("#000000FF")
        picture.image = .init(data: png, fileType: "public.png", width: 10, height: 10)
        text.richText = EaselRichText(runs: [
            .init(location: 0, length: 2, attributes: EaselBoardFeaturesTestsSupport.attributes("#000000FF")),
            .init(location: 2, length: 1, attributes: picture),
            .init(location: 3, length: 2, attributes: EaselBoardFeaturesTestsSupport.attributes("#000000FF")),
        ])
        let board = EaselBoardFeaturesTestsSupport.document([text])
        let overlapping = [EaselFindMatch(itemID: text.id, part: .text, range: 0..<2), EaselFindMatch(itemID: text.id, part: .text, range: 1..<2)]
        #expect(EaselFinder.replace(overlapping, with: "z", in: board).skippedOther == 2, "overlapping matches refuse the object")
    }

    @Test
    func replaceAllRewritesOnlyMatchingCells() {
        var grid = EaselBoardFeaturesTestsSupport.item(.table, "", x: 0, y: 0, width: 280, height: 72)
        grid.table = EaselTable(columnWidths: [140, 140], rowHeights: [36, 36],
                                cells: [[EaselTableCell(text: "cat"), EaselTableCell(text: "dog")],
                                        [EaselTableCell(text: "cat food"), EaselTableCell(text: "")]])
        let board = EaselBoardFeaturesTestsSupport.document([grid])
        let matches = EaselFinder.matches(of: "cat", in: board)
        #expect(matches.map(\.part) == [.cell(row: 0, column: 0), .cell(row: 1, column: 0)], "table cells are searched row by row")
        let outcome = EaselFinder.replace(matches, with: "bird", in: board)
        let table = outcome.document.items[0].table
        #expect(outcome.count == 2 && table?.cells[0][0].text == "bird" && table?.cells[1][0].text == "bird food", "Replace All rewrites each matching cell")
        #expect(table?.cells[0][1].text == "dog", "other cells stay put")
    }

    @Test
    func replacingOneCellAdvancesToTheNextCell() {
        var grid = EaselBoardFeaturesTestsSupport.item(.table, "", x: 0, y: 0, width: 280, height: 72)
        grid.table = EaselTable(columnWidths: [140, 140], rowHeights: [36, 36],
                                cells: [[EaselTableCell(text: "cat"), EaselTableCell(text: "dog")],
                                        [EaselTableCell(text: "cat food"), EaselTableCell(text: "")]])
        let board = EaselBoardFeaturesTestsSupport.document([grid])
        let matches = EaselFinder.matches(of: "cat", in: board)
        #expect(matches.map(\.part) == [.cell(row: 0, column: 0), .cell(row: 1, column: 0)], "table cells are searched row by row")
        let outcome = EaselFinder.replace(matches, with: "bird", in: board)
        let after = EaselFindMatch(itemID: grid.id, part: .cell(row: 0, column: 0), range: 4..<4)
        #expect(EaselFinder.index(of: after, in: EaselFinder.matches(of: "bird", in: outcome.document), document: outcome.document) == 1,
               "after replacing a cell the next match is the next cell, not an earlier offset elsewhere")
    }

    @Test
    func oneInvalidCellRefusesReplacementForTheWholeTable() {
        var grid = EaselBoardFeaturesTestsSupport.item(.table, "", x: 0, y: 0, width: 280, height: 72)
        grid.table = EaselTable(columnWidths: [140, 140], rowHeights: [36, 36],
                                cells: [[EaselTableCell(text: "cat"), EaselTableCell(text: "dog")],
                                        [EaselTableCell(text: "cat food"), EaselTableCell(text: "")]])
        var broken = grid
        broken.table?.cells[1][0].richText = EaselRichText(runs: [.init(location: 0, length: 3, attributes: EaselBoardFeaturesTestsSupport.attributes("#000000FF"))])
        let refused = EaselFinder.replace(EaselFinder.matches(of: "cat", in: EaselBoardFeaturesTestsSupport.document([broken])), with: "x", in: EaselBoardFeaturesTestsSupport.document([broken]))
        #expect(refused.count == 0 && refused.skippedOther == 2, "a cell that can't change leaves the whole table alone")
    }

    @Test
    func lockedTablesAreSearchableAndCannotBeReplaced() {
        var grid = EaselBoardFeaturesTestsSupport.item(.table, "", x: 0, y: 0, width: 280, height: 72)
        grid.table = EaselTable(columnWidths: [140, 140], rowHeights: [36, 36],
                                cells: [[EaselTableCell(text: "cat"), EaselTableCell(text: "dog")],
                                        [EaselTableCell(text: "cat food"), EaselTableCell(text: "")]])
        let pinned = EaselBoardFeaturesTestsSupport.locked(grid)
        #expect(EaselFinder.replace(EaselFinder.matches(of: "cat", in: EaselBoardFeaturesTestsSupport.document([pinned])), with: "x", in: EaselBoardFeaturesTestsSupport.document([pinned])).skippedLocked == 2,
               "locked tables are found but not changed")
    }

    @Test
    func replacingTheCurrentMatchMovesToTheNext() {
        let first = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 0)
        let pinned = EaselBoardFeaturesTestsSupport.locked(EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 400))
        let third = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 800)
        let board = EaselBoardFeaturesTestsSupport.document([first, pinned, third])
        var state = EaselBoardFeaturesTestsSupport.session("cat", in: board)
        guard case .replaced(let outcome, let next) = state.replaceCurrent(with: "dog", in: board) else {
            Issue.record("the current, visible match is replaced"); return
        }
        #expect(outcome.touched == [first.id] && outcome.count == 1, "Replace changes only the current match")
        state.refresh(in: outcome.document, keeping: next)
        #expect(state.currentMatch?.itemID == pinned.id, "after Replace the next match becomes current")
    }

    @Test
    func replacingALockedMatchSkipsToTheNextOne() {
        let first = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 0)
        let pinned = EaselBoardFeaturesTestsSupport.locked(EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 400))
        let third = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 800)
        let board = EaselBoardFeaturesTestsSupport.document([first, pinned, third])
        var state = EaselBoardFeaturesTestsSupport.session("cat", in: board)
        guard case .replaced(let outcome, let next) = state.replaceCurrent(with: "dog", in: board) else {
            Issue.record("the current, visible match is replaced"); return
        }
        #expect(outcome.touched == [first.id] && outcome.count == 1, "Replace changes only the current match")
        state.refresh(in: outcome.document, keeping: next)
        #expect(state.countLabel(replacing: true, in: outcome.document) == "1 of 2 · locked", "a locked current match says so while replacing")
        #expect(state.countLabel(replacing: false, in: outcome.document) == "1 of 2", "plain finding doesn't fuss about locks")
        #expect(state.replaceCurrent(with: "dog", in: outcome.document) == .skipped, "Replace on a locked match skips ahead instead")
        #expect(state.currentMatch?.itemID == third.id, "the skip lands on the next match that can change")
    }

    @Test
    func replacingAVanishedMatchShowsTheNewMatchFirst() {
        let first = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 0)
        let pinned = EaselBoardFeaturesTestsSupport.locked(EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 400))
        let third = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 800)
        let board = EaselBoardFeaturesTestsSupport.document([first, pinned, third])
        var watched = EaselBoardFeaturesTestsSupport.session("cat", in: board)
        var changed = board
        changed.items[0].text = "bird"
        #expect(watched.replaceCurrent(with: "dog", in: changed) == .moved, "a match that vanished is never swapped for an unseen one")
        #expect(watched.currentMatch?.itemID == pinned.id, "the new current match is shown first")
    }

    @Test
    func changesElsewhereDoNotPreventReplacingTheVisibleMatch() {
        let first = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 0)
        let pinned = EaselBoardFeaturesTestsSupport.locked(EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 400))
        let third = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 800)
        let board = EaselBoardFeaturesTestsSupport.document([first, pinned, third])
        var stillThere = board
        stillThere.items[2].text = "cat!"
        var kept = EaselBoardFeaturesTestsSupport.session("cat", in: board)
        guard case .replaced(let keptOutcome, _) = kept.replaceCurrent(with: "dog", in: stillThere) else {
            Issue.record("an edit elsewhere doesn't stop Replace on the match you can see"); return
        }
        #expect(keptOutcome.touched == [first.id], "the visible match is the one replaced")
    }

    @Test
    func replacingRefusesWhenEveryMatchIsLocked() {
        let onlyLocked = EaselBoardFeaturesTestsSupport.document([EaselBoardFeaturesTestsSupport.locked(EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 0))])
        var stuck = EaselBoardFeaturesTestsSupport.session("cat", in: onlyLocked)
        #expect(stuck.replaceCurrent(with: "dog", in: onlyLocked) == .refused, "with nothing replaceable, Replace refuses")
    }

    @Test
    func identicalReplacementAdvancesPastTheMatch() {
        let first = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 0)
        let pinned = EaselBoardFeaturesTestsSupport.locked(EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 400))
        let third = EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 800)
        let board = EaselBoardFeaturesTestsSupport.document([first, pinned, third])
        var same = EaselBoardFeaturesTestsSupport.session("cat", in: board)
        guard case .replaced(let unchanged, let after) = same.replaceCurrent(with: "cat", in: board) else {
            Issue.record("replacing with the same text still moves on"); return
        }
        #expect(unchanged.touched.isEmpty && after.range.lowerBound == 3, "an identical replacement leaves the object alone and moves past it")
    }

    @Test func replaceAllWorksFromAFreshListAndSummarisesSkips() {
        let first = EaselBoardFeaturesTestsSupport.item(.sticky, "cat cat", x: 0, y: 0)
        let pinned = EaselBoardFeaturesTestsSupport.locked(EaselBoardFeaturesTestsSupport.item(.sticky, "cat", x: 0, y: 400))
        let card = EaselBoardFeaturesTestsSupport.item(.link, "cat facts", x: 0, y: 800)
        let board = EaselBoardFeaturesTestsSupport.document([first, pinned, card])
        var state = EaselBoardFeaturesTestsSupport.session("cat", in: board)
        var grown = board
        grown.items.append(EaselBoardFeaturesTestsSupport.item(.text, "cat", x: 0, y: 1200))
        let outcome = state.replaceAll(with: "dog", in: grown)
        #expect(outcome.count == 3, "Replace All works from a fresh list, including matches added since")
        #expect(outcome.skippedLocked == 1 && outcome.skippedReadOnly == 1, "Replace All counts what it skipped")
        #expect(EaselFindSession.summary(outcome) == "Skipped 1 locked, 1 read-only", "the summary names each reason")
        #expect(EaselFindSession.summary(EaselFindReplacement(document: board)).isEmpty, "nothing skipped means no summary")
        var odd = EaselFindReplacement(document: board)
        odd.skippedOther = 2
        #expect(EaselFindSession.summary(odd) == "Skipped 2 that couldn’t change", "unchangeable objects are reported too")
    }
}
