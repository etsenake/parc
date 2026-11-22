import AppKit
import ParcCore
import ParcEngine
@testable import Parc

@MainActor final class SplitDropDragInfo: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation: NSPoint
    var draggedImageLocation = NSPoint.zero
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any? { nil }
    var draggingSequenceNumber = 7
    var draggingFormation = NSDraggingFormation.default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight = NSSpringLoadingHighlight.none
    var items: [NSDraggingItem] = []

    init(window: NSWindow? = nil, location: NSPoint = NSPoint(x: 40, y: 40)) {
        draggingDestinationWindow = window
        draggingLocation = location
    }

    deinit { draggingPasteboard.releaseGlobally() }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        for (index, item) in items.enumerated() where !classArray.isEmpty {
            block(item, index, &stop)
            if stop.boolValue { break }
        }
    }
    func resetSpringLoading() {}

    func write(_ types: [(NSPasteboard.PasteboardType, String)]) {
        draggingPasteboard.clearContents()
        let item = NSPasteboardItem()
        for (type, value) in types { item.setString(value, forType: type) }
        draggingPasteboard.writeObjects([item])
    }

    func writeURL(_ text: String) { write([(.URL, text)]) }

    func writeText(_ text: String) {
        draggingSequenceNumber += 1
        write([(.string, text)])
    }
}

@MainActor final class SplitDropReservedPane: NSView, SplitLayoutFollowing, LocalContentDropHosting {
    let body = NSView()
    private(set) var followed: [(previous: CGRect, duration: CFTimeInterval)] = []
    private(set) var cancelled = 0
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(body)
        body.autoresizingMask = [.width, .height]
        body.frame = NSRect(x: 0, y: 40, width: frame.width, height: max(0, frame.height - 40))
    }

    required init?(coder: NSCoder) { fatalError() }

    func contentDropRouter(for view: NSView) -> any LocalContentDropRouting { SplitDropRouterAdapter(view: view) }
    func followSplitLayout(from previous: CGRect, animation: CAAnimation) { followed.append((previous, animation.duration)) }
    func cancelSplitLayoutFollow() { cancelled += 1 }
}

@MainActor func immediate(_ lease: ParcSplitView.DropReservation) -> ParcSplitView.DropReservation {
    lease.hoverIntent = SplitDropIntent(dwell: 0)
    return lease
}

@MainActor final class SplitDropRouterDouble: NSObject, PCNativeContentDropRouting {
    private weak var view: NSView?
    private weak var destination: (NSView & PCNativeContentDropDestination)?
    private weak var window: NSWindow?
    private var pasteboard: NSPasteboard?
    private var changeCount = 0
    private var sequence = 0
    private var isClaimed = false
    private var currentOperation: NSDragOperation = []

    init(view: NSView) { self.view = view }

    var claimed: Bool { isClaimed }
    var operation: NSDragOperation { currentOperation }

    private func valid(_ info: NSDraggingInfo) -> Bool {
        guard isClaimed, let view, let destination, let window, let pasteboard else { return false }
        return view.window === window && destination.window === window && view.isDescendant(of: destination)
            && info.draggingDestinationWindow === window && info.draggingSequenceNumber == sequence
            && info.draggingPasteboard === pasteboard && pasteboard.changeCount == changeCount
    }

    func begin(_ info: NSDraggingInfo) -> Bool {
        end()
        guard let view, let window = view.window, info.draggingDestinationWindow === window else { return false }
        var parent = view.superview
        while let ancestor = parent {
            defer { parent = ancestor.superview }
            guard let candidate = ancestor as? (NSView & PCNativeContentDropDestination) else { continue }
            destination = candidate
            self.window = window
            pasteboard = info.draggingPasteboard
            changeCount = info.draggingPasteboard.changeCount
            sequence = info.draggingSequenceNumber
            isClaimed = true
            let operation = candidate.contentView(view, beginDrop: info)
            if operation.isEmpty { end(); return false }
            isClaimed = true
            if !valid(info) { cancelRecipient(); return true }
            currentOperation = operation.intersection(info.draggingSourceOperationMask)
            return true
        }
        return false
    }

    private func cancelRecipient() {
        let view = view, destination = destination
        self.destination = nil
        currentOperation = []
        if let view, let destination { destination.contentViewDidEndDrop(view) }
    }

    func update(_ info: NSDraggingInfo) -> NSDragOperation {
        guard valid(info), let view, let destination else { cancelRecipient(); return [] }
        let operation = destination.contentView(view, updateDrop: info)
        if !valid(info) { cancelRecipient(); return [] }
        currentOperation = operation.intersection(info.draggingSourceOperationMask)
        return currentOperation
    }

    func prepare(_ info: NSDraggingInfo) -> Bool {
        guard valid(info), !currentOperation.intersection(info.draggingSourceOperationMask).isEmpty,
              let view, let destination else { cancelRecipient(); return false }
        let ready = destination.contentView(view, prepareDrop: info)
        if !valid(info) { cancelRecipient(); return false }
        return ready
    }

    func perform(_ info: NSDraggingInfo) -> Bool {
        var result = false
        if prepare(info), let view, let destination { result = destination.contentView(view, performDrop: info) }
        end()
        return result
    }

    func exit(_ info: NSDraggingInfo?) {
        if let info, valid(info), let view, let destination,
           destination.contentView?(view, handoffDrop: info, router: self) == true {
            if !valid(info) { cancelRecipient() }
            return
        }
        end()
    }

    func end() {
        let view = view, destination = destination
        let notify = isClaimed
        isClaimed = false
        currentOperation = []
        self.destination = nil
        window = nil
        pasteboard = nil
        if notify, let view, let destination { destination.contentViewDidEndDrop(view) }
    }
}

@MainActor final class SplitDropRouterAdapter: LocalContentDropRouting {
    private let router: SplitDropRouterDouble
    init(view: NSView) { router = SplitDropRouterDouble(view: view) }
    var claimed: Bool { router.claimed }
    func begin(_ info: NSDraggingInfo) -> NSDragOperation { _ = router.begin(info); return router.operation }
    func update(_ info: NSDraggingInfo) -> NSDragOperation { router.update(info) }
    func prepare(_ info: NSDraggingInfo) -> Bool { router.prepare(info) }
    func perform(_ info: NSDraggingInfo) -> Bool { router.perform(info) }
    func exit(_ info: NSDraggingInfo?) { router.exit(info) }
    func end() { router.end() }
}

@MainActor final class SplitDropRoutingPane: NSView, LocalContentDropHosting {
    func contentDropRouter(for view: NSView) -> any LocalContentDropRouting { SplitDropRouterAdapter(view: view) }
}

@MainActor func settleMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}
