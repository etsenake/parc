#include "native_page_shell_notify.h"
#include "page_network_activity_count.h"

#include <cassert>
#include <iostream>

int main() {
  using parc::NativePageShellNotifyState;
  using parc::ShellNotifyPayloadChanged;
  using parc::ShouldNotifyFinishedNavigation;
  using parc::ShouldNotifyLoadingChange;
  using parc::ShouldNotifyShellPayloadChange;
  using parc::TopBarPageColor;

  NativePageShellNotifyState unpublished;
  NativePageShellNotifyState published;
  published.url = "https://example.com/";
  published.title = u"Example";
  published.loading = false;
  published.can_go_back = true;
  published.can_go_forward = false;
  published.published = true;
  NativePageShellNotifyState same = published;
  same.published = false;

  assert(ShouldNotifyFinishedNavigation(false, false, true, unpublished, published));
  assert(ShouldNotifyFinishedNavigation(false, true, true, unpublished, published));
  assert(!ShouldNotifyFinishedNavigation(false, false, true, published, same));
  assert(!ShouldNotifyFinishedNavigation(false, true, true, published, same));
  assert(ShouldNotifyFinishedNavigation(false, true, false, published, same));
  assert(ShouldNotifyFinishedNavigation(true, false, true, published, same));
  assert(ShouldNotifyFinishedNavigation(true, true, true, unpublished, same));
  assert(ShouldNotifyFinishedNavigation(true, true, false, published, same));
  assert(!ShouldNotifyFinishedNavigation(true, true, true, published, same));

  NativePageShellNotifyState changed = same;
  changed.url = "https://example.com/#hash";
  assert(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  changed = same;
  changed.title = u"Renamed";
  assert(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  changed = same;
  changed.loading = true;
  assert(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  changed = same;
  changed.can_go_back = false;
  assert(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  assert(ShouldNotifyFinishedNavigation(false, true, true, published, changed));
  changed = same;
  changed.can_go_forward = true;
  assert(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  assert(ShouldNotifyFinishedNavigation(false, false, true, published, changed));

  assert(!ShellNotifyPayloadChanged(published, same));
  assert(ShellNotifyPayloadChanged(published, changed));

  // Unpublished last always notifies loading start/stop.
  assert(ShouldNotifyLoadingChange(unpublished, same));
  assert(ShouldNotifyLoadingChange(unpublished, published));

  // Iframe load noise: identical shell snapshot must not notify.
  assert(!ShouldNotifyLoadingChange(published, same));

  // Primary loading bit flip must still notify.
  NativePageShellNotifyState loading = same;
  loading.loading = true;
  assert(ShouldNotifyLoadingChange(published, loading));
  NativePageShellNotifyState stopped = loading;
  stopped.loading = false;
  NativePageShellNotifyState published_loading = loading;
  published_loading.published = true;
  assert(ShouldNotifyLoadingChange(published_loading, stopped));

  // Other shell fields changing during a loading callback still notify.
  NativePageShellNotifyState history = same;
  history.can_go_back = false;
  assert(ShouldNotifyLoadingChange(published, history));
  history = same;
  history.can_go_forward = true;
  assert(ShouldNotifyLoadingChange(published, history));
  history = same;
  history.url = "https://example.com/next";
  assert(ShouldNotifyLoadingChange(published, history));
  history = same;
  history.title = u"Next";
  assert(ShouldNotifyLoadingChange(published, history));

  // Already-loading page with another start (iframe) and unchanged payload.
  assert(!ShouldNotifyLoadingChange(published_loading, loading));

  // TitleWasSet / theme-color / visible-security: identical published shell
  // snapshot must not notify (SPA theme/security churn).
  assert(!ShouldNotifyShellPayloadChange(published, same));
  assert(ShouldNotifyShellPayloadChange(unpublished, same));

  // Distinct title updates must still notify.
  NativePageShellNotifyState retitled = same;
  retitled.title = u"SPA title";
  assert(ShouldNotifyShellPayloadChange(published, retitled));
  assert(ShellNotifyPayloadChanged(published, retitled));

  // Loading-adjacent shell changes still notify through the shared gate.
  NativePageShellNotifyState theme_while_loading = same;
  theme_while_loading.loading = true;
  assert(ShouldNotifyShellPayloadChange(published, theme_while_loading));
  theme_while_loading = same;
  theme_while_loading.url = "https://example.com/spa";
  assert(ShouldNotifyShellPayloadChange(published, theme_while_loading));
  theme_while_loading = same;
  theme_while_loading.can_go_back = false;
  assert(ShouldNotifyShellPayloadChange(published, theme_while_loading));
  theme_while_loading = same;
  theme_while_loading.can_go_forward = true;
  assert(ShouldNotifyShellPayloadChange(published, theme_while_loading));

  // Loading helper remains the shared predicate for DidStart/DidStop.
  assert(ShouldNotifyLoadingChange(published, retitled) ==
         ShouldNotifyShellPayloadChange(published, retitled));
  assert(ShouldNotifyLoadingChange(published, same) ==
         ShouldNotifyShellPayloadChange(published, same));

  // Reader changed_ / CaptureChanged: identical published snapshot (including
  // reader + capture bits) must not notify.
  assert(!ShouldNotifyShellPayloadChange(published, same));

  // Real reader mode / revision changes must still notify even when the five
  // tab-metadata fields are unchanged.
  NativePageShellNotifyState reader = same;
  reader.reader_mode = 1;  // kDistilling
  assert(ShouldNotifyShellPayloadChange(published, reader));
  assert(ShellNotifyPayloadChanged(published, reader));
  reader = same;
  reader.reader_revision = 7;
  assert(ShouldNotifyShellPayloadChange(published, reader));
  assert(ShellNotifyPayloadChanged(published, reader));

  // Real capture producer bit flips must still notify with unchanged
  // URL/title/loading/back/forward/reader.
  NativePageShellNotifyState capture = same;
  capture.capture_camera = true;
  assert(ShouldNotifyShellPayloadChange(published, capture));
  assert(ShellNotifyPayloadChanged(published, capture));
  capture = same;
  capture.capture_microphone = true;
  assert(ShouldNotifyShellPayloadChange(published, capture));
  capture = same;
  capture.capture_tab = true;
  assert(ShouldNotifyShellPayloadChange(published, capture));
  capture = same;
  capture.capture_window = true;
  assert(ShouldNotifyShellPayloadChange(published, capture));
  capture = same;
  capture.capture_display = true;
  assert(ShouldNotifyShellPayloadChange(published, capture));
  capture = same;
  capture.capture_mirrored = true;
  assert(ShouldNotifyShellPayloadChange(published, capture));
  capture = same;
  capture.capture_shared = true;
  assert(ShouldNotifyShellPayloadChange(published, capture));

  // The top bar shows theme-color (developerModeTint is always opaque), else
  // an opaque CSS background, else nothing.
  assert(TopBarPageColor(0x800F0F0Fu, 0xFFFFFFFFu) == 0x800F0F0Fu);
  assert(TopBarPageColor(std::nullopt, 0xFF000000u) == 0xFF000000u);
  assert(!TopBarPageColor(std::nullopt, 0x80FFFFFFu));
  assert(!TopBarPageColor(std::nullopt, std::nullopt));

  // A change to the colour the bar shows notifies even when every other field
  // is unchanged; the same colour again skips.
  NativePageShellNotifyState colored = same;
  colored.top_bar_color = TopBarPageColor(0xFF0F0F0Fu, std::nullopt);
  assert(ShouldNotifyShellPayloadChange(published, colored));
  assert(ShellNotifyPayloadChanged(published, colored));
  NativePageShellNotifyState published_colored = colored;
  published_colored.published = true;
  assert(!ShouldNotifyShellPayloadChange(published_colored, colored));
  // A background animating under a winning theme-color changes nothing shown.
  NativePageShellNotifyState animating = colored;
  animating.top_bar_color = TopBarPageColor(0xFF0F0F0Fu, 0xFF102030u);
  assert(!ShouldNotifyShellPayloadChange(published_colored, animating));
  NativePageShellNotifyState cleared = published_colored;
  cleared.published = false;
  cleared.top_bar_color = TopBarPageColor(std::nullopt, std::nullopt);
  assert(ShouldNotifyShellPayloadChange(published_colored, cleared));

  // A top-band delivery notifies, with or without a colour; the same
  // delivery again skips.
  NativePageShellNotifyState sampled = same;
  sampled.top_band_delivered = true;
  assert(ShouldNotifyShellPayloadChange(published, sampled));
  sampled.top_band_color = 0xFF1A73E8u;
  assert(ShellNotifyPayloadChanged(published, sampled));
  NativePageShellNotifyState published_sampled = sampled;
  published_sampled.published = true;
  assert(!ShouldNotifyShellPayloadChange(published_sampled, sampled));
  sampled.top_band_color = 0xFF000000u;
  assert(ShouldNotifyShellPayloadChange(published_sampled, sampled));
  // The same colour from another site's document notifies too, so the
  // shell caches it under the new host.
  NativePageShellNotifyState navigated = published_sampled;
  navigated.published = false;
  navigated.top_band_host = "chatgpt.com";
  assert(ShouldNotifyShellPayloadChange(published_sampled, navigated));

  // Capture/reader bits already published: another identical tick skips.
  NativePageShellNotifyState published_capture = capture;
  published_capture.published = true;
  NativePageShellNotifyState same_capture = capture;
  same_capture.published = false;
  assert(!ShouldNotifyShellPayloadChange(published_capture, same_capture));

  // A cross-document load is held past its main document's end until the
  // main document has had nothing in flight for the quiet window and the
  // page has painted, never past the cap.
  using parc::LoadingHold;
  LoadingHold hold;
  assert(hold.Update(true, false, 0));
  hold.Committed(100);
  assert(hold.Update(true, false, 200));
  assert(hold.Update(false, false, 1000) && hold.holding());
  assert(hold.Remaining(false, 1000) == LoadingHold::kCapMs);
  hold.NetworkBusy(true, 1100);
  hold.NetworkBusy(false, 1200);
  assert(hold.Update(false, true, 1600));
  assert(hold.Remaining(true, 1600) == 100);
  assert(!hold.Update(false, true, 1700) && !hold.holding());
  hold.NetworkBusy(true, 1800);
  assert(!hold.Update(false, true, 1800));
  hold.NetworkBusy(false, 1900);
  // Without a paint, or with a page that is never idle, the cap ends it.
  hold.Committed(0);
  hold.NetworkBusy(true, 0);
  assert(hold.Update(false, false, 0));
  for (int64_t t = 0; t < LoadingHold::kCapMs; t += 100) {
    assert(hold.Update(false, true, t));
    assert(hold.Remaining(true, t) == LoadingHold::kCapMs - t);
  }
  assert(!hold.Update(false, true, LoadingHold::kCapMs));
  hold.NetworkBusy(false, LoadingHold::kCapMs);
  // Already quiet and painted when the load ends: a quiet window after the
  // last request, not after the end.
  hold.Committed(0);
  assert(!hold.Update(false, true, 600));
  // Same-document loads are never held; a new load supersedes a hold.
  assert(!hold.Update(false, true, 700));
  hold.Committed(0);
  assert(hold.Update(false, false, 100));
  assert(hold.Update(true, false, 200) && !hold.holding());
  hold.Committed(0);
  assert(hold.Update(false, false, 100));
  hold.Cancel();
  assert(!hold.Update(false, false, 200));

  // The renderer's count drives the hold: a slow request still downloading
  // after a fast one finishes keeps the page loading until it ends.
  using parc::page_network::InFlightRequests;
  using parc::page_network::kLongLivedMs;
  InFlightRequests count;
  auto report = [&](int64_t now) {
    hold.NetworkBusy(count.BusyUntil(now).has_value(), now);
  };
  hold.Committed(0);
  assert(hold.Update(true, false, 50));
  count.Start(1, 100);
  count.Start(2, 100);
  report(100);
  assert(hold.Update(false, true, 1000));
  count.Finish(1);
  report(1100);
  assert(hold.Update(false, true, 1700) && hold.Update(false, true, 2500));
  assert(hold.Remaining(true, 2500) == 1000 + LoadingHold::kCapMs - 2500);
  count.Finish(2);
  report(2600);
  assert(hold.Update(false, true, 3000));
  assert(hold.Remaining(true, 3000) == 100);
  assert(!hold.Update(false, true, 3100));
  // Finishing an unknown or already finished request changes nothing.
  count.Finish(2);
  count.Finish(7);
  assert(!count.BusyUntil(3100));

  // A navigation that keeps its renderer frame commits while the old
  // document still looks busy; the renderer's reset at commit ends it, and
  // without that report the cap does.
  hold.NetworkBusy(true, 0);
  hold.Committed(100);
  assert(hold.Update(false, true, 200));
  hold.NetworkBusy(false, 300);
  assert(hold.Update(false, true, 799));
  assert(!hold.Update(false, true, 800));
  hold.NetworkBusy(true, 900);
  hold.Committed(1000);
  assert(hold.Update(false, true, 1100));
  assert(hold.Update(false, true, 1100 + LoadingHold::kCapMs - 1));
  assert(!hold.Update(false, true, 1100 + LoadingHold::kCapMs));
  hold.NetworkBusy(false, 1100 + LoadingHold::kCapMs);

  // A long-poll stops counting kLongLivedMs after it starts, so a page whose
  // main document is slow ends its hold on quiet, not at the cap.
  count.Reset();
  hold.Committed(0);
  count.Start(3, 0);
  assert(count.BusyUntil(0) == kLongLivedMs);
  report(0);
  assert(hold.Update(true, true, 3000));
  assert(hold.Update(false, true, 3000));
  assert(count.BusyUntil(kLongLivedMs - 1) == kLongLivedMs);
  report(kLongLivedMs - 1);
  assert(hold.Update(false, true, kLongLivedMs - 1));
  assert(!count.BusyUntil(kLongLivedMs));
  report(kLongLivedMs);
  assert(hold.Update(false, true, kLongLivedMs + 499));
  assert(!hold.Update(false, true, kLongLivedMs + 500));
  // Its late finish is not a new request; the count stays empty.
  count.Finish(3);
  assert(!count.BusyUntil(kLongLivedMs + 600));
  // Busy lasts until the last open request expires, and a new document
  // starts from nothing.
  count.Start(4, 0);
  count.Start(5, 1000);
  assert(count.BusyUntil(500) == 1000 + kLongLivedMs);
  assert(count.BusyUntil(kLongLivedMs) == 1000 + kLongLivedMs);
  count.Reset();
  assert(!count.BusyUntil(kLongLivedMs));

  std::cout << "Passed native page-shell finished-navigation, loading, "
               "title/theme/security, reader, capture, page-colour, top-band and "
               "page-network-activity notify "
               "filters; "
               "no browser execution.\n";
}
