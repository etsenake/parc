import AppKit
import Testing
import ParcCore
@testable import Parc

@MainActor
private final class EditorCanvas {
    let editor: SpaceThemeEditorView
    let dark = NSAppearance(named: .darkAqua)!
    let light = NSAppearance(named: .aqua)!

    init(theme: SpaceTheme = EditorCanvas.mint) {
        _ = NSApplication.shared
        editor = SpaceThemeEditorView(theme: theme, performHapticFeedback: {}, resources: ThemeEditorResources(bundle: .module))
        editor.appearance = dark
        editor.frame = NSRect(x: 0, y: 0, width: 356, height: 508)
        editor.layoutSubtreeIfNeeded()
    }

    nonisolated static var mint: SpaceTheme {
        var theme = SpaceTheme.singleColor(ThemeColor(red: 0.69, green: 1, blue: 0.85)!)
        theme.noise = 0.25
        theme.intensity = 0.5
        return theme
    }

    func control(_ label: String) throws -> NSView {
        try #require(editor.subviews.first { $0.accessibilityLabel() == label })
    }

    func marker() throws -> NSView {
        try #require(editor.subviews.first { $0.identifier?.rawValue == "ThemeNoiseMarker" })
    }

    func snapshot(_ view: NSView, _ appearance: NSAppearance? = nil) throws -> NSBitmapImageRep {
        let appearance = appearance ?? dark
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
                                                pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = view.bounds.size
        editor.appearance = appearance
        defer { editor.appearance = dark }
        appearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
        return rep
    }

    func pixel(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) throws -> NSColor {
        try #require(rep.colorAt(x: Int((x * 2).rounded(.down)), y: Int((y * 2).rounded(.down))))
    }

    func rgb(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) throws -> NSColor {
        try #require(try pixel(rep, x, y).usingColorSpace(.deviceRGB))
    }

    func strongest(_ rep: NSBitmapImageRep) throws -> NSColor {
        var best = NSColor.clear
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let color = try #require(rep.colorAt(x: x, y: y))
                if color.alphaComponent > best.alphaComponent { best = color }
            }
        }
        return try #require(best.usingColorSpace(.deviceRGB))
    }

    func mouseMoved(_ view: NSView, at point: NSPoint) throws {
        view.mouseMoved(with: try #require(NSEvent.mouseEvent(with: .mouseMoved, location: view.convert(point, to: nil),
                                                             modifierFlags: [], timestamp: 30, windowNumber: 0, context: nil,
                                                             eventNumber: 0, clickCount: 0, pressure: 0)))
    }

    func enterExit(_ type: NSEvent.EventType) throws -> NSEvent {
        try #require(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 30, windowNumber: 0,
                                            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
    }
}

struct SpaceThemeDialPresentationTests {
    @MainActor private func slot(_ index: Int, in rep: NSBitmapImageRep, of dial: NSView, canvas: EditorCanvas) throws -> NSColor {
        let angle = (90 + Double(index) * 18) * .pi / 180
        return try canvas.pixel(rep, dial.bounds.midX + cos(angle) * 32, dial.bounds.midY + sin(angle) * 32)
    }

    @Test @MainActor func theDialLeavesItsBottomDotSlotEmpty() throws {
        let canvas = EditorCanvas()
        let dial = try canvas.control("Theme texture and noise")
        #expect(try slot(0, in: try canvas.snapshot(dial), of: dial, canvas: canvas).alphaComponent < 0.02)
    }

    @Test @MainActor func theDialDrawsTheOtherNineteenDots() throws {
        let canvas = EditorCanvas()
        let dial = try canvas.control("Theme texture and noise")
        let image = try canvas.snapshot(dial)
        for index in 1..<20 {
            #expect(try slot(index, in: image, of: dial, canvas: canvas).alphaComponent > 0.1, "dot \(index)")
        }
    }

    @Test @MainActor func litDotsDrawTheForegroundOverTheSeparatorDot() throws {
        let canvas = EditorCanvas()
        let dial = try canvas.control("Theme texture and noise")
        let image = try canvas.snapshot(dial)
        for index in 10...14 {
            let alpha = try slot(index, in: image, of: dial, canvas: canvas).alphaComponent
            #expect(alpha > 0.52 && alpha < 0.55, "dot \(index)")
        }
    }

