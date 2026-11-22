import AppKit

extension NSMenuItem {
    func showImage(_ image: NSImage?) {
        self.image = image
        if #available(macOS 27, *) { preferredImageVisibility = image == nil ? .automatic : .visible }
    }
}
