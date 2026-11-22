import Foundation
import Testing
@testable import ParcCore

struct EaselStyleMemoryTests {
    struct Dice: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    @Test
    func eachSessionStartsStickiesOnARandomNotesColour() {
        var dice = Dice(state: 7)
        let start = EaselStyleMemory.randomSticky(using: &dice)
        #expect(start.color.flatMap(EaselColorChoice.init(storage:)).map { choice -> Bool in
            if case .palette(.note) = choice { return true }
            return false
        } == true, "Each session starts stickies on a random Notes colour")
    }

    @Test
    func stickyPaperIsRememberedAcrossEasels() {
        var dice = Dice(state: 7)
        let start = EaselStyleMemory.randomSticky(using: &dice)
        var memory = EaselStyleMemory(sticky: start)
        let easel = UUID(), other = UUID()
        memory.record(.color(.palette(.note(.green))), for: .stickies, document: easel)
        var sticky = EaselStyleTestsSupport.item(.sticky)
        memory.stamp(&sticky, document: other)
        #expect(sticky.fill == "#B5D5C2", "The last sticky colour becomes the next sticky's paper in every Easel")
    }

    @Test
    func connectorStylesAreRememberedPerEasel() {
        var dice = Dice(state: 7)
        let start = EaselStyleMemory.randomSticky(using: &dice)
        var memory = EaselStyleMemory(sticky: start)
        let easel = UUID(), other = UUID()
        memory.record(.color(.palette(.note(.red))), for: .lines, document: easel)
        memory.record(.weight(.thick), for: .lines, document: easel)
        memory.record(.dash(.dashed), for: .lines, document: easel)
        memory.record(.labelBackground(true), for: .lines, document: easel)
        var arrow = EaselStyleTestsSupport.item(.arrow)
        memory.stamp(&arrow, document: easel)
        #expect(arrow.color == "#C0322D" && arrow.strokeWidth == 6 && arrow.strokeDash == .dashed && arrow.labelBackground == true, "Connectors remember their style in their Easel")
        var elsewhere = EaselStyleTestsSupport.item(.arrow)
        memory.stamp(&elsewhere, document: other)
        #expect(elsewhere.color == "#252525" && elsewhere.strokeWidth == nil, "Another Easel's connectors start fresh")
    }

    @Test
    func shapeColourAndFillAreRememberedAcrossEasels() {
        var dice = Dice(state: 7)
        let start = EaselStyleMemory.randomSticky(using: &dice)
        var memory = EaselStyleMemory(sticky: start)
        let easel = UUID(), other = UUID()
        memory.record(.color(.palette(.note(.blue))), for: .shapes, document: easel)
        memory.record(.fill(.solid), for: .shapes, document: easel)
        var shape = EaselStyleTestsSupport.item(.rectangle)
        memory.stamp(&shape, document: other)
        #expect(shape.color == "#2C6C91" && shape.fill == "#D8E9F3", "Shapes remember colour and fill everywhere")
    }

    @Test
    func opacityDoesNotReplaceTheRememberedFillMode() {
        var dice = Dice(state: 7)
        let start = EaselStyleMemory.randomSticky(using: &dice)
        var memory = EaselStyleMemory(sticky: start)
        let easel = UUID(), other = UUID()
        memory.record(.color(.palette(.note(.blue))), for: .shapes, document: easel)
        memory.record(.fill(.solid), for: .shapes, document: easel)
        memory.record(.fillOpacity(0.25), for: .shapes, document: easel)
        #expect(memory.style(for: .shapes, document: nil).fill == .solid && memory.style(for: .shapes, document: nil).fillOpacity == 0.25, "A custom opacity keeps the remembered fill mode")
        var faded = EaselStyleTestsSupport.item(.rectangle)
        memory.stamp(&faded, document: other)
        #expect(faded.fill == "#D8E9F3" && faded.fillOpacity == 0.25, "New shapes get the remembered fill at its remembered strength")
    }

    @Test
    func onlyShapeStylesPersistAcrossSessions() {
        var dice = Dice(state: 7)
        let start = EaselStyleMemory.randomSticky(using: &dice)
        var memory = EaselStyleMemory(sticky: start)
        let easel = UUID()
        memory.record(.color(.palette(.note(.green))), for: .stickies, document: easel)
        memory.record(.color(.palette(.note(.red))), for: .lines, document: easel)
        memory.record(.weight(.thick), for: .lines, document: easel)
        memory.record(.dash(.dashed), for: .lines, document: easel)
        memory.record(.labelBackground(true), for: .lines, document: easel)
        memory.record(.color(.palette(.note(.blue))), for: .shapes, document: easel)
        memory.record(.fill(.solid), for: .shapes, document: easel)
        memory.record(.fillOpacity(0.25), for: .shapes, document: easel)
        let restored = EaselStyleMemory(families: EaselStyleMemory.persistentFamilies(from: memory.persistentData), sticky: start)
        #expect(restored.style(for: .shapes, document: nil) == memory.style(for: .shapes, document: nil), "Shape styles survive a relaunch")
        #expect(restored.style(for: .stickies, document: nil) == start, "Sticky colours start over each session")
        #expect(restored.style(for: .lines, document: easel) == EaselStyleMemory.Style(), "Connector styles start over each session")
    }

    @Test
    func damagedStyleMemoryIsIgnored() {
        #expect(EaselStyleMemory.persistentFamilies(from: Data("nonsense".utf8)).isEmpty, "Damaged memory is ignored")
    }

    @Test
    func styleMemoryLeavesImagesAlone() {
        var dice = Dice(state: 7)
        let start = EaselStyleMemory.randomSticky(using: &dice)
        let memory = EaselStyleMemory(sticky: start)
        let easel = UUID()
        var image = EaselStyleTestsSupport.item(.image)
        memory.stamp(&image, document: easel)
        #expect(image.color == "#252525", "Kinds without a style are left alone")
    }
}
