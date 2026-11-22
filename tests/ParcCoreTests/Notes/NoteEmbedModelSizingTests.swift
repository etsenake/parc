import Foundation
import Testing
@testable import ParcCore

struct NoteEmbedModelSizingTests {
    struct Height: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let input: Double?
        let expected: Double
    }

    private static let heights = [
        Height(testDescription: "missing height", input: nil, expected: NoteEmbedSizing.defaultHeight),
        Height(testDescription: "NaN", input: .nan, expected: NoteEmbedSizing.defaultHeight),
        Height(testDescription: "infinity", input: .infinity, expected: NoteEmbedSizing.defaultHeight),
        Height(testDescription: "below minimum", input: 10, expected: NoteEmbedSizing.minimumHeight),
        Height(testDescription: "above maximum", input: 99_999, expected: NoteEmbedSizing.maximumHeight),
        Height(testDescription: "fractional height", input: 512.4, expected: 512),
    ]

    struct Drag: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let height: Double?
        let delta: Double
        let expected: Double
    }

    private static let drags = [
        Drag(testDescription: "grow from default", height: nil, delta: 80, expected: NoteEmbedSizing.defaultHeight + 80),
        Drag(testDescription: "clamp at minimum", height: 300, delta: -1000, expected: NoteEmbedSizing.minimumHeight),
        Drag(testDescription: "invalid delta", height: 300, delta: .nan, expected: 300),
    ]

    @Test(arguments: heights) func embedHeightsClampAndRound(_ example: Height) {
        #expect(NoteEmbedSizing.clamped(example.input) == example.expected)
    }

    @Test(arguments: drags) func draggingResizesAnEmbedWithinItsBounds(_ example: Drag) {
        #expect(NoteEmbedSizing.resized(from: example.height, by: example.delta) == example.expected)
    }

    @Test func defaultHeightDoesNotNeedStorage() {
        #expect(NoteEmbedSizing.stored(NoteEmbedSizing.defaultHeight) == nil, "the default height isn't written to the file")
    }

    @Test func customHeightIsStoredRounded() {
        #expect(NoteEmbedSizing.stored(612.6) == 613, "custom heights are stored clamped and rounded")
    }

    @Test func storedHeightClampsWhenRead() {
        var props = NoteBlockProps()
        props.height = 2
        #expect(NoteEmbedSizing.height(of: props) == NoteEmbedSizing.minimumHeight, "stored heights clamp when read")
    }
}
