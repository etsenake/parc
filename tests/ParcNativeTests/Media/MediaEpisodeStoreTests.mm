#import "ParcNativeTest.h"
#include <memory>
#include <optional>
#include <vector>

#include "native_background_picture_in_picture.h"
#include "native_media_episode_store.h"
#include "native_route_wait.h"

struct Source {};
struct Profile {};
template <typename T> struct Weak {
  std::weak_ptr<T> value;
  Weak() = default;
  Weak(const std::shared_ptr<T>& object) : value(object) {}
  T* get() const { auto object = value.lock(); return object.get(); }
};
using Store = parc::NativeMediaEpisodeStore<Weak<Source>, Weak<Profile>>;

enum class MediaKind { Unknown, AudioOnly, AudioVideo, VideoOnly };

@interface MediaEpisodeStoreTests : ParcNativeTestCase
@end

using K = MediaKind;
using V = parc::BackgroundPipVisibility;
using S = parc::BackgroundPipSessionState;
using C = parc::BackgroundPipCommand;
using Sig = parc::BackgroundPipSignal;

static bool Qualifies(bool toggle, bool controllable, bool active, bool muted, std::optional<std::vector<K>> states) {
  return parc::CanAdmitNewMediaEpisode(toggle, controllable, active, muted, states, K::AudioOnly, K::AudioVideo);
}

static bool Is(parc::BackgroundPipStep step, S state, C command) {
  return step.state == state && step.command == command;
}

static parc::BackgroundPipStep Reduce(S state, V shell, bool in_pip, bool eligible, Sig signal = Sig::kReconcile,
                                      unsigned retries = 1) {
  return parc::ReduceBackgroundPipSession(state, shell, in_pip, eligible, signal, retries);
}

static bool Enter(V visibility, bool in_pip, bool allowed, bool controllable, bool playing, bool muted,
                  bool has_video, bool dismissed = false) {
  return parc::ShouldEnterBackgroundVideoPictureInPicture(visibility, in_pip, allowed, controllable, playing, muted,
                                                          has_video, dismissed);
}

struct Ask {
  int page;
  int press;
};

static auto Page(int id) {
  return [id](const Ask& ask) { return ask.page == id; };
}

@implementation MediaEpisodeStoreTests {
  std::vector<std::shared_ptr<Source>> _regular;
}

- (void)setUp {
  [super setUp];
  for (int i = 0; i < 6; ++i) _regular.push_back(std::make_shared<Source>());
}

- (void)testOnlyControllableAudibleSessionsWithAudioQualify {
  PARC_CHECK(!Qualifies(false, true, true, false, std::nullopt));
  PARC_CHECK(!Qualifies(false, true, true, false, std::vector<K>{}));
  PARC_CHECK(!Qualifies(false, true, true, false, std::vector<K>{K::VideoOnly, K::Unknown}));
  PARC_CHECK(Qualifies(false, true, true, false, std::vector<K>{K::VideoOnly, K::AudioOnly}));
  PARC_CHECK(Qualifies(false, true, true, false, std::vector<K>{K::AudioVideo}));
  PARC_CHECK(!Qualifies(false, false, true, false, std::vector<K>{K::AudioOnly}));
  PARC_CHECK(!Qualifies(false, true, false, false, std::vector<K>{K::AudioOnly}));
  PARC_CHECK(!Qualifies(false, true, true, true, std::vector<K>{K::AudioOnly}));
}

- (void)testTheToggleAdmitsAnySession {
  PARC_CHECK(Qualifies(true, false, false, true, std::nullopt));
  PARC_CHECK(Qualifies(true, true, true, false, std::vector<K>{K::AudioVideo}));
}

- (void)testAnIdleSessionEntersOnlyWhenThePageIsOutOfSight {
  PARC_CHECK(Is(Reduce(S::kIdle, V::kHidden, false, true), S::kPendingActive, C::kEnter));
  PARC_CHECK(Is(Reduce(S::kIdle, V::kOccluded, false, true), S::kPendingActive, C::kEnter));
  PARC_CHECK(Is(Reduce(S::kIdle, V::kVisible, false, true), S::kIdle, C::kNone));
  PARC_CHECK(Is(Reduce(S::kIdle, V::kHidden, true, true), S::kIdle, C::kNone));
}

