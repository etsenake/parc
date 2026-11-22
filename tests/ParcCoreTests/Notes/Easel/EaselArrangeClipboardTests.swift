import Foundation
import Testing
@testable import ParcCore

struct EaselArrangeClipboardTests {
    @Test
    func copiesGetFreshObjectAndGroupIDs() throws {
        var a = EaselArrangeTestsSupport.box(0, 0, z: 3), b = EaselArrangeTestsSupport.box(200, 0, z: 1)
        let group = UUID(); a.groupID = group; b.groupID = group
        let outside = EaselArrangeTestsSupport.box(600, 600, z: 2)
        var inner = EaselItem(kind: .arrow, frame: EaselRect(x: 100, y: 50, width: 100, height: 1), zIndex: 4,
                              points: [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0)])
        inner.startConnection = EaselConnection(itemID: a.id, side: .right)
        inner.endConnection = EaselConnection(itemID: outside.id)
        inner.waypoints = [EaselPoint(x: 150, y: 80)]
        var sticker = EaselArrangeTestsSupport.box(10, 10, 20, 20, kind: .image, z: 5)
        sticker.attachedTo = a.id
        var stray = EaselArrangeTestsSupport.box(700, 700, 20, 20, kind: .image, z: 6)
        stray.attachedTo = outside.id
        let board = EaselArrangeTestsSupport.document([a, b, outside, inner, sticker, stray])
        let ids: Set<UUID> = [a.id, b.id, inner.id, sticker.id, stray.id]
        let result = try #require(EaselArrange.duplicating(ids, in: board), "Duplicate returns copies")
        let copies = result.document.items.filter { result.copies.contains($0.id) }
        #expect(copies.count == 5 && Set(result.document.items.map(\.id)).count == 11, "Every copy gets a fresh, unique ID")
        let copiedGroups = Set(copies.compactMap(\.groupID))
        #expect(copiedGroups.count == 1 && !copiedGroups.contains(group), "A whole group's copy becomes a new group of its own")
    }

    @Test
    func copiedConnectorsKeepOnlyInternalConnectionsAndMoveTheirBends() throws {
        var a = EaselArrangeTestsSupport.box(0, 0, z: 3), b = EaselArrangeTestsSupport.box(200, 0, z: 1)
        let group = UUID(); a.groupID = group; b.groupID = group
        let outside = EaselArrangeTestsSupport.box(600, 600, z: 2)
        var inner = EaselItem(kind: .arrow, frame: EaselRect(x: 100, y: 50, width: 100, height: 1), zIndex: 4,
                              points: [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0)])
        inner.startConnection = EaselConnection(itemID: a.id, side: .right)
        inner.endConnection = EaselConnection(itemID: outside.id)
        inner.waypoints = [EaselPoint(x: 150, y: 80)]
        var sticker = EaselArrangeTestsSupport.box(10, 10, 20, 20, kind: .image, z: 5)
        sticker.attachedTo = a.id
        var stray = EaselArrangeTestsSupport.box(700, 700, 20, 20, kind: .image, z: 6)
        stray.attachedTo = outside.id
        let board = EaselArrangeTestsSupport.document([a, b, outside, inner, sticker, stray])
        let ids: Set<UUID> = [a.id, b.id, inner.id, sticker.id, stray.id]
        let result = try #require(EaselArrange.duplicating(ids, in: board), "Duplicate returns copies")
        let copies = result.document.items.filter { result.copies.contains($0.id) }
        let copyA = copies.first { $0.frame.x == 24 && $0.frame.y == 24 && $0.kind == .sticky }
        let copyArrow = copies.first { $0.kind == .arrow }
        #expect(copyArrow?.startConnection?.itemID == copyA?.id && copyArrow?.startConnection?.side == .right, "Connections inside the copied set point at the copies")
        #expect(copyArrow?.endConnection == nil, "Connections to objects outside the copy are dropped")
        #expect(copyArrow?.waypoints == [EaselPoint(x: 174, y: 104)], "Bends move with the copy")
    }

    @Test
    func copiedAttachmentsFollowOnlyCopiedTargets() throws {
        var a = EaselArrangeTestsSupport.box(0, 0, z: 3), b = EaselArrangeTestsSupport.box(200, 0, z: 1)
        let group = UUID(); a.groupID = group; b.groupID = group
        let outside = EaselArrangeTestsSupport.box(600, 600, z: 2)
        var inner = EaselItem(kind: .arrow, frame: EaselRect(x: 100, y: 50, width: 100, height: 1), zIndex: 4,
                              points: [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0)])
        inner.startConnection = EaselConnection(itemID: a.id, side: .right)
        inner.endConnection = EaselConnection(itemID: outside.id)
        inner.waypoints = [EaselPoint(x: 150, y: 80)]
        var sticker = EaselArrangeTestsSupport.box(10, 10, 20, 20, kind: .image, z: 5)
        sticker.attachedTo = a.id
        var stray = EaselArrangeTestsSupport.box(700, 700, 20, 20, kind: .image, z: 6)
        stray.attachedTo = outside.id
        let board = EaselArrangeTestsSupport.document([a, b, outside, inner, sticker, stray])
        let ids: Set<UUID> = [a.id, b.id, inner.id, sticker.id, stray.id]
        let result = try #require(EaselArrange.duplicating(ids, in: board), "Duplicate returns copies")
        let copies = result.document.items.filter { result.copies.contains($0.id) }
        let copyA = copies.first { $0.frame.x == 24 && $0.frame.y == 24 && $0.kind == .sticky }
        #expect(copies.first { $0.frame.x == 34 }?.attachedTo == copyA?.id, "Sticky-ons follow the copied object")
        #expect(copies.first { $0.frame.x == 724 }?.attachedTo == nil, "Sticky-ons let go of objects that weren't copied")
    }

    @Test
    func copiesLandAboveTheOriginalsInTheirOriginalOrder() throws {
        var a = EaselArrangeTestsSupport.box(0, 0, z: 3), b = EaselArrangeTestsSupport.box(200, 0, z: 1)
        let group = UUID(); a.groupID = group; b.groupID = group
        let outside = EaselArrangeTestsSupport.box(600, 600, z: 2)
        var inner = EaselItem(kind: .arrow, frame: EaselRect(x: 100, y: 50, width: 100, height: 1), zIndex: 4,
                              points: [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0)])
        inner.startConnection = EaselConnection(itemID: a.id, side: .right)
        inner.endConnection = EaselConnection(itemID: outside.id)
        inner.waypoints = [EaselPoint(x: 150, y: 80)]
        var sticker = EaselArrangeTestsSupport.box(10, 10, 20, 20, kind: .image, z: 5)
        sticker.attachedTo = a.id
        var stray = EaselArrangeTestsSupport.box(700, 700, 20, 20, kind: .image, z: 6)
        stray.attachedTo = outside.id
        let board = EaselArrangeTestsSupport.document([a, b, outside, inner, sticker, stray])
        let ids: Set<UUID> = [a.id, b.id, inner.id, sticker.id, stray.id]
        let result = try #require(EaselArrange.duplicating(ids, in: board), "Duplicate returns copies")
        let copies = result.document.items.filter { result.copies.contains($0.id) }
        let topCopies = copies.map(\.zIndex).min() ?? 0
        #expect(topCopies > board.items.map(\.zIndex).max() ?? 0, "Copies land on top of the board")
        #expect(copies.sorted { $0.zIndex < $1.zIndex }.first?.frame.x == 224, "Copies keep the stacking order of their originals")
    }

    @Test
    func duplicatingAMemberGrowsItsGroupAndBringsAttachments() throws {
        var a = EaselArrangeTestsSupport.box(0, 0, z: 3), b = EaselArrangeTestsSupport.box(200, 0, z: 1)
        let group = UUID(); a.groupID = group; b.groupID = group
        let outside = EaselArrangeTestsSupport.box(600, 600, z: 2)
        var inner = EaselItem(kind: .arrow, frame: EaselRect(x: 100, y: 50, width: 100, height: 1), zIndex: 4,
                              points: [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0)])
        inner.startConnection = EaselConnection(itemID: a.id, side: .right)
        inner.endConnection = EaselConnection(itemID: outside.id)
        inner.waypoints = [EaselPoint(x: 150, y: 80)]
        var sticker = EaselArrangeTestsSupport.box(10, 10, 20, 20, kind: .image, z: 5)
        sticker.attachedTo = a.id
        var stray = EaselArrangeTestsSupport.box(700, 700, 20, 20, kind: .image, z: 6)
        stray.attachedTo = outside.id
        let board = EaselArrangeTestsSupport.document([a, b, outside, inner, sticker, stray])
        let partial = try #require(EaselArrange.duplicating([a.id], in: board), "Duplicating one member works")
        #expect(partial.document.items.first { partial.copies.contains($0.id) && $0.kind == .sticky }?.groupID == group, "Duplicating inside a group grows that group")
        #expect(partial.copies.count == 2 && partial.document.items.contains { partial.copies.contains($0.id) && $0.kind == .image }, "Duplicating an object brings what's stuck to it")
    }

    @Test
    func repeatedDuplicatesReuseTheLastStepUnlessACopyIsMissing() {
        var a = EaselArrangeTestsSupport.box(0, 0, z: 3), b = EaselArrangeTestsSupport.box(200, 0, z: 1)
        let group = UUID(); a.groupID = group; b.groupID = group
        let outside = EaselArrangeTestsSupport.box(600, 600, z: 2)
        var inner = EaselItem(kind: .arrow, frame: EaselRect(x: 100, y: 50, width: 100, height: 1), zIndex: 4,
                              points: [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0)])
        inner.startConnection = EaselConnection(itemID: a.id, side: .right)
        inner.endConnection = EaselConnection(itemID: outside.id)
        inner.waypoints = [EaselPoint(x: 150, y: 80)]
        var sticker = EaselArrangeTestsSupport.box(10, 10, 20, 20, kind: .image, z: 5)
        sticker.attachedTo = a.id
        var stray = EaselArrangeTestsSupport.box(700, 700, 20, 20, kind: .image, z: 6)
        stray.attachedTo = outside.id
        let board = EaselArrangeTestsSupport.document([a, b, outside, inner, sticker, stray])
        let offset = EaselArrange.repeatOffset(sources: [a.id], copies: [b.id], in: board)
        #expect(offset == EaselPoint(x: 200, y: 0), "Repeating a duplicate reuses the last step")
        #expect(EaselArrange.repeatOffset(sources: [a.id], copies: [UUID()], in: board) == nil, "A missing copy forgets the step")
    }

    @Test
    func lockedObjectsCanBeDuplicated() {
        var a = EaselArrangeTestsSupport.box(0, 0, z: 3), b = EaselArrangeTestsSupport.box(200, 0, z: 1)
        let group = UUID(); a.groupID = group; b.groupID = group
        let outside = EaselArrangeTestsSupport.box(600, 600, z: 2)
        var inner = EaselItem(kind: .arrow, frame: EaselRect(x: 100, y: 50, width: 100, height: 1), zIndex: 4,
                              points: [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0)])
        inner.startConnection = EaselConnection(itemID: a.id, side: .right)
        inner.endConnection = EaselConnection(itemID: outside.id)
        inner.waypoints = [EaselPoint(x: 150, y: 80)]
        var sticker = EaselArrangeTestsSupport.box(10, 10, 20, 20, kind: .image, z: 5)
        sticker.attachedTo = a.id
        var stray = EaselArrangeTestsSupport.box(700, 700, 20, 20, kind: .image, z: 6)
        stray.attachedTo = outside.id
        let board = EaselArrangeTestsSupport.document([a, b, outside, inner, sticker, stray])
        let copiedLocked = EaselArrange.duplicating([a.id], in: EaselArrange.settingLock(true, ids: [a.id], in: board) ?? board)
        #expect(copiedLocked != nil, "Locked objects can still be duplicated")
    }

    @Test
    func shiftDragKeepsOnlyTheDominantAxis() {
        #expect(EaselArrange.axisLocked(EaselPoint(x: 30, y: -10), when: true) == EaselPoint(x: 30, y: 0)
               && EaselArrange.axisLocked(EaselPoint(x: 3, y: -10), when: true) == EaselPoint(x: 0, y: -10)
               && EaselArrange.axisLocked(EaselPoint(x: 3, y: -10), when: false) == EaselPoint(x: 3, y: -10), "Shift-drag keeps only the dominant direction")
    }

    @Test func pasteCentresOnThePointer() {
        let content = EaselRect(x: 100, y: 100, width: 200, height: 100)
        let viewport = EaselRect(x: 0, y: 1000, width: 800, height: 600)
        #expect(EaselArrange.pasteOffset(content: content, anchor: .pointer(EaselPoint(x: 500, y: 400)), viewport: viewport)
               == EaselPoint(x: 300, y: 250), "Paste centres on the pointer")
        #expect(EaselArrange.pasteOffset(content: content, anchor: .pointer(EaselPoint(x: 10, y: 10)), viewport: viewport)
               == EaselPoint(x: -100, y: -100), "Paste near the edge never goes off the board")
        #expect(EaselArrange.pasteOffset(content: content, anchor: .source(step: 2), viewport: viewport) == EaselPoint(x: 48, y: 48), "Repeated paste steps 24 points each time")
        #expect(EaselArrange.pasteOffset(content: content, anchor: .inPlace, viewport: viewport) == EaselPoint(x: 0, y: 0), "Paste after cut lands where it was")
        #expect(EaselArrange.pasteOffset(content: content, anchor: .viewport, viewport: viewport) == EaselPoint(x: 200, y: 1150), "Without a pointer or source, paste lands in the middle of the view")
    }

    @Test
    func copyKnowsWhichPicturesToBringAndRequiresTheirBytes() {
        var a = EaselArrangeTestsSupport.box(0, 0, kind: .image, z: 2), b = EaselArrangeTestsSupport.box(200, 0, z: 1)
        a.assetID = "11111111-1111-1111-1111-111111111111.png"
        let group = UUID(); a.groupID = group; b.groupID = group
        var c = EaselArrangeTestsSupport.box(400, 0, z: 3)
        let other = UUID(); c.groupID = other
        let d = EaselArrangeTestsSupport.box(600, 0, z: 4)
        var e = d; e.id = UUID(); e.groupID = other
        let board = EaselArrangeTestsSupport.document([a, b, c, e])
        #expect(EaselClipboardPayload.assetIDs(of: [a.id, b.id], in: board) == [a.assetID ?? ""], "Copy knows which pictures to bring")
        #expect((try? EaselClipboardPayload.capturing([a.id], in: board, assets: [:])) == nil, "Copy refuses when a picture can't be read")
    }

    @Test
    func capturingASelectionPreservesItsStackAndWholeGroups() {
        var a = EaselArrangeTestsSupport.box(0, 0, kind: .image, z: 2), b = EaselArrangeTestsSupport.box(200, 0, z: 1)
        a.assetID = "11111111-1111-1111-1111-111111111111.png"
        let group = UUID(); a.groupID = group; b.groupID = group
        var c = EaselArrangeTestsSupport.box(400, 0, z: 3)
        let other = UUID(); c.groupID = other
        let d = EaselArrangeTestsSupport.box(600, 0, z: 4)
        var e = d; e.id = UUID(); e.groupID = other
        let board = EaselArrangeTestsSupport.document([a, b, c, e])
        let bytes = Data([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3])
        guard let payload = try? EaselClipboardPayload.capturing([a.id, b.id, c.id], in: board, assets: [a.assetID ?? "": bytes]) else {
            Issue.record("Copy captures the selection")
            return
        }
        #expect(payload.items.map(\.id) == [b.id, a.id, c.id], "Copied objects keep their stacking order")
        #expect(payload.items.first { $0.id == c.id }?.groupID == nil, "A group that wasn't copied whole lets its member go")
        #expect(payload.items.first { $0.id == a.id }?.groupID == group, "A whole group travels as a group")
        #expect(payload.assets == [a.assetID ?? "": bytes] && payload.documentID == board.id, "Image bytes and the source Easel ride along")
    }

    @Test
    func theClipboardPayloadRoundTripsExactly() {
        var a = EaselArrangeTestsSupport.box(0, 0, kind: .image, z: 2), b = EaselArrangeTestsSupport.box(200, 0, z: 1)
        a.assetID = "11111111-1111-1111-1111-111111111111.png"
        let group = UUID(); a.groupID = group; b.groupID = group
        var c = EaselArrangeTestsSupport.box(400, 0, z: 3)
        let other = UUID(); c.groupID = other
        let d = EaselArrangeTestsSupport.box(600, 0, z: 4)
        var e = d; e.id = UUID(); e.groupID = other
        let board = EaselArrangeTestsSupport.document([a, b, c, e])
        let bytes = Data([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3])
        guard let payload = try? EaselClipboardPayload.capturing([a.id, b.id, c.id], in: board, assets: [a.assetID ?? "": bytes]) else {
            Issue.record("Copy captures the selection")
            return
        }
        guard let data = try? payload.encoded(), let decoded = try? EaselClipboardPayload.decoded(data) else {
            Issue.record("The payload survives the pasteboard")
            return
        }
        #expect(decoded == payload, "Decoding gives back exactly what was copied")
    }

    @Test
    func junkClipboardDataIsRefused() {
        #expect((try? EaselClipboardPayload.decoded(Data("nonsense".utf8))) == nil, "Junk on the pasteboard is refused")
    }

    @Test
    func copiedImagesRequireTheirBytes() {
        var a = EaselArrangeTestsSupport.box(0, 0, kind: .image, z: 2), b = EaselArrangeTestsSupport.box(200, 0, z: 1)
        a.assetID = "11111111-1111-1111-1111-111111111111.png"
        let group = UUID(); a.groupID = group; b.groupID = group
        var c = EaselArrangeTestsSupport.box(400, 0, z: 3)
        let other = UUID(); c.groupID = other
        let d = EaselArrangeTestsSupport.box(600, 0, z: 4)
        var e = d; e.id = UUID(); e.groupID = other
        let board = EaselArrangeTestsSupport.document([a, b, c, e])
        let bytes = Data([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3])
        guard let payload = try? EaselClipboardPayload.capturing([a.id, b.id, c.id], in: board, assets: [a.assetID ?? "": bytes]) else {
            Issue.record("Copy captures the selection")
            return
        }
        var broken = payload
        broken.assets = [:]
        #expect((try? broken.validate()) == nil, "A payload missing its image bytes is refused")
    }

    @Test
    func newerClipboardVersionsAreRefused() {
        var a = EaselArrangeTestsSupport.box(0, 0, kind: .image, z: 2), b = EaselArrangeTestsSupport.box(200, 0, z: 1)
        a.assetID = "11111111-1111-1111-1111-111111111111.png"
        let group = UUID(); a.groupID = group; b.groupID = group
        var c = EaselArrangeTestsSupport.box(400, 0, z: 3)
        let other = UUID(); c.groupID = other
        let d = EaselArrangeTestsSupport.box(600, 0, z: 4)
        var e = d; e.id = UUID(); e.groupID = other
        let board = EaselArrangeTestsSupport.document([a, b, c, e])
        let bytes = Data([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3])
        guard let payload = try? EaselClipboardPayload.capturing([a.id, b.id, c.id], in: board, assets: [a.assetID ?? "": bytes]) else {
            Issue.record("Copy captures the selection")
            return
        }
        var future = payload
        future.version = 99
        #expect((try? EaselClipboardPayload.decoded(future.encoded())) == nil, "A newer payload version is refused rather than misread")
    }

    @Test
    func pastingAssignsFreshObjectAndGroupIDs() {
        var a = EaselArrangeTestsSupport.box(0, 0, kind: .image, z: 2), b = EaselArrangeTestsSupport.box(200, 0, z: 1)
        a.assetID = "11111111-1111-1111-1111-111111111111.png"
        let group = UUID(); a.groupID = group; b.groupID = group
        var c = EaselArrangeTestsSupport.box(400, 0, z: 3)
        let other = UUID(); c.groupID = other
        let d = EaselArrangeTestsSupport.box(600, 0, z: 4)
        var e = d; e.id = UUID(); e.groupID = other
        let board = EaselArrangeTestsSupport.document([a, b, c, e])
        let bytes = Data([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3])
        guard let payload = try? EaselClipboardPayload.capturing([a.id, b.id, c.id], in: board, assets: [a.assetID ?? "": bytes]) else {
            Issue.record("Copy captures the selection")
            return
        }
        guard let pasted = EaselArrange.appending(payload.items, to: board, offset: EaselPoint(x: 10, y: 10)) else {
            Issue.record("Pasting appends copies")
            return
        }
        let copies = pasted.document.items.filter { pasted.copies.contains($0.id) }
        #expect(Set(copies.compactMap(\.groupID)).count == 1 && !copies.contains { $0.groupID == group }, "Pasted groups get a group of their own")
        #expect(copies.count == 3 && Set(pasted.document.items.map(\.id)).count == 7, "Pasting never reuses an ID")
    }

    @Test
    func aLoneObjectCanBeDuplicated() {
        let d = EaselArrangeTestsSupport.box(600, 0, z: 4)
        #expect(EaselArrange.duplicating([d.id], in: EaselArrangeTestsSupport.document([d])) != nil, "A lone object duplicates")
    }
}
