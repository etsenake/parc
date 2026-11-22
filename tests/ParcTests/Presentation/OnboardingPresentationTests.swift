import AppKit
import Testing
@testable import ParcCore
@testable import ParcSidebar
@testable import ParcSettings
@testable import ParcOnboarding

struct OnboardingReplayTransitionTests {
    @MainActor private func closingReplay() -> OnboardingReplayTransition {
        var replay = OnboardingReplayTransition()
        replay.begin()
        return replay
    }

    @Test @MainActor func setupPresentsOnlyWhenTheBrowserConsents() {
        var replay = closingReplay()
        #expect(replay.closeResolved(approved: true) == .present)
        #expect(!replay.isClosing)
        #expect(replay.isActive)
    }

    @Test @MainActor func refusingCloseDropsTheWaitingQuitRequest() {
        var replay = closingReplay()
        #expect(replay.deferTerminationWhileClosing { Issue.record("Quit after refusing close") })
        #expect(replay.closeResolved(approved: false) == .cancelled)
        #expect(replay.takeDeferredTermination() == nil)
    }

    @Test @MainActor func consentWithAWaitingQuitRestoresTheBrowserBeforeShowingSetup() {
        var replay = closingReplay()
        #expect(replay.deferTerminationWhileClosing { Issue.record("Quit ahead of restoration") })
        #expect(replay.closeResolved(approved: true) == .restoreForTermination)
        #expect(replay.isActive)
    }

    @Test @MainActor func restoringTheBrowserReleasesTheWaitingQuitOnce() {
        var replay = closingReplay()
        var terminations = 0
        _ = replay.deferTerminationWhileClosing { terminations += 1 }
        _ = replay.closeResolved(approved: true)
        replay.restored()
        replay.takeDeferredTermination()?()
        replay.takeDeferredTermination()?()
        #expect(!replay.isActive)
        #expect(terminations == 1)
    }

    @Test @MainActor func quitIsOnlyDeferredWhileTheBrowserIsClosing() {
        var replay = closingReplay()
        _ = replay.closeResolved(approved: true)
        #expect(!replay.deferTerminationWhileClosing {})
    }
}

extension OnboardingReplayTransitionTests {
    private final class Owner {
        var id = UUID()
        var ready = true
        var standard = true
    }

    @MainActor private func restore(savedID: UUID? = nil, returning owner: Owner? = nil,
                                    among candidates: [Owner], make: () throws -> Owner) rethrows -> Owner {
        try OnboardingReplayTransition.restoreOwner(savedID: savedID, returning: owner,
            owners: candidates, sessionID: { $0.id }, ready: { $0.ready }, standard: { $0.standard }, make: make)
    }

    @Test @MainActor func aSavedReplayReturnsToItsExactWindowRecord() {
        let other = Owner()
        let exact = Owner()
        let restored = restore(savedID: exact.id, among: [other, exact]) {
            Issue.record("Created a second window for the same saved record")
            return Owner()
        }
        #expect(restored === exact)
    }

    @Test(arguments: [false, true])
    @MainActor func anAuxiliaryReplayReturnsToItsOriginalWindowWhileItStillExists(departed: Bool) {
        let fallback = Owner()
        let original = Owner()
        original.standard = false
        let restored = restore(returning: original, among: departed ? [fallback] : [fallback, original]) {
            Issue.record("Created a window even though one could be restored")
            return Owner()
        }
        #expect(restored === (departed ? fallback : original))
    }

    @Test @MainActor func aReplayWithoutAUsableWindowCreatesAStandardOne() {
        let unavailable = Owner()
        unavailable.ready = false
        let auxiliary = Owner()
        auxiliary.standard = false
        let created = Owner()
        let restored = restore(among: [unavailable, auxiliary]) { created }
        #expect(restored === created)
    }

