import AppKit
import Testing
@testable import Parc
@testable import ParcCore

private final class ComponentWindow: NSWindow {
    var keyForComponent = true
    override var isKeyWindow: Bool { keyForComponent }
}

struct FavoritePointerTests {
    fileprivate struct Down: Sendable {
        let modifiers: NSEvent.ModifierFlags
        let clicks: Int
        let isKey: Bool
        let expected: FavoritePointerAction?
        let name: String
    }

    fileprivate struct Up: Sendable {
        let modifiers: NSEvent.ModifierFlags
        let clicks: Int
        let isKey: Bool
        let expected: FavoritePointerAction?
        let name: String
    }

    private static let downs: [Down] = [
        Down(modifiers: [], clicks: 1, isKey: true, expected: .activate, name: "primary selection is a down event"),
        Down(modifiers: .shift, clicks: 1, isKey: true, expected: .activate, name: "shift does not introduce range selection"),
        Down(modifiers: .command, clicks: 1, isKey: true, expected: .resetAndSelect, name: "exact command first down resets the original"),
        Down(modifiers: [.command, .shift], clicks: 1, isKey: true, expected: .activate, name: "combined modifiers do not reset"),
        Down(modifiers: [.command, .capsLock], clicks: 1, isKey: true, expected: .activate, name: "complete flags govern command reset"),
        Down(modifiers: .control, clicks: 1, isKey: true, expected: nil, name: "control belongs to the context provider"),
        Down(modifiers: .option, clicks: 1, isKey: true, expected: nil, name: "option has a separate release path"),
        Down(modifiers: [.option, .command], clicks: 1, isKey: true, expected: nil, name: "option with command has a separate release path"),
        Down(modifiers: [], clicks: 2, isKey: true, expected: .resetIfNeeded, name: "a repeated down uses reset eligibility"),
        Down(modifiers: [], clicks: 3, isKey: true, expected: .resetIfNeeded, name: "a triple down uses reset eligibility"),
        Down(modifiers: .option, clicks: 2, isKey: true, expected: .resetIfNeeded, name: "the double down precedes the option gate"),
        Down(modifiers: [], clicks: 1, isKey: false, expected: nil, name: "an inactive window down does not select"),
        Down(modifiers: [], clicks: 2, isKey: false, expected: .resetIfNeeded, name: "a repeated down in an inactive window resets"),
        Down(modifiers: .command, clicks: 2, isKey: false, expected: .resetIfNeeded, name: "a repeated command down in an inactive window resets"),
        Down(modifiers: .command, clicks: 1, isKey: false, expected: nil, name: "command reset needs a first down selection"),
        Down(modifiers: [], clicks: 0, isKey: true, expected: nil, name: "no synthetic zero click activation"),
    ]

    private static let ups: [Up] = [
        Up(modifiers: [], clicks: 1, isKey: true, expected: nil, name: "a plain release is not replayed"),
        Up(modifiers: .command, clicks: 1, isKey: true, expected: nil, name: "a command release is not replayed"),
        Up(modifiers: .shift, clicks: 1, isKey: true, expected: nil, name: "a shift release is not replayed"),
        Up(modifiers: [], clicks: 1, isKey: false, expected: .activate, name: "a non-key first click resolves on release"),
        Up(modifiers: .command, clicks: 1, isKey: false, expected: .activate, name: "a non-key command click resolves ordinarily"),
        Up(modifiers: .option, clicks: 1, isKey: false, expected: .openInSplit, name: "option release keeps its route in a non-key window"),
        Up(modifiers: [], clicks: 2, isKey: false, expected: nil, name: "a double click does not resolve on release"),
        Up(modifiers: [], clicks: 0, isKey: false, expected: nil, name: "a zero click does not resolve on release"),
        Up(modifiers: [.option, .capsLock, .numericPad], clicks: 1, isKey: true, expected: .openInSplit, name: "release ignores modifiers beyond the low four"),
        Up(modifiers: .option, clicks: 2, isKey: true, expected: nil, name: "a repeated release cannot duplicate the double down reset"),
    ]

    @Test(arguments: downs)
    fileprivate func aMouseDownIsMappedToItsAction(_ down: Down) {
        #expect(FavoritePointerPolicy.mouseDown(modifiers: down.modifiers, clickCount: down.clicks, isKey: down.isKey) == down.expected, Comment(rawValue: down.name))
    }

    @Test(arguments: ups)
    fileprivate func aMouseUpIsMappedToItsAction(_ up: Up) {
        #expect(FavoritePointerPolicy.mouseUp(modifiers: up.modifiers, clickCount: up.clicks, isKey: up.isKey) == up.expected, Comment(rawValue: up.name))
    }

    @MainActor private final class Pointer {
        let window = ComponentWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        let tile = FavoriteTile(title: "Original", monogram: "O", url: "https://example.test/home")
        let owner = FavoritePointerOwner(tabID: UUID(), profileID: UUID(), spaceID: UUID(), createdAt: Date())
        var available = true
        var events: [FavoritePointerAction] = []
        var prepared = 0
        var proposals = 0
        var commits = 0

