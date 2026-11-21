import Foundation

@main
struct EaselTextSizingTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    static func expectThrows(_ message: String, _ body: () throws -> Void) {
        do { try body(); failTest("Expected a refusal: \(message)") } catch {}
    }

    @MainActor static func main() {
        savedFields()
        validation()
        autoWidthRules()
        alignmentRules()
        handles()
        scaling()
        sizeControls()
        print("EaselTextSizingTests passed")
    }

    static func text(_ frame: EaselRect = EaselRect(x: 100, y: 100, width: 200, height: 28),
                     style: EaselTextStyle? = nil, kind: EaselItemKind = .text) -> EaselItem {
        var item = EaselItem(kind: kind, frame: frame, text: "Hello")
        item.textStyle = style
        return item
    }

    static func paragraph(indent: Double) -> EaselRichText.Paragraph {
        EaselRichText.Paragraph(alignment: 4, direction: -1, lineBreak: 0, firstIndent: 0, headIndent: indent, tailIndent: 0,
                                lineSpacing: 0, before: 4, after: 8, minimumHeight: 0, maximumHeight: 0, heightMultiple: 1.25,
                                hyphenation: 0, tightening: 0, allowsTightening: false, defaultHyphenation: false, defaultTab: 0,
                                tabs: [.init(alignment: 2, location: 16), .init(alignment: 0, location: indent)],
                                lists: [.init(marker: "{disc}", options: 0, start: 1)])
    }

    static func savedFields() {
        do {
            let plain = String(decoding: try JSONEncoder().encode(EaselTextStyle()), as: UTF8.self)
            expect(!plain.contains("customSize") && !plain.contains("autoWidth"), "Unused sizing fields stay out of saved bytes")
            let sized = EaselTextStyle(family: .mono, size: .h2, customSize: 36, autoWidth: true)
            let decoded = try JSONDecoder().decode(EaselTextStyle.self, from: JSONEncoder().encode(sized))
            expect(decoded == sized, "Custom size and auto width survive a save")
            let legacy = try JSONDecoder().decode(EaselTextStyle.self, from: Data(#"{"family":"mono","size":"h2"}"#.utf8))
            expect(legacy == EaselTextStyle(family: .mono, size: .h2), "Older text styles open unchanged")
            expect(legacy.customSize == nil && legacy.autoWidth == nil, "Older text stays fixed-width at its preset size")
            expect(legacy.pointSize == 24 && legacy.presetPointSize == 24, "Preset sizes are unchanged")
            expect(sized.pointSize == 36 && sized.presetPointSize == 24, "A custom size overrides the preset's point size")
        } catch { failTest("Text style coding failed: \(error)") }
    }

    @MainActor static func validation() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("easel-text-sizing-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let session = try EaselStore(directory: directory).create()
            let good = text(style: EaselTextStyle(customSize: 8, autoWidth: true))
            try session.perform("Add text") { $0.items.append(good) }
            let largest = text(style: EaselTextStyle(customSize: 400))
            try session.perform("Add text") { $0.items.append(largest) }
            for size in [7.99, 400.5, Double.nan, Double.infinity, -12] {
                expectThrows("custom size \(size)") {
                    try session.perform("Add text") { $0.items.append(text(style: EaselTextStyle(customSize: size))) }
                }
            }
            for kind in [EaselItemKind.sticky, .rectangle, .circle] {
                expectThrows("auto width on \(kind.rawValue)") {
                    try session.perform("Add") { $0.items.append(text(style: EaselTextStyle(autoWidth: true), kind: kind)) }
                }
            }
            try session.perform("Add sticky") { $0.items.append(text(style: EaselTextStyle(customSize: 30), kind: .sticky)) }
            expect(session.document.items.count == 3, "Valid sizing fields save and invalid ones are refused whole")
        } catch { failTest("Text sizing validation failed: \(error)") }
    }

    static func autoWidthRules() {
        expect(EaselTextSizing.maximumAutoWidth(pointSize: 15) == 560, "Body text widens to a comfortable 560 points before wrapping")
        expect(EaselTextSizing.maximumAutoWidth(pointSize: 24) == 864, "Larger text gets a proportionally wider limit")
        expect(EaselTextSizing.maximumAutoWidth(pointSize: 400) == 4000, "The widest auto text stops at 4000 points")
        expect(EaselTextSizing.maximumAutoWidth(pointSize: .nan) == 560, "A broken size falls back to the body limit")
        expect(EaselTextSizing.autoWidth(natural: 100.2, pointSize: 15) == 101, "Auto width rounds up so text never wraps early")
        expect(EaselTextSizing.autoWidth(natural: 3, pointSize: 15) == EaselTextSizing.minimumWidth, "Empty text keeps room for the caret")
        expect(EaselTextSizing.autoWidth(natural: 10_000, pointSize: 15) == 560, "Long lines wrap at the limit")
        expect(EaselTextSizing.autoWidth(natural: .infinity, pointSize: 15) == EaselTextSizing.minimumWidth, "Broken measurements stay safe")

        let style = EaselTextStyle(autoWidth: true)
        let point = text(style: style)
        expect(EaselTextSizing.isAutoWidth(point), "Point text is auto width")
        expect(!EaselTextSizing.isAutoWidth(text()), "Existing text is fixed-width area text")
        expect(!EaselTextSizing.isAutoWidth(text(style: style, kind: .sticky)), "Only text objects can be auto width")
        let wider = EaselTextSizing.fittedFrame(point, naturalWidth: 300) { width in width == 300 ? 40 : 0 }
        expect(wider == EaselRect(x: 100, y: 100, width: 300, height: 40), "Left-aligned point text grows to the right and hugs its height")
        var centered = point; centered.textStyle?.alignment = .center
        let grown = EaselTextSizing.fittedFrame(centered, naturalWidth: 300) { _ in 28 }
        expect(grown.x == 50 && grown.width == 300, "Centred point text grows from its middle")
        var right = point; right.textStyle?.alignment = .right
        let shrunk = EaselTextSizing.fittedFrame(right, naturalWidth: 100) { _ in 28 }
        expect(shrunk.x == 200 && shrunk.width == 100, "Right-aligned point text keeps its right edge")
        var edge = right; edge.frame.x = 0
        expect(EaselTextSizing.fittedFrame(edge, naturalWidth: 500) { _ in 28 }.x == 0, "Growing text never leaves the canvas")
        let area = EaselTextSizing.fittedFrame(text(), naturalWidth: 900) { width in width == 200 ? 60 : 0 }
        expect(area == EaselRect(x: 100, y: 100, width: 200, height: 60), "Area text keeps its width and grows taller")
        let tall = EaselTextSizing.fittedFrame(text(EaselRect(x: 0, y: 0, width: 200, height: 90)), naturalWidth: 50) { _ in 28 }
        expect(tall.height == 90, "Area text keeps a taller box while typing")

        guard let auto = EaselTextSizing.autoWidthFrame(text(), naturalWidth: 120, height: { _ in 28 }) else {
            failTest("Double-clicking a side handle returns area text to auto width")
        }
        expect(auto.textStyle?.autoWidth == true && auto.frame.width == 120, "Auto width fits the text again")
        expect(EaselTextSizing.autoWidthFrame(point, naturalWidth: 120, height: { _ in 28 }) == nil, "Auto width text is already auto")
        var locked = text(); locked.locked = true
        expect(EaselTextSizing.autoWidthFrame(locked, naturalWidth: 120, height: { _ in 28 }) == nil, "Locked text keeps its width")
        expect(EaselTextSizing.autoWidthFrame(text(kind: .sticky), naturalWidth: 120, height: { _ in 28 }) == nil, "Stickies have no auto width")

        var dragged = point; dragged.frame.width = 90
        let resized = EaselTextSizing.widthResized(dragged) { width in width == 90 ? 84 : 0 }
        expect(resized.textStyle?.autoWidth == nil && resized.frame.height == 84, "Side-dragging point text makes wrapping area text")
        let shape = text(kind: .rectangle)
        expect(EaselTextSizing.widthResized(shape) { _ in 1 } == shape, "Side drags leave shapes alone")
    }

    static func alignmentRules() {
        expect(EaselTextSizing.defaultAlignment(for: .rectangle) == .center && EaselTextSizing.defaultAlignment(for: .circle) == .center,
               "Shapes centre their text")
        expect(EaselTextSizing.defaultAlignment(for: .text) == .left && EaselTextSizing.defaultAlignment(for: .sticky) == .left,
               "Text and stickies start on the left")
        expect(EaselTextSizing.resolvedAlignment(text()) == .left, "Text without a choice reads as left-aligned")
        expect(EaselTextSizing.resolvedAlignment(text(style: EaselTextStyle(alignment: .right))) == .right, "Chosen alignment wins")
        expect(EaselTextSizing.resolvedAlignment(text(kind: .rectangle)) == .center, "Shape text is centred by default")
        expect(EaselTextSizing.resolvedAlignment(text(style: EaselTextStyle(alignment: .left), kind: .rectangle)) == .left, "Shape text can align left")

        let shape = text(kind: .rectangle), plain = text()
        var locked = text(); locked.locked = true
        let image = text(kind: .image)
        let document = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [plain, shape, locked, image])
        let ids = Set(document.items.map(\.id))
        guard let aligned = EaselTextSizing.aligning(document, ids: ids, to: .right) else { failTest("Aligning text changes the board") }
        expect(aligned.items[0].textStyle?.alignment == .right && aligned.items[1].textStyle?.alignment == .right, "Text and shapes align")
        expect(aligned.items[2].textStyle == nil && aligned.items[3].textStyle == nil, "Locked objects and images are left alone")
        expect(EaselTextSizing.aligning(aligned, ids: ids, to: .right) == nil, "Aligning again changes nothing")
        expect(EaselTextSizing.sharedAlignment(Array(aligned.items.prefix(2))) == .right, "A uniform selection reports its alignment")
        expect(EaselTextSizing.sharedAlignment(document.items) == nil, "A mixed selection reports no single alignment")
        expect(EaselTextSizing.canAlign([plain]) && !EaselTextSizing.canAlign([locked, image]), "Alignment needs unlocked text")
        expect(EaselTextStyle.Alignment.allCases.map(\.shortcut) == ["⌥⌘L", "⌥⌘T", "⌥⌘R"], "Alignment shortcuts read left, centre, right")
        let chords: [(String, UInt16, EaselTextStyle.Alignment)] = [("l", 37, .left), ("t", 17, .center), ("r", 15, .right)]
        for (letter, code, alignment) in chords {
            expect(EaselChords.command(characters: letter, keyCode: code, modifiers: [.command, .option]) == .alignText(alignment),
                   "⌥⌘\(letter.uppercased()) aligns text")
            expect(EaselChords.command(characters: letter, keyCode: code, modifiers: [.command]) != .alignText(alignment),
                   "⌘\(letter.uppercased()) alone never aligns text")
        }
        expect(EaselChords.reserved.allSatisfy { EaselChords.table[$0] == nil }, "Alignment chords stay clear of Parc's reserved chords")
    }

    static func handles() {
        let frame = EaselRect(x: 0, y: 0, width: 200, height: 28)
        let texts = [text(frame)]
        for handle in [EaselResizeHandle.top, .bottom] {
            expect(EaselTextSizing.handleRect(handle, in: frame, items: texts) == nil, "Text has no top or bottom handle")
        }
        for handle in [EaselResizeHandle.left, .right] {
            guard let rect = EaselTextSizing.handleRect(handle, in: frame, items: texts) else { failTest("Short text still has side handles") }
            expect(rect.height >= 8 && rect.y + rect.height / 2 == 14, "Side handles sit on the middle of the edge")
        }
        expect(EaselTextSizing.handleOrder(for: texts).prefix(2) == [.left, .right], "Side handles win over corners on short text")
        let tall = EaselRect(x: 0, y: 0, width: 200, height: 100)
        expect(EaselTextSizing.handleRect(.left, in: tall, items: texts) == EaselRect(x: -5, y: 10, width: 10, height: 80),
               "Tall text's side handle runs between the corners")
        let mixed = [text(frame), text(frame, kind: .rectangle)]
        for handle in EaselResizeHandle.allCases {
            expect(EaselTextSizing.handleRect(handle, in: tall, items: mixed) == handle.hitRect(in: tall), "Mixed selections keep every handle")
        }
        expect(EaselTextSizing.handleOrder(for: mixed) == EaselResizeHandle.allCases, "Mixed selections keep the usual handle order")
        expect(EaselTextSizing.sideHandlePoints(in: tall, items: texts) == [EaselPoint(x: 0, y: 50), EaselPoint(x: 200, y: 50)],
               "Text shows its width handles at the middle of each side")
        expect(EaselTextSizing.sideHandlePoints(in: tall, items: mixed).isEmpty, "Other selections draw no width handles")
        expect(EaselTextSizing.scalesText(texts, handle: .bottomRight) && !EaselTextSizing.scalesText(texts, handle: .right),
               "Corners scale text and sides set its width")
        expect(!EaselTextSizing.scalesText(mixed, handle: .topLeft), "Mixed selections resize instead of scaling text")
    }

    static func scaling() {
        expect(EaselTextSizing.scaledSize(base: 15, factor: 1.6) == 24, "Scaling snaps to whole points")
        expect(EaselTextSizing.scaledSize(base: 15, factor: 0.1) == 8, "Scaling stops at 8 points")
        expect(EaselTextSizing.scaledSize(base: 80, factor: 9) == 400, "Scaling stops at 400 points")
        expect(EaselTextSizing.scaledSize(base: 15, factor: .nan) == nil && EaselTextSizing.scaledSize(base: 0, factor: 2) == nil,
               "Broken scales are refused")

        var item = text(EaselRect(x: 10, y: 20, width: 200, height: 40))
        let font = EaselRichText.Font(name: ".AppleSystemUIFont", size: 15, style: EaselTextStyle())
        let heading = EaselRichText.Font(name: ".AppleSystemUIFont", size: 32)
        item.text = "Hi\nYo"
        item.richText = EaselRichText(runs: [
            .init(location: 0, length: 3, attributes: .init(font: font, ink: "#252525FF", kern: 1, paragraph: paragraph(indent: 24))),
            .init(location: 3, length: 2, attributes: .init(font: heading, ink: "#252525FF")),
        ])
        guard let doubled = EaselTextSizing.scaled(item, factor: 2), let runs = doubled.richText?.runs else {
            failTest("Corner-dragging text scales it")
        }
        expect(doubled.textStyle?.customSize == 30 && doubled.resolvedTextStyle.pointSize == 30, "The object's size doubles")
        expect(runs[0].attributes.font.size == 30 && runs[1].attributes.font.size == 64, "Every run keeps its proportion")
        expect(runs[0].attributes.font.style == nil, "Scaled runs drop their old preset label")
        expect(runs[0].attributes.kern == 2, "Letter spacing scales too")
        expect(runs[0].attributes.paragraph?.headIndent == 48 && runs[0].attributes.paragraph?.tabs.last?.location == 48,
               "List indents scale with the text")
        expect(doubled.frame == EaselRect(x: 10, y: 20, width: 400, height: 80), "The box scales with the text")
        do { try doubled.richText?.validate(text: doubled.text) } catch { failTest("Scaled rich text stays valid: \(error)") }
        expect(EaselTextSizing.scaled(item, factor: 1) == item, "No scale changes nothing")
        guard let back = EaselTextSizing.scaled(doubled, factor: 0.5) else { failTest("Text scales back down") }
        expect(back.textStyle?.customSize == nil, "Landing on the preset size clears the custom size")
        expect(EaselTextSizing.scaled(text(kind: .sticky), factor: 2) == nil, "Stickies scale their own way")

        let original = EaselRect(x: 100, y: 100, width: 200, height: 40)
        var grown = text(original); grown.frame.width = 300
        let measure: (Double) -> Double = { _ in 60 }
        let bottomRight = EaselTextSizing.scaledFrame(grown, original: original, proposed: original, handle: .bottomRight,
                                                      centered: false, single: true, naturalWidth: 0, height: measure)
        expect(bottomRight == EaselRect(x: 100, y: 100, width: 300, height: 60), "Dragging the bottom-right corner keeps the top-left")
        let topLeft = EaselTextSizing.scaledFrame(grown, original: original, proposed: original, handle: .topLeft,
                                                  centered: false, single: true, naturalWidth: 0, height: measure)
        expect(topLeft == EaselRect(x: 0, y: 80, width: 300, height: 60), "Dragging the top-left corner keeps the bottom-right")
        let centered = EaselTextSizing.scaledFrame(grown, original: original, proposed: original, handle: .topRight,
                                                   centered: true, single: true, naturalWidth: 0, height: measure)
        expect(centered == EaselRect(x: 50, y: 90, width: 300, height: 60), "Option-dragging keeps the centre")
        var point = grown; point.textStyle = EaselTextStyle(autoWidth: true)
        let auto = EaselTextSizing.scaledFrame(point, original: original, proposed: original, handle: .bottomRight,
                                               centered: false, single: true, naturalWidth: 250, height: measure)
        expect(auto.width == 250, "Scaled point text still fits its words")
        let group = EaselTextSizing.scaledFrame(grown, original: original, proposed: EaselRect(x: 7, y: 9, width: 1, height: 1),
                                                handle: .bottomRight, centered: false, single: false, naturalWidth: 0, height: measure)
        expect(group == EaselRect(x: 7, y: 9, width: 300, height: 60), "Several texts follow the group's corner")

        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [item, text(kind: .rectangle)])
        var shape = board.items[1]; shape.frame.width = 999
        let merged = EaselTextSizing.merging([doubled, shape], into: board)
        expect(merged.items[0] == doubled && merged.items[1] == board.items[1], "Only text changes are merged")
        expect(EaselTextSizing.sizeLabel(for: EaselTextStyle()) == "Body · 15", "Preset sizes are named")
        expect(EaselTextSizing.sizeLabel(for: EaselTextStyle(customSize: 36)) == "36 pt", "Custom sizes show their points")
    }

    static func sizeControls() {
        let custom = EaselTextStyle(customSize: 36)
        expect(EaselTextSizing.stepped(custom, by: 1) == EaselTextStyle(size: .h1), "Bigger jumps from a custom size to the next preset")
        expect(EaselTextSizing.stepped(custom, by: -1) == EaselTextStyle(size: .h2), "Smaller jumps to the preset below")
        expect(EaselTextSizing.stepped(EaselTextStyle(customSize: 400), by: 1) == nil, "Nothing is bigger than the largest custom size")
        expect(EaselTextSizing.stepped(EaselTextStyle(), by: -1) == nil, "Body text is the smallest preset")
        expect(EaselTextSizing.stepped(EaselTextStyle(), by: 1) == EaselTextStyle(size: .h2), "Presets still step one at a time")
        expect(EaselTextSizing.customSized(EaselTextStyle(), points: 3)?.customSize == 8, "Custom sizes start at 8 points")
        expect(EaselTextSizing.customSized(EaselTextStyle(), points: 999)?.customSize == 400, "Custom sizes stop at 400 points")
        expect(EaselTextSizing.customSized(EaselTextStyle(), points: 36.4)?.customSize == 36, "Custom sizes are whole points")
        expect(EaselTextSizing.customSized(EaselTextStyle(), points: 15)?.customSize == nil, "Typing the preset size keeps the preset")
        expect(EaselTextSizing.customSized(EaselTextStyle(), points: .nan) == nil, "A broken size is refused")
        expect(EaselTextSizing.preset(custom, size: .h0) == EaselTextStyle(size: .h0), "Picking a preset clears the custom size")
        expect(EaselTextStyle.Size.allCases.map(\.title) == ["Body", "Heading 2", "Heading 1", "Title", "Display"], "Size names match the menu")
    }
}
