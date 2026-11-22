import AppKit
import Combine
import ParcCore
import Quartz
import UniformTypeIdentifiers
import ParcKit

public enum NoteMediaProblem: Equatable {
    case missing, unreachable, unreadable, unsupported
}

@MainActor
final class NoteMediaBlockView: NoteCaptionedBlockView, NotePageHostObserving {
    private typealias Mode = NoteMediaMode

    private var mode: Mode?
    private var content: NoteMediaContentView?
    private var tracking: NSTrackingArea?
    private var pageZone = NoteZoneCursor()
    private var observers: [NSObjectProtocol] = []
    private var failure: (source: String, problem: NoteMediaProblem)?
    private var importWatch: AnyCancellable?
    private(set) var isHovering = false
    private let creditLine = NoteCreditLabel()
    private var unsplashPopover: NotePagePopover?
    private var replacePopover: NotePagePopover?
    private var unsplashImport: Task<Void, Never>?
    private var captureHeader: NoteCaptureSnapshotHeader?
    private var liveSurface: NoteCaptureLiveSurface?
    private var liveEducation: ParcDialog?
    private static let creditGap: CGFloat = 3

    override init(block: NoteBlock, editor: NotePageEditor?) {
        super.init(block: block, editor: editor)
        creditLine.font = NoteMediaStyle.smallFont
        creditLine.linkFont = NoteMediaStyle.nunito(12, weight: .bold)
        creditLine.ink = NoteTheme.tertiaryInk
        creditLine.linkInk = NoteTheme.secondaryInk
        creditLine.onOpen = { [weak self] url in self?.open(url) }
        creditLine.isHidden = true
        addSubview(creditLine)
        setAccessibilityElement(true)
        if let editor {
            importWatch = NoteMediaImport.imports(for: editor.environment).changes.sink { [weak self] source in
                guard let self, source == self.block.props.source else { return }
                self.importDidFinish()
            }
        }
        rebuild(notify: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        unsplashImport?.cancel()
    }

    var source: NoteMediaSource {
        let environment = editor?.environment
        return NoteMediaSource(block.props.source) { environment?.resolve($0) ?? URL(string: $0) }
    }

    var isImporting: Bool {
        guard let editor else { return false }
        return NoteMediaImport.imports(for: editor.environment).isPending(block.props.source, in: editor.session)
    }

    private func importDidFinish() {
        let copyError = editor.flatMap { NoteMediaImport.imports(for: $0.environment).takeFailure(of: block.props.source, in: $0.session) }
        rebuild()
        guard copyError != nil, canEdit, case .local(let url) = source, FileManager.default.fileExists(atPath: url.path) else { return }
        reportMediaError(NoteAttachmentError.leftInPlace(url.lastPathComponent))
    }

    var kind: NoteBlockKind { block.kind }
    var nounPhrase: String { NoteMediaCopy.noun(for: kind) }
    var mediaFileName: String { source.fileName }
    var offersCaption: Bool { !captionVisible }
    var offersColumnLayout: Bool { true }
    var offersShowInFinder: Bool { true }
    var mediaOverlay: NSView? { editor?.canvas.overlayView }
    var mediaCanvas: NSView? { editor?.canvas }

    func focusHostBlock() {
        editor?.session.setSelection(.blocks([blockID]))
    }

    override func update(_ block: NoteBlock) {
        let previous = self.block
        super.update(block)
        if previous.kind != block.kind || previous.props.source != block.props.source { failure = nil }
        if previous.kind == block.kind, previous.props.source != block.props.source, let editor,
           let landed = NoteMediaImport.imports(for: editor.environment).landedPath(for: previous.props.source, in: editor.session),
           landed == block.props.source {
            content?.rebind(to: source)
        }
        rebuild(notify: false)
    }

    private func resolveMode() -> Mode {
        let problem = failure.flatMap { $0.source == block.props.source ? $0.problem : nil }
        return Mode.resolve(kind: kind, source: source, importing: isImporting, failure: problem, plainText: editor?.isPlainText == true)
    }

    static func problem(for error: NoteMediaImageError) -> NoteMediaProblem {
        switch error {
        case .missing: return .missing
        case .unreadable, .tooLarge: return .unreadable
        case .badStatus, .offline: return .unreachable
        }
    }

    private func scheduleResume() {
        guard canEdit, block.props.source?.hasPrefix("file:") == true else { return }
        _ = NoteFileSystemClock.shared.schedule(after: 0) { [weak self] in
            guard let self, self.canEdit, let environment = self.editor?.environment else { return }
            NoteMediaImport.resume(self.block.props.source, environment: environment)
        }
    }

    private func rebuild(notify: Bool = true) {
        scheduleResume()
        let next = resolveMode()
        if next != mode || content == nil {
            mode = next
            content?.removeFromSuperview()
            let view = next.makeContent(host: self)
            addSubview(view, positioned: .below, relativeTo: caption)
            content = view
            view.setHovered(isHovering)
            view.setSelected(isBlockSelected)
        }
        content?.update(block: block, source: source)
        refreshCapture()
        refreshCaption()
        refreshCredit()
        refreshAccessibility()
        if notify { invalidateMeasuredHeight() } else { needsLayout = true }
    }

    override var allowsCaption: Bool { mode != .empty }

    override func measureHeight(width: CGFloat) -> CGFloat {
        let inset = NoteMediaStyle.verticalInset
        let span = content?.captionSpan(width: width) ?? (x: 0, width: width)
        let height = inset + captureHeaderHeight + (content?.measureHeight(width: width) ?? 44) + inset + captionHeight(width: span.width) + creditHeight
        return ceil(height)
    }

    private var showsCredit: Bool {
        guard block.props.credit != nil else { return false }
        switch mode {
        case .image, .video, .audio, .file: return true
        default: return false
        }
    }

    private var creditHeight: CGFloat {
        showsCredit ? Self.creditGap + creditLine.intrinsicContentSize.height : 0
    }

    private func refreshCredit() {
        creditLine.parts = block.props.credit?.parts ?? []
        creditLine.isHidden = !showsCredit
    }

    override var handleAnchorY: CGFloat {
        captureHeader != nil ? NoteMediaStyle.verticalInset + EmbeddedPageHeader.height / 2 : NoteMediaStyle.verticalInset + (content?.handleAnchorY ?? 14)
    }

    private var showsCapture: Bool { mode == .image && NoteCaptureLive.capture(of: block) != nil }

    private var captureHeaderHeight: CGFloat { showsCapture ? EmbeddedPageHeader.height : 0 }

    private var pages: NoteEmbeddedPages? { editor.flatMap { NoteEmbeddedPages.pool(for: $0) } }

    func pageHostDidChange() {
        refreshCapture()
        invalidateMeasuredHeight()
    }

    private func refreshCapture() {
        guard showsCapture else {
            captureHeader?.removeFromSuperview()
            captureHeader = nil
            detachLiveSurface()
            content?.isHidden = false
            return
        }
        let header = captureHeader ?? NoteCaptureSnapshotHeader()
        if captureHeader == nil {
            header.onMakeLive = { [weak self] in self?.makeLive() }
            header.onSnapshot = { [weak self] in self?.showSnapshot() }
            header.onOpen = { [weak self] in
                guard let self, let address = NoteCaptureLive.capture(of: self.block)?.sourceAddress else { return }
                self.editor?.open(address)
            }
            addSubview(header, positioned: .below, relativeTo: caption)
            captureHeader = header
        }
        header.configure(block: block, canEdit: canEdit)
        if window != nil, let capture = NoteEmbeddedPages.liveCapture(of: block),
           let next = pages?.captureSurface(for: blockID, address: capture.address, layout: capture.layout,
                                            title: NoteCaptureText.title(for: block.props.capture!, alt: block.props.alt)) {
            if next.superview !== self { addSubview(next, positioned: .below, relativeTo: caption) }
            if liveSurface !== next { detachLiveSurface() }
            liveSurface = next
            next.selected = isBlockSelected
        } else {
            detachLiveSurface()
        }
        let live = liveSurface != nil
        header.isHidden = live
        content?.isHidden = live
        needsLayout = true
    }

    private func detachLiveSurface() {
        if let liveSurface, liveSurface.superview === self { liveSurface.removeFromSuperview() }
        liveSurface = nil
    }

    func makeLive() {
        guard canEdit, NoteCaptureLive.canMakeLive(block), !NoteCaptureLive.ownsLivePage(block), let session = editor?.session else { return }
        guard UserDefaults.standard.bool(forKey: NoteCaptureSnapshotHeader.educationKey) else {
            guard liveEducation == nil else { return }
            let original = block
            liveEducation = NoteCaptureSnapshotHeader.presentEducation(in: window) { [weak self] in
                guard let self else { return }
                self.liveEducation = nil
                guard self.window != nil, self.editor?.session.page.block(self.blockID) == original else { return }
                self.makeLive()
            }
            if liveEducation == nil { NSSound.beep() }
            return
        }
        session.updateBlock(blockID, name: "Make Captured Region Live") { $0.props.capture?.live = true }
    }

    func showSnapshot() {
        guard canEdit, NoteCaptureLive.ownsLivePage(block) else { return }
        if let pages { pages.showSnapshot(blockID) }
        else { editor?.session.updateBlock(blockID, name: "Show Captured Image") { $0.props.capture?.live = false } }
    }

    override func mouseDown(with event: NSEvent) {
        guard let liveSurface, liveSurface.superview === self, !liveSurface.interactive, let pages,
              liveSurface.takesPageInput(at: event.locationInWindow) else {
            super.mouseDown(with: event)
            return
        }
        pages.activate(blockID)
        refreshCursorIfPointerOwned()
        if liveSurface.interactive { window?.postEvent(event, atStart: true) }
    }

    private func pageCursor(for event: NSEvent) -> NSCursor? {
        guard let liveSurface, liveSurface.superview === self, !liveSurface.interactive,
              convert(liveSurface.pageRect, from: liveSurface).contains(convert(event.locationInWindow, from: nil)) else { return nil }
        return .pointingHand
    }

    override func cursorUpdate(with event: NSEvent) {
        if !pageZone.cursorUpdate(pageCursor(for: event), in: self, event: event) { super.cursorUpdate(with: event) }
    }

    override func layout() {
        super.layout()
        guard let content else { return }
        let inset = NoteMediaStyle.verticalInset
        let width = bounds.width
        let height = content.measureHeight(width: width)
        let headerHeight = captureHeaderHeight
        content.frame = NSRect(x: 0, y: inset + headerHeight, width: width, height: height)
        if showsCapture {
            let image = (content as? NoteImageContentView)?.imageRect ?? NSRect(x: 0, y: 0, width: width, height: height)
            var header = NoteCaptureSnapshotHeader.frame(imageRect: image, columnWidth: width, alignment: block.props.alignment)
            header.origin.y = inset
            NoteAnimation.withoutAnimation {
                captureHeader?.frame = header
                liveSurface?.frame = NSRect(x: header.minX, y: inset, width: header.width, height: headerHeight + image.height)
            }
        }
        let span = content.captionSpan(width: width)
        layoutCaption(top: content.frame.maxY, x: span.x, width: span.width)
        if showsCredit {
            let top = (captionVisible ? caption.frame.maxY : content.frame.maxY) + Self.creditGap
            let size = creditLine.intrinsicContentSize
            creditLine.frame = NSRect(x: span.x, y: top, width: min(size.width, span.width), height: size.height)
        }
    }

    override func setBlockSelected(_ selected: Bool, animated: Bool) {
        super.setBlockSelected(selected, animated: animated)
        content?.setSelected(selected)
        if let liveSurface, liveSurface.superview === self { liveSurface.selected = selected }
    }

    override func readOnlyDidChange() {
        rebuild()
        content?.readOnlyDidChange()
    }

    override func themeDidChange() {
        super.themeDidChange()
        content?.needsLayout = true
        content?.needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { setHovering(isTopmost(atWindowPoint: event.locationInWindow)) }

    override func mouseMoved(with event: NSEvent) {
        setHovering(isTopmost(atWindowPoint: event.locationInWindow))
        pageZone.moved(pageCursor(for: event), in: self, event: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
        pageZone.exited()
    }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        content?.setHovered(hovering)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        if window == nil { setHovering(false) } else if showsCapture { refreshCapture() }
        if let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.content?.visibilityDidChange() }
            })
        }
        if let window {
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.content?.visibilityDidChange() }
            })
        }
        content?.visibilityDidChange()
    }

    override func viewDidHide() {
        super.viewDidHide()
        content?.visibilityDidChange()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        content?.visibilityDidChange()
    }

    var isOnScreen: Bool {
        guard let window, window.isVisible, window.occlusionState.contains(.visible), !isHiddenOrHasHiddenAncestor else { return false }
        return !visibleRect.isEmpty
    }

    private func refreshAccessibility() {
        let name = block.props.alt.flatMap { $0.isEmpty ? nil : $0 } ?? (block.props.caption.isEmpty ? source.fileName : block.props.caption.plainText)
        switch kind {
        case .image:
            setAccessibilityRole(.image)
            setAccessibilityLabel(name.isEmpty ? "Image" : name)
            let framing = [block.props.crop == nil ? nil : "cropped", block.props.mask.map { $0.title.lowercased() + " shape" }].compactMap { $0 }
            setAccessibilityValue(framing.isEmpty ? nil : framing.joined(separator: ", "))
        default:
            setAccessibilityRole(.group)
            setAccessibilityLabel(name.isEmpty ? NoteMediaCopy.title(for: kind) : name)
        }
        setAccessibilityRoleDescription(NoteMediaCopy.roleDescription(for: kind))
    }

    func contentDidFail(_ problem: NoteMediaProblem) {
        failure = (block.props.source ?? "", problem)
        rebuild()
    }

    func retry() {
        failure = nil
        if case .remote(let url) = source {
            NoteMediaImageLoader.shared.forget(url)
            NoteMediaAssets.forget(url)
        }
        mode = nil
        rebuild()
    }

    override func focus(at offset: Int?, field: NoteTextField = .body) -> Bool {
        if field == .caption { return super.focus(at: offset, field: field) }
        guard mode == .empty, canEdit, let card = content as? NoteMediaEmptyCard else { return false }
        return card.beginLinkEntry()
    }

    func selectBlock(with event: NSEvent) -> Bool {
        editor?.selection.blockMouseDown(self, with: event) ?? false
    }

    func replace() {
        guard canEdit else { return }
        NoteMediaActions.chooseFile(for: kind, in: window) { [weak self] url in self?.importFile(url) }
    }

    func importFile(_ url: URL) {
        guard canEdit, let editor else { return }
        let name = (block.props.source == nil ? "Add " : "Replace ") + NoteMediaCopy.title(for: kind)
        failure = nil
        do {
            try NoteMediaImport.replace(blockID, with: url, name: name, in: editor.session, environment: editor.environment)
        } catch {
            reportMediaError(error)
        }
    }

    func importData(_ data: Data, fileExtension: String, suggestedName: String?) {
        guard canEdit, let editor else { return }
        do {
            let source = try NoteMediaImport.source(importing: data, fileExtension: fileExtension, suggestedName: suggestedName,
                                                    environment: editor.environment)
            setSource(source, name: "Add " + NoteMediaCopy.title(for: kind))
        } catch {
            reportMediaError(error)
        }
    }

    func embed(_ url: URL) {
        guard canEdit else { return }
        if NoteClipboard.playsAsEmbed(url, kind: kind) { embedAsPage(url); return }
        setSource(url.absoluteString, name: "Embed " + NoteMediaCopy.title(for: kind))
    }

    var embeddablePage: URL? {
        guard let url = source.url, NoteClipboard.playsAsEmbed(url, kind: kind) else { return nil }
        return url
    }

    func embedAsPage(_ url: URL) {
        guard canEdit else { return }
        failure = nil
        editor?.session.updateBlock(blockID, name: "Embed") { block in
            block.kind = .embed
            block.props.source = url.absoluteString
            block.props.credit = nil
            block.props.crop = nil
        }
    }

    private func setSource(_ value: String, name: String) {
        failure = nil
        editor?.session.updateBlock(blockID, name: name) { block in
            block.props.source = value
            block.props.credit = nil
            block.props.crop = nil
        }
    }

    var offersUnsplash: Bool { kind == .image && canEdit && NoteUnsplash.isAvailable }

    func presentReplaceMenu(from anchor: NSView) {
        guard canEdit else { return }
        guard offersUnsplash, let editor else { replace(); return }
        replacePopover?.close(animated: false)
        replacePopover = NoteMediaPanels.presentReplaceMenu(from: anchor, in: editor.canvas.overlayView,
            upload: { [weak self] in self?.replace() },
            unsplash: { [weak self] anchor in
                guard let self else { return }
                self.presentUnsplash(from: anchor ?? self)
            },
            closed: { [weak self] in self?.replacePopover = nil })
    }

    func presentUnsplash(from anchor: NSView) {
        guard offersUnsplash, let editor else { return }
        unsplashPopover?.close(animated: false)
        let alignment: NoteFloatingPanel.Alignment = anchor === self || anchor is NoteMediaEmptyCard ? .leading : .trailing
        unsplashPopover = NoteMediaPanels.presentUnsplash(from: anchor, in: editor.canvas.overlayView, alignment: alignment,
            open: { [weak self] url in self?.open(url) },
            pick: { [weak self] photo, browser, popover in self?.importUnsplash(photo, browser: browser, popover: popover) },
            closed: { [weak self] in
                guard let self else { return }
                self.unsplashPopover = nil
                self.unsplashImport?.cancel()
                self.unsplashImport = nil
            })
    }

    private func importUnsplash(_ photo: NoteUnsplashPhoto, browser: NoteUnsplashBrowser, popover: NotePagePopover?) {
        guard unsplashImport == nil, canEdit, let environment = editor?.environment else { return }
        browser.busyPhotoID = photo.id
        unsplashImport = Task { [weak self, weak browser, weak popover] in
            do {
                let imported = try await NoteUnsplashImport.importPhoto(photo, width: NoteUnsplash.imageWidth, environment: environment)
                guard let self, !Task.isCancelled else { return }
                self.unsplashImport = nil
                browser?.busyPhotoID = nil
                self.applyUnsplash(imported)
                popover?.close()
            } catch {
                guard let self else { return }
                self.unsplashImport = nil
                browser?.busyPhotoID = nil
                if !(error is CancellationError) { self.reportMediaError(error) }
            }
        }
    }

    private func applyUnsplash(_ imported: NoteUnsplashImport.Imported) {
        guard canEdit else { return }
        failure = nil
        let name = (block.props.source == nil ? "Add " : "Replace ") + NoteMediaCopy.title(for: kind)
        editor?.session.updateBlock(blockID, name: name) { block in
            let replacesOwnAlt = block.props.credit != nil || (block.props.alt ?? "").isEmpty
            block.props.source = imported.source
            block.props.credit = imported.credit
            block.props.crop = nil
            if replacesOwnAlt { block.props.alt = imported.alt }
        }
    }

    func setAlignment(_ alignment: NoteAlignment) {
        guard canEdit, block.props.alignment != alignment else { return }
        editor?.session.updateBlock(blockID, name: "Align " + NoteMediaCopy.title(for: kind)) { $0.props.alignment = alignment }
    }

    func commitWidth(_ fraction: Double?) {
        guard canEdit else { return }
        editor?.session.updateBlock(blockID, name: "Resize " + NoteMediaCopy.title(for: kind)) { $0.props.width = fraction }
    }

    func deleteBlock() {
        guard canEdit else { return }
        editor?.session.deleteBlocks([blockID])
    }

    func download() {
        NoteMediaActions.saveCopy(of: source, suggestedName: source.fileName, in: window) { [weak self] error in
            if let error { self?.reportMediaError(error) }
        }
    }

    func showInFinder() {
        guard case .local(let url) = source else { return }
        NoteMediaActions.showInFinder(url)
    }

    func open(_ url: URL) {
        editor?.open(url)
    }

    func quickLook(from rect: NSRect, in view: NSView) {
        NoteMediaActions.previewURL(for: source) { [weak self, weak view] url in
            guard let self, let view, let url, let window = self.window else { return }
            NoteMediaQuickLook.shared.prepare(url, from: view, rect: rect)
            if window.firstResponder !== self { window.makeFirstResponder(self) }
            NoteMediaQuickLook.shared.show(from: self)
        }
    }

    override var acceptsFirstResponder: Bool { mode != nil && mode != .empty }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " ", event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
            return
        }
        if editor?.handleKeyDown(event, in: nil) == true { return }
        super.keyDown(with: event)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { !NoteMediaQuickLook.shared.items.isEmpty }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { NoteMediaQuickLook.shared.attach(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { NoteMediaQuickLook.shared.detach(panel) }

    @discardableResult
    func presentPreview() -> Bool {
        guard let content else { return false }
        if let image = content as? NoteImageContentView, image.presentZoom() { return true }
        if let pdf = content as? NotePDFContentView { return pdf.presentFullScreen() }
        switch mode {
        case .image, .video, .audio, .file:
            guard source.url != nil else { return false }
            quickLook(from: content.bounds, in: content)
            return true
        default:
            return false
        }
    }

    func zoom(image: NoteMediaImage, from rect: NSRect, in view: NSView, crop: NoteImageCrop? = nil, mask: NoteImageMask? = nil) {
        guard let canvas = editor?.canvas else { return }
        NoteMediaZoomOverlay.present(image: image, source: source.url, from: rect, of: view, in: canvas, overlay: canvas.overlayView,
                                     crop: crop, mask: mask)
    }

    var imageContent: NoteImageContentView? { content as? NoteImageContentView }

    func commitFraming(crop: NoteImageCrop?, mask: NoteImageMask?, name: String) {
        guard canEdit else { return }
        let crop = crop.flatMap { $0.isFull ? nil : $0.normalized }
        guard crop != block.props.crop || mask != block.props.mask else { return }
        editor?.session.updateBlock(blockID, name: name) { block in
            block.props.crop = crop
            block.props.mask = mask
        }
    }

    func setAltText(_ text: String) {
        guard canEdit else { return }
        let cleaned = text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let value: String? = cleaned.isEmpty ? nil : cleaned
        guard value != block.props.alt else { return }
        editor?.session.updateBlock(blockID, name: "Alt Text") { $0.props.alt = value }
    }

    func beginCrop() { imageContent?.beginCrop() }
    func editAltText() { imageContent?.editAltText() }
    func showMaskPicker() { imageContent?.showMaskPicker() }

    func applyMask(_ mask: NoteImageMask?) {
        if let imageContent { imageContent.applyMask(mask); return }
        let natural = source.url.flatMap { NoteMediaImageLoader.shared.naturalSize(of: $0) }
        let next = NoteImageFraming.applying(mask, to: block.props, natural: natural)
        commitFraming(crop: next.crop, mask: next.mask, name: mask == nil ? "Remove Mask" : "Mask Image")
    }
}

@MainActor
package enum NoteMediaCopy {
    package static func noun(for kind: NoteBlockKind) -> String {
        switch kind {
        case .image: return "image"
        case .video: return "video"
        case .audio: return "audio"
        case .pdf: return "PDF"
        default: return "file"
        }
    }

    package static func title(for kind: NoteBlockKind) -> String {
        switch kind {
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .pdf: return "PDF"
        default: return "File"
        }
    }

    package static func roleDescription(for kind: NoteBlockKind) -> String {
        switch kind {
        case .image: return "image block"
        case .video: return "video block"
        case .audio: return "audio block"
        case .pdf: return "PDF block"
        default: return "file block"
        }
    }

    static func addPrompt(for kind: NoteBlockKind) -> String {
        switch kind {
        case .image: return "Add an image"
        case .video: return "Add a video"
        case .audio: return "Add audio"
        case .pdf: return "Add a PDF"
        default: return "Add a file"
        }
    }

    static func emptyReadOnly(for kind: NoteBlockKind) -> String {
        switch kind {
        case .image: return "No image here yet"
        case .video: return "No video here yet"
        case .audio: return "No audio here yet"
        case .pdf: return "No PDF here yet"
        default: return "No file here yet"
        }
    }

    static func symbol(for kind: NoteBlockKind) -> String {
        switch kind {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        default: return "paperclip"
        }
    }

    static func problemTitle(_ problem: NoteMediaProblem, kind: NoteBlockKind) -> String {
        let thing: String
        switch kind {
        case .image: thing = "image"
        case .video: thing = "video"
        case .audio: thing = "sound"
        case .pdf: thing = "PDF"
        default: thing = "file"
        }
        switch problem {
        case .missing: return "Couldn’t find this \(thing)"
        case .unreachable: return "Couldn’t load this \(thing)"
        case .unreadable: return "This \(thing) won’t open"
        case .unsupported: return "This \(thing) can’t play here"
        }
    }
}

@MainActor
public class NoteMediaContentView: NSView, Sendable {
    weak var host: NoteMediaHost?

    init(host: NoteMediaHost) {
        self.host = host
        super.init(frame: .zero)
        wantsLayer = true
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }

    func measureHeight(width: CGFloat) -> CGFloat { 44 }
    var handleAnchorY: CGFloat { 14 }
    package func update(block: NoteBlock, source: NoteMediaSource) {}
    package func setHovered(_ hovered: Bool) {}
    package func setSelected(_ selected: Bool) {}
    func rebind(to source: NoteMediaSource) {}
    package func readOnlyDidChange() {}
    func visibilityDidChange() {}
    func captionSpan(width: CGFloat) -> (x: CGFloat, width: CGFloat) { (0, width) }
}

@MainActor
public class NoteMediaCardView: NoteMediaContentView {
    let card = CALayer()
    var cardHighlighted = false { didSet { if oldValue != cardHighlighted { refreshCard() } } }
    var cardHovered = false { didSet { if oldValue != cardHovered { refreshCard() } } }
    var cardSelected = false { didSet { if oldValue != cardSelected { refreshCard() } } }

    public override init(host: NoteMediaHost) {
        super.init(host: host)
        card.cornerRadius = NoteMediaStyle.cardRadius
        card.cornerCurve = .continuous
        card.borderWidth = 1
        layer?.addSublayer(card)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func layout() {
        super.layout()
        NoteMediaMotion.instant { card.frame = bounds }
        refreshCard()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshCard()
    }

    public override func setSelected(_ selected: Bool) { cardSelected = selected }

    func refreshCard() {
        let fill = cardHighlighted ? NoteMediaStyle.dropFill : (cardHovered ? NoteMediaStyle.cardHover : NoteMediaStyle.cardFill)
        let stroke = cardHighlighted || cardSelected ? NoteTheme.accent : NoteMediaStyle.cardStroke
        let fillColor = NoteMediaStyle.cg(fill, in: self), strokeColor = NoteMediaStyle.cg(stroke, in: self)
        let from = card.presentation()?.backgroundColor
        NoteMediaMotion.instant {
            card.backgroundColor = fillColor
            card.borderColor = strokeColor
            card.borderWidth = cardHighlighted || cardSelected ? 1.5 : 1
        }
        guard window != nil, !NoteAnimation.reduceMotion, let from else { return }
        let fade = CABasicAnimation(keyPath: "backgroundColor")
        fade.fromValue = from
        fade.toValue = fillColor
        fade.duration = 0.1
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.42, 0, 1, 1)
        card.add(fade, forKey: "media.card.fill")
    }
}

@MainActor
package final class NoteMediaEmptyCard: NoteMediaCardView, NSTextFieldDelegate {
    private let icon = NSImageView()
    private let title: NSTextField
    private let uploadChip: NoteChip
    private let linkChip: NoteChip
    private let field = NoteInputField()
    private let embedChip: NoteChip
    private let fieldUploadChip: NoteChip
    private let unsplashChip = NoteChip("Unsplash", icon: .symbol("photo.on.rectangle.angled"))
    private let hint: NSTextField
    private var enteringLink = false
    private static let height: CGFloat = 52

    package override init(host: NoteMediaHost) {
        let kind = host.kind
        title = NoteMediaStyle.label(NoteMediaCopy.addPrompt(for: kind), font: NoteMediaStyle.titleFont, color: NoteTheme.secondaryInk)
        uploadChip = NoteChip("Upload", icon: .symbol(kind == .file || kind == .pdf ? "arrow.up.doc" : "square.and.arrow.up"))
        linkChip = NoteChip("Embed link", icon: .symbol("link"))
        embedChip = NoteChip("Embed", icon: .symbol("return"))
        fieldUploadChip = NoteChip("Upload", icon: .symbol(kind == .file || kind == .pdf ? "arrow.up.doc" : "square.and.arrow.up"))
        hint = NoteMediaStyle.label("That doesn’t look like a link.", font: NoteMediaStyle.smallFont, color: NoteMediaStyle.warningInk)
        super.init(host: host)
        addCursorUpdateArea()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = NoteTheme.tertiaryInk
        icon.image = NoteMediaStyle.symbol(NoteMediaCopy.symbol(for: kind), size: 17, weight: .medium)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NoteMediaStyle.nunito(14)
        field.textColor = NoteTheme.ink
        field.placeholderAttributedString = NSAttributedString(string: "Paste a link to the \(NoteMediaCopy.noun(for: kind))…",
                                                               attributes: [.font: NoteMediaStyle.nunito(14), .foregroundColor: NoteTheme.placeholderInk])
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setAccessibilityLabel("Link to the \(NoteMediaCopy.noun(for: kind))")
        field.setAccessibilityHelp("Press Return to embed it, or Escape to go back.")
        uploadChip.onPress = { [weak self] in self?.host?.replace() }
        linkChip.onPress = { [weak self] in self?.setEnteringLink(true) }
        embedChip.onPress = { [weak self] in self?.submitLink() }
        fieldUploadChip.onPress = { [weak self] in self?.host?.replace() }
        unsplashChip.setToolTip("Find a free photo on Unsplash")
        unsplashChip.onPress = { [weak self] in
            guard let self else { return }
            self.host?.presentUnsplash(from: self)
        }
        for view in [icon, title, uploadChip, linkChip, unsplashChip, field, embedChip, fieldUploadChip, hint] as [NSView] { addSubview(view) }
        registerForDraggedTypes([.fileURL, .URL] + NoteClipboard.imageTypes.map(\.type))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(NoteMediaCopy.addPrompt(for: kind))
        applyMode()
    }

    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    package override func measureHeight(width: CGFloat) -> CGFloat { Self.height }
    package override var handleAnchorY: CGFloat { Self.height / 2 }

    package override func readOnlyDidChange() { applyMode() }

    private var editable: Bool { host?.canEdit == true }

    private func applyMode() {
        let kind = host?.kind ?? .image
        title.stringValue = editable ? NoteMediaCopy.addPrompt(for: kind) : NoteMediaCopy.emptyReadOnly(for: kind)
        let linking = enteringLink && editable
        title.isHidden = linking
        uploadChip.isHidden = linking || !editable
        linkChip.isHidden = linking || !editable
        unsplashChip.isHidden = linking || host?.offersUnsplash != true
        field.isHidden = !linking
        embedChip.isHidden = !linking
        fieldUploadChip.isHidden = !linking
        hint.isHidden = true
        setAccessibilityRole(editable && !linking ? .button : .group)
        refreshCursorIfPointerOwned()
        needsLayout = true
    }

    private func setEnteringLink(_ entering: Bool) {
        guard editable else { return }
        enteringLink = entering
        applyMode()
        layoutSubtreeIfNeeded()
        for view in entering ? [field, embedChip, fieldUploadChip] as [NSView] : [title, uploadChip, linkChip, unsplashChip] {
            guard let layer = view.layer ?? { view.wantsLayer = true; return view.layer }() else { continue }
            MainActor.assumeIsolated { NoteMediaMotion.fadeIn(layer, duration: 0.15) }
        }
        if entering {
            field.stringValue = ""
            window?.makeFirstResponder(field)
        } else if let window, window.firstResponder === field.currentEditor() {
            window.makeFirstResponder(nil)
        }
    }

    package func beginLinkEntry() -> Bool {
        guard editable, window != nil else { return false }
        if !enteringLink { setEnteringLink(true) } else { window?.makeFirstResponder(field) }
        return true
    }

    private func submitLink() {
        guard let url = NoteMediaSource.webURL(from: field.stringValue) else {
            hint.isHidden = false
            needsLayout = true
            shake()
            return
        }
        enteringLink = false
        host?.embed(url)
    }

    private func shake() {
        guard let layer = field.layer ?? { field.wantsLayer = true; return field.layer }(), !NoteAnimation.reduceMotion else { return }
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -6, 5, -3, 2, 0]
        shake.duration = 0.32
        shake.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(shake, forKey: "media.shake")
    }

    package func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)): submitLink(); return true
        case #selector(NSResponder.cancelOperation(_:)): setEnteringLink(false); return true
        default: return false
        }
    }

    package func controlTextDidChange(_ obj: Notification) {
        if !hint.isHidden { hint.isHidden = true; needsLayout = true }
    }

    package override func layout() {
        super.layout()
        let height = bounds.height
        icon.frame = NSRect(x: 16, y: (height - 20) / 2, width: 20, height: 20)
        var trailing = bounds.width - 12
        if enteringLink {
            let uploadSize = fieldUploadChip.intrinsicContentSize
            fieldUploadChip.isHidden = bounds.width < 360
            if !fieldUploadChip.isHidden {
                fieldUploadChip.frame = NSRect(x: trailing - uploadSize.width, y: (height - uploadSize.height) / 2,
                                               width: uploadSize.width, height: uploadSize.height)
                trailing = fieldUploadChip.frame.minX - 4
            }
            let embedWidth = embedChip.intrinsicContentSize.width
            embedChip.frame = NSRect(x: trailing - embedWidth, y: (height - NoteTheme.chipHeight) / 2, width: embedWidth, height: NoteTheme.chipHeight)
            trailing = embedChip.frame.minX - 8
            let fieldHeight: CGFloat = 20
            let hintWidth = hint.isHidden ? 0 : min(200, ceil(hint.intrinsicContentSize.width))
            field.frame = NSRect(x: 44, y: (height - fieldHeight) / 2, width: max(40, trailing - 44 - (hintWidth > 0 ? hintWidth + 8 : 0)), height: fieldHeight)
            hint.frame = NSRect(x: field.frame.maxX + 8, y: (height - 16) / 2, width: hintWidth, height: 16)
        } else {
            let chips = [uploadChip, linkChip] + (host?.offersUnsplash == true ? [unsplashChip] : [])
            let chipsWidth = chips.reduce(CGFloat(0)) { $0 + $1.intrinsicContentSize.width } + CGFloat(chips.count - 1) * 4
            let showsChips = editable && bounds.width - 12 - 44 >= chipsWidth
            let showsTitle = !showsChips || bounds.width - 12 - 44 - chipsWidth - 8 >= 96
            for chip in [uploadChip, linkChip, unsplashChip] { chip.isHidden = !showsChips || !chips.contains(chip) }
            if showsChips {
                for chip in chips.reversed() {
                    let width = chip.intrinsicContentSize.width
                    chip.frame = NSRect(x: trailing - width, y: (height - NoteTheme.chipHeight) / 2, width: width, height: NoteTheme.chipHeight)
                    trailing = chip.frame.minX - 4
                }
                trailing -= 4
            }
            title.isHidden = !showsTitle
            title.frame = NSRect(x: 44, y: (height - 20) / 2, width: max(0, trailing - 44), height: 20)
        }
    }

    package override func setHovered(_ hovered: Bool) { cardHovered = hovered && editable && !enteringLink }

    package override func cursorUpdate(with event: NSEvent) {
        if editable, !enteringLink, applyNoteCursor(.pointingHand, for: event) { return }
        super.cursorUpdate(with: event)
    }

    package override func mouseDown(with event: NSEvent) {
        guard editable, !enteringLink else { super.mouseDown(with: event); return }
        host?.replace()
    }

    package override func accessibilityPerformPress() -> Bool {
        guard editable else { return false }
        host?.replace()
        return true
    }

    private func acceptedFile(_ info: NSDraggingInfo) -> URL? {
        guard let kind = host?.kind,
              let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let url = urls.first, NoteMediaFileType.accepts(url, for: kind) else { return nil }
        return url
    }

    private func acceptedImageData(_ info: NSDraggingInfo) -> (Data, String)? {
        guard host?.kind == .image else { return nil }
        let board = info.draggingPasteboard
        for candidate in NoteClipboard.imageTypes {
            if let data = board.data(forType: candidate.type), !data.isEmpty { return (data, candidate.fileExtension) }
        }
        return nil
    }

    private func acceptedLink(_ info: NSDraggingInfo) -> URL? {
        let board = info.draggingPasteboard
        guard board.availableType(from: [.fileURL]) == nil else { return nil }
        if let link = board.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL,
           let scheme = link.scheme?.lowercased(), scheme == "http" || scheme == "https" { return link }
        return board.string(forType: .string).flatMap(NoteMediaSource.webURL(from:))
    }

    private func acceptsImageData(_ info: NSDraggingInfo) -> Bool {
        host?.kind == .image && info.draggingPasteboard.availableType(from: NoteClipboard.imageTypes.map(\.type)) != nil
    }

    package override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard editable, acceptedFile(sender) != nil || acceptsImageData(sender) || acceptedLink(sender) != nil else { return [] }
        cardHighlighted = true
        title.stringValue = "Drop it right here"
        return .copy
    }

    package override func draggingExited(_ sender: NSDraggingInfo?) {
        cardHighlighted = false
        applyMode()
    }

    package override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { editable }

    package override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        cardHighlighted = false
        if let url = acceptedFile(sender) { host?.importFile(url); return true }
        if let (data, ext) = acceptedImageData(sender) { host?.importData(data, fileExtension: ext, suggestedName: nil); return true }
        if let link = acceptedLink(sender) { host?.embed(link); return true }
        applyMode()
        return false
    }
}

