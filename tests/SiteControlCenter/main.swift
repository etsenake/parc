import AppKit
import SwiftUI

@main
struct SiteControlCenterChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            precondition(condition(), message)
        }
        let arguments = CommandLine.arguments
        expect(SiteControlCenterArtwork.directory == Bundle.main.resourceURL?.appendingPathComponent("SiteControlCenter", isDirectory: true)
               && SiteControlCenterArtwork.controlCenter != nil, "the artwork loads from the bundle's SiteControlCenter resources")

        expect(SiteControlCenterMetrics.padding == SidebarPlusMenuView.inset && SiteControlCenterMetrics.width == 232,
               "the card keeps its tiles and spacing inside the plus HUD's edge inset")
        expect(SiteControlCenterMetrics.button == CGSize(width: 48, height: 32) &&
               SiteControlCenterMetrics.extensionIcon == 16 && SiteControlCenterMetrics.pin == 14,
               "extension tiles stay 48×32 with a 16-point icon and 14-point pin")

        for (name, size) in [("icon-control-center", NSSize(width: 18, height: 18)),
                             ("copy-url", NSSize(width: 19, height: 19)),
                             ("capture-full-page", NSSize(width: 19, height: 19)),
                             ("popup-blocked", NSSize(width: 18, height: 18)),
                             ("redirect-blocked", NSSize(width: 18, height: 18))] {
            let image = SiteControlCenterArtwork.image(name)
            expect(image?.size == size && image?.isTemplate == true, "\(name) loads as a \(size) template")
            expect(image?.representations.contains { $0.pixelsWide == Int(size.width) * 2 } == true,
                   "\(name) keeps its 2× rendition")
            expect(image?.representations.contains { $0 is NSPDFImageRep } == true, "\(name) keeps its vector rendition")
        }
        expect(SiteControlCenterArtwork.controlCenter === SiteControlCenterArtwork.image("icon-control-center"),
               "the entry glyph is the cached bundled image")

        let model = SiteControlCenterModel()
        expect(model.buttons == [.share, .copyURL], "without capture only Share and Copy URL remain")
        model.captureAvailable = true
        expect(model.buttons == [.share, .captureVisiblePage, .capture, .captureFullPage],
               "Visible Area replaces the excluded Boost control beside Portion and Full Page")
        model.canCopy = true
        expect(model.isEnabled(.copyURL) && !model.isEnabled(.share) && !model.isEnabled(.capture),
               "each button follows its own availability")
        model.shortcuts = [.copyURL: "⇧⌘C"]
        expect(model.help(.copyURL) == "Copy URL  ⇧⌘C" && model.help(.capture) == "Capture a portion of this page",
               "accessibility hints carry the titles and the active shortcut")
        expect(model.help(.captureVisiblePage) == "Capture the visible area" && model.help(.captureFullPage) == "Capture the full page",
               "capture hints identify the actual acquisition mode")

        func ext(_ id: String, pinned: Bool = false) -> SiteControlCenterModel.Extension {
            .init(id: id, name: "Extension " + id, tooltip: "", accessibilityLabel: "", icon: nil, isPinned: pinned, canChangePin: true)
        }
        model.extensions = [ext("a", pinned: true), ext("b"), ext("c"), ext("d"), ext("e")]
        model.moveFocus(1)
        expect(model.focusedExtension == "a", "the picker starts at the first extension")
        model.moveFocus(-1)
        expect(model.focusedExtension == "e", "moving back from the first wraps to the last")
        model.moveFocus(1)
        expect(model.focusedExtension == "a", "moving on from the last wraps to the first")
        model.focusedExtension = nil
        model.moveFocus(-1)
        expect(model.focusedExtension == "a", "without a focused action either direction selects the first original action")
        model.extensions = []
        model.moveFocus(1)
        expect(model.focusedExtension == nil, "an empty snapshot clears its retired extension target")
        model.extensions = [ext("a", pinned: true), ext("b"), ext("c"), ext("d"), ext("e")]
        model.focusedExtension = nil

        typealias Input = SiteControlCenterController.PickerInput
        for code: UInt16 in [123, 126] {
            expect(Input.resolve(type: .keyDown, keyCode: code, modifiers: .command) == .previous, "left/up move backward")
        }
        for code: UInt16 in [124, 125, 14] {
            expect(Input.resolve(type: .keyDown, keyCode: code, modifiers: .command) == .next, "right/down/physical E move forward")
        }
        expect(Input.resolve(type: .keyDown, keyCode: 36, modifiers: .command) == .select, "Return selects")
        expect(Input.resolve(type: .flagsChanged, keyCode: 55, modifiers: []) == .select, "Command release selects before key-code interpretation")
        for code: UInt16 in [53, 76, 0, 48] {
            expect(Input.resolve(type: .keyDown, keyCode: code, modifiers: .command) == .cancel, "Escape, keypad Enter and unrelated keys cancel")
        }
        expect(Input.resolve(type: .flagsChanged, keyCode: 56, modifiers: [.command, .shift]) == .cancel,
               "another held-Command modifier change cancels rather than inventing navigation")

        model.settings = [
            .init(id: "developerMode", symbol: "hammer.fill", symbolSize: 13, symbolWeight: .medium, title: "Developer Mode",
                  subtitle: "Off", isOn: false, isEnabled: true),
            .init(id: "permission:0:1", symbol: "gearshape.fill", symbolSize: 13, symbolWeight: .medium, title: "Camera",
                  subtitle: "Allowed", isOn: true, isEnabled: true)]
        model.isSecure = true
        let host = NSHostingView(rootView: SiteControlCenterView(model: model))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        expect(host.fittingSize.width == 232, "the hosted content is exactly 232 points wide")
        let full = host.fittingSize.height

        let tooltipWindow = NSWindow(contentRect: NSRect(origin: .zero, size: host.frame.size), styleMask: .borderless,
                                     backing: .buffered, defer: false)
        tooltipWindow.isReleasedWhenClosed = false
        tooltipWindow.contentView = host
        host.layoutSubtreeIfNeeded()
        func anchors(_ view: NSView) -> [TooltipAnchorView] { ((view as? TooltipAnchorView).map { [$0] } ?? []) + view.subviews.flatMap(anchors) }
        let anchored = anchors(host)
        let tooltips = Dictionary(anchored.compactMap { $0.parcTooltip.map { ($0.label, $0) } }) { first, _ in first }
        expect(Set(tooltips.keys) == ["Share", "Capture the visible area", "Capture a portion of this page", "Capture the full page",
                                      "Extension a", "Extension b", "Extension c", "Extension d", "Extension e", "Unpin", "Add Extension",
                                      "Manage Extensions", "All Site Settings", "Developer Mode", "Camera", "Secure", "More"],
               "every action, extension, the pin badge, Add Extension and the restyle's other items carry a tooltip")
        expect(tooltips["Share"]?.shortcut == nil && tooltips["Capture the full page"]?.shortcut == .command("captureFullPage:")
               && tooltips["Capture a portion of this page"]?.shortcut == .command("capturePage:")
               && tooltips["Capture the visible area"]?.shortcut == .command("captureVisiblePage:")
               && SiteControlCenterModel.Button.copyURL.commandID == "copyCurrentURL:",
               "the actions' keycaps follow their commands' live bindings")
        expect(tooltips.values.allSatisfy { $0.palette == nil && $0.anchor == .bottomTrailing },
               "items take their window controller's palette: the restyle themes it")
        expect(anchored.allSatisfy { anchor in
            let centre = anchor.convert(NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: nil)
            return host.hitTest(host.superview?.convert(centre, from: nil) ?? centre).map { !($0 is TooltipAnchorView) } ?? true
        }, "ordinary hit tests pass through every anchor")
        tooltipWindow.contentView = nil
        tooltipWindow.close()

        do {
            let badge = ExtensionActionBadge(text: "12", textColor: .white, backgroundColor: .systemBlue)
            let badged = SiteControlCenterModel()
            badged.extensions = [
                .init(id: "unbadged", name: "Unbadged", tooltip: "", accessibilityLabel: "", icon: nil, isPinned: true,
                      canChangePin: true, badge: badge, badgeText: "12"),
                .init(id: "baked", name: "Baked", tooltip: "", accessibilityLabel: "", icon: nil, isPinned: false,
                      canChangePin: true, badgeText: "3")]
            let badgeHost = NSHostingView(rootView: SiteControlCenterView(model: badged))
            badgeHost.frame.size = badgeHost.fittingSize
            let badgeWindow = NSWindow(contentRect: NSRect(origin: .zero, size: badgeHost.frame.size), styleMask: .borderless,
                                       backing: .buffered, defer: false)
            badgeWindow.isReleasedWhenClosed = false
            badgeWindow.contentView = badgeHost
            badgeHost.layoutSubtreeIfNeeded()
            func badges(_ view: NSView) -> [ExtensionActionBadgeView] {
                ((view as? ExtensionActionBadgeView).map { [$0] } ?? []) + view.subviews.flatMap(badges)
            }
            let drawn = badges(badgeHost)
            let expected = ExtensionActionBadgeMetrics.frame(text: "12", in: NSRect(origin: .zero, size: SiteControlCenterMetrics.button))
            expect(drawn.count == 1 && drawn[0].badge == badge && drawn[0].frame.size == expected.size,
                   "the shell draws the strips' badge once, over the unbadged canvas only")
            expect(expected.maxX <= SiteControlCenterMetrics.button.width - SiteControlCenterMetrics.pin + 3
                   && expected.maxY <= SiteControlCenterMetrics.button.height - SiteControlCenterMetrics.pin + 3,
                   "the top-right badge stays clear of the bottom-right pin badge")
            badgeWindow.contentView = nil
            badgeWindow.close()
        }
        model.isSecure = nil
        model.settings = []
        model.extensions = (0..<3).map { ext(String($0)) }
        let bare = NSHostingView(rootView: SiteControlCenterView(model: model)).fittingSize
        expect(bare.width == 232 && bare.height < full, "settings and footer collapse when absent")
        model.extensions = (0..<4).map { ext(String($0)) }
        let twoRows = NSHostingView(rootView: SiteControlCenterView(model: model)).fittingSize
        expect(twoRows.height == bare.height + 32 + 8, "a fifth item (Add Extension) starts a second 32-point row 8 points below")

        let button = CGRect(x: 500, y: 700, width: 32, height: 32)
        let parentFrame = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let hung = SiteControlCenterPlacement.windowFrame(anchor: button, card: CGSize(width: 232, height: 300), below: true,
                                                          parent: parentFrame, screen: parentFrame)
        expect(hung.below && hung.frame == CGRect(x: 400, y: 700 - 306, width: 232, height: 306) && hung.tailX == 116,
               "the card hangs centred below the button, its tail touching the button's edge")
        let edge = SiteControlCenterPlacement.windowFrame(anchor: CGRect(x: -6, y: 700, width: 32, height: 32),
                                                          card: CGSize(width: 232, height: 300), below: true,
                                                          parent: parentFrame, screen: parentFrame)
        expect(edge.frame.minX == 0 && edge.tailX == SidebarPlusMenuPlacement.cornerRadius + SidebarPlusMenuPlacement.tailBase / 2,
               "near the window's edge the card stays inside and the tail stops at the corner")
        let low = SiteControlCenterPlacement.windowFrame(anchor: CGRect(x: 500, y: 100, width: 32, height: 32),
                                                         card: CGSize(width: 232, height: 300), below: true,
                                                         parent: parentFrame, screen: parentFrame)
        expect(!low.below && low.frame.minY == 132, "without room below, the card opens above the button")
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let offRight = SiteControlCenterPlacement.windowFrame(anchor: CGRect(x: 1420, y: 800, width: 32, height: 32),
                                                              card: CGSize(width: 232, height: 300), below: true,
                                                              parent: CGRect(x: 900, y: 300, width: 700, height: 575), screen: screen)
        expect(offRight.frame.maxX == screen.maxX, "a window running off the screen keeps the card on it")
        let short = SiteControlCenterPlacement.windowFrame(anchor: CGRect(x: 500, y: 350, width: 32, height: 32),
                                                           card: CGSize(width: 232, height: 380), below: true,
                                                           parent: CGRect(x: 0, y: 0, width: 1000, height: 400), screen: screen)
        expect(!short.below && short.frame.minY == 382 && short.frame.maxX <= 1000,
               "with room on neither side inside the window it hangs past the window rather than cover its button")
        let nowhere = SiteControlCenterPlacement.windowFrame(anchor: CGRect(x: 500, y: 400, width: 32, height: 32),
                                                             card: CGSize(width: 232, height: 600), below: true,
                                                             parent: CGRect(x: 0, y: 0, width: 1000, height: 875), screen: screen)
        expect(!nowhere.below && nowhere.frame.maxY == screen.maxY,
               "with room on neither side anywhere it takes the roomier one, on screen")
        let tall = SiteControlCenterPlacement.windowFrame(anchor: CGRect(x: 500, y: 560, width: 32, height: 32),
                                                          card: CGSize(width: 232, height: 400), below: true,
                                                          parent: CGRect(x: 0, y: 300, width: 1000, height: 300), screen: screen)
        expect(tall.below && tall.frame.maxY == 560 && tall.frame.minY >= screen.minY,
               "a card taller than the window hangs past it but stays on screen")

        let content = NSView(frame: .zero)
        let colors = SiteControlCenterColors(theme: SpaceTheme()).menu
        let top = ParcMenuChrome(content: content, size: NSSize(width: 232, height: 100), colors: colors, tailX: 116, tailOnTop: true)
        expect(content.frame == NSRect(x: 0, y: 0, width: 232, height: 100) && top.tailTip == NSPoint(x: 116, y: 106),
               "a hanging card's tail tip is above it")
        let menu = SidebarPlusMenuView(rows: SidebarPlusMenuModel.rows(privateBrowsing: false, canCreateEasel: true,
                                                                        canCreateNote: true, canSplit: true),
                                       colors: colors) { _ in }
        let plus = SidebarPlusMenuChrome(card: menu, tailX: 50)
        expect(menu.frame.origin.y == SidebarPlusMenuPlacement.tailHeight && plus.tailTip == NSPoint(x: 50, y: 0),
               "the plus HUD keeps its card above a tail pointing down")

        let card = SiteControlCenterCard(content: NSView(frame: .zero), colors: colors)
        var escaped = 0
        card.onEscape = { escaped += 1 }
        card.cancelOperation(nil)
        expect(escaped == 1 && card.acceptsFirstResponder, "the card takes key input and closes on Escape")

        var closed = 0
        let presenter = SiteControlCenterController(model: SiteControlCenterModel())
        presenter.onClose = { closed += 1 }
        presenter.close(); presenter.close()
        expect(closed == 1 && presenter.model.onButton == nil && !presenter.isAwaitingNativeClose,
               "closing an unshown card runs its cleanup once and drops callbacks")
        var after = 0
        let immediateDismissal = SiteControlCenterDismissal()
        immediateDismissal.close(SiteControlCenterController(model: SiteControlCenterModel())) { after += 1 }
        expect(after == 0, "an after-close action waits for the next turn")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        expect(after == 1, "an after-close action runs once the card has gone")

        final class Closing: SiteControlCenterPresentation {
            var isAwaitingNativeClose = true
            var onDidClose: (() -> Void)?
            func close() {}
            func finishClosing() {
                isAwaitingNativeClose = false
                let done = onDidClose; onDidClose = nil; done?()
            }
        }
        let dismissal = SiteControlCenterDismissal()
        func beginNativeClose() -> Closing {
            let card = Closing()
            dismissal.track(card)
            return card
        }
        var dispatched = 0
        let firstClosing = beginNativeClose()
        dismissal.close(nil) { dispatched += 100 }
        dismissal.close(nil) { dispatched += 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        expect(dispatched == 0, "a second extension gesture still waits after current-session removal")
        firstClosing.finishClosing()
        expect(dispatched == 0, "native completion queues rather than immediately dispatching")
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        expect(dispatched == 1, "the latest gesture dispatches once after the native barrier ends")

        let closingBeforeCancel = beginNativeClose()
        dismissal.close(nil) { dispatched += 100 }
        dismissal.close(nil)
        closingBeforeCancel.finishClosing()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        expect(dispatched == 1, "an unrelated dismiss cancels work while native dismissal is pending")
        let closingBeforeQueuedCancel = beginNativeClose()
        dismissal.close(nil) { dispatched += 100 }
        closingBeforeQueuedCancel.finishClosing()
        dismissal.close(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        expect(dispatched == 1, "an unrelated dismiss cancels work already queued by didClose")

        let oldClosing = beginNativeClose()
        let newClosing = beginNativeClose()
        dismissal.close(nil) { dispatched += 1 }
        newClosing.finishClosing()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        expect(dispatched == 1, "closing a replacement cannot bypass an older native dismissal")
        oldClosing.finishClosing()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        expect(dispatched == 2, "all original native barriers finish before the replacement action dispatches")

        var ownerRevision = 1
        let changingOwner = beginNativeClose()
        dismissal.close(nil, when: { ownerRevision == 1 }) { dispatched += 100 }
        ownerRevision = 2
        changingOwner.finishClosing()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        expect(dispatched == 2, "An owner changed during native dismissal cannot receive the old capture action")
        let changingAfterClose = beginNativeClose()
        dismissal.close(nil, when: { ownerRevision == 2 }) { dispatched += 100 }
        changingAfterClose.finishClosing()
        ownerRevision = 3
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        expect(dispatched == 2, "An owner changed after didClose but before dispatch also rejects the old action")
        dismissal.close(nil, when: { ownerRevision == 3 }) { dispatched += 1 }
        expect(dispatched == 3, "The original current owner still executes once when the barrier is clear")

        let delayed = SiteControlCenterController(model: SiteControlCenterModel())
        var delayedClosed = 0
        delayed.onClose = { delayedClosed += 1 }
        let detachedAnchor = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        delayed.show(relativeTo: detachedAnchor.bounds, of: detachedAnchor, preferredEdge: .maxY, after: .milliseconds(10), expectedWindow: nil, when: { true })
        expect(delayed.isShown && !delayed.isAwaitingNativeClose, "a pending address-pill show counts as shown before the card opens")
        delayed.close()
        expect(!delayed.isShown && delayedClosed == 1, "closing cancels the pending show and cleans up once")
        delayed.onClose = { delayedClosed += 100 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        expect(!delayed.isShown && !delayed.isAwaitingNativeClose && delayedClosed == 1,
               "a stale delayed show neither opens nor ends anything")
        let windowless = SiteControlCenterController(model: SiteControlCenterModel())
        var windowlessClosed = 0
        windowless.onClose = { windowlessClosed += 1 }
        windowless.show(relativeTo: detachedAnchor.bounds, of: detachedAnchor, preferredEdge: .maxY, after: .milliseconds(10), expectedWindow: nil, when: { true })
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        expect(!windowless.isShown && windowlessClosed == 1, "an anchor that left its window ends the session instead of opening")

        let ownerWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        let ownedAnchor = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        ownerWindow.contentView?.addSubview(ownedAnchor)
        let interrupted = SiteControlCenterController(model: SiteControlCenterModel())
        var ownerCurrent = true, interruptedClosed = 0
        interrupted.onClose = { interruptedClosed += 1 }
        interrupted.show(relativeTo: ownedAnchor.bounds, of: ownedAnchor, preferredEdge: .maxY,
                         after: .milliseconds(10), expectedWindow: ownerWindow, when: { ownerCurrent })
        ownerCurrent = false
        let interruptionDeadline = Date().addingTimeInterval(2)
        while interrupted.isShown && Date() < interruptionDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        expect(!interrupted.isShown && interruptedClosed == 1,
               "an owner lost during delayed presentation closes without showing")

        let otherWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        let moved = SiteControlCenterController(model: SiteControlCenterModel())
        var movedClosed = 0
        moved.onClose = { movedClosed += 1 }
        moved.show(relativeTo: ownedAnchor.bounds, of: ownedAnchor, preferredEdge: .maxY,
                   after: .milliseconds(10), expectedWindow: ownerWindow, when: { true })
        otherWindow.contentView?.addSubview(ownedAnchor)
        let migrationDeadline = Date().addingTimeInterval(2)
        while moved.isShown && Date() < migrationDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        expect(!moved.isShown && movedClosed == 1, "an anchor moved to another window cannot show")
        let mismatch = SiteControlCenterController(model: SiteControlCenterModel())
        var mismatchClosed = 0
        mismatch.onClose = { mismatchClosed += 1 }
        mismatch.show(relativeTo: ownedAnchor.bounds, of: ownedAnchor, preferredEdge: .maxY,
                      expectedWindow: ownerWindow, when: { true })
        expect(!mismatch.isShown && mismatchClosed == 1, "a mismatched immediate anchor cannot show")

        let click = SiteControlCenterAlternateClick.ClickView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        expect(click.hitTest(NSPoint(x: 5, y: 5)) == nil, "without a secondary click the layer is transparent")

        NSApplication.shared.setActivationPolicy(.prohibited)
        final class Anchor: NSView {
            var onDown: (() -> Void)?, onUp: (() -> Void)?
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
            override func mouseDown(with event: NSEvent) { onDown?() }
            override func mouseUp(with event: NSEvent) { onUp?() }
        }
        func parentAndAnchor() -> (NSWindow, Anchor) {
            let parent = NSWindow(contentRect: NSRect(x: -12_000, y: -12_000, width: 600, height: 700),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            parent.isReleasedWhenClosed = false
            parent.appearance = NSAppearance(named: .darkAqua)
            let anchor = Anchor(frame: NSRect(x: 280, y: 640, width: 32, height: 32))
            parent.contentView?.addSubview(anchor)
            parent.orderFront(nil)
            return (parent, anchor)
        }
        func waitUntil(_ done: () -> Bool) {
            let deadline = Date().addingTimeInterval(2)
            while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        }
        let escapeKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                         context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                         isARepeat: false, keyCode: 53)!
        for path in ["escape", "resign-key", "deactivate", "parent-close", "detached"] {
            let (parent, anchor) = parentAndAnchor()
            let controller = SiteControlCenterController(model: SiteControlCenterModel())
            var closed = 0, didClose = 0, detached = 0
            controller.onClose = { closed += 1 }
            controller.onDidClose = { didClose += 1 }
            controller.onDetach = { detached += 1 }
            controller.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY, expectedWindow: parent, when: { true })
            guard let panel = parent.childWindows?.first as? SiteControlCenterWindow else {
                fatalError("SiteControlCenter: \(path) opens the card as the parent's child window")
            }
            expect(controller.isShown && panel.isVisible && panel.canBecomeKey && panel.accessibilityRole() == .popover
                   && panel.accessibilityLabel() == "Site Control Center", "\(path): a visible child card announced as a popover")
            expect(panel.firstResponder is NSHostingView<SiteControlCenterView>, "\(path): the hosted buttons take keyboard focus")
            expect(panel.appearance?.name == .darkAqua, "\(path): the card takes its parent's appearance")
            expect(controller.isAnchored(to: anchor) && panel.frame.maxY <= parent.convertToScreen(anchor.frame).minY + 0.5,
                   "\(path): the card hangs below its button")
            switch path {
            case "escape": panel.sendEvent(escapeKey)
            case "resign-key": panel.resignKey()
            case "deactivate": NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            case "parent-close": parent.close()
            default:
                let press = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 4, y: panel.frame.height - 12),
                                               modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                               eventNumber: 1, clickCount: 1, pressure: 1)!
                panel.onDragOut?(press)
                expect(controller.isDetached && detached == 1 && parent.childWindows?.isEmpty != false && panel.isVisible,
                       "dragging tears the card off its button")
                panel.resignKey()
                NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                expect(controller.isShown && closed == 0, "a detached card stays open when it loses key or the app deactivates")
                panel.sendEvent(escapeKey)
            }
            waitUntil { didClose > 0 }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            expect(closed == 1 && didClose == 1 && !controller.isShown && !panel.isVisible,
                   "\(path) closes the card, onClose and onDidClose once each")
            if path != "parent-close" { parent.close() }
        }

        do {
            let (parent, anchor) = parentAndAnchor()
            let first = SiteControlCenterController(model: SiteControlCenterModel())
            first.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY, expectedWindow: parent, when: { true })
            let panel = parent.childWindows?.first
            var reopened: SiteControlCenterController?
            var reopenedClosed = 0
            anchor.onDown = { panel?.resignKey() }
            anchor.onUp = {
                let next = SiteControlCenterController(model: SiteControlCenterModel())
                next.onClose = { reopenedClosed += 1 }
                next.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY, expectedWindow: parent, when: { true })
                reopened = next
            }
            let point = anchor.convert(NSPoint(x: 16, y: 16), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                               windowNumber: parent.windowNumber, context: nil, eventNumber: 4242,
                                               clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                NSApp.postEvent(event, atStart: false)
                if let next = NSApp.nextEvent(matching: NSEvent.EventTypeMask(type: type), until: Date().addingTimeInterval(1),
                                              inMode: .default, dequeue: true) {
                    NSApp.sendEvent(next)
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            expect(!first.isShown && reopened?.isShown == false && reopenedClosed == 1
                   && !NSApp.windows.contains { $0 is SiteControlCenterWindow && $0.isVisible },
                   "the press that closed the card does not reopen it")
            parent.close()
        }
        expect(!NSApp.windows.contains { $0 is SiteControlCenterWindow && $0.isVisible },
               "no delayed or refused show left a card open")

        do {
            let (parent, button) = parentAndAnchor()
            button.frame.origin.x = 520
            let grown = SiteControlCenterModel()
            let controller = SiteControlCenterController(model: grown)
            controller.show(relativeTo: button.bounds, of: button, preferredEdge: .minY, expectedWindow: parent, when: { true })
            guard let panel = parent.childWindows?.first as? SiteControlCenterWindow,
                  let before = panel.contentView as? ParcMenuChrome else { fatalError("SiteControlCenter: the re-hang card opens") }
            button.frame.origin.x = 560
            grown.settings = [.init(id: "developerMode", symbol: "hammer.fill", symbolSize: 13, symbolWeight: .medium,
                                    title: "Developer Mode", subtitle: "Off", isOn: false, isEnabled: true)]
            waitUntil { (panel.contentView as? ParcMenuChrome).map { $0 !== before } ?? false }
            let after = panel.contentView as? ParcMenuChrome
            expect(before.tailX == 168 && after?.tailX == 208 && after?.tailOnTop == true,
                   "a taller card follows its moved button, its tail re-hung on the button")
            expect(panel.firstResponder is NSHostingView<SiteControlCenterView>, "re-hanging keeps the hosted buttons' keyboard focus")
            controller.close()
            waitUntil { !panel.isVisible }
            parent.close()
        }

        do {
            let (parent, button) = parentAndAnchor()
            let pressed = SiteControlCenterModel()
            pressed.canShare = true; pressed.captureAvailable = true; pressed.canCapture = true
            let controller = SiteControlCenterController(model: pressed)
            var fired: [SiteControlCenterModel.Button] = []
            pressed.onButton = { fired.append($0) }
            controller.show(relativeTo: button.bounds, of: button, preferredEdge: .minY, expectedWindow: parent, when: { true })
            guard let panel = parent.childWindows?.first as? SiteControlCenterWindow else { fatalError("SiteControlCenter: the pressed card opens") }
            waitUntil { controller.rect(for: .share) != nil }
            func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: panel.windowNumber, context: nil, eventNumber: 77, clickCount: 1,
                                   pressure: type == .leftMouseUp ? 0 : 1)!
            }
            func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            guard let (rect, view) = controller.rect(for: .share) else { fatalError("SiteControlCenter: Share has a frame") }
            let tile = view.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
            expect(SiteControlCenterWindow.isItem(at: tile, in: panel.contentView), "the Share tile is an item")
            panel.sendEvent(mouse(.leftMouseDown, tile)); settle()
            panel.sendEvent(mouse(.leftMouseUp, tile)); settle()
            expect(fired == [.share], "a plain click on the tile reaches its button")
            fired.removeAll()
            let away = NSPoint(x: tile.x, y: tile.y - 60)
            panel.sendEvent(mouse(.leftMouseDown, tile)); settle()
            panel.sendEvent(mouse(.leftMouseDragged, NSPoint(x: tile.x, y: tile.y - 20))); settle()
            panel.sendEvent(mouse(.leftMouseDragged, away)); settle()
            panel.sendEvent(mouse(.leftMouseUp, away)); settle()
            expect(!controller.isDetached && fired.isEmpty && controller.isShown && parent.childWindows?.isEmpty == false,
                   "a drag that starts on a tile neither detaches the card nor fires the tile")
            let background = NSPoint(x: 3, y: 3)
            expect(!SiteControlCenterWindow.isItem(at: background, in: panel.contentView), "the card's corner is background")
            panel.sendEvent(mouse(.leftMouseDown, background))
            panel.sendEvent(mouse(.leftMouseDragged, NSPoint(x: 5, y: 3)))
            expect(!controller.isDetached, "a 2-point drag does not detach")
            panel.sendEvent(mouse(.leftMouseDragged, NSPoint(x: 9, y: 3)))
            panel.sendEvent(mouse(.leftMouseUp, NSPoint(x: 9, y: 3))); settle()
            expect(controller.isDetached && parent.childWindows?.isEmpty != false && panel.isVisible && fired.isEmpty,
                   "a background drag past 3 points tears the card off")
            expect(panel.firstResponder is NSHostingView<SiteControlCenterView>, "the detached card keeps keyboard focus")
            panel.sendEvent(escapeKey)
            waitUntil { !panel.isVisible }
            expect(!controller.isShown, "Escape closes the detached card")
            parent.close()
        }

        if arguments.count > 1 {
            let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let sample = SiteControlCenterModel()
            sample.canCopy = true; sample.canShare = true; sample.captureAvailable = true; sample.canCapture = true
            sample.extensions = [ext("a", pinned: true), ext("b"), ext("c")]
            sample.settings = [
                .init(id: "preview", symbol: "filemenu.and.cursorarrow", symbolSize: 14, symbolWeight: .bold, title: "Preview",
                      subtitle: "Enabled", isOn: true, isEnabled: true),
                .init(id: "developerMode", symbol: "hammer.fill", symbolSize: 13, symbolWeight: .medium, title: "Developer Mode",
                      subtitle: "Off", isOn: false, isEnabled: true),
                .init(id: "permission:0:1", symbol: "gearshape.fill", symbolSize: 13, symbolWeight: .medium, title: "Location",
                      subtitle: "Blocked", isOn: false, isEnabled: true)]
            sample.isSecure = true
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let view = NSHostingView(rootView: SiteControlCenterView(model: sample))
                view.appearance = NSAppearance(named: appearance)
                view.frame.size = view.fittingSize
                let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.backgroundColor = name == "dark" ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.95, alpha: 1)
                window.contentView = view
                view.layoutSubtreeIfNeeded()
                view.display()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("scc-\(name).png"))
            }
        }
        print("PASS: \(assertions) Site Control Center assertions")
    }
}
