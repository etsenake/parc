import Foundation

@main
struct EaselAtomClickTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    static func attributes(_ inline: EaselRichText.Inline? = nil) -> EaselRichText.Attributes {
        EaselRichText.Attributes(font: .init(name: "Helvetica", size: 15), ink: "#252525FF", inline: inline)
    }

    static func item(kind: EaselItemKind = .text, inline: EaselRichText.Inline?, locked: Bool? = nil,
                     rotation: Double? = nil, flipped: Bool? = nil) -> EaselItem {
        var value = EaselItem(kind: kind, frame: .init(x: 0, y: 0, width: 200, height: 80), text: "a\u{FFFC}b")
        value.richText = EaselRichText(runs: [
            .init(location: 0, length: 1, attributes: attributes()),
            .init(location: 1, length: 1, attributes: attributes(inline)),
            .init(location: 2, length: 1, attributes: attributes()),
        ])
        value.locked = locked
        value.rotation = rotation
        value.flipHorizontal = flipped
        return value
    }

    static let equation = EaselRichText.Inline(kind: .equation, tex: "x^2")
    static let date = EaselRichText.Inline(kind: .date, start: .init(year: 2026, month: 11, day: 21))
    static let mention = EaselRichText.Inline(kind: .note, target: "parc://easel/" + UUID().uuidString, title: "Board")

    @MainActor static func main() {
        exitOnFailure {
            expect(EaselAtomClick.opens(.date) && EaselAtomClick.opens(.equation), "dates and equations open on click")
            expect(!EaselAtomClick.opens(.note) && !EaselAtomClick.opens(.emoji), "mentions and emoji keep their own behaviour")

            let selected: (EaselItem) -> Set<UUID> = { [$0.id] }
            let open = { (item: EaselItem, selection: Set<UUID>, editable: Bool, clicks: Int, plain: Bool) in
                EaselAtomClick.allowsClick(on: item, selection: selection, editable: editable, clickCount: clicks, plain: plain)
            }
            for inline in [equation, date] {
                let value = item(inline: inline)
                expect(open(value, selected(value), true, 1, true), "a click on a selected object's atom opens its editor")
                expect(!open(value, [], true, 1, true), "an unselected object selects first")
                expect(!open(value, [value.id, UUID()], true, 1, true), "a multiple selection keeps selecting")
                expect(!open(value, selected(value), false, 1, true), "read-only canvases never open the editor")
                expect(!open(value, selected(value), true, 2, true), "a double click keeps editing the text")
                expect(!open(value, selected(value), true, 1, false), "modified clicks keep selecting")
            }

            let locked = item(inline: date, locked: true)
            expect(!open(locked, selected(locked), true, 1, true), "locked objects stay read-only")
            let turned = item(inline: date, rotation: 12)
            expect(!open(turned, selected(turned), true, 1, true), "rotated objects are skipped like the link card")
            let flipped = item(inline: equation, flipped: true)
            expect(!open(flipped, selected(flipped), true, 1, true), "flipped objects are skipped like the link card")
            let plain = item(inline: mention)
            expect(!open(plain, selected(plain), true, 1, true), "a mention-only object has no atom to open")
            let bare = item(inline: nil)
            expect(!open(bare, selected(bare), true, 1, true), "plain text has no atom to open")

            let connector = item(kind: .arrow, inline: date)
            expect(open(connector, selected(connector), true, 1, true), "connector labels open dates too")
            let sticky = item(kind: .sticky, inline: equation)
            expect(open(sticky, selected(sticky), true, 1, true), "stickies open equations")
            let shape = item(kind: .rectangle, inline: date)
            expect(open(shape, selected(shape), true, 1, true), "shapes open dates")
            let image = item(kind: .image, inline: date)
            expect(!open(image, selected(image), true, 1, true), "objects that hold no text are never opened")

            print("EaselAtomClickTests: \(assertions) assertions passed")
        }
    }
}
