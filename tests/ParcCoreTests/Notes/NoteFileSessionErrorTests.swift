import Foundation
import Testing
@testable import ParcCore

struct NoteFileSessionErrorTests {
    @Test func theOccupiedErrorSaysWhatIsWrong() {
        #expect(NoteFileError.occupied("Taken.md").localizedDescription == "Something else is already called “Taken.md” there. Move or rename it, then try again.")
    }

    @Test func theUnsavedErrorReadsInWordsPeopleCanActOn() {
        #expect(NoteFileError.unsaved(["Stubborn"]).localizedDescription == "Parc couldn’t save “Stubborn” yet. Open it to sort things out.")
    }
}
