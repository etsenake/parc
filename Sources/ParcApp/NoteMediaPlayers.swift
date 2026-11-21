import AppKit
import AVFoundation
import AVKit

@MainActor
enum NoteMediaAssets {
    struct Facts {
        var playable: Bool
        var naturalSize: CGSize?
        var duration: Double?
        var unreachable = false

        var problem: NoteMediaProblem? {
            if unreachable { return .unreachable }
            return playable ? nil : .unsupported
        }
    }

    private static var facts: [URL: Facts] = [:]
    private static var waiting: [URL: [(Facts) -> Void]] = [:]
    private static let posters = NSCache<NSURL, NoteMediaPosterBox>()

    static func cachedFacts(_ url: URL) -> Facts? { facts[url] }

    static func loadFacts(_ url: URL, completion: @escaping (Facts) -> Void) {
        if let hit = facts[url] { completion(hit); return }
        if waiting[url] != nil { waiting[url]?.append(completion); return }
        waiting[url] = [completion]
        let asset = AVURLAsset(url: url)
        Task { @MainActor in
            var result = Facts(playable: false, naturalSize: nil, duration: nil)
            do {
                let (playable, duration) = try await asset.load(.isPlayable, .duration)
                result.playable = playable
                result.duration = duration.isNumeric ? duration.seconds : nil
            } catch {
                result.unreachable = !url.isFileURL && NoteMediaFileType.isNetworkFailure(error)
            }
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) {
                let turned = size.applying(transform)
                result.naturalSize = CGSize(width: abs(turned.width), height: abs(turned.height))
            }
            if url.isFileURL || result.playable { facts[url] = result }
            let callbacks = waiting.removeValue(forKey: url) ?? []
            for callback in callbacks { callback(result) }
        }
    }

    static func forget(_ url: URL) {
        facts.removeValue(forKey: url)
        posters.removeObject(forKey: url as NSURL)
    }

    static func cachedPoster(_ url: URL) -> CGImage? { posters.object(forKey: url as NSURL)?.image }

    static func loadPoster(_ url: URL, maxPixels: Int, completion: @escaping (CGImage?) -> Void) {
        if let hit = cachedPoster(url) { completion(hit); return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        generator.generateCGImageAsynchronously(for: CMTime(seconds: 0.4, preferredTimescale: 600)) { image, _, _ in
            let box = image.map(NoteMediaPosterBox.init)
            DispatchQueue.main.async {
                if let box { posters.setObject(box, forKey: url as NSURL) }
                completion(box?.image)
            }
        }
    }
}

final class NoteMediaPosterBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

