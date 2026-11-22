import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct SplitDropCardTests {
    @MainActor private final class Drag: NSObject, NSDraggingInfo {
        var draggingDestinationWindow: NSWindow?
        var draggingSourceOperationMask: NSDragOperation = .move
        var draggingLocation = NSPoint.zero
        var draggedImageLocation = NSPoint.zero
        nonisolated var draggedImage: NSImage? { nil }
        let draggingPasteboard = NSPasteboard.withUniqueName()
        var source: AnyObject?
        var draggingSource: Any? { source }
        var draggingSequenceNumber = 3
        var draggingFormation = NSDraggingFormation.default
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        var springLoadingHighlight = NSSpringLoadingHighlight.none
        var items: [NSDraggingItem] = []
        var calls: [(options: NSDraggingItemEnumerationOptions, view: NSView?, classes: [AnyClass], visited: [Int])] = []
        func slideDraggedImage(to screenPoint: NSPoint) {}
        nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
        func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
                                    searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
            var visited: [Int] = []
            var stop = ObjCBool(false)
            if !classArray.isEmpty {
                for (index, item) in items.enumerated() {
                    visited.append(index)
                    block(item, index, &stop)
                    if stop.boolValue { break }
                }
            }
            calls.append((enumOpts, view, classArray, visited))
        }
        func resetSpringLoading() {}
        deinit { draggingPasteboard.releaseGlobally() }
    }

    @MainActor private final class Row: SplitDropCardSource {
        var splitDrag: SidebarSplitDrag?
        var splitDropCardContent: (icon: NSImage?, title: String) = (nil, "1Password")
        var splitDragImage: NSImage?
    }

    @MainActor private final class Pane: NSView {
        let body = NSView()
        override var isFlipped: Bool { true }
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            addSubview(body)
            body.autoresizingMask = [.width, .height]
            body.frame = NSRect(x: 0, y: 32, width: frame.width, height: max(0, frame.height - 32))
        }
        required init?(coder: NSCoder) { fatalError() }
    }

    @MainActor private final class Host: NSView { override var isFlipped: Bool { true } }

    @MainActor private final class Overlay {
        static let type = SidebarSplitDrag.pasteboardType
        static let rowSize = NSSize(width: 206, height: 36)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1236, height: 808), styleMask: .borderless, backing: .buffered, defer: false)
        let host = Host(frame: NSRect(x: 0, y: 0, width: 1236, height: 808))
        let split: ParcSplitView
        let panes: [Pane]
        let drag: SidebarSplitDrag
        let reservation: ParcSplitView.DropReservation
        let overlay: SplitDropView
        let row = Row()
        let rowImage = NSImage(size: Overlay.rowSize)
        let session = Drag()
        let sessionItem: NSDraggingItem
        let otherItem: NSDraggingItem

        init() throws {
            window.isReleasedWhenClosed = false
            window.contentView = host
            let split = ParcSplitView(frame: host.bounds)
            let panes = [Pane(frame: host.bounds), Pane(frame: host.bounds)]
            host.addSubview(split)
            panes.forEach { split.addArrangedSubview($0) }
            split.configure(orientation: .horizontal, factors: [0.5, 0.5])
            split.constrain(to: host)
            self.split = split
            self.panes = panes
            host.layoutSubtreeIfNeeded()
            drag = SidebarSplitDrag(tabID: UUID(), window: window, validate: { true }, commit: { _, _ in true }, finish: {})
            reservation = try #require(split.prepareDropReservation(in: host, contents: panes.map(\.body)))
            reservation.hoverIntent = SplitDropIntent(dwell: 0)
            overlay = SplitDropView(frame: host.bounds, drag: drag, reservation: reservation, insertionColor: { .black })
            overlay.canPropose = { _, _ in true }
            host.addSubview(overlay)
            row.splitDrag = drag
            row.splitDragImage = rowImage
            session.source = row
            session.draggingDestinationWindow = window
            session.draggingPasteboard.setString(drag.identifier.uuidString, forType: Self.type)
            sessionItem = SplitDropCardTests.item(Self.type, drag.identifier.uuidString, frame: NSRect(x: 30, y: 40, width: 206, height: 36))
            otherItem = SplitDropCardTests.item(Self.type, "other", frame: NSRect(x: 5, y: 6, width: 206, height: 36))
            session.items = [sessionItem, otherItem]
            session.draggingLocation = host.convert(NSPoint(x: 4, y: 300), to: nil)
        }

        deinit {
            MainActor.assumeIsolated {
                overlay.removeFromSuperview()
                reservation.end()
                window.close()
            }
        }

        var incomingSize: NSSize { SplitDropPlaceholderCard.size(forIncomingPane: reservation.incomingPaneSize)! }

        func moveToStackTarget() {
            session.draggingLocation = host.convert(NSPoint(x: 618, y: 800), to: nil)
        }
    }

    private static let portraitPane = NSSize(width: 412, height: 808)

    private static func item(_ type: NSPasteboard.PasteboardType, _ value: String, frame: NSRect) -> NSDraggingItem {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(value, forType: type)
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        item.setDraggingFrame(frame, contents: NSImage(size: frame.size))
        return item
    }

    private static func contents(_ item: NSDraggingItem) -> NSImage? { item.imageComponentsProvider?().first?.contents as? NSImage }

    private static func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        var values = [Int](repeating: 0, count: 4)
        rep.getPixel(&values, atX: x, y: y)
        return (values[0], values[1], values[2], rep.samplesPerPixel > 3 ? values[3] : 255)
    }

    private static func laidOutCard(title: String = "A long page title that wraps across more lines than the card shows") -> SplitDropPlaceholderCard {
        let card = SplitDropPlaceholderCard(icon: NSImage(size: NSSize(width: 64, height: 64)), title: title)
        card.frame = NSRect(origin: .zero, size: SplitDropPlaceholderCard.size(forIncomingPane: portraitPane)!)
        card.layoutSubtreeIfNeeded()
        card.layoutSubtreeIfNeeded()
        card.updateLayer()
        return card
    }

    private static func render(_ card: SplitDropPlaceholderCard) -> NSBitmapImageRep? {
        card.layoutSubtreeIfNeeded()
        guard let bitmap = card.bitmapImageRepForCachingDisplay(in: card.bounds) else { return nil }
        card.cacheDisplay(in: card.bounds, to: bitmap)
        return bitmap
    }

    @Test func aTallIncomingPaneGivesA250PointHighCardAtItsAspectRatio() throws {
        let size = try #require(SplitDropPlaceholderCard.size(forIncomingPane: Self.portraitPane))
        #expect(size.height == 250)
        #expect(abs(size.width - 250 * 412 / 808) < 1e-9)
    }

    @Test func aWideIncomingPaneGivesA250PointWideCardAtItsAspectRatio() throws {
        let size = try #require(SplitDropPlaceholderCard.size(forIncomingPane: NSSize(width: 808, height: 412)))
        #expect(size.width == 250)
        #expect(abs(size.height - 250 * 412 / 808) < 1e-9)
    }

    @Test func aSquarePaneTakesTheHeightBranch() {
        #expect(SplitDropPlaceholderCard.size(forIncomingPane: NSSize(width: 300, height: 300)) == NSSize(width: 250, height: 250))
    }

    @Test(arguments: [NSSize(width: 0, height: 808), NSSize(width: 412, height: 0), NSSize(width: -4, height: 10),
                      NSSize(width: CGFloat.infinity, height: 10)])
    func anEmptyOrUnboundedPaneMakesNoCard(_ pane: NSSize) {
        #expect(SplitDropPlaceholderCard.size(forIncomingPane: pane) == nil)
    }

    @Test func theCardImageIsTheComputedCardSize() throws {
        let image = try #require(SplitDropPlaceholderCard.image(icon: NSImage(size: NSSize(width: 16, height: 16)), title: "1Password",
                                                                incomingPane: Self.portraitPane))
        #expect(image.size == SplitDropPlaceholderCard.size(forIncomingPane: Self.portraitPane))
    }

    @Test func theWindowlessCardCachesAtAWholePixelScaleOfItsSize() throws {
        let image = try #require(SplitDropPlaceholderCard.image(icon: NSImage(size: NSSize(width: 16, height: 16)), title: "1Password",
                                                                incomingPane: Self.portraitPane))
        let rep = try #require(image.representations.first as? NSBitmapImageRep)
        let scale = rep.pixelsHigh / 250
        #expect(scale >= 1)
        #expect(rep.pixelsHigh == 250 * scale)
        #expect(rep.pixelsWide == Int((image.size.width * CGFloat(scale)).rounded(.up)))
    }

    @Test func theCardCornersAreTransparentOutsideTheRounding() throws {
        let image = try #require(SplitDropPlaceholderCard.image(icon: nil, title: "1Password", incomingPane: Self.portraitPane))
        let rep = try #require(image.representations.first as? NSBitmapImageRep)
        #expect(Self.pixel(rep, 0, 0).a < 8)
        #expect(Self.pixel(rep, rep.pixelsWide - 1, rep.pixelsHigh - 1).a < 8)
    }

    @Test(arguments: [false, true])
    func theCardIsTheFullOpacityPrimaryBackgroundInTheCurrentAppearance(dark: Bool) throws {
        let card = Self.laidOutCard(title: "1Password")
        card.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let rep = try #require(Self.render(card))
        let fill = Self.pixel(rep, 6, rep.pixelsHigh / 2)
        if dark {
            #expect(fill.r < 8 && fill.g < 8 && fill.b < 8 && fill.a > 247)
        } else {
            #expect(fill.r > 247 && fill.g > 247 && fill.b > 247 && fill.a > 247)
        }
    }

    @Test func updateLayerPaintsTheContinuousTwentyPointCard() {
        let card = Self.laidOutCard()
        #expect(card.layer?.cornerRadius == 20)
        #expect(card.layer?.cornerCurve == .continuous)
        #expect(card.layer?.backgroundColor != nil)
    }

    @Test func theFaviconIsSixteenBySixteenWhateverItsImageSize() {
        #expect(Self.laidOutCard().iconView.frame.size == NSSize(width: 16, height: 16))
    }

    @Test func theTitleIsTheBoldThirteenPointLabelFont() {
        let font = Self.laidOutCard().titleView.font
        #expect(font?.pointSize == 13)
        #expect(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true)
    }

    @Test func theTitleIsCentredWordWrappedToThreeLinesAndTruncatesItsLastLine() {
        let title = Self.laidOutCard().titleView
        #expect(title.alignment == .center)
        #expect(title.maximumNumberOfLines == 3)
        #expect(title.lineBreakMode == .byWordWrapping)
        #expect(title.cell?.truncatesLastVisibleLine == true)
    }

    @Test func aLongTitleFillsExactlyThreeLines() throws {
        let title = Self.laidOutCard().titleView
        let font = try #require(title.font)
        #expect((title.frame.height / NSLayoutManager().defaultLineHeight(for: font)).rounded() == 3)
    }

    @Test func theTitleWrapsAtTheCardWidthLessBothInsets() {
        let card = Self.laidOutCard()
        #expect(abs(card.titleView.preferredMaxLayoutWidth - (card.bounds.width - 16)) < 1e-9)
    }

    @Test func aVerticalCentreStackSpacesTheIconAndTitle() throws {
        let stack = try #require(Self.laidOutCard().subviews.first as? NSStackView)
        #expect(stack.orientation == .vertical)
        #expect(stack.alignment == .centerX)
        #expect(stack.spacing == 24)
    }

    @Test func theStackIsCentredInTheCard() throws {
        let card = Self.laidOutCard()
        let stack = try #require(card.subviews.first as? NSStackView)
        let icon = card.convert(card.iconView.frame, from: stack)
        #expect(abs(icon.midX - card.bounds.midX) < 0.5)
        #expect(abs(stack.frame.midY - card.bounds.midY) < 0.5)
    }

    @Test func theIconSitsTwentyFourPointsFromTheTitle() throws {
        let card = Self.laidOutCard()
        let stack = try #require(card.subviews.first as? NSStackView)
        let icon = card.convert(card.iconView.frame, from: stack), text = card.convert(card.titleView.frame, from: stack)
        #expect(abs(min(abs(text.minY - icon.maxY), abs(icon.minY - text.maxY)) - 24) < 0.5)
    }

    @Test func theStackKeepsItsSideInsetsToWithinPointRounding() throws {
        let card = Self.laidOutCard()
        let stack = try #require(card.subviews.first as? NSStackView)
        #expect(stack.frame.minX >= 7)
        #expect(stack.frame.maxX <= card.bounds.maxX - 7)
    }

    private static func featherLink() throws -> NSImage {
        let fonts = try #require(Bundle.module.url(forResource: "SplitViews", withExtension: nil))
            .appendingPathComponent("CustomInfoPicker", isDirectory: true)
        let font = SidebarIconCatalog.font(.feather, size: 22, in: fonts)
        try #require(font.fontName != NSFont.systemFont(ofSize: 22).fontName)
        return SidebarIconCatalog.emojiImage(String(Character(Unicode.Scalar(0xE98A)!)), font: font)
    }

    @Test func theFeatherLinkIconFillsATwentyFivePointSquare() throws {
        #expect(try Self.featherLink().size == NSSize(width: 25, height: 25))
    }

    @Test func theFeatherLinkGlyphDrawsOnlyBlackInk() throws {
        let link = try Self.featherLink()
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 50, pixelsHigh: 50, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = link.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        link.draw(in: NSRect(origin: .zero, size: link.size))
        NSGraphicsContext.restoreGraphicsState()
        let inked = (0..<50).flatMap { y in (0..<50).map { x in Self.pixel(rep, x, y) } }.filter { $0.a > 200 }
        #expect(!inked.isEmpty)
        #expect(inked.allSatisfy { $0.r <= 40 })
    }

    @Test func theLinkIconIsNotATemplate() {
        #expect(!SidebarIconCatalog.emojiImage(String(Character(Unicode.Scalar(0xE98A)!)), size: 22).isTemplate)
    }

    @MainActor private struct Presented {
        let probe = Drag()
        let own: NSDraggingItem
        let foreign: NSDraggingItem
        let ownOriginal: NSImage?
        let image: NSImage
        let replaced: [Int: SplitDropPlaceholderCard.ItemImage]

        init() throws {
            let type = SidebarSplitDrag.pasteboardType
            own = SplitDropCardTests.item(type, "current", frame: NSRect(x: 30, y: 40, width: 206, height: 36))
            foreign = SplitDropCardTests.item(type, "other", frame: NSRect(x: 5, y: 6, width: 206, height: 36))
            ownOriginal = SplitDropCardTests.contents(own)
            probe.items = [own, foreign]
            image = try #require(SplitDropPlaceholderCard.image(icon: nil, title: "1Password", incomingPane: SplitDropCardTests.portraitPane))
            replaced = SplitDropPlaceholderCard.present(image, on: probe) { $0.string(forType: type) == "current" }
        }
    }

    @Test func bothItemsAreOfferedAsPasteboardItemsInScreenCoordinates() throws {
        let presented = try Presented()
        let call = try #require(presented.probe.calls.first)
        #expect(presented.probe.calls.count == 1)
        #expect(call.options.isEmpty)
        #expect(call.view == nil)
        #expect(call.classes.count == 1 && call.classes[0] == NSPasteboardItem.self)
        #expect(call.visited == [0, 1])
    }

    @Test func theSessionsItemBecomesTheCardKeepingItsUnflippedOrigin() throws {
        let presented = try Presented()
        #expect(presented.own.draggingFrame == NSRect(origin: NSPoint(x: 30, y: 40), size: presented.image.size))
        #expect(SplitDropCardTests.contents(presented.own) === presented.image)
    }

    @Test func anotherSessionsItemIsVisitedButKeepsItsOwnImage() throws {
        let presented = try Presented()
        #expect(presented.foreign.draggingFrame == NSRect(x: 5, y: 6, width: 206, height: 36))
        #expect(presented.replaced.keys.sorted() == [0])
    }

    @Test func theReplacedItemsOwnImageAndSizeAreRecorded() throws {
        let presented = try Presented()
        #expect(presented.replaced[0]?.size == NSSize(width: 206, height: 36))
        #expect((presented.replaced[0]?.contents as? NSImage) === presented.ownOriginal)
    }

    @Test func restorePutsTheOwnImageBackAtTheItemsCurrentBottomLeft() throws {
        let presented = try Presented()
        presented.own.setDraggingFrame(NSRect(origin: NSPoint(x: 31, y: 41), size: presented.image.size), contents: presented.image)
        SplitDropPlaceholderCard.restore(presented.replaced, on: presented.probe)
        #expect(presented.own.draggingFrame == NSRect(x: 31, y: 41, width: 206, height: 36))
        #expect(SplitDropCardTests.contents(presented.own) === presented.ownOriginal)
    }

    @Test(arguments: SpaceTheme.Appearance.allCases, [false, true])
    func aThemesInkUnderAnAppearanceIsThatPalettesMaxContrastColor(forced: SpaceTheme.Appearance, dark: Bool) throws {
        let primary = ThemeColor.hsl(hue: 0.42, saturation: 0.5, lightness: 0.75, colorSpace: .displayP3)
        var theme = SpaceTheme(primaryColor: primary, colorCount: 2)
        theme.appearance = forced
        let ink = ThemeChromePalette.appearanceBasedMaxContrast(theme: theme)
        var resolved = NSColor.clear
        try #require(NSAppearance(named: dark ? .darkAqua : .aqua)).performAsCurrentDrawingAppearance {
            resolved = NSColor(cgColor: ink.cgColor)!.usingColorSpace(.extendedSRGB)!
        }
        let expected = try #require(ThemeChromePalette(theme: theme, isDark: dark).maxContrastColor.usingColorSpace(.extendedSRGB))
        #expect(abs(resolved.redComponent - expected.redComponent) < 1e-4)
        #expect(abs(resolved.greenComponent - expected.greenComponent) < 1e-4)
        #expect(abs(resolved.blueComponent - expected.blueComponent) < 1e-4)
    }

    @Test func anAcceptedDragShowsTheCard() throws {
        let fixture = try Overlay()
        #expect(fixture.overlay.draggingEntered(fixture.session) == .move)
        #expect(fixture.overlay.showsCard)
    }

    @Test func theSessionsOwnItemBecomesTheCardForTheIncomingPane() throws {
        let fixture = try Overlay()
        _ = fixture.overlay.draggingEntered(fixture.session)
        #expect(fixture.sessionItem.draggingFrame.size == fixture.incomingSize)
        #expect(fixture.sessionItem.draggingFrame.origin == NSPoint(x: 30, y: 40))
        #expect(SplitDropCardTests.contents(fixture.sessionItem) !== fixture.rowImage)
    }

    @Test func anotherItemKeepsItsImage() throws {
        let fixture = try Overlay()
        _ = fixture.overlay.draggingEntered(fixture.session)
        #expect(fixture.otherItem.draggingFrame.size == Overlay.rowSize)
    }

    @Test func aStackTargetRerendersTheCardOnceAtTheInSlotPaneSize() throws {
        let fixture = try Overlay()
        _ = fixture.overlay.draggingEntered(fixture.session)
        let entered = fixture.incomingSize
        let calls = fixture.session.calls.count
        fixture.moveToStackTarget()
        _ = fixture.overlay.draggingUpdated(fixture.session)
        let stacked = fixture.incomingSize
        #expect(stacked != entered)
        #expect(fixture.session.calls.count == calls + 1)
        #expect(fixture.sessionItem.draggingFrame.size == stacked)
        #expect(fixture.sessionItem.draggingFrame.origin == NSPoint(x: 30, y: 40))
    }

    @Test func anUnchangedSizeKeepsTheCardWithoutAnotherRender() throws {
        let fixture = try Overlay()
        _ = fixture.overlay.draggingEntered(fixture.session)
        fixture.moveToStackTarget()
        _ = fixture.overlay.draggingUpdated(fixture.session)
        let calls = fixture.session.calls.count
        _ = fixture.overlay.draggingUpdated(fixture.session)
        #expect(fixture.session.calls.count == calls)
    }

    @Test func exitPutsBackTheRowsOwnImageAndSizeAtTheSameBottomLeft() throws {
        let fixture = try Overlay()
        _ = fixture.overlay.draggingEntered(fixture.session)
        fixture.overlay.draggingExited(fixture.session)
        #expect(!fixture.overlay.showsCard)
        #expect(fixture.sessionItem.draggingFrame == NSRect(x: 30, y: 40, width: 206, height: 36))
        #expect(SplitDropCardTests.contents(fixture.sessionItem) === fixture.rowImage)
    }

    @Test func aSecondExitWithoutACardChangesNothing() throws {
        let fixture = try Overlay()
        _ = fixture.overlay.draggingEntered(fixture.session)
        fixture.overlay.draggingExited(fixture.session)
        let calls = fixture.session.calls.count
        fixture.overlay.draggingExited(fixture.session)
        #expect(fixture.session.calls.count == calls)
    }

    @Test func theDragsEndForgetsTheCard() throws {
        let fixture = try Overlay()
        _ = fixture.overlay.draggingEntered(fixture.session)
        fixture.overlay.draggingEnded(fixture.session)
        #expect(!fixture.overlay.showsCard)
    }

    @Test func aDragTheOverlayDoesNotAcceptGetsNoCard() throws {
        let fixture = try Overlay()
        let refused = Drag()
        refused.source = fixture.row
        refused.draggingDestinationWindow = fixture.window
        refused.draggingPasteboard.setString(UUID().uuidString, forType: Overlay.type)
        refused.items = [SplitDropCardTests.item(Overlay.type, "stale", frame: NSRect(x: 10, y: 10, width: 206, height: 36))]
        refused.draggingLocation = fixture.host.convert(NSPoint(x: 4, y: 300), to: nil)
        #expect(fixture.overlay.draggingEntered(refused).isEmpty)
        #expect(!fixture.overlay.showsCard)
        #expect(refused.calls.isEmpty)
    }

    @Test func aRefusedDragsExitLeavesItsImageAlone() throws {
        let fixture = try Overlay()
        let refused = Drag()
        refused.source = fixture.row
        refused.draggingDestinationWindow = fixture.window
        refused.draggingPasteboard.setString(UUID().uuidString, forType: Overlay.type)
        let item = SplitDropCardTests.item(Overlay.type, "stale", frame: NSRect(x: 10, y: 10, width: 206, height: 36))
        refused.items = [item]
        refused.draggingLocation = fixture.host.convert(NSPoint(x: 4, y: 300), to: nil)
        _ = fixture.overlay.draggingEntered(refused)
        fixture.overlay.draggingExited(refused)
        #expect(refused.calls.isEmpty)
        #expect(item.draggingFrame.size == Overlay.rowSize)
    }
}
