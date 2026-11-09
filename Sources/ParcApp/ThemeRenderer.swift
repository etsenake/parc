import AppKit
import MetalKit
import simd

extension NSColor {
    /// A layer's fixed colour, resolved in the appearance it is shown in. A
    /// system colour's `cgColor` otherwise resolves in AppKit's current
    /// drawing appearance, which during an appearance switch is still the old one.
    func cgColor(in appearance: NSAppearance?) -> CGColor {
        guard let appearance else { return cgColor }
        var resolved: CGColor?
        appearance.performAsCurrentDrawingAppearance { resolved = cgColor }
        return resolved ?? cgColor
    }
}

/// Source-owned implementation of the installed WindowTheme renderer's measured
/// color math. The evidence and remaining parity limits live in the theme
///
struct ThemeChromePalette: Equatable {
    let isDark: Bool
    let foregroundPrimary: NSColor
    let foregroundSecondary: NSColor
    let foregroundTertiary: NSColor
    let maxContrastColor: NSColor
    let minContrastColor: NSColor
    let backgroundExtra: NSColor
    let background: NSColor
    let focus: NSColor
    let hover: NSColor
    let cutoutColor: NSColor
    let title: NSColor
    let subtitle: NSColor
    ///
    ///
    let shaded: NSColor
    let shadedDark: NSColor
    private var inheritedContentAppearance: NSAppearance?

    /// Content over the theme has its own appearance. Do not apply this to the
    /// window/background: its material and Metal underlay use the app appearance.
    var contentAppearance: NSAppearance? {
        inheritedContentAppearance ?? NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    init(theme: SpaceTheme, appearance: NSAppearance) {
        let dark: Bool
        switch theme.appearance {
        case .light: dark = false
        case .dark: dark = true
        case .automatic:
            dark = ThemeRenderMath.automaticDark(theme: theme)
                ?? (appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        }
        self.init(theme: theme, isDark: dark)
        if theme.appearance == .automatic && (!theme.isValid || theme.primaryColor == nil) {
            //
            // neighbor needs the real window's appearance explicitly, or it
            // would inherit the current Space's contrasting text appearance.
            inheritedContentAppearance = appearance
        }
    }

    init(theme: SpaceTheme, isDark: Bool) {
        self.isDark = isDark
        guard let primary = theme.primaryColor, theme.isValid else {
            foregroundPrimary = .labelColor; foregroundSecondary = .secondaryLabelColor
            foregroundTertiary = .tertiaryLabelColor
            maxContrastColor = isDark ? .white : .black
            minContrastColor = isDark ? .black : .white
            backgroundExtra = .controlBackgroundColor; background = .windowBackgroundColor
            focus = .selectedContentBackgroundColor; hover = .quaternaryLabelColor
            cutoutColor = .windowBackgroundColor; title = .labelColor; subtitle = .secondaryLabelColor
            // No primary palette exists for this system fallback; keep the
            // same semantic positions the themed palette derives from it.
            shaded = isDark ? foregroundTertiary : foregroundPrimary
            shadedDark = isDark ? minContrastColor : maxContrastColor
            return
        }
        //
        // luminance is in the target band; these are not HSL-lightness bounds.
        let light = ThemeRenderMath.luminanceAdjusted(primary, minimum: 0.85, maximum: 0.95)
        let mid = ThemeRenderMath.luminanceAdjusted(primary, minimum: 0.3, maximum: 0.5)
        let shade = ThemeRenderMath.luminanceAdjusted(primary, minimum: 0, maximum: 0.5)
        let dark = ThemeRenderMath.luminanceAdjusted(primary, minimum: 0, maximum: 0.1)
        func color(_ v: SIMD4<Float>) -> NSColor { ThemeRenderMath.color(v) }
        func over(_ v: SIMD4<Float>, _ alpha: Float, _ base: SIMD4<Float>) -> NSColor {
            var foreground = v; foreground.w = alpha
            return color(ThemeRenderMath.over(foreground, base))
        }
        let white = SIMD4<Float>(1, 1, 1, 1), black = SIMD4<Float>(0, 0, 0, 1)
        shaded = color(shade); shadedDark = color(dark)
        //
        // and BasePrimaryLight is black in the shipped asset catalog.
        if isDark {
            foregroundPrimary = color(light); foregroundSecondary = color(mid)
            foregroundTertiary = color(shade); maxContrastColor = color(light)
            minContrastColor = color(dark)
            backgroundExtra = over(dark, 0.15, black); background = over(dark, 0.3, black)
            focus = over(dark, 0.65, SIMD4<Float>(1, 1, 1, 0.45))
            hover = over(dark, 0.35, SIMD4<Float>(1, 1, 1, 0.2))
            cutoutColor = color(dark); title = over(dark, 0.15, white)
            subtitle = over(light, 0.5, black)
        } else {
            foregroundPrimary = color(shade); foregroundSecondary = color(mid)
            foregroundTertiary = color(light); maxContrastColor = color(dark)
            minContrastColor = color(light)
            backgroundExtra = over(dark, 0.01, white); background = over(dark, 0.1, white)
            focus = over(dark, 0.5, white); hover = over(dark, 0.2, white)
            cutoutColor = color(light); title = over(dark, 0.3, black)
            subtitle = over(dark, 0.4, white)
        }
    }

    ///
    ///
    /// so a view takes the theme's light or dark palette by its own
    /// appearance, whatever the theme's forced appearance.
    static func appearanceBasedMaxContrast(theme: SpaceTheme) -> NSColor {
        NSColor(name: nil) { appearance in
            ThemeChromePalette(theme: theme, isDark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua).maxContrastColor
        }
    }

    ///
    /// address scheme. Values come from this window's actual theme and palette.
    ///
    /// Display P3 components to eight-digit uppercase hex, including alpha.
    /// A `basicColor` background, the incognito theme's, exports its one
    /// colour as the simple colour (inferred from the single-colour branch).
    func websiteStylesheet(theme: SpaceTheme, basicBackground: NSColor? = nil) -> String {
        var values: [(String, NSColor)] = [
            ("foregroundPrimary", foregroundPrimary), ("foregroundSecondary", foregroundSecondary),
            ("foregroundTertiary", foregroundTertiary), ("maxContrastColor", maxContrastColor),
            ("minContrastColor", minContrastColor), ("backgroundExtra", backgroundExtra),
            ("background", background), ("focus", focus), ("hover", hover),
            ("cutoutColor", cutoutColor), ("title", title), ("subtitle", subtitle)
        ].map { ("--arc-palette-" + $0.0, $0.1) }
        let colors = basicBackground.map { [$0] } ?? (theme.isValid ? theme.colors.map(ThemeRenderMath.nativeColor) : [])
        if colors.count < 2 {
            values.append(("--arc-background-simple-color", colors.first ?? background))
        } else {
            for (index, color) in colors.prefix(2).enumerated() {
                values.append(("--arc-background-gradient-color\(index)", color))
            }
            if colors.count > 2 {
                values.append(("--arc-background-gradient-overlay-color0", colors[2].withAlphaComponent(0)))
                values.append(("--arc-background-gradient-overlay-color1", colors[2]))
            }
        }
        var declarations: [String] = []
        let resolve = {
            declarations = values.compactMap { name, color -> String? in
                guard let value = Self.websiteColor(color) else { return nil }
                return "  \(name): \(value);"
            }
        }
        if let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua) {
            appearance.performAsCurrentDrawingAppearance(resolve)
        } else { resolve() }
        return ":root {\n" + declarations.joined(separator: "\n") + "\n}"
    }

    static func websiteColor(_ color: NSColor) -> String? {
        guard let converted = color.usingColorSpace(.displayP3) else { return nil }
        let components = [converted.redComponent, converted.greenComponent,
                          converted.blueComponent, converted.alphaComponent]
        guard components.allSatisfy(\.isFinite) else { return nil }
        //
        // conversion is recovered; this bounds adaptation keeps malformed
        // values from entering the stylesheet.
        return "#" + components.map { String(format: "%02X", Int((min(1, max(0, $0)) * 255).rounded())) }.joined()
    }
}

///
/// contrast-selected content appearance (10160a630), while the gradient
/// underlay reads the native window appearance (101383c18). Stored forced
/// appearances predate that recovered separation in Parc; preserve their
/// explicit choice for compatibility. The exception is a floating surface's
///
/// inferred to, so a forced side's text may sit on the window's blur.
struct ThemeSurfaceStyle {
    let backgroundIsDark: Bool
    let material: NSVisualEffectView.Material

