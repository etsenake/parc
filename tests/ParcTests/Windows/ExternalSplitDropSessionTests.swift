import AppKit
import ParcCore
import Testing
@testable import Parc

@MainActor private final class Scene {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    let drag: SplitDropDragInfo
    var valid = true
    var commits = 0

    init() {
        window.isReleasedWhenClosed = false
        window.contentView = host
        drag = SplitDropDragInfo(window: window)
        drag.writeURL("https://native.invalid")
    }

    func session(_ commitResult: Bool = true) -> ExternalSplitDropSession {
        ExternalSplitDropSession(host: host, info: drag, frames: [host.bounds], orientation: .horizontal,
            validate: { [self] in valid }, insertionColor: { .black }, canPropose: { _, _ in true },
            commit: { [self] _, _ in commits += 1; return commitResult })!
    }

    func trackedSession() -> ExternalSplitDropSession {
        ExternalSplitDropSession(host: host, info: drag, frames: [host.bounds], orientation: .horizontal,
            validate: { true }, insertionColor: { .black }, canPropose: { _, _ in true }, commit: { _, _ in true })!
    }
}

@MainActor struct ExternalSplitDropSessionTests {
    struct PasteboardCase: Sendable, CustomTestStringConvertible {
        let name: String
        let types: [(String, String)]
        let host: String?
        var testDescription: String { name }
        static let all = [
            PasteboardCase(name: "a public URL has precedence over a string", types: [("public.url", "https://native.invalid/original?plus=a+b"), ("public.utf8-plain-text", "https://fallback.invalid")], host: "native.invalid"),
            PasteboardCase(name: "a single literal string is a fallback", types: [("public.utf8-plain-text", "https://string.invalid")], host: "string.invalid"),
            PasteboardCase(name: "a file drag stays with the renderer", types: [("public.file-url", "file:///tmp/test"), ("public.url", "https://native.invalid")], host: nil),
            PasteboardCase(name: "an internal sidebar split item keeps its move owner", types: [("org.parc.sidebar-split-drag", "opaque"), ("public.url", "https://native.invalid")], host: nil),
            PasteboardCase(name: "an internal sidebar move item keeps its move owner", types: [("org.parc.sidebar-item-move", "opaque"), ("public.url", "https://native.invalid")], host: nil),
        ]
    }

    @Test(arguments: PasteboardCase.all)
    func readURLAdmitsOnlyAnExternalLink(_ pasteboardCase: PasteboardCase) {
        let drag = SplitDropDragInfo()
        drag.write(pasteboardCase.types.map { (NSPasteboard.PasteboardType($0.0), $0.1) })
        #expect(ExternalSplitDropSession.readURL(drag.draggingPasteboard)?.host == pasteboardCase.host)
    }

    @Test func aPluralPayloadIsNotSilentlyReduced() {
        let drag = SplitDropDragInfo()
        let one = NSPasteboardItem(), two = NSPasteboardItem()
        one.setString("https://one.invalid", forType: .URL)
        two.setString("https://two.invalid", forType: .URL)
        drag.draggingPasteboard.clearContents()
        drag.draggingPasteboard.writeObjects([one, two])
        #expect(ExternalSplitDropSession.readURL(drag.draggingPasteboard) == nil)
    }

    @Test func aLinkIsAdmittedAsACopyWithoutAddingAnOverlay() {
        let scene = Scene()
        #expect(scene.session().update(scene.drag) == .copy)
        #expect(scene.host.subviews.isEmpty)
    }

    @Test func anExpiredOwnerCannotCommit() {
        let scene = Scene()
        let session = scene.session()
        scene.valid = false
        #expect(session.update(scene.drag).isEmpty)
        #expect(!session.perform(scene.drag))
        #expect(scene.commits == 0)
        #expect(scene.host.subviews.isEmpty)
    }

