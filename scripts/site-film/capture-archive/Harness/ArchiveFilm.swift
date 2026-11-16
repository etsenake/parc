import AppKit

@MainActor final class PeekStandIn: NSView {
    var alpha: CGFloat = 0 { didSet { needsDisplay = true } }
    var theme: CGImage?
    var layout: PeekWindowLayout
    var page: NSImage
    var pageFill: NSColor
    var colors: PeekControlColors
    var scroll: CGFloat = 0
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init(frame: NSRect, layout: PeekWindowLayout, page: NSImage, pageFill: NSColor, colors: PeekControlColors) {
        self.layout = layout; self.page = page; self.pageFill = pageFill; self.colors = colors
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard alpha > 0.001, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(alpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        if let theme {
            let pageFrame = layout.page
            let sx = CGFloat(theme.width) / bounds.width, sy = CGFloat(theme.height) / bounds.height
            if let crop = theme.cropping(to: CGRect(x: pageFrame.minX * sx, y: pageFrame.minY * sy, width: pageFrame.width * sx, height: pageFrame.height * sy)) {
                context.saveGState()
                context.setAlpha(PeekCardAppearance.backdropOpacity)
                context.translateBy(x: pageFrame.minX, y: pageFrame.maxY); context.scaleBy(x: 1, y: -1)
                context.draw(crop, in: CGRect(origin: .zero, size: pageFrame.size))
                context.restoreGState()
            }
        }
        let card = layout.card
        let edge = card.insetBy(dx: -0.5, dy: -0.5)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: PeekCardAppearance.shadowRadius * 2,
                          color: NSColor.black.withAlphaComponent(CGFloat(PeekCardAppearance.shadowOpacity)).cgColor)
        PeekCardAppearance.borderColor.setFill()
        NSBezierPath(roundedRect: edge.insetBy(dx: -PeekCardAppearance.borderWidth / 2, dy: -PeekCardAppearance.borderWidth / 2), xRadius: 9, yRadius: 9).fill()
        context.restoreGState()
        PeekCardAppearance.borderColor.setFill()
        NSBezierPath(roundedRect: edge.insetBy(dx: -PeekCardAppearance.borderWidth / 2, dy: -PeekCardAppearance.borderWidth / 2), xRadius: 9, yRadius: 9).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: card, xRadius: 8, yRadius: 8).addClip()
        PeekCardAppearance.cardFill(dark: false).setFill(); card.fill()
        PageArt.draw(page, in: card, fill: pageFill, fitWidth: min(card.width, page.size.width * (682.0 / 700.0)), scroll: scroll)
        NSGraphicsContext.restoreGraphicsState()
        let controls = layout.controls(closeWidth: PeekWindowLayout.controlSize)
        for (index, symbol) in ["xmark", "arrow.up.left.and.arrow.down.right", "square.split.2x1"].enumerated() {
            let circle = NSRect(x: controls.minX, y: controls.minY + CGFloat(index) * (PeekWindowLayout.controlSize + PeekWindowLayout.controlSpacing),
                                width: PeekWindowLayout.controlSize, height: PeekWindowLayout.controlSize)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor.black.withAlphaComponent(0.12).cgColor)
            colors.fill.setFill(); NSBezierPath(ovalIn: circle).fill()
            context.restoreGState()
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold).applying(NSImage.SymbolConfiguration(paletteColors: [colors.accent]))
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let size = glyph.size
                glyph.draw(in: NSRect(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2, width: size.width, height: size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }
}

@MainActor final class ArchiveFilm {
    let scene: BrowserScene
    let store: BrowserStore
    let profileID: UUID
    let work: BrowserSpace
    let before: BrowserState
    let picnic: NSImage
    let picnicFill: NSColor
    let article: NSImage
    let education: AutoArchiveEducationView
    let educationHeight: CGFloat
    var library: LibraryView?
    let peek: PeekStandIn
    let layout: PeekWindowLayout
    let toast: ToastSprite
    let pageHome: NSRect
    let picnicTitle = Canon.picnic.title
    let sweptTitles = [Canon.urbanParks.title, Canon.roadmap.title, Canon.checklist.title]
    var restoredID: UUID?
    var sidebarLights: NSRect?
    var showPicnic = false
    var phase = 0

