import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class NotePageMenu {
    enum ExportFormat: String, CaseIterable {
        case markdown, html, pdf

        var title: String {
            switch self {
            case .markdown: return "Markdown File…"
            case .html: return "HTML File…"
            case .pdf: return "PDF…"
            }
        }

        var contentType: UTType {
            switch self {
            case .markdown: return UTType(filenameExtension: "md") ?? .plainText
            case .html: return .html
            case .pdf: return .pdf
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .html: return "html"
            case .pdf: return "pdf"
            }
        }
    }

    unowned let editor: NotePageEditor
    let file: NoteFileSession?
    var onToast: ((ParcToastContent) -> Void)?
    var onTrashed: ((URL) -> Void)?
    var onOpenHistory: (() -> Void)?
    private var popover: NotePagePopover?
    private var exportPopover: NotePagePopover?
    private weak var content: NotePageMenuView?
    private var subscription: AnyCancellable?

    init(editor: NotePageEditor, file: NoteFileSession?) {
        self.editor = editor
        self.file = file
    }

    var isOpen: Bool { popover?.isOpen == true }

    var url: URL? { file?.url ?? editor.environment.documentURL }

    var title: String {
        if let file { return file.title }
        return url?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    var isPlainText: Bool { editor.environment.isPlainText }

    func showToast(_ content: ParcToastContent) {
        if let onToast { onToast(content); return }
        (editor.canvas.window?.windowController as? BrowserWindowController)?.showToast(content)
    }

    func makeButton() -> NotePageMenuButton {
        NotePageMenuButton(menu: self)
    }

    func toggle(from view: NSView, anchor: NSRect? = nil, origin: NoteMenuList.Origin = .pointer) {
        if isOpen { close() } else { present(from: view, anchor: anchor, origin: origin) }
    }

    func present(from view: NSView, anchor: NSRect? = nil, origin: NoteMenuList.Origin = .pointer) {
        close(animated: false)
        let overlay = editor.canvas.overlayView
        let menu = NotePageMenuView(menu: self)
        menu.list.prepare(origin: origin)
        let popover = NotePagePopover(content: menu)
        popover.exempt(view)
        popover.onKeyDown = { [weak menu] event in menu?.list.handleKeyDown(event) ?? false }
        popover.onClose = { [weak self] in
            self?.popover = nil
            self?.subscription = nil
            self?.content = nil
            (view as? NotePageMenuButton)?.menuDidClose()
        }
        self.popover = popover
        content = menu
        subscription = editor.session.changes.sink { [weak self] change in
            guard change.kind != .selection else { return }
            self?.content?.refresh()
        }
        let rect = overlay.convert(anchor ?? view.bounds, from: view)
        popover.present(in: overlay, anchor: rect, edge: .below, alignment: .trailing)
        (view as? NotePageMenuButton)?.menuDidOpen()
    }

    func close(animated: Bool = true) {
        exportPopover?.close(animated: animated)
        popover?.close(animated: animated)
    }

    static let toggleIDs: Set<String> = ["small-text", "full-width", "lock"]

    func isOn(_ id: String) -> Bool? {
        let settings = editor.session.page.settings
        switch id {
        case "small-text": return settings.smallText
        case "full-width": return settings.fullWidth
        case "lock": return settings.locked
        default: return nil
        }
    }

    private func toggleItem(_ id: String, _ title: String, symbol: String) -> NoteMenuList.Item {
        let on = isOn(id) ?? false
        var item = NoteMenuList.Item(id: id, title: title, icon: .symbol(symbol), isEnabled: !editor.session.isReadOnly)
        item.accessibilityLabel = title + (on ? ", on" : ", off")
        return item
    }

    func items() -> [NoteMenuList.Item] {
        let settings = editor.session.page.settings
        let hasFile = url != nil
        var result: [NoteMenuList.Item] = []
        if !isPlainText {
            result.append(toggleItem("small-text", "Small Text", symbol: "textformat.size.smaller"))
            result.append(toggleItem("full-width", "Full Width", symbol: "arrow.left.and.right"))
        }
        result.append(toggleItem("lock", "Lock Note", symbol: settings.locked ? "lock.fill" : "lock"))
        var copy = NoteMenuList.Item(id: "copy-markdown", title: isPlainText ? "Copy Text" : "Copy as Markdown", icon: .symbol("doc.on.doc"))
        copy.separatorBefore = true
        result.append(copy)
        result.append(.init(id: "copy-link", title: "Copy Link", icon: .symbol("link"), isEnabled: hasFile))
        result.append(.init(id: "export", title: "Export", icon: .symbol("square.and.arrow.up"), hasSubmenu: true))
        result.append(.init(id: "reveal", title: "Show in Finder", icon: .symbol("folder"), isEnabled: hasFile))
        result.append(.init(id: "history", title: "Note History", icon: .symbol("clock.arrow.circlepath"), isEnabled: hasFile))
        if isPlainText {
            result.append(.init(id: "turn-markdown", title: "Save a Markdown Copy", icon: .symbol("doc.richtext"), isEnabled: hasFile))
        }
        var trash = NoteMenuList.Item(id: "trash", title: "Move to Trash…", icon: .symbol("trash"), isEnabled: hasFile, isDestructive: true)
        trash.separatorBefore = true
        result.append(trash)
        return result
    }

    func activate(_ item: NoteMenuList.Item, from row: NSRect?) {
        switch item.id {
        case "small-text": toggleSetting("Small Text") { $0.smallText.toggle() }
        case "full-width": toggleSetting("Full Width") { $0.fullWidth.toggle() }
        case "lock":
            let locked = editor.session.page.settings.locked
            editor.session.updateSettings(name: locked ? "Unlock Note" : "Lock Note") { $0.locked.toggle() }
            content?.refresh()
        case "copy-markdown": close(); copyMarkdown()
        case "copy-link": close(); copyLink()
        case "export": presentExport(from: row)
        case "reveal": close(); revealInFinder()
        case "history": close(); showHistory()
        case "turn-markdown": close(); turnIntoMarkdown()
        case "trash": close(); moveToTrash()
        default: break
        }
    }

    func setFont(_ font: NotePageFont) {
        guard editor.session.page.settings.font != font else { return }
        crossfade { self.editor.session.updateSettings(name: "Note Font") { $0.font = font } }
        content?.refresh()
    }

    private func toggleSetting(_ name: String, _ change: (inout NotePageSettings) -> Void) {
        var next = editor.session.page.settings
        change(&next)
        crossfade { self.editor.session.updateSettings(name: name) { $0 = next } }
        content?.refresh()
    }

    func crossfade(_ change: () -> Void) {
        let canvas = editor.canvas!
        let visible = canvas.visibleRect.intersection(canvas.bounds)
        guard !visible.isEmpty, canvas.window != nil, let rep = canvas.bitmapImageRepForCachingDisplay(in: visible) else {
            change()
            return
        }
        canvas.cacheDisplay(in: visible, to: rep)
        let image = NSImage(size: visible.size)
        image.addRepresentation(rep)
        let snapshot = NotePagePassiveImageView(frame: canvas.overlayView.convert(visible, from: canvas))
        snapshot.image = image
        snapshot.imageScaling = .scaleAxesIndependently
        snapshot.wantsLayer = true
        canvas.overlayView.addSubview(snapshot, positioned: .below, relativeTo: canvas.overlayView.subviews.first)
        change()
        canvas.layoutSubtreeIfNeeded()
        guard let layer = snapshot.layer else { snapshot.removeFromSuperview(); return }
        NoteAnimation.fade(layer, to: 0, duration: NoteAnimation.reducedFadeDuration) { [weak snapshot] in
            snapshot?.removeFromSuperview()
        }
    }

    static func markdownForCopy(_ page: NotePage, title: String, plainText: Bool) -> String {
        if plainText { return NotePlainText.serialize(page) }
        return NotePageExport.markdownForCopy(body: NoteMarkdown.serialize(NotePage(blocks: page.blocks)), title: title)
    }

    func copyMarkdown() {
        let text = Self.markdownForCopy(editor.session.page, title: title, plainText: isPlainText)
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        showToast(.standard(isPlainText ? "Copied Text" : "Copied Markdown"))
    }

    func copyLink() {
        guard let url else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([url as NSURL])
        board.setString(url.absoluteString, forType: .string)
        showToast(.copiedLinks([url]))
    }

    func revealInFinder() {
        guard let url else { return }
        try? file?.flush()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func showHistory() {
        if let onOpenHistory { onOpenHistory(); return }
        guard let file else { return }
        NotePageHistory.present(editor: editor, file: file)
    }

    private func presentExport(from row: NSRect?) {
        guard let popover, popover.isOpen else { return }
        exportPopover?.close(animated: false)
        let list = NoteMenuList(items: ExportFormat.allCases.map { format in
            NoteMenuList.Item(id: format.rawValue, title: format.title, icon: .symbol(format == .pdf ? "doc.richtext" : "doc.text"))
        })
        list.minimumWidth = 180
        let child = NotePagePopover(content: list, parent: popover)
        list.onActivate = { [weak self] item in
            guard let self, let format = ExportFormat(rawValue: item.id) else { return }
            self.close()
            self.export(format)
        }
        list.onCancel = { [weak child] in child?.close() }
        list.onCollapse = { [weak child] in child?.close() }
        child.onKeyDown = { [weak list] event in list?.handleKeyDown(event) ?? false }
        child.onClose = { [weak self] in self?.exportPopover = nil }
        exportPopover = child
        let overlay = editor.canvas.overlayView
        let panelFrame = popover.panel.frame
        let anchor = row.map { overlay.convert($0, from: content) } ?? NSRect(x: panelFrame.minX, y: panelFrame.midY, width: panelFrame.width, height: 30)
        let side = NSRect(x: panelFrame.minX, y: anchor.minY, width: panelFrame.width, height: anchor.height)
        child.present(in: overlay, anchor: side, edge: .leading)
        if NSApp.currentEvent?.type == .keyDown { list.prepare(origin: .keyboard); list.moveHighlight(by: 1) }
    }

    func export(_ format: ExportFormat) {
        guard let window = editor.canvas.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = title + "." + format.fileExtension
        if let folder = url?.deletingLastPathComponent() { panel.directoryURL = folder }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            MainActor.assumeIsolated { self?.write(format, to: destination) }
        }
    }

    func write(_ format: ExportFormat, to destination: URL) {
        if format == .pdf {
            writePDF(to: destination)
            return
        }
        if format == .html {
            writeHTML(to: destination)
            return
        }
        do {
            switch format {
            case .markdown:
                let text = isPlainText ? NotePlainText.serialize(editor.session.page) : NoteMarkdown.serialize(editor.session.page)
                try Data(text.utf8).write(to: destination, options: .atomic)
                try copyAssets(to: destination.deletingLastPathComponent())
            case .html, .pdf:
                try Data(htmlDocument().utf8).write(to: destination, options: .atomic)
            }
            showToast(.standard("Exported \(destination.lastPathComponent)"))
        } catch {
            editor.onError?(error)
        }
    }

    func htmlDocument(diagrams: ((NoteBlock) -> NoteDiagramArt?)? = nil) -> String {
        let environment = editor.environment
        return NotePageHTML.document(editor.session.page, title: title, assets: { environment.resolve($0) }, embedImages: true,
                                     equationArt: { tex, display, numbering in NotePageEquationArtwork.art(tex, display: display, numbering: numbering) },
                                     diagramArt: diagrams)
    }

    private func writeHTML(to destination: URL) {
        let page = editor.session.page
        let light = NotePagePrintView.diagramRequests(in: page, dark: false)
        let dark = NotePagePrintView.diagramRequests(in: page, dark: true)
        NoteMermaidRenderer.shared.renderAll(Array(light.values) + Array(dark.values)) { [weak self] results in
            guard let self else { return }
            let art: (NoteBlock) -> NoteDiagramArt? = { block in
                guard let key = light[block.id]?.key, let drawing = results[key]?.art?.drawing else { return nil }
                return NoteDiagramArt(light: drawing.svg, dark: dark[block.id].flatMap { results[$0.key]?.art?.drawing.svg })
            }
            do {
                try Data(self.htmlDocument(diagrams: art).utf8).write(to: destination, options: .atomic)
                self.showToast(.standard("Exported \(destination.lastPathComponent)"))
            } catch {
                self.editor.onError?(error)
            }
        }
    }

    private func copyAssets(to folder: URL) throws {
        guard let base = url?.deletingLastPathComponent(), base.standardizedFileURL != folder.standardizedFileURL else { return }
        let manager = FileManager.default
        for source in NotePageExport.relativeAssetSources(in: editor.session.page) {
            let decoded = source.removingPercentEncoding ?? source
            let from = URL(fileURLWithPath: decoded, relativeTo: base).standardizedFileURL
            let to = URL(fileURLWithPath: decoded, relativeTo: folder).standardizedFileURL
            guard from.path.hasPrefix(base.standardizedFileURL.path), to.path.hasPrefix(folder.standardizedFileURL.path),
                  manager.fileExists(atPath: from.path), !manager.fileExists(atPath: to.path) else { continue }
            try manager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: from, to: to)
        }
    }

    private func writePDF(to destination: URL) {
        let name = title
        NotePagePrintView.prepare(page: editor.session.page, title: name, environment: editor.environment) { [weak self] view in
            guard let self else { return }
            do {
                try view.writePDF(to: destination)
                self.showToast(.standard("Exported \(destination.lastPathComponent)"))
            } catch {
                self.editor.onError?(error)
            }
        }
    }

    func turnIntoMarkdown() {
        guard isPlainText, let url else { return }
        let target = NotePageExport.markdownCopyURL(for: url) { FileManager.default.fileExists(atPath: $0.path) }
        do {
            try file?.flush()
            let text = NoteMarkdown.serialize(NotePage(blocks: editor.session.page.blocks))
            try Data(text.utf8).write(to: target, options: .withoutOverwriting)
            showToast(.standard("Saved a Markdown copy", subLabel: target.lastPathComponent))
            editor.onOpenNote?(target)
        } catch {
            editor.onError?(error)
        }
    }

    func moveToTrash() {
        guard let url, let window = editor.canvas.window else { return }
        let name = title
        ParcDialog.confirm(in: window, title: "Move “\(name)” to the Trash?",
                           message: "Any tabs showing it close too. You can fish it out of the Trash later.",
                           confirm: "Move to Trash", destructive: true) { [weak self] (confirmed: Bool) in
            guard confirmed, let self else { return }
            do {
                try? self.file?.flush()
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                self.onTrashed?(url)
            } catch {
                self.editor.onError?(error)
            }
        }
    }

    func footerLines() -> (stats: String, edited: String) {
        let stats = NotePageStats(page: editor.session.page)
        let edited: String
        switch file?.state {
        case .unsaved?, .saving?:
            edited = NoteRelativeTime.edited(Date())
        default:
            let date = url.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            edited = NoteRelativeTime.edited(date)
        }
        return (stats.summary, edited)
    }
}

