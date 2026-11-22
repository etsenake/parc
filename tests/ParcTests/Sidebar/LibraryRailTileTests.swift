import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcKit
@testable import ParcLibrary

@MainActor
struct LibraryRailTileTests {
    @MainActor final class Rail {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        let primary = NSColor.black, secondary = NSColor.white
        var clock: CFTimeInterval = 0
        var reduceMotion = false
        private(set) var timers: [Timer] = []
        private var animations: [LibraryRailAnimation.Name: LibraryRailAnimation] = [:]
        private var candidates: [String: [UInt8]] = [:]

        init() throws {
            window.isReleasedWhenClosed = false
            root.appearance = NSAppearance(named: .aqua)
            window.contentView = root
            for name in [LibraryRailAnimation.Name.media, .downloads, .easels, .spaces, .archive] {
                animations[name] = try LibraryRailMotionTests.animation(name.rawValue)
            }
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        func tile(_ title: String, _ name: LibraryRailAnimation.Name, shown: Bool = false) -> LibraryRailTile {
            let tile = LibraryRailTile(title, animation: name, hasProgressBadge: true)
            let animations = self.animations
            tile.loadAnimation = { animations[$0] }
            tile.reduceMotion = { [weak self] in self?.reduceMotion ?? false }
            tile.scheduleTicker = { [weak self] in self?.timers.append($0) }
            tile.now = { [weak self] in self?.clock ?? 0 }
            tile.iconColors = (primary, secondary)
            tile.frame = NSRect(x: 0, y: 0, width: LibraryRailLayout.width - 15, height: LibraryRailLayout.tileHeight)
            tile.layoutSubtreeIfNeeded()
            if shown { root.addSubview(tile) }
            return tile
        }

        func scheduled(during body: () -> Void) -> [Timer] {
            let start = timers.count
            body()
            return Array(timers[start...])
        }

        private func bitmap(_ size: NSSize) -> NSBitmapImageRep {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: Int(size.width * 2) * 4, bitsPerPixel: 32)!
            rep.size = size
            return rep
        }
        private func bytes(_ rep: NSBitmapImageRep) -> [UInt8] {
            Array(UnsafeBufferPointer(start: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh))
        }
        private func candidate(_ tile: LibraryRailTile, frame: Double) -> [UInt8] {
            let alpha = LibraryRailTile.artOpacity(emphasis: tile.currentEmphasis)
            let key = "\(tile.title)|\(alpha)|\(frame)"
            if let cached = candidates[key] { return cached }
            let art = tile.progress!.superview!
            let rep = bitmap(art.bounds.size)
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            let cg = context.cgContext
            cg.translateBy(x: 0, y: rep.size.height); cg.scaleBy(x: 1, y: -1)
            cg.setAlpha(alpha); cg.beginTransparencyLayer(auxiliaryInfo: nil)
            tile.animation!.draw(in: cg, rect: tile.progress!.frame, frame: frame, primary: primary.cgColor, secondary: secondary.cgColor)
            cg.endTransparencyLayer()
            context.flushGraphics()
            let result = bytes(rep)
            candidates[key] = result
            return result
        }
        func capture(_ view: NSView) -> [UInt8] {
            let rep = bitmap(view.bounds.size)
            view.cacheDisplay(in: view.bounds, to: rep)
            return bytes(rep)
        }
        func capture(_ tile: LibraryRailTile) -> [UInt8] { capture(tile.progress!.superview!) }
        func score(_ drawn: [UInt8], _ tile: LibraryRailTile, _ frames: ClosedRange<Double>) -> Double {
            let rect = tile.progress!.frame, stride = Int(tile.progress!.superview!.bounds.width * 2) * 4
            let x0 = Int(rect.minX * 2) * 4, x1 = Int(rect.maxX * 2) * 4, y0 = Int(rect.minY * 2), y1 = Int(rect.maxY * 2)
            var best = Double.infinity
            var frame = max(0, (frames.lowerBound * 4).rounded(.down) / 4)
            while frame <= frames.upperBound {
                let expected = candidate(tile, frame: frame)
                var sum = 0
                drawn.withUnsafeBufferPointer { a in
                    expected.withUnsafeBufferPointer { b in
                        for y in y0..<y1 { for x in (y * stride + x0)..<(y * stride + x1) { sum &+= abs(Int(a[x]) &- Int(b[x])) } }
                    }
                }
                best = min(best, Double(sum) / Double((x1 - x0) * (y1 - y0)))
                frame += 0.25
            }
            return best
        }
        func matches(_ drawn: [UInt8], _ tile: LibraryRailTile, frame: Double) -> Bool { score(drawn, tile, frame...frame) < 0.05 }
        func differs(_ drawn: [UInt8], _ tile: LibraryRailTile, _ frames: ClosedRange<Double>) -> Bool { score(drawn, tile, frames) > 10 }
    }