    init(scene: BrowserScene, articlePath: String, picnicPath: String, storeDirectory: URL) {
        self.scene = scene
        article = NSImage(contentsOfFile: articlePath)!
        picnic = NSImage(contentsOfFile: picnicPath)!
        let rep = NSBitmapImageRep(data: picnic.tiffRepresentation!)!
        picnicFill = rep.colorAt(x: 4, y: 4) ?? .white
        var state = scene.scenario.state
        work = scene.scenario.work
        profileID = work.profileID
        let now = Date()
        let provenance = ArchiveProvenance(reason: .automatic, spaceID: work.id, spaceName: work.name)
        for index in state.tabs.indices where sweptTitles.contains(state.tabs[index].title) {
            state.tabs[index].archivedAt = now.addingTimeInterval(-Double(18 + index) * 60)
            state.tabs[index].archiveProvenance = provenance
        }
        let white = NSColor.white
        let older: [(String, String, Double, FaviconSpec)] = [
            (Canon.homePinned[0].title, Canon.homePinned[0].url, 1, Canon.homePinned[0].icon),
            (Canon.bikeRoute.title, Canon.bikeRoute.url, 1.2, Canon.bikeRoute.icon),
            (picnicTitle, Canon.picnic.url, 3, Canon.picnic.icon),
            ("Farmers market opening hours", "https://citymarkets.example/saturday", 3.1, FaviconSpec(symbol: "carrot.fill", fill: hex(0xEA580C), glyph: white)),
        ]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for (title, url, days, icon) in older {
            Favicons.specs[url] = icon
            let day = calendar.date(byAdding: .day, value: -Int(days), to: today)!
            let stamp = day.addingTimeInterval(14 * 3600 + (days - Double(Int(days))) * 36000)
            var tab = BrowserTab(id: UUID(), spaceID: work.id, profileID: profileID, url: url, title: title, kind: .today,
                                 createdAt: stamp.addingTimeInterval(-7200), lastAccessed: stamp.addingTimeInterval(-3600), savedURL: url, savedTitle: title)
            tab.archivedAt = stamp
            tab.archiveProvenance = provenance
            state.tabs.append(tab)
        }
        try? FileManager.default.removeItem(at: storeDirectory)
        try! FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try! encoder.encode(state).write(to: storeDirectory.appendingPathComponent("session.json"))
        store = try! BrowserStore(directory: storeDirectory)
        var plain = store.state
        for index in plain.tabs.indices where sweptTitles.contains(plain.tabs[index].title) {
            plain.tabs[index].archivedAt = nil; plain.tabs[index].archiveProvenance = nil
        }
        before = plain
        print("store archived items:", store.archivedItems(profileID: profileID).map { "\($0.tabs.first?.title ?? "?") @ \($0.archivedAt)" })
        pageHome = scene.surface.pageCard
        education = AutoArchiveEducationView(frame: .zero)
        education.appearance = NSAppearance(named: .aqua)
        education.applyPalette(scene.themeSurface.palette)
        educationHeight = education.preferredHeight(for: 212)
        education.frame = NSRect(x: 8, y: scene.windowRect.height - 50 - educationHeight, width: 212, height: educationHeight)
        education.isHidden = true
        let bounds = NSRect(origin: .zero, size: scene.windowRect.size)
        let frames = SidebarChromeFrames(bounds: bounds, sidebarWidth: CGFloat(scene.scenario.state.settings.sidebarWidth), presentation: .locked,
                                         placement: .locked, library: true, libraryContentWidth: SidebarChromeFrames.libraryMinimumWidth,
                                         thickness: frameThickness)
        print("library frames: library", frames.library, "page", frames.pageHost)
        layout = PeekWindowLayout(bounds: bounds, page: frames.pageHost, stepsBack: true)
        peek = PeekStandIn(frame: bounds, layout: layout, page: picnic, pageFill: picnicFill, colors: PeekControlColors(palette: scene.themeSurface.palette))
        peek.theme = scene.surface.theme
        toast = ToastSprite(content: .tabRestored(to: work.name, selected: false), theme: work.theme, frame: bounds)
        toast.cornerTarget = NSPoint(x: bounds.maxX - 8, y: 8)
        scene.insert(education)
        scene.insert(peek)
        scene.insert(toast)
        scene.surface.drawPage = { [unowned self] rect in
            if self.showPicnic { PageArt.draw(self.picnic, in: rect, fill: self.picnicFill, fitWidth: min(rect.width, self.picnic.size.width * (682.0 / 700.0))) }
            else { PageArt.draw(self.article, in: rect) }
        }
        renderSidebar(before, focus: scene.scenario.selected.id)
    }

