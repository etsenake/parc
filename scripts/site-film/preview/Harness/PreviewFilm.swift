import AppKit

@MainActor final class FlippedHost: NSView {
    override var isFlipped: Bool { true }
}

@MainActor final class TabPageView: NSView {
    let image: CGImage
    let header: CGFloat
    static let leftPiece: CGFloat = 360
    static let rightPiece: CGFloat = 420

    init(frame: NSRect, image: CGImage, header: CGFloat) {
        self.image = image
        self.header = header
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        hex(0xFFFDF8).setFill(); bounds.fill()
        let width = bounds.width, source = CGFloat(image.width)
        let crop = ((source - width) / 2).rounded(.down)
        context.saveGState()
        context.interpolationQuality = .high
        let left = Self.leftPiece, right = Self.rightPiece
        if let middle = image.cropping(to: CGRect(x: source / 2, y: 0, width: 1, height: header)) {
            drawUpright(middle, in: CGRect(x: left, y: 0, width: width - left - right, height: header), context)
        }
        if let piece = image.cropping(to: CGRect(x: 0, y: 0, width: left, height: header)) {
            drawUpright(piece, in: CGRect(x: 0, y: 0, width: left, height: header), context)
        }
        if let piece = image.cropping(to: CGRect(x: source - right, y: 0, width: right, height: header)) {
            drawUpright(piece, in: CGRect(x: width - right, y: 0, width: right, height: header), context)
        }
        let rest = CGFloat(image.height) - header
        if let body = image.cropping(to: CGRect(x: crop, y: header, width: width, height: rest)) {
            drawUpright(body, in: CGRect(x: 0, y: header, width: width, height: rest), context)
        }
        context.restoreGState()
    }

    static func fieldNotesKite(article: CGImage, kite: CGImage) -> (CGImage, CGFloat) {
        let header: CGFloat = 75, kiteHeader: CGFloat = 72
        let width = kite.width, height = Int(header) + kite.height - Int(kiteHeader)
        let context = PeekFilm.offscreenContext(width: width, height: height)
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        if let top = article.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(article.width), height: header)) {
            drawUpright(top, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: header), context)
        }
        if let body = kite.cropping(to: CGRect(x: 0, y: kiteHeader, width: CGFloat(kite.width), height: CGFloat(kite.height) - kiteHeader)) {
            drawUpright(body, in: CGRect(x: 0, y: header, width: CGFloat(width), height: CGFloat(kite.height) - kiteHeader), context)
        }
        return (context.makeImage()!, header)
    }
}

@MainActor final class PreviewFilm {
    let scene: BrowserScene
    let host: PeekHostView
    let page: TabPageView
    let layout: PeekWindowLayout
    let cardHost: FlippedHost
    let card: SidebarPreviewCard
    let openInPeek: ActionButton
    let closeButton: PeekControlButton
    let row: SidebarTabRow
    let rowRect: NSRect
    let peekRect: NSRect
    let closeRect: NSRect
    let anchor: NSPoint
    let rings: FlippedHost
    let hairline = CALayer()
    let closing: PeekDismissalMotion
    let fps = 60
    let duration = 7.0
    static let cardMargin: CGFloat = 48

    let start = NSPoint(x: 1060, y: 330)
    let onRow = NSPoint(x: 150, y: 471)
    let peekPoint: NSPoint
    let closePoint: NSPoint

    static let glideStart = 0.40, glideEnd = 1.50
    static let toButtonStart = 2.15, toButtonEnd = 2.75
    static let press = 3.05, click = 3.15
    static let toCloseStart = 3.95, toCloseEnd = 4.65
    static let closePress = 4.85, close = 4.95
    static let returnStart = 5.35, returnEnd = 6.25
    let enterRow: Double
    let cardIn: Double

