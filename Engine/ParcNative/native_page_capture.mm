// Copyright 2026 Parc contributors.
#import "native_appkit_page.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <map>
#include <optional>
#include <utility>
#include <vector>

#include "base/base64.h"
#include "parc/native/native_internal_urls.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/thread_pool.h"
#include "base/timer/timer.h"
#include "chrome/browser/enterprise/data_protection/data_protection_navigation_controller.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/common/pref_names.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "components/enterprise/buildflags/buildflags.h"
#include "components/prefs/pref_change_registrar.h"
#include "components/prefs/pref_service.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/devtools_agent_host_client.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/host_zoom_map.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_observer.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "native_appkit_host.h"
#include "native_page_capture.h"
#include "native_page_retirement.h"
#include "native_profile_removal.h"
#include "tab_transfer.h"
#include "third_party/blink/public/common/web_preferences/web_preferences.h"
#include "third_party/blink/public/common/page/page_zoom.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/base/base_window.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/geometry/point_f.h"
#include "ui/gfx/geometry/rect_conversions.h"
#include "ui/gfx/geometry/rect_f.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
constexpr NSUInteger kMaxScrollContainers = 8;
bool ScrollLocatorPartValid(std::string_view text, bool tag) {
  return !text.empty() && text.size() <= (tag ? 64u : 5u) &&
      std::all_of(text.begin(), text.end(), [tag](char c) {
        return tag ? base::IsAsciiAlphaNumeric(c) || c == '-' || c == '_' || c == '.'
                   : base::IsAsciiDigit(c);
      });
}
bool ScrollAnchorValid(NSString* anchor) {
  if (!anchor) return true;
  const std::string text = base::SysNSStringToUTF8(anchor);
  if (text.empty() || text.size() > 128 || !base::IsAsciiAlpha(text[0])) return false;
  int digits = 0;
  for (char c : text) {
    if (!base::IsAsciiAlphaNumeric(c) && c != '-' && c != '_') return false;
    digits = base::IsAsciiDigit(c) ? digits + 1 : 0;
    if (digits >= 3) return false;
  }
  return true;
}
bool ScrollPathValid(NSString* path) {
  if (!path) return false;
  const std::string text = base::SysNSStringToUTF8(path);
  if (text.empty()) return true;
  if (text.size() > 2048) return false;
  const auto steps = base::SplitStringPiece(text, ">", base::KEEP_WHITESPACE, base::SPLIT_WANT_ALL);
  if (steps.size() > 128) return false;
  for (std::string_view step : steps) {
    if (step == "^") continue;
    const size_t colon = step.find(':');
    if (colon == std::string_view::npos || !ScrollLocatorPartValid(step.substr(0, colon), true) ||
        !ScrollLocatorPartValid(step.substr(colon + 1), false)) return false;
  }
  return true;
}
bool BoundedFinite(double value) { return std::isfinite(value) && std::abs(value) <= 1000000; }
}
}

@implementation PCNativeCaptureScrollContainer
@synthesize anchorID = _anchorID, path = _path, scrollOffset = _scrollOffset, frame = _frame;
- (instancetype)initWithAnchorID:(NSString*)anchorID path:(NSString*)path
    scrollOffset:(NSPoint)scrollOffset frame:(NSRect)frame {
  if (!parc::ScrollAnchorValid(anchorID) || !parc::ScrollPathValid(path) ||
      !parc::BoundedFinite(scrollOffset.x) || !parc::BoundedFinite(scrollOffset.y) ||
      !parc::BoundedFinite(frame.origin.x) || !parc::BoundedFinite(frame.origin.y) ||
      !parc::BoundedFinite(frame.size.width) || !parc::BoundedFinite(frame.size.height) ||
      frame.size.width < 0 || frame.size.height < 0) return nil;
  if ((self = [super init])) {
    _anchorID = [anchorID copy];
    _path = [path copy];
    _scrollOffset = scrollOffset;
    _frame = frame;
  }
  return self;
}
@end
@interface PCNativeCaptureLayout ()
- (instancetype)initWithViewport:(NSSize)viewport scroll:(NSPoint)scroll region:(NSRect)region
                 scrollContainers:(NSArray<PCNativeCaptureScrollContainer*>*)scrollContainers;
@end
@implementation PCNativeCaptureLayout
@synthesize viewportSize = _viewportSize, scrollOffset = _scrollOffset, region = _region;
@synthesize scrollContainers = _scrollContainers;
- (instancetype)initWithViewport:(NSSize)viewport scroll:(NSPoint)scroll region:(NSRect)region
                 scrollContainers:(NSArray<PCNativeCaptureScrollContainer*>*)scrollContainers {
  if ((self = [super init])) {
    _viewportSize = viewport;
    _scrollOffset = scroll;
    _region = region;
    _scrollContainers = [scrollContainers copy] ?: @[];
  }
  return self;
}
@end
@interface PCNativePageCaptureResult ()
- (instancetype)initWithData:(NSData*)data size:(NSSize)size error:(NSString*)error
                     layout:(PCNativeCaptureLayout*)layout;
@end
@implementation PCNativePageCaptureResult
@synthesize pngData = _pngData, image = _image, pixelSize = _pixelSize;
@synthesize errorMessage = _errorMessage;
@synthesize layout = _layout, pdfData = _pdfData;
- (instancetype)initWithData:(NSData*)data size:(NSSize)size error:(NSString*)error
                     layout:(PCNativeCaptureLayout*)layout {
  if ((self = [super init])) {
    _pngData = [data copy];
    _image = data ? [[NSImage alloc] initWithData:data] : nil;
    _pixelSize = size;
    _errorMessage = [error copy];
    _layout = layout;
  }
  return self;
}
@end

@interface PCNativePageCaptureTarget ()
@property(nonatomic, readonly) NSPoint queryPoint;
@property(nonatomic, readonly) double pageZoom;
- (instancetype)initWithRect:(NSRect)rect point:(NSPoint)point zoom:(double)zoom;
@end
@implementation PCNativePageCaptureTarget
@synthesize viewportRect = _viewportRect, queryPoint = _queryPoint, pageZoom = _pageZoom;
- (instancetype)initWithRect:(NSRect)rect point:(NSPoint)point zoom:(double)zoom {
  if ((self = [super init])) {
    _viewportRect = rect;
    _queryPoint = point;
    _pageZoom = zoom;
  }
  return self;
}
@end

namespace parc {
namespace {
using CaptureCompletion = void (^)(PCNativePageCaptureResult*);
using TargetCompletion = void (^)(PCNativePageCaptureTarget*);
void PostTarget(TargetCompletion completion, PCNativePageCaptureTarget* target) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce([](TargetCompletion callback, PCNativePageCaptureTarget* value) {
        callback(value);
      }, [completion copy], target));
}

