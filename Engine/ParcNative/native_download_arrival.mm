// Copyright 2026 Parc contributors.
#import "native_download_arrival.h"

#include <cmath>
#include "base/functional/bind.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "content/public/browser/host_zoom_map.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "native_appkit_host.h"
#include "native_appkit_page.h"
#include "native_page_retirement.h"
#include "native_profile_removal.h"
#include "tab_transfer.h"
#include "third_party/blink/public/common/page/page_zoom.h"
#import "window_security_reservation.h"

@interface PCNativeDownloadArrival ()
- (instancetype)initWithProfile:(Profile&)profile
    snapshot:(const parc::NativeDownloadSnapshot&)snapshot
    document:(content::WeakDocumentPtr)document context:(NSString*)context;
- (void)start;
- (void)resolved:(base::Value)value;
@end

namespace {
NSMapTable<PCNativeBrowserWindow*, PCNativeDownloadArrival*>* PendingArrivals() {
  static NSMapTable<PCNativeBrowserWindow*, PCNativeDownloadArrival*>* value =
      [NSMapTable weakToWeakObjectsMapTable];
  return value;
}
content::WeakDocumentPtr ArrivalDocument(content::WeakDocumentPtr document) {
  auto* frame = document.AsRenderFrameHostIfValid();
  auto* contents = frame ? content::WebContents::FromRenderFrameHost(frame) : nullptr;
  auto* devtools = contents ? DevToolsWindow::AsDevToolsWindow(contents) : nullptr;
  auto* inspected = devtools ? devtools->GetInspectedWebContents() : nullptr;
  return inspected ? inspected->GetPrimaryMainFrame()->GetWeakDocumentPtr()
                   : document;
}
}

@implementation PCNativeDownloadArrival {
  base::WeakPtr<Profile> _profile;
  base::WeakPtr<BrowserWindowInterface> _browser;
  content::WeakDocumentPtr _document;
  __weak PCNativeBrowserWindow* _binding;
  __weak NSWindow* _window;
  bool _resolved;
}
@synthesize page = _page, profilePath = _profilePath;
@synthesize downloadIdentifier = _downloadIdentifier, itemIdentity = _itemIdentity;
@synthesize privateContextIdentifier = _privateContextIdentifier;
@synthesize sourceScreenPoint = _sourceScreenPoint;

- (instancetype)initWithProfile:(Profile&)profile
    snapshot:(const parc::NativeDownloadSnapshot&)snapshot
    document:(content::WeakDocumentPtr)document context:(NSString*)context {
  auto* frame = document.AsRenderFrameHostIfValid();
  auto* contents = frame ? content::WebContents::FromRenderFrameHost(frame) : nullptr;
  auto* browser = contents ? GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents) : nullptr;
  PCNativePage* page = contents ? parc::ExistingNativePage(contents) : nil;
  PCNativeBrowserWindow* binding = browser ? parc::AppKitBindingForBrowser(browser) : nil;
  NSWindow* window = binding.window;
  if (!page || !binding || !window || contents->IsCrashed() ||
      contents->GetBrowserContext() != &profile ||
      profile.IsOffTheRecord() != (context != nil) ||
      !parc::AppKitBrowserAcceptsNewPages(*browser) ||
      parc::IsLiveTabTransferTarget(contents)) return nil;
  if ((self = [super init])) {
    _profile = profile.GetWeakPtr(); _browser = browser->GetWeakPtr();
    _document = std::move(document); _binding = binding; _window = window; _page = page;
    _profilePath = [base::SysUTF8ToNSString(profile.GetPath().value()) copy];
    _downloadIdentifier = [base::SysUTF8ToNSString(snapshot.guid) copy];
    _itemIdentity = [base::SysUTF8ToNSString(snapshot.item_identity) copy];
    _privateContextIdentifier = [context copy];
    id<PCNativeBrowserWindowClient> client = binding.client;
    if (!self.valid || !window.keyWindow || window.miniaturized ||
        PCNativeWindowHasSecurityReservation(window) ||
        [client nativeBrowserWindow] != window ||
        ![[client visibleNativePages] containsObject:page]) return nil;
  }
  return self;
}