- (void)testAPendingEntryBecomesActiveOrSettlesBack {
  PARC_CHECK(Is(Reduce(S::kPendingActive, V::kOccluded, true, true), S::kActive, C::kNone));
  PARC_CHECK(Is(Reduce(S::kPendingActive, V::kOccluded, false, true), S::kPendingActive, C::kNone));
  PARC_CHECK(Is(Reduce(S::kPendingActive, V::kOccluded, false, true, Sig::kPictureInPictureChanged), S::kIdle,
                C::kNone));
  PARC_CHECK(Is(Reduce(S::kPendingActive, V::kOccluded, false, false), S::kPendingActive, C::kNone));
  PARC_CHECK(Is(Reduce(S::kActive, V::kHidden, false, true), S::kActive, C::kNone));
}

- (void)testTheUserClosingPictureInPictureHoldsUntilThePageIsVisible {
  PARC_CHECK(Is(Reduce(S::kActive, V::kHidden, false, true, Sig::kPictureInPictureChanged), S::kUserClosed, C::kNone));
  PARC_CHECK(Is(Reduce(S::kUserClosed, V::kHidden, false, true), S::kUserClosed, C::kNone));
  PARC_CHECK(Is(Reduce(S::kUserClosed, V::kVisible, false, true), S::kIdle, C::kNone));
}

- (void)testAVisiblePageExitsPictureInPicture {
  PARC_CHECK(Is(Reduce(S::kActive, V::kVisible, true, true), S::kIdle, C::kExit));
  PARC_CHECK(Is(Reduce(S::kPendingActive, V::kVisible, true, true), S::kIdle, C::kExit));
}

- (void)testATimedOutEntryRetriesWhileRetriesAndEligibilityLast {
  PARC_CHECK(Is(Reduce(S::kPendingActive, V::kOccluded, false, true, Sig::kEnterTimedOut, 1), S::kPendingActive,
                C::kEnter));
  PARC_CHECK(Is(Reduce(S::kPendingActive, V::kOccluded, false, true, Sig::kEnterTimedOut, 0), S::kIdle, C::kNone));
  PARC_CHECK(Is(Reduce(S::kPendingActive, V::kOccluded, false, false, Sig::kEnterTimedOut, 1), S::kIdle, C::kNone));
}

- (void)testAPendingEntryCancelledByVisibilityFinishesCleanly {
  PARC_CHECK(Is(Reduce(S::kPendingActive, V::kVisible, false, true), S::kCancelPending, C::kNone));
  PARC_CHECK(Is(Reduce(S::kCancelPending, V::kVisible, true, true), S::kIdle, C::kExit));
  PARC_CHECK(Is(Reduce(S::kCancelPending, V::kVisible, false, true, Sig::kEnterTimedOut), S::kIdle, C::kNone));
  PARC_CHECK(Is(Reduce(S::kCancelPending, V::kOccluded, false, true, Sig::kEnterTimedOut), S::kPendingActive,
                C::kEnter));
  PARC_CHECK(Is(Reduce(S::kCancelPending, V::kHidden, false, true, Sig::kPictureInPictureChanged), S::kPendingActive,
                C::kEnter));
}

- (void)testBackgroundVideoEntersOnlyWhenEveryConditionHolds {
  PARC_CHECK(Enter(V::kHidden, false, true, true, true, false, true));
  PARC_CHECK(Enter(V::kOccluded, false, true, true, true, false, true));
  PARC_CHECK(!Enter(V::kVisible, false, true, true, true, false, true));
  PARC_CHECK(!Enter(V::kHidden, true, true, true, true, false, true));
  PARC_CHECK(!Enter(V::kOccluded, true, true, true, true, false, true));
  PARC_CHECK(!Enter(V::kHidden, false, false, true, true, false, true));
  PARC_CHECK(!Enter(V::kHidden, false, true, false, true, false, true));
  PARC_CHECK(!Enter(V::kHidden, false, true, true, false, false, true));
  PARC_CHECK(!Enter(V::kHidden, false, true, true, true, true, true));
  PARC_CHECK(!Enter(V::kHidden, false, true, true, true, false, false));
  PARC_CHECK(!Enter(V::kHidden, false, true, true, true, false, true, true));
  PARC_CHECK(!Enter(V::kOccluded, false, true, true, true, false, true, true));
}

- (void)testADismissalIsRememberedOnlyWhileThePageIsOutOfSight {
  PARC_CHECK(parc::ShouldRememberBackgroundVideoPictureInPictureDismissal(V::kHidden));
  PARC_CHECK(parc::ShouldRememberBackgroundVideoPictureInPictureDismissal(V::kOccluded));
  PARC_CHECK(!parc::ShouldRememberBackgroundVideoPictureInPictureDismissal(V::kVisible));
}

