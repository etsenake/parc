// Copyright 2026 Parc contributors.
#include "native_appkit_page.h"
#include "native_page_shell_notify.h"
#include "native_cast.h"
#include "cef/libcef/browser/parc_native/native_internal_urls.h"
#include "components/sessions/content/content_serialized_navigation_builder.h"
#include "components/sessions/content/session_tab_helper.h"
#include "components/sessions/core/serialized_navigation_entry.h"
#include "components/sessions/core/session_constants.h"
#include "content/public/browser/restore_type.h"
#include "content/public/browser/session_storage_namespace_handle.h"
#include "native_link_routing.h"

#include <algorithm>
#include <cfloat>
#include <cmath>
#include <cstdio>
#include <limits>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "base/apple/foundation_util.h"
#include "base/check.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_result_observer.h"
#include "base/command_line.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/pickle.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/supports_user_data.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/single_thread_task_runner.h"
#include "cef/libcef/browser/chrome/chrome_browser_host_impl.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/history/history_service_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ssl/chrome_security_state_util.h"
#include "components/security_state/core/security_state.h"
#include "base/functional/callback_helpers.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/web_contents_capability_type.h"
#include "content/public/common/content_features.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/sad_tab.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/vr/vr_tab_helper.h"
#include "components/performance_manager/public/decorators/page_live_state_decorator.h"
#include "components/performance_manager/public/graph/page_node.h"
#include "components/history/core/browser/history_service.h"
#include "components/history/core/browser/history_service_observer.h"
#include "components/history/core/browser/history_types.h"
#include "components/keyed_service/core/service_access_type.h"
#include "components/performance_manager/public/performance_manager.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/clear_site_data_utils.h"
#include "content/public/browser/media_session.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/page.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/favicon_status.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/favicon/core/favicon_driver_observer.h"
#include "content/browser/renderer_host/render_widget_host_impl.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/render_frame_metadata_provider.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/render_widget_host_observer.h"
#include "content/public/browser/storage_partition.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "mojo/public/cpp/bindings/associated_receiver.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "extensions/common/constants.h"
#include "native_appkit_host.h"
#include "native_chrome_platform_delegate.h"
#include "native_page_retirement.h"
#include "native_reader.h"
#include "native_confirm_infobars.h"
#include "net/base/net_errors.h"
#include "sad_tab.h"
#import "status_text.h"
#include "tab_transfer.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "third_party/blink/public/common/parc/top_band_color_sampling.h"
#include "third_party/blink/public/mojom/parc/top_band_color.mojom.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/accessibility/ax_tree_id.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/image/image.h"
#import "window_security_reservation.h"

@interface PCNativeFindResult ()
- (instancetype)initWithQuery:(NSString*)query revision:(NSUInteger)revision
                      matches:(NSInteger)matches ordinal:(NSInteger)ordinal
                  finalUpdate:(BOOL)finalUpdate;
@end
@implementation PCNativeFindResult
@synthesize query = _query, documentRevision = _documentRevision,
    numberOfMatches = _numberOfMatches, activeMatchOrdinal = _activeMatchOrdinal,
    finalUpdate = _finalUpdate;
- (instancetype)initWithQuery:(NSString*)query revision:(NSUInteger)revision
                      matches:(NSInteger)matches ordinal:(NSInteger)ordinal
                  finalUpdate:(BOOL)finalUpdate {
  if ((self = [super init])) {
    _query = [query copy]; _documentRevision = revision;
    _numberOfMatches = matches; _activeMatchOrdinal = ordinal;
    _finalUpdate = finalUpdate;
  }
  return self;
}
@end

@interface PCNativeCaptureState () {
 @public
  base::WeakPtr<content::WebContents> _contents;
  content::WeakDocumentPtr _document;
  NSWindow* __weak _parent;
  base::OnceClosure _stop_devices;
  base::OnceClosure _stop_sharing;
}
- (instancetype)initWithContents:(content::WebContents*)contents
                         window:(NSWindow*)window
                      indicator:(MediaStreamCaptureIndicator*)indicator;
@end

@implementation PCNativeCaptureState
@synthesize camera = _camera;
@synthesize microphone = _microphone;
@synthesize tab = _tab;
@synthesize window = _window;
@synthesize display = _display;
@synthesize mirrored = _mirrored;
@synthesize shared = _shared;
- (instancetype)initWithContents:(content::WebContents*)contents
                         window:(NSWindow*)window
                      indicator:(MediaStreamCaptureIndicator*)indicator {
  self = [super init];
  if (self) {
    _contents = contents->GetWeakPtr();
    _document = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    _parent = window;
    _camera = indicator->IsCapturingVideo(contents);
    _microphone = indicator->IsCapturingAudio(contents);
    _tab = indicator->IsCapturingTab(contents);
    _window = indicator->IsCapturingWindow(contents);
    _display = indicator->IsCapturingDisplay(contents);
    _mirrored = indicator->IsBeingMirrored(contents);
    _shared = indicator->IsBeingShared(contents);
    _stop_devices = indicator->CreateStopCallbackForCurrentStreams(
        contents, MediaStreamCaptureIndicator::kUserMedia);
    _stop_sharing = indicator->CreateStopCallbackForCurrentStreams(
        contents, MediaStreamCaptureIndicator::kDisplayMedia);
    auto stop_source = indicator->CreateStopCallbackForSharedTab(contents);
    if (_stop_sharing && stop_source) {
      _stop_sharing = std::move(_stop_sharing).Then(std::move(stop_source));
    } else if (stop_source) {
      _stop_sharing = std::move(stop_source);
    }
  }
  return self;
}
- (BOOL)active {
  return _camera || _microphone || _tab || _window || _display || _mirrored || _shared;
}
- (BOOL)canStopDevices { return !!_stop_devices; }
- (BOOL)canStopSharing { return !!_stop_sharing; }
@end

namespace parc {
class NativePageState;
namespace {
int PageToolCommand(PCNativePageTool tool) {
  switch (tool) {
    case PCNativePageToolDeveloperTools:
    case PCNativePageToolInspectElements:
    case PCNativePageToolJavaScriptConsole:
    case PCNativePageToolNetworkInspector:
      return IDC_DEV_TOOLS;
    case PCNativePageToolCast:
      return IDC_ROUTE_MEDIA;
    case PCNativePageToolTaskManager:
      return IDC_TASK_MANAGER_MAIN_MENU;
    case PCNativePageToolPrint:
      return IDC_PRINT;
    case PCNativePageToolSave:
      return IDC_SAVE_PAGE;
    case PCNativePageToolViewSource:
      return IDC_VIEW_SOURCE;
    case PCNativePageToolClearBrowsingData:
      return IDC_CLEAR_BROWSING_DATA;
    case PCNativePageToolClearCacheAndRefresh:
    case PCNativePageToolClearCookiesAndRefresh:
      //
      // Never substitute IDC_RELOAD_CLEARING_CACHE's whole-profile deletion.
      return IDC_RELOAD_BYPASSING_CACHE;
  }
  return 0;
}
struct PageRecord {
  PCNativePage* __strong page;
};
std::map<content::WebContents*, PageRecord>& Pages() {
  static base::NoDestructor<std::map<content::WebContents*, PageRecord>> value;
  return *value;
}
}  // namespace
}  // namespace parc

@interface PCNativePage ()
- (instancetype)initWithState:(std::shared_ptr<parc::NativePageState>)state;
- (std::shared_ptr<parc::NativePageState>)state;
@end

namespace parc {
namespace {
// Opt-in diagnostics of the actual primary widget only. Arrival at this
// observer is distinct from a renderer ACK; neither is proof that a DOM handler
// ran.
class NativePageInputDiagnostics final
    : public content::WebContentsObserver,
      public content::RenderWidgetHost::InputEventObserver,
      public content::RenderWidgetHostObserver {
 public:
  NativePageInputDiagnostics(content::WebContents& contents, NSView* view)
      : content::WebContentsObserver(&contents), view_(view) {
    // Constructed only on the browser UI thread.
    static uint64_t next_page = 0;
    page_ = ++next_page;
    BindPrimaryWidget();
  }
  ~NativePageInputDiagnostics() override { ResetWidget(); }

 private:
  void ResetWidget() {
    input_observation_.Reset();
    widget_observation_.Reset();
  }
  void BindPrimaryWidget() {
    auto* frame =
        web_contents() ? web_contents()->GetPrimaryMainFrame() : nullptr;
    auto* widget = frame ? frame->GetRenderWidgetHost() : nullptr;
    const auto id =
        frame ? frame->GetGlobalId() : content::GlobalRenderFrameHostId();
    const std::string tree = frame ? frame->GetAXTreeID().ToString() : "none";
    const bool changed = widget_observation_.GetSource() != widget ||
                         frame_ != id || tree_ != tree;
    if (widget_observation_.GetSource() != widget) {
      ResetWidget();
      if (widget) {
        widget_observation_.Observe(widget);
        input_observation_.Observe(widget);
      }
    }
    frame_ = id;
    tree_ = tree;
    widget_process_ = widget ? widget->GetProcess()->GetID().value() : -1;
    widget_route_ = widget ? widget->GetRoutingID() : -1;
    if (changed) {
      Log("map", nullptr, -1, -1);
    }
  }
  void Log(const char* phase,
           const blink::WebInputEvent* event,
           int source,
           int state) const {
    fprintf(stderr,
            "[ParcInput] layer=native-page phase=%s page=%llu "
            "frame_process=%d frame_route=%d tree=%s widget_process=%d "
            "widget_route=%d window=%ld event_type=%d event_us=%lld "
            "source=%d ack_state=%d\n",
            phase, static_cast<unsigned long long>(page_),
            frame_.child_id.value(), frame_.frame_routing_id, tree_.c_str(),
            widget_process_, widget_route_,
            static_cast<long>(view_.window.windowNumber),
            event ? static_cast<int>(event->GetType()) : -1,
            event ? static_cast<long long>(
                        event->TimeStamp().since_origin().InMicroseconds())
                  : 0,
            source, state);
  }
  void OnInputEvent(const content::RenderWidgetHost& host,
                    const blink::WebInputEvent& event,
                    InputEventSource source) override {
    if (&host == widget_observation_.GetSource()) {
      Log("input-arrival", &event, static_cast<int>(source), -1);
    }
  }
  void OnInputEventAck(const content::RenderWidgetHost& host,
                       blink::mojom::InputEventResultSource source,
                       blink::mojom::InputEventResultState state,
                       const blink::WebInputEvent& event) override {
    if (&host == widget_observation_.GetSource()) {
      Log("input-ack", &event, static_cast<int>(source),
          static_cast<int>(state));
    }
  }
  void RenderFrameCreated(content::RenderFrameHost* frame) override {
    if (web_contents() && frame == web_contents()->GetPrimaryMainFrame()) {
      BindPrimaryWidget();
    }
  }
  void RenderFrameHostChanged(content::RenderFrameHost*,
                              content::RenderFrameHost* frame) override {
    if (web_contents() && frame == web_contents()->GetPrimaryMainFrame()) {
      BindPrimaryWidget();
    }
  }
  void PrimaryPageChanged(content::Page&) override { BindPrimaryWidget(); }
  void RenderWidgetHostDestroyed(content::RenderWidgetHost* widget) override {
    if (widget == widget_observation_.GetSource()) {
      Log("widget-destroyed", nullptr, -1, -1);
      ResetWidget();
    }
  }
  void WebContentsDestroyed() override {
    Log("page-destroyed", nullptr, -1, -1);
    ResetWidget();
    Observe(nullptr);
  }
  NSView* __weak view_;
  uint64_t page_ = 0;
  content::GlobalRenderFrameHostId frame_;
  std::string tree_;
  int widget_process_ = -1;
  int widget_route_ = -1;
  base::ScopedObservation<content::RenderWidgetHost,
                          content::RenderWidgetHost::InputEventObserver>
      input_observation_{this};
  base::ScopedObservation<content::RenderWidgetHost,
                          content::RenderWidgetHostObserver>
      widget_observation_{this};
};

//
// the primary main frame's TopBandColorTracker, copies the composited frame's
// top band when the renderer cannot tell the colour, and reports changes.
class TopBandColorSampler final : public mojom::TopBandColorObserver {
 public:
  explicit TopBandColorSampler(base::RepeatingClosure changed)
      : changed_(std::move(changed)) {}