std::u16string ElementQuery(NSPoint point, double zoom) {
  std::string script = "(() => { const px = " + base::NumberToString(point.x / zoom) +
      ", py = " + base::NumberToString(point.y / zoom) + R"JS(;
    const v = window.visualViewport;
    if (!v || !Number.isFinite(v.scale) || v.scale <= 0) return null;
    const x = px / v.scale + v.offsetLeft;
    const y = py / v.scale + v.offsetTop;
    for (const el of document.elementsFromPoint(x, y)) {
      const r = el.getBoundingClientRect();
      const style = getComputedStyle(el);
      let score = (r.width + r.height) / 1000;
      if (Math.min(r.width, r.height) < 100) score -= 5;
      if (r.width >= window.innerWidth) score -= 5;
      if (r.height >= window.innerHeight) score -= 5;
      if (r.width * r.height > window.innerWidth * window.innerHeight * 0.7) score -= 5;
      if (el.tagName === 'IMG' || el.tagName === 'PICTURE' || el.tagName === 'OBJECT') score += 5;
      if (style.display === 'inline') score -= 10;
      if (!(score >= 0)) continue;
      return {x:r.left, y:r.top, width:r.width, height:r.height,
              offsetX:v.offsetLeft, offsetY:v.offsetTop, scale:v.scale};
    }
    return null;
  })())JS";
  return base::UTF8ToUTF16(script);
}
std::u16string GeometryQuery(gfx::PointF centre) {
  std::string script = "(() => { const px = " + base::NumberToString(centre.x()) +
      ", py = " + base::NumberToString(centre.y()) + R"JS(;
    const v = visualViewport;
    if (!v) return null;
    const geometry = {width:innerWidth, height:innerHeight, x:v.pageLeft, y:v.pageTop, scale:v.scale};
    if (!Number.isFinite(v.scale) || v.scale <= 0) return geometry;
    const cx = px / v.scale + v.offsetLeft, cy = py / v.scale + v.offsetTop;
    const stableID = id => /^[A-Za-z][A-Za-z0-9_-]{0,127}$/.test(id) && !/[0-9]{3}/.test(id);
    const locate = el => {
      const steps = [];
      for (let node = el; node;) {
        if (node === document.documentElement) return {anchor:null, path:steps.reverse().join('>')};
        if (node.id && stableID(node.id) && node.getRootNode() === document &&
            document.getElementById(node.id) === node) return {anchor:node.id, path:steps.reverse().join('>')};
        const parent = node.parentElement, root = node.parentNode;
        const holder = parent || (root instanceof ShadowRoot && root.mode === 'open' ? root : null);
        if (!holder || !/^[A-Za-z0-9._-]{1,64}$/.test(node.localName)) return null;
        steps.push(node.localName + ':' +
            Array.prototype.filter.call(holder.children, c => c.localName === node.localName).indexOf(node));
        if (parent) { node = parent; } else { steps.push('^'); node = root.host; }
      }
      return null;
    };
    let hit = document.elementFromPoint(cx, cy);
    while (hit && hit.shadowRoot) {
      const inner = hit.shadowRoot.elementFromPoint(cx, cy);
      if (!inner || inner === hit) break;
      hit = inner;
    }
    const scroller = document.scrollingElement || document.documentElement;
    const scrolls = value => value === 'auto' || value === 'scroll' || value === 'overlay';
    const containers = [];
    for (let el = hit; el && el !== document.documentElement && el !== scroller;) {
      const style = getComputedStyle(el);
      if (el.scrollTop || el.scrollLeft ||
          (scrolls(style.overflowY) && el.scrollHeight > el.clientHeight + 1) ||
          (scrolls(style.overflowX) && el.scrollWidth > el.clientWidth + 1)) {
        const at = locate(el);
        if (at) {
          const r = el.getBoundingClientRect();
          containers.push({anchor:at.anchor, path:at.path, x:el.scrollLeft, y:el.scrollTop,
                           left:r.left + scrollX, top:r.top + scrollY, width:r.width, height:r.height});
          if (containers.length === 8) break;
        } else if (el.scrollTop || el.scrollLeft) {
          geometry.containers = null;
          return geometry;
        }
      }
      el = el.parentElement || (el.parentNode instanceof ShadowRoot ? el.parentNode.host : null);
    }
    geometry.containers = containers.reverse();
    return geometry;
  })())JS";
  return base::UTF8ToUTF16(script);
}
std::optional<NSArray<PCNativeCaptureScrollContainer*>*> ScrollContainersFrom(
    const base::DictValue& dict) {
  const base::ListValue* list = dict.FindList("containers");
  if (!list || list->size() > kMaxScrollContainers) return std::nullopt;
  NSMutableArray<PCNativeCaptureScrollContainer*>* containers = [NSMutableArray array];
  for (const base::Value& value : *list) {
    const auto* entry = value.GetIfDict();
    if (!entry) return std::nullopt;
    const base::Value* anchor = entry->Find("anchor");
    const std::string* path = entry->FindString("path");
    auto x = entry->FindDouble("x"), y = entry->FindDouble("y");
    auto left = entry->FindDouble("left"), top = entry->FindDouble("top");
    auto width = entry->FindDouble("width"), height = entry->FindDouble("height");
    if (!anchor || !(anchor->is_none() || anchor->is_string()) || !path ||
        !x || !y || !left || !top || !width || !height) return std::nullopt;
    auto container = [[PCNativeCaptureScrollContainer alloc]
        initWithAnchorID:anchor->is_string() ? base::SysUTF8ToNSString(anchor->GetString()) : nil
        path:base::SysUTF8ToNSString(*path) scrollOffset:NSMakePoint(*x, *y)
        frame:NSMakeRect(*left, *top, *width, *height)];
    if (!container) return std::nullopt;
    [containers addObject:container];
  }
  return containers;
}
struct EncodedCapture {
  std::vector<uint8_t> png;
  gfx::Size pixels;
};
EncodedCapture EncodeBitmap(SkBitmap bitmap) {
  if (bitmap.drawsNothing()) return {};
  auto png = gfx::PNGCodec::EncodeBGRASkBitmap(bitmap, false);
  return png ? EncodedCapture{std::move(*png), gfx::Size(bitmap.width(), bitmap.height())}
             : EncodedCapture{};
}
EncodedCapture DecodeProtocolPNG(std::string encoded) {
  std::string bytes;
  if (!base::Base64Decode(encoded, &bytes)) return {};
  auto span = base::as_byte_span(bytes);
  SkBitmap bitmap = gfx::PNGCodec::Decode(span);
  if (bitmap.drawsNothing()) return {};
  return {std::vector<uint8_t>(span.begin(), span.end()),
          gfx::Size(bitmap.width(), bitmap.height())};
}
constexpr double kFullPageMaxSide = 16384;
constexpr double kFullPageMaxPixels = 80000000;
double FullPageScale(double width, double height, double density) {
  if (!std::isfinite(width) || !std::isfinite(height) || !std::isfinite(density) ||
      width < 1 || height < 1 || density <= 0) return 0;
  const double device_width = width * density, device_height = height * density;
  const double scale = std::min({1.0, (kFullPageMaxSide - 1) / device_width,
      (kFullPageMaxSide - 1) / device_height,
      std::sqrt(kFullPageMaxPixels * 0.999 / (device_width * device_height))});
  return std::ceil(device_width * scale) >= 1 && std::ceil(device_height * scale) >= 1 ? scale : 0;
}
void PostFailure(CaptureCompletion completion, NSString* error) {
  auto result = [[PCNativePageCaptureResult alloc]
      initWithData:nil size:NSZeroSize error:error layout:nil];
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce([](CaptureCompletion callback, PCNativePageCaptureResult* value) {
        callback(value);
      }, [completion copy], result));
}

bool PageShownInWindow(PCNativeBrowserWindow* binding, PCNativePage* page) {
  return [[binding.client visibleNativePages] containsObject:page];
}

bool CaptureEligible(PCNativePage* page, content::WebContents* contents,
                     NSWindow* window, bool require_key) {
  if (!page || page.closed || !contents || contents->IsBeingDestroyed() ||
      !window || page.nativeView.window != window ||
      !PageCaptureWindowAdmits({.app_active = static_cast<bool>(NSApp.active),
                                .visible = static_cast<bool>(window.visible),
                                .miniaturized = static_cast<bool>(window.miniaturized),
                                .key = static_cast<bool>(window.keyWindow),
                                .attached_sheet = window.attachedSheet != nil,
                                .security_reservation =
                                    PCNativeWindowHasSecurityReservation(window)},
                               require_key) ||
      page.nativeView.hiddenOrHasHiddenAncestor || contents->IsCrashed() ||
      contents->GetVisibility() != content::Visibility::VISIBLE ||
      !contents->GetPrimaryMainFrame() ||
      !contents->GetPrimaryMainFrame()->IsRenderFrameLive() ||
      !contents->GetRenderWidgetHostView() || IsNativePageRetiring(page) ||
      IsLiveTabTransferTarget(contents)) return false;
  auto* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  if (!profile || profile->ShutdownStarted() ||
      IsNativeProfileRemovalBlocked(profile->GetPath()) ||
      profile->GetPrefs()->GetBoolean(prefs::kDisableScreenshots)) return false;
#if BUILDFLAG(ENTERPRISE_SCREENSHOT_PROTECTION)
  auto* controller = enterprise_data_protection::DataProtectionNavigationController::
      FromWebContents(contents);
  if (controller && !controller->screenshot_allowed()) return false;
#endif
  auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents);
  if (!browser || browser->IsDeleteScheduled() || !AppKitBrowserAcceptsNewPages(*browser) ||
      !browser->GetWindow() ||
      browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() != window) return false;
  auto* binding = AppKitBindingForBrowser(browser);
  return binding && PageShownInWindow(binding, page);
}
class PageCapture;
auto& ActiveCaptures() {
  static base::NoDestructor<std::map<content::WebContents*, PageCapture*>> captures;
  return *captures;
}

