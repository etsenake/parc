import AppKit
import ObjectiveC

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
    func exit(_ info: NSDraggingInfo?) { router?.exit(info) }
    func end() { let old = router; router = nil; old?.end() }
}

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
        if class_getInstanceMethod(NSTextView.self, #selector(NSView.draggingEnded(_:))) != nil {
            super.draggingEnded(sender)
        }
    }
}

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
