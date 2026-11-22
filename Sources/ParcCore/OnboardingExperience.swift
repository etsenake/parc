import Foundation

package enum OnboardingExperience {
    package typealias TransitionDirection = OnboardingTransitionDirection

    package static func readyTitle(cardName: String) -> String {
        let name = cardName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Welcome to Parc" : "Welcome to Parc, \(name)"
    }

    package static let readyDescription =
        "Here’s your Parc Card. Show it off to the world or keep it to yourself.\n\nAnd with that, you’re now ready to experience your upgraded internet."

    package static func shouldPlayConfetti(reduceMotion: Bool) -> Bool { !reduceMotion }

    package static let readyConfettiDelay: TimeInterval = 0.4

    package static func direction(from: OnboardingDraft.Stage, to: OnboardingDraft.Stage) -> TransitionDirection? {
        if from.isWelcome && !to.isWelcome { return nil }
        if !from.isWelcome && to.isWelcome { return .back }
        let order = OnboardingDraft.Stage.setupOrder(
            includingAdBlockers: from.current == .adBlockers || to.current == .adBlockers,
            continuingImport: from == .continuedImport || to == .continuedImport)
        guard let origin = order.firstIndex(of: from.current),
              let destination = order.firstIndex(of: to.current),
              origin != destination else { return nil }
        return destination > origin ? .forward : .back
    }

    package struct CounterPage: Equatable {
        let stage: OnboardingDraft.Stage
        package let importPage: OnboardingDraft.ImportPage?
        let importStarted: Bool
        package init(stage: OnboardingDraft.Stage, importPage: OnboardingDraft.ImportPage?, importStarted: Bool) {
            self.stage = stage
            self.importPage = stage == .continuedImport ? importPage : nil
            self.importStarted = stage == .bookmarks && importStarted
        }
    }

    package enum ImportChange: Equatable {
        case showFavorites, returnToSource, show, showInPlace, hold
    }

    package static func importChange(on stage: OnboardingDraft.Stage, started: Bool, wasStarted: Bool,
                             resting: Bool) -> ImportChange {
        switch stage {
        case .bookmarks where started && !wasStarted: return .showFavorites
        case .bookmarks where started && resting: return .returnToSource
        case .bookmarks where started: return .showInPlace
        case .bookmarks, .continuedImport: return .show
        default: return .hold
        }
    }

    package enum ImportBack: Equatable {
        case importPage, importSource, favorites, previousStage
    }

    package static func importBack(on stage: OnboardingDraft.Stage, holdingImport: Bool,
                           returnsToSource: Bool) -> ImportBack {
        guard holdingImport else { return .previousStage }
        switch stage {
        case .bookmarks: return .importPage
        case .favorites: return .importSource
        case .continuedImport: return returnsToSource ? .favorites : .importPage
        default: return .previousStage
        }
    }

    package enum ImportNext: Equatable {
        case importPage, favorites, nextStage
    }

    package static func importNext(on stage: OnboardingDraft.Stage, holdingImport: Bool, started: Bool,
                           skippingImport: Bool) -> ImportNext {
        guard holdingImport, stage.showsImport else { return .nextStage }
        return stage == .bookmarks && started && !skippingImport ? .favorites : .importPage
    }

    typealias Spring = OnboardingStepMotion.Spring
    package typealias StepMotion = OnboardingStepMotion

    package enum MusicEvent: Equatable {
        case startWelcome, changeStage, resignKey, resignActive, becomeKey, becomeActive
        case close, finish, terminate, replay
    }

    package static func shouldStartMusic(on event: MusicEvent) -> Bool { event == .startWelcome }

    package static func shouldStopMusic(on event: MusicEvent) -> Bool {
        switch event {
        case .close, .finish, .terminate, .replay: return true
        default: return false
        }
    }

    package static func shouldPauseOrMute(on event: MusicEvent) -> Bool { false }

    static let authFeatureOnboardingPerformsHaptics = false

    package static func welcomeShowsContent(stage: OnboardingDraft.Stage, reduceMotion: Bool) -> Bool {
        stage.isWelcome && (reduceMotion || stage != .introAnimation)
    }

    package static func welcomeContinueTarget(from stage: OnboardingDraft.Stage) -> OnboardingDraft.Stage? {
        stage.isWelcome ? OnboardingDraft.Stage.sellCompleted.next : nil
    }

    package enum FocusTarget: Equatable {
        case welcome, spaceName, next, unchanged
    }

    package static func focusTarget(entering stage: OnboardingDraft.Stage, from previous: OnboardingDraft.Stage?) -> FocusTarget {
        if previous == stage { return .unchanged }
        if stage.isWelcome { return previous?.isWelcome == true ? .unchanged : .welcome }
        if stage == .theme { return .spaceName }
        return .next
    }
}