    @Test @MainActor func theRemainingDotsUseTheSeparatorColor() throws {
        let canvas = EditorCanvas()
        let dial = try canvas.control("Theme texture and noise")
        let image = try canvas.snapshot(dial)
        for index in Array(1...9) + Array(16...19) {
            let alpha = try slot(index, in: image, of: dial, canvas: canvas).alphaComponent
            #expect(alpha > 0.1 && alpha < 0.2, "dot \(index)")
        }
    }

    @Test @MainActor func theIndicatorDrawsInItsOwnNonInteractiveLayerBeyondTheDial() throws {
        let canvas = EditorCanvas()
        let dial = try canvas.control("Theme texture and noise"), marker = try canvas.marker()
        #expect(marker.frame == dial.frame.insetBy(dx: -8, dy: -8))
        #expect(marker.hitTest(NSPoint(x: marker.frame.midX, y: marker.frame.midY)) == nil)
    }

    @Test(arguments: [false, true])
    @MainActor func theIndicatorIsAWhiteCapsuleExtendingRadially(lightAppearance: Bool) throws {
        let canvas = EditorCanvas()
        let marker = try canvas.marker()
        let image = try canvas.snapshot(marker, lightAppearance ? canvas.light : canvas.dark)
        let indicator = try canvas.rgb(image, marker.bounds.midX + 38, marker.bounds.midY)
        #expect(indicator.alphaComponent > 0.95 && indicator.redComponent > 0.95)
    }

    @Test @MainActor func theIndicatorCapsuleIsEightPointsWide() throws {
        let canvas = EditorCanvas()
        let marker = try canvas.marker()
        let image = try canvas.snapshot(marker)
        #expect(try canvas.pixel(image, marker.bounds.midX + 32, marker.bounds.midY + 6).alphaComponent < 0.3)
    }

    @Test @MainActor func theDialItselfNoLongerDrawsTheIndicator() throws {
        let canvas = EditorCanvas()
        let dial = try canvas.control("Theme texture and noise")
        #expect(try canvas.pixel(try canvas.snapshot(dial), dial.bounds.midX + 38, dial.bounds.midY).alphaComponent < 0.02)
    }

    @Test @MainActor func theKnobTextureDrawsAtTheReducedOpacity() throws {
        let canvas = EditorCanvas()
        let dial = try canvas.control("Theme texture and noise")
        let disc = try canvas.pixel(try canvas.snapshot(dial), dial.bounds.midX + 12, dial.bounds.midY).alphaComponent
        #expect(disc > 0.15 && disc < 0.45)
    }

    @Test @MainActor func theKnobDiscIsFortyPointsAcross() throws {
        let canvas = EditorCanvas()
        let dial = try canvas.control("Theme texture and noise")
        #expect(try canvas.pixel(try canvas.snapshot(dial), dial.bounds.midX, dial.bounds.midY - 24).alphaComponent < 0.02)
    }

    @Test @MainActor func aquaSeparatorDotsAreBlackAtFifteenPercent() throws {
        let canvas = EditorCanvas()
        let dial = try canvas.control("Theme texture and noise")
        let dot = try #require(try slot(1, in: try canvas.snapshot(dial, canvas.light), of: dial, canvas: canvas).usingColorSpace(.deviceRGB))
        #expect(dot.alphaComponent > 0.1 && dot.alphaComponent < 0.2)
        #expect(dot.redComponent < 0.1)
    }

    @Test @MainActor func aquaLitDotsComposeBlackThirtyPercentOverFifteen() throws {
        let canvas = EditorCanvas()
        let dial = try canvas.control("Theme texture and noise")
        let lit = try canvas.rgb(try canvas.snapshot(dial, canvas.light), dial.bounds.midX, dial.bounds.midY - 32)
        #expect(lit.alphaComponent > 0.39 && lit.alphaComponent < 0.42)
        #expect(lit.redComponent < 0.1)
    }

    @Test @MainActor func hoverZoomsTheKnobTexture() throws {
        let canvas = EditorCanvas()
        let dial = try canvas.control("Theme texture and noise")
        let center = NSPoint(x: dial.bounds.midX, y: dial.bounds.midY)
        let resting = try canvas.snapshot(dial)
        try canvas.mouseMoved(dial, at: center)
        let hovered = try canvas.snapshot(dial)
        let changed = try (0..<8).contains {
            let x = center.x + 2 + CGFloat($0) * 2
            return try canvas.pixel(hovered, x, center.y) != canvas.pixel(resting, x, center.y)
        }
        #expect(changed)
    }

