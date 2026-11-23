import AppKit
import ParcCore
import ParcEngine
import UniformTypeIdentifiers
import ParcKit
import ParcNotes
import ParcEasels
import ParcLibrary

enum CaptureSendRefusal: LocalizedError, Equatable {
    case windowNotActive, sheetOpen, captureExpired, windowBusy

    var errorDescription: String? {
        switch self {
        case .windowNotActive: return "Parc’s window wasn’t active, so nothing was sent. Click the page once, then try again."
        case .sheetOpen: return "Close the open dialog first, then send the capture."
        case .captureExpired: return "This capture’s page changed, so it can’t be sent anymore. Retake it to send it."
        case .windowBusy: return "Parc is still rearranging this window, so nothing was sent. Try again in a moment."
        }
    }

    @MainActor static func check(_ window: NSWindow) -> Self? {
        if window.attachedSheet != nil { return .sheetOpen }
        if !window.isKeyWindow, window.isVisible, !window.isMiniaturized { window.makeKey() }
        return window.isKeyWindow ? nil : .windowNotActive
    }
}

struct CaptureFramingEnvironment {
    var defaults: UserDefaults = .standard
    var palette: [NSColor]?
    var desktop: (@MainActor (NSScreen?) async throws -> NSImage)?
}

@MainActor
final class PageCaptureController: NSObject {
    enum Mode { case region, viewport, fullPage, portrait }
    private enum State { case selecting, capturing, configuringPortrait, preview, editing, output, finished }
    var onCopied: (() -> Void)?
    private weak var parent: NSWindow?
    private weak var sourceView: NSView?
    private weak var containerView: NSView?
    private weak var host: NSView?
    private let destination: CaptureLibraryDestination?
    private var library: CaptureLibraryStore? { destination?.library }
    private var captureID = UUID()
    private var capturedAt = Date()
    private var libraryNeedsUpdate = false
    private var captureKind = SavedCapture.Kind.region
    private var savedCapture: SavedCapture?
    private var libraryWriteInProgress = false
    private let lease: PCNativePageCapture
    private var sourceURL: String { lease.sourceURL }
    private let valid: () -> Bool
    private let finished: (Bool) -> Void
    private let easelDestinations: @MainActor () async throws -> [CaptureEaselDestination]
    private(set) var destinationsLoad: Task<Void, Never>?
    private(set) var libraryWrite: Task<Void, Never>?
    private var destinationsLoaded = false
    private let addToEasel: (EaselImageInput, UUID?) throws -> Void
    private let noteDestinations: (() throws -> [CaptureNoteDestination])?
    private let addToNote: ((EaselImageInput, CaptureNoteTarget) throws -> Void)?
    private var messageSharing: CaptureMessageSharing?
    let overlay: PageCaptureOverlay
    private let framing: CaptureFramingEnvironment
    private lazy var edgeGuard = PageCaptureEdgeGuard(overlay: overlay)
    private var state = State.selecting
    private var image: CapturedImage?
    private var captureLayout: EaselCaptureLayout?
    private var pngData: Data? { image?.pngData }
    private var imageEditor: CaptureImageEditor?
    private var acceptedEdits: CaptureImageEditSnapshot?
    private var portrait: PortraitCaptureView?
    private var capturedPageColor: NSColor?
    private var acquisitionMode = Mode.region
    private var capturePreviewRect: NSRect?
    private var request: UInt64 = 0
    private var hoverRequest: UInt64 = 0
    private var previousMouseMovedEvents: Bool?
    private var sourceFrame: NSRect = .zero
    private var nativeFrame: NSRect = .zero
    private var containerFrame: NSRect = .zero
    private var parentFrame: NSRect = .zero
    private var hostBounds: NSRect = .zero
    private var savePanel: NSSavePanel?
    private var observers: [NSObjectProtocol] = []
    private var previewFocusPending = false
    private let easelDirectory: URL?

    init(lease: PCNativePageCapture, sourceView: NSView, containerView: NSView, host: NSView, parent: NSWindow,
         valid: @escaping () -> Bool, destination: CaptureLibraryDestination?,
         easelDestinations: @escaping @MainActor () async throws -> [CaptureEaselDestination],
         addToEasel: @escaping (EaselImageInput, UUID?) throws -> Void,
         noteDestinations: (() throws -> [CaptureNoteDestination])? = nil,
         addToNote: ((EaselImageInput, CaptureNoteTarget) throws -> Void)? = nil,
         presentation: PageCaptureOverlay? = nil, framing: CaptureFramingEnvironment = CaptureFramingEnvironment(),
         easelDirectory: URL? = nil, finished: @escaping (Bool) -> Void) {
        self.destination = destination
        self.easelDirectory = easelDirectory?.standardizedFileURL
        self.overlay = presentation ?? PageCaptureOverlay(); self.framing = framing
        self.lease = lease; self.sourceView = sourceView; self.containerView = containerView
        self.host = host; self.parent = parent
        self.valid = valid; self.easelDestinations = easelDestinations
        self.addToEasel = addToEasel; self.finished = finished
        self.noteDestinations = addToNote == nil ? nil : noteDestinations
        self.addToNote = noteDestinations == nil ? nil : addToNote
        super.init()
        overlay.setDestinationAvailability(library: destination != nil, easels: destination?.allowsEasels == true,
                                           notes: self.addToNote != nil)
        lease.invalidated = { [weak self] in
            MainActor.assumeIsolated { self?.dismiss(restoreFocus: false) }
        }
        overlay.onCancel = { [weak self] in self?.cancelEditingOrDismiss() }
        overlay.onRegion = { [weak self] rect in self?.selected(rect) }
        overlay.onHover = { [weak self] point in self?.targetElement(at: point) }
        overlay.onElement = { [weak self] target, point in self?.selectedElement(target, at: point) }
        overlay.onViewport = { [weak self] in self?.capture(.viewport) }
        overlay.onFullPage = { [weak self] in self?.capture(.fullPage) }
        overlay.onAction = { [weak self] action in self?.perform(action) }
    }

