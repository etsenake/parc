import AppKit
import Combine
import ParcEngine
import ParcSettings

@MainActor
final class SharedQuoteController {
    private weak var page: PCNativePage?
    private weak var window: NSWindow?
    private var observation: PCNativeSharedQuoteObservation?
    private var monitor: Any?
    private var subscription: AnyCancellable?
    private let isCurrent: (PCNativePage) -> Bool
    private let session: SharedQuoteSession<PCNativeSharedQuoteSelection>
    private var draggingFromPage = false
    private var quotesEnabled = false
    init(isCurrent: @escaping (PCNativePage) -> Bool,
         display: @escaping (PCNativeSharedQuoteSelection?) -> Void) {
        self.isCurrent = isCurrent
        session = SharedQuoteSession(valid: { $0.canCopy }, schedule: { block in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200), execute: block)
        }, display: display)
        subscription = SharedQuotePreferences.shared.$state.sink { [weak self] state in
            guard let self else { return }
            let enabled = state.isEnabled && !SharedQuotePreferences.shared.loadError
            self.quotesEnabled = enabled
            self.session.setEnabled(enabled)
            self.updateMonitor()
        }
    }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
    func bind(_ page: PCNativePage?, window: NSWindow?) {
        guard self.page !== page || self.window !== window || observation == nil else { return }
        observation?.invalidate(); observation = nil
        self.page = page; self.window = window; draggingFromPage = false; session.reset()
        defer { updateMonitor() }
        guard let page, let window, page.nativeView.window === window else { return }
        observation = page.observeSharedQuoteSelection { [weak self, weak page] selection, reset in
            MainActor.assumeIsolated {
                guard let self, let page, self.page === page, self.isCurrent(page) else {
                    self?.session.reset(); return
                }
                self.session.receive(selection, reset: reset)
            }
        }
    }
    func invalidate() {
        observation?.invalidate(); observation = nil; page = nil; window = nil
        draggingFromPage = false; session.reset()
        updateMonitor()
    }
    func canPerform(_ selection: PCNativeSharedQuoteSelection) -> Bool {
        guard let page, isCurrent(page) else { return false }
        return session.canPerform(selection)
    }
    private func updateMonitor() {
        let needed = quotesEnabled && page != nil
        if needed {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                self?.observe(event)
                return event
            }
            return
        }
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        if draggingFromPage {
            session.pointer(down: false, tracksSelection: false)
            draggingFromPage = false
        }
    }
    private func observe(_ event: NSEvent) {
        guard let page, let window, event.window === window, window.isKeyWindow, isCurrent(page) else { return }
        let view = page.nativeView
        if event.type == .leftMouseDown {
            let point = view.convert(event.locationInWindow, from: nil)
            draggingFromPage = !view.isHiddenOrHasHiddenAncestor && view.visibleRect.contains(point)
        }
        guard draggingFromPage else { return }
        let down = event.type != .leftMouseUp
        session.pointer(down: down, tracksSelection: event.type == .leftMouseDragged ||
            (event.type == .leftMouseDown && event.clickCount >= 2))
        if !down { draggingFromPage = false }
    }
}
