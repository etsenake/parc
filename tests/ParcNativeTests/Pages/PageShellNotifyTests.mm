#include "native_page_shell_notify.h"
#include "page_network_activity_count.h"

#import "ParcNativeTest.h"

using parc::LoadingHold;
using parc::NativePageShellNotifyState;
using parc::ShellNotifyPayloadChanged;
using parc::ShouldNotifyFinishedNavigation;
using parc::ShouldNotifyLoadingChange;
using parc::ShouldNotifyShellPayloadChange;
using parc::TopBarPageColor;
using parc::page_network::InFlightRequests;
using parc::page_network::kLongLivedMs;

static NativePageShellNotifyState Published() {
  NativePageShellNotifyState published;
  published.url = "https://example.com/";
  published.title = u"Example";
  published.loading = false;
  published.can_go_back = true;
  published.can_go_forward = false;
  published.published = true;
  return published;
}

static NativePageShellNotifyState Same() {
  NativePageShellNotifyState same = Published();
  same.published = false;
  return same;
}

static NativePageShellNotifyState Colored() {
  NativePageShellNotifyState colored = Same();
  colored.top_bar_color = TopBarPageColor(0xFF0F0F0Fu, std::nullopt);
  return colored;
}

@interface PageShellNotifyTests : ParcNativeTestCase
@end

@implementation PageShellNotifyTests {
  LoadingHold _hold;
  InFlightRequests _count;
}

- (void)report:(int64_t)now {
  _hold.NetworkBusy(_count.BusyUntil(now).has_value(), now);
}

- (void)testFinishedNavigationNotifiesOnlyWhatTheShellHasNotSeen {
  const NativePageShellNotifyState unpublished, published = Published(), same = Same();
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, false, true, unpublished, published));
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, true, true, unpublished, published));
  PARC_CHECK(!ShouldNotifyFinishedNavigation(false, false, true, published, same));
  PARC_CHECK(!ShouldNotifyFinishedNavigation(false, true, true, published, same));
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, true, false, published, same));
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, false, true, published, same));
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, unpublished, same));
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, false, published, same));
  PARC_CHECK(!ShouldNotifyFinishedNavigation(true, true, true, published, same));
}

- (void)testFinishedNavigationNotifiesEveryPayloadChange {
  const NativePageShellNotifyState published = Published();
  NativePageShellNotifyState changed = Same();
  changed.url = "https://example.com/#hash";
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  changed = Same();
  changed.title = u"Renamed";
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  changed = Same();
  changed.loading = true;
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  changed = Same();
  changed.can_go_back = false;
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, true, true, published, changed));
  changed = Same();
  changed.can_go_forward = true;
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, published, changed));
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, false, true, published, changed));
  PARC_CHECK(!ShellNotifyPayloadChanged(published, Same()));
  PARC_CHECK(ShellNotifyPayloadChanged(published, changed));
}

- (void)testLoadingChangesNotifyOnlyRealChanges {
  const NativePageShellNotifyState unpublished, published = Published(), same = Same();
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
  PARC_CHECK(!ShouldNotifyLoadingChange(published_loading, loading));
}

- (void)testLoadingNotifiesHistoryAddressAndTitleChanges {
  const NativePageShellNotifyState published = Published();
  NativePageShellNotifyState history = Same();
  history.can_go_back = false;
  PARC_CHECK(ShouldNotifyLoadingChange(published, history));
  history = Same();
  history.can_go_forward = true;
  PARC_CHECK(ShouldNotifyLoadingChange(published, history));
  history = Same();
  history.url = "https://example.com/next";
  PARC_CHECK(ShouldNotifyLoadingChange(published, history));
  history = Same();
  history.title = u"Next";
  PARC_CHECK(ShouldNotifyLoadingChange(published, history));
}

