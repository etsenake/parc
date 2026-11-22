import AppKit
@testable import Parc
@testable import ParcNotes
@testable import ParcEasels
import ParcCore

@MainActor final class StandInPageSurface: NSView {
    let page: NSImage?
    var scroll: CGFloat = 0 { didSet { needsDisplay = true } }
    private let back = NSButton(), forward = NSButton(), reload = NSButton(), done = NSButton(), security = NSButton()
    private let label = NSButton(title: "kites.example", target: nil, action: nil)
    override var isFlipped: Bool { true }

    init(page: NSImage?, host: String) {
        self.page = page
        super.init(frame: .zero)
        for (button, title, symbol) in [(back, "Back", "chevron.left"), (forward, "Forward", "chevron.right"),
                                        (reload, "Reload", "arrow.clockwise"), (done, "Return to Easel", "checkmark"),
                                        (security, "Site information", "lock")] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.bezelStyle = .texturedRounded; button.title = ""; button.isEnabled = false
            addSubview(button)
        }
        label.title = host
        label.font = .systemFont(ofSize: 11); label.lineBreakMode = .byTruncatingMiddle
        label.isBordered = false; label.alignment = .left; label.isEnabled = false
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        back.frame = NSRect(x: 4, y: 3, width: 25, height: 25)
        forward.frame = NSRect(x: 30, y: 3, width: 25, height: 25)
        reload.frame = NSRect(x: 56, y: 3, width: 25, height: 25)
        done.frame = NSRect(x: max(82, bounds.width - 30), y: 3, width: 25, height: 25)
        security.frame = NSRect(x: 82, y: 3, width: 25, height: 25)
        label.frame = NSRect(x: 140, y: 9, width: max(0, bounds.width - 178), height: 17)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).addClip()
        EaselAppearance.surface.setFill(); bounds.fill()
        let clip = NSRect(x: 0, y: 32, width: bounds.width, height: max(1, bounds.height - 32))
        NSBezierPath(rect: clip).addClip()
        if let page {
            let height = page.size.height * bounds.width / page.size.width
            page.draw(in: NSRect(x: 0, y: 32 - scroll, width: bounds.width, height: height), from: .zero, operation: .sourceOver,
                      fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    var maximumScroll: CGFloat {
        guard let page else { return 0 }
        return max(0, page.size.height * bounds.width / page.size.width - (bounds.height - 32))
    }
}

@MainActor final class StandInPageObjects: EaselBrowserObjectHosting {
    var surfaces: [UUID: StandInPageSurface] = [:]
    func surface(for item: EaselItem) -> NSView? { surfaces[item.id] }
    func synchronize(items: [EaselItem], selection: Set<UUID>, interacting: Bool) {}
    func prepareReplacement(_ next: EaselDocument, valid: @escaping () -> Bool, completion: @escaping (Bool) -> Void) { completion(true) }
}

@MainActor final class EaselScene {
    let scene: BrowserScene
    let root = EaselDocumentView(frame: NSRect(x: 0, y: 0, width: 1042, height: 820))
    let scroll = NSScrollView()
    let canvas: EaselCanvasView
    let session: EaselSession
    let pages = StandInPageObjects()
    let web: StandInPageSurface
    let ids: (web: UUID, sticky: UUID, card: UUID, arrow: UUID)
    var canvasOrigin: NSPoint { NSPoint(x: scene.surface.pageCard.minX, y: scene.surface.pageCard.minY + Self.canvasTop) }

    static func scenario() -> Scenario {
        var made = ScenarioBuilder.make()
        let quest = made.spaces[2]
        made.state.activeSpaceID = quest.id
        let url = "parc://easel/" + UUID().uuidString.lowercased()
        let easel = ScenarioBuilder.tab(CanonTab("Kite weekend", url, .today, "scribble.variable", 0x2F9E6E), in: quest, order: 900)
        made.state.tabs.append(easel)
        SidebarHierarchy.placingCreatedTab(easel.id, insertion: .automatic, in: &made.state)
        made.state.selectedTabIDs = [easel.id]
        made.state.selectionBySpace[quest.id.uuidString] = [easel.id]
        made.selected = easel
        made.selectedBySpace[quest.id] = easel
        made.todayTitles = [easel.title] + Canon.questToday.map(\.title)
        return made
    }

    init(pagesDirectory: String) {
        let made = Self.scenario()
        scene = BrowserScene(size: NSSize(width: 1440, height: 900), windowRect: NSRect(x: 80, y: 18, width: 1280, height: 840),
                             scale: 2, pagePath: "", scenario: made)
        let kite = NSImage(contentsOfFile: pagesDirectory + "/kite.png")
        let picnicCrop = Self.crop(pagesDirectory + "/picnic.png")
        let webID = UUID(), stickyID = UUID(), cardID = UUID(), arrowID = UUID()
        ids = (webID, stickyID, cardID, arrowID)
        let now = Date(timeIntervalSince1970: 1_794_100_000)
        var sticky = EaselItem(kind: .text, frame: EaselRect(x: 720, y: 56, width: 200, height: 44), zIndex: 2)
        sticky.text = "Saturday picnic"
        sticky.textStyle = EaselTextStyle(fill: .contentHugging, family: .fancy, size: .h2)
        let start = NSPoint(x: 735, y: 110), end = NSPoint(x: 720, y: 474)
        let arrowFrame = EaselRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        let arrow = EaselItem(kind: .arrow, frame: arrowFrame, zIndex: 3,
                              points: [EaselPoint(x: start.x - arrowFrame.x, y: start.y - arrowFrame.y),
                                       EaselPoint(x: end.x - arrowFrame.x, y: end.y - arrowFrame.y)])
        let document = EaselDocument(id: UUID(), title: "Kite weekend", createdAt: now, modifiedAt: now, items: [
            EaselItem(id: webID, kind: .browser, frame: EaselRect(x: 40, y: 40, width: 600, height: 360), zIndex: 1,
                      url: "https://kites.example/delta-kite-guide"),
            { var item = sticky; item.id = stickyID; return item }(),
            EaselItem(id: cardID, kind: .image, frame: EaselRect(x: 692, y: 482, width: 270, height: 180), zIndex: 4, assetID: "picnic-crop"),
            { var item = arrow; item.id = arrowID; return item }(),
        ])
        session = try! EaselSession(inMemory: document, assets: ["picnic-crop": picnicCrop])
        canvas = EaselCanvasView(session: session)
        canvas.objectMotion.frameTime = { FilmClock.now }
        web = StandInPageSurface(page: kite, host: "kites.example")
        pages.surfaces[webID] = web
        canvas.pageObjects = pages
        root.appearance = NSAppearance(named: .aqua)
        buildChrome()
        settle()
        let card = scene.surface.pageCard
        scene.surface.drawPage = { [weak self] rect in
            guard let self, let image = self.editorImage else { NSColor.white.setFill(); rect.fill(); return }
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        _ = card
    }

    var editorImage: NSImage?

    static func crop(_ path: String) -> Data {
        guard let image = NSImage(contentsOfFile: path), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return Data() }
        let inset = Int(Double(cg.width) * 0.057), width = cg.width - 2 * inset, height = Int(Double(width) / 1.5)
        let top = max(0, min(cg.height - height, Int(Double(cg.height) * 0.18)))
        guard let cropped = cg.cropping(to: CGRect(x: inset, y: top, width: width, height: height)) else { return Data() }
        return NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]) ?? Data()
    }

    static let canvasTop: CGFloat = 64
    let palette = EaselToolPalette(frame: .zero)

    func buildChrome() {
        let titleField = NSTextField()
        titleField.stringValue = session.document.title
        titleField.font = NoteTheme.nunitoExtraBold(24)
        titleField.textColor = NoteTheme.titleInk
        titleField.isBezeled = false; titleField.drawsBackground = false
        root.addSubview(titleField)
        let count = session.document.items.count
        let status = NSTextField(labelWithString: "Saved on this Mac · \(count) object\(count == 1 ? "" : "s")")
        status.font = NoteTheme.captionFont(); status.textColor = NoteTheme.secondaryInk
        root.addSubview(status)
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true; scroll.minMagnification = 0.3333; scroll.maxMagnification = 4
        scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.documentView = canvas; root.addSubview(scroll)
        palette.scrollPassthrough = { [weak canvas] in canvas }
        palette.update(tool: canvas.tool, shape: canvas.toolState.shape)
        palette.showsMermaid = canvas.acceptsMermaid
        palette.showsTemplates = canvas.acceptsTemplates
        palette.setZoom(percent: EaselZoom.percent(Double(scroll.magnification)))
        let chrome = NSStackView()
        chrome.orientation = .horizontal; chrome.spacing = 2
        let chromeSize = NoteTheme.toolbarButtonSize.width
        func chromeButton(_ label: String, _ symbol: String, shortcut: String? = nil) -> NSButton {
            let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) ?? NSImage()
            let b = EaselPaletteButton(image: glyph, target: nil, action: nil)
            b.setEaselTooltip(label, shortcut: shortcut); b.setAccessibilityLabel(label)
            b.widthAnchor.constraint(equalToConstant: chromeSize).isActive = true
            b.heightAnchor.constraint(equalToConstant: chromeSize).isActive = true
            chrome.addArrangedSubview(b); return b
        }
        let pageButton = EaselPageSwitcherButton()
        pageButton.pageName = canvas.currentPageName
        pageButton.heightAnchor.constraint(equalToConstant: chromeSize).isActive = true
        chrome.addArrangedSubview(pageButton)
        let timer = EaselTimerButton(documentID: session.document.id)
        chrome.addArrangedSubview(timer)
        _ = chromeButton("Undo Easel change", "arrow.uturn.backward", shortcut: "⌘Z")
        chromeButton("Redo Easel change", "arrow.uturn.forward", shortcut: "⇧⌘Z").isEnabled = false
        _ = chromeButton("Easel Options", "ellipsis")
        root.addSubview(chrome)
        root.addSubview(palette)
        let width = root.bounds.width, height = root.bounds.height, canvasTop = Self.canvasTop
        let bar = EaselFloatingBar.frame(containerWidth: Double(width), containerHeight: Double(height),
                                         preferredWidth: Double(palette.preferredWidth), height: Double(EaselAppearance.toolbarHeight),
                                         top: Double(canvasTop + 8))
        palette.frame = NSRect(x: bar.x, y: bar.y, width: bar.width, height: bar.height)
        canvas.setCoveredBottom(CGFloat(EaselFloatingBar.coveredBottom(containerHeight: Double(height), bar: bar)))
        let pageWidth = pageButton.intrinsicContentSize.width
        let chromeWidth: CGFloat = 3 * chromeSize + 4 * 2 + timer.intrinsicContentSize.width + pageWidth
        titleField.frame = NSRect(x: 24, y: 10, width: max(80, width - chromeWidth - 52), height: 32)
        chrome.frame = NSRect(x: max(24, width - chromeWidth - 14), y: 12, width: chromeWidth, height: chromeSize)
        status.frame = NSRect(x: 26, y: 40, width: max(100, width - 52), height: 18)
        scroll.frame = NSRect(x: 0, y: canvasTop, width: width, height: max(80, height - canvasTop))
        canvas.resizeCanvas(viewport: scroll.contentSize)
    }

    func settle() {
        RunLoop.main.run(until: Date())
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        root.layoutSubtreeIfNeeded()
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
    }

    func event(_ type: NSEvent.EventType, _ point: NSPoint, time: Double, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 1000 + time,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    func snapshot(_ view: NSView) -> NSBitmapImageRep {
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(view.bounds.width * scale)),
                                   pixelsHigh: Int(ceil(view.bounds.height * scale)), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    func renderEditor() {
        settle()
        let size = root.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2084, pixelsHigh: 1640, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        let now = FilmClock.now
        let moving: [(item: EaselItem, view: NSView, shown: EaselObjectPresentation)] = session.document.items
            .sorted { $0.zIndex < $1.zIndex }.compactMap { item in
                guard !item.ownsEmbeddedPage, let view = canvas.artwork[item.id], !view.isHidden else { return nil }
                let shown = canvas.objectMotion.timeline.presentation(for: item.id, at: now)
                return shown.isIdentity ? nil : (item, view, shown)
            }
        func place(_ view: NSView) -> NSRect {
            let box = view.convert(view.bounds, to: root)
            return NSRect(x: box.minX, y: size.height - box.maxY, width: box.width, height: box.height)
        }
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            scroll.isHidden = true
            root.cacheDisplay(in: root.bounds, to: rep)
            scroll.isHidden = false
            for entry in moving { entry.view.isHidden = true }
            canvas.decoration.isHidden = !moving.isEmpty
            let board = snapshot(scroll)
            for entry in moving { entry.view.isHidden = false }
            canvas.decoration.isHidden = false
            let lifted = moving.map { ($0, snapshot($0.view)) }
            let marks = moving.isEmpty ? nil : snapshot(canvas.decoration)
            let bar = snapshot(palette)
            NSGraphicsContext.saveGraphicsState()
            let graphics = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.current = graphics
            let context = graphics.cgContext
            let pixels = CGFloat(rep.pixelsWide) / size.width
            board.draw(in: place(scroll), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            for (entry, image) in lifted {
                let shown = entry.shown, box = EaselCanvasRotation.bounds(entry.item)
                let middle = canvas.convert(NSPoint(x: box.midX, y: box.midY), to: root)
                let centre = NSPoint(x: middle.x + CGFloat(shown.offset.x), y: size.height - middle.y - CGFloat(shown.offset.y))
                let frame = place(entry.view)
                let flippedMiddle = NSPoint(x: middle.x, y: size.height - middle.y)
                context.saveGState()
                context.setAlpha(CGFloat(min(1, max(0, shown.opacity))))
                if shown.shadow > 0 {
                    let amount = min(1, shown.shadow)
                    context.setShadow(offset: CGSize(width: 0, height: -6 * pixels), blur: CGFloat(6 + 22 * amount) * pixels,
                                      color: NSColor.black.withAlphaComponent(CGFloat(amount * 0.24)).cgColor)
                }
                context.translateBy(x: centre.x, y: centre.y)
                context.rotate(by: -CGFloat(shown.rotation * Double.pi / 180))
                context.scaleBy(x: CGFloat(shown.scaleX), y: CGFloat(shown.scaleY))
                context.translateBy(x: -flippedMiddle.x, y: -flippedMiddle.y)
                image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
                context.restoreGState()
            }
            marks?.draw(in: place(canvas.decoration), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            bar.draw(in: place(palette), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        editorImage = image
        scene.surface.needsDisplay = true
    }

    func renderStage() -> CGImage {
        renderEditor()
        return scene.render(NSRect(origin: .zero, size: NSSize(width: 1440, height: 900)), pixelsWide: 2880, pixelsHigh: 1800).cgImage!
    }

    func item(_ id: UUID) -> EaselItem? { session.document.items.first { $0.id == id } }

    func run(out: String, still: Bool) {
        let duration = 9.0
        let frames = Int(duration * Film.fps)
        var beats: [Beat] = []
        func beat(_ time: Double, _ text: String) { beats.append(Beat(time: time, frame: Int((time * Film.fps).rounded()), beat: text)) }
        let card0 = item(ids.card)!.frame
        let grab = NSPoint(x: card0.x + 136, y: card0.y + 92)
        let fastEnd = NSPoint(x: grab.x - 24, y: grab.y - 248)
        let slowEnd = NSPoint(x: grab.x - 29.5, y: grab.y - 263.6)
        let arrowEnd0 = NSPoint(x: 720, y: 474)
        let arrowMid = NSPoint(x: 735 + (720 - 735) * 0.2, y: 110 + (474 - 110) * 0.2)
        let arrowEnd1 = NSPoint(x: 748, y: 211)
        let rest = NSPoint(x: 560, y: 640)
        let blank = NSPoint(x: 420, y: 560)
        let t = (approach: 2.15, down: 2.8, fast: 3.45, slow: 4.3, hold: 4.65, drift: 4.95, up: 5.05,
                 toArrow: 5.25, arrowClick: 5.7, toEnd: 5.85, endDown: 6.25, endDrag: 7.2, endUp: 7.3,
                 toBlank: 7.45, blankClick: 7.85)
        beat(0, "Easel \"Kite weekend\" in the Side quest Space: live webpage card, sticky, picnic image card, arrow; nothing selected")
        beat(0.5, "Live page card scrolls inside its clip (stand-in page pixels)")
        beat(t.down, "Mouse down on the picnic image card: selected (blue outline, corner handles)")
        beat(t.down + 0.02, "Fast drag (about 380 pt/s): above the 125 pt/s guide threshold, so no snapping; handles hidden while dragging")
        beat(t.fast, "Slow approach (about 20 pt/s) into alignment")
        beat(t.slow, "Snapped: bottom edge flush with the webpage card and 24 pt spacing guide from its right edge; guides drawn")
        beat(t.hold, "Hold, then a 3 pt drift stays snapped (hysteresis)")
        beat(t.up, "Mouse up: move commits, guides vanish, outline and handles return")
        beat(t.arrowClick, "Click the arrow: endpoint handles appear")
        beat(t.endDown, "Drag the arrow's end handle to the card's new top edge (the arrow follows)")
        beat(t.endUp, "Release: endpoint move commits")
        beat(t.blankClick, "Click empty canvas: selection clears")
        beat(7.9, "Live page card eases a little further")
        beat(duration, "End")
        var strip: [(Double, CGImage)] = []
        let stripTimes = [0.3, 1.5, 2.85, 3.2, 3.9, 4.4, 5.1, 5.75, 6.7, 7.32, 8.0, 8.9]
        let writer = still ? nil : try! AlphaVideoWriter(path: out + "/easel.mov", width: 2880, height: 1800)
        var pressed = false, endPressed = false
        var arrowClicked = false, blankClicked = false, released = false, endReleased = false
        let renderFrames = still ? [20, 175, 200, 260, 270, 285, 306, 310, 345, 400, 440, 520] : Array(0..<frames)
        var lastPointer = rest
        func pointerAt(_ time: Double) -> NSPoint {
            func lerp(_ a: NSPoint, _ b: NSPoint, _ p: Double) -> NSPoint {
                NSPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
            }
            if time < t.approach { return rest }
            if time < t.down { return lerp(rest, grab, Film.easeInOut(Film.progress(time, t.approach, t.down - 0.1))) }
            if time < t.fast { return lerp(grab, fastEnd, Film.ease(Film.progress(time, t.down + 0.05, t.fast))) }
            if time < t.slow { return lerp(fastEnd, slowEnd, Film.progress(time, t.fast, t.slow)) }
            if time < t.hold { return slowEnd }
            if time < t.up {
                let p = Film.progress(time, t.hold, t.drift)
                return NSPoint(x: slowEnd.x, y: slowEnd.y + 3 * sin(Double.pi * p))
            }
            let dropped = slowEnd
            if time < t.arrowClick { return lerp(dropped, arrowMid, Film.easeInOut(Film.progress(time, t.toArrow, t.arrowClick - 0.08))) }
            if time < t.endDown { return lerp(arrowMid, arrowEnd0, Film.easeInOut(Film.progress(time, t.toEnd, t.endDown - 0.08))) }
            if time < t.endUp { return lerp(arrowEnd0, arrowEnd1, Film.easeInOut(Film.progress(time, t.endDown + 0.05, t.endDrag))) }
            if time < t.blankClick { return lerp(arrowEnd1, blank, Film.easeInOut(Film.progress(time, t.toBlank, t.blankClick - 0.08))) }
            return lerp(blank, NSPoint(x: blank.x - 30, y: blank.y + 50), Film.easeInOut(Film.progress(time, 8.1, 8.9)))
        }
        var probe: [String] = []
        probe.append("canvas visibleRect \(canvas.visibleRect) frame \(canvas.frame) scroll content \(scroll.contentSize)")
        for frame in renderFrames {
            let time = Double(frame) / Film.fps
            FilmClock.now = 1000 + time
            scroll.contentView.postsBoundsChangedNotifications = false
            let scrollValue: Double
            if time < 7.9 { scrollValue = 96 * Film.easeInOut(Film.progress(time, 0.5, 2.3)) }
            else { scrollValue = 96 + 26 * Film.easeInOut(Film.progress(time, 7.9, 8.9)) }
            web.scroll = CGFloat(scrollValue)
            let point = pointerAt(time)
            if time >= t.down && !pressed {
                pressed = true
                canvas.mouseDown(with: event(.leftMouseDown, grab, time: t.down))
            }
            if pressed && !released && time > t.down && time < t.up && point != lastPointer {
                canvas.mouseDragged(with: event(.leftMouseDragged, point, time: time))
            }
            if time >= t.up && !released {
                released = true
                canvas.mouseUp(with: event(.leftMouseUp, slowEnd, time: t.up))
                probe.append("card after drop \(item(ids.card)!.frame)")
            }
            if time >= t.arrowClick && !arrowClicked {
                arrowClicked = true
                canvas.mouseDown(with: event(.leftMouseDown, arrowMid, time: t.arrowClick))
                canvas.mouseUp(with: event(.leftMouseUp, arrowMid, time: t.arrowClick + 0.08))
            }
            if time >= t.endDown && !endPressed {
                endPressed = true
                canvas.mouseDown(with: event(.leftMouseDown, arrowEnd0, time: t.endDown))
            }
            if endPressed && !endReleased && time > t.endDown && time < t.endUp && point != lastPointer {
                canvas.mouseDragged(with: event(.leftMouseDragged, point, time: time))
            }
            if time >= t.endUp && !endReleased {
                endReleased = true
                canvas.mouseUp(with: event(.leftMouseUp, arrowEnd1, time: t.endUp))
                probe.append("arrow after endpoint drag \(item(ids.arrow)!.frame) points \(item(ids.arrow)!.points)")
            }
            if time >= t.blankClick && !blankClicked {
                blankClicked = true
                canvas.mouseDown(with: event(.leftMouseDown, blank, time: t.blankClick))
                canvas.mouseUp(with: event(.leftMouseUp, blank, time: t.blankClick + 0.07))
            }
            scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
            lastPointer = point
            let overEndpoint = arrowClicked && !blankClicked && hypot(point.x - (endPressed ? point.x : arrowEnd0.x), point.y - (endPressed ? point.y : arrowEnd0.y)) < 10
            scene.pointer.cursor = overEndpoint ? .pointingHand : .arrow
            scene.pointer.location = NSPoint(x: canvasOrigin.x + point.x, y: canvasOrigin.y + point.y)
            canvas.objectMotionFrame()
            _ = canvas.canvasFeedbackFrame()
            if frame % 15 == 0 { probe.append("t \(time) card \(canvas.objectMotion.timeline.presentation(for: ids.card, at: FilmClock.now))") }
            let image = renderStage()
            writer?.append(image)
            if still { Film.writePNG(image, out + "/easel-still-\(frame).png") }
            if stripTimes.contains(where: { Int(($0 * Film.fps).rounded()) == frame }) { strip.append((time, image)) }
            if frame % 60 == 0 { print("easel frame", frame) }
        }
        print(probe.joined(separator: "\n"))
        try? probe.joined(separator: "\n").write(toFile: out + "/easel-probe.txt", atomically: true, encoding: .utf8)
        if let writer {
            let result = writer.finish()
            print("wrote", out + "/easel.mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
            Film.writeStrip(strip, path: out + "/easel-strip.png")
            Film.writeBeats(beats, path: out + "/easel-beats.json")
        }
    }
}