    init(scene: BrowserScene, articlePath: String, kitePath: String) {
        self.scene = scene
        let aqua = NSAppearance(named: .aqua)!
        let (composite, header) = TabPageView.fieldNotesKite(article: loadCGImage(articlePath), kite: loadCGImage(kitePath))
        let bounds = NSRect(origin: .zero, size: scene.windowRect.size)
        let pageCard = scene.surface.pageCard
        layout = PeekWindowLayout(bounds: bounds, page: pageCard, stepsBack: true)
        host = PeekHostView(frame: bounds)
        host.appearance = aqua
        host.palette = scene.themeSurface.palette
        host.pageFrame = pageCard
        host.stepsBack = true
        host.canExpand = true
        host.canSplit = true
        host.subviews[0].isHidden = true
        host.layoutSubtreeIfNeeded()
        page = TabPageView(frame: host.content.bounds, image: composite, header: header)
        page.autoresizingMask = [.width, .height]
        host.content.addSubview(page)
        host.layoutSubtreeIfNeeded()
        let controls = BrowserScene.descendants(host).compactMap { $0 as? PeekControlButton }
        for button in controls { button.viewDidMoveToWindow() }
        page.frame = host.content.bounds
        let peekHost = host
        let top = controls.min { peekHost.convert($0.bounds, from: $0).minY < peekHost.convert($1.bounds, from: $1).minY }!
        closeButton = top
        closeRect = peekHost.convert(top.bounds, from: top)
        closePoint = NSPoint(x: closeRect.maxX - 7, y: closeRect.maxY - 5)
        var motion = PeekDismissalMotion(geometry: PeekDismissalMotion.Geometry(paneWidth: bounds.width, cardMinX: layout.card.minX))
        motion.exit(.fade, velocity: 0, reducesMotion: false, at: Self.close)
        closing = motion

        let tab = scene.scenario.state.tabs.first { $0.title == "Urban parks — Field Notes" }!
        row = scene.row(titled: tab.title)!
        rowRect = scene.surface.convert(row.bounds, from: row)
        let url = URL(string: tab.url)!
        cardHost = FlippedHost(frame: bounds)
        cardHost.appearance = aqua
        cardHost.wantsLayer = true
        card = SidebarPreviewCard(title: tab.title, domain: nil, providerURL: url,
                                  picture: Self.thumbnail(composite, header: header, pageWidth: pageCard.width),
                                  site: SidebarAddressSearchIcon.host(of: url) ?? url.absoluteString)
        card.appearance = aqua
        card.offersPeek = { _ in true }
        card.requestFavicon = { _, done in done(Favicons.image(for: tab)) }
        card.setRows([SidebarPreviewRow(id: tab.id.uuidString, tabID: tab.id, title: tab.title, url: url, visitedAt: nil)])
        card.placement = SidebarPreviewPlacement(row: rowRect, location: .right)
        cardHost.addSubview(card, positioned: .above, relativeTo: nil)
        card.place()
        card.layoutSubtreeIfNeeded()
        anchor = card.placement.anchor
        openInPeek = BrowserScene.descendants(card).compactMap { $0 as? ActionButton }.first { $0.toolTip == "Open in Peek" }!
        peekRect = cardHost.convert(openInPeek.bounds, from: openInPeek)
        peekPoint = NSPoint(x: peekRect.maxX - 3, y: peekRect.maxY - 3)
        rings = FlippedHost(frame: card.content.bounds)
        rings.wantsLayer = true
        rings.autoresizingMask = [.width, .height]
        rings.layer?.addSublayer(hairline)
        card.content.addSubview(rings, positioned: .above, relativeTo: nil)

        var probe = Self.glideStart
        let path = { (t: Double) in PreviewFilm.glide(t, from: NSPoint(x: 1060, y: 330), to: NSPoint(x: 150, y: 471)) }
        while probe < Self.glideEnd && !rowRect.contains(path(probe)) { probe += 1.0 / 600 }
        enterRow = (probe * 1000).rounded() / 1000
        cardIn = enterRow + 0.2
    }

