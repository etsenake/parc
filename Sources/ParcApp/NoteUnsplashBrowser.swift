import AppKit
import ParcCore

@MainActor
final class NoteUnsplashClient {
    static let shared = NoteUnsplashClient()
    nonisolated static let downloadLimit = 40 * 1024 * 1024
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 120
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = URLCache(memoryCapacity: 8_000_000, diskCapacity: 0)
        session = URLSession(configuration: configuration)
    }

    func page(query: String, page: Int, orientation: NoteUnsplash.Orientation?) async throws -> NoteUnsplash.Page {
        guard let key = NoteUnsplash.accessKey() else { throw NoteUnsplashError.missingKey }
        let request = NoteUnsplash.listRequest(query: query, page: page, orientation: orientation, key: key)
        let data = try await fetch(request)
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return try NoteUnsplash.page(from: data, searching: searching, page: page)
    }

    func download(_ photo: NoteUnsplashPhoto, width: Int) async throws -> Data {
        guard let key = NoteUnsplash.accessKey() else { throw NoteUnsplashError.missingKey }
        guard let url = NoteUnsplash.imageURL(for: photo, width: width) else { throw NoteUnsplashError.unreadable }
        track(photo, key: key)
        let data = try await fetch(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60))
        guard data.count <= Self.downloadLimit, NoteUnsplash.fileExtension(for: data) != nil else { throw NoteUnsplashError.unreadable }
        return data
    }

    private func track(_ photo: NoteUnsplashPhoto, key: String) {
        guard let request = NoteUnsplash.trackingRequest(for: photo, key: key) else { return }
        session.dataTask(with: request).resume()
    }

    private func fetch(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw NoteUnsplashError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw NoteUnsplashError.unreadable }
        if let failure = NoteUnsplash.error(status: http.statusCode, remaining: http.value(forHTTPHeaderField: "X-Ratelimit-Remaining"), body: data) {
            throw failure
        }
        return data
    }
}

@MainActor
enum NoteUnsplashImport {
    struct Imported {
        var source: String
        var credit: NoteMediaCredit
        var alt: String?
    }

    struct Downloaded {
        var data: Data
        var fileExtension: String
        var suggestedName: String
        var credit: NoteMediaCredit
        var alt: String?
    }

    static func download(_ photo: NoteUnsplashPhoto, width: Int) async throws -> Downloaded {
        let data = try await NoteUnsplashClient.shared.download(photo, width: width)
        try Task.checkCancellation()
        guard let fileExtension = NoteUnsplash.fileExtension(for: data) else { throw NoteUnsplashError.unreadable }
        return Downloaded(data: data, fileExtension: fileExtension, suggestedName: NoteUnsplash.suggestedName(for: photo),
                          credit: NoteUnsplash.credit(for: photo), alt: NoteUnsplash.altText(for: photo))
    }

    static func importPhoto(_ photo: NoteUnsplashPhoto, width: Int, environment: NoteEnvironment) async throws -> Imported {
        let downloaded = try await download(photo, width: width)
        let source = try NoteMediaImport.source(importing: downloaded.data, fileExtension: downloaded.fileExtension,
                                                suggestedName: downloaded.suggestedName, environment: environment)
        return Imported(source: source, credit: downloaded.credit, alt: downloaded.alt)
    }
}

@MainActor
enum NoteMediaPanels {
    static func presentReplaceMenu(from anchor: NSView, in overlay: NSView, upload: @escaping () -> Void,
                                   unsplash: @escaping (NSView?) -> Void, closed: @escaping () -> Void) -> NotePagePopover {
        let list = NoteMenuList(items: [
            NoteMenuList.Item(id: "upload", title: "Upload…", icon: .symbol("square.and.arrow.up")),
            NoteMenuList.Item(id: "unsplash", title: "Unsplash…", icon: .symbol("photo.on.rectangle.angled")),
        ])
        list.minimumWidth = 180
        let popover = NotePagePopover(content: list)
        popover.exempt(anchor)
        list.onActivate = { [weak popover, weak anchor] item in
            popover?.close(animated: false)
            if item.id == "unsplash" { unsplash(anchor) } else { upload() }
        }
        list.onCancel = { [weak popover] in popover?.close() }
        popover.onKeyDown = { [weak list] event in list?.handleKeyDown(event) ?? false }
        popover.onClose = closed
        popover.present(in: overlay, anchor: overlay.convert(anchor.bounds, from: anchor), edge: .below, alignment: .trailing)
        return popover
    }

