import AppKit
import Quartz

@MainActor
final class EaselMediaObjects: EaselHostedObjects {
    struct Stage {
        var overlay: NSView
        var viewport: NSView
    }

    weak var canvas: EaselCanvasView?
    let stage: () -> Stage?
    private var views: [UUID: EaselMediaObjectView] = [:]
    private(set) var pendingFills: Set<UUID> = []
    private var unsplashPopover: NotePagePopover?
    private var replacePopover: NotePagePopover?
    var unsplashImport: Task<Void, Never>?

    init(canvas: EaselCanvasView, stage: @escaping () -> Stage?) {
        self.canvas = canvas
        self.stage = stage
    }

    deinit { unsplashImport?.cancel() }

    static func inEditor(_ canvas: EaselCanvasView) -> EaselMediaObjects {
        EaselMediaObjects(canvas: canvas) { [weak canvas] in
            guard let canvas, let scroll = canvas.enclosingScrollView, let host = scroll.superview else { return nil }
            let overlay = host.subviews.compactMap { $0 as? EaselMediaOverlay }.first ?? EaselMediaOverlay()
            if overlay.superview !== host { host.addSubview(overlay, positioned: .above, relativeTo: scroll) }
            if overlay.frame != scroll.frame { overlay.frame = scroll.frame }
            overlay.autoresizingMask = scroll.autoresizingMask
            return Stage(overlay: overlay, viewport: canvas)
        }
    }

    static func inNote(_ canvas: EaselCanvasView, editor: @escaping () -> NotePageEditor?) -> EaselMediaObjects {
        EaselMediaObjects(canvas: canvas) {
            guard let note = editor()?.canvas else { return nil }
            return Stage(overlay: note.overlayView, viewport: note)
        }
    }

    static func hosts(_ item: EaselItem) -> Bool {
        switch item.kind {
        case .video, .audio, .file, .pdf: return true
        case .image: return item.isEmptyPlaceholder
        default: return false
        }
    }

    func hosts(_ item: EaselItem) -> Bool { Self.hosts(item) }

    func hostedView(for item: EaselItem) -> NSView? {
        guard Self.hosts(item), canvas != nil else { return nil }
        let view: EaselMediaObjectView
        if let existing = views[item.id] { view = existing } else {
            view = EaselMediaObjectView(objects: self, item: item)
            views[item.id] = view
        }
        view.show(item)
        return view
    }

    func synchronizeHosted(items: [EaselItem], selection: Set<UUID>, interacting: Bool) {
        var hosted: Set<UUID> = []
        for item in items where Self.hosts(item) { hosted.insert(item.id) }
        for id in Array(views.keys) where !hosted.contains(id) { views.removeValue(forKey: id) }
        pendingFills.formIntersection(hosted)
        for (id, view) in views {
            view.setSelection(selected: selection.contains(id), interactive: interacting && selection == [id])
        }
    }

    func view(for id: UUID) -> EaselMediaObjectView? { views[id] }

    private var quickLookResponder: EaselMediaQuickLookResponder?
    private var anchor: EaselMediaOverlay?

    private func anchorView(for item: EaselItem) -> NSView? {
        if let view = views[item.id], view.window != nil { return view }
        guard let canvas, let overlay = stage()?.overlay else { return nil }
        let view = anchor ?? EaselMediaOverlay()
        if view.superview !== overlay { overlay.addSubview(view) }
        anchor = view
        let rect = NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
        view.frame = overlay.convert(rect, from: canvas)
        return view
    }

    private func quickLookImage(_ item: EaselItem) -> Bool {
        guard let canvas, let overlay = stage()?.overlay else { return false }
        let responder = quickLookResponder ?? EaselMediaQuickLookResponder()
        responder.canvas = canvas
        if responder.superview !== overlay { overlay.addSubview(responder) }
        quickLookResponder = responder
        let rect = NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
        canvas.mediaPreviewURL(item.id) { [weak canvas, weak responder] url in
            guard let canvas, let responder, let url, let window = canvas.window else { return }
            NoteMediaQuickLook.shared.prepare(url, from: canvas, rect: rect)
            window.makeFirstResponder(responder)
            NoteMediaQuickLook.shared.show(from: responder)
        }
        return true
    }