- (void)testShellPayloadNotifiesTitleLoadingAndHistoryChanges {
  const NativePageShellNotifyState unpublished, published = Published(), same = Same();
  PARC_CHECK(!ShouldNotifyShellPayloadChange(published, same));
  PARC_CHECK(ShouldNotifyShellPayloadChange(unpublished, same));
  NativePageShellNotifyState retitled = same;
  retitled.title = u"SPA title";
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, retitled));
  PARC_CHECK(ShellNotifyPayloadChanged(published, retitled));
  NativePageShellNotifyState changed = same;
  changed.loading = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, changed));
  changed = same;
  changed.url = "https://example.com/spa";
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, changed));
  changed = same;
  changed.can_go_back = false;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, changed));
  changed = same;
  changed.can_go_forward = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, changed));
  PARC_CHECK(ShouldNotifyLoadingChange(published, retitled) == ShouldNotifyShellPayloadChange(published, retitled));
  PARC_CHECK(ShouldNotifyLoadingChange(published, same) == ShouldNotifyShellPayloadChange(published, same));
}

- (void)testReaderModeChangesNotify {
  const NativePageShellNotifyState published = Published();
  NativePageShellNotifyState reader = Same();
  reader.reader_mode = 1;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, reader));
  PARC_CHECK(ShellNotifyPayloadChanged(published, reader));
  reader = Same();
  reader.reader_revision = 7;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, reader));
  PARC_CHECK(ShellNotifyPayloadChanged(published, reader));
}

- (void)testEveryCaptureIndicatorChangeNotifies {
  const NativePageShellNotifyState published = Published();
  NativePageShellNotifyState capture = Same();
  capture.capture_camera = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, capture));
  PARC_CHECK(ShellNotifyPayloadChanged(published, capture));
  bool NativePageShellNotifyState::*flags[] = {
      &NativePageShellNotifyState::capture_microphone, &NativePageShellNotifyState::capture_tab,
      &NativePageShellNotifyState::capture_window, &NativePageShellNotifyState::capture_display,
      &NativePageShellNotifyState::capture_mirrored, &NativePageShellNotifyState::capture_shared};
  for (auto flag : flags) {
    capture = Same();
    capture.*flag = true;
    PARC_CHECK(ShouldNotifyShellPayloadChange(published, capture));
  }
}

- (void)testAnUnchangedCapturePayloadDoesNotNotify {
  NativePageShellNotifyState same_capture = Same();
  same_capture.capture_shared = true;
  NativePageShellNotifyState published_capture = same_capture;
  published_capture.published = true;
  PARC_CHECK(!ShouldNotifyShellPayloadChange(published_capture, same_capture));
}

- (void)testTheTopBarColorPrefersThePageThenAnOpaqueTheme {
  PARC_CHECK(TopBarPageColor(0x800F0F0Fu, 0xFFFFFFFFu) == 0x800F0F0Fu);
  PARC_CHECK(TopBarPageColor(std::nullopt, 0xFF000000u) == 0xFF000000u);
  PARC_CHECK(!TopBarPageColor(std::nullopt, 0x80FFFFFFu));
  PARC_CHECK(!TopBarPageColor(std::nullopt, std::nullopt));
}

- (void)testTopBarColorNotifiesOnceAndIgnoresThemeAnimation {
  const NativePageShellNotifyState published = Published();
  NativePageShellNotifyState colored = Colored();
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
}

- (void)testSampledTopBandNotifiesNewColorsAndHosts {
  const NativePageShellNotifyState published = Published();
  NativePageShellNotifyState sampled = Same();
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
}

- (void)testTheLoadingHoldEndsWhenThePaintedPageGoesNetworkQuiet {
  PARC_CHECK(_hold.Update(true, false, 0));
  _hold.Committed(100);
  PARC_CHECK(_hold.Update(true, false, 200));
  PARC_CHECK(_hold.Update(false, false, 1000) && _hold.holding());
  PARC_CHECK(_hold.Remaining(false, 1000) == LoadingHold::kCapMs);
  _hold.NetworkBusy(true, 1100);
  _hold.NetworkBusy(false, 1200);
  PARC_CHECK(_hold.Update(false, true, 1600));
  PARC_CHECK(_hold.Remaining(true, 1600) == 100);
  PARC_CHECK(!_hold.Update(false, true, 1700) && !_hold.holding());
  _hold.NetworkBusy(true, 1800);
  PARC_CHECK(!_hold.Update(false, true, 1800));
}

- (void)testABusyNetworkHoldsUntilTheCap {
  _hold.Committed(0);
  _hold.NetworkBusy(true, 0);
  PARC_CHECK(_hold.Update(false, false, 0));
  for (int64_t t = 0; t < LoadingHold::kCapMs; t += 100) {
    PARC_CHECK(_hold.Update(false, true, t));
    PARC_CHECK(_hold.Remaining(true, t) == LoadingHold::kCapMs - t);
  }
  PARC_CHECK(!_hold.Update(false, true, LoadingHold::kCapMs));
}

