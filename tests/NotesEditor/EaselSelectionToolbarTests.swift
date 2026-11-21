import Foundation

@main
struct EaselSelectionToolbarTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func plan(_ kinds: [EaselItemKind], editing: Bool = false, locked: Bool = false) -> [[EaselToolbarControl]] {
        EaselSelectionToolbarPlan.groups(for: kinds.map(EaselToolbarSubject.init), editingText: editing, locked: locked)
    }

    static func main() {
        subjects()
        singleSelections()
        textEditing()
        multipleSelections()
        lockedSelections()
        availability()
        placement()
        chord()
        print("EaselSelectionToolbarTests passed")
    }

    static func subjects() {
        expect(EaselToolbarSubject(.rectangle) == .shape && EaselToolbarSubject(.circle) == .shape, "Rectangles and ellipses share the shape toolbar")
        expect(EaselToolbarSubject(.arrow) == .connector, "Arrows use the connector toolbar")
        expect(EaselToolbarSubject(.freehand) == .drawing, "Doodles, highlights and tape use the drawing toolbar")
        expect([EaselItemKind.webCard, .browser, .link].allSatisfy { EaselToolbarSubject($0) == .page }, "Pages, captures and links are page objects")
        expect(EaselToolbarSubject(.code) == .code && plan([.code]).first == [.codeLanguage], "Code blocks lead with their language")
    }

    static func singleSelections() {
        expect(plan([]).isEmpty, "Nothing selected shows no toolbar")
        expect(plan([.webCard]).isEmpty && plan([.browser]).isEmpty && plan([.link]).isEmpty, "A single page object keeps its own header instead")
        let sticky = plan([.sticky])
        expect(sticky.first == [.color] && sticky.joined().contains(.stickyShape), "Stickies lead with colour and offer square or wide")
        expect(sticky.last == [.more], "Every toolbar ends with the ••• menu")
        let shape = plan([.rectangle])
        expect(shape.first == [.shape] && shape.joined().contains(.outline) && shape.joined().contains(.alignment), "Shapes lead with the shape picker and carry outline and alignment")
        expect(shape.joined().contains(.typeface) && !shape.joined().contains(.textFill), "Shape text picks a typeface but leaves fill to the shape itself")
        let connector = plan([.arrow]).joined()
        expect([.connectorLabel, .color, .connectorStyle, .startHead, .endHead, .routing].allSatisfy(connector.contains), "Connectors offer label, colour, style, both heads and routing")
        let section = plan([.section])
        expect(section == [[.sectionTitle], [.color], [.more]], "Sections offer a title edit, colour and the ••• menu with their lock and hide options")
        expect(plan([.image]).first == [.crop, .imageMask, .replaceImage, .altText], "Images group crop, mask, replace and alt text")
        expect(plan([.freehand]).first == [.color, .brushWidth, .pattern], "Drawings offer colour, width and tape pattern")
        let table = plan([.table]).joined()
        expect([.typeface, .textSize, .bold, .strikethrough, .color, .cellFill, .alignment, .mergeCells].allSatisfy(table.contains),
               "Tables offer typeface, size, bold, strike, text and cell colour, alignment and merge")
        expect(plan([.table], editing: true).joined().contains(.italic) && !plan([.table], editing: true).joined().contains(.mergeCells),
               "Editing a cell swaps table tools for range formatting")
        let text = plan([.text]).joined()
        expect([.typeface, .textSize, .smaller, .larger, .color, .textFill, .alignment, .link].allSatisfy(text.contains), "Text keeps the rail's family, size, fill and link plus colour and alignment")
        expect(!text.contains(.bold), "Range emphasis waits for text editing, like the rail")
    }

    static func textEditing() {
        let editing = plan([.text], editing: true).joined()
        expect([.bold, .italic, .underline, .strikethrough, .paragraph, .link, .textFill].allSatisfy(editing.contains), "Editing adds emphasis, paragraph and link controls")
        expect(editing.contains(.smaller) && editing.contains(.larger), "Editing keeps the quick size steps beside the size menu")
        expect(!plan([.text, .text], editing: true).joined().contains(.bold), "Several text objects never show range controls")
    }

    static func multipleSelections() {
        let stickies = plan([.sticky, .sticky])
        expect(stickies.first == [.color] && stickies.joined().contains(.stickyShape), "Same-kind selections keep that kind's controls")
        expect(stickies.contains([.arrange, .tidyUp]) && stickies.contains([.group, .createSection, .lock]), "Several objects add arrange, tidy up, group, section and lock")
        let mixed = plan([.sticky, .rectangle])
        expect(mixed.first == [.textSize, .bold, .paragraph, .color, .link], "Mixed selections keep only controls every kind shares")
        expect(!mixed.joined().contains(.shape) && !mixed.joined().contains(.stickyShape), "Kind-only controls leave mixed selections")
        let unrelated = plan([.image, .arrow])
        expect(unrelated.first == [.arrange, .tidyUp] && unrelated.last == [.more], "Kinds with nothing in common still get arrange tools")
        let pages = plan([.webCard, .link])
        expect(pages.contains([.arrange, .tidyUp]), "Several page objects can still be arranged together")
    }

    static func lockedSelections() {
        expect(plan([.sticky], locked: true) == [[.unlock], [.more]], "Locked selections offer only unlock and the ••• menu")
        expect(plan([.text, .arrow], locked: true) == [[.unlock], [.more]], "Locked groups unlock as one")
    }

    static func availability() {
        let filtered = EaselSelectionToolbarPlan.available(plan([.rectangle])) { $0 != .shape && $0 != .outline }
        expect(filtered.first == [.color], "Controls without a command drop out of their group")
        expect(!filtered.contains([]), "Emptied groups disappear instead of leaving stray dividers")
        expect(EaselSelectionToolbarPlan.available(plan([.image])) { $0 == .more } == [[.more]], "An image without its tools keeps the ••• menu")
    }

    static func place(_ selection: EaselRect, visible: EaselRect = EaselRect(x: 0, y: 0, width: 800, height: 600)) -> EaselSelectionToolbarPlacement? {
        EaselSelectionToolbarPlacement.place(selection: selection, width: 200, height: 36, visible: visible)
    }

    static func clear(_ placement: EaselSelectionToolbarPlacement?, of selection: EaselRect) -> Bool {
        guard let frame = placement?.frame else { return false }
        return frame.x + frame.width <= selection.x || frame.x >= selection.x + selection.width
            || frame.y + frame.height <= selection.y || frame.y >= selection.y + selection.height
    }

    static func placement() {
        let middle = EaselRect(x: 300, y: 200, width: 200, height: 100)
        let above = place(middle)
        expect(above?.edge == .above && above?.frame.y == 156 && above?.frame.x == 300, "Room above puts the toolbar eight points over the selection, centred")
        let top = EaselRect(x: 300, y: 20, width: 200, height: 100)
        let below = place(top)
        expect(below?.edge == .below && below?.frame.y == 128, "No room above drops the toolbar eight points below")
        let left = place(EaselRect(x: -150, y: 200, width: 200, height: 100))
        expect(left?.frame.x == 8, "The toolbar stays inside the visible area when the selection runs off its edge")
        let tall = EaselRect(x: 100, y: -50, width: 200, height: 700)
        let beside = place(tall)
        expect(beside?.edge == .inside && clear(beside, of: tall), "A selection taller than the view gets the toolbar beside it, not on top of it")
        let wide = EaselRect(x: -50, y: -48, width: 900, height: 600)
        let strip = place(wide)
        expect(strip?.edge == .inside && clear(strip, of: wide) && strip?.frame.y == 556, "A selection filling the width keeps the toolbar in the free strip under it")
        let full = EaselRect(x: -100, y: -100, width: 1000, height: 800)
        let pinned = place(full)
        expect(pinned?.edge == .inside && pinned?.frame.y == 8 && pinned?.frame.x == 300, "A selection covering the whole view pins the toolbar to the top centre")
        expect(place(EaselRect(x: 900, y: 900, width: 50, height: 50)) == nil, "A selection scrolled out of view parks the toolbar")
        expect(EaselSelectionToolbarPlacement.place(selection: middle, width: 0, height: 36,
                                                     visible: EaselRect(x: 0, y: 0, width: 800, height: 600)) == nil, "An empty toolbar never places")
    }

    static func chord() {
        expect(EaselChords.command(characters: "?", keyCode: 44, modifiers: [.command, .shift]) == .focusSelectionToolbar,
               "⇧⌘/ focuses the selection toolbar, typed as a question mark")
        expect(EaselChords.command(characters: "/", keyCode: 44, modifiers: [.command, .shift]) == .focusSelectionToolbar,
               "⇧⌘/ also matches when the layout reports the unshifted slash")
        expect(EaselChords.command(characters: "/", keyCode: 44, modifiers: [.command]) == nil
               && EaselChords.command(characters: "?", keyCode: 44, modifiers: [.shift]) == nil, "Other slash chords stay Parc's")
        expect(EaselChords.reserved.allSatisfy { EaselChords.table[$0] == nil }, "The toolbar chord never takes a reserved Parc chord")
    }
}