- (BOOL)isValid {
  CHECK(NSThread.isMainThread);
  auto* frame = _document.AsRenderFrameHostIfValid();
  auto* contents = frame ? content::WebContents::FromRenderFrameHost(frame) : nullptr;
  PCNativePage* page = _page;
  PCNativeBrowserWindow* binding = _binding;
  NSWindow* window = _window;
  if (!frame || !frame->IsRenderFrameLive() || !contents ||
      contents->IsBeingDestroyed() || contents->GetPrimaryMainFrame() != frame ||
      !_profile || _profile->ShutdownStarted() ||
      contents->GetBrowserContext() != _profile.get() ||
      parc::IsNativeProfileRemovalBlocked(_profile->GetPath()) ||
      !_browser || _browser->IsDeleteScheduled() ||
      GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents) != _browser.get() ||
      parc::AppKitBindingForBrowser(_browser.get()) != binding ||
      !page || page.closed || parc::ContentsForNativePage(page) != contents ||
      parc::IsNativePageRetiring(page) ||
      !binding || !window || binding.window != window) return NO;
  auto* downloads = parc::NativeDownloads::From(*_profile);
  return downloads && downloads->CanPresentArrival(
      base::SysNSStringToUTF8(_downloadIdentifier), base::SysNSStringToUTF8(_itemIdentity));
}

- (void)start {
  PCNativeBrowserWindow* binding = _binding;
  NSMapTable<PCNativeBrowserWindow*, PCNativeDownloadArrival*>* pending = PendingArrivals();
  if (PCNativeDownloadArrival* previous = [pending objectForKey:binding])
    previous->_resolved = true;
  [pending setObject:self forKey:binding];
  _document.AsRenderFrameHostIfValid()->ExecuteJavaScriptInIsolatedWorld(
      u"(() => { const a=document.querySelector('a:hover'); if(!a)return null;"
       "const r=a.getBoundingClientRect(),v=window.visualViewport;"
       "if(!v)return null; return {x:r.left+r.width/2,y:r.top+r.height/2,"
       "ox:v.offsetLeft,oy:v.offsetTop,scale:v.scale}; })()",
      base::BindOnce([](PCNativeDownloadArrival* receipt, base::Value value) {
        base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
            FROM_HERE, base::BindOnce([](PCNativeDownloadArrival* receipt, base::Value result) {
              [receipt resolved:std::move(result)];
            }, receipt, std::move(value)));
      }, self), ISOLATED_WORLD_ID_CHROME_INTERNAL);
}

- (void)resolved:(base::Value)value {
  if (_resolved) return;
  _resolved = true;
  PCNativeBrowserWindow* binding = _binding;
  NSMapTable<PCNativeBrowserWindow*, PCNativeDownloadArrival*>* pending = PendingArrivals();
  if ([pending objectForKey:binding] == self) [pending removeObjectForKey:binding];
  NSWindow* window = _window;
  if (!self.valid || PCNativeWindowHasSecurityReservation(window)) return;
  auto* contents = content::WebContents::FromRenderFrameHost(_document.AsRenderFrameHostIfValid());
  auto* view = contents->GetRenderWidgetHostView();
  NSView* renderer = view ? view->GetNativeView().GetNativeNSView() : nil;
  NSPoint source = NSEvent.mouseLocation;
  const auto* result = value.GetIfDict();
  auto x = result ? result->FindDouble("x") : std::nullopt;
  auto y = result ? result->FindDouble("y") : std::nullopt;
  auto ox = result ? result->FindDouble("ox") : std::nullopt;
  auto oy = result ? result->FindDouble("oy") : std::nullopt;
  auto scale = result ? result->FindDouble("scale") : std::nullopt;
  double zoom = blink::ZoomLevelToZoomFactor(content::HostZoomMap::GetZoomLevel(contents));
  if (renderer.window == window && x && y && ox && oy && scale && std::isfinite(*x) &&
      std::isfinite(*y) && std::isfinite(*ox) && std::isfinite(*oy) &&
      std::isfinite(*scale) && *scale > 0 && std::isfinite(zoom) && zoom > 0) {
    NSPoint point = NSMakePoint((*x - *ox) * *scale * zoom, (*y - *oy) * *scale * zoom);
    if (!renderer.flipped) point.y = renderer.bounds.size.height - point.y;
    NSPoint screen = [window convertPointToScreen:[renderer convertPoint:point toView:nil]];
    if (std::isfinite(screen.x) && std::isfinite(screen.y)) source = screen;
  }
  _sourceScreenPoint = source;
  id<PCNativeBrowserWindowClient> client = binding.client;
  if ([client respondsToSelector:@selector(nativeBrowser:downloadDidBegin:)])
    [client nativeBrowser:binding downloadDidBegin:self];
}
@end

namespace parc {
void PresentNativeDownloadArrival(Profile& profile, NativeDownloadSnapshot snapshot,
                                  content::WeakDocumentPtr document, NSString* context_id) {
  PCNativeDownloadArrival* receipt = [[PCNativeDownloadArrival alloc]
      initWithProfile:profile snapshot:snapshot
             document:ArrivalDocument(std::move(document)) context:context_id];
  [receipt start];
}
}