@MainActor
final class NoteMediaPlayButton: NoteMediaControl {
    private let disc = CALayer()
    private let glyph = CALayer()
    var diameter: CGFloat = 56 { didSet { needsLayout = true } }
    var symbolName = "play.fill" { didSet { refresh() } }
    var filled = false { didSet { refresh() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        disc.cornerCurve = .continuous
        disc.shadowOpacity = 0.18
        disc.shadowRadius = 8
        disc.shadowOffset = CGSize(width: 0, height: -2)
        disc.shadowColor = NSColor.black.cgColor
        glyph.contentsGravity = .center
        layer?.addSublayer(disc)
        layer?.addSublayer(glyph)
        setAccessibilityLabel("Play")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        NoteMediaMotion.instant {
            let rect = NSRect(x: (bounds.width - diameter) / 2, y: (bounds.height - diameter) / 2, width: diameter, height: diameter)
            disc.frame = rect
            disc.cornerRadius = diameter / 2
            disc.shadowPath = CGPath(ellipseIn: disc.bounds, transform: nil)
            glyph.frame = rect.offsetBy(dx: symbolName.hasPrefix("play") ? diameter * 0.03 : 0, dy: 0)
            glyph.contentsScale = window?.backingScaleFactor ?? 2
        }
        refresh()
    }

    override func hoverDidChange() {
        guard !NoteAnimation.reduceMotion else { return }
        let target = isHovered ? NoteMediaMotion.scaleTransform(1.06, anchor: CGPoint(x: 0.5, y: 0.5), in: self) : CATransform3DIdentity
        guard let layer else { return }
        let from = layer.presentation()?.transform ?? layer.transform
        NoteMediaMotion.instant { layer.transform = target }
        layer.add(NoteAnimation.spring("transform", .press, from: NSValue(caTransform3D: from), to: NSValue(caTransform3D: target)), forKey: "media.play.hover")
    }

    override func pressDidChange() {
        guard let layer else { return }
        NoteMediaMotion.press(layer, pressed: isPressed, in: self, scale: 0.92)
    }

    override func refresh() {
        let fill: NSColor = filled ? NoteTheme.accent : NSColor(white: 0.05, alpha: 0.55)
        let ink: NSColor = filled ? NoteTheme.adaptive("Media.PlayInk", light: .white, dark: NoteTheme.rgb(0x120F2E)) : .white
        NoteMediaMotion.instant {
            layer?.opacity = isEnabled ? 1 : 0.25
            disc.backgroundColor = NoteMediaStyle.cg(fill, in: self)
            disc.shadowOpacity = filled ? 0 : 0.18
            if let image = NoteMediaStyle.symbol(symbolName, size: diameter * 0.36, weight: .bold) {
                glyph.contents = NoteMediaStyle.tinted(image, ink, in: self)
            }
        }
    }
}

@MainActor
final class NoteVideoContentView: NoteMediaContentView {
    private let poster = CALayer()
    private let shimmer = NoteMediaShimmer()
    private let playButton = NoteMediaPlayButton()
    private let ring = CALayer()
    private let toolbar = NoteMediaToolbar()
    private let captionChip = NoteToolbarButton(icon: .symbol("text.below.photo"), label: "Caption")
    private let replaceChip = NoteToolbarButton(icon: .symbol("arrow.triangle.2.circlepath"), label: "Replace")
    private let downloadChip = NoteToolbarButton(icon: .symbol("arrow.down.to.line"), label: "Download")
    private let deleteChip = NoteToolbarButton(icon: .symbol("trash"), label: "Delete")
    private var playerView: AVPlayerView?
    private var source: NoteMediaSource = .empty
    private var props = NoteBlockProps()
    private var natural: CGSize?
    private var posterRequested = false
    private var hovered = false

