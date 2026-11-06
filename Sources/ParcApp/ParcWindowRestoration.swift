import AppKit

@MainActor
@objc(ParcWindowRestoration)
final class ParcWindowRestoration: NSObject, NSWindowRestoration {
    static let identifierPrefix = "parc.browser."
    static func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder,
                              completionHandler: @escaping (NSWindow?, Error?) -> Void) {
        guard identifier.rawValue.hasPrefix(identifierPrefix),
              let id = UUID(uuidString: String(identifier.rawValue.dropFirst(identifierPrefix.count))),
              let delegate = NSApp.delegate as? AppDelegate else { completionHandler(nil, nil); return }
        delegate.restoreBrowserWindow(id: id, completion: completionHandler)
    }
}