- (void)testAPaintedQuietPageDropsTheHoldAtOnce {
  _hold.Committed(0);
  PARC_CHECK(!_hold.Update(false, true, 600));
  PARC_CHECK(!_hold.Update(false, true, 700));
}

- (void)testMainFrameLoadingAgainEndsTheHold {
  _hold.Committed(0);
  PARC_CHECK(_hold.Update(false, false, 100));
  PARC_CHECK(_hold.Update(true, false, 200) && !_hold.holding());
}

- (void)testCancellingEndsTheHold {
  _hold.Committed(0);
  PARC_CHECK(_hold.Update(false, false, 100));
  _hold.Cancel();
  PARC_CHECK(!_hold.Update(false, false, 200));
}

- (void)testInFlightRequestsKeepTheHoldUntilTheLastFinishes {
  _hold.Committed(0);
  PARC_CHECK(_hold.Update(true, false, 50));
  _count.Start(1, 100);
  _count.Start(2, 100);
  [self report:100];
  PARC_CHECK(_hold.Update(false, true, 1000));
  _count.Finish(1);
  [self report:1100];
  PARC_CHECK(_hold.Update(false, true, 1700) && _hold.Update(false, true, 2500));
  PARC_CHECK(_hold.Remaining(true, 2500) == 1000 + LoadingHold::kCapMs - 2500);
  _count.Finish(2);
  [self report:2600];
  PARC_CHECK(_hold.Update(false, true, 3000));
  PARC_CHECK(_hold.Remaining(true, 3000) == 100);
  PARC_CHECK(!_hold.Update(false, true, 3100));
  _count.Finish(2);
  _count.Finish(7);
  PARC_CHECK(!_count.BusyUntil(3100));
}

- (void)testANetworkThatGoesQuietAfterCommitEndsTheHoldAfterTheQuietTime {
  _hold.NetworkBusy(true, 0);
  _hold.Committed(100);
  PARC_CHECK(_hold.Update(false, true, 200));
  _hold.NetworkBusy(false, 300);
  PARC_CHECK(_hold.Update(false, true, 799));
  PARC_CHECK(!_hold.Update(false, true, 800));
}

- (void)testANetworkBusyThroughCommitHoldsUntilTheCap {
  _hold.NetworkBusy(true, 900);
  _hold.Committed(1000);
  PARC_CHECK(_hold.Update(false, true, 1100));
  PARC_CHECK(_hold.Update(false, true, 1100 + LoadingHold::kCapMs - 1));
  PARC_CHECK(!_hold.Update(false, true, 1100 + LoadingHold::kCapMs));
}

- (void)testALongLivedRequestStopsCountingAsBusy {
  _hold.Committed(0);
  _count.Start(3, 0);
  PARC_CHECK(_count.BusyUntil(0) == kLongLivedMs);
  [self report:0];
  PARC_CHECK(_hold.Update(true, true, 3000));
  PARC_CHECK(_hold.Update(false, true, 3000));
  PARC_CHECK(_count.BusyUntil(kLongLivedMs - 1) == kLongLivedMs);
  [self report:kLongLivedMs - 1];
  PARC_CHECK(_hold.Update(false, true, kLongLivedMs - 1));
  PARC_CHECK(!_count.BusyUntil(kLongLivedMs));
  [self report:kLongLivedMs];
  PARC_CHECK(_hold.Update(false, true, kLongLivedMs + 499));
  PARC_CHECK(!_hold.Update(false, true, kLongLivedMs + 500));
  _count.Finish(3);
  PARC_CHECK(!_count.BusyUntil(kLongLivedMs + 600));
}

- (void)testTheNewestRequestSetsTheBusyDeadlineUntilReset {
  _count.Start(4, 0);
  _count.Start(5, 1000);
  PARC_CHECK(_count.BusyUntil(500) == 1000 + kLongLivedMs);
  PARC_CHECK(_count.BusyUntil(kLongLivedMs) == 1000 + kLongLivedMs);
  _count.Reset();
  PARC_CHECK(!_count.BusyUntil(kLongLivedMs));
}

@end
