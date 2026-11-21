import Foundation

@main
struct CapturePaletteTests {
    @MainActor static var assertions = 0
    @MainActor static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        precondition(value(), message)
    }
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() throws {
        let profile = UUID(), otherProfile = UUID()
        let design = UUID(), travel = UUID(), research = UUID()
        let easels = CaptureEaselDestination.catalog(documents: [
            EaselSummary(id: design, title: "Design", modifiedAt: Date(timeIntervalSince1970: 100), itemCount: 1),
            EaselSummary(id: travel, title: "Travel", modifiedAt: Date(timeIntervalSince1970: 900), itemCount: 2),
            EaselSummary(id: research, title: "Research", modifiedAt: Date(timeIntervalSince1970: 999), itemCount: 0),
        ], activity: [
            .init(id: design, profileID: profile, date: Date(timeIntervalSince1970: 800)),
            .init(id: travel, profileID: profile, date: Date(timeIntervalSince1970: 400)),
            .init(id: research, profileID: otherProfile, date: Date(timeIntervalSince1970: 2000)),
        ], profileID: profile)
        expect(easels.first { $0.id == travel }?.modifiedAt == Date(timeIntervalSince1970: 900),
               "Easel destinations carry their last edit for the submenu subtitle")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("parc-capture-palette-" + UUID().uuidString, isDirectory: true)
        let recipes = folder.appendingPathComponent("Recipes.md"), journal = folder.appendingPathComponent("Journal.md")
        let notes = CaptureNoteDestination.catalog(notes: [
            NoteReference(url: journal, title: "Journal", icon: "📓", modifiedAt: Date(timeIntervalSince1970: 50)),
            NoteReference(url: recipes, title: "Recipes", icon: nil, modifiedAt: Date(timeIntervalSince1970: 10)),
        ], activity: [.init(url: recipes, profileID: profile, date: Date(timeIntervalSince1970: 700))], profileID: profile)

        let full = CapturePaletteContext(easels: easels, notes: notes, notesAvailable: true)
        let main = CapturePaletteMenu.rows(full)
        expect(main.map(\.id) == ["library", "copy", "save", "message", "edit", "crop", "frame", "retake", "easels", "notes"],
               "Quick actions, then the edit group, then Send To with one row per destination kind")
        expect(main.filter(\.separatorBefore).map(\.id) == ["edit"], "Only the edit group opens with a divider")
        expect(main.filter { $0.section == CapturePaletteMenu.sendToTitle }.map(\.id) == ["easels", "notes"],
               "Easel and Note sit under the Send To header")
        expect(main.filter(\.hasSubmenu).map(\.id) == ["easels", "notes"], "Only the destination kinds open submenus")
        expect(main.count == 10 && !main.contains { $0.action.submenu == nil && $0.id.hasPrefix("easel:") },
               "The main palette never grows with the number of Easels or Notes")
        expect(!main.contains { $0.title == "Show More" }, "Show More is gone")
        expect(main.allSatisfy { !$0.isChecked }, "Nothing is filled or checked before a save")
        expect(CapturePaletteMenu.firstAvailable(in: main) == "library",
               "A fresh palette gives Save to Library the shared highlight, so one Return saves")

        let framed = CapturePaletteMenu.rows(CapturePaletteContext(easels: easels, framed: true))
        expect(framed.map(\.id) == ["library", "copy", "save", "message", "edit", "crop", "frame", "removeFrame", "retake", "easels"],
               "Remove Frame joins the edit group only for framed captures")
        expect(framed.first { $0.id == "frame" }?.title == "Edit Portrait Frame", "A framed capture offers to edit its frame")

        let saved = CapturePaletteContext(easels: easels, librarySaved: true)
        let savedRow = CapturePaletteMenu.rows(saved).first!
        expect(savedRow.title == "Saved to Library" && savedRow.isChecked, "A saved capture shows a checked Saved to Library")
        expect(CapturePaletteMenu.rows(saved, query: "saved").map(\.id) == ["library"]
               && CapturePaletteMenu.rows(saved, query: "save to").isEmpty, "Search matches the current toggle title")

        let easelMenu = CapturePaletteMenu.submenu(.easels, context: full)
        expect(easelMenu.map(\.id) == ["newEasel", "easel:" + design.uuidString, "easel:" + travel.uuidString, "easel:" + research.uuidString],
               "New Easel leads, then every Easel by its latest sidebar activity in this profile")
        expect(easelMenu.first?.section == nil && easelMenu.dropFirst().allSatisfy { $0.section == CapturePaletteMenu.recentTitle },
               "Existing Easels sit under Recent")
        let noteMenu = CapturePaletteMenu.submenu(.notes, context: full)
        expect(noteMenu.map(\.id) == [CaptureNoteTarget.newNote.id, notes[0].id, notes[1].id] && noteMenu[1].title == "Recipes",
               "New Note leads, then notes in the notes catalog's recency order")
        expect(noteMenu.dropFirst().map(\.id) == CaptureNoteDestination.ranked(notes).map(\.id), "Note ranking follows the catalog")
        let emptyMenu = CapturePaletteMenu.submenu(.easels, context: CapturePaletteContext())
        expect(emptyMenu.map(\.id) == ["newEasel"] && emptyMenu[0].section == nil, "No Easels means just New Easel, no empty header")
        expect(CapturePaletteMenu.submenu(.easels, context: full, query: "TRA").map(\.id) == ["easel:" + travel.uuidString],
               "Submenu search filters its own kind, case-insensitively")
        expect(CapturePaletteMenu.submenu(.notes, context: full, query: "new").map(\.id) == [CaptureNoteTarget.newNote.id],
               "Submenu search can still reach New Note")
        expect(CapturePaletteMenu.submenu(.easels, context: full, query: "re").allSatisfy { $0.section == nil },
               "Filtered submenus drop their headers")

        let search = CapturePaletteMenu.rows(CapturePaletteContext(easels: easels, notes: notes, framed: true, notesAvailable: true), query: "re")
        expect(search.map(\.id) == ["removeFrame", "retake", "easel:" + research.uuidString, notes.first { $0.title == "Recipes" }!.id],
               "Search runs across actions, then Easels, then Notes, keeping their order")
        expect(search.filter { $0.id.hasPrefix("easel:") || $0.id.hasPrefix("note:") }.map(\.subtitle) == ["Easel", "Note"],
               "Flat results name their kind")
        expect(search.allSatisfy { $0.section == nil && !$0.separatorBefore }, "Flat results omit headers and dividers")
        expect(CapturePaletteMenu.rows(full, query: "e").allSatisfy { !$0.hasSubmenu }, "Search skips the submenu rows themselves")
        expect(CapturePaletteMenu.rows(full, query: "new").map(\.id) == ["newEasel", CaptureNoteTarget.newNote.id],
               "Search reaches New Easel and New Note directly")
        expect(CapturePaletteMenu.rows(full, query: " research").isEmpty && CapturePaletteMenu.rows(full, query: "zzzz").isEmpty,
               "Literal spaces and misses stay empty")

        let privateWindow = CapturePaletteContext(easels: easels, notes: notes, easelsAvailable: false, notesAvailable: false)
        expect(CapturePaletteMenu.rows(privateWindow).map(\.id) == ["library", "copy", "save", "message", "edit", "crop", "frame", "retake"],
               "Private captures keep Library and outputs but have no Send To section")
        expect(CapturePaletteMenu.rows(privateWindow, query: "re").map(\.id) == ["retake"], "Search can't reach Easels or Notes in private")
        expect(CapturePaletteMenu.submenu(.easels, context: privateWindow).isEmpty && CapturePaletteMenu.submenu(.notes, context: privateWindow).isEmpty,
               "Private captures have no destination submenus")
        let noLibrary = CapturePaletteContext(easels: easels, libraryAvailable: false)
        expect(!CapturePaletteMenu.rows(noLibrary).contains { $0.id == "library" || $0.id == "easels" },
               "Without a Library destination there is no Library row or Easel submenu")
        expect(CapturePaletteMenu.firstAvailable(in: CapturePaletteMenu.rows(noLibrary)) == "copy",
               "Without a Library destination the opening highlight falls to Copy")

        let busy = CapturePaletteMenu.rows(CapturePaletteContext(easels: easels, notesAvailable: true, busy: true))
        expect(busy.allSatisfy { !$0.isEnabled }, "A Library write or open composer disables every row")
        expect(CapturePaletteMenu.firstAvailable(in: busy) == nil, "A busy palette opens with nothing to highlight")
        let noMessages = CapturePaletteMenu.rows(CapturePaletteContext(messageAvailable: false))
        expect(noMessages.filter { !$0.isEnabled }.map(\.id) == ["message"], "Unavailable Messages is the only skipped row")

        let renamed = CapturePaletteContext(easels: easels.map {
            $0.id == travel ? CaptureEaselDestination(id: travel, title: "Trips", lastActive: $0.lastActive) : $0
        })
        let renamedRows = CapturePaletteMenu.submenu(.easels, context: renamed)
        expect(CapturePaletteMenu.retainedHighlight("easel:" + travel.uuidString, in: renamedRows) == "easel:" + travel.uuidString
               && renamedRows.contains { $0.title == "Trips" }, "Renaming keeps the exact Easel UUID highlighted")
        expect(CapturePaletteMenu.retainedHighlight("message", in: noMessages) == nil, "A row that became unavailable loses the highlight")
        expect(CapturePaletteMenu.retainedHighlight("easel:" + UUID().uuidString, in: renamedRows) == nil, "A deleted Easel is never substituted")
        expect(CapturePaletteMenu.firstAvailable(in: noMessages.filter { $0.id == "message" || $0.id == "save" }) == "save",
               "New search text highlights the first available result")
        expect(CapturePaletteMenu.firstAvailable(in: []) == nil, "No results means no output selection")
        let travelDocument = CapturePaletteDocument(easels.first { $0.id == travel }!)
        expect(travelDocument.id == "easel:" + travel.uuidString && travelDocument.kind == .easel && travelDocument.target == .easel(travel),
               "Easel rows keep their exact UUID")
        let recipesDocument = CapturePaletteDocument(notes.first { $0.title == "Recipes" }!)
        expect(recipesDocument.id == notes.first { $0.title == "Recipes" }!.id && recipesDocument.target == .note(recipes),
               "Note rows keep the catalog's exact file identity")

        typealias Keys = CapturePaletteKeys
        expect(Keys.command(.down, focus: .main, highlighted: nil) == .move(1)
               && Keys.command(.up, focus: .main, highlighted: .copy) == .move(-1), "Arrows move the single highlight")
        expect(Keys.command(.enter, focus: .main, highlighted: .copy) == .activate, "Return activates the highlighted action")
        expect(Keys.command(.enter, focus: .main, highlighted: .library) == .activate,
               "Return on the opening highlight saves to the Library in one press")
        expect(Keys.command(.enter, focus: .main, highlighted: nil) == .move(1),
               "Return without a highlight reveals the first row instead of acting unseen")
        expect(Keys.command(.enter, focus: .main, highlighted: .easels) == .open(.easels), "Return on Easel opens its submenu")
        expect(Keys.command(.right, focus: .main, highlighted: .notes) == .open(.notes), "Right opens the highlighted submenu")
        expect(Keys.command(.right, focus: .main, highlighted: .notes, caretAtEnd: false) == .pass,
               "Right inside typed text still moves the caret")
        expect(Keys.command(.right, focus: .main, highlighted: .copy) == .pass, "Right on a plain action stays with the field")
        expect(Keys.command(.escape, focus: .main, highlighted: .copy) == .cancel, "Escape in the palette cancels the capture")
        expect(Keys.command(.tab, focus: .main, highlighted: nil) == .consume, "Tab stays in the menu like Parc's other menus")
        expect(Keys.command(.enter, focus: .main, highlighted: .copy, composing: true) == .pass,
               "Input method composition never dispatches a destination")
        expect(Keys.command(.left, focus: .submenu(.easels), highlighted: nil) == .closeSubmenu
               && Keys.command(.left, focus: .submenu(.easels), highlighted: nil, caretAtStart: false) == .pass,
               "Left leaves a submenu only from the start of its search")
        expect(Keys.command(.escape, focus: .submenu(.notes), highlighted: nil) == .closeSubmenu, "Escape closes just the submenu")
        expect(Keys.command(.enter, focus: .submenu(.notes), highlighted: .newNote) == .activate, "Return in a submenu sends there")
        expect(Keys.command(.escape, focus: .frame, highlighted: nil) == .back && Keys.command(.left, focus: .frame, highlighted: nil) == .back,
               "Escape and Left go back from the Frame page")
        expect(Keys.command(.enter, focus: .frame, highlighted: nil) == .activate && Keys.command(.tab, focus: .frame, highlighted: nil) == .pass,
               "Return applies on the Frame page and Tab walks its controls")

        let color = CaptureFrameSettings(background: .color, fraction: 0.5, watermark: true)
        expect(CaptureFrameApply.state(committed: nil, draft: color, renderable: true) == .pending,
               "Adding a frame to an unframed capture is a pending change")
        expect(CaptureFrameApply.state(committed: color, draft: color, renderable: true) == .unchanged,
               "Reopening a frame without changes leaves Apply quiet")
        var moved = color; moved.fraction = 0.8
        expect(CaptureFrameApply.state(committed: color, draft: moved, renderable: true).isPrimary, "A new color is a pending change")
        moved.fraction = 0.5004
        expect(CaptureFrameApply.state(committed: color, draft: moved, renderable: true) == .unchanged, "Slider jitter is not a change")
        let website = CaptureFrameSettings(background: .page, fraction: 0.2, watermark: true)
        var websiteMoved = website; websiteMoved.fraction = 0.9
        expect(CaptureFrameApply.state(committed: website, draft: websiteMoved, renderable: true) == .unchanged,
               "The color slider doesn't change a website-colored frame")
        var bare = color; bare.watermark = false
        expect(CaptureFrameApply.state(committed: color, draft: bare, renderable: true) == .pending, "Hiding the watermark is a change")
        expect(CaptureFrameApply.state(committed: nil, draft: color, renderable: false) == .unavailable
               && !CaptureFrameApply.unavailable.isPrimary, "A frame that can't render can't be applied")
        print("Capture palette: \(assertions) assertions passed")
    }
}
