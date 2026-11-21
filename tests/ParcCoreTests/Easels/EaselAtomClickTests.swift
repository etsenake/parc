import Foundation
import Testing
@testable import ParcCore

struct EaselAtomClickTests {
    struct Click: CustomTestStringConvertible, Sendable {
        let name: String
        let selected: Bool
        let extra: Bool
        let editable: Bool
        let clicks: Int
        let plain: Bool
        var testDescription: String { name }
    }

    private static let equation = EaselRichText.Inline(kind: .equation, tex: "x^2")
    private static let date = EaselRichText.Inline(kind: .date, start: .init(year: 2026, month: 11, day: 21))
    private static let mention = EaselRichText.Inline(kind: .note, target: "parc://easel/" + UUID().uuidString, title: "Board")

    private static func attributes(_ inline: EaselRichText.Inline? = nil) -> EaselRichText.Attributes {
        EaselRichText.Attributes(font: .init(name: "Helvetica", size: 15), ink: "#252525FF", inline: inline)
    }

    private static func item(kind: EaselItemKind = .text, inline: EaselRichText.Inline?, locked: Bool? = nil,
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

    private static func opens(_ item: EaselItem) -> Bool {
        EaselAtomClick.allowsClick(on: item, selection: [item.id], editable: true, clickCount: 1, plain: true)
    }

    @Test func datesAndEquationsOpenOnClick() {
        #expect(EaselAtomClick.opens(.date))
        #expect(EaselAtomClick.opens(.equation))
    }

    @Test func mentionsAndEmojiKeepTheirOwnBehaviour() {
        #expect(!EaselAtomClick.opens(.note))
        #expect(!EaselAtomClick.opens(.emoji))
    }

    @Test(arguments: [equation, date])
    func aPlainSingleClickOnASelectedObjectsAtomOpensItsEditor(inline: EaselRichText.Inline) {
        #expect(Self.opens(Self.item(inline: inline)))
    }

    @Test(arguments: [
        Click(name: "an unselected object selects first", selected: false, extra: false, editable: true, clicks: 1, plain: true),
        Click(name: "a multiple selection keeps selecting", selected: true, extra: true, editable: true, clicks: 1, plain: true),
        Click(name: "read-only canvases never open the editor", selected: true, extra: false, editable: false, clicks: 1, plain: true),
        Click(name: "a double click keeps editing the text", selected: true, extra: false, editable: true, clicks: 2, plain: true),
        Click(name: "modified clicks keep selecting", selected: true, extra: false, editable: true, clicks: 1, plain: false),
    ], [equation, date])
    func otherClicksOnAnAtomDoNotOpenItsEditor(click: Click, inline: EaselRichText.Inline) {
        let value = Self.item(inline: inline)
        var selection: Set<UUID> = click.selected ? [value.id] : []
        if click.extra { selection.insert(UUID()) }
        #expect(!EaselAtomClick.allowsClick(on: value, selection: selection, editable: click.editable,
                                            clickCount: click.clicks, plain: click.plain))
    }

    @Test func lockedObjectsStayReadOnly() {
        #expect(!Self.opens(Self.item(inline: Self.date, locked: true)))
    }

    @Test func rotatedObjectsAreSkippedLikeTheLinkCard() {
        #expect(!Self.opens(Self.item(inline: Self.date, rotation: 12)))
    }

    @Test func flippedObjectsAreSkippedLikeTheLinkCard() {
        #expect(!Self.opens(Self.item(inline: Self.equation, flipped: true)))
    }

    @Test func aMentionOnlyObjectHasNoAtomToOpen() {
        #expect(!Self.opens(Self.item(inline: Self.mention)))
    }

    @Test func plainTextHasNoAtomToOpen() {
        #expect(!Self.opens(Self.item(inline: nil)))
    }

    @Test(arguments: [EaselItemKind.arrow, .sticky, .rectangle])
    func textHoldingObjectsOpenTheirAtoms(kind: EaselItemKind) {
        #expect(Self.opens(Self.item(kind: kind, inline: Self.date)))
        #expect(Self.opens(Self.item(kind: kind, inline: Self.equation)))
    }

    @Test func objectsThatHoldNoTextAreNeverOpened() {
        #expect(!Self.opens(Self.item(kind: .image, inline: Self.date)))
    }
}
