import AppKit
import SwiftUI

@MainActor @main struct SidebarHeaderGlyphChecks {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarHeaderGlyphs: \(message)") }
    }
    static func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.0005) -> Bool { abs(a - b) <= e }
    static func rgba(_ color: NSColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let c = color.usingColorSpace(.sRGB)!
        return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }
    static func gray(_ color: NSColor, white: CGFloat, alpha: CGFloat) -> Bool {
        let (r, g, b, a) = rgba(color)
        return near(r, white) && near(g, white) && near(b, white) && near(a, alpha)
    }

    static func capture(_ view: NSView) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }
    static func maxAlpha(_ rep: NSBitmapImageRep) -> CGFloat {
        var best: CGFloat = 0
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide { best = max(best, rep.colorAt(x: x, y: y)!.alphaComponent) } }
        return best
    }
    static func render(_ size: NSSize, _ draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    static func inkBounds(_ rep: NSBitmapImageRep, threshold: CGFloat = 0.2) -> (minX: Int, maxX: Int) {
        var minX = Int.max, maxX = -1
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide where rep.colorAt(x: x, y: y)!.alphaComponent > threshold {
            minX = min(minX, x); maxX = max(maxX, x) } }
        return (minX, maxX)
    }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        typealias Chrome = SidebarChromeLayout
        check(Chrome.navigationGlyphPointSize == 16 && Chrome.narrowNavigationGlyphPointSize == 14, "16 and 14 points")
        check(Chrome.navigationGlyphPointSize(buttonSide: 32) == 16, "regular 32-point buttons use `_32`")
        check(Chrome.navigationGlyphPointSize(buttonSide: 28) == 14, "narrow 28-point buttons use `_28`")
        let lights = CGSize(width: 60, height: 14)
        let developer = Chrome.toolbar(width: 228, windowButtons: lights, showsNavigation: true, developerReload: true)
        check(developer.reload.map { Chrome.navigationGlyphPointSize(buttonSide: $0.height) } == 16, "the 19-point thin reload stays 16")
        let narrow = Chrome.toolbar(width: 200, windowButtons: lights, showsNavigation: true)
        check(narrow.back.map { Chrome.navigationGlyphPointSize(buttonSide: $0.height) } == 14, "the narrow row draws 14-point glyphs")
        check(Chrome.addressFontSize == 13 && Chrome.addressTextIndent == 12, "CommandBarPlaceholderTextView 13 points")

        let regular = NavigationControlArtwork.symbol("arrow.left", pointSize: 16)
        let small = NavigationControlArtwork.symbol("arrow.left", pointSize: 14)
        check(regular?.isTemplate == true && regular?.representations.count == 2, "1x and 2x template")
        check(regular.map { $0.size.width == $0.size.width.rounded() && $0.size.height == $0.size.height.rounded() } == true,
              "whole-point frame")
        check((small?.size.width ?? 99) < (regular?.size.width ?? 0), "14 points draws smaller than 16")
        check(NavigationControlArtwork.symbol("arrow.left", pointSize: 16) === regular, "cached per symbol and size")

        let light = TranslucentButtonColors.standard(dark: false), dark = TranslucentButtonColors.standard(dark: true)
        check(gray(light.foreground, white: 0, alpha: 0.565) && gray(dark.foreground, white: 1, alpha: 0.592), "GrayA11 rest")
        check(gray(light.disabledForeground, white: 0, alpha: 0.220) && gray(dark.disabledForeground, white: 1, alpha: 0.249), "GrayA8 disabled")
        check(gray(light.hoveredBackground, white: 0, alpha: 0.071) && gray(dark.hoveredBackground, white: 1, alpha: 0.077), "GrayA4 hover")
        check(gray(light.pressedBackground, white: 0, alpha: 0.090) && gray(dark.pressedBackground, white: 1, alpha: 0.103), "GrayA5 pressed")
        check(gray(light.pressedForeground, white: 0, alpha: 0.910) && gray(dark.pressedForeground, white: 1, alpha: 0.923), "GrayA12 pressed")
        check(light.background(hovered: true, pressed: true, enabled: false) == light.disabledBackground, "disabled wins")

        check(TranslucentButtonFace.cornerRadius == 6 && TranslucentButtonFace.pressedScale == 0.95, "6-point corners, 0.95 press")
        check(TranslucentButtonFace.pressResponse == 0.3 && TranslucentButtonFace.pressDamping == 0.6, "press spring")
        check(TranslucentButtonFace.hoverDuration == 0.1, "0.1 s ease-in hover")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        view.appearance = NSAppearance(named: .aqua)
        let face = TranslucentButtonFace(view: view)
        func drawFace() -> (fill: CGFloat, edge: CGFloat, tint: NSColor?) {
            var tint: NSColor?
            let rep = render(view.bounds.size) { face.draw(in: view.bounds, enabled: true, view: view) { tint = $0 } }
            return (rep.colorAt(x: 32, y: 32)!.alphaComponent, rep.colorAt(x: 0, y: 32)!.alphaComponent, tint)
        }
        check(drawFace().fill < 0.01 && face.pressProgress == 0, "starts at rest")
        check(gray(face.foreground(enabled: true, in: view), white: 0, alpha: 0.565), "rest foreground GrayA11")
        check(gray(face.foreground(enabled: false, in: view), white: 0, alpha: 0.220), "disabled foreground GrayA8")
        face.setHovered(true)
        check(near(drawFace().fill, 0.071, 0.01), "windowless hover is immediate")
        face.setPressed(true)
        check(face.pressProgress == 1, "windowless press is immediate")
        check(gray(face.foreground(enabled: true, in: view), white: 0, alpha: 0.910), "pressed foreground GrayA12")
        check(gray(face.foreground(enabled: false, in: view), white: 0, alpha: 0.220), "disabled ignores the press")
        view.appearance = NSAppearance(named: .darkAqua)
        check(gray(face.foreground(enabled: true, in: view), white: 1, alpha: 0.923), "Dark Aqua resolves white")
        view.appearance = NSAppearance(named: .aqua)
        face.setPressed(false); face.setHovered(false)
        check(face.pressProgress == 0 && drawFace().fill < 0.01, "release returns to rest")
        let half = TranslucentButtonFace.blend(.clear, light.hoveredBackground, 0.5)
        check(gray(half, white: 0, alpha: 0.0355), "a clear end blends alpha only")
        check(TranslucentButtonFace.easeIn(0) == 0 && TranslucentButtonFace.easeIn(1) == 1, "ease-in ends")
        check(near(TranslucentButtonFace.easeIn(0.5), 0.3153, 0.001), "CAMediaTimingFunction easeIn midpoint")

        face.setHovered(true); face.setPressed(true)
        let pressed = drawFace()
        check(near(pressed.fill, 0.090, 0.01), "pressed GrayA5 fill")
        check(pressed.edge < 0.01, "0.95 press scale leaves the edge clear")
        check(pressed.tint.map { gray($0, white: 0, alpha: 0.910) } == true, "the glyph closure receives GrayA12")

        check(ReloadGlyph.pressedRotation == .pi / 2 && ReloadGlyph.pressedOffset == 1, "reload press transform")
        let glyph = ReloadGlyph(view: view, pointSize: 16, rasterized: true)
        func reloadInkWidth() -> Int {
            let ink = inkBounds(render(view.bounds.size) { glyph.draw(in: view.bounds, tint: .black, in: view) })
            return ink.maxX - ink.minX
        }
        let regularWidth = reloadInkWidth()
        glyph.pointSize = 14
        check(regularWidth > 0 && reloadInkWidth() < regularWidth, "narrow reload re-renders at 14 points")

        check(SidebarAddressPillView.cornerRadius == 12 && SidebarAddressPillView.hoverDuration == 0.12, "12 points, 0.12 s")
        func p3(_ color: NSColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
            let c = color.usingColorSpace(.displayP3)!
            return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        }
        let rest = p3(SidebarAddressPillView.fill(dark: false, hovered: false))
        check(near(rest.0, 0.055) && near(rest.1, 0.059) && near(rest.2, 0.063) && near(rest.3, 0.05), "SidebarItemBackground light")
        check(near(p3(SidebarAddressPillView.fill(dark: false, hovered: true)).3, 0.1), "SidebarItemHoveredBackground light")
        let darkRest = p3(SidebarAddressPillView.fill(dark: true, hovered: false))
        check(near(darkRest.0, 0.98) && near(darkRest.2, 1) && near(darkRest.3, 0.1), "SidebarItemBackground dark")
        check(near(p3(SidebarAddressPillView.fill(dark: true, hovered: true)).3, 0.15), "SidebarItemHoveredBackground dark")
        let pill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 212, height: 36))
        check(pill.layer?.cornerRadius == 12 && pill.layer?.cornerCurve == .continuous && pill.layer?.masksToBounds == true,
              "continuous 12-point mask")
        check(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: false, hovered: false).cgColor, "rest fill")
        pill.setHovered(true)
        check(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: false, hovered: true).cgColor, "hover fill")
        pill.dark = true
        check(pill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: true, hovered: true).cgColor, "dark follows the palette")
        check(pill.hitTest(NSPoint(x: 10, y: 10)) == nil, "the surface takes no clicks")

        for hovered in [false, true] { for menu in [false, true] { for anchored in [false, true] { for voiceOver in [false, true] {
            check(SidebarAddressButtonsReveal.revealed(sidebarHovered: hovered, showingMenu: menu, anchored: anchored,
                                                       voiceOverRunning: voiceOver)
                  == (hovered || menu || !anchored || voiceOver), "reveal predicate \(hovered) \(menu) \(anchored) \(voiceOver)")
        } } } }
        check(SidebarAddressButtonsReveal.revealed(sidebarHovered: false, showingMenu: false, anchored: true, voiceOverRunning: true),
              "VoiceOver keeps the docked sidebar's buttons revealed with the pointer elsewhere")
        check(SidebarAddressButtonsReveal.extensionPopupLoading(attached: false, visible: false, showsPage: true),
              "a popup window still loading its page, unattached and unseen, counts as open")
        check(!SidebarAddressButtonsReveal.extensionPopupLoading(attached: true, visible: false, showsPage: true),
              "a popup attached to its browser window is open, not loading")
        check(!SidebarAddressButtonsReveal.extensionPopupLoading(attached: false, visible: true, showsPage: true),
              "a visible window detached from its browser window is not loading")
        check(!SidebarAddressButtonsReveal.extensionPopupLoading(attached: false, visible: false, showsPage: false),
              "a hidden window without an attached popup page, such as a closed popup, is not loading")
        check(!SidebarAddressButtonsReveal.showsSiteControlCenter(revealed: false, copyQuoteLink: false), "idle hides Site Control Center")
        check(SidebarAddressButtonsReveal.showsSiteControlCenter(revealed: false, copyQuoteLink: true), "a quote link keeps it")
        check(SidebarAddressButtonsReveal.showsSiteControlCenter(revealed: true, copyQuoteLink: false), "revealed shows it")
        check(SidebarAddressButtonsReveal.fadeDuration == 0.15, "0.15 s ease-out fade")
        let button = NSView(frame: NSRect(x: 0, y: 0, width: 25, height: 28))
        SidebarAddressButtonsReveal.apply(false, to: button, animated: true)
        check(button.alphaValue == 0 && !button.isHidden, "windowless hide is immediate and keeps the view in the tree")
        SidebarAddressButtonsReveal.apply(true, to: button, animated: true)
        check(button.alphaValue == 1, "reveal restores full opacity")

        let toolbar = ReloadGlyph(view: view, pointSize: ReloadGlyph.toolbarPointSize, rasterized: false)
        let flipped = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        func reloadAlpha(_ glyph: ReloadGlyph, _ tint: NSColor) -> CGFloat {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 56, pixelsHigh: 56, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = flipped.bounds.size
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            glyph.draw(in: flipped.bounds, tint: tint, in: flipped)
            NSGraphicsContext.restoreGraphicsState()
            return maxAlpha(rep)
        }
        check(reloadAlpha(toolbar, .black) > 0.97, "enabled toolbar reload is opaque")
        check(near(reloadAlpha(toolbar, NSColor(white: 0, alpha: 0.5)), 0.5, 0.02), "disabled toolbar reload is a true half alpha")
        let sidebarReload = ReloadGlyph(view: flipped, pointSize: 16, rasterized: true)
        check(near(reloadAlpha(sidebarReload, NSColor(white: 0, alpha: 0.565)), 0.565, 0.02), "GrayA11 reload keeps its alpha")
        check(near(reloadAlpha(sidebarReload, NSColor(white: 0, alpha: 0.910)), 0.910, 0.02), "GrayA12 reload keeps its alpha")

        let backButton = NavigationControlButton("Go back", symbol: "arrow.left", history: true, glyphPointSize: 16)
        backButton.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        backButton.appearance = NSAppearance(named: .aqua)
        let restRep = capture(backButton)
        check(near(maxAlpha(restRep), 0.565, 0.03), "arrow at rest is GrayA11")
        backButton.isEnabled = false
        check(near(maxAlpha(capture(backButton)), 0.220, 0.03), "disabled arrow is GrayA8")
        backButton.isEnabled = true
        backButton.isHighlighted = true
        let pressedRep = capture(backButton)
        check(near(maxAlpha(pressedRep), 0.910, 0.03), "pressed arrow is GrayA12 over GrayA5")
        let shift = inkBounds(pressedRep, threshold: 0.5).minX - inkBounds(restRep, threshold: 0.5).minX
        check(shift < 0 && shift >= -6, "pressed Back moves left (3 points, scaled 0.95 about the centre)")
        let toolbarButton = NavigationControlButton("Go back", symbol: "arrow.left", history: true)
        toolbarButton.frame = backButton.frame; toolbarButton.appearance = NSAppearance(named: .aqua)
        toolbarButton.contentTintColor = .black
        check(maxAlpha(capture(toolbarButton)) > 0.97, "the toolbar's arrow keeps its opaque tint")

        let chevron = NavigationControlButton("Reload options", symbol: "chevron.down")
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Refresh options button")
        chevron.windowControlStyle = true
        chevron.frame = NSRect(x: 0, y: 0, width: 14, height: 32)
        chevron.appearance = NSAppearance(named: .aqua)
        let chevronRest = capture(chevron)
        check(near(maxAlpha(chevronRest), 0.565, 0.03), "chevron GrayA11 at rest")
        check(chevronRest.colorAt(x: 4, y: 8)!.alphaComponent < 0.01, "no fill at rest")
        let enter = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        chevron.mouseEntered(with: enter)
        check(near(capture(chevron).colorAt(x: 4, y: 8)!.alphaComponent, 0.071, 0.01), "GrayA4 fill while hovered")
        chevron.isHighlighted = true
        check(near(maxAlpha(capture(chevron)), 0.910, 0.03), "chevron GrayA12 while pressed")
        chevron.isHighlighted = false; chevron.isEnabled = false
        check(capture(chevron).colorAt(x: 4, y: 8)!.alphaComponent < 0.01, "no hover fill while disabled")

        let plateView = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        plateView.appearance = NSAppearance(named: .aqua)
        let plateFace = TranslucentButtonFace(view: plateView)
        plateFace.setHovered(true)
        let plate = render(plateView.bounds.size) { plateFace.draw(in: plateView.bounds, enabled: true, view: plateView) { _ in } }
        func reference(_ style: RoundedCornerStyle) -> NSBitmapImageRep {
            render(plateView.bounds.size) {
                light.hoveredBackground.setFill()
                let context = NSGraphicsContext.current!.cgContext
                context.addPath(Path(roundedRect: plateView.bounds, cornerRadius: 6, style: style).cgPath); context.fillPath()
            }
        }
        func alphaDelta(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> CGFloat {
            var worst: CGFloat = 0
            for y in 0..<a.pixelsHigh { for x in 0..<a.pixelsWide {
                worst = max(worst, abs(a.colorAt(x: x, y: y)!.alphaComponent - b.colorAt(x: x, y: y)!.alphaComponent)) } }
            return worst
        }
        check(alphaDelta(plate, reference(.continuous)) < 0.005, "continuous 6-point plate")
        check(alphaDelta(plate, reference(.circular)) > 0.01, "not circular corners")

        let faced = ActionButton("Hide sidebar")
        faced.frame = NSRect(x: 0, y: 0, width: 32, height: 32); faced.appearance = NSAppearance(named: .aqua)
        faced.translucentFace = TranslucentButtonFace(view: faced)
        faced.mouseEntered(with: enter)
        check(near(capture(faced).colorAt(x: 32, y: 32)!.alphaComponent, 0.071, 0.01), "hovering the button hovers its face")
        faced.refreshHover()
        check(capture(faced).colorAt(x: 32, y: 32)!.alphaComponent < 0.01, "refreshHover clears the face without a window")

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        let pageButton = ActionButton("Site Control Center")
        pageButton.frame = NSRect(x: 10, y: 5, width: 25, height: 28); host.addSubview(pageButton)
        let toolbarView = ExtensionToolbarView(frame: NSRect(x: 40, y: 5, width: 56, height: 28)); host.addSubview(toolbarView)
        pageButton.alphaValue = 0; toolbarView.alphaValue = 0
        check(pageButton.hitTest(NSPoint(x: 20, y: 15)) === pageButton, "transparent ActionButtons hit-test by default")
        check(toolbarView.hitTest(NSPoint(x: 60, y: 15)) === toolbarView, "transparent extension toolbars hit-test by default")
        pageButton.hitTestsWhenTransparent = false; toolbarView.hitTestsWhenTransparent = false
        check(pageButton.hitTest(NSPoint(x: 20, y: 15)) == nil, "a faded Site Control Center button passes clicks through")
        check(toolbarView.hitTest(NSPoint(x: 60, y: 15)) == nil, "faded pinned extensions pass clicks through")
        pageButton.alphaValue = 1; toolbarView.alphaValue = 1
        check(pageButton.hitTest(NSPoint(x: 20, y: 15)) === pageButton && toolbarView.hitTest(NSPoint(x: 60, y: 15)) === toolbarView,
              "revealed buttons take clicks")

        let quotePill = SidebarAddressPillView(frame: NSRect(x: 0, y: 0, width: 200, height: 18))
        let hoverFill = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4)
        quotePill.style = .sharedQuote(fill: hoverFill)
        check(quotePill.layer?.cornerRadius == 7 && quotePill.layer?.cornerCurve == .circular, "earlier 7-point corners")
        check(quotePill.layer?.backgroundColor == hoverFill.cgColor, "the theme's hover fill")
        quotePill.setHovered(true)
        check(quotePill.layer?.backgroundColor == hoverFill.cgColor, "no URL bar hover in shared-quote mode")
        quotePill.style = .urlBar
        check(quotePill.layer?.cornerRadius == 12 && quotePill.layer?.cornerCurve == .continuous
              && quotePill.layer?.backgroundColor == SidebarAddressPillView.fill(dark: false, hovered: true).cgColor, "back to the URL bar")
        let center = NotificationCenter.default
        var ended = 0
        let hold = AddressPopoverRevealHold { ended += 1 }
        let prompt = NSPopover(), other = NSPopover()
        center.post(name: NSPopover.willShowNotification, object: prompt)
        center.post(name: NSPopover.willShowNotification, object: other)
        center.post(name: NSPopover.didCloseNotification, object: other)
        check(ended == 0, "another popover closing keeps the hold")
        center.post(name: NSPopover.didCloseNotification, object: prompt)
        check(ended == 1, "the prompt closing ends the hold")
        var unshown = 0
        let fallback = AddressPopoverRevealHold { unshown += 1 }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        check(unshown == 1 && ended == 1, "a prompt that never shows ends its hold on the next turn, once")
        center.post(name: NSPopover.willShowNotification, object: prompt)
        center.post(name: NSPopover.didCloseNotification, object: prompt)
        check(unshown == 1 && ended == 1, "ended holds ignore later popovers")
        withExtendedLifetime((hold, fallback)) {}

        func window() -> NSWindow {
            let result = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled, .closable],
                                  backing: .buffered, defer: true)
            result.isReleasedWhenClosed = false
            return result
        }
        let popupWindow = window(), otherWindow = window(), browserWindow = window()
        browserWindow.addChildWindow(popupWindow, ordered: .above)
        check(SidebarAddressButtonsReveal.holdsExtensionPopup(popupWindow, of: browserWindow, showsPage: true, atSidebar: true),
              "a page popup in this browser window placed at the sidebar takes a hold")
        check(!SidebarAddressButtonsReveal.holdsExtensionPopup(popupWindow, of: browserWindow, showsPage: false, atSidebar: true),
              "a child window without a page, such as a popover or the history list, takes no hold")
        check(!SidebarAddressButtonsReveal.holdsExtensionPopup(popupWindow, of: browserWindow, showsPage: true, atSidebar: false),
              "a popup placed away from the sidebar takes no hold")
        check(!SidebarAddressButtonsReveal.holdsExtensionPopup(otherWindow, of: browserWindow, showsPage: true, atSidebar: true),
              "another window's popup takes no hold")
        check(SidebarAddressButtonsReveal.extensionPopupOpen(popupWindow, of: browserWindow), "an attached popup is open")
        check(!SidebarAddressButtonsReveal.extensionPopupOpen(popupWindow, of: nil), "a popup whose browser window is gone is not")
        browserWindow.removeChildWindow(popupWindow)
        check(!SidebarAddressButtonsReveal.extensionPopupOpen(popupWindow, of: browserWindow),
              "a popup the engine detached from its browser window is closed")
        var popupOpen = true, popupEnded = 0
        let popupHold = AddressPopoverRevealHold(window: popupWindow, isOpen: { $0 === popupWindow && popupOpen }) { popupEnded += 1 }
        center.post(name: NSWindow.didResignKeyNotification, object: popupWindow)
        popupHold.endIfWindowClosed()
        check(popupEnded == 0, "an extension popup that loses focus but stays open keeps its hold")
        center.post(name: NSWindow.didResignKeyNotification, object: otherWindow)
        center.post(name: NSWindow.willCloseNotification, object: otherWindow)
        check(popupEnded == 0, "another window resigning or closing keeps the popup's hold")
        popupOpen = false
        center.post(name: NSWindow.didResignKeyNotification, object: popupWindow)
        check(popupEnded == 1, "a popup detached from its browser window ends its hold as it loses focus")
        center.post(name: NSWindow.willCloseNotification, object: popupWindow)
        popupHold.endIfWindowClosed()
        check(popupEnded == 1, "a popup hold ends once")
        var closedEnded = 0
        let closingHold = AddressPopoverRevealHold(window: popupWindow, isOpen: { _ in true }) { closedEnded += 1 }
        center.post(name: NSWindow.willCloseNotification, object: popupWindow)
        check(closedEnded == 1, "closing the popup ends its hold whatever closed it")
        var sweptEnded = 0
        let sweptHold = AddressPopoverRevealHold(window: popupWindow, isOpen: { _ in false }) { sweptEnded += 1 }
        sweptHold.endIfWindowClosed()
        check(sweptEnded == 1, "a sweep ends a hold whose popup is no longer open")
        var panelEnded = 0
        let panelHold = AddressPopoverRevealHold { panelEnded += 1 }
        let panel = NSPopover()
        center.post(name: NSPopover.willShowNotification, object: panel)
        panelHold.endIfWindowClosed()
        check(panelEnded == 0, "a popup sweep leaves the site panel's popover hold alone")
        center.post(name: NSPopover.didCloseNotification, object: panel)
        check(panelEnded == 1, "the site panel closing ends its hold")
        withExtendedLifetime((closingHold, sweptHold)) {}

        var holders = Set<ObjectIdentifier>()
        func shown(voiceOver: Bool = false) -> Bool {
            SidebarAddressButtonsReveal.revealed(sidebarHovered: false, showingMenu: !holders.isEmpty, anchored: true,
                                                 voiceOverRunning: voiceOver)
        }
        func holdButtons(_ owner: AnyObject, _ make: (@escaping () -> Void) -> AddressPopoverRevealHold) -> AddressPopoverRevealHold {
            holders.insert(ObjectIdentifier(owner))
            return make { holders.remove(ObjectIdentifier(owner)) }
        }
        check(!shown(), "a docked sidebar hides its buttons with the pointer away and nothing open")
        var extensionOpen = true
        let extensionHold = holdButtons(popupWindow) { AddressPopoverRevealHold(window: popupWindow, isOpen: { _ in extensionOpen }, onEnd: $0) }
        check(shown(), "an open extension popup keeps the buttons revealed with the pointer inside it")
        let sitePanel = NSPopover(), sitePanelOwner = NSObject()
        let siteHold = holdButtons(sitePanelOwner) { AddressPopoverRevealHold(onEnd: $0) }
        center.post(name: NSPopover.willShowNotification, object: sitePanel)
        center.post(name: NSPopover.didCloseNotification, object: sitePanel)
        check(shown(), "closing the site panel leaves the popup's hold in place")
        extensionOpen = false
        center.post(name: NSWindow.didResignKeyNotification, object: popupWindow)
        check(!shown(), "the buttons fade once the popup closes")
        check(shown(voiceOver: true), "VoiceOver still reveals them after every hold ends")
        withExtendedLifetime((extensionHold, siteHold)) {}

        print("SidebarHeaderGlyphs checks: \(count) passed")
    }
}