@MainActor
final class NotePagePrintView: NSView {
    static let canvasWidth: CGFloat = 776
    static let horizontalMargin: CGFloat = 36
    static let verticalMargin: CGFloat = 40
    static let imageWait: TimeInterval = 6

    let editor: NotePageEditor
    let header: NotePageHeaderView
    let title: String

    init(page: NotePage, title: String, environment: NoteEnvironment) {
        var copy = page
        copy.settings.fullWidth = false
        let session = NotePageSession(page: copy)
        session.isReadOnly = true
        editor = NotePageEditor(session: session, environment: environment)
        header = NotePageHeaderView(editor: editor, file: nil, title: title)
        self.title = title
        super.init(frame: NSRect(x: 0, y: 0, width: Self.canvasWidth, height: 1200))
        appearance = NSAppearance(named: .aqua)
        setAccessibilityElement(false)
        let canvas = editor.canvas!
        canvas.frame = bounds
        addSubview(canvas)
        header.isPrinting = true
        canvas.headerView = header
        settle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    static func prepare(page: NotePage, title: String, environment: NoteEnvironment, completion: @escaping (NotePagePrintView) -> Void) {
        var pending = 0
        var finished = false
        func finish() {
            guard !finished else { return }
            finished = true
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                completion(NotePagePrintView(page: page, title: title, environment: environment))
            }
        }
        func arrived() {
            pending -= 1
            if pending <= 0 { finish() }
        }
        var chromeImages: [URL] = []
        if let cover = page.settings.cover, let url = environment.resolve(cover.source) { chromeImages.append(url) }
        if let icon = page.settings.icon, NotePageImageLoader.isImageSource(icon), let url = environment.resolve(icon) { chromeImages.append(url) }
        var mediaImages: [(URL, Int)] = []
        for block in page.allBlocks() {
            if block.kind == .image, let source = block.props.source, let url = environment.resolve(source) { mediaImages.append((url, 1600)) }
            if block.kind == .bookmark, let bookmark = block.props.bookmark {
                if let image = bookmark.imageURL.flatMap(URL.init(string:)) { mediaImages.append((image, 1024)) }
                if let icon = bookmark.iconURL.flatMap(URL.init(string:)) { mediaImages.append((icon, 64)) }
            }
        }
        let diagrams = Array(diagramRequests(in: page, dark: false).values)
        pending = chromeImages.count + mediaImages.count + (diagrams.isEmpty ? 0 : 1)
        guard pending > 0 else { finish(); return }
        if !diagrams.isEmpty { NoteMermaidRenderer.shared.renderAll(diagrams) { _ in arrived() } }
        for url in chromeImages { NotePageImageLoader.shared.load(url) { _ in arrived() } }
        for (url, pixels) in mediaImages { NoteMediaImageLoader.shared.load(url, pixels: pixels) { _ in arrived() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + imageWait) { finish() }
    }

    static func diagramRequests(in page: NotePage, dark: Bool) -> [NoteBlockID: NoteMermaidRequest] {
        let theme = NoteMermaidTheme.note(dark: dark, font: page.settings.font, small: page.settings.smallText)
        var requests: [NoteBlockID: NoteMermaidRequest] = [:]
        for block in page.allBlocks() where NoteMermaid.isDiagram(block) && NoteMermaid.storedMode(of: block).showsDiagram
            && NoteMermaid.hasContent(block.text.string) {
            requests[block.id] = NoteMermaidRequest(source: block.text.string, theme: theme)
        }
        return requests
    }

    func settle() {
        let canvas = editor.canvas!
        for _ in 0..<3 {
            canvas.layoutSubtreeIfNeeded()
            for entry in canvas.canvasLayout.entries { _ = canvas.blockView(for: entry.id) }
            canvas.layoutSubtreeIfNeeded()
            let height = ceil(canvas.canvasLayout.contentBottom + 24)
            guard abs(frame.height - height) > 0.5 else { break }
            setFrameSize(NSSize(width: Self.canvasWidth, height: height))
            canvas.setFrameSize(NSSize(width: Self.canvasWidth, height: height))
        }
        canvas.overlayView.isHidden = true
        hideInvisibleChrome(in: canvas)
    }

    private func hideInvisibleChrome(in view: NSView) {
        for child in view.subviews {
            if child is NSScroller || child.alphaValue < 0.01 || (child.layer.map { $0.opacity < 0.01 } ?? false) {
                child.isHidden = true
                continue
            }
            hideInvisibleChrome(in: child)
        }
    }

    func printInfo(saving destination: URL? = nil) -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        if let destination {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        }
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        info.leftMargin = Self.horizontalMargin
        info.rightMargin = Self.horizontalMargin
        info.topMargin = Self.verticalMargin
        info.bottomMargin = Self.verticalMargin
        return info
    }

