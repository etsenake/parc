import Foundation

@main
struct EaselArrangeTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-6 }

    static func box(_ x: Double, _ y: Double, _ width: Double = 100, _ height: Double = 100,
                    kind: EaselItemKind = .sticky, z: Int = 0) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: width, height: height), zIndex: z)
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Board", createdAt: Date(timeIntervalSince1970: 0),
                      modifiedAt: Date(timeIntervalSince1970: 0), items: items)
    }

    static func frame(_ document: EaselDocument?, _ id: UUID) -> EaselRect? {
        document?.items.first { $0.id == id }?.frame
    }

    static func main() {
        alignment()
        distribution()
        tidying()
        layering()
        grouping()
        locking()
        duplication()
        pastePlacement()
        clipboard()
        selectionRules()
        chords()
        print("EaselArrangeTests passed")
    }

    static func alignment() {
        let a = box(10, 10), b = box(200, 50, 50, 50), c = box(90, 300, 300, 20)
        let board = document([a, b, c])
        let ids: Set<UUID> = [a.id, b.id, c.id]
        let left = EaselArrange.aligned(board, ids: ids, to: .left)
        expect([a, b, c].allSatisfy { frame(left, $0.id)?.x == 10 }, "Align Left lines every object up with the leftmost edge")
        let right = EaselArrange.aligned(board, ids: ids, to: .right)
        expect([a, b, c].allSatisfy { frame(right, $0.id).map { near($0.x + $0.width, 390) } == true }, "Align Right uses the rightmost edge")
        let center = EaselArrange.aligned(board, ids: ids, to: .center)
        expect([a, b, c].allSatisfy { frame(center, $0.id).map { near($0.x + $0.width / 2, 200) } == true }, "Align Center centres on the selection")
        let bottom = EaselArrange.aligned(board, ids: ids, to: .bottom)
        expect([a, b, c].allSatisfy { frame(bottom, $0.id).map { near($0.y + $0.height, 320) } == true }, "Align Bottom uses the lowest edge")
        let middle = EaselArrange.aligned(board, ids: ids, to: .middle)
        expect([a, b, c].allSatisfy { frame(middle, $0.id).map { near($0.y + $0.height / 2, 165) } == true }, "Align Middle centres vertically")
        expect(frame(EaselArrange.aligned(board, ids: ids, to: .top), c.id)?.y == 10, "Align Top uses the highest edge")
        expect(EaselArrange.aligned(board, ids: [a.id], to: .left) == nil, "One object has nothing to align to")

        var g1 = box(0, 0), g2 = box(150, 100)
        let group = UUID()
        g1.groupID = group; g2.groupID = group
        let loose = box(400, 400)
        let grouped = document([g1, g2, loose])
        let moved = EaselArrange.aligned(grouped, ids: [g1.id, g2.id, loose.id], to: .right)
        expect(frame(moved, g1.id)?.x == 250 && frame(moved, g2.id)?.x == 400, "A whole group aligns as one block and keeps its shape")
        expect(frame(moved, loose.id)?.x == 400, "The object with the rightmost edge stays put")

        var locked = box(500, 0); locked.locked = true
        let withLock = document([a, b, locked])
        let lockedResult = EaselArrange.aligned(withLock, ids: [a.id, b.id, locked.id], to: .left)
        expect(frame(lockedResult, locked.id)?.x == 500, "Locked objects never move when aligning")
        expect(frame(lockedResult, b.id)?.x == 10, "Locked objects don't count towards the alignment edge")

        var arrow = EaselItem(kind: .arrow, frame: EaselRect(x: 300, y: 300, width: 50, height: 50),
                              points: [EaselPoint(x: 0, y: 0), EaselPoint(x: 50, y: 50)])
        arrow.startConnection = EaselConnection(itemID: a.id)
        let connected = document([a, b, arrow])
        let skipped = EaselArrange.aligned(connected, ids: [a.id, b.id, arrow.id], to: .left)
        expect(frame(skipped, arrow.id)?.x == 300, "Connected arrows follow their objects instead of aligning on their own")
        var bent = box(400, 400, 10, 10, kind: .arrow)
        bent.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 10, y: 10)]
        bent.waypoints = [EaselPoint(x: 405, y: 450)]
        let bentResult = EaselArrange.aligned(document([a, bent]), ids: [a.id, bent.id], to: .left)
        expect(bentResult?.items.first { $0.id == bent.id }?.waypoints == [EaselPoint(x: 15, y: 450)], "Manual bends travel with a free arrow")
    }

    static func distribution() {
        let a = box(0, 0, 100), b = box(130, 0, 20), c = box(500, 0, 60)
        let board = document([c, a, b])
        let result = EaselArrange.distributed(board, ids: [a.id, b.id, c.id], along: .horizontal)
        guard let fa = frame(result, a.id), let fb = frame(result, b.id), let fc = frame(result, c.id) else {
            failTest("Distribute returns every object")
        }
        let gap1 = fb.x - (fa.x + fa.width), gap2 = fc.x - (fb.x + fb.width)
        expect(near(gap1, gap2) && near(gap1, 190), "Distribute leaves equal gaps between neighbours")
        expect(fa.x == 0 && fc.x == 500, "The outermost objects stay where they are")
        expect(EaselArrange.distributed(board, ids: [a.id, b.id], along: .horizontal) == nil, "Distributing needs three objects")
        let tall = document([box(0, 0, 10, 10), box(0, 15, 10, 50), box(0, 300, 10, 10)])
        let ids = Set(tall.items.map(\.id))
        let vertical = EaselArrange.distributed(tall, ids: ids, along: .vertical)
        let ys = vertical?.items.map(\.frame.y) ?? []
        expect(ys.count == 3 && near(ys[1], 130), "Vertical distribution spaces rows evenly")
    }

    static func tidying() {
        let a = box(0, 0), b = box(300, 10), c = box(10, 300), d = box(320, 290)
        let board = document([d, c, b, a])
        let tidy = EaselArrange.tidied(board, ids: [a.id, b.id, c.id, d.id])
        expect(frame(tidy, a.id).map { $0.x == 0 && $0.y == 0 } == true, "Tidy up starts the grid at the selection's corner")
        expect(frame(tidy, b.id).map { $0.x == 124 && $0.y == 0 } == true, "Tidy up keeps the row order and spaces cells evenly")
        expect(frame(tidy, c.id).map { $0.x == 0 && $0.y == 124 } == true, "Tidy up starts a new row for the next row of objects")
        expect(frame(tidy, d.id).map { $0.x == 124 && $0.y == 124 } == true, "Tidy up fills the grid in reading order")
        let pile = document((0..<9).map { box(Double($0) * 5, Double($0) * 3) })
        let piled = EaselArrange.tidied(pile, ids: Set(pile.items.map(\.id)))
        let xs = Set(piled?.items.map(\.frame.x) ?? []), ys = Set(piled?.items.map(\.frame.y) ?? [])
        expect(xs.count == 3 && ys.count == 3, "A messy pile tidies into a square grid")
        let arrow = box(600, 600, 10, 10, kind: .arrow)
        expect(!EaselArrange.canTidy([a.id, b.id, arrow.id], in: document([a, b, arrow])), "Connectors don't count towards Tidy up")
        expect(EaselArrange.canTidy([a.id, b.id, c.id], in: board), "Three stickies can be tidied")
    }

    static func layering() {
        let a = box(0, 0, z: 1), b = box(50, 50, z: 2), c = box(500, 500, z: 3), d = box(60, 60, z: 4)
        let board = document([a, b, c, d])
        func order(_ document: EaselDocument?) -> [UUID] { document.map { EaselArrange.paintOrder($0).map(\.id) } ?? [] }
        expect(order(EaselArrange.layered(board, ids: [a.id], .front)) == [b.id, c.id, d.id, a.id], "Bring to Front puts the selection on top")
        expect(order(EaselArrange.layered(board, ids: [d.id], .back)) == [d.id, a.id, b.id, c.id], "Send to Back puts the selection at the bottom")
        expect(order(EaselArrange.layered(board, ids: [a.id], .forward)) == [b.id, a.id, c.id, d.id], "Bring Forward steps over the next overlapping object")
        expect(order(EaselArrange.layered(board, ids: [b.id], .forward)) == [a.id, c.id, d.id, b.id], "Bring Forward skips objects it doesn't touch")
        expect(EaselArrange.layered(board, ids: [c.id], .forward) == nil, "Nothing overlapping above means nothing changes")
        expect(order(EaselArrange.layered(board, ids: [d.id], .backward)) == [a.id, d.id, b.id, c.id], "Send Backward steps under the next overlapping object")
        let renumbered = EaselArrange.layered(board, ids: [a.id], .front)
        expect(renumbered.map { Set($0.items.map(\.zIndex)).count == 4 } == true, "Layer moves leave every object a distinct order")
        let huge = document([box(0, 0, z: Int.max), box(10, 10, z: Int.max - 1), box(20, 20, z: Int.min)])
        let overflow = EaselArrange.layered(huge, ids: [huge.items[2].id], .front)
        expect(overflow.map { EaselArrange.paintOrder($0).last?.id == huge.items[2].id } == true, "Extreme orders renumber instead of overflowing")
        var locked = box(0, 0, z: 9); locked.locked = true
        expect(EaselArrange.layered(document([a, locked]), ids: [locked.id], .back) == nil, "Locked objects keep their place in the stack")
        var g1 = box(0, 0, z: 1), g2 = box(10, 10, z: 3)
        let group = UUID(); g1.groupID = group; g2.groupID = group
        let between = box(5, 5, z: 2), top = box(20, 20, z: 4)
        let groupBoard = document([g1, g2, between, top])
        expect(order(EaselArrange.layered(groupBoard, ids: [g1.id, g2.id], .front)) == [between.id, top.id, g1.id, g2.id],
               "A group moves through the stack together and keeps its own order")
        var stuck = box(55, 55, 10, 10, kind: .freehand, z: 3)
        stuck.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 10, y: 10)]
        stuck.attachedTo = b.id
        let stuckBoard = document([a, b, stuck, c, box(60, 60, z: 5)])
        let raised = order(EaselArrange.layered(stuckBoard, ids: [b.id], .front))
        expect(raised.suffix(2) == [b.id, stuck.id], "Things stuck on an object come along to the front and stay on top of it")
    }

    static func grouping() {
        let a = box(0, 0), b = box(200, 0), c = box(400, 0)
        let board = document([a, b, c])
        let id = UUID()
        guard let grouped = EaselArrange.grouped(board, ids: [a.id, b.id], groupID: id) else { failTest("Two objects group") }
        expect(grouped.items.filter { $0.groupID == id }.count == 2, "Grouping tags every chosen object")
        expect(!EaselArrange.canGroup([a.id, b.id], in: grouped), "A whole group can't be grouped with itself")
        expect(EaselArrange.wholeGroup([a.id, b.id], in: grouped) == id, "The members of one group read as that group")
        expect(EaselArrange.expandingGroups([a.id], in: grouped) == [a.id, b.id], "Picking one member reaches the whole group")
        let outer = UUID()
        guard let nested = EaselArrange.grouped(grouped, ids: [a.id, b.id, c.id], groupID: outer) else { failTest("Groups regroup") }
        expect(nested.items.allSatisfy { $0.groupID == outer }, "Grouping grouped objects puts them all in the new group")
        guard let partial = EaselArrange.grouped(grouped, ids: [b.id, c.id], groupID: outer) else { failTest("Partial regroup") }
        expect(partial.items.first { $0.id == a.id }?.groupID == nil, "A group left with one member dissolves")
        guard let ungrouped = EaselArrange.ungrouped(grouped, ids: [a.id]) else { failTest("Ungroup works from one member") }
        expect(ungrouped.items.allSatisfy { $0.groupID == nil }, "Ungroup frees every member of the group")
        expect(EaselArrange.ungrouped(board, ids: [a.id]) == nil, "Ungrouping a loose object changes nothing")
        expect(EaselArrange.sharedGroup([a.id], in: grouped) == id && EaselArrange.sharedGroup([a.id, c.id], in: grouped) == nil,
               "Shift-Return finds the group shared by the selection")
    }

    static func locking() {
        let a = box(0, 0), b = box(10, 10)
        let board = document([a, b])
        guard let locked = EaselArrange.settingLock(true, ids: [a.id], in: board) else { failTest("Locking changes the board") }
        expect(locked.items.first { $0.id == a.id }?.locked == true, "Lock marks the object")
        expect(EaselArrange.shouldLock([a.id, b.id], in: locked), "A mixed selection locks")
        expect(!EaselArrange.shouldLock([a.id], in: locked), "An all-locked selection unlocks")
        let unlocked = EaselArrange.settingLock(false, ids: [a.id], in: locked)
        expect(unlocked?.items.first { $0.id == a.id }?.locked == nil, "Unlocking leaves the field out of the file")
        expect(EaselArrange.settingLock(false, ids: [b.id], in: board) == nil, "Unlocking an unlocked object changes nothing")
        expect(!EaselArrange.canAlign([a.id, b.id], in: locked), "One movable object left means nothing to align")
        expect(!EaselArrange.canGroup([a.id, b.id], in: locked), "Locked objects stay out of new groups")
    }

    static func duplication() {
        var a = box(0, 0, z: 3), b = box(200, 0, z: 1)
        let group = UUID(); a.groupID = group; b.groupID = group
        let outside = box(600, 600, z: 2)
        var inner = EaselItem(kind: .arrow, frame: EaselRect(x: 100, y: 50, width: 100, height: 1), zIndex: 4,
                              points: [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0)])
        inner.startConnection = EaselConnection(itemID: a.id, side: .right)
        inner.endConnection = EaselConnection(itemID: outside.id)
        inner.waypoints = [EaselPoint(x: 150, y: 80)]
        var sticker = box(10, 10, 20, 20, kind: .image, z: 5)
        sticker.attachedTo = a.id
        var stray = box(700, 700, 20, 20, kind: .image, z: 6)
        stray.attachedTo = outside.id
        let board = document([a, b, outside, inner, sticker, stray])
        let ids: Set<UUID> = [a.id, b.id, inner.id, sticker.id, stray.id]
        guard let result = EaselArrange.duplicating(ids, in: board) else { failTest("Duplicate returns copies") }
        let copies = result.document.items.filter { result.copies.contains($0.id) }
        expect(copies.count == 5 && Set(result.document.items.map(\.id)).count == 11, "Every copy gets a fresh, unique ID")
        let copiedGroups = Set(copies.compactMap(\.groupID))
        expect(copiedGroups.count == 1 && !copiedGroups.contains(group), "A whole group's copy becomes a new group of its own")
        let copyA = copies.first { $0.frame.x == 24 && $0.frame.y == 24 && $0.kind == .sticky }
        let copyArrow = copies.first { $0.kind == .arrow }
        expect(copyArrow?.startConnection?.itemID == copyA?.id && copyArrow?.startConnection?.side == .right,
               "Connections inside the copied set point at the copies")
        expect(copyArrow?.endConnection == nil, "Connections to objects outside the copy are dropped")
        expect(copyArrow?.waypoints == [EaselPoint(x: 174, y: 104)], "Bends move with the copy")
        expect(copies.first { $0.frame.x == 34 }?.attachedTo == copyA?.id, "Sticky-ons follow the copied object")
        expect(copies.first { $0.frame.x == 724 }?.attachedTo == nil, "Sticky-ons let go of objects that weren't copied")
        let topCopies = copies.map(\.zIndex).min() ?? 0
        expect(topCopies > board.items.map(\.zIndex).max() ?? 0, "Copies land on top of the board")
        expect(copies.sorted { $0.zIndex < $1.zIndex }.first?.frame.x == 224, "Copies keep the stacking order of their originals")
        guard let partial = EaselArrange.duplicating([a.id], in: board) else { failTest("Duplicating one member works") }
        expect(partial.document.items.first { partial.copies.contains($0.id) && $0.kind == .sticky }?.groupID == group,
               "Duplicating inside a group grows that group")
        expect(partial.copies.count == 2 && partial.document.items.contains { partial.copies.contains($0.id) && $0.kind == .image },
               "Duplicating an object brings what's stuck to it")
        let offset = EaselArrange.repeatOffset(sources: [a.id], copies: [b.id], in: board)
        expect(offset == EaselPoint(x: 200, y: 0), "Repeating a duplicate reuses the last step")
        expect(EaselArrange.repeatOffset(sources: [a.id], copies: [UUID()], in: board) == nil, "A missing copy forgets the step")
        let copiedLocked = EaselArrange.duplicating([a.id], in: EaselArrange.settingLock(true, ids: [a.id], in: board) ?? board)
        expect(copiedLocked != nil, "Locked objects can still be duplicated")
        expect(EaselArrange.axisLocked(EaselPoint(x: 30, y: -10), when: true) == EaselPoint(x: 30, y: 0)
               && EaselArrange.axisLocked(EaselPoint(x: 3, y: -10), when: true) == EaselPoint(x: 0, y: -10)
               && EaselArrange.axisLocked(EaselPoint(x: 3, y: -10), when: false) == EaselPoint(x: 3, y: -10),
               "Shift-drag keeps only the dominant direction")
    }

    static func pastePlacement() {
        let content = EaselRect(x: 100, y: 100, width: 200, height: 100)
        let viewport = EaselRect(x: 0, y: 1000, width: 800, height: 600)
        expect(EaselArrange.pasteOffset(content: content, anchor: .pointer(EaselPoint(x: 500, y: 400)), viewport: viewport)
               == EaselPoint(x: 300, y: 250), "Paste centres on the pointer")
        expect(EaselArrange.pasteOffset(content: content, anchor: .pointer(EaselPoint(x: 10, y: 10)), viewport: viewport)
               == EaselPoint(x: -100, y: -100), "Paste near the edge never goes off the board")
        expect(EaselArrange.pasteOffset(content: content, anchor: .source(step: 2), viewport: viewport) == EaselPoint(x: 48, y: 48),
               "Repeated paste steps 24 points each time")
        expect(EaselArrange.pasteOffset(content: content, anchor: .inPlace, viewport: viewport) == EaselPoint(x: 0, y: 0),
               "Paste after cut lands where it was")
        expect(EaselArrange.pasteOffset(content: content, anchor: .viewport, viewport: viewport) == EaselPoint(x: 200, y: 1150),
               "Without a pointer or source, paste lands in the middle of the view")
    }

    static func clipboard() {
        var a = box(0, 0, kind: .image, z: 2), b = box(200, 0, z: 1)
        a.assetID = "11111111-1111-1111-1111-111111111111.png"
        let group = UUID(); a.groupID = group; b.groupID = group
        var c = box(400, 0, z: 3)
        let other = UUID(); c.groupID = other
        let d = box(600, 0, z: 4)
        var e = d; e.id = UUID(); e.groupID = other
        let board = document([a, b, c, e])
        let bytes = Data([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3])
        expect(EaselClipboardPayload.assetIDs(of: [a.id, b.id], in: board) == [a.assetID ?? ""], "Copy knows which pictures to bring")
        expect((try? EaselClipboardPayload.capturing([a.id], in: board, assets: [:])) == nil, "Copy refuses when a picture can't be read")
        guard let payload = try? EaselClipboardPayload.capturing([a.id, b.id, c.id], in: board, assets: [a.assetID ?? "": bytes]) else {
            failTest("Copy captures the selection")
        }
        expect(payload.items.map(\.id) == [b.id, a.id, c.id], "Copied objects keep their stacking order")
        expect(payload.items.first { $0.id == c.id }?.groupID == nil, "A group that wasn't copied whole lets its member go")
        expect(payload.items.first { $0.id == a.id }?.groupID == group, "A whole group travels as a group")
        expect(payload.assets == [a.assetID ?? "": bytes] && payload.documentID == board.id, "Image bytes and the source Easel ride along")
        guard let data = try? payload.encoded(), let decoded = try? EaselClipboardPayload.decoded(data) else {
            failTest("The payload survives the pasteboard")
        }
        expect(decoded == payload, "Decoding gives back exactly what was copied")
        expect((try? EaselClipboardPayload.decoded(Data("nonsense".utf8))) == nil, "Junk on the pasteboard is refused")
        var broken = payload
        broken.assets = [:]
        expect((try? broken.validate()) == nil, "A payload missing its image bytes is refused")
        var future = payload
        future.version = 99
        expect((try? EaselClipboardPayload.decoded(future.encoded())) == nil, "A newer payload version is refused rather than misread")
        guard let pasted = EaselArrange.appending(payload.items, to: board, offset: EaselPoint(x: 10, y: 10)) else {
            failTest("Pasting appends copies")
        }
        let copies = pasted.document.items.filter { pasted.copies.contains($0.id) }
        expect(Set(copies.compactMap(\.groupID)).count == 1 && !copies.contains { $0.groupID == group },
               "Pasted groups get a group of their own")
        expect(copies.count == 3 && Set(pasted.document.items.map(\.id)).count == 7, "Pasting never reuses an ID")
        expect(EaselArrange.duplicating([d.id], in: document([d])) != nil, "A lone object duplicates")
    }

    static func selectionRules() {
        let group = UUID()
        var a = box(0, 0), b = box(200, 0), locked = box(400, 0)
        a.groupID = group; b.groupID = group; locked.groupID = group; locked.locked = true
        let loose = box(600, 0)
        let board = document([a, b, locked, loose])
        let click = EaselArrange.clickSelection(hit: a, selection: [], entered: nil, extending: false, clickCount: 1, in: board)
        expect(click.selection == [a.id, b.id] && !click.enteredByClick, "A click picks the group's unlocked members")
        let enter = EaselArrange.clickSelection(hit: b, selection: click.selection, entered: nil, extending: false, clickCount: 2, in: board)
        expect(enter.selection == [b.id] && enter.enteredGroup == group && enter.enteredByClick, "Double-click opens the group on one member")
        let inside = EaselArrange.clickSelection(hit: a, selection: enter.selection, entered: group, extending: true, clickCount: 1, in: board)
        expect(inside.selection == [a.id, b.id] && inside.enteredGroup == group, "Inside an open group Shift-click adds single members")
        let leave = EaselArrange.clickSelection(hit: loose, selection: inside.selection, entered: group, extending: false, clickCount: 1, in: board)
        expect(leave.selection == [loose.id] && leave.enteredGroup == nil, "Clicking outside closes the group")
        let stale = EaselArrange.clickSelection(hit: a, selection: [loose.id], entered: group, extending: false, clickCount: 1, in: board)
        expect(stale.selection == [a.id, b.id], "A group left long ago is closed again when nothing in it is selected")
        let unlocking = EaselArrange.clickSelection(hit: locked, selection: [], entered: nil, extending: true, clickCount: 1, in: board)
        expect(unlocking.selection == [a.id, b.id, locked.id], "Shift-clicking a locked member picks it along with its group for unlocking")
        let toggled = EaselArrange.clickSelection(hit: a, selection: [a.id, b.id], entered: nil, extending: true, clickCount: 1, in: board)
        expect(toggled.selection.isEmpty, "Shift-click on a selected group drops the whole group")
        let swept = EaselArrange.marqueeSelection(hits: [a.id, locked.id], original: [], operation: .replace, entered: nil, in: board)
        expect(swept == [a.id, b.id], "A marquee widens to the group and leaves its locked member behind")
        let added = EaselArrange.marqueeSelection(hits: [loose.id], original: [locked.id], operation: .add, entered: nil, in: board)
        expect(added == [locked.id, loose.id], "Shift-marquee keeps a locked object picked earlier")
        let opened = EaselArrange.marqueeSelection(hits: [a.id], original: [], operation: .replace, entered: group, in: board)
        expect(opened == [a.id], "Inside an open group a marquee picks single members")
        expect(EaselChords.consults(canvasFocus: true, editorFocus: false) && EaselChords.consults(canvasFocus: false, editorFocus: true)
               && !EaselChords.consults(canvasFocus: false, editorFocus: false), "Chords only apply with Easel focus")
        expect(!EaselChords.applies(.duplicate, selection: [UUID()], in: board), "A stale selection lets ⌘D reach Parc")
        expect(EaselChords.applies(.duplicate, selection: [locked.id], in: board), "Locked objects can still be duplicated")
        expect(!EaselChords.applies(.group, selection: [a.id], in: board) && EaselChords.applies(.group, selection: [loose.id, a.id], in: board),
               "⌘G only claims two or more objects")
        expect(EaselChords.applies(.ungroup, selection: [a.id], in: board) && !EaselChords.applies(.ungroup, selection: [loose.id], in: board),
               "⇧⌘G only claims a group")
        expect(!EaselChords.applies(.layer(.forward), selection: [locked.id], in: board), "Locked objects leave ⌘] to Parc")
        expect(!EaselChords.applies(.alignText(.left), selection: [a.id], in: board), "Other features' chords decide for themselves")
    }

    static func chords() {
        func chord(_ characters: String, _ keyCode: UInt16, _ modifiers: EaselKeyModifiers) -> EaselChordCommand? {
            EaselChords.command(characters: characters, keyCode: keyCode, modifiers: modifiers)
        }
        expect(chord("d", 2, .command) == .duplicate, "⌘D duplicates")
        expect(chord("g", 5, .command) == .group, "⌘G groups")
        expect(chord("G", 5, [.command, .shift]) == .ungroup, "⇧⌘G ungroups")
        expect(chord("", 51, .command) == .unwrap, "⌘Delete unwraps a group")
        expect(chord("L", 37, [.command, .shift]) == .toggleLock, "⇧⌘L locks and unlocks")
        expect(chord("]", 30, .command) == .layer(.forward) && chord("[", 33, .command) == .layer(.backward), "⌘] and ⌘[ step through layers")
        expect(chord("ж", 30, .command) == .layer(.forward), "Layer chords follow the physical key on other layouts")
        expect(chord("", 36, .command) == .quickCreate && chord("", 76, .command) == .quickCreate, "⌘Return quick creates from either Return key")
        expect(chord("E", 14, [.command, .shift]) == .exportSelection, "⇧⌘E exports the selection")
        expect(chord("", 36, [.command, .shift]) == .mindMapSibling && chord("", 76, [.command, .shift]) == .mindMapSibling,
               "⇧⌘Return adds a mind map sibling from either Return key")
        expect(chord("", 36, []) == nil && chord("", 36, [.command, .option]) == nil, "Other Return chords stay out of quick create")
        expect(chord("d", 2, [.command, .option]) == nil, "Extra modifiers don't trigger Duplicate")
        expect(EaselChords.reserved.allSatisfy { EaselChords.table[$0] == nil }, "Easels never take Parc's reserved chords")
        expect(EaselKeyCommands.command(characters: "]", keyCode: 30, modifiers: []) == .layer(.front), "Bare ] brings to front")
        expect(EaselKeyCommands.command(characters: "[", keyCode: 33, modifiers: []) == .layer(.back), "Bare [ sends to back")
        expect(EaselKeyCommands.command(characters: "}", keyCode: 30, modifiers: [.shift]) != .layer(.front), "Shift-] is not a layer key")
        expect(EaselKeyCommands.command(characters: "v", keyCode: 9, modifiers: []) == .tool(.select), "Tool letters still work")
    }
}
