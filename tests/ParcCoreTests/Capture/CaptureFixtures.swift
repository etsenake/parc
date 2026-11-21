import Foundation
@testable import ParcCore

extension CapturePaletteMenuTests {
    struct Destinations {
        let profile = UUID()
        let otherProfile = UUID()
        let design = UUID()
        let travel = UUID()
        let research = UUID()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("parc-capture-palette-" + UUID().uuidString, isDirectory: true)
        let easels: [CaptureEaselDestination]
        let notes: [CaptureNoteDestination]

        var recipes: URL { folder.appendingPathComponent("Recipes.md") }
        var journal: URL { folder.appendingPathComponent("Journal.md") }
        var recipesNote: CaptureNoteDestination { notes.first { $0.title == "Recipes" }! }
        var full: CapturePaletteContext { CapturePaletteContext(easels: easels, notes: notes, notesAvailable: true) }

        init() {
            easels = CaptureEaselDestination.catalog(documents: [
                EaselSummary(id: design, title: "Design", modifiedAt: Date(timeIntervalSince1970: 100), itemCount: 1),
                EaselSummary(id: travel, title: "Travel", modifiedAt: Date(timeIntervalSince1970: 900), itemCount: 2),
                EaselSummary(id: research, title: "Research", modifiedAt: Date(timeIntervalSince1970: 999), itemCount: 0),
            ], activity: [
                .init(id: design, profileID: profile, date: Date(timeIntervalSince1970: 800)),
                .init(id: travel, profileID: profile, date: Date(timeIntervalSince1970: 400)),
                .init(id: research, profileID: otherProfile, date: Date(timeIntervalSince1970: 2000)),
            ], profileID: profile)
            notes = CaptureNoteDestination.catalog(notes: [
                NoteReference(url: folder.appendingPathComponent("Journal.md"), title: "Journal", icon: "📓", modifiedAt: Date(timeIntervalSince1970: 50)),
                NoteReference(url: folder.appendingPathComponent("Recipes.md"), title: "Recipes", icon: nil, modifiedAt: Date(timeIntervalSince1970: 10)),
            ], activity: [.init(url: folder.appendingPathComponent("Recipes.md"), profileID: profile, date: Date(timeIntervalSince1970: 700))], profileID: profile)
        }

        func easelRow(_ id: UUID) -> String { "easel:" + id.uuidString }
    }
}