    func printOperation(info: NSPrintInfo) -> NSPrintOperation {
        let operation = NSPrintOperation(view: self, printInfo: info)
        operation.jobTitle = title.isEmpty ? "Untitled" : title
        return operation
    }

    func writePDF(to destination: URL) throws {
        let operation = printOperation(info: printInfo(saving: destination))
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw CocoaError(.fileWriteUnknown) }
    }

    var printSpans: [NotePagePrintSpan] {
        let canvas = editor.canvas!
        var spans = [NotePagePrintSpan(minY: header.frame.minY, maxY: header.frame.maxY, keepsTogether: true)]
        for entry in canvas.canvasLayout.entries {
            let frame = convert(entry.outerFrame.isEmpty ? entry.frame : entry.outerFrame, from: canvas)
            let container = entry.hasVisibleChildren || entry.kind == .columns || entry.kind == .column
            spans.append(NotePagePrintSpan(minY: frame.minY, maxY: frame.maxY, keepsTogether: !container))
        }
        return spans
    }

    override func adjustPageHeightNew(_ newBottom: UnsafeMutablePointer<CGFloat>, top oldTop: CGFloat, bottom oldBottom: CGFloat,
                                      limit bottomLimit: CGFloat) {
        let preferred = NotePagePagination.pageBreak(proposed: oldBottom, limit: bottomLimit, spans: printSpans)
        newBottom.pointee = preferred
        super.adjustPageHeightNew(newBottom, top: oldTop, bottom: preferred, limit: bottomLimit)
        newBottom.pointee = max(bottomLimit, min(newBottom.pointee, preferred))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawInOwnAppearance {
            NSColor.white.setFill()
            dirtyRect.fill()
            context.saveGState()
            context.clip(to: dirtyRect)
            renderLayers(of: editor.canvas, in: context, clip: dirtyRect.intersection(bounds))
            context.restoreGState()
        }
    }

    private static let drawSelector = #selector(NSView.draw(_:))
    private static let baseDraw = class_getMethodImplementation(NSView.self, drawSelector)

    private func drawsItself(_ view: NSView) -> Bool {
        guard let type = object_getClass(view) else { return false }
        return class_getMethodImplementation(type, Self.drawSelector) != Self.baseDraw
    }

    private func transform(from view: NSView) -> CGAffineTransform {
        let origin = convert(NSPoint.zero, from: view)
        let x = convert(NSPoint(x: 1, y: 0), from: view)
        let y = convert(NSPoint(x: 0, y: 1), from: view)
        return CGAffineTransform(a: x.x - origin.x, b: x.y - origin.y, c: y.x - origin.x, d: y.y - origin.y, tx: origin.x, ty: origin.y)
    }

    private func renderLayers(of view: NSView, in context: CGContext, clip: NSRect) {
        guard !view.isHidden, view.alphaValue > 0.01 else { return }
        let frame = convert(view.bounds, from: view)
        guard frame.intersects(clip) || frame.isEmpty else { return }
        if let layer = view.layer, layer.opacity > 0.01 {
            if view.wantsUpdateLayer { view.updateLayer() }
            let alpha = CGFloat(layer.opacity) * view.alphaValue
            context.saveGState()
            context.clip(to: clip)
            context.concatenate(transform(from: view))
            if alpha < 0.99 { context.setAlpha(alpha); context.beginTransparencyLayer(auxiliaryInfo: nil) }
            let owned = Set(view.subviews.compactMap { $0.layer.map(ObjectIdentifier.init) })
            drawLayerBody(layer, rect: view.bounds, yDown: view.isFlipped, includeContents: !drawsItself(view), in: context)
            if layer.masksToBounds { context.addPath(shape(for: layer, in: view.bounds)); context.clip() }
            let sublayers = (layer.sublayers ?? []).filter { !owned.contains(ObjectIdentifier($0)) }
            if !sublayers.isEmpty {
                context.saveGState()
                let flips = layer.isGeometryFlipped != view.isFlipped
                if flips { context.translateBy(x: 0, y: view.bounds.minY + view.bounds.maxY); context.scaleBy(x: 1, y: -1) }
                for sublayer in sublayers { render(sublayer, yDown: layer.isGeometryFlipped, in: context) }
                context.restoreGState()
            }
            if alpha < 0.99 { context.endTransparencyLayer() }
            context.restoreGState()
        }
        var childClip = clip
        if view is NSClipView || view.layer?.masksToBounds == true { childClip = clip.intersection(frame) }
        guard !childClip.isEmpty else { return }
        for child in view.subviews { renderLayers(of: child, in: context, clip: childClip) }
    }

    private func render(_ layer: CALayer, yDown: Bool, in context: CGContext) {
        guard !layer.isHidden, layer.opacity > 0.01 else { return }
        context.saveGState()
        let frame = layer.frame
        context.translateBy(x: frame.minX, y: frame.minY)
        if !CATransform3DIsIdentity(layer.transform), CATransform3DIsAffine(layer.transform) {
            let anchor = CGPoint(x: frame.width * layer.anchorPoint.x, y: frame.height * layer.anchorPoint.y)
            context.translateBy(x: anchor.x, y: anchor.y)
            context.concatenate(CATransform3DGetAffineTransform(layer.transform))
            context.translateBy(x: -anchor.x, y: -anchor.y)
        }
        let rect = CGRect(origin: .zero, size: frame.size)
        let alpha = CGFloat(layer.opacity)
        if alpha < 0.99 { context.setAlpha(alpha); context.beginTransparencyLayer(auxiliaryInfo: nil) }
        drawLayerBody(layer, rect: rect, yDown: yDown, includeContents: true, in: context)
        if let sublayers = layer.sublayers, !sublayers.isEmpty {
            if layer.masksToBounds { context.addPath(shape(for: layer, in: rect)); context.clip() }
            if layer.isGeometryFlipped { context.translateBy(x: 0, y: rect.height); context.scaleBy(x: 1, y: -1) }
            for sublayer in sublayers { render(sublayer, yDown: yDown != layer.isGeometryFlipped, in: context) }
        }
        if alpha < 0.99 { context.endTransparencyLayer() }
        context.restoreGState()
    }

    private func shape(for layer: CALayer, in rect: CGRect) -> CGPath {
        let radius = min(layer.cornerRadius, min(rect.width, rect.height) / 2)
        guard radius > 0 else { return CGPath(rect: rect, transform: nil) }
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private func drawLayerBody(_ layer: CALayer, rect: CGRect, yDown: Bool, includeContents: Bool, in context: CGContext) {
        if let fill = layer.backgroundColor, fill.alpha > 0.001 {
            context.saveGState()
            context.addPath(shape(for: layer, in: rect))
            context.setFillColor(fill)
            context.fillPath()
            context.restoreGState()
        }
        if let gradient = layer as? CAGradientLayer { drawGradient(gradient, rect: rect, in: context) }
        if let shapeLayer = layer as? CAShapeLayer, let path = shapeLayer.path {
            context.saveGState()
            context.addPath(path)
            if let fill = shapeLayer.fillColor { context.setFillColor(fill); context.fillPath() }
            if let stroke = shapeLayer.strokeColor, shapeLayer.lineWidth > 0 {
                context.addPath(path)
                context.setStrokeColor(stroke)
                context.setLineWidth(shapeLayer.lineWidth)
                context.setLineCap(shapeLayer.lineCap == .round ? .round : shapeLayer.lineCap == .square ? .square : .butt)
                context.setLineJoin(shapeLayer.lineJoin == .round ? .round : shapeLayer.lineJoin == .bevel ? .bevel : .miter)
                context.strokePath()
            }
            context.restoreGState()
        }
        if includeContents, let contents = layer.contents {
            let image: CGImage?
            if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
                image = (contents as! CGImage)
            } else {
                image = (contents as? NSImage)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
            if let image { drawContents(image, of: layer, rect: rect, yDown: yDown, in: context) }
        }
        if layer.borderWidth > 0, let border = layer.borderColor, border.alpha > 0.001 {
            context.saveGState()
            let inset = layer.borderWidth / 2
            context.addPath(shape(for: layer, in: rect.insetBy(dx: inset, dy: inset)))
            context.setStrokeColor(border)
            context.setLineWidth(layer.borderWidth)
            context.strokePath()
            context.restoreGState()
        }
    }

    private func drawContents(_ image: CGImage, of layer: CALayer, rect: CGRect, yDown: Bool, in context: CGContext) {
        let source = CGSize(width: CGFloat(image.width) / max(layer.contentsScale, 1), height: CGFloat(image.height) / max(layer.contentsScale, 1))
        var target = rect
        switch layer.contentsGravity {
        case .resizeAspect, .resizeAspectFill:
            guard source.width > 0, source.height > 0 else { return }
            let fit = layer.contentsGravity == .resizeAspect
            let scale = fit ? min(rect.width / source.width, rect.height / source.height) : max(rect.width / source.width, rect.height / source.height)
            let size = CGSize(width: source.width * scale, height: source.height * scale)
            target = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        case .center:
            target = CGRect(x: rect.midX - source.width / 2, y: rect.midY - source.height / 2, width: source.width, height: source.height)
        default:
            break
        }
        context.saveGState()
        context.addPath(shape(for: layer, in: rect))
        context.clip()
        if yDown {
            context.translateBy(x: 0, y: target.minY + target.maxY)
            context.scaleBy(x: 1, y: -1)
        }
        context.interpolationQuality = .high
        context.draw(image, in: target)
        context.restoreGState()
    }

    private func drawGradient(_ layer: CAGradientLayer, rect: CGRect, in context: CGContext) {
        guard let colors = layer.colors as? [CGColor], colors.count > 1,
              let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray,
                                        locations: layer.locations?.map { CGFloat($0.doubleValue) }) else { return }
        let start = CGPoint(x: rect.minX + rect.width * layer.startPoint.x, y: rect.minY + rect.height * layer.startPoint.y)
        let end = CGPoint(x: rect.minX + rect.width * layer.endPoint.x, y: rect.minY + rect.height * layer.endPoint.y)
        context.saveGState()
        context.addPath(shape(for: layer, in: rect))
        context.clip()
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }
}

