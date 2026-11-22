import Foundation
import Testing
@testable import ParcCore

struct EaselTextSizingFormattingTests {
    @Test
    func scalingTextDoublesTheBoxAndRichTextMetrics() {
        var item = EaselTextSizingTestsSupport.text(EaselRect(x: 10, y: 20, width: 200, height: 40))
        let font = EaselRichText.Font(name: ".AppleSystemUIFont", size: 15, style: EaselTextStyle())
        let heading = EaselRichText.Font(name: ".AppleSystemUIFont", size: 32)
        item.text = "Hi\nYo"
        item.richText = EaselRichText(runs: [
            .init(location: 0, length: 3, attributes: .init(font: font, ink: "#252525FF", kern: 1, paragraph: EaselTextSizingTestsSupport.paragraph(indent: 24))),
            .init(location: 3, length: 2, attributes: .init(font: heading, ink: "#252525FF")),
        ])
        guard let doubled = EaselTextSizing.scaled(item, factor: 2), let runs = doubled.richText?.runs else {
            Issue.record("Corner-dragging text scales it")
            return
        }
        #expect(doubled.textStyle?.customSize == 30 && doubled.resolvedTextStyle.pointSize == 30, "The object's size doubles")
        #expect(runs[0].attributes.font.size == 30 && runs[1].attributes.font.size == 64, "Every run keeps its proportion")
        #expect(runs[0].attributes.font.style == nil, "Scaled runs drop their old preset label")
        #expect(runs[0].attributes.kern == 2, "Letter spacing scales too")
        #expect(runs[0].attributes.paragraph?.headIndent == 48 && runs[0].attributes.paragraph?.tabs.last?.location == 48, "List indents scale with the text")
        #expect(doubled.frame == EaselRect(x: 10, y: 20, width: 400, height: 80), "The box scales with the text")
        do { try doubled.richText?.validate(text: doubled.text) } catch { Issue.record("Scaled rich text stays valid: \(error)") }
    }

    @Test
    func aScaleOfOneLeavesTextUnchanged() {
        var item = EaselTextSizingTestsSupport.text(EaselRect(x: 10, y: 20, width: 200, height: 40))
        let font = EaselRichText.Font(name: ".AppleSystemUIFont", size: 15, style: EaselTextStyle())
        let heading = EaselRichText.Font(name: ".AppleSystemUIFont", size: 32)
        item.text = "Hi\nYo"
        item.richText = EaselRichText(runs: [
            .init(location: 0, length: 3, attributes: .init(font: font, ink: "#252525FF", kern: 1, paragraph: EaselTextSizingTestsSupport.paragraph(indent: 24))),
            .init(location: 3, length: 2, attributes: .init(font: heading, ink: "#252525FF")),
        ])
        #expect(EaselTextSizing.scaled(item, factor: 1) == item, "No scale changes nothing")
    }

    @Test
    func scalingBackToThePresetClearsTheCustomSize() throws {
        var item = EaselTextSizingTestsSupport.text(EaselRect(x: 10, y: 20, width: 200, height: 40))
        let font = EaselRichText.Font(name: ".AppleSystemUIFont", size: 15, style: EaselTextStyle())
        let heading = EaselRichText.Font(name: ".AppleSystemUIFont", size: 32)
        item.text = "Hi\nYo"
        item.richText = EaselRichText(runs: [
            .init(location: 0, length: 3, attributes: .init(font: font, ink: "#252525FF", kern: 1, paragraph: EaselTextSizingTestsSupport.paragraph(indent: 24))),
            .init(location: 3, length: 2, attributes: .init(font: heading, ink: "#252525FF")),
        ])
        guard let doubled = EaselTextSizing.scaled(item, factor: 2) else {
            Issue.record("Corner-dragging text scales it")
            return
        }
        let back = try #require(EaselTextSizing.scaled(doubled, factor: 0.5), "Text scales back down")
        #expect(back.textStyle?.customSize == nil, "Landing on the preset size clears the custom size")
    }

    @Test
    func textScalingDoesNotApplyToStickies() {
        #expect(EaselTextSizing.scaled(EaselTextSizingTestsSupport.text(kind: .sticky), factor: 2) == nil, "Stickies scale their own way")
    }

