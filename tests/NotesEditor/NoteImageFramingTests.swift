import CoreGraphics
import Foundation

@main
struct NoteImageFramingTests {
    static var failures = 0

    static func expect(_ value: Bool, _ message: @autoclosure () -> String, line: UInt = #line) {
        if !value {
            failures += 1
            FileHandle.standardError.write(Data("NoteImageFramingTests.swift:\(line): \(message())\n".utf8))
        }
    }

    static func near(_ lhs: CGFloat, _ rhs: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(lhs - rhs) <= tolerance }

    static func near(_ lhs: CGRect, _ rhs: CGRect, _ tolerance: CGFloat = 0.01) -> Bool {
        near(lhs.minX, rhs.minX, tolerance) && near(lhs.minY, rhs.minY, tolerance)
            && near(lhs.width, rhs.width, tolerance) && near(lhs.height, rhs.height, tolerance)
    }

    static func main() {
        crops()
        masks()
        geometry()
        framing()
        markdown()
        html()
        clipboard()
        if failures > 0 { failTest("NoteImageFramingTests: \(failures) failures") }
        print("NoteImageFramingTests passed")
    }

    static func crops() {
        let crop = NoteImageCrop(attribute: "0.1, 0.05,0.8,0.9")
        expect(crop == NoteImageCrop(x: 0.1, y: 0.05, width: 0.8, height: 0.9), "crop attributes parse with spaces")
        expect(crop?.attribute == "0.1,0.05,0.8,0.9", "crop attributes write without trailing zeros: \(crop?.attribute ?? "nil")")
        expect(NoteImageCrop(attribute: "0.9,0,0.5,1") == NoteImageCrop(x: 0.5, y: 0, width: 0.5, height: 1), "crops slide back inside the image")
        expect(NoteImageCrop(attribute: "-1,-1,2,3") == .full, "oversized crops clamp to the whole image")
        expect(NoteImageCrop(attribute: "0,0,0.001,0.5")?.width == NoteImageCrop.minimumSide, "slivers grow to the minimum side")
        expect(NoteImageCrop(attribute: "0,0,1") == nil && NoteImageCrop(attribute: "a,b,c,d") == nil, "garbage crops are ignored")
        expect(NoteImageCrop(attribute: "0,0,0,1") == nil && NoteImageCrop(attribute: "0,0,nan,1") == nil, "empty or NaN crops are ignored")
        let precise = NoteImageCrop(x: 0.333333, y: 0.1, width: 0.666666, height: 0.5).normalized
        expect(precise.attribute == "0.3333,0.1,0.6667,0.5", "four decimals is plenty: \(precise.attribute)")
        expect(NoteImageCrop(attribute: precise.attribute) == precise, "normalized crops read back identically")
        expect(NoteImageCrop.full.isFull && !precise.isFull, "full crops are recognised")
        let bounds = CGRect(x: 10, y: 20, width: 400, height: 200)
        let rect = NoteImageCrop(x: 0.25, y: 0.5, width: 0.5, height: 0.25).rect(in: bounds)
        expect(near(rect, CGRect(x: 110, y: 120, width: 200, height: 50)), "crops map into display rects")
        expect(NoteImageCrop(rect, in: bounds) == NoteImageCrop(x: 0.25, y: 0.5, width: 0.5, height: 0.25), "display rects map back to crops")
        let full = NoteImageCrop(x: 0.25, y: 0.5, width: 0.5, height: 0.25).fullRect(forFrame: CGRect(x: 0, y: 0, width: 300, height: 100))
        expect(near(full, CGRect(x: -150, y: -200, width: 600, height: 400)), "the whole picture sits behind the frame: \(full)")
        let size = NoteImageCrop(x: 0, y: 0, width: 0.5, height: 0.25).croppedSize(of: CGSize(width: 800, height: 400))
        expect(size == CGSize(width: 400, height: 100), "cropped natural size")
    }

