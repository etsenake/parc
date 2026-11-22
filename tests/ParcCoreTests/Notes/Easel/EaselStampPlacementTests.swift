import Foundation
import Testing
@testable import ParcCore

struct EaselStampPlacementTests {
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    @Test
    func stampSizesGrowInFourStages() {
        #expect(EaselStamps.sizes.count == 4 && EaselStamps.sizes == EaselStamps.sizes.sorted(), "Four growing sizes")
    }

    private struct Hold: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let seconds: Double
        let stage: Int

        init(_ label: String, _ seconds: Double, _ stage: Int) {
            testDescription = label
            self.seconds = seconds
            self.stage = stage
        }
    }

    @Test(arguments: [
        Hold("tap", 0, 0),
        Hold("negative duration", -1, 0),
        Hold("invalid duration", .nan, 0),
        Hold("below the first step", 0.29, 0),
        Hold("past the first step", 0.31, 1),
        Hold("past the second step", 0.61, 2),
        Hold("past the third step", 0.91, 3),
        Hold("held past every step", 60, 3),
    ])
    private func holdDurationDeterminesGrowthStage(_ hold: Hold) {
        #expect(EaselStamps.stage(heldFor: hold.seconds) == hold.stage)
    }

    @Test
    func aLongHoldStopsAtTheLargestStamp() {
        #expect(EaselStamps.side(heldFor: 60) == EaselStamps.sizes[3])
    }

    @Test
    func aStampCentresOnTheClick() {
        let centred = EaselStamps.frame(centeredAt: EaselPoint(x: 200, y: 150), side: 64)
        #expect(centred == EaselRect(x: 168, y: 118, width: 64, height: 64), "Stamps centre on the click")
    }

    @Test
    func aStampNearAnEdgeStaysOnTheBoard() {
        let corner = EaselStamps.frame(centeredAt: EaselPoint(x: 5, y: 10), side: 64)
        #expect(corner.x == 0 && corner.y == 0 && corner.width == 64, "Stamps near the edge stay on the board")
    }

    @Test
    func invalidPlacementFallsBackToAFiniteSmallStamp() {
        let odd = EaselStamps.frame(centeredAt: EaselPoint(x: .infinity, y: .nan), side: .nan)
        #expect([odd.x, odd.y, odd.width, odd.height].allSatisfy{ $0.isFinite } && odd.width == EaselStamps.sizes[0], "Bad input still lands sanely")
    }

    @Test func tiltStaysAGentleLean() {
        var generator = Seeded(state: 42)
        var signs = Set<Bool>()
        for _ in 0..<200 {
            let angle = EaselStamps.tilt(using: &generator)
            #expect(abs(angle) >= EaselStamps.tiltRange.lowerBound && abs(angle) <= EaselStamps.tiltRange.upperBound, "Tilt \(angle) stays a gentle lean")
            #expect((angle * 10).rounded() == angle * 10, "Tilt is rounded to a tenth of a degree")
            signs.insert(angle > 0)
        }
        #expect(signs.count == 2, "Stamps lean both ways")
    }

    @Test func aStampOnAStampJoinsTheSameObject() {
        let sticky = EaselStampTestsSupport.item(.sticky, 0, 0, 200, 200, z: 1)
        let note = EaselStampTestsSupport.item(.rectangle, 50, 50, 100, 100, z: 2)
        let arrow = EaselStampTestsSupport.item(.arrow, 0, 0, 300, 300, z: 5)
        var placed = EaselStampTestsSupport.stamp(.design(.heart), at: EaselPoint(x: 100, y: 100)); placed.zIndex = 9; placed.attachedTo = note.id
        let items = [sticky, note, arrow, placed]
        #expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 100, y: 100), in: items) == note.id, "A stamp on a stamp joins the same object")
        #expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 60, y: 60), in: [sticky, note, arrow]) == note.id, "The topmost object under the click carries the stamp, never a connector")
        #expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 20, y: 180), in: [sticky, note]) == sticky.id, "Lower objects carry stamps too")
        #expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 500, y: 500), in: items) == nil, "The bare board carries nothing")
        #expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 60, y: 60), in: [sticky, note], excluding: [note.id]) == sticky.id, "Excluded objects are skipped")
        var highlight = EaselStampTestsSupport.item(.freehand, 40, 40, 40, 40, z: 3); highlight.attachedTo = sticky.id
        #expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 45, y: 45), in: [sticky, highlight]) == sticky.id, "Doodles never hold stamps, so a stamp on one sticks to the object below")
        var locked = EaselStampTestsSupport.item(.rectangle, 0, 0, 100, 100, z: 4); locked.locked = true
        #expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 20, y: 20), in: [sticky, locked]) == sticky.id, "Locked backdrops never hold stamps")
        let section = EaselStampTestsSupport.item(.section, 0, 0, 600, 600, z: 0)
        #expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 400, y: 400), in: [section]) == nil, "Sections carry stamps by holding them, not by sticking")
        var turned = EaselStampTestsSupport.item(.rectangle, 300, 0, 200, 40, z: 1); turned.rotation = 90
        #expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 400, y: 90), in: [turned]) == turned.id
               && EaselStamps.attachmentTarget(at: EaselPoint(x: 310, y: 20), in: [turned]) == nil, "Rotated objects hold stamps where they really are")
        var loopA = EaselStampTestsSupport.item(.rectangle, 0, 0, 100, 100, z: 1), loopB = EaselStampTestsSupport.item(.rectangle, 0, 0, 100, 100, z: 2)
        loopA.attachedTo = loopB.id; loopB.attachedTo = loopA.id
        #expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 10, y: 10), in: [loopA, loopB]) == nil, "Attachment loops never hang")
        let same = EaselStampTestsSupport.item(.rectangle, 0, 0, 100, 100, z: 0), later = EaselStampTestsSupport.item(.rectangle, 0, 0, 100, 100, z: 0)
        #expect(EaselStamps.attachmentTarget(at: EaselPoint(x: 10, y: 10), in: [same, later]) == later.id, "Ties go to the later object")
        #expect(EaselStamps.centre(of: placed) == EaselPoint(x: 100, y: 100), "Stamps aim from their centre")
    }

    @Test func droppingAStampOnAnotherObjectMovesItThere() {
        let base = EaselStampTestsSupport.item(.sticky, 0, 0, 200, 200, z: 1), other = EaselStampTestsSupport.item(.sticky, 400, 0, 200, 200, z: 1)
        var riding = EaselStampTestsSupport.stamp(.design(.star), at: EaselPoint(x: 100, y: 100)); riding.attachedTo = base.id; riding.zIndex = 4
        let before = EaselStampTestsSupport.document([base, other, riding])
        func moving(_ ids: Set<UUID>, by dx: Double) -> EaselDocument {
            var next = before
            for index in next.items.indices where ids.contains(next.items[index].id) { next.items[index].frame.x += dx }
            return EaselDependents.settle(next, previous: before, moved: ids)
        }
        let dropped = moving([riding.id], by: 400)
        #expect(dropped.items[2].attachedTo == other.id, "Dropping a stamp on another object moves it there")
        #expect(moving([riding.id], by: 1200).items[2].attachedTo == nil, "Dropping it on the board lets go")
        let carried = moving([base.id], by: 30)
        #expect(carried.items[2].attachedTo == base.id && carried.items[2].frame.x == riding.frame.x + 30, "Stamps ride along when their object moves")
        let together = moving([base.id, riding.id], by: 900)
        #expect(together.items[2].attachedTo == base.id && together.items[2].frame.x == riding.frame.x + 900, "Moving both keeps them together")
        var turnedBase = before
        turnedBase.items[0].rotation = 90
        let spun = EaselDependents.settle(turnedBase, previous: before, moved: [base.id])
        #expect(spun.items[2].rotation == 90 && spun.items[2].attachedTo == base.id, "Stamps turn with the object they ride")
        var arriving = EaselStampTestsSupport.stamp(.design(.heart), at: EaselPoint(x: 500, y: 100)); arriving.zIndex = 6
        var pasting = before
        pasting.items.append(arriving)
        #expect(EaselDependents.settle(pasting, previous: before, moved: []).items[3].attachedTo == other.id, "Pasted and duplicated stamps stick to whatever they land on")
        pasting.items[3].frame = EaselStamps.frame(centeredAt: EaselPoint(x: 900, y: 900), side: 64)
        #expect(EaselDependents.settle(pasting, previous: before, moved: []).items[3].attachedTo == nil, "Stamps pasted on bare board stay free")
        var unstuck = before
        unstuck.items[2].attachedTo = nil
        #expect(EaselDependents.settle(unstuck, previous: before, moved: []).items[2].attachedTo == nil, "Existing free stamps are left alone")
        let cleared = EaselDependents.removing([base.id], from: before)
        #expect(!cleared.items.contains { $0.id == riding.id } && cleared.items.contains { $0.id == other.id }, "Deleting an object takes its stamps with it")
    }

    @Test func stampingMakesAStamp() {
        let sticky = EaselStampTestsSupport.item(.sticky, 0, 0, 200, 200, z: 3)
        let doc = EaselStampTestsSupport.document([sticky])
        let heart = EaselStamps.stamped(.design(.heart), at: EaselPoint(x: 100, y: 100), tilt: -6.5, color: "#C0322D", in: doc)
        #expect(heart.kind == .stamp && heart.stamp == "heart" && heart.text.isEmpty, "Stamping makes a stamp")
        #expect(heart.frame == EaselRect(x: 68, y: 68, width: 64, height: 64) && heart.zIndex == 4, "It lands centred, on top")
        #expect(heart.rotation == -6.5 && heart.attachedTo == sticky.id, "It leans and sticks")
        #expect(heart.color == "#252525", "Built-in stamps keep their own colours")
        let icon = EaselStamps.stamped(.icon("cloud"), at: EaselPoint(x: 600, y: 600), side: 136, tilt: 0, color: "#c0322dff", in: doc)
        #expect(icon.color == "#C0322D" && icon.attachedTo == nil && icon.rotation == nil, "Icons take the ink colour; flat stamps store no angle")
        #expect(icon.frame.width == 136, "Grown stamps keep their size")
        let wild = EaselStamps.stamped(.emoji("🎉"), at: EaselPoint(x: 10, y: 10), tilt: .infinity, color: "nope", in: doc)
        #expect(wild.rotation == nil && wild.color == "#252525", "Bad tilt and colour fall back")
    }

    @Test func pointingAtWheelSlotPicksIt() {
        for index in EaselStamps.ring.indices {
            let offset = EaselStamps.wheelOffset(of: index, radius: 80)
            #expect(EaselStamps.wheelIndex(dx: offset.x, dy: offset.y, inner: 40, outer: 110) == index, "Pointing at wheel slot \(index) picks it")
        }
        #expect(EaselStamps.wheelOffset(of: 0, radius: 80).y < -79 && EaselStamps.wheelOffset(of: 2, radius: 80).x > 79, "The wheel starts at the top and runs clockwise")
        #expect(EaselStamps.wheelIndex(dx: 5, dy: 5, inner: 40, outer: 110) == nil
               && EaselStamps.wheelIndex(dx: 200, dy: 0, inner: 40, outer: 110) == nil
               && EaselStamps.wheelIndex(dx: .nan, dy: 0, inner: 40, outer: 110) == nil, "The hub and the outside pick no ring stamp")
    }

    @Test func keyboardStampsLandInTheTopRightCorner() {
        let sticky = EaselStampTestsSupport.item(.sticky, 100, 100, 200, 200, z: 1)
        let first = EaselStamps.pinnedPoint(on: sticky, side: 64, slot: 0), second = EaselStamps.pinnedPoint(on: sticky, side: 64, slot: 1)
        #expect(abs(first.x - 274.4) < 0.01 && abs(first.y - 125.6) < 0.01, "Keyboard stamps land in the top right corner")
        #expect(second.x < first.x && second.y == first.y, "More keyboard stamps line up beside the first")
        let later = EaselStamps.pinnedPoint(on: sticky, side: 64, slot: 40)
        #expect(later.x >= 125 && later.y <= 275, "Crowded objects keep stamps inside")
        var turned = sticky; turned.rotation = 90
        let spun = EaselStamps.pinnedPoint(on: turned, side: 64, slot: 0)
        #expect(abs(spun.x - 274.4) < 0.01 && abs(spun.y - 274.4) < 0.01, "Turned objects get stamps on their turned corner")
        let tiny = EaselStampTestsSupport.item(.rectangle, 0, 0, 10, 10, z: 0)
        #expect(EaselStamps.pinnedPoint(on: tiny, side: 184, slot: 3) == EaselPoint(x: 5, y: 5), "Tiny objects get stamps in the middle")

        var riding = EaselStampTestsSupport.stamp(.design(.heart), at: EaselPoint(x: 150, y: 150)); riding.attachedTo = sticky.id
        var locked = EaselStampTestsSupport.item(.rectangle, 500, 0, 100, 100, z: 1); locked.locked = true
        let arrow = EaselStampTestsSupport.item(.arrow, 0, 0, 50, 50, z: 1), other = EaselStampTestsSupport.item(.rectangle, 700, 0, 100, 100, z: 1)
        let all = [sticky, riding, locked, arrow, other]
        #expect(EaselStamps.keyboardTargets([riding.id, sticky.id, other.id, locked.id, arrow.id], in: all) == [sticky.id, other.id], "⌘Return stamps each selected object once, through its stamps, never locked objects or connectors")
    }

    @Test func recentsMoveToTheFrontWithoutRepeats() {
        var list: [String] = []
        list = EaselStamps.recording(.emoji("🎉"), in: list)
        list = EaselStamps.recording(.design(.heart), in: list)
        list = EaselStamps.recording(.icon("cloud"), in: list)
        list = EaselStamps.recording(.emoji("🎉"), in: list)
        #expect(list == ["emoji:🎉", "icon:cloud", "stamp:heart"], "Recents move to the front without repeats")
        list = EaselStamps.recording(.icon("bolt"), in: list + ["junk", "emoji:hi", "icon:cloud"])
        #expect(list == ["icon:bolt", "emoji:🎉", "icon:cloud", "stamp:heart"], "Damaged and repeated recents are dropped")
        for index in 0..<20 { list = EaselStamps.recording(.icon("icon\(index)"), in: list) }
        #expect(list.count == EaselStamps.recentsLimit, "Recents stay short")
        let hub = EaselStamps.hubFaces(["stamp:heart", "emoji:🎉", "icon:cloud", "emoji:🎉", "icon:bolt", "emoji:😀"])
        #expect(hub == [.emoji("🎉"), .icon("cloud"), .icon("bolt")], "The wheel's centre shows three recent extras, never ring stamps")
        #expect(EaselStamps.hubFaces([]).isEmpty, "No recents, empty centre")
        #expect(Set(EaselStamps.ring) == Set(EaselStampDesign.allCases) && EaselStamps.ring.count == 8, "The ring holds all eight stamps")
    }
}
