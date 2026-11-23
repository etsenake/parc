// Copyright 2026 Parc contributors.
#include "native_appkit_page.h"
#include "native_page_shell_notify.h"
#include "native_page_observers.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "native_cast.h"
#include "native_internal_urls.h"
#include "components/sessions/content/content_serialized_navigation_builder.h"
#include "components/sessions/content/content_serialized_navigation_driver.h"
#include "components/sessions/content/extended_info_handler.h"
#include "components/sessions/content/session_tab_helper.h"
#include "components/sessions/core/serialized_navigation_entry.h"
#include "components/sessions/core/session_constants.h"
#include "content/public/browser/restore_type.h"
#include "content/public/browser/session_storage_namespace_handle.h"
#include "native_link_routing.h"
#include "fairplay_identity.h"

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
#include "components/find_in_page/find_types.h"
#include "components/url_formatter/url_fixer.h"
#include "components/zoom/zoom_controller.h"
#include "components/zoom/page_zoom.h"
#include "content/public/common/page_zoom.h"
#include "components/find_in_page/find_result_observer.h"
#include "base/command_line.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/pickle.h"
#include "base/scoped_multi_source_observation.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/supports_user_data.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "base/uuid.h"
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
#include "content/public/browser/navigation_details.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/page.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/favicon_status.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/favicon/core/favicon_driver_observer.h"
#include "content/browser/renderer_host/render_widget_host_impl.h"
#include "content/browser/renderer_host/render_widget_host_view_base.h"
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
#include "native_page_binding.h"
#include "native_host_route.h"
#include "native_page_retirement.h"
#include "native_profile_removal.h"
#include "native_reader.h"
#include "native_confirm_infobars.h"
#include "net/base/net_errors.h"
#include "sad_tab.h"
#include "services/network/public/mojom/web_sandbox_flags.mojom.h"
#import "native_shift_link.h"
#import "status_text.h"
#include "tab_transfer.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "third_party/blink/public/common/parc/top_band_color_sampling.h"
#include "third_party/blink/public/mojom/parc/page_network_activity.mojom.h"
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
}
}

@interface PCNativePage ()
- (instancetype)initWithState:(std::shared_ptr<parc::NativePageState>)state;
- (std::shared_ptr<parc::NativePageState>)state;
@end