class PageCapture final : public content::WebContentsObserver,
                          public ProfileObserver,
                          public content::RenderWidgetHostObserver,
                          public content::DevToolsAgentHostClient,
                          public std::enable_shared_from_this<PageCapture> {
 public:
  PageCapture(PCNativePage* page, content::WebContents& contents, NSWindow* window,
              PageCapturePurpose purpose, void (^invalidated)())
      : content::WebContentsObserver(&contents), purpose_(purpose), page_(page), window_(window),
        document_(contents.GetPrimaryMainFrame()->GetWeakDocumentPtr()),
        profile_(Profile::FromBrowserContext(contents.GetBrowserContext())->GetWeakPtr()),
        invalidated_([invalidated copy]),
        runner_(base::SequencedTaskRunner::GetCurrentDefault()) {
    auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(&contents);
    if (browser) browser_ = browser->GetWeakPtr();
    host_size_ = page.nativeView.bounds.size;
    auto* view = contents.GetRenderWidgetHostView();
    if (view) {
      viewport_ = view->GetViewBounds().size();
      NSView* renderer = view->GetNativeView().GetNativeNSView();
      if (renderer) viewport_frame_ = [page.nativeView convertRect:renderer.bounds fromView:renderer];
    }
  }
  ~PageCapture() override { Invalidate(false); }

  bool Start() {
    if (!CanCapture() || viewport_.IsEmpty()) return false;
    profile_observer_.Observe(profile_.get());
    widget_observer_.Observe(web_contents()->GetPrimaryMainFrame()->GetRenderWidgetHost());
    pref_observer_.Init(profile_->GetPrefs());
    pref_observer_.Add(prefs::kDisableScreenshots,
        base::BindRepeating(&PageCapture::PolicyChanged, weak_factory_.GetWeakPtr()));
#if BUILDFLAG(ENTERPRISE_SCREENSHOT_PROTECTION)
    if (auto* controller = enterprise_data_protection::DataProtectionNavigationController::
            FromWebContents(web_contents())) {
      policy_subscription_ = controller->RegisterScreenshotAllowedUpdatedCallback(
          base::BindRepeating([](base::WeakPtr<PageCapture> weak, bool) {
            if (weak) weak->PolicyChanged();
          }, weak_factory_.GetWeakPtr()));
    }
#endif
    auto weak = weak_factory_.GetWeakPtr();
    for (NSNotificationName name in @[NSWindowWillCloseNotification,
        NSWindowDidMiniaturizeNotification, PCNativeWindowSecurityStateChanged]) {
      [observers_ addObject:[NSNotificationCenter.defaultCenter
          addObserverForName:name object:window_ queue:nil usingBlock:^(NSNotification* note) {
            if (weak && (![note.name isEqualToString:PCNativeWindowSecurityStateChanged] ||
                PCNativeWindowHasSecurityReservation(weak->window_)))
              weak->Invalidate(true);
          }]];
    }
    return true;
  }

  NSColor* ThemeColor() const {
    if (!Valid()) return nil;
    const auto color = web_contents()->GetThemeColor();
    if (!color) return nil;
    return [NSColor colorWithSRGBRed:SkColorGetR(*color) / 255.0
                             green:SkColorGetG(*color) / 255.0
                              blue:SkColorGetB(*color) / 255.0
                             alpha:SkColorGetA(*color) / 255.0];
  }

  bool Valid() const {
    auto* contents = web_contents();
    PCNativePage* page = page_;
    if (!valid_ || !contents || contents->IsBeingDestroyed() || !page || page.closed ||
        !window_ || page.nativeView.window != window_ || !profile_ ||
        profile_->ShutdownStarted() || IsNativeProfileRemovalBlocked(profile_->GetPath()) ||
        contents->GetBrowserContext() != profile_.get() || IsNativePageRetiring(page) ||
        IsLiveTabTransferTarget(contents) || !browser_ || browser_->IsDeleteScheduled() ||
        !AppKitBrowserAcceptsNewPages(*browser_) ||
        GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents) != browser_.get() ||
        !browser_->GetWindow() ||
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() != window_ ||
        ContentsForNativePage(page) != contents ||
        document_.AsRenderFrameHostIfValid() != contents->GetPrimaryMainFrame()) return false;
    auto* binding = AppKitBindingForBrowser(browser_.get());
    return binding && PageShownInWindow(binding, page) &&
        GeometryMatches() && PolicyAllowsCapture();
  }
  bool Capturing() const { return completion_ || element_completion_; }
  NSSize ViewportSize() const { return NSMakeSize(viewport_.width(), viewport_.height()); }
  NSRect ViewportFrame() const { return viewport_frame_; }

  void Invalidate(bool notify) {
    auto keep_alive = weak_from_this().lock();
    if (!valid_) return;
    valid_ = false;
    if (element_completion_) {
      auto completion = element_completion_;
      element_completion_ = nil;
      PostFailure(completion, @"The source page is no longer available for this capture.");
    }
    ClearTarget();
    StopProtocol(true);
    ReleaseOperation();
    timer_.Stop();
    weak_factory_.InvalidateWeakPtrs();
    pref_observer_.RemoveAll();
    profile_observer_.Reset();
    widget_observer_.Reset();
    policy_subscription_ = {};
    for (id observer in observers_)
      [NSNotificationCenter.defaultCenter removeObserver:observer];
    [observers_ removeAllObjects];
    if (completion_) {
      auto completion = completion_;
      completion_ = nil;
      PostFailure(completion, @"The source page is no longer available for this capture.");
    }
    auto callback = invalidated_;
    invalidated_ = nil;
    if (notify && callback) {
      runner_->PostTask(FROM_HERE, base::BindOnce([](void (^block)()) { block(); }, callback));
    }
  }

  void TargetElement(NSPoint point, TargetCompletion completion) {
    if (!completion) return;
    if (Capturing() || PageCaptureViewportOnly(purpose_)) { PostTarget(completion, nil); return; }
    if (ActiveCaptures().contains(web_contents()) || !CanCapture() ||
        !std::isfinite(point.x) || !std::isfinite(point.y) ||
        point.x < 0 || point.y < 0 || point.x >= viewport_.width() ||
        point.y >= viewport_.height()) {
      ClearTarget();
      PostTarget(completion, nil);
      if (!Valid()) Invalidate(true);
      return;
    }
    QueueTarget(point, completion);
  }

  void CaptureElement(PCNativePageCaptureTarget* target, CaptureCompletion completion) {
    if (!completion) return;
    if (!target || target != offered_target_ || Capturing() || PageCaptureViewportOnly(purpose_) ||
        !CanCapture()) {
      PostFailure(completion, @"This element selection is no longer available.");
      return;
    }
    offered_target_ = nil;
    element_completion_ = [completion copy];
    auto weak = weak_factory_.GetWeakPtr();
    QueueTarget(target.queryPoint, ^(PCNativePageCaptureTarget* current) {
      if (weak) weak->ElementRevalidated(target, current);
    });
  }

  void Capture(NSRect region, bool full_page, CaptureCompletion completion) {
    auto keep_alive = weak_from_this().lock();
    if (!completion) return;
    if (Capturing() || ActiveCaptures().contains(web_contents())) {
      PostFailure(completion, @"A capture is already in progress.");
      return;
    }
    if (PageCaptureViewportOnly(purpose_) &&
        (full_page || !NSEqualRects(region, NSMakeRect(0, 0, viewport_.width(),
                                                       viewport_.height())))) {
      PostFailure(completion, @"This capture copies only the visible page.");
      return;
    }
    if (!CanCapture()) {
      PostFailure(completion, @"This page cannot be captured in its current state.");
      if (!Valid()) Invalidate(true);
      return;
    }
    ClearTarget();
    gfx::Rect area;
    if (!full_page) {
      if (!std::isfinite(region.origin.x) || !std::isfinite(region.origin.y) ||
          !std::isfinite(region.size.width) || !std::isfinite(region.size.height) ||
          region.origin.x < 0 || region.origin.y < 0 || region.size.width <= 0 ||
          region.size.height <= 0 || NSMaxX(region) > viewport_.width() ||
          NSMaxY(region) > viewport_.height()) {
        PostFailure(completion, @"The selected region is outside the original viewport.");
        return;
      }
      area = gfx::ToEnclosingRect(gfx::RectF(region.origin.x, region.origin.y,
                                            region.size.width, region.size.height));
    }
    ActiveCaptures()[web_contents()] = this;
    completion_ = [completion copy];
    const uint64_t request = ++request_;
    timer_.Start(FROM_HERE, base::Seconds(30), base::BindOnce(
        &PageCapture::Timeout, weak_factory_.GetWeakPtr(), request));
    if (full_page) {
      StartFullPage(request);
      return;
    }
    capture_area_ = area;
    capture_geometry_ = base::Value();
    capture_layout_ = nil;
    ReadGeometry(request, false, SkBitmap());
  }

 private:
  void ReadGeometry(uint64_t request, bool after_copy, SkBitmap bitmap) {
    if (!completion_ || request != request_ || !Valid()) return;
    const double zoom = blink::ZoomLevelToZoomFactor(content::HostZoomMap::GetZoomLevel(web_contents()));
    const gfx::PointF centre = std::isfinite(zoom) && zoom > 0 ?
        gfx::PointF(capture_area_.CenterPoint().x() / zoom, capture_area_.CenterPoint().y() / zoom) :
        gfx::PointF();
    document_.AsRenderFrameHostIfValid()->ExecuteJavaScriptInIsolatedWorld(
        GeometryQuery(centre), base::BindOnce(&PageCapture::GeometryRead, weak_factory_.GetWeakPtr(),
          request, after_copy, std::move(bitmap)), ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }
  void GeometryRead(uint64_t request, bool after_copy, SkBitmap bitmap, base::Value value) {
    if (!completion_ || request != request_) return;
    if (!Valid()) { Invalidate(true); return; }
    const double zoom = blink::ZoomLevelToZoomFactor(content::HostZoomMap::GetZoomLevel(web_contents()));
    if (after_copy) {
      if (value == capture_geometry_ && zoom == capture_zoom_) {
        const auto* dict = value.GetIfDict();
        auto w = dict ? dict->FindDouble("width") : std::nullopt;
        auto h = dict ? dict->FindDouble("height") : std::nullopt;
        auto x = dict ? dict->FindDouble("x") : std::nullopt;
        auto y = dict ? dict->FindDouble("y") : std::nullopt;
        auto scale = dict ? dict->FindDouble("scale") : std::nullopt;
        if (w && h && x && y && scale && std::isfinite(*w) && std::isfinite(*h) &&
            std::isfinite(*x) && std::isfinite(*y) && std::isfinite(*scale) &&
            *w > 0 && *h > 0 && *w <= 16384 && *h <= 16384 &&
            std::abs(*x) <= 1000000 && std::abs(*y) <= 1000000 && *scale > 0 &&
            std::isfinite(zoom) && zoom > 0) {
          const double factor = zoom * *scale;
          auto containers = ScrollContainersFrom(*dict);
          if (containers) {
            capture_layout_ = [[PCNativeCaptureLayout alloc]
                initWithViewport:NSMakeSize(*w, *h) scroll:NSMakePoint(*x, *y)
                region:NSMakeRect(capture_area_.x() / factor, capture_area_.y() / factor,
                    capture_area_.width() / factor, capture_area_.height() / factor)
                scrollContainers:*containers];
          }
        }
      }
      EncodeSurface(request, std::move(bitmap));
      return;
    }
    capture_geometry_ = std::move(value);
    capture_zoom_ = zoom;
    auto weak = weak_factory_.GetWeakPtr();
    web_contents()->GetRenderWidgetHostView()->CopyFromSurface(
        capture_area_, gfx::Size(), base::Seconds(10),
        base::BindOnce([](scoped_refptr<base::SequencedTaskRunner> runner,
                         base::WeakPtr<PageCapture> weak, uint64_t request,
                         const content::CopyFromSurfaceResult& result) {
          runner->PostTask(FROM_HERE, base::BindOnce(&PageCapture::SurfaceCopied,
              weak, request, result.has_value() ? result->bitmap : SkBitmap()));
        }, runner_, weak, request));
  }

  void ClearTarget() {
    ++target_generation_;
    ++target_query_;
    target_inflight_ = false;
    target_timer_.Stop();
    offered_target_ = nil;
    if (target_completion_) {
      auto callback = target_completion_;
      target_completion_ = nil;
      PostTarget(callback, nil);
    }
  }
  void QueueTarget(NSPoint point, TargetCompletion completion) {
    ++target_generation_;
    offered_target_ = nil;
    if (target_completion_) PostTarget(target_completion_, nil);
    target_completion_ = [completion copy];
    target_point_ = point;
    if (!target_inflight_) StartTarget();
  }
  void StartTarget() {
    if (!target_completion_) return;
    if (!CanCapture() || completion_ || ActiveCaptures().contains(web_contents())) {
      ClearTarget();
      return;
    }
    const double zoom = blink::ZoomLevelToZoomFactor(
        content::HostZoomMap::GetZoomLevel(web_contents()));
    if (!std::isfinite(zoom) || zoom <= 0) { ClearTarget(); return; }
    const uint64_t generation = target_generation_;
    const uint64_t query = ++target_query_;
    NSPoint point = target_point_;
    target_inflight_ = true;
    target_timer_.Start(FROM_HERE, base::Seconds(2), base::BindOnce(
        &PageCapture::TargetResult, weak_factory_.GetWeakPtr(), query, generation,
        point, zoom, base::Value()));
    document_.AsRenderFrameHostIfValid()->ExecuteJavaScriptInIsolatedWorld(
        ElementQuery(point, zoom), base::BindOnce(
            [](scoped_refptr<base::SequencedTaskRunner> runner,
               base::WeakPtr<PageCapture> weak, uint64_t query, uint64_t generation,
               NSPoint point, double zoom, base::Value value) {
              runner->PostTask(FROM_HERE, base::BindOnce(&PageCapture::TargetResult,
                  weak, query, generation, point, zoom, std::move(value)));
            }, runner_, weak_factory_.GetWeakPtr(), query, generation, point, zoom),
        ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }
  void TargetResult(uint64_t query, uint64_t generation, NSPoint point,
                    double zoom, base::Value value) {
    auto keep_alive = weak_from_this().lock();
    if (!target_inflight_ || query != target_query_) return;
    target_inflight_ = false;
    target_timer_.Stop();
    if (generation != target_generation_) { StartTarget(); return; }
    auto completion = target_completion_;
    target_completion_ = nil;
    if (!completion) return;
    PCNativePageCaptureTarget* target = nil;
    if (CanCapture() && !completion_ &&
        zoom == blink::ZoomLevelToZoomFactor(content::HostZoomMap::GetZoomLevel(web_contents()))) {
      const auto* dict = value.GetIfDict();
      auto x = dict ? dict->FindDouble("x") : std::nullopt;
      auto y = dict ? dict->FindDouble("y") : std::nullopt;
      auto w = dict ? dict->FindDouble("width") : std::nullopt;
      auto h = dict ? dict->FindDouble("height") : std::nullopt;
      auto ox = dict ? dict->FindDouble("offsetX") : std::nullopt;
      auto oy = dict ? dict->FindDouble("offsetY") : std::nullopt;
      auto scale = dict ? dict->FindDouble("scale") : std::nullopt;
      if (x && y && w && h && ox && oy && scale &&
          std::isfinite(*x) && std::isfinite(*y) && std::isfinite(*w) &&
          std::isfinite(*h) && std::isfinite(*ox) && std::isfinite(*oy) &&
          std::isfinite(*scale) && *w > 0 && *h > 0 && *scale > 0) {
        const double factor = *scale * zoom;
        NSRect rect = NSMakeRect((*x - *ox) * factor, (*y - *oy) * factor,
                                 *w * factor, *h * factor);
        if (std::isfinite(rect.origin.x) && std::isfinite(rect.origin.y) &&
            std::isfinite(rect.size.width) && std::isfinite(rect.size.height)) {
          rect = NSIntersectionRect(rect, NSMakeRect(0, 0, viewport_.width(), viewport_.height()));
          if (!NSIsEmptyRect(rect)) target = [[PCNativePageCaptureTarget alloc]
              initWithRect:rect point:point zoom:zoom];
        }
      }
    }
    offered_target_ = target;
    runner_->PostTask(FROM_HERE, base::BindOnce(
        [](base::WeakPtr<PageCapture> weak, uint64_t generation,
           TargetCompletion callback, PCNativePageCaptureTarget* target) {
          callback(weak && weak->target_generation_ == generation && weak->CanCapture()
                       ? target : nil);
        }, weak_factory_.GetWeakPtr(), generation, completion, target));
  }
  void ElementRevalidated(PCNativePageCaptureTarget* expected,
                          PCNativePageCaptureTarget* current) {
    auto keep_alive = weak_from_this().lock();
    if (!element_completion_) return;
    auto completion = element_completion_;
    element_completion_ = nil;
    offered_target_ = nil;
    if (!current || !NSEqualRects(expected.viewportRect, current.viewportRect) ||
        expected.pageZoom != current.pageZoom) {
      PostFailure(completion, @"The element moved. Select it again before capturing.");
      return;
    }
    NSRect area = NSIntersectionRect(NSInsetRect(current.viewportRect, -2, -2),
        NSMakeRect(0, 0, viewport_.width(), viewport_.height()));
    Capture(area, false, completion);
  }
  bool GeometryMatches() const {
    if (!page_ || !NSEqualSizes(page_.nativeView.bounds.size, host_size_)) return false;
    if (protocol_inflight_ || restoring_) return true;
    auto* view = web_contents() ? web_contents()->GetRenderWidgetHostView() : nullptr;
    NSView* renderer = view ? view->GetNativeView().GetNativeNSView() : nil;
    return renderer && view->GetViewBounds().size() == viewport_ &&
        NSEqualRects([page_.nativeView convertRect:renderer.bounds fromView:renderer],
                     viewport_frame_);
  }
  void CheckGeometry() { if (!GeometryMatches()) Invalidate(true); }
  bool PolicyAllowsCapture() const {
    if (!profile_ || !web_contents() ||
        profile_->GetPrefs()->GetBoolean(prefs::kDisableScreenshots)) return false;
#if BUILDFLAG(ENTERPRISE_SCREENSHOT_PROTECTION)
    auto* controller = enterprise_data_protection::DataProtectionNavigationController::
        FromWebContents(web_contents());
    if (controller && !controller->screenshot_allowed()) return false;
#endif
    return true;
  }
  bool CanCapture() const {
    return Valid() &&
        CaptureEligible(page_, web_contents(), window_, PageCaptureNeedsKeyWindow(purpose_)) &&
        web_contents()->GetRenderWidgetHostView()->GetViewBounds().size() == viewport_;
  }
  void ReleaseOperation() {
    auto it = ActiveCaptures().find(web_contents());
    if (it != ActiveCaptures().end() && it->second == this) ActiveCaptures().erase(it);
  }
  void PolicyChanged() { if (!PolicyAllowsCapture()) Invalidate(true); }
  void SurfaceCopied(uint64_t request, SkBitmap bitmap) {
    if (!completion_ || request != request_) return;
    if (!Valid()) { Invalidate(true); return; }
    ReadGeometry(request, true, std::move(bitmap));
  }
  void EncodeSurface(uint64_t request, SkBitmap bitmap) {
    base::ThreadPool::PostTaskAndReplyWithResult(FROM_HERE,
        {base::TaskPriority::USER_VISIBLE}, base::BindOnce(&EncodeBitmap, std::move(bitmap)),
        base::BindOnce(&PageCapture::Deliver, weak_factory_.GetWeakPtr(), request));
  }
  void StartFullPage(uint64_t request) {
    capture_layout_ = nil;
    agent_ = content::DevToolsAgentHost::GetOrCreateFor(web_contents());
    if (!agent_ || agent_->IsAttached() || !agent_->AttachClient(this)) {
      agent_.reset();
      Fail(request, @"Close this page’s developer tools before capturing the full page.");
      return;
    }
    attached_ = true;
    const auto& prefs = web_contents()->GetOrCreateWebPreferences();
    original_hide_scrollbars_ = prefs.hide_scrollbars;
    original_record_document_ = prefs.record_whole_document;
    protocol_inflight_ = true;
    constexpr std::string_view command = R"({"id":1,"method":"Page.getLayoutMetrics"})";
    agent_->DispatchProtocolMessage(this, base::as_byte_span(command));
  }
  void FullPageMeasured(uint64_t request, double width, double height,
                        double viewport_width, double viewport_height) {
    auto keep_alive = weak_from_this().lock();
    if (!completion_ || request != request_) return;
    if (!Valid()) { Invalidate(true); return; }
    auto* view = web_contents()->GetRenderWidgetHostView();
    const double density = view ? view->GetDeviceScaleFactor() : 0;
    const double scale = FullPageScale(width, height, density);
    if (!agent_ || !attached_ || scale <= 0) {
      Fail(request, @"The renderer could not measure the full page.");
      return;
    }
    if (std::isfinite(viewport_width) && std::isfinite(viewport_height) &&
        viewport_width >= 1 && viewport_height >= 1 &&
        viewport_width <= kFullPageMaxSide && viewport_height <= kFullPageMaxSide) {
      capture_layout_ = [[PCNativeCaptureLayout alloc]
          initWithViewport:NSMakeSize(viewport_width, viewport_height) scroll:NSZeroPoint
          region:NSMakeRect(0, 0, viewport_width, viewport_height) scrollContainers:@[]];
    }
    base::DictValue clip;
    clip.Set("x", 0);
    clip.Set("y", 0);
    clip.Set("width", width);
    clip.Set("height", height);
    clip.Set("scale", scale);
    base::DictValue params;
    params.Set("format", "png");
    params.Set("fromSurface", true);
    params.Set("captureBeyondViewport", true);
    params.Set("clip", std::move(clip));
    base::DictValue command;
    command.Set("id", 2);
    command.Set("method", "Page.captureScreenshot");
    command.Set("params", std::move(params));
    std::string json;
    if (!base::JSONWriter::Write(command, &json)) {
      Fail(request, @"The renderer could not capture the full page.");
      return;
    }
    agent_->DispatchProtocolMessage(this, base::as_byte_span(json));
  }
  void StopProtocol(bool restore) {
    auto keep_alive = weak_from_this().lock();
    if (restoring_) return;
    restoring_ = true;
    if (agent_ && attached_) {
      attached_ = false;
      agent_->DetachClient(this);
    }
    agent_.reset();
    if (!protocol_inflight_) { restoring_ = false; return; }
    protocol_inflight_ = false;
    auto* contents = web_contents();
    if (!restore || !contents || contents->IsBeingDestroyed()) {
      restoring_ = false;
      return;
    }
    auto prefs = contents->GetOrCreateWebPreferences();
    prefs.hide_scrollbars = original_hide_scrollbars_;
    prefs.record_whole_document = original_record_document_;
    contents->SetWebPreferences(prefs);
    if (document_.AsRenderFrameHostIfValid() == contents->GetPrimaryMainFrame() &&
        page_ && ContentsForNativePage(page_) == contents &&
        page_.nativeView.window == window_) {
      NSView* container = contents->GetNativeView().GetNativeNSView();
      if (auto* view = contents->GetRenderWidgetHostView(); view && container) {
        NSSize size = container.bounds.size;
        if (size.width > 0 && size.height > 0)
          view->SetSize(gfx::Size(std::lround(size.width), std::lround(size.height)));
      }
    }
    restoring_ = false;
  }
  void DispatchProtocolMessage(content::DevToolsAgentHost* agent,
                               base::span<const uint8_t> message) override {
    if (agent != agent_.get() || !attached_ || !completion_) return;
    auto parsed = base::JSONReader::Read(base::as_string_view(message),
                                        base::JSON_PARSE_RFC);
    const base::DictValue* value = parsed ? parsed->GetIfDict() : nullptr;
    const std::optional<int> id = value ? value->FindInt("id") : std::nullopt;
    if (!id || (*id != 1 && *id != 2)) return;
    const uint64_t request = request_;
    if (*id == 1) {
      auto read = [value](std::string_view path) {
        return value->FindDoubleByDottedPath(path).value_or(0);
      };
      runner_->PostTask(FROM_HERE, base::BindOnce(&PageCapture::FullPageMeasured,
          weak_factory_.GetWeakPtr(), request, read("result.cssContentSize.width"),
          read("result.cssContentSize.height"), read("result.cssLayoutViewport.clientWidth"),
          read("result.cssLayoutViewport.clientHeight")));
      return;
    }
    const std::string* data = value->FindStringByDottedPath("result.data");
    std::string encoded = data ? *data : std::string();
    runner_->PostTask(FROM_HERE, base::BindOnce(&PageCapture::ProtocolResult,
        weak_factory_.GetWeakPtr(), request, std::move(encoded)));
  }
  void ProtocolResult(uint64_t request, std::string encoded) {
    auto keep_alive = weak_from_this().lock();
    if (!completion_ || request != request_) return;
    StopProtocol(true);
    if (!Valid()) { Invalidate(true); return; }
    if (encoded.empty()) {
      Fail(request, @"The renderer could not capture the full page.");
      return;
    }
    base::ThreadPool::PostTaskAndReplyWithResult(FROM_HERE,
        {base::TaskPriority::USER_VISIBLE},
        base::BindOnce(&DecodeProtocolPNG, std::move(encoded)),
        base::BindOnce(&PageCapture::Deliver, weak_factory_.GetWeakPtr(), request));
  }
  void AgentHostClosed(content::DevToolsAgentHost*) override {
    attached_ = false;
    runner_->PostTask(FROM_HERE, base::BindOnce(&PageCapture::Invalidate,
        weak_factory_.GetWeakPtr(), true));
  }
  bool MayAttachToURL(const GURL& url, bool) override {
    return Valid() && url == web_contents()->GetLastCommittedURL();
  }
  bool MayAttachToRenderFrameHost(content::RenderFrameHost* frame) override {
    return Valid() && frame == document_.AsRenderFrameHostIfValid();
  }
  bool IsTrusted() override { return false; }
  bool MayReadLocalFiles() override { return false; }
  bool MayWriteLocalFiles() override { return false; }
  bool AllowUnsafeOperations() override { return false; }
  void Deliver(uint64_t request, EncodedCapture encoded) {
    if (!completion_ || request != request_) return;
    if (!Valid()) { Invalidate(true); return; }
    timer_.Stop();
    ReleaseOperation();
    auto completion = completion_;
    completion_ = nil;
    NSData* data = encoded.png.empty() ? nil :
        [NSData dataWithBytes:encoded.png.data() length:encoded.png.size()];
    auto result = [[PCNativePageCaptureResult alloc] initWithData:data
        size:NSMakeSize(encoded.pixels.width(), encoded.pixels.height())
        error:data ? nil : @"The renderer returned no usable capture pixels."
        layout:data ? capture_layout_ : nil];
    completion(result);
  }
  void Fail(uint64_t request, NSString* error) {
    auto keep_alive = weak_from_this().lock();
    if (!completion_ || request != request_) return;
    StopProtocol(true);
    timer_.Stop();
    ReleaseOperation();
    auto completion = completion_;
    completion_ = nil;
    PostFailure(completion, error);
  }
  void Timeout(uint64_t request) {
    Fail(request, @"The page capture did not finish in time.");
  }
  void DidStartNavigation(content::NavigationHandle* handle) override {
    if (handle->IsInPrimaryMainFrame() && !handle->IsSameDocument()) Invalidate(true);
  }
  void PrimaryPageChanged(content::Page&) override { Invalidate(true); }
  void WebContentsDestroyed() override { Invalidate(true); }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override { Invalidate(true); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN) Invalidate(true);
  }
  void OnProfileWillBeDestroyed(Profile*) override { Invalidate(true); }
  void PrimaryMainFrameWasResized(bool) override { CheckGeometry(); }
  void RenderWidgetHostDidUpdateVisualProperties(content::RenderWidgetHost*) override {
    CheckGeometry();
  }
  void RenderWidgetHostDestroyed(content::RenderWidgetHost*) override {
    Invalidate(true);
  }

  const PageCapturePurpose purpose_;
  PCNativePage* __weak page_;
  NSWindow* __weak window_;
  content::WeakDocumentPtr document_;
  base::WeakPtr<Profile> profile_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  gfx::Size viewport_;
  gfx::Rect capture_area_;
  base::Value capture_geometry_;
  double capture_zoom_ = 1;
  PCNativeCaptureLayout* __strong capture_layout_ = nil;
  NSRect viewport_frame_ = NSZeroRect;
  NSSize host_size_ = NSZeroSize;
  bool valid_ = true;
  bool attached_ = false;
  bool protocol_inflight_ = false;
  bool restoring_ = false;
  bool original_hide_scrollbars_ = false;
  bool original_record_document_ = false;
  uint64_t request_ = 0;
  CaptureCompletion completion_ = nil;
  CaptureCompletion element_completion_ = nil;
  TargetCompletion target_completion_ = nil;
  PCNativePageCaptureTarget* __strong offered_target_ = nil;
  NSPoint target_point_ = NSZeroPoint;
  uint64_t target_generation_ = 0;
  uint64_t target_query_ = 0;
  bool target_inflight_ = false;
  void (^invalidated_)() = nil;
  NSMutableArray* __strong observers_ = [[NSMutableArray alloc] init];
  scoped_refptr<base::SequencedTaskRunner> runner_;
  scoped_refptr<content::DevToolsAgentHost> agent_;
  base::OneShotTimer timer_;
  base::OneShotTimer target_timer_;
  PrefChangeRegistrar pref_observer_;
  base::ScopedObservation<Profile, ProfileObserver> profile_observer_{this};
  base::CallbackListSubscription policy_subscription_;
  base::ScopedObservation<content::RenderWidgetHost, content::RenderWidgetHostObserver>
      widget_observer_{this};
  base::WeakPtrFactory<PageCapture> weak_factory_{this};
};
}
}

