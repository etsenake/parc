import Foundation

extension NoteCaptureGeometry {
    init(_ layout: EaselCaptureLayout) {
        self.init(viewportWidth: layout.viewport.x, viewportHeight: layout.viewport.y, scrollX: layout.scroll.x, scrollY: layout.scroll.y,
                  regionX: layout.region.x, regionY: layout.region.y, regionWidth: layout.region.width, regionHeight: layout.region.height,
                  scrollers: layout.scrollContainers.map(EaselScrollContainer.encode))
    }

    var easelLayout: EaselCaptureLayout? {
        let containers = scrollers.map(EaselScrollContainer.decode)
        if containers == .some(nil) { return nil }
        return EaselCaptureLayout(viewport: EaselPoint(x: viewportWidth, y: viewportHeight), scroll: EaselPoint(x: scrollX, y: scrollY),
                                  region: EaselRect(x: regionX, y: regionY, width: regionWidth, height: regionHeight),
                                  scrollContainers: containers ?? nil)
    }
}

enum NoteCaptureLive {
    static func chromeItem(of block: NoteBlock) -> EaselItem? {
        guard let capture = capture(of: block) else { return nil }
        var item = EaselItem(kind: .webCard, frame: EaselRect(x: 0, y: 0, width: 1, height: 1))
        item.url = capture.sourceURL
        item.assetID = block.props.source.flatMap { $0.isEmpty ? nil : $0 }
        item.capturedAt = capture.capturedAt
        item.captureLayout = capture.geometry?.easelLayout
        item.liveCapture = capture.live
        item.text = block.props.alt ?? ""
        return item
    }

    static func badge(of block: NoteBlock, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String? {
        chromeItem(of: block).flatMap { EaselWebItemChrome.badge(for: $0, now: now, calendar: calendar, locale: locale) }
    }

    static func badgeHelp(of block: NoteBlock) -> String? {
        chromeItem(of: block).flatMap(EaselWebItemChrome.badgeHelp(for:))
    }

    static func capture(of block: NoteBlock) -> NoteCapture? {
        block.kind == .image ? block.props.capture : nil
    }

    static func layout(of block: NoteBlock) -> EaselCaptureLayout? {
        guard let capture = capture(of: block), capture.canMakeLive, let layout = capture.geometry?.easelLayout, layout.isValid else { return nil }
        return layout
    }

    static func canMakeLive(_ block: NoteBlock) -> Bool {
        layout(of: block) != nil && chromeItem(of: block).map(EaselWebItemChrome.canMakeLive) == true
    }

    static func ownsLivePage(_ block: NoteBlock) -> Bool {
        canMakeLive(block) && block.props.capture?.live == true
    }

    static func liveAddress(of block: NoteBlock) -> URL? {
        ownsLivePage(block) ? block.props.capture?.sourceAddress : nil
    }
}
