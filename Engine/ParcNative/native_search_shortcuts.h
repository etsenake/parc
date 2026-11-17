// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_SEARCH_SHORTCUTS_H_
#define PARC_NATIVE_NATIVE_SEARCH_SHORTCUTS_H_

#include <optional>

#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "url/gurl.h"

namespace parc {

inline bool ShortcutNavigationCounts(bool primary_main_frame,
                                     bool committed,
                                     std::optional<int> response_code,
                                     const GURL& destination,
                                     const GURL& visible,
                                     const GURL& redirect_origin) {
  if (!primary_main_frame || !committed || !response_code)
    return false;
  const int code = *response_code;
  if (code / 100 != 2 && code != 401 && code != 407)
    return false;
  using net::registry_controlled_domains::SameDomainOrHost;
  constexpr auto kRegistries =
      net::registry_controlled_domains::EXCLUDE_PRIVATE_REGISTRIES;
  return !redirect_origin.is_valid() ||
         SameDomainOrHost(destination, visible, kRegistries) ||
         !SameDomainOrHost(visible, redirect_origin, kRegistries);
}

}

#endif
