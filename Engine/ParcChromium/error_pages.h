// Copyright 2026 Parc contributors.
#ifndef PARC_ERROR_PAGES_H_
#define PARC_ERROR_PAGES_H_

#include <string>
#include <string_view>

namespace parc {

std::string_view NetErrorPageTemplate();
std::string_view InterstitialStyle();
std::string_view InterstitialScript();
std::string_view WebAppErrorStyle();

inline void AddErrorPageSkin(std::string& html,
                             std::string_view style,
                             std::string_view script) {
  const auto head = html.find("</head>");
  if (head == std::string::npos) {
    return;
  }
  html.insert(head, style);
  const auto body = html.rfind("</body>");
  if (body != std::string::npos && !script.empty()) {
    html.insert(body, script);
  }
}

}  // namespace parc

#endif  // PARC_ERROR_PAGES_H_