    @Test
    func fractionalScalingSnapsRunsToWholePoints() {
        var item = EaselTextSizingTestsSupport.text(EaselRect(x: 10, y: 20, width: 200, height: 40))
        let font = EaselRichText.Font(name: ".AppleSystemUIFont", size: 15, style: EaselTextStyle())
        let heading = EaselRichText.Font(name: ".AppleSystemUIFont", size: 32)
        item.text = "Hi\nYo"
        item.richText = EaselRichText(runs: [
            .init(location: 0, length: 3, attributes: .init(font: font, ink: "#252525FF", kern: 1, paragraph: EaselTextSizingTestsSupport.paragraph(indent: 24))),
            .init(location: 3, length: 2, attributes: .init(font: heading, ink: "#252525FF")),
        ])
        guard let odd = EaselTextSizing.scaled(item, factor: 1.37), let oddRuns = odd.richText?.runs else { Issue.record("Odd scales work"); return }
        #expect(odd.resolvedTextStyle.pointSize == 21 && oddRuns.allSatisfy { $0.attributes.font.size == $0.attributes.font.size.rounded() }, "Scaled runs land on whole points")
        #expect(oddRuns[1].attributes.font.size == 45, "Runs follow the snapped base size, 32 × 21⁄15 rounds to 45")
    }

    @Test
    func scaledRunsStopAtFourHundredPoints() throws {
        var item = EaselTextSizingTestsSupport.text(EaselRect(x: 10, y: 20, width: 200, height: 40))
        let font = EaselRichText.Font(name: ".AppleSystemUIFont", size: 15, style: EaselTextStyle())
        let heading = EaselRichText.Font(name: ".AppleSystemUIFont", size: 32)
        item.text = "Hi\nYo"
        item.richText = EaselRichText(runs: [
            .init(location: 0, length: 3, attributes: .init(font: font, ink: "#252525FF", kern: 1, paragraph: EaselTextSizingTestsSupport.paragraph(indent: 24))),
            .init(location: 3, length: 2, attributes: .init(font: heading, ink: "#252525FF")),
        ])
        var giant = item
        giant.richText?.runs[1].attributes.font.size = 300
        let capped = try #require(EaselTextSizing.scaled(giant, factor: 3)?.richText?.runs, "Big text scales")
        #expect(capped[1].attributes.font.size == 400, "No run grows past 400 points")
    }

    @Test
    func scaledRunsStayAtOrAboveEightPoints() throws {
        var item = EaselTextSizingTestsSupport.text(EaselRect(x: 10, y: 20, width: 200, height: 40))
        let font = EaselRichText.Font(name: ".AppleSystemUIFont", size: 15, style: EaselTextStyle())
        let heading = EaselRichText.Font(name: ".AppleSystemUIFont", size: 32)
        item.text = "Hi\nYo"
        item.richText = EaselRichText(runs: [
            .init(location: 0, length: 3, attributes: .init(font: font, ink: "#252525FF", kern: 1, paragraph: EaselTextSizingTestsSupport.paragraph(indent: 24))),
            .init(location: 3, length: 2, attributes: .init(font: heading, ink: "#252525FF")),
        ])
        var tiny = item
        tiny.textStyle = EaselTextStyle(customSize: 40)
        let shrunk = try #require(EaselTextSizing.scaled(tiny, factor: 0.25)?.richText?.runs, "Text scales down")
        #expect(shrunk[0].attributes.font.size == 8, "No run shrinks under 8 points")
    }

    @Test
    func aRunThatKeepsItsSizeKeepsItsPreset() throws {
        var item = EaselTextSizingTestsSupport.text(EaselRect(x: 10, y: 20, width: 200, height: 40))
        let font = EaselRichText.Font(name: ".AppleSystemUIFont", size: 15, style: EaselTextStyle())
        let heading = EaselRichText.Font(name: ".AppleSystemUIFont", size: 32)
        item.text = "Hi\nYo"
        item.richText = EaselRichText(runs: [
            .init(location: 0, length: 3, attributes: .init(font: font, ink: "#252525FF", kern: 1, paragraph: EaselTextSizingTestsSupport.paragraph(indent: 24))),
            .init(location: 3, length: 2, attributes: .init(font: heading, ink: "#252525FF")),
        ])
        let steady = try #require(EaselTextSizing.scaled(item, factor: 1.02)?.richText?.runs, "Tiny drags work")
        #expect(steady[0].attributes.font.style == EaselTextStyle() && steady[0].attributes.font.size == 15, "A run whose size doesn't change keeps its preset label")
    }

