import AppKit
import ParcCore
import QuartzCore
import ParcKit
import ParcNotes

extension Notification.Name {
    static let easelTimerChanged = Notification.Name("ParcEaselTimerChanged")
    static let easelTimerFinished = Notification.Name("ParcEaselTimerFinished")
}

@MainActor
final class EaselTimers {
    static let shared = EaselTimers()
    private var timers: [UUID: EaselCountdown] = [:]
    private var ticker: Timer?
    private var announced: Set<UUID> = []
    private var buttons: [UUID: [WeakButton]] = [:]
    var now: () -> Date = Date.init

    private struct WeakButton { weak var button: EaselTimerButton? }

    private init() {
        NotificationCenter.default.addObserver(forName: .easelDocumentRemoved, object: nil, queue: .main) { notification in
            guard let id = notification.object as? UUID else { return }
            MainActor.assumeIsolated { EaselTimers.shared.forget(id) }
        }
    }

    func attach(_ button: EaselTimerButton) {
        let id = button.documentID
        var list = (buttons[id] ?? []).filter { $0.button != nil }
        if !list.contains(where: { $0.button === button }) { list.append(WeakButton(button: button)) }
        buttons[id] = list
    }

    func detach(_ button: EaselTimerButton) { prune(button.documentID, removing: button) }

    func detachDocument(_ id: UUID) { prune(id, removing: nil) }

    private func prune(_ id: UUID, removing button: EaselTimerButton?) {
        let list = (buttons[id] ?? []).filter { $0.button != nil && $0.button !== button }
        buttons[id] = list.isEmpty ? nil : list
        if list.isEmpty, announced.contains(id), countdown(for: id).phase == .finished { forget(id) }
    }

    private func announce(_ id: UUID) {
        let candidates = (buttons[id] ?? []).compactMap(\.button).filter(\.canAnnounce)
        guard let chosen = candidates.first(where: { $0.window?.isKeyWindow == true }) ?? candidates.first else { return }
        announced.insert(id)
        chosen.onFinished?()
    }

    func countdown(for id: UUID) -> EaselCountdown { timers[id] ?? EaselCountdown() }

    func update(_ id: UUID, _ change: (inout EaselCountdown, Date) -> Void) {
        var countdown = countdown(for: id)
        let before = countdown
        change(&countdown, now())
        guard countdown != before else { return }
        timers[id] = countdown
        announced.remove(id)
        NotificationCenter.default.post(name: .easelTimerChanged, object: id)
        refreshTicker()
    }

    func forget(_ id: UUID) {
        announced.remove(id)
        guard timers.removeValue(forKey: id) != nil else { return }
        NotificationCenter.default.post(name: .easelTimerChanged, object: id)
        refreshTicker()
    }

