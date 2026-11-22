import Foundation
import Testing
@testable import ParcCore

struct NotePageToolsTitleTests {
    struct AcceptedTitle: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let title: String
    }

    private static let acceptedTitles = [
        AcceptedTitle(testDescription: "fresh name", title: "Weekend plans"),
        AcceptedTitle(testDescription: "same name", title: "Groceries"),
        AcceptedTitle(testDescription: "case only change", title: "groceries"),
        AcceptedTitle(testDescription: "blank keeps the old name", title: "   "),
        AcceptedTitle(testDescription: "slash becomes a dash", title: "a/b"),
    ]

    @Test func aTakenNameIsCaughtBeforeRenaming() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("title-checks-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("Groceries.md")
        let neighbour = folder.appendingPathComponent("Errands.md")
        try? Data("a".utf8).write(to: note)
        try? Data("b".utf8).write(to: neighbour)
        #expect(NotePageTitleCheck.problem(renaming: note, to: "Errands") == .nameTaken("Errands"), "a taken name is caught before renaming")
        #expect(NotePageTitleCheck.problem(renaming: note, to: "Errands")?.errorDescription == "There’s already a note called “Errands” here.", "the collision reads in Parc's voice")
    }

    @Test func aNameOfOnlyDotsIsInvalid() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("title-checks-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("Groceries.md")
        let neighbour = folder.appendingPathComponent("Errands.md")
        try? Data("a".utf8).write(to: note)
        try? Data("b".utf8).write(to: neighbour)
        #expect(NotePageTitleCheck.problem(renaming: note, to: "...") == .invalidName, "a name made only of dots can't be a file")
        #expect(NotePageTitleCheck.problem(renaming: note, to: "...")?.errorDescription == "Notes can’t be named that.", "invalid names explain themselves")
    }

    @Test(arguments: acceptedTitles) func validTitleChangesPassTheRenameCheck(_ example: AcceptedTitle) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("title-checks-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("Groceries.md")
        let neighbour = folder.appendingPathComponent("Errands.md")
        try? Data("a".utf8).write(to: note)
        try? Data("b".utf8).write(to: neighbour)
        #expect(NotePageTitleCheck.problem(renaming: note, to: example.title) == nil)
    }
}
