import Foundation
import Testing
@testable import ParcCore

struct EaselVectorExportDrawingTests {
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!

    @Test func exportBoundsCoverEveryObjectPlusMargins() {
        let empty = EaselVectorExport.contentBounds([])
        #expect(empty.width > 0 && empty.height > 0, "an empty Easel still exports a page")
        let items = [EaselItem(kind: .rectangle, frame: .init(x: 100, y: 50, width: 200, height: 100)),
                     EaselItem(kind: .circle, frame: .init(x: -20, y: 300, width: 40, height: 40))]
        let rect = EaselVectorExport.contentBounds(items, margin: 10)
        #expect(rect.x == -34 && rect.y == 36, "bounds start at the leftmost and topmost object minus margin and stroke")
        #expect(rect.width == 320 + 28 && rect.height == 290 + 28, "bounds cover every object plus margins")
    }

    @Test func outlinesArrowheadsAndLabelsStayInsideTheExport() {
        var thick = EaselItem(kind: .rectangle, frame: .init(x: 0, y: 0, width: 100, height: 100))
        thick.strokeWidth = 40
        #expect(EaselVectorExport.contentBounds([thick], margin: 0).x == -20, "wide outlines stay inside the export")
        var arrow = EaselItem(kind: .arrow, frame: .init(x: 0, y: 0, width: 100, height: 1), points: [.init(x: 0, y: 0), .init(x: 100, y: 0)])
        arrow.strokeWidth = 20
        let headed = EaselVectorExport.contentBounds([arrow], margin: 0)
        #expect(headed.x + headed.width >= 100 + EaselPaintRules.arrowHeadLength(width: 20), "thick arrowheads stay inside the export")
        arrow.strokeWidth = nil
        arrow.text = "a fairly long connector label"
        let labelled = EaselVectorExport.contentBounds([arrow], margin: 0)
        #expect(labelled.x < -60 && labelled.y < -20, "connector labels stay inside the export")
        var art = EaselVectorArt()
        art.connectorLabels[arrow.id] = EaselConnectorLabelArt(text: .init(), width: 200, height: 18)
        let exact = EaselVectorExport.contentBounds([arrow], art: art, margin: 0)
        #expect(exact.x <= -57 && exact.x > -70, "known label sizes give exact bounds")

        var section = EaselItem(kind: .section, frame: .init(x: 100, y: 100, width: 400, height: 300))
        let inner = EaselItem(kind: .sticky, frame: .init(x: 200, y: 200, width: 100, height: 100))
        let open = EaselPreviewRegion.content([section, inner])
        section.contentsHidden = true
        let closed = EaselPreviewRegion.content([section, inner])
        #expect(open == closed, "objects tucked inside a section stay inside its bounds")
        #expect(EaselPreviewRegion.content([]) == nil, "empty Easels have no preview")
        var rotated = EaselItem(kind: .rectangle, frame: .init(x: 400, y: 400, width: 200, height: 20))
        rotated.rotation = 90
        let turned = EaselPreviewRegion.content([rotated])
        #expect(turned.map { $0.y < 400 - 80 + 1 && $0.height > 200 } == true, "previews frame rotated objects as they look")

        let wide = EaselPreviewRegion.fit(.init(x: 100, y: 100, width: 1600, height: 100), aspect: 0.625, minimumWidth: 800)
        #expect(wide.width == 1600 && wide.height == 1000, "previews keep the card aspect")
        #expect(wide.y == 0, "previews never reach above the canvas")
        let small = EaselPreviewRegion.fit(.init(x: 1000, y: 1000, width: 100, height: 100), aspect: 0.625, minimumWidth: 800)
        #expect(small.width == 800 && small.x == 650 && small.y == 800, "small boards centre in a minimum-width preview")
        let tall = EaselPreviewRegion.fit(.init(x: 0, y: 0, width: 100, height: 1000), aspect: 0.5, minimumWidth: 0)
        #expect(tall.width == 2000 && tall.height == 1000, "tall boards widen to fit")
        let crop = EaselPreviewRegion.crop(.init(x: -40, y: 10, width: 100, height: 50))
        #expect(crop.x == 0 && crop.width == 60 && crop.y == 10 && crop.height == 50, "crops stay on the canvas")
    }

    @Test func markupIsEscapedAndScriptLinksAreNotExported() {
        #expect(EaselVectorExport.escape("<a href=\"x\">&'</a>") == "&lt;a href=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;", "markup is escaped")
        #expect(EaselVectorExport.escape("a\u{0}b\u{8}c") == "abc", "control characters that break XML are dropped")
        #expect(EaselVectorExport.safeLink("javascript:alert(1)") == nil, "script links are not exported")
        #expect(EaselVectorExport.safeLink("https://example.com/a?b=1&c=2") == "https://example.com/a?b=1&c=2", "web links survive")
        #expect(EaselVectorExport.number(1.005) == "1" || EaselVectorExport.number(1.005) == "1.01", "numbers round to two places")
        #expect(EaselVectorExport.number(.nan) == "0", "non-finite numbers never reach the SVG")
        #expect(EaselVectorExport.exportFileName("  a/b:c ", fileExtension: "html") == "a-b-c.html", "file names stay safe")
        #expect(EaselVectorExport.exportFileName("", fileExtension: "pdf") == "Untitled Easel.pdf", "untitled Easels get a name")
    }

