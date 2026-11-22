import Foundation
import Testing
@testable import ParcCore

struct EaselVectorExportPaletteTests {
    @Test
    func legacyShapesExportWithTheirOriginalStrokeAndWash() {
        let shape = EaselItem(kind: .rectangle, frame: .init(x: 0, y: 0, width: 40, height: 20))
        let legacy = EaselVectorExport.element(shape, art: .init())
        #expect(legacy.contains("fill:var(--easel-ink);fill-opacity:0.09;stroke:var(--easel-ink);stroke-width:2.5"),
               "shapes saved before styles export as before")
    }

    @Test
    func paletteFillsAndOutlinesExportAsAdaptiveVariables() {
        var shape = EaselItem(kind: .rectangle, frame: .init(x: 0, y: 0, width: 40, height: 20))
        shape.color = "#2C6C91"; shape.fill = "#D8E9F3"; shape.strokeWidth = 5; shape.strokeDash = .dotted
        let styled = EaselVectorExport.element(shape, art: .init())
        #expect(styled.contains("fill:var(--easel-fill-blue,#D8E9F3)") && styled.contains("stroke:var(--easel-ink-blue,#2C6C91)"),
               "palette fills and outlines export as adaptive variables with light fallbacks")
        #expect(styled.contains("stroke-width:5;stroke-dasharray:0 10;stroke-linecap:round"), "outline width and dots export")
    }

    @Test
    func objectsWithoutFillOrOutlineExportWithNeither() {
        var shape = EaselItem(kind: .rectangle, frame: .init(x: 0, y: 0, width: 40, height: 20))
        shape.color = "#2C6C91"; shape.fill = "#D8E9F3"; shape.strokeWidth = 5; shape.strokeDash = .dotted
        shape.fillOpacity = 0; shape.strokeWidth = 0
        let bare = EaselVectorExport.element(shape, art: .init())
        #expect(bare.contains("fill:none") && bare.contains("stroke:none"), "no fill and no outline export as none")
    }

    @Test
    func stickyPaperAdaptsOnlyToStickyPaletteColours() {
        var sticky = EaselItem(kind: .sticky, frame: .init(x: 0, y: 0, width: 200, height: 200))
        sticky.fill = "#F5E0AC"
        #expect(EaselVectorExport.element(sticky, art: .init()).contains("fill:var(--easel-sticky-yellow,#F5E0AC)"),
               "sticky paper exports through the sticky colours")
        sticky.fill = "#2C6C91"
        #expect(EaselVectorExport.element(sticky, art: .init()).contains("fill:#2C6C91"), "an ink colour used as paper stays fixed")
    }

    @Test
    func arrowExportAppliesDashesOnlyToTheShaft() {
        var arrow = EaselItem(kind: .arrow, frame: .init(x: 0, y: 0, width: 100, height: 0))
        arrow.points = [.init(x: 0, y: 0), .init(x: 100, y: 0)]
        arrow.color = "#C0322D"; arrow.strokeWidth = 6; arrow.strokeDash = .dashed
        let svgArrow = EaselVectorExport.element(arrow, art: .init())
        let paths = svgArrow.components(separatedBy: "<path").dropFirst()
        let shaft = paths.first ?? ""
        #expect(shaft.contains("stroke:var(--easel-ink-red,#C0322D)") && shaft.contains("stroke-width:6") && shaft.contains("stroke-dasharray:18 18"),
               "arrow shafts export their colour, width and dashes")
        #expect(paths.last?.contains("stroke-dasharray") == false, "arrow heads stay solid")
    }

    @Test
    func highlighterExportUsesTranslucentHighlightColours() {
        var marker = EaselItem(kind: .freehand, frame: .init(x: 0, y: 0, width: 10, height: 10))
        marker.points = [.init(x: 0, y: 0), .init(x: 10, y: 10)]
        marker.brush = .highlighter
        let highlight = EaselVectorExport.strokeStyle(marker, rounded: true)
        #expect(highlight.contains("stroke:var(--easel-highlight-yellow,#E8B53A);stroke-width:16;stroke-opacity:0.35"),
               "highlighters export translucent highlight colours")
    }

    @Test
    func exportedStylesIncludeLightAndDarkSwatches() {
        let css = EaselVectorExport.css(.standard)
        let parts = css.components(separatedBy: "prefers-color-scheme:dark")
        #expect(parts.count >= 2 && parts[0].contains("--easel-ink-blue:#2C6C91;") && parts[1].contains("--easel-ink-blue:#4CA5D8;"),
               "palette colours carry light and dark values")
        #expect(parts.count >= 2 && parts[1].contains("--easel-sticky-neutral:#2A2733;") && parts[1].contains("--easel-fill-blue:#27425A;"),
               "dark viewers get the dark paper colours")
    }

    @Test
    func paletteTextColoursAdaptInExports() {
        let run = EaselVectorTextRun(x: 0, y: 0, text: "Hi", fontFamily: "serif", fontSize: 12, color: "#3B7255")
        #expect(EaselVectorExport.textRun(run).contains("fill:var(--easel-ink-green,#3B7255)"), "palette text colours adapt in exports")
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
