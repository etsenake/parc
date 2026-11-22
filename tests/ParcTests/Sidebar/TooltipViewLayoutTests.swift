import AppKit
import Testing
@testable import Parc
@testable import ParcKit

@MainActor
struct TooltipViewLayoutTests {
    private static let commandS = KeyboardShortcut(key: "s", flags: .command)
    private static let long = "We’re having trouble connecting to GitHub; click here to see your Pull Requests."
    private static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.001) -> Bool { abs(a - b) <= tolerance }
    private static func content(_ label: String, _ shortcut: KeyboardShortcut? = nil, maxWidth: CGFloat = 296) -> TooltipView.Content {
        TooltipView.Content(label: label, keycaps: shortcut.map(TooltipKeycap.keycaps) ?? [], corners: TooltipCorners(anchor: .bottomTrailing),
                            palette: .neutral, maxWidth: maxWidth)
    }
    private static func layout(_ label: String, _ shortcut: KeyboardShortcut? = nil, scale: CGFloat = 2) -> TooltipView.Layout {
        TooltipView.layout(for: content(label, shortcut), scale: scale)
    }
    private static func label(_ title: String, _ subtitle: String?) -> TooltipView.Layout {
        var value = content(title); value.style = .label(subtitle: subtitle)
        return TooltipView.layout(for: value, scale: 2)
    }

    @Test func aOneLineTooltipIsTwentyEightPointsTall() {
        let hide = Self.layout("Hide sidebar", Self.commandS)
        #expect(hide.size.height == 28 && hide.pill == CGRect(origin: .zero, size: hide.size))
    }

    @Test func theLabelSitsTenPointsInVerticallyCentredToThePixel() {
        let hide = Self.layout("Hide sidebar", Self.commandS)
        #expect(hide.label.minX == 10 && Self.near(hide.label.midY, 14, 0.25))
    }

    @Test func theLabelTakesItsNaturalWidthRoundedUpToAPixel() {
        let hide = Self.layout("Hide sidebar", Self.commandS), natural = TooltipView.labelString("Hide sidebar").size().width
        #expect(hide.label.width >= natural && hide.label.width - natural < 0.5)
    }

    @Test func nineteenPointKeycapsAreCentredInTheRow() {
        let hide = Self.layout("Hide sidebar", Self.commandS)
        #expect(hide.keycaps.count == 2 && hide.keycaps.allSatisfy { $0.size == CGSize(width: 19, height: 19) && $0.minY == 4.5 })
    }

    @Test func keycapsSitSixPointsAfterTheLabelThreeApartAndTenFromTheEnd() {
        let hide = Self.layout("Hide sidebar", Self.commandS)
        #expect(hide.keycaps[0].minX == hide.label.maxX + 6 && hide.keycaps[1].minX == hide.keycaps[0].maxX + 3)
        #expect(hide.size.width == hide.keycaps[1].maxX + 10)
    }

    @Test func sizesLandOnDevicePixels() {
        let hide = Self.layout("Hide sidebar", Self.commandS)
        #expect(hide.size.width * 2 == (hide.size.width * 2).rounded())
    }

    @Test(arguments: [CGFloat(1), 2])
    func labelAndKeycapOriginsLandOnDevicePixels(_ scale: CGFloat) {
        let layout = Self.layout("Hide sidebar", Self.commandS, scale: scale)
        #expect(([layout.label.minY] + layout.keycaps.map(\.minY)).allSatisfy { $0 * scale == ($0 * scale).rounded() })
    }

    @Test func theMarginRoundsUpToADevicePixel() {
        #expect(TooltipView.margin(scale: 2) == 32.5 && TooltipView.margin(scale: 1) == 33)
        #expect(Self.near(TooltipView.margin(scale: 3), 98.0 / 3))
    }

    @Test func aLabelOnlyTooltipHasNoKeycaps() {
        let reload = Self.layout("Reload this page")
        #expect(reload.keycaps.isEmpty && reload.size.width == reload.label.width + 20)
    }

    @Test func aWiderGlyphWidensItsKeycap() {
        let tab = Self.layout("Next", KeyboardShortcut(key: "\t", flags: .control))
        #expect(tab.keycaps[0].width == 19 && tab.keycaps[1].width > 19)
        #expect(tab.keycaps[1].width >= TooltipView.glyphString("TAB").size().width + 6)
    }

    @Test func aLongLabelWrapsWithin296Points() {
        let wrapped = Self.layout(Self.long)
        #expect(wrapped.size.width == 296 && wrapped.size.height > 28)
    }

    @Test func thePillIsAsWideAsTheWidestLine() {
        let wrapped = Self.layout(Self.long)
        #expect(wrapped.label.width <= 276 && wrapped.pill.width == wrapped.label.width + 20 && wrapped.pill.height == wrapped.size.height)
    }

    @Test func theLabelWrapsBesideTheKeycapsWhichStayCentred() {
        let withKeys = Self.layout(Self.long, KeyboardShortcut(key: "c", flags: [.command, .shift]))
        let keys = withKeys.keycaps.last!.maxX - withKeys.keycaps.first!.minX
        #expect(withKeys.label.width <= 296 - 20 - 6 - keys)
        #expect(withKeys.keycaps.allSatisfy { Self.near($0.midY, withKeys.size.height / 2) })
    }

    @Test func aConfiguredMaximumWidthIsUsed() {
        #expect(TooltipView.layout(for: Self.content(Self.long, maxWidth: 150), scale: 2).size.width == 150)
    }

    @Test func labelAndSubtitleTakeSwiftUIsWholePointLineHeights() {
        #expect(TooltipView.Label.lineHeight(TooltipView.labelFont) == 15)
        #expect(TooltipView.Label.lineHeight(TooltipView.Label.subtitleFont) == 14)
    }

    @Test func theSubtitleSitsDirectlyBelowTheLabelLeading() {
        let titled = Self.label("Sign in to GitHub", "Double-click to rename")
        #expect(titled.label.height == 15 && titled.subtitle?.height == 14 && titled.subtitle?.minY == titled.label.maxY)
        #expect(titled.subtitle?.minX == 10 && titled.label.minX == 10)
    }

    @Test func twoLinesMakeATwentyNinePointRow() {
        let titled = Self.label("Sign in to GitHub", "Double-click to rename")
        #expect(titled.size.height == 29 && titled.pill.height == 29)
    }

    @Test func theRowIsAsWideAsTheWiderText() throws {
        let titled = Self.label("Sign in to GitHub", "Double-click to rename")
        let subtitle = try #require(titled.subtitle)
        let hint = TooltipView.lineString("Double-click to rename", font: TooltipView.Label.subtitleFont).size().width
        #expect(titled.size.width == max(titled.label.width, subtitle.width) + 20 && subtitle.width >= hint)
    }

    @Test func withoutASubtitleTheLabelIsCentredInTheRow() {
        let renamed = Self.label("Sign in to GitHub", nil)
        #expect(renamed.subtitle == nil && renamed.size.height == 28 && renamed.label.height == 15 && Self.near(renamed.label.midY, 14, 0.25))
    }

    @Test func theLabelStopsAtFourLinesAndTheSubtitleFollowsIt() {
        let capped = Self.label(String(repeating: Self.long + " ", count: 4), "Double-click to rename")
        #expect(capped.label.height == 60 && capped.subtitle?.minY == 60 && capped.size.height == 74 && capped.size.width == 296)
    }

    @Test func standardContentHasNoSubtitle() {
        #expect(Self.layout("Sign in to GitHub").subtitle == nil)
    }
}

