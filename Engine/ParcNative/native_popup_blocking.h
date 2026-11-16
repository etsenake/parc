// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_POPUP_BLOCKING_H_
#define PARC_NATIVE_NATIVE_POPUP_BLOCKING_H_

#include <cstdint>
#include <optional>
#include <vector>

#include "url/gurl.h"

namespace content {
class WebContents;
struct OpenURLParams;
}

namespace parc {

struct NativeBlockedItem {
  enum class Kind { kPopup, kRedirect };
  Kind kind;
  int32_t id;
  GURL url;
};

struct NativeBlockedContent {
  NativeBlockedContent();
  NativeBlockedContent(const NativeBlockedContent&);
  NativeBlockedContent& operator=(const NativeBlockedContent&);
  ~NativeBlockedContent();

  uint64_t revision = 0;
  std::vector<NativeBlockedItem> items;
  GURL site;
  bool allowed = false;
  bool can_allow = false;
};

void InstallNativePopupBlocking(void (*changed)(content::WebContents&));
bool BlockNativeLinkPopup(content::WebContents* source,
                          const content::OpenURLParams& params);
void NativeNavigationBlocked(content::WebContents& contents);

std::optional<NativeBlockedContent> GetNativeBlockedContent(
    content::WebContents& contents);
bool OpenNativeBlockedItem(content::WebContents& contents,
                           NativeBlockedItem::Kind kind,
                           int32_t id,
                           uint64_t revision);
bool OpenAllNativeBlockedPopups(content::WebContents& contents,
                                uint64_t revision);
bool AllowNativeBlockedPopups(content::WebContents& contents,
                              uint64_t revision);

}

#endif