    private static func fill(_ tile: LibraryRailTile) -> CALayer { tile.subviews[0].layer! }
    private static func fillFade(_ tile: LibraryRailTile) -> CABasicAnimation? { fill(tile).animation(forKey: "parc.rail.fill") as? CABasicAnimation }

    @Test func theIdleBadgeHoldsATwentyEightPointIconSlot() throws {
        let rail = try Rail()
        #expect(rail.tile("Media", .media).progress?.frame.size == NSSize(width: 28, height: 28))
    }

    @Test func selectionPlaysFramesOneToThirtyFiveOfASixtyFrameCompositionRestingOnFrameZero() throws {
        let composition = try LibraryRailMotionTests.animation("archive")
        #expect(composition.frameRate == 60 && composition.startFrame == 0)
        #expect(composition.frame(forMarker: "hover-start") == 1 && composition.frame(forMarker: "selection-end") == 35)
    }

    @Test func aPageSelectedBeforeItsWindowSchedulesNoPlay() throws {
        let rail = try Rail()
        let opening = rail.tile("Archived Tabs", .archive)
        #expect(rail.scheduled { opening.state = .on }.isEmpty)
    }

    @Test func aPageSelectedBeforeItsWindowLightsUpWithoutFading() throws {
        let rail = try Rail()
        let opening = rail.tile("Archived Tabs", .archive)
        opening.state = .on
        #expect(Self.fillFade(opening) == nil)
        #expect(opening.currentEmphasis == 1)
    }

    @Test func aPageSelectedBeforeItsWindowRestsOnTheStartFrameInsteadOfPlaying() throws {
        let rail = try Rail()
        let opening = rail.tile("Archived Tabs", .archive)
        opening.state = .on
        rail.root.addSubview(opening)
        rail.clock += 0.3
        let drawn = rail.capture(opening)
        #expect(rail.matches(drawn, opening, frame: 0))
        #expect(rail.differs(drawn, opening, 15...23))
    }

    @Test func anUnplayedPageShowsTheCompositionsStartFrame() throws {
        let rail = try Rail()
        let media = rail.tile("Media", .media, shown: true)
        #expect(rail.matches(rail.capture(media), media, frame: 0))
    }

    @Test func selectionDrivesItsHopAndFadeFromOneSixtyASecondTimer() throws {
        let rail = try Rail()
        let media = rail.tile("Media", .media, shown: true)
        let play = rail.scheduled { media.state = .on }
        #expect(play.count == 1)
        #expect(play.first?.timeInterval == 1.0 / 60)
        #expect(play.first?.isValid == true)
    }

    @Test func selectionEasesTheFillAndTheInkInInsteadOfSnapping() throws {
        let rail = try Rail()
        let media = rail.tile("Media", .media, shown: true)
        media.state = .on
        #expect(Self.fillFade(media)?.duration == LibraryRailMotion.arrival)
        #expect(media.currentEmphasis == 0)
    }

    @Test func halfwayThroughTheFadeTheTileIsPartlyLit() throws {
        let rail = try Rail()
        let media = rail.tile("Media", .media, shown: true)
        media.state = .on
        rail.clock = LibraryRailMotion.arrival / 2
        #expect(media.currentEmphasis > 0 && media.currentEmphasis < 1)
    }

    private func playing(_ rail: Rail) -> (LibraryRailTile, Timer) {
        let media = rail.tile("Media", .media, shown: true)
        let play = rail.scheduled { media.state = .on }
        return (media, play[0])
    }

