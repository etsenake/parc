import AppKit
@testable import Parc
@testable import ParcKit
@testable import ParcCommandBar
import ParcCore

struct BarRow {
    let id: String
    let title: String
    var subtitle: String? = nil
    var accessory: String = ""
    var isTab = false
    var icon: NSImage?
    var isAction = false
}

@MainActor final class CommandBarOverlay: NSView {
    var bar = NSRect.zero
    var backdrop: CGImage?
    var shown = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard shown, let context = NSGraphicsContext.current?.cgContext else { return }
        let path = CGPath(roundedRect: bar, cornerWidth: 12, cornerHeight: 12, transform: nil)
        let scale = context.convertToDeviceSpace(CGSize(width: 1, height: 1)).width
        context.saveGState()
        let outside = CGMutablePath(); outside.addRect(bounds.insetBy(dx: -200, dy: -200)); outside.addPath(path)
        context.addPath(outside); context.clip(using: .evenOdd)
        context.setShadow(offset: CGSize(width: 0, height: 24 * abs(scale)), blur: 48 * abs(scale),
                          color: NSColor.black.withAlphaComponent(0.5).cgColor)
        context.addPath(path); context.setFillColor(NSColor.black.cgColor); context.fillPath()
        context.restoreGState()
        guard let backdrop else { return }
        context.saveGState()
        context.addPath(path); context.clip()
        context.translateBy(x: bar.minX, y: bar.maxY); context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(backdrop, in: CGRect(origin: .zero, size: bar.size))
        context.restoreGState()
    }
}

@MainActor final class Caret: NSView {
    var opacity: CGFloat = 1 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard opacity > 0 else { return }
        NSColor(srgbRed: 0, green: 0.533, blue: 1, alpha: opacity).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1, yRadius: 1).fill()
    }
}

@MainActor final class CommandBarScene {
    let scene: BrowserScene
    let picnicTab: BrowserTab
    let overlay: CommandBarOverlay
    let container = PopoverBackgroundView(blending: .withinWindow)
    let inputIcon = NSImageView()
    let input = NSTextField()
    let divider = CommandBarHairline(frame: .zero)
    let list = FlippedBox()
    let caret = Caret()
    let palette: CommandBarPalette
    var rowViews: [String: CommandResultRowView] = [:]
    var current: [BarRow] = []
    var article: NSImage?
    var picnic: NSImage?

    final class FlippedBox: NSView { override var isFlipped: Bool { true } }

    static func scenario() -> (Scenario, BrowserTab) {
        let made = ScenarioBuilder.make()
        let tab = ScenarioBuilder.tab(Canon.picnic, in: made.work, order: 500)
        return (made, tab)
    }

    init(pagesDirectory: String) {
        let (made, tab) = Self.scenario()
        picnicTab = tab
        article = NSImage(contentsOfFile: pagesDirectory + "/article.png")
        picnic = NSImage(contentsOfFile: pagesDirectory + "/picnic.png")
        scene = BrowserScene(size: NSSize(width: 1440, height: 900), windowRect: NSRect(x: 80, y: 18, width: 1280, height: 840),
                             scale: 2, pagePath: pagesDirectory + "/article.png", scenario: made)
        palette = CommandBarPalette(theme: made.work.theme)
        overlay = CommandBarOverlay(frame: NSRect(origin: .zero, size: scene.windowRect.size))
        scene.surface.addSubview(overlay, positioned: .below, relativeTo: scene.pointer)
        let width = max(260, min(765, scene.windowRect.width - 48))
        let x = scene.windowRect.width / 2 - width / 2
        let top = scene.windowRect.height / 2 - 326 / 2
        overlay.bar = NSRect(x: x, y: top, width: width, height: 326)
        container.frame = overlay.bar
        container.cornerRadius = 12
        container.appearance = NSAppearance(named: .aqua)
        container.translucency.alphaValue = 0
        overlay.addSubview(container)
        inputIcon.imageScaling = .scaleProportionallyDown
        inputIcon.contentTintColor = palette.inputIcon
        inputIcon.frame = NSRect(x: 22, y: 22, width: 18, height: 18)
        container.addSubview(inputIcon)
        input.isBordered = false; input.drawsBackground = false
        input.font = CommandBarTypography.field
        input.placeholderString = "Search or Enter URL…"
        input.usesSingleLineMode = true; input.cell?.wraps = false
        input.cell?.isScrollable = true; input.lineBreakMode = .byClipping
        input.focusRingType = .none
        input.textColor = palette.inputText
        input.frame = NSRect(x: 49, y: 21, width: width - 71, height: 31)
        container.addSubview(input)
        divider.frame = NSRect(x: 12, y: 64, width: width - 24, height: 0.5)
        container.addSubview(divider)
        list.frame = NSRect(x: 8, y: 68, width: width - 16, height: 326 - 76)
        container.addSubview(list)
        container.addSubview(caret)
        overlay.isHidden = true
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
    }