    override init(host: NoteMediaBlockView) {
        super.init(host: host)
        poster.contentsGravity = .resizeAspectFill
        poster.masksToBounds = true
        poster.cornerRadius = NoteMediaStyle.imageRadius
        poster.cornerCurve = .continuous
        poster.backgroundColor = NSColor.black.cgColor
        poster.opacity = 0
        ring.cornerRadius = NoteMediaStyle.imageRadius + 2
        ring.cornerCurve = .continuous
        ring.borderWidth = 2
        ring.isHidden = true
        layer?.addSublayer(poster)
        layer?.addSublayer(ring)
        addSubview(shimmer)
        playButton.onPress = { [weak self] in self?.play() }
        playButton.setAccessibilityLabel("Play video")
        addSubview(playButton)
        captionChip.onPress = { [weak self] in self?.host?.revealCaption() }
        replaceChip.onPress = { [weak self] in self?.host?.replace() }
        downloadChip.onPress = { [weak self] in self?.host?.download() }
        deleteChip.onPress = { [weak self] in self?.host?.deleteBlock() }
        addSubview(toolbar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func update(block: NoteBlock, source: NoteMediaSource) {
        if source != self.source {
            self.source = source
            stop()
            posterRequested = false
            natural = source.url.flatMap { NoteMediaAssets.cachedFacts($0)?.naturalSize }
            if let url = source.url, let cached = NoteMediaAssets.cachedPoster(url) {
                NoteMediaMotion.instant { poster.contents = cached; poster.opacity = 1 }
                shimmer.isHidden = true
            }
            loadFacts()
        }
        props = block.props
        configureToolbar()
        needsLayout = true
    }

    override func rebind(to source: NoteMediaSource) {
        guard playerView != nil || shimmer.isHidden else { return }
        self.source = source
    }

    private func loadFacts() {
        guard let url = source.url else { return }
        let expected = source
        NoteMediaAssets.loadFacts(url) { [weak self] facts in
            guard let self, self.source == expected else { return }
            if let problem = facts.problem { self.host?.contentDidFail(problem); return }
            if let size = facts.naturalSize, size != self.natural {
                self.natural = size
                self.host?.invalidateMeasuredHeight()
            }
            self.requestPoster()
        }
    }

    private func requestPoster() {
        guard !posterRequested, let url = source.url, bounds.width > 0 else { return }
        posterRequested = true
        let expected = source
        let pixels = NoteMediaImageLoader.pixels(for: videoRect.size, scale: window?.backingScaleFactor ?? 2)
        NoteMediaAssets.loadPoster(url, maxPixels: pixels) { [weak self] image in
            guard let self, self.source == expected else { return }
            self.shimmer.isHidden = true
            guard let image else { return }
            NoteMediaMotion.instant { self.poster.contents = image }
            if self.poster.opacity == 0 { NoteMediaMotion.fadeIn(self.poster) }
        }
    }

    private var editable: Bool { host?.canEdit == true }

    private func rect(for column: CGFloat) -> NSRect {
        let width = NoteMediaLayout.displayWidth(fraction: props.width ?? 1, natural: nil, columnWidth: column)
        let height = NoteMediaLayout.displayHeight(width: width, natural: natural)
        return NSRect(x: NoteMediaLayout.originX(width: width, alignment: props.alignment, columnWidth: column), y: 0, width: width, height: height)
    }

    private var videoRect: NSRect { rect(for: bounds.width) }

    override func measureHeight(width: CGFloat) -> CGFloat { rect(for: width).height }

    override func captionSpan(width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let frame = rect(for: width)
        return (frame.minX, frame.width)
    }

    override func layout() {
        super.layout()
        let frame = videoRect
        NoteMediaMotion.instant {
            poster.frame = frame
            ring.frame = frame.insetBy(dx: -3, dy: -3)
            ring.borderColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
        }
        shimmer.frame = frame
        playButton.frame = NSRect(x: frame.midX - 40, y: frame.midY - 40, width: 80, height: 80)
        playerView?.frame = frame
        let width = toolbar.fittingWidth
        toolbar.frame = NSRect(x: max(0, frame.maxX - 8 - width), y: frame.minY + 8, width: width, height: NoteMediaToolbar.height)
        if let url = source.url, NoteMediaAssets.cachedFacts(url)?.playable == true { requestPoster() }
    }

    private func configureToolbar() {
        var chips: [NoteControlButton] = []
        if editable {
            if host?.captionVisible != true { chips.append(captionChip) }
            chips.append(replaceChip)
        }
        chips.append(downloadChip)
        if editable { chips.append(deleteChip) }
        toolbar.setButtons(chips)
    }

    override func setHovered(_ hovered: Bool) {
        self.hovered = hovered
        if hovered && playerView == nil {
            configureToolbar()
            layoutSubtreeIfNeeded()
            toolbar.show()
        } else {
            toolbar.hide()
        }
    }

    override func setSelected(_ selected: Bool) {
        NoteMediaMotion.instant { ring.isHidden = !selected }
    }

    override func readOnlyDidChange() { configureToolbar() }

    private func play() {
        guard playerView == nil, let url = source.url else { return }
        let view = AVPlayerView(frame: videoRect)
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = .resizeAspect
        view.wantsLayer = true
        view.layer?.cornerRadius = NoteMediaStyle.imageRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        let player = AVPlayer(url: url)
        view.player = player
        addSubview(view, positioned: .below, relativeTo: toolbar)
        playerView = view
        playButton.isHidden = true
        toolbar.hideImmediately()
        if let layer = view.layer { NoteMediaMotion.fadeIn(layer, duration: 0.15) }
        player.play()
    }

    private func stop() {
        playerView?.player?.pause()
        playerView?.player = nil
        playerView?.removeFromSuperview()
        playerView = nil
        playButton.isHidden = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { playerView?.player?.pause() }
    }

    override func mouseDown(with event: NSEvent) {
        if playerView == nil, videoRect.contains(convert(event.locationInWindow, from: nil)) {
            if event.clickCount >= 2 { play(); return }
            if host?.selectBlock(with: event) == true { return }
        }
        super.mouseDown(with: event)
    }
}

@MainActor
final class NoteAudioContentView: NoteMediaCardView {
    private let playButton = NoteMediaPlayButton()
    private let name: NSTextField
    private let time: NSTextField
    private let scrubber = NoteMediaScrubber()
    private let captionChip = NoteToolbarButton(icon: .symbol("text.below.photo"), label: "Caption")
    private let replaceChip = NoteToolbarButton(icon: .symbol("arrow.triangle.2.circlepath"), label: "Replace")
    private let downloadChip = NoteToolbarButton(icon: .symbol("arrow.down.to.line"), label: "Download")
    private let deleteChip = NoteToolbarButton(icon: .symbol("trash"), label: "Delete")
    private var source: NoteMediaSource = .empty
    private var props = NoteBlockProps()
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var duration: Double?
    private var position: Double = 0
    private var hovered = false
    private static let height: CGFloat = 62

    override init(host: NoteMediaBlockView) {
        name = NoteMediaStyle.label("", font: NoteMediaStyle.nunito(14, weight: .bold), color: NoteTheme.ink)
        name.lineBreakMode = .byTruncatingMiddle
        time = NoteMediaStyle.label("0:00", font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium), color: NoteTheme.tertiaryInk)
        time.alignment = .right
        super.init(host: host)
        playButton.diameter = 34
        playButton.filled = true
        playButton.onPress = { [weak self] in self?.togglePlayback() }
        playButton.setAccessibilityLabel("Play")
        scrubber.onScrub = { [weak self] fraction, finished in self?.scrub(to: fraction, finished: finished) }
        captionChip.onPress = { [weak self] in self?.host?.revealCaption() }
        replaceChip.onPress = { [weak self] in self?.host?.replace() }
        downloadChip.onPress = { [weak self] in self?.host?.download() }
        deleteChip.onPress = { [weak self] in self?.host?.deleteBlock() }
        for view in [playButton, name, time, scrubber, captionChip, replaceChip, downloadChip, deleteChip] as [NSView] { addSubview(view) }
        setChipsVisible(false)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    override func measureHeight(width: CGFloat) -> CGFloat { Self.height }
    override var handleAnchorY: CGFloat { Self.height / 2 }

    override func update(block: NoteBlock, source: NoteMediaSource) {
        if source != self.source {
            self.source = source
            teardown()
            position = 0
            duration = source.url.flatMap { NoteMediaAssets.cachedFacts($0)?.duration }
            name.stringValue = source.fileName
            if let url = source.url {
                let expected = source
                NoteMediaAssets.loadFacts(url) { [weak self] facts in
                    guard let self, self.source == expected else { return }
                    if let problem = facts.problem { self.host?.contentDidFail(problem); return }
                    self.duration = facts.duration
                    self.refreshTime()
                }
            }
        }
        props = block.props
        refreshTime()
        needsLayout = true
    }

    private var editable: Bool { host?.canEdit == true }

    override func layout() {
        super.layout()
        let height = bounds.height
        playButton.frame = NSRect(x: 12, y: (height - 40) / 2, width: 40, height: 40)
        var trailing = bounds.width - 12
        for chip in [deleteChip, downloadChip, replaceChip, captionChip] where !chip.isHidden {
            let size = chip.intrinsicContentSize
            chip.frame = NSRect(x: trailing - size.width, y: 21 - size.height / 2, width: size.width, height: size.height)
            trailing = chip.frame.minX - 2
        }
        let timeWidth: CGFloat = 92
        time.frame = NSRect(x: trailing - timeWidth - 4, y: 13, width: timeWidth, height: 16)
        name.frame = NSRect(x: 62, y: 11, width: max(0, time.frame.minX - 70), height: 20)
        scrubber.frame = NSRect(x: 62, y: 36, width: max(0, bounds.width - 62 - 14), height: 16)
    }

    override func setHovered(_ hovered: Bool) {
        self.hovered = hovered
        cardHovered = hovered
        setChipsVisible(hovered)
        scrubber.showsKnob = hovered || player?.rate ?? 0 > 0
        needsLayout = true
    }

    override func readOnlyDidChange() { setChipsVisible(hovered) }

    private func setChipsVisible(_ visible: Bool) {
        captionChip.isHidden = !(visible && editable && host?.captionVisible != true)
        replaceChip.isHidden = !(visible && editable)
        downloadChip.isHidden = !visible
        deleteChip.isHidden = !(visible && editable)
    }

    private func ensurePlayer() -> AVPlayer? {
        if let player {
            observeTime(of: player)
            return player
        }
        guard let url = source.url else { return nil }
        let created = AVPlayer(url: url)
        created.actionAtItemEnd = .pause
        observeTime(of: created)
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: created.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.position = 0
                self.player?.seek(to: .zero)
                self.refreshPlayback()
            }
        }
        player = created
        return created
    }

