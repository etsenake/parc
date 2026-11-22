import AppKit
import Testing
@testable import Parc

struct CaptureLibraryTileTests {
    @MainActor private final class KeyedWindow: NSWindow {
        var key = true
        var pointer = NSPoint(x: -1000, y: -1000)
        override var isKeyWindow: Bool { key }
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    }

    struct Scene: Sendable, CustomTestStringConvertible {
        let name: String
        let kind: CaptureLibraryTile.Kind
        let width: CGFloat
        let height: CGFloat
        var aspect: CGFloat { width / height }
        var testDescription: String { name }
        static let wide = Scene(name: "wide image", kind: .image, width: 240, height: 120)
        static let tall = Scene(name: "tall image", kind: .image, width: 100, height: 200)
        static let capture = Scene(name: "capture", kind: .capture, width: 160, height: 100)
        static let files = [wide, tall]
    }

    @MainActor private final class Fixture {
        let window: KeyedWindow
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 137, height: 137))
        let tile = CaptureLibraryTile(frame: NSRect(x: 0, y: 0, width: 137, height: 137))
        let bounds = NSRect(x: 0, y: 0, width: 137, height: 137)
        let center = NSPoint(x: 68.5, y: 68.5)
        let ring = NSPoint(x: 2, y: 68.5)
        let corner = NSPoint(x: 2, y: 2)
        let side: CGFloat = 117
        let reduced: Bool

        init(_ scene: Scene? = .wide, kind: CaptureLibraryTile.Kind? = nil, reduced: Bool = true, scrolling: Bool = false) {
            _ = NSApplication.shared
            self.reduced = reduced
            window = KeyedWindow(contentRect: host.frame, styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.addSubview(tile)
            tile.reduceMotion = { [reduced] in reduced }
            let image = scene.map { NSImage(size: NSSize(width: $0.width, height: $0.height)) }
            tile.configure(kind: kind ?? scene?.kind ?? .image, image: image, scrolling: scrolling)
            tile.layoutSubtreeIfNeeded()
        }

        var parts: (plate: CALayer, placeholder: CALayer, paper: CALayer, border: CAShapeLayer, artwork: CALayer, play: CALayer) {
            let layers = tile.layer!.sublayers!
            return (layers[0], layers[1], layers[2], layers[3] as! CAShapeLayer, layers[4], layers[5])
        }

        var primary: CGFloat {
            var alpha: CGFloat = 0
            tile.effectiveAppearance.performAsCurrentDrawingAppearance { alpha = NSColor.labelColor.alphaComponent }
            return alpha
        }

        func near(_ a: NSRect, _ b: NSRect) -> Bool {
            abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01 && abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
        }

        func fitted(_ aspect: CGFloat, lit: Bool) -> (paper: NSRect, artwork: NSRect) {
            let room = side * (lit ? 1 : 0.95) - 8
            let size = aspect >= 1 ? NSSize(width: room, height: room / aspect) : NSSize(width: room * aspect, height: room)
            let artwork = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
            return (artwork.insetBy(dx: -4, dy: -4), artwork)
        }

        func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            let location = tile.convert(point, to: nil)
            if type == .mouseMoved {
                return NSEvent.mouseEvent(with: .mouseMoved, location: location, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            }
            return NSEvent.enterExitEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }

        func hoverIn(at point: NSPoint? = nil) { tile.mouseEntered(with: event(.mouseEntered, at: point ?? center)) }
        func hoverMove(to point: NSPoint) { tile.mouseMoved(with: event(.mouseMoved, at: point)) }
        func hoverOut() { tile.mouseExited(with: event(.mouseExited, at: .zero)) }
        func lit(_ lit: Bool) { if lit { hoverIn() } }
    }

    @MainActor @Test(arguments: [(0, CGFloat(1)), (1, CGFloat(2)), (2, CGFloat(0.5))])
    func theLiveGridDrawsCaptureAndFileThumbnailsAtTheirOwnAspectRatios(index: Int, aspect: CGFloat) async throws {
        let fixture = try await CaptureLibraryViewTests.Fixture(files: 2, captures: 1)
        defer { fixture.teardown() }
        let tile = try #require(fixture.tile(index))
        let image = try #require(tile.image)
        let drawn = try #require(tile.artworkRect)
        #expect(image.size.width / image.size.height == aspect)
        #expect(abs(drawn.width / drawn.height - aspect) < 0.001)
    }

    @MainActor @Test func aTileCreatedDuringLiveScrollingRefusesHoverUntilScrollingEnds() async throws {
        let fixture = try await CaptureLibraryViewTests.Fixture(files: 2)
        defer { fixture.teardown() }
        let scroll = try #require(fixture.grid.enclosingScrollView)
        let original = Set(fixture.grid.visibleItems().map { ObjectIdentifier($0.view) })
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        let late = fixture.folder.appendingPathComponent("late.png")
        try CaptureLibraryViewTests.Fixture.png().write(to: late)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)], ofItemAtPath: late.path)
        try await fixture.changes(late)
        let tile = try #require(fixture.tile(2))
        try #require(fixture.title(2) == "late.png" && !original.contains(ObjectIdentifier(tile)))
        fixture.window.pointer = tile.convert(NSPoint(x: tile.bounds.midX, y: tile.bounds.midY), to: nil)
        tile.mouseEntered(with: try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: fixture.window.pointer,
            modifierFlags: [], timestamp: 0, windowNumber: fixture.window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil)))
        let plate = try #require(tile.layer?.sublayers?.first)
        #expect(plate.frame == tile.bounds.insetBy(dx: 4, dy: 4))
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        #expect(plate.frame == tile.bounds)
    }

    @MainActor @Test(arguments: [0, 1])
    func replacingAFileRefreshesItsThumbnailAndKeepsItsHighlight(_ index: Int) async throws {
        let fixture = try await CaptureLibraryViewTests.Fixture(files: 2)
        defer { fixture.teardown() }
        fixture.select(1)
        let hovered = try #require(fixture.tile(0))
        fixture.window.pointer = hovered.convert(NSPoint(x: hovered.bounds.midX, y: hovered.bounds.midY), to: nil)
        hovered.resamplePointer()
        let file = fixture.file(index)
        let expected = index == 0 ? CGFloat(3) : 1 / CGFloat(3)
        try CaptureLibraryViewTests.Fixture.png(index == 0 ? 30 : 10, index == 0 ? 10 : 30).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 - Double(index) * 60)],
                                              ofItemAtPath: file.path)
        try await fixture.changes(file)
        let tile = try #require(fixture.tile(index))
        let drawn = try #require(tile.artworkRect)
        #expect(abs(drawn.width / drawn.height - expected) < 0.001)
        #expect(tile.layer?.sublayers?.first?.frame == tile.bounds)
        #expect(fixture.grid.selectionIndexPaths == [IndexPath(item: 1, section: 0)])
    }

    @MainActor @Test func previewUsesTheSelectedTilesDrawnThumbnailAndRetiresWithMedia() async throws {
        let fixture = try await CaptureLibraryViewTests.Fixture(files: 2)
        defer { fixture.teardown() }
        var parent: NSWindow?
        let preview = DownloadLibraryPreview(itemName: "media file", reduceMotion: { true },
            presentWindow: { _, owner in parent = owner }, isPresented: { _ in true })
        fixture.view.makeFilePreview = { preview }
        fixture.select(1)
        fixture.grid.onActivate?()
        await fixture.finish()
        let tile = try #require(fixture.tile(1))
        let drawn = try #require(tile.artworkRect)
        #expect(parent === fixture.window && preview.sourceImage === tile.image)
        #expect(preview.sourceRect?() == tile.convert(drawn, to: nil))
        fixture.view.invalidate()
        #expect(preview.sourceRect == nil)
    }

    @MainActor @Test(arguments: Scene.files + [Scene.capture], [false, true])
    func thePlateFillsTheCellWhenLitAndSitsFourPointsInsideAtRestWithAContinuousRadiusOfTwelve(_ scene: Scene, _ lit: Bool) {
        let fixture = Fixture(scene)
        fixture.lit(lit)
        let plate = fixture.parts.plate
        #expect(fixture.near(plate.frame, fixture.bounds.insetBy(dx: lit ? 0 : 4, dy: lit ? 0 : 4)))
        #expect(plate.cornerRadius == 12 && plate.cornerCurve == .continuous)
    }

    @MainActor @Test(arguments: Scene.files + [Scene.capture], [false, true])
    func thePlateIsPrimaryAtFifteenPercentWhenLitAndFivePercentAtRest(_ scene: Scene, _ lit: Bool) {
        let fixture = Fixture(scene)
        fixture.lit(lit)
        #expect(abs((fixture.parts.plate.backgroundColor?.alpha ?? 0) - fixture.primary * (lit ? 0.15 : 0.05)) < 0.001)
    }

    @MainActor @Test(arguments: Scene.files + [Scene.capture], [false, true])
    func theThumbnailFitsItsAspectInsideAFourPointBorderWithinTheOneHundredSeventeenPointFrame(_ scene: Scene, _ lit: Bool) {
        let fixture = Fixture(scene)
        fixture.lit(lit)
        #expect(fixture.near(fixture.parts.artwork.frame, fixture.fitted(scene.aspect, lit: lit).artwork))
    }

    @MainActor @Test(arguments: Scene.files, [false, true])
    func aFileThumbnailSitsOnPaperHuggingItsFittedImage(_ scene: Scene, _ lit: Bool) {
        let fixture = Fixture(scene)
        fixture.lit(lit)
        let parts = fixture.parts
        #expect(!parts.paper.isHidden && parts.border.isHidden)
        #expect(fixture.near(parts.paper.frame, fixture.fitted(scene.aspect, lit: lit).paper))
    }

    @MainActor @Test(arguments: Scene.files, [false, true])
    func thePaperShadowIsBlackLightAtRestAndDeeperWhenLit(_ scene: Scene, _ lit: Bool) {
        let fixture = Fixture(scene)
        fixture.lit(lit)
        let paper = fixture.parts.paper
        let down: CGFloat = paper.contentsAreFlipped() ? 1 : -1
        #expect(paper.shadowOpacity == (lit ? 0.2 : 0.1) && paper.shadowRadius == (lit ? 5 : 1))
        #expect(paper.shadowOffset == CGSize(width: 0, height: down * (lit ? 3 : 1)))
    }

    @MainActor @Test(arguments: [false, true])
    func aCaptureDrawsADashedOutlineInsteadOfPaper(_ lit: Bool) {
        let fixture = Fixture(.capture)
        fixture.lit(lit)
        let parts = fixture.parts
        #expect(parts.paper.isHidden && !parts.border.isHidden)
        #expect(fixture.near(parts.border.path!.boundingBox, fixture.fitted(Scene.capture.aspect, lit: lit).paper.insetBy(dx: 1, dy: 1)))
        #expect(parts.border.lineDashPhase == (lit ? 5 : 0))
    }

    @MainActor @Test func paperIsWhiteWithAContinuousRadiusOfTwoAndABlackShadow() {
        let paper = Fixture(.wide).parts.paper
        #expect(paper.cornerRadius == 2 && paper.cornerCurve == .continuous)
        #expect(paper.backgroundColor == NSColor.white.cgColor && paper.shadowColor == NSColor.black.cgColor)
    }

    @MainActor @Test func theCaptureOutlineIsWhiteFiftyPercentTwoPointsWithRoundCappedFivePointDashes() {
        let outline = Fixture(.capture).parts.border
        #expect(outline.lineWidth == 2 && outline.lineCap == .round && outline.lineDashPattern == [5])
        #expect(outline.fillColor == nil && outline.strokeColor == NSColor.white.withAlphaComponent(0.5).cgColor)
    }

    @MainActor @Test(arguments: [(CaptureLibraryTile.Kind.image, true), (.capture, true), (.video, false)])
    func onlyTheVideoTileCarriesThePlayBadge(_ kind: CaptureLibraryTile.Kind, _ hidden: Bool) {
        let fixture = Fixture(.wide, kind: kind)
        #expect(fixture.parts.play.isHidden == hidden)
    }

    @MainActor @Test func thePlayBadgeIsCenteredAndCarriesItsShadowInItsOwnImage() {
        let fixture = Fixture(.wide, kind: .video)
        let badge = fixture.parts.play
        #expect(badge.contents != nil && abs(badge.frame.midX - fixture.center.x) < 0.01 && abs(badge.frame.midY - fixture.center.y) < 0.01)
        #expect(badge.shadowOpacity == 0)
    }

    @MainActor @Test func anUnreadableVideoShowsTheBlankPlaceholder() {
        let fixture = Fixture(nil, kind: .video)
        let parts = fixture.parts
        #expect(parts.artwork.isHidden && parts.paper.isHidden && !parts.placeholder.isHidden)
        #expect(fixture.near(parts.placeholder.frame, NSRect(x: fixture.center.x - 58.5, y: fixture.center.y - 58.5, width: 117, height: 117)))
    }

    @MainActor @Test func thePlaceholderHasAContinuousRadiusOfEightAndPrimaryFivePercent() {
        let fixture = Fixture(nil, kind: .video)
        let placeholder = fixture.parts.placeholder
        #expect(placeholder.cornerRadius == 8 && placeholder.cornerCurve == .continuous)
        #expect(abs((placeholder.backgroundColor?.alpha ?? 0) - fixture.primary * 0.05) < 0.001)
    }

    @MainActor @Test func hoveringUsesASpringWithResponsePointOneEightAndDampingPointEight() throws {
        let fixture = Fixture(.wide, reduced: false)
        fixture.hoverIn()
        let spring = try #require(fixture.parts.plate.animation(forKey: "bounds") as? CASpringAnimation)
        #expect(spring.mass == 1 && abs(spring.stiffness - pow(2 * .pi / 0.18, 2)) < 0.001)
        #expect(abs(spring.damping - 4 * .pi * 0.8 / 0.18) < 0.001 && spring.duration == spring.settlingDuration)
    }

    @MainActor @Test func thePlateSpringGrowsFromTheRestingInsetToTheCellEdge() throws {
        let fixture = Fixture(.wide, reduced: false)
        fixture.hoverIn()
        let spring = try #require(fixture.parts.plate.animation(forKey: "bounds") as? CASpringAnimation)
        #expect((spring.fromValue as? NSValue)?.rectValue.size == fixture.bounds.insetBy(dx: 4, dy: 4).size)
        #expect((spring.toValue as? NSValue)?.rectValue.size == fixture.bounds.size)
    }

    @MainActor @Test func theFillPaperShadowAndThumbnailAllRideTheSameSpring() {
        let fixture = Fixture(.wide, reduced: false)
        fixture.hoverIn()
        let parts = fixture.parts
        let keys = Set((parts.paper.animationKeys() ?? []) + (parts.artwork.animationKeys() ?? []))
        #expect(keys.isSuperset(of: ["bounds", "shadowPath", "shadowOpacity", "shadowRadius", "shadowOffset"]))
        #expect(parts.plate.animation(forKey: "backgroundColor") != nil)
    }

    @MainActor @Test func theHiddenOutlineOfAFileTileGetsNoSpring() {
        let fixture = Fixture(.wide, reduced: false)
        fixture.hoverIn()
        #expect(fixture.parts.border.animationKeys() == nil)
    }

    @MainActor @Test func theHiddenPaperOfACaptureGetsNoSpring() {
        let fixture = Fixture(.capture, reduced: false)
        fixture.hoverIn()
        #expect(fixture.parts.paper.animationKeys() == nil)
    }

    @MainActor @Test func reduceMotionSnapsThePopWithoutAnyAnimation() {
        let fixture = Fixture(.wide, reduced: true)
        fixture.hoverIn()
        let parts = fixture.parts
        #expect(parts.plate.animationKeys() == nil && parts.paper.animationKeys() == nil && parts.artwork.animationKeys() == nil)
    }

    @MainActor @Test func leavingSpringsThePlateBackToItsRestingInset() throws {
        let fixture = Fixture(.wide, reduced: false)
        fixture.hoverIn()
        fixture.hoverOut()
        let back = fixture.parts.plate.animation(forKey: "bounds") as? CASpringAnimation
        #expect((back?.toValue as? NSValue)?.rectValue.size == fixture.bounds.insetBy(dx: 4, dy: 4).size)
    }

    @MainActor @Test func enteringThroughTheCellsOuterRingDoesNotLightTheTile() {
        let fixture = Fixture(.wide)
        fixture.hoverIn(at: fixture.ring)
        #expect(fixture.near(fixture.parts.plate.frame, fixture.bounds.insetBy(dx: 4, dy: 4)))
    }

    @MainActor @Test func movingOntoTheRestingPlateLightsTheTile() {
        let fixture = Fixture(.wide)
        fixture.hoverIn(at: fixture.ring)
        fixture.hoverMove(to: fixture.center)
        #expect(fixture.near(fixture.parts.plate.frame, fixture.bounds))
    }

    @MainActor @Test func theLitPlateReachesTheCellEdgeSoItsRingKeepsTheHover() {
        let fixture = Fixture(.wide)
        fixture.hoverIn()
        fixture.hoverMove(to: fixture.ring)
        #expect(fixture.near(fixture.parts.plate.frame, fixture.bounds))
    }

    @MainActor @Test func theCellCornerOutsideTheLitPlatesRoundingEndsTheHover() {
        let fixture = Fixture(.wide)
        fixture.hoverIn()
        fixture.hoverMove(to: fixture.corner)
        #expect(fixture.near(fixture.parts.plate.frame, fixture.bounds.insetBy(dx: 4, dy: 4)))
    }

    @MainActor @Test func onlyTheRestingPlateTakesClicks() {
        let fixture = Fixture(.wide)
        #expect(fixture.tile.hitTest(fixture.tile.convert(fixture.ring, to: fixture.host)) == nil)
        #expect(fixture.tile.hitTest(fixture.tile.convert(fixture.center, to: fixture.host)) != nil)
    }

    @MainActor @Test func aScrollStartKeepsACurrentHover() {
        let fixture = Fixture(.wide)
        fixture.hoverIn()
        fixture.tile.setScrolling(true)
        #expect(fixture.near(fixture.parts.plate.frame, fixture.bounds))
    }

    @MainActor @Test func leavingDuringALiveScrollClearsTheHover() {
        let fixture = Fixture(.wide)
        fixture.hoverIn()
        fixture.tile.setScrolling(true)
        fixture.hoverOut()
        #expect(fixture.near(fixture.parts.plate.frame, fixture.bounds.insetBy(dx: 4, dy: 4)))
    }

    @MainActor @Test func aPointerCrossingDuringALiveScrollDoesNotLightTheTile() {
        let fixture = Fixture(.wide)
        fixture.tile.setScrolling(true)
        fixture.hoverIn()
        #expect(fixture.near(fixture.parts.plate.frame, fixture.bounds.insetBy(dx: 4, dy: 4)))
    }

    @MainActor @Test func aTileCreatedDuringALiveScrollRefusesHover() {
        let fixture = Fixture(.wide, scrolling: true)
        fixture.hoverIn()
        #expect(fixture.near(fixture.parts.plate.frame, fixture.bounds.insetBy(dx: 4, dy: 4)))
    }

    @MainActor @Test func scrollEndUnderThePointerLightsTheTile() {
        let fixture = Fixture(.wide)
        fixture.tile.setScrolling(true)
        fixture.hoverIn()
        fixture.window.pointer = fixture.tile.convert(fixture.center, to: nil)
        fixture.tile.setScrolling(false)
        #expect(fixture.near(fixture.parts.plate.frame, fixture.bounds))
    }

    @MainActor @Test func theWindowLosingKeyClearsTheHover() {
        let fixture = Fixture(.wide)
        fixture.hoverIn()
        fixture.window.key = false
        fixture.tile.resamplePointer()
        #expect(fixture.near(fixture.parts.plate.frame, fixture.bounds.insetBy(dx: 4, dy: 4)))
    }

    @MainActor @Test(arguments: [false, true])
    func aSelectedTileIsLitAndADeselectedOneRests(_ selected: Bool) {
        let fixture = Fixture(.tall)
        fixture.tile.isSelected = true
        fixture.tile.isSelected = selected
        #expect(fixture.near(fixture.parts.plate.frame, fixture.bounds.insetBy(dx: selected ? 0 : 4, dy: selected ? 0 : 4)))
    }

    @MainActor @Test func selectionKeepsAFocusBorderOnlyForIncreaseContrast() {
        let fixture = Fixture(.tall)
        fixture.tile.isSelected = true
        #expect(fixture.parts.plate.borderWidth == (NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0))
    }

    @MainActor @Test func theDrawnThumbnailRectIsWhatAPreviewOpensFrom() {
        let fixture = Fixture(.wide)
        fixture.hoverIn()
        let rect = fixture.tile.artworkRect
        #expect(rect != nil && fixture.near(rect!, fixture.fitted(2, lit: true).artwork))
    }

    @MainActor @Test func aReplacedThumbnailKeepsTheLitStateAndFitsTheNewAspect() {
        let fixture = Fixture(.wide)
        fixture.tile.isSelected = true
        fixture.tile.setImage(NSImage(size: NSSize(width: 300, height: 100)))
        #expect(fixture.near(fixture.parts.artwork.frame, fixture.fitted(3, lit: true).artwork))
    }
}