    static func presentUnsplash(from anchor: NSView, in overlay: NSView, alignment: NoteFloatingPanel.Alignment,
                                open: @escaping (URL) -> Void,
                                pick: @escaping (NoteUnsplashPhoto, NoteUnsplashBrowser, NotePagePopover?) -> Void,
                                closed: @escaping () -> Void) -> NotePagePopover {
        let browser = NoteUnsplashBrowser(orientation: nil)
        let popover = NotePagePopover(content: browser)
        popover.exempt(anchor)
        browser.onOpen = open
        browser.onPick = { [weak browser, weak popover] photo in
            guard let browser else { return }
            pick(photo, browser, popover)
        }
        popover.onClose = closed
        popover.present(in: overlay, anchor: overlay.convert(anchor.bounds, from: anchor), edge: .below, alignment: alignment)
        browser.focus()
        return popover
    }
}

@MainActor
final class NoteUnsplashBrowser: NSView, NoteFloatingPanelContent {
    static let preferredSize = NSSize(width: 452, height: 392)
    static let inset: CGFloat = 12
    static let gap: CGFloat = 8
    static let footerHeight: CGFloat = 26
    static let searchDelay: TimeInterval = 0.35

    let orientation: NoteUnsplash.Orientation?
    let columns: Int
    var onPick: ((NoteUnsplashPhoto) -> Void)?
    var onOpen: ((URL) -> Void)?
    var preferredSizeDidChange: (() -> Void)?
    var busyPhotoID: String? { didSet { if busyPhotoID != oldValue { refreshBusy() } } }

    private let searchField = NoteSearchField(placeholder: "Search Unsplash…")
    private let scrollView = NSScrollView()
    private let grid = NoteUnsplashGridView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let retryChip = NoteChip("Try again", icon: .symbol("arrow.clockwise"))
    private let footer = NoteCreditLabel()
    private let footerRule = NSView()
    private var photos: [NoteUnsplashPhoto] = []
    private var tiles: [NoteUnsplashTile] = []
    private var placeholders: [NoteMediaShimmer] = []
    private var query = ""
    private var page = 0
    private var hasMore = true
    private var failure: String?
    private var loading: Task<Void, Never>?
    private var pendingSearch: DispatchWorkItem?
    private var generation = 0
    private var scrollObserver: NSObjectProtocol?