@MainActor
final class NoteMediaProblemCard: NoteMediaCardView {
    private let problem: NoteMediaProblem
    private let icon = NSImageView()
    private let title: NSTextField
    private let detail: NSTextField
    private let replaceChip = NoteChip("Replace", icon: .symbol("arrow.triangle.2.circlepath"))
    private let retryChip = NoteChip("Try again", icon: .symbol("arrow.clockwise"))
    private let openChip = NoteChip("Open", icon: .symbol("arrow.up.right.square"))
    private let embedChip = NoteChip("Play here", icon: .symbol("play.rectangle"))
    private let deleteChip = NoteToolbarButton(icon: .symbol("trash"), label: "Delete")
    private static let height: CGFloat = 64

    init(host: NoteMediaHost, problem: NoteMediaProblem) {
        self.problem = problem
        title = NoteMediaStyle.label(NoteMediaCopy.problemTitle(problem, kind: host.kind), font: NoteMediaStyle.titleFont, color: NoteTheme.ink)
        detail = NoteMediaStyle.label("", font: NoteMediaStyle.detailFont, color: NoteTheme.tertiaryInk)
        detail.lineBreakMode = .byTruncatingMiddle
        super.init(host: host)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = NoteMediaStyle.warningInk
        icon.image = NoteMediaStyle.symbol(problem == .unsupported ? "play.slash" : "exclamationmark.triangle", size: 17, weight: .semibold)
        replaceChip.onPress = { [weak self] in self?.host?.replace() }
        retryChip.onPress = { [weak self] in self?.host?.retry() }
        openChip.onPress = { [weak self] in
            guard let self, let url = self.host?.source.url else { return }
            self.host?.open(url)
        }
        deleteChip.onPress = { [weak self] in self?.host?.deleteBlock() }
        embedChip.onPress = { [weak self] in
            guard let self, let url = self.host?.embeddablePage else { return }
            self.host?.embedAsPage(url)
        }
        for view in [icon, title, detail, embedChip, replaceChip, retryChip, openChip, deleteChip] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func writtenPath(_ written: String?, source: NoteMediaSource) -> String {
        guard let written = written?.trimmingCharacters(in: .whitespacesAndNewlines), !written.isEmpty else { return "" }
        if case .remote = source { return written }
        if case .local = source, written.lowercased().hasPrefix("file:") { return source.displayPath(original: written) }
        return written.removingPercentEncoding ?? written
    }

    override func measureHeight(width: CGFloat) -> CGFloat { Self.height }
    override var handleAnchorY: CGFloat { 22 }

    override func update(block: NoteBlock, source: NoteMediaSource) {
        detail.stringValue = Self.writtenPath(block.props.source, source: source)
        setAccessibilityLabel(title.stringValue + ". " + detail.stringValue)
        needsLayout = true
    }

    override func readOnlyDidChange() { needsLayout = true }

    override func layout() {
        super.layout()
        let editable = host?.canEdit == true
        let remote: Bool = { if case .remote = host?.source { return true }; return false }()
        replaceChip.isHidden = !editable
        deleteChip.isHidden = !editable
        retryChip.isHidden = !(remote && (problem == .unreachable || problem == .unreadable))
        let opensElsewhere = remote || (host?.kind == .pdf && host?.source.url != nil)
        openChip.isHidden = !(opensElsewhere && (problem == .unsupported || problem == .unreadable))
        embedChip.isHidden = !(editable && problem == .unsupported && host?.embeddablePage != nil)
        var trailing = bounds.width - 12
        for chip in [deleteChip, replaceChip, retryChip, openChip, embedChip] where !chip.isHidden {
            let width = chip.intrinsicContentSize.width
            chip.frame = NSRect(x: trailing - width, y: (bounds.height - NoteTheme.chipHeight) / 2, width: width, height: NoteTheme.chipHeight)
            trailing = chip.frame.minX - 4
        }
        icon.frame = NSRect(x: 16, y: (bounds.height - 20) / 2, width: 20, height: 20)
        let textWidth = max(0, trailing - 8 - 46)
        title.frame = NSRect(x: 46, y: 13, width: textWidth, height: 20)
        detail.frame = NSRect(x: 46, y: 33, width: textWidth, height: 18)
    }
}

@MainActor
final class NoteMediaPendingCard: NoteMediaCardView {
    private let shimmer = NoteMediaShimmer()
    private let title: NSTextField
    private static let height: CGFloat = 52

