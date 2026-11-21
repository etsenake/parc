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

@implementation MediaEpisodeStoreTests

- (void)testEpisodeQualificationAndTransitions {
  @autoreleasepool {
  using K = MediaKind;
  auto qualifies = [](bool toggle, bool controllable, bool active, bool muted,
                      std::optional<std::vector<K>> states) {
    return parc::CanAdmitNewMediaEpisode(toggle, controllable, active, muted,
                                         states, K::AudioOnly, K::AudioVideo);
  };
  PARC_CHECK(!qualifies(false, true, true, false, std::nullopt));
  PARC_CHECK(!qualifies(false, true, true, false, std::vector<K>{}));
  PARC_CHECK(!qualifies(false, true, true, false, std::vector<K>{K::VideoOnly, K::Unknown}));
  PARC_CHECK(qualifies(false, true, true, false, std::vector<K>{K::VideoOnly, K::AudioOnly}));
  PARC_CHECK(qualifies(false, true, true, false, std::vector<K>{K::AudioVideo}));
  PARC_CHECK(!qualifies(false, false, true, false, std::vector<K>{K::AudioOnly}));
  PARC_CHECK(!qualifies(false, true, false, false, std::vector<K>{K::AudioOnly}));
  PARC_CHECK(!qualifies(false, true, true, true, std::vector<K>{K::AudioOnly}));
  PARC_CHECK(qualifies(true, false, false, true, std::nullopt));
  PARC_CHECK(qualifies(true, true, true, false, std::vector<K>{K::AudioVideo}));

  using V = parc::BackgroundPipVisibility;
  using S = parc::BackgroundPipSessionState;
  using C = parc::BackgroundPipCommand;
  using Sig = parc::BackgroundPipSignal;
  auto reduce = [](S state, V shell, bool in_pip, bool eligible,
                   Sig signal = Sig::kReconcile, unsigned retries = 1) {
    return parc::ReduceBackgroundPipSession(state, shell, in_pip, eligible,
                                            signal, retries);
  };

  {
    auto step = reduce(S::kIdle, V::kHidden, false, true);
    PARC_CHECK(step.state == S::kPendingActive && step.command == C::kEnter);
  }
  {
    auto step = reduce(S::kIdle, V::kOccluded, false, true);
    PARC_CHECK(step.state == S::kPendingActive && step.command == C::kEnter);
  }
  {
    auto step = reduce(S::kIdle, V::kVisible, false, true);
    PARC_CHECK(step.state == S::kIdle && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kIdle, V::kHidden, true, true);
    PARC_CHECK(step.state == S::kIdle && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, true, true);
    PARC_CHECK(step.state == S::kActive && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, false, true);
    PARC_CHECK(step.state == S::kPendingActive && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, false, true,
                       Sig::kPictureInPictureChanged);
    PARC_CHECK(step.state == S::kIdle && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kActive, V::kHidden, false, true,
                       Sig::kPictureInPictureChanged);
    PARC_CHECK(step.state == S::kUserClosed && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kUserClosed, V::kHidden, false, true);
    PARC_CHECK(step.state == S::kUserClosed && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kActive, V::kVisible, true, true);
    PARC_CHECK(step.state == S::kIdle && step.command == C::kExit);
  }
  {
    auto step = reduce(S::kUserClosed, V::kVisible, false, true);
    PARC_CHECK(step.state == S::kIdle && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kPendingActive, V::kVisible, true, true);
    PARC_CHECK(step.state == S::kIdle && step.command == C::kExit);
  }
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, false, false);
    PARC_CHECK(step.state == S::kPendingActive && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, false, true,
                       Sig::kEnterTimedOut, 1);
    PARC_CHECK(step.state == S::kPendingActive && step.command == C::kEnter);
  }
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, false, true,
                       Sig::kEnterTimedOut, 0);
    PARC_CHECK(step.state == S::kIdle && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, false, false,
                       Sig::kEnterTimedOut, 1);
    PARC_CHECK(step.state == S::kIdle && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kActive, V::kHidden, false, true);
    PARC_CHECK(step.state == S::kActive && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kPendingActive, V::kVisible, false, true);
    PARC_CHECK(step.state == S::kCancelPending && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kCancelPending, V::kVisible, true, true);
    PARC_CHECK(step.state == S::kIdle && step.command == C::kExit);
  }
  {
    auto step = reduce(S::kCancelPending, V::kVisible, false, true,
                       Sig::kEnterTimedOut);
    PARC_CHECK(step.state == S::kIdle && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kCancelPending, V::kOccluded, false, true,
                       Sig::kEnterTimedOut);
    PARC_CHECK(step.state == S::kPendingActive && step.command == C::kEnter);
  }
  {
    auto step = reduce(S::kCancelPending, V::kHidden, false, true,
                       Sig::kPictureInPictureChanged);
    PARC_CHECK(step.state == S::kPendingActive && step.command == C::kEnter);
  }

  auto enter = [](V visibility, bool in_pip, bool allowed, bool controllable,
                  bool playing, bool muted, bool has_video,
                  bool dismissed = false) {
    return parc::ShouldEnterBackgroundVideoPictureInPicture(
        visibility, in_pip, allowed, controllable, playing, muted, has_video,
        dismissed);
  };
  PARC_CHECK(enter(V::kHidden, false, true, true, true, false, true));
  PARC_CHECK(enter(V::kOccluded, false, true, true, true, false, true));
  PARC_CHECK(!enter(V::kVisible, false, true, true, true, false, true));
  PARC_CHECK(!enter(V::kHidden, true, true, true, true, false, true));
  PARC_CHECK(!enter(V::kOccluded, true, true, true, true, false, true));
  PARC_CHECK(!enter(V::kHidden, false, false, true, true, false, true));
  PARC_CHECK(!enter(V::kHidden, false, true, false, true, false, true));
  PARC_CHECK(!enter(V::kHidden, false, true, true, false, false, true));
  PARC_CHECK(!enter(V::kHidden, false, true, true, true, true, true));
  PARC_CHECK(!enter(V::kHidden, false, true, true, true, false, false));
  PARC_CHECK(!enter(V::kHidden, false, true, true, true, false, true, true));
  PARC_CHECK(!enter(V::kOccluded, false, true, true, true, false, true, true));
  PARC_CHECK(parc::ShouldRememberBackgroundVideoPictureInPictureDismissal(
      V::kHidden));
  PARC_CHECK(parc::ShouldRememberBackgroundVideoPictureInPictureDismissal(
      V::kOccluded));
  PARC_CHECK(!parc::ShouldRememberBackgroundVideoPictureInPictureDismissal(
      V::kVisible));
  PARC_CHECK(parc::HasBackgroundPipVideoTrack(
      std::optional{std::vector{K::AudioVideo}}, K::AudioVideo, K::VideoOnly));
  PARC_CHECK(parc::HasBackgroundPipVideoTrack(
      std::optional{std::vector{K::VideoOnly}}, K::AudioVideo, K::VideoOnly));
  PARC_CHECK(!parc::HasBackgroundPipVideoTrack(
      std::optional{std::vector{K::AudioOnly}}, K::AudioVideo, K::VideoOnly));
  PARC_CHECK(!parc::HasBackgroundPipVideoTrack(std::optional<std::vector<K>>{},
                                           K::AudioVideo, K::VideoOnly));
  PARC_CHECK(parc::ShouldExitBackgroundVideoPictureInPicture(V::kVisible, true, true));
  PARC_CHECK(!parc::ShouldExitBackgroundVideoPictureInPicture(V::kHidden, true, true));
  PARC_CHECK(!parc::ShouldExitBackgroundVideoPictureInPicture(V::kVisible, false, true));
  PARC_CHECK(!parc::ShouldExitBackgroundVideoPictureInPicture(V::kVisible, true, false));

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
  int calls = 0;
  auto accepted = [&] { ++calls; return true; };
  for (bool was_active : {false, true}) {
    bool active = was_active, dismissed = true;
    PARC_CHECK(parc::AdmitAfterPresentationRemoval(active, dismissed, accepted));
    PARC_CHECK(!active && !dismissed);
  }
  bool active = true, dismissed = true;
  PARC_CHECK(!parc::AdmitAfterPresentationRemoval(active, dismissed, [] { return false; }));
  PARC_CHECK(active && dismissed);
  active = false; dismissed = true;
  PARC_CHECK(!parc::AdmitAfterPresentationRemoval(active, dismissed, [] { return false; }));
  PARC_CHECK(!active && dismissed);
  active = false; dismissed = false;
  PARC_CHECK(parc::AdmitAfterPresentationRemoval(active, dismissed, accepted));
  active = true; dismissed = false;
  PARC_CHECK(!parc::AdmitAfterPresentationRemoval(active, dismissed, accepted));
  PARC_CHECK(calls == 3 && active && !dismissed);
  auto casting = [] { return true; };
  auto idle = [] { return false; };
  PARC_CHECK(parc::MediaEpisodeHeld(true, false, idle));
  PARC_CHECK(parc::MediaEpisodeHeld(false, true, casting));
  PARC_CHECK(!parc::MediaEpisodeHeld(false, true, idle));
  PARC_CHECK(!parc::MediaEpisodeHeld(false, false, casting));
  active = true; dismissed = false;
  PARC_CHECK(parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, casting));
  PARC_CHECK(active && !dismissed);
  PARC_CHECK(!parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, idle));
  PARC_CHECK(!active && !dismissed);
  active = true; dismissed = true;
  PARC_CHECK(!parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, casting));
  PARC_CHECK(!active && !dismissed);
  auto unasked = [] { PARC_CHECK(false); return true; };
  PARC_CHECK(!parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, unasked));
  dismissed = true;
  PARC_CHECK(!parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, unasked));
  PARC_CHECK(!active && !dismissed);
  Store store;
  std::vector<std::shared_ptr<Source>> regular;
  for (int i = 0; i < 6; ++i) regular.push_back(std::make_shared<Source>());
  for (int i = 0; i < 5; ++i) {
    PARC_CHECK(!store.Admit(regular[i], {}, false).get());
    PARC_CHECK(store.Sequence(regular[i].get()) == static_cast<unsigned>(i));
  }
  PARC_CHECK(!store.Admit(regular[1], {}, false).get());
  PARC_CHECK(store.Admit(regular[5], {}, false).get() == regular[0].get());
  PARC_CHECK(store.Sequence(regular[5].get()) > store.Sequence(regular[4].get()));

  auto private_a = std::make_shared<Profile>();
  auto private_b = std::make_shared<Profile>();
  std::vector<std::shared_ptr<Source>> a;
  for (int i = 0; i < 6; ++i) a.push_back(std::make_shared<Source>());
  auto b = std::make_shared<Source>();
  for (int i = 0; i < 5; ++i) PARC_CHECK(!store.Admit(a[i], private_a, true).get());
  PARC_CHECK(!store.Admit(b, private_b, true).get());
  PARC_CHECK(store.Admit(a[5], private_a, true).get() == a[0].get());
  PARC_CHECK(store.Sequence(b.get()) == 0);
  PARC_CHECK(store.Sequence(regular[1].get()) == 1);

  Store reconcile;
  for (int i = 0; i < 5; ++i) PARC_CHECK(!reconcile.Admit(regular[i], {}, false).get());
  auto withdrawn = reconcile.RemoveIf([&](Source* source) { return source == regular[4].get(); });
  PARC_CHECK(withdrawn.size() == 1 && withdrawn[0].get() == regular[4].get());
  PARC_CHECK(!reconcile.Admit(regular[5], {}, false).get());
  PARC_CHECK(reconcile.Sequence(regular[0].get()) == 0);

  store.Remove(a[2].get());
  auto replacement = std::make_shared<Source>();
  PARC_CHECK(!store.Admit(replacement, private_a, true).get());
  auto expired = std::make_shared<Source>();
  Store cleanup;
  PARC_CHECK(!cleanup.Admit(expired, private_a, true).get());
  expired.reset();
  PARC_CHECK(!cleanup.Admit(b, private_b, true).get());
  private_b.reset();
  PARC_CHECK(cleanup.Sequence(b.get()) == UINT64_MAX);

  struct Ask { int page; int press; };
  auto page = [](int id) { return [id](const Ask& ask) { return ask.page == id; }; };
  parc::NativeRouteWait<Ask> wait;
  PARC_CHECK(!wait.Arrived(page(1)));
  PARC_CHECK(!wait.Begin({1, 1}));
  const auto first = wait.ticket();
  PARC_CHECK(!wait.Arrived(page(2)));
  auto opened = wait.Arrived(page(1));
  PARC_CHECK(opened && opened->press == 1 && !wait.Arrived(page(1)));
  PARC_CHECK(!wait.Expire(first));
  PARC_CHECK(!wait.Begin({1, 2}));
  const auto second = wait.ticket();
  auto replaced = wait.Begin({2, 3});
  PARC_CHECK(replaced && replaced->press == 2);
  PARC_CHECK(!wait.Expire(second));
  auto expired_ask = wait.Expire(wait.ticket());
  PARC_CHECK(expired_ask && expired_ask->press == 3 && !wait.Arrived(page(2)));
  PARC_CHECK(!wait.Begin({1, 4}));
  auto cancelled = wait.Cancel();
  PARC_CHECK(cancelled && cancelled->press == 4 && !wait.Cancel());
  }
}

@end
