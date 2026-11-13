// Copyright 2026 Parc contributors.

#ifndef PARC_NATIVE_NATIVE_SPLIT_LINK_API_H_
#define PARC_NATIVE_NATIVE_SPLIT_LINK_API_H_
class BrowserWindowInterface;
enum class WindowOpenDisposition;
namespace content { class WebContents; }
namespace parc {
enum class NativeSplitDecision { kUnmanaged, kOrdinary, kAdmitted };

constexpr NativeSplitDecision ClassifyNativeSplit(bool owned, bool current_lease) {
  return !owned ? NativeSplitDecision::kUnmanaged :
      current_lease ? NativeSplitDecision::kAdmitted : NativeSplitDecision::kOrdinary;
}

bool HasNativeSplitOwner(BrowserWindowInterface& browser, content::WebContents& source);
bool PrepareNativeCreatedSplit(BrowserWindowInterface& browser,
                               content::WebContents* source,
                               content::WebContents* child,
                               WindowOpenDisposition& disposition);
}
#endif
