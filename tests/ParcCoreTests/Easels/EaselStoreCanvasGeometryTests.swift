import Foundation
import Testing
@testable import ParcCore

struct EaselStoreCanvasGeometryTests {
    @Test
    func geometryEditsTolerateAnAliasedDocumentWithoutTrapping() {
        let first = EaselItem(kind: .rectangle, frame: EaselStoreTestsSupport.frame)
        let second = EaselItem(kind: .circle, frame: EaselStoreTestsSupport.frame)
        let date = Date(timeIntervalSince1970: 0)
        let repaired = EaselDocument(id: UUID(), title: "Shapes", createdAt: date, modifiedAt: date, items: [first, second])
        var aliased = repaired; aliased.items[1].id = aliased.items[0].id
        let edit = EaselGeometryEdit(document: repaired, selection: [repaired.items[0].id])!
        #expect(!edit.isCurrent(in: aliased) || edit.applying(edit.translated(x: 5, y: 5), to: aliased) != nil, "Geometry edits tolerate an aliased document without trapping")
    }

    @MainActor @Test
    func resizingAGroupPreservesProportionalGapsAndIdentity() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let text = EaselItem(kind: .text, frame: .init(x: 100, y: 100, width: 100, height: 50), zIndex: 8, text: "Unscaled text", textStyle: .init(family: .fancy, size: .h1))
            let image = EaselItem(kind: .image, frame: .init(x: 300, y: 200, width: 100, height: 50), zIndex: 9, assetID: asset)
            try session.perform("Seed resize") { $0.items = [text, image] }
            let edit = EaselGeometryEdit(document: session.document, selection: [text.id, image.id])!
            #expect(edit.bounds == .init(x: 100, y: 100, width: 300, height: 150), "Original group bounds include gaps between members")
            let enlarged = edit.resized(using: .bottomRight, x: 150, y: 150, centered: false)!
            #expect(enlarged[0].frame == .init(x: 100, y: 100, width: 150, height: 100) && enlarged[1].frame == .init(x: 400, y: 300, width: 150, height: 100), "Original group transform preserves proportional gaps and individual frames")
            #expect(enlarged[0].id == text.id && enlarged[1].id == image.id && enlarged[0].textStyle == text.textStyle && enlarged[1].assetID == asset && enlarged.map(\.zIndex) == [8, 9], "Resize preserves identity, text font, image asset and stacking")
        }
    }

    @MainActor @Test
    func optionResizesFromTheOriginalGroupCentre() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let text = EaselItem(kind: .text, frame: .init(x: 100, y: 100, width: 100, height: 50), zIndex: 8, text: "Unscaled text", textStyle: .init(family: .fancy, size: .h1))
            let image = EaselItem(kind: .image, frame: .init(x: 300, y: 200, width: 100, height: 50), zIndex: 9, assetID: asset)
            try session.perform("Seed resize") { $0.items = [text, image] }
            let edit = EaselGeometryEdit(document: session.document, selection: [text.id, image.id])!
            func close(_ a: EaselRect?, _ b: EaselRect) -> Bool {
                guard let a else { return false }
                return zip([a.x, a.y, a.width, a.height], [b.x, b.y, b.width, b.height]).allSatisfy { abs($0 - $1) < 0.000001 }
            }
            let centered = edit.resized(using: .bottomRight, x: 50, y: 25, centered: true)!
            #expect(close(EaselGeometryEdit.bounds(of: centered), .init(x: 50, y: 75, width: 400, height: 200)), "Option grows from the original group center")
        }
    }

    @MainActor @Test
    func draggingACrossedSideReflectsTheGroupAlongThatAxis() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let text = EaselItem(kind: .text, frame: .init(x: 100, y: 100, width: 100, height: 50), zIndex: 8, text: "Unscaled text", textStyle: .init(family: .fancy, size: .h1))
            let image = EaselItem(kind: .image, frame: .init(x: 300, y: 200, width: 100, height: 50), zIndex: 9, assetID: asset)
            try session.perform("Seed resize") { $0.items = [text, image] }
            let edit = EaselGeometryEdit(document: session.document, selection: [text.id, image.id])!
            let crossed = edit.resized(using: .left, x: 360, y: 20, centered: false)!
            #expect(crossed[0].frame.x == 440 && crossed[1].frame.x == 400 && crossed[0].frame.width == 20 && crossed[0].frame.y == 100, "Crossed left handle reflects original member arrangement and ignores vertical input")
        }
    }

    @MainActor @Test
    func centeredResizeCrossingUsesTheOriginalGroupWidth() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let text = EaselItem(kind: .text, frame: .init(x: 100, y: 100, width: 100, height: 50), zIndex: 8, text: "Unscaled text", textStyle: .init(family: .fancy, size: .h1))
            let image = EaselItem(kind: .image, frame: .init(x: 300, y: 200, width: 100, height: 50), zIndex: 9, assetID: asset)
            try session.perform("Seed resize") { $0.items = [text, image] }
            let edit = EaselGeometryEdit(document: session.document, selection: [text.id, image.id])!
            let centeredCross = edit.resized(using: .right, x: -200, y: 0, centered: true)!
            #expect(centeredCross[0].frame.x == 200, "Recovered center-resize crossing flag uses original width, not half-width sign")
        }
    }

    @MainActor @Test
    func returningThePointerToItsOriginRestoresOriginalFrames() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let text = EaselItem(kind: .text, frame: .init(x: 100, y: 100, width: 100, height: 50), zIndex: 8, text: "Unscaled text", textStyle: .init(family: .fancy, size: .h1))
            let image = EaselItem(kind: .image, frame: .init(x: 300, y: 200, width: 100, height: 50), zIndex: 9, assetID: asset)
            try session.perform("Seed resize") { $0.items = [text, image] }
            let edit = EaselGeometryEdit(document: session.document, selection: [text.id, image.id])!
            #expect(edit.resized(using: .bottomRight, x: 0, y: 0, centered: false) == edit.originals, "Pointer reversal computes from originals without accumulated drift")
        }
    }

    @MainActor @Test
    func invalidGroupResizesRefuseTheWholeSelection() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let text = EaselItem(kind: .text, frame: .init(x: 100, y: 100, width: 100, height: 50), zIndex: 8, text: "Unscaled text", textStyle: .init(family: .fancy, size: .h1))
            let image = EaselItem(kind: .image, frame: .init(x: 300, y: 200, width: 100, height: 50), zIndex: 9, assetID: asset)
            try session.perform("Seed resize") { $0.items = [text, image] }
            let edit = EaselGeometryEdit(document: session.document, selection: [text.id, image.id])!
            #expect(edit.resized(using: .left, x: 300, y: 0, centered: false) == nil, "Zero-width proposal refuses entire group")
            #expect(edit.resized(using: .left, x: 299, y: 0, centered: false) == nil, "Sub-point member refuses without individually clamping or distorting spacing")
            #expect(edit.resized(using: .topLeft, x: -200, y: -200, centered: false) == nil, "Off-canvas group proposal does not lose original objects beyond the point canvas")
            #expect(edit.resized(using: .right, x: .infinity, y: 0, centered: false) == nil, "Nonfinite pointer input refuses before durable mutation")
        }
    }

    @MainActor @Test
    func groupResizeMergesCurrentContentAndKeepsImageBytes() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let text = EaselItem(kind: .text, frame: .init(x: 100, y: 100, width: 100, height: 50), zIndex: 8, text: "Unscaled text", textStyle: .init(family: .fancy, size: .h1))
            let image = EaselItem(kind: .image, frame: .init(x: 300, y: 200, width: 100, height: 50), zIndex: 9, assetID: asset)
            try session.perform("Seed resize") { $0.items = [text, image] }
            let edit = EaselGeometryEdit(document: session.document, selection: [text.id, image.id])!
            let enlarged = edit.resized(using: .bottomRight, x: 150, y: 150, centered: false)!
            try session.perform("Other owner text") { $0.items[0].text = "Concurrent text" }
            try session.perform("Resize original group") { $0 = edit.applying(enlarged, to: $0)! }
            #expect(session.document.items[0].text == "Concurrent text" && session.document.items[1].assetID == asset, "Real resize transaction merges current content without replacement")
            let reopened = try EaselStore(directory: directory).load(session.document.id)
            #expect(reopened.document.items == session.document.items, "Actual group resize round trips through durable store")
            #expect(try! Data(contentsOf: session.assetURL(asset)) == EaselStoreTestsSupport.png, "Resize leaves exact source PNG bytes intact")
        }
    }

    @MainActor @Test
    func groupResizeUndoAndRedoPreserveOriginalObjects() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let text = EaselItem(kind: .text, frame: .init(x: 100, y: 100, width: 100, height: 50), zIndex: 8, text: "Unscaled text", textStyle: .init(family: .fancy, size: .h1))
            let image = EaselItem(kind: .image, frame: .init(x: 300, y: 200, width: 100, height: 50), zIndex: 9, assetID: asset)
            try session.perform("Seed resize") { $0.items = [text, image] }
            let edit = EaselGeometryEdit(document: session.document, selection: [text.id, image.id])!
            let enlarged = edit.resized(using: .bottomRight, x: 150, y: 150, centered: false)!
            try session.perform("Other owner text") { $0.items[0].text = "Concurrent text" }
            try session.perform("Resize original group") { $0 = edit.applying(enlarged, to: $0)! }
            try session.undo()
            #expect(session.document.items[0].frame == text.frame && session.document.items[0].text == "Concurrent text", "One undo restores all original frames and preserves prior content edit")
            try session.redo(); #expect(session.document.items[1].frame == enlarged[1].frame, "One redo restores actual original-image geometry")
        }
    }

    @MainActor @Test
    func staleGroupResizeProposalsRefuseTheWholeGroup() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let text = EaselItem(kind: .text, frame: .init(x: 100, y: 100, width: 100, height: 50), zIndex: 8, text: "Unscaled text", textStyle: .init(family: .fancy, size: .h1))
            let image = EaselItem(kind: .image, frame: .init(x: 300, y: 200, width: 100, height: 50), zIndex: 9, assetID: asset)
            try session.perform("Seed resize") { $0.items = [text, image] }
            let edit = EaselGeometryEdit(document: session.document, selection: [text.id, image.id])!
            let enlarged = edit.resized(using: .bottomRight, x: 150, y: 150, centered: false)!
            var changed = session.document; changed.items[1].frame.width += 1
            #expect(edit.applying(enlarged, to: changed) == nil, "Concurrent member resize refuses whole old group proposal")
        }
    }

    @MainActor @Test
    func failedGroupResizeSaveLeavesTheBoardUnchanged() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            let text = EaselItem(kind: .text, frame: .init(x: 100, y: 100, width: 100, height: 50), zIndex: 8, text: "Unscaled text", textStyle: .init(family: .fancy, size: .h1))
            let image = EaselItem(kind: .image, frame: .init(x: 300, y: 200, width: 100, height: 50), zIndex: 9, assetID: asset)
            try session.perform("Seed resize") { $0.items = [text, image] }
            let edit = EaselGeometryEdit(document: session.document, selection: [text.id, image.id])!
            let enlarged = edit.resized(using: .bottomRight, x: 150, y: 150, centered: false)!
            try session.perform("Other owner text") { $0.items[0].text = "Concurrent text" }
            let fileURL = EaselStoreTestsSupport.file(directory, session.document.id), before = session.document
            try FileManager.default.removeItem(at: fileURL); try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
            EaselStoreTestsSupport.expectThrows("group resize save failure") { try session.perform("Resize") { $0 = edit.applying(enlarged, to: $0)! } }
            #expect(session.document == before, "Failed group resize preserves all original published frames")
        }
    }

    @Test
    func crossingAResizeHandleReflectsAFreehandStroke() {
        let freehand = EaselItem(kind: .freehand, frame: .init(x: 100, y: 100, width: 100, height: 100), points: [.init(x: 0, y: 10), .init(x: 100, y: 90)])
        let document = EaselDocument(id: UUID(), title: "Paths", createdAt: Date(), modifiedAt: Date(), items: [freehand])
        let reflected = EaselGeometryEdit(document: document, selection: [freehand.id])!.resized(using: .right, x: -150, y: 0, centered: false)!
        #expect(reflected[0].points == [.init(x: 50, y: 10), .init(x: 0, y: 90)], "Crossing mirrors normalized freehand points inside their resized original frame")
    }

    @Test
    func crossingAResizeHandleKeepsArrowPointDirection() {
        var freehand = EaselItem(kind: .freehand, frame: .init(x: 100, y: 100, width: 100, height: 100), points: [.init(x: 0, y: 10), .init(x: 100, y: 90)])
        var document = EaselDocument(id: UUID(), title: "Paths", createdAt: Date(), modifiedAt: Date()); document.items = [freehand]
        freehand.kind = .arrow; document.items = [freehand]
        let arrow = EaselGeometryEdit(document: document, selection: [freehand.id])!.resized(using: .right, x: -150, y: 0, centered: false)!
        #expect(arrow[0].points == [.init(x: 0, y: 10), .init(x: 50, y: 90)], "Frame control preserves arrow payload direction while adapting local point size")
    }

    @Test
    func resizeHandlesKeepScreenSizedHitRegions() {
        #expect(EaselResizeHandle.topLeft.hitRect(in: .init(x: 20, y: 20, width: 10, height: 10)) == .init(x: 10, y: 10, width: 20, height: 20), "Small group retains original corner hit region")
        #expect(EaselResizeHandle.right.hitRect(in: .init(x: 20, y: 20, width: 29, height: 100)) == nil, "Edge strip hides below recovered minimum dimensions")
        #expect(EaselResizeHandle.top.hitRect(in: .init(x: 20, y: 20, width: 100, height: 30)) == .init(x: 30, y: 15, width: 80, height: 10), "Edge strip spans original edge excluding corner regions")
        let scaledFrame = EaselRect(x: 20, y: 20, width: 100, height: 30)
        #expect(EaselResizeHandle.topLeft.hitRect(in: scaledFrame, scale: 2) == .init(x: 15, y: 15, width: 10, height: 10), "Zoomed corners retain a twenty-screen-point target")
        #expect(EaselResizeHandle.top.hitRect(in: scaledFrame, scale: 2) == .init(x: 25, y: 17.5, width: 90, height: 5), "Zoomed edge excludes the screen-sized corner targets")
        #expect(EaselResizeHandle.top.hitRect(in: scaledFrame, scale: 0.5) == nil, "Edge eligibility uses screen dimensions while zoomed out")
        #expect(EaselResizeHandle.topLeft.hitRect(in: scaledFrame, scale: 0) == nil && EaselResizeHandle.left.hitRect(in: scaledFrame, scale: .nan) == nil, "Invalid zoom cannot create nonfinite native targets")
    }

    @MainActor @Test
    func endpointEditsRoundTripAndUndoWithConcurrentContentIntact() throws {
        let arrow = EaselItem(kind: .arrow, frame: .init(x: 100, y: 100, width: 100, height: 80),
                              points: [.init(x: 0, y: 0), .init(x: 100, y: 80)])
        let document = EaselDocument(id: UUID(), title: "Direct controls", createdAt: Date(), modifiedAt: Date(), items: [arrow])
        let edit = EaselGeometryEdit(document: document, selection: [arrow.id])!
        let moved = edit.movingEndpoint(.start, x: 150, y: 120)![0]
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: "original.png")
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            var realImage = image; realImage.assetID = asset
            try session.perform("Seed controls") { $0.items = [arrow, realImage] }
            let ae = EaselGeometryEdit(document: session.document, selection: [arrow.id])!
            try session.perform("Concurrent color") { $0.items[0].color = "#112233" }
            try session.perform("Endpoint") { $0 = ae.applying([moved], to: $0)! }
            #expect(session.document.items[0].color == "#112233" && session.document.items[0].points == moved.points, "Endpoint commit preserves concurrent content while updating only original geometry")
            try session.undo(); #expect(session.document.items[0].frame == arrow.frame && session.document.items[0].points == arrow.points, "One undo restores both original endpoint and frame")
            try session.redo()
            let reopened = try EaselStore(directory: directory).load(session.document.id)
            #expect(reopened.document.items[0].points == moved.points, "Endpoint direction persists through real disk reopen")
        }
    }

    @MainActor @Test
    func aspectResizingKeepsTheOriginalImageBytes() throws {
        let arrow = EaselItem(kind: .arrow, frame: .init(x: 100, y: 100, width: 100, height: 80),
                              points: [.init(x: 0, y: 0), .init(x: 100, y: 80)])
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: "original.png")
        try EaselStoreTestsSupport.withDirectory { directory in
            let store = try EaselStore(directory: directory), session = try store.create()
            let asset = try session.importPNG(EaselStoreTestsSupport.png)
            var realImage = image; realImage.assetID = asset
            try session.perform("Seed controls") { $0.items = [arrow, realImage] }
            let liveImage = EaselGeometryEdit(document: session.document, selection: [realImage.id])!
            let target = liveImage.resizedPreservingAspect(using: .bottomRight, x: 100, y: 0, centering: [])!
            try session.perform("Image aspect") { $0 = liveImage.applying(target, to: $0)! }
            #expect(try! Data(contentsOf: session.assetURL(asset)) == EaselStoreTestsSupport.png && session.document.items[1].assetID == asset, "Real aspect resize leaves original imported image bytes unchanged")
        }
    }

    @Test(arguments: EaselResizeHandle.allCases)
    func resizeHandlesMoveOnlyTheirOwnEdges(_ handle: EaselResizeHandle) throws {
        let text = EaselItem(kind: .text, frame: .init(x: 100, y: 100, width: 100, height: 50), zIndex: 8, text: "Unscaled text", textStyle: .init(family: .fancy, size: .h1))
        let image = EaselItem(kind: .image, frame: .init(x: 300, y: 200, width: 100, height: 50), zIndex: 9, assetID: "example.png")
        let date = Date(timeIntervalSince1970: 0)
        let document = EaselDocument(id: UUID(), title: "Board", createdAt: date, modifiedAt: date, items: [text, image])
        let edit = try #require(EaselGeometryEdit(document: document, selection: [text.id, image.id]))
        func close(_ a: EaselRect?, _ b: EaselRect) -> Bool {
            guard let a else { return false }
            return zip([a.x, a.y, a.width, a.height], [b.x, b.y, b.width, b.height]).allSatisfy { abs($0 - $1) < 0.000001 }
        }
        let expected: [EaselRect] = [
            .init(x: 120, y: 130, width: 280, height: 120), .init(x: 100, y: 130, width: 320, height: 120),
            .init(x: 120, y: 100, width: 280, height: 180), .init(x: 100, y: 100, width: 320, height: 180),
            .init(x: 100, y: 130, width: 300, height: 120), .init(x: 120, y: 100, width: 280, height: 150),
            .init(x: 100, y: 100, width: 300, height: 180), .init(x: 100, y: 100, width: 320, height: 150)]
        let proposal = edit.resized(using: handle, x: 20, y: 30, centered: false)!
        #expect(close(EaselGeometryEdit.bounds(of: proposal), expected[handle.rawValue]), "Each control point changes only its original edges: \(handle)")
    }
}