  // A new primary main document. The renderer's tracker lives as long as its
  // LocalFrame, so only a new renderer frame (`rebind`) needs a new channel.
  void Bind(content::RenderFrameHost* frame, bool rebind) {
    delivery_.Reset();
    delivered_ = false;
    color_.reset();
    crossfade_ = false;
    host_.clear();
    // A copy for the previous document must not deliver into this one.
    weak_factory_.InvalidateWeakPtrs();
    const auto id =
        frame ? frame->GetGlobalId() : content::GlobalRenderFrameHostId();
    if (!rebind && id == frame_ && agent_.is_bound()) {
      return;
    }
    receiver_.reset();
    agent_.reset();
    frame_ = id;
    if (!frame || !frame->IsRenderFrameLive()) {
      return;
    }
    frame->GetRemoteAssociatedInterfaces()->GetInterface(&agent_);
    agent_->SetObserver(receiver_.BindNewEndpointAndPassRemote());
  }
  bool delivered() const { return delivered_; }
  std::optional<uint32_t> color() const { return color_; }
  bool crossfade() const { return crossfade_; }
  // The host of the document that produced the delivered colour.
  const std::string& host() const { return host_; }

 private:
  void DidSampleTopBandColor(uint32_t color,
                             bool has_color,
                             bool sample_frame,
                             int64_t frame_sample_id,
                             bool reuse_frame_sample,
                             bool crossfade) override {
    Apply(delivery_.OnRendererSample(
        has_color ? std::optional<uint32_t>(color) : std::nullopt,
        sample_frame, frame_sample_id, reuse_frame_sample, crossfade));
  }
  void Apply(const top_band::FrameSampleDelivery::Action& action) {
    if (action.copy) {
      CopyFrame(*action.copy);
    }
    if (action.deliver) {
      auto* frame = content::RenderFrameHost::FromID(frame_);
      delivered_ = true;
      color_ = action.deliver->color;
      crossfade_ = action.deliver->crossfade;
      const GURL& url =
          frame ? frame->GetLastCommittedURL() : GURL::EmptyGURL();
      host_ = std::string(top_band::CacheHost(url.scheme(), url.host()));
      changed_.Run();
    }
  }
  // 0x40c0230: the view's top kBandRows DIP at full resolution.
  void CopyFrame(int64_t id) {
    auto* frame = content::RenderFrameHost::FromID(frame_);
    auto* view = frame ? frame->GetView() : nullptr;
    const gfx::Rect bounds = view ? view->GetViewBounds() : gfx::Rect();
    if (!view || bounds.width() < 1 || !view->IsSurfaceAvailableForCopy()) {
      delivery_.CopyUnavailable();
      return;
    }
    view->CopyFromSurface(
        gfx::Rect(0, 0, bounds.width(), top_band::kBandRows), gfx::Size(),
        base::TimeDelta(),
        base::BindOnce(&TopBandColorSampler::DidCopyFrame,
                       weak_factory_.GetWeakPtr(), id,
                       view->GetDeviceScaleFactor()));
  }
  // 0x40c04bc: the band's rows and right margin scale with the display.
  void DidCopyFrame(int64_t id,
                    float scale,
                    const content::CopyFromSurfaceResult& result) {
    std::optional<uint32_t> color;
    if (result.has_value() && !result->bitmap.drawsNothing()) {
      const SkBitmap& bitmap = result->bitmap;
      const int rows =
          std::max(1, static_cast<int>(std::round(top_band::kBandRows * scale)));
      const int margin =
          static_cast<int>(std::round(top_band::kRightMargin * scale));
      color = top_band::SampleBand(
          bitmap.width(), bitmap.height(), rows, margin,
          [&bitmap](int x, int y) { return bitmap.getColor(x, y); });
    }
    Apply(delivery_.OnFrameSample(id, color));
  }

