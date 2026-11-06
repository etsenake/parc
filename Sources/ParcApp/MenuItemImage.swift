import AppKit

extension NSMenuItem {
    /// Shows `image` beside the title. On macOS 27 AppKit hides a menu item's
    ///
    /// shows the images it sets.
    func showImage(_ image: NSImage?) {
        self.image = image
        if #available(macOS 27, *) { preferredImageVisibility = image == nil ? .automatic : .visible }
    }
}