    private func refreshTicker() {
        let running = timers.values.contains { $0.phase == .running }
        if running, ticker == nil {
            let ticker = Timer(timeInterval: 0.25, repeats: true) { _ in
                MainActor.assumeIsolated { EaselTimers.shared.tick() }
            }
            ticker.tolerance = 0.05
            RunLoop.main.add(ticker, forMode: .common)
            self.ticker = ticker
        } else if !running {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func tick() {
        let date = now()
        for (id, countdown) in Array(timers) where countdown.phase == .running {
            if countdown.isDue(at: date) {
                var finished = countdown
                finished.finish()
                timers[id] = finished
                announced.remove(id)
                NotificationCenter.default.post(name: .easelTimerChanged, object: id)
                NotificationCenter.default.post(name: .easelTimerFinished, object: id)
                announce(id)
            } else {
                NotificationCenter.default.post(name: .easelTimerChanged, object: id)
            }
        }
        refreshTicker()
    }
}

@MainActor
final class EaselTimerButton: PointingHandButton {
    let documentID: UUID
    var onFinished: (() -> Void)?
    private var shown = ""
    private var phase: EaselCountdown.Phase = .idle
    private var pointerInside = false
    private let readout = EaselRollingText()
    private var hoverTracking: NSTrackingArea?
    private static let pauseKey = NoteAnimation.keyPrefix + "easel.timer.pause"
    private let glyph = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timer")?
        .withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) ?? NSImage()

    init(documentID: UUID) {
        self.documentID = documentID
        super.init(frame: NSRect(x: 0, y: 0, width: NoteTheme.toolbarButtonSize.width, height: NoteTheme.toolbarButtonSize.height))
        isBordered = false
        focusRingType = .exterior
        title = ""
        wantsLayer = true
        setEaselTooltip("Timer")
        setAccessibilityRole(.button)
        readout.alignment = .left
        addSubview(readout)
        let center = NotificationCenter.default
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(motionPreferenceChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(timerChanged(_:)), name: .easelTimerChanged, object: nil)
        center.addObserver(self, selector: #selector(timerFinished(_:)), name: .easelTimerFinished, object: nil)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        let id = documentID
        MainActor.assumeIsolated { EaselTimers.shared.detachDocument(id) }
    }

    @objc private func motionPreferenceChanged() {
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        if let layer { NoteAnimation.settle(layer) }
        readout.settle()
        EaselControlSurface.clearGlow(self)
        placePauseLook(from: phase, animated: false)
    }

    @objc private func timerChanged(_ notification: Notification) {
        guard notification.object as? UUID == documentID else { return }
        refresh()
    }

    @objc private func timerFinished(_ notification: Notification) {
        guard notification.object as? UUID == documentID else { return }
        finished()
    }

    var showsTime: Bool { phase != .idle }

    var canAnnounce: Bool {
        guard let window, window.isVisible else { return false }
        return !isHiddenOrHasHiddenAncestor
    }

    private var timeFont: NSFont { Self.monospacedDigits(NoteTheme.chromeFont(13)) }

    static func monospacedDigits(_ base: NSFont) -> NSFont {
        let descriptor = base.fontDescriptor.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
        ]]])
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    override var intrinsicContentSize: NSSize {
        let side = NoteTheme.toolbarButtonSize.width
        guard showsTime else { return NSSize(width: side, height: NoteTheme.toolbarButtonSize.height) }
        let text = ceil(("00:00" as NSString).size(withAttributes: [.font: timeFont]).width)
        return NSSize(width: side + text + 6, height: NoteTheme.toolbarButtonSize.height)
    }

    func refresh() {
        let countdown = EaselTimers.shared.countdown(for: documentID)
        let remaining = countdown.remaining(at: EaselTimers.shared.now())
        let label = EaselCountdown.label(remaining)
        let resized = (countdown.phase == .idle) != (phase == .idle)
        let previousPhase = phase
        phase = countdown.phase
        shown = label
        readout.update(text: label, font: timeFont, color: phase == .paused ? NoteTheme.menuSecondaryInk : activeInk,
                       animated: !resized && showsTime)
        readout.isHidden = !showsTime
        if previousPhase == .finished, phase != .finished { EaselControlSurface.clearFinish(self, shaking: layer) }
        if previousPhase != phase || resized { placePauseLook(from: previousPhase, animated: !resized) }
        if resized { invalidateIntrinsicContentSize(); superview?.needsLayout = true; onResize?() }
        switch phase {
        case .idle: setAccessibilityValue(nil)
        case .running: setAccessibilityValue("Running, " + EaselCountdown.spoken(remaining) + " left")
        case .paused: setAccessibilityValue("Paused, " + EaselCountdown.spoken(remaining) + " left")
        case .finished: setAccessibilityValue("Time’s up")
        }
        setAccessibilityLabel("Timer")
        needsDisplay = true
    }

    var onResize: (() -> Void)?

    private func finished() {
        refresh()
        guard phase == .finished, window != nil, !isHiddenOrHasHiddenAncestor, let layer else { return }
        EaselControlSurface.shake(layer)
        EaselControlSurface.glow(self, color: NoteTheme.accent)
    }

    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hoverChanged(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged(false) }

    private func hoverChanged(_ inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        needsDisplay = true
        refreshReadoutColor()
        EaselControlSurface.crossfade(self, duration: NoteAnimation.hoverDuration, pops: nil)
    }

    private func refreshReadoutColor() {
        readout.update(text: shown, font: timeFont, color: phase == .paused ? NoteTheme.menuSecondaryInk : activeInk, animated: false)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pointerInside = false
        if window == nil { EaselTimers.shared.detach(self) } else { EaselTimers.shared.attach(self) }
        refresh()
    }

    override func layout() {
        super.layout()
        let side = NoteTheme.toolbarButtonSize.width
        readout.frame = NSRect(x: side - 4, y: 0, width: max(0, bounds.width - side + 4), height: bounds.height)
    }

    private func placePauseLook(from previous: EaselCountdown.Phase, animated: Bool) {
        guard let layer = readout.layer else { return }
        let resting: Float = phase == .paused ? 0.55 : 1
        NoteAnimation.settle(layer, keys: [Self.pauseKey])
        guard animated, window != nil, previous != phase else {
            NoteAnimation.withoutAnimation { layer.opacity = resting }
            return
        }
        if phase == .paused, previous == .running {
            EaselControlSurface.blink(layer, resting: resting, key: Self.pauseKey)
        } else {
            NoteAnimation.fade(layer, to: resting, duration: 0.2, key: Self.pauseKey)
        }
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override var state: NSControl.StateValue { didSet { needsDisplay = true; refreshReadoutColor() } }

    override func highlight(_ flag: Bool) {
        let released = !flag && isHighlighted
        super.highlight(flag)
        needsDisplay = true
        refreshReadoutColor()
        EaselControlSurface.apply(self, hovered: false, pressed: flag, released: released, casts: false)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = NoteTheme.controlRadius
        let fill: NSColor? = state != .off ? NoteTheme.checkedFill : isHighlighted ? NoteTheme.pressedFill
            : pointerInside ? NoteTheme.hoverFill : phase == .finished ? NoteTheme.checkedFill : nil
        if let fill {
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        let ink = activeInk
        let side = NoteTheme.toolbarButtonSize.width
        let size = glyph.size
        let factor = min(1, 20 / max(1, size.width), 20 / max(1, size.height))
        let box = NSRect(x: ((side - size.width * factor) / 2).rounded(), y: ((bounds.height - size.height * factor) / 2).rounded(),
                         width: size.width * factor, height: size.height * factor)
        let tinted = NSImage(size: box.size, flipped: false) { [glyph] rect in
            glyph.draw(in: rect)
            ink.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: box)
    }

    private var activeInk: NSColor {
        let active = phase == .running || phase == .finished
        return state != .off || active ? NoteTheme.accent : isHighlighted || pointerInside ? NoteTheme.menuInk : NoteTheme.menuSecondaryInk
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: NoteTheme.controlRadius, yRadius: NoteTheme.controlRadius).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds }
}