    @Test func aTickMidPlayRedrawsTheArtAndKeepsPlayingAfterTheFadeSettles() throws {
        let rail = try Rail()
        let (media, timer) = playing(rail)
        let art = try #require(media.progress?.superview)
        rail.clock = 0.375
        art.needsDisplay = false
        timer.fire()
        #expect(timer.isValid)
        #expect(art.needsDisplay)
        #expect(media.currentEmphasis == 1)
    }

    @Test func selectionPlaysHoverStartToSelectionEndAtSixtyPercentOfTheCompositionsPace() throws {
        let rail = try Rail()
        let (media, timer) = playing(rail)
        rail.clock = 0.375
        timer.fire()
        let drawn = rail.capture(media)
        #expect(rail.matches(drawn, media, frame: 14.5))
        #expect(rail.differs(drawn, media, 0...0))
    }

    @Test func deselectionEasesTheFillOutALittleQuickerThanItCameIn() throws {
        let rail = try Rail()
        let (media, _) = playing(rail)
        rail.clock = 0.4375
        media.state = .off
        #expect(Self.fillFade(media)?.duration == LibraryRailMotion.departure)
    }

    @Test func deselectionDoesNotStopAPlayThatIsStillRunning() throws {
        let rail = try Rail()
        let (media, timer) = playing(rail)
        rail.clock = 0.4375
        media.state = .off
        timer.fire()
        let drawn = rail.capture(media)
        #expect(timer.isValid)
        #expect(rail.matches(drawn, media, frame: 16.75))
        #expect(rail.differs(drawn, media, 0...1))
    }

    @Test func reselectionMidPlayCarriesOnWithTheRunningHop() throws {
        let rail = try Rail()
        let (media, timer) = playing(rail)
        rail.clock = 0.4375
        media.state = .off
        timer.fire()
        let replay = rail.scheduled { media.state = .on }
        let drawn = rail.capture(media)
        #expect(replay.isEmpty && timer.isValid)
        #expect(media.currentEmphasis == 1)
        #expect(rail.matches(drawn, media, frame: 16.75))
        #expect(rail.differs(drawn, media, 1...1))
    }

    @Test func thePlayKeepsTickingUntilSelectionEnd() throws {
        let rail = try Rail()
        let (media, timer) = playing(rail)
        rail.clock = 0.625
        timer.fire()
        #expect(timer.isValid)
        #expect(rail.matches(rail.capture(media), media, frame: 23.5))
    }

    @Test func theTickThatPassesSelectionEndParksThePlayThere() throws {
        let rail = try Rail()
        let (media, timer) = playing(rail)
        rail.clock = 1
        timer.fire()
        #expect(!timer.isValid)
        #expect(rail.matches(rail.capture(media), media, frame: 35))
    }

    private func finished(_ rail: Rail) -> (LibraryRailTile, Timer) {
        let archive = rail.tile("Archived Tabs", .archive, shown: true)
        let play = rail.scheduled { archive.state = .on }
        rail.clock = 1
        return (archive, play[0])
    }

    @Test func aFinishedPlayParksOnSelectionEndWhichMatchesTheStartFrame() throws {
        let rail = try Rail()
        let (archive, _) = finished(rail)
        let drawn = rail.capture(archive)
        #expect(rail.matches(drawn, archive, frame: 35))
        #expect(rail.matches(drawn, archive, frame: 0))
    }

    @Test func aFinishedPlayStopsTicking() throws {
        let rail = try Rail()
        let (_, timer) = finished(rail)
        timer.fire()
        #expect(!timer.isValid)
    }

    @Test func reselectingTheSelectedPageDoesNotReplay() throws {
        let rail = try Rail()
        let (archive, timer) = finished(rail)
        timer.fire()
        #expect(rail.scheduled { archive.state = .on }.isEmpty)
    }

    @Test func reselectingTheSelectedPageKeepsTheParkedFrame() throws {
        let rail = try Rail()
        let (archive, timer) = finished(rail)
        timer.fire()
        archive.state = .on
        rail.clock = 1.1
        #expect(rail.matches(rail.capture(archive), archive, frame: 35))
    }

