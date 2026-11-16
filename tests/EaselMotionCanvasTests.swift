import AppKit

@MainActor private final class CanvasMotionWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

@main struct EaselMotionCanvasTests {
    @MainActor static var count = 0
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(condition(), message)
    }

    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        _ = NSApplication.shared
        let date = Date()
        let object = EaselItem(kind: .rectangle, frame: .init(x: 80, y: 80, width: 100, height: 100))
        let document = EaselDocument(id: UUID(), title: "Motion", createdAt: date, modifiedAt: date, items: [object])
        let session = try EaselSession(inMemory: document, assets: [:])
        let canvas = EaselCanvasView(session: session)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.allowsMagnification = true; scroll.minMagnification = 0.3333; scroll.maxMagnification = 4
        scroll.documentView = canvas
        let window = CanvasMotionWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = scroll
        defer { window.contentView = nil; window.close() }
        canvas.layoutSubtreeIfNeeded(); canvas.selectAll(nil)
        func handles() -> [NSAccessibilityElement] {
            (canvas.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityElement }
                .filter { $0.accessibilityRole() == .handle }
        }
        let initialHandles = handles()
        expect(!initialHandles.isEmpty, "Selected geometry exposes actual native handle nodes")
        let retained = initialHandles[0].accessibilityCustomActions()![0]
        scroll.magnification = 0.8
        NotificationCenter.default.post(name: NSScrollView.willStartLiveMagnifyNotification, object: scroll)
        expect(handles().isEmpty, "Pinch suppression removes invisible handles from the native AX children")
        expect(retained.handler?() == false && session.document == document, "A retained hidden handle cannot mutate its original document")
        scroll.magnification = 0.5
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        expect(canvas.bounds.width >= scroll.contentView.bounds.width && canvas.bounds.height >= scroll.contentView.bounds.height,
               "Canvas covers the actual document-space viewport below100percent")
        let extent = canvas.frame.size
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        expect(canvas.frame.size == extent && session.document == document, "Repeated bounds notifications converge without geometry writes")
        NotificationCenter.default.post(name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        expect(!handles().isEmpty, "Gesture completion restores current manipulation controls")
        NotificationCenter.default.post(name: NSScrollView.willStartLiveMagnifyNotification, object: scroll)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        expect(!handles().isEmpty && session.document == document, "Window retirement clears transient suppression without document mutation")
        try session.perform("Small fixture") { $0.items[0].frame.width = 40; $0.items[0].frame.height = 40 }
        scroll.magnification = 1; canvas.selectAll(nil)
        let smallDocument = session.document
        let edge = handles().first { $0.accessibilityLabel() == "Resize Right" }!.accessibilityCustomActions()![0]
        NotificationCenter.default.post(name: NSScrollView.willStartLiveMagnifyNotification, object: scroll)
        scroll.magnification = 0.5
        NotificationCenter.default.post(name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        expect(!handles().contains { $0.accessibilityLabel() == "Resize Right" }, "Scale change removes edges below their30pt screen admission threshold")
        expect(edge.handler?() == false && session.document == smallDocument, "A retained edge action rechecks scale eligibility after pinch completes")
        let arrow = EaselItem(kind: .arrow, frame: .init(x: 80, y: 80, width: 100, height: 100),
                              points: [.init(x: 0, y: 100), .init(x: 100, y: 0)])
        try session.perform("Replace fixture") { $0.items = [arrow] }
        canvas.selectAll(nil)
        let endpoints = handles()
        expect(endpoints.count == 2, "Arrow exposes its original two endpoint nodes")
        let endpoint = endpoints[0].accessibilityCustomActions()![0]
        NotificationCenter.default.post(name: NSScrollView.willStartLiveMagnifyNotification, object: scroll)
        expect(handles().isEmpty && endpoint.handler?() == false && session.document.items == [arrow],
               "Invisible original arrow endpoints reject their retained action")
        NotificationCenter.default.post(name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        canvas.fixedCanvasSize = NSSize(width: 40, height: 20)
        canvas.resizeCanvas(viewport: NSSize(width: 800, height: 600))
        expect(canvas.frame.size == NSSize(width: 40, height: 20), "Capture's fixed pixel canvas is never expanded to the viewport")
        print("Easel motion canvas: \(count) assertions passed")
    }
}
