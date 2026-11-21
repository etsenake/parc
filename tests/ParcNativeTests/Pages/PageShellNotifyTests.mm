#include "native_page_shell_notify.h"
#include "page_network_activity_count.h"

#import "ParcNativeTest.h"
#include <iostream>

@interface PageShellNotifyTests : ParcNativeTestCase
@end

@implementation PageShellNotifyTests

- (void)testFinishedNavigationLoadingAndActivity {
  @autoreleasepool {
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

  PARC_CHECK(ShouldNotifyFinishedNavigation(false, false, true, unpublished, published));
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, true, true, unpublished, published));
  PARC_CHECK(!ShouldNotifyFinishedNavigation(false, false, true, published, same));
  PARC_CHECK(!ShouldNotifyFinishedNavigation(false, true, true, published, same));
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, true, false, published, same));
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, false, true, published, same));
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, unpublished, same));
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, false, published, same));
  PARC_CHECK(!ShouldNotifyFinishedNavigation(true, true, true, published, same));

  NativePageShellNotifyState changed = same;
  changed.url = "https://example.com/#hash";
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  changed = same;
  changed.title = u"Renamed";
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  changed = same;
  changed.loading = true;
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  changed = same;
  changed.can_go_back = false;
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, true, true, published, changed));
  changed = same;
  changed.can_go_forward = true;
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, false, true, published, changed));

  PARC_CHECK(!ShellNotifyPayloadChanged(published, same));
  PARC_CHECK(ShellNotifyPayloadChanged(published, changed));

  PARC_CHECK(ShouldNotifyLoadingChange(unpublished, same));
  PARC_CHECK(ShouldNotifyLoadingChange(unpublished, published));

  PARC_CHECK(!ShouldNotifyLoadingChange(published, same));

  NativePageShellNotifyState loading = same;
  loading.loading = true;
  PARC_CHECK(ShouldNotifyLoadingChange(published, loading));
  NativePageShellNotifyState stopped = loading;
  stopped.loading = false;
  NativePageShellNotifyState published_loading = loading;
  published_loading.published = true;
  PARC_CHECK(ShouldNotifyLoadingChange(published_loading, stopped));

  NativePageShellNotifyState history = same;
  history.can_go_back = false;
  PARC_CHECK(ShouldNotifyLoadingChange(published, history));
  history = same;
  history.can_go_forward = true;
  PARC_CHECK(ShouldNotifyLoadingChange(published, history));
  history = same;
  history.url = "https://example.com/next";
  PARC_CHECK(ShouldNotifyLoadingChange(published, history));
  history = same;
  history.title = u"Next";
  PARC_CHECK(ShouldNotifyLoadingChange(published, history));

  PARC_CHECK(!ShouldNotifyLoadingChange(published_loading, loading));

  PARC_CHECK(!ShouldNotifyShellPayloadChange(published, same));
  PARC_CHECK(ShouldNotifyShellPayloadChange(unpublished, same));

  NativePageShellNotifyState retitled = same;
  retitled.title = u"SPA title";
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, retitled));
  PARC_CHECK(ShellNotifyPayloadChanged(published, retitled));

  NativePageShellNotifyState theme_while_loading = same;
  theme_while_loading.loading = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, theme_while_loading));
  theme_while_loading = same;
  theme_while_loading.url = "https://example.com/spa";
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, theme_while_loading));
  theme_while_loading = same;
  theme_while_loading.can_go_back = false;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, theme_while_loading));
  theme_while_loading = same;
  theme_while_loading.can_go_forward = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, theme_while_loading));

  PARC_CHECK(ShouldNotifyLoadingChange(published, retitled) ==
         ShouldNotifyShellPayloadChange(published, retitled));
  PARC_CHECK(ShouldNotifyLoadingChange(published, same) ==
         ShouldNotifyShellPayloadChange(published, same));

  PARC_CHECK(!ShouldNotifyShellPayloadChange(published, same));

  NativePageShellNotifyState reader = same;
  reader.reader_mode = 1;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, reader));
  PARC_CHECK(ShellNotifyPayloadChanged(published, reader));
  reader = same;
  reader.reader_revision = 7;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, reader));
  PARC_CHECK(ShellNotifyPayloadChanged(published, reader));

  NativePageShellNotifyState capture = same;
  capture.capture_camera = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, capture));
  PARC_CHECK(ShellNotifyPayloadChanged(published, capture));
  capture = same;
  capture.capture_microphone = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, capture));
  capture = same;
  capture.capture_tab = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, capture));
  capture = same;
  capture.capture_window = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, capture));
  capture = same;
  capture.capture_display = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, capture));
  capture = same;
  capture.capture_mirrored = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, capture));
  capture = same;
  capture.capture_shared = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, capture));

  PARC_CHECK(TopBarPageColor(0x800F0F0Fu, 0xFFFFFFFFu) == 0x800F0F0Fu);
  PARC_CHECK(TopBarPageColor(std::nullopt, 0xFF000000u) == 0xFF000000u);
  PARC_CHECK(!TopBarPageColor(std::nullopt, 0x80FFFFFFu));
  PARC_CHECK(!TopBarPageColor(std::nullopt, std::nullopt));

  NativePageShellNotifyState colored = same;
  colored.top_bar_color = TopBarPageColor(0xFF0F0F0Fu, std::nullopt);
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, colored));
  PARC_CHECK(ShellNotifyPayloadChanged(published, colored));
  NativePageShellNotifyState published_colored = colored;
  published_colored.published = true;
  PARC_CHECK(!ShouldNotifyShellPayloadChange(published_colored, colored));
  NativePageShellNotifyState animating = colored;
  animating.top_bar_color = TopBarPageColor(0xFF0F0F0Fu, 0xFF102030u);
  PARC_CHECK(!ShouldNotifyShellPayloadChange(published_colored, animating));
  NativePageShellNotifyState cleared = published_colored;
  cleared.published = false;
  cleared.top_bar_color = TopBarPageColor(std::nullopt, std::nullopt);
  PARC_CHECK(ShouldNotifyShellPayloadChange(published_colored, cleared));

  NativePageShellNotifyState sampled = same;
  sampled.top_band_delivered = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, sampled));
  sampled.top_band_color = 0xFF1A73E8u;
  PARC_CHECK(ShellNotifyPayloadChanged(published, sampled));
  NativePageShellNotifyState published_sampled = sampled;
  published_sampled.published = true;
  PARC_CHECK(!ShouldNotifyShellPayloadChange(published_sampled, sampled));
  sampled.top_band_color = 0xFF000000u;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published_sampled, sampled));
  NativePageShellNotifyState navigated = published_sampled;
  navigated.published = false;
  navigated.top_band_host = "chatgpt.com";
  PARC_CHECK(ShouldNotifyShellPayloadChange(published_sampled, navigated));

  NativePageShellNotifyState published_capture = capture;
  published_capture.published = true;
  NativePageShellNotifyState same_capture = capture;
  same_capture.published = false;
  PARC_CHECK(!ShouldNotifyShellPayloadChange(published_capture, same_capture));

  using parc::LoadingHold;
  LoadingHold hold;
  PARC_CHECK(hold.Update(true, false, 0));
  hold.Committed(100);
  PARC_CHECK(hold.Update(true, false, 200));
  PARC_CHECK(hold.Update(false, false, 1000) && hold.holding());
  PARC_CHECK(hold.Remaining(false, 1000) == LoadingHold::kCapMs);
  hold.NetworkBusy(true, 1100);
  hold.NetworkBusy(false, 1200);
  PARC_CHECK(hold.Update(false, true, 1600));
  PARC_CHECK(hold.Remaining(true, 1600) == 100);
  PARC_CHECK(!hold.Update(false, true, 1700) && !hold.holding());
  hold.NetworkBusy(true, 1800);
  PARC_CHECK(!hold.Update(false, true, 1800));
  hold.NetworkBusy(false, 1900);
  hold.Committed(0);
  hold.NetworkBusy(true, 0);
  PARC_CHECK(hold.Update(false, false, 0));
  for (int64_t t = 0; t < LoadingHold::kCapMs; t += 100) {
    PARC_CHECK(hold.Update(false, true, t));
    PARC_CHECK(hold.Remaining(true, t) == LoadingHold::kCapMs - t);
  }
  PARC_CHECK(!hold.Update(false, true, LoadingHold::kCapMs));
  hold.NetworkBusy(false, LoadingHold::kCapMs);
  hold.Committed(0);
  PARC_CHECK(!hold.Update(false, true, 600));
  PARC_CHECK(!hold.Update(false, true, 700));
  hold.Committed(0);
  PARC_CHECK(hold.Update(false, false, 100));
  PARC_CHECK(hold.Update(true, false, 200) && !hold.holding());
  hold.Committed(0);
  PARC_CHECK(hold.Update(false, false, 100));
  hold.Cancel();
  PARC_CHECK(!hold.Update(false, false, 200));

  using parc::page_network::InFlightRequests;
  using parc::page_network::kLongLivedMs;
  InFlightRequests count;
  auto report = [&](int64_t now) {
    hold.NetworkBusy(count.BusyUntil(now).has_value(), now);
  };
  hold.Committed(0);
  PARC_CHECK(hold.Update(true, false, 50));
  count.Start(1, 100);
  count.Start(2, 100);
  report(100);
  PARC_CHECK(hold.Update(false, true, 1000));
  count.Finish(1);
  report(1100);
  PARC_CHECK(hold.Update(false, true, 1700) && hold.Update(false, true, 2500));
  PARC_CHECK(hold.Remaining(true, 2500) == 1000 + LoadingHold::kCapMs - 2500);
  count.Finish(2);
  report(2600);
  PARC_CHECK(hold.Update(false, true, 3000));
  PARC_CHECK(hold.Remaining(true, 3000) == 100);
  PARC_CHECK(!hold.Update(false, true, 3100));
  count.Finish(2);
  count.Finish(7);
  PARC_CHECK(!count.BusyUntil(3100));

  hold.NetworkBusy(true, 0);
  hold.Committed(100);
  PARC_CHECK(hold.Update(false, true, 200));
  hold.NetworkBusy(false, 300);
  PARC_CHECK(hold.Update(false, true, 799));
  PARC_CHECK(!hold.Update(false, true, 800));
  hold.NetworkBusy(true, 900);
  hold.Committed(1000);
  PARC_CHECK(hold.Update(false, true, 1100));
  PARC_CHECK(hold.Update(false, true, 1100 + LoadingHold::kCapMs - 1));
  PARC_CHECK(!hold.Update(false, true, 1100 + LoadingHold::kCapMs));
  hold.NetworkBusy(false, 1100 + LoadingHold::kCapMs);

  count.Reset();
  hold.Committed(0);
  count.Start(3, 0);
  PARC_CHECK(count.BusyUntil(0) == kLongLivedMs);
  report(0);
  PARC_CHECK(hold.Update(true, true, 3000));
  PARC_CHECK(hold.Update(false, true, 3000));
  PARC_CHECK(count.BusyUntil(kLongLivedMs - 1) == kLongLivedMs);
  report(kLongLivedMs - 1);
  PARC_CHECK(hold.Update(false, true, kLongLivedMs - 1));
  PARC_CHECK(!count.BusyUntil(kLongLivedMs));
  report(kLongLivedMs);
  PARC_CHECK(hold.Update(false, true, kLongLivedMs + 499));
  PARC_CHECK(!hold.Update(false, true, kLongLivedMs + 500));
  count.Finish(3);
  PARC_CHECK(!count.BusyUntil(kLongLivedMs + 600));
  count.Start(4, 0);
  count.Start(5, 1000);
  PARC_CHECK(count.BusyUntil(500) == 1000 + kLongLivedMs);
  PARC_CHECK(count.BusyUntil(kLongLivedMs) == 1000 + kLongLivedMs);
  count.Reset();
  PARC_CHECK(!count.BusyUntil(kLongLivedMs));

  }
}

@end
