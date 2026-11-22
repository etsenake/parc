import AppKit
import CoreText
import Testing
@testable import ParcCore
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct SplitAppearanceTitleViewTests {
    @MainActor private final class Fixture {
        let row: SidebarSplitTitleView
        let iconView: NSImageView
        let countIcon: NSView

        init(title: String = "Original", count: Int = 2) {
            _ = NSApplication.shared
            row = SidebarSplitTitleView(title: title, count: count)
            iconView = row.subviews.compactMap { $0 as? NSImageView }.first!
            countIcon = row.subviews.first { !($0 is NSTextField) && !($0 is NSImageView) && $0.layer?.cornerRadius == 4 }!
        }

        var shownCount: String? { countIcon.isHidden ? nil : countIcon.subviews.compactMap { $0 as? NSTextField }.first?.stringValue }
        var shownImage: NSImage? { iconView.isHidden ? nil : iconView.image }
        var title: NSTextField { row.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Original" }! }

        func layout() {
            row.frame = NSRect(x: 0, y: 0, width: 212, height: 36)
            row.titleTrailing = 164
            row.layoutSubtreeIfNeeded()
        }
    }

    private static func pixels(_ image: NSImage?) -> Data? {
        guard let image, let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
                                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.bitmapData.map { Data(bytes: $0, count: bitmap.bytesPerRow * bitmap.pixelsHigh) }
    }

    @Test func aNativeSymbolShowsAsAGenuineTemplateSymbolWithNoCount() {
        let f = Fixture()
        f.row.setIcon(.symbol("star"))
        #expect(f.shownImage?.isTemplate == true)
        #expect(Self.pixels(f.shownImage) == Self.pixels(NSImage(systemSymbolName: "star", accessibilityDescription: nil)))
        #expect(f.shownCount == nil)
    }

    @Test func anEmojiIsDrawnAsAnUntintedSixteenPointImage() {
        let f = Fixture()
        f.row.setIcon(.emoji("🧭"))
        let compass = Self.pixels(SidebarGroupIcon.emoji("🧭").image(size: 16))
        #expect(compass != nil)
        #expect(Self.pixels(f.shownImage) == compass)
        #expect(compass != Self.pixels(SidebarGroupIcon.emoji("🍕").image(size: 16)))
        #expect(f.shownCount == nil)
        #expect(f.shownImage?.size == NSSize(width: 16, height: 16))
        #expect(f.shownImage?.isTemplate == false)
        #expect(!f.row.subviews.contains { ($0 as? NSTextField)?.stringValue == "🧭" })
    }

    @Test func resettingTheIconRestoresTheOriginalCount() {
        let f = Fixture()
        f.row.setIcon(.emoji("🧭"))
        f.row.setIcon(nil)
        #expect(f.shownCount == "2")
        #expect(f.shownImage == nil)
    }

    @Test func aCatalogIconIsASixteenPointTemplateGlyph() {
        let f = Fixture()
        f.row.setIcon(.icon(.star))
        f.row.layoutSubtreeIfNeeded()
        #expect(Self.pixels(f.shownImage) == Self.pixels(SidebarGroupIcon.icon(.star).image(size: 16)))
        #expect(f.shownCount == nil)
        #expect(f.shownImage?.isTemplate == true)
        #expect(f.shownImage?.size == NSSize(width: 16, height: 16))
    }

    @Test func theCustomTitleIsDrawnFromThirtySixAtFourteenPointsRegularBeforeClose() {
        let f = Fixture()
        f.layout()
        #expect(f.title.frame.minX == SidebarSplitCellLayout.infoTitleInset - SidebarRowAppearance.titleTextPadding)
        #expect(SidebarSplitCellLayout.infoTitleInset == 36)
        #expect(f.title.frame.maxX == 164 + SidebarRowAppearance.titleTextPadding)
        #expect(f.title.font?.pointSize == 14)
        #expect(f.title.font?.fontDescriptor.symbolicTraits.contains(.bold) == false)
    }

    @Test func renamingEditsInTheTitlesFrame() {
        let f = Fixture()
        f.layout()
        #expect(f.row.subviews.compactMap { $0 as? SidebarTitleField }.first?.frame == f.title.frame)
    }

    @Test func theCountIconIsSixteenPointsCentredInTheTwentyFourPointSlot() {
        let f = Fixture()
        f.layout()
        #expect(f.countIcon.frame == NSRect(x: 10, y: 10, width: 16, height: 16))
    }

    @Test func theCountLabelIsBoldTen() throws {
        let f = Fixture()
        f.layout()
        let label = try #require(f.countIcon.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(label.font?.pointSize == 10)
        #expect(label.font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test func theCountUsesMaxContrastOnACutoutAtEightyPercent() throws {
        let f = Fixture()
        f.layout()
        let label = try #require(f.countIcon.subviews.compactMap { $0 as? NSTextField }.first)
        f.row.applyColors(title: .systemPurple, secondary: .systemOrange, countText: .white, countBackground: .black, dark: true)
        #expect(label.textColor == .white)
        #expect(f.countIcon.layer?.backgroundColor?.alpha == 0.8)
    }

    @Test func withoutCloseTheTitleEndsTenInside() {
        let f = Fixture()
        f.layout()
        f.row.titleTrailing = nil
        f.row.layoutSubtreeIfNeeded()
        #expect(f.title.frame.maxX == 202 + SidebarRowAppearance.titleTextPadding)
    }

    @Test func anIconOnlySplitShowsTheDefaultTitleNamesItselfToAccessibilityAndHasNoTooltip() {
        _ = NSApplication.shared
        let unnamed = SidebarSplitTitleView(title: SidebarSplitCellLayout.defaultTitle(count: 3), count: 3, named: false)
        #expect(unnamed.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "3 Tabs" })
        #expect(unnamed.accessibilityLabel() == "Split View, 3 tabs")
        #expect(unnamed.toolTip == nil)
        #expect(unnamed.parcTooltip == nil)
    }

    @Test func aNamedSplitsTitleIsItsTooltipAfterAHundredthOfASecond() {
        let f = Fixture()
        #expect(f.row.parcTooltip == TooltipConfiguration("Original", behavior: .onMouseIdle(delay: 0.01)))
        #expect(f.row.toolTip == nil)
    }

    @Test func theTwentyFourPointSlotAnchorsThePicker() {
        let f = Fixture()
        f.layout()
        f.row.setIcon(.icon(.star))
        f.row.layoutSubtreeIfNeeded()
        #expect(f.row.iconContainerFrame == NSRect(x: SidebarSplitCellLayout.infoLeadingInset, y: 6, width: 24, height: 24))
    }
}