    @Test func aChangedPasteboardCannotRetarget() {
        let scene = Scene()
        let session = scene.session()
        scene.drag.writeURL("https://replacement.invalid")
        #expect(session.update(scene.drag).isEmpty)
        #expect(!session.perform(scene.drag))
    }

    @Test func aSessionCommitsOnceAndNeverRepeats() {
        let scene = Scene()
        let session = scene.session()
        #expect(session.perform(scene.drag))
        #expect(scene.commits == 1)
        #expect(!session.perform(scene.drag))
        #expect(scene.commits == 1)
        #expect(scene.host.subviews.isEmpty)
    }

    @Test func aRefusedCommitReturnsTheFailure() {
        let scene = Scene()
        #expect(!scene.session(false).perform(scene.drag))
        #expect(scene.commits == 1)
    }

    @Test func endingASessionCancelsIt() {
        let scene = Scene()
        let session = scene.session()
        session.end()
        #expect(!session.perform(scene.drag))
        #expect(scene.commits == 0)
    }

    @Test func anAdmittedLinkPublishesItsReplacementProposal() {
        let scene = Scene()
        var proposals: [SplitDropTarget?] = []
        let tracked = scene.trackedSession()
        tracked.targets.performFeedback = {}
        tracked.targets.onChange = { proposals.append($0) }
        scene.drag.draggingLocation = NSPoint(x: 100, y: 100)
        #expect(tracked.update(scene.drag) == .copy)
        #expect(proposals == [.replace(0)])
    }

    @Test func performingClearsTheProposalBeforeCommit() {
        let scene = Scene()
        var proposals: [SplitDropTarget?] = []
        let tracked = scene.trackedSession()
        tracked.targets.performFeedback = {}
        tracked.targets.onChange = { proposals.append($0) }
        scene.drag.draggingLocation = NSPoint(x: 100, y: 100)
        _ = tracked.update(scene.drag)
        #expect(tracked.perform(scene.drag))
        #expect(proposals.last == .some(nil))
    }

    @Test func endingASessionClearsItsProposalOnce() {
        let scene = Scene()
        var proposals: [SplitDropTarget?] = []
        let tracked = scene.trackedSession()
        tracked.targets.performFeedback = {}
        tracked.targets.onChange = { proposals.append($0) }
        scene.drag.draggingLocation = NSPoint(x: 100, y: 100)
        _ = tracked.update(scene.drag)
        tracked.end()
        tracked.end()
        #expect(proposals == [.replace(0), nil])
    }

    @Test func aTerminalValidationSeesARevokedSessionAndCannotRepeatCleanup() {
        let scene = Scene()
        var ending: ExternalSplitDropSession?
        var validations = 0
        var sawRevoked = false
        ending = ExternalSplitDropSession(host: scene.host, info: scene.drag, frames: [scene.host.bounds], orientation: .horizontal,
            validate: {
                validations += 1
                sawRevoked = ending?.ended == true
                ending?.end()
                return true
            }, insertionColor: { .black }, canPropose: { _, _ in true }, commit: { _, _ in false })
        ending?.end()
        ending?.end()
        #expect(sawRevoked)
        #expect(validations == 1)
        #expect(scene.host.subviews.isEmpty)
    }

    @Test func aPointNearTheTopEdgeInsertsOnTheSecondaryAxis() {
        let bounds = NSRect(x: 0, y: 0, width: 200, height: 200)
        let proposal = ExternalSplitDropSession.proposal(at: NSPoint(x: 100, y: 5), frames: [bounds], orientation: .horizontal)
        guard case .insert(0)? = proposal?.0 else { Issue.record("wrong top target"); return }
        #expect(proposal?.1 == .vertical)
    }

    @Test func theCentreReplacesTheExactPane() {
        let bounds = NSRect(x: 0, y: 0, width: 200, height: 200)
        let proposal = ExternalSplitDropSession.proposal(at: NSPoint(x: 100, y: 100), frames: [bounds], orientation: .horizontal)
        guard case .replace(0)? = proposal?.0 else { Issue.record("wrong center target"); return }
        #expect(proposal?.2 == bounds)
    }

