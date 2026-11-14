import AppKit

@main
struct ParcDialogTests {
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

        let mark = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.black.setFill(); rect.fill(); return true
        }
        let single = ParcDialog(.init(title: [("Exporting Easel", false)], message: [("Encountered problem exporting easel.", false)],
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
        let okLabel = ("OK" as NSString).size(withAttributes: [.font: ParcDialogStyle.buttonFont]).width
        expect(ok.bodyWidth > 12 + okLabel + 8 + 12, "The body holds padding, label and the return hint")
        expect(close(pixel(root, 445, 5), 0xFAFBFF, in: root), "DialogViewBase fills light PopoverBackground")
        expect(close(pixel(ok, 6, 18), 0x3139FB, in: root), "The primary face is the indigo")
        panel.appearance = NSAppearance(named: .darkAqua)
        expect(close(pixel(root, 445, 5), 0x151C30, in: root), "DialogViewBase fills dark PopoverBackground")
        ok.isEnabled = false
        expect(close(pixel(ok, 6, 18), 0x1C1D4F, in: root), "A disabled primary uses Indigo4")
        ok.isEnabled = true
        panel.appearance = nil

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

        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        defer { host.close() }
        let first = ParcDialog(.init(title: [("First", false)], confirm: "OK")), next = ParcDialog(.init(title: [("Next", false)], confirm: "OK"))
        var order: [String] = []
        expect(first.begin(for: host) { _ in order.append("first") }, "The first dialog begins")
        expect(!next.begin(for: host) { _ in fatalError("unqueued") }, "An unqueued dialog refuses a window that already shows a sheet")
        expect(next.begin(for: host, queued: true) { _ in order.append("next") } && host.attachedSheet === first.panel,
               "A queued dialog waits while the first stays in front")
        first.confirmButton.performClick(nil); drain()
        expect(order == ["first"] && host.attachedSheet === next.panel, "The queued dialog follows when the first ends")
        next.confirmButton.performClick(nil); drain()
        expect(order == ["first", "next"] && host.attachedSheet == nil, "Both answer once, in order")

        var deleting = ParcDialog.Content(title: [("Delete your “Work” Space?", false)],
                                         message: [("This will archive all the tabs and folders inside it.", false)],
                                         confirm: "Delete", cancel: "Cancel")
        deleting.destructive = true
        let destructive = ParcDialog(deleting)
        let destructiveRoot = destructive.panel.contentView!
        expect(destructive.confirmButton.destructive && destructive.cancelButton?.destructive == false,
               "Only the confirm button is destructive")
        expect(close(pixel(destructive.confirmButton, 6, 18), 0xF53714, in: destructiveRoot), "The destructive face is the red")
        destructive.panel.appearance = NSAppearance(named: .darkAqua)
        expect(close(pixel(destructive.confirmButton, 6, 18), 0xF53714, in: destructiveRoot), "The destructive face is the same in dark")
        destructive.panel.appearance = nil
        expect(close(pixel(sample.confirmButton, 6, 18), 0x3139FB, in: sampleRoot), "A plain confirm keeps the indigo primary")

        func confirmed(_ act: (NSWindow) -> Void) -> Bool? {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            var result: Bool?
            expect(ParcDialog.confirm(in: window, title: "Clear?", message: "This action is permanent.", confirm: "Clear Archive",
                                     destructive: true) { result = $0 }, "The confirmation begins")
            act(window); drain()
            return result
        }
        expect(confirmed { ($0.attachedSheet?.contentView?.subviews.compactMap { $0 as? ParcDialogButton }.first { $0.primary })?.performClick(nil) } == true,
               "Confirm reports true")
        expect(confirmed { $0.attachedSheet?.cancelOperation(nil) } == false, "Escape reports false")
        let busy = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        busy.isReleasedWhenClosed = false
        defer { busy.close() }
        let blocker = ParcDialog(.init(title: [("Busy", false)], confirm: "OK"))
        _ = blocker.begin(for: busy) { _ in }
        var refused: Bool?
        expect(!ParcDialog.confirm(in: busy, title: "Delete?", message: nil, confirm: "Delete") { refused = $0 } && refused == false,
               "A window that already shows a sheet refuses at once")
        blocker.confirmButton.performClick(nil); drain()

        var auxiliaryContent = ParcDialog.Content(title: [("Quit Parc?", false)], confirm: "Quit", cancel: "Cancel")
        auxiliaryContent.auxiliary = "Quit, and don’t ask again"
        let auxiliary = ParcDialog(auxiliaryContent)
        let auxiliaryButton = auxiliary.auxiliaryButton!
        expect(!auxiliaryButton.primary && !auxiliaryButton.hint && auxiliary.cancelButton!.hint
               && auxiliaryButton.frame.maxX < auxiliary.cancelButton!.frame.minX, "The auxiliary button precedes Cancel without a hint")
        var auxiliaryResponse: ParcDialog.Response?
        expect(auxiliary.begin(for: host) { auxiliaryResponse = $0 }, "The auxiliary dialog begins")
        auxiliaryButton.performClick(nil); drain()
        expect(auxiliaryResponse == .auxiliary && host.attachedSheet == nil, "The auxiliary button ends the sheet with its own response")

        let named = ParcDialog(.init(title: [("Create a new Profile", false)], message: [("What do you want to call this Profile?", false)],
                                    confirm: "Create Profile", cancel: "Cancel", field: .init(value: "", placeholder: "Profile name")))
        let nameField = named.textField!
        let messageLabel = named.panel.contentView!.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("What") }!
        let nameRoot = named.panel.contentView!
        let fieldFrame = nameField.convert(nameField.bounds, to: nameRoot)
        let card = nameField.superview!
        expect(!nameField.isBordered && !nameField.drawsBackground && nameField.focusRingType == .none && nameField.font?.pointSize == 14
               && card.frame.minY == messageLabel.frame.maxY + 16 && card.frame.maxY + 22 == named.confirmButton.frame.minY + 0.5,
               "The field's card sits 16 points under the message and 22 above the buttons")
        expect(card.frame.minX == 38 && card.frame.width == 450 - 76 && card.frame.height == 36,
               "The card spans the text column at the buttons' 36-point height")
        expect(fieldFrame.minX + 2 == card.frame.minX + 12 && abs(fieldFrame.midY - card.frame.midY) <= 0.5,
               "The text sits on the card's 12-point padding, centered")
        expect(close(pixel(nameRoot, 44, card.frame.midY), 0xFAFBFF, in: nameRoot) == false
               && close(pixel(nameRoot, 445, card.frame.midY), 0xFAFBFF, in: nameRoot),
               "The card is tinted against the popover background and stops at the column")
        expect(!named.confirmButton.isEnabled && named.panel.initialFirstResponder === nameField, "Blank required text disables confirm; the field takes focus")
        nameField.stringValue = "  "; named.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: nameField))
        expect(!named.confirmButton.isEnabled, "Whitespace is still blank")
        nameField.stringValue = "Work"; named.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: nameField))
        expect(named.confirmButton.isEnabled, "A name enables confirm")
        final class Composing: NSTextView { override func hasMarkedText() -> Bool { true } }
        expect(!named.control(nameField, textView: Composing(), doCommandBy: #selector(NSResponder.insertNewline(_:))),
               "Composition keeps Return")
        expect(!named.control(nameField, textView: Composing(), doCommandBy: #selector(NSResponder.cancelOperation(_:))),
               "Composition keeps Escape")
        var namedResponse: ParcDialog.Response?
        expect(named.begin(for: host) { namedResponse = $0 }, "The text dialog begins")
        expect(named.control(nameField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))), "Return is handled")
        drain()
        expect(namedResponse == .confirm && host.attachedSheet == nil, "Return confirms a valid name")

        struct Failure: LocalizedError {
            var errorDescription: String? { "The disk is full." }
            var recoverySuggestion: String? { "Free some space and try again." }
        }
        let plain = ParcDialog.Content(title: "Couldn’t open search", message: "Try again.")
        expect(plain.title.map(\.0) == ["Couldn’t open search"] && plain.message?.map(\.0) == ["Try again."]
               && plain.confirm == "OK" && plain.cancel == nil, "A plain alert is a title, a message and OK")
        let failed = ParcDialog.Content(error: Failure())
        expect(failed.title.map(\.0) == ["The disk is full."] && failed.message?.map(\.0) == ["Free some space and try again."],
               "An error alert shows its description and recovery suggestion")
        let retitled = ParcDialog.Content(error: Failure(), title: "Parc couldn’t save these settings.")
        expect(retitled.title.map(\.0) == ["Parc couldn’t save these settings."] && retitled.message?.map(\.0) == ["Free some space and try again."],
               "A given title replaces the description, as setting NSAlert.messageText did")
        expect(ParcDialog.inform(in: host, .init(title: "One")) && !ParcDialog.inform(in: host, .init(title: "Two"))
               && ParcDialog.inform(in: host, .init(title: "Three"), queued: true),
               "An alert refuses a window that shows a sheet unless queued")
        for _ in 0..<2 { (host.attachedSheet?.contentView?.subviews.compactMap { $0 as? ParcDialogButton }.first { $0.primary })?.performClick(nil); drain() }
        expect(host.attachedSheet == nil, "Both alerts dismiss with OK")

        var trio = ParcDialog.Content(title: "The page move needs attention", confirm: "Retry")
        trio.secondary = "Close Page"; trio.auxiliary = "Keep Open"
        let choice = ParcDialog(trio)
        expect(choice.auxiliaryButton!.frame.maxX < choice.secondaryButton!.frame.minX
               && choice.secondaryButton!.frame.maxX < choice.confirmButton.frame.minX && choice.cancelButton == nil
               && !choice.secondaryButton!.hint && !choice.auxiliaryButton!.hint, "Retry, Close Page and Keep Open keep NSAlert's order")
        var chosen: ParcDialog.Response?
        expect(choice.begin(for: host) { chosen = $0 }, "The choice begins")
        choice.panel.cancelOperation(nil); choice.panel.sendEvent(key(53, "\u{1b}", in: choice.panel)); drain()
        expect(chosen == nil && host.attachedSheet === choice.panel, "Escape does not answer a choice that has no Cancel")
        choice.secondaryButton!.performClick(nil); drain()
        expect(chosen == .secondary && host.attachedSheet == nil, "The second button answers with its own response")
        let lone = ParcDialog(.init(title: "Done"))
        var loneResponse: ParcDialog.Response?
        expect(lone.begin(for: host) { loneResponse = $0 }, "The lone OK begins")
        lone.panel.cancelOperation(nil); drain()
        expect(loneResponse == .cancel && host.attachedSheet == nil, "Escape dismisses a lone OK")

        var detailed = ParcDialog.Content(title: "Air Traffic Control Details", confirm: "Done")
        detailed.details = String(repeating: "Could not save the routes. ", count: 40)
        let details = ParcDialog(detailed)
        let detailsText = details.panel.contentView!.subviews.compactMap { $0.subviews.first as? NSScrollView }.first?.documentView as? NSTextView
        expect(detailsText?.string == detailed.details && detailsText?.isEditable == false && detailsText?.isSelectable == true
               && details.confirmButton.title == "Done", "The details are selectable read-only text")

        guard let mark = sample.suppression else { fatalError("Missing checkbox") }
        mark.performClick(nil)
        expect(mark.state == NSControl.StateValue.on, "A click toggles the NSButton switch, which VoiceOver reads as a checkbox")
        mark.state = .off
        expect(mark.showsPointingHand, "The checkbox shows the pointing hand")
        expect(mark.contentTintColor == ParcSelectionMark.tint, "The checkbox takes the selection tint")
        expect(ParcSelectionMark.symbolName(selected: false) == "circle"
               && ParcSelectionMark.symbolName(selected: true) == "checkmark.circle.fill", "The checkbox uses the picker's symbols")
        expect((mark.accessibilityValue() as? String) == "Not selected", "An unchecked mark reads Not selected")
        mark.state = .on
        expect((mark.accessibilityValue() as? String) == "Selected", "A checked mark reads Selected")
        mark.state = .off
        func tinted(_ view: NSView) -> Int {
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            var count = 0
            for x in 0..<rep.pixelsWide { for y in 0..<rep.pixelsHigh {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.9 else { continue }
                if color.blueComponent > 0.9 && color.redComponent < 0.35 && color.greenComponent < 0.35 { count += 1 }
            } }
            return count
        }
        let outline = tinted(mark)
        mark.state = .on
        expect(outline > 0 && tinted(mark) > 2 * outline, "The mark draws an outline circle, filled when checked")
        mark.state = .off

        var focusedContent = ParcDialog.Content(title: [("Rename", false)], confirm: "Rename", cancel: "Cancel",
                                               field: .init(value: "Work", placeholder: "Name", required: false))
        focusedContent.suppression = "Don’t ask again"
        func answer(focus: (ParcDialog) -> Void, press code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) -> ParcDialog.Response? {
            let dialog = ParcDialog(focusedContent)
            var response: ParcDialog.Response?
            expect(dialog.begin(for: host) { response = $0 }, "The focus dialog begins")
            focus(dialog)
            dialog.panel.sendEvent(key(code, characters, flags, in: dialog.panel)); drain()
            if response == nil { dialog.cancelButton!.performClick(nil); drain() }
            return response
        }
        let onField: (ParcDialog) -> Void = { _ = $0.panel.makeFirstResponder($0.textField) }
        let onCheckbox: (ParcDialog) -> Void = { expect($0.panel.makeFirstResponder($0.suppression), "The checkbox takes focus") }
        for (name, focus) in [("field", onField), ("checkbox", onCheckbox)] {
            expect(answer(focus: focus, press: 36, "\r") == .confirm, "Return confirms from the \(name)")
            expect(answer(focus: focus, press: 76, "\u{3}", [.numericPad]) == .confirm, "Keypad Enter confirms from the \(name)")
            expect(answer(focus: focus, press: 53, "\u{1b}") == .cancel, "Escape cancels from the \(name)")
        }
        let spaced = ParcDialog(focusedContent)
        _ = spaced.begin(for: host) { _ in }
        expect(spaced.panel.makeFirstResponder(spaced.suppression), "The checkbox takes focus for Space")
        spaced.panel.sendEvent(key(49, " ", in: spaced.panel))
        drain()
        spaced.panel.sendEvent(key(49, " ", [.option], in: spaced.panel))
        expect(spaced.suppression!.state == NSControl.StateValue.on, "Option-Space does not toggle the checkbox again")
        expect(spaced.suppression!.state == NSControl.StateValue.on && host.attachedSheet === spaced.panel, "Space toggles the checkbox and keeps the dialog open")
        spaced.cancelButton!.performClick(nil); drain()
        let composing = ParcDialog(focusedContent)
        var composed: ParcDialog.Response?
        _ = composing.begin(for: host) { composed = $0 }
        final class Marked: NSTextView { override func hasMarkedText() -> Bool { true } }
        let marked = Marked(frame: NSRect(x: 0, y: 0, width: 50, height: 20))
        composing.panel.contentView!.addSubview(marked)
        _ = composing.panel.makeFirstResponder(marked)
        expect(!composing.panel.performKeyEquivalent(with: key(36, "\r", in: composing.panel)) && composed == nil,
               "A composing input method keeps Return for its candidate")
        marked.removeFromSuperview(); _ = composing.panel.makeFirstResponder(composing.textField)
        composing.cancelButton!.performClick(nil); drain()

        func modal(_ content: ParcDialog.Content, _ act: @escaping (ParcDialog) -> Void) -> ParcDialog.Response {
            let dialog = ParcDialog(content)
            dialog.panel.alphaValue = 0
            DispatchQueue.main.async { act(dialog) }
            return dialog.runModal()
        }
        expect(modal(.init(title: "Restore", confirm: "Retry")) { $0.confirmButton.performClick(nil) } == .confirm, "A modal alert returns its confirm")
        expect(modal(.init(title: "Restore", confirm: "Retry", cancel: "Cancel")) { $0.panel.cancelOperation(nil) } == .cancel, "Escape ends a modal with Cancel")
        var modalChoice = ParcDialog.Content(title: "Update error!", confirm: "OK"); modalChoice.secondary = "Download manually"
        expect(modal(modalChoice) { $0.secondaryButton!.performClick(nil) } == .secondary, "A modal returns its second button")
        print("Parc dialog: \(count) checks passed")
    }
}