    static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? SidebarPlusMenuArtwork.image(name)
    }

    static func favicon(_ url: String) -> NSImage? { Favicons.specs[url].map(Favicons.image) }

    static func rows(for query: String) -> [BarRow] {
        let picnicTab = BarRow(id: "history:picnic", title: Canon.picnic.title, subtitle: CommandBarResultText.urlSubtitle(Canon.picnic.url),
                               icon: favicon(Canon.picnic.url))
        func search(_ text: String) -> BarRow { BarRow(id: "search:" + text, title: text, icon: symbol("magnifyingglass")) }
        let note = BarRow(id: "note:picnic", title: "Picnic packing list", icon: symbol("note.text"))
        switch query {
        case "":
            return [
                BarRow(id: "tab:urban-parks", title: Canon.urbanParks.title, accessory: "Switch to Tab", isTab: true,
                       icon: favicon(Canon.urbanParks.url)),
                BarRow(id: "tab:roadmap", title: "Quarterly roadmap draft", accessory: "Switch to Tab", isTab: true,
                       icon: favicon("https://docs.example.com/roadmap")),
                BarRow(id: "history:garden", title: "Community garden volunteer day", subtitle: "— parks.example/garden-day", icon: symbol("clock")),
                BarRow(id: "history:bread", title: "Sourdough starter, step by step", subtitle: "— breadnotes.example/starter", icon: symbol("clock")),
                BarRow(id: "history:weather", title: "Weekend forecast", subtitle: "— weather.example/weekend", icon: symbol("clock")),
            ]
        case "p":
            return [
                BarRow(id: "cmd:print", title: "Print Page", accessory: KeyboardShortcut(key: "p", flags: [.command]).display,
                       icon: symbol("printer"), isAction: true),
                search("parks near me"), search("pasta recipes"), picnicTab,
                BarRow(id: "history:pottery", title: "Pottery wheel basics", subtitle: "— clayhouse.example/wheel", icon: symbol("clock")),
            ]
        case "pi":
            return [search("pizza dough"), search("pilates classes"), picnicTab, search("pie crust recipe"), note]
        case "pic":
            return [picnicTab, search("picnic"), search("pictures"), note, search("pickled onions")]
        case "picn", "picni":
            return [picnicTab, search("picnic"), note, search("picnic ideas"), search("picnic table plans")]
        default:
            return [picnicTab, search("picnic"), note, search("picnic ideas for summer"),
                    BarRow(id: "history:spots", title: "Best picnic spots in the city — Weekend Guide",
                           subtitle: "— weekendguide.example/picnic-spots", icon: favicon("https://weekendguide.example/picnic-spots") ?? symbol("clock"))]
        }
    }

    func publish(_ rows: [BarRow]) {
        let ids = Set(rows.map(\.id))
        for (id, view) in rowViews where !ids.contains(id) { view.removeFromSuperview(); rowViews[id] = nil }
        for (index, row) in rows.enumerated() {
            let view: CommandResultRowView
            if let existing = rowViews[row.id] { view = existing } else {
                view = CommandResultRowView(frame: NSRect(x: 0, y: 0, width: list.bounds.width, height: 50))
                view.selectedColor = palette.selected
                view.selectionHighlightStyle = .none
                let cell = CommandResultCell(title: row.title, subtitle: row.subtitle, detail: "", accessory: row.accessory,
                                             isTab: row.isTab, icon: row.icon, enabled: true, isAction: row.isAction)
                cell.selectedColor = palette.selected
                cell.frame = view.bounds
                cell.autoresizingMask = [.width, .height]
                view.addSubview(cell)
                list.addSubview(view)
                rowViews[row.id] = view
            }
            view.frame = NSRect(x: 0, y: CGFloat(index) * 50, width: list.bounds.width, height: 50)
            view.needsLayout = true
        }
        current = rows
        list.layoutSubtreeIfNeeded()
    }

    func select(_ index: Int, fadingFrom previous: Int?, progress: Double) {
        let base = palette.selected.usingColorSpace(.sRGB) ?? palette.selected
        let p = CGFloat(Film.caDefault(progress))
        for (offset, row) in current.enumerated() {
            guard let view = rowViews[row.id] else { continue }
            let changing = previous != nil && previous != index && p < 1
            let fadingOut = changing && offset == previous
            let target = offset == index
            view.isSelected = target || fadingOut
            if fadingOut { view.subviews.compactMap { $0 as? CommandResultCell }.forEach { $0.setSelected(false) } }
            var amount: CGFloat = target ? 1 : 0
            if changing { if target { amount = p } else if fadingOut { amount = 1 - p } }
            view.selectedColor = NSColor(srgbRed: base.redComponent * amount, green: base.greenComponent * amount,
                                         blue: base.blueComponent * amount, alpha: base.alphaComponent * amount)
        }
        updateInputIcon(index)
    }

    func updateInputIcon(_ index: Int) {
        if input.stringValue.isEmpty || !current.indices.contains(index) {
            inputIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        } else {
            inputIcon.image = current[index].icon
        }
    }

    func placeCaret(opacity: CGFloat) {
        let text = NSAttributedString(string: input.stringValue, attributes: [.font: CommandBarTypography.field])
        let width = input.stringValue.isEmpty ? 0 : ceil(text.size().width)
        caret.frame = NSRect(x: input.frame.minX + 2 + width, y: 21.5, width: 2, height: 22)
        caret.opacity = opacity
    }

    func showPage(_ image: NSImage?) {
        guard let image else { return }
        scene.surface.drawPage = { card in
            NSColor.white.setFill(); card.fill()
            let scale = card.width / image.size.width
            image.draw(in: NSRect(x: card.minX, y: card.minY, width: card.width, height: image.size.height * scale),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                       hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
        scene.surface.needsDisplay = true
    }

    func focus(_ tab: BrowserTab) {
        var state = scene.scenario.state
        if !state.tabs.contains(where: { $0.id == tab.id }) {
            state.tabs.append(tab)
            SidebarHierarchy.placingCreatedTab(tab.id, insertion: .automatic, in: &state)
        }
        state.selectedTabIDs = [tab.id]
        state.selectionBySpace[state.activeSpaceID.uuidString] = [tab.id]
        scene.sidebar.render(state: state, focusedTabID: tab.id, loading: [], canBack: true, canForward: false)
        let end = Date().addingTimeInterval(0.6)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        scene.sidebar.needsLayout = true
        scene.sidebar.layoutSubtreeIfNeeded()
    }

    func renderStage() -> CGImage {
        scene.render(NSRect(origin: .zero, size: NSSize(width: 1440, height: 900)), pixelsWide: 2880, pixelsHigh: 1800).cgImage!
    }

    func refreshBackdrop() {
        overlay.isHidden = true
        let beneath = renderStage()
        let bar = overlay.bar.offsetBy(dx: scene.windowRect.minX, dy: scene.windowRect.minY)
        overlay.backdrop = Film.blurredBackdrop(beneath, crop: CGRect(x: bar.minX * 2, y: bar.minY * 2, width: bar.width * 2, height: bar.height * 2),
                                                radius: 50)
        overlay.isHidden = false
    }

    func run(out: String, still: Bool) {
        let keys: [(Double, String)] = [(1.50, "p"), (1.63, "pi"), (1.76, "pic"), (1.97, "picn"), (2.09, "picni"), (2.21, "picnic")]
        let open = 0.8, down = 3.30, up = 3.95, enter = 4.70, duration = 8.0
        var beats: [Beat] = []
        func beat(_ time: Double, _ text: String) { beats.append(Beat(time: time, frame: Int((time * Film.fps).rounded()), beat: text)) }
        beat(0, "Window at rest in the Work Space: sidebar plus the article page")
        beat(open, "Command-T: the command bar appears in one frame, empty field with placeholder and magnifier, recent tabs and visits")
        for (time, text) in keys { beat(time, "Keystroke: \"\(text)\" (rows republish instantly; top row selected)") }
        beat(down, "Down arrow: highlight cross-fades to row 2 (0.25 s, Core Animation default curve)")
        beat(up, "Up arrow: highlight cross-fades back to the open tab")
        beat(enter, "Return: bar vanishes in one frame, Parc opens the picnic page in a new tab at the top of Today")
        beat(duration, "End")
        let frames = Int(duration * Film.fps)
        let stripTimes = [0.4, 0.82, 1.3, 1.55, 1.8, 2.25, 2.8, 3.42, 3.7, 4.1, 4.72, 6.5]
        var strip: [(Double, CGImage)] = []
        let writer = still ? nil : try! AlphaVideoWriter(path: out + "/commandbar.mov", width: 2880, height: 1800)
        var backdropReady = false
        var lastQuery: String? = nil
        var switched = false
        let renderFrames = still ? [24, 60, 95, 140, 200, 240, 290] : Array(0..<frames)
        for frame in renderFrames {
            let t = Double(frame) / Film.fps
            let visible = t >= open && t < enter
            if t >= enter && !switched {
                switched = true
                overlay.isHidden = true; overlay.shown = false
                showPage(picnic)
                focus(picnicTab)
            }
            if visible {
                if !backdropReady { refreshBackdrop(); backdropReady = true }
                overlay.isHidden = false; overlay.shown = true
                let query = keys.last(where: { $0.0 <= t })?.1 ?? ""
                if query != lastQuery {
                    input.stringValue = query
                    publish(Self.rows(for: query))
                    lastQuery = query
                }
                var selected = 0, previous: Int? = nil, progress = 1.0
                if t >= down && t < up { selected = 1; previous = 0; progress = Film.progress(t, down, down + 0.25) }
                if t >= up { selected = 0; previous = 1; progress = Film.progress(t, up, up + 0.25) }
                select(selected, fadingFrom: previous, progress: progress)
                let lastKey = max(open, keys.last(where: { $0.0 <= t })?.0 ?? open)
                let idle = t - lastKey
                var opacity: CGFloat = 1
                if idle > 0.5 {
                    let phase = (idle - 0.5).truncatingRemainder(dividingBy: 1.0)
                    let fade = 0.12
                    if phase < 0.5 { opacity = phase < fade ? CGFloat(1 - phase / fade) : 0 }
                    else { opacity = phase - 0.5 < fade ? CGFloat((phase - 0.5) / fade) : 1 }
                }
                placeCaret(opacity: opacity)
                container.layoutSubtreeIfNeeded()
                container.updateLayer()
                divider.updateLayer()
            }
            let image = renderStage()
            writer?.append(image)
            if still { Film.writePNG(image, out + "/commandbar-still-\(frame).png") }
            if stripTimes.contains(where: { Int(($0 * Film.fps).rounded()) == frame }) { strip.append((t, image)) }
            if frame % 60 == 0 { print("commandbar frame", frame) }
        }
        if let writer {
            let result = writer.finish()
            print("wrote", out + "/commandbar.mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
            Film.writeStrip(strip, path: out + "/commandbar-strip.png")
            Film.writeBeats(beats, path: out + "/commandbar-beats.json")
        }
    }
}
