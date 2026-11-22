import AppKit
import Combine
import ParcTestSupport
import Testing
@testable import Parc

struct InterfaceFeedbackTests {
    @MainActor private final class Sound: InterfaceCaptureSound {
        var volume: Float = 1
        var volumes: [Float] = []
        var acceptsPlay = true
        func play() -> Bool {
            volumes.append(volume)
            return acceptsPlay
        }
    }

    @MainActor private func withPreferences(_ body: (InterfaceFeedbackPreferences, UserDefaults) throws -> Void) throws {
        let defaults = try #require(TestDefaults("parc.feedback."))
        try body(InterfaceFeedbackPreferences(defaults: defaults), defaults)
    }

    @Test @MainActor func absentPreferencesEnableBothFormsOfFeedbackWithoutWritingARecord() throws {
        try withPreferences { preferences, defaults in
            #expect(!preferences.loadError)
            #expect(preferences.state.playsSoundEffects && preferences.state.reorderingHaptics)
            #expect(defaults.object(forKey: "parc.interfaceFeedback.v1") == nil)
        }
    }

    @Test(arguments: [false, true])
    @MainActor func changingOneFeedbackPreferencePreservesTheOther(sound: Bool) throws {
        try withPreferences { preferences, defaults in
            if sound { try preferences.setPlaysSoundEffects(false) } else { try preferences.setReorderingHaptics(false) }
            let reopened = InterfaceFeedbackPreferences(defaults: defaults)
            #expect(reopened.state.playsSoundEffects == !sound)
            #expect(reopened.state.reorderingHaptics == sound)
        }
    }

    @Test @MainActor func anUnchangedFeedbackPreferenceDoesNotPublish() throws {
        try withPreferences { preferences, _ in
            let observation = preferences.$state.dropFirst().sink { _ in Issue.record("Published an unchanged preference") }
            try preferences.setReorderingHaptics(true)
            withExtendedLifetime(observation) {}
        }
    }

    @Test(arguments: [(false, true), (true, false)])
    @MainActor func disabledOrInactiveCaptureFeedbackDoesNotLoadASound(example: (Bool, Bool)) throws {
        try withPreferences { preferences, _ in
            try preferences.setPlaysSoundEffects(example.1)
            let audio = InterfaceSoundEffects(preferences: preferences, isActive: { example.0 }) {
                Issue.record("Loaded a disabled sound")
                return nil
            }
            audio.playCapture()
        }
    }

    @Test @MainActor func preloadingCachesTheSoundWithoutPlayingIt() throws {
        try withPreferences { preferences, _ in
            let sound = Sound()
            var loads = 0
            let audio = InterfaceSoundEffects(preferences: preferences, isActive: { true }) { loads += 1; return sound }
            audio.preload()
            audio.preload()
            #expect(loads == 1)
            #expect(sound.volumes.isEmpty)
        }
    }

    @Test(arguments: [true, false])
    @MainActor func aCaptureEventPlaysCachedAudioOnceAtTheConfiguredVolume(acceptsPlay: Bool) throws {
        try withPreferences { preferences, _ in
            let sound = Sound()
            sound.acceptsPlay = acceptsPlay
            var loads = 0
            let audio = InterfaceSoundEffects(preferences: preferences, isActive: { true }) { loads += 1; return sound }
            audio.preload()
            audio.playCapture()
            #expect(loads == 1)
            #expect(sound.volumes == [0.7])
        }
    }

    @Test @MainActor func missingPreloadedAudioCanBeRetriedAtTheNextCapture() throws {
        try withPreferences { preferences, _ in
            let sound = Sound()
            var loads = 0
            let audio = InterfaceSoundEffects(preferences: preferences, isActive: { true }) {
                loads += 1
                return loads == 1 ? nil : sound
            }
            audio.preload()
            audio.playCapture()
            #expect(loads == 2)
            #expect(sound.volumes == [0.7])
        }
    }

    @Test(arguments: [(2, 1), (3, 2), (-1, 2)])
    @MainActor func onlyChangingTheInsertionIndexRepeatsTheHaptic(example: (Int, Int)) throws {
        try withPreferences { preferences, _ in
            var pulses = 0
            let feedback = SidebarReorderingFeedback(preferences: preferences) { pulses += 1 }
            feedback.propose(index: 2)
            feedback.propose(index: example.0)
            #expect(pulses == example.1)
        }
    }

    @Test @MainActor func reenablingHapticsEmitsForTheLatestInsertionIndex() throws {
        try withPreferences { preferences, _ in
            try preferences.setReorderingHaptics(false)
            var pulses = 0
            let feedback = SidebarReorderingFeedback(preferences: preferences) { pulses += 1 }
            feedback.propose(index: 8)
            #expect(pulses == 0)
            try preferences.setReorderingHaptics(true)
            feedback.propose(index: 8)
            #expect(pulses == 1)
        }
    }

    @Test @MainActor func changingSoundDoesNotReplayTheInsertionHaptic() throws {
        try withPreferences { preferences, _ in
            var pulses = 0
            let feedback = SidebarReorderingFeedback(preferences: preferences) { pulses += 1 }
            feedback.propose(index: 8)
            try preferences.setPlaysSoundEffects(false)
            #expect(pulses == 1)
        }
    }

    @Test @MainActor func eachSidebarOwnsItsInsertionHistory() throws {
        try withPreferences { preferences, _ in
            var first = 0
            var second = 0
            let left = SidebarReorderingFeedback(preferences: preferences) { first += 1 }
            let right = SidebarReorderingFeedback(preferences: preferences) { second += 1 }
            left.propose(index: 8)
            right.propose(index: 8)
            #expect(first == 1 && second == 1)
        }
    }

    @Test(arguments: ["bad", #"{"version":99,"playsSoundEffects":true,"reorderingHaptics":true}"#])
    @MainActor func invalidFeedbackPreferencesPreserveTheRecordAndDisableOutput(saved: String) throws {
        try withPreferences { _, defaults in
            let key = "parc.interfaceFeedback.v1"
            let bytes = Data(saved.utf8)
            defaults.set(bytes, forKey: key)
            let preferences = InterfaceFeedbackPreferences(defaults: defaults)
            #expect(preferences.loadError)
            #expect(throws: InterfaceFeedbackPreferences.Failure.unavailable) { try preferences.setPlaysSoundEffects(false) }
            #expect(throws: InterfaceFeedbackPreferences.Failure.unavailable) { try preferences.setReorderingHaptics(false) }
            #expect(defaults.data(forKey: key) == bytes)
            let audio = InterfaceSoundEffects(preferences: preferences, isActive: { true }) {
                Issue.record("Unreadable preferences allowed audio")
                return nil
            }
            let feedback = SidebarReorderingFeedback(preferences: preferences) { Issue.record("Unreadable preferences allowed haptics") }
            audio.playCapture()
            feedback.propose(index: 2)
        }
    }
}