    @Test @MainActor func aRestorationFailureCanBeRetriedBeforeReleasingThePendingQuit() {
        var replay = closingReplay()
        var quits = 0
        _ = replay.deferTerminationWhileClosing { quits += 1 }
        _ = replay.closeResolved(approved: true)
        #expect(throws: CocoaError(.fileReadNoSuchFile)) {
            try restore(among: []) { throw CocoaError(.fileReadNoSuchFile) }
        }
        #expect(replay.isActive && quits == 0)
        let replacement = Owner()
        #expect(restore(among: []) { replacement } === replacement)
        replay.restored()
        replay.takeDeferredTermination()?()
        #expect(quits == 1)
    }

    @Test(arguments: [false, true])
    @MainActor func notesAreTemporarilyReadOnlyAndGetTheirOriginalEditingStateBack(alreadyReadOnly: Bool) {
        let page = NotePageSession(page: NotePage(blocks: [.paragraph()]))
        page.isReadOnly = alreadyReadOnly
        let frozen = OnboardingReadOnly([page, page], isReadOnly: \.isReadOnly)
        #expect(page.isReadOnly)
        frozen.restore()
        #expect(page.isReadOnly == alreadyReadOnly)
    }

    @Test @MainActor func duplicatePagesCannotEnterAnAuxiliaryConsentRequest() {
        let page = NSObject()
        #expect(OnboardingAuxiliaryConsent([page, page]) == nil)
    }

    @Test @MainActor func auxiliaryConsentDoesNotCloseTheApprovedPages() throws {
        let first = NSObject(), second = NSObject(), third = NSObject()
        let consent = try #require(OnboardingAuxiliaryConsent([first, second, third]))
        #expect(!consent.recordConsent(current: consent.matches([third, first, second]) { _ in true }))
        #expect(consent.approved(consent.matches([first, second, third]) { _ in true }))
    }

    @Test(arguments: [false, true])
    @MainActor func auxiliaryConsentRejectsPagesAddedOrMovedDuringApproval(added: Bool) throws {
        let first = NSObject(), second = NSObject()
        let consent = try #require(OnboardingAuxiliaryConsent([first, second]))
        _ = consent.recordConsent(current: true)
        let candidates = added ? [first, second, NSObject()] : [first, second]
        #expect(!consent.approved(consent.matches(candidates) { page in added || page === first }))
    }
}

struct OnboardingWindowFrameTests {
    private let copyBounds = CGRect(x: 0, y: 0, width: 560, height: 380)

    @Test @MainActor func theWindowCopyIsCenteredOnWholePoints() {
        let column = CGRect(x: 0, y: 0, width: 610, height: 548)
        let copy = OnboardingWindowFrameLayout.copyFrame(in: column)
        #expect(copy.size == OnboardingWindowFrameLayout.copySize)
        #expect(copy.midX == column.midX && copy.midY == column.midY)
        #expect(copy.minX == copy.minX.rounded() && copy.minY == copy.minY.rounded())
    }

    @Test(arguments: [false, true])
    @MainActor func theCrankSitsAtTheSharedHubInEitherCoordinateDirection(flipped: Bool) {
        let hub = WindowFrameCrankPlacement.hub(in: copyBounds, dockedSidebarEdge: nil)
        let frame = OnboardingWindowFrameLayout.crankFrame(in: copyBounds, side: 288, flipped: flipped)
        #expect(WindowFrameCrankPlacement.fits(hub: hub, in: copyBounds))
        #expect(frame.midX == hub.x && frame.midY == (flipped ? copyBounds.maxY - hub.y : hub.y))
    }

    @Test(arguments: [(CGFloat(1), CGFloat(2.6)), (3, 3), (10, 10), (13, 13), (20, 13.4)])
    @MainActor func thePreviewUsesTheSameFrameThicknessAndEndStopsAsLiveWindows(example: (CGFloat, CGFloat)) {
        let page = OnboardingWindowFrameLayout.pageCard(in: copyBounds, thickness: example.0)
        #expect(page == copyBounds.insetBy(dx: example.1, dy: example.1))
    }

    @Test(arguments: [CGFloat(3), 10, 13])
    @MainActor func placeholderContentFitsInsideTheInsetPage(thickness: CGFloat) {
        let page = OnboardingWindowFrameLayout.pageCard(in: copyBounds, thickness: thickness)
        let local = CGRect(origin: .zero, size: page.size)
        let bars = OnboardingWindowFrameLayout.placeholderBars(in: page.size)
        #expect(!bars.isEmpty && bars.allSatisfy { !$0.isEmpty && local.contains($0) })
    }
}

struct OnboardingSetupCardTests {
    @MainActor private func card() -> OnboardingSetupCard {
        _ = NSApplication.shared
        return OnboardingSetupCard(frame: CGRect(origin: .zero, size: OnboardingSetupLayout.size))
    }

