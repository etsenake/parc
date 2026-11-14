import AppKit

struct ThemeChromePalette: Equatable {
    var contentAppearance: NSAppearance?
}

@MainActor final class ViewDisplayFrameDriver {
    func start(in view: NSView, onFrame: @escaping () -> Bool) {}
    func stop() {}
}

@main struct HistorySwipeOverlayViewTests {
    static var count = 0

    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("HistorySwipeOverlayView: \(message)") }
    }

    static func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1e-6 }

    static func components(_ color: CGColor?) -> (white: CGFloat, alpha: CGFloat)? {
        guard let color, let gray = NSColor(cgColor: color)?.usingColorSpace(.genericGray) else { return nil }
        return (gray.whiteComponent, gray.alphaComponent)
    }

    @MainActor static func main() {
        let size = NSSize(width: 600, height: 400)
        let view = HistorySwipeOverlayView(frame: NSRect(origin: .zero, size: size))
        check(view.layer?.masksToBounds == true, "the overlay clips everything it draws to its pane")
        check(view.hitTest(NSPoint(x: 300, y: 200)) == nil, "the overlay lets every click through to the page")
        check(!view.isAccessibilityElement() && view.accessibilityChildren()?.isEmpty == true,
              "the overlay stays out of the accessibility tree")

        check(view.subviews.count == 2, "the overlay holds a shadow and the indicator")
        let shadow = view.subviews[0], capsule = view.subviews[1]
        check(shadow.isHidden && capsule.isHidden, "nothing shows before a swipe begins")
        check(capsule.layer?.masksToBounds == true && capsule.layer?.cornerCurve == .continuous
              && capsule.layer?.borderWidth == 1, "the indicator clips its contents to its own continuous-corner shape with a 1 pt ring")
        let material = capsule.subviews.compactMap { $0 as? NSVisualEffectView }.first
        check(material?.material == .popover && material?.blendingMode == .withinWindow && material?.state == .active,
              "the indicator uses the active popover material blended within the window")
        let shade = shadow.layer?.sublayers?.first
        check(shadow.layer?.masksToBounds == false && shade?.shadowRadius == 8
              && shade?.shadowOffset == CGSize(width: 0, height: -2), "the shadow is soft and drops 2 pt")

        let dark = NSAppearance(named: .darkAqua), light = NSAppearance(named: .aqua)
        view.palette = ThemeChromePalette(contentAppearance: dark)
        check(view.appearance?.name == .darkAqua, "the overlay takes the palette's content appearance")
        let darkRing = components(capsule.layer?.borderColor)
        check(darkRing.map { close($0.white, 1) && abs($0.alpha - 0.15) < 0.002 } == true
              && abs((shade?.shadowOpacity ?? 0) - 0.25) < 1e-6, "a dark palette gives a white 15% ring and a 25% shadow")
        view.palette = ThemeChromePalette(contentAppearance: light)
        check(view.appearance?.name == .aqua, "changing the palette changes the appearance")
        let lightRing = components(capsule.layer?.borderColor)
        check(lightRing.map { close($0.white, 0) && abs($0.alpha - 0.125) < 0.002 } == true
              && abs((shade?.shadowOpacity ?? 0) - 0.2) < 1e-6, "a light palette gives a black 12.5% ring and a 20% shadow")
        view.palette = ThemeChromePalette(contentAppearance: dark)
        check(abs((shade?.shadowOpacity ?? 0) - 0.25) < 1e-6 && components(capsule.layer?.borderColor).map { close($0.white, 1) } == true,
              "switching back to dark restores the dark shadow and ring")
        view.palette = nil
        check(view.appearance == nil, "without a palette the overlay inherits its window's appearance")

        view.handle(.begin(.back))
        view.handle(.progress(HistorySwipeProgress(fraction: 1, stretch: 1)))
        let resting = NSRect(x: 14, y: (size.height - 72) / 2, width: 72, height: 72)
        check(!capsule.isHidden && capsule.frame == resting && shadow.frame == resting,
              "at the commit point the circle sits 14 pt inside the pane's left edge, centred vertically")
        check(close(capsule.layer?.cornerRadius ?? 0, 36) && shade?.frame == NSRect(x: 0, y: 0, width: 72, height: 72)
              && shade?.shadowPath?.boundingBox == CGRect(x: 0, y: 0, width: 72, height: 72), "the indicator and its shadow are circles")
        let chevron = capsule.subviews.compactMap { $0 as? NSImageView }.first
        check(chevron?.image != nil && chevron?.frame == NSRect(x: 22, y: 22, width: 28, height: 28)
              && chevron?.contentTintColor == .labelColor, "a 28 pt label-coloured chevron sits in the circle's centre")
        check(view.hitTest(NSPoint(x: resting.midX, y: resting.midY)) == nil, "the indicator itself lets clicks through")
        let list = capsule.subviews.first { !($0 is NSVisualEffectView) && !($0 is NSImageView) && !$0.subviews.isEmpty }
        check(list?.isHidden == true, "the list stays hidden until the hold")

        view.handle(.cancel)
        let forward = HistorySwipeOverlayView(frame: NSRect(origin: .zero, size: size))
        forward.handle(.begin(.forward))
        forward.handle(.progress(HistorySwipeProgress(fraction: 1, stretch: 1)))
        check(forward.subviews[1].frame.maxX == size.width - 14, "a Forward swipe mirrors the circle to the right edge")
        print("HistorySwipeOverlayView: \(count) checks passed")
    }
}
