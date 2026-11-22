import Foundation
import Testing
@testable import ParcCore

struct EaselFreehandDrawingWashiTests {
    @Test
    func missingOrUnknownPatternNamesFallBackToStripes() {
        #expect(EaselWashi.pattern(named: nil) == .stripes && EaselWashi.pattern(named: "nope") == .stripes, "Unknown patterns fall back to stripes")
        #expect(EaselWashi.pattern(named: "kraft") == .kraft, "Saved pattern names come back")
    }

    @Test
    func onlyNondefaultPatternsAreStored() {
        #expect(EaselWashi.storedName(.stripes) == nil && EaselWashi.storedName(.dots) == "dots", "The default pattern isn't written to the file")
    }

    @Test
    func washiTilesUseValidColoursAndKeepMarksInsideTheirBounds() {
        for pattern in EaselWashiPattern.allCases {
            #expect(pattern.rawValue.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil, "\(pattern) saves as a valid pattern name")
            for color in [EaselPalette.automaticInk, "#2C6C91", "#123456"] {
                let tile = EaselWashi.tile(pattern, color: color)
                #expect(tile.height == EaselWashi.width && tile.width > 0, "\(pattern) tiles span the tape")
                #expect(EaselPalette.normalized(tile.base) != nil, "\(pattern) has a real base colour")
                for mark in tile.marks {
                    #expect(EaselPalette.normalized(mark.color) != nil && mark.opacity > 0 && mark.opacity <= 1, "\(pattern) marks have real colours")
                    let inside: Bool
                    switch mark.shape {
                    case .rect(let r): inside = r.x >= -1e-9 && r.y >= -1e-9 && r.x + r.width <= tile.width + 1e-9 && r.y + r.height <= tile.height + 1e-9
                    case .circle(let c, let radius): inside = c.x - radius >= 0 && c.y - radius >= 0 && c.x + radius <= tile.width && c.y + radius <= tile.height
                    case .polygon(let points): inside = points.count >= 3 && points.allSatisfy { $0.x >= -1e-9 && $0.y >= -1e-9 && $0.x <= tile.width + 1e-9 && $0.y <= tile.height + 1e-9 }
                    }
                    #expect(inside, "\(pattern) marks stay inside their tile so repeats never double up")
                }
            }
        }
    }

    @Test
    func washiColoursFollowDefaultPaletteAndCustomChoices() {
        #expect(EaselWashi.tile(.dots, color: EaselPalette.automaticInk).base == EaselPalette.hex(.note(.blue), role: .sticky), "Default dots come in blue")
        #expect(EaselWashi.tile(.dots, color: "#C0322D").base == EaselPalette.hex(.note(.red), role: .sticky), "Choosing a palette colour retints the tape")
        #expect(EaselWashi.tile(.stripes, color: "#123456").base == "#123456", "A custom colour becomes the tape itself")
    }

    @Test
    func tapeTearsAreSeededAndStayAtItsEnds() {
        let outline = EaselWashi.outline(length: 120, seed: 42)
        #expect(outline.count == 16, "Torn tape has seven teeth at each end")
        #expect(outline == EaselWashi.outline(length: 120, seed: 42), "The same strip always tears the same way")
        #expect(outline != EaselWashi.outline(length: 120, seed: 43), "Different strips tear differently")
        #expect(outline.allSatisfy { abs($0.y) <= EaselWashi.width / 2 + 1e-9 }, "Tears stay within the tape's width")
        #expect(outline.allSatisfy { $0.x >= -EaselWashi.tooth - 1e-9 && $0.x <= 120 + EaselWashi.tooth + 1e-9 }, "Tears only nibble the ends")
    }

    @Test
    func washiRunsFromItsFirstPointToItsLast() {
        let tape = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(10, 10), EaselFreehandDrawingTestsSupport.p(110, 110)], brush: .washi)
        let placement = EaselWashi.placement(tape)!
        #expect(EaselFreehandDrawingTestsSupport.near(placement.origin, EaselFreehandDrawingTestsSupport.p(10, 10)) && EaselFreehandDrawingTestsSupport.near(placement.length, hypot(100, 100)) && EaselFreehandDrawingTestsSupport.near(placement.angle, Double.pi / 4), "Tape runs from its first point to its last")
    }

    @Test
    func tearSeedsComeFromTheObjectID() {
        let first = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        #expect(EaselWashi.seed(first) == EaselWashi.seed(first), "Tear seeds come from the strip's ID")
    }

    @Test
    func polygonsClipToTheTile() {
        let clipped = EaselWashi.clipped([EaselFreehandDrawingTestsSupport.p(-5, -5), EaselFreehandDrawingTestsSupport.p(5, -5), EaselFreehandDrawingTestsSupport.p(5, 5), EaselFreehandDrawingTestsSupport.p(-5, 5)], to: EaselRect(x: 0, y: 0, width: 10, height: 10))
        #expect(clipped.allSatisfy { $0.x >= 0 && $0.y >= 0 }, "Clipping trims polygons to the tile")
    }

    @Test
    func eachBrushHasASpokenName() {
        #expect(EaselBrush.marker.title == "Drawing" && EaselBrush.highlighter.title == "Highlight" && EaselBrush.washi.title == "Washi tape", "Each brush has a name people hear")
    }

    @Test
    func highlightsAndTapeAreTheBrushesThatAttach() {
        #expect(!EaselBrush.marker.sticksToObjects && EaselBrush.highlighter.sticksToObjects && EaselBrush.washi.sticksToObjects, "Highlights and tape stick; doodles don't")
    }
}
