import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcEasels

struct EaselCanvasTestsImageResize {
    private typealias GestureBoard = EaselCanvasTestsSupport.GestureBoard

    @MainActor @Test
    func anImageCornerProjectsTheDragOntoItsAspectRatio() throws {
        let board = try GestureBoard([])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try session.importPNG(png)
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: asset)
        try session.perform("Seed real image") { $0.items = [image] }
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 300, 200)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 400, 200))
        canvas.mouseUp(with: board.event(.leftMouseUp, 400, 200))
        let projected = session.document.items[0]
        #expect(abs(projected.frame.width - 280) < 0.000001 && abs(projected.frame.height - 140) < 0.000001, "Native image corner applies real diagonal projection")
    }

    @MainActor @Test(arguments: [false, true])
    func commandDisablesAspectUntilReleased(_ release: Bool) throws {
        let board = try GestureBoard([])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try session.importPNG(png)
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: asset)
        try session.perform("Seed real image") { $0.items = [image] }
        canvas.selectAll(nil)
        let start: NSEvent.ModifierFlags = release ? .command : []
        let finish: NSEvent.ModifierFlags = release ? [] : .command
        canvas.mouseDown(with: board.event(.leftMouseDown, 300, 200))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 400, 200, flags: start))
        board.modifiers(finish)
        canvas.mouseUp(with: board.event(.leftMouseUp, 400, 200, flags: finish))
        let shape = session.document.items[0].frame
        #expect(abs(shape.width - (release ? 280 : 300)) < 0.000001)
        #expect(abs(shape.height - (release ? 140 : 100)) < 0.000001)
    }

    @MainActor @Test
    func optionResizesAnImageAroundItsCenter() throws {
        let board = try GestureBoard([])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try session.importPNG(png)
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: asset)
        try session.perform("Seed real image") { $0.items = [image] }
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 300, 200)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 320, 250, flags: .option))
        canvas.mouseUp(with: board.event(.leftMouseUp, 320, 250, flags: .option))
        #expect(session.document.items[0].frame == .init(x: 80, y: 90, width: 240, height: 120), "Native Option uses the recovered centered aspect branch")
    }

    @MainActor @Test
    func focusLossCancelsAnInProgressImageResize() throws {
        let board = try GestureBoard([])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try session.importPNG(png)
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: asset)
        try session.perform("Seed real image") { $0.items = [image] }
        canvas.selectAll(nil)
        canvas.mouseDown(with: board.event(.leftMouseDown, 300, 200)); canvas.mouseDragged(with: board.event(.leftMouseDragged, 400, 200))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: board.window)
        canvas.mouseUp(with: board.event(.leftMouseUp, 400, 200))
        #expect(session.document.items[0] == image, "Owner focus loss cancels pending aspect preview")
    }

    @MainActor @Test(arguments: [EaselItemKind.image, .webCard, .link])
    func theShiftGuideReadsIntrinsicImageOrCardSize(_ kind: EaselItemKind) throws {
        let board = try GestureBoard([])
        defer { board.close() }
        let canvas = board.canvas
        let session = board.session
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try session.importPNG(png)
        let image = EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: asset)
        var object = image
        object.kind = kind
        if kind != .image { object.url = "https://example.com/" }
        try session.perform("Seed original") { $0.items = [object] }
        canvas.selectAll(nil)
        let neighbor = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 220, width: 50, height: 60))
        try session.perform("Add guide target") { $0.items.append(neighbor) }
        canvas.mouseDown(with: board.event(.leftMouseDown, 300, 200))
        canvas.mouseDragged(with: board.event(.leftMouseDragged, 348, 224, flags: .shift))
        canvas.mouseUp(with: board.event(.leftMouseUp, 348, 224, flags: .shift))
        let expected = kind == .link ? 248 + 1.6 + 0.8 / (220.0 / 160.0) : 250.4
        #expect(abs(session.document.items[0].frame.width - expected) < 0.000001)
        try session.undo()
        #expect(session.document.items[0] == object)
        #expect(try session.assetData(asset) == png)
    }
}
