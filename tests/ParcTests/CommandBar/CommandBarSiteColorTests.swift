import AppKit
import Testing
@testable import ParcCommandBar

struct CommandBarSiteColorTests {
    @Test(arguments: [
        ("www.youtube.com", false, "FF0000"), ("www.youtube.com", true, nil),
        ("en.wikipedia.org", false, "FF4500"), ("m.youtube.com", false, nil),
        ("www.google.com", true, nil), ("", false, nil),
    ] as [(String, Bool, String?)])
    @MainActor func aBundledSearchColorUsesTheEngineHost(host: String, prepopulated: Bool, hex: String?) {
        let color = CommandBarSiteColor.bundledColor(template: "https://\(host)/?q={searchTerms}",
                                                    searchHost: host, prepopulated: prepopulated)
        #expect(color == hex.flatMap(CommandBarSiteColor.color(hex:)))
        if let color { #expect(color.colorSpace == .displayP3) }
    }

    @Test(arguments: ["75A99", "GGGGGG"])
    @MainActor func invalidHexHasNoColor(hex: String) {
        #expect(CommandBarSiteColor.color(hex: hex) == nil)
    }

    @Test(arguments: [
        ("www.youtube.com", "www.youtube.com", true), ("WWW.YouTube.com", "youtube.com", true),
        ("a.b.example.com", "b", true), ("notyoutube.com", "youtube.com", false),
    ])
    @MainActor func aHostMatchesOnLabelBoundaries(host: String, pattern: String, expected: Bool) {
        #expect(CommandBarSiteColor.host(host, matches: pattern) == expected)
    }

    @Test(arguments: [
        ("www.youtube.com", "YouTube"), ("youtube.com", "YouTube"), ("wikipedia.org", "Wikipedia"),
        ("m.youtube.com", nil), ("en.m.wikipedia.org", nil), ("www", "Maps"), ("", nil),
    ] as [(String, String?)])
    @MainActor func theSearchScopeUsesThePageHost(host: String, expected: String?) {
        let engines = [(name: "Maps", host: "www.google.com"), (name: "YouTube", host: "www.youtube.com"),
                       (name: "Wikipedia", host: "en.wikipedia.org"), (name: "Legacy", host: "")]
        #expect(CommandBarSiteColor.scope(forPageHost: host, in: engines) { $0.host }?.name == expected)
    }

    @Test(arguments: [((238, 203, 168), [225, 165, 104]), ((148, 148, 148), [110, 110, 110]), ((20, 20, 20), [0, 0, 0])]
          as [((UInt8, UInt8, UInt8), [Int])])
    @MainActor func aFaviconColorReducesLightnessWhileKeepingItsHue(rgb: (UInt8, UInt8, UInt8), expected: [Int]) throws {
        let color = try #require(CommandBarSiteColor.faviconColor(rgb).usingColorSpace(.sRGB))
        #expect([color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) } == expected)
    }

    private func pixels(_ samples: [(UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] {
        samples.flatMap { [$0.3, $0.2, $0.1, $0.0] + [UInt8](repeating: 0, count: 36) }
    }

    @Test(arguments: [(255, 0, 0, 0), (255, 255, 255, 255)] as [(UInt8, UInt8, UInt8, UInt8)])
    func transparentAndWhitePixelsDoNotSupplyPaletteColors(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        #expect(MedianCutPalette.palette(pixels([(red, green, blue, alpha)]),
                                         colorCount: 5, quality: 10, ignoresWhite: true) == nil)
    }

    @Test(arguments: [false, true])
    @MainActor func aVisibleFaviconColorTakesPrecedenceOverBlack(hasGreen: Bool) {
        let black = Array(repeating: (UInt8(0), UInt8(0), UInt8(0), UInt8(255)), count: 9)
        let data = pixels(black + (hasGreen ? [(0, 255, 0, 255)] : []))
        #expect(CommandBarSiteColor.dominantRGB(data).map { [$0.0, $0.1, $0.2] } == (hasGreen ? [4, 252, 4] : [4, 4, 4]))
    }

    @Test @MainActor func faviconPixelsKeepTheirChannelOrder() throws {
        let icon = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let data = try #require(CommandBarSiteColor.faviconPixels(icon))
        let image = try #require(icon.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(data.count == image.width * image.height * 4)
        #expect(data[1] > data[3])
    }

    enum Scope: CaseIterable { case site, actions, extensionSearch }

    @Test(arguments: Scope.allCases)
    @MainActor func theScopePillFitsItsCenteredTitle(scope: Scope) {
        let pill = CommandBarScopePill()
        let title: String
        switch scope {
        case .site: title = "YouTube"; pill.showSite(name: title, unavailable: false)
        case .actions: title = "Actions"; pill.showActions()
        case .extensionSearch: title = "Extension Finder"; pill.showExtension(name: title)
        }
        pill.frame = NSRect(origin: .zero, size: pill.intrinsicContentSize)
        pill.layout()
        #expect(pill.titleLabel.stringValue == title)
        #expect(pill.titleLabel.frame.midY == pill.bounds.midY)
        #expect(pill.titleLabel.frame.width >= pill.titleLabel.intrinsicContentSize.width)
    }

    @Test @MainActor func theScopePillUsesItsFocusColorForTheFillAndGlow() throws {
        let pill = CommandBarScopePill()
        #expect(pill.focusColor == CommandBarPalette.colourless.scopePill)
        let color = NSColor(srgbRed: 1, green: 0.27, blue: 0, alpha: 1)
        pill.focusColor = color
        pill.frame = NSRect(x: 0, y: 0, width: 100, height: 24)
        pill.layout()
        let fill = try #require(pill.layer?.backgroundColor)
        #expect(NSColor(cgColor: fill)?.usingColorSpace(.sRGB) == color)
        #expect(pill.shadow?.shadowColor?.alphaComponent == 0.3)
        #expect(pill.layer?.shadowPath != nil)
    }

    @Test(arguments: [false, true])
    @MainActor func theScopeHintShowsOnlyEnabledTriggers(spaceEnabled: Bool) {
        let hint = CommandBarScopeHint()
        hint.show(site: "YouTube", spaceTriggerEnabled: spaceEnabled)
        #expect(hint.subviews.compactMap { ($0 as? CommandBarKeycap)?.key } == (spaceEnabled ? ["Space", "Tab"] : ["Tab"]))
    }

    @Test @MainActor func aNarrowScopeHintGivesTheKeycapsRoomBeforeTheTitle() throws {
        let hint = CommandBarScopeHint()
        hint.show(site: "Wikipedia (English)", spaceTriggerEnabled: true)
        hint.frame = NSRect(x: 0, y: 0, width: 350 * 0.45, height: hint.intrinsicContentSize.height)
        hint.layout()
        let text = try #require(hint.textFrames.first)
        #expect(text.frame.width < CommandBarScopeHint.width(text.text))
        #expect(hint.subviews.compactMap { $0 as? CommandBarKeycap }.allSatisfy { hint.bounds.contains($0.frame) })
    }

    @Test @MainActor func aHiddenScopeHintDoesNotCaptureClicks() {
        let hint = CommandBarScopeHint()
        hint.show(site: "YouTube", spaceTriggerEnabled: true)
        hint.frame = NSRect(origin: .zero, size: hint.intrinsicContentSize)
        hint.isHidden = true
        #expect(hint.hitTest(NSPoint(x: 1, y: 1)) == nil)
    }
}

extension CommandBarSiteColorTests {
    @Test @MainActor func theSearchHintDropsItsTitleBeforeTheKeys() {
        let hint = CommandBarScopeHint()
        hint.show(site: "Wikipedia (English)", spaceTriggerEnabled: true)
        let title = CommandBarScopeHint.width("Search Wikipedia (English)")
        let keyWidth = hint.intrinsicContentSize.width - title - CommandBarScopeHint.spacing
        hint.frame = NSRect(x: 0, y: 0, width: keyWidth + 4, height: hint.intrinsicContentSize.height)
        hint.layout()
        #expect(hint.textFrames.map(\.text) == ["or"])
        #expect(hint.subviews.compactMap { $0 as? CommandBarKeycap }.allSatisfy { hint.bounds.contains($0.frame) })
    }

    @Test(arguments: [false, true])
    @MainActor func theKeycapsKeepTheExpectedContrastInEachAppearance(dark: Bool) {
        let appearance = dark ? CommandBarTestSupport.dark : CommandBarTestSupport.light
        #expect(CommandBarTestSupport.rgba(CommandBarScopeHint.keyColor, in: appearance).w == (dark ? 0.66 : 0.5))
        #expect(CommandBarTestSupport.rgba(CommandBarScopeHint.keyFill, in: appearance).w == 0.05)
    }

    @Test @MainActor func repeatedSolidPixelsSupplyTheDominantPaletteColor() {
        let data = pixels([(255, 0, 0, 255), (255, 0, 0, 255)])
        let palette = MedianCutPalette.palette(data, colorCount: 5, quality: 10, ignoresWhite: true)
        #expect(palette?.first.map { [$0.0, $0.1, $0.2] } == [252, 4, 4])
    }
}