- (void)testOnlyTracksWithVideoCount {
  PARC_CHECK(parc::HasBackgroundPipVideoTrack(std::optional{std::vector{K::AudioVideo}}, K::AudioVideo, K::VideoOnly));
  PARC_CHECK(parc::HasBackgroundPipVideoTrack(std::optional{std::vector{K::VideoOnly}}, K::AudioVideo, K::VideoOnly));
  PARC_CHECK(!parc::HasBackgroundPipVideoTrack(std::optional{std::vector{K::AudioOnly}}, K::AudioVideo, K::VideoOnly));
  PARC_CHECK(!parc::HasBackgroundPipVideoTrack(std::optional<std::vector<K>>{}, K::AudioVideo, K::VideoOnly));
}

- (void)testBackgroundVideoExitsOnlyWhenVisibleInItsOwnPictureInPicture {
  PARC_CHECK(parc::ShouldExitBackgroundVideoPictureInPicture(V::kVisible, true, true));
  PARC_CHECK(!parc::ShouldExitBackgroundVideoPictureInPicture(V::kHidden, true, true));
  PARC_CHECK(!parc::ShouldExitBackgroundVideoPictureInPicture(V::kVisible, false, true));
  PARC_CHECK(!parc::ShouldExitBackgroundVideoPictureInPicture(V::kVisible, true, false));
}

- (void)testTheSuppressionFenceAcceptsOneLiveCaptureFromAValidSource {
  parc::NativeMediaSuppressionFence fence;
  auto stale = fence.Capture();
  fence.Suppress();
  PARC_CHECK(!stale.Consume(fence, true));
  auto invalid_source = fence.Capture();
  PARC_CHECK(!invalid_source.Consume(fence, false));
  PARC_CHECK(!invalid_source.Consume(fence, true));
  auto live = fence.Capture();
  PARC_CHECK(live.Consume(fence, true));
  PARC_CHECK(!live.Consume(fence, true));
}

- (void)checkRemovingActive:(bool)active dismissed:(bool)dismissed admission:(bool)admission
             expectsAttempt:(bool)attempt expectsReadmission:(bool)readmitted {
  const bool wasActive = active;
  const bool wasDismissed = dismissed;
  int calls = 0;
  const bool result = parc::AdmitAfterPresentationRemoval(active, dismissed, [&] {
    ++calls;
    return admission;
  });
  PARC_CHECK(result == readmitted);
  PARC_CHECK(calls == int(attempt));
  PARC_CHECK(active == (readmitted ? false : wasActive));
  PARC_CHECK(dismissed == (readmitted ? false : wasDismissed));
}

- (void)testAdmittingAnInactiveDismissedEpisodeClearsDismissal {
  [self checkRemovingActive:false dismissed:true admission:true
             expectsAttempt:true expectsReadmission:true];
}

- (void)testAdmittingAnActiveDismissedEpisodeClearsPresentation {
  [self checkRemovingActive:true dismissed:true admission:true
             expectsAttempt:true expectsReadmission:true];
}

- (void)testRefusingAnActiveDismissedEpisodePreservesPresentation {
  [self checkRemovingActive:true dismissed:true admission:false
             expectsAttempt:true expectsReadmission:false];
}

- (void)testRefusingAnInactiveDismissedEpisodePreservesDismissal {
  [self checkRemovingActive:false dismissed:true admission:false
             expectsAttempt:true expectsReadmission:false];
}

- (void)testAnInactiveUndismissedEpisodeCanBeReadmitted {
  [self checkRemovingActive:false dismissed:false admission:true
             expectsAttempt:true expectsReadmission:true];
}

- (void)testAnActiveUndismissedEpisodeSkipsReadmission {
  [self checkRemovingActive:true dismissed:false admission:true
             expectsAttempt:false expectsReadmission:false];
}

- (void)testAnEpisodeIsHeldWhileActiveOrCasting {
  auto casting = [] { return true; };
  auto idle = [] { return false; };
  PARC_CHECK(parc::MediaEpisodeHeld(true, false, idle));
  PARC_CHECK(parc::MediaEpisodeHeld(false, true, casting));
  PARC_CHECK(!parc::MediaEpisodeHeld(false, true, idle));
  PARC_CHECK(!parc::MediaEpisodeHeld(false, false, casting));
}

- (void)testOnlyACastingUndismissedEpisodeSurvivesAPageChange {
  auto casting = [] { return true; };
  auto idle = [] { return false; };
  bool active = true, dismissed = false;
  PARC_CHECK(parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, casting));
  PARC_CHECK(active && !dismissed);
  PARC_CHECK(!parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, idle));
  PARC_CHECK(!active && !dismissed);
  active = true;
  dismissed = true;
  PARC_CHECK(!parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, casting));
  PARC_CHECK(!active && !dismissed);
}

