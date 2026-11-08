// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_PUBLIC_COMMON_PARC_PAGE_NETWORK_ACTIVITY_COUNT_H_
#define THIRD_PARTY_BLINK_PUBLIC_COMMON_PARC_PAGE_NETWORK_ACTIVITY_COUNT_H_

// The renderer's count of an ordinary page's main-document requests in
// flight, for the browser's page-loading indicator (LoadingHold in
// Engine/ParcNative/native_page_shell_notify.h). No Blink or content types.

#include <cstdint>
#include <optional>
#include <unordered_map>

namespace parc::page_network {

// A request open this long stops counting (long-polls): the browser never
// holds the indicator longer than this past the main document's end.
inline constexpr int64_t kLongLivedMs = 4000;

class InFlightRequests {
 public:
  void Reset() { started_.clear(); }
  // A counted request's first send; redirects are not new requests.
  void Start(uint64_t id, int64_t now_ms) { started_.emplace(id, now_ms); }
  void Finish(uint64_t id) { started_.erase(id); }
  // Drops requests open kLongLivedMs or longer. Returns when the last
  // remaining one stops counting, or nullopt when none is in flight.
  std::optional<int64_t> BusyUntil(int64_t now_ms) {
    std::optional<int64_t> until;
    for (auto it = started_.begin(); it != started_.end();) {
      const int64_t expiry = it->second + kLongLivedMs;
      if (expiry <= now_ms) {
        it = started_.erase(it);
        continue;
      }
      if (!until || expiry > *until) {
        until = expiry;
      }
      ++it;
    }
    return until;
  }

 private:
  std::unordered_map<uint64_t, int64_t> started_;
};

}  // namespace parc::page_network

#endif  // THIRD_PARTY_BLINK_PUBLIC_COMMON_PARC_PAGE_NETWORK_ACTIVITY_COUNT_H_
