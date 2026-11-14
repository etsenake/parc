import AppKit
import MetalKit

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
        notePaper()
        backgroundForwarding()
        livePalette()
        renderedBackground()
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
        check(page.background.frame == page.bounds && page.subviews.first === page.background, "the theme fills the page beneath everything")
        check(page.mark.frame == layout.mark && page.commandBarSlot.frame == layout.commandBarSlot, "the view places the mark and slot from the layout")
        check(page.mark.superview === page && page.commandBarSlot.superview === page, "mark and slot are the page's own")
        check(page.chromeOrigin == CGPoint(x: -5, y: -5), "the chrome anchors to the floating sidebar's corner in the window's space")
        page.barRestHeight = 52
        page.layoutSubtreeIfNeeded()
        check(page.commandBarSlot.frame == StartPageLayout(size: page.bounds.size, barRestHeight: 52, chromeOrigin: nil,
                                                           showsWindowButtons: true).commandBarSlot, "the owner's resting height re-centres the pair")
        page.frame.size = NSSize(width: 700, height: 500)
        page.layoutSubtreeIfNeeded()
        check(page.commandBarSlot.frame.width == 620 && page.background.frame == page.bounds, "resizing re-lays out the slot and background")
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

    static func notePaper() {
        let (_, _, page) = hierarchy()
        let order = page.subviews
        check(order.firstIndex(of: page.paper).map { $0 == order.firstIndex(of: page.background)! + 1 } == true
              && order.firstIndex(of: page.paper)! < order.firstIndex(of: page.mark)!, "Note paper lies on the theme, under the mark and the bar")
        check(page.paper.frame == page.bounds && page.paper.hitTest(CGPoint(x: 10, y: 10)) == nil, "the paper covers the page and takes no clicks")
        for (name, alpha, white) in [(NSAppearance.Name.aqua, 0.85, 1.0), (.darkAqua, 0.5, 0.0)] {
            page.paper.appearance = NSAppearance(named: name)
            page.paper.updateLayer()
            let color = page.paper.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB)
            check(color.map { abs($0.alphaComponent - alpha) < 0.001 && abs($0.redComponent - white) < 0.001 } == true,
                  "the page is a Note's paper in \(name.rawValue)")
        }
    }

    static func accessibility() {
        let (root, _, page) = hierarchy()
        check(page.isAccessibilityElement() && page.accessibilityRole() == .group && page.accessibilityLabel() == "Start page",
              "the page is one labelled group")
        check(page.sidebarButton.accessibilityLabel() == "Show sidebar" && page.sidebarButton.cell?.accessibilityLabel() == "Show sidebar",
              "the sidebar button says what it does")
        check(!page.background.isAccessibilityElement() && !page.commandBarSlot.isAccessibilityElement(), "the background and slot add no elements")
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

    static func backgroundForwarding() {
        let (root, _, page) = hierarchy()
        check(page.background.coordinateSpace === root && page.mark.coordinateSpace === root, "background and mark share the window's gradient space")
        let theme = textured(violet, .tweed)
        page.theme = theme
        let drawn = page.background.theme
        check(drawn.noise == 0, "the page background draws no texture")
        check(drawn.primaryColor == theme.primaryColor && drawn.colorCount == theme.colorCount && drawn.wheel == theme.wheel
              && drawn.appearance == theme.appearance && drawn.intensity == theme.intensity, "every colour, the intensity and the appearance stay")
        check(page.mark.theme == theme, "the mark keeps the theme's texture")
        var multi = SpaceTheme(primaryColor: ThemeColor(red: 0.2, green: 0.5, blue: 0.7)!, colorCount: 3, wheel: .analogous,
                               appearance: .dark, noise: 0.6, intensity: 0.35, texture: .denim)
        page.theme = multi
        check(page.background.theme.colors == multi.colors && page.background.theme.noise == 0, "three-colour themes keep all three colours")
        multi.noise = 2
        page.theme = multi
        check(page.background.theme == multi, "an invalid theme passes through untouched, so it falls back to material like the window")
        page.theme = SpaceTheme()
        check(page.background.theme == SpaceTheme(), "a colourless theme reaches the background as material")
        page.pagingTransition = ThemePagingTransition(from: textured(violet), theme: textured(amber, .sand), progress: 0.3)
        let paging = page.background.pagingTransition
        check(paging?.from == StartPageView.untextured(textured(violet)) && paging?.theme == StartPageView.untextured(textured(amber, .sand))
              && paging?.progress == 0.3, "a Space swipe reaches the background, untextured on both sides")
        page.pagingTransition = nil
        check(page.background.pagingTransition == nil, "the swipe's end clears it")
        page.incognito = true
        check(page.background.incognito && page.mark.incognito, "a private window's page uses the private palette")
        let canvas = page.background.subviews.compactMap { $0 as? MTKView }.first
        let material = page.background.subviews.compactMap { $0 as? NSVisualEffectView }.first
        check(canvas.map(\.isHidden) != false && material?.isHidden == true
              && page.background.layer?.backgroundColor == IncognitoWindowTheme.background.cgColor, "private: the opaque private fill, no material or canvas")
        page.incognito = false
        page.theme = SpaceTheme()
        check(material?.isHidden == false && canvas.map(\.isHidden) != false, "a colourless theme shows material only")
        page.theme = violet
        check(material?.isHidden == false && canvas.map { !$0.isHidden } != false, "a coloured theme draws the gradient over the window's material")
        check(material?.blendingMode == .behindWindow, "the material is the window's own behind-window kind")
    }

    static func livePalette() {
        let (_, _, page) = hierarchy()
        page.theme = textured(violet, appearance: .dark)
        check(page.windowButtons.appearance?.name == .darkAqua && page.sidebarButton.appearance?.name == .darkAqua
              && page.commandBarSlot.appearance?.name == .darkAqua, "a dark theme dresses the chrome and the bar's slot dark")
        check(page.sidebarButton.contentTintColor == page.background.palette.title, "the toggle takes the palette's title colour")
        page.theme = textured(amber, appearance: .light)
        check(page.windowButtons.appearance?.name == .aqua && page.sidebarButton.appearance?.name == .aqua
              && page.commandBarSlot.appearance?.name == .aqua, "switching to a light theme refreshes live")
        page.appearance = NSAppearance(named: .darkAqua)
        page.theme = violet
        check(page.commandBarSlot.appearance?.name == page.background.palette.contentAppearance?.name,
              "an automatic theme follows the appearance the page lives in")
    }

    static func pixels(_ surface: ThemeRendererView) -> (bytes: [UInt8], width: Int, height: Int) {
        surface.needsLayout = true; surface.layoutSubtreeIfNeeded()
        guard let canvas = surface.subviews.compactMap({ $0 as? MTKView }).first else { fatalError("StartPage: Metal canvas") }
        canvas.framebufferOnly = false
        canvas.releaseDrawables()
        guard let drawable = canvas.currentDrawable else { fatalError("StartPage: offscreen drawable") }
        canvas.draw(canvas.bounds)
        canvas.needsDisplay = false
        let texture = drawable.texture, length = texture.width * texture.height * 4
        let buffer = canvas.device!.makeBuffer(length: length, options: .storageModeShared)!
        let command = canvas.device!.makeCommandQueue()!.makeCommandBuffer()!, blit = command.makeBlitCommandEncoder()!
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: texture.width * 4, destinationBytesPerImage: length)
        blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        let bytes = Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: UInt8.self, capacity: length), count: length))
        return (bytes, texture.width, texture.height)
    }

    static func rightHalf(_ image: (bytes: [UInt8], width: Int, height: Int)) -> [UInt8] {
        (0..<image.height).flatMap { row in image.bytes[(row * image.width + image.width / 2) * 4 ..< (row * image.width + image.width) * 4] }
    }

    static func difference(_ a: [UInt8], _ b: [UInt8]) -> (maximum: Int, changed: Int) {
        zip(a, b).reduce((0, 0)) { result, pair in
            let delta = abs(Int(pair.0) - Int(pair.1))
            return (max(result.0, delta), result.1 + (delta > 2 ? 1 : 0))
        }
    }

    static func renderedBackground() {
        guard MTLCreateSystemDefaultDevice() != nil else { return check(false, "Metal is available for the render check") }
        let size = NSRect(x: 0, y: 0, width: 200, height: 100)
        let root = ThemeRendererView(frame: size)
        let page = StartPageView(frame: NSRect(x: 100, y: 0, width: 100, height: 100))
        root.addSubview(page)
        page.coordinateSpace = root
        let reference = ThemeRendererView(frame: size)
        let theme = textured(violet)
        root.theme = theme; page.theme = theme; reference.theme = StartPageView.untextured(theme)
        let window = pixels(root), plain = pixels(reference), drawn = pixels(page.background)
        check(plain.width == 2 * drawn.width && plain.height == drawn.height && window.width == plain.width && drawn.width > 0,
              "the page draws half the window's width at the same density")
        let textureShows = difference(window.bytes, plain.bytes)
        check(textureShows.changed > plain.bytes.count / 20, "the window's own surface still draws its texture (\(textureShows.changed) values differ)")
        let sameAsWindow = difference(drawn.bytes, rightHalf(plain))
        check(sameAsWindow.maximum <= 1, "the page draws the window's gradient for the same spot, untextured (max Δ \(sameAsWindow.maximum))")
        let swipe = ThemePagingTransition(from: theme, theme: textured(amber, .tweed), progress: 0.5)
        page.pagingTransition = swipe
        reference.pagingTransition = StartPageView.untextured(swipe)
        let blended = pixels(page.background), blendedPlain = pixels(reference)
        check(difference(blended.bytes, rightHalf(blendedPlain)).maximum <= 1, "mid-swipe the page blends both themes like the window")
        check(difference(blended.bytes, drawn.bytes).changed > drawn.bytes.count / 4, "the swipe visibly changes the page")
    }
}
