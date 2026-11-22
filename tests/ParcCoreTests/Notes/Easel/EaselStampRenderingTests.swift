import Foundation
import Testing
@testable import ParcCore

struct EaselStampRenderingTests {
    @Test(arguments: EaselStampDesign.allCases)
    func eachDesignHasFiniteArtWithARimAndSoftShadow(_ design: EaselStampDesign) {
        let layers = EaselStampArt.layers(design)
        #expect(layers.count >= 5, "\(design.title) has a rim, shadow and body")
        #expect(layers.contains { $0.tone == .rim && $0.outline == EaselStampArt.rimWidth }, "\(design.title) wears a sticker rim")
        #expect(layers.filter { $0.tone == .shadow }.allSatisfy { $0.opacity < 0.2 }, "\(design.title) casts a soft shadow")
        for layer in layers {
            #expect(!layer.path.elements.isEmpty, "\(design.title) layers have shapes")
            #expect(layer.path.points.allSatisfy { $0.x >= -1 && $0.x <= 101 && $0.y >= -1 && $0.y <= 101 && $0.x.isFinite && $0.y.isFinite }, "\(design.title) stays inside its square")
            #expect(layer.opacity > 0 && layer.opacity <= 1, "\(design.title) opacities are sane")
            #expect(layer.filled || layer.outline != nil, "\(design.title) layers paint something")
            let hex = EaselStampArt.hex(layer.tone, for: design)
            #expect(hex.count == 7 && hex.hasPrefix("#") && hex.dropFirst().allSatisfy{ $0.isHexDigit }, "\(design.title) colours are hex")
        }
    }

    @Test
    func thumbsDownHasItsOwnPose() {
        let thumbsUp = EaselStampArt.layers(.thumbsUp), thumbsDown = EaselStampArt.layers(.thumbsDown)
        #expect(thumbsUp.count == thumbsDown.count && thumbsUp.last?.path != thumbsDown.last?.path, "Thumbs down is its own pose")
    }

    @Test
    func circlesFitTheirRadius() {
        let disc = EaselStampPath.circle(50, 50, 40)
        let xs = disc.points.map(\.x), ys = disc.points.map(\.y)
        #expect(abs((xs.min() ?? 0) - 10) < 1e-9 && abs((xs.max() ?? 0) - 90) < 1e-9 && abs((ys.min() ?? 0) - 10) < 1e-9, "Circles fit their radius")
    }

    @Test
    func svgArtMapsIntoTheStampFrame() {
        let disc = EaselStampPath.circle(50, 50, 40)
        let svg = disc.svgData(in: EaselRect(x: 100, y: 200, width: 50, height: 50))
        #expect(svg.hasPrefix("M145 225C") && svg.hasSuffix("Z"), "Paths map into the stamp's frame for SVG")
    }

    @Test
    func rotationAroundTheCentreKeepsArtInPlace() {
        let turned = EaselStampPath.roundedRect(0, 0, 10, 10, 2).rotated(by: 180, around: EaselPoint(x: 5, y: 5))
        #expect(turned.points.allSatisfy { $0.x > -1e-9 && $0.x < 10 + 1e-9 }, "Rotating about the centre stays in place")
    }

    @Test
    func starArtRoundsAllTenCorners() {
        let star = EaselStampPath.star(centre: EaselPoint(x: 50, y: 50), outer: 40, inner: 20)
        #expect(star.elements.filter { if case .curve = $0 { return true } else { return false } }.count == 10, "Stars round all ten corners")
    }

    @Test
    func arcsHugTheirCircle() {
        let ring = EaselStampPath.ring(centre: EaselPoint(x: 50, y: 50), outer: 20, inner: 10, from: 180, to: 450)
        #expect(ring.points.allSatisfy { hypot($0.x - 50, $0.y - 50) < 23 }, "Arcs hug their circle")
    }

    @Test func builtInStampsExportAsVectorPaths() {
        let art = EaselVectorArt()
        var heart = EaselStampTestsSupport.stamp(.design(.heart)); heart.rotation = 8
        let heartSVG = EaselVectorExport.element(heart, art: art)
        #expect(heartSVG.contains("<g class=\"easel-stamp\">") && heartSVG.components(separatedBy: "<path").count - 1 == EaselStampArt.layers(.heart).count, "Built-in stamps export as vector paths")
        #expect(heartSVG.hasPrefix("<g transform=\"rotate(8 ") && heartSVG.components(separatedBy: "rotate(").count == 2, "A tilted stamp exports its tilt once, around its centre")
        #expect(heartSVG.contains("#F2506A") && heartSVG.contains("stroke:#FFFFFF"), "Their colours and rim come along")
        let party = EaselVectorExport.element(EaselStampTestsSupport.stamp(.emoji("🎉")), art: art)
        #expect(party.contains(">🎉</text>") && party.contains("text-anchor=\"middle\""), "Emoji export as text")
        var cloud = EaselStampTestsSupport.stamp(.icon("cloud"))
        #expect(EaselVectorExport.element(cloud, art: art).isEmpty, "Icons without a picture export nothing rather than junk")
        var withPicture = EaselVectorArt()
        withPicture.images[cloud.id] = EaselVectorImage(data: Data([0x89, 0x50, 0x4E, 0x47]), mimeType: "image/png")
        let automatic = EaselVectorExport.element(cloud, art: withPicture)
        #expect(automatic.contains("<mask") && automatic.contains("fill:var(--easel-ink)") && automatic.contains("data:image/png;base64,"), "Icons export as a tinted mask that follows light and dark")
        cloud.color = "#123456"
        #expect(EaselVectorExport.element(cloud, art: withPicture).contains("fill:#123456"), "Custom icon colours stay exact")
        cloud.color = "#2C6C91"
        #expect(EaselVectorExport.element(cloud, art: withPicture).contains("fill:var(--"), "Palette icon colours follow light and dark like other Easel colours")
        var broken = EaselStampTestsSupport.stamp(.design(.heart)); broken.stamp = "wave"
        #expect(EaselVectorExport.element(broken, art: art).isEmpty, "Damaged stamps export nothing")
        let doc = EaselStampTestsSupport.document([EaselStampTestsSupport.item(.rectangle, 0, 0, 50, 50), heart, EaselStampTestsSupport.stamp(.emoji("🎉"))])
        let html = EaselVectorExport.htmlDocument(doc, art: art)
        #expect(html.contains("easel-stamp") && html.contains("🎉"), "Stamps make it into the HTML page")
    }
}
