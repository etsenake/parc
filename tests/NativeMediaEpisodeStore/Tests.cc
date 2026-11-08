#include <cassert>
#include <memory>
#include <optional>
#include <vector>

#include "native_background_picture_in_picture.h"
#include "native_media_episode_store.h"

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

int main() {
  using K = MediaKind;
  auto qualifies = [](bool toggle, bool controllable, bool active, bool muted,
                      std::optional<std::vector<K>> states) {
    return parc::CanAdmitNewMediaEpisode(toggle, controllable, active, muted,
                                         states, K::AudioOnly, K::AudioVideo);
  };
  assert(!qualifies(false, true, true, false, std::nullopt));
  assert(!qualifies(false, true, true, false, std::vector<K>{}));
  assert(!qualifies(false, true, true, false, std::vector<K>{K::VideoOnly, K::Unknown}));
  assert(qualifies(false, true, true, false, std::vector<K>{K::VideoOnly, K::AudioOnly}));
  assert(qualifies(false, true, true, false, std::vector<K>{K::AudioVideo}));
  assert(!qualifies(false, false, true, false, std::vector<K>{K::AudioOnly}));
  assert(!qualifies(false, true, false, false, std::vector<K>{K::AudioOnly}));
  assert(!qualifies(false, true, true, true, std::vector<K>{K::AudioOnly}));
  assert(qualifies(true, false, false, true, std::nullopt));
  assert(qualifies(true, true, true, false, std::vector<K>{K::AudioVideo}));

  using V = parc::BackgroundPipVisibility;
  using S = parc::BackgroundPipSessionState;
  using C = parc::BackgroundPipCommand;
  using Sig = parc::BackgroundPipSignal;
  auto reduce = [](S state, V shell, bool in_pip, bool eligible,
                   Sig signal = Sig::kReconcile, unsigned retries = 1) {
    return parc::ReduceBackgroundPipSession(state, shell, in_pip, eligible,
                                            signal, retries);
  };

  //
  {
    auto step = reduce(S::kIdle, V::kHidden, false, true);
    assert(step.state == S::kPendingActive && step.command == C::kEnter);
  }
  {
    auto step = reduce(S::kIdle, V::kOccluded, false, true);
    assert(step.state == S::kPendingActive && step.command == C::kEnter);
  }
  {
    auto step = reduce(S::kIdle, V::kVisible, false, true);
    assert(step.state == S::kIdle && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kIdle, V::kHidden, true, true);
    assert(step.state == S::kIdle && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, true, true);
    assert(step.state == S::kActive && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, false, true);
    assert(step.state == S::kPendingActive && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, false, true,
                       Sig::kPictureInPictureChanged);
    assert(step.state == S::kIdle && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kActive, V::kHidden, false, true,
                       Sig::kPictureInPictureChanged);
    assert(step.state == S::kUserClosed && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kUserClosed, V::kHidden, false, true);
    assert(step.state == S::kUserClosed && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kActive, V::kVisible, true, true);
    assert(step.state == S::kIdle && step.command == C::kExit);
  }
  {
    auto step = reduce(S::kUserClosed, V::kVisible, false, true);
    assert(step.state == S::kIdle && step.command == C::kNone);
  }
  // Fast return while pending + Chromium already in PiP must Exit, not orphan.
  {
    auto step = reduce(S::kPendingActive, V::kVisible, true, true);
    assert(step.state == S::kIdle && step.command == C::kExit);
  }
  // Pending must not drop on transient !eligible (races in-flight Enter).
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, false, false);
    assert(step.state == S::kPendingActive && step.command == C::kNone);
  }
  // Silent Enter failure timeout → one retry while eligible, then Idle.
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, false, true,
                       Sig::kEnterTimedOut, 1);
    assert(step.state == S::kPendingActive && step.command == C::kEnter);
  }
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, false, true,
                       Sig::kEnterTimedOut, 0);
    assert(step.state == S::kIdle && step.command == C::kNone);
  }
  {
    auto step = reduce(S::kPendingActive, V::kOccluded, false, false,
                       Sig::kEnterTimedOut, 1);
    assert(step.state == S::kIdle && step.command == C::kNone);
  }
  // Active dismiss only on explicit PiP-false, not reconcile churn.
  {
    auto step = reduce(S::kActive, V::kHidden, false, true);
    assert(step.state == S::kActive && step.command == C::kNone);
  }
  // Fast return while Enter still in flight → CancelPending (not Idle orphan).
  {
    auto step = reduce(S::kPendingActive, V::kVisible, false, true);
    assert(step.state == S::kCancelPending && step.command == C::kNone);
  }
  // Late success after cancel → Exit.
  {
    auto step = reduce(S::kCancelPending, V::kVisible, true, true);
    assert(step.state == S::kIdle && step.command == C::kExit);
  }
  // Late failure/timeout after cancel while still foreground → Idle, no Exit.
  {
    auto step = reduce(S::kCancelPending, V::kVisible, false, true,
                       Sig::kEnterTimedOut);
    assert(step.state == S::kIdle && step.command == C::kNone);
  }
  // Away again before settle ends → timeout must resume Enter, not stuck Idle.
  {
    auto step = reduce(S::kCancelPending, V::kOccluded, false, true,
                       Sig::kEnterTimedOut);
    assert(step.state == S::kPendingActive && step.command == C::kEnter);
  }
  {
    auto step = reduce(S::kCancelPending, V::kHidden, false, true,
                       Sig::kPictureInPictureChanged);
    assert(step.state == S::kPendingActive && step.command == C::kEnter);
  }

  // Compatibility wrappers.
  auto enter = [](V visibility, bool in_pip, bool allowed, bool controllable,
                  bool playing, bool muted, bool has_video,
                  bool dismissed = false) {
    return parc::ShouldEnterBackgroundVideoPictureInPicture(
        visibility, in_pip, allowed, controllable, playing, muted, has_video,
        dismissed);
  };
  assert(enter(V::kHidden, false, true, true, true, false, true));
  assert(enter(V::kOccluded, false, true, true, true, false, true));
  assert(!enter(V::kVisible, false, true, true, true, false, true));
  assert(!enter(V::kHidden, true, true, true, true, false, true));
  assert(!enter(V::kOccluded, true, true, true, true, false, true));
  assert(!enter(V::kHidden, false, false, true, true, false, true));
  assert(!enter(V::kHidden, false, true, false, true, false, true));
  assert(!enter(V::kHidden, false, true, true, false, false, true));
  assert(!enter(V::kHidden, false, true, true, true, true, true));
  assert(!enter(V::kHidden, false, true, true, true, false, false));
  assert(!enter(V::kHidden, false, true, true, true, false, true, true));
  assert(!enter(V::kOccluded, false, true, true, true, false, true, true));
  assert(parc::ShouldRememberBackgroundVideoPictureInPictureDismissal(
      V::kHidden));
  assert(parc::ShouldRememberBackgroundVideoPictureInPictureDismissal(
      V::kOccluded));
  assert(!parc::ShouldRememberBackgroundVideoPictureInPictureDismissal(
      V::kVisible));
  assert(parc::HasBackgroundPipVideoTrack(
      std::optional{std::vector{K::AudioVideo}}, K::AudioVideo, K::VideoOnly));
  assert(parc::HasBackgroundPipVideoTrack(
      std::optional{std::vector{K::VideoOnly}}, K::AudioVideo, K::VideoOnly));
  assert(!parc::HasBackgroundPipVideoTrack(
      std::optional{std::vector{K::AudioOnly}}, K::AudioVideo, K::VideoOnly));
  assert(!parc::HasBackgroundPipVideoTrack(std::optional<std::vector<K>>{},
                                           K::AudioVideo, K::VideoOnly));
  assert(parc::ShouldExitBackgroundVideoPictureInPicture(V::kVisible, true, true));
  assert(!parc::ShouldExitBackgroundVideoPictureInPicture(V::kHidden, true, true));
  assert(!parc::ShouldExitBackgroundVideoPictureInPicture(V::kVisible, false, true));
  assert(!parc::ShouldExitBackgroundVideoPictureInPicture(V::kVisible, true, false));

  // Production producer fence and re-admission state transition: the lease is
  // single use and a newer dismissal/eviction must win over captured work.
  parc::NativeMediaSuppressionFence fence;
  auto stale = fence.Capture();
  fence.Suppress();
  assert(!stale.Consume(fence, true));
  auto invalid_source = fence.Capture();
  assert(!invalid_source.Consume(fence, false));
  assert(!invalid_source.Consume(fence, true));
  auto live = fence.Capture();
  assert(live.Consume(fence, true));
  assert(!live.Consume(fence, true));
  int calls = 0;
  auto accepted = [&] { ++calls; return true; };
  for (bool was_active : {false, true}) {
    bool active = was_active, dismissed = true;
    assert(parc::AdmitAfterPresentationRemoval(active, dismissed, accepted));
    assert(!active && !dismissed);  // Real Snapshot sets active on acceptance.
  }
  bool active = true, dismissed = true;
  assert(!parc::AdmitAfterPresentationRemoval(active, dismissed, [] { return false; }));
  assert(active && dismissed);
  active = false; dismissed = true;
  assert(!parc::AdmitAfterPresentationRemoval(active, dismissed, [] { return false; }));
  assert(!active && dismissed);
  active = false; dismissed = false;
  assert(parc::AdmitAfterPresentationRemoval(active, dismissed, accepted));
  active = true; dismissed = false;
  assert(!parc::AdmitAfterPresentationRemoval(active, dismissed, accepted));
  assert(calls == 3 && active && !dismissed);
  auto casting = [] { return true; };
  auto idle = [] { return false; };
  assert(parc::MediaEpisodeHeld(true, false, idle));
  assert(parc::MediaEpisodeHeld(false, true, casting));
  assert(!parc::MediaEpisodeHeld(false, true, idle));
  assert(!parc::MediaEpisodeHeld(false, false, casting));
  active = true; dismissed = false;
  assert(parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, casting));
  assert(active && !dismissed);
  assert(!parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, idle));
  assert(!active && !dismissed);
  active = true; dismissed = true;
  assert(!parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, casting));
  assert(!active && !dismissed);
  // Casting() creates the cast watcher, so it's asked only for a shown row.
  auto unasked = [] { assert(false); return true; };
  assert(!parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, unasked));
  dismissed = true;
  assert(!parc::KeepMediaEpisodeAcrossPageChange(active, dismissed, unasked));
  assert(!active && !dismissed);
  Store store;
  std::vector<std::shared_ptr<Source>> regular;
  for (int i = 0; i < 6; ++i) regular.push_back(std::make_shared<Source>());
  for (int i = 0; i < 5; ++i) {
    assert(!store.Admit(regular[i], {}, false).get());
    assert(store.Sequence(regular[i].get()) == static_cast<unsigned>(i));
  }
  assert(!store.Admit(regular[1], {}, false).get());  // Duplicate is not a new admission.
  assert(store.Admit(regular[5], {}, false).get() == regular[0].get());
  assert(store.Sequence(regular[5].get()) > store.Sequence(regular[4].get()));

  auto private_a = std::make_shared<Profile>();
  auto private_b = std::make_shared<Profile>();
  std::vector<std::shared_ptr<Source>> a;
  for (int i = 0; i < 6; ++i) a.push_back(std::make_shared<Source>());
  auto b = std::make_shared<Source>();
  for (int i = 0; i < 5; ++i) assert(!store.Admit(a[i], private_a, true).get());
  assert(!store.Admit(b, private_b, true).get());
  assert(store.Admit(a[5], private_a, true).get() == a[0].get());
  assert(store.Sequence(b.get()) == 0);
  assert(store.Sequence(regular[1].get()) == 1);  // Private admission cannot evict regular.

  // Prune a newly ineligible entry before admitting a new source: a still
  // eligible oldest entry must not be evicted by a stale slot.
  Store reconcile;
  for (int i = 0; i < 5; ++i) assert(!reconcile.Admit(regular[i], {}, false).get());
  auto withdrawn = reconcile.RemoveIf([&](Source* source) { return source == regular[4].get(); });
  assert(withdrawn.size() == 1 && withdrawn[0].get() == regular[4].get());
  assert(!reconcile.Admit(regular[5], {}, false).get());
  assert(reconcile.Sequence(regular[0].get()) == 0);

  store.Remove(a[2].get());
  auto replacement = std::make_shared<Source>();
  assert(!store.Admit(replacement, private_a, true).get());
  auto expired = std::make_shared<Source>();
  Store cleanup;
  assert(!cleanup.Admit(expired, private_a, true).get());
  expired.reset();
  assert(!cleanup.Admit(b, private_b, true).get());
  private_b.reset();
  assert(cleanup.Sequence(b.get()) == UINT64_MAX);  // A dead OTR identity cannot fall back to regular.
}
