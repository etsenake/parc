import AppKit

//
//
// InterProfileMoveDialog decisions built on it. No browser is involved.
@main
struct PArcDialogTests {
    @MainActor static var count = 0
    @MainActor static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; if !value() { fatalError(message) }
    }
    @MainActor static func drain() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
    @MainActor static func pixel(_ view: NSView, _ x: CGFloat, _ y: CGFloat) -> NSColor {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let row = view.isFlipped ? y : view.bounds.height - y
        return rep.colorAt(x: Int(x * scale), y: Int(row * scale))!.usingColorSpace(.sRGB)!
    }
    /// Compares with the sRGB value drawn by a swatch in the same window, so
    /// the window's backing color space cancels out.
    @MainActor static func close(_ color: NSColor, _ rgb: UInt32, in host: NSView) -> Bool {
        let swatch = Swatch(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        swatch.color = NSColor(srgbRed: CGFloat(rgb >> 16 & 0xff) / 255, green: CGFloat(rgb >> 8 & 0xff) / 255,
                               blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
        host.window!.contentView!.addSubview(swatch)
        defer { swatch.removeFromSuperview() }
        let reference = pixel(swatch, 5, 5)
        return abs(color.redComponent - reference.redComponent) < 0.02 &&
            abs(color.greenComponent - reference.greenComponent) < 0.02 &&
            abs(color.blueComponent - reference.blueComponent) < 0.02
    }
    @MainActor final class Swatch: NSView {
        var color = NSColor.clear
        override func draw(_ dirtyRect: NSRect) { color.setFill(); bounds.fill() }
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)

        //
        let mark = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.black.setFill(); rect.fill(); return true
        }
        let single = PArcDialog(.init(title: [("Exporting Easel", false)], message: [("Encountered problem exporting easel.", false)],
                                     icon: mark, confirm: "OK"))
        let panel = single.panel, root = panel.contentView!
        expect(panel.styleMask.contains(.titled) && panel.styleMask.contains(.fullSizeContentView) && panel.titlebarAppearsTransparent
               && panel.titleVisibility == .hidden && !panel.isOpaque, "SheetWindow is a titled, full-size, non-opaque sheet with a hidden title bar")
        expect(root.frame.width == 450 && root.isFlipped, "The default display options give a 450-point dialog")
        let labels = root.subviews.compactMap { $0 as? NSTextField }
        let icon = root.subviews.first { $0.frame.size == NSSize(width: 62, height: 62) }
        expect(icon?.frame.origin == NSPoint(x: 38, y: 38), "The 62-point picture icon sits at the 38-point insets")
        let title = labels[0], message = labels[1]
        let titleFont = title.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let messageFont = message.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let titleStyle = title.attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        expect(titleFont?.pointSize == 18 && titleStyle?.lineSpacing == 4, "DialogTitle is 18-point with line spacing 4")
        expect(messageFont?.pointSize == 14, "The message is 14-point")
        expect(title.frame.minX == 36 && title.frame.minY == 38 + 62 + 17, "The title's text starts 38 points in, 17 below the icon")
        expect(message.frame.minY == title.frame.maxY + 8, "The message follows the title's 8-point bottom padding")
        let ok = single.confirmButton
        expect(ok.primary && ok.keyEquivalent == "\r" && single.cancelButton == nil && single.suppression == nil, "A single primary OK answers Return")
        expect(ok.frame.maxX == 450 - 28 + 0.5 && ok.frame.height == 38.5 && ok.frame.width == ok.bodyWidth + 1,
               "The button's 36-point body ends 28 points from the right, with room for its border and lip")
        expect(ok.frame.minY == message.frame.maxY + 22 - 0.5, "The footer follows the prompt's 22-point bottom padding")
        expect(root.frame.height == message.frame.maxY + 22 + 36 + 28, "The dialog ends 28 points below the footer")
        let okLabel = ("OK" as NSString).size(withAttributes: [.font: PArcDialogStyle.buttonFont]).width
        expect(ok.bodyWidth > 12 + okLabel + 8 + 12, "The body holds padding, label and the return hint")
        expect(close(pixel(root, 445, 5), 0xFAFBFF, in: root), "DialogViewBase fills light PopoverBackground")
        expect(close(pixel(ok, 6, 18), 0x3139FB, in: root), "The primary face is the indigo")
        panel.appearance = NSAppearance(named: .darkAqua)
        expect(close(pixel(root, 445, 5), 0x151C30, in: root), "DialogViewBase fills dark PopoverBackground")
        ok.isEnabled = false
        expect(close(pixel(ok, 6, 18), 0x1C1D4F, in: root), "A disabled primary uses Indigo4")
        ok.isEnabled = true
        panel.appearance = nil

        // InterProfileMoveDialog on the same component.
        let prompt = InterProfileMovePrompt(tabCount: 1, spaceName: "Work")
        func move(_ act: (InterProfileMoveDialog) -> Void) -> InterProfileMoveDecision? {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let dialog = InterProfileMoveDialog(prompt: prompt)
            var decision: InterProfileMoveDecision?
            expect(dialog.begin(for: window) { decision = $0 }, "The move dialog begins as a sheet")
            expect(window.attachedSheet === dialog.dialog.panel, "The sheet attaches to the original window")
            expect(!dialog.begin(for: window) { _ in }, "The same dialog cannot begin twice")
            act(dialog); drain()
            return decision
        }
        let sample = InterProfileMoveDialog(prompt: prompt).dialog
        let sampleRoot = sample.panel.contentView!
        expect(sampleRoot.frame.width == 455, "The move prompt keeps the 455-point width")
        let moveTitle = sampleRoot.subviews.compactMap { $0 as? NSTextField }[0].attributedStringValue
        let nameRange = (moveTitle.string as NSString).range(of: "Work")
        let nameFont = moveTitle.attribute(.font, at: nameRange.location, effectiveRange: nil) as? NSFont
        expect(moveTitle.string == prompt.title && nameFont?.fontDescriptor.symbolicTraits.contains(.bold) == true,
               "The Space name stays bold in the dialog title")
        guard let cancel = sample.cancelButton, let box = sample.suppression else { fatalError("Missing move controls") }
        expect(!cancel.primary && cancel.keyEquivalent == "\u{1b}" && cancel.title == "Cancel" && sample.confirmButton.title == "Move it",
               "Cancel answers Escape beside the primary Move it")
        expect(sample.confirmButton.frame.minX - cancel.frame.maxX == 7, "Button bodies are 8 points apart")
        expect(box.frame.minX == 38 && box.title == "Don’t ask again", "The suppression checkbox starts at the 38-point inset")
        expect(move { $0.dialog.confirmButton.performClick(nil) } == .proceed, "Move it proceeds")
        expect(move { $0.dialog.suppression!.state = .on; $0.dialog.confirmButton.performClick(nil) } == .alwaysProceed,
               "Move it with Don’t ask again always proceeds")
        expect(move { $0.dialog.cancelButton!.performClick(nil) } == .abort, "Cancel aborts")
        expect(move { $0.dialog.panel.cancelOperation(nil) } == .abort, "Escape aborts")
        func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = [], in panel: NSWindow) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                             characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        expect(move { $0.dialog.panel.sendEvent(key(36, "\r", in: $0.dialog.panel)) } == .proceed, "A real Return key event confirms")
        expect(move { $0.dialog.panel.sendEvent(key(76, "\u{3}", [.numericPad], in: $0.dialog.panel)) } == .proceed, "Keypad Enter confirms")
        expect(move { $0.dialog.panel.sendEvent(key(53, "\u{1b}", in: $0.dialog.panel)) } == .abort, "A real Escape key event cancels")
        expect((sample.panel.accessibilityDefaultButton() as? NSButton) === sample.confirmButton, "VoiceOver reports the confirm button as the default")

        // A queued dialog waits behind the window's current sheet.
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        defer { host.close() }
        let first = PArcDialog(.init(title: [("First", false)], confirm: "OK")), next = PArcDialog(.init(title: [("Next", false)], confirm: "OK"))
        var order: [String] = []
        expect(first.begin(for: host) { _ in order.append("first") }, "The first dialog begins")
        expect(!next.begin(for: host) { _ in fatalError("unqueued") }, "An unqueued dialog refuses a window that already shows a sheet")
        expect(next.begin(for: host, queued: true) { _ in order.append("next") } && host.attachedSheet === first.panel,
               "A queued dialog waits while the first stays in front")
        first.confirmButton.performClick(nil); drain()
        expect(order == ["first"] && host.attachedSheet === next.panel, "The queued dialog follows when the first ends")
        next.confirmButton.performClick(nil); drain()
        expect(order == ["first", "next"] && host.attachedSheet == nil, "Both answer once, in order")

        //
        // Archive): ButtonsConfig.destructive draws DestructiveButtonFace.
        var deleting = PArcDialog.Content(title: [("Delete your “Work” Space?", false)],
                                         message: [("This will archive all the tabs and folders inside it.", false)],
                                         confirm: "Delete", cancel: "Cancel")
        deleting.destructive = true
        let destructive = PArcDialog(deleting)
        let destructiveRoot = destructive.panel.contentView!
        expect(destructive.confirmButton.destructive && destructive.cancelButton?.destructive == false,
               "Only the confirm button is destructive")
        expect(close(pixel(destructive.confirmButton, 6, 18), 0xF53714, in: destructiveRoot), "The destructive face is the red")
        destructive.panel.appearance = NSAppearance(named: .darkAqua)
        expect(close(pixel(destructive.confirmButton, 6, 18), 0xF53714, in: destructiveRoot), "The destructive face is the same in dark")
        destructive.panel.appearance = nil
        expect(close(pixel(sample.confirmButton, 6, 18), 0x3139FB, in: sampleRoot), "A plain confirm keeps the indigo primary")

        //
        func confirmed(_ act: (NSWindow) -> Void) -> Bool? {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            var result: Bool?
            expect(PArcDialog.confirm(in: window, title: "Clear?", message: "This action is permanent.", confirm: "Clear Archive",
                                     destructive: true) { result = $0 }, "The confirmation begins")
            act(window); drain()
            return result
        }
        expect(confirmed { ($0.attachedSheet?.contentView?.subviews.compactMap { $0 as? PArcDialogButton }.first { $0.primary })?.performClick(nil) } == true,
               "Confirm reports true")
        expect(confirmed { $0.attachedSheet?.cancelOperation(nil) } == false, "Escape reports false")
        let busy = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        busy.isReleasedWhenClosed = false
        defer { busy.close() }
        let blocker = PArcDialog(.init(title: [("Busy", false)], confirm: "OK"))
        _ = blocker.begin(for: busy) { _ in }
        var refused: Bool?
        expect(!PArcDialog.confirm(in: busy, title: "Delete?", message: nil, confirm: "Delete") { refused = $0 } && refused == false,
               "A window that already shows a sheet refuses at once")
        blocker.confirmButton.performClick(nil); drain()

        // ButtonsConfig.auxiliaryButton: a hint-less neutral button left of
        // Cancel that answers with its own response.
        var auxiliaryContent = PArcDialog.Content(title: [("Quit Parc?", false)], confirm: "Quit", cancel: "Cancel")
        auxiliaryContent.auxiliary = "Quit, and don’t ask again"
        let auxiliary = PArcDialog(auxiliaryContent)
        let auxiliaryButton = auxiliary.auxiliaryButton!
        expect(!auxiliaryButton.primary && !auxiliaryButton.hint && auxiliary.cancelButton!.hint
               && auxiliaryButton.frame.maxX < auxiliary.cancelButton!.frame.minX, "The auxiliary button precedes Cancel without a hint")
        var auxiliaryResponse: PArcDialog.Response?
        expect(auxiliary.begin(for: host) { auxiliaryResponse = $0 }, "The auxiliary dialog begins")
        auxiliaryButton.performClick(nil); drain()
        expect(auxiliaryResponse == .auxiliary && host.attachedSheet == nil, "The auxiliary button ends the sheet with its own response")

        // TextInputDialogContext: a borderless 14-point field under the title and
        // message; a required field disables confirm while blank; Return confirms
        // and Escape cancels, but not during input-method composition.
        let named = PArcDialog(.init(title: [("Create a new Profile", false)], message: [("What do you want to call this Profile?", false)],
                                    confirm: "Create Profile", cancel: "Cancel", field: .init(value: "", placeholder: "Profile name")))
        let nameField = named.textField!
        let messageLabel = named.panel.contentView!.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("What") }!
        expect(!nameField.isBordered && !nameField.drawsBackground && nameField.focusRingType == .none && nameField.font?.pointSize == 14
               && nameField.frame.minY >= messageLabel.frame.maxY && nameField.frame.maxY < named.confirmButton.frame.minY,
               "The borderless field sits between the message and the buttons")
        expect(!named.confirmButton.isEnabled && named.panel.initialFirstResponder === nameField, "Blank required text disables confirm; the field takes focus")
        nameField.stringValue = "  "; named.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: nameField))
        expect(!named.confirmButton.isEnabled, "Whitespace is still blank")
        nameField.stringValue = "Work"; named.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: nameField))
        expect(named.confirmButton.isEnabled, "A name enables confirm")
        final class Composing: NSTextView { override func hasMarkedText() -> Bool { true } }
        expect(!named.control(nameField, textView: Composing(), doCommandBy: #selector(NSResponder.insertNewline(_:))),
               "Composition keeps Return")
        var namedResponse: PArcDialog.Response?
        expect(named.begin(for: host) { namedResponse = $0 }, "The text dialog begins")
        expect(named.control(nameField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))), "Return is handled")
        drain()
        expect(namedResponse == .confirm && host.attachedSheet == nil, "Return confirms a valid name")
        print("Parc dialog: \(count) checks passed")
    }
}
