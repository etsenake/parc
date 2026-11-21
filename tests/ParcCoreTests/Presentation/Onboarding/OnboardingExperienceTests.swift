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

    @Test func setupTransitionDirectionIsBackOrForwardFromStepOrder() {
        let direction = OnboardingExperience.direction
        #expect(direction(.defaultBrowser, .ready) == .forward)
        #expect(direction(.ready, .defaultBrowser) == .back)
        #expect(direction(.theme, .adBlockers) == .forward)
        #expect(direction(.adBlockers, .defaultBrowser) == .forward)
        #expect(direction(.adBlockers, .theme) == .back)
        #expect(direction(.theme, .theme) == nil)
        #expect(direction(.theme, .windowFrame) == .forward)
        #expect(direction(.windowFrame, .theme) == .back)
        #expect(direction(.windowFrame, .adBlockers) == .forward)
        #expect(direction(.defaultBrowser, .windowFrame) == .back)
    }

    @Test func theFirstSetupCardAppearsInPlaceAfterWelcomeAndReturningToWelcomeStaysBack() {
        let direction = OnboardingExperience.direction
        #expect(direction(.sellCompleted, .bookmarks) == nil)
        #expect(direction(.introAnimation, .bookmarks) == nil)
        #expect(direction(.bookmarks, .introAnimation) == .back)
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

    @Test func focusReturnsToSpaceNameNextOrWelcomeRatherThanRerenderingTheSameControl() {
        #expect(OnboardingExperience.focusTarget(entering: .theme, from: .favorites) == .spaceName)
        #expect(OnboardingExperience.focusTarget(entering: .theme, from: .theme) == .unchanged)
        #expect(OnboardingExperience.focusTarget(entering: .ready, from: .defaultBrowser) == .next)
        #expect(OnboardingExperience.focusTarget(entering: .windowFrame, from: .theme) == .next)
        #expect(OnboardingExperience.focusTarget(entering: .introAnimation, from: nil) == .welcome)
        #expect(OnboardingExperience.focusTarget(entering: .sellIntro, from: .introAnimation) == .unchanged)
        #expect(OnboardingExperience.focusTarget(entering: .introAnimation, from: .introAnimation) == .unchanged)
        #expect(OnboardingExperience.focusTarget(entering: .introAnimation, from: .sellCompleted) == .unchanged)
    }
}