    init(theme: SpaceTheme, appearance: NSAppearance, colorRenderingAvailable: Bool = true) {
        let hasColor = theme.isValid && theme.colorCount > 0
        if hasColor && !colorRenderingAvailable {
            // Without the color canvas, the native material is the entire
            // backdrop. Keep it legible with the published content palette.
            backgroundIsDark = ThemeChromePalette(theme: theme, appearance: appearance).isDark
            material = NSVisualEffectView.Material(rawValue: backgroundIsDark ? 2 : 1)!
            return
        }
        let systemDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        switch theme.appearance {
        case .automatic: backgroundIsDark = systemDark
        case .light: backgroundIsDark = false
        case .dark: backgroundIsDark = true
        }
        let darkMaterial = hasColor ? theme.appearance == .dark : backgroundIsDark
        // Original WindowBackgroundTranslucencyViewAppKit uses material 1/2
        // (101392e3c, constants103444dd0/103444dc8), emphasized and follows-key.
        // The numeric initializer avoids deprecated Swift spellings while
        // retaining the shipped native material, rather than substituting sidebar.
        material = NSVisualEffectView.Material(rawValue: darkMaterial ? 2 : 1)!
    }
}

@MainActor
enum ThemeWindowActivity {
    ///
    /// main state and every parent; an editor child must not dim the main theme.
    static func isActive(_ window: NSWindow?) -> Bool {
        var owner = window
        while let current = owner {
            if current.isKeyWindow || current.isMainWindow { return true }
            owner = current.parent
        }
        return false
    }

    static func contains(_ changed: NSWindow, in window: NSWindow?) -> Bool {
        var owner = window
        while let current = owner {
            if current === changed { return true }
            owner = current.parent
        }
        return false
    }
}

private enum ThemeRenderMath {
    static func nativeColor(_ color: ThemeColor) -> NSColor {
        let space: NSColorSpace
        switch color.colorSpace {
        case .sRGB: space = .sRGB
        case .displayP3: space = .displayP3
        case .linearSRGB:
            space = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)!
        }
        let values = [CGFloat(color.red), CGFloat(color.green), CGFloat(color.blue), 1]
        return NSColor(colorSpace: space, components: values, count: 4)
    }

    static func srgb(_ color: ThemeColor) -> SIMD4<Float> {
        let native = nativeColor(color)
        let converted = native.usingColorSpace(.extendedSRGB) ?? native
        return SIMD4(Float(converted.redComponent), Float(converted.greenComponent), Float(converted.blueComponent), 1)
    }

    static func color(_ value: SIMD4<Float>) -> NSColor {
        let values = [CGFloat(value.x), CGFloat(value.y), CGFloat(value.z), CGFloat(value.w)]
        return NSColor(colorSpace: .extendedSRGB, components: values, count: 4)
    }

    static func over(_ foreground: SIMD4<Float>, _ background: SIMD4<Float>) -> SIMD4<Float> {
        let alpha = foreground.w + background.w * (1 - foreground.w)
        guard alpha > 0 else { return .zero }
        let rgb = (SIMD3(foreground.x, foreground.y, foreground.z) * foreground.w
            + SIMD3(background.x, background.y, background.z) * background.w * (1 - foreground.w)) / alpha
        return SIMD4(rgb, alpha)
    }

    static func luminance(_ rgb: SIMD4<Float>) -> Double {
        func linear(_ v: Float) -> Double {
            let c = Double(v)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.x) + 0.7152 * linear(rgb.y) + 0.0722 * linear(rgb.z)
    }

    static func luminanceAdjusted(_ base: ThemeColor, minimum: Double, maximum: Double) -> SIMD4<Float> {
        // Native HSL adjustment preserves the original RGB color space. Its
        // luminance helper reads components in that space before the semantic
        // palette converts the resulting colors to extended sRGB.
        func components(_ value: ThemeColor) -> SIMD4<Float> {
            SIMD4(Float(value.red), Float(value.green), Float(value.blue), 1)
        }
        let hsl = base.hsl
        var lightness = hsl.lightness, result = base
        let delta: Double
        if luminance(components(result)) < minimum { delta = 0.01 }
        else if luminance(components(result)) > maximum { delta = -0.01 }
        else { return srgb(result) }
        for _ in 0..<101 {
            lightness = min(1, max(0, lightness + delta))
            guard let next = ThemeColor.hsl(hue: hsl.hue, saturation: hsl.saturation, lightness: lightness,
                                           colorSpace: base.colorSpace) else { break }
            result = next
            if delta > 0 ? luminance(components(result)) >= minimum : luminance(components(result)) <= maximum { break }
            if lightness == 0 || lightness == 1 { break }
        }
        return srgb(result)
    }

    static func automaticDark(theme: SpaceTheme) -> Bool? {
        guard let primary = theme.primaryColor, theme.colorCount > 0, theme.isValid,
              let converted = nativeColor(primary).cgColor.converted(to: CGColorSpaceCreateDeviceRGB(),
                    intent: .defaultIntent, options: nil), let c = converted.components, c.count >= 3 else { return nil }
        let base = SIMD4<Float>(Float(c[0]), Float(c[1]), Float(c[2]), 1)
        func contrast(_ color: NSColor) -> Double {
            let candidate = color.usingColorSpace(.extendedSRGB) ?? color
            let rgb = SIMD4<Float>(Float(candidate.redComponent), Float(candidate.greenComponent),
                                   Float(candidate.blueComponent), Float(candidate.alphaComponent))
            let first = luminance(base) + 0.05, second = luminance(rgb) + 0.05
            return max(first, second) / min(first, second)
        }
        //
        // The installed sidebar-dark-mode-bias flag has a baked default of0.
        let light = ThemeChromePalette(theme: theme, isDark: false)
        let dark = ThemeChromePalette(theme: theme, isDark: true)
        return contrast(dark.title) >= contrast(light.title)
    }
}