namespace parc {
namespace {
std::set<SessionID>& OmittedSessions() {
  static base::NoDestructor<std::set<SessionID>> value;
  return *value;
}
class NativePageInputDiagnostics final
    : public content::WebContentsObserver,
      public content::RenderWidgetHost::InputEventObserver,
      public content::RenderWidgetHostObserver {
 public:
  NativePageInputDiagnostics(content::WebContents& contents, NSView* view)
      : content::WebContentsObserver(&contents), view_(view) {
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

struct LinkFrame {
  bool fenced = false;
  bool can_navigate_page = true;
  bool operator==(const LinkFrame&) const = default;
};

class LinkFramePointer final
    : public content::WebContentsObserver,
      public content::RenderWidgetHost::InputEventObserver,
      public content::RenderWidgetHostObserver {
 public:
  LinkFramePointer(content::WebContents& contents,
                   base::RepeatingClosure changed)
      : content::WebContentsObserver(&contents), changed_(std::move(changed)) {
    contents.ForEachRenderFrameHost([this](content::RenderFrameHost* frame) {
      if (frame->IsRenderFrameLive()) {
        Watch(frame);
      }
    });
  }
  bool fenced() const { return inside_ && fenced_.contains(inside_.get()); }
  bool FrameCanNavigatePage() const {
    auto* main = web_contents() ? web_contents()->GetPrimaryMainFrame() : nullptr;
    if (!main || !inside_ || main->GetRenderWidgetHost() == inside_.get()) {
      return true;
    }
    content::RenderFrameHost* root = nullptr;
    main->ForEachRenderFrameHostWithAction([&](content::RenderFrameHost* frame) {
      auto* parent = frame->GetParentOrOuterDocument();
      if (frame->GetRenderWidgetHost() != inside_.get() ||
          (parent && parent->GetRenderWidgetHost() == inside_.get())) {
        return content::RenderFrameHost::FrameIterationAction::kContinue;
      }
      root = frame;
      return content::RenderFrameHost::FrameIterationAction::kStop;
    });
    using Sandbox = network::mojom::WebSandboxFlags;
    return !root || NativeFrameCanNavigatePage(false,
        root->IsSandboxed(Sandbox::kTopNavigation),
        root->IsSandboxed(Sandbox::kTopNavigationByUserActivation));
  }

 private:
  void Watch(content::RenderFrameHost* frame) {
    auto* widget = frame->GetRenderWidgetHost();
    if (!widget || widgets_.IsObservingSource(widget)) {
      return;
    }
    widgets_.AddObservation(widget);
    inputs_.AddObservation(widget);
    if (frame->IsNestedWithinFencedFrame()) {
      fenced_.insert(widget);
    }
  }
  void Point(const content::RenderWidgetHost* widget) {
    if (inside_ == widget) {
      return;
    }
    inside_ = widget;
    changed_.Run();
  }
  void RenderFrameCreated(content::RenderFrameHost* frame) override {
    Watch(frame);
  }
  void OnInputEvent(const content::RenderWidgetHost& widget,
                    const blink::WebInputEvent& event,
                    InputEventSource) override {
    const auto type = event.GetType();
    if (type == blink::WebInputEvent::Type::kMouseLeave) {
      if (inside_ == &widget) {
        Point(nullptr);
      }
    } else if (blink::WebInputEvent::IsMouseEventType(type)) {
      Point(&widget);
    }
  }
  void RenderWidgetHostDestroyed(content::RenderWidgetHost* widget) override {
    if (inputs_.IsObservingSource(widget)) {
      inputs_.RemoveObservation(widget);
    }
    if (widgets_.IsObservingSource(widget)) {
      widgets_.RemoveObservation(widget);
    }
    fenced_.erase(widget);
    if (inside_ == widget) {
      Point(nullptr);
    }
  }
  base::RepeatingClosure changed_;
  raw_ptr<const content::RenderWidgetHost> inside_ = nullptr;
  std::set<const content::RenderWidgetHost*> fenced_;
  base::ScopedMultiSourceObservation<
      content::RenderWidgetHost,
      content::RenderWidgetHost::InputEventObserver>
      inputs_{this};
  base::ScopedMultiSourceObservation<content::RenderWidgetHost,
                                     content::RenderWidgetHostObserver>
      widgets_{this};
};

class TopBandColorSampler final : public mojom::TopBandColorObserver {
 public:
  explicit TopBandColorSampler(base::RepeatingClosure changed)
      : changed_(std::move(changed)) {}

  void Bind(content::RenderFrameHost* frame, bool rebind) {
    delivery_.Reset();
    delivered_ = false;
    color_.reset();
    crossfade_ = false;
    host_.clear();
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

class PageNetworkActivityWatcher final
    : public mojom::PageNetworkActivityObserver {
 public:
  explicit PageNetworkActivityWatcher(base::RepeatingClosure changed)
      : changed_(std::move(changed)) {}

  void Bind(content::RenderFrameHost* frame, bool rebind) {
    const auto id =
        frame ? frame->GetGlobalId() : content::GlobalRenderFrameHostId();
    if (!rebind && id == frame_ && agent_.is_bound()) {
      return;
    }
    receiver_.reset();
    agent_.reset();
    frame_ = id;
    Set(false);
    if (!frame || !frame->IsRenderFrameLive()) {
      return;
    }
    frame->GetRemoteAssociatedInterfaces()->GetInterface(&agent_);
    agent_->SetObserver(receiver_.BindNewEndpointAndPassRemote());
    receiver_.set_disconnect_handler(base::BindOnce(
        &PageNetworkActivityWatcher::Set, base::Unretained(this), false));
  }
  bool busy() const { return busy_; }

 private:
  void DidChangeNetworkBusy(bool busy) override { Set(busy); }
  void Set(bool busy) {
    if (busy == busy_) {
      return;
    }
    busy_ = busy;
    changed_.Run();
  }

  base::RepeatingClosure changed_;
  content::GlobalRenderFrameHostId frame_;
  mojo::AssociatedRemote<mojom::PageNetworkActivityAgent> agent_;
  mojo::AssociatedReceiver<mojom::PageNetworkActivityObserver> receiver_{this};
  bool busy_ = false;
};

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
constexpr char kHistoryEntryKey[] = "parc_history_entry";
class HistoryEntryIdentifier final : public base::SupportsUserData::Data {
 public:
  explicit HistoryEntryIdentifier(std::string value) : value_(std::move(value)) {}
  std::unique_ptr<base::SupportsUserData::Data> Clone() override {
    return std::make_unique<HistoryEntryIdentifier>(value_);
  }
  const std::string& value() const { return value_; }

 private:
  const std::string value_;
};
bool IsHistoryEntryIdentifier(const std::string& value) {
  return !value.empty() && value.size() <= 64 &&
         std::all_of(value.begin(), value.end(), [](char c) {
           return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') ||
                  (c >= 'A' && c <= 'Z') || c == '-';
         });
}
std::string HistoryEntryIdentifierOf(content::NavigationEntry* entry) {
  auto* data = static_cast<HistoryEntryIdentifier*>(
      entry->GetUserData(kHistoryEntryKey));
  return data ? data->value() : std::string();
}
void SetHistoryEntryIdentifier(content::NavigationEntry* entry,
                               const std::string& value) {
  if (value.empty()) {
    entry->RemoveUserData(kHistoryEntryKey);
  } else {
    entry->SetUserData(kHistoryEntryKey,
                       std::make_unique<HistoryEntryIdentifier>(value));
  }
}
class HistoryEntryIdentifierHandler final
    : public sessions::ExtendedInfoHandler {
 public:
  std::string GetExtendedInfo(content::NavigationEntry* entry) const override {
    return HistoryEntryIdentifierOf(entry);
  }
  void RestoreExtendedInfo(const std::string& info,
                           content::NavigationEntry* entry) override {
    if (IsHistoryEntryIdentifier(info)) {
      SetHistoryEntryIdentifier(entry, info);
    }
  }
};
void RegisterHistoryEntryIdentifiers() {
  CHECK(NSThread.isMainThread);
  static bool registered = false;
  if (registered) {
    return;
  }
  registered = true;
  sessions::ContentSerializedNavigationDriver::GetInstance()
      ->RegisterExtendedInfoHandler(
          kHistoryEntryKey, std::make_unique<HistoryEntryIdentifierHandler>());
}
class HistoryEntryTracker final : public content::WebContentsObserver {
 public:
  HistoryEntryTracker(content::WebContents& contents,
                      base::RepeatingClosure changed)
      : content::WebContentsObserver(&contents), changed_(std::move(changed)) {
    RegisterHistoryEntryIdentifiers();
  }
  uint64_t revision() const { return revision_; }
  void Assign() {
    auto* contents = web_contents();
    if (!contents) {
      return;
    }
    auto& controller = contents->GetController();
    std::set<std::string> seen;
    for (int i = 0; i < controller.GetEntryCount(); ++i) {
      content::NavigationEntry* entry = controller.GetEntryAtIndex(i);
      if (entry->IsInitialEntry()) {
        continue;
      }
      std::string value = HistoryEntryIdentifierOf(entry);
      if (!IsHistoryEntryIdentifier(value) || !seen.insert(value).second) {
        value = base::Uuid::GenerateRandomV4().AsLowercaseString();
        seen.insert(value);
        SetHistoryEntryIdentifier(entry, value);
      }
    }
    Remember();
  }

 private:
  void Remember() {
    entries_.clear();
    auto* contents = web_contents();
    if (!contents) {
      return;
    }
    auto& controller = contents->GetController();
    for (int i = 0; i < controller.GetEntryCount(); ++i) {
      content::NavigationEntry* entry = controller.GetEntryAtIndex(i);
      entries_.emplace_back(entry->GetUniqueID(),
                            HistoryEntryIdentifierOf(entry));
    }
    remembered_ = true;
  }
  void Changed() {
    ++revision_;
    changed_.Run();
  }
  void DidStartNavigation(content::NavigationHandle*) override { Remember(); }
  void NavigationEntryCommitted(
      const content::LoadCommittedDetails& details) override {
    auto& controller = web_contents()->GetController();
    content::NavigationEntry* entry = controller.GetLastCommittedEntry();
    const int index = controller.GetLastCommittedEntryIndex();
    const bool known = std::any_of(
        entries_.begin(), entries_.end(), [entry](const auto& remembered) {
          return entry && remembered.first == entry->GetUniqueID();
        });
    if (remembered_ && entry && details.entry == entry && !known) {
      const bool replaced = details.did_replace_entry && index >= 0 &&
                            index < static_cast<int>(entries_.size());
      SetHistoryEntryIdentifier(
          entry, replaced ? entries_[index].second : std::string());
    }
    Remember();
    Changed();
  }
  void NavigationListPruned(const content::PrunedDetails&) override {
    Remember();
    Changed();
  }
  void NavigationEntriesDeleted() override {
    Remember();
    Changed();
  }
  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame() && !navigation->HasCommitted()) {
      Changed();
    }
  }
  base::RepeatingClosure changed_;
  std::vector<std::pair<int, std::string>> entries_;
  bool remembered_ = false;
  uint64_t revision_ = 0;
};
}
class NativePageState final
    : public content::WebContentsObserver,
      public MediaStreamCaptureIndicator::Observer,
      public favicon::FaviconDriverObserver,
      public find_in_page::FindResultObserver,
      public std::enable_shared_from_this<NativePageState> {
 public:
  NativePageState(content::WebContents& contents,
                  NativePageBinding& platform,
                  NSString* path)
      : content::WebContentsObserver(&contents),
        contents_(contents.GetWeakPtr()),
        page_view_(platform.GetNativePageView().GetNativeNSView()),
        identifier_([NSUUID UUID].UUIDString),
        profile_path_([path copy]) {
    CHECK(NSThread.isMainThread);
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
    link_pointer_ = std::make_unique<LinkFramePointer>(
        contents, base::BindRepeating(&NativePageState::LinkPointerChanged,
                                      base::Unretained(this)));
    top_band_ = std::make_unique<TopBandColorSampler>(base::BindRepeating(
        &NativePageState::TopBandColorChanged, base::Unretained(this)));
    top_band_->Bind(contents.GetPrimaryMainFrame(), true);
    network_activity_ = std::make_unique<PageNetworkActivityWatcher>(
        base::BindRepeating(&NativePageState::NetworkActivityChanged,
                            base::Unretained(this)));
    network_activity_->Bind(contents.GetPrimaryMainFrame(), true);
    history_entries_ = std::make_unique<HistoryEntryTracker>(
        contents, base::BindRepeating(&NativePageState::Notify,
                                      base::Unretained(this)));
    if (auto* profile = Profile::FromBrowserContext(contents.GetBrowserContext())) {
      HistoryDeletionNotifier::EnsureFor(*profile);
    }
  }
  HistoryEntryTracker* history_entries() const {
    return history_entries_.get();
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
    status_text_.linkOutcome = ^PCNativeStatusLinkOutcome(NSEventModifierFlags flags, NSURL* url) {
      auto state = weak.lock();
      if (!state || !state->browser())
        return PCNativeStatusLinkOutcomeNone;
      constexpr NSEventModifierFlags shift = NSEventModifierFlagShift;
      constexpr NSEventModifierFlags command = NSEventModifierFlagCommand;
      constexpr NSEventModifierFlags option = NSEventModifierFlagOption;
      if (flags == command) return PCNativeStatusLinkOutcomeNewBackgroundTab;
      if (flags == (shift | command)) return PCNativeStatusLinkOutcomeNewForegroundTab;
      if (flags == (shift | option)) return PCNativeStatusLinkOutcomeNewWindow;
      PCNativePage* source = state->page_;
      NSString* scheme = url.scheme.lowercaseString;
      const bool web = [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
      const bool web_link = source && web && !state->StatusLinkInFencedFrame();
      if (flags == option || flags == (option | command)) {
        auto* contents = state->contents();
        return web_link && contents &&
                NativeSplitLinkAvailable(*state->browser(), *contents)
            ? PCNativeStatusLinkOutcomeSplitView : PCNativeStatusLinkOutcomeNone;
      }
      if (flags != shift) return PCNativeStatusLinkOutcomeNone;
      if (!web_link) return PCNativeStatusLinkOutcomeNewWindow;
      PCNativeBrowserWindow* binding = AppKitBindingForBrowser(state->browser());
      id<PCNativeBrowserWindowClient> client = binding.client;
      if (![client respondsToSelector:@selector(nativeBrowser:allowsPeekWithShift:)] ||
          ![client nativeBrowser:binding allowsPeekWithShift:YES])
        return PCNativeStatusLinkOutcomeNewWindow;
      NativeShiftLinkClick click{.modifiers = flags, .shift_peek_enabled = true,
          .frame_can_navigate_page = state->StatusLinkCanNavigatePage()};
      click.in_shown_peek =
          [client respondsToSelector:@selector(nativeBrowser:canNavigatePeekLinkFromPage:)] &&
          [client nativeBrowser:binding canNavigatePeekLinkFromPage:source];
      click.can_open_peek = !click.in_shown_peek &&
          ([client respondsToSelector:@selector(nativeBrowser:canPeekLinkFromPage:)]
               ? [client nativeBrowser:binding canPeekLinkFromPage:source]
               : [client respondsToSelector:@selector(nativeBrowser:canPresentPeekFrom:)] &&
                     [client nativeBrowser:binding canPresentPeekFrom:source]);
      return NativeShiftLinkOutcome(ClassifyNativeShiftLink(click));
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
  void SetStatusText(NSString* text) {
    const LinkFrame frame = PointerLinkFrame();
    const bool changed = frame != status_link_frame_;
    status_link_frame_ = frame;
    [status_text_ updateText:text];
    if (changed) [status_text_ setNeedsLinkOutcomeRefresh];
  }
  void SetStatusAttached(bool attached) { [status_text_ setAttached:attached]; }
  content::WebContents* contents() const { return contents_.get(); }
  Browser* browser() const {
    return contents_ ? NativeBrowserForContents(contents_.get()) : nullptr;
  }
  NSView* view() const { return page_view_; }
  NSString* identifier() const { return identifier_; }
  NSString* path() const { return profile_path_; }
  bool embedded() const { return embedded_; }
  bool ShellLoading() const {
    auto* contents = contents_.get();
    return contents &&
           (contents->ShouldShowLoadingUI() || loading_hold_.holding());
  }
  void CancelLoadingHold() {
    loading_hold_.Cancel();
    LoadingChanged();
  }
  void MarkEmbedded() {
    CHECK(!embedded_);
    embedded_ = true;
    auto* session = sessions::SessionTabHelper::FromWebContents(contents_.get());
    CHECK(session);
    OmittedSessions().insert(session->session_id());
    contents_->GetController().GetDefaultSessionStorageNamespace()->SetShouldPersist(false);
    auto* browser = this->browser();
    CHECK(browser);
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
        !binding.client || !AppKitBrowserAcceptsNewPages(destination) || browser() != &destination || !tab ||
        tab->GetBrowserWindowInterface() != &destination ||
        destination.GetTabStripModel()->GetIndexOfTab(tab) == TabStripModel::kNoTab) {
      return false;
    }
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
        this->browser() == browser && tab &&
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
    state.loading = ShellLoading();
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
                           bool require_live_renderer = true,
                           bool require_selection = true) const {
    CHECK(NSThread.isMainThread);
    auto* contents = contents_.get();
    if (!contents || contents->IsBeingDestroyed()) return nullptr;
    auto* browser = this->browser();
    auto* platform = NativePageBinding::FromWebContents(contents);
    auto* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
    const bool native_route = GetNativeRoute(*profile) ||
        (profile->IsOffTheRecord() && GetNativeRoute(*profile->GetOriginalProfile()));
    NSWindow* window = page_view_.window;
    if (closing_ || (embedded_ && !EmbeddedOwnerValid()) ||
        (require_live_renderer &&
         (contents->IsCrashed() || !contents->GetPrimaryMainFrame() ||
          !contents->GetPrimaryMainFrame()->IsRenderFrameLive())) || !browser ||
        !platform || !native_route || !window ||
        (require_interaction &&
         (!window.keyWindow || !window.visible || window.miniaturized ||
          page_view_.hiddenOrHasHiddenAncestor)) ||
        window.attachedSheet || !AppKitBrowserAcceptsNewPages(*browser) ||
        IsNativePageRetiring(page_) || IsLiveTabTransferTarget(contents) ||
        (require_selection
             ? browser->tab_strip_model()->GetActiveWebContents() != contents
             : browser->tab_strip_model()->GetIndexOfWebContents(contents) ==
                   TabStripModel::kNoTab) ||
        !platform->HasAttachedPage()) {
      return nullptr;
    }
    PCNativeBrowserWindow* binding = AppKitBindingForBrowser(browser);
    if (!binding || binding.window != window ||
        (require_selection && [binding.client selectedNativePage] != page_)) {
      return nullptr;
    }
    return browser;
  }
  bool CanPerformPageTool(PCNativePageTool tool) const {
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
    content::ClearSiteData(
        contents->GetBrowserContext()->GetWeakPtr(),
        frame->GetStoragePartition()->GetConfig(), origin,
        content::ClearSiteDataTypeSet::All(), {},
        false, storage_key.ToCookiePartitionKey(),
        storage_key, false, base::BindOnce(^{
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
                        !state->PageToolBrowser(false)) {
                      return;
                    }
                    [state->status_text_ reset];
                    live_contents->GetController().Reload(
                        content::ReloadType::BYPASSING_CACHE,
                        false);
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
    auto keep_alive = shared_from_this();
    if (contents_->NeedToFireBeforeUnloadOrUnloadEvents()) {
      contents_->DispatchBeforeUnload(false);
      return;
    }
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce([](std::weak_ptr<NativePageState> weak) {
          auto state = weak.lock();
          if (!state || !state->closing_) return;
          auto* contents = state->contents();
          auto* browser = state->browser();
          if (!contents || !browser || browser->IsDeleteScheduled()) {
            state->CancelClose();
            return;
          }
          auto* tabs = browser->tab_strip_model();
          const int index = tabs->GetIndexOfWebContents(contents);
          if (index == TabStripModel::kNoTab) {
            state->CancelClose();
            return;
          }
          tabs->CloseWebContentsAt(index,
              TabCloseTypes::CLOSE_CREATE_HISTORICAL_TAB |
              TabCloseTypes::CLOSE_USER_GESTURE);
        }, weak_from_this()));
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
      PostNotification(nil, true);
    }
  }
  void CaptureChanged(content::WebContents* changed) {
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
    top_band_->Bind(&page.GetMainDocument(), false);
    network_activity_->Bind(&page.GetMainDocument(), false);
    FitPrimaryWidgetView();
    ResendVisualProperties(page);
  }
  void FitPrimaryWidgetView() {
    content::RenderWidgetHostView* view =
        contents_ ? contents_->GetRenderWidgetHostView() : nullptr;
    NSView* container = contents_ ? contents_->GetNativeView().GetNativeNSView() : nil;
    NSView* widget = view ? view->GetNativeView().GetNativeNSView() : nil;
    if (!container || !widget || widget.superview != container ||
        NSEqualRects(widget.frame, container.bounds)) {
      return;
    }
    widget.frame = container.bounds;
  }
  static void ResendVisualProperties(content::Page& page) {
    auto* host = content::RenderWidgetHostImpl::From(
        page.GetMainDocument().GetRenderWidgetHost());
    content::RenderWidgetHostViewBase* view = host ? host->GetView() : nullptr;
    if (view && view->HasSize()) {
      host->SynchronizeVisualPropertiesIgnoringPendingAck();
    }
  }
  void RenderFrameCreated(content::RenderFrameHost* frame) override {
    if (contents_ && frame == contents_->GetPrimaryMainFrame()) {
      top_band_->Bind(frame, true);
      network_activity_->Bind(frame, true);
      FitPrimaryWidgetView();
    }
  }
  void RenderFrameHostChanged(content::RenderFrameHost*,
                              content::RenderFrameHost* frame) override {
    if (contents_ && frame == contents_->GetPrimaryMainFrame()) {
      top_band_->Bind(frame, true);
      network_activity_->Bind(frame, true);
      FitPrimaryWidgetView();
    }
  }
  void LinkPointerChanged() { [status_text_ setNeedsLinkOutcomeRefresh]; }
  LinkFrame PointerLinkFrame() const {
    if (!link_pointer_) return {};
    return {.fenced = link_pointer_->fenced(),
            .can_navigate_page = link_pointer_->FrameCanNavigatePage()};
  }
  bool StatusLinkInFencedFrame() const {
    return status_link_frame_.fenced || (link_pointer_ && link_pointer_->fenced());
  }
  bool StatusLinkCanNavigatePage() const { return status_link_frame_.can_navigate_page; }
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
  void DidStopLoading() override { LoadingChanged(); }
  void DidStartLoading() override { LoadingChanged(); }
  void LoadProgressChanged(double) override { LoadingChanged(); }
  void NetworkActivityChanged() {
    loading_hold_.NetworkBusy(network_activity_->busy(), NowMs());
    if (loading_hold_.holding()) {
      LoadingChanged();
    }
  }
  void OnFirstContentfulPaintInPrimaryMainFrame(base::TimeTicks) override {
    if (!contents_) {
      return;
    }
    painted_page_ = contents_->GetPrimaryPage().GetWeakPtr();
    if (loading_hold_.holding()) {
      LoadingChanged();
    }
  }
  static int64_t NowMs() {
    return (base::TimeTicks::Now() - base::TimeTicks()).InMilliseconds();
  }
  void LoadingChanged() {
    auto* contents = contents_.get();
    if (!contents) {
      return;
    }
    const int64_t now = NowMs();
    const bool painted =
        painted_page_ && painted_page_.get() == &contents->GetPrimaryPage();
    loading_hold_.Update(contents->ShouldShowLoadingUI(), painted, now);
    loading_hold_timer_.Stop();
    if (loading_hold_.holding()) {
      loading_hold_timer_.Start(
          FROM_HERE, base::Milliseconds(loading_hold_.Remaining(painted, now)),
          base::BindOnce(&NativePageState::LoadingChanged,
                         base::Unretained(this)));
    }
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
    if (navigation->IsInPrimaryMainFrame() && navigation->HasCommitted() &&
        !navigation->IsSameDocument() && !navigation->IsPageActivation() &&
        !navigation->GetURL().IsAboutBlank()) {
      loading_hold_.Committed(NowMs());
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
    if (SadTab::ShouldShow(status)) {
      return;
    }
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
    closing_ = false;
    auto callbacks = std::move(close_callbacks_);
    close_callbacks_.clear();
    auto closed = std::move(closed_);
    PCNativePage* page = page_;
    id<PCNativePageObserver> observer = page.observer;
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
  std::unique_ptr<LinkFramePointer> link_pointer_;
  LinkFrame status_link_frame_;
  std::unique_ptr<TopBandColorSampler> top_band_;
  std::unique_ptr<NativeReader> reader_;
  base::WeakPtr<content::WebContents> contents_;
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
  LoadingHold loading_hold_;
  base::WeakPtr<content::Page> painted_page_;
  base::OneShotTimer loading_hold_timer_;
  std::unique_ptr<PageNetworkActivityWatcher> network_activity_;
  std::unique_ptr<HistoryEntryTracker> history_entries_;
  NativePageShellNotifyState last_shell_notify_;
};
void MarkNativePageEmbedded(PCNativePage* page) {
  CHECK(NSThread.isMainThread);
  [page state]->MarkEmbedded();
}
PCNativePage* GetOrCreateNativePage(content::WebContents& contents,
                                    NativePageBinding& platform,
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
  InstallNativePageObservers(contents);
  AttachNativeConfirmInfoBars(contents);
  AttachFairPlayIdentity(contents);
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
  if (!attached) DetachNativePageObservers(contents);
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
bool IsSessionOmittedFromRestore(SessionID session_id) {
  return OmittedSessions().contains(session_id);
}
}

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
  return _state->ShellLoading();
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
  const GURL requested = url_formatter::FixupURL(
      url.absoluteString.UTF8String ?: "", std::string());
  if (!requested.is_valid()) return;
  if (parc::IsNativeAppDocumentURL(requested) || requested.SchemeIs("arc")) return;
  if (_state->embedded() && (!_state->PageToolBrowser(false, false) ||
      PCNativeWindowHasSecurityReservation(self.nativeView.window))) return;
  CHECK(NSThread.isMainThread);
  if (auto* contents = _state->contents()) {
    contents->GetController().LoadURL(requested, content::Referrer(),
                                      ui::PageTransitionFromInt(ui::PAGE_TRANSITION_TYPED |
                                          ui::PAGE_TRANSITION_FROM_ADDRESS_BAR),
                                      std::string());
  }
}
- (void)goBack {
  if (_state->embedded() && (!_state->PageToolBrowser(false, false) ||
      PCNativeWindowHasSecurityReservation(self.nativeView.window))) return;
  if (auto* contents = _state->contents()) {
    contents->GetController().GoBack();
  }
}
- (void)goForward {
  if (_state->embedded() && (!_state->PageToolBrowser(false, false) ||
      PCNativeWindowHasSecurityReservation(self.nativeView.window))) return;
  if (auto* contents = _state->contents()) {
    contents->GetController().GoForward();
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
  if (auto* contents = _state->contents()) {
    contents->GetController().Reload(content::ReloadType::NORMAL, true);
  }
}
- (void)stop {
  if (_state->embedded() && (!_state->PageToolBrowser(false, false) ||
      PCNativeWindowHasSecurityReservation(self.nativeView.window))) return;
  if (auto* contents = _state->contents()) {
    contents->Stop();
  }
}
- (void)setZoomLevel:(double)level {
  auto* contents = _state->contents();
  auto* zoom = contents ? zoom::ZoomController::FromWebContents(contents) : nullptr;
  if (!zoom || !std::isfinite(level)) return;
  if (level == 0) {
    level = zoom->GetDefaultZoomLevel();
    contents->SetPageScale(1.f);
  }
  zoom->SetZoomLevel(level);
}
- (void)zoomPage:(NSInteger)direction {
  if (auto* contents = _state->contents()) {
    zoom::PageZoom::Zoom(contents, direction < 0 ? content::PAGE_ZOOM_OUT
        : direction > 0 ? content::PAGE_ZOOM_IN : content::PAGE_ZOOM_RESET);
  }
}
- (double)pageZoomLevel {
  auto* contents = _state->contents();
  auto* zoom = contents ? zoom::ZoomController::FromWebContents(contents) : nullptr;
  return zoom ? zoom->GetZoomLevel() : 0;
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
  auto* contents = _state->contents();
  auto* helper = contents ? find_in_page::FindTabHelper::FromWebContents(contents) : nullptr;
  if (browser && [self canFindInPage] && helper && text.length) {
    _state->PrepareFind(text);
    helper->StartFinding(base::SysNSStringToUTF16(text), forward, false, findNext);
  }
}
- (void)stopFinding {
  _state->ClearFind();
  auto* contents = _state->contents();
  if (auto* helper = contents ? find_in_page::FindTabHelper::FromWebContents(contents) : nullptr) {
    helper->StopFinding(find_in_page::SelectionAction::kClear);
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
- (BOOL)hasDeveloperTools {
  auto* contents = parc::ContentsForNativePage(self);
  return contents && DevToolsWindow::GetInstanceForInspectedWebContents(contents);
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
@synthesize persistentIdentifier = _persistentIdentifier;
@synthesize title = _title;
@synthesize URL = _URL;
@synthesize favicon = _favicon;
- (instancetype)initWithEntry:(content::NavigationEntry*)entry index:(int)index {
  self = [super init];
  if (self) {
    _index = index;
    _identifier = entry->GetUniqueID();
    _persistentIdentifier =
        base::SysUTF8ToNSString(parc::HistoryEntryIdentifierOf(entry));
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
}

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
  if (!page) return false;
  auto* browser = [page state]->PageToolBrowser(false, true, false);
  NSWindow* window = page.nativeView.window;
  if (!browser || !window.visible || window.miniaturized ||
      page.nativeView.hiddenOrHasHiddenAncestor ||
      PCNativeWindowHasSecurityReservation(window)) return false;
  auto* binding = AppKitBindingForBrowser(browser);
  return [binding.client respondsToSelector:
      @selector(nativeBrowser:allowsHistorySwipeForPage:)] &&
      [binding.client nativeBrowser:binding allowsHistorySwipeForPage:page];
}
}

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
  if (browser && action == PCNativeNavigationActionStop) return _state->ShellLoading();
  if (!browser || !command || !chrome::IsCommandEnabled(browser, command)) return NO;
  auto* contents = parc::ContentsForNativePage(self);
  switch (action) {
    case PCNativeNavigationActionBack: return contents->GetController().CanGoBack();
    case PCNativeNavigationActionForward: return contents->GetController().CanGoForward();
    case PCNativeNavigationActionReload:
    case PCNativeNavigationActionReloadBypassingCache: return chrome::CanReload(browser);
    case PCNativeNavigationActionStop: return NO;
  }
  return NO;
}
- (BOOL)performNavigationAction:(PCNativeNavigationAction)action inNewTab:(BOOL)inNewTab {
  CHECK(NSThread.isMainThread);
  auto* browser = NavigationBrowser(self, true);
  if (!browser || ![self canPerformNavigationAction:action] ||
      (inNewTab && action == PCNativeNavigationActionStop)) return NO;
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
    case PCNativeNavigationActionStop:
      _state->CancelLoadingHold();
      if (source->ShouldShowLoadingUI()) source->Stop();
      break;
  }
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
}
}

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
- (nullable PCNativeNavigationState*)stateAtEntry:(const std::string&)identifier
                                         endingAt:(const std::string&)last;
@end
namespace {
constexpr int kNavigationArchiveVersion = 1;
constexpr int kMaxArchivedNavigationSize =
    std::numeric_limits<uint16_t>::max() - 1024;
}
@implementation PCNativeNavigationState {
  std::vector<sessions::SerializedNavigationEntry> _navigations;
  int _index;
  base::WeakPtr<Profile> _profile;
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
  const bool owner =
      profile && (_archived ? !profile->IsOffTheRecord() &&
                                  profile->GetPath() == _archivePath
                            : _profile.get() == profile);
  if (!owner || _index < 0 ||
      _index >= static_cast<int>(_navigations.size())) {
    return nullptr;
  }
  parc::RegisterHistoryEntryIdentifiers();
  content::WebContents::CreateParams params(profile);
  params.initially_hidden = hidden;
  auto contents = content::WebContents::Create(params);
  NSURL* bundled = [NSBundle.mainBundle URLForResource:@"WhatsNew"
                                         withExtension:@"html"];
  const GURL bundled_whats_new(
      base::SysNSStringToUTF8(bundled.absoluteString ?: @""));
  std::vector<sessions::SerializedNavigationEntry> navigations;
  int index = -1;
  for (int i = 0; i < static_cast<int>(_navigations.size()); ++i) {
    if (i != _index && bundled_whats_new.is_valid() &&
        _navigations[i].virtual_url().GetWithoutRef() == bundled_whats_new) {
      continue;
    }
    if (i == _index) index = static_cast<int>(navigations.size());
    navigations.push_back(_navigations[i]);
    navigations.back().set_index(static_cast<int>(navigations.size()) - 1);
  }
  auto entries = sessions::ContentSerializedNavigationBuilder::ToNavigationEntries(
      navigations, profile);
  contents->GetController().Restore(index, content::RestoreType::kRestored,
                                    &entries);
  return contents;
}
- (PCNativeNavigationState*)stateAtEntry:(const std::string&)identifier
                                endingAt:(const std::string&)last {
  CHECK(NSThread.isMainThread);
  const int count = static_cast<int>(_navigations.size());
  int index = -1;
  int end = count;
  for (int i = 0; i < count; ++i) {
    const auto& info = _navigations[i].extended_info_map();
    const auto found = info.find(parc::kHistoryEntryKey);
    const std::string value = found == info.end() ? std::string() : found->second;
    if (value.empty()) {
      continue;
    }
    if (index < 0 && value == identifier) {
      index = i;
    }
    if (!last.empty() && value == last) {
      end = i + 1;
    }
  }
  if (index < 0) {
    return nil;
  }
  if (end <= index) {
    end = count;
  }
  std::vector<sessions::SerializedNavigationEntry> navigations(
      _navigations.begin(), _navigations.begin() + end);
  for (int i = 0; i < end; ++i) {
    navigations[i].set_index(i);
  }
  PCNativeNavigationState* state = [[PCNativeNavigationState alloc] init];
  state->_navigations = std::move(navigations);
  state->_index = index;
  state->_profile = _profile;
  state->_archivePath = _archivePath;
  state->_archived = _archived;
  return state;
}
@end

@implementation PCNativePage (Discard)
- (BOOL)discardIfIdle {
  CHECK(NSThread.isMainThread);
  auto* contents = self.closed ? nullptr : parc::ContentsForNativePage(self);
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

@implementation PCNativeBrowserWindow (TaskManager)
- (BOOL)canOpenTaskManager {
  CHECK(NSThread.isMainThread);
  NSWindow* window = self.window;
  return parc::NativeProfileRemovalApplicationReady() && window &&
         [self.client nativeBrowserWindow] == window && window.keyWindow &&
         window.visible && !window.miniaturized && !window.attachedSheet &&
         chrome::CanOpenTaskManager();
}
- (BOOL)openTaskManager {
  if (!self.canOpenTaskManager) return NO;
  chrome::OpenTaskManager(nullptr, task_manager::StartAction::kMainMenu);
  return YES;
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
content::WebContents* HistoryContents(PCNativePage* page) {
  CHECK(NSThread.isMainThread);
  auto* contents = page.closed ? nullptr : ContentsForNativePage(page);
  return contents && !page.embedded && !contents->IsBeingDestroyed() &&
                 [page state]->history_entries()
             ? contents
             : nullptr;
}
}
}

@implementation PCNativePage (HistoryEntries)
- (NSUInteger)historyRevision {
  return parc::HistoryContents(self) ? [self state]->history_entries()->revision() : 0;
}
- (NSArray<PCNativeNavigationEntry*>*)historyEntries {
  auto* contents = parc::HistoryContents(self);
  if (!contents) return @[];
  [self state]->history_entries()->Assign();
  auto& controller = contents->GetController();
  NSMutableArray<PCNativeNavigationEntry*>* entries = [NSMutableArray array];
  for (int i = 0; i < controller.GetEntryCount(); ++i) {
    content::NavigationEntry* entry = controller.GetEntryAtIndex(i);
    if (entry->IsInitialEntry()) continue;
    [entries addObject:[[PCNativeNavigationEntry alloc] initWithEntry:entry
                                                                index:i]];
  }
  return [entries copy];
}
- (NSInteger)currentHistoryIndex {
  auto* contents = parc::HistoryContents(self);
  if (!contents) return -1;
  auto& controller = contents->GetController();
  const int current = controller.GetCurrentEntryIndex();
  if (current < 0 || current >= controller.GetEntryCount() ||
      controller.GetEntryAtIndex(current)->IsInitialEntry()) {
    return -1;
  }
  NSInteger index = 0;
  for (int i = 0; i < current; ++i) {
    if (!controller.GetEntryAtIndex(i)->IsInitialEntry()) ++index;
  }
  return index;
}
- (BOOL)historyNavigationPending {
  auto* contents = parc::HistoryContents(self);
  return contents && contents->GetController().GetPendingEntry();
}
- (BOOL)goToHistoryEntry:(NSString*)persistentIdentifier {
  auto* contents = parc::HistoryContents(self);
  const std::string identifier = base::SysNSStringToUTF8(persistentIdentifier ?: @"");
  if (!contents || identifier.empty() || parc::IsNativePageRetiring(self)) return NO;
  auto& controller = contents->GetController();
  for (int i = 0; i < controller.GetEntryCount(); ++i) {
    content::NavigationEntry* entry = controller.GetEntryAtIndex(i);
    if (entry->IsInitialEntry() || parc::HistoryEntryIdentifierOf(entry) != identifier) {
      continue;
    }
    if (i != controller.GetCurrentEntryIndex()) controller.GoToIndex(i);
    return YES;
  }
  return NO;
}
- (BOOL)removeHistoryEntriesAfterCurrent {
  auto* contents = parc::HistoryContents(self);
  if (!contents || parc::IsNativePageRetiring(self)) return NO;
  auto& controller = contents->GetController();
  if (!controller.CanPruneAllButLastCommitted()) return NO;
  std::set<int> ahead;
  for (int i = controller.GetLastCommittedEntryIndex() + 1;
       i < controller.GetEntryCount(); ++i) {
    ahead.insert(controller.GetEntryAtIndex(i)->GetUniqueID());
  }
  if (ahead.empty()) return YES;
  controller.DeleteNavigationEntries(base::BindRepeating(
      [](const std::set<int>& ids, content::NavigationEntry* entry) {
        return ids.contains(entry->GetUniqueID());
      },
      std::move(ahead)));
  return YES;
}
+ (NSObject*)navigationState:(NSObject*)state
              atHistoryEntry:(NSString*)persistentIdentifier
               endingAtEntry:(NSString*)lastPersistentIdentifier {
  CHECK(NSThread.isMainThread);
  if (![state isKindOfClass:[PCNativeNavigationState class]] ||
      !persistentIdentifier.length) {
    return nil;
  }
  return [static_cast<PCNativeNavigationState*>(state)
      stateAtEntry:base::SysNSStringToUTF8(persistentIdentifier)
          endingAt:base::SysNSStringToUTF8(lastPersistentIdentifier ?: @"")];
}
@end

namespace parc {
namespace {
const char kRestoredLoadPendingKey = 0;
}
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
}
