import AppKit
import SwiftUI

@MainActor @main struct TooltipChecks {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("Tooltip: \(message)") }
    }
    static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.001) -> Bool { abs(a - b) <= tolerance }
    static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        near(a.minX, b.minX) && near(a.minY, b.minY) && near(a.width, b.width) && near(a.height, b.height)
    }
    static func components(_ color: NSColor) -> [CGFloat] {
        let c = color.usingColorSpace(.extendedSRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }
    static func same(_ a: NSColor, _ b: NSColor) -> Bool { zip(components(a), components(b)).allSatisfy { abs($0 - $1) < 0.0005 } }
    static func gray(_ color: NSColor, _ white: CGFloat) -> Bool { same(color, NSColor(colorSpace: .extendedSRGB, components: [white, white, white, 1], count: 4)) }

    static let commandS = KeyboardShortcut(key: "s", flags: .command)

    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        configuration()
        palette()
        keycaps()
        corners()
        placement()
        layout()
        drawing()
        dockItem()
        eligibility()
        presentationState()
        viewConfiguration()
        routing()
        bridge()
        print("Tooltip: \(count) checks passed")
    }

    static func configuration() {
        let standard = TooltipConfiguration("Hide sidebar")
        check(standard.anchor == .bottomTrailing && standard.behavior == .onMouseIdle(delay: 0.45), "bottom-trailing after 0.45 s idle")
        check(standard.shortcut == nil && standard.maxWidth == nil && standard.allowedModifierKeys == [] && standard.palette == nil,
              "no shortcut, width limit, allowed modifiers or palette by default")
        check(TooltipConfiguration.defaultMaxWidth == 296, "296-point maximum width")
        check(TooltipConfiguration.Anchor.allCases.map(\.rawValue) == Array(0...8) && TooltipConfiguration.Anchor.allCases.last == .cursor,
              "preferredAnchor raw values 0–8, the eight edges then the cursor")
        check(TooltipConfiguration("Go back", shortcut: .command("goBack:")) != TooltipConfiguration("Go back"), "the shortcut takes part in equality")
        check(standard.style == .standard && !standard.requiresShortcut && standard.anchorRect == nil,
              "plain text, shown without a binding, anchored to the view's bounds by default")
        check(TooltipConfiguration("Tab", style: .label(subtitle: "Double-click to rename")) != TooltipConfiguration("Tab", style: .label(subtitle: nil))
              && TooltipConfiguration("Tab", anchorRect: .zero) != TooltipConfiguration("Tab")
              && TooltipConfiguration("Tab", requiresShortcut: true) != TooltipConfiguration("Tab"),
              "style, anchor rect and the binding requirement take part in equality")
        check(TooltipConfiguration("Work", style: .dockItem(profileName: "Personal")) != TooltipConfiguration("Work", style: .dockItem(profileName: nil)),
              "the dock item's Profile takes part in equality")

        check(TooltipShadow.standard == [TooltipShadow(radius: 2.5, offset: .zero, opacity: 0.18),
                                         TooltipShadow(radius: 10, offset: CGSize(width: 0, height: 2.5), opacity: 0.15)],
              "the two recovered shadows, in order")
        check(TooltipShadow.windowMargin == 32.5, "window outset: largest offset + 3 × largest radius")
        check(TooltipTiming.presentDuration == 0.05 && TooltipTiming.exitDuration == 0.3 && TooltipTiming.cursorExitDuration == 0.1
              && TooltipTiming.interruptionDuration == 0.1 && TooltipTiming.shortcutDismissalDelay == 0.25,
              "fade-in 0.05 s; fade-out 0.3 s, 0.1 s for cursor exits and interruptions; shortcut 0.25 s")
        check(TooltipTiming.pointerStopDelay == 0.08 && TooltipTiming.hitTestInterval == 0.25
              && TooltipTiming.cursorWarmInterval == 0.6 && TooltipTiming.cursorWarmDelay == 0.01, "idle, backstop and cursor warm timing")
    }

    static func palette() {
        let neutral = TooltipColorPalette.neutral
        check(gray(neutral.title.light, 0) && gray(neutral.title.dark, 1), "neutral title black / white")
        check(gray(neutral.background.light, 1) && gray(neutral.background.dark, 0.17), "neutral background white / 0.17")
        check(gray(neutral.keyForeground.light, 0.9) && gray(neutral.keyForeground.dark, 0.28), "neutral key face 0.9 / 0.28")
        check(gray(neutral.keyBackground.light, 0.66) && gray(neutral.keyBackground.dark, 0.45), "neutral key base 0.66 / 0.45")
        check(gray(neutral.keyTitle.light, 0) && gray(neutral.keyTitle.dark, 1), "neutral glyph black / white")
        check(neutral.background.resolved(dark: true) === neutral.background.dark && neutral.background.resolved(dark: false) === neutral.background.light,
              "Dark Aqua resolves the dark variant, anything else the light one")

        let theme = SpaceTheme(primaryColor: ThemeColor.hsl(hue: 0.575, saturation: 1, lightness: 0.7, colorSpace: .displayP3), colorCount: 2)
        let light = ThemeChromePalette(theme: theme, isDark: false), dark = ThemeChromePalette(theme: theme, isDark: true)
        let themed = TooltipColorPalette(theme: theme)
        check(same(themed.title.light, light.title) && same(themed.title.dark, dark.title), "title follows the semantic palette's light/dark split")
        check(same(themed.background.light, light.background) && same(themed.background.dark, dark.background),
              "background follows the semantic palette's light/dark split")
        for (color, role, darkRole, name) in [(themed.keyForeground, light.hover, dark.hover, "face = hover"),
                                              (themed.keyBackground, light.focus, dark.focus, "base = focus"),
                                              (themed.keyTitle, light.maxContrastColor, dark.maxContrastColor, "glyph = maxContrastColor")] {
            check(same(color.light, role) && same(color.dark, role), "key \(name) from the light palette in both appearances")
            check(!same(color.dark, darkRole), "key \(name) never takes the dark palette's value")
        }
        check(components(themed.keyTitle.light)[0] < 0, "a wide-gamut theme keeps its extended-sRGB components")
        check(TooltipColorPalette(theme: SpaceTheme()) == .neutral, "a colourless theme keeps the neutral palette")
        check(TooltipColorPalette(theme: SpaceTheme(primaryColor: nil, colorCount: 2)) == .neutral, "an invalid theme keeps the neutral palette")
    }

    static func keycaps() {
        let commandS = TooltipKeycap.keycaps(for: commandS)
        check(commandS == [TooltipKeycap(glyph: "⌘", trigger: .modifier(.command)), TooltipKeycap(glyph: "S", trigger: .key("s"))],
              "⌘S: one modifier keycap, then the uppercased key")
        let chord = TooltipKeycap.keycaps(for: KeyboardShortcut(key: "k", flags: [.command, .shift, .option, .control]))
        check(chord.map(\.glyph) == ["⌃", "⌥", "⇧", "⌘", "K"], "modifiers in modifierDisplayInfo order ⌃ ⌥ ⇧ ⌘")
        check(TooltipKeycap.keycaps(for: KeyboardShortcut(key: "K", flags: .command)).map(\.glyph) == ["⇧", "⌘", "K"],
              "an uppercase binding shows its implied Shift")
        let glyphs: [(String, String)] = [(" ", "⎵"), ("\t", "TAB"), ("\u{F704}", "F1"), ("\u{F70D}", "F10"), ("\u{F717}", "F20"),
                                          ("s", "S"), ("1", "1"), ("[", "["), ("é", "É"),
                                          ("\u{F718}", "F21"), ("\r", "↩"), ("\u{7f}", "⌫"), ("\u{1b}", "⎋"), ("\u{f700}", "↑"), ("\u{f728}", "⌦")]
        for (key, glyph) in glyphs { check(TooltipKeycap.glyph(forKey: key) == glyph, "key \(key.debugDescription) shows \(glyph)") }
        let command = commandS[0], key = commandS[1]
        check(command.isPressed(modifiers: [.command, .shift], characters: nil) && !command.isPressed(modifiers: .shift, characters: "s"),
              "a modifier keycap is held while its flag is")
        check(key.isPressed(modifiers: [], characters: "S") && key.isPressed(modifiers: .command, characters: "s")
              && !key.isPressed(modifiers: .command, characters: nil) && !key.isPressed(modifiers: [], characters: "d"),
              "the key keycap is held while its character is, case-insensitively")
    }

    static func corners() {
        let r: CGFloat = 14, a: CGFloat = 3
        let expected: [TooltipConfiguration.Anchor: (CGFloat, CGFloat, CGFloat, CGFloat)] = [
            .top: (r, r, r, r), .bottom: (r, r, r, r), .leading: (r, r, r, r), .trailing: (r, r, r, r),
            .topLeading: (r, r, a, r), .topTrailing: (r, r, r, a), .bottomLeading: (r, a, r, r),
            .bottomTrailing: (a, r, r, r), .cursor: (a, r, r, r)]
        for anchor in TooltipConfiguration.Anchor.allCases {
            let c = TooltipCorners(anchor: anchor), e = expected[anchor]!
            check((c.topLeft, c.topRight, c.bottomRight, c.bottomLeft) == e, "corner radii for \(anchor)")
        }
        let pill = CGRect(x: 0, y: 0, width: 140, height: 28)
        let anchored = TooltipCorners(anchor: .bottomTrailing).path(in: pill), uniform = TooltipCorners(anchor: .top).path(in: pill)
        check(near(anchored.boundingBoxOfPath, pill) && near(uniform.boundingBoxOfPath, pill), "the shape fills its rect")
        check(anchored.contains(CGPoint(x: 1.5, y: 1.5)) && !uniform.contains(CGPoint(x: 1.5, y: 1.5)),
              "the anchor-facing top-left corner is 3 points, the others 14")
        check(!anchored.contains(CGPoint(x: 1.5, y: 26.5)) && !anchored.contains(CGPoint(x: 138.5, y: 1.5)), "the other corners round at 14")
        check(uniform.contains(CGPoint(x: 0.5, y: 14)) && uniform.contains(CGPoint(x: 139.5, y: 14)), "a 28-point pill is a capsule")
        let tall = TooltipCorners(anchor: .top).path(in: CGRect(x: 0, y: 0, width: 20, height: 10))
        check(tall.contains(CGPoint(x: 10, y: 0.5)) && !tall.contains(CGPoint(x: 0.6, y: 0.6)), "radii are limited to half the shorter side")
    }

    static func placement() {
        typealias P = TooltipPlacement
        let a = CGRect(x: 100, y: 50, width: 32, height: 32), size = CGSize(width: 140, height: 28)
        let clamp = CGRect(x: 8, y: 8, width: 984, height: 584), mouse = CGPoint(x: 300, y: 200)
        let origins: [TooltipConfiguration.Anchor: CGPoint] = [
            .top: CGPoint(x: 46, y: 18), .bottom: CGPoint(x: 46, y: 86), .leading: CGPoint(x: -44, y: 52), .trailing: CGPoint(x: 136, y: 52),
            .topLeading: CGPoint(x: -34, y: 28), .topTrailing: CGPoint(x: 126, y: 28), .bottomLeading: CGPoint(x: -34, y: 76),
            .bottomTrailing: CGPoint(x: 126, y: 76), .cursor: CGPoint(x: 312, y: 212)]
        for (anchor, origin) in origins {
            check(P.origin(for: anchor, size: size, anchorRect: a, clamp: clamp, mouse: mouse) == origin, "\(anchor) origin")
        }
        check(P.origin(for: .top, size: size, anchorRect: CGRect(x: 0, y: 50, width: 32, height: 32), clamp: clamp, mouse: mouse).x == 8,
              "top/bottom clamp to the region's leading edge")
        check(P.origin(for: .bottom, size: size, anchorRect: CGRect(x: 960, y: 50, width: 32, height: 32), clamp: clamp, mouse: mouse).x == 852,
              "top/bottom clamp to the region's trailing edge")
        check(P.origin(for: .bottomTrailing, size: size, anchorRect: CGRect(x: 960, y: 50, width: 32, height: 32), clamp: clamp, mouse: mouse).x == 986,
              "diagonal anchors are not clamped")

        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        check(P.clampRegion(windowFrame: CGRect(x: 100, y: 100, width: 800, height: 600), screenFrame: screen)
              == CGRect(x: 8, y: 8, width: 784, height: 584), "clamp region: the window inset by 8")
        check(P.clampRegion(windowFrame: CGRect(x: -100, y: 100, width: 800, height: 600), screenFrame: screen)
              == CGRect(x: 108, y: 8, width: 684, height: 584), "clamp region: only the window's on-screen part")
        check(P.screenRect(CGRect(x: 126, y: 76, width: 140, height: 28), windowFrame: CGRect(x: 100, y: 100, width: 800, height: 600))
              == CGRect(x: 226, y: 596, width: 140, height: 28), "top-left window space to screen space")

        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        check(P.screenIndex(containing: CGRect(x: 1500, y: 500, width: 32, height: 32), screens: screens) == 1, "the screen holding the anchor")
        check(P.screenIndex(containing: CGRect(x: 1430, y: 500, width: 32, height: 32), screens: screens) == 1,
              "an anchor across two screens takes the one holding most of it")
        check(P.screenIndex(containing: CGRect(x: 5000, y: 500, width: 32, height: 32), screens: screens) == nil
              && P.screenIndex(containing: CGRect(x: 100, y: 100, width: 0, height: 0), screens: screens) == nil,
              "no screen for an anchor off every screen or without area")

        let window = CGRect(x: 0, y: 0, width: 1000, height: 600)
        check(P.screenFrame(preferred: .bottomTrailing, size: size, anchorRect: a, mouse: .zero, windowFrame: window, screenFrame: window)
              == CGRect(x: 126, y: 496, width: 140, height: 28), "the preferred anchor when it fits")
        let corner = CGRect(x: 960, y: 560, width: 32, height: 32)
        check(P.screenFrame(preferred: .bottomTrailing, size: size, anchorRect: corner, mouse: .zero, windowFrame: window, screenFrame: window)
              == CGRect(x: 852, y: 44, width: 140, height: 28), "otherwise the fitting candidate nearest the preferred frame (top)")
        check(P.screenFrame(preferred: .bottomTrailing, size: CGSize(width: 2000, height: 28), anchorRect: a, mouse: .zero,
                            windowFrame: window, screenFrame: window) == nil, "no tooltip when nothing fits")
    }

    static func layout() {
        func content(_ label: String, _ shortcut: KeyboardShortcut? = nil, maxWidth: CGFloat = 296) -> TooltipView.Content {
            TooltipView.Content(label: label, keycaps: shortcut.map(TooltipKeycap.keycaps) ?? [], corners: TooltipCorners(anchor: .bottomTrailing),
                                palette: .neutral, maxWidth: maxWidth)
        }
        let hide = TooltipView.layout(for: content("Hide sidebar", commandS), scale: 2)
        check(hide.size.height == 28 && hide.pill == CGRect(origin: .zero, size: hide.size), "a one-line tooltip is 28 points tall")
        check(hide.label.minX == 10 && near(hide.label.midY, 14, 0.25), "label 10 points in, vertically centred to the pixel")
        let natural = TooltipView.labelString("Hide sidebar").size().width
        check(hide.label.width >= natural && hide.label.width - natural < 0.5, "label at its natural width, rounded up to a pixel")
        check(hide.keycaps.count == 2 && hide.keycaps.allSatisfy { $0.size == CGSize(width: 19, height: 19) && $0.minY == 4.5 },
              "19-point keycaps centred in the row")
        check(hide.keycaps[0].minX == hide.label.maxX + 6 && hide.keycaps[1].minX == hide.keycaps[0].maxX + 3
              && hide.size.width == hide.keycaps[1].maxX + 10, "6 points to the keycaps, 3 between them, 10 trailing")
        check(hide.size.width * 2 == (hide.size.width * 2).rounded(), "sizes land on device pixels")
        let single = TooltipView.layout(for: content("Hide sidebar", commandS), scale: 1)
        check(([single.label.minY] + single.keycaps.map(\.minY)).allSatisfy { $0 == $0.rounded() }
              && ([hide.label.minY] + hide.keycaps.map(\.minY)).allSatisfy { $0 * 2 == ($0 * 2).rounded() },
              "label and keycap origins land on device pixels at 1x and 2x")
        check(TooltipView.margin(scale: 2) == 32.5 && TooltipView.margin(scale: 1) == 33 && near(TooltipView.margin(scale: 3), 98.0 / 3),
              "the 32.5-point margin rounds up to a device pixel")

        let reload = TooltipView.layout(for: content("Reload this page"), scale: 2)
        check(reload.keycaps.isEmpty && reload.size.width == reload.label.width + 20, "a label-only tooltip")
        let tab = TooltipView.layout(for: content("Next", KeyboardShortcut(key: "\t", flags: .control)), scale: 2)
        let tabGlyph = TooltipView.glyphString("TAB").size().width
        check(tab.keycaps[0].width == 19 && tab.keycaps[1].width > 19 && tab.keycaps[1].width >= tabGlyph + 6,
              "a wider glyph widens its keycap past 19 (2-point padding, 1-point face inset)")

        let long = "We’re having trouble connecting to GitHub; click here to see your Pull Requests."
        let wrapped = TooltipView.layout(for: content(long), scale: 2)
        check(wrapped.size.width == 296 && wrapped.size.height > 28, "a long label wraps within 296 points")
        check(wrapped.label.width <= 276 && wrapped.pill.width == wrapped.label.width + 20 && wrapped.pill.height == wrapped.size.height,
              "the pill is as wide as the widest line, leading")
        let withKeys = TooltipView.layout(for: content(long, KeyboardShortcut(key: "c", flags: [.command, .shift])), scale: 2)
        let keys = withKeys.keycaps.last!.maxX - withKeys.keycaps.first!.minX
        check(withKeys.label.width <= 296 - 20 - 6 - keys && withKeys.keycaps.allSatisfy { near($0.midY, withKeys.size.height / 2) },
              "the label wraps beside the keycaps, which stay centred")
        check(TooltipView.layout(for: content(long, maxWidth: 150), scale: 2).size.width == 150, "a configured maximum width")

        func label(_ title: String, _ subtitle: String?) -> TooltipView.Layout {
            var value = content(title); value.style = .label(subtitle: subtitle)
            return TooltipView.layout(for: value, scale: 2)
        }
        check(TooltipView.Label.lineHeight(TooltipView.labelFont) == 15 && TooltipView.Label.lineHeight(TooltipView.Label.subtitleFont) == 14,
              "SwiftUI's whole-point line heights for the 12-point label and the 11-point subtitle")
        let titled = label("Sign in to GitHub", "Double-click to rename")
        check(titled.label.height == 15 && titled.subtitle?.height == 14 && titled.subtitle?.minY == titled.label.maxY
              && titled.subtitle?.minX == 10 && titled.label.minX == 10, "the subtitle sits directly below the label, leading")
        check(titled.size.height == 29 && titled.pill.height == 29, "two lines make a 29-point row, above the 28-point minimum")
        let hint = TooltipView.lineString("Double-click to rename", font: TooltipView.Label.subtitleFont).size().width
        check(titled.size.width == max(titled.label.width, titled.subtitle!.width) + 20 && titled.subtitle!.width >= hint,
              "the row is as wide as the wider text")
        let renamed = label("Sign in to GitHub", nil)
        check(renamed.subtitle == nil && renamed.size.height == 28 && renamed.label.height == 15 && near(renamed.label.midY, 14, 0.25),
              "without a subtitle the label is centred in the 28-point row")
        let capped = label(String(repeating: long + " ", count: 4), "Double-click to rename")
        check(capped.label.height == 60 && capped.subtitle?.minY == 60 && capped.size.height == 74 && capped.size.width == 296,
              "the label stops at four lines and the subtitle follows it")
        check(TooltipView.layout(for: content("Sign in to GitHub"), scale: 2).subtitle == nil, "standard content has no subtitle")
    }

    static func render(_ view: NSView) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!.retagging(with: .sRGB)!
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }
    static func pixel(_ rep: NSBitmapImageRep, _ point: CGPoint) -> [Int] {
        var raw = [Int](repeating: 0, count: 4)
        rep.getPixel(&raw, atX: Int(point.x * 2), y: Int(point.y * 2))
        return raw
    }

    static func drawing() {
        let content = TooltipView.Content(label: "Hide sidebar", keycaps: TooltipKeycap.keycaps(for: commandS),
                                          corners: TooltipCorners(anchor: .bottomTrailing), palette: .neutral, maxWidth: 296)
        func tooltip(dark: Bool) -> TooltipView {
            let view = TooltipView(content: content)
            let size = view.contentLayout.size, margin = TooltipShadow.windowMargin
            view.frame = NSRect(x: 0, y: 0, width: size.width + 2 * margin, height: size.height + 2 * margin)
            view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            return view
        }
        let m = TooltipShadow.windowMargin
        let light = tooltip(dark: false), layout = light.contentLayout
        let key = layout.keycaps[0].offsetBy(dx: m, dy: m)
        let lightRep = render(light)
        check(pixel(lightRep, CGPoint(x: m + 4, y: m + 14)) == [255, 255, 255, 255], "the light pill fills with the background colour")
        check(pixel(lightRep, CGPoint(x: key.minX + 3, y: key.minY + 2.5)).prefix(3).allSatisfy { (229...230).contains($0) }, "the key face is keyForeground")
        let lip = pixel(lightRep, CGPoint(x: key.midX, y: key.maxY - 2))
        check(lip.prefix(3).allSatisfy { (140...165).contains($0) }, "the 2.5-point lip shows the shaded keyBackground")
        check(pixel(lightRep, CGPoint(x: m + 70, y: m + 0.25))[0] == 255, "no border in light appearance")
        let below = pixel(lightRep, CGPoint(x: m + 70, y: m + 30))[3], above = pixel(lightRep, CGPoint(x: m + 70, y: m - 2))[3]
        check(below > above && above > 0, "two shadows, the wider one offset downward")
        check(pixel(lightRep, CGPoint(x: 1, y: 1))[3] == 0, "the margin beyond the shadows stays clear")

        let dark = render(tooltip(dark: true))
        check(pixel(dark, CGPoint(x: m + 4, y: m + 14)).prefix(3).allSatisfy { $0 == 43 }, "the dark pill is 0.17 grey")
        check(pixel(dark, CGPoint(x: m + 70, y: m + 0.25))[0] > 55, "a 10% white border in dark appearance")

        let held = tooltip(dark: false)
        held.setPressed(modifiers: .command, characters: nil)
        let heldRep = render(held)
        check(pixel(heldRep, CGPoint(x: key.midX, y: key.maxY - 2)).prefix(3).allSatisfy { (229...230).contains($0) },
              "a held key's face drops to its 1-point inset")
        let other = layout.keycaps[1].offsetBy(dx: m, dy: m)
        check(pixel(heldRep, CGPoint(x: other.midX, y: other.maxY - 2)).prefix(3).allSatisfy { (140...165).contains($0) },
              "keys that are not held keep the lip")

        var labelContent = TooltipView.Content(label: "Sign in to GitHub", keycaps: [], corners: TooltipCorners(anchor: .cursor),
                                               palette: .neutral, maxWidth: 296, style: .label(subtitle: "Double-click to rename"))
        labelContent.palette.title = .init(.black)
        let labelView = TooltipView(content: labelContent)
        let labelSize = labelView.contentLayout.size
        labelView.frame = NSRect(x: 0, y: 0, width: labelSize.width + 2 * m, height: labelSize.height + 2 * m)
        labelView.appearance = NSAppearance(named: .aqua)
        let labelRep = render(labelView)
        check(pixel(labelRep, CGPoint(x: m + 40, y: m - 5)) == [255, 255, 255, 255]
              && pixel(labelRep, CGPoint(x: m + 40, y: m + labelSize.height + 5)) == [255, 255, 255, 255],
              "a two-line label's background overhangs 7 points above and below")
        func darkest(_ rect: CGRect) -> Int {
            var value = 255
            for y in stride(from: rect.minY, to: rect.maxY, by: 0.5) {
                for x in stride(from: rect.minX, to: rect.maxX, by: 0.5) { value = min(value, pixel(labelRep, CGPoint(x: x, y: y))[0]) }
            }
            return value
        }
        let titleInk = darkest(labelView.contentLayout.label.offsetBy(dx: m, dy: m))
        let subtitleInk = darkest(labelView.contentLayout.subtitle!.offsetBy(dx: m, dy: m))
        check(titleInk < 40 && (60...130).contains(subtitleInk), "black title; subtitle at 0.66 opacity over white")
    }

    static func dockItem() {
        func content(_ label: String, profile: String?, keycaps: [TooltipKeycap] = TooltipKeycap.keycaps(for: KeyboardShortcut(key: "1", flags: .control)))
            -> TooltipView.Content {
            TooltipView.Content(label: label, keycaps: keycaps, corners: TooltipCorners(anchor: .top), palette: .neutral, maxWidth: 296,
                                style: .dockItem(profileName: profile))
        }
        func onPixel(_ value: CGFloat) -> CGFloat { ceil(value * 2 - 0.001) / 2 }
        let layout = TooltipView.layout(for: content("Work", profile: "Personal"), scale: 2)
        let name = onPixel(TooltipView.profileString("Personal").size().width)
        check(TooltipView.Label.lineHeight(TooltipView.Profile.font) == 14, "the 11-point medium name sits on a 14-point line")
        if let profile = layout.profile {
            check(profile.minX == 10 + layout.label.width + 6 && profile.width == 5 + 20 + 2 + name + 6 && profile.height == 22,
                  "the capsule follows the title by 6 points and is 5 / 20 / 2 / name / 6 wide and 22 tall")
            check(profile.minY == 3 && layout.size.height == 28, "the capsule is centred in the 28-point row")
            check(layout.keycaps.first?.minX == profile.maxX + 6, "the Space's keycaps follow the capsule")
            check(layout.size.width == profile.maxX + 6 + (layout.keycaps.last!.maxX - layout.keycaps.first!.minX) + 10,
                  "the pill holds title, capsule and keycaps with 10 points either side")
        } else {
            check(false, "a Profile name lays out its capsule")
        }
        let bare = TooltipView.layout(for: content("Work", profile: nil), scale: 2)
        let standard = TooltipView.layout(for: TooltipView.Content(label: "Work", keycaps: content("Work", profile: nil).keycaps,
                                                                   corners: TooltipCorners(anchor: .top), palette: .neutral, maxWidth: 296), scale: 2)
        check(bare.profile == nil && bare == standard, "without a Profile the dock item is the standard pill")
        let long = TooltipView.layout(for: content(String(repeating: "Research ", count: 8), profile: "Personal", keycaps: []), scale: 2)
        check(long.size.width == 296 && long.profile.map { $0.maxX <= 296 - 10 } == true && long.label.height > 28,
              "a long title wraps beside the capsule within 296 points")
        let longName = "Personal Research and Writing Account"
        let capped = TooltipView.layout(for: content("Work", profile: longName), scale: 2)
        let room = 296 - 20 - (6 + capped.keycaps.last!.maxX - capped.keycaps.first!.minX)
        check(capped.pill.width <= 296 && capped.size.width <= 296 && capped.label.width > 0 && capped.label.width == layout.label.width
              && capped.profile?.width == floor((room - 6) / 2 * 2) / 2,
              "a long Profile name caps the capsule at half the row's room, within 296 points, and the title keeps its width")
        let crowded = TooltipView.layout(for: content(String(repeating: "Research ", count: 8), profile: longName), scale: 2)
        check(crowded.pill.width <= 296 && crowded.size.width == 296 && crowded.label.width > 0,
              "a long title beside a long Profile wraps within 296 points")

        func draw(_ name: String) -> (rep: NSBitmapImageRep, capsule: CGRect) {
            var drawn = content("Work", profile: name, keycaps: [])
            drawn.palette.keyForeground = .init(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            drawn.palette.keyTitle = .init(NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
            let view = TooltipView(content: drawn)
            let m = TooltipView.margin(scale: 2), size = view.contentLayout.size
            view.frame = NSRect(x: 0, y: 0, width: size.width + 2 * m, height: size.height + 2 * m)
            view.appearance = NSAppearance(named: .aqua)
            return (render(view), view.contentLayout.profile!.offsetBy(dx: m, dy: m))
        }
        func bluest(_ rep: NSBitmapImageRep, _ rect: CGRect) -> Int {
            var value = 0
            for y in stride(from: rect.minY, to: rect.maxY, by: 0.5) {
                for x in stride(from: rect.minX, to: rect.maxX, by: 0.5) {
                    let p = pixel(rep, CGPoint(x: x, y: y)); value = max(value, p[2] - p[0])
                }
            }
            return value
        }
        let (rep, capsule) = draw("Personal")
        check(pixel(rep, CGPoint(x: capsule.midX, y: capsule.minY + 1.5)) == [255, 0, 0, 255], "the capsule fills with the key face colour")
        check(pixel(rep, CGPoint(x: capsule.minX + 0.5, y: capsule.minY + 0.5))[1] == 255, "its corners are round, a capsule")
        let icon = CGRect(x: capsule.minX + 5, y: capsule.minY + 4, width: 20, height: 14)
        let text = CGRect(x: capsule.minX + 27, y: capsule.minY + 4, width: capsule.width - 33, height: 14)
        check(bluest(rep, icon) > 200 && bluest(rep, text) > 200, "the icon and name draw in the key glyph colour")
        let truncated = draw(longName)
        let tail = CGRect(x: truncated.capsule.maxX - 5.5, y: truncated.capsule.minY + 4, width: 3, height: 14)
        check(bluest(truncated.rep, CGRect(x: truncated.capsule.minX + 27, y: truncated.capsule.minY + 4, width: 20, height: 14)) > 200
              && bluest(truncated.rep, tail) < 40, "a long name truncates inside the capsule's 6-point trailing padding")
    }

    static func eligibility() {
        func permits(buttons: Int = 0, flags: NSEvent.ModifierFlags = [], allowed: NSEvent.ModifierFlags = [], key: Bool = true) -> Bool {
            TooltipEligibility.permits(pressedMouseButtons: buttons, modifierFlags: flags, allowed: allowed, keyInParentChain: { key })
        }
        check(permits(), "eligible with no buttons or modifiers in a key chain")
        check(!permits(buttons: 1), "never while a mouse button is held")
        check(!permits(flags: .command) && permits(flags: .command, allowed: .command), "a held modifier blocks unless allowed")
        check(!permits(flags: [.command, .shift], allowed: .command), "every held modifier must be allowed")
        check(!permits(flags: .capsLock), "the unmasked check: Caps Lock blocks")
        check(!permits(key: false), "a key window up the parent chain")
    }

    static func presentationState() {
        typealias State = TooltipPresentationState<String>
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        var state = State()
        check(state.phase == .tracking && !state.isShowing && state.schedulesWhenPointerStops, "starts tracking with no window")
        check(state.schedule("toggle", anchor: .bottomTrailing, behavior: .onMouseIdle(delay: 0.45), now: t0) == .presentAfter(0.45),
              "an idle tooltip waits its delay")
        check(state.phase == .scheduled("toggle") && !state.schedulesWhenPointerStops, "scheduled")
        check(state.pointerMoved() && state.phase == .tracking && !state.pointerMoved(), "movement cancels the pending presentation")
        _ = state.schedule("toggle", anchor: .bottomTrailing, behavior: .onMouseIdle(delay: 0.45), now: t0)
        state.didPresent("toggle")
        check(state.phase == .presented("toggle") && state.isShowing && !state.pointerMoved(), "presented; movement keeps it")

        check(state.schedule("back", anchor: .bottomTrailing, behavior: .onMouseIdle(delay: 0.45), now: t0) == .present,
              "warm handoff: another view's tooltip shows at once")
        state.didPresent("back")
        check(state.schedule("row", anchor: .cursor, behavior: .onMouseIdle(delay: 1.5), now: t0) == nil && state.phase == .presented("back"),
              "a cursor tooltip is not scheduled while one is up")

        let t1 = t0.addingTimeInterval(1)
        check(state.hide(State.Fade(duration: 0.3), now: t1) == State.Fade(duration: 0.3) && state.phase == .tracking, "hiding fades the window")
        check(state.isShowing && state.lastDismissal == t1, "still showing while it fades")
        check(state.schedule("forward", anchor: .bottomTrailing, behavior: .onMouseIdle(delay: 0.45), now: t1) == .present,
              "warm handoff during the fade")
        state.didPresent("forward")
        check(!state.fadeDidFinish() && state.isShowing, "the replaced fade leaves the window up")
        _ = state.hide(.init(duration: 0.3), now: t1)
        check(state.fadeDidFinish() && !state.isShowing, "an unreplaced fade closes the window")
        check(state.schedule("toggle", anchor: .bottomTrailing, behavior: .onMouseIdle(delay: 0.45), now: t1) == .presentAfter(0.45),
              "after the fade the delay applies again")

        var idle = State()
        check(idle.hide(.init(duration: 0.1), now: t1) == nil && idle.lastDismissal == .distantPast, "nothing to hide leaves no dismissal")
        _ = idle.schedule("toggle", anchor: .bottomTrailing, behavior: .onMouseIdle(delay: 0.45), now: t1)
        check(idle.hide(.init(duration: 0.1), now: t1) == nil && idle.phase == .tracking && idle.lastDismissal == t1,
              "hiding a pending tooltip cancels it")
        _ = idle.schedule("toggle", anchor: .bottomTrailing, behavior: .onMouseIdle(delay: 0.45), now: t1)
        _ = idle.hide(.init(duration: 0.1), scrolled: true, now: t1)
        check(idle.lastDismissal == .distantPast, "a scroll leaves no warm state")

        var cursor = State()
        _ = cursor.schedule("row", anchor: .cursor, behavior: .onMouseIdle(delay: 1.5), now: t0)
        _ = cursor.hide(.init(duration: 0.1), now: t0)
        check(cursor.schedule("row", anchor: .cursor, behavior: .onMouseIdle(delay: 1.5), now: t0.addingTimeInterval(0.5)) == .presentAfter(0.01),
              "a cursor tooltip within 0.6 s of a dismissal waits 0.01 s")
        check(cursor.schedule("row", anchor: .cursor, behavior: .onMouseIdle(delay: 1.5), now: t0.addingTimeInterval(0.7)) == .presentAfter(1.5),
              "later it waits its own delay")
        var immediate = State()
        check(immediate.schedule("info", anchor: .top, behavior: .immediate, now: t0) == .present && immediate.phase == .tracking,
              "an immediate tooltip presents without scheduling")

        var exit = State()
        check(exit.exit(targetUnderPointer: false, enclosing: nil, enclosingAnchor: nil, anchor: .bottomTrailing) == .keep, "no target, nothing to do")
        exit.didPresent("inner")
        check(exit.exit(targetUnderPointer: true, enclosing: nil, enclosingAnchor: nil, anchor: .bottomTrailing) == .keep, "still over its view")
        check(exit.exit(targetUnderPointer: false, enclosing: "outer", enclosingAnchor: .bottomTrailing, anchor: .bottomTrailing) == .handOff("outer"),
              "hands off to an enclosing view-anchored view")
        check(exit.exit(targetUnderPointer: false, enclosing: nil, enclosingAnchor: nil, anchor: .bottomTrailing) == .hide(.init(duration: 0.3)), "a view tooltip fades in 0.3 s")
        check(exit.exit(targetUnderPointer: false, enclosing: nil, enclosingAnchor: nil, anchor: .cursor) == .hide(.init(duration: 0.1)), "a cursor tooltip in 0.1 s")

        var row = State()
        _ = row.schedule("close", anchor: .bottomTrailing, behavior: .onMouseIdle(delay: 0.45), now: t0)
        row.didPresent("close")
        check(row.exit(targetUnderPointer: false, enclosing: "row", enclosingAnchor: .cursor, anchor: .bottomTrailing) == .hide(.init(duration: 0.3)),
              "a cursor-anchored enclosing view is not handed off to while a tooltip shows: the pill hides")
        check(row.hide(.init(duration: 0.3), now: t0) == .init(duration: 0.3) && row.isShowing && row.schedulesWhenPointerStops,
              "the pill fades and the pointer's next stop may schedule again")
        check(row.schedule("row", anchor: .cursor, behavior: .onMouseIdle(delay: 1.5), now: t0.addingTimeInterval(0.1)) == nil,
              "during the fade the row is declined schedule declines it")
        check(row.fadeDidFinish(), "the fade closes the pill's window")
        check(row.schedule("row", anchor: .cursor, behavior: .onMouseIdle(delay: 1.5), now: t0.addingTimeInterval(0.35)) == .presentAfter(0.01)
              && row.target == "row", "after it, the next stop schedules the row with the cursor warm delay")
        var pendingChild = State()
        _ = pendingChild.schedule("close", anchor: .bottomTrailing, behavior: .onMouseIdle(delay: 0.45), now: t0)
        check(pendingChild.exit(targetUnderPointer: false, enclosing: "row", enclosingAnchor: .cursor, anchor: .bottomTrailing) == .handOff("row"),
              "with nothing shown, a pending child hands off to the cursor-anchored row")

        var keys = State()
        keys.didPresent("toggle")
        check(keys.keyDown(escape: false, modifiers: .command, characters: "d", shortcut: commandS, now: t0) == nil, "other keys never dismiss")
        check(keys.keyDown(escape: false, modifiers: [.command, .shift], characters: "s", shortcut: commandS, now: t0) == nil,
              "a different chord does not dismiss")
        check(keys.keyDown(escape: false, modifiers: [.command, .capsLock], characters: "S", shortcut: commandS, now: t0)
              == State.Fade(duration: 0.3, delay: 0.25), "performing the shown shortcut fades after 0.25 s")
        keys.didPresent("toggle")
        check(keys.keyDown(escape: true, modifiers: [], characters: nil, shortcut: commandS, now: t0) == State.Fade(duration: 0.1), "Escape fades in 0.1 s")
        var pending = State()
        _ = pending.schedule("toggle", anchor: .bottomTrailing, behavior: .onMouseIdle(delay: 0.45), now: t0)
        check(pending.keyDown(escape: false, modifiers: .command, characters: "s", shortcut: commandS, now: t0) == nil && pending.isScheduled,
              "the shortcut only dismisses a shown tooltip")
        check(pending.keyDown(escape: true, modifiers: [], characters: nil, shortcut: nil, now: t0) == nil && pending.phase == .tracking,
              "Escape cancels a pending one")

        var failed = State()
        failed.didPresent("toggle")
        failed.didFailToPresent()
        check(failed.phase == .tracking && !failed.isShowing, "a failed presentation closes the window")
        _ = failed.schedule("toggle", anchor: .bottomTrailing, behavior: .onMouseIdle(delay: 0.45), now: t0)
        failed.cancelSchedule()
        check(failed.phase == .tracking, "a pending presentation can be cancelled")
    }

    final class KeyStandInWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var mouseLocationOutsideOfEventStream: NSPoint { NSPoint(x: -10_000, y: -10_000) }
    }
    final class PointerStandInWindow: NSWindow {
        var pointer = NSPoint.zero
        override var isKeyWindow: Bool { true }
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    }
    final class PartView: NSView {
        var part = NSRect.zero
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let superview else { return nil }
            return part.contains(convert(point, from: superview)) ? self : nil
        }
    }

    static func routing() {
        InputOverrides.install()
        InputOverrides.pressedMouseButtons = 0; InputOverrides.modifierFlags = []
        defer { InputOverrides.pressedMouseButtons = nil; InputOverrides.modifierFlags = nil }
        func scene() -> (window: NSWindow, owner: NSResponder, anchor: NSView) {
            let window = KeyStandInWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 200), styleMask: .borderless,
                                          backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let anchor = NSView(frame: NSRect(x: 20, y: 120, width: 40, height: 40))
            window.contentView!.addSubview(anchor)
            anchor.parcTooltip = TooltipConfiguration("Hide sidebar", shortcut: .fixed(commandS))
            return (window, anchor.trackingAreas.compactMap { $0.owner as? NSResponder }.first!, anchor)
        }
        func event(_ type: NSEvent.EventType, in window: NSWindow) -> NSEvent {
            let point = NSPoint(x: 40, y: 140), time = ProcessInfo.processInfo.systemUptime
            if type == .mouseMoved {
                return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time, windowNumber: window.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            }
            return NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [], timestamp: time, windowNumber: window.windowNumber,
                                          context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
        func tooltip(of window: NSWindow) -> NSWindow? { window.childWindows?.first }

        let shown = scene()
        shown.owner.mouseEntered(with: event(.mouseEntered, in: shown.window))
        wait(0.3)
        check(tooltip(of: shown.window) == nil, "nothing before the idle delay")
        wait(0.25)
        let child = tooltip(of: shown.window)
        check(child != nil, "entering shows the tooltip after 0.45 s")
        if let child {
            check(!child.canBecomeKey && !child.canBecomeMain && child.ignoresMouseEvents, "the tooltip window never takes key, main or the mouse")
            check(!child.isAccessibilityElement(), "the tooltip window is hidden from accessibility")
            check(!child.isVisible && !shown.window.isVisible, "nothing was put on screen")
        }
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: shown.window)
        wait(0.05)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: shown.window)
        wait(0.1)
        check(tooltip(of: shown.window) != nil, "a second dismissal during a fade keeps fading rather than closing at once")
        wait(0.6)
        check(tooltip(of: shown.window) == nil, "the latest fade closes the window")
        shown.window.close()

        let moved = scene()
        moved.owner.mouseEntered(with: event(.mouseEntered, in: moved.window))
        wait(0.2)
        moved.owner.mouseMoved(with: event(.mouseMoved, in: moved.window))
        wait(0.4)
        check(tooltip(of: moved.window) == nil, "a real mouse-moved reaches the controller and cancels the pending tooltip")
        moved.window.close()

        let hidden = scene()
        hidden.owner.mouseEntered(with: event(.mouseEntered, in: hidden.window))
        wait(0.2)
        hidden.anchor.superview?.isHidden = true
        wait(0.4)
        check(tooltip(of: hidden.window) == nil, "a view hidden during the idle delay never shows its tooltip")
        hidden.window.close()

        let held = scene()
        InputOverrides.modifierFlags = .shift
        held.owner.mouseEntered(with: event(.mouseEntered, in: held.window))
        wait(0.55)
        check(tooltip(of: held.window) == nil, "a held modifier declines the tooltip")
        InputOverrides.modifierFlags = []
        held.window.close()

        let unbound = scene()
        TooltipController.commandShortcut = { _ in nil }
        unbound.anchor.parcTooltip = TooltipConfiguration("Reset Tab", shortcut: .command("resetTab:"), requiresShortcut: true)
        unbound.owner.mouseEntered(with: event(.mouseEntered, in: unbound.window))
        wait(0.55)
        check(tooltip(of: unbound.window) == nil, "no binding, no Reset Tab tooltip")
        TooltipController.commandShortcut = { $0 == "resetTab:" ? KeyboardShortcut(key: "r", flags: [.command, .option]) : nil }
        unbound.owner.mouseEntered(with: event(.mouseEntered, in: unbound.window))
        wait(0.55)
        check(tooltip(of: unbound.window) != nil, "a binding shows it")
        TooltipController.commandShortcut = nil
        unbound.window.close()

        let window = KeyStandInWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 200), styleMask: .borderless,
                                      backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let canvas = PartView(frame: NSRect(x: 20, y: 40, width: 200, height: 140))
        canvas.part = NSRect(x: 100, y: 20, width: 40, height: 40)
        window.contentView!.addSubview(canvas)
        canvas.parcTooltip = TooltipConfiguration("View Library", anchorRect: canvas.part)
        let owner = canvas.trackingAreas.compactMap { $0.owner as? NSResponder }.first!
        func enter(at point: NSPoint) -> NSEvent {
            NSEvent.enterExitEvent(with: .mouseEntered, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        owner.mouseEntered(with: enter(at: NSPoint(x: 30, y: 50)))
        wait(0.55)
        check(tooltip(of: window) == nil, "entering the view outside its part schedules nothing")
        owner.mouseEntered(with: enter(at: NSPoint(x: 140, y: 80)))
        wait(0.55)
        let partTip = tooltip(of: window)
        check(partTip != nil, "entering over the part shows its tooltip")
        if let partTip {
            let margin = TooltipView.margin(scale: partTip.screen?.backingScaleFactor ?? window.backingScaleFactor)
            check(near(partTip.frame.minX + margin, 200 + 160 - 6, 1) && near(partTip.frame.maxY - margin, 400 - (140 - 6), 1),
                  "the tooltip sits at the part's bottom-trailing corner")
        }
        window.close()

        let stopping = PointerStandInWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 200), styleMask: .borderless,
                                            backing: .buffered, defer: false)
        stopping.isReleasedWhenClosed = false
        let drawn = PartView(frame: canvas.frame)
        drawn.part = canvas.part
        stopping.contentView!.addSubview(drawn)
        drawn.parcTooltip = TooltipConfiguration("View Library", anchorRect: drawn.part)
        let drawnOwner = drawn.trackingAreas.compactMap { $0.owner as? NSResponder }.first!
        stopping.pointer = NSPoint(x: 30, y: 50)
        drawnOwner.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: stopping.pointer, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: stopping.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil)!)
        wait(0.55)
        check(tooltip(of: stopping) == nil, "entering outside the part shows nothing")
        func move(to point: NSPoint) {
            stopping.pointer = point
            drawnOwner.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: stopping.windowNumber, context: nil,
                eventNumber: 0, clickCount: 0, pressure: 0)!)
        }
        move(to: NSPoint(x: 140, y: 80))
        wait(0.3)
        check(tooltip(of: stopping) == nil, "the stop's idle delay is still running")
        wait(0.6)
        check(tooltip(of: stopping) != nil, "the pointer stopping on the part shows the tooltip of the view it entered elsewhere")
        move(to: NSPoint(x: 60, y: 120))
        wait(0.9)
        check(tooltip(of: stopping) == nil, "past the backstop, a gap inside the view hides its part's tooltip")
        move(to: NSPoint(x: 130, y: 70))
        wait(0.9)
        check(tooltip(of: stopping) != nil, "stopping on the part again shows its tooltip without a new entry")
        stopping.close()

        let changing = PointerStandInWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 200), styleMask: .borderless,
                                            backing: .buffered, defer: false)
        changing.isReleasedWhenClosed = false
        let control = NSView(frame: NSRect(x: 20, y: 120, width: 40, height: 40))
        changing.contentView!.addSubview(control)
        control.parcTooltip = TooltipConfiguration("Mute this tab")
        let controlOwner = control.trackingAreas.compactMap { $0.owner as? NSResponder }.first!
        changing.pointer = NSPoint(x: 40, y: 140)
        controlOwner.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: changing.pointer, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: changing.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil)!)
        wait(0.55)
        func shownLabel() -> String? { (tooltip(of: changing)?.contentView as? TooltipView)?.content.label }
        check(shownLabel() == "Mute this tab", "the control's tooltip shows")
        control.parcTooltip = TooltipConfiguration("Unmute this tab")
        check(shownLabel() == "Unmute this tab", "a change with the pointer over the view replaces the shown content")
        changing.pointer = NSPoint(x: 250, y: 20)
        control.parcTooltip = TooltipConfiguration("Mute this tab")
        check(shownLabel() == "Unmute this tab", "a change after the pointer left does not show the new content")
        wait(0.5)
        check(tooltip(of: changing) == nil, "it fades the tooltip and closes its window")
        changing.close()
    }

    static func bridge() {
        InputOverrides.install()
        InputOverrides.pressedMouseButtons = 0; InputOverrides.modifierFlags = []
        defer { InputOverrides.pressedMouseButtons = nil; InputOverrides.modifierFlags = nil }
        func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
        func anchors(_ view: NSView) -> [TooltipAnchorView] { ((view as? TooltipAnchorView).map { [$0] } ?? []) + view.subviews.flatMap(anchors) }

        let window = PointerStandInWindow(contentRect: NSRect(x: 200, y: 200, width: 120, height: 80), styleMask: .borderless,
                                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var clicks = 0
        let host = NSHostingView(rootView: SwiftUI.Button("Copy") { clicks += 1 }
            .frame(width: 48, height: 32)
            .parcTooltip(TooltipConfiguration("Copy URL", shortcut: .fixed(KeyboardShortcut(key: "c", flags: [.command, .shift])))))
        host.frame = window.contentView!.bounds
        window.contentView!.addSubview(host)
        host.layoutSubtreeIfNeeded()
        let found = anchors(host)
        check(found.count == 1 && found.first?.parcTooltip?.label == "Copy URL", "the modifier overlays one anchor carrying the configuration")
        guard let anchor = found.first else { window.close(); return }
        let centre = anchor.convert(NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: nil)
        window.pointer = centre
        check(anchor.bounds.size == CGSize(width: 48, height: 32), "the anchor covers the control")
        let hit = window.contentView!.hitTest(centre)
        check(hit != nil && !(hit is TooltipAnchorView) && hit?.isDescendant(of: anchor) == false,
              "ordinary hit tests pass through the anchor to the SwiftUI control")
        check(TooltipController.controller(for: window).hitTestingView == nil, "no controller hit test is running")

        let owner = anchor.trackingAreas.compactMap { $0.owner as? NSResponder }.first!
        owner.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: centre, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil)!)
        check(TooltipController.controller(for: window).hitTestingView == nil, "the controller clears its hit-testing view after its hit test")
        wait(0.55)
        let tip = window.childWindows?.first
        check((tip?.contentView as? TooltipView)?.content.label == "Copy URL", "the controller's own hit test reaches the anchor and shows its tooltip")
        check(tip?.isVisible == false && !window.isVisible && clicks == 0, "nothing was put on screen or clicked")
        wait(0.8)
        check(window.childWindows?.first != nil, "the 0.25 s backstop's own hit test reaches the anchor too, so the tooltip stays")
        window.pointer = NSPoint(x: -100, y: -100)
        wait(0.9)
        check(window.childWindows?.first == nil, "once the pointer leaves, the backstop hides it")

        host.rootView = SwiftUI.Button("Copy") { clicks += 1 }.frame(width: 48, height: 32).parcTooltip(nil)
        host.layoutSubtreeIfNeeded()
        check(anchors(host).isEmpty, "a nil configuration removes the anchor")
        window.close()
    }

    static func viewConfiguration() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        view.toolTip = "Hide sidebar ⌘S"
        let configuration = TooltipConfiguration("Hide sidebar", shortcut: .command("toggleSidebar:"))
        view.parcTooltip = configuration
        check(view.parcTooltip == configuration && view.toolTip == nil, "a configuration replaces the AppKit help tag")
        check(view.trackingAreas.count == 1, "and tracks the pointer with one area")
        let area = view.trackingAreas[0]
        check(area.options.isSuperset(of: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]) && area.userInfo == nil,
              "entered, exited and moved, in every window state, over the visible rect")
        check(area.owner is NSResponder && area.owner !== view, "owned by the view's tooltip tracker")
        view.parcTooltip = configuration
        view.parcTooltip = TooltipConfiguration("Lock sidebar", shortcut: .command("toggleSidebar:"))
        check(view.trackingAreas.count == 1 && view.trackingAreas[0] === area && view.parcTooltip?.label == "Lock sidebar",
              "updates reuse the one tracking area")
        view.parcTooltip = nil
        check(view.parcTooltip == nil && view.trackingAreas.isEmpty, "nil removes the tooltip and its tracking area")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered, defer: true)
        let controller = TooltipController.controller(for: window)
        check(TooltipController.controller(for: window) === controller && controller.palette == nil, "one controller per window, neutral until told")
        check(!window.isVisible && !window.isKeyWindow, "the check window is never shown")

        let button = NSButton(title: "", target: nil, action: nil)
        button.toolTip = "Go back ⌘["
        LiveShortcutToolTip.set(button, "Go back", commandID: "goBack:")
        check(button.parcTooltip == TooltipConfiguration("Go back", shortcut: .command("goBack:")) && button.toolTip == nil,
              "a control gets the pill with its command's live keycaps, and no help tag")
        check(button.accessibilityHelp() == "Go back" && button.cell?.accessibilityHelp() == "Go back",
              "without the app's binder the help is the title, on the button and the cell AppKit exposes")
        LiveShortcutToolTip.set(button, "Remove Personal Filter", anchor: .top, behavior: .onMouseIdle(delay: 0.6))
        check(button.parcTooltip == TooltipConfiguration("Remove Personal Filter", anchor: .top, behavior: .onMouseIdle(delay: 0.6)),
              "a site's own anchor and delay; no command, no keycaps")
        LiveShortcutToolTip.set(button, "Reset Tab", commandID: "resetTab:", requiresBinding: true)
        check(button.parcTooltip?.requiresShortcut == true && button.accessibilityHelp() == nil,
              "a binding-only tooltip without a binder has no help")
        var bound: [(String, String?, Bool)] = []
        LiveShortcutToolTip.binder = { view, title, id, requires in
            bound.append((title, id, requires)); view.setAccessibilityHelp(title + " ⌘[")
        }
        LiveShortcutToolTip.set(button, "Go back", commandID: "goBack:")
        check(bound.count == 1 && bound[0] == ("Go back", "goBack:", false) && button.accessibilityHelp() == "Go back ⌘[",
              "the app's binder keeps the help on the live binding")
        let pill = NSButton(title: "", target: nil, action: nil)
        LiveShortcutToolTip.help(pill, "New tab", commandID: "newTab:")
        check(pill.parcTooltip == nil && pill.toolTip == nil && bound.last! == ("New tab", "newTab:", false),
              "help alone, for a control Parc shows no tooltip on")
        LiveShortcutToolTip.binder = nil
    }
}
