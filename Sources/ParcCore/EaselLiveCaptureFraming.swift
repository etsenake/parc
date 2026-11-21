import Foundation

enum EaselCaptureGeometry {
    static let elementOutset: Double = 2

    static func elementCaptureArea(elementRect: EaselRect, viewport: EaselPoint) -> EaselRect? {
        let minX = max(0, elementRect.x - elementOutset), minY = max(0, elementRect.y - elementOutset)
        let maxX = min(viewport.x, elementRect.x + elementRect.width + elementOutset)
        let maxY = min(viewport.y, elementRect.y + elementRect.height + elementOutset)
        guard maxX > minX, maxY > minY else { return nil }
        return EaselRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func layout(captureArea: EaselRect, viewport: EaselPoint, scroll: EaselPoint,
                       pageZoom: Double, visualScale: Double) -> EaselCaptureLayout? {
        let factor = pageZoom * visualScale
        guard factor.isFinite, factor > 0 else { return nil }
        let layout = EaselCaptureLayout(viewport: viewport, scroll: scroll,
            region: EaselRect(x: captureArea.x / factor, y: captureArea.y / factor,
                              width: captureArea.width / factor, height: captureArea.height / factor))
        return layout.isValid ? layout : nil
    }

    static func displaySize(_ layout: EaselCaptureLayout, availableWidth: Double, availableHeight: Double,
                            pageZoom: Double) -> (width: Double, height: Double) {
        let aspect = layout.region.width / layout.region.height
        let width = max(0, min(availableWidth, max(1, availableHeight) * aspect,
                               layout.viewport.x * pageZoom, layout.viewport.y * pageZoom * aspect))
        return (width, width / aspect)
    }

    struct Framing: Equatable {
        var scale: Double
        var scrollTarget: EaselPoint
        var documentRegion: EaselRect
    }

    static func framing(_ layout: EaselCaptureLayout, displayWidth: Double, pageZoom: Double) -> Framing? {
        let scale = displayWidth / (layout.region.width * pageZoom)
        guard scale.isFinite, scale > 0, scale <= 10_000 else { return nil }
        return Framing(scale: scale,
                       scrollTarget: EaselPoint(x: layout.scroll.x * scale, y: layout.scroll.y * scale),
                       documentRegion: EaselRect(x: layout.scroll.x + layout.region.x, y: layout.scroll.y + layout.region.y,
                                                 width: layout.region.width, height: layout.region.height))
    }
}

struct EaselLiveFraming: Equatable {
    enum Phase: Equatable { case waiting, framed, failed }
    enum Outcome: Equatable { case reveal, keepWaiting, backToSnapshot }

    static let liningUp = "Lining up the region you captured…"
    static let failureBadge = "Snapshot · couldn't go live"
    static let failureHelp = "The live page couldn't line up with the region you captured, so the card stays a snapshot. The site may have changed; you can try Make live again."

    private(set) var phase: Phase = .waiting

    var revealsPage: Bool { phase == .framed }

    mutating func pageChanged() { phase = .waiting }

    mutating func positioned(success: Bool, pageStillLoading: Bool) -> Outcome {
        if success { phase = .framed; return .reveal }
        if pageStillLoading { phase = .waiting; return .keepWaiting }
        phase = .failed
        return .backToSnapshot
    }

    static func admitsPageScrolling(framesCapture: Bool) -> Bool { !framesCapture }
}