    init(orientation: NoteUnsplash.Orientation?, columns: Int = 3) {
        self.orientation = orientation
        self.columns = max(1, columns)
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Unsplash photos")
        searchField.textField.setAccessibilityLabel("Search Unsplash")
        searchField.onChange = { [weak self] text in self?.queryChanged(text) }
        searchField.onSubmit = { [weak self] text in self?.search(text, immediately: true) }
        grid.onLayout = { [weak self] in self?.layoutGrid() }
        scrollView.documentView = grid
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        statusLabel.font = NoteTheme.nunitoRegular(13)
        statusLabel.textColor = NoteTheme.menuSecondaryInk
        statusLabel.alignment = .center
        statusLabel.isHidden = true
        retryChip.isHidden = true
        retryChip.onPress = { [weak self] in self?.retry() }
        grid.addSubview(statusLabel)
        grid.addSubview(retryChip)
        footer.font = NoteTheme.nunitoRegular(11.5)
        footer.ink = NoteTheme.menuTertiaryInk
        footer.linkInk = NoteTheme.menuSecondaryInk
        footer.parts = [.text("Photos from "), .link("Unsplash", NoteMediaCredit.referral(URL(string: "https://unsplash.com/")!))]
        footer.onOpen = { [weak self] url in self?.onOpen?(url) }
        footerRule.wantsLayer = true
        for view in [searchField, scrollView, footerRule, footer] as [NSView] { addSubview(view) }
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.loadMoreIfNeeded() }
        }
        refreshAppearance()
        load(reset: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        loading?.cancel()
        pendingSearch?.cancel()
    }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { Self.preferredSize }
    override var fittingSize: NSSize { Self.preferredSize }

    func focus() {
        searchField.focus()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window == nil else { return }
        pendingSearch?.cancel()
    }

    override func layout() {
        super.layout()
        let inset = Self.inset
        searchField.frame = NSRect(x: inset, y: 0, width: bounds.width - inset * 2, height: NoteTheme.fieldHeight)
        let top = searchField.frame.maxY + 8
        let footerTop = bounds.height - Self.footerHeight
        scrollView.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, footerTop - top))
        footerRule.frame = NSRect(x: 0, y: footerTop, width: bounds.width, height: 1)
        let footerSize = footer.intrinsicContentSize
        footer.frame = NSRect(x: inset + 2, y: footerTop + (Self.footerHeight - footerSize.height) / 2 + 1, width: min(footerSize.width, bounds.width - inset * 2),
                              height: footerSize.height)
        layoutGrid()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
        redisplayChromeSubtree()
    }

    private func refreshAppearance() {
        NoteAnimation.withoutAnimation { footerRule.layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self) }
    }

    private var tileWidth: CGFloat {
        let width = scrollView.contentSize.width > 0 ? scrollView.contentSize.width : bounds.width
        return floor((width - Self.inset * 2 - Self.gap * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private var rowHeight: CGFloat { NoteUnsplashTile.height(forWidth: tileWidth) + Self.gap }

    private func tileFrame(at index: Int) -> NSRect {
        let column = index % columns, row = index / columns
        let width = tileWidth
        return NSRect(x: Self.inset + CGFloat(column) * (width + Self.gap), y: 2 + CGFloat(row) * rowHeight,
                      width: width, height: NoteUnsplashTile.height(forWidth: width))
    }

    private func layoutGrid() {
        let width = scrollView.contentSize.width > 0 ? scrollView.contentSize.width : bounds.width
        NoteAnimation.withoutAnimation {
            for (index, tile) in tiles.enumerated() { tile.frame = tileFrame(at: index) }
            for (index, placeholder) in placeholders.enumerated() {
                var frame = tileFrame(at: tiles.count + index)
                frame.size.height = NoteUnsplashTile.imageHeight(forWidth: frame.width)
                placeholder.frame = frame
            }
        }
        let rows = (tiles.count + placeholders.count + columns - 1) / columns
        var contentHeight = 2 + CGFloat(rows) * rowHeight
        let showsStatus = !statusLabel.isHidden || !retryChip.isHidden
        if showsStatus {
            let labelWidth = min(width - 48, 320)
            let labelHeight = statusLabel.isHidden ? 0 : ceil(statusLabel.sizeThatFits(NSSize(width: labelWidth, height: 400)).height)
            let chipSize = retryChip.intrinsicContentSize
            let block = labelHeight + (retryChip.isHidden ? 0 : (labelHeight > 0 ? 10 : 0) + chipSize.height)
            let viewport = scrollView.contentSize.height
            let top = tiles.isEmpty ? max(8, (viewport - block) / 2 - 6) : contentHeight + 6
            statusLabel.frame = NSRect(x: (width - labelWidth) / 2, y: top, width: labelWidth, height: labelHeight)
            retryChip.frame = NSRect(x: (width - chipSize.width) / 2, y: top + labelHeight + (labelHeight > 0 ? 10 : 0), width: chipSize.width, height: chipSize.height)
            contentHeight = max(contentHeight, top + block + 14)
        }
        let height = max(contentHeight + Self.gap, scrollView.contentSize.height)
        if abs(grid.frame.height - height) > 0.5 || abs(grid.frame.width - width) > 0.5 {
            grid.setFrameSize(NSSize(width: width, height: height))
        }
    }

    private func queryChanged(_ text: String) {
        search(text, immediately: false)
    }

    private func search(_ text: String, immediately: Bool) {
        pendingSearch?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != query || immediately && failure != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.query = trimmed
                self.load(reset: true)
            }
        }
        pendingSearch = work
        if immediately { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + Self.searchDelay, execute: work) }
    }

    private func retry() {
        failure = nil
        if photos.isEmpty { load(reset: true) } else { hasMore = true; load(reset: false) }
    }

    private func load(reset: Bool) {
        if reset {
            generation += 1
            loading?.cancel()
            loading = nil
            page = 0
            hasMore = true
            failure = nil
            photos = []
            for tile in tiles { tile.removeFromSuperview() }
            tiles = []
            NoteAnimation.withoutAnimation { scrollView.contentView.scroll(to: .zero) }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        guard hasMore, loading == nil, failure == nil else { return }
        let generation = self.generation, nextPage = page + 1, query = self.query, orientation = self.orientation
        showPlaceholders(photos.isEmpty ? columns * 3 : columns)
        setStatus(nil, retry: false)
        loading = Task { [weak self] in
            do {
                let result = try await NoteUnsplashClient.shared.page(query: query, page: nextPage, orientation: orientation)
                guard let self, self.generation == generation else { return }
                self.loading = nil
                self.received(result, page: nextPage)
            } catch {
                guard let self, self.generation == generation else { return }
                self.loading = nil
                guard !(error is CancellationError) else { return }
                self.failed(error)
            }
        }
    }

    private func received(_ result: NoteUnsplash.Page, page: Int) {
        self.page = page
        hasMore = result.hasMore
        let merged = NoteUnsplash.merge(photos, result.photos)
        let added = Array(merged.dropFirst(photos.count))
        photos = merged
        showPlaceholders(0)
        let first = tiles.count
        for (offset, photo) in added.enumerated() {
            let tile = NoteUnsplashTile(photo: photo)
            tile.onPick = { [weak self] photo in self?.pick(photo) }
            tile.onOpen = { [weak self] url in self?.onOpen?(url) }
            tile.isDisabled = busyPhotoID != nil
            grid.addSubview(tile)
            tiles.append(tile)
            tile.frame = tileFrame(at: first + offset)
            tile.reveal(delay: Double(min(offset, 11)) * 0.018)
        }
        if photos.isEmpty {
            let shown = query.isEmpty ? "Unsplash has nothing to show right now." : "No photos of “\(query)”. Try another word?"
            setStatus(shown, retry: false)
        } else {
            setStatus(nil, retry: false)
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        loadMoreIfNeeded()
    }

    private func failed(_ error: Error) {
        failure = error.localizedDescription
        showPlaceholders(0)
        let retryable = (error as? NoteUnsplashError).map { $0 != .missingKey && $0 != .unauthorized } ?? true
        setStatus(error.localizedDescription, retry: retryable)
        needsLayout = true
    }

    private func setStatus(_ message: String?, retry: Bool) {
        statusLabel.stringValue = message ?? ""
        statusLabel.isHidden = message == nil
        retryChip.isHidden = !retry
        statusLabel.setAccessibilityLabel(message)
        if let message, window != nil {
            NSAccessibility.post(element: self, notification: .announcementRequested,
                                 userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        needsLayout = true
    }

    private func showPlaceholders(_ count: Int) {
        guard count != placeholders.count else { return }
        for placeholder in placeholders { placeholder.removeFromSuperview() }
        placeholders = []
        for _ in 0..<count {
            let placeholder = NoteMediaShimmer()
            placeholder.cornerRadius = NoteUnsplashTile.radius
            grid.addSubview(placeholder)
            placeholders.append(placeholder)
        }
        needsLayout = true
    }

    private func loadMoreIfNeeded() {
        guard hasMore, loading == nil, failure == nil, !photos.isEmpty else { return }
        let visible = scrollView.contentView.bounds
        guard grid.frame.height - visible.maxY < rowHeight * 2 else { return }
        load(reset: false)
    }

    private func pick(_ photo: NoteUnsplashPhoto) {
        guard busyPhotoID == nil else { return }
        onPick?(photo)
    }

    private func refreshBusy() {
        for tile in tiles {
            tile.isBusy = tile.photo.id == busyPhotoID
            tile.isDisabled = busyPhotoID != nil && tile.photo.id != busyPhotoID
        }
    }
}

@MainActor
final class NoteUnsplashGridView: NSView {
    var onLayout: (() -> Void)?

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if changed { onLayout?() }
    }
}

@MainActor
final class NoteUnsplashTile: NSView {
    static let radius: CGFloat = 6
    static let nameHeight: CGFloat = 18

    static func imageHeight(forWidth width: CGFloat) -> CGFloat { floor(width * 0.64) }
    static func height(forWidth width: CGFloat) -> CGFloat { imageHeight(forWidth: width) + 3 + nameHeight }

    let photo: NoteUnsplashPhoto
    var onPick: ((NoteUnsplashPhoto) -> Void)?
    var onOpen: ((URL) -> Void)?
    var isBusy = false { didSet { if isBusy != oldValue { refreshBusy() } } }
    var isDisabled = false { didSet { if isDisabled != oldValue { thumb.isEnabled = !isDisabled; refreshDim() } } }
    private let thumb: NoteUnsplashThumb
    private let name = NoteCreditLabel()
    private let shimmer = NoteMediaShimmer()

    init(photo: NoteUnsplashPhoto) {
        self.photo = photo
        thumb = NoteUnsplashThumb(photo: photo)
        super.init(frame: .zero)
        wantsLayer = true
        thumb.onPress = { [weak self] in
            guard let self else { return }
            self.onPick?(self.photo)
        }
        name.font = NoteTheme.nunitoRegular(11.5)
        name.ink = NoteTheme.menuTertiaryInk
        name.linkInk = NoteTheme.menuTertiaryInk
        if let profile = NoteUnsplash.credit(for: photo).profileURL {
            name.parts = [NoteMediaCredit.Part.link(photo.photographer, profile)]
        } else {
            name.parts = [NoteMediaCredit.Part.text(photo.photographer)]
        }
        name.onOpen = { [weak self] url in self?.onOpen?(url) }
        name.setAccessibilityLabel("Photographer: " + photo.photographer)
        shimmer.cornerRadius = Self.radius
        shimmer.isHidden = true
        addSubview(thumb)
        addSubview(shimmer)
        addSubview(name)
        thumb.load()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let imageHeight = Self.imageHeight(forWidth: bounds.width)
        thumb.frame = NSRect(x: 0, y: 0, width: bounds.width, height: imageHeight)
        shimmer.frame = thumb.frame
        let nameWidth = min(bounds.width - 2, name.intrinsicContentSize.width)
        name.frame = NSRect(x: 1, y: imageHeight + 3, width: max(0, nameWidth), height: Self.nameHeight)
    }

    func reveal(delay: TimeInterval) {
        guard let layer, window != nil else { return }
        if NoteAnimation.reduceMotion {
            NoteAnimation.withoutAnimation { layer.opacity = 0 }
            NoteAnimation.fade(layer, to: 1, duration: NoteAnimation.reducedFadeDuration)
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let rise = CABasicAnimation(keyPath: "transform")
        let down = superview?.isFlipped == true ? NoteAnimation.insertRise : -NoteAnimation.insertRise
        rise.fromValue = NSValue(caTransform3D: CATransform3DMakeTranslation(0, down, 0))
        rise.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        let group = CAAnimationGroup()
        group.animations = [fade, rise]
        group.duration = NoteAnimation.insertDuration
        group.timingFunction = NoteCurve.easeOut
        group.beginTime = CACurrentMediaTime() + delay
        group.fillMode = .backwards
        layer.add(group, forKey: NoteAnimation.revealKey)
    }

    private func refreshBusy() {
        shimmer.isHidden = !isBusy
        thumb.isBusy = isBusy
        thumb.setAccessibilityLabel(isBusy ? "Bringing this photo in…" : "Photo by " + photo.photographer)
        refreshDim()
    }

    private func refreshDim() {
        guard let layer else { return }
        let target: Float = isDisabled ? 0.45 : 1
        if window == nil { NoteAnimation.withoutAnimation { layer.opacity = target } } else { NoteAnimation.fade(layer, to: target, duration: 0.15) }
    }
}

@MainActor
final class NoteUnsplashThumb: PointingHandButton {
    let photo: NoteUnsplashPhoto
    var onPress: (() -> Void)?
    var isBusy = false { didSet { needsDisplay = true } }
    private var picture: CGImage?
    private var isHovered = false
    private var hoverArea: NSTrackingArea?

    init(photo: NoteUnsplashPhoto) {
        self.photo = photo
        super.init(frame: .zero)
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        refusesFirstResponder = true
        wantsLayer = true
        target = self
        action = #selector(pressed)
        setAccessibilityLabel("Photo by " + photo.photographer)
        if let alt = NoteUnsplash.altText(for: photo) { setAccessibilityHelp(alt) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    @objc private func pressed() { onPress?() }

    func load() {
        guard let url = NoteUnsplash.thumbnailURL(for: photo, width: 400) else { return }
        if let cached = NoteMediaImageLoader.shared.cached(url, pixels: 400) {
            picture = cached.frames.first
            return
        }
        NoteMediaImageLoader.shared.load(url, pixels: 400) { [weak self] result in
            guard let self, case .success(let loaded) = result, let frame = loaded.frames.first else { return }
            self.picture = frame
            if let layer = self.layer, self.window != nil {
                let transition = CATransition()
                transition.type = .fade
                transition.duration = NoteAnimation.reduceMotion ? NoteAnimation.reducedFadeDuration : NoteAnimation.revealDuration
                layer.add(transition, forKey: NoteAnimation.keyPrefix + "unsplash.thumb")
            }
            self.needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { trackPointer(event) }
    override func mouseMoved(with event: NSEvent) { trackPointer(event) }

    override func mouseExited(with event: NSEvent) {
        guard isHovered else { return }
        isHovered = false
        needsDisplay = true
    }

    private func trackPointer(_ event: NSEvent) {
        let hovered = NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)
        if hovered != isHovered {
            isHovered = hovered
            needsDisplay = true
        }
        if showsPointingHand { applyNoteCursor(.pointingHand, for: event) }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        press(true)
        super.mouseDown(with: event)
        press(false)
    }

    private func press(_ down: Bool) {
        guard let layer else { return }
        let center = NoteAnimation.layerPoint(NSPoint(x: bounds.midX, y: bounds.midY), in: self)
        let target = down ? NoteAnimation.scaleTransform(NoteAnimation.pressedScale, about: center) : CATransform3DIdentity
        if NoteAnimation.reduceMotion { NoteAnimation.withoutAnimation { layer.transform = target }; return }
        NoteAnimation.animate(layer, "transform", to: NSValue(caTransform3D: target), spring: .press, key: NoteAnimation.keyPrefix + "unsplash.press")
    }

    private var placeholder: NSColor {
        guard let color = photo.placeholderColor else { return NoteTheme.mediaPlaceholderFill }
        return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawInOwnAppearance {
            let rect = bounds.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: NoteUnsplashTile.radius, yRadius: NoteUnsplashTile.radius)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            placeholder.setFill()
            rect.fill()
            if let picture, let context = NSGraphicsContext.current?.cgContext {
                let size = CGSize(width: picture.width, height: picture.height)
                let scale = max(rect.width / max(size.width, 1), rect.height / max(size.height, 1))
                let drawn = CGSize(width: size.width * scale, height: size.height * scale)
                let frame = CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2, width: drawn.width, height: drawn.height)
                context.saveGState()
                context.translateBy(x: 0, y: frame.maxY + frame.minY)
                context.scaleBy(x: 1, y: -1)
                context.interpolationQuality = .high
                context.setAlpha(isBusy ? 0.55 : 1)
                context.draw(picture, in: frame)
                context.restoreGState()
            }
            NSGraphicsContext.restoreGraphicsState()
            if (isHovered || isHighlighted) && isEnabled && !isBusy {
                NoteTheme.accent.setStroke()
                let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: NoteUnsplashTile.radius + 1, yRadius: NoteUnsplashTile.radius + 1)
                ring.lineWidth = 2
                ring.stroke()
            } else {
                NoteTheme.menuHairline.setStroke()
                path.lineWidth = 0.5
                path.stroke()
            }
        }
    }
}