    func renderSidebar(_ state: BrowserState, focus: UUID) {
        scene.sidebar.render(state: state, focusedTabID: focus, loading: [], canBack: true, canForward: false)
        scene.sidebar.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        scene.sidebar.needsLayout = true
        scene.sidebar.layoutSubtreeIfNeeded()
    }

    func openLibrary() {
        let view = LibraryView(store: store, kind: .archive, profileID: profileID)
        view.appearance = NSAppearance(named: .aqua)
        view.palette = scene.themeSurface.palette
        view.archiveOwnerValid = { true }
        view.showsWindowButtons = true
        view.frame = NSRect(x: 0, y: 0, width: view.contentWidth, height: scene.windowRect.height)
        scene.surface.addSubview(view, positioned: .above, relativeTo: education)
        var icons: [URL: NSImage] = [:]
        for tab in store.state.tabs where tab.archivedAt != nil {
            if let url = URL(string: tab.url), let image = Favicons.image(for: tab) { icons[url] = image }
        }
        view.harnessIcons(icons)
        view.layoutSubtreeIfNeeded()
        library = view
        scene.sidebar.isHidden = true
        education.isHidden = true
        if let buttons = BrowserScene.descendants(view).first(where: { $0 is WindowStandardButtons }), !buttons.isHiddenOrHasHiddenAncestor {
            sidebarLights = scene.lights.frame
            scene.lights.frame = scene.surface.convert(buttons.bounds, from: buttons)
        }
        scene.surface.pageCard = layout.page
        print("library", view.frame, "rows", view.harnessRowCount, "picnic row", view.harnessRowFrame(picnicTitle) ?? .zero)
    }