    @Test @MainActor func hoverKeepsTheFortyPointKnobCircle() throws {
        let canvas = EditorCanvas()
        let dial = try canvas.control("Theme texture and noise")
        try canvas.mouseMoved(dial, at: NSPoint(x: dial.bounds.midX, y: dial.bounds.midY))
        #expect(try canvas.pixel(try canvas.snapshot(dial), dial.bounds.midX, dial.bounds.midY - 24).alphaComponent < 0.02)
    }
}

struct SpaceThemeChevronPresentationTests {
    @MainActor private func chevrons(_ canvas: EditorCanvas) throws -> (previous: NSButton, next: NSButton) {
        (try #require(try canvas.control("Previous color presets") as? NSButton),
         try #require(try canvas.control("Next color presets") as? NSButton))
    }

    @Test @MainActor func theFirstPresetPageDisablesOnlyPrevious() throws {
        let buttons = try chevrons(EditorCanvas())
        #expect(!buttons.previous.isEnabled && buttons.next.isEnabled)
    }

    @Test @MainActor func aDisabledChevronDrawsAtAThirdOfTheEnabledOpacity() throws {
        let canvas = EditorCanvas()
        let buttons = try chevrons(canvas)
        let dimming = try canvas.strongest(try canvas.snapshot(buttons.previous)).alphaComponent
            / canvas.strongest(try canvas.snapshot(buttons.next)).alphaComponent
        #expect(dimming > 0.3 && dimming < 0.37)
    }

    @Test @MainActor func theChevronKeepsAThirtyTwoPointFrame() throws {
        #expect(try chevrons(EditorCanvas()).previous.frame.size == NSSize(width: 32, height: 32))
    }

    @Test(arguments: [false, true])
    @MainActor func theChevronDrawsTheLabelColorAtSixtyPercent(lightAppearance: Bool) throws {
        let canvas = EditorCanvas()
        let ink = try canvas.strongest(try canvas.snapshot(try chevrons(canvas).next, lightAppearance ? canvas.light : canvas.dark))
        #expect(ink.alphaComponent > 0.46 && ink.alphaComponent < 0.53)
        #expect(lightAppearance ? ink.redComponent < 0.1 : ink.redComponent > 0.9)
    }

    @Test @MainActor func aHoveredChevronFillsItsFrameWithTheSecondaryTint() throws {
        let canvas = EditorCanvas()
        let next = try chevrons(canvas).next
        next.mouseEntered(with: try canvas.enterExit(.mouseEntered))
        let fill = try canvas.pixel(try canvas.snapshot(next), 1, 16).alphaComponent
        #expect(fill > 0.05 && fill < 0.16)
    }

    @Test @MainActor func theHoverFillKeepsTheEightPointCorner() throws {
        let canvas = EditorCanvas()
        let next = try chevrons(canvas).next
        next.mouseEntered(with: try canvas.enterExit(.mouseEntered))
        #expect(try canvas.pixel(try canvas.snapshot(next), 0.5, 0.5).alphaComponent < 0.02)
    }

    @Test @MainActor func aDisabledChevronShowsNoHoverFill() throws {
        let canvas = EditorCanvas()
        let previous = try chevrons(canvas).previous
        previous.mouseEntered(with: try canvas.enterExit(.mouseEntered))
        #expect(try canvas.pixel(try canvas.snapshot(previous), 1, 16).alphaComponent < 0.01)
    }

    @Test @MainActor func theHoverFillClearsOnExit() throws {
        let canvas = EditorCanvas()
        let next = try chevrons(canvas).next
        next.mouseEntered(with: try canvas.enterExit(.mouseEntered))
        next.mouseExited(with: try canvas.enterExit(.mouseExited))
        #expect(try canvas.pixel(try canvas.snapshot(next), 1, 16).alphaComponent < 0.01)
    }
}

struct SpaceThemeSliderAndSwatchPresentationTests {
    private static let leading = 20 + 6.0332 * 1.5 * .pi
    private static let trailing = 20 + 6.0332 * 9.5 * .pi

    @Test @MainActor func theIntensitySliderSharesTheDialsCenterLine() throws {
        #expect(try EditorCanvas().control("Theme intensity").frame == NSRect(x: 6, y: 412, width: 248, height: 80))
    }

