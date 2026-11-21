import Foundation

@main
struct EaselBoardFeaturesTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    @MainActor static func main() {
        findOrder()
        findMatches()
        findVisibility()
        replacePlain()
        replaceRich()
        replaceRefusals()
        findTables()
        sessionRefresh()
        sessionReplace()
        sessionReplaceAll()
        viewportFocus()
        objectLinks()
        historyNames()
        historyPolicy()
        historyRecording()
        countdown()
        selectionExport()
        stickyCSV()
        templates()
        print("EaselBoardFeaturesTests: \(assertions) assertions passed")
    }

    static func item(_ kind: EaselItemKind, _ text: String, x: Double, y: Double, width: Double = 200, height: Double = 100) -> EaselItem {
        EaselItem(kind: kind, frame: .init(x: x, y: y, width: width, height: height), text: text)
    }

    static func locked(_ value: EaselItem) -> EaselItem {
        var copy = value
        copy.locked = true
        return copy
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Board", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    static func attributes(_ ink: String, bold: Bool = false) -> EaselRichText.Attributes {
        EaselRichText.Attributes(font: .init(name: "Helvetica", size: 15, traits: bold ? 2 : 0), ink: ink)
    }

    static func session(_ query: String, in board: EaselDocument) -> EaselFindSession {
        var value = EaselFindSession()
        value.query = query
        value.refresh(in: board, keeping: nil)
        return value
    }

    @MainActor static func findOrder() {
        let right = item(.sticky, "b", x: 300, y: 104)
        let left = item(.sticky, "a", x: 20, y: 100)
        let below = item(.sticky, "c", x: 0, y: 400)
        let order = EaselFinder.readingOrder([below, right, left]).map(\.text)
        expect(order == ["a", "b", "c"], "objects on roughly the same row read left to right before the next row")
        let tall = item(.section, "t", x: 0, y: 0, width: 100, height: 1000)
        let beside = item(.text, "s", x: 400, y: 450)
        expect(EaselFinder.readingOrder([beside, tall]).map(\.text) == ["t", "s"], "an object starting below half the row's anchor starts a new row")
    }

    @MainActor static func findMatches() {
        let sticky = item(.sticky, "Plan the launch, then plan the party", x: 0, y: 0)
        let arrow = item(.arrow, "plan B", x: 0, y: 300)
        let image = EaselItem(kind: .image, frame: .init(x: 0, y: 500, width: 10, height: 10), text: "plan", assetID: "x")
        let link = item(.link, "Planning guide", x: 300, y: 0)
        let board = document([link, arrow, sticky, image])
        let matches = EaselFinder.matches(of: "plan", in: board)
        expect(matches.count == 4, "stickies, connector labels and link cards match but images never do")
        expect(matches.map(\.itemID) == [sticky.id, sticky.id, link.id, arrow.id], "matches follow reading order")
        expect(matches[0].range == 0..<4 && matches[1].range == 22..<26, "ranges are UTF-16 offsets in order")
        expect(EaselFinder.matches(of: "plan", in: board, options: NoteFindOptions(matchCase: true)).count == 2, "Match Case is honoured")
        expect(EaselFinder.matches(of: "", in: board).isEmpty, "an empty query finds nothing")
        let accented = document([item(.text, "Café crème", x: 0, y: 0)])
        expect(EaselFinder.matches(of: "creme", in: accented).count == 1, "finding ignores accents unless Match Case is on")
        expect(EaselFinder.index(of: matches[2], in: matches, document: board) == 2, "the current match survives a refresh")
        let gone = EaselFindMatch(itemID: UUID(), part: .text, range: 0..<1)
        expect(EaselFinder.index(of: gone, in: matches, document: board) == 0, "a vanished match falls back to the first")
        expect(EaselFinder.index(of: nil, in: [], document: board) == nil, "no matches means no current match")
    }

    @MainActor static func findVisibility() {
        var section = item(.section, "Hidden plans", x: 0, y: 0, width: 600, height: 400)
        section.contentsHidden = true
        let inside = item(.sticky, "plans inside", x: 40, y: 60)
        var captured = item(.webCard, "plans captured", x: 900, y: 0)
        captured.url = "https://example.com/plans"
        captured.assetID = "a"
        var card = item(.webCard, "plans card", x: 900, y: 300)
        card.url = "https://example.com/plans"
        var live = item(.browser, "plans live", x: 900, y: 600)
        live.url = "https://example.com/plans"
        let board = document([section, inside, captured, card, live])
        let found = EaselFinder.matches(of: "plans", in: board).map(\.itemID)
        expect(found.contains(section.id), "a section hiding its contents still shows its own title")
        expect(!found.contains(inside.id), "objects tucked inside a hidden section are left out")
        expect(!found.contains(captured.id) && !found.contains(live.id), "captured and live webpages show no title on the canvas, so they aren't searched")
        expect(found.contains(card.id), "a webpage card that draws its title is searched")
        expect(EaselFinder.matches(of: "example", in: board).isEmpty, "hidden URLs are never searched")
    }

    @MainActor static func replacePlain() {
        let section = item(.section, "Ideas and ideas", x: 0, y: 0)
        let pinned = locked(item(.sticky, "ideas", x: 0, y: 300))
        let card = item(.link, "ideas.example", x: 300, y: 0)
        let board = document([section, pinned, card])
        let matches = EaselFinder.matches(of: "ideas", in: board)
        expect(matches.count == 4, "locked objects and cards are still found")
        let outcome = EaselFinder.replace(matches, with: "Plans", in: board)
        expect(outcome.count == 2 && outcome.touched == [section.id], "Replace All changes only what it can")
        expect(outcome.skippedLocked == 1 && outcome.skippedReadOnly == 1 && outcome.skipped == 2, "skipped matches are counted by reason")
        expect(outcome.document.items.first { $0.id == section.id }?.text == "Plans and Plans", "every match in one object is replaced")
        expect(outcome.document.items.first { $0.id == pinned.id }?.text == "ideas", "locked objects keep their text")
        let single = EaselFinder.replace([matches[1]], with: "x", in: board)
        expect(single.document.items.first { $0.id == section.id }?.text == "Ideas and x", "Replace changes only the given match")
        let same = EaselFinder.replace([matches[0]], with: "Ideas", in: board)
        expect(same.count == 0 && same.document == board && same.skipped == 0, "replacing text with itself changes nothing and skips nothing")
        expect(EaselFinder.replaceability(of: pinned) == .locked && EaselFinder.replaceability(of: card) == .readOnly,
               "locked objects and card titles report why they can't change")
    }

    @MainActor static func replaceRich() {
        var sticky = item(.sticky, "Hello world", x: 0, y: 0)
        sticky.richText = EaselRichText(runs: [
            .init(location: 0, length: 6, attributes: attributes("#000000FF")),
            .init(location: 6, length: 5, attributes: attributes("#FF0000FF", bold: true)),
        ])
        let board = document([sticky])
        let outcome = EaselFinder.replace(EaselFinder.matches(of: "world", in: board), with: "everyone", in: board)
        let next = outcome.document.items[0]
        expect(next.text == "Hello everyone", "plain text follows the replacement")
        expect(next.richText?.runs.count == 2 && next.richText?.runs[1].length == 8, "the replacement keeps the formatting it replaced")
        expect(next.richText?.runs[1].attributes.ink == "#FF0000FF", "the replacement takes the first replaced character's colour")
        expect((try? next.richText?.validate(text: next.text)) != nil, "replaced rich text stays valid")
        let spanning = EaselFinder.replace(EaselFinder.matches(of: "o w", in: board), with: "", in: board).document.items[0]
        expect(spanning.text == "Hellorld" && spanning.richText?.runs.map(\.length) == [4, 4], "deleting across runs keeps both sides")
        expect((try? spanning.richText?.validate(text: spanning.text)) != nil, "deleting across runs stays valid")
        var merged = item(.text, "aXb", x: 0, y: 0)
        merged.richText = EaselRichText(runs: [
            .init(location: 0, length: 1, attributes: attributes("#000000FF")),
            .init(location: 1, length: 1, attributes: attributes("#00FF00FF")),
            .init(location: 2, length: 1, attributes: attributes("#000000FF")),
        ])
        let collapsed = EaselFinder.replace(EaselFinder.matches(of: "X", in: document([merged]), options: NoteFindOptions(matchCase: true)),
                                            with: "", in: document([merged])).document.items[0]
        expect(collapsed.richText?.runs.count == 1 && collapsed.richText?.runs[0].length == 2, "neighbouring runs with the same look merge")
        let emoji = item(.text, "👋 hi 👋", x: 0, y: 0)
        let waved = EaselFinder.replace(EaselFinder.matches(of: "hi", in: document([emoji])), with: "hello", in: document([emoji]))
        expect(waved.document.items[0].text == "👋 hello 👋", "offsets after emoji stay on character boundaries")
    }

    @MainActor static func replaceRefusals() {
        var text = item(.text, "ab\u{FFFC}ab", x: 0, y: 0)
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13])
        var picture = attributes("#000000FF")
        picture.image = .init(data: png, fileType: "public.png", width: 10, height: 10)
        text.richText = EaselRichText(runs: [
            .init(location: 0, length: 2, attributes: attributes("#000000FF")),
            .init(location: 2, length: 1, attributes: picture),
            .init(location: 3, length: 2, attributes: attributes("#000000FF")),
        ])
        let board = document([text])
        let swallowing = EaselFindMatch(itemID: text.id, part: .text, range: 1..<4)
        let plain = EaselFindMatch(itemID: text.id, part: .text, range: 0..<1)
        let refused = EaselFinder.replace([plain, swallowing], with: "x", in: board)
        expect(refused.count == 0 && refused.touched.isEmpty && refused.skippedOther == 2,
               "if one match in an object can't change, the whole object is left alone and reported")
        expect(refused.document == board, "a refused object keeps every character")
        let outside = EaselFindMatch(itemID: text.id, part: .text, range: 0..<99)
        expect(EaselFinder.replace([outside], with: "x", in: board).skippedOther == 1, "out-of-range matches are refused")
        let twice = [plain, plain]
        expect(EaselFinder.replace(twice, with: "z", in: board).count == 1, "the same match listed twice replaces once")
        let overlapping = [EaselFindMatch(itemID: text.id, part: .text, range: 0..<2), EaselFindMatch(itemID: text.id, part: .text, range: 1..<2)]
        expect(EaselFinder.replace(overlapping, with: "z", in: board).skippedOther == 2, "overlapping matches refuse the object")
    }

    @MainActor static func findTables() {
        var grid = item(.table, "", x: 0, y: 0, width: 280, height: 72)
        grid.table = EaselTable(columnWidths: [140, 140], rowHeights: [36, 36],
                                cells: [[EaselTableCell(text: "cat"), EaselTableCell(text: "dog")],
                                        [EaselTableCell(text: "cat food"), EaselTableCell(text: "")]])
        let board = document([grid])
        let matches = EaselFinder.matches(of: "cat", in: board)
        expect(matches.map(\.part) == [.cell(row: 0, column: 0), .cell(row: 1, column: 0)], "table cells are searched row by row")
        let outcome = EaselFinder.replace(matches, with: "bird", in: board)
        let table = outcome.document.items[0].table
        expect(outcome.count == 2 && table?.cells[0][0].text == "bird" && table?.cells[1][0].text == "bird food", "Replace All rewrites each matching cell")
        expect(table?.cells[0][1].text == "dog", "other cells stay put")
        let after = EaselFindMatch(itemID: grid.id, part: .cell(row: 0, column: 0), range: 4..<4)
        expect(EaselFinder.index(of: after, in: EaselFinder.matches(of: "bird", in: outcome.document), document: outcome.document) == 1,
               "after replacing a cell the next match is the next cell, not an earlier offset elsewhere")
        var broken = grid
        broken.table?.cells[1][0].richText = EaselRichText(runs: [.init(location: 0, length: 3, attributes: attributes("#000000FF"))])
        let refused = EaselFinder.replace(EaselFinder.matches(of: "cat", in: document([broken])), with: "x", in: document([broken]))
        expect(refused.count == 0 && refused.skippedOther == 2, "a cell that can't change leaves the whole table alone")
        let pinned = locked(grid)
        expect(EaselFinder.replace(EaselFinder.matches(of: "cat", in: document([pinned])), with: "x", in: document([pinned])).skippedLocked == 2,
               "locked tables are found but not changed")
    }

    @MainActor static func sessionRefresh() {
        let first = item(.sticky, "cat cat", x: 0, y: 0)
        let second = item(.sticky, "cat", x: 0, y: 400)
        let board = document([first, second])
        var state = session("cat", in: board)
        expect(state.matches.count == 3 && state.currentIndex == 0, "a fresh search starts at the first match")
        state.step(1)
        state.step(1)
        expect(state.currentMatch?.itemID == second.id, "stepping walks in reading order")
        state.step(1)
        expect(state.currentIndex == 0, "stepping past the last match wraps to the first")
        state.step(-1)
        expect(state.currentIndex == 2, "stepping back from the first wraps to the last")
        var edited = board
        edited.items[0].text = "cat dog"
        state.refresh(in: edited, keeping: state.currentMatch)
        expect(state.currentMatch?.itemID == second.id && state.matches.count == 2, "a refresh after an edit keeps the current match")
        var preferred = EaselFindSession()
        preferred.query = "cat"
        preferred.refresh(in: board, keeping: nil) { matches in matches.firstIndex { $0.itemID == second.id } }
        expect(preferred.currentMatch?.itemID == second.id, "a new search can start at the first match already in view")
        expect(state.countLabel(replacing: false, in: edited) == "2 of 2", "the count says where you are")
        var none = session("zebra", in: board)
        expect(none.countLabel(replacing: true, in: board) == "No matches", "no matches says so")
        none.query = ""
        expect(none.countLabel(replacing: true, in: board).isEmpty, "an empty query shows no count")
    }

    @MainActor static func sessionReplace() {
        let first = item(.sticky, "cat", x: 0, y: 0)
        let pinned = locked(item(.sticky, "cat", x: 0, y: 400))
        let third = item(.sticky, "cat", x: 0, y: 800)
        let board = document([first, pinned, third])
        var state = session("cat", in: board)
        guard case .replaced(let outcome, let next) = state.replaceCurrent(with: "dog", in: board) else {
            return expect(false, "the current, visible match is replaced")
        }
        expect(outcome.touched == [first.id] && outcome.count == 1, "Replace changes only the current match")
        state.refresh(in: outcome.document, keeping: next)
        expect(state.currentMatch?.itemID == pinned.id, "after Replace the next match becomes current")
        expect(state.countLabel(replacing: true, in: outcome.document) == "1 of 2 · locked", "a locked current match says so while replacing")
        expect(state.countLabel(replacing: false, in: outcome.document) == "1 of 2", "plain finding doesn't fuss about locks")
        expect(state.replaceCurrent(with: "dog", in: outcome.document) == .skipped, "Replace on a locked match skips ahead instead")
        expect(state.currentMatch?.itemID == third.id, "the skip lands on the next match that can change")

        var watched = session("cat", in: board)
        var changed = board
        changed.items[0].text = "bird"
        expect(watched.replaceCurrent(with: "dog", in: changed) == .moved, "a match that vanished is never swapped for an unseen one")
        expect(watched.currentMatch?.itemID == pinned.id, "the new current match is shown first")
        var stillThere = board
        stillThere.items[2].text = "cat!"
        var kept = session("cat", in: board)
        guard case .replaced(let keptOutcome, _) = kept.replaceCurrent(with: "dog", in: stillThere) else {
            return expect(false, "an edit elsewhere doesn't stop Replace on the match you can see")
        }
        expect(keptOutcome.touched == [first.id], "the visible match is the one replaced")

        let onlyLocked = document([locked(item(.sticky, "cat", x: 0, y: 0))])
        var stuck = session("cat", in: onlyLocked)
        expect(stuck.replaceCurrent(with: "dog", in: onlyLocked) == .refused, "with nothing replaceable, Replace refuses")
        var same = session("cat", in: board)
        guard case .replaced(let unchanged, let after) = same.replaceCurrent(with: "cat", in: board) else {
            return expect(false, "replacing with the same text still moves on")
        }
        expect(unchanged.touched.isEmpty && after.range.lowerBound == 3, "an identical replacement leaves the object alone and moves past it")
    }

    @MainActor static func sessionReplaceAll() {
        let first = item(.sticky, "cat cat", x: 0, y: 0)
        let pinned = locked(item(.sticky, "cat", x: 0, y: 400))
        let card = item(.link, "cat facts", x: 0, y: 800)
        let board = document([first, pinned, card])
        var state = session("cat", in: board)
        var grown = board
        grown.items.append(item(.text, "cat", x: 0, y: 1200))
        let outcome = state.replaceAll(with: "dog", in: grown)
        expect(outcome.count == 3, "Replace All works from a fresh list, including matches added since")
        expect(outcome.skippedLocked == 1 && outcome.skippedReadOnly == 1, "Replace All counts what it skipped")
        expect(EaselFindSession.summary(outcome) == "Skipped 1 locked, 1 read-only", "the summary names each reason")
        expect(EaselFindSession.summary(EaselFindReplacement(document: board)).isEmpty, "nothing skipped means no summary")
        var odd = EaselFindReplacement(document: board)
        odd.skippedOther = 2
        expect(EaselFindSession.summary(odd) == "Skipped 2 that couldn’t change", "unchangeable objects are reported too")
    }

    @MainActor static func viewportFocus() {
        let visible = EaselRect(x: 0, y: 0, width: 1000, height: 800)
        let inside = EaselRect(x: 400, y: 300, width: 200, height: 100)
        expect(EaselViewportFocus.plan(target: inside, visible: visible, magnification: 1, minimum: 0.33, maximum: 4) == nil,
               "a match already in view doesn't move the canvas")
        let offscreen = EaselRect(x: 3000, y: 2000, width: 200, height: 100)
        let pan = EaselViewportFocus.plan(target: offscreen, visible: visible, magnification: 1, minimum: 0.33, maximum: 4)
        expect(pan?.magnification == 1 && pan?.center == EaselPoint(x: 3100, y: 2050), "an off-screen match pans to its centre")
        let huge = EaselRect(x: 0, y: 0, width: 4000, height: 3000)
        let out = EaselViewportFocus.plan(target: huge, visible: visible, magnification: 1, minimum: 0.33, maximum: 4)
        expect((out?.magnification ?? 1) < 1, "a match bigger than the view zooms out to fit")
        let tiny = EaselViewportFocus.plan(target: inside, visible: EaselRect(x: 0, y: 0, width: 4000, height: 3200), magnification: 0.25,
                                           minimum: 0.25, maximum: 4)
        expect(tiny?.magnification == 1, "a match too small to read zooms in to 100%")
        let focused = EaselViewportFocus.plan(target: inside, visible: visible, magnification: 2.5, minimum: 0.33, maximum: 4, mode: .focus)
        expect(focused?.magnification == 1 && focused?.center == EaselPoint(x: 500, y: 350), "focusing a link shows its object at 100%")
        let bad = EaselRect(x: .nan, y: 0, width: 1, height: 1)
        expect(EaselViewportFocus.plan(target: bad, visible: visible, magnification: 1, minimum: 0.33, maximum: 4) == nil, "bad geometry is ignored")
    }

    final class Clock {
        var now = Date(timeIntervalSinceReferenceDate: 700_000_000)
    }

    @MainActor static func historyNames() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)
        let name = EaselHistory.fileName(savedAt: date, itemCount: 12)
        expect(name == "v-1700000000123-12.json", "version files carry their time and object count")
        let parsed = EaselHistory.parse(name)
        expect(parsed?.itemCount == 12 && parsed.map { abs($0.savedAt.timeIntervalSince1970 - 1_700_000_000.123) < 0.001 } == true,
               "version names read back")
        expect(EaselHistory.parse("v-1-2.json.tmp") == nil && EaselHistory.parse("../v-1-2.json") == nil, "stray files are ignored")
        expect(EaselHistory.parse("v--1-2.json") == nil && EaselHistory.parse("v-x-2.json") == nil, "malformed names are ignored")
    }

    @MainActor static func historyPolicy() {
        var policy = EaselHistoryPolicy()
        policy.maximumVersions = 3
        policy.maximumBytes = 250
        let versions = (0..<5).map { (version: EaselVersion(id: "v\($0)", savedAt: Date(timeIntervalSince1970: Double($0)), itemCount: 0), bytes: 100) }
        expect(Set(policy.expired(versions).map(\.id)) == ["v0", "v1", "v2"], "only the newest versions that fit the caps stay")
        let huge = [(version: EaselVersion(id: "big", savedAt: Date(), itemCount: 0), bytes: 10_000)]
        expect(policy.expired(huge).isEmpty, "the newest version stays even when it alone passes the size cap")
        let start = Date(timeIntervalSinceReferenceDate: 0)
        expect(policy.shouldRecord(lastRecordedAt: nil, now: start), "the first change always records")
        expect(!policy.shouldRecord(lastRecordedAt: start, now: start.addingTimeInterval(299)), "changes within five minutes share a snapshot")
        expect(policy.shouldRecord(lastRecordedAt: start, now: start.addingTimeInterval(300)), "five minutes later a new snapshot is due")
    }

    @MainActor static func historyRecording() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-easel-history-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = Clock()
        do {
            let store = try EaselStore(directory: root, now: { clock.now })
            EaselHistories.attach(to: store)
            let session = try store.create(title: "Board")
            let id = session.document.id
            guard let history = EaselHistories.history(for: id) else { return expect(false, "attached stores keep a history") }
            try session.perform("Add") { $0.items.append(item(.sticky, "one", x: 0, y: 0)) }
            clock.now.addTimeInterval(60)
            try session.perform("Edit") { $0.items[0].text = "two" }
            var versions = history.versions(of: id)
            expect(versions.count == 1 && versions.first?.itemCount == 0, "the first change keeps the Easel as it was when opened")
            clock.now.addTimeInterval(400)
            try session.perform("Add more") { $0.items.append(item(.text, "three", x: 0, y: 300)) }
            versions = history.versions(of: id)
            expect(versions.count == 2 && versions.first?.itemCount == 2, "five minutes on, the current state is kept too")
            let oldest = try history.document(versions[versions.count - 1], of: id)
            expect(oldest.items.isEmpty && oldest.id == id, "versions load back as whole documents")
            expect(!history.record(session.document, savedAt: clock.now, wait: true), "identical content is never stored twice")
            try store.delete(id)
            expect(history.versions(of: id).isEmpty, "deleting an Easel deletes its history")
        } catch {
            expect(false, "history recording failed: \(error)")
        }
    }

    @MainActor static func countdown() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = EaselCountdown()
        expect(timer.phase == .idle && timer.remaining(at: start) == 300, "a new timer offers five minutes")
        timer.adjust(minutes: 1, at: start)
        timer.adjust(minutes: 5, at: start)
        expect(timer.duration == 660, "up and Shift-up add one and five minutes")
        timer.adjust(minutes: -20, at: start)
        expect(timer.duration == 0, "the timer never goes below zero")
        timer.set(minutes: 120)
        expect(timer.duration == EaselCountdown.maximum && EaselCountdown.label(timer.duration) == "99:59", "the timer tops out at 99:59")
        timer.adjust(minutes: -1, at: start)
        expect(timer.duration == 99 * 60, "stepping down from 99:59 lands on the whole minute below")
        timer.set(minutes: 3)
        timer.start(at: start)
        expect(timer.phase == .running && timer.remaining(at: start.addingTimeInterval(61)) == 119, "a running timer counts down")
        timer.adjust(minutes: -1, at: start.addingTimeInterval(61))
        expect(timer.remaining(at: start.addingTimeInterval(61)) == 119, "a running timer can't be shortened")
        timer.addMinute(at: start.addingTimeInterval(61))
        expect(timer.remaining(at: start.addingTimeInterval(61)) == 179, "+1 min adds a minute while running")
        timer.pause(at: start.addingTimeInterval(91))
        expect(timer.phase == .paused && timer.remaining(at: start.addingTimeInterval(500)) == 149, "pausing freezes the time left")
        timer.addMinute(at: start.addingTimeInterval(500))
        expect(timer.remaining(at: start.addingTimeInterval(500)) == 209, "+1 min works while paused")
        timer.toggle(at: start.addingTimeInterval(600))
        expect(timer.phase == .running && timer.remaining(at: start.addingTimeInterval(700)) == 109, "resuming carries on from the pause")
        expect(!timer.isDue(at: start.addingTimeInterval(808)) && timer.isDue(at: start.addingTimeInterval(809)), "the timer is due right at zero")
        timer.finish()
        expect(timer.phase == .finished && timer.remaining(at: start) == 0, "a finished timer reads zero")
        timer.start(at: start.addingTimeInterval(900))
        expect(timer.phase == .running && timer.remaining(at: start.addingTimeInterval(900)) == 180, "starting again runs the same length")
        timer.reset()
        expect(timer.phase == .idle && timer.remaining(at: start) == 180, "reset goes back to the set length")
        expect(EaselCountdown.label(65.2) == "01:06" && EaselCountdown.label(0) == "00:00", "labels round up to whole seconds")
        expect(EaselCountdown.spoken(65) == "1 minute 5 seconds" && EaselCountdown.spoken(120) == "2 minutes", "VoiceOver hears plain words")
        var empty = EaselCountdown()
        empty.set(minutes: 0)
        empty.start(at: start)
        expect(empty.phase == .idle, "a zero timer doesn't start")
    }

    @MainActor static func objectLinks() {
        let easel = UUID(), object = UUID()
        let link = EaselObjectAddress.urlString(easel: easel, object: object)
        expect(link == "parc://easel/" + easel.uuidString.lowercased() + "#" + object.uuidString.lowercased(), "object links are the Easel link plus the object id")
        expect(EaselObjectAddress.target(of: link)?.easel == easel && EaselObjectAddress.target(of: link)?.object == object, "object links round trip")
        expect(InternalPage(urlString: link) == .easel(easel), "an object link still opens its Easel")
        expect(InternalPage(urlString: link)?.urlString == InternalPage.easel(easel).urlString, "tabs keep the plain Easel address")
        expect(InternalPage(urlString: "parc://easel/" + easel.uuidString + "#heading") == nil, "other fragments aren't Easel links")
        expect(InternalPage(urlString: "parc://easel/" + easel.uuidString + "?x=1#" + object.uuidString) == nil, "queries still aren't Easel links")
        expect(EaselObjectAddress.target(of: InternalPage.easel(easel).urlString) == nil, "a plain Easel link names no object")
    }

    @MainActor static func selectionExport() {
        let section = item(.section, "Ideas", x: 0, y: 0, width: 600, height: 400)
        let inside = item(.sticky, "inside", x: 40, y: 40)
        let outside = item(.sticky, "outside", x: 900, y: 40)
        var arrow = item(.arrow, "", x: 240, y: 90, width: 660, height: 1)
        arrow.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 660, y: 0)]
        arrow.startConnection = EaselConnection(itemID: inside.id)
        arrow.endConnection = EaselConnection(itemID: outside.id)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [section, inside, outside, arrow])
        let scope = EaselSelectionExport.scope([section.id], in: board)
        expect(scope == [section.id, inside.id], "exporting a section brings its contents along")
        expect(EaselSelectionExport.scope([UUID()], in: board).isEmpty, "a vanished selection exports nothing")
        let subset = EaselSelectionExport.document(board, keeping: [inside.id, arrow.id])
        expect(subset.items.map(\.id) == [inside.id, arrow.id], "the export keeps only the chosen objects")
        expect(subset.items.last?.endConnection == nil && subset.items.last?.startConnection?.itemID == inside.id,
               "connectors let go of objects left out of the export")
        var hidden = section
        hidden.contentsHidden = true
        let tucked = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [hidden, inside, outside])
        expect(EaselSelectionExport.scope([hidden.id], in: tucked) == [hidden.id], "hidden section contents stay out, as on the canvas")
        expect(EaselSelectionExport.stickies(in: tucked).map(\.id) == [outside.id], "hidden stickies stay out of the CSV")
    }

    @MainActor static func stickyCSV() {
        let first = item(.sticky, "Plain", x: 300, y: 0)
        let second = item(.sticky, "Says \"hi\", twice\nand more", x: 0, y: 0)
        let third = item(.sticky, "Below", x: 0, y: 400)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(),
                                  items: [third, first, item(.text, "not a sticky", x: 0, y: 200), second])
        let stickies = EaselSelectionExport.stickies(in: board)
        expect(stickies.map(\.id) == [second.id, first.id, third.id], "stickies export in reading order")
        expect(EaselSelectionExport.stickies(in: board, within: [first.id]).map(\.id) == [first.id], "a selection exports only its stickies")
        let csv = EaselSelectionExport.stickyCSV(stickies)
        expect(csv == "Content\r\n\"Says \"\"hi\"\", twice\nand more\"\r\nPlain\r\nBelow\r\n", "the CSV has a Content column with quoted fields")
        expect(EaselSelectionExport.stickyCSV([]) == "Content\r\n", "no stickies still makes a valid CSV")
        let risky = ["=1+1", "+5", "-2", "@SUM(A1)", "\tgo", "\rgo"].map { item(.sticky, $0, x: 0, y: 0) }
        let safe = EaselSelectionExport.stickyCSV(risky)
        expect(safe == "Content\r\n\"'=1+1\"\r\n\"'+5\"\r\n\"'-2\"\r\n\"'@SUM(A1)\"\r\n\"'\tgo\"\r\n\"'\rgo\"\r\n", "formula starters are defused with a quoted apostrophe")
        expect(EaselSelectionExport.stickyCSV([item(.sticky, "", x: 0, y: 0)]) == "Content\r\n\"\"\r\n", "an empty sticky stays a row")
        expect(EaselSelectionExport.stickyCSV([item(.sticky, "a=b", x: 0, y: 0)]) == "Content\r\na=b\r\n", "an equals sign inside text is left alone")
        expect(EaselTableData.field("=1", separator: ",") == "=1", "table copy keeps its own field rules")
    }

    @MainActor static func templates() {
        expect((6...8).contains(EaselTemplate.allCases.count), "the gallery offers six to eight templates")
        for template in EaselTemplate.allCases {
            let base = EaselTemplates.drawing(template)
            expect(!base.items.isEmpty && Set(base.items.map(\.id)).count == base.items.count, "\(template.title) has unique objects")
            let ids = Set(base.items.map(\.id))
            for connector in base.items where connector.kind == .arrow {
                expect([connector.startConnection?.itemID, connector.endConnection?.itemID].allSatisfy { $0.map(ids.contains) == true },
                       "\(template.title) connectors join objects in the template")
            }
            for section in base.items where section.kind == .section {
                expect(!EaselBoardObjects.contents(of: section, in: base.items).isEmpty || template == .moodboard,
                       "\(template.title) sections hold their stickies")
            }
            let visible = EaselRect(x: 2000, y: 3000, width: 1400, height: 900)
            let placed = EaselTemplates.placed(template, centeredAt: EaselPoint(x: 2700, y: 3450), within: visible, firstZIndex: 10)
            expect(placed.items.count == base.items.count && placed.items.map(\.zIndex) == Array(10..<(10 + base.items.count)),
                   "\(template.title) lands above everything in its own order")
            expect(placed.bounds.x >= visible.x && placed.bounds.y >= visible.y, "\(template.title) lands in view")
            let corner = EaselTemplates.placed(template, centeredAt: EaselPoint(x: 0, y: 0), firstZIndex: 0)
            expect(corner.bounds.x >= EaselTemplates.margin.x && corner.bounds.y >= EaselTemplates.margin.y, "\(template.title) never lands off the board")
            let document = EaselDocument(id: UUID(), title: template.title, createdAt: Date(), modifiedAt: Date(), items: placed.items)
            do { _ = try EaselSession(inMemory: document, assets: [:]) }
            catch { expect(false, "\(template.title) makes a valid Easel: \(error)") }
        }
    }
}
