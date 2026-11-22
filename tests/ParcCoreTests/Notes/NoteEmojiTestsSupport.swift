import Foundation
import Testing
@testable import ParcCore

enum NoteEmojiTestsSupport {
    @MainActor final class Fixture {
        let url = Bundle.module.url(forResource: "emoji", withExtension: "json")!
        let suite = "Parc.Notes.EmojiTests." + UUID().uuidString
        let defaults: UserDefaults
        let catalog: NoteEmojiCatalog

        init() {
            defaults = UserDefaults(suiteName: suite)!
            catalog = NoteEmojiCatalog(url: url, defaults: defaults)
        }

        deinit {
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