    @Test @MainActor func theSliderThumbIsWhite() throws {
        let canvas = EditorCanvas()
        let slider = try canvas.control("Theme intensity")
        let thumb = try canvas.pixel(try canvas.snapshot(slider), 20 + 208 * 0.5, slider.bounds.midY)
        #expect(thumb.alphaComponent > 0.95 && thumb.redComponent > 0.95)
    }

    @Test @MainActor func onlyTheLeadingSideDrawsTheHalfOpacityTrack() throws {
        let canvas = EditorCanvas()
        let slider = try canvas.control("Theme intensity")
        let image = try canvas.snapshot(slider)
        let track = try canvas.pixel(image, Self.leading, slider.bounds.midY).alphaComponent
        #expect(track > 0.04 && track < 0.12)
        #expect(try canvas.pixel(image, Self.trailing, slider.bounds.midY).alphaComponent < 0.02)
    }

    @Test @MainActor func theWaveUsesTheForegroundBeforeTheThumbAndTheSeparatorAfter() throws {
        let canvas = EditorCanvas()
        let slider = try canvas.control("Theme intensity")
        let image = try canvas.snapshot(slider)
        let lit = try canvas.pixel(image, Self.leading, slider.bounds.midY + 7.5).alphaComponent
        let unlit = try canvas.pixel(image, Self.trailing, slider.bounds.midY + 7.5).alphaComponent
        #expect(lit > 0.52 && lit < 0.62)
        #expect(unlit > 0.1 && unlit < 0.2)
    }

    @Test @MainActor func aPresetSwatchKeepsItsTwentyFourPointFrame() throws {
        #expect(try EditorCanvas().control("Brand color 1").frame.size == NSSize(width: 24, height: 24))
    }

    @Test @MainActor func thePresetColorReachesTheFrameEdge() throws {
        let canvas = EditorCanvas()
        let swatch = try canvas.control("Brand color 1")
        #expect(try canvas.pixel(try canvas.snapshot(swatch), 0.75, 12).alphaComponent > 0.8)
    }

    @Test @MainActor func aTwoPointInnerBorderDarkensTheEdge() throws {
        let canvas = EditorCanvas()
        let image = try canvas.snapshot(try canvas.control("Brand color 1"))
        let fill = try canvas.rgb(image, 12, 12), border = try canvas.rgb(image, 1.25, 12)
        #expect(border.greenComponent < fill.greenComponent * 0.95 && border.greenComponent > fill.greenComponent * 0.8)
    }

    @MainActor private func padAlphaRange(_ canvas: EditorCanvas) throws -> (lowest: CGFloat, highest: CGFloat) {
        let image = try canvas.snapshot(try canvas.control("Theme color pad"))
        var lowest = CGFloat(1), highest = CGFloat(0)
        for y in stride(from: CGFloat(100), to: 116, by: 0.5) {
            for x in stride(from: CGFloat(4), to: 20, by: 0.5) {
                let alpha = try canvas.pixel(image, x, y).alphaComponent
                lowest = min(lowest, alpha)
                highest = max(highest, alpha)
            }
        }
        return (lowest, highest)
    }

    @Test @MainActor func thePadFillIsThePrimaryColorAtFivePercent() throws {
        let lowest = try padAlphaRange(EditorCanvas(theme: SpaceTheme())).lowest
        #expect(lowest > 0.03 && lowest < 0.06)
    }

    @Test @MainActor func thePadGridDrawsAtFortyPercent() throws {
        #expect(try padAlphaRange(EditorCanvas(theme: SpaceTheme())).highest > 0.2)
    }

    @Test @MainActor func thePadClipsToAnEightPointContinuousCorner() throws {
        let pad = try EditorCanvas(theme: SpaceTheme()).control("Theme color pad")
        #expect(pad.layer?.cornerRadius == 8 && pad.layer?.cornerCurve == .continuous)
    }
}

struct SpaceThemeEditorWindowTests {
    @MainActor private final class Host {
        let window: NSWindow
        let editor: SpaceThemeEditorView
        var reported: [SpaceTheme] = []
        nonisolated static let theme = SpaceTheme.singleColor(ThemeColor(hex: "5E3FA0")!)

        init(theme: SpaceTheme = Host.theme) {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 356, height: 508), styleMask: [.borderless],
                              backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            editor = SpaceThemeEditorView(theme: theme, performHapticFeedback: {})
            editor.onTooltipThemeChange = { [unowned self] in self.reported.append($0) }
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        func attach() { window.contentView = editor }
        func detach() { window.contentView = nil }
    }