// Opt-in native delivery diagnostics only: no content/URLs/keys, hit tests,
// layout, focus or window changes. Tree/ancestor walks have fixed bounds.
@MainActor
enum NativeInputDiagnostics {
    static let enabled = CommandLine.arguments.contains("--parc-input-diagnostics")
    private static let nodeLimit = 256
    private static let recordLimit = 48

    @MainActor
    final class ViewRecord {
        weak var view: NSView?
        let identity: UInt
        let className: String
        init(_ view: NSView) {
            self.view = view
            identity = NativeInputDiagnostics.identity(view)
            className = NSStringFromClass(type(of: view))
        }
    }
    @MainActor
    final class Snapshot {
        weak var window: NSWindow?
        let windowNumber: Int
        let views: [ViewRecord]
        init(_ window: NSWindow?, views: [ViewRecord]) {
            self.window = window
            windowNumber = window?.windowNumber ?? 0
            self.views = views
        }
    }
    static func isLeftClick(_ event: NSEvent) -> Bool {
        event.type == .leftMouseDown || event.type == .leftMouseUp
    }
    private static func identity(_ object: AnyObject?) -> UInt {
        object.map { UInt(bitPattern: Unmanaged.passUnretained($0).toOpaque()) } ?? 0
    }
    private static func relevant(_ view: NSView) -> Bool {
        let name = NSStringFromClass(type(of: view)).split(separator: ".").last
        return ["PCBrowserView", "PCNativePageHost", "WebContentsViewCocoa",
                "RenderWidgetHostViewCocoa", "BrowserPane"].contains(name.map(String.init) ?? "")
    }
    private static func log(_ event: NSEvent, _ phase: String, _ fields: String) {
        NSLog("%@", "[ParcInput] phase=\(phase) event=\(event.eventNumber) window=\(event.windowNumber) type=\(event.type.rawValue) time=\(event.timestamp) \(fields)")
    }
    private static func windowState(_ event: NSEvent, _ phase: String, _ window: NSWindow?) {
        log(event, phase, "native_window=\(window?.windowNumber ?? 0) alive=\(window != nil) miniaturized=\(window?.isMiniaturized ?? false) visible=\(window?.isVisible ?? false) key=\(window?.isKeyWindow ?? false) ignores_mouse=\(window?.ignoresMouseEvents ?? false)")
    }
    private static func viewState(_ event: NSEvent, _ phase: String,
                                  _ record: ViewRecord, expectedWindow: NSWindow?) {
        guard let view = record.view else {
            log(event, phase, "view=\(record.identity) class=\(record.className) alive=false")
            return
        }
        log(event, phase, "view=\(record.identity) class=\(record.className) alive=true parent=\(identity(view.superview)) native_window=\(view.window?.windowNumber ?? 0) same_window=\(expectedWindow != nil && view.window === expectedWindow) hidden=\(view.isHidden) ancestor_hidden=\(view.isHiddenOrHasHiddenAncestor) frame_size=\(view.frame.width)x\(view.frame.height) bounds_size=\(view.bounds.width)x\(view.bounds.height)")
    }
    private static func capture(_ event: NSEvent, _ phase: String, _ window: NSWindow?) -> [ViewRecord] {
        var queue = window?.contentView.map { [$0] } ?? []
        var visited = 0
        var records: [ViewRecord] = []
        while visited < queue.count && visited < nodeLimit {
            let view = queue[visited]
            visited += 1
            if relevant(view), records.count < recordLimit {
                let record = ViewRecord(view)
                records.append(record)
                viewState(event, phase, record, expectedWindow: window)
            }
            let remaining = nodeLimit - queue.count
            if remaining > 0 { queue.append(contentsOf: view.subviews.prefix(remaining)) }
        }
        log(event, phase + "-summary", "visited=\(visited) recorded=\(records.count) node_limit=\(nodeLimit) record_limit=\(recordLimit) bounded=\(visited == nodeLimit || records.count == recordLimit)")
        return records
    }
    static func beforeDispatch(_ event: NSEvent, phase: String = "dispatch") -> Snapshot? {
        guard enabled, isLeftClick(event) else { return nil }
        let window = event.window
        windowState(event, phase + "-before-window", window)
        return Snapshot(window, views: capture(event, phase + "-before-view", window))
    }
    static func afterDispatch(_ event: NSEvent, snapshot: Snapshot?, phase: String = "dispatch") {
        guard let snapshot else { return }
        // Log the same weak original owner even if the event's current window
        // changed. A fresh bounded tree separately identifies new page views.
        let window = snapshot.window
        windowState(event, phase + "-after-window", window)
        log(event, phase + "-after-owner", "original_window=\(snapshot.windowNumber) event_native_window=\(event.window?.windowNumber ?? 0) same_window=\(window != nil && event.window === window)")
        for record in snapshot.views {
            viewState(event, phase + "-after-original-view", record, expectedWindow: window)
        }
        _ = capture(event, phase + "-after-view", window)
    }
    static func hitResult(_ event: NSEvent, root: NSView, result: NSView?) {
        var chain: [String] = []
        var current = result
        while let view = current, chain.count < 12 {
            chain.append("\(NSStringFromClass(type(of: view))):\(identity(view))")
            current = view.superview
        }
        log(event, "root-hit-result", "root=\(identity(root)) root_window=\(root.window?.windowNumber ?? 0) result=\(identity(result)) class=\(result.map { NSStringFromClass(type(of: $0)) } ?? "nil") ancestors=\(chain.joined(separator: ">")) truncated=\(current != nil)")
    }
}

///
///
///
/// `basicColor` with no translucency style, no content appearance and not
/// vibrant, so the window and its floating sidebar are opaque; its window
/// appearance is `.single(.dark)`.
enum IncognitoWindowTheme {
    ///
    static let background = NSColor(displayP3Red: 0.054, green: 0.06, blue: 0.075, alpha: 1)
    /// Both palettes come from BaseAssets BrandBlue, Display P3 (49, 57, 251)/255,
    ///
    ///
    ///
    /// ThemeColor cannot hold, so it is clamped to 1.
    static let paletteTheme = SpaceTheme.singleColor(ThemeColor(red: 0.18420, green: 0.22480, blue: 1)!)
}