@interface PCNativePageCapture () {
 @public
  std::shared_ptr<parc::PageCapture> state;
}
- (instancetype)initWithPage:(PCNativePage*)page
                   contents:(content::WebContents&)contents window:(NSWindow*)window
                    purpose:(parc::PageCapturePurpose)purpose;
@end
@implementation PCNativePageCapture
@synthesize sourceURL = _sourceURL, pageTitle = _pageTitle, invalidated = _invalidated;
- (instancetype)initWithPage:(PCNativePage*)page
                   contents:(content::WebContents&)contents window:(NSWindow*)window
                    purpose:(parc::PageCapturePurpose)purpose {
  if ((self = [super init])) {
    _sourceURL = base::SysUTF8ToNSString(parc::PublicInternalURL(contents.GetLastCommittedURL()).spec());
    _pageTitle = base::SysUTF16ToNSString(contents.GetTitle());
    __weak PCNativePageCapture* weakSelf = self;
    state = std::make_shared<parc::PageCapture>(page, contents, window, purpose, ^{
      PCNativePageCapture* owner = weakSelf;
      if (owner.invalidated) owner.invalidated();
    });
    if (!state->Start()) return nil;
  }
  return self;
}
- (void)dealloc { if (state) state->Invalidate(false); }
- (BOOL)isValid { return state && state->Valid(); }
- (NSColor*)pageThemeColor { return state ? state->ThemeColor() : nil; }
- (BOOL)isCapturing { return state && state->Capturing(); }
- (NSSize)viewportSize { return state ? state->ViewportSize() : NSZeroSize; }
- (NSRect)viewportFrame { return state ? state->ViewportFrame() : NSZeroRect; }
- (void)invalidate { if (state) state->Invalidate(true); }
- (void)targetElementAtPoint:(NSPoint)point completion:(parc::TargetCompletion)completion {
  if (state) state->TargetElement(point, completion);
}
- (void)captureElement:(PCNativePageCaptureTarget*)target
           completion:(parc::CaptureCompletion)completion {
  if (state) state->CaptureElement(target, completion);
}
- (void)captureRegion:(NSRect)region completion:(parc::CaptureCompletion)completion {
  if (state) state->Capture(region, false, completion);
}
- (void)captureViewportWithCompletion:(parc::CaptureCompletion)completion {
  [self captureRegion:NSMakeRect(0, 0, self.viewportSize.width, self.viewportSize.height)
           completion:completion];
}
- (void)captureFullPageWithCompletion:(parc::CaptureCompletion)completion {
  if (state) state->Capture(NSZeroRect, true, completion);
}
@end