  base::RepeatingClosure changed_;
  content::GlobalRenderFrameHostId frame_;
  mojo::AssociatedRemote<mojom::TopBandColorAgent> agent_;
  mojo::AssociatedReceiver<mojom::TopBandColorObserver> receiver_{this};
  top_band::FrameSampleDelivery delivery_;
  bool delivered_ = false;
  std::optional<uint32_t> color_;
  bool crossfade_ = false;
  std::string host_;
  base::WeakPtrFactory<TopBandColorSampler> weak_factory_{this};
};

// Tells the shell about a profile's history deletions (Clear Browsing Data,
// history removal), so caches keyed by site, such as the top bar's colours,
// forget them, and the shell's own visits follow Chromium's history: the
// profile's path, the URLs removed outright and a time range's URLs, if any,
// come with the hosts. Old history expiring is not a deletion. One per
// regular profile, created with its first page.
class HistoryDeletionNotifier final : public base::SupportsUserData::Data,
                                      public history::HistoryServiceObserver {
 public:
  static void EnsureFor(Profile& profile) {
    if (profile.IsOffTheRecord() || profile.GetUserData(UserDataKey())) {
      return;
    }
    auto* service = HistoryServiceFactory::GetForProfile(
        &profile, ServiceAccessType::EXPLICIT_ACCESS);
    if (!service) {
      return;
    }
    profile.SetUserData(UserDataKey(), std::make_unique<HistoryDeletionNotifier>(
                                           *service, profile.GetPath()));
  }
  HistoryDeletionNotifier(history::HistoryService& service,
                          base::FilePath profile_path)
      : profile_path_(std::move(profile_path)) {
    observation_.Observe(&service);
  }

 private:
  static const void* UserDataKey() {
    static const char key = 0;
    return &key;
  }
  void OnHistoryDeletions(history::HistoryService*,
                          const history::DeletionInfo& info) override {
    if (info.is_from_expiration()) {
      return;
    }
    std::set<std::string> deleted_hosts;
    NSMutableArray<NSString*>* urls = [NSMutableArray array];
    if (!info.IsAllHistory()) {
      for (const auto& row : info.deleted_rows()) {
        [urls addObject:base::SysUTF8ToNSString(row.url().spec())];
        if (!row.url().host().empty()) {
          deleted_hosts.emplace(row.url().host());
        }
      }
    }
    NSMutableArray<NSString*>* hosts =
        [NSMutableArray arrayWithCapacity:deleted_hosts.size()];
    for (const std::string& host : deleted_hosts) {
      [hosts addObject:base::SysUTF8ToNSString(host)];
    }
    const auto& range = info.time_range();
    // An empty or absent restriction means every URL in the range.
    NSMutableArray<NSString*>* range_urls = nil;
    if (range.IsValid() && info.restrict_urls().has_value() &&
        !info.restrict_urls()->empty()) {
      range_urls = [NSMutableArray array];
      for (const GURL& url : *info.restrict_urls()) {
        [range_urls addObject:base::SysUTF8ToNSString(url.spec())];
      }
    }
    NSMutableDictionary* details = [@{
      @"profilePath" : base::SysUTF8ToNSString(profile_path_.value()),
      @"allHistory" : @(info.IsAllHistory()),
      @"urls" : [urls copy],
      @"hosts" : [hosts copy],
      @"begin" : @(range.IsValid() && !range.begin().is_null()
                       ? range.begin().ToNSDate().timeIntervalSinceReferenceDate
                       : -DBL_MAX),
      @"end" : @(range.IsValid() && !range.end().is_null() &&
                         !range.end().is_max()
                     ? range.end().ToNSDate().timeIntervalSinceReferenceDate
                     : DBL_MAX),
      @"timeRange" : @(range.IsValid()),
    } mutableCopy];
    if (range_urls) {
      details[@"restrictURLs"] = [range_urls copy];
    }
    NSDictionary* user_info = [details copy];
    // Never call the shell from the history service's notification stack.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(^{
          [NSNotificationCenter.defaultCenter
              postNotificationName:@"PCNativeHistoryDidDeleteNotification"
                            object:nil
                          userInfo:user_info];
        }));
  }
  void HistoryServiceBeingDeleted(history::HistoryService*) override {
    observation_.Reset();
  }
  const base::FilePath profile_path_;
  base::ScopedObservation<history::HistoryService,
                          history::HistoryServiceObserver>
      observation_{this};
};
}  // namespace
class NativePageState final
    : public content::WebContentsObserver,
      public MediaStreamCaptureIndicator::Observer,
      public favicon::FaviconDriverObserver,
      public find_in_page::FindResultObserver,
      public std::enable_shared_from_this<NativePageState> {
 public:
  NativePageState(content::WebContents& contents,
                  NativeChromePlatformDelegate& platform,
                  NSString* path)
      : content::WebContentsObserver(&contents),
        contents_(contents.GetWeakPtr()),
        host_(ChromeBrowserHostImpl::GetBrowserForContents(&contents)),
        page_view_(platform.GetNativePageView().GetNativeNSView()),
        identifier_([NSUUID UUID].UUIDString),
        profile_path_([path copy]) {
    CHECK(NSThread.isMainThread);
    CHECK(host_);
    CHECK(page_view_);
    EnableNativeLinkNavigation(contents);
    capture_indicator_ = MediaCaptureDevicesDispatcher::GetInstance()
                             ->GetMediaStreamCaptureIndicator();
    capture_observation_.Observe(capture_indicator_.get());
    ObserveFavicon();
    if (base::CommandLine::ForCurrentProcess()->HasSwitch(
            "parc-input-diagnostics")) {
      input_diagnostics_ =
          std::make_unique<NativePageInputDiagnostics>(contents, page_view_);
    }
    top_band_ = std::make_unique<TopBandColorSampler>(base::BindRepeating(
        &NativePageState::TopBandColorChanged, base::Unretained(this)));
    top_band_->Bind(contents.GetPrimaryMainFrame(), /*rebind=*/true);
    if (auto* profile = Profile::FromBrowserContext(contents.GetBrowserContext())) {
      HistoryDeletionNotifier::EnsureFor(*profile);
    }
  }
  ~NativePageState() override {
    find_observation_.Reset();
    favicon_observation_.Reset();
    capture_observation_.Reset();
  }
  PCNativeCaptureState* CaptureState() const {
    if (!contents_ || contents_->IsBeingDestroyed() ||
        !contents_->GetPrimaryMainFrame()) {
      return nil;
    }
    return [[PCNativeCaptureState alloc] initWithContents:contents_.get()
                                                  window:page_view_.window
                                               indicator:capture_indicator_.get()];
  }
  bool StopCapture(PCNativeCaptureState* snapshot, bool sharing) {
    CHECK(NSThread.isMainThread);
    auto* contents = contents_.get();
    NSWindow* parent = snapshot ? snapshot->_parent : nil;
    if (!snapshot || !contents || contents->IsBeingDestroyed() ||
        snapshot->_contents.get() != contents || !parent ||
        parent != page_view_.window || !parent.visible || parent.attachedSheet ||
        snapshot->_document.AsRenderFrameHostIfValid() !=
            contents->GetPrimaryMainFrame() || IsNativePageRetiring(page_) ||
        IsLiveTabTransferTarget(contents)) {
      return false;
    }
    auto stop = sharing ? std::move(snapshot->_stop_sharing)
                        : std::move(snapshot->_stop_devices);
    if (!stop) {
      return false;
    }
    auto keep_alive = shared_from_this();
    // Runs only captured stream IDs. Never obtains a fresh callback after a
    // menu has opened, and never stops managed all-screens capture.
    std::move(stop).Run();
    Notify();
    return true;
  }
  void SetPage(PCNativePage* page) {
    page_ = page;
    std::weak_ptr<NativePageState> weak = shared_from_this();
    reader_ = std::make_unique<NativeReader>(*contents_, base::BindRepeating(^{
      auto state = weak.lock();
      if (!state) {
        return;
      }
      if (state->reader_ && state->PageToolBrowser()) {
        if (state->reader_->mode() == NativeReader::Mode::kDistilling) {
          [state->status_text_ updateText:@"Preparing Reader…"];
        } else if (!state->reader_->message().empty()) {
          [state->status_text_
              updateText:base::SysUTF8ToNSString(state->reader_->message())];
        } else {
          [state->status_text_ reset];
        }
      }
      if (!ShouldNotifyShellPayloadChange(state->last_shell_notify_,
                                          state->CurrentShellNotifyState())) {
        return;
      }
      state->Notify();
    }));
    status_text_ = [[PCNativeStatusTextController alloc]
        initWithPage:page_view_
            validate:^BOOL {
              auto state = weak.lock();
              auto* contents = state ? state->contents() : nullptr;
              return contents &&
                     contents->GetVisibility() == content::Visibility::VISIBLE;
            }];
    //
    //
    //
    // own routes differ for Option: Shift-Option opens a window and Option
    // reaches no split route, so neither explains a split.
    status_text_.linkOutcome = ^PCNativeStatusLinkOutcome(NSEventModifierFlags flags, NSURL* url) {
      auto state = weak.lock();
      if (!state || !state->host_ || !state->host_->browser())
        return PCNativeStatusLinkOutcomeNone;
      constexpr NSEventModifierFlags shift = NSEventModifierFlagShift;
      constexpr NSEventModifierFlags command = NSEventModifierFlagCommand;
      if (flags == command) return PCNativeStatusLinkOutcomeNewBackgroundTab;
      if (flags == (shift | command)) return PCNativeStatusLinkOutcomeNewForegroundTab;
      if (flags == (shift | NSEventModifierFlagOption)) return PCNativeStatusLinkOutcomeNewWindow;
      if (flags != shift) return PCNativeStatusLinkOutcomeNone;
      PCNativePage* source = state->page_;
      if (!source || source.peekParentPage) return PCNativeStatusLinkOutcomeNewWindow;
      // Parc's Shift route admits only HTTP(S) into a presentable Peek
      // (native_link_routing.mm); otherwise the click opens a window.
      NSString* scheme = url.scheme.lowercaseString;
      if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])
        return PCNativeStatusLinkOutcomeNewWindow;
      PCNativeBrowserWindow* binding = AppKitBindingForBrowser(state->host_->browser());
      id<PCNativeBrowserWindowClient> client = binding.client;
      return [client respondsToSelector:@selector(nativeBrowser:allowsPeekWithShift:)] &&
              [client respondsToSelector:@selector(nativeBrowser:canPresentPeekFrom:)] &&
              [client nativeBrowser:binding allowsPeekWithShift:YES] &&
              [client nativeBrowser:binding canPresentPeekFrom:source]
          ? PCNativeStatusLinkOutcomePeek : PCNativeStatusLinkOutcomeNewWindow;
    };
  }
  void PrepareFind(NSString* text) {
    CHECK(NSThread.isMainThread);
    auto* contents = contents_.get();
    auto* frame = contents ? contents->GetPrimaryMainFrame() : nullptr;
    auto* helper = contents ? find_in_page::FindTabHelper::FromWebContents(contents) : nullptr;
    if (!frame || !helper) return;
    if (!find_observation_.IsObserving()) find_observation_.Observe(helper);
    NSString* query = [text stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    if (find_document_.AsRenderFrameHostIfValid() != frame ||
        ![find_query_ isEqualToString:query]) {
      find_result_ = nil;
      find_query_ = [query copy];
      find_document_ = frame->GetWeakDocumentPtr();
      find_revision_ = reader_->revision();
      PostFindChange();
    }
  }
  void ClearFind() {
    find_document_ = content::WeakDocumentPtr();
    find_query_ = nil; find_result_ = nil;
    PostFindChange();
  }
  PCNativeFindResult* FindResult() const {
    auto* contents = contents_.get();
    return contents && !contents->IsBeingDestroyed() && !closing_ &&
        find_document_.AsRenderFrameHostIfValid() == contents->GetPrimaryMainFrame() &&
        reader_ && reader_->revision() == find_revision_ ? find_result_ : nil;
  }
  void SetStatusText(NSString* text) { [status_text_ updateText:text]; }
  void SetStatusAttached(bool attached) { [status_text_ setAttached:attached]; }
  content::WebContents* contents() const { return contents_.get(); }
  CefRefPtr<ChromeBrowserHostImpl> host() const { return host_; }
  NSView* view() const { return page_view_; }
  NSString* identifier() const { return identifier_; }
  NSString* path() const { return profile_path_; }
  bool embedded() const { return embedded_; }
  void MarkEmbedded() {
    CHECK(!embedded_);
    embedded_ = true;
    auto* session = sessions::SessionTabHelper::FromWebContents(contents_.get());
    CHECK(session);
    session->OmitFromSessionRestore();
    contents_->GetController().GetDefaultSessionStorageNamespace()->SetShouldPersist(false);
    auto* browser = host_->browser();
    embedded_browser_ = browser->GetWeakPtr();
    embedded_profile_ = browser->GetProfile()->GetWeakPtr();
    embedded_window_ = AppKitBindingForBrowser(browser).window;
  }
  bool RebindEmbeddedForTransfer(BrowserWindowInterface& expected,
                                 BrowserWindowInterface& destination) {
    auto* contents = contents_.get();
    auto* tab = contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
    PCNativeBrowserWindow* binding = AppKitBindingForBrowser(&destination);
    if (!embedded_ || closing_ || !contents || contents->IsBeingDestroyed() ||
        !IsLiveTabTransferTarget(contents) || !embedded_profile_ ||
        embedded_profile_->ShutdownStarted() || expected.IsDeleteScheduled() ||
        destination.IsDeleteScheduled() || expected.GetProfile() != embedded_profile_.get() ||
        destination.GetProfile() != embedded_profile_.get() || !binding.window ||
        !binding.client || !AppKitBrowserAcceptsNewPages(destination) || !host_ ||
        host_->browser() != &destination || !tab ||
        tab->GetBrowserWindowInterface() != &destination ||
        destination.GetTabStripModel()->GetIndexOfTab(tab) == TabStripModel::kNoTab) {
      return false;
    }
    // Rollback/reattachment may revisit an owner already established by this
    // transaction. An unrelated native move never acquires this capability.
    if (embedded_browser_.get() == &destination) return EmbeddedOwnerValid();
    if (embedded_browser_.get() != &expected || !embedded_window_ ||
        AppKitBindingForBrowser(&expected).window != embedded_window_) return false;
    embedded_browser_ = destination.GetWeakPtr();
    embedded_window_ = binding.window;
    return EmbeddedOwnerValid();
  }
  bool EmbeddedOwnerValid() const {
    auto* contents = contents_.get();
    auto* browser = embedded_browser_.get();
    auto* tab = contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
    PCNativeBrowserWindow* binding = browser ? AppKitBindingForBrowser(browser) : nil;
    return embedded_ && contents && browser && embedded_profile_ &&
        !embedded_profile_->ShutdownStarted() && browser->GetProfile() == embedded_profile_.get() &&
        embedded_window_ && binding.window == embedded_window_ && binding.client &&
        host_ && host_->browser() == browser && tab &&
        tab->GetBrowserWindowInterface() == browser &&
        browser->GetTabStripModel()->GetIndexOfTab(tab) != TabStripModel::kNoTab;
  }
  NativePageShellNotifyState CurrentShellNotifyState() const {
    NativePageShellNotifyState state;
    auto* contents = contents_.get();
    if (!contents) {
      return state;
    }
    const GURL visible =
        reader_ ? reader_->DisplayURL() : contents->GetVisibleURL();
    state.url = PublicInternalURL(visible).spec();
    state.title = contents->GetTitle();
    state.loading = contents->IsLoading();
    state.can_go_back = contents->GetController().CanGoBack();
    state.can_go_forward = contents->GetController().CanGoForward();
    state.top_bar_color = TopBarPageColor(contents->GetThemeColor(),
                                          contents->GetBackgroundColor());
    if (top_band_) {
      state.top_band_delivered = top_band_->delivered();
      state.top_band_color = top_band_->color();
      state.top_band_host = top_band_->host();
    }
    if (reader_) {
      state.reader_mode = static_cast<uint8_t>(reader_->mode());
      state.reader_revision = reader_->revision();
    }
    if (capture_indicator_) {
      state.capture_camera = capture_indicator_->IsCapturingVideo(contents);
      state.capture_microphone = capture_indicator_->IsCapturingAudio(contents);
      state.capture_tab = capture_indicator_->IsCapturingTab(contents);
      state.capture_window = capture_indicator_->IsCapturingWindow(contents);
      state.capture_display = capture_indicator_->IsCapturingDisplay(contents);
      state.capture_mirrored = capture_indicator_->IsBeingMirrored(contents);
      state.capture_shared = capture_indicator_->IsBeingShared(contents);
    }
    return state;
  }
  void Notify() { PostNotification(nil); }
  Browser* PageToolBrowser(bool require_interaction = true,
                           bool require_live_renderer = true) const {
    CHECK(NSThread.isMainThread);
    auto* contents = contents_.get();
    auto* browser = host_ ? host_->browser() : nullptr;
    auto* platform = host_ ? host_->platform_delegate() : nullptr;
    NSWindow* window = page_view_.window;
    if (closing_ || (embedded_ && !EmbeddedOwnerValid()) || !contents || contents->IsBeingDestroyed() ||
        (require_live_renderer &&
         (contents->IsCrashed() || !contents->GetPrimaryMainFrame() ||
          !contents->GetPrimaryMainFrame()->IsRenderFrameLive())) || !browser ||
        !platform || !platform->native_route() || !window ||
        (require_interaction &&
         (!window.keyWindow || !window.visible || window.miniaturized ||
          page_view_.hiddenOrHasHiddenAncestor)) ||
        window.attachedSheet || !AppKitBrowserAcceptsNewPages(*browser) ||
        IsNativePageRetiring(page_) || IsLiveTabTransferTarget(contents) ||
        browser->tab_strip_model()->GetActiveWebContents() != contents ||
        !static_cast<NativeChromePlatformDelegate*>(platform)
             ->HasAttachedPage()) {
      return nullptr;
    }
    PCNativeBrowserWindow* binding = AppKitBindingForBrowser(browser);
    if (!binding || binding.window != window ||
        [binding.client selectedNativePage] != page_) {
      return nullptr;
    }
    return browser;
  }
  bool CanPerformPageTool(PCNativePageTool tool) const {
    // The task manager is how a hung or crashed page is ended.
    auto* browser = PageToolBrowser(tool != PCNativePageToolCast,
                                    tool != PCNativePageToolTaskManager);
    const int command = PageToolCommand(tool);
    if (!browser || !command || !chrome::IsCommandEnabled(browser, command)) {
      return false;
    }
    switch (tool) {
      case PCNativePageToolDeveloperTools:
      case PCNativePageToolInspectElements:
      case PCNativePageToolJavaScriptConsole:
      case PCNativePageToolNetworkInspector:
        return DevToolsWindow::AllowDevToolsFor(browser->GetProfile(), contents());
      case PCNativePageToolCast:
        return CanShowNativeCast(contents());
      case PCNativePageToolTaskManager:
        return true;
      case PCNativePageToolPrint:
        return chrome::CanPrint(browser);
      case PCNativePageToolSave:
        return chrome::CanSavePage(browser);
      case PCNativePageToolViewSource:
        return chrome::CanViewSource(browser) &&
               DevToolsWindow::AllowDevToolsFor(browser->GetProfile(),
                                                contents());
      case PCNativePageToolClearBrowsingData:
        // The real command retains policy and the special private-profile UI.
        return true;
      case PCNativePageToolClearCacheAndRefresh:
      case PCNativePageToolClearCookiesAndRefresh:
        return !clearing_site_data_ && chrome::CanReload(browser) &&
               !contents()->GetController().GetPendingEntry() &&
               contents()->GetLastCommittedURL().SchemeIsHTTPOrHTTPS() &&
               !contents()
                    ->GetPrimaryMainFrame()
                    ->GetLastCommittedOrigin()
                    .opaque();
    }
    return false;
  }
  bool PerformPageTool(PCNativePageTool tool) {
    auto keep_alive = shared_from_this();
    if (!CanPerformPageTool(tool)) {
      return false;
    }
    if (tool == PCNativePageToolCast) {
      return ShowNativeCast(contents());
    }
    if (tool == PCNativePageToolDeveloperTools ||
        tool == PCNativePageToolInspectElements ||
        tool == PCNativePageToolJavaScriptConsole ||
        tool == PCNativePageToolNetworkInspector) {
      auto* target = contents();
      const auto document = target->GetPrimaryMainFrame()->GetWeakDocumentPtr();
      const uint64_t generation = event_generation_;
      __weak NSWindow* original_window = page_view_.window;
      std::weak_ptr<NativePageState> weak = weak_from_this();
      const auto action = tool == PCNativePageToolInspectElements
          ? DevToolsToggleAction::Inspect()
          : tool == PCNativePageToolJavaScriptConsole
                ? DevToolsToggleAction::ShowNativePanel("console")
                : tool == PCNativePageToolNetworkInspector
                      ? DevToolsToggleAction::ShowNativePanel("network")
                      : DevToolsToggleAction::Show();
      return DevToolsWindow::PerformNativePageAction(
          target, action,
          base::BindRepeating(
              [](std::weak_ptr<NativePageState> weak,
                 content::WeakDocumentPtr document, uint64_t generation,
                 __weak NSWindow* original_window, PCNativePageTool tool) {
                auto state = weak.lock();
                return state && document.AsRenderFrameHostIfValid() &&
                    state->event_generation_ == generation && original_window &&
                    state->page_view_.window == original_window &&
                    state->CanPerformPageTool(tool);
              }, weak, document, generation, original_window, tool));
    }
    if (tool == PCNativePageToolClearCookiesAndRefresh) {
      return ClearSiteDataAndRefresh();
    }
    auto* browser = PageToolBrowser(true, tool != PCNativePageToolTaskManager);
    // Commands run synchronously on the UI thread. Their actual controllers
    // own asynchronous preview, save chooser, cancellation and document life.
    // The source command retains Chromium's original navigation entry/POST
    // handling; constructing a view-source URL here would lose that behavior.
    return browser && chrome::ExecuteCommand(browser, PageToolCommand(tool));
  }
  bool ClearSiteDataAndRefresh() {
    auto* contents = contents_.get();
    auto* frame = contents ? contents->GetPrimaryMainFrame() : nullptr;
    if (!frame || !CanPerformPageTool(PCNativePageToolClearCookiesAndRefresh)) {
      return false;
    }
    const auto document = frame->GetWeakDocumentPtr();
    const auto storage_key = frame->GetStorageKey();
    const auto origin = frame->GetLastCommittedOrigin();
    const uint64_t generation = event_generation_;
    __weak NSWindow* original_window = page_view_.window;
    std::weak_ptr<NativePageState> weak = weak_from_this();
    clearing_site_data_ = true;
    [status_text_ updateText:@"Clearing site data…"];
    Notify();
    //
    // Keep current Chromium's real origin/domain, partition and storage-key
    // semantics. This is site data only, not history, passwords or permissions.
    content::ClearSiteData(
        contents->GetBrowserContext()->GetWeakPtr(),
        frame->GetStoragePartition()->GetConfig(), origin,
        content::ClearSiteDataTypeSet::All(), {},
        /*avoid_closing_connections=*/false, storage_key.ToCookiePartitionKey(),
        storage_key, /*partitioned_state_allowed_only=*/false, base::BindOnce(^{
          // Leave the remover's observer stack before notifying or reloading.
          // The deletion already authorized by the user's action cannot be
          // undone by navigation; only the follow-up reload is cancellable.
          base::SingleThreadTaskRunner::GetCurrentDefault()
              ->PostNonNestableTask(
                  FROM_HERE, base::BindOnce(^{
                    auto state = weak.lock();
                    if (!state) {
                      return;
                    }
                    state->clearing_site_data_ = false;
                    state->Notify();
                    NSWindow* window = original_window;
                    auto* live_contents = state->contents();
                    if (!live_contents || !window ||
                        state->event_generation_ != generation ||
                        document.AsRenderFrameHostIfValid() !=
                            live_contents->GetPrimaryMainFrame() ||
                        state->page_view_.window != window ||
                        !state->PageToolBrowser(
                            /*require_interaction=*/false)) {
                      return;
                    }
                    [state->status_text_ reset];
                    // Chromium's ClearSiteData completion means work finished;
                    // its API does not return a per-type success mask. Do not
                    // invent one.
                    live_contents->GetController().Reload(
                        content::ReloadType::BYPASSING_CACHE,
                        /*check_for_repost=*/false);
                  }));
        }));
    return true;
  }
  NativeReader* reader() const { return reader_.get(); }
  const TopBandColorSampler* top_band() const { return top_band_.get(); }
  bool CanToggleReaderMode() const {
    return PageToolBrowser() && reader_ && reader_->CanToggle();
  }
  bool ToggleReaderMode() {
    if (!CanToggleReaderMode()) {
      return false;
    }
    auto keep_alive = shared_from_this();
    std::weak_ptr<NativePageState> weak = weak_from_this();
    __weak NSWindow* original_window = page_view_.window;
    return reader_->Toggle(base::BindRepeating(^bool {
      auto state = weak.lock();
      NSWindow* window = original_window;
      return state && window && state->page_view_.window == window &&
             state->PageToolBrowser();
    }));
  }
  void RequestCrashFocus(PCNativeRendererCrash* snapshot) {
    __weak PCNativePage* weak_page = page_;
    __weak id<PCNativePageObserver> weak_observer = page_.observer;
    std::weak_ptr<NativePageState> weak = weak_from_this();
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(^{
          auto state = weak.lock();
          PCNativePage* page = weak_page;
          id<PCNativePageObserver> observer = weak_observer;
          if (!state || !state->contents_ || !page || !observer ||
              state->page_ != page || page.observer != observer ||
              NativeRendererCrash(state->contents()) != snapshot ||
              ![observer respondsToSelector:@selector
                         (nativePage:requestFocusForRendererCrash:)]) {
            return;
          }
          [observer nativePage:page requestFocusForRendererCrash:snapshot];
        }));
  }
  void Close(void (^completion)(PCNativePageCloseResult)) {
    CHECK(NSThread.isMainThread);
    if (!contents_) {
      completion(PCNativePageCloseResultClosed);
      return;
    }
    if (IsNativePageRetiring(page_) ||
        IsLiveTabTransferTarget(contents_.get())) {
      completion(PCNativePageCloseResultCancelled);
      return;
    }
    close_callbacks_.push_back([completion copy]);
    if (closing_) {
      return;
    }
    closing_ = true;
    reader_->Cancel();
    // A retained state survives synchronous beforeunload/observer reentry.
    auto keep_alive = shared_from_this();
    auto host = host_;
    host->CloseBrowser(false);
  }
  void CancelClose() {
    if (!closing_) {
      return;
    }
    closing_ = false;
    auto callbacks = std::move(close_callbacks_);
    close_callbacks_.clear();
    for (auto callback : callbacks) {
      callback(PCNativePageCloseResultCancelled);
    }
  }
  void SetClosed(base::OnceClosure callback) { closed_ = std::move(callback); }

 private:
  void PostFindChange() {
    if (find_notification_queued_) return;
    find_notification_queued_ = true;
    std::weak_ptr<NativePageState> weak = weak_from_this();
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce([](std::weak_ptr<NativePageState> weak) {
          auto state = weak.lock();
          if (!state) return;
          state->find_notification_queued_ = false;
          PCNativePage* page = state->page_;
          if (page) {
            [NSNotificationCenter.defaultCenter
                postNotificationName:PCNativePage.findResultDidChangeNotification
                              object:page];
          }
        }, weak));
  }
  void OnFindResultAvailable(content::WebContents* contents) override {
    auto* helper = find_observation_.GetSource();
    if (!helper || contents != contents_.get() || contents->IsBeingDestroyed() ||
        find_document_.AsRenderFrameHostIfValid() != contents->GetPrimaryMainFrame() ||
        !reader_ || reader_->revision() != find_revision_ || !find_query_.length ||
        base::SysNSStringToUTF16(find_query_) != helper->find_text()) return;
    const auto& result = helper->find_result();
    find_result_ = [[PCNativeFindResult alloc]
        initWithQuery:find_query_ revision:find_revision_
        matches:result.number_of_matches() ordinal:result.active_match_ordinal()
        finalUpdate:result.final_update()];
    // Never re-enter the observer list or the shell from Chromium's delivery.
    PostFindChange();
  }
  void OnFindEmptyText(content::WebContents* contents) override {
    if (contents == contents_.get()) ClearFind();
  }
  void OnFindTabHelperDestroyed(find_in_page::FindTabHelper* helper) override {
    if (helper == find_observation_.GetSource()) {
      find_observation_.Reset(); ClearFind();
    }
  }
  void ObserveFavicon() {
    if (!favicon_observation_.IsObserving() && contents_) {
      if (auto* driver = favicon::ContentFaviconDriver::FromWebContents(contents_.get()))
        favicon_observation_.Observe(driver);
    }
  }
  void OnFaviconUpdated(favicon::FaviconDriver* driver,
                       NotificationIconType type, const GURL&, bool,
                       const gfx::Image&) override {
    if (driver == favicon_observation_.GetSource() &&
        type == NON_TOUCH_16_DIP) {
      // Re-read the current original page after leaving the observer stack;
      // the callback's image may belong to a navigation that is now superseded.
      PostNotification(nil, true);
    }
  }
  void CaptureChanged(content::WebContents* changed) {
    // The producer recursively includes inner contents; match their actual
    // ownership chain, never the active tab or focused window.
    for (auto* owner = changed; owner; owner = owner->GetOuterWebContents()) {
      if (owner == contents_.get()) {
        if (!ShouldNotifyShellPayloadChange(last_shell_notify_,
                                            CurrentShellNotifyState())) {
          return;
        }
        Notify();
        return;
      }
    }
  }
  void OnIsBeingSharedChanged(content::WebContents* changed, bool) override {
    CaptureChanged(changed);
  }
  void OnIsCapturingVideoChanged(content::WebContents* changed, bool) override {
    CaptureChanged(changed);
  }
  void OnIsCapturingAudioChanged(content::WebContents* changed, bool) override {
    CaptureChanged(changed);
  }
  void OnIsBeingMirroredChanged(content::WebContents* changed, bool) override {
    CaptureChanged(changed);
  }
  void OnIsCapturingTabChanged(content::WebContents* changed, bool) override {
    CaptureChanged(changed);
  }
  void OnIsCapturingWindowChanged(content::WebContents* changed, bool) override {
    CaptureChanged(changed);
  }
  void OnIsCapturingDisplayChanged(content::WebContents* changed, bool) override {
    CaptureChanged(changed);
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) {
      ++event_generation_;
      ClearFind();
      [status_text_ reset];
    }
  }
  void PrimaryPageChanged(content::Page& page) override {
    [status_text_ reset];
    top_band_->Bind(&page.GetMainDocument(), /*rebind=*/false);
  }
  void RenderFrameCreated(content::RenderFrameHost* frame) override {
    if (contents_ && frame == contents_->GetPrimaryMainFrame()) {
      top_band_->Bind(frame, /*rebind=*/true);
    }
  }
  void RenderFrameHostChanged(content::RenderFrameHost*,
                              content::RenderFrameHost* frame) override {
    if (contents_ && frame == contents_->GetPrimaryMainFrame()) {
      top_band_->Bind(frame, /*rebind=*/true);
    }
  }
  void TopBandColorChanged() {
    if (!ShouldNotifyShellPayloadChange(last_shell_notify_,
                                        CurrentShellNotifyState())) {
      return;
    }
    Notify();
  }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility != content::Visibility::VISIBLE) {
      [status_text_ reset];
    }
  }
  void TitleWasSet(content::NavigationEntry*) override {
    if (!ShouldNotifyShellPayloadChange(last_shell_notify_,
                                        CurrentShellNotifyState())) {
      return;
    }
    Notify();
  }
  void DidChangeThemeColor() override {
    if (!ShouldNotifyShellPayloadChange(last_shell_notify_,
                                        CurrentShellNotifyState())) {
      return;
    }
    Notify();
  }
  void OnBackgroundColorChanged() override {
    if (!ShouldNotifyShellPayloadChange(last_shell_notify_,
                                        CurrentShellNotifyState())) {
      return;
    }
    Notify();
  }
  void DidChangeVisibleSecurityState() override {
    if (!ShouldNotifyShellPayloadChange(last_shell_notify_,
                                        CurrentShellNotifyState())) {
      return;
    }
    Notify();
  }
  void DidStopLoading() override {
    if (!ShouldNotifyLoadingChange(last_shell_notify_,
                                   CurrentShellNotifyState())) {
      return;
    }
    Notify();
  }
  void DidStartLoading() override {
    if (!ShouldNotifyLoadingChange(last_shell_notify_,
                                   CurrentShellNotifyState())) {
      return;
    }
    Notify();
  }
  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    if (!navigation) {
      return;
    }
    const bool favicon_already = favicon_observation_.IsObserving();
    ObserveFavicon();
    if (!ShouldNotifyFinishedNavigation(
            navigation->IsInPrimaryMainFrame(), navigation->IsSameDocument(),
            favicon_already, last_shell_notify_, CurrentShellNotifyState())) {
      return;
    }
    Notify();
  }
  void DidFailLoad(content::RenderFrameHost* frame,
                   const GURL&,
                   int code) override {
    if (!contents_ || frame != contents_->GetPrimaryMainFrame() ||
        code == net::ERR_ABORTED) {
      return;
    }
    NSError* error =
        [NSError errorWithDomain:@"org.parc.chromium.navigation"
                            code:code
                        userInfo:@{
                          NSLocalizedDescriptionKey :
                              base::SysUTF8ToNSString(net::ErrorToString(code))
                        }];
    PostNotification(error);
  }
  void PrimaryMainFrameRenderProcessGone(
      base::TerminationStatus status) override {
    [status_text_ reset];
    // SadTabHelper owns the policy, including background-memory discard, and
    // publishes authoritative install/reset state. Never duplicate that as a
    // transient NSError (observer ordering may precede helper installation).
    if (SadTab::ShouldShow(status)) {
      return;
    }
    // Match CefBrowserContentsDelegate's current macOS failure classification.
    // TabStripModel fast-close reports NORMAL_TERMINATION with exit code 0
    // while its mutation guard is held; that is not a renderer failure.
    switch (status) {
      case base::TERMINATION_STATUS_ABNORMAL_TERMINATION:
      case base::TERMINATION_STATUS_PROCESS_WAS_KILLED:
      case base::TERMINATION_STATUS_PROCESS_CRASHED:
      case base::TERMINATION_STATUS_OOM:
      case base::TERMINATION_STATUS_LAUNCH_FAILED:
        break;
      default:
        return;
    }
    NSError* error = [NSError
        errorWithDomain:@"org.parc.chromium.renderer"
                   code:status
               userInfo:@{
                 NSLocalizedDescriptionKey :
                     @"The page renderer exited. Reload to reopen the page."
               }];
    PostNotification(error);
  }
  void PostNotification(NSError* error, bool favicon_only = false) {
    PCNativePage* page = page_;
    id<PCNativePageObserver> observer = page.observer;
    if (!contents_ || !page || !observer) {
      return;
    }
    if (!error && !favicon_only) {
      last_shell_notify_ = CurrentShellNotifyState();
      last_shell_notify_.published = true;
    }
    __weak PCNativePage* weak_page = page;
    __weak id<PCNativePageObserver> weak_observer = observer;
    // The shell can activate/remove tabs in response. Leave every engine
    // observer stack, including nested native loops, before entering that UI.
    //
    std::weak_ptr<NativePageState> weak = weak_from_this();
    const uint64_t generation = event_generation_;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(^{
          auto state = weak.lock();
          PCNativePage* live_page = weak_page;
          id<PCNativePageObserver> live_observer = weak_observer;
          if (!state || !state->contents_ ||
              (error && state->event_generation_ != generation) || !live_page ||
              !live_observer || state->page_ != live_page ||
              live_page.observer != live_observer) {
            return;
          }
          if (favicon_only) {
            if ([live_observer respondsToSelector:@selector(nativePageFaviconDidChange:)])
              [live_observer nativePageFaviconDidChange:live_page];
          } else if (error) {
            [live_observer nativePage:live_page didFailWithError:error];
          } else {
            // Metadata has no captured payload: ask the shell to read the
            // current state, even if navigation began after it was queued.
            [live_observer nativePageDidChange:live_page];
          }
        }));
  }
  void BeforeUnloadFired(bool proceed) override {
    if (!proceed) {
      auto keep_alive = shared_from_this();
      CancelClose();
    }
  }
  void BeforeUnloadDialogCancelled() override {
    auto keep_alive = shared_from_this();
    CancelClose();
  }
  void WebContentsDestroyed() override {
    auto keep_alive = shared_from_this();
    [status_text_ invalidate];
    ClearFind();
    find_observation_.Reset();
    favicon_observation_.Reset();
    capture_observation_.Reset();
    auto* old_contents = web_contents();
    Observe(nullptr);
    contents_.reset();
    ++event_generation_;
    host_ = nullptr;
    closing_ = false;
    auto callbacks = std::move(close_callbacks_);
    close_callbacks_.clear();
    auto closed = std::move(closed_);
    PCNativePage* page = page_;
    id<PCNativePageObserver> observer = page.observer;
    // Drop the engine registry before notifying. Shell callbacks can close or
    // replace tabs; retaining page locally does not retain WebContents.
    Pages().erase(old_contents);
    if (closed) {
      std::move(closed).Run();
    }
    if (page && observer) {
      [observer nativePageDidClose:page];
    }
    for (auto callback : callbacks) {
      callback(PCNativePageCloseResultClosed);
    }
  }
  base::ScopedObservation<find_in_page::FindTabHelper, find_in_page::FindResultObserver>
      find_observation_{this};
  content::WeakDocumentPtr find_document_;
  NSString* __strong find_query_;
  PCNativeFindResult* __strong find_result_;
  NSUInteger find_revision_ = 0;
  bool find_notification_queued_ = false;
  scoped_refptr<MediaStreamCaptureIndicator> capture_indicator_;
  base::ScopedObservation<favicon::FaviconDriver, favicon::FaviconDriverObserver>
      favicon_observation_{this};
  base::ScopedObservation<MediaStreamCaptureIndicator,
                          MediaStreamCaptureIndicator::Observer>
      capture_observation_{this};
  std::unique_ptr<NativePageInputDiagnostics> input_diagnostics_;
  std::unique_ptr<TopBandColorSampler> top_band_;
  std::unique_ptr<NativeReader> reader_;
  base::WeakPtr<content::WebContents> contents_;
  CefRefPtr<ChromeBrowserHostImpl> host_;
  NSView* __strong page_view_;
  PCNativeStatusTextController* __strong status_text_;
  NSString* __strong identifier_;
  NSString* __strong profile_path_;
  PCNativePage* __weak page_;
  std::vector<void (^)(PCNativePageCloseResult)> close_callbacks_;
  base::OnceClosure closed_;
  base::WeakPtr<BrowserWindowInterface> embedded_browser_;
  base::WeakPtr<Profile> embedded_profile_;
  NSWindow* __weak embedded_window_;
  bool embedded_ = false;
  bool closing_ = false;
  bool clearing_site_data_ = false;
  uint64_t event_generation_ = 0;
  NativePageShellNotifyState last_shell_notify_;
};
void MarkNativePageEmbedded(PCNativePage* page) {
  CHECK(NSThread.isMainThread);
  [page state]->MarkEmbedded();
}
PCNativePage* GetOrCreateNativePage(content::WebContents& contents,
                                    NativeChromePlatformDelegate& platform,
                                    NSString* profile_path) {
  CHECK(NSThread.isMainThread);
  auto found = Pages().find(&contents);
  if (found != Pages().end()) {
    return found->second.page;
  }
  auto state =
      std::make_shared<NativePageState>(contents, platform, profile_path);
  PCNativePage* page = [[PCNativePage alloc] initWithState:state];
  state->SetPage(page);
  Pages().emplace(&contents, PageRecord{page});
  AttachNativeConfirmInfoBars(contents);
  return page;
}
bool RebindNativeEmbeddedPageForTransfer(PCNativePage* page,
                                        BrowserWindowInterface& expected_owner,
                                        BrowserWindowInterface& destination) {
  CHECK(NSThread.isMainThread);
  return page && [page state]->RebindEmbeddedForTransfer(expected_owner, destination);
}
content::WebContents* ContentsForNativePage(PCNativePage* page) {
  return page ? [page state]->contents() : nullptr;
}
PCNativePage* ExistingNativePage(content::WebContents* contents) {
  auto found = Pages().find(contents);
  return found == Pages().end() ? nil : found->second.page;
}
void NotifyNativePageChanged(content::WebContents* contents) {
  PCNativePage* page = ExistingNativePage(contents);
  if (page) {
    [page state]->Notify();
  }
}
void RequestNativeRendererCrashFocus(content::WebContents* contents,
                                     PCNativeRendererCrash* snapshot) {
  PCNativePage* page = ExistingNativePage(contents);
  if (page) {
    [page state]->RequestCrashFocus(snapshot);
  }
}
void UpdateNativePageStatusText(content::WebContents& contents,
                                NSString* text) {
  CHECK(NSThread.isMainThread);
  if (PCNativePage* page = ExistingNativePage(&contents)) {
    [page state]->SetStatusText(text);
  }
}
void SetNativePageStatusAttached(content::WebContents& contents,
                                 bool attached) {
  CHECK(NSThread.isMainThread);
  if (PCNativePage* page = ExistingNativePage(&contents)) {
    [page state]->SetStatusAttached(attached);
  }
}
void NotifyNativePageCloseCancelled(content::WebContents* contents) {
  PCNativePage* page = ExistingNativePage(contents);
  if (page) {
    auto state = [page state];
    state->CancelClose();
  }
}
void SetNativePageClosedCallback(PCNativePage* page,
                                 base::OnceClosure callback) {
  CHECK(page);
  [page state]->SetClosed(std::move(callback));
}
}  // namespace parc