/// A background container: normal child controls remain interactive. Only its
/// backing surfaces (the material, the theme canvas and a floating surface's
/// shadow) pass pointer events through to the container's content.
@MainActor
final class ThemeRendererView: NSView {
    var onLayout: (() -> Void)?
    /// Set to the full-window background when this view paints a smaller
    /// sidebar surface. Both surfaces then sample one continuous gradient.
    weak var coordinateSpace: NSView? { didSet { invalidateCoordinates() } }
    var theme = SpaceTheme() { didSet { if theme != oldValue { refreshTheme() } } }
    /// A private window draws `IncognitoWindowTheme` in place of its Space's
    /// theme: an opaque fill with no material or canvas, and the brand palette
    /// resolved against the window's appearance.
    var incognito = false { didSet { if incognito != oldValue { refreshTheme() } } }
    /// The theme whose semantic palette this surface publishes.
    var paletteTheme: SpaceTheme { incognito ? IncognitoWindowTheme.paletteTheme : theme }
    /// Locked sidebars use the window's existing surface. Floating sidebars
    /// paint their own surface above page content, without hiding child controls.
    var drawsBackground = true { didSet { updateBackgroundVisibility() } }
    /// Library Space cards paint the theme over their own card fill rather
    /// than the window's behind-window material.
    var drawsMaterial = true { didSet { updateBackgroundVisibility() } }
    /// A floating sidebar's surface (FloatingSidebarSurface): the material
    ///
    /// it and the theme round to this radius inside the view's edge and
    /// shadow. The view does not clip, so content that must stay rounded
    /// clips itself. Nil draws the window's surface.
    var floatingCornerRadius: CGFloat? { didSet { if floatingCornerRadius != oldValue { updateFloatingSurface() } } }
    ///
    /// locked group fades `blurView` and `shadowView` out and
    /// `behindWindowBlurView` in with the slide, and keeps the corners and
    ///
    ///
    var docksFloatingSurface = false {
        didSet {
            guard docksFloatingSurface != oldValue else { return }
            updateFloatingShadow()
            updateDockMaterial()
            // A dock reversed before it settles floats again at once.
            if !docksFloatingSurface {
                for view in [material, dockMaterial, floatingShadow] as [NSView?] { view?.layer?.removeAnimation(forKey: "opacity") }
            }
        }
    }
    ///
    ///
    var preparesFloatingDock = false { didSet { if preparesFloatingDock != oldValue { updateDockMaterial() } } }
    ///
    /// `transitioning(from:to:progress:)` configuration, for the pages either
    /// side of the strip's position, to the window's background and the
    ///
    /// mixes the two themes' inputs by the progress (`ThemeMetalRenderer.draw`).
    /// While it is set the surface's own theme is not drawn, so a commit that
    /// changes that theme leaves the canvas unchanged.
    var pagingTransition: ThemePagingTransition? {
        didSet { if pagingTransition != oldValue { updateBackgroundVisibility() } }
    }
    private(set) var palette = ThemeChromePalette(theme: SpaceTheme(), isDark: false)
    var onPaletteChange: ((ThemeChromePalette) -> Void)?
    private let material = ThemeMaterialView()
    ///
    /// the `from` style's material, with the `to` style at alpha = progress
    /// while a swipe's two styles differ, and hides it otherwise
    ///
    ///
    private var pagingMaterial: ThemeMaterialView?
    ///
    /// material over the floating blur, shown only while the surface docks.
    private var dockMaterial: ThemeMaterialView?
    private var floatingShadow: FloatingSidebarShadowView?
    private var canvas: ThemeMetalCanvas?
    private var renderer: ThemeMetalRenderer?
    private var observers: [NSObjectProtocol] = []
    private var windowAppearanceObservation: NSKeyValueObservation?
    /// Last key/main activity bit sampled into a Metal draw, or scheduled by an
    /// activity dirty. Observers compare against this so redundant key↔main
    /// flips that leave `ThemeWindowActivity.isActive` unchanged skip.
    private var publishedWindowActive: Bool?
    /// Window-activity dirties that actually wrote `canvas.needsDisplay`. Used
    /// to observe true no-op skips; AppKit may keep `needsDisplay` set until draw.
    private(set) var canvasActivityDisplayInvalidations = 0
    private(set) var surfaceStyle = ThemeSurfaceStyle(theme: SpaceTheme(), appearance: NSAppearance(named: .aqua)!)
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        material.isEmphasized = true
        addSubview(material)
        do {
            let renderer = try ThemeMetalRenderer()
            let canvas = ThemeMetalCanvas(frame: bounds, device: renderer.device)
            canvas.isPaused = true; canvas.enableSetNeedsDisplay = true
            canvas.colorPixelFormat = .bgra8Unorm
            canvas.clearColor = MTLClearColorMake(0, 0, 0, 0)
            canvas.layer?.isOpaque = false
            canvas.render = { [weak self] view in self?.drawTheme(in: view) }
            self.renderer = renderer; self.canvas = canvas
            addSubview(canvas)
        } catch {
            // Keep the native material usable on machines without Metal.
            NSLog("Parc theme renderer unavailable: %@", error.localizedDescription)
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let changed = note.object as? NSWindow,
                          ThemeWindowActivity.contains(changed, in: self.window) else { return }
                    self.invalidateCanvasForWindowActivityIfNeeded()
                }
            })
        }
        refreshTheme()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Instrument the actual root result without another hit test or any
        // change to dispatch. Nested sidebar surfaces use the same superclass.
        let result = super.hitTest(point)
        if NativeInputDiagnostics.enabled, window?.contentView === self,
           let event = NSApp.currentEvent, NativeInputDiagnostics.isLeftClick(event) {
            NativeInputDiagnostics.hitResult(event, root: self, result: result)
        }
        return result
    }

    override func layout() {
        super.layout()
        // AppKit still marks the window root dirty when chrome geometry is
        // unchanged. Material/canvas sync is the local proxy for a bounds move
        // that requires chrome onLayout (BrowserWindowController.layoutChrome);
        // Cmd-S and other chrome owners call layoutChrome directly. Skip the
        // fan-out when those surfaces already match bounds.
        var surfacesMoved = false
        if material.frame != bounds {
            material.frame = bounds
            surfacesMoved = true
        }
        if let pagingMaterial, pagingMaterial.frame != bounds { pagingMaterial.frame = bounds }
        if let dockMaterial, dockMaterial.frame != bounds { dockMaterial.frame = bounds }
        if let canvas, canvas.frame != bounds {
            canvas.frame = bounds
            canvas.needsDisplay = true
            surfacesMoved = true
        }
        if surfacesMoved { onLayout?() }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Ownership changed; the next draw re-samples activity for this window.
        publishedWindowActive = nil
        // A Library Space card's surface lives under the Library's forced,
        // contrast-selected content appearance; effective-appearance
        // propagation alone then misses app changes.
        windowAppearanceObservation = window?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshTheme() }
        }
        refreshTheme()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshTheme() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); canvas?.needsDisplay = true }

    func invalidateCoordinates() { canvas?.needsDisplay = true }

    /// Key/main notifications only affect Metal noise strength via
    /// `ThemeWindowActivity.isActive`. Skip when the canvas is already dirty,
    /// hidden/idle, noise cannot sample activity, or the active bit matches the
    /// last draw/schedule. Real activity flips and theme/appearance refresh still dirty.
    private func invalidateCanvasForWindowActivityIfNeeded() {
        guard let canvas, !canvas.isHidden else { return }
        // ThemeOutputUniforms.z is noise * max * (active ? 1 : 0.25); with noise
        // 0 the multiplier never reaches a fragment (hasTexture stays false).
        guard theme.isValid, theme.colorCount > 0, theme.noise > 0 else { return }
        let active = ThemeWindowActivity.isActive(window)
        if publishedWindowActive == active { return }
        // Pending theme/layout/activity draw will sample live isActive; avoid a
        // redundant needsDisplay write. Do not publish here — draw reconciles.
        if canvas.needsDisplay { return }
        canvasActivityDisplayInvalidations += 1
        // Publish scheduled intent so same-turn key+main does not rewrite.
        publishedWindowActive = active
        canvas.needsDisplay = true
    }

    private func refreshTheme() {
        // A Library Space card's surface lives below the Library's
        // contrast-selected content appearance. Always resolve its backing
        // against its real window, never that unrelated text appearance.
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        palette = incognito
            ? ThemeChromePalette(theme: IncognitoWindowTheme.paletteTheme,
                                 isDark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            : ThemeChromePalette(theme: theme, appearance: appearance)
        surfaceStyle = ThemeSurfaceStyle(theme: theme, appearance: appearance, colorRenderingAvailable: renderer != nil)
        material.material = floatingCornerRadius == nil ? surfaceStyle.material : .popover
        updateMaterialAppearance()
        updateBackgroundVisibility()
        canvas?.needsDisplay = true
        onPaletteChange?(palette)
    }
    private func updateBackgroundVisibility() {
        material.isHidden = !drawsBackground || !drawsMaterial || incognito
        let colored = pagingTransition.map { $0.from.rendersColor || $0.theme.rendersColor } ?? theme.rendersColor
        canvas?.isHidden = !drawsBackground || !colored || incognito
        let fill = incognito && drawsBackground ? IncognitoWindowTheme.background.cgColor : nil
        if layer?.backgroundColor != fill { layer?.backgroundColor = fill }
        if drawsBackground && !incognito { canvas?.needsDisplay = true }
        updatePagingMaterial()
        updateDockMaterial()
    }
    /// Only the window's own surface: the sidebar's samples the window
    /// (`coordinateSpace`), and floating it hides translucency. Its base
    /// material takes the left page's (`from`) style through a swipe.
    private func updatePagingMaterial() {
        guard coordinateSpace == nil, floatingCornerRadius == nil, !incognito else {
            if pagingMaterial?.isHidden == false { pagingMaterial?.isHidden = true }
            return
        }
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        func style(_ theme: SpaceTheme) -> ThemeSurfaceStyle {
            ThemeSurfaceStyle(theme: theme, appearance: appearance, colorRenderingAvailable: renderer != nil)
        }
        let from = pagingTransition.map { style($0.from) } ?? surfaceStyle
        Self.apply(from, to: material)
        let to = pagingTransition.map { style($0.theme) }
        guard let transition = pagingTransition, let to, drawsBackground, drawsMaterial,
              to.material != from.material || to.backgroundIsDark != from.backgroundIsDark else {
            if pagingMaterial?.isHidden == false { pagingMaterial?.isHidden = true }
            return
        }
        let view = pagingMaterial ?? makePagingMaterial()
        Self.apply(to, to: view)
        let alpha = min(1, max(0, transition.progress))
        if view.alphaValue != alpha { view.alphaValue = alpha }
        if view.isHidden { view.isHidden = false }
    }
    private static func apply(_ style: ThemeSurfaceStyle, to view: NSVisualEffectView) {
        if view.material != style.material { view.material = style.material }
        let appearance: NSAppearance.Name = style.backgroundIsDark ? .darkAqua : .aqua
        if view.appearance?.name != appearance { view.appearance = NSAppearance(named: appearance) }
    }
    private func makePagingMaterial() -> ThemeMaterialView {
        let view = ThemeMaterialView(frame: bounds)
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.isEmphasized = true
        addSubview(view, positioned: .above, relativeTo: material)
        pagingMaterial = view
        return view
    }
    ///
    /// emphasized, under a theme view with no translucency of its own
    ///
    private func updateFloatingSurface() {
        let radius = floatingCornerRadius
        let blending: NSVisualEffectView.BlendingMode = radius == nil ? .behindWindow : .withinWindow
        if material.blendingMode != blending { material.blendingMode = blending }
        let kind = radius == nil ? surfaceStyle.material : .popover
        if material.material != kind { material.material = kind }
        updateMaterialAppearance()
        material.maskImage = radius.flatMap(FloatingSidebarSurface.mask)
        if let canvas {
            if canvas.layer?.cornerRadius != radius ?? 0 { canvas.layer?.cornerRadius = radius ?? 0 }
            if canvas.clipsToBounds != (radius != nil) { canvas.clipsToBounds = radius != nil }
        }
        if layer?.cornerRadius != radius ?? 0 { layer?.cornerRadius = radius ?? 0 }
        // AppKit clips a view once its layer has a corner radius; the shadow
        // lies outside.
        if clipsToBounds { clipsToBounds = false }
        let borderWidth = radius == nil ? 0 : FloatingSidebarSurface.borderWidth
        if layer?.borderWidth != borderWidth { layer?.borderWidth = borderWidth }
        let borderColor = radius == nil ? nil : FloatingSidebarSurface.borderColor
        if layer?.borderColor != borderColor { layer?.borderColor = borderColor }
        if radius != nil, floatingShadow == nil {
            let shadow = FloatingSidebarShadowView(frame: bounds.insetBy(dx: -FloatingSidebarSurface.shadowOutset,
                                                                         dy: -FloatingSidebarSurface.shadowOutset))
            shadow.image = FloatingSidebarSurface.shadowImage
            shadow.alphaValue = FloatingSidebarSurface.shadowAlpha
            shadow.autoresizingMask = [.width, .height]
            shadow.setAccessibilityElement(false)
            addSubview(shadow, positioned: .below, relativeTo: material)
            floatingShadow = shadow
        }
        updateFloatingShadow()
        updateDockMaterial()
        updatePagingMaterial()
    }
    ///
    ///
    ///
    /// inferred to, and a Space swipe or its commit leaves it as it is. Where
    /// the blur is the whole backdrop (no colour, or no Metal) it keeps the
    /// side the palette's text was chosen for, in the window's own variant
    /// when the window is on that side.
    private func updateMaterialAppearance() {
        let side: NSAppearance.Name = surfaceStyle.backgroundIsDark ? .darkAqua : .aqua
        let windowAppearance = window?.effectiveAppearance
        let followsWindow = floatingCornerRadius != nil
            && ((renderer != nil && theme.rendersColor) || windowAppearance?.bestMatch(from: [.aqua, .darkAqua]) == side)
        let appearance = followsWindow ? windowAppearance : NSAppearance(named: side)
        if material.appearance?.name != appearance?.name { material.appearance = appearance }
    }
    private func updateFloatingShadow() {
        guard let shadow = floatingShadow else { return }
        let hidden = floatingCornerRadius == nil
        if shadow.isHidden != hidden { shadow.isHidden = hidden }
        let alpha = docksFloatingSurface && !hidden ? 0 : FloatingSidebarSurface.shadowAlpha
        if shadow.alphaValue != alpha { shadow.alphaValue = alpha }
    }
    ///
    /// behind-window, emphasized and masked like `blurView`. Its material is
    /// the window surface's, so the dock ends on the surface it settles onto.
    private func updateDockMaterial() {
        let floating = floatingCornerRadius != nil
        let shown = floating && drawsBackground && drawsMaterial && !incognito && (preparesFloatingDock || docksFloatingSurface)
        let materialAlpha: CGFloat = floating && docksFloatingSurface ? 0 : 1
        if material.alphaValue != materialAlpha { material.alphaValue = materialAlpha }
        guard shown || dockMaterial != nil else { return }
        let view = dockMaterial ?? makeDockMaterial()
        if shown {
            Self.apply(surfaceStyle, to: view)
            if view.maskImage == nil { view.maskImage = floatingCornerRadius.flatMap(FloatingSidebarSurface.mask) }
        }
        let alpha: CGFloat = shown && docksFloatingSurface ? 1 : 0
        if view.alphaValue != alpha { view.alphaValue = alpha }
        if view.isHidden == shown { view.isHidden = !shown }
    }
    private func makeDockMaterial() -> ThemeMaterialView {
        let view = ThemeMaterialView(frame: bounds)
        // Its layer otherwise waits for the next commit, so the first dock's
        // group, in the preparation's turn, could not fade it in.
        view.wantsLayer = true
        view.blendingMode = .behindWindow
        view.isEmphasized = true
        view.isHidden = true
        view.alphaValue = 0
        addSubview(view, positioned: .above, relativeTo: material)
        dockMaterial = view
        return view
    }
    private func drawTheme(in canvas: MTKView) {
        let space = coordinateSpace ?? self
        let size = space.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let rect = convert(bounds, to: space)
        let originY = space.isFlipped ? rect.minY - space.bounds.minY : space.bounds.maxY - rect.maxY
        let sampleRect = SIMD4<Float>(Float((rect.minX - space.bounds.minX) / size.width),
                                      Float(originY / size.height),
                                      Float(rect.width / size.width), Float(rect.height / size.height))
        let isActive = ThemeWindowActivity.isActive(window)
        publishedWindowActive = isActive
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        let next = pagingTransition.map {
            (theme: $0.theme, isDark: ThemeSurfaceStyle(theme: $0.theme, appearance: appearance).backgroundIsDark,
             progress: Float(min(1, max(0, $0.progress))))
        }
        let from = pagingTransition.map { (theme: $0.from, isDark: ThemeSurfaceStyle(theme: $0.from, appearance: appearance).backgroundIsDark) }
            ?? (theme: theme, isDark: surfaceStyle.backgroundIsDark)
        renderer?.draw(in: canvas, theme: from.theme, isDark: from.isDark, next: next,
                       isActive: isActive, pointSize: size, sampleRect: sampleRect)
    }
}