    func present(_ mode: Mode) {
        guard valid(), lease.isValid, let parent, let sourceView, let containerView, let host,
              parent.isKeyWindow, parent.attachedSheet == nil,
              sourceView.window === parent else { dismiss(restoreFocus: false); return }
        sourceFrame = host.convert(lease.viewportFrame, from: sourceView)
        nativeFrame = host.convert(sourceView.bounds, from: sourceView)
        containerFrame = host.convert(containerView.bounds, from: containerView)
        parentFrame = parent.frame; hostBounds = host.bounds
        guard sourceFrame.width > 1, sourceFrame.height > 1 else { dismiss(restoreFocus: false); return }
        overlay.frame = sourceFrame
        if let theme = host as? ThemeRendererView { overlay.adoptWindowTheme(theme) }
        overlay.pageSize = lease.viewportSize
        previousMouseMovedEvents = parent.acceptsMouseMovedEvents
        parent.acceptsMouseMovedEvents = true
        host.addSubview(overlay, positioned: .above, relativeTo: nil)
        edgeGuard.install(in: host, below: overlay)
        parent.makeFirstResponder(overlay)
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss(restoreFocus: false) }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state != .output else { return }
                self.dismiss(restoreFocus: false)
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.previewFocusPending else { return }
                self.focusPreview()
            }
        })
        for name in [Notification.Name.easelDocumentChanged, .easelDocumentRemoved] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let directory = (note.userInfo?[EaselStore.directoryKey] as? URL)?.standardizedFileURL
                MainActor.assumeIsolated {
                    guard let self, let directory, directory == self.easelDirectory,
                          self.destinationsLoaded, self.state != .finished else { return }
                    self.refreshDestinations(reload: true)
                }
            })
        }
        InterfaceSoundEffects.shared.preload()
        acquisitionMode = mode
        if mode == .region { overlay.showSelection() } else { capture(mode) }
    }

    func handleCaptureGesture(_ recognizer: NSPanGestureRecognizer) {
        reconcile()
        guard state == .selecting, parent?.isKeyWindow == true else { return }
        if recognizer.state == .cancelled || recognizer.state == .failed {
            dismiss(restoreFocus: true); return
        }
        overlay.handleCaptureGesture(state: recognizer.state, point: recognizer.location(in: overlay))
    }

    func reconcile() {
        guard state != .finished else { return }
        guard valid(), lease.isValid, let sourceView, let containerView, let host, let parent,
              sourceView.window === parent, containerView.window === parent,
              parent.frame == parentFrame, host.bounds == hostBounds,
              host.convert(containerView.bounds, from: containerView) == containerFrame,
              host.convert(sourceView.bounds, from: sourceView) == nativeFrame,
              host.convert(lease.viewportFrame, from: sourceView) == sourceFrame else {
            dismiss(restoreFocus: false); return
        }
    }

    func dismiss(restoreFocus: Bool) {
        guard state != .finished else { return }
        state = .finished; previewFocusPending = false; request &+= 1; hoverRequest &+= 1
        destinationsLoad?.cancel(); destinationsLoad = nil
        overlay.retirePresentation()
        if let previousMouseMovedEvents { parent?.acceptsMouseMovedEvents = previousMouseMovedEvents }
        previousMouseMovedEvents = nil
        lease.invalidated = nil
        lease.invalidate()
        if let savePanel, let parent, parent.attachedSheet === savePanel { parent.endSheet(savePanel, returnCode: .cancel) }
        savePanel = nil
        messageSharing?.detach(); messageSharing = nil
        imageEditor?.close(); imageEditor = nil; acceptedEdits = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        portrait?.removeFromSuperview(); portrait = nil
        edgeGuard.removeFromSuperview(); overlay.removeFromSuperview(); image = nil; capturedPageColor = nil
        finished(restoreFocus)
    }

    private func targetElement(at point: NSPoint?) {
        hoverRequest &+= 1
        let generation = hoverRequest
        guard state == .selecting, let point else { overlay.setTarget(nil, rect: nil); return }
        reconcile()
        guard state == .selecting, valid(), lease.isValid,
              overlay.bounds.width > 0, overlay.bounds.height > 0 else { return }
        overlay.targetPending()
        let nativePoint = NSPoint(x: point.x / overlay.bounds.width * lease.viewportSize.width,
                                  y: point.y / overlay.bounds.height * lease.viewportSize.height)
        lease.targetElement(at: nativePoint) { [weak self] target in
            MainActor.assumeIsolated {
                guard let self, self.state == .selecting, self.hoverRequest == generation else { return }
                self.reconcile()
                guard self.state == .selecting, self.valid(), self.lease.isValid else { return }
                let rect = target.map { target in
                    NSRect(x: target.viewportRect.minX / self.lease.viewportSize.width * self.overlay.bounds.width,
                           y: target.viewportRect.minY / self.lease.viewportSize.height * self.overlay.bounds.height,
                           width: target.viewportRect.width / self.lease.viewportSize.width * self.overlay.bounds.width,
                           height: target.viewportRect.height / self.lease.viewportSize.height * self.overlay.bounds.height)
                }
                let size = target.flatMap { target -> CGSize? in
                    let r = target.viewportRect
                    return EaselCaptureGeometry.elementCaptureArea(elementRect: EaselRect(x: r.minX, y: r.minY, width: r.width, height: r.height),
                        viewport: EaselPoint(x: self.lease.viewportSize.width, y: self.lease.viewportSize.height))
                        .map { CaptureSizeReadout.pointSize(CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)) }
                }
                self.overlay.setTarget(target, rect: rect, size: size)
            }
        }
    }

    private func selectedElement(_ target: PCNativePageCaptureTarget?, at point: NSPoint) {
        guard state == .selecting, valid(), lease.isValid else { return }
        if let target { capture(.region, element: target); return }
        hoverRequest &+= 1; request &+= 1
        let generation = request
        state = .capturing; overlay.showBusy()
        let nativePoint = NSPoint(x: point.x / overlay.bounds.width * lease.viewportSize.width,
                                  y: point.y / overlay.bounds.height * lease.viewportSize.height)
        lease.targetElement(at: nativePoint) { [weak self] target in
            MainActor.assumeIsolated {
                guard let self, self.state == .capturing, self.request == generation else { return }
                self.reconcile()
                guard self.state == .capturing, self.valid(), self.lease.isValid else { return }
                self.state = .selecting
                if let target { self.capture(.region, element: target) }
                else { self.overlay.showSelection(message: CaptureModeHint.noElement) }
            }
        }
    }

    private func capture(_ mode: Mode, rect: NSRect = .zero,
                         element: PCNativePageCaptureTarget? = nil) {
        guard state != .finished, valid(), lease.isValid else { dismiss(restoreFocus: false); return }
        acquisitionMode = mode
        let viewport = NSRect(origin: .zero, size: lease.viewportSize)
        let nativeRect = element.flatMap { target -> NSRect? in
            let r = target.viewportRect
            return EaselCaptureGeometry.elementCaptureArea(elementRect: EaselRect(x: r.minX, y: r.minY, width: r.width, height: r.height),
                viewport: EaselPoint(x: viewport.width, y: viewport.height)).map { NSRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        } ?? (mode == .region ? rect : viewport)
        capturePreviewRect = NSRect(x: nativeRect.minX / viewport.width * overlay.bounds.width,
            y: nativeRect.minY / viewport.height * overlay.bounds.height,
            width: nativeRect.width / viewport.width * overlay.bounds.width,
            height: nativeRect.height / viewport.height * overlay.bounds.height)
        captureKind = mode == .region ? .region : mode == .fullPage ? .fullPage : .viewport
        state = .capturing; request &+= 1; hoverRequest &+= 1
        let generation = request
        overlay.showBusy()
        let completion: (PCNativePageCaptureResult) -> Void = { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, self.state == .capturing, self.request == generation else { return }
                self.reconcile()
                guard self.state == .capturing, self.valid(), self.lease.isValid else { self.dismiss(restoreFocus: false); return }
                do {
                    guard let data = result.pngData else { throw PortraitCaptureError.encoding }
                    self.image = try CapturedImage(pngData: data, backingScale: self.parent?.backingScaleFactor ?? 1)
                    self.captureLayout = result.layout.flatMap {
                        EaselCaptureGeometry.captured(viewport: EaselPoint(x: $0.viewportSize.width, y: $0.viewportSize.height),
                            scroll: EaselPoint(x: $0.scrollOffset.x, y: $0.scrollOffset.y),
                            region: EaselRect(x: $0.region.minX, y: $0.region.minY, width: $0.region.width, height: $0.region.height),
                            scrollContainers: $0.scrollContainers.map(EaselScrollContainer.init))
                    }
                    self.capturedAt = Date(); self.capturedPageColor = self.lease.pageThemeColor
                    InterfaceSoundEffects.shared.playCapture()
                    self.showPreview(changed: true)
                    self.overlay.revealCapturedImage()
                    if mode == .portrait { self.configurePortrait() }
                } catch {
                    self.state = .selecting
                    self.overlay.showSelection(message: result.errorMessage ?? error.localizedDescription)
                    self.parent?.makeFirstResponder(self.overlay)
                }
            }
        }
        if let element { lease.captureElement(element, completion: completion); return }
        switch mode {
        case .region: lease.captureRegion(rect, completion: completion)
        case .viewport, .portrait: lease.captureViewport(completion: completion)
        case .fullPage: coverThenCaptureFullPage(generation: generation, completion: completion)
        }
    }

    private func coverThenCaptureFullPage(generation: UInt64, completion: @escaping (PCNativePageCaptureResult) -> Void) {
        lease.captureViewport { [weak self] cover in
            MainActor.assumeIsolated {
                guard let self, self.state == .capturing, self.request == generation else { return }
                self.reconcile()
                guard self.state == .capturing, self.valid(), self.lease.isValid else { self.dismiss(restoreFocus: false); return }
                if let still = cover.pngData.flatMap({ NSBitmapImageRep(data: $0)?.cgImage }) { self.overlay.showStillCover(still) }
                self.lease.captureFullPage(completion: completion)
            }
        }
    }

    private func configurePortrait() {
        guard state == .preview, let image, valid(), lease.isValid, let parent else { return }
        let view = PortraitCaptureView(source: image.unframedPixels, pageColor: capturedPageColor,
                                       backingScale: image.backingScale, composition: image.frame,
                                       previewPixels: overlay.convertToBacking(overlay.bounds).size,
                                       defaults: framing.defaults, colors: framing.palette)
        view.onCapture = { [weak self, weak view] in
            guard let self, self.state == .configuringPortrait, let view, self.portrait === view else { return }
            self.reconcile()
            guard self.state == .configuringPortrait, let image = self.image else { return }
            do { try image.applyFrame(view.composition); self.showPreview(changed: true) }
            catch { view.showError(error.localizedDescription); self.parent?.makeFirstResponder(view) }
        }
        view.onCancel = { [weak self] in self?.cancelEditingOrDismiss() }
        view.onPreview = { [weak self, weak view] image in
            guard let self, let view, self.state == .configuringPortrait, self.portrait === view else { return }
            self.overlay.showDraft(image)
        }
        view.onResize = { [weak self] in self?.overlay.palette.view.frameContentSizeChanged() }
        portrait = view; state = .configuringPortrait
        overlay.onPicturePixels = { [weak self, weak view] pixels in
            guard let self, let view, self.state == .configuringPortrait, self.portrait === view else { return }
            view.previewPixels = pixels
        }
        overlay.showFramePage(view, preview: view.previewImage)
        if let desktop = framing.desktop { view.loadDesktop(screen: parent.screen, provider: desktop) }
        else { view.loadDesktop(screen: parent.screen) }
        parent.makeFirstResponder(view)
    }

    private func cancelEditingOrDismiss() {
        if state == .editing || state == .configuringPortrait {
            reconcile()
            if state != .finished { showPreview(changed: false) }
        } else { dismiss(restoreFocus: true) }
    }

    private func selected(_ rect: NSRect) {
        reconcile()
        guard state != .finished, rect.width >= 1, rect.height >= 1 else { return }
        if state == .editing, let image {
            let originalPixels = image.sourcePixels
            let imageRect = overlay.imageRect
            guard imageRect.width > 0, imageRect.height > 0 else { return }
            guard let crop = CapturePresentation.pixelCrop(rect, imageRect: imageRect,
                pixels: NSSize(width: originalPixels.width, height: originalPixels.height)) else { return }
            do { try image.crop(to: crop); showPreview(changed: true) }
            catch { showPreview(changed: false); overlay.showError(error.localizedDescription) }
        } else if state == .selecting {
            let size = lease.viewportSize
            let converted = NSRect(x: rect.minX / overlay.bounds.width * size.width,
                                   y: rect.minY / overlay.bounds.height * size.height,
                                   width: rect.width / overlay.bounds.width * size.width,
                                   height: rect.height / overlay.bounds.height * size.height)
            capture(.region, rect: converted)
        }
    }

    private func showPreview(changed: Bool) {
        guard let image else { return }
        portrait = nil
        state = .preview
        captureKind = image.frame != nil ? .portrait : acquisitionMode == .region ? .region : acquisitionMode == .fullPage ? .fullPage : .viewport
        overlay.setFramed(image.frame != nil)
        overlay.showPreview(image.pixels, sourceRect: capturePreviewRect)
        overlay.setMessageAvailable(CaptureMessageSharing.isAvailable(for:
            CaptureMessagePayload(png: image.pngData, sourceAddress: sourceURL)))
        refreshDestinations()
        if changed {
            libraryNeedsUpdate = savedCapture != nil
            overlay.setLibrarySaved(false)
            if savedCapture != nil { persistCapture() }
        } else { overlay.setLibrarySaved(savedCapture != nil && !libraryNeedsUpdate) }
        focusPreview()
    }

    private func focusPreview() {
        previewFocusPending = state == .preview
        guard previewFocusPending, valid(), lease.isValid, let parent,
              parent.isKeyWindow, parent.attachedSheet == nil, overlay.window === parent else { return }
        previewFocusPending = false
        overlay.focusPreferredControl()
    }

    private func perform(_ action: PageCaptureOverlay.Action) {
        guard state == .preview else { return }
        overlay.clearError()
        guard valid(), lease.isValid else { overlay.showError(CaptureSendRefusal.captureExpired.localizedDescription); return }
        guard !(libraryWriteInProgress && action.waitsForLibrary) else { return }
        if let savedCapture, library?.contains(savedCapture) != true {
            self.savedCapture = nil; overlay.setLibrarySaved(false)
        }
        switch action {
        case .library:
            if let savedCapture, !libraryNeedsUpdate { removeFromLibrary(savedCapture) } else { persistCapture() }
        case .copy:
            guard let data = pngData else { return }
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setData(data, forType: .png) { dismiss(restoreFocus: true); onCopied?() }
            else { overlay.showError("The image could not be copied. Try again.") }
        case .save: save()
        case .edit: editImage()
        case .crop:
            guard let image else { return }
            state = .editing; overlay.showEditing(image.sourcePixels); parent?.makeFirstResponder(overlay)
        case .frame: configurePortrait()
        case .removeFrame:
            image?.removeFrame(); showPreview(changed: true)
        case .retake:
            captureID = UUID(); savedCapture = nil; libraryNeedsUpdate = false; overlay.setLibrarySaved(false)
            image = nil; capturedPageColor = nil; acceptedEdits = nil
            if acquisitionMode == .region { state = .selecting; overlay.showSelection(); parent?.makeFirstResponder(overlay) }
            else { capture(acquisitionMode) }
        case .message: shareMessage()
        case .newEasel: placeOnEasel(nil)
        case .newNote: placeInNote(.newNote)
        case .document(let document):
            switch document.target {
            case .easel(let id): placeOnEasel(id)
            case .note(let url): placeInNote(.note(url))
            }
        case .easels, .notes: break
        }
    }

    private func editImage() {
        guard let image, let parent, parent.isKeyWindow, parent.attachedSheet == nil, imageEditor == nil else { return }
        let id = captureID
        var changed = false
        do {
            let editor = try CaptureImageEditor(png: image.originalPNG, pixels: image.originalPixels,
                backingScale: image.backingScale, snapshot: acceptedEdits, parent: parent,
                valid: { [weak self, weak image] in
                    guard let self, let image else { return false }
                    self.reconcile()
                    return self.state == .output && self.captureID == id && self.image === image && self.valid() && self.lease.isValid
                }, apply: { [weak self, weak image] pixels, snapshot in
                    guard let self, let image, self.state == .output, self.captureID == id,
                          self.image === image, self.valid(), self.lease.isValid else { throw CocoaError(.userCancelled) }
                    try image.applyEditedOriginal(pixels)
                    self.acceptedEdits = snapshot; changed = true
                }, completion: { [weak self] in
                    guard let self, self.state == .output, self.captureID == id else { return }
                    self.imageEditor = nil; self.reconcile()
                    if self.state != .finished { self.showPreview(changed: changed) }
                })
            imageEditor = editor; state = .output
            if !editor.show() { editor.close() }
        } catch { overlay.showError(error.localizedDescription) }
    }

    private func refreshDestinations(reload: Bool = false) {
        guard reload || !destinationsLoaded else { return }
        destinationsLoaded = true
        destinationsLoad?.cancel()
        let load = easelDestinations, notes = noteDestinations, offersEasels = destination?.allowsEasels == true
        destinationsLoad = Task { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled, self.state != .finished else { return }
            if let notes {
                do { self.overlay.setNoteDestinations(try notes()) }
                catch { self.overlay.setNoteDestinations([]); self.overlay.showError(error.localizedDescription, alert: false) }
            }
            guard offersEasels else { self.overlay.setEaselDestinations([]); self.destinationsLoad = nil; return }
            do {
                let items = try await load()
                guard !Task.isCancelled, self.state != .finished else { return }
                self.overlay.setEaselDestinations(items)
                self.destinationsLoad = nil
            } catch {
                guard !Task.isCancelled, self.state != .finished, !(error is CancellationError),
                      (error as? CocoaError)?.code != .userCancelled else { return }
                self.destinationsLoad = nil
                self.overlay.setEaselDestinations([])
                self.overlay.showError(error.localizedDescription, alert: false)
            }
        }
    }

    private func documentInput(_ pngData: Data) -> EaselImageInput {
        var input = EaselImageInput(pngData: pngData, sourceURL: URL(string: sourceURL),
                                   pageTitle: lease.pageTitle, valid: { [weak self] in
            guard let self else { return false }
            return self.state != .finished && self.valid() && self.lease.isValid
        })
        input.capturedPage = true
        input.capturedAt = capturedAt
        input.captureLayout = image?.isOriginalOutput == true ? captureLayout : nil
        return input
    }

    private func placeOnEasel(_ id: UUID?) {
        guard destination?.allowsEasels == true, let pngData, outputWindowReady() else { return }
        state = .output
        deliver { try self.addToEasel(self.documentInput(pngData), id) }
    }

    private func placeInNote(_ target: CaptureNoteTarget) {
        guard let addToNote, let pngData, outputWindowReady() else { return }
        state = .output
        deliver { try addToNote(self.documentInput(pngData), target) }
    }

    private func outputWindowReady() -> Bool {
        guard let parent else { return false }
        if let refusal = CaptureSendRefusal.check(parent) {
            overlay.showError(refusal.localizedDescription)
            return false
        }
        return true
    }

    private func deliver(_ placement: () throws -> Void) {
        do {
            try placement()
            if state != .finished { dismiss(restoreFocus: false) }
        } catch {
            guard state != .finished else { return }
            state = .preview; reconcile()
            guard state == .preview else { return }
            refreshDestinations(reload: true)
            overlay.showError((error as? CocoaError)?.code == .userCancelled
                ? CaptureSendRefusal.captureExpired.localizedDescription
                : error.localizedDescription)
            focusPreview()
        }
    }

    private func shareMessage() {
        guard let pngData, let parent, parent.isKeyWindow, parent.attachedSheet == nil,
              messageSharing == nil else { return }
        guard let payload = CaptureMessagePayload(png: pngData, sourceAddress: sourceURL),
              let sharing = CaptureMessageSharing(payload: payload, parent: parent,
            sourceView: overlay, sourceRect: overlay.imageRect, completion: { [weak self] outcome in
                guard let self, self.state == .output, self.messageSharing != nil else { return }
                self.messageSharing = nil; self.state = .preview
                self.overlay.setOutputBusy(false); self.reconcile()
                guard self.state == .preview else { return }
                switch outcome {
                case .completed: self.dismiss(restoreFocus: false)
                case .cancelled: break
                case .failed(let error): self.overlay.showError(error.localizedDescription)
                }
                if self.state == .preview { self.focusPreview() }
            }) else {
            overlay.setMessageAvailable(false)
            overlay.showError("Messages is not available for this image."); return
        }
        state = .output; messageSharing = sharing
        overlay.setOutputBusy(true)
        sharing.present()
    }

    private func persistCapture() {
        guard let destination, let library, !libraryWriteInProgress, valid(), lease.isValid, let pngData else { return }
        guard let reservation = destination.reserve() else { overlay.showError("This Space is no longer available."); return }
        let id = captureID
        let input = destination.input(id: id, expectedRevision: savedCapture?.revision, capturedAt: capturedAt,
            title: lease.pageTitle, sourceURL: sourceURL, kind: captureKind, pngData: pngData)
        libraryWriteInProgress = true; overlay.setLibraryBusy(true)
        libraryWrite = Task { [weak self, library] in
            do {
                let item = try await reservation.perform { try await library.save(input) }
                guard let self, self.state != .finished, self.captureID == id else { return }
                self.savedCapture = item; self.libraryNeedsUpdate = false; self.libraryWriteInProgress = false
                self.overlay.setLibraryBusy(false); self.overlay.setLibrarySaved(true)
            } catch {
                guard let self, self.state != .finished, self.captureID == id else { return }
                self.libraryWriteInProgress = false; self.overlay.setLibraryBusy(false)
                if let saved = self.savedCapture, !library.contains(saved) { self.savedCapture = nil; self.overlay.setLibrarySaved(false) }
                self.overlay.showError(error.localizedDescription)
            }
        }
    }
    private func removeFromLibrary(_ item: SavedCapture) {
        guard let destination, let library, valid(), lease.isValid else { return }
        guard let reservation = destination.reserve() else { overlay.showError("This Space is no longer available."); return }
        libraryWriteInProgress = true; overlay.setLibraryBusy(true)
        libraryWrite = Task { [weak self, library] in
            do {
                try await reservation.perform { try await library.delete(item) }
                guard let self, self.state != .finished, self.captureID == item.id else { return }
                self.savedCapture = nil; self.libraryNeedsUpdate = false; self.libraryWriteInProgress = false
                self.overlay.setLibraryBusy(false); self.overlay.setLibrarySaved(false)
            } catch {
                guard let self, self.state != .finished else { return }
                self.libraryWriteInProgress = false; self.overlay.setLibraryBusy(false)
                if !library.contains(item) {
                    self.savedCapture = nil; self.libraryNeedsUpdate = false; self.overlay.setLibrarySaved(false)
                }
                self.overlay.showError(error.localizedDescription)
            }
        }
    }

    private func save() {
        guard let parent, parent.attachedSheet == nil, let data = pngData else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true; panel.isExtensionHidden = false
        let name = lease.pageTitle.components(separatedBy: CharacterSet(charactersIn: "/:\n\r")).joined(separator: " ")
        panel.nameFieldStringValue = (name.isEmpty ? "Capture" : String(name.prefix(100))) + ".png"
        savePanel = panel; state = .output
        panel.beginSheetModal(for: parent) { [weak self, weak panel] response in
            MainActor.assumeIsolated {
                guard let self, self.state == .output, self.savePanel === panel else { return }
                self.savePanel = nil; self.state = .preview
                guard self.valid(), self.lease.isValid else { self.dismiss(restoreFocus: false); return }
                if response == .OK, let url = panel?.url {
                    do { try data.write(to: url, options: .atomic); self.dismiss(restoreFocus: true) }
                    catch { self.overlay.showError(error.localizedDescription) }
                }
                if self.state == .preview { self.focusPreview() }
            }
        }
    }
}

