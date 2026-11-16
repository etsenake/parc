// Copyright 2026 Parc contributors.
#ifndef PARC_ERROR_PAGES_H_
#define PARC_ERROR_PAGES_H_

#include <string_view>

namespace parc {

std::string_view NetErrorPageTemplate();
std::string_view InterstitialStyle();
std::string_view InterstitialScript();

}  // namespace parc

#endif  // PARC_ERROR_PAGES_H_