@implementation PCNativePage {
  std::shared_ptr<parc::NativePageState> _state;
  __weak id<PCNativePageObserver> _observer;
}
- (instancetype)initWithState:(std::shared_ptr<parc::NativePageState>)state {
  self = [super init];
  if (self) {
    _state = std::move(state);
  }
  return self;
}
- (std::shared_ptr<parc::NativePageState>)state {
  return _state;
}
- (NSString*)identifier {
  return _state->identifier();
}
- (NSString*)profilePath {
  return _state->path();
}
- (NSView*)nativeView {
  return _state->view();
}
- (BOOL)isClosed {
  return !_state->contents();
}
- (NSURL*)URL {
  auto* contents = _state->contents();
  return contents
             ? [NSURL URLWithString:base::SysUTF8ToNSString(
                                        parc::PublicInternalURL(_state->reader()->DisplayURL()).spec())]
             : nil;
}
- (NSString*)title {
  auto* contents = _state->contents();
  return contents ? base::SysUTF16ToNSString(contents->GetTitle()) : @"";
}
- (NSImage*)favicon {
  CHECK(NSThread.isMainThread);
  auto* contents = _state->contents();
  if (!contents || contents->IsBeingDestroyed()) return nil;
  auto* entry = contents->GetController().GetLastCommittedEntry();
  if (!entry) return nil;
  const auto& icon = entry->GetFavicon();
  return icon.valid && !icon.image.IsEmpty() ? [icon.image.ToNSImage() copy] : nil;
}
- (PCNativeCaptureState*)captureState {
  CHECK(NSThread.isMainThread);
  return _state->CaptureState();
}
- (BOOL)stopCapture:(PCNativeCaptureState*)snapshot sharing:(BOOL)sharing {
  return _state->StopCapture(snapshot, sharing);
}
- (BOOL)loading {
  auto* contents = _state->contents();
  return contents && contents->IsLoading();
}
- (BOOL)canGoBack {
  auto* contents = _state->contents();
  return contents && contents->GetController().CanGoBack();
}
- (BOOL)canGoForward {
  auto* contents = _state->contents();
  return contents && contents->GetController().CanGoForward();
}
- (PCNativeArchiveProtectionState)archiveProtectionState {
  CHECK(NSThread.isMainThread);
  auto* contents = _state->contents();
  using PM = performance_manager::PerformanceManager;
  using Live = performance_manager::PageLiveStateDecorator;
  if (!contents || !PM::IsAvailable() || !Live::GetFromGraph(PM::GetGraph())) {
    return PCNativeArchiveProtectionStateUnknown;
  }
  auto page = PM::GetPrimaryPageNodeForWebContents(contents);
  if (!page) {
    return PCNativeArchiveProtectionStateUnknown;
  }
  // Graph and native session reads are all main-thread in pinned Chromium156.
  // Muted is intentionally a conservative superset, not an assertion that the
  //
  if (page->HadFormInteraction() || page->HadUserEdits() ||
      contents->IsCurrentlyAudible() || contents->IsAudioMuted() ||
      contents->IsBeingCaptured() || contents->HasPictureInPictureVideo() ||
      contents->HasPictureInPictureDocument() ||
      Live::IsCapturingAudio(contents) || Live::IsCapturingVideo(contents) ||
      Live::IsBeingMirrored(contents) || Live::IsCapturingWindow(contents) ||
      Live::IsCapturingDisplay(contents) ||
      vr::VrTabHelper::IsContentDisplayedInHeadset(contents)) {
    return PCNativeArchiveProtectionStateProtected;
  }
  if (auto* session = content::MediaSession::GetIfExists(contents)) {
    auto info = session->GetMediaSessionInfoSync();
    if (!info) {
      return PCNativeArchiveProtectionStateUnknown;
    }
    if (info->state !=
        media_session::mojom::MediaSessionInfo::SessionState::kInactive) {
      return PCNativeArchiveProtectionStateProtected;
    }
  }
  return PCNativeArchiveProtectionStateEligible;
}
- (id<PCNativePageObserver>)observer {
  return _observer;
}
- (void)setObserver:(id<PCNativePageObserver>)observer {
  _observer = observer;
}
- (BOOL)isEmbedded { return _state->embedded(); }
- (BOOL)embeddedOwnerValid { return _state->EmbeddedOwnerValid(); }
- (void)loadURL:(NSURL*)url {
  const GURL requested(url.absoluteString.UTF8String ?: "");
  if (parc::IsNativeAppDocumentURL(requested) || requested.SchemeIs("arc")) return;
  if (_state->embedded() && (!_state->PageToolBrowser(false, false) ||
      PCNativeWindowHasSecurityReservation(self.nativeView.window))) return;
  CHECK(NSThread.isMainThread);
  auto host = _state->host();
  auto frame = host ? host->GetMainFrame() : nullptr;
  if (frame) {
    frame->LoadURL(url.absoluteString.UTF8String);
  }
}
- (void)goBack {
  if (_state->embedded() && (!_state->PageToolBrowser(false, false) ||
      PCNativeWindowHasSecurityReservation(self.nativeView.window))) return;
  auto host = _state->host();
  if (host) {
    host->GoBack();
  }
}
- (void)goForward {
  if (_state->embedded() && (!_state->PageToolBrowser(false, false) ||
      PCNativeWindowHasSecurityReservation(self.nativeView.window))) return;
  auto host = _state->host();
  if (host) {
    host->GoForward();
  }
}
- (PCNativeRendererCrash*)rendererCrash {
  return parc::NativeRendererCrash(_state->contents());
}
- (BOOL)rendererCrashDidPresent:(PCNativeRendererCrash*)snapshot {
  return parc::NativeRendererCrashDidPresent(_state->contents(), snapshot);
}
- (BOOL)performRendererCrashAction:(PCNativeRendererCrash*)snapshot {
  return parc::PerformNativeRendererCrashAction(_state->contents(), snapshot);
}
- (void)reload {
  if (_state->embedded() && (!_state->PageToolBrowser(false, false) ||
      PCNativeWindowHasSecurityReservation(self.nativeView.window))) return;
  auto host = _state->host();
  if (host) {
    host->Reload();
  }
}
- (void)stop {
  if (_state->embedded() && (!_state->PageToolBrowser(false, false) ||
      PCNativeWindowHasSecurityReservation(self.nativeView.window))) return;
  auto host = _state->host();
  if (host) {
    host->StopLoad();
  }
}
- (void)setZoomLevel:(double)level {
  auto host = _state->host();
  if (host) {
    host->SetZoomLevel(level);
  }
}
- (void)zoomPage:(NSInteger)direction {
  auto host = _state->host();
  if (host) {
    host->Zoom(direction < 0   ? CEF_ZOOM_COMMAND_OUT
               : direction > 0 ? CEF_ZOOM_COMMAND_IN
                               : CEF_ZOOM_COMMAND_RESET);
  }
}
- (double)pageZoomLevel {
  auto host = _state->host();
  return host ? host->GetZoomLevel() : 0;
}
+ (NSNotificationName)findResultDidChangeNotification {
  return @"ParcNativePageFindResultDidChange";
}
- (PCNativeFindResult*)findResult { return _state->FindResult(); }
- (BOOL)canFindInPage {
  id responder = self.nativeView.window.firstResponder;
  if ([responder conformsToProtocol:@protocol(NSTextInputClient)] &&
      [(id<NSTextInputClient>)responder hasMarkedText]) return NO;
  auto* browser = _state->PageToolBrowser(false);
  return browser && chrome::IsCommandEnabled(browser, IDC_FIND);
}
- (NSString*)selectionForFind {
  if (![self canFindInPage]) return @"";
  auto* contents = _state->contents();
  auto* frame = contents ? contents->GetFocusedFrame() : nullptr;
  auto* widget = frame ? frame->GetRenderWidgetHost() : nullptr;
  auto* view = widget ? widget->GetView() : nullptr;
  return view ? base::SysUTF16ToNSString(view->GetSelectedText()) : @"";
}
- (void)findText:(NSString*)text forward:(BOOL)forward findNext:(BOOL)findNext {
  auto* browser = _state->PageToolBrowser();
  auto host = _state->host();
  if (browser && [self canFindInPage] && host && text.length) {
    _state->PrepareFind(text);
    host->Find(text.UTF8String, forward, false, findNext);
  }
}
- (void)stopFinding {
  _state->ClearFind();
  auto host = _state->host();
  if (host) {
    host->StopFinding(true);
  }
}
- (NSString*)developerModeHost {
  auto* contents = parc::ContentsForNativePage(self);
  if (!contents || contents->IsBeingDestroyed() || parc::IsNativePageRetiring(self))
    return nil;
  const auto& url = contents->GetLastCommittedURL();
  if (!url.SchemeIsHTTPOrHTTPS() || !url.has_host()) return nil;
  return base::SysUTF8ToNSString(url.host());
}
- (NSString*)developerModeExtensionHost {
  auto* contents = parc::ContentsForNativePage(self);
  if (!contents || contents->IsBeingDestroyed() || parc::IsNativePageRetiring(self))
    return nil;
  const auto& url = contents->GetLastCommittedURL();
  if (!url.SchemeIs(extensions::kExtensionScheme) || !url.has_host()) return nil;
  return base::SysUTF8ToNSString(url.host());
}
- (BOOL)developerModeSecure {
  auto* contents = parc::ContentsForNativePage(self);
  if (!contents || contents->IsBeingDestroyed()) return NO;
  return chrome_security_state::GetSecurityLevel(contents) == security_state::SECURE;
}
- (NSColor*)developerModeTint {
  auto* contents = parc::ContentsForNativePage(self);
  if (!contents || contents->IsBeingDestroyed()) return nil;
  auto color = contents->GetThemeColor();
  if (!color) return nil;
  return [NSColor colorWithSRGBRed:SkColorGetR(*color) / 255.0
                           green:SkColorGetG(*color) / 255.0
                            blue:SkColorGetB(*color) / 255.0
                           alpha:1.0];
}
- (void)showDeveloperTools {
  auto* contents = parc::ContentsForNativePage(self);
  if (contents) {
    parc::RequestAppKitDevtools(*contents);
  }
}
- (BOOL)canPerformPageTool:(PCNativePageTool)tool {
  return _state->CanPerformPageTool(tool);
}
- (BOOL)performPageTool:(PCNativePageTool)tool {
  return _state->PerformPageTool(tool);
}
- (PCNativeReaderMode)readerMode {
  return static_cast<PCNativeReaderMode>(_state->reader()->mode());
}
- (NSUInteger)readerRevision {
  return _state->reader()->revision();
}
- (NSString*)readerMessage {
  return base::SysUTF8ToNSString(_state->reader()->message());
}
- (BOOL)canToggleReaderMode {
  return _state->CanToggleReaderMode();
}
- (BOOL)toggleReaderMode {
  return _state->ToggleReaderMode();
}
- (void)requestClose:(void (^)(PCNativePageCloseResult))completion {
  CHECK(completion);
  auto state = _state;
  state->Close(completion);
}
@end