namespace parc {
namespace {
PCNativePageCapture* BeginPageCapture(PCNativePage* page, NSWindow* window,
                                      PageCapturePurpose purpose) {
  auto* contents = ContentsForNativePage(page);
  if (!contents || contents->IsBeingDestroyed() || !contents->GetPrimaryMainFrame() ||
      page.closed || page.nativeView.window != window) return nil;
  return [[PCNativePageCapture alloc] initWithPage:page contents:*contents window:window
                                           purpose:purpose];
}
}
}

@implementation PCNativePage (Capture)
- (BOOL)canCaptureInWindow:(NSWindow*)window {
  return parc::CaptureEligible(self, parc::ContentsForNativePage(self), window, false);
}
- (PCNativePageCapture*)beginCaptureInWindow:(NSWindow*)window {
  return parc::BeginPageCapture(self, window, parc::PageCapturePurpose::kPerson);
}
- (PCNativePageCapture*)beginPlaceholderCaptureInWindow:(NSWindow*)window {
  return parc::BeginPageCapture(self, window, parc::PageCapturePurpose::kPlaceholder);
}
@end

namespace parc {
class LiveCapturePosition final : public std::enable_shared_from_this<LiveCapturePosition> {
 public:
  LiveCapturePosition(PCNativePage* page, NSRect region, NSPoint scroll,
                      NSArray<PCNativeCaptureScrollContainer*>* containers,
                      double width, void (^completion)(BOOL))
      : page_(page), window_(page.nativeView.window), region_(region), scroll_(scroll),
        containers_(ContainersScript(containers)), width_(width), completion_([completion copy]) {
    auto* contents = ContentsForNativePage(page);
    if (contents && contents->GetPrimaryMainFrame()) {
      contents_ = contents->GetWeakPtr();
      document_ = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    }
  }
  void Cancel() { cancelled_ = true; Finish(false); }
  bool Valid() const {
    return !cancelled_ && page_ && !page_.closed && page_.embeddedOwnerValid &&
        window_ && page_.nativeView.window == window_ && contents_ &&
        ContentsForNativePage(page_) == contents_.get() && !contents_->IsBeingDestroyed() &&
        !contents_->IsCrashed() && !IsNativePageRetiring(page_) &&
        !IsLiveTabTransferTarget(contents_.get()) &&
        document_.AsRenderFrameHostIfValid() &&
        document_.AsRenderFrameHostIfValid()->IsRenderFrameLive() &&
        document_.AsRenderFrameHostIfValid() == contents_->GetPrimaryMainFrame();
  }
  void Run() {
    if (attempts_ == 0) {
      timer_.Start(FROM_HERE, base::Seconds(5), base::BindOnce(
          &LiveCapturePosition::Cancel, base::Unretained(this)));
    }
    if (!Valid() || attempts_++ >= 20) { Finish(false); return; }
    const double zoom = blink::ZoomLevelToZoomFactor(content::HostZoomMap::GetZoomLevel(contents_.get()));
    if (!std::isfinite(zoom) || zoom <= 0) { Finish(false); return; }
    const double scale = width_ / (region_.size.width * zoom);
    if (!std::isfinite(scale) || scale <= 0 || scale > 10000) { Finish(false); return; }
    auto n = [](double value) { return base::NumberToString(value); };
    std::string script = R"JS((() => {
      if (!document.body || !['interactive','complete'].includes(document.readyState)) return false;
      let aligned = true;)JS" + containers_ + R"JS(
      document.body.style.transformOrigin = 'top left';
      document.body.style.transform = 'scale()JS" + n(scale) + ") translate(" +
        n(-region_.origin.x) + "px," + n(-region_.origin.y) + R"JS(px)';
      window.scroll({left:)JS" + n(scroll_.x * scale) + ",top:" + n(scroll_.y * scale) + R"JS(,behavior:'instant'});
      return aligned && Math.abs(scrollX - )JS" + n(scroll_.x * scale) + ") < 3 && Math.abs(scrollY - " +
        n(scroll_.y * scale) + ") < 3; })()";
    auto self = shared_from_this();
    document_.AsRenderFrameHostIfValid()->ExecuteJavaScriptInIsolatedWorld(
        base::UTF8ToUTF16(script), base::BindOnce([](std::shared_ptr<LiveCapturePosition> owner, base::Value value) {
          if (!owner->Valid()) { owner->Finish(false); return; }
          if (value.is_bool() && value.GetBool()) { owner->Finish(true); return; }
          base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(FROM_HERE,
              base::BindOnce(&LiveCapturePosition::Run, owner), base::Milliseconds(100));
        }, self), ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }
 private:
  std::string ContainersScript(NSArray<PCNativeCaptureScrollContainer*>* containers) const {
    if (containers.count == 0) return std::string();
    base::ListValue list;
    for (PCNativeCaptureScrollContainer* container in containers) {
      base::DictValue entry;
      if (container.anchorID) entry.Set("anchor", base::SysNSStringToUTF8(container.anchorID));
      else entry.Set("anchor", base::Value());
      entry.Set("path", base::SysNSStringToUTF8(container.path));
      entry.Set("x", container.scrollOffset.x);
      entry.Set("y", container.scrollOffset.y);
      entry.Set("left", container.frame.origin.x);
      entry.Set("top", container.frame.origin.y);
      entry.Set("width", container.frame.size.width);
      entry.Set("height", container.frame.size.height);
      list.Append(std::move(entry));
    }
    auto json = base::WriteJson(list);
    if (!json) return "aligned = false;";
    auto n = [](double value) { return base::NumberToString(value); };
    return "const containers = " + *json + R"JS(;
      const find = (anchor, path) => {
        let node = anchor === null ? document.documentElement : document.getElementById(anchor);
        for (const step of path ? path.split('>') : []) {
          if (!node) return null;
          if (step === '^') { node = node.shadowRoot; continue; }
          const [tag, index] = step.split(':');
          node = Array.prototype.filter.call(node.children, c => c.localName === tag)[Number(index)];
        }
        return node instanceof Element ? node : null;
      };
      document.body.style.transform = '';
      for (const c of containers) {
        c.element = find(c.anchor, c.path);
        if (!c.element) { aligned = false; continue; }
        c.element.scrollTo({left:c.x, top:c.y, behavior:'instant'});
        if (Math.abs(c.element.scrollLeft - c.x) >= 3 || Math.abs(c.element.scrollTop - c.y) >= 3) aligned = false;
      }
      window.scroll({left:)JS" + n(scroll_.x) + ",top:" + n(scroll_.y) + R"JS(,behavior:'instant'});
      for (const c of containers) {
        if (!c.element) continue;
        const r = c.element.getBoundingClientRect();
        if (Math.abs(r.left + scrollX - c.left) > 4 || Math.abs(r.top + scrollY - c.top) > 4 ||
            Math.abs(r.width - c.width) > 4 || Math.abs(r.height - c.height) > 4) aligned = false;
      })JS";
  }
  void Finish(bool success) {
    timer_.Stop();
    cancelled_ = true;
    auto callback = completion_;
    completion_ = nil;
    if (callback) base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([](void (^block)(BOOL), bool result) { block(result); }, callback, success));
  }
  PCNativePage* __weak page_;
  NSWindow* __weak window_;
  base::WeakPtr<content::WebContents> contents_;
  content::WeakDocumentPtr document_;
  NSRect region_;
  NSPoint scroll_;
  std::string containers_;
  double width_;
  int attempts_ = 0;
  bool cancelled_ = false;
  base::OneShotTimer timer_;
  void (^completion_)(BOOL);
};
}
@interface PCNativeLiveCapturePosition () {
 @public
  std::shared_ptr<parc::LiveCapturePosition> state;
}
- (instancetype)initWithState:(std::shared_ptr<parc::LiveCapturePosition>)value;
@end
@implementation PCNativeLiveCapturePosition
- (instancetype)initWithState:(std::shared_ptr<parc::LiveCapturePosition>)value {
  if ((self = [super init])) state = std::move(value);
  return self;
}
- (void)cancel { if (state) state->Cancel(); }
- (void)dealloc { if (state) state->Cancel(); }
@end
@implementation PCNativePage (LiveCapture)
- (double)liveCaptureZoomFactor {
  auto* contents = parc::ContentsForNativePage(self);
  return contents && self.embeddedOwnerValid ?
      blink::ZoomLevelToZoomFactor(content::HostZoomMap::GetZoomLevel(contents)) : 1;
}
- (PCNativeLiveCapturePosition*)positionLiveCapture:(NSRect)region scrollOffset:(NSPoint)scroll
    scrollContainers:(NSArray<PCNativeCaptureScrollContainer*>*)containers
    displayWidth:(double)width completion:(void (^)(BOOL))completion {
  if (!containers || containers.count > parc::kMaxScrollContainers) return nil;
  for (id container in containers) {
    if (![container isKindOfClass:[PCNativeCaptureScrollContainer class]]) return nil;
  }
  if (!self.embeddedOwnerValid || !completion || !std::isfinite(width) || width <= 0 || width > 1000000 ||
      !std::isfinite(region.origin.x) || !std::isfinite(region.origin.y) ||
      !std::isfinite(region.size.width) || !std::isfinite(region.size.height) ||
      !std::isfinite(scroll.x) || !std::isfinite(scroll.y) || region.origin.x < 0 || region.origin.y < 0 ||
      region.size.width <= 0 || region.size.height <= 0 || NSMaxX(region) > 16385 || NSMaxY(region) > 16385 ||
      std::abs(scroll.x) > 1000000 || std::abs(scroll.y) > 1000000) return nil;
  auto state = std::make_shared<parc::LiveCapturePosition>(self, region, scroll, containers, width,
                                                           completion);
  if (!state->Valid()) return nil;
  auto request = [[PCNativeLiveCapturePosition alloc] initWithState:state];
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(&parc::LiveCapturePosition::Run, state));
  return request;
}
@end