@MainActor
final class NotePagePassiveImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class NotePageMenuView: NSView, NoteFloatingPanelContent {
    static let width: CGFloat = 284
    unowned let pageMenu: NotePageMenu
    let list: NoteMenuList
    var preferredSizeDidChange: (() -> Void)?
    private var cards: [NotePageFontCard] = []
    private var switches: [String: NotePageMenuSwitch] = [:]
    private let topSeparator = NSView()
    private let bottomSeparator = NSView()
    private let statsLabel = NSTextField(labelWithString: "")
    private let editedLabel = NSTextField(labelWithString: "")
    private let showsFonts: Bool

    init(menu: NotePageMenu) {
        self.pageMenu = menu
        showsFonts = !menu.isPlainText
        list = NoteMenuList(items: menu.items())
        list.fixedWidth = Self.width
        list.maximumHeight = 600
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 400))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Note Options")
        if showsFonts {
            for font in NotePageFont.allCases {
                let card = NotePageFontCard(font: font)
                card.onPress = { [weak menu] in menu?.setFont(font) }
                cards.append(card)
                addSubview(card)
            }
        }
        list.onActivate = { [weak self] item in
            guard let self else { return }
            self.pageMenu.activate(item, from: self.rowRect(for: item.id))
        }
        list.onCancel = { [weak menu] in menu?.close() }
        list.preferredSizeDidChange = { [weak self] in self?.preferredSizeDidChange?() }
        for separator in [topSeparator, bottomSeparator] {
            separator.wantsLayer = true
            addSubview(separator)
        }
        topSeparator.isHidden = !showsFonts
        statsLabel.font = NoteTheme.nunitoBold(12)
        statsLabel.textColor = NoteTheme.menuSecondaryInk
        editedLabel.font = NoteTheme.nunitoRegular(12)
        editedLabel.textColor = NoteTheme.menuTertiaryInk
        addSubview(list)
        addSubview(statsLabel)
        addSubview(editedLabel)
        refresh()
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var cardsHeight: CGFloat { showsFonts ? NotePageFontCard.size.height + 20 : 0 }
    private var footerHeight: CGFloat { 50 }

    override var fittingSize: NSSize {
        NSSize(width: Self.width, height: cardsHeight + list.fittingSize.height + 1 + footerHeight)
    }

    override var intrinsicContentSize: NSSize { fittingSize }

    func refresh() {
        let current = pageMenu.editor.session.page.settings.font
        for card in cards {
            card.isCurrent = card.pageFont == current
            card.isEnabled = !pageMenu.editor.session.isReadOnly
        }
        let items = pageMenu.items()
        list.setItems(items, keepingHighlight: true)
        refreshSwitches(items)
        let lines = pageMenu.footerLines()
        statsLabel.stringValue = lines.stats
        editedLabel.stringValue = lines.edited
        needsLayout = true
        preferredSizeDidChange?()
    }

    private func refreshSwitches(_ items: [NoteMenuList.Item]) {
        let wanted = items.filter { NotePageMenu.toggleIDs.contains($0.id) }
        for (id, view) in switches where !wanted.contains(where: { $0.id == id }) {
            view.removeFromSuperview()
            switches[id] = nil
        }
        for item in wanted {
            let on = pageMenu.isOn(item.id) ?? false
            let view = switches[item.id] ?? {
                let created = NotePageMenuSwitch(isOn: on)
                addSubview(created, positioned: .above, relativeTo: list)
                switches[item.id] = created
                return created
            }()
            view.isOn = on
            view.isEnabled = item.isEnabled
        }
    }

    func switchView(for id: String) -> NotePageMenuSwitch? { switches[id] }

    func rowRect(for id: String) -> NSRect? {
        let visible = list.visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return nil }
        let separators = visible.prefix(index + 1).enumerated().filter { $0.offset > 0 && $0.element.separatorBefore }.count
        let y = NoteTheme.menuInset + CGFloat(index) * list.rowHeight + CGFloat(separators) * NoteTheme.menuSeparatorSlot
        return convert(NSRect(x: NoteTheme.menuInset, y: y, width: list.frame.width - NoteTheme.menuInset * 2, height: list.rowHeight), from: list)
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        if showsFonts {
            let size = NotePageFontCard.size
            let gap = (bounds.width - 16 - size.width * CGFloat(cards.count)) / CGFloat(max(1, cards.count - 1))
            for (index, card) in cards.enumerated() {
                card.frame = NSRect(x: 8 + CGFloat(index) * (size.width + gap), y: 10, width: size.width, height: size.height)
            }
            y = cardsHeight
            topSeparator.frame = NSRect(x: 0, y: y - 1, width: bounds.width, height: 1)
        }
        let listHeight = list.fittingSize.height
        list.frame = NSRect(x: 0, y: y, width: bounds.width, height: listHeight)
        y += listHeight
        let size = NotePageMenuSwitch.size
        for (id, view) in switches {
            guard let row = rowRect(for: id) else { view.isHidden = true; continue }
            view.isHidden = false
            view.frame = NSRect(x: row.maxX - 10 - size.width, y: (row.midY - size.height / 2).rounded(), width: size.width, height: size.height)
        }
        bottomSeparator.frame = NSRect(x: 0, y: y, width: bounds.width, height: 1)
        y += 9
        let statsHeight = ceil(statsLabel.intrinsicContentSize.height)
        statsLabel.frame = NSRect(x: 14, y: y, width: bounds.width - 28, height: statsHeight)
        editedLabel.frame = NSRect(x: 14, y: y + statsHeight + 1, width: bounds.width - 28, height: ceil(editedLabel.intrinsicContentSize.height))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
        redisplayChromeSubtree()
    }

    private func refreshAppearance() {
        NoteAnimation.withoutAnimation {
            for separator in [topSeparator, bottomSeparator] {
                separator.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self)
            }
        }
    }
}