    static func thumbnail(_ composite: CGImage, header: CGFloat, pageWidth: CGFloat) -> NSImage {
        let height = (pageWidth * 10 / 16).rounded()
        let view = TabPageView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: height), image: composite, header: header)
        view.appearance = NSAppearance(named: .aqua)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 536, pixelsHigh: 335, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        bitmap.size = NSSize(width: 268, height: 167.5)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    static func glide(_ t: Double, from a: NSPoint, to d: NSPoint) -> NSPoint {
        let s = CGFloat(Ease.easeInOut((t - glideStart) / (glideEnd - glideStart))), r = 1 - s
        let b = NSPoint(x: 560, y: 280), c = NSPoint(x: 150, y: 300)
        let x = r * r * r * a.x + 3 * r * r * s * b.x + 3 * r * s * s * c.x + s * s * s * d.x
        let y = r * r * r * a.y + 3 * r * r * s * b.y + 3 * r * s * s * c.y + s * s * s * d.y
        return NSPoint(x: x, y: y)
    }

    func report() -> [String] {
        ["row \(rowRect) anchor \(anchor) card \(card.frame) preferred height \(card.preferredHeight(width: card.frame.width))",
         "open in peek \(peekRect) image \(openInPeek.image.map { "\($0.size) template=\($0.isTemplate)" } ?? "none")",
         "card subviews \(BrowserScene.descendants(card).map { "\(type(of: $0))" })",
         "peek card \(host.cardFrame) close \(closeRect)",
         "card layer shadow offset \(card.layer?.shadowOffset ?? .zero) radius \(card.layer?.shadowRadius ?? 0) opacity \(card.layer?.shadowOpacity ?? 0) flipped \(card.layer?.isGeometryFlipped ?? false) path \(card.layer?.shadowPath != nil)",
         "rings \(popover.map { [$0.outerBorder, $0.innerBorder].map { "frame \($0.frame) width \($0.borderWidth) alpha \($0.borderColor?.alpha ?? -1)" } } ?? [])",
         String(format: "enter row %.3f card in %.3f click %.3f close %.3f", enterRow, cardIn, Self.click, Self.close)]
    }

    struct State {
        var pointer: NSPoint
        var hand: Bool
        var hovered: SidebarTabRow?
        var cardAlpha: CGFloat
        var cardScale: CGFloat
        var button: Int
        var close: Int
        var opacity: CGFloat
        var frame: PeekDismissalFrame
        var step: CGFloat
        var present: Bool
    }

    func pointer(_ t: Double) -> NSPoint {
        func curve(_ a: NSPoint, _ b: NSPoint, _ control: NSPoint, _ s: Double) -> NSPoint {
            let s = CGFloat(s), r = 1 - s
            return NSPoint(x: r * r * a.x + 2 * r * s * control.x + s * s * b.x, y: r * r * a.y + 2 * r * s * control.y + s * s * b.y)
        }
        if t < Self.glideStart { return start }
        if t < Self.glideEnd { return Self.glide(t, from: start, to: onRow) }
        if t < Self.toButtonStart { return onRow }
        if t < Self.toButtonEnd {
            return curve(onRow, peekPoint, NSPoint(x: 320, y: 455), Ease.easeInOut((t - Self.toButtonStart) / (Self.toButtonEnd - Self.toButtonStart)))
        }
        if t < Self.toCloseStart { return peekPoint }
        if t < Self.toCloseEnd {
            return curve(peekPoint, closePoint, NSPoint(x: 980, y: 150), Ease.easeInOut((t - Self.toCloseStart) / (Self.toCloseEnd - Self.toCloseStart)))
        }
        if t < Self.returnStart { return closePoint }
        if t < Self.returnEnd {
            return curve(closePoint, start, NSPoint(x: 1160, y: 230), Ease.easeInOut((t - Self.returnStart) / (Self.returnEnd - Self.returnStart)))
        }
        return start
    }

    func state(_ t: Double) -> State {
        let point = pointer(t)
        var alpha: CGFloat = 0, scale: CGFloat = SidebarPreviewMetrics.scale
        let span = SidebarPreviewMetrics.duration
        if t >= cardIn && t < Self.click {
            let p = CGFloat(Ease.easeInOut((t - cardIn) / span))
            alpha = p; scale = SidebarPreviewMetrics.scale + (1 - SidebarPreviewMetrics.scale) * p
        } else if t >= Self.click {
            let p = CGFloat(Ease.easeInOut((t - Self.click) / span))
            alpha = 1 - p; scale = 1 - (1 - SidebarPreviewMetrics.scale) * p
        }
        let overButton = peekRect.contains(point)
        var button = 0
        if alpha > 0 && overButton { button = t >= Self.press && t < Self.click ? 2 : 1 }
        let present = t >= Self.click && t < Self.close + PeekDismissalTiming.fade
        let overClose = closeRect.contains(point)
        var close = 0
        if present && overClose { close = t >= Self.closePress && t < Self.close ? 2 : 1 }
        let hand = (overButton && t >= cardIn && t < Self.click + span) || (overClose && t >= Self.click && t < Self.close + PeekDismissalTiming.fade)
        let opening = t >= Self.click ? Ease.easeOut((t - Self.click) / PeekStepBack.openDuration) : 0
        let frame = t >= Self.close ? closing.frame(at: t) : .rest
        let step = present ? CGFloat(opening * frame.wash) : 0
        let hovered = scene.tabRows.first { scene.surface.convert($0.bounds, from: $0).contains(point) }
        return State(pointer: point, hand: hand, hovered: hovered, cardAlpha: alpha, cardScale: scale, button: button, close: close,
                     opacity: CGFloat(opening), frame: frame, step: step, present: present)
    }

    private var baseKey: (CGFloat, CGFloat, ObjectIdentifier?)?
    private var baseImage: CGImage?
    private var peekImages: [Int: CGImage] = [:]
    private var cardImages: [Int: CGImage] = [:]

    func applyRowHover(_ hovered: SidebarTabRow?) {
        scene.setHover(hovered)
        for row in scene.tabRows { row.layoutSubtreeIfNeeded() }
        guard let row = hovered,
              let close = row.subviews.compactMap({ $0 as? SidebarRowActionButton }).first,
              let stack = row.subviews.first(where: { $0 is SidebarRowTitleStack }),
              let label = stack.subviews.compactMap({ $0 as? NSTextField }).first else { return }
        close.isHidden = false
        let trailing = SidebarRowAppearance.titleTrailingEdge(in: row.bounds, closeVisible: true)
        let span = SidebarRowAppearance.titleLabelSpan(resettable: false, trailing: trailing)
        stack.frame = NSRect(x: span.minX, y: stack.frame.minY, width: span.width, height: stack.frame.height)
        label.frame = NSRect(x: 0, y: 0, width: span.width, height: label.frame.height)
    }

    func base(scale: CGFloat, wash: CGFloat, hovered: SidebarTabRow?) -> CGImage {
        let id = hovered.map(ObjectIdentifier.init)
        if let baseKey, let baseImage, baseKey.0 == scale, baseKey.1 == wash, baseKey.2 == id { return baseImage }
        applyRowHover(hovered)
        scene.surface.pageScale = scale
        scene.surface.washAlpha = wash
        scene.edge.isHidden = true
        scene.pointer.isHidden = true
        let size = scene.stage.bounds.size
        let image = scene.render(NSRect(origin: .zero, size: size), pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2)).cgImage!
        baseKey = (scale, wash, id); baseImage = image
        return image
    }

    func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
        NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                               eventNumber: 0, trackingNumber: 0, userData: nil)!
    }

    func peek(_ close: Int) -> CGImage {
        if let image = peekImages[close] { return image }
        closeButton.highlight(false)
        closeButton.mouseExited(with: event(.mouseExited, at: .zero))
        if close >= 1 { closeButton.mouseEntered(with: event(.mouseEntered, at: closePoint)) }
        if close == 2 { closeButton.highlight(true) }
        closeButton.settleMotion()
        host.layoutSubtreeIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = host.bounds.size
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
        let image = bitmap.cgImage!
        peekImages[close] = image
        return image
    }

    var popover: PopoverBackgroundView? {
        BrowserScene.descendants(card).compactMap { $0 as? PopoverBackgroundView }.first
    }

    var cardCapture: NSRect { card.frame.insetBy(dx: -Self.cardMargin, dy: -Self.cardMargin) }

    func cardImage(_ state: Int) -> CGImage {
        if let image = cardImages[state] { return image }
        openInPeek.highlight(false)
        openInPeek.mouseExited(with: event(.mouseExited, at: .zero))
        openInPeek.showsSelectedFill = false
        if state >= 1 { openInPeek.mouseEntered(with: event(.mouseEntered, at: peekPoint)) }
        if state == 2 { openInPeek.highlight(true) }
        if state == 1 && !openInPeek.hovered { openInPeek.showsSelectedFill = true }
        cardHost.layoutSubtreeIfNeeded()
        for view in BrowserScene.descendants(card) {
            view.needsDisplay = true
            view.layer?.setNeedsDisplay(); view.layer?.displayIfNeeded()
        }
        if let popover {
            popover.layoutSubtreeIfNeeded()
            popover.updateLayer()
            let outer = popover.outerBorder
            CATransaction.begin(); CATransaction.setDisableActions(true)
            hairline.frame = outer.frame
            hairline.cornerRadius = outer.cornerRadius
            hairline.cornerCurve = outer.cornerCurve
            hairline.borderColor = outer.borderColor
            hairline.borderWidth = 0.5
            hairline.zPosition = outer.zPosition
            outer.isHidden = true
            CATransaction.commit()
        }
        card.layer?.shadowOffset = CGSize(width: 0, height: -6)
        let rect = cardCapture
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width * 2), pixelsHigh: Int(rect.height * 2),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = rect.size
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { cardHost.cacheDisplay(in: rect, to: bitmap) }
        let image = bitmap.cgImage!
        cardImages[state] = image
        return image
    }

    func compose(_ t: Double, into context: CGContext) -> State {
        let s = state(t)
        let window = scene.windowRect
        let stageSize = scene.stage.bounds.size
        let wash = s.present ? PeekCardAppearance.backdropOpacity * CGFloat(s.frame.wash) * s.opacity : 0
        let base = base(scale: layout.scale(progress: s.step), wash: wash, hovered: s.hovered)
        context.interpolationQuality = .high
        context.draw(base, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: CGFloat(context.width) / stageSize.width, y: -CGFloat(context.height) / stageSize.height)
        context.saveGState()
        context.addPath(CGPath(roundedRect: window, cornerWidth: windowCornerRadius, cornerHeight: windowCornerRadius, transform: nil))
        context.clip()
        let alpha = s.opacity * CGFloat(s.frame.card)
        if s.present && alpha > 0 {
            context.saveGState()
            context.setAlpha(alpha)
            drawUpright(peek(s.close), in: window.offsetBy(dx: s.frame.offset, dy: 0), context)
            context.restoreGState()
        }
        if s.cardAlpha > 0 {
            let image = cardImage(s.button)
            let pivot = NSPoint(x: anchor.x + window.minX, y: anchor.y + window.minY)
            context.saveGState()
            context.translateBy(x: pivot.x, y: pivot.y)
            context.scaleBy(x: s.cardScale, y: s.cardScale)
            context.translateBy(x: -pivot.x, y: -pivot.y)
            context.setAlpha(s.cardAlpha)
            drawUpright(image, in: cardCapture.offsetBy(dx: window.minX, dy: window.minY), context)
            context.restoreGState()
        }
        context.restoreGState()
        context.saveGState()
        context.translateBy(x: window.minX, y: window.minY)
        scene.edge.draw(scene.edge.bounds)
        context.restoreGState()
        let cursor: NSCursor = s.hand ? .pointingHand : .arrow
        let image = cursor.image, hot = cursor.hotSpot
        let location = NSPoint(x: s.pointer.x + window.minX, y: s.pointer.y + window.minY)
        image.draw(in: NSRect(x: location.x - hot.x, y: location.y - hot.y, width: image.size.width, height: image.size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        PreviewFilm.fadeMargins(context, window: window, stage: stageSize)
        return s
    }

    static func fadeMargins(_ context: CGContext, window: NSRect, stage: NSSize) {
        let height = CGFloat(context.height), scale = height / stage.height
        let bottom = (stage.height - window.maxY) * scale, top = window.minY * scale
        var locations: [CGFloat] = [], alphas: [CGFloat] = []
        for index in 0...8 {
            let u = CGFloat(index) / 8, eased = u * u * (3 - 2 * u)
            locations.append(u * bottom / height); alphas.append(eased)
        }
        for index in 0...8 {
            let u = CGFloat(index) / 8, eased = 1 - u * u * (3 - 2 * u)
            locations.append((height - top + u * top) / height); alphas.append(eased)
        }
        let colors = alphas.map { CGColor(gray: 0, alpha: $0) } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: locations) else { return }
        context.saveGState()
        context.setBlendMode(.destinationIn)
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        context.restoreGState()
    }

    var beats: [PeekBeat] {
        [PeekBeat(name: "rest", time: 0),
         PeekBeat(name: "pointer_glide_start", time: Self.glideStart),
         PeekBeat(name: "pointer_enters_urban_parks_row", time: enterRow),
         PeekBeat(name: "pointer_rests_on_row", time: Self.glideEnd),
         PeekBeat(name: "card_pop_start_after_200ms_dwell", time: cardIn),
         PeekBeat(name: "card_fully_open", time: cardIn + SidebarPreviewMetrics.duration),
         PeekBeat(name: "pointer_to_open_in_peek", time: Self.toButtonStart),
         PeekBeat(name: "open_in_peek_hover", time: hoverTime(rect: peekRect, from: Self.toButtonStart, to: Self.toButtonEnd)),
         PeekBeat(name: "open_in_peek_press", time: Self.press),
         PeekBeat(name: "click_card_exit_and_peek_entry_start", time: Self.click),
         PeekBeat(name: "card_gone", time: Self.click + SidebarPreviewMetrics.duration),
         PeekBeat(name: "peek_open_stepped_back", time: Self.click + PeekStepBack.openDuration),
         PeekBeat(name: "pointer_to_close", time: Self.toCloseStart),
         PeekBeat(name: "close_hover", time: hoverTime(rect: closeRect, from: Self.toCloseStart, to: Self.toCloseEnd)),
         PeekBeat(name: "close_press", time: Self.closePress),
         PeekBeat(name: "close_click_fade_start", time: Self.close),
         PeekBeat(name: "peek_removed_page_full_scale", time: Self.close + PeekDismissalTiming.fade),
         PeekBeat(name: "pointer_return_start", time: Self.returnStart),
         PeekBeat(name: "pointer_back_at_rest", time: Self.returnEnd),
         PeekBeat(name: "end", time: duration)]
    }

    func hoverTime(rect: NSRect, from: Double, to: Double) -> Double {
        var time = from
        while time < to && !rect.contains(pointer(time)) { time += 1.0 / Double(fps) }
        return (time * 1000).rounded() / 1000
    }

    func still(_ t: Double, path: String) {
        let context = PeekFilm.offscreenContext(width: 2880, height: 1800)
        _ = compose(t, into: context)
        PeekFilm.writePNG(PeekFilm.onGrey(context.makeImage()!), path)
    }

    func film(out: String, keyTimes: [(String, Double)], stripTimes: [Double]) {
        let writer = try! AlphaMovieWriter(path: out + "/preview.mov", width: 2880, height: 1800, fps: Int32(fps), quality: 1.0)
        let frames = Int((duration * Double(fps)).rounded())
        let keyFrames = Dictionary(uniqueKeysWithValues: keyTimes.map { (Int(($0.1 * Double(fps)).rounded()), $0.0) })
        let stripFrames = Set(stripTimes.map { Int(($0 * Double(fps)).rounded()) })
        var strip: [(Double, CGImage)] = []
        var log: [String] = []
        var first: CGImage?, last: CGImage?
        let began = Date()
        for frame in 0..<frames {
            let t = Double(frame) / Double(fps)
            var captured: CGImage?
            var state: State?
            writer.append { context in
                state = compose(t, into: context)
                if keyFrames[frame] != nil || stripFrames.contains(frame) || frame == 0 || frame == frames - 1 { captured = context.makeImage() }
            }
            if let state, frame % 6 == 0 || keyFrames[frame] != nil {
                log.append(String(format: "t=%.3f pointer=(%.0f,%.0f) hand=%@ cardAlpha=%.3f cardScale=%.3f button=%d close=%d opacity=%.3f card=%.3f wash=%.3f step=%.3f present=%@",
                                  t, state.pointer.x, state.pointer.y, state.hand ? "yes" : "no", state.cardAlpha, state.cardScale, state.button,
                                  state.close, state.opacity, state.frame.card, state.frame.wash, state.step, state.present ? "yes" : "no"))
            }
            if let captured {
                if frame == 0 { first = captured }
                if frame == frames - 1 { last = captured }
                if let name = keyFrames[frame] { PeekFilm.writePNG(PeekFilm.onGrey(captured), out + "/key-\(name).png") }
                if stripFrames.contains(frame) { strip.append((t, captured)) }
            }
            if frame % 60 == 0 { print("frame", frame, String(format: "%.1fs elapsed", Date().timeIntervalSince(began))) }
        }
        let result = writer.finish()
        print("wrote", out + "/preview.mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
        if let first, let last { log.append("first and last frames identical: \(Self.identical(first, last))") }
        try? log.joined(separator: "\n").write(toFile: out + "/preview-motion.txt", atomically: true, encoding: .utf8)
        writeStrip(strip, path: out + "/preview-strip.png")
        let body = beats.map { "  \"\($0.name)\": \(String(format: "%.3f", $0.time))" }.joined(separator: ",\n")
        try? ("{\n" + body + "\n}\n").write(toFile: out + "/preview-beats.json", atomically: true, encoding: .utf8)
        print("wrote", out + "/preview-beats.json")
    }

    static func identical(_ a: CGImage, _ b: CGImage) -> Bool {
        guard let da = a.dataProvider?.data, let db = b.dataProvider?.data else { return false }
        return CFEqual(da, db)
    }

    func writeStrip(_ frames: [(Double, CGImage)], path: String) {
        let columns = 6, thumbWidth = 480, thumbHeight = 300, label = 22, gap = 8
        let rows = (frames.count + columns - 1) / columns
        let width = columns * thumbWidth + (columns + 1) * gap, height = rows * (thumbHeight + label) + (rows + 1) * gap
        let context = PeekFilm.offscreenContext(width: width, height: height)
        context.setFillColor(hex(0x8E939B).cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        for (index, (time, image)) in frames.enumerated() {
            let x = gap + (index % columns) * (thumbWidth + gap), y = gap + (index / columns) * (thumbHeight + label + gap)
            drawUpright(image, in: CGRect(x: x, y: y + label, width: thumbWidth, height: thumbHeight), context)
            NSAttributedString(string: String(format: "%.2f s", time), attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
                                                                                    .foregroundColor: NSColor.white])
                .draw(at: NSPoint(x: x + 4, y: y + 2))
        }
        NSGraphicsContext.restoreGraphicsState()
        PeekFilm.writePNG(context.makeImage()!, path)
    }
}
