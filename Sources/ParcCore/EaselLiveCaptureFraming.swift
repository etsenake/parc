import Foundation

package enum EaselCaptureGeometry {
    static let elementOutset: Double = 2

    package static func elementCaptureArea(elementRect: EaselRect, viewport: EaselPoint) -> EaselRect? {
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

    package static func captured(viewport: EaselPoint, scroll: EaselPoint, region: EaselRect,
                         scrollContainers: [EaselScrollContainer], fullPage: Bool = false) -> EaselCaptureLayout? {
        let layout = EaselCaptureLayout(viewport: viewport, scroll: scroll, region: region,
                                        scrollContainers: scrollContainers.isEmpty ? nil : scrollContainers,
                                        fullPage: fullPage ? true : nil)
        return layout.isValid ? layout : nil
    }

    package static func liveFrame(_ frame: EaselRect, layout: EaselCaptureLayout) -> EaselRect {
        EaselRect(x: frame.x, y: frame.y, width: frame.width, height: max(1, frame.width * layout.screenAspect))
    }

    package static func snapshotFrame(_ frame: EaselRect, imageWidth: Double, imageHeight: Double) -> EaselRect {
        guard imageWidth.isFinite, imageHeight.isFinite, imageWidth > 0, imageHeight > 0 else { return frame }
        return EaselRect(x: frame.x, y: frame.y, width: frame.width, height: max(1, frame.width * imageHeight / imageWidth))
    }

    package static func settingLive(_ item: EaselItem, enabled: Bool, imageSize: CGSize?) -> EaselItem {
        var next = item
        next.liveCapture = enabled
        guard let layout = item.captureLayout, layout.isFullPage, (item.liveCapture == true) != enabled else { return next }
        if enabled {
            next.frame = liveFrame(item.frame, layout: layout)
        } else if let imageSize {
            next.frame = snapshotFrame(item.frame, imageWidth: Double(imageSize.width), imageHeight: Double(imageSize.height))
        }
        return next
    }

    package static func displaySize(_ layout: EaselCaptureLayout, availableWidth: Double, availableHeight: Double,
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

package struct EaselLiveFraming: Equatable {
    package enum Phase: Equatable { case waiting, framed, failed }
    package enum Outcome: Equatable { case reveal, keepWaiting, backToSnapshot }

    static let liningUp = "Lining up the region you captured…"
    package static let failureBadge = "Snapshot · couldn't go live"
    package static let failureHelp = "The live page couldn't line up with the region you captured, so the card stays a snapshot. The site may have changed; you can try Make live again."

    private(set) var phase: Phase = .waiting

    package var revealsPage: Bool { phase == .framed }

    package init(phase: Phase = .waiting) {
        self.phase = phase
    }

    package mutating func pageChanged() { phase = .waiting }

    package mutating func positioned(success: Bool, pageStillLoading: Bool) -> Outcome {
        if success { phase = .framed; return .reveal }
        if pageStillLoading { phase = .waiting; return .keepWaiting }
        phase = .failed
        return .backToSnapshot
    }

    package static func admitsPageScrolling(framesCapture: Bool) -> Bool { !framesCapture }

    package static func framesCapture(_ layout: EaselCaptureLayout?) -> Bool { layout.map { !$0.isFullPage } ?? false }
}