/// A swipe between two Spaces' themes, the left page's and the right page's:
/// `theme` has come in by `progress` over `from`.
struct ThemePagingTransition: Equatable {
    var from: SpaceTheme
    var theme: SpaceTheme
    var progress: CGFloat
}

private extension SpaceTheme {
    var rendersColor: Bool { isValid && colorCount > 0 }
}

@MainActor
private final class ThemeMaterialView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class ThemeMetalCanvas: MTKView {
    var render: ((MTKView) -> Void)?
    override func draw(_ dirtyRect: NSRect) { render?(self) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

///
///
/// the theme, both rounded, and a fine edge over its unclipped layer.
/// `ThemeRendererView.floatingCornerRadius` draws it for Parc's sidebar
///
@MainActor enum FloatingSidebarSurface {
    ///
    ///
    static let cornerRadius: CGFloat = 8
    /// `SidebarBorderColor`, white at 0.3 in both appearances, 1 point wide
    ///
    static let borderWidth: CGFloat = 1
    static let borderColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.3).cgColor
    ///
    ///
    static let shadowAlpha: CGFloat = 0.2
    static let shadowOutset: CGFloat = 10
    static let directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("FloatingSidebar", isDirectory: true)
    private static var cachedShadow: NSImage?

    /// `CellDropShadow` as the catalog's NSImage holds it: both bitmaps at
    /// 40 points with its cap insets.
    static var shadowImage: NSImage? {
        if let cachedShadow { return cachedShadow }
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent("CellDropShadow.png")),
              let base = NSBitmapImageRep(data: data) else { return nil }
        base.size = NSSize(width: base.pixelsWide, height: base.pixelsHigh)
        let image = NSImage(size: base.size)
        image.addRepresentation(base)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("CellDropShadow@2x.png")),
           let double = NSBitmapImageRep(data: data) {
            double.size = NSSize(width: CGFloat(double.pixelsWide) / 2, height: CGFloat(double.pixelsHigh) / 2)
            image.addRepresentation(double)
        }
        image.capInsets = NSEdgeInsets(top: 19, left: 19, bottom: 20, right: 20)
        cachedShadow = image
        return image
    }

    ///
    /// its r-point caps.
    static func mask(radius: CGFloat) -> NSImage? {
        guard radius > 0 else { return nil }
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.set()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

///
/// axes independently, but as layer contents: a resize, a docking slide's
/// included, is one bounds animation with no redraw. It passes every click
/// through.
@MainActor final class FloatingSidebarShadowView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let layer else { return }
        guard let image, image.size.width > 0, image.size.height > 0 else { layer.contents = nil; return }
        let scale = image.recommendedLayerContentsScale(window?.backingScaleFactor ?? layer.contentsScale)
        layer.contentsScale = scale
        layer.contents = image.layerContents(forContentsScale: scale)
        layer.contentsGravity = .resize
        // Unit coordinates from the image's bottom-left corner.
        let caps = image.capInsets, size = image.size
        layer.contentsCenter = CGRect(x: caps.left / size.width, y: caps.bottom / size.height,
                                      width: max(0, size.width - caps.left - caps.right) / size.width,
                                      height: max(0, size.height - caps.top - caps.bottom) / size.height)
    }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsDisplay = true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct ThemeGradientUniforms {
    var baseStartEnd = SIMD4<Float>(0, 0, 1, 1)
    var base0 = SIMD4<Float>.zero
    var base1 = SIMD4<Float>.zero
    var overlay0 = SIMD4<Float>.zero
    var overlay1 = SIMD4<Float>.zero
    var underlay = SIMD4<Float>.zero
    // x: gradient alpha, y: base count, z: overlay count
    var parameters = SIMD4<Float>.zero

    init(theme: SpaceTheme, backgroundIsDark: Bool, pointSize: NSSize) {
        let colors = theme.colors.map(ThemeRenderMath.srgb)
        guard !colors.isEmpty, pointSize.width > 0, pointSize.height > 0 else { return }
        let ratio = Float(pointSize.width / pointSize.height)
        if ratio > 1 { baseStartEnd = SIMD4(0, 0.5 - 0.5 / ratio, 1, 0.5 + 0.5 / ratio) }
        else { baseStartEnd = SIMD4(0.5 - 0.5 * ratio, 0, 0.5 + 0.5 * ratio, 1) }
        base0 = colors[0]
        if colors.count > 1 { base1 = colors[1] }
        if colors.count > 2 {
            overlay1 = colors[2]
            overlay0 = SIMD4(colors[2].x, colors[2].y, colors[2].z, 0)
        }
        let alpha = Float(0.2 + 0.55 * theme.intensity)
        let underlayAlpha = min(alpha, 0.5) * (backgroundIsDark ? 0.35 : 1)
        underlay = SIMD4(backgroundIsDark ? SIMD3<Float>.zero : SIMD3<Float>(repeating: 1), underlayAlpha)
        parameters = SIMD4(alpha, Float(min(2, colors.count)), colors.count == 3 ? 2 : 0, 0)
    }
}

