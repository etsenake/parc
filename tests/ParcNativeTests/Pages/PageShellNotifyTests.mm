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

- (void)testTheFirstSubframeLoadNotifies {
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, false, true, {}, Published()));
}

- (void)testTheFirstSubframeHistoryChangeNotifies {
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, true, true, {}, Published()));
}

- (void)testRepeatedSubframeLoadsSkipDelivery {
  PARC_CHECK(!ShouldNotifyFinishedNavigation(false, false, true, Published(), Same()));
}

- (void)testRepeatedSubframeHistoryChangesSkipDelivery {
  PARC_CHECK(!ShouldNotifyFinishedNavigation(false, true, true, Published(), Same()));
}

- (void)testSubframeHistoryNotifiesWhenFaviconObservationIsNeeded {
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, true, false, Published(), Same()));
}

- (void)testNewMainDocumentsAlwaysNotify {
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, false, true, Published(), Same()));
}

- (void)testFirstMainFrameHistoryChangesNotify {
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, {}, Same()));
}

- (void)testMainFrameHistoryNotifiesWhenFaviconObservationIsNeeded {
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, false, Published(), Same()));
}

- (void)testUnchangedMainFrameHistorySkipsNotification {
  PARC_CHECK(!ShouldNotifyFinishedNavigation(true, true, true, Published(), Same()));
}

- (void)testChangesToAddressReachTheShell {
  NativePageShellNotifyState changed = Same();
  changed.url = "https://example.com/#hash";
  PARC_CHECK(ShellNotifyPayloadChanged(Published(), changed));
  PARC_CHECK(ShouldNotifyShellPayloadChange(Published(), changed));
  PARC_CHECK(ShouldNotifyLoadingChange(Published(), changed));
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, Published(), changed));
}

- (void)testChangesToTitleReachTheShell {
  NativePageShellNotifyState changed = Same();
  changed.title = u"Renamed";
  PARC_CHECK(ShellNotifyPayloadChanged(Published(), changed));
  PARC_CHECK(ShouldNotifyShellPayloadChange(Published(), changed));
  PARC_CHECK(ShouldNotifyLoadingChange(Published(), changed));
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, Published(), changed));
}

- (void)testChangesToLoadingReachTheShell {
  NativePageShellNotifyState changed = Same();
  changed.loading = true;
  PARC_CHECK(ShellNotifyPayloadChanged(Published(), changed));
  PARC_CHECK(ShouldNotifyShellPayloadChange(Published(), changed));
  PARC_CHECK(ShouldNotifyLoadingChange(Published(), changed));
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, Published(), changed));
}

- (void)testChangesToBackHistoryReachTheShell {
  NativePageShellNotifyState changed = Same();
  changed.can_go_back = false;
  PARC_CHECK(ShellNotifyPayloadChanged(Published(), changed));
  PARC_CHECK(ShouldNotifyShellPayloadChange(Published(), changed));
  PARC_CHECK(ShouldNotifyLoadingChange(Published(), changed));
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, Published(), changed));
}

- (void)testChangesToForwardHistoryReachTheShell {
  NativePageShellNotifyState changed = Same();
  changed.can_go_forward = true;
  PARC_CHECK(ShellNotifyPayloadChanged(Published(), changed));
  PARC_CHECK(ShouldNotifyShellPayloadChange(Published(), changed));
  PARC_CHECK(ShouldNotifyLoadingChange(Published(), changed));
  PARC_CHECK(ShouldNotifyFinishedNavigation(true, true, true, Published(), changed));
}

- (void)testSubframeUpdatesNotifyBackHistory {
  NativePageShellNotifyState changed = Same();
  changed.can_go_back = false;
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, true, true, Published(), changed));
}

- (void)testSubframeUpdatesNotifyForwardHistory {
  NativePageShellNotifyState changed = Same();
  changed.can_go_forward = true;
  PARC_CHECK(ShouldNotifyFinishedNavigation(false, false, true, Published(), changed));
}

