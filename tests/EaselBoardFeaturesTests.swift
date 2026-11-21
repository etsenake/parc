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
        replacePlain()
        replaceRich()
        replaceRefusals()
        viewportFocus()
        print("EaselBoardFeaturesTests: \(assertions) assertions passed")
    }

    static func item(_ kind: EaselItemKind, _ text: String, x: Double, y: Double, width: Double = 200, height: Double = 100) -> EaselItem {
        EaselItem(kind: kind, frame: .init(x: x, y: y, width: width, height: height), text: text)
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Board", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    static func attributes(_ ink: String, bold: Bool = false) -> EaselRichText.Attributes {
        EaselRichText.Attributes(font: .init(name: "Helvetica", size: 15, traits: bold ? 2 : 0), ink: ink)
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
        expect(matches.count == 4, "stickies, connector labels and card titles match but images never do")
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

    @MainActor static func replacePlain() {
        let section = item(.section, "Ideas and ideas", x: 0, y: 0)
        let locked: EaselItem = {
            var value = item(.sticky, "ideas", x: 0, y: 300)
            value.locked = true
            return value
        }()
        let card = item(.link, "ideas.example", x: 300, y: 0)
        let board = document([section, locked, card])
        let matches = EaselFinder.matches(of: "ideas", in: board)
        expect(matches.count == 4, "locked objects and cards are still found")
        let outcome = EaselFinder.replace(matches, with: "Plans", in: board)
        expect(outcome.count == 2 && outcome.touched == [section.id], "Replace All skips locked objects and cards")
        expect(outcome.document.items.first { $0.id == section.id }?.text == "Plans and Plans", "every match in one object is replaced")
        expect(outcome.document.items.first { $0.id == locked.id }?.text == "ideas", "locked objects keep their text")
        let single = EaselFinder.replace([matches[1]], with: "x", in: board)
        expect(single.document.items.first { $0.id == section.id }?.text == "Ideas and x", "Replace changes only the current match")
        let same = EaselFinder.replace([matches[0]], with: "Ideas", in: board)
        expect(same.count == 0 && same.document == board, "replacing text with itself changes nothing")
    }

    @MainActor static func replaceRich() {
        var sticky = item(.sticky, "Hello world", x: 0, y: 0)
        sticky.richText = EaselRichText(runs: [
            .init(location: 0, length: 6, attributes: attributes("#000000FF")),
            .init(location: 6, length: 5, attributes: attributes("#FF0000FF", bold: true)),
        ])
        let board = document([sticky])
        let matches = EaselFinder.matches(of: "world", in: board)
        let outcome = EaselFinder.replace(matches, with: "everyone", in: board)
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
        var text = item(.text, "a\u{FFFC}b", x: 0, y: 0)
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13])
        var picture = attributes("#000000FF")
        picture.image = .init(data: png, fileType: "public.png", width: 10, height: 10)
        text.richText = EaselRichText(runs: [
            .init(location: 0, length: 1, attributes: attributes("#000000FF")),
            .init(location: 1, length: 1, attributes: picture),
            .init(location: 2, length: 1, attributes: attributes("#000000FF")),
        ])
        let match = EaselFindMatch(itemID: text.id, part: .text, range: 0..<3)
        let refused = EaselFinder.replace([match], with: "x", in: document([text]))
        expect(refused.count == 0, "a replacement never swallows an inline image")
        let outside = EaselFindMatch(itemID: text.id, part: .text, range: 0..<99)
        expect(EaselFinder.replace([outside], with: "x", in: document([text])).count == 0, "out-of-range matches are ignored")
        let overlapping = [EaselFindMatch(itemID: text.id, part: .text, range: 0..<1), EaselFindMatch(itemID: text.id, part: .text, range: 0..<1)]
        expect(EaselFinder.replace(overlapping, with: "z", in: document([text])).count == 1, "overlapping matches replace once")
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
}