    @Test
    func aTextFrameFitsOnlyWithinTheBoard() {
        let limit = EaselRect(x: 0, y: 0, width: 400, height: 300)
        #expect(EaselTextSizing.fits(EaselRect(x: 0, y: 0, width: 400, height: 300), in: limit), "A frame the board's size fits")
        #expect(!EaselTextSizing.fits(EaselRect(x: 0, y: 0, width: 401, height: 10), in: limit), "A wider frame doesn't fit")
    }

    @Test
    func placingTextClampsItToTheBoard() {
        let limit = EaselRect(x: 0, y: 0, width: 400, height: 300)
        #expect(EaselTextSizing.placed(EaselRect(x: 350, y: -20, width: 100, height: 40), in: limit) == EaselRect(x: 300, y: 0, width: 100, height: 40), "Text slides back inside a fixed board")
        #expect(EaselTextSizing.placed(EaselRect(x: 50, y: 50, width: 500, height: 40), in: limit).x == 0, "Oversized text pins to the board's edge")
    }

    @Test
    func scalingFromACornerKeepsTheOppositeCorner() {
        let original = EaselRect(x: 100, y: 100, width: 200, height: 40)
        var grown = EaselTextSizingTestsSupport.text(original); grown.frame.width = 300
        let measure: (Double) -> Double = { _ in 60 }
        let bottomRight = EaselTextSizing.scaledFrame(grown, original: original, proposed: original, handle: .bottomRight,
                                                      centered: false, single: true, naturalWidth: 0, height: measure)
        #expect(bottomRight == EaselRect(x: 100, y: 100, width: 300, height: 60), "Dragging the bottom-right corner keeps the top-left")
        let topLeft = EaselTextSizing.scaledFrame(grown, original: original, proposed: original, handle: .topLeft,
                                                  centered: false, single: true, naturalWidth: 0, height: measure)
        #expect(topLeft == EaselRect(x: 0, y: 80, width: 300, height: 60), "Dragging the top-left corner keeps the bottom-right")
    }

    @Test
    func optionScalingKeepsTheCentre() {
        let original = EaselRect(x: 100, y: 100, width: 200, height: 40)
        var grown = EaselTextSizingTestsSupport.text(original); grown.frame.width = 300
        let measure: (Double) -> Double = { _ in 60 }
        let centered = EaselTextSizing.scaledFrame(grown, original: original, proposed: original, handle: .topRight,
                                                   centered: true, single: true, naturalWidth: 0, height: measure)
        #expect(centered == EaselRect(x: 50, y: 90, width: 300, height: 60), "Option-dragging keeps the centre")
    }

    @Test
    func scaledPointTextStillFitsItsWords() {
        let original = EaselRect(x: 100, y: 100, width: 200, height: 40)
        var grown = EaselTextSizingTestsSupport.text(original); grown.frame.width = 300
        let measure: (Double) -> Double = { _ in 60 }
        var point = grown; point.textStyle = EaselTextStyle(autoWidth: true)
        let auto = EaselTextSizing.scaledFrame(point, original: original, proposed: original, handle: .bottomRight,
                                               centered: false, single: true, naturalWidth: 250, height: measure)
        #expect(auto.width == 250, "Scaled point text still fits its words")
    }

    @Test
    func scaledTextInAGroupFollowsTheGroupCorner() {
        let original = EaselRect(x: 100, y: 100, width: 200, height: 40)
        var grown = EaselTextSizingTestsSupport.text(original); grown.frame.width = 300
        let measure: (Double) -> Double = { _ in 60 }
        let group = EaselTextSizing.scaledFrame(grown, original: original, proposed: EaselRect(x: 7, y: 9, width: 1, height: 1),
                                                handle: .bottomRight, centered: false, single: false, naturalWidth: 0, height: measure)
        #expect(group == EaselRect(x: 7, y: 9, width: 300, height: 60), "Several texts follow the group's corner")
    }

