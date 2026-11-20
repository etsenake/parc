import AppKit

@main @MainActor
struct NoteDesignSystemTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func main() {
        springs()
        placement()
        menuNavigation()
        menuFiltering()
        menuKeys()
        keycaps()
        panelLifecycle()
        theme()
        controls()
        print("NoteDesignSystemTests passed")
    }

    static func springs() {
        let spring = NoteSpring.highlight
        let omega = 2 * Double.pi / 0.15
        expect(abs(spring.stiffness - omega * omega) < 0.001, "stiffness follows response")
        expect(abs(spring.dampingCoefficient - 2 * 0.825 * omega) < 0.001, "damping follows ratio")
        expect(spring.progress(at: 0) == 0, "spring starts at zero")
        expect(abs(spring.progress(at: 2) - 1) < 0.001, "spring settles at one")
        expect(NoteSpring.toggle.progress(at: 0.12) > 1, "the bouncy toggle overshoots")
        let animation = NoteAnimation.spring("opacity", .press, from: 0, to: 1)
        expect(animation.duration == animation.settlingDuration && animation.duration > 0, "spring duration settles")
        let layer = CALayer()
        NoteAnimation.spring(layer, "opacity", to: Float(0.5), spring: .highlight)
        expect(abs(layer.opacity - 0.5) < 0.0001, "the model value lands immediately")
        let first = NoteAnimation.advanceGeneration(of: layer, key: "k")
        let second = NoteAnimation.advanceGeneration(of: layer, key: "k")
        expect(!first.isCurrent && second.isCurrent, "a newer generation retires the older token")
    }

    static func placement() {
        let visible = NSRect(x: 0, y: 0, width: 600, height: 400)
        let below = NoteFloatingPanel.placement(anchor: NSRect(x: 100, y: 50, width: 10, height: 20), size: NSSize(width: 200, height: 150),
                                                preferred: .below, visible: visible)
        expect(below.edge == .below && below.frame.minY == 76 && below.frame.minX == 100, "fits below the anchor with a gap")
        let flipped = NoteFloatingPanel.placement(anchor: NSRect(x: 100, y: 330, width: 10, height: 20), size: NSSize(width: 200, height: 150),
                                                  preferred: .below, visible: visible)
        expect(flipped.edge == .above && flipped.frame.maxY == 324, "flips above when the bottom is crowded")
        let clamped = NoteFloatingPanel.placement(anchor: NSRect(x: 560, y: 50, width: 10, height: 20), size: NSSize(width: 200, height: 100),
                                                  preferred: .below, visible: visible)
        expect(clamped.frame.maxX == 592, "clamps inside the visible rect")
        let squeezed = NoteFloatingPanel.placement(anchor: NSRect(x: 10, y: 180, width: 10, height: 20), size: NSSize(width: 200, height: 900),
                                                   preferred: .below, visible: visible)
        expect(squeezed.frame.maxY <= 392 && squeezed.frame.height >= NoteFloatingPanel.minimumVisibleHeight, "tall content shrinks to the room")
        let side = NoteFloatingPanel.placement(anchor: NSRect(x: 500, y: 100, width: 80, height: 34), size: NSSize(width: 200, height: 100),
                                               preferred: .trailing, visible: visible)
        expect(side.edge == .leading && side.frame.maxX == 494, "submenus flip to the leading side")
        let scrolled = NoteFloatingPanel.placement(anchor: NSRect(x: 100, y: 1050, width: 10, height: 20), size: NSSize(width: 200, height: 150),
                                                   preferred: .below, visible: NSRect(x: 0, y: 1000, width: 600, height: 400))
        expect(scrolled.edge == .below && scrolled.frame.minY == 1076, "placement follows a scrolled document's visible rect")
    }

    static func sampleItems() -> [NoteMenuList.Item] {
        [
            .init(id: "text", title: "Text", icon: .glyph("Aa"), section: "Basic blocks"),
            .init(id: "h1", title: "Heading 1", icon: .glyph("H1"), shortcut: "#", section: "Basic blocks", keywords: ["title"]),
            .init(id: "todo", title: "To-do List", icon: .symbol("checkmark.square"), section: "Basic blocks", keywords: ["checkbox", "task"]),
            .init(id: "image", title: "Image", section: "Media", isEnabled: false),
            .init(id: "video", title: "Video", section: "Media"),
            .init(id: "delete", title: "Delete", shortcut: "Delete", separatorBefore: true),
        ]
    }

    static func menuNavigation() {
        let list = NoteMenuList(items: sampleItems())
        let rows = NoteTheme.menuRowHeight * 6
        let chrome = NoteTheme.menuHeaderHeight * 2 + NoteTheme.menuSeparatorSlot * 2 + NoteTheme.menuInset * 2
        expect(list.intrinsicContentSize.height == rows + chrome, "sections add headers and separators")
        expect(list.highlightedIndex == nil, "pointer menus open without a highlight")
        list.prepare(origin: .keyboard)
        expect(list.highlightedIndex == 0, "keyboard menus highlight the first row")
        list.moveHighlight(by: 1); list.moveHighlight(by: 1); list.moveHighlight(by: 1)
        expect(list.highlightedItem?.id == "video", "arrows skip disabled rows")
        list.moveHighlight(by: 1); list.moveHighlight(by: 1)
        expect(list.highlightedIndex == 0, "arrows wrap around")
        list.moveHighlight(by: -1)
        expect(list.highlightedItem?.id == "delete", "up from the top wraps to the bottom")
        var activated: [String] = []
        list.onActivate = { activated.append($0.id) }
        expect(list.activateHighlighted() && activated == ["delete"], "Return activates the highlighted row")
        list.highlightedIndex = 3
        expect(list.highlightedIndex == 0 || list.highlightedIndex != 3, "disabled rows refuse the highlight")
        list.items = sampleItems()
        expect(list.highlightedIndex == 0, "keyboard menus re-highlight the first row after an update")
        list.highlight(id: "video")
        list.setItems(sampleItems(), keepingHighlight: true)
        expect(list.highlightedItem?.id == "video", "updates can keep the highlighted row")
        let long = NoteMenuList(items: (0..<40).map { .init(id: "\($0)", title: "Row \($0)") })
        expect(long.intrinsicContentSize.height == long.maximumHeight, "long menus cap their height and scroll")
        long.maximumHeight = 200
        expect(long.fittingSize.height == 200, "maximum height is adjustable")
    }

    static func menuFiltering() {
        let list = NoteMenuList(items: sampleItems())
        var resized = 0
        list.preferredSizeDidChange = { resized += 1 }
        list.prepare(origin: .keyboard)
        list.filterText = "task"
        expect(list.visibleItems.map(\.id) == ["todo"], "keywords match")
        expect(resized > 0, "filtering reports a new size")
        expect(list.highlightedItem?.id == "todo", "the best match is highlighted")
        list.filterText = "h"
        expect(list.visibleItems.first?.id == "h1", "title prefixes rank first")
        list.filterText = "zzz"
        expect(list.visibleItems.isEmpty && !list.activateHighlighted(), "no results activate nothing")
        expect(list.intrinsicContentSize.height == NoteTheme.menuRowHeight + NoteTheme.menuInset * 2, "the friendly empty row keeps its place")
        list.filterText = ""
        expect(list.visibleItems.count == 6, "clearing the filter restores everything")
        expect(NoteMenuList.filter(sampleItems(), query: "vid").map(\.id) == ["video"], "external filtering shares the ranking")
        expect(NoteMenuList.matches(sampleItems()[1], query: "HEADING"), "matching ignores case")
        expect(NoteMenuList.matches(.init(id: "c", title: "Café"), query: "cafe"), "matching ignores accents")
    }

    static func key(_ code: UInt16, _ characters: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    static func menuKeys() {
        let list = NoteMenuList(items: sampleItems())
        list.prepare(origin: .pointer)
        expect(list.handleKeyDown(key(125)) && list.highlightedIndex == 0, "down arrow starts at the top")
        expect(list.handle(command: #selector(NSResponder.moveDown(_:))) && list.highlightedIndex == 1, "moveDown: moves")
        var cancelled = false
        list.onCancel = { cancelled = true }
        expect(list.handleKeyDown(key(53)) && cancelled, "Escape cancels")
        expect(!list.handleKeyDown(key(0, "a")), "typing passes through unless the menu filters")
        list.filtersOnTyping = true
        expect(list.handleKeyDown(key(9, "v")) && list.filterText == "v", "type to filter")
        expect(list.handleKeyDown(key(51)) && list.filterText.isEmpty, "Delete trims the filter")
        let submenu = NoteMenuList(items: [.init(id: "color", title: "Color", hasSubmenu: true)])
        var opened = false
        submenu.onActivate = { _ in opened = true }
        submenu.prepare(origin: .keyboard)
        expect(submenu.handleKeyDown(key(124)) && opened, "right arrow opens a submenu")
        expect(list.accessibilityRole() == .menu, "the list is a menu")
        expect((list.accessibilityChildren() as? [NSAccessibilityElement])?.first?.accessibilityRole() == .menuItem, "rows are menu items")
    }

    static func keycaps() {
        expect(NoteKeycapRenderer.keys(in: "⌘⇧S") == ["⇧", "⌘", "S"], "modifiers sort ⌃⌥⇧⌘")
        expect(NoteKeycapRenderer.keys(in: "cmd+shift+k") == ["⇧", "⌘", "K"], "words become symbols")
        expect(NoteKeycapRenderer.keys(in: "⌥⌘1") == ["⌥", "⌘", "1"], "digits stay")
        expect(NoteKeycapRenderer.resolvedStyle(.automatic, for: "Delete") == .caps, "named keys are caps")
        expect(NoteKeycapRenderer.resolvedStyle(.automatic, for: "##") == .text, "Markdown hints stay text")
        expect(NoteKeycapRenderer.size(for: "⌘B").height == NoteKeycapRenderer.minimumSide, "caps are 19 points tall")
        expect(NoteKeycapLabel.spoken("⌘⇧S") == "Shift-Command-S", "shortcuts read aloud")
    }

    static func panelLifecycle() {
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        let list = NoteMenuList(items: sampleItems())
        let panel = NoteFloatingPanel(content: list)
        var dismissed = 0
        panel.onDismiss = { dismissed += 1 }
        panel.present(in: host, anchor: NSRect(x: 40, y: 380, width: 10, height: 20), edge: .below, animated: false)
        expect(panel.superview === host && panel.isPresented, "present adds the panel to the host")
        expect(panel.resolvedEdge == .above && panel.frame.maxY == 374, "the panel flips above a low anchor")
        expect(panel.frame.size == list.fittingSize, "the panel hugs its content")
        expect(panel.contentView.frame.size == panel.frame.size, "content fills the card")
        list.filterText = "video"
        expect(panel.frame.height == list.fittingSize.height && panel.frame.maxY == 374, "the panel follows a shrinking menu and keeps its edge")
        panel.reposition(anchor: NSRect(x: 80, y: 40, width: 10, height: 20), animated: false)
        expect(panel.resolvedEdge == .below && panel.frame.minY == 66, "reposition follows the anchor")
        let plain = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        panel.present(in: plain, anchor: NSRect(x: 40, y: 300, width: 10, height: 20), edge: .below, animated: false)
        expect(panel.superview === plain && panel.resolvedEdge == .below && panel.frame.maxY == 294,
               "unflipped hosts place below in their own coordinates")
        panel.dismiss(animated: false)
        expect(panel.superview == nil && !panel.isPresented && dismissed == 1, "dismiss removes the panel once")
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 36))
        let bar = NoteFloatingPanel(content: content)
        expect(bar.preferredSize == NSSize(width: 120, height: 36), "constraint-free content keeps its frame size")
    }

    static func theme() {
        expect(NoteTheme.color(.text(.red)) === NoteTheme.color(.text(.red)), "colours are cached")
        expect(NoteTheme.syntaxFamily("keyword.control") == "keyword", "syntax names map to families")
        expect(NoteTheme.syntaxFamily("stringLiteral") == "string", "camel-case kinds still map")
        expect(NoteTheme.syntaxFamily("comment") == "comment" && NoteTheme.syntaxIsItalic("comment"), "comments are italic")
        expect(NoteTheme.syntaxFamily("whatever") == "plain", "unknown kinds fall back to plain ink")
        expect(NoteTheme.placeholder(for: .heading, level: 2) == "Heading 2", "heading placeholders name their level")
        expect(NoteTheme.contentWidth(forViewport: 1200) == NoteTheme.pageColumnWidth, "wide windows keep the column")
        expect(NoteTheme.contentWidth(forViewport: 500) == 500 - NoteTheme.minimumSideMargin * 2, "narrow windows keep the margins")
        let style = NoteTheme.textStyle(.body)
        expect(style.lineHeight == (NoteTheme.bodySize * NoteTheme.lineHeightRatio).rounded(), "body line height comes from the ratio")
        expect(NoteTheme.textStyle(.heading(1)).font.pointSize > NoteTheme.textStyle(.heading(3)).font.pointSize, "headings step down")
        for font in NotePageFont.allCases {
            expect(NoteTheme.titleFont(font, small: false).pointSize > NoteTheme.bodyFont(font).pointSize, "titles beat body text in \(font)")
        }
    }

    static func controls() {
        let button = NoteToolbarButton(icon: .glyph("B"), label: "Bold", shortcut: "⌘B")
        expect(button.frame.size == NoteTheme.toolbarButtonSize, "icon buttons are square")
        expect(!button.acceptsFirstResponder, "toolbar buttons leave focus in the text")
        if case .fixed(let shortcut)? = button.parcTooltip?.shortcut {
            expect(shortcut == KeyboardShortcut(key: "b", flags: .command), "the tooltip carries the shortcut")
        } else {
            expect(false, "the tooltip carries the shortcut")
        }
        var pressed = 0
        button.onPress = { pressed += 1 }
        expect(button.accessibilityPerformPress() && pressed == 1, "accessibility press activates")
        button.isEnabled = false
        expect(!button.accessibilityPerformPress() && button.alphaValue == NoteTheme.disabledOpacity, "disabled buttons dim and refuse")
        let text = NoteToolbarButton(.text("Text"), label: "Turn into")
        text.showsDisclosure = true
        expect(text.intrinsicContentSize.width > NoteTheme.toolbarButtonSize.width, "text buttons fit their label")
        let chip = NoteChip("Add icon", icon: .symbol("face.smiling"))
        expect(chip.intrinsicContentSize.height == NoteTheme.chipHeight, "chips are 26 points tall")
        chip.flash("Copied!")
        expect(chip.accessibilityLabel() == "Copied!", "flashing announces the new label")
        let field = NoteSearchField(placeholder: "Search")
        let list = NoteMenuList(items: sampleItems())
        field.bind(to: list)
        field.onChange?("vid")
        expect(list.visibleItems.map(\.id) == ["video"], "the search field filters a bound menu")
        expect(field.onCommand?(#selector(NSResponder.moveDown(_:))) == true && list.highlightedItem?.id == "video", "arrows reach the menu")
    }
}

final class FlippedHost: NSView {
    override var isFlipped: Bool { true }
}
