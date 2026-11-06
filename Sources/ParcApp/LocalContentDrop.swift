import AppKit
import ObjectiveC

/// Native editor entry points depend only on AppKit. The application ancestor
/// supplies the same engine-backed router used by renderer views; this layer
/// neither decodes a URL nor owns a split transaction.
@MainActor
protocol LocalContentDropRouting: AnyObject {
    var claimed: Bool { get }
    func begin(_ info: NSDraggingInfo) -> NSDragOperation
    func update(_ info: NSDraggingInfo) -> NSDragOperation
    func prepare(_ info: NSDraggingInfo) -> Bool
    func perform(_ info: NSDraggingInfo) -> Bool
    func exit(_ info: NSDraggingInfo?)
    func end()
}

@MainActor
extension LocalContentDropRouting {
    func exit(_ info: NSDraggingInfo?) { end() }
}

@MainActor
protocol LocalContentDropHosting: AnyObject {
    func contentDropRouter(for view: NSView) -> any LocalContentDropRouting
}

@MainActor
final class LocalContentDropForwarder {
    private weak var view: NSView?
    private var router: (any LocalContentDropRouting)?
    private var claimed = false
    init(view: NSView) { self.view = view }
    /// Nil keeps the original AppKit/content receiver. An empty operation from
    /// an already claimed router is a refusal, never a second drop destination.
    func begin(_ info: NSDraggingInfo) -> NSDragOperation? {
        end(); claimed = false
        guard let view else { return nil }
        if let text = view as? NSTextView, text.hasMarkedText() { return nil }
        var ancestor = view.superview
        while let candidate = ancestor {
            if let host = candidate as? any LocalContentDropHosting {
                let next = host.contentDropRouter(for: view)
                let operation = next.begin(info)
                guard next.claimed else { next.end(); return nil }
                router = next; claimed = true
                return operation
            }
            ancestor = candidate.superview
        }
        return nil
    }
    func update(_ info: NSDraggingInfo) -> NSDragOperation? { claimed ? router?.update(info) ?? [] : nil }
    func prepare(_ info: NSDraggingInfo) -> Bool? { claimed ? router?.prepare(info) ?? false : nil }
    func perform(_ info: NSDraggingInfo) -> Bool? { claimed ? router?.perform(info) ?? false : nil }
    // Retain the claimed tombstone until the next real draggingEntered. AppKit
    // may still deliver prepare/perform after a detach or conclusion callback.
    func exit(_ info: NSDraggingInfo?) { router?.exit(info) }
    func end() { let old = router; router = nil; old?.end() }
}

/// Native text drag behavior stays in NSTextView unless the original ancestor
/// accepts the gesture. Copy, paste, Undo and IME are otherwise untouched.
@MainActor
class LocalContentDropTextView: NSTextView {
    private lazy var contentDrop = LocalContentDropForwarder(view: self)
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes(registeredDraggedTypes + [.URL])
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { contentDrop.end() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        contentDrop.begin(sender) ?? super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        contentDrop.update(sender) ?? super.draggingUpdated(sender)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        contentDrop.prepare(sender) ?? super.prepareForDragOperation(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        contentDrop.perform(sender) ?? super.performDragOperation(sender)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        contentDrop.exit(sender); super.draggingExited(sender)
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        contentDrop.end(); super.concludeDragOperation(sender)
    }
    override func draggingEnded(_ sender: NSDraggingInfo) {
        contentDrop.end()
        // NSDraggingDestination is optional; NSView need not implement this
        // terminal selector. Preserve a real native text implementation only.
        if class_getInstanceMethod(NSTextView.self, #selector(NSView.draggingEnded(_:))) != nil {
            super.draggingEnded(sender)
        }
    }
}

/// Covers the document/canvas background. A concrete canvas can retain its own
/// image/rich-text receiver by testing the optional forwarding result first.
@MainActor
class LocalContentDropView: NSView {
    lazy var contentDrop = LocalContentDropForwarder(view: self)
    override init(frame: NSRect) {
        super.init(frame: frame); registerForDraggedTypes([.URL, .string])
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder); registerForDraggedTypes([.URL, .string])
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { contentDrop.end() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { contentDrop.begin(sender) ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { contentDrop.update(sender) ?? super.draggingUpdated(sender) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { contentDrop.prepare(sender) ?? super.prepareForDragOperation(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { contentDrop.perform(sender) ?? false }
    override func draggingExited(_ sender: NSDraggingInfo?) { contentDrop.exit(sender); super.draggingExited(sender) }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { contentDrop.end(); super.concludeDragOperation(sender) }
    override func draggingEnded(_ sender: NSDraggingInfo) {
        contentDrop.end()
        if class_getInstanceMethod(NSView.self, #selector(NSView.draggingEnded(_:))) != nil {
            super.draggingEnded(sender)
        }
    }
}
