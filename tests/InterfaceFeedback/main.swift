import AppKit
import Combine

@MainActor
final class RecordingSound: InterfaceCaptureSound {
    var volume: Float = 1
    var plays = 0
    var volumes: [Float] = []
    var acceptsPlay = true
    func play() -> Bool {
        plays += 1; volumes.append(volume); return acceptsPlay
    }
}

MainActor.assumeIsolated { exitOnFailure {
    let suite = "Parc.InterfaceFeedbackChecks." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "parc.interfaceFeedback.v1"
    var checks = 0
    func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    let preferences = InterfaceFeedbackPreferences(defaults: defaults)
    check(!preferences.loadError, "empty preference owner is readable")
    check(defaults.object(forKey: key) == nil, "loading does not write a default record")
    check(preferences.state.playsSoundEffects && preferences.state.reorderingHaptics, "documented absent-record fallback")
    var published: [InterfaceFeedbackPreferences.State] = []
    let subscription = preferences.$state.sink { published.append($0) }
    try preferences.setPlaysSoundEffects(false)
    check(preferences.state.reorderingHaptics, "sound toggle preserves haptic choice")
    try preferences.setReorderingHaptics(false)
    check(!preferences.state.playsSoundEffects, "haptic toggle preserves sound choice")
    let restored = InterfaceFeedbackPreferences(defaults: defaults)
    check(restored.state == preferences.state, "both choices survive a fresh owner")
    let publicationCount = published.count
    let stored = defaults.data(forKey: key)
    try preferences.setReorderingHaptics(false)
    check(published.count == publicationCount && defaults.data(forKey: key) == stored, "same value has no extra publication")
    try preferences.setPlaysSoundEffects(true)
    check(published.last?.playsSoundEffects == true && published.last?.reorderingHaptics == false, "consumers receive incoming new state")

    let sound = RecordingSound()
    var loads = 0
    var active = false
    let audio = InterfaceSoundEffects(preferences: preferences, isActive: { active }) { loads += 1; return sound }
    audio.playCapture()
    check(loads == 0 && sound.plays == 0, "inactive app neither loads nor plays")
    active = true
    try preferences.setPlaysSoundEffects(false)
    audio.playCapture()
    check(loads == 0 && sound.plays == 0, "disabled sound neither loads nor plays")
    audio.preload(); audio.preload()
    check(loads == 1 && sound.plays == 0, "preload caches once without audible output")
    try preferences.setPlaysSoundEffects(true)
    audio.playCapture(); audio.playCapture()
    check(loads == 1 && sound.plays == 2, "rapid valid events use the same native sound")
    check(sound.volumes == [0.7, 0.7], "each native play receives recovered capture volume")
    sound.acceptsPlay = false
    audio.playCapture()
    check(sound.plays == 3 && loads == 1, "native overlap refusal is not replayed or reloaded")
    active = false; audio.playCapture()
    check(sound.plays == 3, "later inactivity does not queue a cue")
    active = true
    check(sound.plays == 3, "reactivation alone does not play a deferred cue")
    var missingLoads = 0
    let missing = InterfaceSoundEffects(preferences: preferences, isActive: { true }) { missingLoads += 1; return nil }
    missing.preload(); missing.preload()
    check(missingLoads == 1, "missing resource preload still runs once")
    missing.playCapture()
    check(missingLoads == 2, "eligible play can retry a missing cache entry without substitute output")

    try preferences.setReorderingHaptics(true)
    var pulses = 0
    var reorder: SidebarReorderingFeedback? = SidebarReorderingFeedback(preferences: preferences) { pulses += 1 }
    check(pulses == 0, "preference subscription does not invent an initial index")
    reorder?.propose(index: 2)
    check(pulses == 1, "first accepted insertion index emits")
    reorder?.propose(index: 2); reorder?.propose(index: 2)
    check(pulses == 1, "periodic validation of unchanged index does not repeat")
    reorder?.propose(index: 3)
    check(pulses == 2, "changed insertion index emits")
    reorder?.propose(index: -1); reorder?.propose(index: -1)
    check(pulses == 3, "on-item sentinel participates in the same distinct stream")
    try preferences.setReorderingHaptics(false)
    reorder?.propose(index: 7); reorder?.propose(index: 8)
    check(pulses == 3, "disabled feedback consumes new indices silently")
    try preferences.setPlaysSoundEffects(false)
    check(pulses == 3, "unrelated sound preference does not produce haptic feedback")
    try preferences.setReorderingHaptics(true)
    check(pulses == 4, "recovered combineLatest re-emits the current index on enabling")
    reorder?.propose(index: 8)
    check(pulses == 4, "enabling does not reset the index stream")
    try preferences.setPlaysSoundEffects(true)
    check(pulses == 4, "unrelated sound change does not re-emit enabled state")
    var otherPulses = 0
    let other = SidebarReorderingFeedback(preferences: preferences) { otherPulses += 1 }
    other.propose(index: 8)
    check(otherPulses == 1 && pulses == 4, "each outline owns independent index history")
    weak var retired = reorder
    reorder = nil
    check(retired == nil, "outline feedback lifetime is not retained by its subscription")
    retired = nil
    try preferences.setReorderingHaptics(false); try preferences.setReorderingHaptics(true)
    check(pulses == 4 && otherPulses == 2, "retired outline cancels feedback while a live outline still follows its preference")
    withExtendedLifetime([subscription, other]) {}

    for invalid: Any in [Data("not json".utf8), Data("{\"version\":99,\"playsSoundEffects\":true,\"reorderingHaptics\":true}".utf8), "unexpected legacy type"] {
        defaults.set(invalid, forKey: key)
        let preserved = defaults.object(forKey: key) as! NSObject
        let unavailable = InterfaceFeedbackPreferences(defaults: defaults)
        check(unavailable.loadError, "malformed or future preference data is unavailable")
        do { try unavailable.setPlaysSoundEffects(false); preconditionFailure("invalid preference overwritten") } catch { checks += 1 }
        do { try unavailable.setReorderingHaptics(false); preconditionFailure("invalid preference overwritten") } catch { checks += 1 }
        check((defaults.object(forKey: key) as! NSObject).isEqual(preserved), "unreadable preference bytes remain untouched")
        var outputs = 0
        let silent = InterfaceSoundEffects(preferences: unavailable, isActive: { true }) { outputs += 1; return sound }
        let quiet = SidebarReorderingFeedback(preferences: unavailable) { outputs += 1 }
        silent.playCapture(); quiet.propose(index: 1)
        check(outputs == 0, "unreadable preference cannot authorize audio or haptics")
    }
    print("Interface feedback component checks: \(checks) passed")
} }