@MainActor
final class NotePageMenuSwitch: NSView {
    static let size = NoteToggleSwitch.size
    let toggle = NoteToggleSwitch(label: "")

    var isOn: Bool {
        get { toggle.isOn }
        set { toggle.isOn = newValue }
    }

    var isEnabled: Bool {
        get { toggle.isEnabled }
        set {
            toggle.isEnabled = newValue
            alphaValue = newValue ? 1 : NoteTheme.disabledOpacity
            toggle.alphaValue = 1
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawInOwnAppearance {
            let radius = bounds.height / 2
            NoteTheme.hoverFill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    init(isOn: Bool) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        toggle.isOn = isOn
        toggle.setAccessibilityElement(false)
        addSubview(toggle)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        toggle.frame = bounds
    }
}

@MainActor
final class NotePageFontCard: NoteControlButton {
    static let size = NSSize(width: 62, height: 66)
    let pageFont: NotePageFont
    var isCurrent = false { didSet { if isCurrent != oldValue { needsDisplay = true; setAccessibilityValue(isCurrent ? "Selected" : nil) } } }

    init(font: NotePageFont) {
        self.pageFont = font
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        cornerRadius = 8
        setAccessibilityLabel("\(Self.name(font)) font")
        setToolTip(Self.name(font) + " font")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func name(_ font: NotePageFont) -> String {
        switch font {
        case .standard: return "Default"
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .wide: return "Wide"
        }
    }

    static func sampleFont(_ font: NotePageFont) -> NSFont {
        let base = NoteTheme.titleFont(font)
        return NSFont(descriptor: base.fontDescriptor, size: font == .serif ? 27 : font == .standard ? 25 : 21) ?? base
    }

    override var intrinsicContentSize: NSSize { Self.size }

    override func fill(hovered: Bool, pressed: Bool, checked: Bool) -> NSColor? {
        if isCurrent { return NoteTheme.checkedFill }
        return super.fill(hovered: hovered, pressed: pressed, checked: checked)
    }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        drawInOwnAppearance {
            if let fill = fill(hovered: isHovered, pressed: isPressed, checked: false) {
                fill.setFill()
                NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
            }
            if isCurrent {
                NoteTheme.accent.setStroke()
                let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
                ring.lineWidth = 2
                ring.stroke()
            }
            let sampleInk = isCurrent ? NoteTheme.checkedInk : NoteTheme.menuInk
            let sample = NSAttributedString(string: "Ag", attributes: [.font: Self.sampleFont(pageFont), .foregroundColor: sampleInk])
            let size = sample.size()
            sample.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: 30 - size.height / 2 + 2))
            let label = NSAttributedString(string: Self.name(pageFont), attributes: [
                .font: NoteTheme.nunitoBold(11.5), .foregroundColor: isCurrent ? NoteTheme.checkedInk : NoteTheme.menuSecondaryInk])
            let labelSize = label.size()
            label.draw(at: NSPoint(x: bounds.midX - labelSize.width / 2, y: bounds.maxY - labelSize.height - 7))
        }
    }
}