    private func observeTime(of player: AVPlayer) {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self, weak player] now in
            MainActor.assumeIsolated {
                guard let self, !self.scrubber.isTracking else { return }
                self.position = now.seconds.isFinite ? now.seconds : 0
                if let total = player?.currentItem?.duration, total.isNumeric, total.seconds > 0 { self.duration = total.seconds }
                self.refreshTime()
            }
        }
    }

    private func stopObservingTime() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    private func togglePlayback() {
        guard let player = ensurePlayer() else { return }
        if player.rate > 0 { player.pause() } else { player.play() }
        refreshPlayback()
    }

    private func refreshPlayback() {
        let playing = (player?.rate ?? 0) > 0
        playButton.symbolName = playing ? "pause.fill" : "play.fill"
        playButton.setAccessibilityLabel(playing ? "Pause" : "Play")
        scrubber.showsKnob = hovered || playing
        playButton.needsLayout = true
    }

    private func scrub(to fraction: Double, finished: Bool) {
        guard let duration, duration > 0 else { return }
        position = duration * fraction
        refreshTime()
        guard let player = ensurePlayer() else { return }
        let target = CMTime(seconds: position, preferredTimescale: 600)
        if finished {
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: target, toleranceBefore: CMTime(seconds: 0.2, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.2, preferredTimescale: 600))
        }
    }

    private func refreshTime() {
        let total = duration ?? 0
        time.stringValue = total > 0 ? NoteMediaFormat.duration(position) + " / " + NoteMediaFormat.duration(total) : NoteMediaFormat.duration(position)
        scrubber.fraction = total > 0 ? min(1, max(0, position / total)) : 0
        scrubber.setAccessibilityValueDescription(NoteMediaFormat.duration(position) + " of " + NoteMediaFormat.duration(total))
    }

    private func teardown() {
        stopObservingTime()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        refreshPlayback()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window == nil else { return }
        player?.pause()
        stopObservingTime()
        refreshPlayback()
    }
}