@MainActor
final class PageCaptureOverlay: NSView {
    typealias Action = CapturePaletteAction
    var onCancel: (() -> Void)?
    var onRegion: ((NSRect) -> Void)?
    var onHover: ((NSPoint?) -> Void)?
    var onElement: ((PCNativePageCaptureTarget?, NSPoint) -> Void)?
    var onViewport: (() -> Void)?
    var onFullPage: (() -> Void)?
    var onAction: ((Action) -> Void)?
    var pageSize = CGSize.zero
    let palette = CapturePalette()
    private let stillCover = CaptureStillCover()
    private let wash = ThemeRendererView()
    private let picture = CapturePictureView()
    private let pictureFrame = CaptureFlippedView()
    private let selectionShade = CaptureSelectionShade()
    private let elementLens = CaptureElementLens()
    private let modeChrome = CaptureModeChrome()
    private var hint: CaptureHintCard { modeChrome.hint }
    private var selectionMode = CaptureSelectionMode.element
    private var readoutSize: CGSize?
    private let cancel = ActionButton("Cancel", symbol: "xmark")
    private let spinner = NSProgressIndicator()
    private var paletteShown = false
    private var committedPixels: CGImage?
    private var drafting = false
    private var outputBusy = false
    private var libraryBusy = false
    private var selection: NSRect?
    private var start: NSPoint?
    private var target: PCNativePageCaptureTarget?
    private var mouseDownTarget: PCNativePageCaptureTarget?
    private var pointer: NSPoint?
    private var dragging = false
    private var tracking: NSTrackingArea?
    private let captureCursor = CaptureElementLens.cameraCursor()
    private var accessibilityTarget = false
    private var editing = false
    private var selecting = true
    private var busy = false
    private var motionObserver: NSObjectProtocol?
    private(set) var imageRect = NSRect.zero
    private(set) var capturedRect = NSRect.zero
    private var imageSize = NSSize.zero
    private var previewSourceRect: NSRect?
    private var lift: CaptureLiftMotion?
    private var liftTimer: Timer?
    private let now: () -> TimeInterval
    private let reduceMotion: () -> Bool
    private let scheduleFrames: (Timer) -> Void
    var presentedImageRect: NSRect { picture.frame }
    var stillCoverImage: CGImage? { stillCover.image }
    var onPicturePixels: ((CGSize) -> Void)? {
        get { picture.onPixelSizeChange }
        set { picture.onPixelSizeChange = newValue }
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override convenience init(frame: NSRect) {
        self.init(frame: frame, now: { ProcessInfo.processInfo.systemUptime },
                  reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
                  scheduleFrames: { RunLoop.main.add($0, forMode: .common) })
    }

    init(frame: NSRect, now: @escaping () -> TimeInterval, reduceMotion: @escaping () -> Bool,
         scheduleFrames: @escaping (Timer) -> Void) {
        self.now = now
        self.reduceMotion = reduceMotion
        self.scheduleFrames = scheduleFrames
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel("Page capture")
        picture.setAccessibilityLabel("Captured image preview")
        picture.layer?.cornerRadius = PeekCardAppearance.cornerRadius - CapturePresentation.imageBorder
        picture.layer?.masksToBounds = true
        pictureFrame.wantsLayer = true; pictureFrame.layer?.cornerRadius = PeekCardAppearance.cornerRadius
        pictureFrame.layer?.borderWidth = PeekCardAppearance.borderWidth
        pictureFrame.layer?.borderColor = PeekCardAppearance.borderColor.cgColor
        pictureFrame.layer?.shadowColor = NSColor.black.cgColor
        pictureFrame.layer?.shadowOpacity = PeekCardAppearance.shadowOpacity
        pictureFrame.layer?.shadowRadius = PeekCardAppearance.shadowRadius
        pictureFrame.layer?.shadowOffset = NSSize(width: 0, height: PeekCardAppearance.shadowOffsetY)
        wash.alphaValue = PeekCardAppearance.backdropOpacity; wash.isHidden = true
        addSubview(stillCover); addSubview(wash); addSubview(pictureFrame); addSubview(picture)
        addSubview(selectionShade)
        elementLens.isHidden = true; addSubview(elementLens)
        modeChrome.install(in: self)
        modeChrome.bar.onItem = { [weak self] item in self?.choose(item) }
        elementLens.onFocusChange = { [weak self] focus in self?.followFocus(focus) }
        cancel.actionBlock = { [weak self] in self?.onCancel?() }; addSubview(cancel)
        updateKeyLoop()
        setAccessibilityHelp("Drag to select a region, or in Element mode click the outlined part of the page. E and R switch modes, V captures the visible area, F the full page, and Escape cancels.")
        palette.onAction = { [weak self] action in self?.onAction?(action) }
        palette.onCancel = { [weak self] in self?.onCancel?() }
        palette.onSizeChange = { [weak self] in self?.needsLayout = true }
        spinner.style = .spinning; spinner.controlSize = .regular; addSubview(spinner)
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func showSelection(message: String? = nil) {
        let entering = !modeChrome.isShown
        settlePresentation()
        endSelection()
        selecting = true; editing = false; busy = false; selection = nil; start = nil; stillCover.image = nil
        elementLens.isHidden = false; elementLens.setTarget(nil, animated: false)
        if entering { CaptureModeMotion.enter(elementLens) }
        selectionShade.region = nil; hideWash()
        picture.isHidden = true; pictureFrame.isHidden = true; setPaletteShown(false); spinner.stopAnimation(nil); spinner.isHidden = true
        hint.stringValue = message ?? CaptureModeHint.text(mode: selectionMode, targeted: false, dragging: false)
        hint.isHidden = false; cancel.isHidden = true
        modeChrome.bar.setMode(selectionMode); modeChrome.show(in: bounds)
        needsLayout = true; needsDisplay = true; window?.invalidateCursorRects(for: self)
        updateKeyLoop(); setAccessibilityValue(CaptureModeHint.accessibilityValue(mode: selectionMode, targeted: false))
        if let window { updateHover(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
    }
    func showBusy() {
        settlePresentation()
        endSelection()
        selecting = false; editing = false; busy = true; setPaletteShown(false); showWash(); stillCover.image = nil
        picture.isHidden = true; pictureFrame.isHidden = true
        hint.stringValue = CaptureModeHint.capturing; hint.isHidden = false
        modeChrome.setBusy(true); cancel.isHidden = modeChrome.isShown
        spinner.isHidden = false; spinner.startAnimation(nil); needsLayout = true; needsDisplay = true
        updateKeyLoop(); setAccessibilityValue("Capturing image")
    }
    func showPreview(_ image: CGImage, sourceRect: NSRect? = nil) {
        showImage(image, sourceRect: sourceRect, palette: true)
        setAccessibilityValue("Captured image. Choose a destination or edit.")
    }
    func showEditing(_ image: CGImage) {
        showImage(image, sourceRect: previewSourceRect, palette: false); editing = true; selecting = true
        hint.isHidden = false; hint.stringValue = "Drag to crop. Return keeps the full image. Escape returns to preview."
        cancel.isHidden = false; updateKeyLoop(); needsLayout = true; needsDisplay = true
        setAccessibilityValue("Crop captured image. Escape returns to preview.")
    }
    private func showImage(_ image: CGImage, sourceRect: NSRect?, palette shown: Bool) {
        settlePresentation()
        previewSourceRect = sourceRect
        endSelection()
        editing = false; selecting = false; busy = false; selection = nil; stillCover.image = nil
        committedPixels = image
        let previous = drafting ? picture.image : nil
        picture.image = image; imageSize = NSSize(width: image.width, height: image.height)
        if drafting { drafting = false; CaptureMotion.blendPortrait(picture, previous: previous) }
        picture.isHidden = false; pictureFrame.isHidden = false; hint.isHidden = true; showWash()
        modeChrome.hide(animated: true); cancel.isHidden = true; spinner.stopAnimation(nil); spinner.isHidden = true
        if shown { palette.reset() }
        setPaletteShown(shown); updateKeyLoop()
        needsLayout = true; needsDisplay = true; window?.invalidateCursorRects(for: self)
    }
    var alertSound: () -> Void = { NSSound.beep() }
    func showStillCover(_ image: CGImage) {
        guard busy else { return }
        stillCover.image = image
    }
    func showError(_ message: String, alert: Bool = true) {
        palette.setError(message)
        if alert { alertSound() }
        CaptureMotion.announce(message, from: self)
    }
    func clearError() { palette.setError(nil) }
    func showFramePage(_ page: NSView, preview: CGImage?) {
        palette.showFramePage(page)
        showDraft(preview)
        setAccessibilityValue("Pick a frame. The big preview shows how it'll look.")
    }
    func showDraft(_ image: CGImage?) {
        guard let shown = image ?? committedPixels else { return }
        let previous = picture.image
        picture.image = shown; imageSize = NSSize(width: shown.width, height: shown.height)
        drafting = image != nil
        needsLayout = true
        CaptureMotion.blendPortrait(picture, previous: previous)
    }
    private func setPaletteShown(_ shown: Bool) {
        guard shown != paletteShown else { return }
        paletteShown = shown
        needsLayout = true
        if shown { layoutSubtreeIfNeeded() } else { palette.hide(animated: window != nil) }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); updateAppearance()
    }
    private func updateAppearance() {
        let dark = CaptureAppearance.dark(effectiveAppearance)
        pictureFrame.layer?.backgroundColor = PeekCardAppearance.cardFill(dark: dark).cgColor
        cancel.contentTintColor = .white
        needsDisplay = true
    }
    override func layout() {
        super.layout()
        let barBefore = modeChrome.barFrame
        modeChrome.layout(in: bounds, hintVisible: !hint.isHidden)
        if modeChrome.barFrame != barBefore { window?.invalidateCursorRects(for: self) }
        let hintHeight = hint.isHidden ? 0 : hint.frame.height
        cancel.frame = NSRect(x: max(4, bounds.width - 90), y: 10, width: min(80, max(1, bounds.width - 8)), height: 28)
        spinner.frame = NSRect(x: bounds.midX - 16, y: bounds.midY - 16, width: 32, height: 32)
        let geometry = CapturePresentation.layout(bounds: bounds, pixels: imageSize, source: previewSourceRect,
            paletteHeight: palette.view.naturalHeight, editing: editing, editingFooterHeight: hintHeight + 60,
            fullPalette: palette.view.showsFramePage)
        imageRect = backingAlignedRect(geometry.image, options: .alignAllEdgesNearest); capturedRect = geometry.captured
        lift?.retarget(imageRect)
        placePicture()
        elementLens.frame = bounds; selectionShade.frame = bounds; stillCover.frame = bounds
        if wash.frame != bounds { wash.frame = bounds; wash.invalidateCoordinates() }
        selectionShade.region = editing ? selection : nil; selectionShade.dimmingRect = editing ? imageRect : nil
        if paletteShown, geometry.palette.width > 0, geometry.palette.height > 0 {
            palette.place(geometry.palette, image: imageRect.insetBy(dx: -CapturePresentation.imageBorder,
                dy: -CapturePresentation.imageBorder), in: self)
        }
    }
    func adoptWindowTheme(_ source: ThemeRendererView) {
        if wash.coordinateSpace !== source { wash.coordinateSpace = source }
        wash.incognito = source.incognito
        wash.theme = source.theme
    }
    private func showWash() {
        guard wash.isHidden else { return }
        wash.isHidden = false
        guard window != nil, !reduceMotion(), let layer = wash.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = Float(PeekCardAppearance.backdropOpacity)
        fade.duration = PeekStepBack.openDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "parc.capture.wash")
    }
    private func hideWash() {
        wash.layer?.removeAnimation(forKey: "parc.capture.wash")
        wash.isHidden = true
    }
    func endSelection() {
        selecting = false
        target = nil; mouseDownTarget = nil; pointer = nil
        dragging = false; start = nil; selection = nil; selectionShade.region = nil
        selectionShade.dimmingRect = nil
        elementLens.setTarget(nil, animated: false); elementLens.isHidden = true
        readoutSize = nil; modeChrome.readout.hide()
        updateTargetAccessibility(false)
        onHover?(nil)
        window?.invalidateCursorRects(for: self)
    }
    func targetPending() {
        target = nil
        updateTargetAccessibility(false)
    }
    func setTarget(_ target: PCNativePageCaptureTarget?, rect: NSRect?, size: CGSize? = nil) {
        guard selecting, !editing, !dragging, start == nil, target == nil || selectionMode == .element else { return }
        self.target = target
        readoutSize = target == nil ? nil : size
        if readoutSize == nil { modeChrome.readout.hide() }
        elementLens.isHidden = false
        elementLens.setTarget(rect, animated: target != nil)
        if !busy { hint.stringValue = CaptureModeHint.text(mode: selectionMode, targeted: target != nil, dragging: false) }
        updateTargetAccessibility(target != nil)
    }
    private func followFocus(_ focus: NSRect?) {
        guard selecting, !editing, !dragging, let focus, let readoutSize else { modeChrome.readout.hide(); return }
        modeChrome.readout.show(readoutSize, around: focus, in: bounds, avoiding: modeChrome.readoutObstacle)
    }
    private func showDragReadout(_ selection: NSRect) {
        let page = CaptureSizeReadout.viewportRect(selection, overlay: bounds.size,
            viewport: pageSize.width > 0 && pageSize.height > 0 ? pageSize : bounds.size) ?? selection
        modeChrome.readout.show(CaptureSizeReadout.pointSize(page), around: selection.insetBy(dx: -4, dy: -4), in: bounds,
                                avoiding: modeChrome.readoutObstacle)
    }
    private func restoreAfterTinyDrag() {
        modeChrome.setDragging(false); modeChrome.readout.hide()
        hint.stringValue = CaptureModeHint.text(mode: selectionMode, targeted: false, dragging: false)
    }
    private func choose(_ item: CaptureModeItem) {
        switch item {
        case .element, .region:
            if let mode = item.mode { setSelectionMode(mode) }
        case .visibleArea:
            guard selecting, !editing, start == nil else { return }
            onViewport?()
        case .fullPage:
            guard selecting, !editing, start == nil else { return }
            onFullPage?()
        case .cancel:
            onCancel?()
        }
    }
    private func setSelectionMode(_ mode: CaptureSelectionMode) {
        guard selecting, !editing, !busy, start == nil else { return }
        modeChrome.bar.setMode(mode)
        guard mode != selectionMode else { return }
        selectionMode = mode
        if mode == .region { pointer = nil; onHover?(nil) }
        hint.stringValue = CaptureModeHint.text(mode: mode, targeted: false, dragging: false)
        setAccessibilityValue(CaptureModeHint.accessibilityValue(mode: mode, targeted: false))
        NSAccessibility.post(element: self, notification: .valueChanged)
        window?.invalidateCursorRects(for: self)
        if mode == .element, let window { updateHover(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
    }
    private func updateTargetAccessibility(_ available: Bool) {
        guard accessibilityTarget != available else { return }
        accessibilityTarget = available
        setAccessibilityValue(CaptureModeHint.accessibilityValue(mode: selectionMode, targeted: available))
        setAccessibilityCustomActions(available ? [NSAccessibilityCustomAction(name: "Capture selected area", handler: { [weak self] in
            guard let self, let target = self.target, let pointer = self.pointer,
                  self.selecting, !self.editing, !self.busy else { return false }
            self.onElement?(target, pointer); return true
        })] : [])
        NSAccessibility.post(element: self, notification: .valueChanged)
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        tracking = area; addTrackingArea(area)
        super.updateTrackingAreas()
    }
    private func updateHover(_ point: NSPoint) {
        guard selecting, !editing, !busy, start == nil else { return }
        let onControl = (!cancel.isHidden && cancel.frame.contains(point)) || modeChrome.blocks(point)
        guard bounds.contains(point), !onControl, selectionMode == .element else {
            pointer = nil; onHover?(nil); return
        }
        elementLens.isHidden = false
        pointer = point; onHover?(point)
    }
    override func mouseEntered(with event: NSEvent) { updateHover(convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { updateHover(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) {
        guard start == nil else { return }
        pointer = nil; onHover?(nil)
    }
    override func resetCursorRects() {
        if selecting {
            addCursorRect(editing ? imageRect : bounds, cursor: editing || selectionMode == .region ? .crosshair : captureCursor)
            if !editing, modeChrome.isShown { addCursorRect(modeChrome.barFrame, cursor: .arrow) }
            if !cancel.isHidden { addCursorRect(cancel.frame, cursor: .arrow) }
        }
    }
    private func point(_ event: NSEvent) -> NSPoint {
        let p = convert(event.locationInWindow, from: nil), limit = editing ? imageRect : bounds
        return NSPoint(x: min(max(p.x, limit.minX), limit.maxX), y: min(max(p.y, limit.minY), limit.maxY))
    }
    override func mouseDown(with event: NSEvent) {
        if !selecting { palette.closeSubmenu() }
        guard selecting, !busy else { return }
        let p = point(event)
        if editing && !imageRect.contains(convert(event.locationInWindow, from: nil)) { return }
        window?.makeFirstResponder(self)
        mouseDownTarget = target; target = nil; start = p; dragging = false; selection = nil
        updateTargetAccessibility(false)
        onHover?(nil); needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        updateDrag(to: point(event))
    }
    private func updateDrag(to p: NSPoint) {
        guard selecting, let start else { return }
        if !dragging && hypot(p.x - start.x, p.y - start.y) < 3 { return }
        dragging = true; mouseDownTarget = nil; target = nil
        selection = NSRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(start.x - p.x), height: abs(start.y - p.y))
        if editing { selectionShade.region = selection }
        else {
            elementLens.isHidden = false; elementLens.setSelection(selection)
            modeChrome.setDragging(true)
            hint.stringValue = CaptureModeHint.text(mode: selectionMode, targeted: false, dragging: true)
            if let selection { showDragReadout(selection) }
        }
        needsDisplay = true
    }
    func handleCaptureGesture(state: NSGestureRecognizer.State, point: NSPoint) {
        guard selecting, !editing, !busy, point.x.isFinite, point.y.isFinite else { return }
        let p = NSPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                        y: min(max(point.y, bounds.minY), bounds.maxY))
        switch state {
        case .began:
            start = p; dragging = false; selection = nil; mouseDownTarget = nil; target = nil
            updateTargetAccessibility(false); onHover?(nil)
            elementLens.setTarget(nil, animated: false); elementLens.isHidden = false
            selectionShade.region = nil; needsDisplay = true
        case .changed: updateDrag(to: p)
        case .ended:
            updateDrag(to: p); start = nil
            if let selection, selection.width >= 2, selection.height >= 2 { onRegion?(selection) }
            else { selection = nil; selectionShade.region = nil; dragging = false; restoreAfterTinyDrag()
                elementLens.setTarget(nil, animated: false); updateHover(p); needsDisplay = true }
        default: break
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard selecting, let start else { return }
        mouseDragged(with: event)
        let wasDragging = dragging, clickedTarget = mouseDownTarget
        self.start = nil; mouseDownTarget = nil
        if wasDragging {
            if let selection, selection.width >= 2, selection.height >= 2 { onRegion?(selection) }
            else {
                self.selection = nil; selectionShade.region = nil; dragging = false
                if !editing { restoreAfterTinyDrag() }
                updateHover(point(event)); needsDisplay = true
            }
        } else if !editing, selectionMode == .element { onElement?(clickedTarget, start) }
    }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty || event.keyCode == 48 && modifiers == .shift else { super.keyDown(with: event); return }
        if event.keyCode == 53 { onCancel?() }
        else if event.keyCode == 36 || event.keyCode == 76 {
            if selecting && start == nil {
                if editing { onRegion?(selection ?? imageRect) }
                else if let target, let pointer { onElement?(target, pointer) }
                else { onViewport?() }
            }
        } else if event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        } else if selecting, !editing, start == nil, !event.isARepeat,
                  let item = CaptureModeKeys.item(typed: event.charactersIgnoringModifiers, keyCode: event.keyCode) {
            choose(item)
        } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    func setFramed(_ framed: Bool) { palette.update { $0.framed = framed } }
    func setDestinationAvailability(library: Bool, easels: Bool, notes: Bool = false) {
        palette.update { $0.libraryAvailable = library; $0.easelsAvailable = easels; $0.notesAvailable = notes }
    }
    func setLibrarySaved(_ saved: Bool) { palette.update { $0.librarySaved = saved } }
    func setLibraryBusy(_ busy: Bool) {
        libraryBusy = busy
        palette.setStatus(busy ? "Saving Library changes…" : outputBusy ? "Finish or cancel in Messages." : nil)
        palette.update { $0.libraryBusy = busy }
    }
    func setEaselDestinations(_ items: [CaptureEaselDestination]) { palette.update { $0.easels = items } }
    func setNoteDestinations(_ items: [CaptureNoteDestination]) { palette.update { $0.notes = items } }
    func setMessageAvailable(_ available: Bool) { palette.update { $0.messageAvailable = available } }
    func setOutputBusy(_ busy: Bool) {
        outputBusy = busy
        palette.setStatus(busy ? "Finish or cancel in Messages." : libraryBusy ? "Saving Library changes…" : nil)
        palette.update { $0.busy = busy }
    }
    func focusPreferredControl() {
        guard let window, window.isKeyWindow, window.attachedSheet == nil else { return }
        if paletteShown {
            layoutSubtreeIfNeeded()
            palette.focusSearch()
        } else { window.makeFirstResponder(self) }
    }
    private func updateKeyLoop() {
        nextKeyView = nil
        let controls: [NSView] = !paletteShown
            ? ([self] + (modeChrome.isShown ? modeChrome.bar.keyViews : []) + (cancel.isHidden ? [] : [cancel]))
            : []
        guard let first = controls.first else { return }
        for (index, control) in controls.enumerated() { control.nextKeyView = index + 1 < controls.count ? controls[index + 1] : first }
        if first !== self { nextKeyView = nil }
    }
    func revealCapturedImage() {
        layoutSubtreeIfNeeded()
        settleLift()
        guard capturedRect != imageRect, capturedRect.width > 0, capturedRect.height > 0 else {
            CaptureMotion.reveal(picture.layer, reduceMotion: reduceMotion()); return
        }
        guard !reduceMotion() else {
            CaptureMotion.fadeIntoCard(picture.layer); CaptureMotion.fadeIntoCard(pictureFrame.layer); return
        }
        lift = CaptureLiftMotion(from: capturedRect, to: imageRect, at: now())
        placePicture()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.tickLift()
            }
        }
        liftTimer = timer; scheduleFrames(timer)
    }
    private func tickLift() {
        guard var motion = lift else { settleLift(); return }
        motion.tick(at: now())
        lift = motion
        if !motion.isAnimating { settleLift() } else { placePicture() }
    }
    private func settleLift() {
        liftTimer?.invalidate(); liftTimer = nil
        guard lift != nil else { return }
        lift = nil
        placePicture()
    }
    private func placePicture() {
        let shown = lift?.rect ?? imageRect
        picture.keepsRendering = lift != nil
        picture.frame = shown
        pictureFrame.frame = shown.insetBy(dx: -CapturePresentation.imageBorder, dy: -CapturePresentation.imageBorder)
        pictureFrame.layer?.shadowPath = CGPath(roundedRect: pictureFrame.bounds, cornerWidth: PeekCardAppearance.cornerRadius,
                                                cornerHeight: PeekCardAppearance.cornerRadius, transform: nil)
    }
    private func settlePresentation() {
        settleLift()
        picture.layer?.removeAnimation(forKey: "captureReveal")
        pictureFrame.layer?.removeAnimation(forKey: "captureReveal")
        if hint.superview === self { hint.settleMotion() }
    }
    func retirePresentation() {
        settlePresentation()
        let fading = modeChrome.isShown && superview != nil && window?.isVisible == true
        if fading {
            let ghost = elementLens.ghost(); addSubview(ghost, positioned: .above, relativeTo: elementLens)
            CaptureModeMotion.fadeAway(ghost, from: self)
            if !hint.isHidden { hint.retire(); CaptureModeMotion.fadeAway(hint, from: self) }
        }
        modeChrome.retire(fading: fading)
        endSelection(); elementLens.retire(); stillCover.image = nil
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }; motionObserver = nil
        if window != nil {
            motionObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                        self?.settlePresentation(); self?.elementLens.settleMotion()
                    }
                }
        } else { retirePresentation() }
    }
    deinit { if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) } }
}

