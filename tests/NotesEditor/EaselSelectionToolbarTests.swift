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
        print("EaselSelectionToolbarTests passed")
    }

    static func subjects() {
        expect(EaselToolbarSubject(.rectangle) == .shape && EaselToolbarSubject(.circle) == .shape, "Rectangles and ellipses share the shape toolbar")
        expect(EaselToolbarSubject(.arrow) == .connector, "Arrows use the connector toolbar")
        expect(EaselToolbarSubject(.freehand) == .drawing, "Doodles, highlights and tape use the drawing toolbar")
        expect([EaselItemKind.webCard, .browser, .link].allSatisfy { EaselToolbarSubject($0) == .page }, "Pages, captures and links are page objects")
    }

    static func singleSelections() {
        expect(plan([]).isEmpty, "Nothing selected shows no toolbar")
        expect(plan([.webCard]).isEmpty && plan([.browser]).isEmpty && plan([.link]).isEmpty, "A single page object keeps its own header instead")
        let sticky = plan([.sticky])
        expect(sticky.first == [.color] && sticky.joined().contains(.stickyShape), "Stickies lead with colour and offer square or wide")
        expect(sticky.last == [.more], "Every toolbar ends with the ••• menu")
        let shape = plan([.rectangle])
        expect(shape.first == [.shape] && shape.joined().contains(.outline) && shape.joined().contains(.alignment), "Shapes lead with the shape picker and carry outline and alignment")
        let connector = plan([.arrow]).joined()
        expect([.connectorLabel, .color, .connectorStyle, .startHead, .endHead, .routing].allSatisfy(connector.contains), "Connectors offer label, colour, style, both heads and routing")
        let section = plan([.section])
        expect(section.first == [.sectionTitle] && section.joined().contains(.sectionOptions), "Sections offer a title edit and their own options")
        expect(plan([.image]).first == [.crop, .replaceImage, .altText], "Images group crop, replace and alt text")
        expect(plan([.freehand]).first == [.color, .brushWidth, .pattern], "Drawings offer colour, width and tape pattern")
        let text = plan([.text]).joined()
        expect([.typeface, .textSize, .smaller, .larger, .color, .textFill, .alignment, .link].allSatisfy(text.contains), "Text keeps the rail's family, size, fill and link plus colour and alignment")
        expect(!text.contains(.bold), "Range emphasis waits for text editing, like the rail")
    }

    static func textEditing() {
        let editing = plan([.text], editing: true).joined()
        expect([.bold, .italic, .underline, .strikethrough, .paragraph, .link, .textFill].allSatisfy(editing.contains), "Editing adds emphasis, paragraph and link controls")
        expect(!editing.contains(.smaller) && !editing.contains(.larger), "Editing swaps the size steppers for the size menu")
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
}