@interface PCNativeNavigationEntry () {
 @public
  int _index;
}
- (instancetype)initWithEntry:(content::NavigationEntry*)entry index:(int)index;
@end
@implementation PCNativeNavigationEntry
@synthesize identifier = _identifier;
@synthesize title = _title;
@synthesize URL = _URL;
@synthesize favicon = _favicon;
- (instancetype)initWithEntry:(content::NavigationEntry*)entry index:(int)index {
  self = [super init];
  if (self) {
    _index = index;
    _identifier = entry->GetUniqueID();
    _title = base::SysUTF16ToNSString(entry->GetTitleForDisplay());
    _URL = [NSURL URLWithString:base::SysUTF8ToNSString(parc::PublicInternalURL(entry->GetVirtualURL()).spec())];
    const auto& icon = entry->GetFavicon();
    if (icon.valid && !icon.image.IsEmpty()) {
      _favicon = [icon.image.ToNSImage() copy];
    }
  }
  return self;
}
@end

namespace {
Browser* NavigationBrowser(PCNativePage* page, bool require_key) {
  if (!page || page.isClosed) return nullptr;
  auto state = [page state];
  // Failure surfaces intentionally hide the still-attached renderer. The
  // exact shell selection, native active tab and registered parent remain
  // authoritative for Back/Reload on that page.
  auto* browser = state->PageToolBrowser(false, false);
  NSWindow* window = page.nativeView.window;
  if (!browser || !window.visible || window.miniaturized ||
      (require_key && !window.keyWindow) ||
      PCNativeWindowHasSecurityReservation(window)) {
    return nullptr;
  }
  return browser;
}
int NavigationCommand(PCNativeNavigationAction action) {
  switch (action) {
    case PCNativeNavigationActionBack: return IDC_BACK;
    case PCNativeNavigationActionForward: return IDC_FORWARD;
    case PCNativeNavigationActionReload: return IDC_RELOAD;
    case PCNativeNavigationActionReloadBypassingCache: return IDC_RELOAD_BYPASSING_CACHE;
    case PCNativeNavigationActionStop: return IDC_STOP;
  }
  return 0;
}
//
//
//
//
// GetTabAndRevertIfNecessary clones the active tab and appends the clone; the
// shell adopts it later, so the exact new WebContents carries that receipt.
const char kAlternateNavigationSourceKey = 0;
class AlternateNavigationSource final : public base::SupportsUserData::Data {
 public:
  AlternateNavigationSource(content::WebContents& source, bool top)
      : source(source.GetWeakPtr()), top(top) {}
  const base::WeakPtr<content::WebContents> source;
  const bool top;
};
std::vector<content::WebContents*> TabContents(Browser* browser) {
  std::vector<content::WebContents*> result;
  auto* strip = browser->GetTabStripModel();
  for (int index = 0; index < strip->count(); ++index)
    result.push_back(strip->GetWebContentsAt(index));
  return result;
}
// Chromium clones the browser's active tab. Only that original source, with
// exactly one newly inserted page of its own Profile, receives a receipt.
void MarkAlternateNavigationClone(Browser* browser, content::WebContents* source,
    bool source_was_active, const std::vector<content::WebContents*>& before,
    bool top) {
  if (!source_was_active || !source) return;
  content::WebContents* clone = nullptr;
  for (auto* contents : TabContents(browser)) {
    if (std::find(before.begin(), before.end(), contents) != before.end()) continue;
    if (clone) return;
    clone = contents;
  }
  if (!clone || clone == source ||
      clone->GetBrowserContext() != source->GetBrowserContext() ||
      clone->GetUserData(&kAlternateNavigationSourceKey)) return;
  clone->SetUserData(&kAlternateNavigationSourceKey,
      std::make_unique<AlternateNavigationSource>(*source, top));
}
}  // namespace

