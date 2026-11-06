import AppKit

/// The capture caller supplies its original source URL and explicitly no text.
/// Preparing this immutable payload neither opens Messages nor contacts anyone.
@MainActor
struct CaptureMessagePayload {
    let pngData: Data
    let sourceURL: URL?
    private let image: NSImage

    init?(png: Data, sourceAddress: String) {
        guard let image = NSImage(data: png), image.isValid else { return nil }
        self.pngData = png; self.image = image
        let source = URL(string: sourceAddress)
        sourceURL = source?.scheme?.isEmpty == false ? source : nil
    }

    var items: [Any] {
        //
        // Capture's text is nil; page titles and brand copy are never invented.
        var result: [Any] = []
        if let sourceURL { result.append(sourceURL) }
        result.append(image)
        return result
    }
}

/// The real macOS Compose Message service owns its composer and immutable image
/// after perform(withItems:). It has no public cancellation API. Detaching a
/// retired page drops our callback; it cannot retract the user's OS composer.
@MainActor
final class CaptureMessageSharing: NSObject, NSSharingServiceDelegate {
    enum Outcome { case completed, cancelled, failed(Error) }
    private let service: NSSharingService
    private let items: [Any]
    private weak var parent: NSWindow?
    private weak var sourceView: NSView?
    private let sourceRect: NSRect
    private var completion: ((Outcome) -> Void)?

    static func isAvailable(for payload: CaptureMessagePayload?) -> Bool {
        guard let payload, let service = NSSharingService(named: .composeMessage) else { return false }
        return service.canPerform(withItems: payload.items)
    }

    init?(payload: CaptureMessagePayload, parent: NSWindow, sourceView: NSView, sourceRect: NSRect,
          completion: @escaping (Outcome) -> Void) {
        let items = payload.items
        guard let service = NSSharingService(named: .composeMessage),
              service.canPerform(withItems: items) else { return nil }
        self.service = service; self.items = items
        self.parent = parent; self.sourceView = sourceView; self.sourceRect = sourceRect
        self.completion = completion
        super.init()
        service.delegate = self
    }

    func present() {
        guard let parent, parent.isKeyWindow, parent.isVisible, parent.attachedSheet == nil,
              sourceView?.window === parent else { finish(.cancelled); return }
        guard service.canPerform(withItems: items) else {
            finish(.failed(NSError(domain: "Parc.CaptureSharing", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Messages is not available for this image."])))
            return
        }
        service.perform(withItems: items)
    }

    func detach() { completion = nil; service.delegate = nil }
    private func finish(_ outcome: Outcome) {
        let callback = completion
        detach()
        callback?(outcome)
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        guard sharingService === service else { return }
        // This is the service's completion, not proof of delivery to a recipient.
        finish(.completed)
    }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        guard sharingService === service else { return }
        let nsError = error as NSError
        finish(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError ? .cancelled : .failed(error))
    }
    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        sharingContentScope.pointee = .partial
        return parent
    }
    func sharingService(_ sharingService: NSSharingService, sourceFrameOnScreenForShareItem item: Any) -> NSRect {
        guard let parent, let sourceView, sourceView.window === parent else { return .zero }
        return parent.convertToScreen(sourceView.convert(sourceRect, to: nil))
    }
}