    private func zoomImage(_ item: EaselItem) -> Bool {
        guard item.kind == .image, let canvas, let assetID = item.assetID, let url = try? canvas.session.assetURL(assetID) else { return false }
        let rect = NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
        let pixels = NoteMediaImageLoader.pixels(for: CGSize(width: 2400, height: 2400), scale: canvas.window?.backingScaleFactor ?? 2)
        NoteMediaImageLoader.shared.load(url, pixels: pixels) { [weak self, weak canvas] result in
            guard let self, let canvas, case .success(let image) = result, let stage = self.stage() else { return }
            let crop = item.crop.map { NoteImageCrop(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
            NoteMediaZoomOverlay.present(image: image, source: url, from: rect, of: canvas, in: stage.viewport, overlay: stage.overlay,
                                         crop: crop, mask: item.mask.flatMap { NoteImageMask(rawValue: $0.rawValue) })
        }
        return true
    }

    func fillHosted(_ id: UUID, link url: URL) -> Bool {
        guard let view = views[id], view.canEdit else { return false }
        view.embed(url)
        return true
    }

    func hostedPlayingVideo() -> UUID? {
        views.first { $0.value.isPlayingVideo }?.key
    }

    func canPerformHosted(_ action: EaselHostedAction, on item: EaselItem) -> Bool {
        guard item.kind.isMedia, let canvas else { return false }
        let editable = !canvas.viewOnly && !item.isLocked && !canvas.session.isClosed
        let filled = !item.isEmptyPlaceholder
        switch action {
        case .play, .pause: return item.kind == .video && filled
        case .stopAll: return false
        case .quickLook: return filled && item.kind != .pdf && stage() != nil
        case .fullScreen: return filled && (item.kind == .image || item.kind == .pdf) && stage() != nil
        case .download, .viewOriginal: return filled
        case .replace: return editable && filled
        case .upload: return editable
        case .unsplash: return editable && item.kind == .image && NoteUnsplash.isAvailable && stage() != nil
        case .embedLink: return editable && item.isEmptyPlaceholder && views[item.id] != nil
        }
    }

    func performHosted(_ action: EaselHostedAction, on id: UUID?, from anchor: NSView?) -> Bool {
        if action == .stopAll {
            let playing = views.values.filter(\.isPlayingVideo)
            for view in playing { view.stopVideo() }
            return !playing.isEmpty
        }
        guard let id, let canvas, let item = canvas.session.document.items.first(where: { $0.id == id }),
              canPerformHosted(action, on: item) else { return false }
        switch action {
        case .play:
            for (other, view) in views where other != id && view.isPlayingVideo { view.stopVideo() }
            return views[id]?.playVideo() == true
        case .pause:
            views[id]?.pauseVideo()
            return true
        case .quickLook:
            if let view = views[id] {
                view.quickLook(from: view.bounds, in: view)
                return true
            }
            return quickLookImage(item)
        case .fullScreen:
            if let view = views[id] { return view.presentPreview() }
            return zoomImage(item)
        case .upload:
            canvas.chooseMediaFile(for: id)
            return true
        case .download:
            canvas.downloadMedia(id)
            return true
        case .viewOriginal:
            canvas.mediaPreviewURL(id) { [weak canvas] url in
                guard let url else { return }
                canvas?.onOpenURL?(url)
            }
            return true
        case .replace:
            guard let anchor = anchor ?? anchorView(for: item) else { canvas.chooseMediaFile(for: id); return true }
            if item.kind == .image, NoteUnsplash.isAvailable, stage() != nil {
                presentReplaceMenu(for: id, from: anchor)
            } else {
                canvas.chooseMediaFile(for: id)
            }
            return true
        case .unsplash:
            guard let anchor = anchor ?? anchorView(for: item) else { return false }
            presentUnsplash(for: id, from: anchor)
            return true
        case .embedLink:
            return views[id]?.beginLinkEntry() == true
        case .stopAll:
            return false
        }
    }

    func hostedFillDidChange(_ id: UUID, pending: Bool) {
        if pending { pendingFills.insert(id) } else { pendingFills.remove(id) }
        views[id]?.refresh()
    }

    func presentReplaceMenu(for id: UUID, from anchor: NSView) {
        guard let overlay = stage()?.overlay else { canvas?.chooseMediaFile(for: id); return }
        replacePopover?.close(animated: false)
        replacePopover = NoteMediaPanels.presentReplaceMenu(from: anchor, in: overlay,
            upload: { [weak self] in self?.canvas?.chooseMediaFile(for: id) },
            unsplash: { [weak self, weak anchor] _ in
                guard let self, let anchor else { return }
                self.presentUnsplash(for: id, from: anchor)
            },
            closed: { [weak self] in self?.replacePopover = nil })
    }

    func presentUnsplash(for id: UUID, from anchor: NSView) {
        guard NoteUnsplash.isAvailable, let overlay = stage()?.overlay else { return }
        unsplashPopover?.close(animated: false)
        unsplashPopover = NoteMediaPanels.presentUnsplash(from: anchor, in: overlay, alignment: .leading,
            open: { [weak self] url in self?.canvas?.onOpenURL?(url) },
            pick: { [weak self] photo, browser, popover in self?.importUnsplash(photo, into: id, browser: browser, popover: popover) },
            closed: { [weak self] in
                guard let self else { return }
                self.unsplashPopover = nil
                self.unsplashImport?.cancel()
                self.unsplashImport = nil
            })
    }

    private func importUnsplash(_ photo: NoteUnsplashPhoto, into id: UUID, browser: NoteUnsplashBrowser, popover: NotePagePopover?) {
        guard unsplashImport == nil else { return }
        browser.busyPhotoID = photo.id
        unsplashImport = Task { [weak self, weak browser, weak popover] in
            do {
                let downloaded = try await NoteUnsplashImport.download(photo, width: NoteUnsplash.imageWidth)
                guard let self, !Task.isCancelled else { return }
                self.unsplashImport = nil
                browser?.busyPhotoID = nil
                let credit = EaselMediaCredit(name: downloaded.credit.name, profileURL: downloaded.credit.profileURL?.absoluteString,
                                              photoURL: photo.links.html)
                try self.canvas?.fillImage(id, data: downloaded.data, credit: credit, altText: downloaded.alt)
                popover?.close()
            } catch {
                guard let self else { return }
                self.unsplashImport = nil
                browser?.busyPhotoID = nil
                if !(error is CancellationError) { self.canvas?.onError?(error) }
            }
        }
    }
}

@MainActor
final class EaselMediaObjectView: NSView, NoteMediaHost {
    private weak var objects: EaselMediaObjects?
    let itemID: UUID
    private(set) var item: EaselItem
    private var mode: NoteMediaMode?
    private var content: NoteMediaContentView?
    private var failure: (key: String, problem: NoteMediaProblem)?
    private var selected = false
    private var interactive = false
    private var hovering = false
    private var tracking: NSTrackingArea?
    private let blockID = NoteBlockID()

    init(objects: EaselMediaObjects, item: EaselItem) {
        self.objects = objects
        itemID = item.id
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var canvas: EaselCanvasView? { objects?.canvas }

    func show(_ item: EaselItem) {
        let changed = item != self.item
        self.item = item
        if changed || content == nil { refresh() }
    }

    func setSelection(selected: Bool, interactive: Bool) {
        guard selected != self.selected || interactive != self.interactive else { return }
        self.selected = selected
        self.interactive = interactive
        content?.setSelected(false)
        content?.setHovered(hovering && interactive)
        content?.readOnlyDidChange()
        window?.invalidateCursorRects(for: self)
        if !interactive, let window, let responder = window.firstResponder as? NSView, responder.isDescendant(of: self),
           let canvas, canvas.window === window {
            window.makeFirstResponder(canvas)
        }
    }

    private var sourceKey: String { item.assetID ?? item.url ?? "" }

    func refresh() {
        let source = self.source
        let problem = failure.flatMap { $0.key == sourceKey ? $0.problem : nil }
        let pending = objects?.pendingFills.contains(itemID) == true
        let next: NoteMediaMode = pending ? .pending : NoteMediaMode.resolve(kind: kind, source: source, importing: false, failure: problem)
        if next != mode || content == nil {
            mode = next
            content?.removeFromSuperview()
            let view = next.makeContent(host: self)
            addSubview(view)
            content = view
            view.frame = bounds
            view.setSelected(false)
            view.setHovered(hovering && interactive)
        }
        content?.update(block: block, source: source)
        refreshAccessibility()
        needsLayout = true
    }

    private var block: NoteBlock {
        var props = NoteBlockProps()
        props.source = item.assetID.flatMap { try? canvas?.session.assetURL($0).absoluteString } ?? item.url
        props.alt = item.altText
        props.credit = item.credit.map { NoteMediaCredit(name: $0.name, link: $0.profileURL) }
        return NoteBlock(kind, props: props, id: blockID)
    }

    override func layout() {
        super.layout()
        content?.frame = bounds
    }

    private func refreshAccessibility() {
        setAccessibilityRole(.group)
        setAccessibilityLabel(EaselMediaPlacement.accessibilityLabel(item))
        setAccessibilityValue(item.altText ?? item.fileName)
        setAccessibilityRoleDescription(NoteMediaCopy.roleDescription(for: kind))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactive, !isHidden else { return nil }
        let hit = super.hitTest(point)
        if hit === self || hit === content { return nil }
        return hit
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        content?.setHovered(interactive)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        content?.setHovered(false)
    }

    override var acceptsFirstResponder: Bool { interactive }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " ", event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
            return
        }
        if let canvas { canvas.keyDown(with: event) } else { super.keyDown(with: event) }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { !NoteMediaQuickLook.shared.items.isEmpty }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { NoteMediaQuickLook.shared.attach(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { NoteMediaQuickLook.shared.detach(panel) }

    var kind: NoteBlockKind { EaselMediaHostKinds.noteKind(item.kind) }

    var source: NoteMediaSource { canvas?.mediaSource(item) ?? .empty }

    var nounPhrase: String { NoteMediaCopy.noun(for: kind) }
    var mediaFileName: String { canvas?.mediaFileName(item) ?? NoteMediaCopy.title(for: kind) }
    var canEdit: Bool {
        guard let canvas else { return false }
        return !canvas.viewOnly && !item.isLocked && !canvas.session.isClosed && !canvas.session.isDeleted
    }
    var offersUnsplash: Bool { kind == .image && canEdit && NoteUnsplash.isAvailable && objects?.stage() != nil }
    var offersCaption: Bool { false }
    var offersColumnLayout: Bool { false }
    var offersShowInFinder: Bool { false }
    var isBlockSelected: Bool { selected }
    var isOnScreen: Bool {
        guard let window, window.isVisible, window.occlusionState.contains(.visible), !isHiddenOrHasHiddenAncestor else { return false }
        return !visibleRect.isEmpty
    }
    var embeddablePage: URL? {
        guard let url = source.url, NoteClipboard.playsAsEmbed(url, kind: kind) else { return nil }
        return url
    }
    var mediaOverlay: NSView? { objects?.stage()?.overlay }
    var mediaCanvas: NSView? { objects?.stage()?.viewport }

    func invalidateMeasuredHeight() { needsLayout = true }

    func contentDidFail(_ problem: NoteMediaProblem) {
        failure = (sourceKey, problem)
        refresh()
    }

    func retry() {
        failure = nil
        if case .remote(let url) = source {
            NoteMediaImageLoader.shared.forget(url)
            NoteMediaAssets.forget(url)
        }
        mode = nil
        refresh()
    }

    func selectBlock(with event: NSEvent) -> Bool { false }

    func focusHostBlock() {
        guard let canvas else { return }
        canvas.selectOnly(itemID)
        canvas.window?.makeFirstResponder(canvas)
    }

    func replace() {
        guard canEdit else { return }
        canvas?.chooseMediaFile(for: itemID)
    }

    func importFile(_ url: URL) {
        guard canEdit else { return }
        failure = nil
        canvas?.fillMedia(itemID, fileURL: url)
    }

    func importData(_ data: Data, fileExtension: String, suggestedName: String?) {
        guard canEdit else { return }
        failure = nil
        canvas?.fillMedia(itemID, data: data, fileExtension: fileExtension, fileName: suggestedName)
    }

    func embed(_ url: URL) {
        guard canEdit else { return }
        failure = nil
        if NoteClipboard.playsAsEmbed(url, kind: kind) { embedAsPage(url); return }
        canvas?.fillMediaLink(itemID, url: url)
    }

    func embedAsPage(_ url: URL) {
        guard canEdit else { return }
        failure = nil
        canvas?.turnMediaIntoEmbed(itemID, url: url)
    }

    func presentReplaceMenu(from anchor: NSView) {
        guard canEdit else { return }
        guard offersUnsplash else { replace(); return }
        objects?.presentReplaceMenu(for: itemID, from: anchor)
    }

    func presentUnsplash(from anchor: NSView) {
        guard offersUnsplash else { return }
        objects?.presentUnsplash(for: itemID, from: anchor)
    }

    func revealCaption() {}
    func setAlignment(_ alignment: NoteAlignment) {}
    func commitWidth(_ fraction: Double?) {}
    func commitFraming(crop: NoteImageCrop?, mask: NoteImageMask?, name: String) {}
    func showInFinder() {}

    func deleteBlock() {
        guard canEdit, let canvas, canvas.selectOnly(itemID) else { return }
        _ = canvas.deleteSelection()
    }

    func download() {
        canvas?.downloadMedia(itemID)
    }

    func open(_ url: URL) {
        canvas?.onOpenURL?(url)
    }

    func quickLook(from rect: NSRect, in view: NSView) {
        canvas?.mediaPreviewURL(itemID) { [weak self, weak view] url in
            guard let self, let view, let url, let window = self.window else { return }
            NoteMediaQuickLook.shared.prepare(url, from: view, rect: rect)
            if window.firstResponder !== self { window.makeFirstResponder(self) }
            NoteMediaQuickLook.shared.show(from: self)
        }
    }

    func zoom(image: NoteMediaImage, from rect: NSRect, in view: NSView, crop: NoteImageCrop?, mask: NoteImageMask?) {
        guard let stage = objects?.stage() else { return }
        NoteMediaZoomOverlay.present(image: image, source: source.url, from: rect, of: view, in: stage.viewport, overlay: stage.overlay,
                                     crop: crop, mask: mask)
    }

    func setAltText(_ text: String) {
        guard canEdit else { return }
        canvas?.setMediaAltText(itemID, text: text)
    }

    func presentPreview() -> Bool {
        guard let content else { return false }
        if let pdf = content as? NotePDFContentView { return pdf.presentFullScreen() }
        guard source.url != nil, mode == .video || mode == .audio || mode == .file else { return false }
        quickLook(from: content.bounds, in: content)
        return true
    }

    func beginLinkEntry() -> Bool {
        (content as? NoteMediaEmptyCard)?.beginLinkEntry() ?? false
    }

    var isPlayingVideo: Bool { (content as? NoteVideoContentView)?.isPlaying == true }

    func playVideo() -> Bool {
        guard let video = content as? NoteVideoContentView else { return false }
        video.play()
        return true
    }

    func pauseVideo() { (content as? NoteVideoContentView)?.pause() }

    func stopVideo() { (content as? NoteVideoContentView)?.stop() }
}

extension EaselCanvasView {
    func chooseMediaFile(for id: UUID) {
        guard let item = session.document.items.first(where: { $0.id == id }), item.kind.isMedia, !item.isLocked else { return }
        NoteMediaActions.chooseFile(for: EaselMediaHostKinds.noteKind(item.kind), in: window) { [weak self] url in
            self?.fillMedia(id, fileURL: url)
        }
    }

    func mediaSource(_ item: EaselItem) -> NoteMediaSource {
        if let id = item.assetID {
            guard let url = try? session.assetURL(id) else { return .unresolved(id) }
            return .local(url)
        }
        if let raw = item.url, let url = URL(string: raw) { return .remote(url) }
        return .empty
    }

    func mediaFileName(_ item: EaselItem) -> String {
        if let name = item.fileName { return name }
        let kind = EaselMediaHostKinds.noteKind(item.kind)
        guard item.url != nil else {
            let ext = item.assetID.flatMap(EaselAssetType.fileExtension(of:)).map { "." + $0 } ?? ""
            return NoteMediaCopy.title(for: kind) + ext
        }
        return mediaSource(item).fileName
    }

    func downloadMedia(_ id: UUID) {
        guard let item = session.document.items.first(where: { $0.id == id }) else { return }
        NoteMediaActions.saveCopy(of: mediaSource(item), suggestedName: mediaFileName(item), in: window) { [weak self] error in
            if let error { self?.onError?(error) }
        }
    }

    func mediaPreviewURL(_ id: UUID, completion: @escaping (URL?) -> Void) {
        guard let item = session.document.items.first(where: { $0.id == id }) else { completion(nil); return }
        let source = mediaSource(item)
        if case .local(let url) = source, let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           let staged = try? Self.stagedFile(data, fileExtension: url.pathExtension, fileName: mediaFileName(item)) {
            completion(staged)
            return
        }
        NoteMediaActions.previewURL(for: source, completion: completion)
    }
}

enum EaselMediaHostKinds {
    static func noteKind(_ kind: EaselItemKind) -> NoteBlockKind {
        switch kind {
        case .video: return .video
        case .audio: return .audio
        case .pdf: return .pdf
        case .file: return .file
        default: return .image
        }
    }
}

@MainActor
final class EaselMediaOverlay: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

@MainActor
final class EaselMediaQuickLookResponder: NSView {
    weak var canvas: EaselCanvasView?
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || event.keyCode == 53, QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
            if let canvas { window?.makeFirstResponder(canvas) }
            return
        }
        if let canvas { canvas.keyDown(with: event) } else { super.keyDown(with: event) }
    }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { !NoteMediaQuickLook.shared.items.isEmpty }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { NoteMediaQuickLook.shared.attach(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { NoteMediaQuickLook.shared.detach(panel) }
}