    func run(out: String, stills: Bool) {
        let recorder = FilmRecorder(scene: scene, name: "archive", out: out)
        let rest = NSPoint(x: 760, y: 560)
        let libraryButton = NSPoint(x: 24, y: 815)
        var path = PointerPath(keys: [(0, rest), (2.0, rest), (2.55, libraryButton)])
        var rowPoint = NSPoint.zero, putBackPoint = NSPoint.zero
        let toastPoint = NSPoint(x: toast.cornerTarget.x - toast.card.width / 2, y: toast.cornerTarget.y + toast.card.height / 2)
        recorder.beat(0, "morning", "Work Space Today list with the long read selected")
        recorder.beat(0.8, "sweep", "re-render from the store: three Today tabs archived (archivedAt set) vanish in one frame — no drift [gap]")
        recorder.beat(0.9, "education", "AutoArchiveEducationView rises: spring response 0.6 damping 0.4 on translation y (+h→0) and opacity")
        recorder.beat(2.6, "library", "LibraryView(kind: .archive) added at (0,0,417,840); page card jumps to (417,10,853,820) — no animation")
        recorder.beat(3.0, "hover", "pointer over \"\(picnicTitle)\": row highlight, Put Back and trash appear")
        recorder.beat(3.6, "preview-open", "archive preview: wash 0.7 + card (502,12,682,816) fade 0→1 over 0.3 s ease-out; page steps back to 0.9789 over 0.3 s ease-out")
        recorder.beat(6.0, "preview-close", "preview fades out with step-back reversing over 0.2 s")
        recorder.beat(6.7, "put-back", "store.restoreArchivedTab(.putBack); row vanishes instantly on reload")
        recorder.beat(6.7, "toast", "\"Tab restored to Work. Click to view.\" springs in at the window top-right (response 0.4, damping 0.7)")
        recorder.beat(7.8, "toast-click", "Library closes instantly; restored tab selected in Today; page card back at (228,10)")
        let keyTimes = [0.5, 1.2, 2.0, 2.8, 3.4, 3.75, 4.5, 6.1, 6.6, 7.0, 7.9, 9.0]
        recorder.record(duration: 9.5, keyTimes: keyTimes, onlyStills: stills) { t, _ in
            if t >= 0.8 && phase == 0 {
                phase = 1
                renderSidebar(store.state, focus: scene.scenario.selected.id)
            }
            if t >= 0.9 && library == nil {
                let s = Curve.spring(response: 0.6, damping: 0.4, t - 0.9)
                education.isHidden = false
                education.alphaValue = CGFloat(min(1, max(0, s)))
                education.frame.origin.y = scene.windowRect.height - 50 - educationHeight + educationHeight * CGFloat(1 - s)
            }
            if t >= 2.6 && phase == 1 {
                phase = 2
                scene.setHover(nil)
                openLibrary()
                if let row = library?.harnessRowFrame(picnicTitle) { rowPoint = NSPoint(x: row.minX + 150, y: row.midY + 2) }
                path = PointerPath(keys: [(2.6, libraryButton), (3.0, libraryButton), (3.5, rowPoint)])
            }
            if let library, phase >= 2 && phase < 5 {
                let here = path.at(t)
                let row = library.harnessRowFrame(picnicTitle) ?? .zero
                library.harnessHover(row.contains(here) || (t >= 3.6 && t < 6.7) ? picnicTitle : nil)
            }
            if t >= 3.6 && phase == 2 {
                phase = 3
                putBackPoint = library.flatMap { $0.harnessPutBackFrame(picnicTitle) }.map { NSPoint(x: $0.midX, y: $0.midY) } ?? rowPoint
                print("put back button", putBackPoint)
                path = PointerPath(keys: [(3.6, rowPoint), (6.3, rowPoint), (6.65, putBackPoint)])
            }
            if phase >= 3 && phase < 5 {
                let progress: Double
                if t < 6.0 { progress = Curve.easeOut(Curve.progress(t, 3.6, 3.9)) }
                else { progress = 1 - Curve.easeInOut(Curve.progress(t, 6.0, 6.2)) }
                peek.alpha = CGFloat(progress)
                scene.surface.pageCard = layout.steppedPage(progress: CGFloat(progress))
            }
            if t >= 6.7 && phase == 3 {
                phase = 4
                if let item = store.archivedItems(profileID: profileID).first(where: { $0.tabs.first?.title == picnicTitle }) {
                    let restored = store.restoreArchivedTab(item.id, profileID: profileID,
                                                            destination: .putBack(currentSpaceID: work.id, requestedSpaceID: work.id))
                    restoredID = restored.first
                    print("restored", restored)
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                library?.harnessHover(nil)
                library?.layoutSubtreeIfNeeded()
                path = PointerPath(keys: [(6.7, putBackPoint), (6.85, putBackPoint), (7.65, toastPoint)])
            }
            if phase >= 4 && phase < 5 { toast.progress = Curve.spring(response: 0.4, damping: 0.7, t - 6.7) }
            if t >= 7.8 && phase == 4 {
                phase = 5
                library?.removeFromSuperview(); library = nil
                scene.sidebar.isHidden = false
                if let sidebarLights { scene.lights.frame = sidebarLights }
                peek.alpha = 0
                scene.surface.pageCard = pageHome
                if let restoredID { _ = store.selectTab(restoredID) }
                showPicnic = true
                renderSidebar(store.state, focus: restoredID ?? scene.scenario.selected.id)
                path = PointerPath(keys: [(7.8, toastPoint), (9.3, NSPoint(x: toastPoint.x - 160, y: toastPoint.y + 120))])
                print("today after restore", store.state.tabs.filter { $0.kind == .today && $0.archivedAt == nil }.map(\.title))
            }
            if phase >= 5 { toast.progress = max(0, 1 - Curve.spring(response: 0.4, damping: 0.7, t - 7.8)) }
            let here = path.at(t)
            scene.pointer.location = here
            if phase < 2 || phase >= 5 {
                scene.setHover(scene.tabRows.first { scene.surface.convert($0.bounds, from: $0).contains(here) })
            }
            scene.surface.needsDisplay = true
        }
    }
}
