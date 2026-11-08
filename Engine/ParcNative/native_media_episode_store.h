// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_MEDIA_EPISODE_STORE_H_
#define PARC_NATIVE_NATIVE_MEDIA_EPISODE_STORE_H_

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <memory>
#include <utility>
#include <optional>
#include <vector>

namespace parc {

// Only for a new episode. Existing episodes retain their separate eligibility
// and dismissal lifecycle. Toggle support is a legacy compatibility path, not
// evidence that a device is recording.
template <typename State>
bool CanAdmitNewMediaEpisode(bool toggle_supported, bool controllable,
                             bool active, bool muted,
                             const std::optional<std::vector<State>>& states,
                             State audio_only, State audio_video) {
  if (toggle_supported) return true;
  if (!controllable || !active || muted || !states) return false;
  return std::ranges::any_of(*states, [=](State state) {
    return state == audio_only || state == audio_video;
  });
}

// A captured producer may be consumed only once and cannot cross a later
// dismissal or eviction. Shared identity avoids counter wraparound.
class NativeMediaSuppressionFence {
 public:
  class Lease {
   public:
    bool Consume(const NativeMediaSuppressionFence& fence, bool source_valid) {
      if (consumed_) return false;
      consumed_ = true;
      return source_valid && revision_ == fence.revision_;
    }
   private:
    friend class NativeMediaSuppressionFence;
    explicit Lease(std::shared_ptr<const bool> revision) : revision_(std::move(revision)) {}
    std::shared_ptr<const bool> revision_;
    bool consumed_ = false;
  };
  Lease Capture() const { return Lease(revision_); }
  void Suppress() { revision_ = std::make_shared<const bool>(false); }
 private:
  std::shared_ptr<const bool> revision_ = std::make_shared<const bool>(false);
};

// Called only after the exact lease and live eligibility have been checked.
// Snapshot applies the ordinary admission policy and creates the identity.
template <typename Admit>
bool AdmitAfterPresentationRemoval(bool& active, bool& dismissed, Admit admit) {
  if (active && !dismissed) return false;  // Preserve registered identity/order.
  const bool was_active = active, was_dismissed = dismissed;
  active = false; dismissed = false;
  if (admit()) return true;
  active = was_active; dismissed = was_dismissed;
  return false;
}

// An episode's row outlives its session while the cast it shows lives, so it
// keeps Casting to <device> and Stop casting after a site drops its session
// for its receiver. A cast never admits a new episode.
template <typename Casting>
bool MediaEpisodeHeld(bool session_eligible, bool admitted, Casting casting) {
  return session_eligible || (admitted && casting());
}

// A cast carries on from the back/forward cache and its route stays with the
// tab, so a page change keeps the row showing it, with Stop casting, until
// the cast ends. Any other episode, or a dismissed one, ends with its page.
template <typename Casting>
bool KeepMediaEpisodeAcrossPageChange(bool& active, bool& dismissed, Casting casting) {
  if (active && !dismissed && casting()) return true;
  active = false; dismissed = false;
  return false;
}

// Source and Profile are weak handles with get(). Regular sources share one
// pool; each live off-the-record Profile has its own pool. The returned weak
// source is the oldest evicted entry, if any. No callback runs while the store
// is being changed.
template <typename Source, typename Profile>
class NativeMediaEpisodeStore {
 public:
  using SourcePointer = decltype(Source().get());
  using ProfilePointer = decltype(Profile().get());

  Source Admit(Source source, Profile profile, bool off_the_record) {
    Prune();
    if (!source.get() || (off_the_record && !profile.get())) return {};
    for (const auto& entry : entries_) {
      if (entry.source.get() == source.get()) return {};
    }
    std::size_t count = 0;
    std::uint64_t latest = 0;
    auto oldest = entries_.end();
    for (auto it = entries_.begin(); it != entries_.end(); ++it) {
      if (!SameDomain(*it, profile.get(), off_the_record)) continue;
      if (oldest == entries_.end()) oldest = it;
      latest = it->sequence;
      ++count;
    }
    if (count && latest == std::numeric_limits<std::uint64_t>::max()) {
      latest = 0;
      for (auto& entry : entries_) {
        if (SameDomain(entry, profile.get(), off_the_record)) entry.sequence = latest++;
      }
      --latest;
    }
    Source evicted;
    if (count >= kCapacity) {
      evicted = oldest->source;
      entries_.erase(oldest);
    }
    entries_.push_back({source, profile, off_the_record, count ? latest + 1 : 0});
    return evicted;
  }

  void Remove(SourcePointer source) {
    std::erase_if(entries_, [source](const Entry& entry) {
      return !entry.source.get() ||
          (entry.off_the_record && !entry.profile.get()) ||
          entry.source.get() == source;
    });
  }

  // Remove invalid sources before admission, returning weak handles so the
  // caller can notify them after the store mutation has finished.
  template <typename Predicate>
  std::vector<Source> RemoveIf(Predicate predicate) {
    Prune();
    std::vector<Source> removed;
    std::erase_if(entries_, [&](const Entry& entry) {
      if (!predicate(entry.source.get())) return false;
      removed.push_back(entry.source);
      return true;
    });
    return removed;
  }

  std::uint64_t Sequence(SourcePointer source) {
    Prune();
    auto found = std::find_if(entries_.begin(), entries_.end(),
        [source](const Entry& entry) { return entry.source.get() == source; });
    return found == entries_.end() ? std::numeric_limits<std::uint64_t>::max()
                                  : found->sequence;
  }

 private:
  struct Entry {
    Source source;
    Profile profile;
    bool off_the_record;
    std::uint64_t sequence;
  };
  static constexpr std::size_t kCapacity = 5;

  static bool SameDomain(const Entry& entry, ProfilePointer profile,
                         bool off_the_record) {
    return entry.off_the_record == off_the_record &&
        (!off_the_record || entry.profile.get() == profile);
  }
  void Prune() { Remove(nullptr); }
  std::vector<Entry> entries_;
};

}  // namespace parc
#endif  // PARC_NATIVE_NATIVE_MEDIA_EPISODE_STORE_H_