@MainActor
struct TooltipViewDrawingTests {
    private static let m = TooltipShadow.windowMargin
    private static let content = TooltipView.Content(label: "Hide sidebar", keycaps: TooltipKeycap.keycaps(for: KeyboardShortcut(key: "s", flags: .command)),
                                                     corners: TooltipCorners(anchor: .bottomTrailing), palette: .neutral, maxWidth: 296)

    private static func tooltip(dark: Bool) -> TooltipView {
        let view = TooltipView(content: content)
        let size = view.contentLayout.size
        view.frame = NSRect(x: 0, y: 0, width: size.width + 2 * m, height: size.height + 2 * m)
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        return view
    }
    private static func render(_ view: NSView) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!.retagging(with: .sRGB)!
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }
    private static func pixel(_ rep: NSBitmapImageRep, _ point: CGPoint) -> [Int] {
        var raw = [Int](repeating: 0, count: 4)
        rep.getPixel(&raw, atX: Int(point.x * 2), y: Int(point.y * 2))
        return raw
    }
    private static func keyFace(_ value: [Int]) -> Bool { value.prefix(3).allSatisfy { (229...230).contains($0) } }
    private static func lip(_ value: [Int]) -> Bool { value.prefix(3).allSatisfy { (140...165).contains($0) } }
    private static func key(_ view: TooltipView, _ index: Int) -> CGRect { view.contentLayout.keycaps[index].offsetBy(dx: m, dy: m) }

    @Test func theLightPillFillsWithTheBackgroundColour() {
        #expect(Self.pixel(Self.render(Self.tooltip(dark: false)), CGPoint(x: Self.m + 4, y: Self.m + 14)) == [255, 255, 255, 255])
    }

    @Test func theKeyFaceIsKeyForeground() {
        let view = Self.tooltip(dark: false), key = Self.key(view, 0)
        #expect(Self.keyFace(Self.pixel(Self.render(view), CGPoint(x: key.minX + 3, y: key.minY + 2.5))))
    }

    @Test func theLipShowsTheShadedKeyBackground() {
        let view = Self.tooltip(dark: false), key = Self.key(view, 0)
        #expect(Self.lip(Self.pixel(Self.render(view), CGPoint(x: key.midX, y: key.maxY - 2))))
    }

    @Test func theLightAppearanceHasNoBorder() {
        #expect(Self.pixel(Self.render(Self.tooltip(dark: false)), CGPoint(x: Self.m + 70, y: Self.m + 0.25))[0] == 255)
    }

    @Test func twoShadowsTheWiderOneOffsetDownward() {
        let rep = Self.render(Self.tooltip(dark: false))
        let below = Self.pixel(rep, CGPoint(x: Self.m + 70, y: Self.m + 30))[3], above = Self.pixel(rep, CGPoint(x: Self.m + 70, y: Self.m - 2))[3]
        #expect(below > above && above > 0)
    }

    @Test func theMarginBeyondTheShadowsStaysClear() {
        #expect(Self.pixel(Self.render(Self.tooltip(dark: false)), CGPoint(x: 1, y: 1))[3] == 0)
    }

    @Test func theDarkPillIsSeventeenPercentGrey() {
        #expect(Self.pixel(Self.render(Self.tooltip(dark: true)), CGPoint(x: Self.m + 4, y: Self.m + 14)).prefix(3).allSatisfy { $0 == 43 })
    }

    @Test func theDarkAppearanceHasATenPercentWhiteBorder() {
        #expect(Self.pixel(Self.render(Self.tooltip(dark: true)), CGPoint(x: Self.m + 70, y: Self.m + 0.25))[0] > 55)
    }

    @Test func aHeldKeysFaceDropsToItsOnePointInset() {
        let held = Self.tooltip(dark: false), key = Self.key(held, 0)
        held.setPressed(modifiers: .command, characters: nil)
        #expect(Self.keyFace(Self.pixel(Self.render(held), CGPoint(x: key.midX, y: key.maxY - 2))))
    }

    @Test func keysThatAreNotHeldKeepTheLip() {
        let held = Self.tooltip(dark: false), other = Self.key(held, 1)
        held.setPressed(modifiers: .command, characters: nil)
        #expect(Self.lip(Self.pixel(Self.render(held), CGPoint(x: other.midX, y: other.maxY - 2))))
    }

    @Test func aNewPaletteRepaintsThePillInPlaceAndKeepsAHeldKeyHeld() {
        let held = Self.tooltip(dark: false), key = Self.key(held, 0), layout = held.contentLayout
        held.setPressed(modifiers: .command, characters: nil)
        var repainted = held.content.palette
        repainted.background = .init(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        held.content.palette = repainted
        let rep = Self.render(held)
        #expect(Self.pixel(rep, CGPoint(x: Self.m + 4, y: Self.m + 14)) == [255, 0, 0, 255])
        #expect(held.contentLayout == layout)
        #expect(Self.keyFace(Self.pixel(rep, CGPoint(x: key.midX, y: key.maxY - 2))))
    }

    private static func labelView() -> (TooltipView, NSBitmapImageRep) {
        var labelContent = TooltipView.Content(label: "Sign in to GitHub", keycaps: [], corners: TooltipCorners(anchor: .cursor),
                                               palette: .neutral, maxWidth: 296, style: .label(subtitle: "Double-click to rename"))
        labelContent.palette.title = .init(.black)
        let view = TooltipView(content: labelContent)
        let size = view.contentLayout.size
        view.frame = NSRect(x: 0, y: 0, width: size.width + 2 * m, height: size.height + 2 * m)
        view.appearance = NSAppearance(named: .aqua)
        return (view, render(view))
    }

    @Test func aTwoLineLabelsBackgroundOverhangsSevenPointsAboveAndBelow() {
        let (view, rep) = Self.labelView()
        let height = view.contentLayout.size.height
        #expect(Self.pixel(rep, CGPoint(x: Self.m + 40, y: Self.m - 5)) == [255, 255, 255, 255])
        #expect(Self.pixel(rep, CGPoint(x: Self.m + 40, y: Self.m + height + 5)) == [255, 255, 255, 255])
    }

    @Test func theTitleIsBlackAndTheSubtitleAtTwoThirdsOpacityOverWhite() throws {
        let (view, rep) = Self.labelView()
        func darkest(_ rect: CGRect) -> Int {
            var value = 255
            for y in stride(from: rect.minY, to: rect.maxY, by: 0.5) {
                for x in stride(from: rect.minX, to: rect.maxX, by: 0.5) { value = min(value, Self.pixel(rep, CGPoint(x: x, y: y))[0]) }
            }
            return value
        }
        let subtitle = try #require(view.contentLayout.subtitle)
        #expect(darkest(view.contentLayout.label.offsetBy(dx: Self.m, dy: Self.m)) < 40)
        #expect((60...130).contains(darkest(subtitle.offsetBy(dx: Self.m, dy: Self.m))))
    }
}
