import AppKit

@main @MainActor struct MenuImagesTests {
    static var count = 0
    static func check(_ value: Bool, _ message: String) {
        count += 1
        if !value { fatalError(message) }
    }

    static func main() {
        _ = NSApplication.shared
        let image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)!
        let plain = MenuAction.item("Copy URL") {}
        check(plain.image == nil, "A MenuAction item has no image context menu items")

        let shown = NSMenuItem(title: "Copy URL", action: nil, keyEquivalent: "")
        shown.showImage(image)
        check(shown.image === image, "showImage sets the item's image")

        guard #available(macOS 27, *) else { print("MenuImagesTests: \(count) assertions passed (before macOS 27)"); return }
        check(plain.preferredImageVisibility == .automatic, "A MenuAction item leaves visibility to AppKit")
        check(shown.preferredImageVisibility == .visible, "showImage asks AppKit to show the image")
        let cleared = NSMenuItem(title: "Open in Personal", action: nil, keyEquivalent: "")
        cleared.showImage(image); cleared.showImage(nil)
        check(cleared.image == nil && cleared.preferredImageVisibility == .automatic,
              "showImage(nil) clears the image and returns visibility to AppKit")
        func width(_ item: NSMenuItem) -> CGFloat { let menu = NSMenu(); menu.addItem(item); return menu.size.width }
        let set = NSMenuItem(title: "Copy URL", action: nil, keyEquivalent: ""); set.image = image
        let titleOnly = width(MenuAction.item("Copy URL") {})
        check(width(set) == titleOnly, "macOS 27 hides an image the item does not ask to show")
        check(width(shown) > titleOnly, "AppKit makes room for an image shown through showImage")
        print("MenuImagesTests: \(count) assertions passed")
    }
}
