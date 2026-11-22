import Foundation
import ParcTestSupport
import Testing
@testable import ParcCore

enum NoteEmojiTestsSupport {
    @MainActor final class Fixture {
        let url = Bundle.module.url(forResource: "emoji", withExtension: "json")!
        let defaults: UserDefaults
        let catalog: NoteEmojiCatalog

        init() {
            defaults = TestDefaults("Parc.Notes.EmojiTests.")!
            catalog = NoteEmojiCatalog(url: url, defaults: defaults)
        }
    }
}
