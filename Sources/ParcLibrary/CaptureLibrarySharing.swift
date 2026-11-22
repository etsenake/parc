import AppKit

@MainActor
struct CaptureLibrarySharePayload {
    enum Destination: CaseIterable {
        case message, airDrop
        var title: String { self == .message ? "Send via iMessage…" : "AirDrop…" }
        var serviceName: NSSharingService.Name { self == .message ? .composeMessage : .sendViaAirDrop }
    }
    let destination: Destination
    let image: NSImage
    let sourceAddress: String
    init?(png: Data, sourceAddress: String, destination: Destination) {
        guard let image = NSImage(data: png) else { return nil }
        self.image = image; self.sourceAddress = sourceAddress; self.destination = destination
    }
    var items: [Any] {
        if destination == .message, !sourceAddress.isEmpty { return [image, sourceAddress] }
        return [image]
    }
    var isAvailable: Bool { NSSharingService(named: destination.serviceName)?.canPerform(withItems: items) == true }
}

@MainActor
final class CaptureLibrarySharing: NSObject, NSSharingServiceDelegate {
    private let payload: CaptureLibrarySharePayload
    private let service: NSSharingService
    private weak var parent: NSWindow?
    private weak var source: NSView?
    private var completion: ((Error?) -> Void)?
    init?(payload: CaptureLibrarySharePayload, parent: NSWindow, source: NSView, completion: @escaping (Error?) -> Void) {
        guard let service = NSSharingService(named: payload.destination.serviceName), service.canPerform(withItems: payload.items) else { return nil }
        self.payload = payload; self.service = service; self.parent = parent; self.source = source; self.completion = completion
        super.init(); service.delegate = self
    }
    func present() {
        guard let parent, parent.isKeyWindow, parent.isVisible, parent.attachedSheet == nil,
              source?.window === parent, service.canPerform(withItems: payload.items) else {
            finish(CocoaError(.userCancelled)); return
        }
        service.perform(withItems: payload.items)
    }
    func detach() { completion = nil; service.delegate = nil }
    private func finish(_ error: Error?) { let callback = completion; detach(); callback?(error) }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        guard sharingService === service else { return }; finish(nil)
    }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        guard sharingService === service else { return }; finish(error)
    }
    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        sharingContentScope.pointee = .partial; return parent
    }
    func sharingService(_ sharingService: NSSharingService, sourceFrameOnScreenForShareItem item: Any) -> NSRect {
        guard let parent, let source, source.window === parent else { return .zero }
        return parent.convertToScreen(source.convert(source.bounds, to: nil))
    }
    static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }
}