- (void)testTheFirstPayloadNotifies {
  PARC_CHECK(ShouldNotifyShellPayloadChange({}, Same()));
}

- (void)testAnUnchangedPayloadSkipsDelivery {
  PARC_CHECK(!ShouldNotifyShellPayloadChange(Published(), Same()));
  PARC_CHECK(!ShellNotifyPayloadChanged(Published(), Same()));
}

- (void)testTheFirstLoadingUpdateNotifies {
  PARC_CHECK(ShouldNotifyLoadingChange({}, Same()));
  PARC_CHECK(ShouldNotifyLoadingChange({}, Published()));
}

- (void)testUnchangedLoadingSkipsDelivery {
  PARC_CHECK(!ShouldNotifyLoadingChange(Published(), Same()));
}

- (void)testFinishingLoadingNotifies {
  auto loading = Same();
  loading.loading = true;
  NativePageShellNotifyState stopped = loading;
  stopped.loading = false;
  NativePageShellNotifyState published_loading = loading;
  published_loading.published = true;
  PARC_CHECK(ShouldNotifyLoadingChange(published_loading, stopped));
}

- (void)testContinuingToLoadSkipsDuplicateDelivery {
  auto loading = Same();
  loading.loading = true;
  NativePageShellNotifyState published_loading = loading;
  published_loading.published = true;
  PARC_CHECK(!ShouldNotifyLoadingChange(published_loading, loading));
}

- (void)testReaderModeChangesReachTheShell {
  const NativePageShellNotifyState published = Published();
  NativePageShellNotifyState reader = Same();
  reader.reader_mode = 1;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, reader));
  PARC_CHECK(ShellNotifyPayloadChanged(published, reader));
}

- (void)testReaderRevisionChangesReachTheShell {
  const NativePageShellNotifyState published = Published();
  NativePageShellNotifyState reader = Same();
  reader.reader_revision = 7;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, reader));
  PARC_CHECK(ShellNotifyPayloadChanged(published, reader));
}

- (void)testCameraCaptureChangesReachTheShell {
  NativePageShellNotifyState capture = Same();
  capture.capture_camera = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(Published(), capture));
  PARC_CHECK(ShellNotifyPayloadChanged(Published(), capture));
}

- (void)testMicrophoneCaptureChangesReachTheShell {
  NativePageShellNotifyState capture = Same();
  capture.capture_microphone = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(Published(), capture));
  PARC_CHECK(ShellNotifyPayloadChanged(Published(), capture));
}

- (void)testTabCaptureChangesReachTheShell {
  NativePageShellNotifyState capture = Same();
  capture.capture_tab = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(Published(), capture));
  PARC_CHECK(ShellNotifyPayloadChanged(Published(), capture));
}

- (void)testWindowCaptureChangesReachTheShell {
  NativePageShellNotifyState capture = Same();
  capture.capture_window = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(Published(), capture));
  PARC_CHECK(ShellNotifyPayloadChanged(Published(), capture));
}

- (void)testDisplayCaptureChangesReachTheShell {
  NativePageShellNotifyState capture = Same();
  capture.capture_display = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(Published(), capture));
  PARC_CHECK(ShellNotifyPayloadChanged(Published(), capture));
}

- (void)testMirroredCaptureChangesReachTheShell {
  NativePageShellNotifyState capture = Same();
  capture.capture_mirrored = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(Published(), capture));
  PARC_CHECK(ShellNotifyPayloadChanged(Published(), capture));
}

- (void)testSharedCaptureChangesReachTheShell {
  NativePageShellNotifyState capture = Same();
  capture.capture_shared = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(Published(), capture));
  PARC_CHECK(ShellNotifyPayloadChanged(Published(), capture));
}

- (void)testAnUnchangedCapturePayloadDoesNotNotify {
  NativePageShellNotifyState same_capture = Same();
  same_capture.capture_shared = true;
  NativePageShellNotifyState published_capture = same_capture;
  published_capture.published = true;
  PARC_CHECK(!ShouldNotifyShellPayloadChange(published_capture, same_capture));
}

