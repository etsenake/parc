// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_ROUTE_WAIT_H_
#define PARC_NATIVE_NATIVE_ROUTE_WAIT_H_

#include <cstdint>
#include <optional>
#include <utility>

namespace parc {

// A route list asked for while its page has no player that can play to a
// target, as while a new player replaces the old one, opens for that page's
// next player instead. The wait ends when it opens, when its time is up, or
// when another list is asked for. Each call returns the request it ended, for
// the caller to open or dismiss once the wait has changed.
template <typename Request>
class NativeRouteWait {
 public:
  std::optional<Request> Begin(Request request) {
    ++ticket_;
    return std::exchange(request_, std::move(request));
  }
  std::uint64_t ticket() const { return ticket_; }
  template <typename Matches>
  std::optional<Request> Arrived(Matches matches) {
    if (!request_ || !matches(*request_)) return std::nullopt;
    return std::exchange(request_, std::nullopt);
  }
  std::optional<Request> Expire(std::uint64_t ticket) {
    if (ticket != ticket_) return std::nullopt;
    return std::exchange(request_, std::nullopt);
  }
  std::optional<Request> Cancel() { return std::exchange(request_, std::nullopt); }

 private:
  std::optional<Request> request_;
  std::uint64_t ticket_ = 0;
};

}  // namespace parc

#endif  // PARC_NATIVE_NATIVE_ROUTE_WAIT_H_
