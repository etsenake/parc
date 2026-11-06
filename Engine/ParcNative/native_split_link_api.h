// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_SPLIT_LINK_API_H_
#define PARC_NATIVE_NATIVE_SPLIT_LINK_API_H_
class BrowserWindowInterface;
namespace content { class WebContents; }
namespace parc {
enum class NativeSplitDecision { kUnmanaged, kOrdinary, kAdmitted };
// A Parc-owned split must never fall through to Chromium's two-pane model.
constexpr NativeSplitDecision ClassifyNativeSplit(bool owned, bool current_lease) {
  return !owned ? NativeSplitDecision::kUnmanaged :
      current_lease ? NativeSplitDecision::kAdmitted : NativeSplitDecision::kOrdinary;
}
// True only for a source page owned by Parc's native browser window.
bool HasNativeSplitOwner(BrowserWindowInterface& browser, content::WebContents& source);
}
#endif  // PARC_NATIVE_NATIVE_SPLIT_LINK_API_H_