namespace parc {
class EmbeddedPageSnapshot final : public std::enable_shared_from_this<EmbeddedPageSnapshot> {
 public:
  EmbeddedPageSnapshot(PCNativePage* page, content::WebContents& contents,
                       CaptureCompletion completion)
      : page_(page), contents_(contents.GetWeakPtr()),
        document_(contents.GetPrimaryMainFrame()->GetWeakDocumentPtr()),
        completion_([completion copy]), runner_(base::SequencedTaskRunner::GetCurrentDefault()) {}
  ~EmbeddedPageSnapshot() {
    if (capturer_) {
      runner_->PostTask(FROM_HERE, base::BindOnce([](base::ScopedClosureRunner) {}, std::move(capturer_)));
    }
    if (completion_) Reply(runner_, completion_, EncodedCapture());
  }
  static bool Eligible(PCNativePage* page, content::WebContents* contents) {
    if (!page || page.closed || !page.embeddedOwnerValid || !contents ||
        contents->IsBeingDestroyed() || contents->IsCrashed() || !contents->GetPrimaryMainFrame() ||
        !contents->GetPrimaryMainFrame()->IsRenderFrameLive() ||
        !contents->GetRenderWidgetHostView() || IsNativePageRetiring(page) ||
        IsLiveTabTransferTarget(contents)) return false;
    auto* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
    if (!profile || profile->ShutdownStarted() || IsNativeProfileRemovalBlocked(profile->GetPath()) ||
        profile->GetPrefs()->GetBoolean(prefs::kDisableScreenshots)) return false;
#if BUILDFLAG(ENTERPRISE_SCREENSHOT_PROTECTION)
    auto* controller = enterprise_data_protection::DataProtectionNavigationController::
        FromWebContents(contents);
    if (controller && !controller->screenshot_allowed()) return false;
#endif
    return true;
  }
  void Start() {
    if (!Valid()) { Finish(EncodedCapture()); return; }
    capturer_ = contents_->IncrementCapturerCount(gfx::Size(), true, false, false);
    runner_->PostDelayedTask(FROM_HERE, base::BindOnce([](std::weak_ptr<EmbeddedPageSnapshot> weak) {
      if (auto owner = weak.lock()) owner->Finish(EncodedCapture());
    }, weak_from_this()), base::Seconds(5));
    Attempt();
  }

