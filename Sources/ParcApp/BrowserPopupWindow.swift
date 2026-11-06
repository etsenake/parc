import AppKit

///
/// `.browserPopup` entry point. Its normal key/main eligibility is explicit.
final class BrowserPopupWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func makeKey() {
        // LittleBrowserWindow's browser-popup entry point temporarily rises
        // to level 24 while becoming key, then returns to normal next turn.
        level = NSWindow.Level(rawValue: 24)
        super.makeKey()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.level = .normal
            self.collectionBehavior.remove(.moveToActiveSpace)
        }
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isRestorable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = .managed
    }
}