    override init(host: NoteMediaHost) {
        title = NoteMediaStyle.label("Bringing your \(host.nounPhrase) in…", font: NoteMediaStyle.titleFont, color: NoteTheme.secondaryInk)
        super.init(host: host)
        shimmer.cornerRadius = NoteMediaStyle.cardRadius
        shimmer.setAccessibilityElement(false)
        addSubview(shimmer)
        addSubview(title)
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel(title.stringValue)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func measureHeight(width: CGFloat) -> CGFloat { Self.height }
    override var handleAnchorY: CGFloat { Self.height / 2 }

    override func layout() {
        super.layout()
        shimmer.frame = bounds
        title.frame = NSRect(x: 16, y: (bounds.height - 20) / 2, width: max(0, bounds.width - 32), height: 20)
    }
}

@MainActor
final class NoteFileContentView: NoteMediaContentView {
    private let fill = CALayer()
    private let icon = NSImageView()
    private let name: NSTextField
    private let size: NSTextField
    private let finderChip = NoteChip("Show in Finder", icon: .symbol("folder"))
    private let openChip = NoteChip("Open", icon: .symbol("arrow.up.right.square"))
    private let selectionRing = CALayer()
    private var hovered = false
    private var pressed = false
    private static let height: CGFloat = 40

    override init(host: NoteMediaHost) {
        name = NoteMediaStyle.label("", font: NoteMediaStyle.nunito(15, weight: .bold), color: NoteTheme.ink)
        name.lineBreakMode = .byTruncatingMiddle
        size = NoteMediaStyle.label("", font: NoteMediaStyle.detailFont, color: NoteTheme.tertiaryInk)
        super.init(host: host)
        addCursorUpdateArea()
        fill.cornerRadius = NoteTheme.controlRadius
        fill.cornerCurve = .continuous
        fill.opacity = 0
        selectionRing.cornerRadius = NoteTheme.controlRadius
        selectionRing.cornerCurve = .continuous
        selectionRing.borderWidth = 1.5
        selectionRing.isHidden = true
        layer?.addSublayer(fill)
        layer?.addSublayer(selectionRing)
        icon.imageScaling = .scaleProportionallyUpOrDown
        finderChip.onPress = { [weak self] in self?.host?.showInFinder() }
        openChip.onPress = { [weak self] in
            guard let self, let url = self.host?.source.url else { return }
            self.host?.open(url)
        }
        finderChip.isHidden = true
        openChip.isHidden = true
        for view in [icon, name, size, finderChip, openChip] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func measureHeight(width: CGFloat) -> CGFloat { Self.height }
    override var handleAnchorY: CGFloat { Self.height / 2 }

    override func update(block: NoteBlock, source: NoteMediaSource) {
        name.stringValue = host?.mediaFileName ?? source.fileName
        switch source {
        case .local(let url):
            icon.image = NSWorkspace.shared.icon(forFile: url.path)
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]))
                .flatMap { $0.fileSize.map(Int64.init) ?? $0.totalFileAllocatedSize.map(Int64.init) }
            size.stringValue = bytes.map(NoteMediaFormat.fileSize) ?? ""
        case .remote(let url):
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            icon.image = NSWorkspace.shared.icon(for: type)
            size.stringValue = NoteMediaFormat.displayHost(url)
        case .empty, .unresolved:
            icon.image = NSWorkspace.shared.icon(for: .data)
            size.stringValue = ""
        }
        let detail = size.stringValue.isEmpty ? "" : ", " + size.stringValue
        setAccessibilityLabel("File: " + name.stringValue + detail)
        setAccessibilityHelp(isLocal ? "Opens Quick Look." : "Opens the link.")
        needsLayout = true
    }

