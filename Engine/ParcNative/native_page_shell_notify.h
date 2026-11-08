// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PAGE_SHELL_NOTIFY_H_
#define PARC_NATIVE_NATIVE_PAGE_SHELL_NOTIFY_H_

#include <cstdint>
#include <optional>
#include <string>

namespace parc {

// Tab metadata nativePageDidChange causes the facade to reread. Capture bits
// travel on that same Notify path (didChangeCaptureState). Crash and favicon
// keep their own observer paths.
struct NativePageShellNotifyState {
  std::string url;
  std::u16string title;
  bool loading = false;
  bool can_go_back = false;
  bool can_go_forward = false;
  // MediaStreamCaptureIndicator producer bits reread for capture fan-out.
  bool capture_camera = false;
  bool capture_microphone = false;
  bool capture_tab = false;
  bool capture_window = false;
  bool capture_display = false;
  bool capture_mirrored = false;
  bool capture_shared = false;
  // NativeReader mode/revision reread after reader changed_ → Notify.
  uint8_t reader_mode = 0;
  uint64_t reader_revision = 0;
  // The colour the pane top bar shows (TopBarPageColor), so a background
  // change under a winning theme-color does not notify.
  std::optional<uint32_t> top_bar_color;
  // The top-band sampler's delivered colour (SkColor) and the host of the
  // document it came from; a delivery may carry no colour.
  bool top_band_delivered = false;
  std::optional<uint32_t> top_band_color;
  std::string top_band_host;
  bool published = false;
};

// SkColor (ARGB) values. The shell reads theme-color through
// developerModeTint, which is always opaque, then an opaque CSS root
// background (pageBackgroundColor).
inline std::optional<uint32_t> TopBarPageColor(
    std::optional<uint32_t> theme_color,
    std::optional<uint32_t> background_color) {
  if (theme_color) {
    return theme_color;
  }
  if (background_color && (*background_color >> 24) == 0xFFu) {
    return background_color;
  }
  return std::nullopt;
}

// True when the Swift shell payload reread by nativePageDidChange differs from
// the last published notify: URL/title/loading/back/forward, capture producer
// bits, reader mode/revision, the top bar's page colour and the top-band
// sample.
inline bool ShellNotifyPayloadChanged(
    const NativePageShellNotifyState& last,
    const NativePageShellNotifyState& current) {
  return last.url != current.url || last.title != current.title ||
         last.loading != current.loading ||
         last.can_go_back != current.can_go_back ||
         last.can_go_forward != current.can_go_forward ||
         last.capture_camera != current.capture_camera ||
         last.capture_microphone != current.capture_microphone ||
         last.capture_tab != current.capture_tab ||
         last.capture_window != current.capture_window ||
         last.capture_display != current.capture_display ||
         last.capture_mirrored != current.capture_mirrored ||
         last.capture_shared != current.capture_shared ||
         last.reader_mode != current.reader_mode ||
         last.reader_revision != current.reader_revision ||
         last.top_bar_color != current.top_bar_color ||
         last.top_band_delivered != current.top_band_delivered ||
         last.top_band_color != current.top_band_color ||
         last.top_band_host != current.top_band_host;
}

//
// URL/title events on the frame, separate from other frame activity. CEF
// OnAddressChange is already main-frame only, including same-document URL
// changes. Primary cross-document navigations always notify. Subframe/iframe
// and primary same-document skip only a proven no-op of the current
// payload-free Notify contract (identical URL, title, loading, back/forward,
// with favicon observation already current). Iframe history can still change
// CanGoBack/CanGoForward, so those must still notify.
inline bool ShouldNotifyFinishedNavigation(
    bool primary_main_frame,
    bool same_document,
    bool favicon_already_observing,
    const NativePageShellNotifyState& last,
    const NativePageShellNotifyState& current) {
  if (primary_main_frame && !same_document) {
    return true;
  }
  if (!favicon_already_observing || !last.published) {
    return true;
  }
  return ShellNotifyPayloadChanged(last, current);
}

// Observer paths that can fire without changing the published shell snapshot:
// DidStart/StopLoading (iframe load noise), TitleWasSet, DidChangeThemeColor,
// OnBackgroundColorChanged, DidChangeVisibleSecurityState (SPA security
// churn), reader changed_, and CaptureChanged (indicator callbacks with
// unchanged producer bits). Skip only an identical published snapshot; a real
// title, loading, capture, reader mode/revision or page colour change must
// still notify.
inline bool ShouldNotifyShellPayloadChange(
    const NativePageShellNotifyState& last,
    const NativePageShellNotifyState& current) {
  if (!last.published) {
    return true;
  }
  return ShellNotifyPayloadChanged(last, current);
}

//
// end of loading), the shell keeps showing it loading while the page fills
// itself in: until the main frame's own resources (fetch/XHR included) have
// been quiet for Blink's network-quiet window and the page has had its first
// contentful paint, never longer than Chromium waits for new content to
// render. Same-document navigations are never held.
class LoadingHold {
 public:
  static constexpr int64_t kQuietMs = 500;   // Blink NetworkQuietTimeout.
  static constexpr int64_t kCapMs = 4000;    // blink::kNewContentRenderingDelay.

  bool holding() const { return holding_; }
  void Committed(int64_t now) {
    armed_ = true;
    holding_ = false;
    last_activity_ = now;
  }
  void Activity(int64_t now) {
    if (armed_ || holding_) last_activity_ = now;
  }
  void Cancel() { armed_ = holding_ = false; }
  // `main_loading` is ShouldShowLoadingUI. Returns what the shell shows.
  bool Update(bool main_loading, bool painted, int64_t now) {
    if (main_loading) {
      holding_ = false;
      return true;
    }
    if (armed_) {
      armed_ = false;
      holding_ = true;
      finished_ = now;
    }
    if (holding_ && (now - finished_ >= kCapMs ||
                     (painted && now - last_activity_ >= kQuietMs))) {
      holding_ = false;
    }
    return holding_;
  }
  // Milliseconds until Update can next end the hold.
  int64_t Remaining(bool painted, int64_t now) const {
    int64_t due = finished_ + kCapMs;
    if (painted && last_activity_ + kQuietMs < due) due = last_activity_ + kQuietMs;
    return due > now ? due - now : 0;
  }

 private:
  bool armed_ = false;
  bool holding_ = false;
  int64_t finished_ = 0;
  int64_t last_activity_ = 0;
};

inline bool ShouldNotifyLoadingChange(
    const NativePageShellNotifyState& last,
    const NativePageShellNotifyState& current) {
  return ShouldNotifyShellPayloadChange(last, current);
}

}  // namespace parc

#endif  // PARC_NATIVE_NATIVE_PAGE_SHELL_NOTIFY_H_
