import AppKit
import Combine

@MainActor
final class WebpageWindowDraggingPreferences: ObservableObject {
    static let shared = WebpageWindowDraggingPreferences()
    struct State: Codable, Equatable {
        var version = 1
        var isEnabled = true
    }
    @Published private(set) var state: State
    private let defaults: UserDefaults
    private let key = "parc.webpageWindowDragging.v1"
    private(set) var loadError = false
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.object(forKey: key) {
            guard let data = stored as? Data,
                  let decoded = try? JSONDecoder().decode(State.self, from: data), decoded.version == 1 else {
                state = State(); loadError = true; return
            }
            state = decoded
        } else { state = State() }
    }
    func setEnabled(_ enabled: Bool) throws {
        guard !loadError else { throw Failure.unavailable }
        guard state.isEnabled != enabled else { return }
        var next = state; next.isEnabled = enabled
        defaults.set(try JSONEncoder().encode(next), forKey: key)
        state = next
    }
    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "Window dragging preferences are unavailable. The existing preferences have been preserved." }
    }
}

struct WebpageWindowDragState: Equatable {
    enum Phase: Equatable { case inactive, began, committed(x: CGFloat, y: CGFloat) }
    private(set) var phase = Phase.inactive
    static func region(in bounds: NSRect, topStripHeight: CGFloat) -> NSRect {
        let top = min(max(0, topStripHeight), bounds.height)
        return NSRect(x: bounds.minX, y: bounds.minY + top,
                      width: max(0, bounds.width - 14), height: max(0, min(60, bounds.height) - top))
    }
    static func permitsModifiers(_ flags: NSEvent.ModifierFlags) -> Bool {
        let meaningful = flags.intersection(.deviceIndependentFlagsMask)
        return meaningful.isEmpty || meaningful == .option
    }
    mutating func begin(eligible: Bool) { phase = eligible ? .began : .inactive }
    mutating func commit() { phase = .committed(x: 0, y: 0) }
    mutating func cancel() { phase = .inactive }
    mutating func consume(_ type: NSEvent.EventType, deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        guard case .committed(let x, let y) = phase else { return false }
        if type == .leftMouseDragged {
            phase = .committed(x: x + abs(deltaX), y: y + abs(deltaY)); return true
        }
        if type == .leftMouseUp {
            phase = .inactive
            return hypot(x, y) > 1
        }
        return false
    }
}

@MainActor
final class WebpageWindowGrabber: NSView {
    private weak var owner: AnyObject?
    private var revision: UInt = 0
    private var eligibility: ((NSEvent) -> Bool)?
    private var isCurrent: (() -> Bool)?
    private(set) var drag = WebpageWindowDragState()
    private weak var sequenceWindow: NSWindow?
    private var monitor: Any?
    private var committing = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isHidden: Bool { didSet { if isHidden { cancel() } } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func configure(owner: AnyObject?, revision: UInt, isCurrent: (() -> Bool)?, eligibility: ((NSEvent) -> Bool)?) {
        if self.owner !== owner || self.revision != revision { cancel() }
        self.owner = owner; self.revision = revision; self.isCurrent = isCurrent; self.eligibility = eligibility
        isHidden = owner == nil || isCurrent == nil || eligibility == nil
    }
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        if newOrigin != frame.origin { cancel() }
        super.setFrameOrigin(newOrigin)
    }
    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { cancel() }
        super.setFrameSize(newSize)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancel() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !committing, let event = NSApp?.currentEvent,
              event.type == .leftMouseDown || event.type == .leftMouseDragged,
              super.hitTest(point) === self, let window, event.window === window else { return nil }
        if event.type == .leftMouseDragged, drag.phase == .inactive { return nil }
        let eligible = owner != nil && isCurrent?() == true && !isHiddenOrHasHiddenAncestor && NSCursor.current == NSCursor.arrow && eligibility?(event) == true
        if event.type == .leftMouseDown {
            cancel(); drag.begin(eligible: eligible); sequenceWindow = eligible ? window : nil
            return nil
        }
        guard eligible, sequenceWindow === window else { cancel(); return nil }
        switch drag.phase {
        case .inactive: return nil
        case .began:
            committing = true
            window.performDrag(with: event)
            committing = false
            guard self.window === window, sequenceWindow === window, owner != nil,
                  !isHiddenOrHasHiddenAncestor, isCurrent?() == true else { cancel(); return nil }
            drag.commit(); installMonitor()
            return self
        case .committed: return self
        }
    }
    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.filterCommittedEvent(event) == nil
            }
            return consumed ? nil : event
        }
    }
    func filterCommittedEvent(_ event: NSEvent) -> NSEvent? {
        guard event.window === sequenceWindow, event.window === window else { return event }
        guard owner != nil, !isHiddenOrHasHiddenAncestor, isCurrent?() == true else { cancel(); return event }
        let consumed = drag.consume(event.type, deltaX: event.deltaX, deltaY: event.deltaY)
        if drag.phase == .inactive { cancel() }
        return consumed ? nil : event
    }
    func cancel() {
        drag.cancel(); sequenceWindow = nil
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