@MainActor
final class EaselTimerView: NSView, NoteFloatingPanelContent {
    static let width: CGFloat = 248
    let documentID: UUID
    var preferredSizeDidChange: (() -> Void)?
    var onClose: (() -> Void)?
    private let clock = EaselRollingText()
    private var lastPhase: EaselCountdown.Phase?
    private let caption = NSTextField(labelWithString: "")
    private let minus = NoteChip("", icon: .symbol("minus"))
    private let plus = NoteChip("", icon: .symbol("plus"))
    private let start = NoteChip("Start", icon: .symbol("play.fill"), style: .filled)
    private let addMinute = NoteChip("+1 min")
    private let reset = NoteChip("Reset", icon: .symbol("arrow.counterclockwise"))

    init(documentID: UUID) {
        self.documentID = documentID
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 168))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Timer")
        clock.alignment = .center
        clock.clips = true
        clock.setAccessibilityElement(true)
        clock.setAccessibilityRole(.staticText)
        caption.wantsLayer = true
        caption.font = NoteTheme.nunitoRegular(12)
        caption.textColor = NoteTheme.menuTertiaryInk
        caption.alignment = .center
        minus.setAccessibilityLabel("One minute less")
        minus.setToolTip("One minute less (↓, ⇧↓ for five)")
        plus.setAccessibilityLabel("One minute more")
        plus.setToolTip("One minute more (↑, ⇧↑ for five)")
        start.setToolTip("Start or pause (Space)")
        addMinute.setToolTip("Add a minute")
        minus.onPress = { [weak self] in self?.step(NSEvent.modifierFlags.contains(.shift) ? -5 : -1) }
        plus.onPress = { [weak self] in self?.step(NSEvent.modifierFlags.contains(.shift) ? 5 : 1) }
        start.onPress = { [weak self] in self?.toggle() }
        addMinute.onPress = { [weak self] in self?.change { $0.addMinute(at: $1) } }
        reset.onPress = { [weak self] in self?.change { countdown, _ in countdown.reset() } }
        for view in [clock, caption, minus, plus, start, addMinute, reset] { addSubview(view) }
        NotificationCenter.default.addObserver(self, selector: #selector(timerChanged(_:)), name: .easelTimerChanged, object: nil)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func timerChanged(_ notification: Notification) {
        guard notification.object as? UUID == documentID else { return }
        refresh()
    }

    override var isFlipped: Bool { true }
    override var fittingSize: NSSize { NSSize(width: Self.width, height: 168) }
    override var intrinsicContentSize: NSSize { fittingSize }

    override func layout() {
        super.layout()
        let width = bounds.width
        let clockHeight = ceil(clock.intrinsicContentSize.height) + 4
        let stepSize = NSSize(width: 34, height: NoteTheme.chipHeight)
        clock.frame = NSRect(x: 14 + stepSize.width, y: 14, width: width - 28 - 2 * stepSize.width, height: clockHeight)
        minus.frame = NSRect(x: 14, y: 14 + (clockHeight - stepSize.height) / 2, width: stepSize.width, height: stepSize.height)
        plus.frame = NSRect(x: width - 14 - stepSize.width, y: minus.frame.minY, width: stepSize.width, height: stepSize.height)
        caption.frame = NSRect(x: 14, y: clock.frame.maxY + 2, width: width - 28, height: 18)
        let row = caption.frame.maxY + 14
        let startWidth = max(84, start.intrinsicContentSize.width)
        start.frame = NSRect(x: 14, y: row, width: startWidth, height: NoteTheme.chipHeight)
        let addWidth = addMinute.intrinsicContentSize.width
        addMinute.frame = NSRect(x: start.frame.maxX + 6, y: row, width: addWidth, height: NoteTheme.chipHeight)
        let resetWidth = reset.intrinsicContentSize.width
        reset.frame = NSRect(x: width - 14 - resetWidth, y: row, width: resetWidth, height: NoteTheme.chipHeight)
    }

    private var countdown: EaselCountdown { EaselTimers.shared.countdown(for: documentID) }

    private func change(_ body: (inout EaselCountdown, Date) -> Void) {
        EaselTimers.shared.update(documentID, body)
    }

    func step(_ minutes: Int) { change { $0.adjust(minutes: minutes, at: $1) } }

    func toggle() { change { $0.toggle(at: $1) } }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let shift = flags == .shift
        guard flags.isEmpty || shift else { return false }
        switch event.keyCode {
        case 126: step(shift ? 5 : 1); return true
        case 125: step(shift ? -5 : -1); return true
        case 49, 36, 76:
            guard !shift else { return false }
            toggle(); return true
        case 53: onClose?(); return true
        default: break
        }
        guard !shift, let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if characters == "r" { change { countdown, _ in countdown.reset() }; return true }
        if characters == "=" || characters == "+" { change { $0.addMinute(at: $1) }; return true }
        return false
    }

    private func phaseChanged(from previous: EaselCountdown.Phase, to phase: EaselCountdown.Phase) {
        if previous == .finished, phase != .finished { EaselControlSurface.clearFinish(self, shaking: clock.layer) }
        guard window != nil, let layer = clock.layer else { return }
        switch (previous, phase) {
        case (.running, .paused): EaselControlSurface.blink(layer)
        case (.running, .finished):
            EaselControlSurface.shake(layer, distance: 7)
            EaselControlSurface.glow(self, color: NoteTheme.accent, radius: 14, around: clock.frame.insetBy(dx: 10, dy: 2))
        default: break
        }
    }

    private func refresh() {
        let countdown = self.countdown
        let remaining = countdown.remaining(at: EaselTimers.shared.now())
        let previous = lastPhase
        lastPhase = countdown.phase
        clock.update(text: EaselCountdown.label(remaining), font: EaselTimerButton.monospacedDigits(NoteTheme.nunitoExtraBold(40)),
                     color: countdown.phase == .running || countdown.phase == .finished ? NoteTheme.accent : NoteTheme.menuInk,
                     animated: window != nil)
        clock.setAccessibilityLabel(EaselCountdown.spoken(remaining))
        if let previous, previous != countdown.phase { phaseChanged(from: previous, to: countdown.phase) }
        let adjustable = countdown.phase == .idle || countdown.phase == .finished
        minus.isEnabled = adjustable && countdown.duration > 0
        plus.isEnabled = adjustable && countdown.duration < EaselCountdown.maximum
        addMinute.isEnabled = (countdown.phase == .running || countdown.phase == .paused)
            && remaining < EaselCountdown.maximum
        reset.isEnabled = countdown.phase != .idle
        let face: (title: String, symbol: String, caption: String)
        switch countdown.phase {
        case .idle: face = ("Start", "play.fill", "↑ ↓ for a minute, ⇧ for five")
        case .running: face = ("Pause", "pause.fill", "Just for you, not saved in the Easel")
        case .paused: face = ("Resume", "play.fill", "Paused")
        case .finished: face = ("Again", "play.fill", "Time’s up!")
        }
        if start.chipTitle != face.title {
            EaselControlSurface.morph(start) { start.chipTitle = face.title; start.icon = .symbol(face.symbol) }
        }
        if caption.stringValue != face.caption {
            caption.stringValue = face.caption
            EaselControlSurface.crossfade(caption, pops: nil)
        }
        start.isEnabled = countdown.phase != .idle || countdown.duration > 0
        start.setAccessibilityLabel(start.chipTitle)
        needsLayout = true
    }
}

