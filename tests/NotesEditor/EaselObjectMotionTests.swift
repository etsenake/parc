import Foundation

@main
struct EaselObjectMotionTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    static func box(_ x: Double, _ y: Double, kind: EaselItemKind = .sticky, z: Int = 0) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: 100, height: 100), zIndex: z)
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Board", createdAt: Date(timeIntervalSince1970: 0),
                      modifiedAt: Date(timeIntervalSince1970: 0), items: items)
    }

    static func main() {
        appearing()
        vanishing()
        gliding()
        lifting()
        reducedMotion()
        bookkeeping()
        diffs()
        entrances()
        stampSlam()
        landing()
        pulsing()
        shaking()
        restyling()
        carrying()
        cascading()
        history()
        stampHold()
        wheel()
        bursts()
        foldAnchors()
        print("EaselObjectMotionTests passed")
    }

    static func appearing() {
        var motion = EaselObjectMotion()
        let id = UUID()
        motion.appear([id], at: 10, reduced: false)
        let first = motion.presentation(for: id, at: 10)
        expect(near(first.opacity, 0) && near(first.scale, 0.8), "an appearing object starts faded at 80%")
        let middle = motion.presentation(for: id, at: 10.1)
        expect(middle.opacity > 0.9 && middle.scale > 0.8 && middle.scale < 1, "the fade finishes before the pop")
        let peak = stride(from: 10.0, to: 10.42, by: 0.005).map { motion.presentation(for: id, at: $0).scale }.max() ?? 0
        expect(peak > 1.002 && peak < 1.03, "the pop overshoots a touch on the pop spring")
        expect(motion.presentation(for: id, at: 10.43).isIdentity, "an appearing object ends at rest")
        expect(motion.presentation(for: UUID(), at: 10.05).isIdentity, "other objects stay at rest")
    }

    static func vanishing() {
        var motion = EaselObjectMotion()
        let item = box(0, 0)
        motion.vanish([item], at: 0, reduced: false)
        expect(motion.ghosts.map(\.id) == [item.id], "a deleted object leaves a ghost while it fades")
        let middle = motion.presentation(for: item.id, at: 0.09)
        expect(middle.opacity < 1 && middle.opacity > 0 && middle.scale < 1, "the ghost fades and shrinks")
        expect(motion.presentation(for: item.id, at: 0.1799).scale < 0.86, "the poof shrinks to 85%")
        expect(near(motion.presentation(for: item.id, at: 0.18).opacity, 0), "the ghost ends invisible")
        motion.prune(at: 0.2)
        expect(motion.ghosts.isEmpty && motion.isEmpty, "finished ghosts are dropped")
    }

    static func gliding() {
        var motion = EaselObjectMotion()
        let id = UUID()
        motion.glide([id: EaselPoint(x: -40, y: 0)], fades: true, at: 0, reduced: false)
        let start = motion.presentation(for: id, at: 0)
        expect(near(start.offset.x, -40) && near(start.opacity, 1), "a copy starts on its source, fully drawn")
        let later = motion.presentation(for: id, at: 0.15)
        expect(later.offset.x > -40 && later.offset.x < 0, "a copy travels towards its slot")
        expect(motion.presentation(for: id, at: 0.45).isIdentity, "a glide ends at rest")
        motion.glide([id: EaselPoint(x: 0.2, y: 0.1)], fades: false, at: 1, reduced: false)
        expect(motion.transition(for: id) == nil || motion.presentation(for: id, at: 1).isIdentity, "sub-point moves never glide")

        var chained = EaselObjectMotion()
        chained.glide([id: EaselPoint(x: 100, y: 0)], fades: false, at: 0, reduced: false)
        let shown = chained.presentation(for: id, at: 0.05).offset.x
        chained.glide([id: EaselPoint(x: 10, y: 0)], fades: false, at: 0.05, reduced: false)
        expect(near(chained.presentation(for: id, at: 0.05).offset.x, shown + 10, 1e-3), "a second move continues from where the object is shown")
    }

    static func lifting() {
        var motion = EaselObjectMotion()
        let id = UUID()
        motion.lift([id], from: 1.03, at: 0, reduced: false)
        expect(near(motion.presentation(for: id, at: 0).scale, 1.03), "bringing forward starts slightly large")
        expect(motion.presentation(for: id, at: 0.2).isIdentity, "a lift settles at full size")
        var reduced = EaselObjectMotion()
        reduced.lift([id], from: 1.03, at: 0, reduced: true)
        expect(reduced.isEmpty, "Reduce Motion skips layer lifts")
    }

    static func reducedMotion() {
        var motion = EaselObjectMotion()
        let a = UUID(), b = UUID(), c = box(0, 0)
        motion.appear([a], at: 0, reduced: true)
        motion.glide([b: EaselPoint(x: 50, y: 50)], fades: false, at: 0, reduced: true)
        motion.vanish([c], at: 0, reduced: true)
        let appear = motion.presentation(for: a, at: 0.05)
        expect(near(appear.scale, 1) && appear.opacity < 1, "Reduce Motion turns the pop into a fade")
        let glide = motion.presentation(for: b, at: 0)
        expect(near(glide.offset.x, 0) && near(glide.offset.y, 0) && near(glide.opacity, 0.4), "Reduce Motion turns the glide into a short fade in place")
        expect(near(motion.presentation(for: c.id, at: 0.05).scale, 1), "Reduce Motion fades deletes without shrinking")
        expect(motion.presentation(for: a, at: 0.15).isIdentity && motion.presentation(for: b, at: 0.15).isIdentity, "reduced fades are short")
    }

    static func bookkeeping() {
        var motion = EaselObjectMotion()
        let kept = UUID(), dropped = UUID(), ghost = box(0, 0)
        motion.appear([kept, dropped], at: 0, reduced: false)
        motion.vanish([ghost], at: 0, reduced: false)
        motion.forget(missing: [kept])
        expect(motion.ids == [kept, ghost.id], "objects that vanish from the document stop animating, ghosts stay")
        motion.forget(missing: [kept, ghost.id])
        expect(motion.ghosts.isEmpty && motion.ids == [kept], "an undone delete drops its ghost")
        motion.cancelAll()
        expect(motion.isEmpty && motion.ghosts.isEmpty, "cancel settles everything")
    }

    static func diffs() {
        let a = box(0, 0), b = box(200, 0, z: 1)
        var moved = a; moved.frame.x = 50
        var arrow = EaselItem(kind: .arrow, frame: EaselRect(x: 0, y: 0, width: 10, height: 10), zIndex: 2)
        arrow.startConnection = EaselConnection(itemID: a.id)
        var shifted = arrow; shifted.frame.x = 40
        let before = document([a, b, arrow])
        let after = document([moved, b, shifted, box(400, 0, z: 3)])
        let moves = EaselObjectMotion.moves(from: before, to: after)
        expect(moves.count == 1 && near(moves[a.id]?.x ?? 0, -50), "moves glide objects back from their old spot, never attached connectors")
        expect(EaselObjectMotion.added(from: before, to: after).count == 1, "added objects are found")
        expect(EaselObjectMotion.removed(from: after, to: before).count == 1, "removed objects are found")
        let copy = box(16, 16)
        let offsets = EaselObjectMotion.copyOffsets(sources: [a.id], copies: [copy.id], before: before, after: document([a, copy]))
        expect(near(offsets[copy.id]?.x ?? 0, -16) && near(offsets[copy.id]?.y ?? 0, -16), "copies glide out of their source")
    }

    static func sample(_ motion: EaselObjectMotion, _ id: UUID, from start: Double, to end: Double) -> [EaselObjectPresentation] {
        stride(from: start, through: end, by: 0.004).map { motion.presentation(for: id, at: $0) }
    }

    static func entrances() {
        let sticky = box(0, 0, kind: .sticky), stamp = box(0, 0, kind: .stamp), shape = box(0, 0, kind: .rectangle)
        let arrow = box(0, 0, kind: .arrow)
        if case .drop(let tilt) = EaselObjectEntrance.of(sticky) { expect(near(abs(tilt), 3), "stickies drop with a 3° tilt") }
        else { expect(false, "stickies drop like paper") }
        if case .slam(let tilt, let raised) = EaselObjectEntrance.of(stamp) { expect(near(abs(tilt), 12) && !raised, "stamps slam with 12° of tilt") }
        else { expect(false, "stamps slam") }
        expect(EaselObjectEntrance.of(shape) == .pop, "shapes pop")
        expect(EaselObjectEntrance.of(arrow) == .fade, "connectors fade in so they can draw themselves")
        expect(EaselObjectEntrance.returning(arrow) == .fade && EaselObjectEntrance.returning(shape) == .quick,
               "undo brings connectors back with a fade and objects with a quick pop")
        expect(!EaselObjectEntrance.cascades(arrow) && EaselObjectEntrance.cascades(shape), "connectors skip the cascade while they draw on")

        var motion = EaselObjectMotion()
        motion.appear([sticky.id: .drop(tilt: 3)], at: 0, reduced: false)
        let first = motion.presentation(for: sticky.id, at: 0)
        expect(near(first.scale, 1.08) && near(first.offset.y, -8) && near(first.rotation, 3) && near(first.shadow, 1), "a sticky starts lifted, higher and tilted")
        let midway = motion.presentation(for: sticky.id, at: 0.12)
        expect(midway.shadow < first.shadow && midway.shadow > 0 && midway.rotation < 3, "the sticky's shadow tightens as it lands")
        expect(motion.presentation(for: sticky.id, at: 0.43).isIdentity, "the sticky ends flat on the board")

        var quick = EaselObjectMotion()
        quick.appear([shape.id: .quick], at: 0, reduced: false)
        expect(near(quick.presentation(for: shape.id, at: 0).scale, 0.92), "undo pops back from 92%")
        expect(quick.presentation(for: shape.id, at: 0.25).isIdentity, "undo pops are quick")

        var reduced = EaselObjectMotion()
        reduced.appear([sticky.id: .drop(tilt: 3), stamp.id: .slam(tilt: 12, raised: false)], at: 0, reduced: true)
        for id in [sticky.id, stamp.id] {
            let shown = reduced.presentation(for: id, at: 0.05)
            expect(near(shown.scale, 1) && near(shown.rotation, 0) && near(shown.offset.y, 0) && near(shown.shadow, 0) && shown.opacity < 1,
                   "Reduce Motion lands stickies and stamps with a fade only")
        }
    }

    static func stampSlam() {
        var motion = EaselObjectMotion()
        let id = UUID()
        motion.appear([id: .slam(tilt: 12, raised: false)], at: 0, reduced: false)
        let first = motion.presentation(for: id, at: 0)
        expect(near(first.scale, 1.6) && near(first.opacity, 0) && near(first.rotation, 12), "a stamp starts big, clear and tilted")
        let shown = sample(motion, id, from: 0, to: 0.36)
        let low = shown.map(\.scale).min() ?? 1
        expect(low > 0.86 && low < 0.94, "the stamp overshoots to about 90% before springing back")
        expect(motion.presentation(for: id, at: 0.08).opacity > 0.99, "the stamp is solid as soon as it hits")
        expect(motion.presentation(for: id, at: 0.37).isIdentity, "the stamp settles at rest")

        var pressed = EaselObjectMotion()
        pressed.raise(id, at: 0, reduced: false)
        expect(pressed.isRaised(id) && !pressed.isEmpty, "a held stamp hovers above the board")
        let hovering = pressed.presentation(for: id, at: 0.5)
        expect(hovering.scale > 1.1 && hovering.opacity < 0.9 && hovering.shadow > 0.5, "the held stamp is raised with a soft shadow")
        pressed.appear([id: .slam(tilt: 4, raised: true)], at: 1, reduced: false)
        expect(!pressed.isRaised(id), "landing ends the hover")
        let landing = pressed.presentation(for: id, at: 1)
        expect(near(landing.scale, 1.15) && near(landing.opacity, 0.8), "a held stamp slams from where it hovered")
        var calm = EaselObjectMotion()
        calm.raise(id, at: 0, reduced: true)
        expect(!calm.isRaised(id), "Reduce Motion never raises the held stamp")
    }

    static func landing() {
        var motion = EaselObjectMotion()
        let id = UUID()
        motion.glide([id: EaselPoint(x: -16, y: -16)], fades: true, lands: true, at: 0, reduced: false)
        let squashed = sample(motion, id, from: 0.16, to: 0.4).map { $0.stretch.x - $0.stretch.y }.max() ?? 0
        expect(squashed > 0.03 && squashed < 0.08, "a duplicate finishes with a small settle squash")
        expect(motion.presentation(for: id, at: 0.46).isIdentity, "the squash ends at rest")

        var turned = EaselObjectMotion()
        turned.glide([:], fades: false, stretches: [id: EaselPoint(x: 2, y: 0.5)], turns: [id: 30], at: 0, reduced: false)
        let start = turned.presentation(for: id, at: 0)
        expect(near(start.scaleX, 2) && near(start.scaleY, 0.5) && near(start.rotation, 30), "a resize or turn glides back from the old shape")
        expect(turned.presentation(for: id, at: 0.46).isIdentity, "resizes settle at the new shape")
    }

    static func pulsing() {
        var motion = EaselObjectMotion()
        let id = UUID()
        motion.pulse([id], at: 0, reduced: false)
        let peak = sample(motion, id, from: 0, to: 0.5).map(\.scale).max() ?? 0
        expect(near(peak, 1.05, 0.002), "an attention pulse swells to 105%")
        expect(motion.presentation(for: id, at: 0.51).isIdentity, "the pulse returns to rest")
        var reduced = EaselObjectMotion()
        reduced.pulse([id], at: 0, reduced: true)
        expect(reduced.isEmpty, "Reduce Motion skips the pulse scale")
    }

    static func shaking() {
        var motion = EaselObjectMotion()
        let id = UUID()
        motion.shake([id], at: 0, reduced: false)
        let shown = sample(motion, id, from: 0, to: 0.3).map(\.offset.x)
        expect((shown.map(abs).max() ?? 0) <= 4 && (shown.map(abs).max() ?? 0) > 2.5, "a locked object shakes about 4 points sideways")
        var swings = 0
        for (a, b) in zip(shown, shown.dropFirst()) where (a < 0) != (b < 0) && abs(a - b) > 1e-9 { swings += 1 }
        expect(swings >= 4 && swings <= 6, "the shake swings back and forth three times")
        expect(motion.presentation(for: id, at: 0.31).isIdentity, "the shake ends where it started")
        var reduced = EaselObjectMotion()
        reduced.shake([id], at: 0, reduced: true)
        expect(reduced.isEmpty, "Reduce Motion skips the shake")
    }

    static func restyling() {
        var motion = EaselObjectMotion()
        let old = box(0, 0, kind: .rectangle)
        motion.restyle([old], at: 0, reduced: false)
        expect(motion.previousLook(for: old.id) == old, "a restyle keeps the old look while it fades")
        let middle = motion.presentation(for: old.id, at: 0.075)
        expect(middle.opacity > 0.3 && middle.opacity < 0.7 && near(middle.scale, 1), "the new look cross-fades in place")
        motion.prune(at: 0.16)
        expect(motion.previousLook(for: old.id) == nil && motion.isEmpty, "the old look is dropped when the fade ends")
        var twice = EaselObjectMotion()
        var middle1 = old; middle1.color = "#FF0000"
        twice.restyle([old], at: 0, reduced: false)
        let before = twice.fadingLooks(for: old.id, at: 0.06), shownBefore = twice.presentation(for: old.id, at: 0.06).opacity
        twice.restyle([middle1], at: 0.06, reduced: false)
        let after = twice.fadingLooks(for: old.id, at: 0.06), shownAfter = twice.presentation(for: old.id, at: 0.06).opacity
        expect(near(after.first { $0.item == old }?.weight ?? 0, before.first?.weight ?? 1, 1e-9), "a second restyle keeps the first look exactly as visible")
        expect(near(after.first { $0.item == middle1 }?.weight ?? 0, shownBefore, 1e-9) && near(shownAfter, 0),
               "the half-faded look carries its opacity instead of popping")
        expect(near(after.reduce(0) { $0 + $1.weight } + shownAfter, 1, 1e-9), "the cross-fade weights always add up to a solid object")
        let later = twice.fadingLooks(for: old.id, at: 0.15).reduce(0) { $0 + $1.weight } + twice.presentation(for: old.id, at: 0.15).opacity
        expect(near(later, 1, 1e-9), "the stacked fade stays solid while it runs")
        for step in 1...6 {
            var next = old; next.color = "#00000\(step)"
            twice.restyle([next], at: 0.06 + Double(step) * 0.01, reduced: false)
        }
        expect(twice.fadingLooks(for: old.id, at: 0.12).count <= EaselObjectMotion.fadingLookLimit, "rapid restyles keep at most three looks")
        twice.prune(at: 0.4)
        expect(twice.isEmpty && twice.fadingLooks(for: old.id, at: 0.4).isEmpty, "stacked looks are dropped when the fade ends")
        var reduced = EaselObjectMotion()
        reduced.restyle([old], at: 0, reduced: true)
        expect(reduced.previousLook(for: old.id) != nil, "Reduce Motion still cross-fades restyles")
    }

    static func carrying() {
        expect(near(EaselCarryTilt.target(forPointerSpeed: 100_000), 5) && near(EaselCarryTilt.target(forPointerSpeed: -100_000), -5),
               "tilt never passes 5°")
        expect(EaselCarryTilt.target(forPointerSpeed: 300) > 0 && EaselCarryTilt.target(forPointerSpeed: -300) < 0, "tilt follows the pointer's direction")
        var tilt = EaselCarryTilt()
        for _ in 0..<60 { tilt.step(by: 1.0 / 60.0, toward: 5) }
        expect(abs(tilt.angle - 5) < 0.3, "tilt springs to its target")
        for _ in 0..<90 { tilt.step(by: 1.0 / 60.0, toward: 0) }
        expect(tilt.isResting, "tilt levels out again")

        let sticky = UUID(), card = UUID(), page = UUID()
        var motion = EaselObjectMotion()
        motion.pickUp([sticky, card, page], tilting: [sticky], shadowOnly: [page], at: 0, reduced: false)
        for step in 1...30 {
            motion.carry?.pointer(speed: 2_000, at: 0.05 + Double(step) / 60)
            motion.carry?.advance(to: 0.05 + Double(step) / 60)
        }
        let lifted = motion.presentation(for: sticky, at: 0.5)
        expect(lifted.scale > 1.02 && lifted.scale < 1.03 && lifted.shadow > 0.9, "picked-up objects lift to 102.5% with a shadow")
        expect(near(motion.presentation(for: card, at: 0.5).rotation, 0), "only stickies and stamps tilt")
        expect(lifted.rotation > 3 && lifted.rotation <= 5.5, "a sticky tilts up to 5° while dragged briskly")
        let pageShown = motion.presentation(for: page, at: 0.5)
        expect(near(pageShown.scale, 1) && pageShown.shadow > 0.9, "live page cards only get the shadow")
        var still = motion
        for step in 1...60 { still.carry?.advance(to: 0.6 + Double(step) / 60) }
        expect(abs(still.presentation(for: sticky, at: 1.6).rotation) < 0.3, "a still pointer levels the sticky")
        let landed = motion.drop(at: 0.6)
        expect(landed == [sticky, card, page] && motion.carry == nil, "dropping ends the carry")
        let touchdown = motion.presentation(for: card, at: 0.6)
        expect(touchdown.scale > 1.02 && touchdown.shadow > 0.9, "the landing starts from the lifted look")
        let squash = sample(motion, card, from: 0.6, to: 1.0).map { $0.stretch.x - $0.stretch.y }.max() ?? 0
        expect(squash > 0.02, "landing gives a tiny squash")
        expect(motion.presentation(for: card, at: 1.03).isIdentity, "the landing settles at rest")
        var reduced = EaselObjectMotion()
        reduced.pickUp([card], tilting: [], shadowOnly: [], at: 0, reduced: true)
        expect(reduced.carry == nil, "Reduce Motion never lifts")
    }

    static func cascading() {
        let centre = UUID(), near1 = UUID(), far = UUID()
        let delays = EaselObjectMotion.cascade([
            centre: EaselRect(x: 300, y: 100, width: 100, height: 100),
            near1: EaselRect(x: 150, y: 100, width: 100, height: 100),
            far: EaselRect(x: 0, y: 100, width: 100, height: 100),
            UUID(): EaselRect(x: 600, y: 100, width: 100, height: 100),
        ])
        expect((delays[centre] ?? 1) < (delays[near1] ?? 0) && (delays[near1] ?? 1) < (delays[far] ?? 0), "the cascade spreads from the centre")
        expect(delays.values.allSatisfy { $0 >= 0 && $0 <= 0.25 }, "the whole cascade stays within 0.25 seconds")
        var many: [UUID: EaselRect] = [:]
        for index in 0..<60 { many[UUID()] = EaselRect(x: Double(index * 40), y: 0, width: 30, height: 30) }
        expect((EaselObjectMotion.cascade(many).values.max() ?? 1) <= 0.25, "big groups still finish within 0.25 seconds")
        expect(EaselObjectMotion.cascade([centre: EaselRect(x: 0, y: 0, width: 10, height: 10)])[centre] == 0, "a single object pops at once")

        var motion = EaselObjectMotion()
        motion.appear([far: .pop], delays: [far: 0.1], at: 0, reduced: false)
        expect(near(motion.presentation(for: far, at: 0.05).opacity, 0), "a delayed pop waits hidden")
        expect(motion.presentation(for: far, at: 0.53).isIdentity, "a delayed pop still lands")
        var reduced = EaselObjectMotion()
        reduced.appear([far: .pop], delays: [far: 0.2], at: 0, reduced: true)
        expect(reduced.presentation(for: far, at: 0.15).isIdentity, "Reduce Motion drops the stagger")

        var unfolding = EaselObjectMotion()
        let shallow = UUID(), deep = UUID()
        unfolding.glide([shallow: EaselPoint(x: -60, y: 0), deep: EaselPoint(x: -120, y: 0)], fades: true,
                        delays: [deep: 0.12], at: 0, reduced: false)
        expect(unfolding.presentation(for: shallow, at: 0.06).offset.x > -60, "the first topic starts gliding at once")
        expect(near(unfolding.presentation(for: deep, at: 0.06).offset.x, -120), "a deeper topic waits on its parent")
        expect(unfolding.presentation(for: deep, at: 0.2).offset.x > -120, "the deeper topic follows after its delay")
        expect(unfolding.presentation(for: deep, at: 0.58).isIdentity && !unfolding.presentation(for: deep, at: 0.5).isIdentity,
               "a delayed glide still runs its full length")
        var calm = EaselObjectMotion()
        calm.glide([deep: EaselPoint(x: -120, y: 0)], fades: true, delays: [deep: 0.12], at: 0, reduced: true)
        expect(calm.presentation(for: deep, at: 0.151).isIdentity, "Reduce Motion drops glide delays")
    }

    static func history() {
        let kept = box(0, 0, kind: .rectangle, z: 0), moved = box(200, 0, kind: .rectangle, z: 1)
        let typed = box(400, 0, kind: .text, z: 2), styled = box(600, 0, kind: .rectangle, z: 3)
        let gone = box(800, 0, z: 4), turned = box(1000, 0, kind: .rectangle, z: 5)
        var movedAfter = moved; movedAfter.frame = EaselRect(x: 250, y: 0, width: 200, height: 100)
        var typedAfter = typed; typedAfter.text = "Hello"
        var styledAfter = styled; styledAfter.color = "#FF0000"
        var turnedAfter = turned; turnedAfter.rotation = 350
        let fresh = box(0, 400, z: 6)
        let before = document([kept, moved, typed, styled, gone, turned])
        let after = document([kept, movedAfter, typedAfter, styledAfter, turnedAfter, fresh])
        let change = EaselObjectMotion.history(from: before, to: after)
        expect(change.added == [fresh.id], "undo finds objects that come back")
        expect(change.removed.map(\.id) == [gone.id], "undo finds objects that leave")
        expect(near(change.offsets[moved.id]?.x ?? 0, -100) && near(change.stretches[moved.id]?.x ?? 0, 0.5), "moved and resized objects glide back from their old frame")
        expect(near(change.turns[turned.id] ?? 0, 10), "turns take the short way round")
        expect(change.restyled.map(\.id) == [styled.id] && change.restyled.first?.color == styled.color, "restyles keep the old look to fade from")
        expect(change.offsets[typed.id] == nil && !change.restyled.contains { $0.id == typed.id }, "typing undo stays instant")
        expect(EaselObjectMotion.history(from: before, to: before).isEmpty, "an unchanged board has nothing to animate")
        expect(EaselObjectMotion.restyled(from: before, to: after).map(\.id).contains(styled.id), "restyle commands find their changed look")
        expect(!EaselObjectMotion.restyled(from: before, to: after).contains { $0.id == typed.id }, "typing is never a restyle")
    }

    static func stampHold() {
        expect(near(EaselStampGrowth.side(from: 64, to: 96, since: 0, reduced: false), 64), "a growth stage starts from the shown size")
        let sizes = stride(from: 0.0, through: 0.5, by: 0.005).map { EaselStampGrowth.side(from: 64, to: 96, since: $0, reduced: false) }
        expect((sizes.max() ?? 0) > 97 && (sizes.max() ?? 0) < 102, "each growth stage pops past its size")
        expect(abs((sizes.last ?? 0) - 96) < 0.5, "the stage settles at its size")
        expect(near(EaselStampGrowth.side(from: 64, to: 96, since: 0.01, reduced: true), 96), "Reduce Motion jumps between sizes")
        let breaths = stride(from: 0.4, through: 1.6, by: 0.01).map { EaselObjectMotion.raisedPresentation(since: $0).scale }
        let swing = (breaths.max() ?? 0) - (breaths.min() ?? 0)
        expect(swing > 0.02 && swing < 0.05, "the held stamp breathes gently")
    }

    static func wheel() {
        let first = EaselStampWheelMotion.fan(slot: 0, elapsed: 0.01), late = EaselStampWheelMotion.fan(slot: 7, elapsed: 0.01)
        expect(first.opacity > 0 && late.opacity == 0, "wheel faces fan out one after another")
        expect(EaselStampWheelMotion.duration(count: 12) < 0.7, "the fan is quick")
        let settled = EaselStampWheelMotion.fan(slot: 7, elapsed: 2)
        expect(near(settled.reach, 1, 1e-3) && near(settled.scale, 1, 1e-3) && near(settled.opacity, 1), "faces end in their slots")
        let tucked = EaselStampWheelMotion.tucked(settled, elapsed: EaselStampWheelMotion.tuck)
        expect(near(tucked.opacity, 0) && tucked.reach < 1, "the wheel tucks away")
        let flown = EaselStampWheelMotion.flight(elapsed: EaselStampWheelMotion.tuck)
        expect(near(flown.travel, 1) && flown.scale < 1, "the picked face flies to the pointer")
    }

    static func bursts() {
        let confetti = EaselBurstPlan.confetti(width: 64, height: 64, seed: 7)
        expect((6...8).contains(confetti.count), "a stamp throws six to eight specks")
        expect(confetti == EaselBurstPlan.confetti(width: 64, height: 64, seed: 7), "speck plans are deterministic")
        expect(confetti.allSatisfy { $0.distance > 32 && $0.size >= 3 }, "specks land outside the stamp")
        let angles = confetti.map(\.angle).sorted()
        expect(zip(angles, angles.dropFirst()).allSatisfy { $1 - $0 > 0.2 }, "specks spread all the way round")
        let puff = EaselBurstPlan.puff(width: 100, height: 40, seed: 3)
        expect((5...6).contains(puff.count) && puff.allSatisfy { $0.size >= 7 }, "a poof puffs a few soft specks")
        expect(EaselBurstPlan.perCommand == 8, "bursts play for at most eight objects")
    }

    static func foldAnchors() {
        let root = UUID(), left = UUID(), right = UUID(), leftChild = UUID(), leftGrandchild = UUID(), rightChild = UUID()
        var tree = EaselMindMapTree()
        let parents: [UUID: UUID?] = [root: nil, left: root, right: root, leftChild: left, leftGrandchild: leftChild, rightChild: right]
        for (id, parent) in parents { tree.nodes[id] = EaselMindMapTree.Node(id: id, parent: parent) }
        let folded: Set<UUID> = [left, right]
        expect(tree.foldAnchor(of: leftChild, among: folded) == left, "a topic folds into its own branch")
        expect(tree.foldAnchor(of: leftGrandchild, among: folded) == left, "deep topics fold into the branch they belong to")
        expect(tree.foldAnchor(of: rightChild, among: folded) == right, "the other branch keeps its own topics")
        expect(tree.foldAnchor(of: left, among: folded) == nil, "a folded branch never anchors to itself")
        expect(tree.foldAnchor(of: UUID(), among: folded) == nil, "unknown topics fall back to the nearest branch")
        let siblings: Set<UUID> = [leftChild, right]
        expect(tree.foldAnchor(of: leftGrandchild, among: siblings) == leftChild, "the nearest folded ancestor wins")
    }
}
