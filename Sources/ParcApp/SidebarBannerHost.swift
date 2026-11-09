import AppKit
import SwiftUI

///
/// SidebarBanner slot, used by the auto-archive education and Update Complete
///
/// + opacity, with a 0.6/0.4 spring on entry and 0.25-second ease-in on exit.
/// The shared reducer retains the dismissing banner for 0.7 seconds. See
/// docs/archive.md (AUTO12) and docs/software-update.md.
@MainActor
final class SidebarBannerHost: NSView {
    enum Phase: Equatable { case absent, initial, appeared, dismissing }
    static let dismissalLifetime: TimeInterval = 0.7

    private final class Presentation: ObservableObject {
        @Published var phase = Phase.absent
        @Published var height: CGFloat = 0
        @Published var interactive = false
        @Published var motionRevision: UInt64 = 0
    }
    private struct Card: NSViewRepresentable {
        let view: NSView
        func makeNSView(context: Context) -> NSView { view }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }
    private struct Content: View {
        @ObservedObject var presentation: Presentation
        let card: NSView
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            ZStack(alignment: .bottom) {
                if presentation.phase == .appeared {
                    Card(view: card)
                        .frame(height: presentation.height)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(presentation.interactive)
                }
            }
            .id(presentation.motionRevision)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(reduceMotion ? nil : (presentation.phase == .dismissing
                ? .easeIn(duration: 0.25)
                : .spring(response: 0.6, dampingFraction: 0.4, blendDuration: 0)), value: presentation.phase)
        }
    }

    let card: NSView
    var onLayoutChanged: (() -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?
    /// Called before removing a card that actually owns the first responder.
    /// It must not activate a window or restore an old page selection.
    var onRelinquishFocus: (() -> Void)?
    private let presentation = Presentation()
    private var hosting: NSHostingView<Content>!
    private var desiredVisible = false
    private var permitsInteraction = true
    private var generation: UInt64 = 0
    private var scheduled: DispatchWorkItem?
    private var accessibilityObserver: NSObjectProtocol?
    var phase: Phase { presentation.phase }
    var occupiesSpace: Bool { phase != .absent }
    /// Asked to show (not leaving): the slot sizes to this card first.
    var isShowing: Bool { desiredVisible }
    var isInteractive: Bool { presentation.interactive }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    init(card: NSView) {
        self.card = card
        super.init(frame: .zero)
        hosting = NSHostingView(rootView: Content(presentation: presentation, card: card))
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        isHidden = true
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                self.settle()
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        scheduled?.cancel()
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }

    func show(_ visible: Bool) {
        guard desiredVisible != visible else { return }
        desiredVisible = visible
        invalidateScheduled()
        if visible {
            isHidden = false
            setPhase(.initial, animated: false)
            onLayoutChanged?()
            scheduleAppearance()
        } else {
            relinquishFocusIfOwned()
            guard phase != .absent else { return }
            guard window != nil, phase == .appeared,
                  !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { finishDismissal(); return }
            setPhase(.dismissing)
            let token = generation
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.generation == token, !self.desiredVisible else { return }
                self.scheduled = nil
                self.finishDismissal()
            }
            scheduled = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.dismissalLifetime, execute: work)
        }
    }

    func setInteractionAllowed(_ allowed: Bool) {
        guard permitsInteraction != allowed else { return }
        if !allowed { relinquishFocusIfOwned() }
        permitsInteraction = allowed
        updateInteraction()
    }

    /// Window destruction and replacement invalidate both delayed entry and
    /// exit. An old completion never removes a newer card.
    func reset() {
        desiredVisible = false
        invalidateScheduled()
        relinquishFocusIfOwned()
        finishDismissal()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidateScheduled()
        if window == nil {
            setPhase(.absent, animated: false)
            isHidden = true
        } else if desiredVisible {
            isHidden = false
            setPhase(.initial, animated: false)
            onLayoutChanged?()
            scheduleAppearance()
        } else { finishDismissal() }
    }

    override func layout() {
        super.layout()
        hosting.frame = bounds
        if presentation.height != bounds.height { presentation.height = bounds.height }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        isInteractive ? super.hitTest(point) : nil
    }

    private func scheduleAppearance() {
        guard window != nil, desiredVisible, phase == .initial else { return }
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.window != nil,
                  self.desiredVisible, self.phase == .initial else { return }
            self.scheduled = nil
            // The native sidebar establishes this card's measured slot before
            // SwiftUI starts its bottom-edge insertion.
            self.superview?.layoutSubtreeIfNeeded()
            self.layoutSubtreeIfNeeded()
            self.setPhase(.appeared)
            self.onLayoutChanged?()
        }
        scheduled = work
        //
        DispatchQueue.main.async(execute: work)
    }
    private func setPhase(_ phase: Phase, animated: Bool = true) {
        if animated { presentation.phase = phase }
        else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                presentation.motionRevision &+= 1
                presentation.phase = phase
            }
        }
        updateInteraction()
    }
    private func updateInteraction() {
        let enabled = permitsInteraction && phase == .appeared && desiredVisible && window != nil
        guard presentation.interactive != enabled else { return }
        presentation.interactive = enabled
        onInteractionChanged?(enabled)
    }
    private func relinquishFocusIfOwned() {
        guard let responder = window?.firstResponder as? NSView, responder.isDescendant(of: self) else { return }
        onRelinquishFocus?()
    }
    private func invalidateScheduled() { generation &+= 1; scheduled?.cancel(); scheduled = nil }
    private func finishDismissal() {
        setPhase(.absent, animated: false)
        isHidden = true
        onLayoutChanged?()
    }
    private func settle() {
        invalidateScheduled()
        if desiredVisible, window != nil { setPhase(.appeared, animated: false) }
        else { finishDismissal() }
    }
}
