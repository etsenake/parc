import Testing
@testable import ParcCore

struct OnboardingExperienceTests {
    typealias Motion = OnboardingExperience.StepMotion
    typealias Stage = OnboardingDraft.Stage
    typealias MusicEvent = OnboardingExperience.MusicEvent

    @Test func theFinishedStepTitleInterpolatesTheMembershipCardName() {
        #expect(OnboardingExperience.readyTitle(cardName: "Ada Lovelace") == "Welcome to Parc, Ada Lovelace")
    }

    @Test func anEmptyCardNameDoesNotInventAComma() {
        #expect(OnboardingExperience.readyTitle(cardName: "  ") == "Welcome to Parc")
    }

    @Test func theFinishedStepDescriptionIsTheRecoveredLastStepCopy() {
        #expect(OnboardingExperience.readyDescription.contains("Parc Card"))
        #expect(OnboardingExperience.readyDescription.contains("upgraded internet"))
    }

    @Test func confettiIsTheInverseOfReduceMotionAndWaitsFourTenthsOfASecond() {
        #expect(OnboardingExperience.shouldPlayConfetti(reduceMotion: false))
        #expect(!OnboardingExperience.shouldPlayConfetti(reduceMotion: true))
        #expect(OnboardingExperience.readyConfettiDelay == 0.4)
    }

    @Test(arguments: [(Stage.defaultBrowser, Stage.ready), (.theme, .adBlockers), (.adBlockers, .defaultBrowser),
                      (.theme, .windowFrame), (.windowFrame, .adBlockers)])
    func aLaterSetupStageMovesForward(stages: (Stage, Stage)) {
        #expect(OnboardingExperience.direction(from: stages.0, to: stages.1) == .forward)
    }

    @Test(arguments: [(Stage.ready, Stage.defaultBrowser), (.adBlockers, .theme), (.windowFrame, .theme),
                      (.defaultBrowser, .windowFrame), (.bookmarks, .introAnimation)])
    func anEarlierSetupStageMovesBack(stages: (Stage, Stage)) {
        #expect(OnboardingExperience.direction(from: stages.0, to: stages.1) == .back)
    }

    @Test(arguments: [Stage.sellCompleted, .introAnimation])
    func theFirstSetupCardAppearsInPlaceAfterWelcome(welcome: Stage) {
        #expect(OnboardingExperience.direction(from: welcome, to: .bookmarks) == nil)
    }

    @Test func stayingOnTheSameStageDoesNotMoveTheCard() {
        #expect(OnboardingExperience.direction(from: .theme, to: .theme) == nil)
    }

    @Test func forwardTextComesFromPlus400AndLeavesToMinus400AndBackMirrorsIt() {
        #expect(Motion.offset == 400)
        #expect(Motion.offsets(.forward) == (400, -400))
        #expect(Motion.offsets(.back) == (-400, 400))
    }

    @Test func titleAndMessageSpringsUseTheirResponseAndDamping() {
        #expect(Motion.titleSpring == .init(response: 0.4, dampingFraction: 0.8))
        #expect(Motion.messageSpring == .init(response: 0.5, dampingFraction: 0.8))
    }

    @Test func swiftUIResponseAndDampingConvertToUnitMassStiffnessAndDamping() {
        #expect(abs(Motion.titleSpring.stiffness - 246.74) < 0.01)
        #expect(abs(Motion.titleSpring.damping - 25.133) < 0.001)
        #expect(abs(Motion.messageSpring.stiffness - 157.91) < 0.01)
        #expect(abs(Motion.messageSpring.damping - 20.106) < 0.001)
    }

    @Test func contentCrossfadesOverHalfASecondAndNextsEnabledStateFadesOverTwelveHundredths() {
        #expect(Motion.contentFadeDuration == 0.5)
        #expect(Motion.enabledFadeDuration == 0.12)
    }

    @Test func reduceMotionDropsTheSlidesButKeepsTheFades() {
        #expect(Motion.slidesText(reduceMotion: false))
        #expect(!Motion.slidesText(reduceMotion: true))
        #expect(Motion.fadesContent(reduceMotion: true))
        #expect(Motion.fadesEnabledState(reduceMotion: true))
    }

    @Test func musicStartsOnlyWithWelcome() {
        #expect(OnboardingExperience.shouldStartMusic(on: .startWelcome))
        #expect(!OnboardingExperience.shouldStartMusic(on: .changeStage))
        #expect(!OnboardingExperience.shouldStartMusic(on: .resignKey))
    }

    @Test(arguments: [MusicEvent.changeStage, .resignKey, .resignActive, .becomeKey, .becomeActive])
    func focusAndStageChangesDoNotMuteOrStopTheCue(event: MusicEvent) {
        #expect(!OnboardingExperience.shouldPauseOrMute(on: event))
        #expect(!OnboardingExperience.shouldStopMusic(on: event))
    }

    @Test(arguments: [MusicEvent.close, .finish, .terminate, .replay])
    func ownerTeardownStopsMusic(event: MusicEvent) {
        #expect(OnboardingExperience.shouldStopMusic(on: event))
    }

    @Test func authFeatureOnboardingHasNoRecoveredHapticProducer() {
        #expect(!OnboardingExperience.authFeatureOnboardingPerformsHaptics)
    }

    @Test func theWelcomesFirstPhaseBuildsNoLogoHeadlineOrArrow() {
        #expect(!OnboardingExperience.welcomeShowsContent(stage: .introAnimation, reduceMotion: false))
        #expect(OnboardingExperience.welcomeShowsContent(stage: .sellIntro, reduceMotion: false))
        #expect(OnboardingExperience.welcomeShowsContent(stage: .sellCompleted, reduceMotion: false))
    }

    @Test func reduceMotionShowsTheSettledHeadlineAndArrowFromTheFirstPhaseNeverInSetup() {
        #expect(OnboardingExperience.welcomeShowsContent(stage: .introAnimation, reduceMotion: true))
        #expect(!OnboardingExperience.welcomeShowsContent(stage: .bookmarks, reduceMotion: true))
    }

    @Test(arguments: [Stage.introAnimation, .sellIntro, .sellCompleted])
    func onePressOnTheWelcomeArrowLeavesForTheFirstSetupStep(stage: Stage) {
        #expect(OnboardingExperience.welcomeContinueTarget(from: stage) == .bookmarks)
    }

    @Test(arguments: [Stage.bookmarks, .theme, .ready])
    func aLateWelcomePressAfterSetupBeganDoesNothing(stage: Stage) {
        #expect(OnboardingExperience.welcomeContinueTarget(from: stage) == nil)
    }

    @Test func timedWelcomePhasesStillStepOneAtATime() {
        #expect(Stage.introAnimation.next == .sellIntro)
        #expect(Stage.sellIntro.next == .sellCompleted)
    }

    @Test(arguments: [(Stage.theme, Stage?.some(.favorites), OnboardingExperience.FocusTarget.spaceName),
                      (.theme, .theme, .unchanged), (.ready, .defaultBrowser, .next),
                      (.windowFrame, .theme, .next), (.introAnimation, nil, .welcome),
                      (.sellIntro, .introAnimation, .unchanged), (.introAnimation, .introAnimation, .unchanged),
                      (.introAnimation, .sellCompleted, .unchanged)])
    func movingThroughSetupSelectsTheNewCardFocus(example: (Stage, Stage?, OnboardingExperience.FocusTarget)) {
        #expect(OnboardingExperience.focusTarget(entering: example.0, from: example.1) == example.2)
    }
}
