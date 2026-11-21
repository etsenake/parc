import AppKit

@main struct CapturePresentationChecks {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        _ = NSApplication.shared
        let bounds = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let source = NSRect(x: 100, y: 120, width: 300, height: 200)
        let right = CapturePresentation.layout(bounds: bounds, pixels: NSSize(width: 600, height: 400),
            source: source, paletteHeight: 350, editing: false)
        precondition(right.image == source, "Backing-scale pixels must keep the original logical rectangle")
        precondition(right.palette == NSRect(x: 414, y: 116, width: 273, height: 350))
        let trailing = NSRect(x: 600, y: 450, width: 300, height: 200)
        let left = CapturePresentation.layout(bounds: bounds, pixels: NSSize(width: 600, height: 400),
            source: trailing, paletteHeight: 350, editing: false)
        precondition(left.image == trailing && left.palette == NSRect(x: 313, y: 304, width: 273, height: 350))
        let crop = CapturePresentation.pixelCrop(NSRect(x: 175, y: 170, width: 150, height: 100),
            imageRect: source, pixels: NSSize(width: 1200, height: 800))
        precondition(crop == NSRect(x: 300, y: 200, width: 600, height: 400))
        precondition(CapturePresentation.pixelCrop(source, imageRect: source, pixels: NSSize(width: 1200, height: 800))
                     == NSRect(x: 0, y: 0, width: 1200, height: 800))
        precondition(CapturePresentation.pixelCrop(NSRect(x: -20, y: -20, width: 40, height: 40), imageRect: source,
            pixels: NSSize(width: 1200, height: 800)) == nil)
        var layouts = 0
        for width in [160.0, 320, 480, 600, 1000] {
            for height in [200.0, 400, 800] {
                for pixels in [NSSize(width: 400, height: 200), NSSize(width: 300, height: 9000)] {
                    let area = NSRect(x: 0, y: 0, width: width, height: height)
                    let result = CapturePresentation.layout(bounds: area, pixels: pixels, source: area,
                        paletteHeight: 450, editing: false)
                    precondition(area.contains(result.image) && area.contains(result.palette))
                    precondition(result.image.width > 0 && result.image.height > 0)
                    precondition(abs(result.image.width / result.image.height - pixels.width / pixels.height) < 0.0001)
                    if width < 576 { precondition(!result.image.intersects(result.palette), "Compact panes must keep the preview visible") }
                    let editing = CapturePresentation.layout(bounds: area, pixels: pixels, source: area,
                        paletteHeight: 450, editing: true)
                    precondition(area.contains(editing.image))
                    layouts += 1
                }
            }
        }
        let narrow = NSRect(x: 0, y: 0, width: 400, height: 500)
        let capped = CapturePresentation.layout(bounds: narrow, pixels: NSSize(width: 800, height: 600), source: nil,
                                                paletteHeight: 400, editing: false)
        let page = CapturePresentation.layout(bounds: narrow, pixels: NSSize(width: 800, height: 600), source: nil,
                                              paletteHeight: 400, editing: false, fullPalette: true)
        precondition(capped.palette.height < 300 && page.palette.height == 400 && narrow.contains(page.palette)
                     && page.image.maxY <= page.palette.minY, "Narrow panes keep the whole Frame page, with the image above it")
        let light = CaptureAppearance.imageBackground(false).usingColorSpace(.sRGB)!
        let dark = CaptureAppearance.imageBackground(true).usingColorSpace(.sRGB)!
        precondition(light.redComponent == 1 && dark.blueComponent > dark.redComponent)
        precondition(CaptureArtwork.directory == Bundle.main.resourceURL?.appendingPathComponent("Capture", isDirectory: true),
                     "The artwork loads from the bundle's Capture resources")
        let cursor = CaptureArtwork.image("camera-cross-cursor")!
        precondition(cursor.size.height == 50 && cursor.representations.count >= 3 && !cursor.isTemplate)
        print("Capture presentation passed: source anchors, crop mapping, \(layouts) fitted layouts, image frame appearance and cursor renditions.")
    }
}
