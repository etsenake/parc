import Foundation
import Testing
@testable import ParcCore
struct EaselVectorExportTests {
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!

    @Test func palettesExportAsAdaptiveVariablesWithLightFallbacks() {
        var shape = EaselItem(kind: .rectangle, frame: .init(x: 0, y: 0, width: 40, height: 20))
        let legacy = EaselVectorExport.element(shape, art: .init())
        #expect(legacy.contains("fill:var(--easel-ink);fill-opacity:0.09;stroke:var(--easel-ink);stroke-width:2.5"),
               "shapes saved before styles export as before")
        shape.color = "#2C6C91"; shape.fill = "#D8E9F3"; shape.strokeWidth = 5; shape.strokeDash = .dotted
        let styled = EaselVectorExport.element(shape, art: .init())
        #expect(styled.contains("fill:var(--easel-fill-blue,#D8E9F3)") && styled.contains("stroke:var(--easel-ink-blue,#2C6C91)"),
               "palette fills and outlines export as adaptive variables with light fallbacks")
        #expect(styled.contains("stroke-width:5;stroke-dasharray:0 10;stroke-linecap:round"), "outline width and dots export")
        shape.fillOpacity = 0; shape.strokeWidth = 0
        let bare = EaselVectorExport.element(shape, art: .init())
        #expect(bare.contains("fill:none") && bare.contains("stroke:none"), "no fill and no outline export as none")
        var sticky = EaselItem(kind: .sticky, frame: .init(x: 0, y: 0, width: 200, height: 200))
        sticky.fill = "#F5E0AC"
        #expect(EaselVectorExport.element(sticky, art: .init()).contains("fill:var(--easel-sticky-yellow,#F5E0AC)"),
               "sticky paper exports through the sticky colours")
        sticky.fill = "#2C6C91"
        #expect(EaselVectorExport.element(sticky, art: .init()).contains("fill:#2C6C91"), "an ink colour used as paper stays fixed")
        var arrow = EaselItem(kind: .arrow, frame: .init(x: 0, y: 0, width: 100, height: 0))
        arrow.points = [.init(x: 0, y: 0), .init(x: 100, y: 0)]
        arrow.color = "#C0322D"; arrow.strokeWidth = 6; arrow.strokeDash = .dashed
        let svgArrow = EaselVectorExport.element(arrow, art: .init())
        let paths = svgArrow.components(separatedBy: "<path").dropFirst()
        let shaft = paths.first ?? ""
        #expect(shaft.contains("stroke:var(--easel-ink-red,#C0322D)") && shaft.contains("stroke-width:6") && shaft.contains("stroke-dasharray:18 18"),
               "arrow shafts export their colour, width and dashes")
        #expect(paths.last?.contains("stroke-dasharray") == false, "arrow heads stay solid")
        var marker = EaselItem(kind: .freehand, frame: .init(x: 0, y: 0, width: 10, height: 10))
        marker.points = [.init(x: 0, y: 0), .init(x: 10, y: 10)]
        marker.brush = .highlighter
        let highlight = EaselVectorExport.strokeStyle(marker, rounded: true)
        #expect(highlight.contains("stroke:var(--easel-highlight-yellow,#E8B53A);stroke-width:16;stroke-opacity:0.35"),
               "highlighters export translucent highlight colours")
        let css = EaselVectorExport.css(.standard)
        let parts = css.components(separatedBy: "prefers-color-scheme:dark")
        #expect(parts.count >= 2 && parts[0].contains("--easel-ink-blue:#2C6C91;") && parts[1].contains("--easel-ink-blue:#4CA5D8;"),
               "palette colours carry light and dark values")
        #expect(parts.count >= 2 && parts[1].contains("--easel-sticky-neutral:#2A2733;") && parts[1].contains("--easel-fill-blue:#27425A;"),
               "dark viewers get the dark paper colours")
        let run = EaselVectorTextRun(x: 0, y: 0, text: "Hi", fontFamily: "serif", fontSize: 12, color: "#3B7255")
        #expect(EaselVectorExport.textRun(run).contains("fill:var(--easel-ink-green,#3B7255)"), "palette text colours adapt in exports")
    }

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

    @Test func everyObjectKindExportsItsOwnElement() {
        var circle = EaselItem(kind: .circle, frame: .init(x: 0, y: 0, width: 40, height: 20))
        circle.color = "#FF0000"
        let svgCircle = EaselVectorExport.element(circle, art: .init())
        #expect(svgCircle.contains("<ellipse cx=\"20\" cy=\"10\" rx=\"20\" ry=\"10\""), "circles become ellipses")
        #expect(svgCircle.contains("stroke:#FF0000"), "chosen colours stay exact")
        let square = EaselVectorExport.element(EaselItem(kind: .rectangle, frame: .init(x: 1, y: 2, width: 3, height: 4)), art: .init())
        #expect(square.contains("var(--easel-ink)"), "automatic ink adapts to light and dark")
        var arrow = EaselItem(kind: .arrow, frame: .init(x: 10, y: 10, width: 100, height: 0))
        arrow.points = [.init(x: 0, y: 0), .init(x: 100, y: 0)]
        let svgArrow = EaselVectorExport.element(arrow, art: .init())
        #expect(svgArrow.components(separatedBy: "<path").count == 3, "arrows draw a shaft and a head")
        #expect(svgArrow.contains("M10 10L110 10"), "the shaft follows the saved points")
        var scribble = EaselItem(kind: .freehand, frame: .init(x: 0, y: 0, width: 10, height: 10))
        scribble.points = [.init(x: 0, y: 0), .init(x: 5, y: 5), .init(x: 10, y: 0)]
        #expect(EaselVectorExport.element(scribble, art: .init()).components(separatedBy: "<path").count == 2, "freehand strokes have no head")
        let picture = EaselItem(kind: .image, frame: .init(x: 0, y: 0, width: 10, height: 10), assetID: "a")
        var art = EaselVectorArt()
        art.images[picture.id] = EaselVectorImage(data: png, mimeType: "image/png")
        #expect(EaselVectorExport.element(picture, art: art).contains("href=\"data:image/png;base64,"), "images are embedded")
        #expect(EaselVectorExport.element(picture, art: .init()).isEmpty, "missing images draw nothing")
        let web = EaselItem(kind: .webCard, frame: .init(x: 0, y: 0, width: 10, height: 10), url: "https://example.com", assetID: "w")
        art.images[web.id] = EaselVectorImage(data: png, mimeType: "image/png")
        let svgWeb = EaselVectorExport.element(web, art: art)
        #expect(svgWeb.hasPrefix("<a href=\"https://example.com\""), "web snapshots link to their source")
        #expect(svgWeb.contains("<image"), "web cards show their snapshot")
        let link = EaselItem(kind: .link, frame: .init(x: 0, y: 0, width: 220, height: 160), text: "A <b>", url: "https://example.com")
        let svgLink = EaselVectorExport.element(link, art: .init())
        #expect(svgLink.contains("A &lt;b&gt;") && svgLink.contains("var(--easel-card)"), "link cards show an escaped title on the card fill")
        #expect(EaselVectorExport.imageMimeType(png) == "image/png", "PNG bytes are recognised")
        #expect(EaselVectorExport.imageMimeType(Data([0xFF, 0xD8, 0xFF, 0xE0])) == "image/jpeg", "JPEG bytes are recognised")
        #expect(EaselVectorExport.imageMimeType(Data([1, 2, 3])) == nil, "unknown bytes need converting")
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

    @Test func exportsAreFullHTMLDocumentsWithBothPalettes() {
        var doc = EaselDocument(id: UUID(), title: "Plan <A>", createdAt: Date(), modifiedAt: Date())
        doc.items = [EaselItem(kind: .rectangle, frame: .init(x: 0, y: 0, width: 10, height: 10))]
        let palette = EaselVectorPalette(light: .init(ink: "#111111", card: "#EEEEEE", cardLine: "#DDDDDD", muted: "#777777"),
                                         dark: .init(ink: "#FAFAFA", card: "#222222", cardLine: "#333333", muted: "#999999"))
        let html = EaselVectorExport.htmlDocument(doc, art: .init(), palette: palette)
        #expect(html.hasPrefix("<!DOCTYPE html>"), "exports are full HTML documents")
        #expect(html.contains("<title>Plan &lt;A&gt;</title>") && html.contains("<h1 class=\"page-title\">Plan &lt;A&gt;</h1>"), "the title is escaped")
        #expect(html.contains("--easel-ink:#111111") && html.contains("prefers-color-scheme:dark){:root{--easel-ink:#FAFAFA"), "both palettes ship")
        #expect(html.contains("<svg") && html.contains("viewBox=\"-44 -44 98 98\""), "the canvas is an SVG sized to its content")
        #expect(!html.contains("<script"), "exports carry no scripts")
    }
}
