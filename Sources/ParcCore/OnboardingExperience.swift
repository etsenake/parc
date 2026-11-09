import Foundation

///
/// Addresses and remaining gaps live in docs/onboarding.md.
enum OnboardingExperience {
    typealias TransitionDirection = OnboardingTransitionDirection

    ///
    ///
    ///
    static func readyTitle(cardName: String) -> String {
        let name = cardName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Welcome to Parc" : "Welcome to Parc, \(name)"
    }

    ///
    static let readyDescription =
        "Here’s your Parc Card. Show it off to the world or keep it to yourself.\n\nAnd with that, you’re now ready to experience your upgraded internet."

    ///
    static func shouldPlayConfetti(reduceMotion: Bool) -> Bool { !reduceMotion }

    ///
    static let readyConfettiDelay: TimeInterval = 0.4

    ///
    ///
    /// NewSetupView with no transition, and its per-step animations can't fire
    /// on insertion, so the first setup card appears in place.
    static func direction(from: OnboardingDraft.Stage, to: OnboardingDraft.Stage) -> TransitionDirection? {
        if from.isWelcome && !to.isWelcome { return nil }
        if !from.isWelcome && to.isWelcome { return .back }
        let order = OnboardingDraft.Stage.setupOrder(
            includingAdBlockers: from.current == .adBlockers || to.current == .adBlockers)
        guard let origin = order.firstIndex(of: from.current),
              let destination = order.firstIndex(of: to.current),
              origin != destination else { return nil }
        return destination > origin ? .forward : .back
    }

    typealias Spring = OnboardingStepMotion.Spring
    typealias StepMotion = OnboardingStepMotion

    enum MusicEvent: Equatable {
        case startWelcome, changeStage, resignKey, resignActive, becomeKey, becomeActive
        case close, finish, terminate, replay
    }

    ///
    static func shouldStartMusic(on event: MusicEvent) -> Bool { event == .startWelcome }

    /// Field accesses stop/release the player on owner destruction and replay start.
    static func shouldStopMusic(on event: MusicEvent) -> Bool {
        switch event {
        case .close, .finish, .terminate, .replay: return true
        default: return false
        }
    }

    /// No Unboxing-range `pause`, `stop` on resign, `AVAudioSession`, or
    /// `applicationDidResignActive` observer was recovered.
    static func shouldPauseOrMute(on event: MusicEvent) -> Bool { false }

    /// Whole-image `performFeedbackPattern:performanceTime:` callers do not
    /// include AuthFeature/Unboxing `0x10166`–`0x1016f`. Theme-editor haptics
    ///
    static let authFeatureOnboardingPerformsHaptics = false

    ///
    /// the logo and content (whose onAppear starts their timers) arrive with
    /// sellIntro. Reduce Motion shows the settled headline and arrow at once.
    static func welcomeShowsContent(stage: OnboardingDraft.Stage, reduceMotion: Bool) -> Bool {
        stage.isWelcome && (reduceMotion || stage != .introAnimation)
    }

    /// A press on the visible welcome arrow always leaves the welcome, unlike
    ///
    /// changes still step one phase at a time.
    static func welcomeContinueTarget(from stage: OnboardingDraft.Stage) -> OnboardingDraft.Stage? {
        stage.isWelcome ? OnboardingDraft.Stage.sellCompleted.next : nil
    }

    enum FocusTarget: Equatable {
        case welcome, spaceName, next, unchanged
    }

    static func focusTarget(entering stage: OnboardingDraft.Stage, from previous: OnboardingDraft.Stage?) -> FocusTarget {
        if previous == stage { return .unchanged }
        if stage.isWelcome { return previous?.isWelcome == true ? .unchanged : .welcome }
        if stage == .theme { return .spaceName }
        return .next
    }
}
