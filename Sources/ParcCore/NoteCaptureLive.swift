import Foundation

extension NoteCaptureGeometry {
    init(_ layout: EaselCaptureLayout) {
        self.init(viewportWidth: layout.viewport.x, viewportHeight: layout.viewport.y, scrollX: layout.scroll.x, scrollY: layout.scroll.y,
                  regionX: layout.region.x, regionY: layout.region.y, regionWidth: layout.region.width, regionHeight: layout.region.height)
    }

    var easelLayout: EaselCaptureLayout {
        EaselCaptureLayout(viewport: EaselPoint(x: viewportWidth, y: viewportHeight), scroll: EaselPoint(x: scrollX, y: scrollY),
                           region: EaselRect(x: regionX, y: regionY, width: regionWidth, height: regionHeight))
    }
}

enum NoteCaptureLive {
    static func capture(of block: NoteBlock) -> NoteCapture? {
        block.kind == .image ? block.props.capture : nil
    }

    static func layout(of block: NoteBlock) -> EaselCaptureLayout? {
        guard let capture = capture(of: block), capture.canMakeLive, let layout = capture.geometry?.easelLayout, layout.isValid else { return nil }
        return layout
    }

    static func canMakeLive(_ block: NoteBlock) -> Bool {
        layout(of: block) != nil && block.props.source?.isEmpty == false
    }

    static func ownsLivePage(_ block: NoteBlock) -> Bool {
        canMakeLive(block) && block.props.capture?.live == true
    }

    static func liveAddress(of block: NoteBlock) -> URL? {
        ownsLivePage(block) ? block.props.capture?.sourceAddress : nil
    }
}