    @Test(arguments: [CGSize(width: 1280, height: 800), CGSize(width: 952, height: 696),
                      CGSize(width: 1208, height: 648), CGSize(width: 760, height: 500)])
    @MainActor func theSetupCardFitsWithoutDistortingItsContent(size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        let frame = OnboardingSetupLayout.frame(in: bounds)
        #expect(bounds.contains(frame))
        #expect(frame.midX == bounds.midX && frame.midY == bounds.midY)
        #expect(abs(frame.width / frame.height - 967 / 548.0) < 0.0001)
    }

    @Test(arguments: [false, true])
    @MainActor func theSpaceNameFieldHasRoomBetweenTheCopyAndActions(hasName: Bool) {
        let card = card()
        let back = NSButton()
        let skip = NSButton()
        let next = OnboardingProgressionControl(frame: .zero)
        let progress = NSTextField()
        let name = NSTextField()
        next.title = "Next"
        next.configure(background: OnboardingSetupPalette.action, foreground: .white, reduceMotion: true)
        card.configure(title: "Choose a theme", subtitle: "Make your Space yours.", font: .systemFont(ofSize: 35),
                       back: back, next: next, skip: skip, progress: progress,
                       accessory: hasName ? name : nil, accessoryHeight: hasName ? 36 : 30)
        card.layoutSubtreeIfNeeded()
        #expect(card.heading.frame.maxY < card.message.frame.minY)
        #expect(card.message.frame.maxY < next.frame.minY)
        if hasName {
            #expect(name.superview === card.instructions)
            #expect(card.message.frame.maxY < name.frame.minY && name.frame.maxY < skip.frame.minY)
        } else {
            #expect(name.superview == nil)
        }
    }

    @Test @MainActor func theNextButtonRoutesKeyboardFocusThroughItsHostedControl() {
        let card = card()
        let next = OnboardingProgressionControl(frame: .zero)
        next.title = "Next"
        next.configure(background: OnboardingSetupPalette.action, foreground: .white, reduceMotion: true)
        card.configure(title: "Choose a theme", subtitle: "Make your Space yours.", font: .systemFont(ofSize: 35),
                       back: NSButton(), next: next, skip: NSButton(), progress: NSTextField(), accessory: nil)
        card.layoutSubtreeIfNeeded()
        #expect(next.keyboardView === next.subviews.first)
        #expect(next.acceptsFirstResponder)
    }

    @Test @MainActor func theCardClipsItsChromeWithoutClippingTheOuterBorder() {
        let card = card()
        card.layoutSubtreeIfNeeded()
        #expect(card.chrome.layer?.masksToBounds == true)
        #expect(card.chrome.grain.superlayer === card.chrome.layer)
        #expect(card.borders.layer?.masksToBounds == false)
        #expect(card.subviews.last === card.borders)
        #expect(card.borders.outer.superlayer === card.borders.layer)
    }

    @Test(arguments: [false, true])
    @MainActor func theCardUsesThemeInkInEitherAppearance(dark: Bool) {
        let card = card()
        card.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        card.viewDidChangeEffectiveAppearance()
        let ink = NSColor(srgbRed: 0.04, green: 0.2, blue: 0.12, alpha: 1)
        card.themeTextColor = ink
        #expect(card.titleColor == ink && card.messageColor == ink && card.chromeColor == ink)
    }

    @Test @MainActor func theReadyCardPlacesItsAccessibleActionsBelowTheMembershipCard() throws {
        _ = NSApplication.shared
        let ready = OnboardingReadyContent(frame: CGRect(x: 0, y: 0, width: 967, height: 548))
        ready.layoutSubtreeIfNeeded()
        let card = try #require(ready.subviews.first { $0 is MembershipCardView })
        let buttons = ready.subviews.compactMap { $0 as? NSButton }
        #expect(buttons.map { $0.accessibilityLabel() } == ["Share card", "Download card", "Randomize card design"])
        #expect(buttons.allSatisfy { $0.frame.minY > card.frame.maxY })
    }

    @Test(arguments: [("Ada Lovelace", "Ada Lovelace_Parc.png"), (" ", "Parc.png")])
    @MainActor func theDownloadNameUsesTheCardNameWhenAvailable(example: (String, String)) {
        #expect(OnboardingReadyContent.downloadName(cardName: example.0) == example.1)
    }