- (void)testPageColorOverridesThemeColor {
  PARC_CHECK(TopBarPageColor(0x800F0F0Fu, 0xFFFFFFFFu) == 0x800F0F0Fu);
}

- (void)testOpaqueThemeColorsSupplyTheFallback {
  PARC_CHECK(TopBarPageColor(std::nullopt, 0xFF000000u) == 0xFF000000u);
}

- (void)testTranslucentThemesSupplyNoFallback {
  PARC_CHECK(!TopBarPageColor(std::nullopt, 0x80FFFFFFu));
}

- (void)testMissingColorsLeaveTheTopBarUnset {
  PARC_CHECK(!TopBarPageColor(std::nullopt, std::nullopt));
}

- (void)testAFirstTopBarColorReachesTheShell {
  const NativePageShellNotifyState published = Published();
  NativePageShellNotifyState colored = Colored();
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, colored));
  PARC_CHECK(ShellNotifyPayloadChanged(published, colored));
}

- (void)testDuplicateTopBarColorsSkipDelivery {
  NativePageShellNotifyState colored = Colored();
  NativePageShellNotifyState published_colored = colored;
  published_colored.published = true;
  PARC_CHECK(!ShouldNotifyShellPayloadChange(published_colored, colored));
}

- (void)testThemeAnimationKeepsAnExistingPageColor {
  NativePageShellNotifyState colored = Colored();
  NativePageShellNotifyState published_colored = colored;
  published_colored.published = true;
  NativePageShellNotifyState animating = colored;
  animating.top_bar_color = TopBarPageColor(0xFF0F0F0Fu, 0xFF102030u);
  PARC_CHECK(!ShouldNotifyShellPayloadChange(published_colored, animating));
}

- (void)testClearingTheTopBarColorReachesTheShell {
  NativePageShellNotifyState colored = Colored();
  NativePageShellNotifyState published_colored = colored;
  published_colored.published = true;
  NativePageShellNotifyState cleared = published_colored;
  cleared.published = false;
  cleared.top_bar_color = TopBarPageColor(std::nullopt, std::nullopt);
  PARC_CHECK(ShouldNotifyShellPayloadChange(published_colored, cleared));
}

- (void)testAnEmptyBandSampleStillNotifies {
  const NativePageShellNotifyState published = Published();
  NativePageShellNotifyState sampled = Same();
  sampled.top_band_delivered = true;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published, sampled));
}

- (void)testTheFirstBandColorChangesThePayload {
  const NativePageShellNotifyState published = Published();
  NativePageShellNotifyState sampled = Same();
  sampled.top_band_delivered = true;
  sampled.top_band_color = 0xFF1A73E8u;
  PARC_CHECK(ShellNotifyPayloadChanged(published, sampled));
}

- (void)testARepeatedBandSampleSkipsDelivery {
  NativePageShellNotifyState sampled = Same();
  sampled.top_band_delivered = true;
  sampled.top_band_color = 0xFF1A73E8u;
  NativePageShellNotifyState published_sampled = sampled;
  published_sampled.published = true;
  PARC_CHECK(!ShouldNotifyShellPayloadChange(published_sampled, sampled));
}

- (void)testANewBandColorNotifies {
  NativePageShellNotifyState sampled = Same();
  sampled.top_band_delivered = true;
  sampled.top_band_color = 0xFF1A73E8u;
  NativePageShellNotifyState published_sampled = sampled;
  published_sampled.published = true;
  sampled.top_band_color = 0xFF000000u;
  PARC_CHECK(ShouldNotifyShellPayloadChange(published_sampled, sampled));
}

- (void)testANewBandHostNotifies {
  NativePageShellNotifyState sampled = Same();
  sampled.top_band_delivered = true;
  sampled.top_band_color = 0xFF1A73E8u;
  NativePageShellNotifyState published_sampled = sampled;
  published_sampled.published = true;
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