@MainActor
enum EaselTimerPanel {
    private static var openPopover: NotePagePopover?

    static var isOpen: Bool { openPopover?.isOpen == true }

    static func toggle(editor: EaselEditorViewController, from button: EaselTimerButton) {
        if let openPopover, openPopover.isOpen { openPopover.close(); return }
        guard !editor.session.isClosed else { return }
        let view = EaselTimerView(documentID: button.documentID)
        let popover = NotePagePopover(content: view)
        popover.exempt(button)
        view.onClose = { [weak popover] in popover?.close() }
        popover.onKeyDown = { [weak view] event in view?.handleKeyDown(event) ?? false }
        popover.onClose = { [weak button] in
            openPopover = nil
            button?.state = .off
        }
        openPopover = popover
        button.state = .on
        let host = editor.view
        popover.present(in: host, anchor: host.convert(button.bounds, from: button), edge: .below, alignment: .trailing)
    }
}

@MainActor
extension EaselEditorViewController {
    func makeTimerButton() -> EaselTimerButton {
        let button = EaselTimerButton(documentID: session.document.id)
        button.target = self
        button.action = #selector(showTimer(_:))
        button.onFinished = { [weak self] in self?.timerFinished() }
        return button
    }

    @objc func showTimer(_ sender: Any?) {
        guard let button = sender as? EaselTimerButton else { return }
        EaselTimerPanel.toggle(editor: self, from: button)
    }

    private func timerFinished() {
        guard isViewLoaded, let window = view.window, window.isVisible, !view.isHiddenOrHasHiddenAncestor else { return }
        showExportToast(.standard("Time’s up", icon: "timer"))
        NSAccessibility.post(element: view, notification: .announcementRequested,
                             userInfo: [.announcement: "Time’s up", .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
