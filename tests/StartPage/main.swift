import AppKit

@MainActor @main struct StartPageChecks {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("StartPage: \(message)") }
    }
    static func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.5) -> Bool { abs(a - b) <= e }

    static let violet = SpaceTheme.singleColor(ThemeColor(red: 0.42, green: 0.36, blue: 0.86)!)
    static let amber = SpaceTheme.singleColor(ThemeColor(red: 0.9, green: 0.55, blue: 0.2)!)
    static func textured(_ base: SpaceTheme, _ texture: SpaceTheme.Texture = .grain, appearance: SpaceTheme.Appearance = .automatic) -> SpaceTheme {
        var theme = base
        theme.noise = 1; theme.texture = texture; theme.intensity = 1; theme.appearance = appearance
        return theme
    }

    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        layoutGeometry()
        chromeGeometry()
        viewPlacement()
        chromeVisibilityAndAction()
        hitTesting()
        accessibility()
        tintedPaper()
        paperView()
        forwarding()
        livePalette()
        print("StartPage: \(count) assertions passed")
    }

    static func layoutGeometry() {
        typealias Layout = StartPageLayout
        check(Layout.markSize.width == 65 && Layout.markSpacing == 24 && Layout.maximumBarWidth == 765, "a 65-point mark 24 points above a 765-point bar")
        check(Layout.defaultBarRestHeight == 64, "the bar rests at 64 points until the owner says otherwise")
        for size in [CGSize(width: 1220, height: 820), CGSize(width: 1001, height: 677), CGSize(width: 640, height: 480)] {
            for rest in [64, 52, 80] as [CGFloat] {
                let layout = Layout(size: size, barRestHeight: rest, chromeOrigin: nil, showsWindowButtons: true)
                let slot = layout.commandBarSlot, mark = layout.mark
                check(slot.width == min(765, size.width - 2 * Layout.sideGutter), "the slot is min(765, width − gutters) at \(size)")
                check(near(slot.midX, size.width / 2) && near(mark.midX, size.width / 2), "mark and bar are centred at \(size)")
                check(slot.minY - mark.maxY == 24, "the mark sits 24 points above the bar's top edge at \(size)")
                check(slot.maxY == size.height, "the slot runs to the bottom so the bar can grow down at \(size)")
                let pairCenter = (mark.minY + slot.minY + rest) / 2
                check(near(pairCenter, size.height * Layout.pairCenter), "the resting pair centres at 45% of the height at \(size), rest \(rest)")
                check(pairCenter < size.height / 2 && pairCenter > size.height * 0.4, "the pair sits a little above the vertical centre at \(size)")
                check([slot.minX, slot.minY, mark.minX, mark.minY].allSatisfy { $0 == $0.rounded() }, "whole-point frames at \(size)")
                check(layout.windowButtons == nil && layout.sidebarButton == nil, "no chrome without an origin")
            }
        }
        let low = Layout(size: CGSize(width: 1000, height: 600), barRestHeight: 64, chromeOrigin: nil, showsWindowButtons: true)
        let tall = Layout(size: CGSize(width: 1000, height: 600), barRestHeight: 120, chromeOrigin: nil, showsWindowButtons: true)
        check(tall.commandBarSlot.minY == low.commandBarSlot.minY - 28, "a taller resting bar lifts the pair by half the difference")
        let measured = Layout(size: CGSize(width: 1000, height: 600), barRestHeight: 64, markSize: CGSize(width: 64, height: 90),
                              chromeOrigin: nil, showsWindowButtons: true)
        check(measured.mark.size == CGSize(width: 64, height: 90) && measured.commandBarSlot.minY - measured.mark.maxY == 24
              && near((measured.mark.minY + measured.commandBarSlot.minY + 64) / 2, 270), "the layout follows the mark's own size")
        let unmeasured = Layout(size: CGSize(width: 1000, height: 600), barRestHeight: 64, markSize: CGSize(width: -1, height: -1),
                                chromeOrigin: nil, showsWindowButtons: true)
        check(unmeasured == low, "a mark without a size falls back to 65 × 96")
        let narrow = Layout(size: CGSize(width: 300, height: 900), barRestHeight: 64, chromeOrigin: nil, showsWindowButtons: true)
        check(narrow.commandBarSlot.width == 220 && narrow.commandBarSlot.minX == 40, "a narrow page keeps 40-point gutters")
        let tiny = Layout(size: CGSize(width: 50, height: 100), barRestHeight: 64, chromeOrigin: nil, showsWindowButtons: true)
        check(tiny.mark.minY == 0 && tiny.commandBarSlot.width == 0 && tiny.commandBarSlot.height >= 0, "a tiny page clamps instead of going negative")
    }

    static func chromeGeometry() {
        let origin = CGPoint(x: -5, y: -5)
        let layout = StartPageLayout(size: CGSize(width: 1220, height: 820), barRestHeight: 64, chromeOrigin: origin, showsWindowButtons: true)
        let sidebar = SidebarChromeLayout.toolbar(width: 1220, windowButtons: WindowStandardButtons.stackSize, showsNavigation: false)
        check(layout.windowButtons == sidebar.windowButtons?.offsetBy(dx: -5, dy: -5), "the window buttons sit where the sidebar header puts them")
        check(layout.sidebarButton == sidebar.toggle?.offsetBy(dx: -5, dy: -5), "the sidebar button sits where the sidebar's own toggle does")
        guard let lights = layout.windowButtons, let toggle = layout.sidebarButton else { return check(false, "chrome frames exist") }
        check(lights.size == WindowStandardButtons.stackSize && toggle.size == CGSize(width: 32, height: 32), "standard buttons and a 32-point toggle")
        check(lights.midY == toggle.midY && toggle.minX == lights.maxX + SidebarChromeLayout.windowButtonMargin, "one row, toggle after the lights")
        let bare = StartPageLayout(size: CGSize(width: 1220, height: 820), barRestHeight: 64, chromeOrigin: origin, showsWindowButtons: false)
        check(bare.windowButtons == nil && bare.sidebarButton?.minX == SidebarChromeLayout.navigationLeading - 5,
              "without window buttons the toggle takes the leading slot")
        for width: CGFloat in [164, 190, 210, 228, 320] {
            for navigation in [false, true] {
                let narrow = StartPageLayout(size: CGSize(width: 1220, height: 820), barRestHeight: 64, chromeOrigin: origin,
                                             showsWindowButtons: true, toolbarWidth: width, showsNavigation: navigation)
                let own = SidebarChromeLayout.toolbar(width: width, windowButtons: WindowStandardButtons.stackSize, showsNavigation: navigation)
                check(narrow.sidebarButton == own.toggle?.offsetBy(dx: -5, dy: -5) && narrow.windowButtons == own.windowButtons?.offsetBy(dx: -5, dy: -5),
                      "a \(width)-point sidebar with navigation \(navigation) lands its toggle exactly on the page's")
            }
        }
    }

    static func hierarchy() -> (root: ThemeRendererView, card: NSView, page: StartPageView) {
        let root = ThemeRendererView(frame: NSRect(x: 0, y: 0, width: 1240, height: 840))
        let card = NSView(frame: NSRect(x: 10, y: 10, width: 1220, height: 820))
        root.addSubview(card)
        let page = StartPageView()
        page.frame = card.bounds
        card.addSubview(page)
        page.coordinateSpace = root
        page.needsLayout = true; page.layoutSubtreeIfNeeded()
        return (root, card, page)
    }

    static func viewPlacement() {
        let (root, _, page) = hierarchy()
        let layout = StartPageLayout(size: page.bounds.size, barRestHeight: 64, chromeOrigin: nil, showsWindowButtons: true)
        check(page.paper.frame == page.bounds && page.subviews.first === page.paper, "the tinted paper fills the page beneath everything")
        check(page.mark.frame == layout.mark && page.commandBarSlot.frame == layout.commandBarSlot, "the view places the mark and slot from the layout")
        check(page.mark.superview === page && page.commandBarSlot.superview === page, "mark and slot are the page's own")
        check(page.chromeOrigin == CGPoint(x: -5, y: -5), "the chrome anchors to the floating sidebar's corner in the window's space")
        page.barRestHeight = 52
        page.layoutSubtreeIfNeeded()
        check(page.commandBarSlot.frame == StartPageLayout(size: page.bounds.size, barRestHeight: 52, chromeOrigin: nil,
                                                           showsWindowButtons: true).commandBarSlot, "the owner's resting height re-centres the pair")
        page.frame.size = NSSize(width: 700, height: 500)
        page.layoutSubtreeIfNeeded()
        check(page.commandBarSlot.frame.width == 620 && page.paper.frame == page.bounds, "resizing re-lays out the slot and paper")
        _ = root
    }

    static func chromeVisibilityAndAction() {
        let (root, _, page) = hierarchy()
        check(page.windowButtons.isHidden && page.sidebarButton.isHidden, "a docked sidebar keeps the page's chrome hidden")
        page.showsWindowChrome = true
        page.layoutSubtreeIfNeeded()
        check(!page.windowButtons.isHidden && !page.sidebarButton.isHidden, "a hidden sidebar shows the window buttons and the sidebar button")
        let floating = SidebarPresentationFrame.floating.rect(width: 260, in: root.bounds)
        let header = SidebarChromeLayout.toolbar(width: 260, windowButtons: WindowStandardButtons.stackSize, showsNavigation: false)
        check(page.convert(page.windowButtons.frame, to: root) == header.windowButtons?.offsetBy(dx: floating.minX, dy: floating.minY),
              "the page's window buttons line up with the floating sidebar's")
        check(page.convert(page.sidebarButton.frame, to: root) == header.toggle?.offsetBy(dx: floating.minX, dy: floating.minY),
              "the page's sidebar button lines up with the floating sidebar's toggle")
        check(page.sidebarButton.translucentFace != nil && page.sidebarButton.imagePosition == .imageOnly
              && page.sidebarButton.focusRingCornerRadius == 5, "the sidebar button is styled like the sidebar's toggle")
        var toggles = 0
        page.onToggleSidebar = { toggles += 1 }
        page.sidebarButton.sendAction(page.sidebarButton.action, to: page.sidebarButton.target)
        check(toggles == 1, "the sidebar button asks the window to show the sidebar")
        page.showsWindowButtons = false
        page.layoutSubtreeIfNeeded()
        check(page.windowButtons.isHidden && !page.sidebarButton.isHidden
              && page.sidebarButton.frame.minX == SidebarChromeLayout.navigationLeading + page.chromeOrigin.x,
              "with the system's own buttons showing, only the sidebar button remains, in the leading slot")
        page.showsWindowButtons = true; page.showsWindowChrome = false
        page.layoutSubtreeIfNeeded()
        check(page.windowButtons.isHidden && page.sidebarButton.isHidden, "docking the sidebar hides the page's chrome again")
        let loose = StartPageView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        loose.showsWindowChrome = true
        loose.layoutSubtreeIfNeeded()
        check(loose.chromeOrigin == .zero && loose.sidebarButton.frame.minY == SidebarChromeLayout.headerTop + 4,
              "without a coordinate space the chrome measures from the page corner")
    }

    static func hitTesting() {
        let (_, card, page) = hierarchy()
        func hit(_ point: CGPoint) -> NSView? { page.hitTest(card.convert(point, from: page)) }
        let slot = page.commandBarSlot.frame
        let card8 = NSView(frame: NSRect(x: 0, y: 0, width: slot.width, height: 64))
        page.commandBarSlot.addSubview(card8)
        check(hit(CGPoint(x: slot.midX, y: slot.minY + 32)) === card8, "the bar card inside the slot takes its clicks")
        check(hit(CGPoint(x: slot.midX, y: slot.minY + 200)) === page, "the slot below the bar card falls through to the page background")
        check(page.commandBarSlot.hitTest(page.convert(CGPoint(x: slot.midX, y: slot.minY + 200), to: page.commandBarSlot.superview)) == nil,
              "the slot itself never swallows a click")
        check(hit(CGPoint(x: 20, y: 400)) === page, "the background routes clicks to the page so it can drag the window")
        check(hit(CGPoint(x: page.mark.frame.midX, y: page.mark.frame.midY)) === page.mark, "the mark gets its own clicks")
        let toggle = page.sidebarButton.frame
        check(hit(CGPoint(x: toggle.midX, y: toggle.midY)) === page, "hidden chrome takes no clicks")
        page.showsWindowChrome = true
        page.layoutSubtreeIfNeeded()
        let shown = page.sidebarButton.frame
        check(hit(CGPoint(x: shown.midX, y: shown.midY)) === page.sidebarButton, "the shown sidebar button takes its click")
        page.isDeparting = true
        check(hit(CGPoint(x: 20, y: 400)) == nil && hit(CGPoint(x: slot.midX, y: slot.minY + 32)) == nil
              && hit(CGPoint(x: shown.midX, y: shown.midY)) == nil, "a start page fading out lets every click reach the new page")
        page.isDeparting = false
    }

    static func accessibility() {
        let (root, _, page) = hierarchy()
        check(page.isAccessibilityElement() && page.accessibilityRole() == .group && page.accessibilityLabel() == "Start page",
              "the page is one labelled group")
        check(page.sidebarButton.accessibilityLabel() == "Show sidebar" && page.sidebarButton.cell?.accessibilityLabel() == "Show sidebar",
              "the sidebar button says what it does")
        check(!page.paper.isAccessibilityElement() && !page.commandBarSlot.isAccessibilityElement(), "the paper and slot add no elements")
        let window = NSWindow(contentRect: root.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = root
        page.commandBarSlot.addSubview(NSButton(title: "Bar", target: nil, action: nil))
        page.showsWindowChrome = true
        page.layoutSubtreeIfNeeded()
        let children = (page.accessibilityChildren() ?? []).compactMap { ($0 as? NSView) ?? ($0 as? NSCell)?.controlView }
        check(page.windowButtons.buttons.count == 3, "the page carries its own close, minimise and zoom buttons")
        let order = children.map { child in
            child.isDescendant(of: page.windowButtons) ? 0 : child === page.sidebarButton ? 1 : child.isDescendant(of: page.commandBarSlot) ? 2 : 3
        }
        check(order == [0, 0, 0, 1, 2], "VoiceOver meets the window controls, then the sidebar button, then the bar: \(order)")
        window.contentView = nil
    }

    static func tintedPaper() {
        typealias Style = StartPagePaperStyle
        let colourless = Style(theme: SpaceTheme(), dark: false), colourlessDark = Style(theme: SpaceTheme(), dark: true)
        check(colourless.glows.isEmpty && colourless.base == Style.colorlessLight && colourlessDark.base == Style.colorlessDark,
              "a colourless theme is plain solid paper in light and dark")
        let multi = SpaceTheme(primaryColor: ThemeColor(red: 0.48, green: 0.87, blue: 0.38)!, colorCount: 3, wheel: .complimentary)
        let light = Style(theme: multi, dark: false), dark = Style(theme: multi, dark: true)
        check(light.glows.count == 3 && light.glows.map(\.anchor) == Style.anchors, "every theme colour glows from its corner")
        let colors = multi.colors.map { ThemeRenderMath.srgb($0) }.map { SIMD3(Double($0.x), Double($0.y), Double($0.z)) }
        let average = colors.reduce(SIMD3<Double>(repeating: 0), +) / 3
        check(light.glows.map(\.color) == colors, "the glows are the theme's own colours")
        check(light.base == Style.mix(average, SIMD3(repeating: 1), Style.lightTint), "light paper is the theme's average tint, mostly white")
        check(dark.base == Style.mix(average, Style.darkBase, Style.darkTint), "dark paper is the theme's average tint, mostly near-black")
        check(light.glowStrength == 0.55 && dark.glowStrength == 0.42 && light.grain > dark.grain, "glows and grain are softer in the dark")
        let single = Style(theme: violet, dark: false)
        check(single.glows.count == 1 && single.glows.first?.anchor == Style.anchors[0], "a single colour glows from the top-left corner")
        check(Style.glowAlpha(at: 0, strength: 0.5) == 0.5 && Style.glowAlpha(at: 1, strength: 0.5) == 0
              && Style.glowAlpha(at: 0.3, strength: 0.5) > Style.glowAlpha(at: 0.6, strength: 0.5), "a glow fades from its centre to nothing")
        let frame = Style.glowFrame(CGPoint(x: 1, y: 0.25), in: CGSize(width: 1000, height: 600))
        check(frame.midX == 1000 && frame.midY == 150 && frame.width == 1240 && frame.height == 1240, "a glow is centred on its anchor, 62% of the page's long side in radius")
    }

    static func paperView() {
        let (_, _, page) = hierarchy()
        let paper = page.paper
        check(paper.hitTest(CGPoint(x: 10, y: 10)) == nil && !paper.isAccessibilityElement(), "the paper takes no clicks and adds no element")
        page.theme = SpaceTheme(primaryColor: ThemeColor(red: 0.48, green: 0.87, blue: 0.38)!, colorCount: 3, wheel: .complimentary)
        for (name, dark) in [(NSAppearance.Name.aqua, false), (.darkAqua, true)] {
            page.appearance = NSAppearance(named: name)
            page.viewDidChangeEffectiveAppearance(); paper.viewDidChangeEffectiveAppearance()
            paper.updateLayer()
            check(paper.style.dark == dark, "the paper follows the \(name.rawValue) appearance it lives in")
            let base = paper.style.base
            let drawn = paper.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB)
            check(drawn.map { abs($0.redComponent - base.x) < 0.002 && abs($0.greenComponent - base.y) < 0.002 } == true,
                  "the paper's layer is its tint in \(name.rawValue)")
        }
        let glows = paper.layer?.sublayers?.first?.sublayers ?? []
        check(glows.count == 3 && glows.allSatisfy { ($0 as? CAGradientLayer)?.type == .radial }, "three radial glows sit on the tint")
        page.pagingTransition = ThemePagingTransition(from: violet, theme: amber, progress: 0.25)
        check(paper.incomingStyle != nil, "a Space swipe prepares the incoming Space's paper")
        let layers = paper.layer?.sublayers ?? []
        check(layers.count >= 2 && abs(layers[0].opacity - 0.75) < 0.001 && abs(layers[1].opacity - 0.25) < 0.001, "the swipe cross-fades the two Spaces' glows")
        page.pagingTransition = nil
        check(paper.incomingStyle == nil && layers[1].opacity == 0, "the swipe's end leaves one Space's paper")
        page.incognito = true
        check(paper.effectiveTheme == IncognitoWindowTheme.paletteTheme, "a private window's paper uses the private palette")
    }

    static func forwarding() {
        let (root, _, page) = hierarchy()
        check(page.mark.coordinateSpace === root, "the mark shares the window's coordinate space")
        let theme = textured(violet, .tweed)
        page.theme = theme
        check(page.paper.theme == theme && page.mark.theme == theme, "the theme reaches the paper and the mark")
        let swipe = ThemePagingTransition(from: violet, theme: amber, progress: 0.3)
        page.pagingTransition = swipe
        check(page.paper.pagingTransition == swipe && page.mark.pagingTransition == swipe, "a Space swipe reaches the paper and the mark")
        page.incognito = true
        check(page.paper.incognito && page.mark.incognito, "a private window reaches the paper and the mark")
    }

    static func livePalette() {
        let (_, _, page) = hierarchy()
        page.theme = violet
        page.appearance = NSAppearance(named: .darkAqua)
        page.viewDidChangeEffectiveAppearance()
        check(page.commandBarSlot.appearance == nil && page.windowButtons.appearance == nil && page.sidebarButton.appearance == nil,
              "the bar and chrome follow the page's own appearance")
        check(page.sidebarButton.contentTintColor == ThemeChromePalette(theme: violet, isDark: true).title, "dark: the toggle takes the dark title colour")
        page.appearance = NSAppearance(named: .aqua)
        page.viewDidChangeEffectiveAppearance()
        check(page.sidebarButton.contentTintColor == ThemeChromePalette(theme: violet, isDark: false).title, "light: switching appearance refreshes live")
    }
}