    @Test func aPointOutsideTheContentHasNoProposal() {
        let bounds = NSRect(x: 0, y: 0, width: 200, height: 200)
        #expect(ExternalSplitDropSession.proposal(at: NSPoint(x: 250, y: 100), frames: [bounds], orientation: .horizontal) == nil)
    }

    @Test func anUnavailableInsertionFallsBackToReplacingTheOriginalPane() {
        let scene = Scene()
        var accepted: SplitDropTarget?
        scene.drag.draggingLocation = NSPoint(x: 10, y: 100)
        let fallback = ExternalSplitDropSession(host: scene.host, info: scene.drag, frames: [scene.host.bounds], orientation: .horizontal,
            validate: { true }, insertionColor: { .black },
            canPropose: { target, _ in if case .replace = target { return true }; return false },
            commit: { target, _ in accepted = target; return true })!
        #expect(fallback.update(scene.drag) == .copy)
        #expect(fallback.perform(scene.drag))
        #expect(accepted == .replace(0))
    }

    @Test func noSupportedTargetMeansNoPreviewAndNoCommit() {
        let scene = Scene()
        var committed = false
        scene.drag.draggingLocation = NSPoint(x: 10, y: 100)
        let unavailable = ExternalSplitDropSession(host: scene.host, info: scene.drag, frames: [scene.host.bounds], orientation: .horizontal,
            validate: { true }, insertionColor: { .black }, canPropose: { _, _ in false },
            commit: { _, _ in committed = true; return true })!
        #expect(unavailable.update(scene.drag).isEmpty)
        #expect(!unavailable.perform(scene.drag))
        #expect(!committed)
    }

    @MainActor private final class NativeHost {
        let scene = Scene()
        let owner: ExternalSplitDropHost
        let childA: NSView, childB: NSView

        init() {
            owner = ExternalSplitDropHost(frame: scene.host.bounds)
            scene.host.addSubview(owner)
            childA = NSView(frame: scene.host.bounds)
            childB = NSView(frame: scene.host.bounds)
            owner.addSubview(childA)
            owner.addSubview(childB)
            owner.makeSession = { [scene, owner] _, info in
                ExternalSplitDropSession(host: owner, info: info, frames: [owner.bounds], orientation: .horizontal,
                    validate: { true }, insertionColor: { .black }, canPropose: { _, _ in true },
                    commit: { _, _ in scene.commits += 1; return true })
            }
        }
    }

    @Test func aNewNativePaneReceivesItsOwnDragOwner() {
        let fixture = NativeHost()
        #expect(fixture.owner.contentView(fixture.childA, beginDrop: fixture.scene.drag) == .copy)
        #expect(fixture.owner.contentView(fixture.childB, beginDrop: fixture.scene.drag) == .copy)
    }

    @Test func anOldPaneExitOrDropCannotCancelOrRetargetTheNewRecipient() {
        let fixture = NativeHost()
        let drag = fixture.scene.drag
        _ = fixture.owner.contentView(fixture.childA, beginDrop: drag)
        _ = fixture.owner.contentView(fixture.childB, beginDrop: drag)
        fixture.owner.contentViewDidEndDrop(fixture.childA)
        #expect(fixture.owner.contentView(fixture.childB, updateDrop: drag) == .copy)
        #expect(!fixture.owner.contentView(fixture.childA, performDrop: drag))
    }

    @Test func onlyTheCurrentNativeRecipientCommits() {
        let fixture = NativeHost()
        let drag = fixture.scene.drag
        _ = fixture.owner.contentView(fixture.childA, beginDrop: drag)
        _ = fixture.owner.contentView(fixture.childB, beginDrop: drag)
        fixture.owner.contentViewDidEndDrop(fixture.childA)
        #expect(fixture.owner.contentView(fixture.childB, performDrop: drag))
        #expect(fixture.scene.commits == 1)
    }
}