@MainActor
class CaptureFlippedView: NSView { override var isFlipped: Bool { true } }

@MainActor
final class CaptureStillCover: CaptureFlippedView {
    var image: CGImage? {
        didSet { isHidden = image == nil; layer?.contents = image; needsDisplay = true }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; isHidden = true
        layer?.contentsGravity = .resize
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.contentsGravity = .resize; layer?.contents = image }
}

@MainActor
final class CaptureElementLens: CaptureFlippedView {
    private let grayscale = CAShapeLayer()
    private let veil = CAShapeLayer()
    private let halo = CAShapeLayer()
    private let outline = CAShapeLayer()
    var onFocusChange: ((NSRect?) -> Void)?
    private var focusRect: NSRect?
    private var motion = CaptureLensMotion()
    private var timer: Timer?
    private var previousBounds = NSRect.zero
    private let now: () -> TimeInterval
    private let reduceMotion: () -> Bool
    private let scheduleFrames: (Timer) -> Void

    override convenience init(frame: NSRect) {
        self.init(frame: frame, now: { ProcessInfo.processInfo.systemUptime },
                  reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
                  scheduleFrames: { RunLoop.main.add($0, forMode: .common) })
    }

    init(frame: NSRect, now: @escaping () -> TimeInterval, reduceMotion: @escaping () -> Bool,
         scheduleFrames: @escaping (Timer) -> Void) {
        self.now = now
        self.reduceMotion = reduceMotion
        self.scheduleFrames = scheduleFrames
        super.init(frame: frame)
        wantsLayer = true
        layer?.isGeometryFlipped = true
        grayscale.fillColor = NSColor.black.cgColor
        grayscale.fillRule = .evenOdd; grayscale.compositingFilter = "colorBlendMode"
        veil.fillColor = NSColor.black.withAlphaComponent(0.25).cgColor
        veil.fillRule = .evenOdd
        halo.fillColor = NSColor.clear.cgColor
        halo.strokeColor = NSColor.white.cgColor
        halo.lineWidth = 4
        halo.shadowColor = NSColor.black.cgColor
        halo.shadowOpacity = 0.25
        halo.shadowRadius = 12
        halo.shadowOffset = CGSize(width: 0, height: 8)
        outline.fillColor = NSColor.clear.cgColor
        outline.lineWidth = 2
        layer?.addSublayer(grayscale); layer?.addSublayer(veil); layer?.addSublayer(halo); layer?.addSublayer(outline)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        grayscale.frame = bounds; veil.frame = bounds; halo.frame = bounds; outline.frame = bounds
        CATransaction.commit()
        if previousBounds != bounds { previousBounds = bounds; settleMotion() }
        updatePaths()
    }
    func setTarget(_ rect: NSRect?, animated: Bool) {
        let inset = rect?.insetBy(dx: -6, dy: -6)
        if inset == focusRect, !motion.isAnimating {
            stopFrames()
            return
        }
        motion.target(inset, at: now(),
            animated: animated && !reduceMotion())
        applyMotionPresentation()
        if motion.isAnimating { startFrames() } else { stopFrames() }
    }
    private func tick() {
        motion.tick(at: now())
        applyMotionPresentation()
        if !motion.isAnimating { stopFrames() }
    }
    private func applyMotionPresentation() {
        let next = motion.rect
        guard next != focusRect else { return }
        focusRect = next
        updatePaths()
        onFocusChange?(next)
    }
    private func startFrames() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer; scheduleFrames(timer)
    }
    private func stopFrames() { timer?.invalidate(); timer = nil }
    func settleMotion() {
        stopFrames()
        motion.settle(at: now())
        applyMotionPresentation()
    }
    func retire() { stopFrames(); motion.clear(); focusRect = nil; updatePaths() }
    func ghost() -> CaptureElementLens {
        let ghost = CaptureElementLens(frame: frame)
        ghost.appearance = effectiveAppearance
        ghost.focusRect = focusRect; ghost.previousBounds = ghost.bounds
        ghost.updatePaths()
        return ghost
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { retire() }; super.viewWillMove(toWindow: newWindow)
    }
    func setSelection(_ rect: NSRect?) {
        stopFrames(); motion.clear()
        focusRect = rect?.insetBy(dx: -4, dy: -4)
        updatePaths()
    }
    private func updatePaths() {
        let shade = CGMutablePath(); shade.addRect(bounds)
        var border: CGPath?
        if let outer = focusRect, !outer.isEmpty {
            shade.addRoundedRect(in: outer.insetBy(dx: 4, dy: 4), cornerWidth: 3, cornerHeight: 3)
            border = CGPath(roundedRect: outer.insetBy(dx: 2, dy: 2), cornerWidth: 5, cornerHeight: 5, transform: nil)
        }
        halo.strokeColor = CaptureAppearance.imageBackground(CaptureAppearance.dark(effectiveAppearance)).cgColor
        outline.strokeColor = NoteTheme.resolved(NoteTheme.accent, in: self)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        grayscale.path = shade; veil.path = shade; halo.path = border; outline.path = border
        CATransaction.commit()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); updatePaths()
    }
    static func cameraCursor() -> NSCursor {
        guard let image = CaptureArtwork.image("camera-cross-cursor") else { return .crosshair }
        return NSCursor(image: image, hotSpot: NSPoint(x: 24, y: 25))
    }

}

@MainActor
private final class CaptureSelectionShade: CaptureFlippedView {
    var region: NSRect? { didSet { needsDisplay = true } }
    var dimmingRect: NSRect? { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        if let dimmingRect {
            let shade = NSBezierPath(rect: dimmingRect)
            if let region { shade.appendRect(region); shade.windingRule = .evenOdd }
            NSColor.black.withAlphaComponent(0.25).setFill(); shade.fill()
        }
        if let region {
            CaptureAppearance.imageBackground(CaptureAppearance.dark(effectiveAppearance)).setStroke(); let border = NSBezierPath(rect: region); border.lineWidth = 4; border.stroke()
        }
    }
}

extension PageCaptureOverlay {
    var harnessPicture: CapturePictureView { picture }
    var harnessSelection: NSRect? { selection }
    var harnessLensShown: Bool { !elementLens.isHidden && selecting }
    func harnessGrayscale(_ shown: Bool) { elementLens.harnessGrayscale(shown) }
}

private extension CaptureElementLens {
    func harnessGrayscale(_ shown: Bool) { grayscale.isHidden = !shown }
}
