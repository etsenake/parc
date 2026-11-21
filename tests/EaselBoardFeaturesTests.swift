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
        sessionRefresh()
        sessionReplace()
        sessionReplaceAll()
        viewportFocus()
        objectLinks()
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
        expect(EaselFindSession.summary(odd) == "Skipped 2 couldn’t change", "unchangeable objects are reported too")
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
}