@interface PCNativeNavigationHistory () {
  PCNativePage* __weak _page;
  NSWindow* __weak _window;
  base::WeakPtr<content::WebContents> _contents;
  content::WeakDocumentPtr _document;
  std::vector<int> _entry_ids;
  int _current_index;
  int _pending_id;
  bool _consumed;
}
- (instancetype)initWithPage:(PCNativePage*)page back:(BOOL)back;
@end
@implementation PCNativeNavigationHistory
@synthesize entries = _entries;
- (instancetype)initWithPage:(PCNativePage*)page back:(BOOL)back {
  self = [super init];
  if (self) {
    _page = page;
    _window = page.nativeView.window;
    auto* contents = parc::ContentsForNativePage(page);
    _contents = contents->GetWeakPtr();
    if (auto* frame = contents->GetPrimaryMainFrame())
      _document = frame->GetWeakDocumentPtr();
    auto& controller = contents->GetController();
    _current_index = controller.GetCurrentEntryIndex();
    auto* pending = controller.GetPendingEntry();
    _pending_id = pending ? pending->GetUniqueID() : 0;
    NSMutableArray<PCNativeNavigationEntry*>* entries = [NSMutableArray array];
    for (int i = 0; i < controller.GetEntryCount(); ++i)
      _entry_ids.push_back(controller.GetEntryAtIndex(i)->GetUniqueID());
    const int direction = back ? -1 : 1;
    for (int i = _current_index + direction;
         i >= 0 && i < controller.GetEntryCount(); i += direction) {
      [entries addObject:[[PCNativeNavigationEntry alloc]
          initWithEntry:controller.GetEntryAtIndex(i) index:i]];
    }
    _entries = [entries copy];
  }
  return self;
}
- (BOOL)isValid {
  CHECK(NSThread.isMainThread);
  PCNativePage* page = _page;
  auto* contents = _contents.get();
  if (_consumed || !page || !contents || page.nativeView.window != _window ||
      !NavigationBrowser(page, false) ||
      parc::ContentsForNativePage(page) != contents ||
      !_document.AsRenderFrameHostIfValid() ||
      _document.AsRenderFrameHostIfValid() != contents->GetPrimaryMainFrame()) {
    return NO;
  }
  auto& controller = contents->GetController();
  auto* pending = controller.GetPendingEntry();
  if (controller.GetCurrentEntryIndex() != _current_index ||
      (pending ? pending->GetUniqueID() : 0) != _pending_id ||
      controller.GetEntryCount() != static_cast<int>(_entry_ids.size())) return NO;
  for (int i = 0; i < controller.GetEntryCount(); ++i)
    if (controller.GetEntryAtIndex(i)->GetUniqueID() != _entry_ids[i]) return NO;
  return YES;
}
- (void)invalidate { _consumed = true; _contents.reset(); _page = nil; }
- (BOOL)navigateToEntry:(PCNativeNavigationEntry*)entry inNewTab:(BOOL)inNewTab {
  CHECK(NSThread.isMainThread);
  if (![self isValid] || [_entries indexOfObjectIdenticalTo:entry] == NSNotFound)
    return NO;
  auto* browser = NavigationBrowser(_page, true);
  if (!browser) return NO;
  auto* contents = _contents.get();
  const int index = entry->_index;
  _consumed = true;
  if (inNewTab) {
    //
    //
    // Its insertion strategy is nil, so placement follows the referrer.
    const auto before = TabContents(browser);
    const bool active = browser->GetTabStripModel()->GetActiveWebContents() == contents;
    chrome::NavigateToIndexWithDisposition(
        browser, index, WindowOpenDisposition::NEW_BACKGROUND_TAB);
    MarkAlternateNavigationClone(browser, contents, active, before, false);
  } else {
    contents->GetController().GoToIndex(index);
  }
  return YES;
}
@end