    private var isLocal: Bool { if case .local = host?.source { return true }; return false }

    override func layout() {
        super.layout()
        NoteMediaMotion.instant {
            fill.frame = bounds
            selectionRing.frame = bounds
            fill.backgroundColor = NoteMediaStyle.cg(pressed ? NoteTheme.pressedFill : NoteTheme.hoverFill, in: self)
            selectionRing.borderColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
        }
        let height = bounds.height
        icon.frame = NSRect(x: 6, y: (height - 26) / 2, width: 26, height: 26)
        var trailing = bounds.width - 8
        for chip in [finderChip, openChip] where !chip.isHidden {
            let width = chip.intrinsicContentSize.width
            chip.frame = NSRect(x: trailing - width, y: (height - NoteTheme.chipHeight) / 2, width: width, height: NoteTheme.chipHeight)
            trailing = chip.frame.minX - 6
        }
        let available = max(0, trailing - 40)
        let sizeWidth = min(available * 0.4, NoteMediaStyle.textWidth(size))
        let nameWidth = min(available - (sizeWidth > 0 ? sizeWidth + 6 : 0), NoteMediaStyle.textWidth(name))
        name.frame = NSRect(x: 40, y: (height - 21) / 2, width: max(0, nameWidth), height: 21)
        size.frame = NSRect(x: name.frame.maxX + 6, y: (height - 17) / 2 + 1, width: sizeWidth, height: 17)
    }