    @Test
    func mergingScaledTextLeavesShapesAlone() {
        var item = EaselTextSizingTestsSupport.text(EaselRect(x: 10, y: 20, width: 200, height: 40))
        let font = EaselRichText.Font(name: ".AppleSystemUIFont", size: 15, style: EaselTextStyle())
        let heading = EaselRichText.Font(name: ".AppleSystemUIFont", size: 32)
        item.text = "Hi\nYo"
        item.richText = EaselRichText(runs: [
            .init(location: 0, length: 3, attributes: .init(font: font, ink: "#252525FF", kern: 1, paragraph: EaselTextSizingTestsSupport.paragraph(indent: 24))),
            .init(location: 3, length: 2, attributes: .init(font: heading, ink: "#252525FF")),
        ])
        guard let doubled = EaselTextSizing.scaled(item, factor: 2) else {
            Issue.record("Corner-dragging text scales it")
            return
        }
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [item, EaselTextSizingTestsSupport.text(kind: .rectangle)])
        var shape = board.items[1]; shape.frame.width = 999
        let merged = EaselTextSizing.merging([doubled, shape], into: board)
        #expect(merged.items[0] == doubled && merged.items[1] == board.items[1], "Only text changes are merged")
    }

    @Test
    func sizeLabelsShowPresetNamesOrCustomPoints() {
        #expect(EaselTextSizing.sizeLabel(for: EaselTextStyle()) == "Body · 15", "Preset sizes are named")
        #expect(EaselTextSizing.sizeLabel(for: EaselTextStyle(customSize: 36)) == "36 pt", "Custom sizes show their points")
    }

    @Test func biggerJumpsFromACustomSizeToTheNext() {
        let custom = EaselTextStyle(customSize: 36)
        #expect(EaselTextSizing.stepped(custom, by: 1) == EaselTextStyle(size: .h1), "Bigger jumps from a custom size to the next preset")
        #expect(EaselTextSizing.stepped(custom, by: -1) == EaselTextStyle(size: .h2), "Smaller jumps to the preset below")
        #expect(EaselTextSizing.stepped(EaselTextStyle(customSize: 400), by: 1) == nil, "Nothing is bigger than the largest custom size")
        #expect(EaselTextSizing.stepped(EaselTextStyle(), by: -1) == nil, "Body text is the smallest preset")
        #expect(EaselTextSizing.stepped(EaselTextStyle(), by: 1) == EaselTextStyle(size: .h2), "Presets still step one at a time")
        #expect(EaselTextSizing.customSized(EaselTextStyle(), points: 3)?.customSize == 8, "Custom sizes start at 8 points")
        #expect(EaselTextSizing.customSized(EaselTextStyle(), points: 999)?.customSize == 400, "Custom sizes stop at 400 points")
        #expect(EaselTextSizing.customSized(EaselTextStyle(), points: 36.4)?.customSize == 36, "Custom sizes are whole points")
        #expect(EaselTextSizing.customSized(EaselTextStyle(), points: 15)?.customSize == nil, "Typing the preset size keeps the preset")
        #expect(EaselTextSizing.customSized(EaselTextStyle(), points: .nan) == nil, "A broken size is refused")
        #expect(EaselTextSizing.preset(custom, size: .h0) == EaselTextStyle(size: .h0), "Picking a preset clears the custom size")
        #expect(EaselTextStyle.Size.allCases.map(\.title) == ["Body", "Heading 2", "Heading 1", "Title", "Display"], "Size names match the menu")
    }

    @Test
    func recolouringTextUpdatesItsRunsAndDropsSemanticInk() throws {
        let font = EaselRichText.Font(name: ".AppleSystemUIFont", size: 15)
        func rich(_ ink: String, semantic: EaselRichText.SemanticInk? = nil) -> EaselRichText {
            EaselRichText(runs: [.init(location: 0, length: 5, attributes: .init(font: font, ink: ink, semanticInk: semantic))])
        }
        var plain = EaselTextSizingTestsSupport.text(); plain.richText = rich("#000000FF", semantic: .noteBody)
        let painted = try #require(EaselTextColor.recoloured(plain, hex: "#e05656"), "Text takes a colour")
        #expect(painted.color == "#E05656" && painted.richText?.runs[0].attributes.ink == "#E05656FF", "Text colours its ink and every run")
        #expect(painted.richText?.runs[0].attributes.semanticInk == nil, "Recoloured runs drop the Notes body ink")
    }

    @Test
    func recolouringShapeTextKeepsItsOutline() throws {
        let font = EaselRichText.Font(name: ".AppleSystemUIFont", size: 15)
        func rich(_ ink: String, semantic: EaselRichText.SemanticInk? = nil) -> EaselRichText {
            EaselRichText(runs: [.init(location: 0, length: 5, attributes: .init(font: font, ink: ink, semanticInk: semantic))])
        }
        var shape = EaselTextSizingTestsSupport.text(kind: .rectangle); shape.color = "#112233"; shape.richText = rich("#252525FF")
        let shaded = try #require(EaselTextColor.recoloured(shape, hex: "#E05656"), "Shape text takes a colour")
        #expect(shaded.color == "#112233" && shaded.richText?.runs[0].attributes.ink == "#E05656FF", "Shape text changes, its outline doesn't")
    }

    @Test
    func lockedTextKeepsItsColour() {
        var locked = EaselTextSizingTestsSupport.text(); locked.locked = true
        #expect(EaselTextColor.recoloured(locked, hex: "#E05656") == nil, "Locked text keeps its colour")
    }

    @Test
    func imagesDoNotHaveTextColour() {
        #expect(EaselTextColor.recoloured(EaselTextSizingTestsSupport.text(kind: .image), hex: "#E05656") == nil, "Images have no text colour")
    }

    @Test
    func onlyHexColoursApplyToText() {
        #expect(EaselTextColor.recoloured(EaselTextSizingTestsSupport.text(), hex: "red") == nil, "Only hex colours apply")
    }

    @Test
    func reapplyingTheSameTextColourChangesNothing() throws {
        let font = EaselRichText.Font(name: ".AppleSystemUIFont", size: 15)
        func rich(_ ink: String, semantic: EaselRichText.SemanticInk? = nil) -> EaselRichText {
            EaselRichText(runs: [.init(location: 0, length: 5, attributes: .init(font: font, ink: ink, semanticInk: semantic))])
        }
        var plain = EaselTextSizingTestsSupport.text(); plain.richText = rich("#000000FF", semantic: .noteBody)
        let painted = try #require(EaselTextColor.recoloured(plain, hex: "#e05656"), "Text takes a colour")
        #expect(EaselTextColor.recoloured(painted, hex: "#E05656") == nil, "The same colour again changes nothing")
    }

    @Test
    func stickyTextNeedsRunsAndPlainTextUsesObjectInk() {
        let sticky = EaselTextSizingTestsSupport.text(kind: .sticky)
        #expect(EaselTextColor.needsRuns(sticky) && !EaselTextColor.needsRuns(EaselTextSizingTestsSupport.text()), "Plain sticky text needs runs; text objects use their ink")
    }

    @Test
    func aMixedSelectionRecoloursTextAndSkipsLockedObjects() {
        let font = EaselRichText.Font(name: ".AppleSystemUIFont", size: 15)
        func rich(_ ink: String, semantic: EaselRichText.SemanticInk? = nil) -> EaselRichText {
            EaselRichText(runs: [.init(location: 0, length: 5, attributes: .init(font: font, ink: ink, semanticInk: semantic))])
        }
        var plain = EaselTextSizingTestsSupport.text(); plain.richText = rich("#000000FF", semantic: .noteBody)
        var locked = EaselTextSizingTestsSupport.text(); locked.locked = true
        let sticky = EaselTextSizingTestsSupport.text(kind: .sticky)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [plain, sticky, locked])
        var made: [UUID] = []
        guard let next = EaselTextColor.recolouring(board, ids: Set(board.items.map(\.id)), hex: "#E05656", runs: { item, hex in
            made.append(item.id)
            return EaselRichText(runs: [.init(location: 0, length: 5, attributes: .init(font: font, ink: hex + "FF"))])
        }) else { Issue.record("A mixed selection recolours its text"); return }
        #expect(made == [sticky.id], "Only plain shape and sticky text gets fresh runs")
        #expect(next.items[1].richText?.runs[0].attributes.ink == "#E05656FF" && next.items[1].color == sticky.color, "Sticky text recolours, paper stays")
        #expect(next.items[2] == locked, "Locked objects are skipped")
        #expect(EaselTextColor.recolouring(next, ids: Set(next.items.map(\.id)), hex: "#E05656", runs: { _, _ in nil }) == nil, "Recolouring twice is one step, not two")
    }
}