namespace parc {
bool CanNativePageHistorySwipe(PCNativePage* page) {
  if (!page || !NSApp.active) return false;
  auto* browser = [page state]->PageToolBrowser();
  NSWindow* window = page.nativeView.window;
  if (!browser || PCNativeWindowHasSecurityReservation(window)) return false;
  NSResponder* responder = window.firstResponder;
  if (![responder isKindOfClass:NSView.class] ||
      ![(NSView*)responder isDescendantOf:page.nativeView]) return false;
  auto* binding = AppKitBindingForBrowser(browser);
  return [binding.client respondsToSelector:
      @selector(nativeBrowser:allowsHistorySwipeForPage:)] &&
      [binding.client nativeBrowser:binding allowsHistorySwipeForPage:page];
}
}  // namespace parc

@implementation PCNativePage (NavigationControls)
- (BOOL)canShowBackHistory {
  auto* browser = NavigationBrowser(self, false);
  return browser && chrome::ShouldEnableBackButton(browser);
}
- (BOOL)canShowForwardHistory {
  auto* browser = NavigationBrowser(self, false);
  return browser && chrome::ShouldEnableForwardButton(browser);
}
- (PCNativeNavigationHistory*)navigationHistoryBack:(BOOL)back {
  CHECK(NSThread.isMainThread);
  if (!NavigationBrowser(self, true) ||
      !(back ? self.canShowBackHistory : self.canShowForwardHistory)) return nil;
  return [[PCNativeNavigationHistory alloc] initWithPage:self back:back];
}
- (BOOL)canPerformNavigationAction:(PCNativeNavigationAction)action {
  CHECK(NSThread.isMainThread);
  auto* browser = NavigationBrowser(self, false);
  const int command = NavigationCommand(action);
  if (!browser || !command || !chrome::IsCommandEnabled(browser, command)) return NO;
  auto* contents = parc::ContentsForNativePage(self);
  switch (action) {
    case PCNativeNavigationActionBack: return contents->GetController().CanGoBack();
    case PCNativeNavigationActionForward: return contents->GetController().CanGoForward();
    case PCNativeNavigationActionReload:
    case PCNativeNavigationActionReloadBypassingCache: return chrome::CanReload(browser);
    case PCNativeNavigationActionStop: return contents->IsLoading();
  }
  return NO;
}
- (BOOL)performNavigationAction:(PCNativeNavigationAction)action inNewTab:(BOOL)inNewTab {
  CHECK(NSThread.isMainThread);
  auto* browser = NavigationBrowser(self, true);
  if (!browser || ![self canPerformNavigationAction:action] ||
      (inNewTab && action == PCNativeNavigationActionStop)) return NO;
  //
  //
  //
  auto disposition = inNewTab ? WindowOpenDisposition::NEW_FOREGROUND_TAB
                              : WindowOpenDisposition::CURRENT_TAB;
  auto* source = parc::ContentsForNativePage(self);
  const auto before = inNewTab ? TabContents(browser)
                               : std::vector<content::WebContents*>();
  const bool active = browser->GetTabStripModel()->GetActiveWebContents() == source;
  switch (action) {
    case PCNativeNavigationActionBack: chrome::GoBack(browser, disposition); break;
    case PCNativeNavigationActionForward: chrome::GoForward(browser, disposition); break;
    case PCNativeNavigationActionReload: chrome::Reload(browser, disposition); break;
    case PCNativeNavigationActionReloadBypassingCache:
      chrome::ReloadBypassingCache(browser, disposition); break;
    case PCNativeNavigationActionStop: chrome::Stop(browser); break;
  }
  //
  // Reload in a new tab passes a nil strategy with the window's active item.
  if (inNewTab) {
    MarkAlternateNavigationClone(browser, source, active, before,
        action == PCNativeNavigationActionBack ||
        action == PCNativeNavigationActionForward);
  }
  return YES;
}
- (PCNativePage*)alternateNavigationSourcePage {
  CHECK(NSThread.isMainThread);
  auto* contents = parc::ContentsForNativePage(self);
  auto* receipt = contents ? static_cast<AlternateNavigationSource*>(
      contents->GetUserData(&kAlternateNavigationSourceKey)) : nullptr;
  auto* source = receipt ? receipt->source.get() : nullptr;
  if (!source || source->GetBrowserContext() != contents->GetBrowserContext())
    return nil;
  return parc::ExistingNativePage(source);
}
- (BOOL)alternateNavigationPlacesAtTop {
  CHECK(NSThread.isMainThread);
  auto* contents = parc::ContentsForNativePage(self);
  auto* receipt = contents ? static_cast<AlternateNavigationSource*>(
      contents->GetUserData(&kAlternateNavigationSourceKey)) : nullptr;
  return receipt && receipt->top;
}
@end

namespace parc {
namespace {
//
// pixel size divided by a float scale, in its observer bridge (0x4413968) and
// from the web contents' cached size/scale fields (+0x210/+0x20c, 0x440e9c0).
// That these are cc::RenderFrameMetadata's fields is inferred.
NSSize RenderFrameViewport(const cc::RenderFrameMetadata& metadata) {
  const float scale = metadata.device_scale_factor;
  if (!(scale > 0)) return NSZeroSize;
  return NSMakeSize(metadata.viewport_size_in_pixels.width() / scale,
                    metadata.viewport_size_in_pixels.height() / scale);
}
content::RenderWidgetHostImpl* PrimaryWidget(content::WebContents* contents) {
  auto* frame = contents ? contents->GetPrimaryMainFrame() : nullptr;
  return frame ? content::RenderWidgetHostImpl::From(frame->GetRenderWidgetHost())
               : nullptr;
}
// Follows the primary main-frame widget as NativePageInputDiagnostics does and
// reports each activated frame's viewport (LastRenderFrameMetadata is the
// metadata of the frame just activated).
class RenderFrameViewportObserver final
    : public content::WebContentsObserver,
      public content::RenderWidgetHostObserver,
      public content::RenderFrameMetadataProvider::Observer {
 public:
  RenderFrameViewportObserver(content::WebContents& contents,
                              void (^handler)(NSSize))
      : content::WebContentsObserver(&contents), handler_([handler copy]) {
    BindPrimaryWidget();
  }

 private:
  void Invalidate() {
    handler_ = nil;
    ResetWidget();
    Observe(nullptr);
  }
  void ResetWidget() {
    metadata_observation_.Reset();
    widget_observation_.Reset();
  }
  void BindPrimaryWidget() {
    auto* widget = PrimaryWidget(web_contents());
    if (widget_observation_.GetSource() == widget) return;
    ResetWidget();
    if (!widget) return;
    widget_observation_.Observe(widget);
    metadata_observation_.Observe(widget->render_frame_metadata_provider());
  }
  void OnRenderFrameMetadataChangedBeforeActivation(
      const cc::RenderFrameMetadata&) override {}
  void OnRenderFrameMetadataChangedAfterActivation(base::TimeTicks) override {
    auto* widget =
        content::RenderWidgetHostImpl::From(widget_observation_.GetSource());
    PCNativePage* page = ExistingNativePage(web_contents());
    if (!widget || !page || page.closed) {
      Invalidate();
      return;
    }
    // The handler may end this lease; nothing is read after it returns.
    auto handler = handler_;
    if (handler) {
      handler(RenderFrameViewport(
          widget->render_frame_metadata_provider()->LastRenderFrameMetadata()));
    }
  }
  void OnRenderFrameSubmission() override {}
  void OnLocalSurfaceIdChanged(const cc::RenderFrameMetadata&) override {}
  void RenderFrameCreated(content::RenderFrameHost* frame) override {
    if (web_contents() && frame == web_contents()->GetPrimaryMainFrame()) {
      BindPrimaryWidget();
    }
  }
  void RenderFrameHostChanged(content::RenderFrameHost*,
                              content::RenderFrameHost* frame) override {
    if (web_contents() && frame == web_contents()->GetPrimaryMainFrame()) {
      BindPrimaryWidget();
    }
  }
  void PrimaryPageChanged(content::Page&) override { BindPrimaryWidget(); }
  void RenderWidgetHostDestroyed(content::RenderWidgetHost* widget) override {
    if (widget == widget_observation_.GetSource()) ResetWidget();
  }
  void WebContentsDestroyed() override { Invalidate(); }
  void (^handler_)(NSSize) = nil;
  base::ScopedObservation<content::RenderWidgetHost,
                          content::RenderWidgetHostObserver>
      widget_observation_{this};
  base::ScopedObservation<content::RenderFrameMetadataProvider,
                          content::RenderFrameMetadataProvider::Observer>
      metadata_observation_{this};
};
}  // namespace
}  // namespace parc

@interface PCNativeRenderFrameObservation () {
  std::unique_ptr<parc::RenderFrameViewportObserver> _observer;
}
- (instancetype)initWithContents:(content::WebContents&)contents
                         handler:(void (^)(NSSize))handler;
@end
@implementation PCNativeRenderFrameObservation
- (instancetype)initWithContents:(content::WebContents&)contents
                         handler:(void (^)(NSSize))handler {
  if ((self = [super init])) {
    _observer = std::make_unique<parc::RenderFrameViewportObserver>(contents, handler);
  }
  return self;
}
- (void)invalidate {
  CHECK(NSThread.isMainThread);
  _observer.reset();
}
@end

@implementation PCNativePage (SecureContext)
- (PCNativeSecureContextState)secureContextState {
  CHECK(NSThread.isMainThread);
  auto* contents = self.closed ? nullptr : parc::ContentsForNativePage(self);
  if (!contents || contents->IsBeingDestroyed() ||
      parc::IsNativePageRetiring(self)) {
    return PCNativeSecureContextStateNone;
  }
  const auto level = chrome_security_state::GetSecurityLevel(contents);
  if (level == security_state::NONE) return PCNativeSecureContextStateNone;
  if (level == security_state::SECURE) return PCNativeSecureContextStateSecure;
  return PCNativeSecureContextStateInsecure;
}
@end

