import AppKit
import ParcCore
import Testing
@testable import Parc

@MainActor
struct ExternalSplitDropHandoffPlaceholderCardTests {
    @MainActor private final class HeaderScene {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1810, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
        let host = ExternalSplitDropHost(frame: NSRect(x: 0, y: 0, width: 1810, height: 700))
        let split: ParcSplitView
        let page: SplitDropReservedPane
        let drag: SplitDropDragInfo
        let router: SplitDropRouterDouble
        let item: NSDraggingItem
        let linkImage = NSImage(size: NSSize(width: 120, height: 20))
        var targets: [(SplitDropTarget, SplitOrientation)] = []

        init() {
            window.isReleasedWhenClosed = false
            window.contentView = host
            split = ParcSplitView(frame: host.bounds)
            host.addSubview(split)
            page = SplitDropReservedPane(frame: host.bounds)
            split.addArrangedSubview(page)
            split.configure(orientation: .horizontal, factors: [1])
            split.constrain(to: host)
            drag = SplitDropDragInfo(window: window)
            drag.draggingPasteboard.setString("https://header.invalid/path", forType: .URL)
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString("https://header.invalid/path", forType: .URL)
            item = NSDraggingItem(pasteboardWriter: pasteboardItem)
            item.setDraggingFrame(NSRect(x: 40, y: 50, width: 120, height: 20), contents: linkImage)
            drag.items = [item]
            router = SplitDropRouterDouble(view: page.body)
            host.makeSession = { [weak self] _, info in
                guard let self else { return nil }
                let reservation = immediate(split.prepareDropReservation(in: host, contents: [page.body])!)
                return ExternalSplitDropSession(host: host, info: info, frames: [], orientation: .horizontal,
                    reservation: reservation, validate: { reservation.isCurrent }, insertionColor: { .black },
                    canPropose: { _, _ in true }, commit: { [weak self] target, orientation in self?.targets.append((target, orientation)); return true })
            }
        }

        var cardSize: NSSize {
            SplitDropPlaceholderCard.size(forIncomingPane: NSSize(width: split.bounds.width / 2, height: split.bounds.height))!
        }

        func place(_ point: NSPoint) { drag.draggingLocation = host.convert(point, to: nil) }
    }

    @Test func theAdmittedLinkBecomesAPlaceholderCardAtItsOwnBottomLeft() {
        let scene = HeaderScene()
        scene.place(NSPoint(x: 905, y: 400))
        #expect(scene.router.begin(scene.drag))
        #expect(scene.router.operation == .copy)
        let image = scene.item.imageComponentsProvider?().first?.contents as? NSImage
        #expect(image !== scene.linkImage)
        #expect(image?.size == scene.cardSize)
        #expect(scene.item.draggingFrame == NSRect(origin: NSPoint(x: 40, y: 50), size: scene.cardSize))
    }

    @Test func theHostAcceptsTheLinkOverASinglePanesHeader() {
        let scene = HeaderScene()
        scene.place(NSPoint(x: 905, y: 400))
        _ = scene.router.begin(scene.drag)
        scene.place(NSPoint(x: scene.page.frame.midX, y: 20))
        scene.router.exit(scene.drag)
        #expect(scene.host.draggingEntered(scene.drag) == .copy)
    }

    @Test func aDropOverASinglePanesHeaderInsertsAboveIt() {
        let scene = HeaderScene()
        scene.place(NSPoint(x: 905, y: 400))
        _ = scene.router.begin(scene.drag)
        scene.place(NSPoint(x: scene.page.frame.midX, y: 20))
        scene.router.exit(scene.drag)
        _ = scene.host.draggingEntered(scene.drag)
        #expect(scene.host.performDragOperation(scene.drag))
        #expect(scene.targets.count == 1)
        #expect(scene.targets.first?.0 == .insert(0))
        #expect(scene.targets.first?.1 == .vertical)
    }

    @Test func aPerformedDropKeepsTheCardReshapedForItsTarget() {
        let scene = HeaderScene()
        scene.place(NSPoint(x: 905, y: 400))
        _ = scene.router.begin(scene.drag)
        scene.place(NSPoint(x: scene.page.frame.midX, y: 20))
        scene.router.exit(scene.drag)
        _ = scene.host.draggingEntered(scene.drag)
        _ = scene.host.performDragOperation(scene.drag)
        let topZone = SplitDropPlaceholderCard.size(forIncomingPane: NSSize(width: scene.split.bounds.width, height: scene.split.bounds.height / 2))
        #expect(scene.item.draggingFrame.size == topZone)
        #expect((scene.item.imageComponentsProvider?().first?.contents as? NSImage) !== scene.linkImage)
    }

    @Test func aNewEntryShowsTheCardAgain() {
        let scene = HeaderScene()
        scene.place(NSPoint(x: 905, y: 400))
        _ = scene.router.begin(scene.drag)
        scene.router.end()
        scene.item.setDraggingFrame(NSRect(x: 40, y: 50, width: 120, height: 20), contents: scene.linkImage)
        scene.place(NSPoint(x: 905, y: 400))
        #expect(scene.router.begin(scene.drag))
        #expect(scene.item.draggingFrame.size == scene.cardSize)
    }

    @Test func leavingTheSplitGivesTheLinkItsOwnImageBack() {
        let scene = HeaderScene()
        scene.place(NSPoint(x: 905, y: 400))
        _ = scene.router.begin(scene.drag)
        scene.place(NSPoint(x: scene.page.frame.midX, y: scene.page.frame.maxY + 40))
        scene.router.exit(scene.drag)
        #expect(scene.item.draggingFrame == NSRect(x: 40, y: 50, width: 120, height: 20))
        #expect((scene.item.imageComponentsProvider?().first?.contents as? NSImage) === scene.linkImage)
    }
}
