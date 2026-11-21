import AppKit
import UniformTypeIdentifiers

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
    private let easelDestinations: () throws -> [CaptureEaselDestination]
    private let addToEasel: (EaselImageInput, UUID?) throws -> Void
    private var messageSharing: CaptureMessageSharing?
    private let overlay = PageCaptureOverlay()
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

    init(lease: PCNativePageCapture, sourceView: NSView, containerView: NSView, host: NSView, parent: NSWindow,
         valid: @escaping () -> Bool, destination: CaptureLibraryDestination?,
         easelDestinations: @escaping () throws -> [CaptureEaselDestination],
         addToEasel: @escaping (EaselImageInput, UUID?) throws -> Void,
         finished: @escaping (Bool) -> Void) {
        self.destination = destination
        self.lease = lease; self.sourceView = sourceView; self.containerView = containerView
        self.host = host; self.parent = parent
        self.valid = valid; self.easelDestinations = easelDestinations
        self.addToEasel = addToEasel; self.finished = finished
        super.init()
        overlay.setDestinationAvailability(library: destination != nil, easels: destination?.allowsEasels == true)
        lease.invalidated = { [weak self] in
            MainActor.assumeIsolated { self?.dismiss(restoreFocus: false) }
        }
        overlay.onCancel = { [weak self] in self?.cancelEditingOrDismiss() }
        overlay.onRegion = { [weak self] rect in self?.selected(rect) }
        overlay.onHover = { [weak self] point in self?.targetElement(at: point) }
        overlay.onElement = { [weak self] target, point in self?.selectedElement(target, at: point) }
        overlay.onViewport = { [weak self] in self?.capture(.viewport) }
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
                self.overlay.setTarget(target, rect: rect)
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
                else { self.overlay.showSelection(message: "Drag to capture a portion of this page") }
            }
        }
    }

    private func capture(_ mode: Mode, rect: NSRect = .zero,
                         element: PCNativePageCaptureTarget? = nil) {
        guard state != .finished, valid(), lease.isValid else { dismiss(restoreFocus: false); return }
        acquisitionMode = mode
        let viewport = NSRect(origin: .zero, size: lease.viewportSize)
        let nativeRect = element.map { $0.viewportRect.insetBy(dx: -2, dy: -2).intersection(viewport) }
            ?? (mode == .region ? rect : viewport)
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
                    self.captureLayout = result.layout.map {
                        EaselCaptureLayout(viewport: EaselPoint(x: $0.viewportSize.width, y: $0.viewportSize.height),
                            scroll: EaselPoint(x: $0.scrollOffset.x, y: $0.scrollOffset.y),
                            region: EaselRect(x: $0.region.minX, y: $0.region.minY, width: $0.region.width, height: $0.region.height))
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
        case .fullPage: lease.captureFullPage(completion: completion)
        }
    }

    private func configurePortrait() {
        guard state == .preview, let image, valid(), lease.isValid, let parent else { return }
        portrait?.removeFromSuperview()
        let view = PortraitCaptureView(source: image.unframedPixels, pageColor: capturedPageColor,
                                       backingScale: image.backingScale, composition: image.frame)
        view.onCapture = { [weak self, weak view] in
            guard let self, self.state == .configuringPortrait, let view, self.portrait === view else { return }
            self.reconcile()
            guard self.state == .configuringPortrait, let image = self.image else { return }
            do { try image.applyFrame(view.composition); self.showPreview(changed: true) }
            catch { view.showError(error.localizedDescription); self.parent?.makeFirstResponder(view.captureButton) }
        }
        view.onCancel = { [weak self] in self?.cancelEditingOrDismiss() }
        portrait = view; state = .configuringPortrait
        overlay.showConfiguration()
        if let host {
            host.addSubview(view, positioned: .above, relativeTo: overlay)
            let top = host.isFlipped ? sourceFrame.minY + 12 : sourceFrame.maxY - view.frame.height - 12
            view.frame.origin = NSPoint(x: min(max(host.bounds.minX + 12, sourceFrame.maxX - view.frame.width - 12),
                                             host.bounds.maxX - view.frame.width - 12),
                                        y: min(max(host.bounds.minY + 12, top), host.bounds.maxY - view.frame.height - 12))
        }
        view.onResize = { [weak self, weak view] in
            guard let self, let view, self.portrait === view, let host = self.host else { return }
            view.frame.origin.y = min(max(host.bounds.minY + 12, view.frame.origin.y),
                                      max(host.bounds.minY + 12, host.bounds.maxY - view.frame.height - 12))
        }
        view.loadDesktop(screen: parent.screen)
        parent.makeFirstResponder(view.captureButton)
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
        portrait?.removeFromSuperview(); portrait = nil
        state = .preview
        captureKind = image.frame != nil ? .portrait : acquisitionMode == .region ? .region : acquisitionMode == .fullPage ? .fullPage : .viewport
        overlay.setFramed(image.frame != nil)
        overlay.showPreview(image.pixels, sourceRect: capturePreviewRect)
        overlay.setMessageAvailable(CaptureMessageSharing.isAvailable(for:
            CaptureMessagePayload(png: image.pngData, sourceAddress: sourceURL)))
        refreshEaselDestinations()
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
        guard state == .preview, !libraryWriteInProgress, valid(), lease.isValid else { return }
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
        case .easel(let id, _): placeOnEasel(id)
        case .expand: break
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

    private func refreshEaselDestinations() {
        guard let destination else { overlay.setEaselDestinations([]); return }
        do { overlay.setEaselDestinations(try destination.easels(easelDestinations)) }
        catch { overlay.setEaselDestinations([]); overlay.showError(error.localizedDescription) }
    }

    private func placeOnEasel(_ id: UUID?) {
        guard destination?.allowsEasels == true, let pngData, let parent, parent.isKeyWindow, parent.attachedSheet == nil else { return }
        state = .output
        var input = EaselImageInput(pngData: pngData, sourceURL: URL(string: sourceURL),
                                   pageTitle: lease.pageTitle, valid: { [weak self] in
            guard let self else { return false }
            return self.state != .finished && self.valid() && self.lease.isValid
        })
        input.capturedPage = true
        input.capturedAt = capturedAt
        input.captureLayout = image?.isOriginalOutput == true ? captureLayout : nil
        do {
            try addToEasel(input, id)
            if state != .finished { dismiss(restoreFocus: false) }
        } catch {
            guard state != .finished else { return }
            state = .preview; reconcile()
            guard state == .preview else { return }
            refreshEaselDestinations(); overlay.showError(error.localizedDescription)
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
        Task { [weak self, library] in
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
        Task { [weak self, library] in
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
final class PageCaptureOverlay: NSView, NSSearchFieldDelegate {
    typealias Action = CaptureDestinationAction
    var onCancel: (() -> Void)?
    var onRegion: ((NSRect) -> Void)?
    var onHover: ((NSPoint?) -> Void)?
    var onElement: ((PCNativePageCaptureTarget?, NSPoint) -> Void)?
    var onViewport: (() -> Void)?
    var onAction: ((Action) -> Void)?
    let searchField = NSSearchField()
    private let picture = CapturePreviewImageView()
    private let pictureFrame = CaptureFlippedView()
    private let palette = CaptureFlippedView()
    private let paletteShadow = CaptureFlippedView()
    private let actionScroll = NSScrollView()
    private let actionContent = CaptureFlippedView()
    private let emptyResults = NSTextField(labelWithString: "No matching destinations")
    private let selectionShade = CaptureSelectionShade()
    private let elementLens = CaptureElementLens()
    private let hint = CaptureHintView()
    private let viewport = ActionButton("Capture Visible Area", symbol: "camera")
    private let cancel = ActionButton("Cancel", symbol: "xmark")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private var buttons: [CaptureActionButton] = []
    private var destinations: [CaptureEaselDestination] = []
    private var destinationsExpanded = false
    private var actions: [Action] = []
    private var separators: [NSView] = []
    private var rowOffsets: [CGFloat] = []
    private var contentHeight: CGFloat = 0
    private var messageAvailable = false
    private var outputBusy = false
    private var framed = false
    private var persistentDestinationsAvailable = true
    private var easelDestinationsAvailable = true
    private var librarySaved = false
    private var libraryBusy = false
    private var selectedAction = 0
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
    private var imageSize = NSSize.zero
    private var previewSourceRect: NSRect?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel("Page capture")
        picture.imageScaling = .scaleProportionallyUpOrDown; picture.setAccessibilityLabel("Captured image preview")
        picture.wantsLayer = true; picture.layer?.cornerRadius = 3.5; picture.layer?.masksToBounds = true
        pictureFrame.wantsLayer = true; pictureFrame.layer?.cornerRadius = CapturePresentation.cornerRadius
        pictureFrame.layer?.shadowColor = NSColor.black.cgColor
        pictureFrame.layer?.shadowOpacity = 0.25; pictureFrame.layer?.shadowRadius = 12
        pictureFrame.layer?.shadowOffset = NSSize(width: 0, height: 8)
        addSubview(pictureFrame); addSubview(picture)
        addSubview(selectionShade)
        elementLens.isHidden = true; addSubview(elementLens)
        addSubview(hint)
        viewport.actionBlock = { [weak self] in self?.onViewport?() }; addSubview(viewport)
        cancel.actionBlock = { [weak self] in self?.onCancel?() }; addSubview(cancel)
        updateKeyLoop()
        setAccessibilityHelp("Move over an area and click to capture it, or drag to select. Escape cancels. Tab reaches capture controls.")
        paletteShadow.wantsLayer = true; paletteShadow.layer?.cornerRadius = CapturePresentation.cornerRadius
        paletteShadow.layer?.shadowOpacity = 0.1; paletteShadow.layer?.shadowRadius = 12
        paletteShadow.layer?.shadowOffset = NSSize(width: 0, height: 2); addSubview(paletteShadow)
        palette.wantsLayer = true; palette.layer?.cornerRadius = CapturePresentation.cornerRadius
        palette.layer?.shadowOpacity = 0.1; palette.layer?.shadowRadius = 2
        palette.layer?.shadowOffset = NSSize(width: 0, height: 2); addSubview(palette)
        actionScroll.drawsBackground = false; actionScroll.hasVerticalScroller = true
        actionScroll.autohidesScrollers = true; actionScroll.documentView = actionContent
        palette.addSubview(actionScroll)
        emptyResults.font = .systemFont(ofSize: 12); emptyResults.textColor = NSColor.white.withAlphaComponent(0.65)
        emptyResults.alignment = .center; emptyResults.isHidden = true
        emptyResults.setAccessibilityLabel("No matching capture destinations")
        actionContent.addSubview(emptyResults)
        searchField.placeholderString = "Send To…"; searchField.delegate = self
        searchField.font = .systemFont(ofSize: 13, weight: .medium)
        searchField.drawsBackground = true
        searchField.isBordered = false; searchField.focusRingType = .none
        searchField.wantsLayer = true; searchField.layer?.cornerRadius = 6; searchField.layer?.masksToBounds = true
        if let cell = searchField.cell as? NSSearchFieldCell {
            cell.searchButtonCell = nil; cell.cancelButtonCell = nil
            cell.placeholderAttributedString = NSAttributedString(string: "Send To…", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.55)])
        }
        searchField.setAccessibilityLabel("Capture action search"); palette.addSubview(searchField)
        status.setAccessibilityLabel("Capture status")
        status.font = .systemFont(ofSize: 12); status.textColor = .white
        palette.addSubview(status)
        spinner.style = .spinning; spinner.controlSize = .regular; addSubview(spinner)
        rebuildActions(); updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func showSelection(message: String? = nil) {
        settlePresentation()
        endSelection()
        selecting = true; editing = false; busy = false; selection = nil; start = nil
        elementLens.isHidden = false; elementLens.setTarget(nil, animated: false)
        selectionShade.region = nil
        picture.isHidden = true; pictureFrame.isHidden = true; palette.isHidden = true; paletteShadow.isHidden = true; spinner.stopAnimation(nil); spinner.isHidden = true
        hint.stringValue = message ?? "Drag to capture a portion of this page"
        hint.isHidden = false; viewport.isHidden = false; cancel.isHidden = false
        needsLayout = true; needsDisplay = true; window?.invalidateCursorRects(for: self)
        updateKeyLoop(); setAccessibilityValue("Select an area to capture")
        if let window { updateHover(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
    }
    func showConfiguration() {
        settlePresentation()
        endSelection()
        selecting = false; editing = false; busy = false; selection = nil; start = nil
        picture.isHidden = true; pictureFrame.isHidden = true; palette.isHidden = true; paletteShadow.isHidden = true; hint.isHidden = true
        viewport.isHidden = true; cancel.isHidden = true
        spinner.stopAnimation(nil); spinner.isHidden = true
        updateKeyLoop()
        needsDisplay = true; window?.invalidateCursorRects(for: self)
    }
    func showBusy() {
        settlePresentation()
        endSelection()
        selecting = false; editing = false; busy = true; palette.isHidden = true; paletteShadow.isHidden = true
        picture.isHidden = true; pictureFrame.isHidden = true
        hint.stringValue = "Capturing…"; hint.isHidden = false; viewport.isHidden = true; cancel.isHidden = false
        spinner.isHidden = false; spinner.startAnimation(nil); needsLayout = true; needsDisplay = true
        updateKeyLoop(); setAccessibilityValue("Capturing image")
    }
    func showPreview(_ image: CGImage, sourceRect: NSRect? = nil) {
        settlePresentation()
        previewSourceRect = sourceRect
        endSelection()
        editing = false; selecting = false; busy = false; selection = nil
        picture.image = NSImage(cgImage: image, size: .zero); imageSize = NSSize(width: image.width, height: image.height)
        picture.isHidden = false; pictureFrame.isHidden = false; palette.isHidden = false; paletteShadow.isHidden = false; hint.isHidden = true
        viewport.isHidden = true; cancel.isHidden = true; spinner.stopAnimation(nil); spinner.isHidden = true
        searchField.stringValue = ""; status.stringValue = ""; destinationsExpanded = false
        selectedAction = 0; rebuildActions(resetSelection: true)
        setAccessibilityValue("Captured image. Choose a destination or edit.")
        needsLayout = true; needsDisplay = true; window?.invalidateCursorRects(for: self)
    }
    func showEditing(_ image: CGImage) {
        let sourceRect = previewSourceRect
        showPreview(image, sourceRect: sourceRect); editing = true; selecting = true; palette.isHidden = true; paletteShadow.isHidden = true
        hint.isHidden = false; hint.stringValue = "Drag to crop. Return keeps the full image. Escape returns to preview."
        cancel.isHidden = false; updateKeyLoop(); needsLayout = true; needsDisplay = true
        setAccessibilityValue("Crop captured image. Escape returns to preview.")
    }
    func showError(_ message: String) {
        status.stringValue = message; needsLayout = true
        NSAccessibility.post(element: status, notification: .valueChanged)
        CaptureMotion.announce(message, from: self)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); updateAppearance()
    }
    private func updateAppearance() {
        let dark = CaptureAppearance.dark(effectiveAppearance)
        palette.layer?.backgroundColor = CaptureAppearance.background(dark).cgColor
        paletteShadow.layer?.backgroundColor = CaptureAppearance.background(dark).cgColor
        pictureFrame.layer?.backgroundColor = CaptureAppearance.imageBackground(dark).cgColor
        searchField.textColor = CaptureAppearance.text(dark)
        searchField.backgroundColor = CaptureAppearance.field(dark)
        if let cell = searchField.cell as? NSSearchFieldCell {
            cell.placeholderAttributedString = NSAttributedString(string: "Send To…", attributes: [
                .foregroundColor: CaptureAppearance.text(dark).withAlphaComponent(0.45)])
        }
        status.textColor = CaptureAppearance.text(dark)
        viewport.contentTintColor = .white; cancel.contentTintColor = .white
        emptyResults.textColor = CaptureAppearance.text(dark).withAlphaComponent(0.45)
        for separator in separators { separator.layer?.backgroundColor = CaptureAppearance.text(dark).withAlphaComponent(0.12).cgColor }
        needsDisplay = true
    }
    override func layout() {
        super.layout()
        let width = min(430, max(1, bounds.width - 20))
        let hintHeight = hint.height(for: width)
        hint.frame = NSRect(x: (bounds.width - width) / 2, y: max(8, bounds.height - hintHeight - 52), width: width, height: hintHeight)
        viewport.frame = NSRect(x: max(4, (bounds.width - 180) / 2), y: max(64, bounds.height - 40), width: min(180, max(1, bounds.width - 8)), height: 28)
        cancel.frame = NSRect(x: max(4, bounds.width - 90), y: 10, width: min(80, max(1, bounds.width - 8)), height: 28)
        spinner.frame = NSRect(x: bounds.midX - 16, y: bounds.midY - 16, width: 32, height: 32)
        let statusHeight: CGFloat = status.stringValue.isEmpty ? 0 : 58
        let geometry = CapturePresentation.layout(bounds: bounds, pixels: imageSize, source: previewSourceRect,
            paletteHeight: 60 + contentHeight + statusHeight, editing: editing, editingFooterHeight: hintHeight + 60)
        palette.frame = geometry.palette
        paletteShadow.frame = palette.frame; paletteShadow.isHidden = palette.isHidden
        let paletteWidth = palette.bounds.width, paletteHeight = palette.bounds.height
        searchField.frame = NSRect(x: 10, y: 10, width: max(1, paletteWidth - 20), height: 30)
        actionScroll.frame = NSRect(x: 10, y: 50, width: max(1, paletteWidth - 20), height: max(1, paletteHeight - 60 - statusHeight))
        actionContent.frame = NSRect(x: 0, y: 0, width: actionScroll.contentSize.width, height: contentHeight)
        emptyResults.frame = NSRect(x: 4, y: 8, width: max(0, actionContent.bounds.width - 8), height: 26)
        for (index, button) in buttons.enumerated() { button.frame = NSRect(x: 0, y: rowOffsets[index], width: actionContent.bounds.width, height: CapturePresentation.rowHeight) }
        for separator in separators { separator.frame.size.width = max(0, actionContent.bounds.width - 12) }
        status.frame = NSRect(x: 14, y: max(0, paletteHeight - statusHeight - 4), width: max(1, paletteWidth - 28), height: statusHeight)
        imageRect = geometry.image; picture.frame = imageRect
        pictureFrame.frame = imageRect.insetBy(dx: -CapturePresentation.imageBorder, dy: -CapturePresentation.imageBorder)
        elementLens.frame = bounds; selectionShade.frame = bounds
        selectionShade.region = editing ? selection : nil; selectionShade.dimmingRect = editing ? imageRect : nil
    }
    override func draw(_ dirtyRect: NSRect) {
        if selecting && !editing { return }
        NSColor.black.withAlphaComponent(0.25).setFill()
        let shade = NSBezierPath(rect: bounds)
        if let selection { shade.appendRect(selection); shade.windingRule = .evenOdd }
        shade.fill()
    }
    func endSelection() {
        selecting = false
        target = nil; mouseDownTarget = nil; pointer = nil
        dragging = false; start = nil; selection = nil; selectionShade.region = nil
        selectionShade.dimmingRect = nil
        elementLens.setTarget(nil, animated: false); elementLens.isHidden = true
        updateTargetAccessibility(false)
        onHover?(nil)
        window?.invalidateCursorRects(for: self)
    }
    func targetPending() {
        target = nil
        updateTargetAccessibility(false)
    }
    func setTarget(_ target: PCNativePageCaptureTarget?, rect: NSRect?) {
        guard selecting, !editing, !dragging, start == nil else { return }
        self.target = target
        elementLens.isHidden = false
        elementLens.setTarget(rect, animated: target != nil)
        if !busy {
            hint.stringValue = target == nil ? "Drag to capture a portion of this page" : "Click to capture this area, or drag to select a portion of the page"
        }
        updateTargetAccessibility(target != nil)
    }
    private func updateTargetAccessibility(_ available: Bool) {
        guard accessibilityTarget != available else { return }
        accessibilityTarget = available
        setAccessibilityValue(available ? "Area selected. Press Return to capture it." : "Drag to select an area, or capture the visible area.")
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
        let onControl = (!cancel.isHidden && cancel.frame.contains(point)) ||
            (!viewport.isHidden && viewport.frame.contains(point)) ||
            (!hint.isHidden && hint.frame.contains(point))
        guard bounds.contains(point), !onControl else {
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
            addCursorRect(editing ? imageRect : bounds, cursor: editing ? .crosshair : captureCursor)
            if !viewport.isHidden { addCursorRect(viewport.frame, cursor: .arrow) }
            if !cancel.isHidden { addCursorRect(cancel.frame, cursor: .arrow) }
        }
    }
    private func point(_ event: NSEvent) -> NSPoint {
        let p = convert(event.locationInWindow, from: nil), limit = editing ? imageRect : bounds
        return NSPoint(x: min(max(p.x, limit.minX), limit.maxX), y: min(max(p.y, limit.minY), limit.maxY))
    }
    override func mouseDown(with event: NSEvent) {
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
        else { elementLens.isHidden = false; elementLens.setSelection(selection) }
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
            else { selection = nil; selectionShade.region = nil; dragging = false
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
            else { self.selection = nil; selectionShade.region = nil; dragging = false; updateHover(point(event)); needsDisplay = true }
        } else if !editing { onElement?(clickedTarget, start) }
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
        } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    func controlTextDidChange(_ obj: Notification) { rebuildActions(resetSelection: true) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if textView.hasMarkedText() { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { onCancel?(); return true }
        if commandSelector == #selector(NSResponder.moveDown(_:)) || commandSelector == #selector(NSResponder.moveUp(_:)) {
            if !actions.isEmpty {
                moveSelection(forward: commandSelector == #selector(NSResponder.moveDown(_:)))
            }; return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if actions.indices.contains(selectedAction), buttons[selectedAction].isEnabled { activate(actions[selectedAction]) }; return true
        }
        return false
    }
    func setFramed(_ framed: Bool) { self.framed = framed; rebuildActions() }
    func setPersistentDestinationsAvailable(_ available: Bool) { setDestinationAvailability(library: available, easels: available) }
    func setDestinationAvailability(library: Bool, easels: Bool) {
        persistentDestinationsAvailable = library; easelDestinationsAvailable = easels; rebuildActions()
    }
    func setLibrarySaved(_ saved: Bool) { librarySaved = saved; rebuildActions() }
    func setLibraryBusy(_ busy: Bool) {
        libraryBusy = busy; status.stringValue = busy ? "Saving Library changes…" : ""
        rebuildActions(); needsLayout = true
    }
    func setEaselDestinations(_ items: [CaptureEaselDestination]) { destinations = items; rebuildActions() }
    func setMessageAvailable(_ available: Bool) { messageAvailable = available; rebuildActions() }
    func setOutputBusy(_ busy: Bool) {
        outputBusy = busy; status.stringValue = busy ? "Finish or cancel in Messages." : ""
        rebuildActions(); needsLayout = true
    }
    private func title(for action: Action) -> String {
        action.title(librarySaved: librarySaved, framed: framed)
    }
    private func rebuildActions(resetSelection: Bool = false) {
        let replacingFocusedRow = buttons.contains { $0 === window?.firstResponder }
        let previouslySelected = !resetSelection && actions.indices.contains(selectedAction) ? actions[selectedAction].id : nil
        buttons.forEach { $0.removeFromSuperview() }; separators.forEach { $0.removeFromSuperview() }
        separators = []; rowOffsets = []; contentHeight = 0
        actions = CaptureDestinationMenu.actions(destinations: destinations, query: searchField.stringValue,
            expanded: destinationsExpanded, framed: framed, librarySaved: librarySaved,
            persistentDestinations: persistentDestinationsAvailable, easelDestinationsAvailable: easelDestinationsAvailable)
        emptyResults.isHidden = !actions.isEmpty
        if actions.isEmpty { contentHeight = 40 }
        var previousGroup: Int?
        buttons = actions.map { action in
            if searchField.stringValue.isEmpty, let previousGroup, action.group != previousGroup {
                let divider = NSView(frame: NSRect(x: 6, y: contentHeight + 3, width: 200, height: 1))
                divider.wantsLayer = true; divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
                actionContent.addSubview(divider); separators.append(divider); contentHeight += 8
            }
            previousGroup = action.group; rowOffsets.append(contentHeight); contentHeight += CapturePresentation.rowHeight
            let title = title(for: action)
            let symbol = action == .library && librarySaved ? "checkmark.circle.fill" : action.symbol
            let button = CaptureActionButton(title, symbol: symbol) { [weak self] in self?.activate(action) }
            button.alignment = .left; button.font = .systemFont(ofSize: 14, weight: .medium)
            button.isSavedToggle = action == .library && librarySaved; button.wantsLayer = true; button.layer?.cornerRadius = 6
            button.isEnabled = !libraryBusy && !outputBusy && (action != .message || messageAvailable)
            button.lineBreakMode = .byTruncatingTail
            if action == .message && !messageAvailable { button.toolTip = "Messages is not available for this image." }
            if action == .library { button.setAccessibilityValue(librarySaved ? "Saved" : "Not saved") }
            if case .easel(_, let title) = action { button.toolTip = title; button.setAccessibilityLabel("Add image to Easel: " + title) }
            button.onFocus = { [weak self] in
                guard let self, let index = self.actions.firstIndex(where: { $0.id == action.id }) else { return }
                self.selectedAction = index; self.updateSelectedAction()
            }
            button.onMoveFocus = { [weak self] forward in
                guard let self else { return }
                self.moveSelection(forward: forward)
                if self.buttons.indices.contains(self.selectedAction) { self.window?.makeFirstResponder(self.buttons[self.selectedAction]) }
            }
            button.focusRingType = .exterior; actionContent.addSubview(button); return button
        }
        selectedAction = CaptureDestinationMenu.selectedIndex(actions: actions, previousID: previouslySelected) {
            !libraryBusy && !outputBusy && ($0 != .message || messageAvailable)
        } ?? 0
        updateSelectedAction(); updateAppearance(); updateKeyLoop(); needsLayout = true
        if replacingFocusedRow { focusPreferredControl() }
    }
    private func activate(_ action: Action) {
        guard !libraryBusy, !outputBusy else { return }
        if action == .expand {
            let next = actions.firstIndex(of: .expand) ?? 0
            destinationsExpanded = true; rebuildActions(); layoutSubtreeIfNeeded()
            selectedAction = min(next, max(0, actions.count - 1)); updateSelectedAction()
            window?.makeFirstResponder(searchField)
        } else { onAction?(action) }
    }
    func focusPreferredControl() {
        guard let window, window.isKeyWindow, window.attachedSheet == nil else { return }
        window.makeFirstResponder(palette.isHidden ? self : searchField)
    }
    private func updateKeyLoop() {
        nextKeyView = nil
        let controls: [NSView] = palette.isHidden
            ? ([self] + (viewport.isHidden ? [] : [viewport]) + (cancel.isHidden ? [] : [cancel]))
            : ([searchField] + buttons.filter(\.isEnabled))
        guard let first = controls.first else { return }
        for (index, control) in controls.enumerated() { control.nextKeyView = index + 1 < controls.count ? controls[index + 1] : first }
        if first !== self { nextKeyView = nil }
    }
    func revealCapturedImage() {
        CaptureMotion.reveal(picture.layer, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    private func settlePresentation() {
        picture.layer?.removeAnimation(forKey: "captureReveal")
        hint.settleMotion()
    }
    func retirePresentation() { endSelection(); settlePresentation(); elementLens.retire() }
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
    private func moveSelection(forward: Bool) {
        guard !buttons.isEmpty else { return }
        for _ in buttons.indices {
            selectedAction = (selectedAction + (forward ? 1 : buttons.count - 1)) % buttons.count
            if buttons[selectedAction].isEnabled { break }
        }
        updateSelectedAction()
    }
    private func updateSelectedAction() {
        for (index, button) in buttons.enumerated() {
            button.chosen = index == selectedAction && button.isEnabled
            button.setAccessibilitySelected(index == selectedAction && button.isEnabled)
        }
        if buttons.indices.contains(selectedAction) {
            actionContent.scrollToVisible(buttons[selectedAction].frame)
            searchField.setAccessibilityHelp("Selected destination: " + buttons[selectedAction].title + ". Use Up and Down, then Return.")
        } else { searchField.setAccessibilityHelp("No matching destinations") }
        NSAccessibility.post(element: actionContent, notification: .selectedChildrenChanged)
    }
}

@MainActor
private class CaptureFlippedView: NSView { override var isFlipped: Bool { true } }

@MainActor
private final class CapturePreviewImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class CaptureElementLens: CaptureFlippedView {
    private let grayscale = CAShapeLayer()
    private let veil = CAShapeLayer()
    private let outline = CAShapeLayer()
    private var focusRect: NSRect?
    private var motion = CaptureLensMotion()
    private var timer: Timer?
    private var previousBounds = NSRect.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isGeometryFlipped = true
        grayscale.fillColor = NSColor.black.cgColor
        grayscale.fillRule = .evenOdd; grayscale.compositingFilter = "colorBlendMode"
        veil.fillColor = NSColor.black.withAlphaComponent(0.25).cgColor
        veil.fillRule = .evenOdd
        outline.fillColor = NSColor.clear.cgColor
        outline.strokeColor = NSColor.white.cgColor
        outline.lineWidth = 4
        outline.shadowColor = NSColor.black.cgColor
        outline.shadowOpacity = 0.25
        outline.shadowRadius = 12
        outline.shadowOffset = CGSize(width: 0, height: 8)
        layer?.addSublayer(grayscale); layer?.addSublayer(veil); layer?.addSublayer(outline)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        grayscale.frame = bounds; veil.frame = bounds; outline.frame = bounds
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
        motion.target(inset, at: ProcessInfo.processInfo.systemUptime,
            animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        applyMotionPresentation()
        if motion.isAnimating { startFrames() } else { stopFrames() }
    }
    private func tick() {
        motion.tick(at: ProcessInfo.processInfo.systemUptime)
        applyMotionPresentation()
        if !motion.isAnimating { stopFrames() }
    }
    private func applyMotionPresentation() {
        let next = motion.rect
        guard next != focusRect else { return }
        focusRect = next
        updatePaths()
    }
    private func startFrames() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func stopFrames() { timer?.invalidate(); timer = nil }
    func settleMotion() {
        stopFrames()
        motion.settle(at: ProcessInfo.processInfo.systemUptime)
        applyMotionPresentation()
    }
    func retire() { stopFrames(); motion.clear(); focusRect = nil; updatePaths() }
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
        outline.strokeColor = CaptureAppearance.imageBackground(CaptureAppearance.dark(effectiveAppearance)).cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        grayscale.path = shade; veil.path = shade; outline.path = border
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

@MainActor
private final class CaptureActionButton: PointingHandButton {
    var onFocus: (() -> Void)?
    var onMoveFocus: ((Bool) -> Void)?
    var chosen = false { didSet { needsDisplay = true } }
    var isSavedToggle = false { didSet { needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    private var hovered = false
    private var pressed = false
    private var tracking: NSTrackingArea?
    private let invokeAction: () -> Void
    init(_ title: String, symbol: String, action: @escaping () -> Void) {
        invokeAction = action
        super.init(frame: .zero)
        self.title = title; image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imagePosition = .imageLeading; isBordered = false; bezelStyle = .regularSquare
        target = self; self.action = #selector(invoke)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }; return accepted
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           event.keyCode == 125 || event.keyCode == 126 { onMoveFocus?(event.keyCode == 125); return }
        super.keyDown(with: event)
    }
    @objc private func invoke() { invokeAction() }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        tracking = area; addTrackingArea(area); super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        pressed = true; needsDisplay = true; super.mouseDown(with: event)
        pressed = false; needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let dark = CaptureAppearance.dark(effectiveAppearance)
        let active = isEnabled && chosen
        let background = !isEnabled ? CaptureAppearance.background(dark) : active
            ? (hovered || pressed ? CaptureAppearance.hoveredSelected : CaptureAppearance.selected)
            : hovered || pressed ? CaptureAppearance.hover(dark) : CaptureAppearance.background(dark)
        background.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let ink = active ? CaptureAppearance.selectedText(dark) : isSavedToggle
            ? CaptureAppearance.toggle(dark) : CaptureAppearance.text(dark)
        let color = ink.withAlphaComponent(ink.alphaComponent * (isEnabled ? 1 : 0.35))
        let symbolRect = NSRect(x: 7, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let symbolColors = isSavedToggle ? [background, color] : [color]
        if let image, let tinted = image.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: symbolColors)) {
            tinted.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: color, .paragraphStyle: paragraph]
        let height = (title as NSString).size(withAttributes: attributes).height
        (title as NSString).draw(in: NSRect(x: 31, y: (bounds.height - height) / 2, width: max(0, bounds.width - 38), height: height), withAttributes: attributes)
    }
}

@MainActor
private final class CaptureHintView: NSView {
    var stringValue = "" { didSet {
        guard stringValue != oldValue else { return }
        needsDisplay = true; superview?.needsLayout = true
        if window != nil, !isHidden, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let transition = CATransition(); transition.type = .fade; transition.duration = 0.2
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(transition, forKey: "captureHintText")
        }
    } }
    private var tracking: NSTrackingArea?
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        self.tracking = tracking; addTrackingArea(tracking); super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    private func setHovered(_ hovered: Bool) {
        guard let layer else { return }
        let from = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin(); CATransaction.setDisableActions(true); layer.opacity = hovered ? 0.1 : 1; CATransaction.commit()
        layer.removeAnimation(forKey: "captureHintHover")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath: "opacity"); animation.fromValue = from; animation.toValue = layer.opacity
            animation.duration = 0.2; animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "captureHintHover")
        }
    }
    func settleMotion() { layer?.removeAllAnimations(); layer?.opacity = 1 }
    override var isFlipped: Bool { true }
    private var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        return [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: CaptureAppearance.hint,
                .paragraphStyle: paragraph]
    }
    func height(for width: CGFloat) -> CGFloat {
        ceil((stringValue as NSString).boundingRect(with: NSSize(width: max(1, width - 50), height: 300),
            options: [.usesLineFragmentOrigin], attributes: attributes).height) + 50
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        NSColor.white.setFill(); path.fill()
        NSGradient(starting: NSColor(displayP3Red: 0, green: 0.278, blue: 1, alpha: 0.08),
                   ending: NSColor(displayP3Red: 1, green: 0.6, blue: 0.6, alpha: 0.08))?.draw(in: path, angle: 20)
        NSColor.white.withAlphaComponent(0.7).setStroke(); path.lineWidth = 1; path.stroke()
        (stringValue as NSString).draw(in: bounds.insetBy(dx: 25, dy: 25), withAttributes: attributes)
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { stringValue }
}
