import Foundation
import CoreGraphics
import Testing
@testable import ParcCore

struct EaselImageFramingExportTests {
    @Test func exportsShowFramedImagesClippedAndTurned() {
        let picture = EaselVectorImage(data: EaselImageFramingTestsSupport.png, mimeType: "image/png")
        var item = EaselImageFramingTestsSupport.image()
        let plain = EaselVectorExport.element(item, art: EaselVectorArt(images: [item.id: picture]))
        #expect(plain.hasPrefix("<image ") && !plain.contains("clipPath"), "an unframed image exports as a plain image")
        item.altText = "A <cat>"
        item.mask = .circle
        item.quarterTurns = 1
        item.crop = EaselRect(x: 0, y: 0, width: 0.5, height: 1)
        let framed = EaselVectorExport.element(item, art: EaselVectorArt(images: [item.id: picture]))
        #expect(framed.contains("<clipPath") && framed.contains("clip-path=\"url(#frame-"), "a framed image clips to its frame")
        #expect(framed.contains("transform=\"rotate(90 "), "turns export as a rotation")
        #expect(framed.contains("aria-label=\"A &lt;cat&gt;\"") && framed.contains("<title>A &lt;cat&gt;</title>"), "alt text exports escaped as a label and title")
        #expect(framed.contains("<path d=\"M"), "a mask exports as its outline")
    }
}