@implementation PCNativePage (TopBandColor)
- (BOOL)hasTopBandColorSample {
  CHECK(NSThread.isMainThread);
  const auto* sampler = self.closed ? nullptr : [self state]->top_band();
  return sampler && sampler->delivered() && !parc::IsNativePageRetiring(self);
}
- (NSColor*)topBandColor {
  CHECK(NSThread.isMainThread);
  if (!self.hasTopBandColorSample) {
    return nil;
  }
  const auto color = [self state]->top_band()->color();
  if (!color) {
    return nil;
  }
  return [NSColor colorWithSRGBRed:SkColorGetR(*color) / 255.0
                             green:SkColorGetG(*color) / 255.0
                              blue:SkColorGetB(*color) / 255.0
                             alpha:SkColorGetA(*color) / 255.0];
}
- (BOOL)topBandColorCrossfades {
  CHECK(NSThread.isMainThread);
  return self.hasTopBandColorSample && [self state]->top_band()->crossfade();
}
- (NSString*)topBandColorHost {
  CHECK(NSThread.isMainThread);
  if (!self.hasTopBandColorSample || [self state]->top_band()->host().empty()) {
    return nil;
  }
  return base::SysUTF8ToNSString([self state]->top_band()->host());
}
@end

@implementation PCNativePage (PageBackgroundColor)
- (NSColor*)pageBackgroundColor {
  CHECK(NSThread.isMainThread);
  auto* contents = self.closed ? nullptr : parc::ContentsForNativePage(self);
  if (!contents || contents->IsBeingDestroyed() ||
      parc::IsNativePageRetiring(self)) {
    return nil;
  }
  const auto color = contents->GetBackgroundColor();
  if (!color || SkColorGetA(*color) != SK_AlphaOPAQUE) return nil;
  return [NSColor colorWithSRGBRed:SkColorGetR(*color) / 255.0
                             green:SkColorGetG(*color) / 255.0
                              blue:SkColorGetB(*color) / 255.0
                             alpha:1.0];
}
@end

@implementation PCNativePage (RenderFrameViewport)
- (NSSize)renderFrameViewportSize {
  CHECK(NSThread.isMainThread);
  auto* widget =
      parc::PrimaryWidget(self.closed ? nullptr : parc::ContentsForNativePage(self));
  return widget ? parc::RenderFrameViewport(
                      widget->render_frame_metadata_provider()->LastRenderFrameMetadata())
                : NSZeroSize;
}
- (PCNativeRenderFrameObservation*)observeRenderFrameViewportSize:
    (void (^)(NSSize))handler {
  CHECK(NSThread.isMainThread);
  auto* contents = parc::ContentsForNativePage(self);
  if (!contents || !handler || self.closed) return nil;
  return [[PCNativeRenderFrameObservation alloc] initWithContents:*contents
                                                          handler:handler];
}
@end

// Engine-internal; the bridge hands it to the app only as an opaque NSObject.
@interface PCNativeNavigationState : NSObject
- (instancetype)initWithNavigations:
                    (std::vector<sessions::SerializedNavigationEntry>)navigations
                              index:(int)index
                            profile:(Profile*)profile;
- (instancetype)initWithNavigations:
                    (std::vector<sessions::SerializedNavigationEntry>)navigations
                              index:(int)index
                        archivePath:(base::FilePath)path;
- (std::unique_ptr<content::WebContents>)restoredContentsForProfile:(Profile*)profile
                                                             hidden:(bool)hidden;
@end
namespace {
// Tab History bytes: version, current index, count, then each entry as its
// own length-prefixed pickle, written the way SessionService writes one.
constexpr int kNavigationArchiveVersion = 1;
// SessionService's own per-navigation cap (base_session_service_commands.cc).
constexpr int kMaxArchivedNavigationSize =
    std::numeric_limits<uint16_t>::max() - 1024;
}  // namespace
@implementation PCNativeNavigationState {
  std::vector<sessions::SerializedNavigationEntry> _navigations;
  int _index;
  base::WeakPtr<Profile> _profile;
  // A value read back from Tab History restores only into the persistent
  // Profile at this path; a captured one only into its own Profile object.
  base::FilePath _archivePath;
  BOOL _archived;
}
- (instancetype)initWithNavigations:
                    (std::vector<sessions::SerializedNavigationEntry>)navigations
                              index:(int)index
                            profile:(Profile*)profile {
  self = [super init];
  if (self) {
    _navigations = std::move(navigations);
    _index = index;
    _profile = profile->GetWeakPtr();
  }
  return self;
}
- (instancetype)initWithNavigations:
                    (std::vector<sessions::SerializedNavigationEntry>)navigations
                              index:(int)index
                        archivePath:(base::FilePath)path {
  self = [super init];
  if (self) {
    _navigations = std::move(navigations);
    _index = index;
    _archivePath = std::move(path);
    _archived = YES;
  }
  return self;
}
- (std::unique_ptr<content::WebContents>)restoredContentsForProfile:(Profile*)profile
                                                             hidden:(bool)hidden {
  CHECK(NSThread.isMainThread);
  // A private Profile shares its parent's path, so an archived value also
  // requires a persistent Profile.
  const bool owner =
      profile && (_archived ? !profile->IsOffTheRecord() &&
                                  profile->GetPath() == _archivePath
                            : _profile.get() == profile);
  if (!owner || _index < 0 ||
      _index >= static_cast<int>(_navigations.size())) {
    return nullptr;
  }
  content::WebContents::CreateParams params(profile);
  params.initially_hidden = hidden;
  auto contents = content::WebContents::Create(params);
  auto entries = sessions::ContentSerializedNavigationBuilder::ToNavigationEntries(
      _navigations, profile);
  contents->GetController().Restore(_index, content::RestoreType::kRestored,
                                    &entries);
  return contents;
}
@end

@implementation PCNativePage (Discard)
- (BOOL)discardIfIdle {
  CHECK(NSThread.isMainThread);
  auto* contents = self.closed ? nullptr : parc::ContentsForNativePage(self);
  // The archive protection (typed text, audio, capture and sharing, PiP, an
  // active media session) plus what a reload would lose or break.
  if (!contents || self.embedded || contents->IsBeingDestroyed() ||
      !base::FeatureList::IsEnabled(features::kWebContentsDiscard) ||
      contents->WasDiscarded() ||
      contents->GetVisibility() != content::Visibility::HIDDEN ||
      contents->IsLoading() ||
      self.archiveProtectionState != PCNativeArchiveProtectionStateEligible ||
      contents->HasFileSystemAccessHandles() ||
      contents->NeedToFireBeforeUnloadOrUnloadEvents() ||
      content::DevToolsAgentHost::IsDebuggerAttached(contents) ||
      !contents->GetLastCommittedURL().SchemeIsHTTPOrHTTPS()) {
    return NO;
  }
  for (auto capability : {content::WebContentsCapabilityType::kUSB,
                          content::WebContentsCapabilityType::kBluetoothConnected,
                          content::WebContentsCapabilityType::kBluetoothScanning,
                          content::WebContentsCapabilityType::kHID,
                          content::WebContentsCapabilityType::kSerial,
                          content::WebContentsCapabilityType::kGeolocation}) {
    if (contents->IsCapabilityActive(capability)) return NO;
  }
  contents->Discard(base::DoNothing());
  return contents->WasDiscarded();
}
@end

@implementation PCNativePage (NavigationState)
- (NSObject*)captureNavigationState {
  CHECK(NSThread.isMainThread);
  auto* contents = self.closed ? nullptr : parc::ContentsForNativePage(self);
  if (!contents || self.embedded || contents->IsBeingDestroyed()) return nil;
  Profile* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  auto& controller = contents->GetController();
  const int committed = controller.GetLastCommittedEntryIndex();
  std::vector<sessions::SerializedNavigationEntry> navigations;
  int index = -1;
  for (int i = 0; i < controller.GetEntryCount(); ++i) {
    content::NavigationEntry* entry = controller.GetEntryAtIndex(i);
    if (!entry || entry->IsInitialEntry()) continue;
    if (i == committed) index = static_cast<int>(navigations.size());
    navigations.push_back(
        sessions::ContentSerializedNavigationBuilder::FromNavigationEntry(
            static_cast<int>(navigations.size()), entry));
  }
  if (!profile || index < 0) return nil;
  return [[PCNativeNavigationState alloc] initWithNavigations:std::move(navigations)
                                                        index:index
                                                      profile:profile];
}
- (NSData*)archivedNavigationState {
  CHECK(NSThread.isMainThread);
  auto* contents = self.closed ? nullptr : parc::ContentsForNativePage(self);
  if (!contents || self.embedded || contents->IsBeingDestroyed()) return nil;
  Profile* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  if (!profile || profile->IsOffTheRecord()) return nil;
  auto& controller = contents->GetController();
  const int committed = controller.GetLastCommittedEntryIndex();
  if (committed < 0) return nil;
  // SessionService's window around the current entry (BuildCommandsForTab).
  const int first = std::max(0, committed - sessions::gMaxPersistNavigationCount);
  const int end = std::min(controller.GetEntryCount(),
                           committed + sessions::gMaxPersistNavigationCount + 1);
  std::vector<base::Pickle> entries;
  int index = -1;
  for (int i = first; i < end; ++i) {
    content::NavigationEntry* entry = controller.GetEntryAtIndex(i);
    if (!entry || entry->IsInitialEntry()) continue;
    const int position = static_cast<int>(entries.size());
    if (i == committed) index = position;
    base::Pickle& one = entries.emplace_back();
    sessions::ContentSerializedNavigationBuilder::FromNavigationEntry(position,
                                                                      entry)
        .WriteToPickle(kMaxArchivedNavigationSize, &one);
  }
  if (index < 0) return nil;
  base::Pickle pickle;
  pickle.WriteInt(kNavigationArchiveVersion);
  pickle.WriteInt(index);
  pickle.WriteInt(static_cast<int>(entries.size()));
  for (const base::Pickle& one : entries) {
    pickle.WriteData(one.AsBytes());
  }
  const base::span<const uint8_t> bytes = pickle.AsBytes();
  return [NSData dataWithBytes:bytes.data() length:bytes.size()];
}
+ (NSObject*)navigationStateWithArchive:(NSData*)data
                            profilePath:(NSString*)path {
  CHECK(NSThread.isMainThread);
  if (!data.length || !path.isAbsolutePath) return nil;
  base::PickleIterator iterator =
      base::PickleIterator::WithData(base::apple::NSDataToSpan(data));
  int version = 0, index = -1, count = 0;
  if (!iterator.ReadInt(&version) || version != kNavigationArchiveVersion ||
      !iterator.ReadInt(&index) || !iterator.ReadInt(&count) || count <= 0 ||
      count > 2 * sessions::gMaxPersistNavigationCount + 1 || index < 0 ||
      index >= count) {
    return nil;
  }
  std::vector<sessions::SerializedNavigationEntry> navigations(count);
  for (int i = 0; i < count; ++i) {
    std::optional<base::span<const uint8_t>> bytes = iterator.ReadData();
    if (!bytes) return nil;
    base::PickleIterator entry = base::PickleIterator::WithData(*bytes);
    if (!navigations[i].ReadFromPickle(&entry)) return nil;
    navigations[i].set_index(i);
  }
  if (!iterator.ReachedEnd()) return nil;
  return [[PCNativeNavigationState alloc]
      initWithNavigations:std::move(navigations)
                    index:index
              archivePath:base::FilePath(base::SysNSStringToUTF8(path))];
}
@end

namespace parc {
namespace {
const char kRestoredLoadPendingKey = 0;
}  // namespace
std::unique_ptr<content::WebContents> CreateRestoredContents(
    NSObject* state, Profile& profile, bool initially_hidden) {
  if (![state isKindOfClass:[PCNativeNavigationState class]]) return nullptr;
  auto contents = [static_cast<PCNativeNavigationState*>(state)
      restoredContentsForProfile:&profile
                          hidden:initially_hidden];
  if (contents) {
    contents->SetUserData(&kRestoredLoadPendingKey,
                          std::make_unique<base::SupportsUserData::Data>());
  }
  return contents;
}
bool HasRestoredLoadPending(content::WebContents& contents) {
  return contents.GetUserData(&kRestoredLoadPendingKey) != nullptr;
}
bool TakeRestoredLoadPending(content::WebContents& contents) {
  if (!contents.GetUserData(&kRestoredLoadPendingKey)) return false;
  contents.RemoveUserData(&kRestoredLoadPendingKey);
  return true;
}
}  // namespace parc