@MainActor
final class NoteMediaScrubber: NSView {
    private let track = CALayer()
    private let progress = CALayer()
    private let knob = CALayer()
    var fraction: Double = 0 { didSet { needsLayout = true; setAccessibilityValue(fraction) } }
    var showsKnob = false { didSet { if oldValue != showsKnob { NoteMediaMotion.instant { knob.opacity = showsKnob ? 1 : 0 } } } }
    var onScrub: ((Double, Bool) -> Void)?
    private(set) var isTracking = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for part in [track, progress] {
            part.cornerRadius = 2
            part.cornerCurve = .continuous
            layer?.addSublayer(part)
        }
        knob.cornerRadius = 6
        knob.shadowOpacity = 0.2
        knob.shadowRadius = 2
        knob.shadowOffset = CGSize(width: 0, height: -1)
        knob.shadowColor = NSColor.black.cgColor
        knob.opacity = 0
        layer?.addSublayer(knob)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Playback position")
        setAccessibilityMinValue(0)
        setAccessibilityMaxValue(1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let y = (bounds.height - 4) / 2
        let width = bounds.width * CGFloat(fraction)
        NoteMediaMotion.instant {
            track.frame = NSRect(x: 0, y: y, width: bounds.width, height: 4)
            progress.frame = NSRect(x: 0, y: y, width: width, height: 4)
            knob.frame = NSRect(x: min(max(0, width - 6), bounds.width - 12), y: (bounds.height - 12) / 2, width: 12, height: 12)
            track.backgroundColor = NoteMediaStyle.cg(NoteTheme.separator, in: self)
            progress.backgroundColor = NoteMediaStyle.cg(NoteTheme.accent, in: self)
            knob.backgroundColor = NoteMediaStyle.cg(NoteTheme.adaptive("Media.Knob", light: .white, dark: NoteTheme.rgb(0xEDEBFA)), in: self)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func value(for event: NSEvent) -> Double {
        guard bounds.width > 0 else { return 0 }
        return Double(min(max(0, convert(event.locationInWindow, from: nil).x / bounds.width), 1))
    }

    override func mouseDown(with event: NSEvent) {
        isTracking = true
        showsKnob = true
        fraction = value(for: event)
        onScrub?(fraction, false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTracking else { return }
        fraction = value(for: event)
        onScrub?(fraction, false)
    }

    override func mouseUp(with event: NSEvent) {
        guard isTracking else { return }
        isTracking = false
        fraction = value(for: event)
        onScrub?(fraction, true)
    }

    override func accessibilityPerformIncrement() -> Bool {
        fraction = min(1, fraction + 0.05)
        onScrub?(fraction, true)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        fraction = max(0, fraction - 0.05)
        onScrub?(fraction, true)
        return true
    }
}
