import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteDesignSystemTests {
    final class FlippedHost: NSView {
        override var isFlipped: Bool { true }
    }

    init() { NoteEditorFixtures.registerFonts() }

    @Test func stiffnessFollowsResponse() {
        let omega = 2 * Double.pi / 0.15
        #expect(abs(NoteSpring.highlight.stiffness - omega * omega) < 0.001)
    }

    @Test func dampingFollowsRatio() {
        let omega = 2 * Double.pi / 0.15
        #expect(abs(NoteSpring.highlight.dampingCoefficient - 2 * 0.825 * omega) < 0.001)
    }

    @Test func aSpringStartsAtZero() {
        #expect(NoteSpring.highlight.progress(at: 0) == 0)
    }

    @Test func aSpringSettlesAtOne() {
        #expect(abs(NoteSpring.highlight.progress(at: 2) - 1) < 0.001)
    }

    @Test func theBouncyToggleOvershoots() {
        #expect(NoteSpring.toggle.progress(at: 0.12) > 1)
    }

    @Test func aSpringsDurationSettles() {
        let animation = NoteAnimation.spring("opacity", .press, from: 0, to: 1)
        #expect(animation.duration == animation.settlingDuration)
        #expect(animation.duration > 0)
    }

    @Test func theModelValueLandsImmediately() {
        let layer = CALayer()
        NoteAnimation.spring(layer, "opacity", to: Float(0.5), spring: .highlight)
        #expect(abs(layer.opacity - 0.5) < 0.0001)
    }

    @Test func aNewerGenerationRetiresTheOlderToken() {
        let layer = CALayer()
        let first = NoteAnimation.advanceGeneration(of: layer, key: "k")
        let second = NoteAnimation.advanceGeneration(of: layer, key: "k")
        #expect(!first.isCurrent)
        #expect(second.isCurrent)
    }

    @Test func centredLayersLiftAboutTheirMiddle() {
        let centred = CALayer()
        centred.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        NoteAnimation.lift(centred, lifted: true)
        #expect(centred.transform.m11 == NoteAnimation.liftScale)
        #expect(centred.transform.m41 == 0)
    }

    func corneredLayer() -> CALayer {
        let cornered = CALayer()
        cornered.anchorPoint = .zero
        cornered.bounds = CGRect(x: 0, y: 0, width: 100, height: 40)
        return cornered
    }

    @Test func viewLayersLiftAboutTheirMiddleToo() {
        let cornered = corneredLayer()
        NoteAnimation.lift(cornered, lifted: true)
        #expect(abs(cornered.transform.m41 + 50 * (NoteAnimation.liftScale - 1)) < 0.0001)
    }

    @Test func droppingSettlesBackToRest() {
        let cornered = corneredLayer()
        NoteAnimation.lift(cornered, lifted: true)
        NoteAnimation.lift(cornered, lifted: false)
        #expect(CATransform3DIsIdentity(cornered.transform))
    }

    let visible = NSRect(x: 0, y: 0, width: 600, height: 400)

    func place(_ anchor: NSRect, _ size: NSSize, _ preferred: NoteFloatingPanel.Edge = .below, in area: NSRect? = nil) -> (frame: NSRect, edge: NoteFloatingPanel.Edge) {
        NoteFloatingPanel.placement(anchor: anchor, size: size, preferred: preferred, visible: area ?? visible)
    }

    @Test func aPanelFitsBelowTheAnchorWithAGap() {
        let below = place(NSRect(x: 100, y: 50, width: 10, height: 20), NSSize(width: 200, height: 150))
        #expect(below.edge == .below)
        #expect(below.frame.minY == 76)
        #expect(below.frame.minX == 100)
    }

    @Test func aPanelFlipsAboveWhenTheBottomIsCrowded() {
        let flipped = place(NSRect(x: 100, y: 330, width: 10, height: 20), NSSize(width: 200, height: 150))
        #expect(flipped.edge == .above)
        #expect(flipped.frame.maxY == 324)
    }

    @Test func aPanelClampsInsideTheVisibleRect() {
        #expect(place(NSRect(x: 560, y: 50, width: 10, height: 20), NSSize(width: 200, height: 100)).frame.maxX == 592)
    }

    @Test func tallContentShrinksToTheRoom() {
        let squeezed = place(NSRect(x: 10, y: 180, width: 10, height: 20), NSSize(width: 200, height: 900))
        #expect(squeezed.frame.maxY <= 392)
        #expect(squeezed.frame.height >= NoteFloatingPanel.minimumVisibleHeight)
    }

    @Test func submenusFlipToTheLeadingSide() {
        let side = place(NSRect(x: 500, y: 100, width: 80, height: 34), NSSize(width: 200, height: 100), .trailing)
        #expect(side.edge == .leading)
        #expect(side.frame.maxX == 494)
    }

    @Test func placementFollowsAScrolledDocumentsVisibleRect() {
        let scrolled = place(NSRect(x: 100, y: 1050, width: 10, height: 20), NSSize(width: 200, height: 150),
                             in: NSRect(x: 0, y: 1000, width: 600, height: 400))
        #expect(scrolled.edge == .below)
        #expect(scrolled.frame.minY == 1076)
    }

    func sampleItems() -> [NoteMenuList.Item] {
        [
            .init(id: "text", title: "Text", icon: .glyph("Aa"), section: "Basic blocks"),
            .init(id: "h1", title: "Heading 1", icon: .glyph("H1"), shortcut: "#", section: "Basic blocks", keywords: ["title"]),
            .init(id: "todo", title: "To-do List", icon: .symbol("checkmark.square"), section: "Basic blocks", keywords: ["checkbox", "task"]),
            .init(id: "image", title: "Image", section: "Media", isEnabled: false),
            .init(id: "video", title: "Video", section: "Media"),
            .init(id: "delete", title: "Delete", shortcut: "Delete", separatorBefore: true),
        ]
    }

    func keyboardList() -> NoteMenuList {
        let list = NoteMenuList(items: sampleItems())
        list.prepare(origin: .keyboard)
        return list
    }

    @Test func sectionsAddHeadersAndSeparators() {
        let list = NoteMenuList(items: sampleItems())
        let rows = NoteTheme.menuRowHeight * 6
        let chrome = NoteTheme.menuHeaderHeight * 2 + NoteTheme.menuSeparatorSlot * 2 + NoteTheme.menuInset * 2
        #expect(list.intrinsicContentSize.height == rows + chrome)
    }

    @Test func pointerMenusOpenWithoutAHighlight() {
        #expect(NoteMenuList(items: sampleItems()).highlightedIndex == nil)
    }

    @Test func keyboardMenusHighlightTheFirstRow() {
        #expect(keyboardList().highlightedIndex == 0)
    }

    @Test func arrowsSkipDisabledRows() {
        let list = keyboardList()
        for _ in 0..<3 { list.moveHighlight(by: 1) }
        #expect(list.highlightedItem?.id == "video")
    }

    @Test func arrowsWrapAround() {
        let list = keyboardList()
        for _ in 0..<5 { list.moveHighlight(by: 1) }
        #expect(list.highlightedIndex == 0)
    }

    @Test func upFromTheTopWrapsToTheBottom() {
        let list = keyboardList()
        list.moveHighlight(by: -1)
        #expect(list.highlightedItem?.id == "delete")
    }

    @Test func returnActivatesTheHighlightedRow() {
        let list = keyboardList()
        list.moveHighlight(by: -1)
        var activated: [String] = []
        list.onActivate = { activated.append($0.id) }
        #expect(list.activateHighlighted())
        #expect(activated == ["delete"])
    }

    @Test func disabledRowsRefuseTheHighlight() {
        let list = keyboardList()
        list.highlightedIndex = 3
        #expect(list.highlightedIndex != 3)
    }

    @Test func keyboardMenusReHighlightTheFirstRowAfterAnUpdate() {
        let list = keyboardList()
        list.highlight(id: "video")
        list.items = sampleItems()
        #expect(list.highlightedIndex == 0)
    }

    @Test func updatesCanKeepTheHighlightedRow() {
        let list = keyboardList()
        list.highlight(id: "video")
        list.setItems(sampleItems(), keepingHighlight: true)
        #expect(list.highlightedItem?.id == "video")
    }

    func longList() -> NoteMenuList {
        NoteMenuList(items: (0..<40).map { .init(id: "\($0)", title: "Row \($0)") })
    }

    @Test func longMenusCapTheirHeightAndScroll() {
        let long = longList()
        #expect(long.intrinsicContentSize.height == long.maximumHeight)
    }

    @Test func theMaximumHeightIsAdjustable() {
        let long = longList()
        long.maximumHeight = 200
        #expect(long.fittingSize.height == 200)
    }

    func filtering() -> (NoteMenuList, Counter) {
        let list = keyboardList()
        let counter = Counter()
        list.preferredSizeDidChange = { counter.value += 1 }
        return (list, counter)
    }

    final class Counter { var value = 0 }

    @Test func keywordsMatch() {
        let (list, _) = filtering()
        list.filterText = "task"
        #expect(list.visibleItems.map(\.id) == ["todo"])
    }

    @Test func filteringReportsANewSize() {
        let (list, counter) = filtering()
        list.filterText = "task"
        #expect(counter.value > 0)
    }

    @Test func theBestMatchIsHighlighted() {
        let (list, _) = filtering()
        list.filterText = "task"
        #expect(list.highlightedItem?.id == "todo")
    }

    @Test func titlePrefixesRankFirst() {
        let (list, _) = filtering()
        list.filterText = "h"
        #expect(list.visibleItems.first?.id == "h1")
    }

    @Test func noResultsActivateNothing() {
        let (list, _) = filtering()
        list.filterText = "zzz"
        #expect(list.visibleItems.isEmpty)
        #expect(!list.activateHighlighted())
    }

    @Test func theFriendlyEmptyRowKeepsItsPlace() {
        let (list, _) = filtering()
        list.filterText = "zzz"
        #expect(list.intrinsicContentSize.height == NoteTheme.menuRowHeight + NoteTheme.menuInset * 2)
    }

    @Test func clearingTheFilterRestoresEverything() {
        let (list, _) = filtering()
        list.filterText = "zzz"
        list.filterText = ""
        #expect(list.visibleItems.count == sampleItems().count)
    }

    @Test func externalFilteringSharesTheRanking() {
        #expect(NoteMenuList.filter(sampleItems(), query: "vid").map(\.id) == ["video"])
    }

    @Test func matchingIgnoresCase() {
        #expect(NoteMenuList.matches(sampleItems()[1], query: "HEADING"))
    }

    @Test func matchingIgnoresAccents() {
        #expect(NoteMenuList.matches(.init(id: "c", title: "Café"), query: "cafe"))
    }

    func key(_ code: UInt16, _ characters: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    func pointerList() -> NoteMenuList {
        let list = NoteMenuList(items: sampleItems())
        list.prepare(origin: .pointer)
        return list
    }

    @Test func downArrowStartsAtTheTop() {
        let list = pointerList()
        #expect(list.handleKeyDown(key(125)))
        #expect(list.highlightedIndex == 0)
    }

    @Test func moveDownMoves() {
        let list = pointerList()
        _ = list.handleKeyDown(key(125))
        #expect(list.handle(command: #selector(NSResponder.moveDown(_:))))
        #expect(list.highlightedIndex == 1)
    }

    @Test func escapeCancels() {
        let list = pointerList()
        var cancelled = false
        list.onCancel = { cancelled = true }
        #expect(list.handleKeyDown(key(53)))
        #expect(cancelled)
    }

    @Test func typingPassesThroughUnlessTheMenuFilters() {
        #expect(!pointerList().handleKeyDown(key(0, "a")))
    }

    @Test func typingFiltersWhenTheMenuFilters() {
        let list = pointerList()
        list.filtersOnTyping = true
        #expect(list.handleKeyDown(key(9, "v")))
        #expect(list.filterText == "v")
    }

    @Test func deleteTrimsTheFilter() {
        let list = pointerList()
        list.filtersOnTyping = true
        _ = list.handleKeyDown(key(9, "v"))
        #expect(list.handleKeyDown(key(51)))
        #expect(list.filterText.isEmpty)
    }

    @Test func rightArrowOpensASubmenu() {
        let submenu = NoteMenuList(items: [.init(id: "color", title: "Color", hasSubmenu: true)])
        var opened = false
        submenu.onActivate = { _ in opened = true }
        submenu.prepare(origin: .keyboard)
        #expect(submenu.handleKeyDown(key(124)))
        #expect(opened)
    }

    @Test func theListIsAMenu() {
        #expect(NoteMenuList(items: sampleItems()).accessibilityRole() == .menu)
    }

    @Test func rowsAreMenuItems() {
        let rows = NoteMenuList(items: sampleItems()).accessibilityChildren() as? [NSAccessibilityElement]
        #expect(rows?.first?.accessibilityRole() == .menuItem)
    }

    @Test(arguments: [("⌘⇧S", ["⇧", "⌘", "S"]), ("cmd+shift+k", ["⇧", "⌘", "K"]), ("⌥⌘1", ["⌥", "⌘", "1"]), ("⌫", ["⌫"])] as [(String, [String])])
    func keycapsSortModifiersAndTurnWordsIntoSymbols(text: String, keys: [String]) {
        #expect(NoteKeycapRenderer.keys(in: text) == keys)
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

    @Test(arguments: [("⌘⇧S", "Shift-Command-S"), ("⌫", "Delete")])
    func shortcutsReadAloud(text: String, spoken: String) {
        #expect(NoteKeycapLabel.spoken(text) == spoken)
    }

    @MainActor struct Presented {
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

    @Test func thePanelFollowsAShrinkingMenuAndKeepsItsEdge() {
        let presented = Presented(items: sampleItems())
        presented.list.filterText = "video"
        #expect(presented.panel.frame.height == presented.list.fittingSize.height)
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

    func hud(anchor: NSRect) -> (NoteFloatingPanel, FlippedHost) {
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

    @Test func coloursAreCached() {
        #expect(NoteTheme.color(.text(.red)) === NoteTheme.color(.text(.red)))
    }

    @Test(arguments: [("keyword.control", "keyword"), ("stringLiteral", "string"), ("comment", "comment"), ("whatever", "plain")])
    func syntaxNamesMapToFamilies(name: String, family: String) {
        #expect(NoteTheme.syntaxFamily(name) == family)
    }

    @Test func commentsAreItalic() {
        #expect(NoteTheme.syntaxIsItalic("comment"))
    }

    nonisolated static let syntaxFamilies: [NoteSyntaxKind: String] = [
        .keyword: "keyword", .type: "type", .string: "string", .number: "number", .comment: "comment", .function: "function",
        .property: "attribute", .operatorSymbol: "operator", .punctuation: "operator", .tag: "tag", .attribute: "attribute",
        .variable: "variable", .constant: "number", .regex: "escape", .builtin: "type", .inserted: "string", .deleted: "tag",
        .heading: "heading", .emphasis: "emphasis", .strong: "strong", .link: "link", .meta: "meta", .escape: "escape",
    ]

    @Test(arguments: NoteSyntaxKind.allCases)
    func everySyntaxKindHasItsOwnFamily(kind: NoteSyntaxKind) {
        #expect(NoteTheme.syntaxFamily(kind.rawValue) == Self.syntaxFamilies[kind])
    }

    @Test func markdownEmphasisKeepsItsShapeInCode() {
        #expect(NoteTheme.syntaxIsItalic(.emphasis))
        #expect(NoteTheme.syntaxIsBold(.strong))
        #expect(NoteTheme.syntaxIsUnderlined(.link))
    }

    @Test func headingPlaceholdersNameTheirLevel() {
        #expect(NoteTheme.placeholder(for: .heading, level: 2) == "Heading 2")
    }

    @Test func wideWindowsKeepTheColumn() {
        #expect(NoteTheme.contentWidth(forViewport: 1200) == NoteTheme.pageColumnWidth)
    }

    @Test func narrowWindowsKeepTheMargins() {
        #expect(NoteTheme.contentWidth(forViewport: 500) == 500 - NoteTheme.minimumSideMargin * 2)
    }

    @Test func bodyLineHeightComesFromTheRatio() {
        #expect(NoteTheme.textStyle(.body).lineHeight == (NoteTheme.bodySize * NoteTheme.lineHeightRatio).rounded())
    }

    @Test func headingsStepDown() {
        #expect(NoteTheme.textStyle(.heading(1)).font.pointSize > NoteTheme.textStyle(.heading(3)).font.pointSize)
    }

    @Test func inlineCodeSitsOnTheBodyBaseline() {
        #expect(NoteTheme.textStyle(.inlineCode).baselineOffset == NoteTheme.textStyle(.body).baselineOffset)
    }

    @Test func runAttributesLeaveTheParagraphAlone() {
        #expect(NoteTheme.textStyle(.inlineCode).runAttributes[.paragraphStyle] == nil)
    }

    @Test(arguments: NotePageFont.allCases)
    func titlesBeatBodyTextInEveryPageFont(font: NotePageFont) {
        #expect(NoteTheme.titleFont(font, small: false).pointSize > NoteTheme.bodyFont(font).pointSize)
    }

    @Test(arguments: NotePageFont.allCases)
    func italicsKeepTheirSize(font: NotePageFont) {
        #expect(abs(NoteTheme.bodyFont(font, italic: true).pointSize - NoteTheme.bodyFont(font).pointSize) < 0.01)
    }

    @Test(arguments: NotePageFont.allCases)
    func italicsStayCloseToUprightWidth(font: NotePageFont) {
        func width(_ face: NSFont) -> CGFloat { NSAttributedString(string: "Slanted words", attributes: [.font: face]).size().width }
        #expect(width(NoteTheme.bodyFont(font, italic: true)) < width(NoteTheme.bodyFont(font)) * 1.3)
    }

    @Test(arguments: NotePageFont.allCases)
    func italicsActuallyLean(font: NotePageFont) {
        let italic = NoteTheme.bodyFont(font, italic: true)
        #expect(italic.fontDescriptor.symbolicTraits.contains(.italic) || italic.matrix[2] > 0.1)
    }

    @Test func theSerifPageFontIsEBGaramond() {
        #expect(NoteTheme.bodyFont(.serif).fontName.contains("Garamond"))
    }

    func boldButton() -> NoteToolbarButton { NoteToolbarButton(icon: .glyph("B"), label: "Bold", shortcut: "⌘B") }

    @Test func iconButtonsAreSquare() {
        #expect(boldButton().frame.size == NoteTheme.toolbarButtonSize)
    }

    @Test func toolbarButtonsLeaveFocusInTheText() {
        #expect(!boldButton().acceptsFirstResponder)
    }

    @Test func theTooltipCarriesTheShortcut() {
        guard case .fixed(let shortcut)? = boldButton().parcTooltip?.shortcut else {
            Issue.record("the tooltip carries the shortcut")
            return
        }
        #expect(shortcut == KeyboardShortcut(key: "b", flags: .command))
    }

    @Test func accessibilityPressActivates() {
        let button = boldButton()
        var pressed = 0
        button.onPress = { pressed += 1 }
        #expect(button.accessibilityPerformPress())
        #expect(pressed == 1)
    }

    @Test func disabledButtonsDimAndRefuse() {
        let button = boldButton()
        button.isEnabled = false
        #expect(!button.accessibilityPerformPress())
        #expect(button.alphaValue == NoteTheme.disabledOpacity)
    }

    @Test func textButtonsFitTheirLabel() {
        let text = NoteToolbarButton(.text("Text"), label: "Turn into")
        text.showsDisclosure = true
        #expect(text.intrinsicContentSize.width > NoteTheme.toolbarButtonSize.width)
    }

    @Test func chipsHaveTheirOwnHeight() {
        #expect(NoteChip("Add icon", icon: .symbol("face.smiling")).intrinsicContentSize.height == NoteTheme.chipHeight)
    }

    @Test func flashingAnnouncesTheNewLabel() {
        let chip = NoteChip("Add icon", icon: .symbol("face.smiling"))
        chip.flash("Copied!")
        #expect(chip.accessibilityLabel() == "Copied!")
    }

    @Test func theSearchFieldFiltersABoundMenu() {
        let field = NoteSearchField(placeholder: "Search")
        let list = NoteMenuList(items: sampleItems())
        field.bind(to: list)
        field.onChange?("vid")
        #expect(list.visibleItems.map(\.id) == ["video"])
    }

    @Test func arrowsReachTheBoundMenu() {
        let field = NoteSearchField(placeholder: "Search")
        let list = NoteMenuList(items: sampleItems())
        field.bind(to: list)
        field.onChange?("vid")
        #expect(field.onCommand?(#selector(NSResponder.moveDown(_:))) == true)
        #expect(list.highlightedItem?.id == "video")
    }
}
