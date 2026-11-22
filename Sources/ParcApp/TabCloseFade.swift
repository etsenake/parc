import AppKit

@MainActor
final class TabCloseFade {
    let tabID: UUID
    private weak var page: NSView?
    private weak var startPage: NSView?
    private var transition = PeekCloseTransition()
    private var motion = PeekDismissalMotion()
    private let frames = ViewDisplayFrameDriver()
    private var sheetObserver: NSObjectProtocol?
    private var sheetEndObserver: NSObjectProtocol?
    private var focusReturn: PeekFocusReturn?
    private var restoring = false
    var now: () -> TimeInterval = { CACurrentMediaTime() }
    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, body in
        let timer = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { body() } }
        RunLoop.main.add(timer, forMode: .common)
    }
    var hop: (@escaping () -> Void) -> Void = { work in DispatchQueue.main.async { work() } }
    var passesInput: ((Bool) -> Void)?
    var returnFocus: ((NSResponder?) -> Void)?
    var onRequestClose: (() -> Void)?
    var onRestored: (() -> Void)?

    init(tabID: UUID, page: NSView, startPage: NSView) {
        self.tabID = tabID
        self.page = page
        self.startPage = startPage
    }

    var phase: PeekCloseTransition.Phase { transition.phase }
    var isClosing: Bool { phase == .exiting || phase == .closing }

    func begin() {
        guard phase == .resting else { return }
        restoring = false
        if let page, let window = page.window {
            focusReturn = PeekFocusReturn(source: page)
            focusReturn?.lend(in: window) { false }
            if sheetObserver == nil {
                sheetObserver = NotificationCenter.default.addObserver(forName: NSWindow.willBeginSheetNotification,
                                                                       object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sheetBegan() }
                }
            }
        }
        passesInput?(true)
        apply(transition.close(visible: true, exit: .fade))
    }

    func sheetBegan() {
        apply(transition.sheetBegan(visible: true))
    }

    func refused() {
        guard phase == .closing else { return }
        restoring = true
        passesInput?(false)
        returnFocusWhenClear()
        let effects = transition.refused(visible: true)
        if effects.isEmpty { run() } else { apply(effects) }
    }

    func interrupt() {
        let effects = transition.hide()
        apply(effects.filter { $0 != .requestClose })
        if effects.contains(.requestClose), let request = onRequestClose {
            hop { request() }
        }
    }

    func finish() {
        apply(transition.finish())
        paint()
        end()
    }

    func handOff() {
        if phase == .exiting { interrupt() }
        if phase != .finished { finish() }
    }

    func end() {
        frames.stop()
        if phase == .resting { motion.settle(); paint() }
        if let sheetObserver { NotificationCenter.default.removeObserver(sheetObserver) }
        sheetObserver = nil
        stopWaitingForSheetEnd()
        focusReturn?.cancel(); focusReturn = nil
        onRequestClose = nil; onRestored = nil; returnFocus = nil
        passesInput?(false); passesInput = nil
    }

    func paint() {
        let card = CGFloat(motion.frame(at: now()).card)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        page?.alphaValue = card
        startPage?.alphaValue = 1 - card
        CATransaction.commit()
    }

    private func apply(_ effects: [PeekCloseTransition.Effect]) {
        for effect in effects {
            switch effect {
            case let .exit(kind, _, _, generation):
                let duration = motion.exit(kind, velocity: 0, reducesMotion: reducesMotion(), at: now())
                run()
                schedule(duration) { [weak self] in
                    guard let self else { return }
                    self.apply(self.transition.exitFinished(generation))
                }
            case .requestClose:
                onRequestClose?()
            case .vanish:
                frames.stop(); motion.vanish(at: now()); paint()
            case .reappear:
                motion.reappear(reducesMotion: reducesMotion(), at: now()); run()
            case .settle:
                frames.stop(); motion.settle(); paint(); settled()
            case .follow, .haptic, .springBack, .cancelClose:
                break
            }
        }
    }

    private func run() {
        paint()
        guard motion.isAnimating(at: now()) else { settled(); return }
        guard let page, page.window != nil else { return }
        frames.start(in: page) { [weak self] in
            guard let self else { return false }
            self.paint()
            guard self.motion.isAnimating(at: self.now()) else { self.settled(); return false }
            return true
        }
    }

    func settled() {
        guard restoring, phase == .resting, sheetEndObserver == nil, !motion.isAnimating(at: now()) else { return }
        restoring = false
        onRestored?()
    }

    private func returnFocusWhenClear() {
        guard let pending = focusReturn, let window = page?.window else { focusReturn = nil; settled(); return }
        guard window.attachedSheet == nil else {
            guard sheetEndObserver == nil else { return }
            sheetEndObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification,
                                                                      object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.retryAfterSheetEnded(attempts: 10, delay: 0) }
            }
            return
        }
        stopWaitingForSheetEnd()
        focusReturn = nil
        let restore = returnFocus
        pending.perform(in: window, ownerIsAvailable: { [weak page] in page?.window === window }) { responder in
            if let restore { restore(responder) } else { window.makeFirstResponder(responder) }
        }
        settled()
    }

    private func retryAfterSheetEnded(attempts: Int, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.sheetEndObserver != nil else { return }
                guard self.page?.window?.attachedSheet == nil || attempts <= 1 else {
                    self.retryAfterSheetEnded(attempts: attempts - 1, delay: 0.05)
                    return
                }
                self.stopWaitingForSheetEnd()
                self.returnFocusWhenClear()
            }
        }
    }

    private func stopWaitingForSheetEnd() {
        if let sheetEndObserver { NotificationCenter.default.removeObserver(sheetEndObserver) }
        sheetEndObserver = nil
    }
}