struct ThemeOutputUniforms {
    var parameters: SIMD4<Float>
    var sampleRect: SIMD4<Float>

    init(theme: SpaceTheme, isActive: Bool, pointSize: NSSize, sampleRect: SIMD4<Float>, hasTexture: Bool) {
        parameters = SIMD4(Float(pointSize.width / ThemeTexturePitch.points), Float(pointSize.height / ThemeTexturePitch.points),
                           Float(theme.textureStrength(isActive: isActive)), hasTexture ? 1 : 0)
        self.sampleRect = sampleRect
    }
}

@MainActor
private final class ThemeMetalRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let gradientPipeline: MTLRenderPipelineState
    private let outputPipeline: MTLRenderPipelineState
    private let library: MTLLibrary
    private let gradient: MTLTexture
    /// Built on the first draw with a paging transition, so surfaces that
    /// never page do not hold them; nil if they cannot be built.
    private lazy var transition: (gradient: MTLRenderPipelineState, output: MTLRenderPipelineState)? = {
        guard let gradient = try? Self.pipeline(device, library, vertex: "themeGradientVertex", fragment: "themeTransitionGradientFragment"),
              let output = try? Self.pipeline(device, library, vertex: "themeOutputVertex", fragment: "themeTransitionFragment") else {
            NSLog("Parc theme paging transition unavailable")
            return nil
        }
        return (gradient, output)
    }()
    private var textures: [SpaceTheme.Texture: MTLTexture] = [:]
    private var missingTextures: Set<SpaceTheme.Texture> = []

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "Parc.Theme", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal is unavailable."])
        }
        self.device = device; self.queue = queue
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        self.library = library
        gradientPipeline = try Self.pipeline(device, library, vertex: "themeGradientVertex", fragment: "themeGradientFragment")
        outputPipeline = try Self.pipeline(device, library, vertex: "themeOutputVertex", fragment: "themeOutputFragment")
        guard let gradient = Self.gradientTarget(device) else {
            throw NSError(domain: "Parc.Theme", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot allocate the theme texture."])
        }
        self.gradient = gradient
    }

    private static func pipeline(_ device: MTLDevice, _ library: MTLLibrary, vertex: String, fragment: String) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// The recovered native renderer uses a 32×32 gradient target; the
    /// display pass samples it linearly while retaining full-resolution grain.
    private static func gradientTarget(_ device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 32, height: 32, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]; descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private func texture(_ type: SpaceTheme.Texture) -> MTLTexture? {
        if let cached = textures[type] { return cached }
        guard !missingTextures.contains(type) else { return nil }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("ThemeTextures").appendingPathComponent(type.rawValue + ".png"),
              let image = NSImage(contentsOf: url),
              let decoded = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cgImage = Self.premultiplied(decoded) else {
            missingTextures.insert(type)
            NSLog("Parc theme texture unavailable: %@", type.rawValue)
            return nil
        }
        do {
            let texture = try MTKTextureLoader(device: device).newTexture(cgImage: cgImage,
                options: [.SRGB: false, .generateMipmaps: false, .textureUsage: MTLTextureUsage.shaderRead.rawValue])
            textures[type] = texture
            return texture
        } catch {
            missingTextures.insert(type)
            NSLog("Parc theme texture failed: %@", error.localizedDescription)
            return nil
        }
    }

    ///
    /// straight alpha. Opaque images pass through unchanged.
    private static func premultiplied(_ image: CGImage) -> CGImage? {
        guard image.alphaInfo == .last || image.alphaInfo == .first else { return image }
        guard let space = image.colorSpace,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space.model == .rgb ? space : CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    ///
    /// renderer does: its gradient pass mixes the two layers' straight colours
    /// by p before premultiplying (`gradientFragment`), and its overlay pass
    /// mixes the two textures, each at its own strength (`overlayFragment`).
    /// A theme without colour contributes no layer or texture.
    func draw(in view: MTKView, theme: SpaceTheme, isDark: Bool, next requested: (theme: SpaceTheme, isDark: Bool, progress: Float)? = nil,
              isActive: Bool, pointSize: NSSize, sampleRect: SIMD4<Float>) {
        let transition = requested == nil ? nil : self.transition
        let next = transition == nil ? nil : requested
        let incoming = next?.theme.rendersColor == true
        guard pointSize.width > 0, pointSize.height > 0,
              let drawable = view.currentDrawable, let outputPass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer() else { return }
        outputPass.colorAttachments[0].loadAction = .clear
        outputPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        let progress = next?.progress ?? 0
        guard (theme.rendersColor && progress < 1) || (incoming && progress > 0) else {
            // A visible canvas with nothing to draw, such as a swipe's end in
            // an uncoloured Space, must not keep showing its last frame.
            command.makeRenderCommandEncoder(descriptor: outputPass)?.endEncoding()
            command.present(drawable); command.commit()
            return
        }
        var uniforms = ThemeGradientUniforms(theme: theme, backgroundIsDark: isDark, pointSize: pointSize)
        let nextUniforms = next.map { ThemeGradientUniforms(theme: $0.theme, backgroundIsDark: $0.isDark, pointSize: pointSize) }
        // An uncoloured theme's uniforms leave the gradient line unset.
        var line = theme.rendersColor ? uniforms : nextUniforms ?? uniforms
        var mixing = SIMD4<Float>(progress, theme.rendersColor ? 1 : 0, incoming ? 1 : 0, 0)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = gradient
        pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(transition?.gradient ?? gradientPipeline)
        encoder.setVertexBytes(&line, length: MemoryLayout<ThemeGradientUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ThemeGradientUniforms>.stride, index: 0)
        if var incomingUniforms = nextUniforms {
            encoder.setFragmentBytes(&incomingUniforms, length: MemoryLayout<ThemeGradientUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&mixing, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        func output(_ theme: SpaceTheme) -> (ThemeOutputUniforms, MTLTexture?) {
            let overlay = theme.rendersColor && theme.noise > 0 ? texture(theme.texture) : nil
            return (ThemeOutputUniforms(theme: theme, isActive: isActive, pointSize: pointSize,
                                        sampleRect: sampleRect, hasTexture: overlay != nil), overlay)
        }
        guard let display = command.makeRenderCommandEncoder(descriptor: outputPass) else { return }
        let current = output(theme)
        var currentUniforms = current.0
        display.setFragmentTexture(gradient, index: 0); display.setFragmentTexture(current.1, index: 1)
        display.setFragmentBytes(&currentUniforms, length: MemoryLayout<ThemeOutputUniforms>.stride, index: 0)
        if let next, let transition {
            let incoming = output(next.theme)
            var incomingUniforms = incoming.0
            display.setRenderPipelineState(transition.output)
            display.setFragmentTexture(incoming.1, index: 2)
            display.setFragmentBytes(&incomingUniforms, length: MemoryLayout<ThemeOutputUniforms>.stride, index: 1)
            display.setFragmentBytes(&mixing, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
        } else {
            display.setRenderPipelineState(outputPipeline)
        }
        display.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        display.endEncoding(); command.present(drawable); command.commit()
    }

    // Re-expression of gradientVertex/gradientFragment/renderFragment recovered
    // from default.metallib AIR, with explicit sRGB↔OKLab conversion. The static
    // texture-alpha pass is folded into display; no original shader binary loads.
    private static let shader = #"""
    #include <metal_stdlib>
    using namespace metal;
    struct Config { float4 baseStartEnd, base0, base1, overlay0, overlay1, underlay, parameters; };
    struct OutputConfig { float4 parameters, sampleRect; };
    struct Vertex { float4 position [[position]]; float2 uv; float baseT; float overlayT; };
    constant float2 uvs[] = {float2(0,0),float2(0,1),float2(1,0),float2(1,1)};
    constant float2 positions[] = {float2(-1,1),float2(-1,-1),float2(1,1),float2(1,-1)};
    float project(float2 p, float4 line) {
        float2 d = line.zw-line.xy;
        return clamp(dot(p-line.xy,d)/dot(d,d),0.0f,1.0f);
    }
    vertex Vertex themeGradientVertex(uint id [[vertex_id]], constant Config &c [[buffer(0)]]) {
        return {float4(positions[id],0,1),uvs[id],project(uvs[id],c.baseStartEnd),uvs[id].y};
    }
    vertex Vertex themeOutputVertex(uint id [[vertex_id]]) {
        return {float4(positions[id],0,1),uvs[id],0,0};
    }
    float3 linearRGB(float3 rgb) {
        float3 a=abs(rgb);
        return select(rgb/12.92f,sign(rgb)*pow((a+0.055f)/1.055f,float3(2.4f)),a>0.04045f);
    }
    float3 encodedRGB(float3 rgb) {
        float3 a=abs(rgb);
        return select(rgb*12.92f,sign(rgb)*(1.055f*pow(a,float3(1.0f/2.4f))-0.055f),a>0.0031308f);
    }
    float3 lab(float3 rgb) {
        rgb=linearRGB(rgb);
        float3 lms=float3(dot(rgb,float3(.4122214708f,.5363325363f,.0514459929f)),
                          dot(rgb,float3(.2119034982f,.6806995451f,.1073969566f)),
                          dot(rgb,float3(.0883024619f,.2817188376f,.6299787005f)));
        lms=sign(lms)*pow(abs(lms),float3(1.0f/3.0f));
        return float3(dot(lms,float3(.2104542553f,.7936177850f,-.0040720468f)),
                      dot(lms,float3(1.9779984951f,-2.4285922050f,.4505937099f)),
                      dot(lms,float3(.0259040371f,.7827717662f,-.8086757660f)));
    }
    float3 fromLab(float3 c) {
        float3 lms=float3(dot(c,float3(1,.3963377774f,.2158037573f)),
                          dot(c,float3(1,-.1055613458f,-.0638541728f)),
                          dot(c,float3(1,-.0894841775f,-1.2914855480f)));
        lms=lms*lms*lms;
        return float3(dot(lms,float3(4.0767416621f,-3.3077115913f,.2309699292f)),
                      dot(lms,float3(-1.2684380046f,2.6097574011f,-.3413193965f)),
                      dot(lms,float3(-.0041960863f,-.7034186147f,1.7076147010f)));
    }
    float4 sampleGradient(float4 a,float4 b,float t,bool pair) {
        float4 c=pair ? mix(float4(lab(a.rgb),a.a),float4(lab(b.rgb),b.a),t) : float4(lab(a.rgb),a.a);
        return float4(fromLab(c.rgb),c.a);
    }
    float4 over(float4 f,float4 b) {
        float a=f.a+b.a*(1-f.a);
        return a>0 ? float4((f.rgb*f.a+b.rgb*b.a*(1-f.a))/a,a) : float4(0);
    }
    float4 themeLayer(Vertex v, constant Config &c) {
        float4 base=sampleGradient(c.base0,c.base1,clamp(v.baseT*(4.0f/3.0f),0.0f,1.0f),c.parameters.y>1);
        base.a*=c.parameters.x;
        if(c.parameters.z>0) {
            float4 top=sampleGradient(c.overlay0,c.overlay1,v.overlayT,true);
            top.a*=c.parameters.x; base=over(top,base);
        }
        base.rgb=encodedRGB(base.rgb);
        return over(base,c.underlay);
    }
    fragment float4 themeGradientFragment(Vertex v [[stage_in]], constant Config &c [[buffer(0)]]) {
        float4 result=themeLayer(v,c);
        return float4(result.rgb*result.a,result.a);
    }
    // gradientFragment's two-layer case: the straight layer colours mix by
    // the progress, then premultiply. An absent layer is clear.
    fragment float4 themeTransitionGradientFragment(Vertex v [[stage_in]], constant Config &c [[buffer(0)]],
        constant Config &next [[buffer(1)]], constant float4 &mixing [[buffer(2)]]) {
        float4 from=themeLayer(v,c), to=themeLayer(v,next);
        if(mixing.y<0.5f) from=float4(to.rgb,0);
        if(mixing.z<0.5f) to=float4(from.rgb,0);
        float4 result=mix(from,to,mixing.x);
        return float4(result.rgb*result.a,result.a);
    }
    constexpr sampler themeSampler(coord::normalized,address::clamp_to_edge,filter::linear);
    float4 themeOverlay(float2 uv, texture2d<float> texture, constant OutputConfig &config) {
        float4 c=config.parameters;
        if(c.w<0.5f) return float4(0);
        // Textures are premultiplied at load; multiplying all channels matches
        // the original unpremultiply → alpha scale → premultiply sequence.
        return texture.sample(themeSampler,fract(uv*c.xy))*c.z;
    }
    float4 themeComposite(float4 background, float4 overlay) {
        return overlay*(1-background.a+background)+background*(1-overlay.a);
    }
    fragment float4 themeOutputFragment(Vertex v [[stage_in]],
        texture2d<float> gradient [[texture(0)]], texture2d<float> texture [[texture(1)]],
        constant OutputConfig &config [[buffer(0)]]) {
        float2 uv=config.sampleRect.xy+v.uv*config.sampleRect.zw;
        float4 background=gradient.sample(themeSampler,uv);
        if(config.parameters.w<0.5f) return background;
        return themeComposite(background,themeOverlay(uv,texture,config));
    }
    // overlayFragment's two textures mix by the progress over the mixed
    // gradient; renderFragment composites them as for one theme.
    fragment float4 themeTransitionFragment(Vertex v [[stage_in]],
        texture2d<float> gradient [[texture(0)]], texture2d<float> texture [[texture(1)]],
        texture2d<float> nextTexture [[texture(2)]],
        constant OutputConfig &config [[buffer(0)]], constant OutputConfig &next [[buffer(1)]],
        constant float4 &mixing [[buffer(2)]]) {
        float2 uv=config.sampleRect.xy+v.uv*config.sampleRect.zw;
        float4 overlay=mix(themeOverlay(uv,texture,config),themeOverlay(uv,nextTexture,next),mixing.x);
        return themeComposite(gradient.sample(themeSampler,uv),overlay);
    }
    """#
}