- (void)testAnInactiveEpisodeNeverAsksAboutCasting {
  bool unaskedCalled = false;
  auto unasked = [&] {
    unaskedCalled = true;
    return true;
  };
  bool active = false, dismissed = false;
  PARC_CHECK(!parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, unasked));
  dismissed = true;
  PARC_CHECK(!parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, unasked));
  PARC_CHECK(!active && !dismissed);
  PARC_CHECK(!unaskedCalled);
}

- (void)testTheStoreKeepsFiveEpisodesAndEvictsTheOldest {
  Store store;
  for (int i = 0; i < 5; ++i) {
    PARC_CHECK(!store.Admit(_regular[i], {}, false).get());
    PARC_CHECK(store.Sequence(_regular[i].get()) == static_cast<unsigned>(i));
  }
  PARC_CHECK(!store.Admit(_regular[1], {}, false).get());
  PARC_CHECK(store.Admit(_regular[5], {}, false).get() == _regular[0].get());
  PARC_CHECK(store.Sequence(_regular[5].get()) > store.Sequence(_regular[4].get()));
}

- (void)testEachPrivateProfileHasItsOwnEpisodes {
  Store store;
  for (int i = 0; i < 5; ++i) store.Admit(_regular[i], {}, false);
  auto private_a = std::make_shared<Profile>();
  auto private_b = std::make_shared<Profile>();
  std::vector<std::shared_ptr<Source>> a;
  for (int i = 0; i < 6; ++i) a.push_back(std::make_shared<Source>());
  auto b = std::make_shared<Source>();
  for (int i = 0; i < 5; ++i) PARC_CHECK(!store.Admit(a[i], private_a, true).get());
  PARC_CHECK(!store.Admit(b, private_b, true).get());
  PARC_CHECK(store.Admit(a[5], private_a, true).get() == a[0].get());
  PARC_CHECK(store.Sequence(b.get()) == 0);
  PARC_CHECK(store.Sequence(_regular[1].get()) == 1);
  store.Remove(a[2].get());
  PARC_CHECK(!store.Admit(std::make_shared<Source>(), private_a, true).get());
}

- (void)testWithdrawingAnEpisodeFreesItsPlace {
  Store store;
  for (int i = 0; i < 5; ++i) PARC_CHECK(!store.Admit(_regular[i], {}, false).get());
  auto withdrawn = store.RemoveIf([&](Source* source) { return source == _regular[4].get(); });
  PARC_CHECK(withdrawn.size() == 1 && withdrawn[0].get() == _regular[4].get());
  PARC_CHECK(!store.Admit(_regular[5], {}, false).get());
  PARC_CHECK(store.Sequence(_regular[0].get()) == 0);
}

- (void)testEpisodesOfGoneSourcesAndProfilesAreForgotten {
  auto private_a = std::make_shared<Profile>();
  auto private_b = std::make_shared<Profile>();
  auto b = std::make_shared<Source>();
  auto expired = std::make_shared<Source>();
  Store cleanup;
  PARC_CHECK(!cleanup.Admit(expired, private_a, true).get());
  expired.reset();
  PARC_CHECK(!cleanup.Admit(b, private_b, true).get());
  private_b.reset();
  PARC_CHECK(cleanup.Sequence(b.get()) == UINT64_MAX);
}

- (void)testARouteWaitDeliversItsAskOnceToTheRightPage {
  parc::NativeRouteWait<Ask> wait;
  PARC_CHECK(!wait.Arrived(Page(1)));
  PARC_CHECK(!wait.Begin({1, 1}));
  const auto first = wait.ticket();
  PARC_CHECK(!wait.Arrived(Page(2)));
  auto opened = wait.Arrived(Page(1));
  PARC_CHECK(opened && opened->press == 1 && !wait.Arrived(Page(1)));
  PARC_CHECK(!wait.Expire(first));
}

- (void)testANewAskReplacesTheWaitingOneAndOnlyTheCurrentTicketExpires {
  parc::NativeRouteWait<Ask> wait;
  PARC_CHECK(!wait.Begin({1, 2}));
  const auto second = wait.ticket();
  auto replaced = wait.Begin({2, 3});
  PARC_CHECK(replaced && replaced->press == 2);
  PARC_CHECK(!wait.Expire(second));
  auto expired_ask = wait.Expire(wait.ticket());
  PARC_CHECK(expired_ask && expired_ask->press == 3 && !wait.Arrived(Page(2)));
}

- (void)testCancellingReturnsTheWaitingAskOnce {
  parc::NativeRouteWait<Ask> wait;
  PARC_CHECK(!wait.Begin({1, 4}));
  auto cancelled = wait.Cancel();
  PARC_CHECK(cancelled && cancelled->press == 4 && !wait.Cancel());
}

@end
