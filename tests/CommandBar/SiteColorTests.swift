import AppKit

@main struct CommandBarSiteColorTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); assertions += 1
        }
        func components(_ color: NSColor?) -> [Int] {
            guard let c = color?.usingColorSpace(.sRGB) else { return [] }
            return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
        }

        let youtube = "https://www.youtube.com/results?search_query={searchTerms}"
        let red = CommandBarSiteColor.bundledColor(template: youtube, searchHost: "www.youtube.com", prepopulated: false)
        check(red?.colorSpace == .displayP3, "bundled hex is read as Display P3")
        check(red.map { [$0.redComponent, $0.greenComponent, $0.blueComponent] } == [1, 0, 0], "YouTube is P3 FF0000")
        check(CommandBarSiteColor.bundledColor(template: youtube, searchHost: "www.youtube.com", prepopulated: true) == nil,
              "a prepopulated engine takes no bundled colour")
        check(CommandBarSiteColor.bundledColor(template: "https://www.youtube.com/results?search_query={searchTerms}&sp=EgIQAQ",
                                               searchHost: "www.youtube.com", prepopulated: false) == red,
              "another YouTube template matches by host")
        check(components(CommandBarSiteColor.bundledColor(template: "https://en.wikipedia.org/w/index.php?search={searchTerms}",
                                                          searchHost: "en.wikipedia.org", prepopulated: false))
              == components(CommandBarSiteColor.color(hex: "FF4500")), "a subdomain of a bundled host matches")
        check(CommandBarSiteColor.bundledColor(template: "https://m.youtube.com/results?q={searchTerms}",
                                               searchHost: "m.youtube.com", prepopulated: false) == nil,
              "the engine host must sit at or under the bundled host")
        check(CommandBarSiteColor.bundledColor(template: "https://www.google.com/search?q={searchTerms}",
                                               searchHost: "www.google.com", prepopulated: true) == nil,
              "prepopulated Google falls through to its favicon")
        check(CommandBarSiteColor.bundledColor(template: "", searchHost: "", prepopulated: false) == nil, "no host, no colour")
        check(CommandBarSiteColor.bundled.count == 19, "Parc bundles nineteen engines")
        check(CommandBarSiteColor.color(hex: "75A99") == nil && CommandBarSiteColor.color(hex: "GGGGGG") == nil, "malformed hex")

        check(CommandBarSiteColor.host("www.youtube.com", matches: "www.youtube.com"), "equal hosts match")
        check(CommandBarSiteColor.host("WWW.YouTube.com", matches: "youtube.com"), "subdomains match, case-insensitively")
        check(CommandBarSiteColor.host("a.b.example.com", matches: "b"), "a single label matches")
        check(!CommandBarSiteColor.host("notyoutube.com", matches: "youtube.com"), "a suffix without a dot does not")

        check(components(CommandBarSiteColor.faviconColor((238, 203, 168))) == [225, 165, 104], "HSL lightness step")
        check(components(CommandBarSiteColor.faviconColor((148, 148, 148))) == [110, 110, 110], "grey stays grey")
        check(components(CommandBarSiteColor.faviconColor((20, 20, 20))) == [0, 0, 0], "lightness clamps at zero")

        func pixels(_ samples: [(UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] {
            samples.flatMap { sample -> [UInt8] in
                [sample.3, sample.2, sample.1, sample.0] + [UInt8](repeating: 0, count: 36)
            }
        }
        check(MedianCutPalette.palette(pixels([(255, 0, 0, 0)]), colorCount: 5, quality: 10, ignoresWhite: true) == nil,
              "transparent pixels are skipped")
        check(MedianCutPalette.palette(pixels([(255, 255, 255, 255)]), colorCount: 5, quality: 10, ignoresWhite: true) == nil,
              "white pixels are skipped")
        let solid = MedianCutPalette.palette(pixels([(255, 0, 0, 255), (255, 0, 0, 255)]), colorCount: 5, quality: 10, ignoresWhite: true)
        check(solid?.count == 5 && solid?.first.map { [$0.0, $0.1, $0.2] } == [252, 4, 4],
              "a box averages its cell centres; empty cut boxes still fill the palette")
        let mostlyBlack = pixels(Array(repeating: (0, 0, 0, 255), count: 9) + [(0, 255, 0, 255)])
        check(CommandBarSiteColor.dominantRGB(mostlyBlack).map { [$0.0, $0.1, $0.2] } == [4, 252, 4],
              "the first palette entry at least 0.15 bright wins")
        check(CommandBarSiteColor.dominantRGB(pixels(Array(repeating: (0, 0, 0, 255), count: 4))).map { [$0.0, $0.1, $0.2] } == [4, 4, 4],
              "with none that bright, the first entry stands")

        let icon = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1).setFill(); rect.fill(); return true
        }
        let iconPixels = CommandBarSiteColor.faviconPixels(icon)
        check(iconPixels?.count == (icon.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width ?? 0)
              * (icon.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height ?? 0) * 4, "one word per pixel")
        check(iconPixels.map { $0[1] > 200 && $0[3] < 40 } == true, "blue lands in byte 1 and red in byte 3")

        let pill = CommandBarScopePill(), orange = NSColor(srgbRed: 1, green: 0.27, blue: 0, alpha: 1)
        check(pill.focusColor == CommandBarPalette.colourless.scopePill, "pill defaults to the colourless palette, not the accent")
        for (show, title) in [({ pill.showSite(name: "YouTube", unavailable: false) }, "YouTube"),
                              ({ pill.showActions() }, "Actions"), ({ pill.showExtension(name: "Extension Finder") }, "Extension Finder")] {
            show()
            let label = NSTextField(labelWithString: title); label.font = CommandBarTypography.label
            check(pill.titleLabel.stringValue == title, "\(title) pill shows its scope's name")
            check(pill.intrinsicContentSize == NSSize(width: label.intrinsicContentSize.width + 20, height: label.intrinsicContentSize.height + 8),
                  "\(title) pill is its title label plus 10 points each side and 4 above and below")
            check(pill.intrinsicContentSize.height == 24, "\(title) pill is 24 points high")
            pill.frame = NSRect(origin: .zero, size: pill.intrinsicContentSize); pill.layout()
            check(pill.titleLabel.cell!.cellSize.width <= pill.titleLabel.frame.width, "\(title) title fits its pill without truncating")
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pill.frame.width * 2), pixelsHigh: 48,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
            rep.size = pill.frame.size
            pill.cacheDisplay(in: pill.bounds, to: rep)
            let ink = (0..<48).filter { y in (20..<rep.pixelsWide - 20).contains { x in
                (rep.bitmapData! + y * rep.bytesPerRow + x * 4).pointee > 245 } }
            check(abs((ink.first ?? 0) - (47 - (ink.last ?? 0))) <= 2, "\(title) title is centred in its pill, not drawn at the top")
        }
        pill.focusColor = orange
        check(pill.layer?.cornerRadius == 12 && pill.layer?.cornerCurve == .continuous, "pill corners")
        check(pill.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)).map(components) == components(orange), "pill fill")
        check(pill.shadow?.shadowBlurRadius == 8 && pill.shadow?.shadowOffset == NSSize(width: 0, height: -1), "pill glow geometry")
        check(pill.shadow?.shadowColor?.alphaComponent == 0.3, "pill glow is the focus colour at 0.3")
        check(pill.layer?.shadowPath != nil, "glow follows the capsule")

        let hint = CommandBarScopeHint()
        check(CommandBarScopeHint.font == CommandBarTypography.label, "hint uses the pill's label font")
        hint.show(site: "YouTube", spaceTriggerEnabled: false)
        let tabOnly = hint.intrinsicContentSize
        let keycap = CommandBarScopeHint.width("Tab") + 2 * CommandBarScopeHint.keyPadding
        check(tabOnly.width == CommandBarScopeHint.width("Search YouTube") + 8 + keycap, "Tab-only width")
        check(tabOnly.height == CommandBarScopeHint.textHeight + 8, "keycap height pads the label by 4")
        hint.show(site: "YouTube", spaceTriggerEnabled: true)
        let keycaps = hint.subviews.compactMap { $0 as? CommandBarKeycap }
        check(keycaps.map(\.key) == ["Space", "Tab"], "Space and Tab keycaps")
        check(hint.intrinsicContentSize.width == tabOnly.width + 8 + CommandBarScopeHint.width("Space") + 8
              + CommandBarScopeHint.width("or") + 8, "Space, or and Tab share the 8-point spacing")
        hint.frame = NSRect(origin: .zero, size: hint.intrinsicContentSize); hint.layout()
        check(keycaps[0].frame.minX < keycaps[1].frame.minX && keycaps[1].frame.maxX == hint.bounds.maxX, "keys trail the hint")
        let dark = NSAppearance(named: .darkAqua)!, light = NSAppearance(named: .aqua)!
        func alpha(_ color: NSColor, _ appearance: NSAppearance) -> CGFloat {
            var value: CGFloat = 0
            appearance.performAsCurrentDrawingAppearance { value = color.usingColorSpace(.sRGB)?.alphaComponent ?? -1 }
            return value
        }
        check(alpha(CommandBarScopeHint.textColor, dark) == 0.33 && alpha(CommandBarScopeHint.keyColor, dark) == 0.66
              && alpha(CommandBarScopeHint.keyFill, dark) == 0.05, "dark accessory colours")
        check(alpha(CommandBarScopeHint.keyColor, light) == 0.5 && alpha(CommandBarScopeHint.keyFill, light) == 0.05, "light accessory colours")
        hint.isHidden = true
        check(hint.hitTest(NSPoint(x: 1, y: 1)) == nil, "a hidden hint takes no clicks")

        let engines = [(name: "Maps", host: "www.google.com"), (name: "YouTube", host: "www.youtube.com"),
                       (name: "Wikipedia", host: "en.wikipedia.org"), (name: "Legacy", host: "")]
        func offered(_ page: String) -> String? {
            CommandBarSiteColor.scope(forPageHost: URL(string: page)!.host!, in: engines) { $0.host }?.name
        }
        check(offered("https://www.youtube.com/watch?v=1") == "YouTube", "same host")
        check(offered("https://youtube.com/") == "YouTube", "engine under the page's host")
        check(offered("https://wikipedia.org/wiki/A") == "Wikipedia", "language subdomain under its site")
        check(offered("https://m.youtube.com/") == nil, "a sibling subdomain is not under the page's host")
        check(offered("https://en.m.wikipedia.org/") == nil, "a page under the engine's host does not match")
        check(offered("http://www/") == "Maps", "a single label page host matches the first engine carrying it")
        check(CommandBarSiteColor.scope(forPageHost: "", in: engines) { $0.host } == nil, "no host, no engine")

        hint.show(site: "Wikipedia (English)", spaceTriggerEnabled: true)
        hint.isHidden = false
        let capped = min(hint.intrinsicContentSize.width, 350 * 0.45)
        hint.frame = NSRect(x: 0, y: 0, width: capped, height: hint.intrinsicContentSize.height); hint.layout()
        let narrowKeys = hint.subviews.compactMap { $0 as? CommandBarKeycap }
        check(capped < hint.intrinsicContentSize.width, "the sidebar bar is narrower than the full hint")
        check(narrowKeys.allSatisfy { hint.bounds.contains($0.frame) }, "keycaps stay inside the frame")
        check(hint.textFrames.allSatisfy { $0.frame.minX >= 0 && $0.frame.maxX <= hint.bounds.maxX }, "text stays inside the frame")
        check(hint.textFrames.first.map { $0.text == "Search Wikipedia (English)" && $0.frame.width < CommandBarScopeHint.width($0.text) } == true,
              "the hint text tail-truncates")
        let keysOnly = hint.intrinsicContentSize.width - CommandBarScopeHint.width("Search Wikipedia (English)") - CommandBarScopeHint.spacing
        hint.frame.size.width = keysOnly + 4; hint.layout()
        check(hint.textFrames.map(\.text) == ["or"] && narrowKeys.allSatisfy { hint.bounds.contains($0.frame) },
              "with no room left the hint text drops and the keys remain")

        print("CommandBarSiteColorTests: \(assertions) assertions passed")
    }
}
