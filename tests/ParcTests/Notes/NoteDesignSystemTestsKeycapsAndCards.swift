import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteDesignSystemTestsKeycapsAndCards {
    private struct KeycapCase: Sendable, CustomTestStringConvertible {
        let text: String
        let keys: [String]

        var testDescription: String { "\(text)" }
    }

    private struct SpokenShortcutCase: Sendable, CustomTestStringConvertible {
        let text: String
        let spoken: String

        var testDescription: String { "\(text)" }
    }

    private final class FlippedHost: NSView {
        override var isFlipped: Bool { true }
    }

    private init() { NoteEditorFixtures.registerFonts() }

    private func sampleItems() -> [NoteMenuList.Item] {
        [
            .init(id: "text", title: "Text", icon: .glyph("Aa"), section: "Basic blocks"),
            .init(id: "h1", title: "Heading 1", icon: .glyph("H1"), shortcut: "#", section: "Basic blocks", keywords: ["title"]),
            .init(id: "todo", title: "To-do List", icon: .symbol("checkmark.square"), section: "Basic blocks", keywords: ["checkbox", "task"]),
            .init(id: "image", title: "Image", section: "Media", isEnabled: false),
            .init(id: "video", title: "Video", section: "Media"),
            .init(id: "delete", title: "Delete", shortcut: "Delete", separatorBefore: true),
        ]
    }

    private final class Counter { var value = 0 }

    @Test(arguments: [
        KeycapCase(text: "⌘⇧S", keys: ["⇧", "⌘", "S"]),
        KeycapCase(text: "cmd+shift+k", keys: ["⇧", "⌘", "K"]),
        KeycapCase(text: "⌥⌘1", keys: ["⌥", "⌘", "1"]),
        KeycapCase(text: "⌫", keys: ["⌫"]),
    ])
    private func keycapsSortModifiersAndTurnWordsIntoSymbols(sample: KeycapCase) {
        #expect(NoteKeycapRenderer.keys(in: sample.text) == sample.keys)
    }

    @Test func namedKeysAreCaps() {
        #expect(NoteKeycapRenderer.resolvedStyle(.automatic, for: "Delete") == .caps)
    }

    @Test func markdownHintsStayText() {
        #expect(NoteKeycapRenderer.resolvedStyle(.automatic, for: "##") == .text)
    }

    @Test func aLoneBackspaceIsAKeycap() {
        #expect(NoteKeycapRenderer.resolvedStyle(.automatic, for: "⌫") == .caps)
    }

    @Test func capsAreAsTallAsTheMinimumSide() {
        #expect(NoteKeycapRenderer.size(for: "⌘B").height == NoteKeycapRenderer.minimumSide)
    }

    @Test(arguments: [
        SpokenShortcutCase(text: "⌘⇧S", spoken: "Shift-Command-S"),
        SpokenShortcutCase(text: "⌫", spoken: "Delete"),
    ])
    private func shortcutsReadAloud(sample: SpokenShortcutCase) {
        #expect(NoteKeycapLabel.spoken(sample.text) == sample.spoken)
    }

    @MainActor private struct Presented {
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        let list: NoteMenuList
        let panel: NoteFloatingPanel
        let dismissals = Counter()

        init(items: [NoteMenuList.Item]) {
            list = NoteMenuList(items: items)
            panel = NoteFloatingPanel(content: list)
            let dismissals = dismissals
            panel.onDismiss = { dismissals.value += 1 }
            panel.present(in: host, anchor: NSRect(x: 40, y: 380, width: 10, height: 20), edge: .below, animated: false)
        }
    }

    @Test func presentAddsThePanelToTheHost() {
        let presented = Presented(items: sampleItems())
        #expect(presented.panel.superview === presented.host)
        #expect(presented.panel.isPresented)
    }

    @Test func thePanelFlipsAboveALowAnchor() {
        let presented = Presented(items: sampleItems())
        #expect(presented.panel.resolvedEdge == .above)
        #expect(presented.panel.frame.maxY == 374)
    }

    @Test func thePanelHugsItsContent() {
        let presented = Presented(items: sampleItems())
        #expect(presented.panel.frame.size == presented.list.fittingSize)
        #expect(presented.panel.contentView.frame.size == presented.panel.frame.size)
    }

    @Test func thePanelShrinksWithItsMenu() {
        let presented = Presented(items: sampleItems())
        presented.list.filterText = "video"
        #expect(presented.panel.frame.height == presented.list.fittingSize.height)
    }

    @Test func aShrinkingPanelKeepsItsAnchorEdge() {
        let presented = Presented(items: sampleItems())
        presented.list.filterText = "video"
        #expect(presented.panel.frame.maxY == 374)
    }

    @Test func repositionFollowsTheAnchor() {
        let presented = Presented(items: sampleItems())
        presented.panel.reposition(anchor: NSRect(x: 80, y: 40, width: 10, height: 20), animated: false)
        #expect(presented.panel.resolvedEdge == .below)
        #expect(presented.panel.frame.minY == 66)
    }

    @Test func unflippedHostsPlaceBelowInTheirOwnCoordinates() {
        let presented = Presented(items: sampleItems())
        let plain = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        presented.panel.present(in: plain, anchor: NSRect(x: 40, y: 300, width: 10, height: 20), edge: .below, animated: false)
        #expect(presented.panel.superview === plain)
        #expect(presented.panel.resolvedEdge == .below)
        #expect(presented.panel.frame.maxY == 294)
    }

    @Test func dismissRemovesThePanelOnce() {
        let presented = Presented(items: sampleItems())
        presented.panel.dismiss(animated: false)
        #expect(presented.panel.superview == nil)
        #expect(!presented.panel.isPresented)
        #expect(presented.dismissals.value == 1)
    }

    private func hud(anchor: NSRect) -> (NoteFloatingPanel, FlippedHost) {
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        let hud = NoteFloatingPanel(content: NoteMenuList(items: sampleItems()))
        hud.alignment = .center
        hud.present(in: host, anchor: anchor, edge: .below, animated: true)
        return (hud, host)
    }

    @Test func theCardGrowsOutOfTheEdgeNearestItsAnchor() {
        let (hud, _) = hud(anchor: NSRect(x: 300, y: 40, width: 20, height: 20))
        #expect(hud.scaleOrigin.y == 0)
        #expect(hud.scaleOrigin.x == 310 - hud.frame.minX)
    }

    @Test func centredCardsSitUnderTheMiddleOfTheirAnchor() {
        #expect(hud(anchor: NSRect(x: 300, y: 40, width: 20, height: 20)).0.frame.midX == 310)
    }

    @Test func openingScalesUpFrom95Percent() throws {
        try #require(!NoteAnimation.reduceMotion)
        let (hud, _) = hud(anchor: NSRect(x: 300, y: 40, width: 20, height: 20))
        let grow = hud.layer?.animation(forKey: NoteAnimation.hudTransformKey) as? CABasicAnimation
        let start = (grow?.fromValue as? NSValue)?.caTransform3DValue
        #expect(grow?.duration == NoteAnimation.hudOpenDuration)
        #expect(start?.m11 == NoteAnimation.hudHiddenScale)
    }

    @Test func openingFadesInFast() throws {
        try #require(!NoteAnimation.reduceMotion)
        let (hud, _) = hud(anchor: NSRect(x: 300, y: 40, width: 20, height: 20))
        #expect(hud.layer?.animation(forKey: NoteAnimation.hudOpacityKey)?.duration == NoteAnimation.hudFadeDuration)
    }

    @Test func aboveTheCardGrowsFromItsBottomEdge() {
        let (hud, _) = hud(anchor: NSRect(x: 300, y: 40, width: 20, height: 20))
        hud.reposition(anchor: NSRect(x: 300, y: 420, width: 20, height: 20), animated: false)
        #expect(hud.resolvedEdge == .above)
        #expect(hud.scaleOrigin.y == hud.frame.height)
    }

    @Test func anUnanimatedDismissFinishesAtOnce() {
        let (hud, _) = hud(anchor: NSRect(x: 300, y: 40, width: 20, height: 20))
        var finished = false
        hud.dismiss(animated: false) { finished = true }
        #expect(finished)
        #expect(hud.superview == nil)
    }

    @Test func constraintFreeContentKeepsItsFrameSize() {
        let bar = NoteFloatingPanel(content: NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 36)))
        #expect(bar.preferredSize == NSSize(width: 120, height: 36))
    }
}
