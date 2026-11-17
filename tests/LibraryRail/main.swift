import AppKit
import QuartzCore

@main
struct LibraryRailChecks {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() { run() }
}

@MainActor
func run() {
    NSApplication.shared.setActivationPolicy(.prohibited)
    SystemOverrides.install()
    FrameSources.install()
    Redraws.install()
    SystemOverrides.reduceMotion = false
    defer { SystemOverrides.reduceMotion = nil }
    var count = 0
    func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); count += 1
    }
    let primary = NSColor.black, secondary = NSColor.white
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
    root.appearance = NSAppearance(named: .aqua)
    window.contentView = root

    func makeTile(_ title: String, _ name: LibraryRailAnimation.Name) -> LibraryRailTile {
        let tile = LibraryRailTile(title, animation: name, hasProgressBadge: true)
        tile.iconColors = (primary, secondary)
        tile.frame = NSRect(x: 0, y: 0, width: LibraryRailLayout.width - 15, height: LibraryRailLayout.tileHeight)
        tile.layoutSubtreeIfNeeded()
        expect(tile.progress!.frame.size == NSSize(width: 28, height: 28), "The idle badge holds a 28-point icon slot")
        return tile
    }
    func bitmap(_ size: NSSize) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: Int(size.width * 2) * 4, bitsPerPixel: 32)!
        rep.size = size
        return rep
    }
    func bytes(_ rep: NSBitmapImageRep) -> [UInt8] {
        Array(UnsafeBufferPointer(start: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh))
    }
    var candidates: [String: [UInt8]] = [:]
    func candidate(_ tile: LibraryRailTile, frame: Double) -> [UInt8] {
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
    func capture(_ tile: LibraryRailTile) -> [UInt8] {
        let art = tile.progress!.superview!
        let rep = bitmap(art.bounds.size)
        art.cacheDisplay(in: art.bounds, to: rep)
        return bytes(rep)
    }
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
    func playTimers(_ body: () -> Void) -> [FrameSource] { FrameSources.scheduled(during: body) }
    var clock: CFTimeInterval = 0
    func makeClockedTile(_ title: String, _ name: LibraryRailAnimation.Name) -> LibraryRailTile {
        let tile = makeTile(title, name)
        tile.now = { clock }
        return tile
    }

    let composition = LibraryRailAnimation.named(.archive)!
    expect(composition.frameRate == 60 && composition.startFrame == 0 && composition.frame(forMarker: "hover-start") == 1
           && composition.frame(forMarker: "selection-end") == 35,
           "Selection plays frames 1 to 35 of a 60-frames-a-second composition that rests on frame 0")

    let opening = makeClockedTile("Archived Tabs", .archive)
    expect(playTimers { opening.state = .on }.isEmpty, "A page selected before its window schedules no play")
    expect(opening.subviews[0].layer?.animation(forKey: "parc.rail.fill") == nil && opening.currentEmphasis == 1,
           "A page selected before its window lights up without fading")
    root.addSubview(opening)
    clock += 0.3
    var drawn = capture(opening)
    expect(matches(drawn, opening, frame: 0) && score(drawn, opening, 15...23) > 10,
           "A page selected before its window rests on the start frame instead of playing")
    opening.removeFromSuperview()

    let media = makeClockedTile("Media", .media)
    root.addSubview(media)
    let art = media.progress!.superview!
    let mediaFill = media.subviews[0].layer!
    expect(matches(capture(media), media, frame: 0), "An unplayed page shows the composition's start frame")
    var start = clock
    let play = playTimers { media.state = .on }
    expect(play.count == 1 && play[0].timer?.timeInterval == 1.0 / 60 && play[0].isLive,
           "Selection drives its hop and its fade from one 60-a-second timer")
    expect((mediaFill.animation(forKey: "parc.rail.fill") as? CABasicAnimation)?.duration == LibraryRailMotion.arrival
           && media.currentEmphasis == 0, "Selection eases the fill and the tile's ink in instead of snapping")
    clock = start + LibraryRailMotion.arrival / 2
    expect(media.currentEmphasis > 0 && media.currentEmphasis < 1, "Halfway through the fade the tile is partly lit")
    clock = start + 0.375
    let redraws = Redraws.count(art)
    play[0].fire()
    expect(play[0].isLive && Redraws.count(art) > redraws && media.currentEmphasis == 1,
           "A tick mid-play redraws the art and keeps playing after the fade settles")
    drawn = capture(media)
    expect(matches(drawn, media, frame: 14.5) && score(drawn, media, 0...0) > 10,
           "Selection plays hover-start to selection-end at 60 percent of the composition's pace")
    clock = start + 0.4375
    media.state = .off
    expect((mediaFill.animation(forKey: "parc.rail.fill") as? CABasicAnimation)?.duration == LibraryRailMotion.departure,
           "Deselection eases the fill out a little quicker than it came in")
    play[0].fire()
    drawn = capture(media)
    expect(play[0].isLive && matches(drawn, media, frame: 16.75) && score(drawn, media, 0...1) > 10,
           "Deselection does not stop a play that is still running")
    let replay = playTimers { media.state = .on }
    drawn = capture(media)
    expect(replay.isEmpty && play[0].isLive && media.currentEmphasis == 1 && matches(drawn, media, frame: 16.75)
           && score(drawn, media, 1...1) > 10,
           "Reselection mid-play carries on with the running hop instead of jumping back to hover-start")
    clock = start + 0.625
    play[0].fire()
    expect(play[0].isLive && matches(capture(media), media, frame: 23.5), "The play keeps ticking until selection-end")
    clock = start + 1
    play[0].fire()
    expect(!play[0].isLive && matches(capture(media), media, frame: 35), "The tick that passes selection-end parks the play there")
    media.removeFromSuperview()

    let archive = makeClockedTile("Archived Tabs", .archive)
    root.addSubview(archive)
    start = clock
    let finished = playTimers { archive.state = .on }
    clock = start + 1
    drawn = capture(archive)
    expect(finished.count == 1 && matches(drawn, archive, frame: 35) && matches(drawn, archive, frame: 0),
           "A finished play parks on selection-end, which matches the start frame")
    finished[0].fire()
    expect(!finished[0].isLive, "A finished play stops ticking")
    expect(playTimers { archive.state = .on }.isEmpty, "Reselecting the selected page does not replay")
    clock = start + 1.1
    expect(matches(capture(archive), archive, frame: 35), "Reselecting the selected page keeps the parked frame")
    let fading = playTimers { archive.state = .off }
    clock = start + 1.15
    drawn = capture(archive)
    expect(fading.count == 1 && fading[0].isLive && archive.currentEmphasis > 0 && archive.currentEmphasis < 1
           && matches(drawn, archive, frame: 35) && matches(drawn, archive, frame: 0),
           "Deselection fades the tile down on the frame timer and keeps the parked selection-end frame")
    clock = start + 1.15 + LibraryRailMotion.departure
    fading[0].fire()
    expect(!fading[0].isLive && archive.currentEmphasis == 0, "The timer stops once the fade settles")
    start = clock
    let again = playTimers { archive.state = .on }
    clock = start + 0.1875
    again.first?.fire()
    drawn = capture(archive)
    expect(again.count == 1 && again[0].isLive && matches(drawn, archive, frame: 7.75) && score(drawn, archive, 35...35) > 10,
           "Selecting again replays from hover-start")
    archive.removeFromSuperview()
    expect(!again[0].isLive && archive.currentEmphasis == 1, "Leaving the window mid-play stops the play and settles the fade")
    root.addSubview(archive)
    drawn = capture(archive)
    clock += 0.25
    let later = capture(archive)
    expect(matches(drawn, archive, frame: 35) && matches(later, archive, frame: 35),
           "Leaving the window parks a running play on selection-end")
    archive.removeFromSuperview()

    let still = makeClockedTile("Archived Tabs", .archive)
    root.addSubview(still)
    SystemOverrides.reduceMotion = true
    let calm = playTimers { still.state = .on }
    clock += 0.3
    calm.first?.fire()
    drawn = capture(still)
    expect(calm.count == 1 && matches(drawn, still, frame: 0) && score(drawn, still, 15...23) > 10,
           "Reduce Motion fades the tile in place without the hop")
    clock += LibraryRailMotion.arrival
    calm.first?.fire()
    expect(calm.first?.isLive == false && still.currentEmphasis == 1, "Reduce Motion's fade settles and stops its timer")
    SystemOverrides.reduceMotion = false
    still.removeFromSuperview()

    let downloads = makeTile("Downloads", .downloads)
    root.addSubview(downloads)
    let badge = downloads.progress!, profile = UUID()
    var retirements: [(delay: TimeInterval, body: @MainActor () -> Void)] = []
    badge.after = { delay, body in retirements.append((delay, body)) }
    func flight(_ id: String, received: Int64, total: Int64 = 100, started: Double) -> BrowserDownload {
        var item = BrowserDownload(id: id, name: id, path: "/nonexistent/" + id, receivedBytes: received, totalBytes: total, status: .downloading)
        item.profileID = profile; item.nativeID = id; item.nativeIdentity = id + "-1"; item.startedAt = Date(timeIntervalSince1970: started)
        return item
    }
    badge.updateInFlight([flight("full", received: 100, started: 1)], profiles: [profile], enabled: true)
    expect(!badge.isHidden && badge.activity?.progress == 1 && badge.activity?.completed == false && retirements.isEmpty,
           "A badge that first appears at full progress does not play its completion")
    badge.updateInFlight([], profiles: [profile], enabled: true)
    expect(badge.isHidden && badge.subviews.isEmpty, "Nothing in flight retires the renderer")
    badge.updateInFlight([flight("a", received: 40, started: 1)], profiles: [profile], enabled: true)
    let renderer = badge.subviews.first
    badge.updateInFlight([flight("a", received: 100, started: 1)], profiles: [profile], enabled: true)
    expect(renderer != nil && badge.subviews.first === renderer && badge.activity?.completed == true,
           "Progress changing to 1 plays the completion on the same renderer")
    expect(retirements.count == 1 && retirements[0].delay == 1.45, "The completion settles at a 1.45-second deadline")
    badge.updateInFlight([flight("a", received: 100, started: 1), flight("b", received: 10, started: 2)], profiles: [profile], enabled: true)
    expect(badge.activity?.identity == DownloadLibraryIdentity(flight("b", received: 10, started: 2)) && badge.activity?.progress == 0.1
           && badge.activity?.completed == true && badge.subviews.first === renderer && retirements.count == 1,
           "A newer download in flight keeps the renderer, and its completion is not replayed or undone")
    func inked(_ drawn: [UInt8]) -> Bool {
        let rect = badge.frame, stride = Int(badge.superview!.bounds.width * 2) * 4
        for y in Int(rect.minY * 2)..<Int(rect.maxY * 2) {
            for x in Int(rect.minX * 2)..<Int(rect.maxX * 2) where drawn[y * stride + x * 4 + 3] > 0 { return true }
        }
        return false
    }
    expect(inked(capture(downloads)), "The played checkmark draws before its deadline")
    retirements[0].body()
    expect(!badge.isHidden && badge.activity?.completed == true && badge.subviews.isEmpty && !inked(capture(downloads)),
           "At the 1.45-second deadline the completion settles: nothing draws, and the slot persists without the icon")
    badge.updateInFlight([flight("b", received: 20, started: 2)], profiles: [profile], enabled: true)
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    expect(badge.activity?.progress == 0.2 && badge.activity?.completed == true && badge.subviews.isEmpty && retirements.count == 1,
           "Neither a progress tick nor an accessibility display change brings a settled completion back")
    badge.updateInFlight([flight("b", received: 10, started: 2)], profiles: [profile], enabled: false)
    expect(badge.isHidden && badge.activity == nil, "The badge leaves when the window cannot badge")
    badge.updateInFlight([flight("c", received: 5, total: 0, started: 3)], profiles: [profile], enabled: true)
    let fresh = badge.subviews.first
    expect(!badge.isHidden && badge.activity?.progress == nil && badge.activity?.completed == false
           && fresh != nil && fresh !== renderer,
           "An unknown total gets a fresh renderer with no completion")
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    let rebuilt = badge.subviews.first
    expect(badge.subviews.count == 1 && rebuilt !== fresh, "An accessibility display change rebuilds a live badge's renderer")
    badge.updateInFlight([flight("d", received: 40, started: 4)], profiles: [profile], enabled: true)
    badge.updateInFlight([flight("d", received: 100, started: 4)], profiles: [profile], enabled: true)
    expect(badge.activity?.completed == true && retirements.count == 2 && retirements[1].delay == 1.45,
           "A newer download reaching 1 plays its own completion")
    retirements[0].body()
    expect(badge.activity?.completed == true && badge.subviews.first === rebuilt, "A stale completion deadline leaves a newer completion playing")
    retirements[1].body()
    expect(!badge.isHidden && badge.subviews.isEmpty, "The newer completion settles at its own deadline")
    downloads.removeFromSuperview()
    expect(badge.isHidden && badge.activity == nil, "Leaving the window retires the badge")

    let compact = makeTile("Archived Tabs", .archive)
    expect(compact.parcTooltip == nil && compact.toolTip == nil, "A labelled tile has no tooltip")
    compact.showsLabel = false
    expect(compact.parcTooltip == TooltipConfiguration("Archived Tabs"), "A tile too short for its label shows its title as a tooltip")
    compact.showsLabel = true
    expect(compact.parcTooltip == nil, "The label's return removes it")

    window.close()
    expect(!NSApplication.shared.isActive, "The check never activates the application")
    print("Library rail: \(count) assertions passed")
}
