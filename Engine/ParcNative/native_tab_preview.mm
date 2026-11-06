// Copyright 2026 Parc contributors.
#import "native_appkit_page.h"
#include <memory>
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/thumbnails/thumbnail_image.h"
#include "chrome/browser/ui/thumbnails/thumbnail_tab_helper.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "native_appkit_host.h"
#include "native_host_route.h"
#include "native_tab_preview.h"
#include "chrome/browser/profiles/profile.h"
#include "ui/base/base_window.h"
#include "ui/gfx/image/image_skia_util_mac.h"
#import "window_security_reservation.h"

namespace parc {
bool NeedsNativeTabThumbnails(Profile& profile) {
  return !!GetNativeRoute(profile) ||
      (profile.IsOffTheRecord() && !!GetNativeRoute(*profile.GetOriginalProfile()));
}
namespace {
bool CanPresent(NSWindow* window) {
  return window && window.visible && window.keyWindow && !window.miniaturized &&
      NSApp.active && !window.attachedSheet &&
      !PCNativeWindowHasSecurityReservation(window) &&
      [PCNativeBrowserApplication windowForNativeWindow:window];
}

class TabPreview final : public content::WebContentsObserver {
 public:
  TabPreview(content::WebContents& contents, NSWindow* window,
             void (^handler)(NSImage*))
      : content::WebContentsObserver(&contents), window_(window),
        document_(contents.GetPrimaryMainFrame()->GetWeakDocumentPtr()),
        handler_([handler copy]) {
    auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(&contents);
    if (browser) browser_ = browser->GetWeakPtr();
  }
  ~TabPreview() override { Invalidate(false); }
  bool Start() {
    if (!Current()) return false;
    auto* tab = tabs::TabInterface::GetFromContents(web_contents());
    auto* helper = tab ? ThumbnailTabHelper::From(tab) : nullptr;
    if (!helper) return false;
    thumbnail_ = helper->thumbnail();
    subscription_ = thumbnail_->Subscribe();
    subscription_->SetSizeHint(gfx::Size(320, 200));
    subscription_->SetUncompressedImageCallback(base::BindRepeating(
        &TabPreview::Received, weak_factory_.GetWeakPtr()));
    thumbnail_->RequestThumbnailImage();
    auto weak = weak_factory_.GetWeakPtr();
    auto cancel = ^(NSNotification*) { if (weak) weak->Invalidate(true); };
    for (NSNotificationName name in @[NSWindowWillCloseNotification,
        NSWindowDidResignKeyNotification, NSWindowDidMiniaturizeNotification,
        PCNativeWindowSecurityStateChanged]) {
      [observers_ addObject:[NSNotificationCenter.defaultCenter
          addObserverForName:name object:window_ queue:nil usingBlock:cancel]];
    }
    return true;
  }
  void Invalidate(bool notify) {
    weak_factory_.InvalidateWeakPtrs();
    subscription_.reset();
    thumbnail_.reset();
    for (id observer in observers_)
      [NSNotificationCenter.defaultCenter removeObserver:observer];
    [observers_ removeAllObjects];
    auto handler = handler_;
    handler_ = nil;
    if (notify && handler) handler(nil);
  }
 private:
  bool Current() const {
    auto* contents = web_contents();
    PCNativePage* page = contents ? ExistingNativePage(contents) : nil;
    return contents && page && !page.closed && CanPresent(window_) &&
        page.nativeView.window == window_ && browser_ &&
        !browser_->IsDeleteScheduled() && AppKitBrowserAcceptsNewPages(*browser_) &&
        GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents) == browser_.get() &&
        browser_->GetWindow() &&
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() == window_ &&
        document_.AsRenderFrameHostIfValid() == contents->GetPrimaryMainFrame();
  }
  void Received(gfx::ImageSkia image) {
    // ThumbnailImage forbids destroying its subscription from its callback.
    // Post delivery, including invalidation, so shell reentry may safely close.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce(&TabPreview::Deliver, weak_factory_.GetWeakPtr(), image));
  }
  void Deliver(gfx::ImageSkia image) {
    if (!Current()) { Invalidate(true); return; }
    auto handler = handler_;
    if (handler && !image.isNull()) handler(gfx::NSImageFromImageSkia(image));
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument())
      Invalidate(true);
  }
  void PrimaryPageChanged(content::Page&) override { Invalidate(true); }
  void WebContentsDestroyed() override { Invalidate(true); }
  NSWindow* __weak window_ = nil;
  base::WeakPtr<BrowserWindowInterface> browser_;
  content::WeakDocumentPtr document_;
  void (^handler_)(NSImage*) = nil;
  NSMutableArray* __strong observers_ = [[NSMutableArray alloc] init];
  scoped_refptr<ThumbnailImage> thumbnail_;
  std::unique_ptr<ThumbnailImage::Subscription> subscription_;
  base::WeakPtrFactory<TabPreview> weak_factory_{this};
};
}  // namespace
}  // namespace parc

@interface PCNativeTabPreview () {
 @public
  std::unique_ptr<parc::TabPreview> state;
}
@end
@implementation PCNativeTabPreview
- (void)invalidate { state.reset(); }
@end

@implementation PCNativePage (TabPreview)
- (PCNativeTabPreview*)observePreviewInWindow:(NSWindow*)window
                                     handler:(void (^)(NSImage*))handler {
  content::WebContents* contents = parc::ContentsForNativePage(self);
  if (!contents || !handler || self.closed || self.nativeView.window != window ||
      !parc::CanPresent(window)) return nil;
  PCNativeTabPreview* lease = [[PCNativeTabPreview alloc] init];
  lease->state = std::make_unique<parc::TabPreview>(*contents, window, handler);
  if (!lease->state->Start()) return nil;
  return lease;
}
@end
@implementation PCNativeBrowserApplication (TabSwitcher)
+ (NSNotificationName)tabSwitcherAvailabilityDidChangeNotification {
  return PCNativeWindowSecurityStateChanged;
}
+ (BOOL)canPresentTabSwitcherInWindow:(NSWindow*)window {
  return parc::CanPresent(window);
}
@end