        init() {
            window.isReleasedWhenClosed = false
            tile.frame = NSRect(x: 10, y: 10, width: 60, height: 48)
            window.contentView!.addSubview(tile)
            tile.update(title: "Original", monogram: "O", url: "https://example.test/home", owner: owner)
            tile.canActivate = { [unowned self] in available }
            tile.preparePointerAction = { [unowned self] intent in
                prepared += 1
                var consumed = false
                return { [unowned self] in
                    guard available, !consumed else { return false }
                    consumed = true
                    events.append(intent)
                    return true
                }
            }
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func event(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags = [], _ clicks: Int = 1,
                   _ point: NSPoint = NSPoint(x: 20, y: 20)) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 1, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 12, clickCount: clicks, pressure: 1)!
        }

        func click(_ flags: NSEvent.ModifierFlags = [], _ clicks: Int = 1) {
            tile.mouseDown(with: event(.leftMouseDown, flags, clicks))
            tile.mouseUp(with: event(.leftMouseUp, flags, clicks))
        }

        func session(commit: Bool = true) -> SidebarMoveSession {
            SidebarMoveSession(items: [.tab(owner.tabID)], window: window, validate: { [unowned self] in available },
                               propose: { [unowned self] _, _ in available }, commit: { [unowned self] _, _ in commits += 1; return commit })
        }
    }

    @MainActor @Test func theTileSelectsOnMouseDownBeforeRelease() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown))
        #expect(pointer.events == [.activate])
    }

    @MainActor @Test func aSameItemRedrawDoesNotReplayActivation() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown))
        pointer.tile.selected = true
        pointer.tile.update(title: "Updated title", monogram: "U", url: "https://example.test/current", owner: pointer.owner)
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp))
        #expect(pointer.events == [.activate])
    }

    @MainActor @Test func aRetainedTileRefreshesItsTitleAndSelection() {
        let pointer = Pointer()
        pointer.tile.selected = true
        pointer.tile.update(title: "Updated title", monogram: "U", url: "https://example.test/current", owner: pointer.owner)
        #expect(pointer.tile.accessibilityTitle() == "Updated title")
        #expect(pointer.tile.isAccessibilitySelected())
    }

    @MainActor @Test func aCommandClickRequestsOneOriginalReset() {
        let pointer = Pointer()
        pointer.click(.command)
        #expect(pointer.events == [.resetAndSelect])
    }

    @MainActor @Test func aDoubleDownRequestsAResetNeverRenameOrReleaseActivation() {
        let pointer = Pointer()
        pointer.click([], 2)
        #expect(pointer.events == [.resetIfNeeded])
    }

    @MainActor @Test func anUnavailableTargetIsNotDispatched() {
        let pointer = Pointer()
        pointer.available = false
        pointer.click()
        #expect(pointer.events.isEmpty)
    }

    @MainActor @Test func aDeferredRouteDoesNotActOnDown() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown, .option))
        #expect(pointer.events.isEmpty)
    }

    @MainActor @Test func aCapturedReleaseLeaseRevalidatesAndRefusesAnUnavailableTarget() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown, .option))
        pointer.available = false
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp, .option))
        #expect(pointer.events.isEmpty)
        #expect(pointer.prepared > pointer.events.count)
    }

    @MainActor @Test func aDragRevokesDeferredActivation() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown, .option))
        pointer.tile.mouseDragged(with: pointer.event(.leftMouseDragged, .option))
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp, .option))
        #expect(pointer.events.isEmpty)
    }

    @MainActor @Test func aReleaseOutsideTheTileRefuses() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown, .option))
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp, .option, 1, NSPoint(x: 150, y: 90)))
        #expect(pointer.events.isEmpty)
    }

    @MainActor @Test func aHiddenRoundTripCannotReviveAnOldIntent() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown, .option))
        pointer.tile.isHidden = true
        pointer.tile.isHidden = false
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp, .option))
        #expect(pointer.events.isEmpty)
    }

    @MainActor @Test func aDisabledRoundTripCannotReviveAnOldIntent() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown, .option))
        pointer.tile.isEnabled = false
        pointer.tile.isEnabled = true
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp, .option))
        #expect(pointer.events.isEmpty)
    }

    @MainActor @Test func deactivationCancelsTheExactPendingPhase() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown, .option))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: pointer.window)
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp, .option))
        #expect(pointer.events.isEmpty)
    }

    @MainActor @Test func theSameFavoriteInAnotherSpaceCannotInheritPendingInput() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown, .option))
        let next = FavoritePointerOwner(tabID: pointer.owner.tabID, profileID: pointer.owner.profileID, spaceID: UUID(), createdAt: pointer.owner.createdAt)
        pointer.tile.update(title: "Other Space", monogram: "O", url: "https://example.test/home", owner: next)
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp, .option))
        #expect(pointer.events.isEmpty)
    }

    @MainActor @Test func detachingAndReattachingCancelsTheOriginalPointerOwner() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown, .option))
        pointer.tile.removeFromSuperview()
        pointer.window.contentView!.addSubview(pointer.tile)
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp, .option))
        #expect(pointer.events.isEmpty)
    }

    @MainActor @Test func anOptionReleaseConsumesItsOriginalSplitLeaseOnce() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown, .option))
        pointer.tile.update(title: "Refreshed", monogram: "R", url: "https://example.test/home", owner: pointer.owner)
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp, .option))
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp, .option))
        #expect(pointer.events == [.openInSplit])
    }

    @MainActor @Test func theExcludedMiniBrowserWindowRouteNeverSubstitutesActivation() {
        let pointer = Pointer()
        pointer.click([.option, .command])
        #expect(pointer.events.isEmpty)
    }

    @MainActor @Test func removingOptionBeforeReleaseDoesNotReplayTheDownSelection() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown, .option))
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp))
        #expect(pointer.events.isEmpty)
    }

    @MainActor @Test func releaseModifiersChooseTheOrdinaryFallback() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown, .option))
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp, [.option, .shift]))
        #expect(pointer.events == [.activate])
    }

    @MainActor @Test func optionAddedAfterDownUsesTheResultingOriginalSelection() {
        let pointer = Pointer()
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown))
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp, .option))
        #expect(pointer.events == [.activate, .openInSplit])
    }

    @MainActor @Test func theClickThatActivatesAnInactiveWindowNeverReachesTheTile() {
        let pointer = Pointer()
        #expect(!pointer.tile.acceptsFirstMouse(for: pointer.event(.leftMouseDown)))
    }

    @MainActor @Test func aDeliveredNonKeyDownDoesNotSelect() {
        let pointer = Pointer()
        pointer.window.keyForComponent = false
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown))
        #expect(pointer.events.isEmpty)
    }

    @MainActor @Test func aNonKeyReleasePerformsTheOneOrdinarySelectionLease() {
        let pointer = Pointer()
        pointer.window.keyForComponent = false
        pointer.click()
        #expect(pointer.events == [.activate])
    }

    @MainActor @Test func aDragCapturesTheOriginalOwnerAfterDownActivation() {
        let pointer = Pointer()
        var captured: SidebarMoveSession?
        pointer.tile.beginMove = {
            pointer.proposals += 1
            captured = pointer.session()
            return captured
        }
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown))
        #expect(pointer.proposals == 1)
        #expect(captured?.isValid == true)
    }

    @MainActor @Test func aLaterProducerCannotReplaceTheOriginalDownOwner() {
        let pointer = Pointer()
        pointer.tile.beginMove = { pointer.proposals += 1; return pointer.session() }
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown))
        pointer.tile.beginMove = { pointer.proposals += 10; return pointer.session() }
        pointer.tile.mouseDragged(with: pointer.event(.leftMouseDragged, [], 1, NSPoint(x: 50, y: 20)))
        #expect(pointer.proposals == 1)
    }

    @MainActor @Test func aStaleDragCancelsItsOriginalLeaseWithoutANewQuery() {
        let pointer = Pointer()
        var captured: SidebarMoveSession?
        pointer.tile.beginMove = { captured = pointer.session(); return captured }
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown))
        pointer.available = false
        pointer.tile.mouseDragged(with: pointer.event(.leftMouseDragged, [], 1, NSPoint(x: 50, y: 20)))
        #expect(captured?.ended == true)
        #expect(pointer.tile.sidebarDrag == nil)
        #expect(pointer.commits == 0)
    }

    @MainActor @Test func anUnsupportedOptionCopyNeverBecomesAMove() {
        let pointer = Pointer()
        var captured: SidebarMoveSession?
        pointer.tile.beginMove = { captured = pointer.session(); return captured }
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown, .option))
        pointer.tile.mouseDragged(with: pointer.event(.leftMouseDragged, .option, 1, NSPoint(x: 50, y: 20)))
        #expect(captured?.ended == true)
        #expect(pointer.tile.sidebarDrag == nil)
        #expect(pointer.commits == 0)
    }

    @MainActor @Test func anOrdinaryClickEndsTheUnusedMoveLease() {
        let pointer = Pointer()
        var captured: SidebarMoveSession?
        pointer.tile.beginMove = { captured = pointer.session(); return captured }
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown))
        pointer.tile.mouseUp(with: pointer.event(.leftMouseUp))
        #expect(captured?.ended == true)
        #expect(pointer.commits == 0)
    }

    @MainActor @Test func detachmentCancelsTheCapturedDragOwner() {
        let pointer = Pointer()
        var captured: SidebarMoveSession?
        pointer.tile.beginMove = { captured = pointer.session(); return captured }
        pointer.tile.mouseDown(with: pointer.event(.leftMouseDown))
        pointer.tile.removeFromSuperview()
        #expect(captured?.ended == true)
        #expect(pointer.commits == 0)
    }

    @MainActor @Test func oneMoveTransactionCannotReplay() {
        let pointer = Pointer()
        let session = pointer.session()
        let target = SidebarContainerLocation(spaceID: pointer.owner.spaceID, folderID: nil, section: .favorite, profileID: pointer.owner.profileID)
        #expect(session.move(to: target, before: nil))
        #expect(!session.move(to: target, before: nil))
        #expect(pointer.commits == 1)
    }
}