    @Test func deselectionFadesTheTileDownOnTheFrameTimerAndKeepsTheParkedFrame() throws {
        let rail = try Rail()
        let (archive, timer) = finished(rail)
        timer.fire()
        rail.clock = 1.1
        let fading = rail.scheduled { archive.state = .off }
        rail.clock = 1.15
        let drawn = rail.capture(archive)
        #expect(fading.count == 1 && fading.first?.isValid == true)
        #expect(archive.currentEmphasis > 0 && archive.currentEmphasis < 1)
        #expect(rail.matches(drawn, archive, frame: 35) && rail.matches(drawn, archive, frame: 0))
    }

    @Test func theFadeTimerStopsOnceTheFadeSettles() throws {
        let rail = try Rail()
        let (archive, timer) = finished(rail)
        timer.fire()
        rail.clock = 1.1
        let fading = rail.scheduled { archive.state = .off }
        rail.clock = 1.1 + LibraryRailMotion.departure + 0.05
        fading[0].fire()
        #expect(!fading[0].isValid)
        #expect(archive.currentEmphasis == 0)
    }

    private func replaying(_ rail: Rail) -> (LibraryRailTile, Timer) {
        let (archive, timer) = finished(rail)
        timer.fire()
        let fading = rail.scheduled { archive.state = .off }
        rail.clock = 2
        fading.forEach { $0.fire() }
        let again = rail.scheduled { archive.state = .on }
        rail.clock = 2.1875
        again[0].fire()
        return (archive, again[0])
    }

    @Test func selectingAgainReplaysFromHoverStart() throws {
        let rail = try Rail()
        let (archive, timer) = replaying(rail)
        let drawn = rail.capture(archive)
        #expect(timer.isValid)
        #expect(rail.matches(drawn, archive, frame: 7.75))
        #expect(rail.differs(drawn, archive, 35...35))
    }

    @Test func leavingTheWindowMidPlayStopsThePlayAndSettlesTheFade() throws {
        let rail = try Rail()
        let (archive, timer) = replaying(rail)
        archive.removeFromSuperview()
        #expect(!timer.isValid)
        #expect(archive.currentEmphasis == 1)
    }

    @Test func leavingTheWindowParksARunningPlayOnSelectionEnd() throws {
        let rail = try Rail()
        let (archive, _) = replaying(rail)
        archive.removeFromSuperview()
        rail.root.addSubview(archive)
        let drawn = rail.capture(archive)
        rail.clock += 0.25
        #expect(rail.matches(drawn, archive, frame: 35))
        #expect(rail.matches(rail.capture(archive), archive, frame: 35))
    }

    @Test func reduceMotionFadesTheTileInPlaceWithoutTheHop() throws {
        let rail = try Rail()
        let still = rail.tile("Archived Tabs", .archive, shown: true)
        rail.reduceMotion = true
        let calm = rail.scheduled { still.state = .on }
        rail.clock = 0.3
        calm.first?.fire()
        let drawn = rail.capture(still)
        #expect(calm.count == 1)
        #expect(rail.matches(drawn, still, frame: 0))
        #expect(rail.differs(drawn, still, 15...23))
    }

    @Test func reduceMotionsFadeSettlesAndStopsItsTimer() throws {
        let rail = try Rail()
        let still = rail.tile("Archived Tabs", .archive, shown: true)
        rail.reduceMotion = true
        let calm = rail.scheduled { still.state = .on }
        rail.clock = LibraryRailMotion.arrival + 0.05
        calm.first?.fire()
        #expect(calm.first?.isValid == false)
        #expect(still.currentEmphasis == 1)
    }

    @Test func aLabelledTileHasNoTooltip() throws {
        let rail = try Rail()
        let compact = rail.tile("Archived Tabs", .archive)
        #expect(compact.parcTooltip == nil && compact.toolTip == nil)
    }

    @Test func aTileTooShortForItsLabelShowsItsTitleAsATooltip() throws {
        let rail = try Rail()
        let compact = rail.tile("Archived Tabs", .archive)
        compact.showsLabel = false
        #expect(compact.parcTooltip == TooltipConfiguration("Archived Tabs"))
    }

    @Test func theLabelsReturnRemovesTheTooltip() throws {
        let rail = try Rail()
        let compact = rail.tile("Archived Tabs", .archive)
        compact.showsLabel = false
        compact.showsLabel = true
        #expect(compact.parcTooltip == nil)
    }
}