    @Test func circleExportUsesAnEllipseAndTheSavedStroke() {
        var circle = EaselItem(kind: .circle, frame: .init(x: 0, y: 0, width: 40, height: 20))
        circle.color = "#FF0000"
        let svgCircle = EaselVectorExport.element(circle, art: .init())
        #expect(svgCircle.contains("<ellipse cx=\"20\" cy=\"10\" rx=\"20\" ry=\"10\""), "circles become ellipses")
        #expect(svgCircle.contains("stroke:#FF0000"), "chosen colours stay exact")
    }

    @Test func defaultRectangleInkAdaptsToAppearance() {
        let square = EaselVectorExport.element(EaselItem(kind: .rectangle, frame: .init(x: 1, y: 2, width: 3, height: 4)), art: .init())
        #expect(square.contains("var(--easel-ink)"), "automatic ink adapts to light and dark")
    }

    @Test func arrowExportUsesItsSavedPointsAndHead() {
        var arrow = EaselItem(kind: .arrow, frame: .init(x: 10, y: 10, width: 100, height: 0))
        arrow.points = [.init(x: 0, y: 0), .init(x: 100, y: 0)]
        let svgArrow = EaselVectorExport.element(arrow, art: .init())
        #expect(svgArrow.components(separatedBy: "<path").count == 3, "arrows draw a shaft and a head")
        #expect(svgArrow.contains("M10 10L110 10"), "the shaft follows the saved points")
    }

    @Test func freehandExportDrawsOnlyItsStroke() {
        var scribble = EaselItem(kind: .freehand, frame: .init(x: 0, y: 0, width: 10, height: 10))
        scribble.points = [.init(x: 0, y: 0), .init(x: 5, y: 5), .init(x: 10, y: 0)]
        #expect(EaselVectorExport.element(scribble, art: .init()).components(separatedBy: "<path").count == 2, "freehand strokes have no head")
    }

    @Test func imageExportEmbedsItsAssetWhenPresent() {
        let picture = EaselItem(kind: .image, frame: .init(x: 0, y: 0, width: 10, height: 10), assetID: "a")
        var art = EaselVectorArt()
        art.images[picture.id] = EaselVectorImage(data: png, mimeType: "image/png")
        #expect(EaselVectorExport.element(picture, art: art).contains("href=\"data:image/png;base64,"), "images are embedded")
        #expect(EaselVectorExport.element(picture, art: .init()).isEmpty, "missing images draw nothing")
    }

    @Test func webSnapshotExportLinksToTheOriginalAddress() {
        var art = EaselVectorArt()
        let web = EaselItem(kind: .webCard, frame: .init(x: 0, y: 0, width: 10, height: 10), url: "https://example.com", assetID: "w")
        art.images[web.id] = EaselVectorImage(data: png, mimeType: "image/png")
        let svgWeb = EaselVectorExport.element(web, art: art)
        #expect(svgWeb.hasPrefix("<a href=\"https://example.com\""), "web snapshots link to their source")
        #expect(svgWeb.contains("<image"), "web cards show their snapshot")
    }

    @Test func linkCardExportEscapesItsTitle() {
        let link = EaselItem(kind: .link, frame: .init(x: 0, y: 0, width: 220, height: 160), text: "A <b>", url: "https://example.com")
        let svgLink = EaselVectorExport.element(link, art: .init())
        #expect(svgLink.contains("A &lt;b&gt;") && svgLink.contains("var(--easel-card)"), "link cards show an escaped title on the card fill")
    }

    @Test(arguments: [(Data([0xFF, 0xD8, 0xFF, 0xE0]), Optional("image/jpeg")),
                      (Data([1, 2, 3]), nil)])
    func vectorExportRecognizesSupportedImageBytes(_ bytes: Data, _ mimeType: String?) {
        #expect(EaselVectorExport.imageMimeType(bytes) == mimeType)
    }

    @Test func vectorExportRecognizesPngBytes() {
        #expect(EaselVectorExport.imageMimeType(png) == "image/png")
    }

    @Test func textExportsAtItsObjectsOriginEscapedInTheEaselFont() {
        let item = EaselItem(kind: .text, frame: .init(x: 30, y: 40, width: 200, height: 40), text: "Hi")
        var layout = EaselVectorText()
        layout.runs = [EaselVectorTextRun(x: 10, y: 20, text: "Hi & bye", fontFamily: "\"EB Garamond\",serif", fontSize: 16, weight: 700,
                                          italic: true, color: nil, underline: true, link: "https://example.com")]
        var art = EaselVectorArt()
        art.texts[item.id] = layout
        let svg = EaselVectorExport.element(item, art: art)
        #expect(svg.contains("translate(30 40)"), "text sits at its object's origin")
        #expect(svg.contains("Hi &amp; bye"), "text content is escaped")
        #expect(svg.contains("font-family:&quot;EB Garamond&quot;,serif"), "the Easel font is kept")
        #expect(svg.contains("font-weight:700") && svg.contains("font-style:italic") && svg.contains("text-decoration:underline"), "emphasis survives")
        #expect(svg.contains("<a href=\"https://example.com\""), "text links stay links")
        layout.runs[0].color = "#00FF00"
        layout.fillPath = "M0 0L10 0L10 10Z"
        art.texts[item.id] = layout
        let filled = EaselVectorExport.element(item, art: art)
        #expect(filled.contains("fill:#00FF00") && filled.contains("<path d=\"M0 0L10 0L10 10Z\""), "fills and chosen text colours are exported")
    }
}