@MainActor
final class NotePageMenuButton: NSView {
    static let size = NSSize(width: 30, height: 30)
    unowned let pageMenu: NotePageMenu
    let button = NoteToolbarButton(icon: .symbol("ellipsis"), label: "Note Options")
    private weak var trackedView: NSView?
    private var paneArea: NSTrackingArea?
    private var isPaneHovered = false
    private var isMenuOpen = false
    private var hasKeyboardFocus = false

    init(menu: NotePageMenu) {
        self.pageMenu = menu
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        button.iconPointSize = 15
        button.onPress = { [weak self] in
            guard let self else { return }
            self.pageMenu.toggle(from: self)
        }
        addSubview(button)
        setAccessibilityElement(false)
        layer?.opacity = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { Self.size }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { NSApp.isFullKeyboardAccessEnabled }

    override func layout() {
        super.layout()
        button.frame = bounds.insetBy(dx: 1, dy: 1)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let paneArea, let trackedView { trackedView.removeTrackingArea(paneArea) }
        paneArea = nil
        trackedView = superview
        guard let superview else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        superview.addTrackingArea(area)
        paneArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPaneHovered = true
        refreshVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        isPaneHovered = false
        refreshVisibility()
    }

    func menuDidOpen() {
        isMenuOpen = true
        button.isChecked = true
        refreshVisibility()
    }

    func menuDidClose() {
        isMenuOpen = false
        button.isChecked = false
        refreshVisibility()
    }

    private func refreshVisibility() {
        guard let layer else { return }
        let visible = isPaneHovered || isMenuOpen || hasKeyboardFocus
        NoteAnimation.fade(layer, to: visible ? 1 : 0, duration: NoteAnimation.hoverDuration)
    }

    override func becomeFirstResponder() -> Bool {
        hasKeyboardFocus = true
        refreshVisibility()
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        hasKeyboardFocus = false
        refreshVisibility()
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76, 49, 125: pageMenu.present(from: self, origin: .keyboard)
        default: super.keyDown(with: event)
        }
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: NoteTheme.controlRadius, yRadius: NoteTheme.controlRadius).fill()
    }

    override func accessibilityChildren() -> [Any]? { [button] }
}