    override func setHovered(_ hovered: Bool) {
        self.hovered = hovered
        finderChip.isHidden = !(hovered && isLocal && host?.offersShowInFinder == true)
        openChip.isHidden = !(hovered && !isLocal && host?.source.url != nil)
        let target: Float = hovered ? 1 : 0
        let from = fill.presentation()?.opacity ?? fill.opacity
        NoteMediaMotion.instant { fill.opacity = target }
        if !NoteAnimation.reduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = from
            fade.toValue = target
            fade.duration = 0.1
            fill.add(fade, forKey: "media.file.hover")
        }
        needsLayout = true
    }

    override func setSelected(_ selected: Bool) {
        NoteMediaMotion.instant { selectionRing.isHidden = !selected }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func cursorUpdate(with event: NSEvent) {
        if applyNoteCursor(.pointingHand, for: event) { return }
        super.cursorUpdate(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        needsLayout = true
        if let layer { NoteMediaMotion.press(layer, pressed: true, in: self, scale: 0.992) }
    }

    override func mouseUp(with event: NSEvent) {
        pressed = false
        needsLayout = true
        if let layer { NoteMediaMotion.press(layer, pressed: false, in: self, scale: 0.992) }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        activate()
    }

    override func accessibilityPerformPress() -> Bool {
        activate()
        return true
    }

    private func activate() {
        guard let host else { return }
        switch host.source {
        case .local: host.quickLook(from: icon.frame, in: self)
        case .remote(let url): host.open(url)
        case .empty, .unresolved: break
        }
    }
}

extension NoteMediaBlockView: NoteMediaHost {}