    @Test @MainActor func theConfettiCannonsFanAcrossTheCenterAtEvenIntervals() {
        let bounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let points = OnboardingConfettiView.cannonPoints(in: bounds)
        #expect(points.map(\.x) == [140, 340, 540, 740, 940, 1140])
        #expect(points.allSatisfy { $0.y == bounds.midY })
    }

    @Test(arguments: [(0.0, false), (0.6, true), (4.6, false), (5.5, false)])
    @MainActor func aConfettiPieceAppearsAfterItsBurstThenFades(sample: (Double, Bool)) {
        let piece = OnboardingConfettiView.Piece(cannon: 0, glyph: 0, color: 0, offset: CGVector(dx: 0, dy: 300),
                                               burstDelay: 0.05, fadeDelay: 4, xSpeed: 1, zSpeed: 1,
                                               xDirection: 1, zDirection: 1, anchor: 0)
        #expect((piece.sample(at: sample.0).opacity > 0) == sample.1)
    }
}

struct OnboardingThemeStepTests {
    @MainActor private func editor(theme: SpaceTheme = SpaceTheme()) -> SpaceThemeEditorView {
        _ = NSApplication.shared
        return SpaceThemeEditorView(theme: theme, performHapticFeedback: {})
    }

    @Test @MainActor func theSetupChromeScalesTheStockEditorWithoutReflowingItsControls() {
        let editor = editor()
        let chrome = OnboardingThemeEditorChrome(editor: editor)
        chrome.applyFrame(in: CGRect(x: 0, y: 0, width: 610, height: 548))
        #expect(chrome.composition.frame.size == OnboardingThemeEditorLayout.visualSize)
        #expect(abs(chrome.composition.bounds.width - OnboardingThemeEditorLayout.editorSize.width) < 0.001)
        #expect(abs(chrome.composition.bounds.height - OnboardingThemeEditorLayout.editorSize.height) < 0.001)
        #expect(chrome.composition.layer?.shadowOpacity == 0.25)
    }

    @Test @MainActor func theSetupWrapOwnsThePopoverMaterial() {
        let editor = editor()
        let chrome = OnboardingThemeEditorChrome(editor: editor)
        let wrap = chrome.popoverBackground
        #expect(editor.superview === wrap)
        #expect(wrap.subviews.first === wrap.translucency)
        #expect(wrap.translucency.material == .popover)
        #expect(editor.subviews.compactMap { $0 as? NSVisualEffectView }.first?.isHidden == true)
    }

    @Test(arguments: [true, false])
    @MainActor func onlyTheSidebarPresentationUsesTheEditorsMaterial(setup: Bool) {
        let editor = editor()
        editor.presentation = setup ? .setup : .sidebar
        #expect(editor.subviews.compactMap { $0 as? NSVisualEffectView }.first?.isHidden == setup)
    }

    @Test(arguments: [true, false])
    @MainActor func aChosenColorHidesTheSetupAndSidebarPrompts(setup: Bool) throws {
        let color = try #require(ThemeColor(hex: "4C6688"))
        let editor = editor(theme: .singleColor(color))
        editor.presentation = setup ? .setup : .sidebar
        #expect(editor.emptyStatePrompt == nil)
    }

    @Test @MainActor func theSetupPromptAsksForAPointerChoice() {
        let editor = editor()
        editor.presentation = .setup
        #expect(editor.emptyStatePrompt == "Click to pick a color")
    }

    @Test @MainActor func theSpaceNameFieldRetainsThemeInkAfterAnAppearanceChange() {
        _ = NSApplication.shared
        let name = OnboardingSpaceNameField(frame: CGRect(x: 0, y: 0, width: 257, height: 36))
        let ink = NSColor(srgbRed: 0.04, green: 0.2, blue: 0.12, alpha: 1)
        name.themeTextColor = ink
        name.viewDidChangeEffectiveAppearance()
        #expect(name.field.textColor == ink)
        #expect(name.field.placeholderAttributedString?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                == ink.withAlphaComponent(0.65))
    }

    @Test(arguments: [false, true])
    @MainActor func reduceMotionShowsTheSettledEditorImmediately(reduceMotion: Bool) {
        let chrome = OnboardingThemeEditorChrome(editor: editor())
        chrome.prepareAppearance(reduceMotion: reduceMotion, in: CGRect(x: 0, y: 0, width: 610, height: 548))
        #expect(chrome.composition.alphaValue == (reduceMotion ? 1 : 0))
    }
}
