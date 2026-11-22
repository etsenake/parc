import Foundation
import Testing
@testable import ParcCore

struct EaselStoreTypingHistoryTests {
    @MainActor @Test
    func eachEditInACoalescedRunStillReachesDisk() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            try session.perform("Add") { $0.items = [EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "")] }
            let group = UUID()
            for text in ["a", "ab", "abc"] {
                try session.perform("Type", coalescing: group) { $0.items[0].text = text }
                let fresh = try EaselStore(directory: directory).load(session.document.id)
                #expect(fresh.document.items[0].text == text, "Each coalesced edit still reaches disk")
            }
        }
    }

    @MainActor @Test
    func coalescedTypingUndoesAndRedoesAsOneRun() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            try session.perform("Add") { $0.items = [EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "")] }
            let group = UUID()
            for text in ["a", "ab", "abc"] {
                try session.perform("Type", coalescing: group) { $0.items[0].text = text }
                let fresh = try EaselStore(directory: directory).load(session.document.id)
                #expect(fresh.document.items[0].text == text, "Each coalesced edit still reaches disk")
            }
            try session.undo()
            #expect(session.document.items[0].text == "", "One document undo restores typing-run start")
            try session.redo()
        }
    }

    @MainActor @Test
    func aRunWithNoNetChangesLeavesNoExtraUndoStep() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            try session.perform("Add") { $0.items = [EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "")] }
            let group = UUID()
            for text in ["a", "ab", "abc"] {
                try session.perform("Type", coalescing: group) { $0.items[0].text = text }
            }
            try session.perform("Type", coalescing: group) { $0.items[0].text = "abcX" }
            try session.perform("Type", coalescing: group) { $0.items[0].text = "abc" }
            #expect(session.document.items[0].text == "abc", "Typing that is undone back to its start leaves the text unchanged")
            try session.undo()
            #expect(session.document.items[0].text == "", "A typing run that nets to nothing leaves no empty undo step behind")
            try session.redo()
            #expect(session.document.items[0].text == "abc", "Redo restores the complete typing run")
        }
    }

    @MainActor @Test
    func anInterveningEditBreaksCoalescingAndHasItsOwnUndo() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            try session.perform("Add") { $0.items = [EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "")] }
            let group = UUID()
            for text in ["a", "ab", "abc"] {
                try session.perform("Type", coalescing: group) { $0.items[0].text = text }
            }
            try session.perform("Type", coalescing: group) { $0.items[0].text = "abcd" }
            try session.perform("Other window") { $0.title = "From another window" }
            try session.perform("Type", coalescing: group) { $0.items[0].text = "abcde" }
            try session.undo()
            #expect(session.document.items[0].text == "abcd" && session.document.title == "From another window", "An intervening transaction breaks coalescing and survives undo")
            try session.undo()
            #expect(session.document.items[0].text == "abcd" && session.document.title != "From another window", "Other-window transaction stays independently undoable")
        }
    }

    @MainActor @Test
    func aFailedCoalescedEditKeepsTheRedoBranch() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            try session.perform("Add") { $0.items = [EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "")] }
            let group = UUID()
            for text in ["a", "ab", "abc"] {
                try session.perform("Type", coalescing: group) { $0.items[0].text = text }
            }
            try session.perform("Type", coalescing: group) { $0.items[0].text = "abcd" }
            try session.perform("Other window") { $0.title = "From another window" }
            try session.perform("Type", coalescing: group) { $0.items[0].text = "abcde" }
            try session.undo()
            try session.undo()
            let beforeFailure = session.document
            EaselStoreTestsSupport.expectThrows("failed coalesced transaction") {
                try session.perform("Type", coalescing: group) { $0.items[0].color = "invalid" }
            }
            #expect(session.document == beforeFailure && session.canRedo, "Failed coalesced write preserves document and redo branch")
        }
    }

    @MainActor @Test
    func undoingAStyleChangePreservesTheText() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            try session.perform("Add") { $0.items = [EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "")] }
            let group = UUID()
            for text in ["a", "ab", "abc"] {
                try session.perform("Type", coalescing: group) { $0.items[0].text = text }
            }
            try session.perform("Type", coalescing: group) { $0.items[0].text = "abcd" }
            try session.perform("Other window") { $0.title = "From another window" }
            try session.perform("Type", coalescing: group) { $0.items[0].text = "abcde" }
            try session.undo()
            try session.undo()
            try session.perform("Style") { $0.items[0].textStyle = EaselTextStyle(family: .fancy, size: .h0) }
            try session.undo()
            #expect(session.document.items[0].textStyle == nil && session.document.items[0].text == "abcd", "Style undo preserves text and previous implicit style")
        }
    }
}
