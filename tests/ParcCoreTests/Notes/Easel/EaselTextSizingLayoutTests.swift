import Foundation
import Testing
@testable import ParcCore

struct EaselTextSizingLayoutTests {
    @Test func unusedSizingFieldsStayOutOfSavedBytes() {
        do {
            let plain = String(decoding: try JSONEncoder().encode(EaselTextStyle()), as: UTF8.self)
            #expect(!plain.contains("customSize") && !plain.contains("autoWidth"), "Unused sizing fields stay out of saved bytes")
            let sized = EaselTextStyle(family: .mono, size: .h2, customSize: 36, autoWidth: true)
            let decoded = try JSONDecoder().decode(EaselTextStyle.self, from: JSONEncoder().encode(sized))
            #expect(decoded == sized, "Custom size and auto width survive a save")
            let legacy = try JSONDecoder().decode(EaselTextStyle.self, from: Data(#"{"family":"mono","size":"h2"}"#.utf8))
            #expect(legacy == EaselTextStyle(family: .mono, size: .h2), "Older text styles open unchanged")
            #expect(legacy.customSize == nil && legacy.autoWidth == nil, "Older text stays fixed-width at its preset size")
            #expect(legacy.pointSize == 24 && legacy.presetPointSize == 24, "Preset sizes are unchanged")
            #expect(sized.pointSize == 36 && sized.presetPointSize == 24, "A custom size overrides the preset's point size")
        } catch { Issue.record("Text style coding failed: \(error)") }
    }

    @Test @MainActor func validSizingFieldsSaveAndInvalidOnesAreRefused() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("easel-text-sizing-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let session = try EaselStore(directory: directory).create()
            let good = EaselTextSizingTestsSupport.text(style: EaselTextStyle(customSize: 8, autoWidth: true))
            try session.perform("Add text") { $0.items.append(good) }
            let largest = EaselTextSizingTestsSupport.text(style: EaselTextStyle(customSize: 400))
            try session.perform("Add text") { $0.items.append(largest) }
            for size in [7.99, 400.5, Double.nan, Double.infinity, -12] {
                EaselTextSizingTestsSupport.expectThrows("custom size \(size)") {
                    try session.perform("Add text") { $0.items.append(EaselTextSizingTestsSupport.text(style: EaselTextStyle(customSize: size))) }
                }
            }
            for kind in [EaselItemKind.sticky, .rectangle, .circle] {
                EaselTextSizingTestsSupport.expectThrows("auto width on \(kind.rawValue)") {
                    try session.perform("Add") { $0.items.append(EaselTextSizingTestsSupport.text(style: EaselTextStyle(autoWidth: true), kind: kind)) }
                }
            }
            try session.perform("Add sticky") { $0.items.append(EaselTextSizingTestsSupport.text(style: EaselTextStyle(customSize: 30), kind: .sticky)) }
            #expect(session.document.items.count == 3, "Valid sizing fields save and invalid ones are refused whole")
        } catch { Issue.record("Text sizing validation failed: \(error)") }
    }

    @Test func bodyTextWidensToAComfortable560PointsBefore() {
        #expect(EaselTextSizing.maximumAutoWidth(pointSize: 15) == 560, "Body text widens to a comfortable 560 points before wrapping")
        #expect(EaselTextSizing.maximumAutoWidth(pointSize: 24) == 864, "Larger text gets a proportionally wider limit")
        #expect(EaselTextSizing.maximumAutoWidth(pointSize: 400) == 4000, "The widest auto text stops at 4000 points")
        #expect(EaselTextSizing.maximumAutoWidth(pointSize: .nan) == 560, "A broken size falls back to the body limit")
        #expect(EaselTextSizing.autoWidth(natural: 100.2, pointSize: 15) == 101, "Auto width rounds up so text never wraps early")
        #expect(EaselTextSizing.autoWidth(natural: 3, pointSize: 15) == EaselTextSizing.minimumWidth, "Empty text keeps room for the caret")
        #expect(EaselTextSizing.autoWidth(natural: 10_000, pointSize: 15) == 560, "Long lines wrap at the limit")
        #expect(EaselTextSizing.autoWidth(natural: .infinity, pointSize: 15) == EaselTextSizing.minimumWidth, "Broken measurements stay safe")
    }

    @Test
    func onlyPointTextUsesAutoWidth() {
        let style = EaselTextStyle(autoWidth: true)
        let point = EaselTextSizingTestsSupport.text(style: style)
        #expect(EaselTextSizing.isAutoWidth(point), "Point text is auto width")
        #expect(!EaselTextSizing.isAutoWidth(EaselTextSizingTestsSupport.text()), "Existing text is fixed-width area text")
        #expect(!EaselTextSizing.isAutoWidth(EaselTextSizingTestsSupport.text(style: style, kind: .sticky)), "Only text objects can be auto width")
    }

    @Test
    func leftAlignedPointTextGrowsToTheRight() {
        let style = EaselTextStyle(autoWidth: true)
        let point = EaselTextSizingTestsSupport.text(style: style)
        let wider = EaselTextSizing.fittedFrame(point, naturalWidth: 300) { width in width == 300 ? 40 : 0 }
        #expect(wider == EaselRect(x: 100, y: 100, width: 300, height: 40), "Left-aligned point text grows to the right and hugs its height")
    }

    @Test
    func centredPointTextGrowsFromItsMiddle() {
        let style = EaselTextStyle(autoWidth: true)
        let point = EaselTextSizingTestsSupport.text(style: style)
        var centered = point; centered.textStyle?.alignment = .center
        let grown = EaselTextSizing.fittedFrame(centered, naturalWidth: 300) { _ in 28 }
        #expect(grown.x == 50 && grown.width == 300, "Centred point text grows from its middle")
    }

    @Test
    func rightAlignedPointTextKeepsItsRightEdge() {
        let style = EaselTextStyle(autoWidth: true)
        let point = EaselTextSizingTestsSupport.text(style: style)
        var right = point; right.textStyle?.alignment = .right
        let shrunk = EaselTextSizing.fittedFrame(right, naturalWidth: 100) { _ in 28 }
        #expect(shrunk.x == 200 && shrunk.width == 100, "Right-aligned point text keeps its right edge")
    }

    @Test
    func growingPointTextStaysOnTheCanvas() {
        let style = EaselTextStyle(autoWidth: true)
        let point = EaselTextSizingTestsSupport.text(style: style)
        var right = point; right.textStyle?.alignment = .right
        var edge = right; edge.frame.x = 0
        #expect(EaselTextSizing.fittedFrame(edge, naturalWidth: 500) { _ in 28 }.x == 0, "Growing text never leaves the canvas")
    }

    @Test
    func areaTextKeepsItsWidthAndGrowsOnlyAsNeeded() {
        let area = EaselTextSizing.fittedFrame(EaselTextSizingTestsSupport.text(), naturalWidth: 900) { width in width == 200 ? 60 : 0 }
        #expect(area == EaselRect(x: 100, y: 100, width: 200, height: 60), "Area text keeps its width and grows taller")
        let tall = EaselTextSizing.fittedFrame(EaselTextSizingTestsSupport.text(EaselRect(x: 0, y: 0, width: 200, height: 90)), naturalWidth: 50) { _ in 28 }
        #expect(tall.height == 90, "Area text keeps a taller box while typing")
    }

    @Test
    func anAreaTextBoxCanReturnToAutoWidth() {
        let style = EaselTextStyle(autoWidth: true)
        let point = EaselTextSizingTestsSupport.text(style: style)
        guard let auto = EaselTextSizing.autoWidthFrame(EaselTextSizingTestsSupport.text(), naturalWidth: 120, height: { _ in 28 }) else {
            Issue.record("Double-clicking a side handle returns area text to auto width")
            return
        }
        #expect(auto.textStyle?.autoWidth == true && auto.frame.width == 120, "Auto width fits the text again")
        #expect(EaselTextSizing.autoWidthFrame(point, naturalWidth: 120, height: { _ in 28 }) == nil, "Auto width text is already auto")
    }

    @Test
    func lockedTextCannotReturnToAutoWidth() {
        var locked = EaselTextSizingTestsSupport.text(); locked.locked = true
        #expect(EaselTextSizing.autoWidthFrame(locked, naturalWidth: 120, height: { _ in 28 }) == nil, "Locked text keeps its width")
    }

    @Test
    func stickiesHaveNoAutoWidth() {
        #expect(EaselTextSizing.autoWidthFrame(EaselTextSizingTestsSupport.text(kind: .sticky), naturalWidth: 120, height: { _ in 28 }) == nil, "Stickies have no auto width")
    }

    @Test
    func sideDraggingPointTextMakesItWrap() {
        let style = EaselTextStyle(autoWidth: true)
        let point = EaselTextSizingTestsSupport.text(style: style)
        var dragged = point; dragged.frame.width = 90
        let resized = EaselTextSizing.widthResized(dragged) { width in width == 90 ? 84 : 0 }
        #expect(resized.textStyle?.autoWidth == nil && resized.frame.height == 84, "Side-dragging point text makes wrapping area text")
    }

    @Test
    func widthResizingLeavesShapesAlone() {
        let shape = EaselTextSizingTestsSupport.text(kind: .rectangle)
        #expect(EaselTextSizing.widthResized(shape) { _ in 1 } == shape, "Side drags leave shapes alone")
    }

    @Test func shapesCentreTheirText() {
        #expect(EaselTextSizing.defaultAlignment(for: .rectangle) == .center && EaselTextSizing.defaultAlignment(for: .circle) == .center, "Shapes centre their text")
        #expect(EaselTextSizing.defaultAlignment(for: .text) == .left && EaselTextSizing.defaultAlignment(for: .sticky) == .left, "Text and stickies start on the left")
        #expect(EaselTextSizing.resolvedAlignment(EaselTextSizingTestsSupport.text()) == .left, "Text without a choice reads as left-aligned")
        #expect(EaselTextSizing.resolvedAlignment(EaselTextSizingTestsSupport.text(style: EaselTextStyle(alignment: .right))) == .right, "Chosen alignment wins")
        #expect(EaselTextSizing.resolvedAlignment(EaselTextSizingTestsSupport.text(kind: .rectangle)) == .center, "Shape text is centred by default")
        #expect(EaselTextSizing.resolvedAlignment(EaselTextSizingTestsSupport.text(style: EaselTextStyle(alignment: .left), kind: .rectangle)) == .left, "Shape text can align left")
    }

    @Test func textAndShapesAlign() throws {
        let shape = EaselTextSizingTestsSupport.text(kind: .rectangle), plain = EaselTextSizingTestsSupport.text()
        var locked = EaselTextSizingTestsSupport.text(); locked.locked = true
        let image = EaselTextSizingTestsSupport.text(kind: .image)
        let document = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [plain, shape, locked, image])
        let ids = Set(document.items.map(\.id))
        let aligned = try #require(EaselTextSizing.aligning(document, ids: ids, to: .right), "Aligning text changes the board")
        #expect(aligned.items[0].textStyle?.alignment == .right && aligned.items[1].textStyle?.alignment == .right, "Text and shapes align")
        #expect(aligned.items[2].textStyle == nil && aligned.items[3].textStyle == nil, "Locked objects and images are left alone")
        #expect(EaselTextSizing.aligning(aligned, ids: ids, to: .right) == nil, "Aligning again changes nothing")
        #expect(EaselTextSizing.sharedAlignment(Array(aligned.items.prefix(2))) == .right, "A uniform selection reports its alignment")
        #expect(EaselTextSizing.sharedAlignment(document.items) == nil, "A mixed selection reports no single alignment")
        #expect(EaselTextSizing.canAlign([plain]) && !EaselTextSizing.canAlign([locked, image]), "Alignment needs unlocked text")
        #expect(EaselTextStyle.Alignment.allCases.map(\.shortcut) == ["⌥⌘L", "⌥⌘T", "⌥⌘R"], "Alignment shortcuts read left, centre, right")
        let chords: [(String, UInt16, EaselTextStyle.Alignment)] = [("l", 37, .left), ("t", 17, .center), ("r", 15, .right)]
        for (letter, code, alignment) in chords {
            #expect(EaselChords.command(characters: letter, keyCode: code, modifiers: [.command, .option]) == .alignText(alignment), "⌥⌘\(letter.uppercased()) aligns text")
            #expect(EaselChords.command(characters: letter, keyCode: code, modifiers: [.command]) != .alignText(alignment), "⌘\(letter.uppercased()) alone never aligns text")
        }
        #expect(EaselChords.reserved.allSatisfy { EaselChords.table[$0] == nil }, "Alignment chords stay clear of Parc's reserved chords")
    }

