import AppKit

/// Offscreen command bar surface, palette, hairline, row highlight and cell
/// colours (CommandBarAppearance.swift). No browser, provider or window focus.
@main @MainActor struct AppearanceTests {
    static func main() {
        _ = NSApplication.shared
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            count += 1; precondition(value(), message)
        }
        let dark = NSAppearance(named: .darkAqua)!, light = NSAppearance(named: .aqua)!
        func rgba(_ color: NSColor, _ appearance: NSAppearance) -> SIMD4<Double> {
            var out = SIMD4<Double>()
            appearance.performAsCurrentDrawingAppearance {
                let c = NSColor(cgColor: color.cgColor)!.usingColorSpace(.extendedSRGB)!
                out = SIMD4(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
            }
            return out
        }
        func rgba(_ cg: CGColor?) -> SIMD4<Double> {
            guard let cg, let c = NSColor(cgColor: cg)?.usingColorSpace(.extendedSRGB) else { return SIMD4(-1, -1, -1, -1) }
            return SIMD4(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
        }
        func near(_ a: SIMD4<Double>, _ b: SIMD4<Double>, _ tolerance: Double = 0.003) -> Bool {
            let d = a - b; return max(abs(d.x), abs(d.y), abs(d.z), abs(d.w)) <= tolerance
        }

        //
        // 0.759): dark focus 0.801, 0.080, 0.444 at 0.8075; light focus 0.877,
        // 0.428, 0.654; dark subtitle is tintedLight at 0.5 over black.
        let pink = NSColor(colorSpace: .extendedSRGB, components: [1.0698519945144653, 0.5164691805839539, 0.7590587735176086, 1], count: 4)
            .usingColorSpace(.displayP3)!
        let theme = SpaceTheme.singleColor(ThemeColor(red: Double(pink.redComponent), green: Double(pink.greenComponent),
                                                      blue: Double(pink.blueComponent), colorSpace: .displayP3)!)
        let palette = CommandBarPalette(theme: theme)
        // A light Space in a dark-mode app: the centred bar and a bar with a
        // query follow the app; only the empty sidebar bar takes the Space's.
        expect(CommandBarPalette.panelAppearance(inlineEmpty: false, space: light, window: nil) == nil, "the centred bar follows the app")
        expect(CommandBarPalette.panelAppearance(inlineEmpty: false, space: light, window: dark) === dark, "a dark window keeps its bar dark")
        expect(CommandBarPalette.panelAppearance(inlineEmpty: true, space: light, window: dark) === light, "the empty sidebar bar takes the Space's")
        expect(CommandBarPalette.panelAppearance(inlineEmpty: true, space: nil, window: dark) === dark, "a Space without one leaves the window's")
        expect(near(rgba(palette.selected, dark), SIMD4(0.801, 0.080, 0.444, 0.8075)), "dark selection is the theme's semantic focus")
        expect(near(rgba(palette.selected, light), SIMD4(0.877, 0.428, 0.654, 1)), "light selection is the light focus")
        expect(near(rgba(palette.inputSelection, dark), SIMD4(1.019 * 0.5, 0.903 * 0.5, 0.951 * 0.5, 1)),
               "field text selection is the palette subtitle")
        expect(near(rgba(palette.inputIcon, dark), SIMD4(1.019, 0.903, 0.951, 1)), "field icon is maxContrastColor")
        expect(near(rgba(palette.scopePill, dark), rgba(palette.selected, dark)), "the pill's default colour is focus")
        // A Space without a colour selects in the neutral grey palette (inferred), never the accent.
        let neutral = CommandBarPalette(theme: SpaceTheme())
        let neutralDark = SIMD4<Double>(0.356, 0.356, 0.356, 0.8075), neutralLight = SIMD4<Double>(0.6, 0.6, 0.6, 1)
        func accent(_ appearance: NSAppearance) -> [SIMD4<Double>] {
            [rgba(.controlAccentColor, appearance), rgba(.selectedContentBackgroundColor, appearance)]
        }
        expect(near(rgba(neutral.selected, dark), neutralDark) && near(rgba(neutral.selected, light), neutralLight),
               "a colourless Space selects in the neutral grey palette")
        expect(!accent(dark).contains { near($0, rgba(neutral.selected, dark), 0.05) }
               && !accent(light).contains { near($0, rgba(neutral.selected, light), 0.05) }, "never the system accent")
        expect(near(rgba(neutral.inputSelection, dark), SIMD4(0.47, 0.47, 0.47, 1))
               && near(rgba(neutral.inputSelection, light), SIMD4(0.68, 0.68, 0.68, 1)), "neutral field selection")
        expect(near(rgba(neutral.scopePill, dark), neutralDark), "the scope and Actions pills follow the neutral focus")

        //
        expect(near(rgba(CommandBarPalette.rowHover, dark), SIMD4(1, 1, 1, 0.05)), "dark hover")
        expect(near(rgba(CommandBarPalette.rowHover, light), SIMD4(0, 0, 0, 0.05)), "light hover")
        expect(near(rgba(CommandBarPalette.textPrimary, dark), SIMD4(1, 1, 1, 0.8)), "dark primary text")
        expect(near(rgba(CommandBarPalette.textSecondary, light), SIMD4(0, 0, 0, 0.33)), "light secondary text")
        expect(near(rgba(CommandBarPalette.accessoryForeground, dark), SIMD4(1, 1, 1, 0.66)), "dark accessory ink")
        expect(near(rgba(CommandBarPalette.accessoryForeground, light), SIMD4(0, 0, 0, 0.5)), "light accessory ink")
        expect(near(rgba(CommandBarPalette.accessoryBackground, dark), SIMD4(1, 1, 1, 0.05)), "accessory tile")
        expect(near(rgba(CommandBarPalette.hairline, dark), SIMD4(1, 1, 1, 0.1)), "hairline colour")
        expect(rgba(CommandBarPalette.popoverInputText, dark).w > 0.89 && rgba(CommandBarPalette.popoverInputText, light).w < 0.81,
               "PopoverInputText alpha 0.9 dark, 0.8 light")
        expect(CommandBarTypography.label.pointSize == 13 && CommandBarTypography.field.pointSize == 18, "type sizes")
        expect(NSFontManager.shared.weight(of: CommandBarTypography.label) == NSFontManager.shared.weight(of: .systemFont(ofSize: 13, weight: .medium)),
               "label is medium weight")

        // Surface: popover material, wash and decorative rings in each appearance.
        let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 900, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        let surface = PopoverBackgroundView(blending: .withinWindow)
        window.contentView = surface
        let host = surface
        for (appearance, isDark) in [(dark, true), (light, false)] {
            window.appearance = appearance
            host.layoutSubtreeIfNeeded(); surface.updateLayer()
            expect(surface.translucency.material == .popover && surface.translucency.state == .followsWindowActiveState
                   && surface.translucency.blendingMode == .withinWindow && !surface.translucency.isEmphasized, "popover material")
            let wash = rgba(surface.wash.layer?.backgroundColor)
            expect(isDark ? near(wash, SIMD4(0.065, 0.065, 0.065, 0.7)) : near(wash, SIMD4(1, 1, 1, 0.7)), "wash")
            expect(near(rgba(surface.outerBorder.borderColor), SIMD4(0, 0, 0, isDark ? 0.9 : 0.34)), "outer ring")
            expect(isDark ? near(rgba(surface.innerBorder.borderColor), SIMD4(1, 1, 1, 0.23)) : rgba(surface.innerBorder.borderColor).w == 0,
                   "inner ring only in dark")
        }
        let pixel = 1 / window.backingScaleFactor
        expect(surface.outerBorder.superlayer === surface.layer && surface.innerBorder.superlayer === surface.layer,
               "both rings are attached to the surface")
        expect(surface.wash.superview === surface && surface.subviews.firstIndex(of: surface.wash) == 1
               && surface.subviews.first === surface.translucency, "the wash is its own view just over the material")
        expect(surface.outerBorder.borderWidth == pixel && surface.innerBorder.borderWidth == 1, "ring widths")
        expect(surface.innerBorder.frame == surface.bounds.insetBy(dx: pixel, dy: pixel)
               && surface.innerBorder.cornerRadius == surface.cornerRadius - pixel, "inner ring sits inside the outer pixel")
        surface.sidebarBrowsing = true; host.layoutSubtreeIfNeeded(); surface.updateLayer()
        expect(surface.translucency.isHidden && surface.wash.isHidden && surface.outerBorder.borderWidth == 0
               && surface.layer?.backgroundColor != nil,
               "inline sidebar bar has a fill and no material or ring")
        surface.sidebarBrowsing = false

        // Shadow: a view around the bar in its window that ignores the mouse, masked to outside the bar.
        let bar = NSRect(x: 100, y: 200, width: 700, height: 326)
        let m = CommandBarShadowView.margins
        let view = CommandBarShadowView(frame: NSRect(x: 0, y: 0, width: bar.width + m.left + m.right,
                                                      height: bar.height + m.top + m.bottom))
        view.layoutSubtreeIfNeeded()
        expect(view.barFrame.size == bar.size && view.hitTest(NSPoint(x: 2, y: 2)) == nil, "the bar's place in its shadow, which never takes the mouse")
        expect(view.shadowLayer.superlayer === view.layer, "the shadow layer is attached")
        expect(view.shadowLayer.shadowOpacity == 0.5 && view.shadowLayer.shadowRadius == 48
               && view.shadowLayer.shadowOffset == CGSize(width: 0, height: 24), "black 0.5 / 48 / 24 shadow")
        let mask = view.shadowLayer.mask as? CAShapeLayer
        expect(mask?.fillRule == .evenOdd && mask?.path?.contains(CGPoint(x: 4, y: 4), using: .evenOdd) == true
               && mask?.path?.contains(CGPoint(x: view.barFrame.midX, y: view.barFrame.midY), using: .evenOdd) == false,
               "the shadow is masked to outside the bar")
        CommandBarBounce.play(on: view.shadowLayer, about: view.barCentreOffset)
        let shadowFrom = ((view.shadowLayer.animation(forKey: CommandBarBounce.key) as? CASpringAnimation)?.fromValue as? NSValue)?
            .caTransform3DValue ?? CATransform3DIdentity
        // The layer scales about its anchor, the middle of its bounds; the bar sits off that middle.
        let barFromAnchor = CGPoint(x: view.barFrame.midX - view.shadowLayer.bounds.midX, y: view.barFrame.midY - view.shadowLayer.bounds.midY)
        let barMoved = barFromAnchor.applying(CATransform3DGetAffineTransform(shadowFrom))
        expect(view.shadowLayer.anchorPoint == CGPoint(x: 0.5, y: 0.5) && view.shadowLayer.frame == view.bounds
               && barFromAnchor.y != 0 && abs(barMoved.x - barFromAnchor.x) < 0.0001 && abs(barMoved.y - barFromAnchor.y) < 0.0001
               && abs(shadowFrom.m11 - 0.95) < 0.0001, "the shadow bounces about the bar's centre, not its own")

        // Scoped search: the bar's spring bounce and the colour splash under it.
        let bounce = CommandBarBounce.animation(about: CGPoint(x: 350, y: 32))
        let stiffness = pow(2 * CGFloat.pi / 0.7, 2), damping = 4 * CGFloat.pi * 0.9 / 0.7
        expect(bounce.keyPath == "transform" && bounce.mass == 1 && abs(bounce.stiffness - stiffness) < 0.001
               && abs(bounce.damping - damping) < 0.001 && bounce.duration == bounce.settlingDuration,
               "the bounce is the 0.9 / 0.7 s spring for its settling time")
        let from = (bounce.fromValue as? NSValue)?.caTransform3DValue ?? CATransform3DIdentity
        let centre = CGPoint(x: 350, y: 32).applying(CATransform3DGetAffineTransform(from))
        expect(abs(from.m11 - 0.95) < 0.0001 && abs(from.m22 - 0.95) < 0.0001
               && abs(centre.x - 350) < 0.0001 && abs(centre.y - 32) < 0.0001
               && CATransform3DIsIdentity((bounce.toValue as? NSValue)?.caTransform3DValue ?? from),
               "it springs from 95% to full size about the given centre")
        let bounced = CALayer(); bounced.bounds = CGRect(x: 0, y: 0, width: 700, height: 64); bounced.anchorPoint = .zero
        CommandBarBounce.play(on: bounced)
        let played = bounced.animation(forKey: CommandBarBounce.key) as? CASpringAnimation
        let playedFrom = (played?.fromValue as? NSValue)?.caTransform3DValue ?? CATransform3DIdentity
        expect(abs(playedFrom.m41 - 0.05 * 350) < 0.0001 && abs(playedFrom.m42 - 0.05 * 32) < 0.0001,
               "a layer anchored at its corner bounces about its middle")
        expect(CommandBarSplashView.padding == 2 * CommandBarSplashView.blurRadius, "the splash leaves two blur radii around the bar")
        expect(CommandBarSplashView.blurRadius == 150 && CommandBarSplashView.duration == 1.2,
               "the splash blurs to 150 and fades over 1.2 seconds")

        // Hairline: one device pixel in CommandBarHairlineDividerColor.
        let hairline = CommandBarHairline(frame: NSRect(x: 12, y: 64, width: 700, height: CommandBarHairline.height(in: window)))
        surface.addSubview(hairline); window.appearance = dark; hairline.updateLayer()
        expect(CommandBarHairline.height(in: window) == pixel && CommandBarHairline.height(in: nil) == 1, "one device pixel")
        expect(near(rgba(hairline.layer?.backgroundColor), SIMD4(1, 1, 1, 0.1)), "hairline paints white 0.1 in dark")

        // Row highlight: a plain 2-point-inset layer, radius 6, with an implicit fade.
        // Implicit actions need a rendered tree: order the offscreen window in
        // without activating the app or making it key.
        window.orderFrontRegardless()
        let row = CommandResultRowView(frame: NSRect(x: 0, y: 0, width: 600, height: 50))
        row.selectedColor = palette.selected
        surface.addSubview(row); row.layoutSubtreeIfNeeded()
        expect(row.highlight.superlayer === row.layer, "the highlight is attached to the row")
        expect(row.highlight.frame == row.bounds.insetBy(dx: 2, dy: 2) && row.highlight.cornerRadius == 6
               && row.highlight.cornerCurve == .continuous, "highlight geometry")
        expect(rgba(row.highlight.backgroundColor).w == 0, "unselected rows are clear")
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        row.isSelected = true
        expect(near(rgba(row.highlight.backgroundColor), rgba(palette.selected, dark)), "selected rows take the theme focus")
        let fade = row.highlight.animation(forKey: "backgroundColor") as? CABasicAnimation
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        let midway = rgba(row.highlight.presentation()?.backgroundColor).w
        expect(fade?.duration == CATransaction.animationDuration() || (midway > 0.05 && midway < 0.8),
               "selection changes take Core Animation's implicit fade")
        expect(row.highlight.delegate == nil, "the highlight is not a view's backing layer")
        row.isSelected = false
        expect(rgba(row.highlight.backgroundColor).w == 0, "deselection clears")

        // Rows default to the neutral palette, not the system accent.
        let plainRow = CommandResultRowView()
        expect(near(rgba(plainRow.selectedColor, dark), neutralDark) && near(rgba(plainRow.selectedColor, light), neutralLight)
               && !accent(dark).contains { near($0, rgba(plainRow.selectedColor, dark), 0.05) }, "no system-accent row default")

        // Cell colours: Type Travel tiles and keycaps; favicon tiles only when selected.
        let favicon = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }
        let site = CommandResultCell(title: "YouTube", detail: "youtube.com", accessory: "", isTab: false, icon: favicon, enabled: true)
        let command = CommandResultCell(title: "New Easel", detail: "", accessory: "⌃⇧E", isTab: false,
                                        icon: NSImage(systemSymbolName: "scribble", accessibilityDescription: nil), enabled: true, isAction: true)
        for cell in [site, command] {
            cell.frame = NSRect(x: 0, y: 0, width: 600, height: 50); surface.addSubview(cell)
            cell.selectedColor = palette.selected; cell.layoutSubtreeIfNeeded()
        }
        func tile(_ cell: CommandResultCell) -> NSView? { cell.subviews.first { $0.frame.size == NSSize(width: 24, height: 24) } }
        site.setSelected(false)
        expect(tile(site)?.isHidden == true, "an unselected favicon has no tile")
        site.setSelected(true)
        expect(tile(site)?.isHidden == false && near(rgba(tile(site)?.layer?.backgroundColor), SIMD4(1, 1, 1, 1)), "selected favicon tile is white")
        command.setSelected(false)
        expect(tile(command)?.isHidden == false && near(rgba(tile(command)?.layer?.backgroundColor), SIMD4(1, 1, 1, 0.05)),
               "command tile is the accessory background")
        command.setSelected(true)
        let label = command.subviews.compactMap { $0 as? NSTextField }.first { $0.attributedStringValue.string == "New Easel" }
        let title = label?.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let font = label?.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        expect(title.map { near(rgba($0, dark), SIMD4(1, 1, 1, 1)) } == true, "selected title is white")
        expect(font == CommandBarTypography.label, "row text uses the command bar label font")
        let plainCell = CommandResultCell(title: "x", detail: "", accessory: "", isTab: false, icon: nil, enabled: true)
        expect(near(rgba(plainCell.selectedColor, dark), neutralDark)
               && !accent(dark).contains { near($0, rgba(plainCell.selectedColor, dark), 0.05) }, "no system-accent cell default")

        // A label framed at its intrinsic (alignment) width loses its 2-point text
        // padding and truncates, so every row label must hold its single line.
        let longSpace = CommandBarSpaceAction(spaceID: UUID(), profileID: UUID(), name: "Personal Projects", symbol: "briefcase",
                                              profileName: "Work Profile", needsProfileLabel: true)
        let longCell = CommandResultCell(title: "Focus on", detail: longSpace.detail, accessory: "", isTab: false, icon: nil,
                                         enabled: true, spaceAction: longSpace)
        longCell.frame = NSRect(x: 0, y: 0, width: 600, height: 50); surface.addSubview(longCell); longCell.layoutSubtreeIfNeeded()
        func labels(_ view: NSView) -> [NSTextField] { view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? labels($0) } }
        for cell in [longCell, command] {
            for field in labels(cell) where !field.isHidden && !field.stringValue.isEmpty {
                let line = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 100)).width ?? .infinity
                expect(line <= field.frame.width, "'\(field.stringValue)' fits its frame without truncating")
            }
        }
        let keycap = labels(command).first { $0.stringValue == "⌃⇧E" }
        expect(keycap.map { $0.alignmentRect(forFrame: $0.frame).minX } == 4, "the keycap's text starts 4 points in pins it")

        // Appearance changes re-resolve tiles, keycaps and the Space capsule.
        command.setSelected(false)
        window.appearance = light; command.layoutSubtreeIfNeeded()
        expect(near(rgba(tile(command)?.layer?.backgroundColor), SIMD4(0, 0, 0, 0.05)), "light tile after an appearance change")
        let space = CommandBarSpaceAction(spaceID: UUID(), profileID: UUID(), name: "Work", symbol: "briefcase",
                                          profileName: "Personal", needsProfileLabel: false)
        let spaceCell = CommandResultCell(title: "Focus on", detail: "", accessory: "", isTab: false, icon: nil, enabled: true,
                                          spaceAction: space)
        spaceCell.frame = NSRect(x: 0, y: 0, width: 600, height: 50); surface.addSubview(spaceCell)
        spaceCell.setSelected(false)
        let capsule = spaceCell.subviews.first { $0.layer?.cornerRadius == 4 && $0.subviews.contains { $0 is NSImageView } }
        expect(near(rgba(capsule?.layer?.backgroundColor), SIMD4(0, 0, 0, 0.05)), "the Space capsule shows on a light bar")
        window.appearance = dark
        expect(near(rgba(tile(command)?.layer?.backgroundColor), SIMD4(1, 1, 1, 0.05)), "dark tile after switching back")

        window.orderOut(nil)
        print("Command bar appearance checks passed (\(count) assertions).")
    }
}