    static func masks() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        for mask in NoteImageMask.allCases {
            let box = mask.path(in: rect).boundingBoxOfPath
            expect(!box.isEmpty && rect.insetBy(dx: -0.5, dy: -0.5).contains(box), "\(mask) stays inside its frame: \(box)")
            expect(mask.path(in: rect).contains(CGPoint(x: rect.midX, y: rect.midY)), "\(mask) keeps the middle visible")
            let svg = mask.svgPathData
            expect(svg.hasPrefix("M") && svg.hasSuffix("Z"), "\(mask) writes a closed SVG path")
            expect(!mask.title.isEmpty, "\(mask) has a name")
            let unit = mask.unitPath.boundingBoxOfPath
            expect(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.001, dy: -0.001).contains(unit), "\(mask) unit path fits the unit square")
            expect(mask.isSquare == (mask.borderRadius(frameAspect: nil) == nil || mask == .circle), "\(mask) square shapes need a mask image except circles")
        }
        expect(!NoteImageMask.rounded.path(in: rect).contains(CGPoint(x: rect.minX + 1, y: rect.minY + 1)), "rounded corners are cut")
        expect(NoteImageMask.rounded.path(in: rect).contains(CGPoint(x: rect.minX + 1, y: rect.midY)), "rounded sides stay")
        expect(NoteImageMask.roundedRadius(for: CGSize(width: 300, height: 200)) == 20, "rounded radius is a tenth of the short side")
        expect(NoteImageMask.archRadius(for: CGSize(width: 300, height: 200)) == 150, "arches are round on top")
        expect(NoteImageMask.archRadius(for: CGSize(width: 300, height: 100)) == 100, "low arches stay circular like CSS")
        let arch = NoteImageMask.arch.path(in: rect)
        expect(!arch.contains(CGPoint(x: rect.minX + 2, y: rect.minY + 2)) && arch.contains(CGPoint(x: rect.minX + 2, y: rect.maxY - 2)),
               "arches cut the top corners and keep the bottom ones")
        let heart = NoteImageMask.heart.path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        expect(heart.contains(CGPoint(x: 25, y: 25)) && !heart.contains(CGPoint(x: 10, y: 90)), "hearts point down in top-down space")
        let star = NoteImageMask.star.path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        expect(star.contains(CGPoint(x: 50, y: 10)) && !star.contains(CGPoint(x: 50, y: 92)), "stars point up in top-down space")
        expect(NoteImageMask.rounded.borderRadius(frameAspect: 0.5) == "5%/10%", "rounded CSS radius follows the frame")
        expect(NoteImageMask.rounded.borderRadius(frameAspect: 2) == "10%/5%", "tall frames swap the radius")
        expect(NoteImageMask.circle.borderRadius(frameAspect: 1) == "50%", "circles are a radius")
        expect(NoteImageMask.arch.borderRadius(frameAspect: nil) == "9999px 9999px 0 0", "arches clamp like the editor")
        expect(NoteImageMask.star.maskImageURL.hasPrefix("data:image/svg+xml,%3Csvg"), "shapes become SVG mask images")
        expect(!NoteImageMask.heart.maskImageURL.contains("<") && !NoteImageMask.heart.maskImageURL.contains("\""), "mask URLs are CSS safe")
    }

    static func geometry() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let start = CGRect(x: 100, y: 100, width: 200, height: 100)
        let free = NoteImageCropGeometry.resize(start, handle: .bottomRight, by: CGSize(width: 50, height: 20), within: bounds, minimum: 24, aspect: nil)
        expect(near(free, CGRect(x: 100, y: 100, width: 250, height: 120)), "free corners follow the pointer")
        let clamped = NoteImageCropGeometry.resize(start, handle: .topLeft, by: CGSize(width: -500, height: -500), within: bounds, minimum: 24, aspect: nil)
        expect(near(clamped, CGRect(x: 0, y: 0, width: 300, height: 200)), "corners stop at the image edge")
        let tiny = NoteImageCropGeometry.resize(start, handle: .right, by: CGSize(width: -400, height: 0), within: bounds, minimum: 24, aspect: nil)
        expect(near(tiny.width, 24) && tiny.minX == 100, "edges keep a grabbable minimum")
        let edge = NoteImageCropGeometry.resize(start, handle: .top, by: CGSize(width: 30, height: -40), within: bounds, minimum: 24, aspect: nil)
        expect(near(edge, CGRect(x: 100, y: 60, width: 200, height: 140)), "edges move one side only")
        let square = NoteImageCropGeometry.resize(start, handle: .bottomRight, by: CGSize(width: 60, height: 10), within: bounds, minimum: 24, aspect: 1)
        expect(near(square.width, square.height) && near(square.width, 200) && square.origin == start.origin, "locked corners keep the ratio: \(square)")
        let roomy = NoteImageCropGeometry.resize(start, handle: .bottomRight, by: CGSize(width: 400, height: 400), within: bounds, minimum: 24, aspect: 1)
        expect(near(roomy, CGRect(x: 100, y: 100, width: 200, height: 200)), "locked corners stop at the nearest edge: \(roomy)")
        let wide = NoteImageCropGeometry.resize(CGRect(x: 100, y: 100, width: 100, height: 100), handle: .right, by: CGSize(width: 100, height: 0),
                                                within: bounds, minimum: 24, aspect: 1)
        expect(near(wide, CGRect(x: 100, y: 50, width: 200, height: 200)), "locked edges grow around the middle: \(wide)")
        let topEdge = NoteImageCropGeometry.resize(CGRect(x: 100, y: 200, width: 100, height: 100), handle: .top, by: CGSize(width: 0, height: -150),
                                                   within: bounds, minimum: 24, aspect: 2)
        expect(near(topEdge.width, topEdge.height * 2) && bounds.insetBy(dx: -0.01, dy: -0.01).contains(topEdge), "locked top edges stay inside: \(topEdge)")
        let moved = NoteImageCropGeometry.move(start, by: CGSize(width: 500, height: -500), within: bounds)
        expect(near(moved, CGRect(x: 200, y: 0, width: 200, height: 100)), "moving stops at the edges")
        let fitted = NoteImageCropGeometry.fitted(aspect: 1, around: CGRect(x: 0, y: 0, width: 400, height: 300), within: bounds)
        expect(near(fitted, CGRect(x: 50, y: 0, width: 300, height: 300)), "a ratio keeps as much picture as fits: \(fitted)")
        let small = NoteImageCropGeometry.fitted(aspect: 2, around: CGRect(x: 300, y: 200, width: 50, height: 50), within: bounds)
        expect(near(small.width, small.height * 2) && near(small.width * small.height, 2500, 1) && bounds.contains(small),
               "a ratio on a small crop keeps its size and stays inside: \(small)")
        expect(NoteImageCropGeometry.matches(CGRect(x: 0, y: 0, width: 160, height: 90), aspect: 16.0 / 9.0), "ratios match")
        expect(NoteImageCropAspect.original.ratio(natural: CGSize(width: 300, height: 200)) == 1.5 && NoteImageCropAspect.free.ratio(natural: nil) == nil,
               "aspect presets")
        expect(Set(NoteImageCropAspect.allCases.map(\.id)).count == NoteImageCropAspect.allCases.count, "aspect ids are unique")
        expect(NoteImageCropHandle.allCases.filter(\.isCorner).count == 4, "four corners")
    }

    static func framing() {
        var props = NoteBlockProps()
        props.crop = NoteImageCrop(x: 0, y: 0, width: 1, height: 0.5)
        let circled = NoteImageFraming.applying(.circle, to: props, natural: CGSize(width: 800, height: 600))
        expect(circled.mask == .circle, "the mask applies")
        expect(circled.crop == NoteImageCrop(x: 0.3125, y: 0, width: 0.375, height: 0.5), "square shapes crop to the middle square: \(String(describing: circled.crop))")
        let rounded = NoteImageFraming.applying(.rounded, to: props, natural: CGSize(width: 800, height: 600))
        expect(rounded.crop == props.crop && rounded.mask == .rounded, "free shapes leave the crop alone")
        let plain = NoteImageFraming.applying(.heart, to: NoteBlockProps(), natural: CGSize(width: 500, height: 500))
        expect(plain.crop == nil, "square pictures need no crop for square shapes")
        let unknown = NoteImageFraming.applying(.star, to: NoteBlockProps(), natural: nil)
        expect(unknown.crop == nil && unknown.mask == .star, "unknown sizes still take the shape")
        let cleared = NoteImageFraming.applying(nil, to: circled, natural: nil)
        expect(cleared.mask == nil && cleared.crop == circled.crop, "removing the shape keeps the crop")
        expect(NoteImageFraming.frameAspect(crop: props.crop, natural: CGSize(width: 800, height: 600)) == 0.375, "frame aspect")
    }

    static func markdown() {
        var image = NoteBlock(.image)
        image.props.source = "Attachments/cat.png"
        image.props.alt = "A sleepy cat"
        image.props.width = 0.5
        image.props.alignment = .left
        image.props.crop = NoteImageCrop(x: 0.1, y: 0.05, width: 0.8, height: 0.9)
        image.props.mask = .circle
        let page = NotePage(blocks: [image, .paragraph(NoteText("After"))])
        let text = NoteMarkdown.serialize(page)
        expect(text.contains("![A sleepy cat](Attachments/cat.png) <!-- parc width=\"0.5\" align=\"left\" crop=\"0.1,0.05,0.8,0.9\" mask=\"circle\" -->"),
               "crop and mask ride in the Parc comment:\n\(text)")
        let back = NoteMarkdown.parse(text)
        expect(back.blocks.first?.props == image.props, "image framing survives a round trip")
        expect(NoteMarkdown.serialize(back) == text, "a second save is identical")
        let hand = NoteMarkdown.parse("![](a.png) <!-- parc crop=\"0.95,0,0.5,1\" mask=\"HEART\" -->\n\nWords <!-- parc crop=\"0,0,1,1\" -->\n")
        expect(hand.blocks.first?.props.crop == NoteImageCrop(x: 0.5, y: 0, width: 0.5, height: 1), "hand-written crops are tidied")
        expect(hand.blocks.first?.props.mask == .heart, "mask names ignore case")
        expect(hand.blocks.count > 1 && hand.blocks[1].props.crop == nil, "crops on text are ignored")
        let unknown = NoteMarkdown.parse("![](a.png) <!-- parc mask=\"blob\" crop=\"x\" -->\n")
        expect(unknown.blocks.first?.props.mask == nil && unknown.blocks.first?.props.crop == nil, "unknown shapes and bad crops are skipped")
        var masked = NoteBlock(.image)
        masked.props.source = "b.png"
        masked.props.mask = .star
        let starText = NoteMarkdown.serialize(NotePage(blocks: [masked]))
        expect(starText.contains("![](b.png) <!-- parc mask=\"star\" -->"), "a lone mask writes a short comment: \(starText)")
        var titled = image
        titled.props.caption = NoteText("Nap time")
        let titledText = NoteMarkdown.serialize(NotePage(blocks: [titled]))
        expect(NoteMarkdown.parse(titledText).blocks.first?.props == titled.props, "captions and framing live together")
    }

    static func html() {
        var cropped = NoteBlock(.image)
        cropped.props.source = "Attachments/cat.png"
        cropped.props.alt = "Cat"
        cropped.props.crop = NoteImageCrop(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        var starred = NoteBlock(.image)
        starred.props.source = "Attachments/star.png"
        starred.props.mask = .star
        starred.props.width = 0.4
        var rounded = NoteBlock(.image)
        rounded.props.source = "Attachments/round.png"
        rounded.props.mask = .rounded
        rounded.props.crop = NoteImageCrop(x: 0, y: 0, width: 1, height: 0.5)
        var mystery = NoteBlock(.image)
        mystery.props.source = "https://example.com/unknown.png"
        mystery.props.crop = NoteImageCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.6)
        let sizes: [String: CGSize] = ["Attachments/cat.png": CGSize(width: 800, height: 400), "Attachments/star.png": CGSize(width: 300, height: 300),
                                       "Attachments/round.png": CGSize(width: 600, height: 600)]
        let page = NotePage(blocks: [cropped, starred, rounded, mystery])
        let html = NotePageHTML.document(page, title: "Framed", assets: { _ in nil }, embedImages: false, imageSize: { sizes[$0] })
        expect(html.contains("<span class=\"image-frame cropped\" style=\"aspect-ratio:400/100;width:400px\">"), "crops size their frame:\n\(html)")
        expect(html.contains("data-crop=\"0.25,0.5,0.5,0.25\" style=\"width:200%;left:-50%;top:-200%\">"), "the picture shifts behind the frame")
        expect(html.contains("<span class=\"image-frame mask-star\"><img src=\"Attachments/star.png\" alt=\"\" data-mask=\"star\"></span>"),
               "shapes wrap the picture")
        expect(html.contains(".image-frame.mask-star{-webkit-mask:url(\"data:image/svg+xml,"), "used shapes get a mask rule")
        expect(!html.contains(".image-frame.mask-heart{"), "unused shapes stay out of the stylesheet")
        expect(html.contains("class=\"image-frame mask-rounded cropped\" style=\"border-radius:5%/10%;aspect-ratio:600/300;width:600px\""),
               "rounded frames get exact corners")
        expect(html.contains("style=\"object-view-box:inset(20% 40% 20% 10%)\""), "unknown sizes still crop where browsers can")
        let fragment = NotePageHTML.fragment([cropped, starred])
        expect(!fragment.contains("image-frame") && fragment.contains("data-crop=\"0.25,0.5,0.5,0.25\"") && fragment.contains("data-mask=\"star\""),
               "clipboard HTML keeps framing as data")
        let back = NoteHTMLReader.blocks(from: fragment, baseURL: nil)
        expect(back.count == 2 && back[0].props.crop == cropped.props.crop && back[1].props.mask == .star,
               "clipboard HTML reads framing back")
        let reread = NoteHTMLReader.blocks(from: html, baseURL: nil).filter { $0.kind == .image }
        expect(reread.count == 4 && reread[0].props.crop == cropped.props.crop && reread[1].props.mask == .star && reread[2].props.mask == .rounded,
               "exported documents read framing back: \(reread.map { ($0.props.crop?.attribute ?? "-") + "/" + ($0.props.mask?.rawValue ?? "-") })")
        let plain = NotePageHTML.document(NotePage(blocks: [NoteBlock(.image)]), title: "", assets: { _ in nil }, embedImages: false)
        expect(!plain.contains("image-frame mask") && !plain.contains("<span class=\"image-frame"), "plain images stay plain")
    }

    static func clipboard() {
        var props = NoteBlockProps()
        props.crop = NoteImageCrop(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        props.mask = .hexagon
        let block = NoteBlock(.image, props: props)
        let data = (try? JSONEncoder().encode(block)) ?? Data()
        let decoded = try? JSONDecoder().decode(NoteBlock.self, from: data)
        expect(decoded?.props.crop == props.crop && decoded?.props.mask == .hexagon, "the block clipboard keeps framing")
        var old = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        var oldProps = old["props"] as? [String: Any] ?? [:]
        oldProps.removeValue(forKey: "crop")
        oldProps.removeValue(forKey: "mask")
        old["props"] = oldProps
        let legacy = (try? JSONSerialization.data(withJSONObject: old)).flatMap { try? JSONDecoder().decode(NoteBlock.self, from: $0) }
        expect(legacy != nil && legacy?.props.crop == nil && legacy?.props.mask == nil, "older clipboard blocks still decode")
    }
}