    @Test func textHasNoTopOrBottomHandle() throws {
        let frame = EaselRect(x: 0, y: 0, width: 200, height: 28)
        let texts = [EaselTextSizingTestsSupport.text(frame)]
        for handle in [EaselResizeHandle.top, .bottom] {
            #expect(EaselTextSizing.handleRect(handle, in: frame, items: texts) == nil, "Text has no top or bottom handle")
        }
        for handle in [EaselResizeHandle.left, .right] {
            let rect = try #require(EaselTextSizing.handleRect(handle, in: frame, items: texts), "Short text still has side handles")
            #expect(rect.height >= 8 && rect.y + rect.height / 2 == 14, "Side handles sit on the middle of the edge")
        }
        #expect(EaselTextSizing.handleOrder(for: texts).prefix(2) == [.left, .right], "Side handles win over corners on short text")
        let tall = EaselRect(x: 0, y: 0, width: 200, height: 100)
        #expect(EaselTextSizing.handleRect(.left, in: tall, items: texts) == EaselRect(x: -5, y: 10, width: 10, height: 80), "Tall text's side handle runs between the corners")
        let mixed = [EaselTextSizingTestsSupport.text(frame), EaselTextSizingTestsSupport.text(frame, kind: .rectangle)]
        for handle in EaselResizeHandle.allCases {
            #expect(EaselTextSizing.handleRect(handle, in: tall, items: mixed) == handle.hitRect(in: tall), "Mixed selections keep every handle")
        }
        #expect(EaselTextSizing.handleOrder(for: mixed) == EaselResizeHandle.allCases, "Mixed selections keep the usual handle order")
        #expect(EaselTextSizing.sideHandlePoints(in: tall, items: texts) == [EaselPoint(x: 0, y: 50), EaselPoint(x: 200, y: 50)], "Text shows its width handles at the middle of each side")
        #expect(EaselTextSizing.sideHandlePoints(in: tall, items: mixed).isEmpty, "Other selections draw no width handles")
        #expect(EaselTextSizing.scalesText(texts, handle: .bottomRight) && !EaselTextSizing.scalesText(texts, handle: .right), "Corners scale text and sides set its width")
        #expect(!EaselTextSizing.scalesText(mixed, handle: .topLeft), "Mixed selections resize instead of scaling text")
    }

    @Test func scalingSnapsToWholePoints() {
        #expect(EaselTextSizing.scaledSize(base: 15, factor: 1.6) == 24, "Scaling snaps to whole points")
        #expect(EaselTextSizing.scaledSize(base: 15, factor: 0.1) == 8, "Scaling stops at 8 points")
        #expect(EaselTextSizing.scaledSize(base: 80, factor: 9) == 400, "Scaling stops at 400 points")
        #expect(EaselTextSizing.scaledSize(base: 15, factor: .nan) == nil && EaselTextSizing.scaledSize(base: 0, factor: 2) == nil, "Broken scales are refused")
    }
}
