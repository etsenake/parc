import Foundation
import Testing
@testable import ParcCore

struct EaselObjectMotionTests {
    func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    func box(_ x: Double, _ y: Double, kind: EaselItemKind = .sticky, z: Int = 0) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: 100, height: 100), zIndex: z)
    }

    func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Board", createdAt: Date(timeIntervalSince1970: 0),
                      modifiedAt: Date(timeIntervalSince1970: 0), items: items)
    }

    @Test func anAppearingObjectStartsFadedAt80() {
        var motion = EaselObjectMotion()
        let id = UUID()
        motion.appear([id], at: 10, reduced: false)
        let first = motion.presentation(for: id, at: 10)
        #expect(near(first.opacity, 0) && near(first.scale, 0.8), "an appearing object starts faded at 95%")
        let middle = motion.presentation(for: id, at: 10.1)
        #expect(middle.opacity > 0.9 && middle.scale > 0.8 && middle.scale < 1, "the fade finishes before the pop")
        #expect(motion.presentation(for: id, at: 10.43).isIdentity, "an appearing object ends at rest")
        #expect(motion.presentation(for: UUID(), at: 10.05).isIdentity, "other objects stay at rest")
    }

    @Test func aDeletedObjectLeavesAGhostWhileItFades() {
        var motion = EaselObjectMotion()
        let item = box(0, 0)
        motion.vanish([item], at: 0, reduced: false)
        #expect(motion.ghosts.map(\.id) == [item.id], "a deleted object leaves a ghost while it fades")
        let middle = motion.presentation(for: item.id, at: 0.075)
        #expect(middle.opacity < 1 && middle.opacity > 0 && middle.scale < 1, "the ghost fades and shrinks a touch")
        #expect(near(motion.presentation(for: item.id, at: 0.18).opacity, 0), "the ghost ends invisible")
        motion.prune(at: 0.2)
        #expect(motion.ghosts.isEmpty && motion.isEmpty, "finished ghosts are dropped")
    }

    @Test func aCopyStartsOnItsSourceFullyDrawn() {
        var motion = EaselObjectMotion()
        let id = UUID()
        motion.glide([id: EaselPoint(x: -40, y: 0)], fades: true, at: 0, reduced: false)
        let start = motion.presentation(for: id, at: 0)
        #expect(near(start.offset.x, -40) && near(start.opacity, 1), "a copy starts on its source, fully drawn")
        let later = motion.presentation(for: id, at: 0.15)
        #expect(later.offset.x > -40 && later.offset.x < 0, "a copy travels towards its slot")
        #expect(motion.presentation(for: id, at: 0.45).isIdentity, "a glide ends at rest")
        motion.glide([id: EaselPoint(x: 0.2, y: 0.1)], fades: false, at: 1, reduced: false)
        #expect(motion.transition(for: id) == nil || motion.presentation(for: id, at: 1).isIdentity, "sub-point moves never glide")

        var chained = EaselObjectMotion()
        chained.glide([id: EaselPoint(x: 100, y: 0)], fades: false, at: 0, reduced: false)
        let shown = chained.presentation(for: id, at: 0.05).offset.x
        chained.glide([id: EaselPoint(x: 10, y: 0)], fades: false, at: 0.05, reduced: false)
        #expect(near(chained.presentation(for: id, at: 0.05).offset.x, shown + 10, 1e-3), "a second move continues from where the object is shown")
    }

    @Test func bringingForwardStartsSlightlyLarge() {
        var motion = EaselObjectMotion()
        let id = UUID()
        motion.lift([id], from: 1.03, at: 0, reduced: false)
        #expect(near(motion.presentation(for: id, at: 0).scale, 1.03), "bringing forward starts slightly large")
        #expect(motion.presentation(for: id, at: 0.2).isIdentity, "a lift settles at full size")
        var reduced = EaselObjectMotion()
        reduced.lift([id], from: 1.03, at: 0, reduced: true)
        #expect(reduced.isEmpty, "Reduce Motion skips layer lifts")
    }

    @Test func reduceMotionTurnsThePopIntoAFade() {
        var motion = EaselObjectMotion()
        let a = UUID(), b = UUID(), c = box(0, 0)
        motion.appear([a], at: 0, reduced: true)
        motion.glide([b: EaselPoint(x: 50, y: 50)], fades: false, at: 0, reduced: true)
        motion.vanish([c], at: 0, reduced: true)
        let appear = motion.presentation(for: a, at: 0.05)
        #expect(near(appear.scale, 1) && appear.opacity < 1, "Reduce Motion turns the pop into a fade")
        let glide = motion.presentation(for: b, at: 0)
        #expect(near(glide.offset.x, 0) && near(glide.offset.y, 0) && near(glide.opacity, 0.4), "Reduce Motion turns the glide into a short fade in place")
        #expect(near(motion.presentation(for: c.id, at: 0.05).scale, 1), "Reduce Motion fades deletes without shrinking")
        #expect(motion.presentation(for: a, at: 0.15).isIdentity && motion.presentation(for: b, at: 0.15).isIdentity, "reduced fades are short")
    }

    @Test func objectsThatVanishFromTheDocumentStopAnimatingGhosts() {
        var motion = EaselObjectMotion()
        let kept = UUID(), dropped = UUID(), ghost = box(0, 0)
        motion.appear([kept, dropped], at: 0, reduced: false)
        motion.vanish([ghost], at: 0, reduced: false)
        motion.forget(missing: [kept])
        #expect(motion.ids == [kept, ghost.id], "objects that vanish from the document stop animating, ghosts stay")
        motion.forget(missing: [kept, ghost.id])
        #expect(motion.ghosts.isEmpty && motion.ids == [kept], "an undone delete drops its ghost")
        motion.cancelAll()
        #expect(motion.isEmpty && motion.ghosts.isEmpty, "cancel settles everything")
    }

    @Test func movesGlideObjectsBackFromTheirOldSpotNever() {
        let a = box(0, 0), b = box(200, 0, z: 1)
        var moved = a; moved.frame.x = 50
        var arrow = EaselItem(kind: .arrow, frame: EaselRect(x: 0, y: 0, width: 10, height: 10), zIndex: 2)
        arrow.startConnection = EaselConnection(itemID: a.id)
        var shifted = arrow; shifted.frame.x = 40
        let before = document([a, b, arrow])
        let after = document([moved, b, shifted, box(400, 0, z: 3)])
        let moves = EaselObjectMotion.moves(from: before, to: after)
        #expect(moves.count == 1 && near(moves[a.id]?.x ?? 0, -50), "moves glide objects back from their old spot, never attached connectors")
        #expect(EaselObjectMotion.added(from: before, to: after).count == 1, "added objects are found")
        #expect(EaselObjectMotion.removed(from: after, to: before).count == 1, "removed objects are found")
        let copy = box(16, 16)
        let offsets = EaselObjectMotion.copyOffsets(sources: [a.id], copies: [copy.id], before: before, after: document([a, copy]))
        #expect(near(offsets[copy.id]?.x ?? 0, -16) && near(offsets[copy.id]?.y ?? 0, -16), "copies glide out of their source")
    }
}