    @MainActor private func restored() -> SpaceTheme {
        var theme = Host.theme
        theme.noise = 0.4
        return theme
    }

    @Test @MainActor func aWindowlessEditorReportsNoTooltipTheme() {
        let host = Host()
        host.editor.synchronizeTheme(restored())
        #expect(host.reported.isEmpty)
    }

    @Test @MainActor func arrivingInAWindowReportsTheShownThemeOnce() {
        let host = Host()
        host.editor.synchronizeTheme(restored())
        host.attach()
        #expect(host.reported == [restored()])
    }

    @Test @MainActor func aRefreshWithoutAThemeChangeReportsNothing() {
        let host = Host()
        host.attach()
        host.editor.finishEditing()
        #expect(host.reported.count == 1)
    }

    @Test @MainActor func aParentReplacementReportsTheNewTheme() {
        let host = Host()
        host.attach()
        var replaced = restored()
        replaced.primaryColor = ThemeColor(hex: "F25E6B")
        host.editor.synchronizeTheme(replaced)
        #expect(host.reported.last == replaced)
    }

    @Test @MainActor func anEditReportsTheEditedTheme() throws {
        let host = Host()
        host.attach()
        let before = host.editor.theme.intensity
        let intensity = try #require(host.editor.subviews.first { $0.accessibilityLabel() == "Theme intensity" })
        _ = intensity.accessibilityPerformIncrement()
        #expect(host.editor.theme.intensity != before)
        #expect(host.reported.last?.intensity == host.editor.theme.intensity)
    }

    @Test @MainActor func arrivingInAWindowAgainReportsEvenAnUnchangedTheme() {
        let host = Host()
        host.attach()
        host.detach()
        host.attach()
        #expect(host.reported == [Host.theme, Host.theme])
    }

    @Test @MainActor func aDetachedEditorReportsNothing() {
        let host = Host()
        host.attach()
        host.detach()
        let count = host.reported.count
        host.editor.synchronizeTheme(restored())
        #expect(host.reported.count == count)
    }

    @MainActor private func knob(in host: Host) throws -> (pad: NSView, knob: CALayer) {
        host.attach()
        host.editor.layoutSubtreeIfNeeded()
        let pad = try #require(host.editor.subviews.first { $0.accessibilityLabel() == "Theme color pad" })
        let container = try #require(pad.layer?.sublayers?.first { layer in
            !pad.subviews.contains { $0.layer === layer } && layer.sublayers?.isEmpty == false
        })
        return (pad, try #require(container.sublayers?.first))
    }

    @MainActor private func inheritMotion(_ knob: CALayer, _ key: String) {
        let animation = CABasicAnimation(keyPath: key == "position" ? "position" : "transform.scale")
        animation.duration = 1
        knob.add(animation, forKey: key)
    }

    @MainActor private func mouse(_ type: NSEvent.EventType, on pad: NSView, at point: CGPoint) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: pad.convert(point, to: nil), modifierFlags: [], timestamp: 30,
                                        windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
    }

    @Test @MainActor func theInitialPadLayoutPlacesItsKnobWithoutASpring() throws {
        let knob = try knob(in: Host(theme: SpaceTheme.singleColor(try #require(ThemeColor(red: 0.04, green: 0.03, blue: 0.08)))))
        #expect(knob.knob.animationKeys()?.isEmpty != false)
    }

    @Test @MainActor func anAdmittedDirectStartRetiresInheritedPositionalMotion() throws {
        let host = Host(theme: SpaceTheme.singleColor(try #require(ThemeColor(red: 0.04, green: 0.03, blue: 0.08))))
        let (pad, knob) = try knob(in: host)
        inheritMotion(knob, "position")
        pad.mouseDown(with: try mouse(.leftMouseDown, on: pad, at: knob.position))
        #expect(knob.animation(forKey: "position") == nil)
        pad.mouseUp(with: try mouse(.leftMouseUp, on: pad, at: knob.position))
    }

    @Test @MainActor func detachingTheEditorRetiresAllPendingKnobMotion() throws {
        let host = Host(theme: SpaceTheme.singleColor(try #require(ThemeColor(red: 0.04, green: 0.03, blue: 0.08))))
        let knob = try knob(in: host).knob
        inheritMotion(knob, "position")
        inheritMotion(knob, "hover")
        host.detach()
        #expect(knob.animationKeys()?.isEmpty != false)
    }
}