 private:
  bool Valid() const {
    return !finished_ && page_ && contents_ && ContentsForNativePage(page_) == contents_.get() &&
        Eligible(page_, contents_.get()) &&
        document_.AsRenderFrameHostIfValid() == contents_->GetPrimaryMainFrame();
  }
  void Attempt() {
    if (finished_) return;
    if (!Valid()) { Finish(EncodedCapture()); return; }
    auto* view = contents_->GetRenderWidgetHostView();
    if (!view->IsSurfaceAvailableForCopy() || view->GetViewBounds().IsEmpty()) { Retry(); return; }
    view->CopyFromSurface(gfx::Rect(), gfx::Size(), base::Seconds(2), base::BindOnce(
        [](scoped_refptr<base::SequencedTaskRunner> runner,
           std::shared_ptr<EmbeddedPageSnapshot> owner, const content::CopyFromSurfaceResult& result) {
          runner->PostTask(FROM_HERE, base::BindOnce(&EmbeddedPageSnapshot::Copied, owner,
              result.has_value() ? result->bitmap : SkBitmap()));
        }, runner_, shared_from_this()));
  }
  void Retry() {
    if (++attempts_ >= 20) { Finish(EncodedCapture()); return; }
    runner_->PostDelayedTask(FROM_HERE,
        base::BindOnce(&EmbeddedPageSnapshot::Attempt, shared_from_this()), base::Milliseconds(100));
  }
  void Copied(SkBitmap bitmap) {
    if (finished_) return;
    if (!Valid()) { Finish(EncodedCapture()); return; }
    if (bitmap.drawsNothing()) { Retry(); return; }
    base::ThreadPool::PostTaskAndReplyWithResult(FROM_HERE,
        {base::TaskPriority::USER_VISIBLE}, base::BindOnce(&EncodeBitmap, std::move(bitmap)),
        base::BindOnce(&EmbeddedPageSnapshot::Finish, shared_from_this()));
  }
  void Finish(EncodedCapture encoded) {
    if (finished_) return;
    finished_ = true;
    capturer_.RunAndReset();
    auto completion = completion_;
    completion_ = nil;
    Reply(runner_, completion, std::move(encoded));
  }
  static void Reply(scoped_refptr<base::SequencedTaskRunner> runner, CaptureCompletion completion,
                    EncodedCapture encoded) {
    NSData* data = encoded.png.empty() ? nil :
        [NSData dataWithBytes:encoded.png.data() length:encoded.png.size()];
    auto result = [[PCNativePageCaptureResult alloc] initWithData:data
        size:NSMakeSize(encoded.pixels.width(), encoded.pixels.height())
        error:data ? nil : @"The embedded page could not be captured."
        layout:nil];
    runner->PostTask(FROM_HERE, base::BindOnce(
        [](CaptureCompletion callback, PCNativePageCaptureResult* value) { callback(value); },
        completion, result));
  }
  PCNativePage* __weak page_;
  base::WeakPtr<content::WebContents> contents_;
  content::WeakDocumentPtr document_;
  CaptureCompletion completion_ = nil;
  scoped_refptr<base::SequencedTaskRunner> runner_;
  base::ScopedClosureRunner capturer_;
  int attempts_ = 0;
  bool finished_ = false;
};
}
@implementation PCNativePage (EmbeddedSnapshot)
- (BOOL)snapshotEmbeddedPageWithCompletion:(void (^)(PCNativePageCaptureResult*))completion {
  auto* contents = parc::ContentsForNativePage(self);
  if (!completion || !parc::EmbeddedPageSnapshot::Eligible(self, contents)) return NO;
  auto state = std::make_shared<parc::EmbeddedPageSnapshot>(self, *contents, completion);
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(&parc::EmbeddedPageSnapshot::Start, state));
  return YES;
}
@end
