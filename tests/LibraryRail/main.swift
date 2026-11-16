import AppKit
import QuartzCore

@main
struct LibraryRailChecks {
    @MainActor static func main() { run() }
}

@MainActor
func run() {
    NSApplication.shared.setActivationPolicy(.prohibited)
    SystemOverrides.install()
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
        let alpha: CGFloat = tile.state == .on ? 1 : 0.7
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
    struct Drawn {
        let pixels: [UInt8]
        let elapsed: CFTimeInterval
    }
    func capture(_ tile: LibraryRailTile, since start: CFTimeInterval) -> Drawn {
        let art = tile.progress!.superview!
        let rep = bitmap(art.bounds.size)
        let before = CACurrentMediaTime()
        art.cacheDisplay(in: art.bounds, to: rep)
        return Drawn(pixels: bytes(rep), elapsed: (before + CACurrentMediaTime()) / 2 - start)
    }
    func score(_ drawn: Drawn, _ tile: LibraryRailTile, _ frames: ClosedRange<Double>) -> Double {
        let rect = tile.progress!.frame, stride = Int(tile.progress!.superview!.bounds.width * 2) * 4
        let x0 = Int(rect.minX * 2) * 4, x1 = Int(rect.maxX * 2) * 4, y0 = Int(rect.minY * 2), y1 = Int(rect.maxY * 2)
        var best = Double.infinity
        var frame = max(0, (frames.lowerBound * 4).rounded(.down) / 4)
        while frame <= frames.upperBound {
            let expected = candidate(tile, frame: frame)
            var sum = 0
            drawn.pixels.withUnsafeBufferPointer { a in
                expected.withUnsafeBufferPointer { b in
                    for y in y0..<y1 { for x in (y * stride + x0)..<(y * stride + x1) { sum &+= abs(Int(a[x]) &- Int(b[x])) } }
                }
            }
            best = min(best, Double(sum) / Double((x1 - x0) * (y1 - y0)))
            frame += 0.25
        }
        return best
    }
    func spin(until target: CFTimeInterval) {
        while CACurrentMediaTime() < target {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: min(0.002, max(0, target - CACurrentMediaTime()))))
        }
    }
    func playing(_ drawn: Drawn) -> ClosedRange<Double> {
        let frame = min(35, 1 + 60 * drawn.elapsed)
        return (frame - 1.5)...(frame + 1.5)
    }
    let exact = 0.05, moving = 1.0

    let opening = makeTile("Archived Tabs", .archive)
    opening.state = .on
    root.addSubview(opening)
    var start = CACurrentMediaTime()
    spin(until: start + 0.3)
    var drawn = capture(opening, since: start)
    expect(score(drawn, opening, 0...0) < exact && score(drawn, opening, 15...23) > 10,
           "A page selected before its window rests on the start frame instead of playing")
    opening.removeFromSuperview()

    let media = makeTile("Media", .media)
    root.addSubview(media)
    drawn = capture(media, since: CACurrentMediaTime())
    expect(score(drawn, media, 0...0) < exact, "An unplayed page shows the composition's start frame")
    start = CACurrentMediaTime()
    media.state = .on
    spin(until: start + 0.225)
    drawn = capture(media, since: start)
    expect(score(drawn, media, playing(drawn)) < moving && score(drawn, media, 0...0) > 10,
           "Selection plays hover-start to selection-end at the composition's 60 frames a second")
    expect(CACurrentMediaTime() - start < 0.5, "The deselection happens mid-play")
    media.state = .off
    spin(until: start + 0.3)
    drawn = capture(media, since: start)
    expect(score(drawn, media, playing(drawn)) < moving && score(drawn, media, 0...1) > 10,
           "Deselection does not stop a play that is still running")
    expect(CACurrentMediaTime() - start < 0.4, "The reselection happens mid-play")
    let restart = CACurrentMediaTime()
    media.state = .on
    drawn = capture(media, since: restart)
    let previous = capture(media, since: start)
    expect(score(drawn, media, playing(drawn)) < moving && score(previous, media, playing(previous)) > 10,
           "Reselection mid-play restarts from hover-start")
    spin(until: restart + 0.1)
    drawn = capture(media, since: restart)
    expect(score(drawn, media, playing(drawn)) < moving, "The restarted play runs at 60 frames a second")
    media.removeFromSuperview()

    let archive = makeTile("Archived Tabs", .archive)
    root.addSubview(archive)
    let parked = 34.9...35.0, rest = 0.0...0.0
    start = CACurrentMediaTime()
    archive.state = .on
    spin(until: start + 0.75)
    drawn = capture(archive, since: start)
    expect(score(drawn, archive, parked) < exact && score(drawn, archive, rest) < exact,
           "A finished play parks on selection-end, which matches the start frame")
    archive.state = .on
    spin(until: start + 0.85)
    drawn = capture(archive, since: start)
    expect(score(drawn, archive, parked) < exact, "Reselecting the selected page does not replay")
    archive.state = .off
    spin(until: start + 0.9)
    drawn = capture(archive, since: start)
    expect(score(drawn, archive, parked) < exact && score(drawn, archive, rest) < exact,
           "Deselection keeps the parked selection-end frame")
    start = CACurrentMediaTime()
    archive.state = .on
    spin(until: start + 0.1)
    drawn = capture(archive, since: start)
    expect(score(drawn, archive, playing(drawn)) < moving && score(drawn, archive, parked) > 10,
           "Selecting again replays from hover-start")

    expect(CACurrentMediaTime() - start < 0.5, "Leaving the window happens mid-play")
    archive.removeFromSuperview()
    root.addSubview(archive)
    let returned = CACurrentMediaTime()
    drawn = capture(archive, since: returned)
    spin(until: returned + 0.2)
    let later = capture(archive, since: returned)
    expect(score(drawn, archive, parked) < exact && score(later, archive, parked) < exact,
           "Leaving the window parks a running play on selection-end")
    archive.removeFromSuperview()

    let still = makeTile("Archived Tabs", .archive)
    root.addSubview(still)
    SystemOverrides.reduceMotion = true
    start = CACurrentMediaTime()
    still.state = .on
    spin(until: start + 0.3)
    drawn = capture(still, since: start)
    expect(score(drawn, still, 0...0) < exact && score(drawn, still, 15...23) > 10, "Reduce Motion keeps the start frame")
    SystemOverrides.reduceMotion = false
    still.removeFromSuperview()

    let downloads = makeTile("Downloads", .downloads)
    root.addSubview(downloads)
    let badge = downloads.progress!, profile = UUID()
    func flight(_ id: String, received: Int64, total: Int64 = 100, started: Double) -> BrowserDownload {
        var item = BrowserDownload(id: id, name: id, path: "/nonexistent/" + id, receivedBytes: received, totalBytes: total, status: .downloading)
        item.profileID = profile; item.nativeID = id; item.nativeIdentity = id + "-1"; item.startedAt = Date(timeIntervalSince1970: started)
        return item
    }
    badge.updateInFlight([flight("full", received: 100, started: 1)], profiles: [profile], enabled: true)
    expect(!badge.isHidden && badge.activity?.progress == 1 && badge.activity?.completed == false,
           "A badge that first appears at full progress does not play its completion")
    badge.updateInFlight([], profiles: [profile], enabled: true)
    expect(badge.isHidden && badge.subviews.isEmpty, "Nothing in flight retires the renderer")
    badge.updateInFlight([flight("a", received: 40, started: 1)], profiles: [profile], enabled: true)
    let renderer = badge.subviews.first
    badge.updateInFlight([flight("a", received: 100, started: 1)], profiles: [profile], enabled: true)
    start = CACurrentMediaTime()
    expect(renderer != nil && badge.subviews.first === renderer && badge.activity?.completed == true,
           "Progress changing to 1 plays the completion on the same renderer")
    badge.updateInFlight([flight("a", received: 100, started: 1), flight("b", received: 10, started: 2)], profiles: [profile], enabled: true)
    expect(badge.activity?.identity == DownloadLibraryIdentity(flight("b", received: 10, started: 2)) && badge.activity?.progress == 0.1
           && badge.activity?.completed == true && badge.subviews.first === renderer,
           "A newer download in flight keeps the renderer, and its completion is not replayed or undone")
    func inked(_ drawn: Drawn) -> Bool {
        let rect = badge.frame, stride = Int(badge.superview!.bounds.width * 2) * 4
        for y in Int(rect.minY * 2)..<Int(rect.maxY * 2) {
            for x in Int(rect.minX * 2)..<Int(rect.maxX * 2) where drawn.pixels[y * stride + x * 4 + 3] > 0 { return true }
        }
        return false
    }
    spin(until: start + 0.5)
    expect(inked(capture(downloads, since: start)), "The played checkmark draws before its deadline")
    spin(until: start + 1.6)
    expect(!badge.isHidden && badge.activity?.completed == true && badge.subviews.isEmpty && !inked(capture(downloads, since: start)),
           "At the 1.45-second deadline the completion settles: nothing draws, and the slot persists without the icon")
    badge.updateInFlight([flight("b", received: 20, started: 2)], profiles: [profile], enabled: true)
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    spin(until: CACurrentMediaTime() + 0.1)
    expect(badge.activity?.progress == 0.2 && badge.activity?.completed == true && badge.subviews.isEmpty,
           "Neither a progress tick nor an accessibility display change brings a settled completion back")
    badge.updateInFlight([flight("b", received: 10, started: 2)], profiles: [profile], enabled: false)
    expect(badge.isHidden && badge.activity == nil, "The badge leaves when the window cannot badge")
    badge.updateInFlight([flight("c", received: 5, total: 0, started: 3)], profiles: [profile], enabled: true)
    expect(!badge.isHidden && badge.activity?.progress == nil && badge.activity?.completed == false
           && badge.subviews.first != nil && badge.subviews.first !== renderer,
           "An unknown total gets a fresh renderer with no completion")
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
