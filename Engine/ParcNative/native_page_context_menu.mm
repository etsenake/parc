// Copyright 2026 Parc contributors.
#include "native_page_context_menu.h"
#include "cef/libcef/browser/parc_native/native_internal_urls.h"

#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/memory/raw_ptr.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/clipboard_types.h"
#include "content/public/browser/content_browser_client.h"
#include "content/public/common/content_client.h"
#include "ui/base/clipboard/clipboard_format_type.h"
#include "ui/base/clipboard/clipboard_metadata.h"
#include "ui/base/data_transfer_policy/data_transfer_endpoint.h"
#include "base/strings/sys_string_conversions.h"
#include "cef/include/internal/cef_types.h"
#include "cef/libcef/common/app_manager.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/renderer_context_menu/render_view_context_menu.h"
#include "chrome/browser/search_engines/template_url_service_factory.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/grit/generated_resources.h"
#include "components/search_engines/template_url.h"
#include "components/search_engines/template_url_service.h"
#include "chrome/common/chrome_render_frame.mojom.h"
#include "components/enterprise/buildflags/buildflags.h"
#if BUILDFLAG(ENTERPRISE_DATA_CONTROLS)
#include "chrome/browser/enterprise/data_protection/data_protection_clipboard_utils.h"
#endif
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "native_appkit_page.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"
#include "third_party/blink/public/mojom/context_menu/context_menu.mojom.h"
#include "ui/base/cocoa/menu_utils.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/menus/simple_menu_model.h"
#include "ui/gfx/codec/png_codec.h"
#include "url/origin.h"
#include "third_party/skia/include/core/SkBitmap.h"
#import "ui/menus/cocoa/menu_controller.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
constexpr int kAddImageToEasel = MENU_ID_USER_FIRST;
constexpr int kOpenLinkInSplitView = MENU_ID_USER_FIRST + 1;
// render_view_context_menu.cc kMaxOpenLinkInProfileItems (file-local there).
constexpr int kProfileLinkCommands = 100;
struct PageLease {
  base::WeakPtr<content::WebContents> contents;
  content::WeakDocumentPtr document;
  NSWindow* __weak window;
  bool Valid(bool allow_sheet = false) const {
    auto* frame = document.AsRenderFrameHostIfValid();
    PCNativePage* page = ExistingNativePage(contents.get());
    return contents && frame && frame->IsRenderFrameLive() &&
        content::WebContents::FromRenderFrameHost(frame) == contents.get() &&
        &frame->GetPage() == &contents->GetPrimaryPage() &&
        !contents->IsBeingDestroyed() && !contents->IsCrashed() &&
        contents->GetVisibility() == content::Visibility::VISIBLE &&
        page && !page.closed && window && window.visible &&
        page.nativeView.window == window && (allow_sheet || !window.attachedSheet) &&
        !PCNativeWindowHasSecurityReservation(window);
  }
};
PageLease Lease(RenderViewContextMenu& menu) {
  auto* contents = menu.source_web_contents();
  auto* frame = menu.GetRenderFrameHost();
  PCNativePage* page = ExistingNativePage(contents);
  return {contents->GetWeakPtr(), frame ? frame->GetWeakDocumentPtr()
                                      : content::WeakDocumentPtr(),
          page.nativeView.window};
}
}  // namespace
}  // namespace parc

@interface PCNativeContextImage () {
 @public
  parc::PageLease _lease;
}
- (instancetype)initWithPNG:(NSData*)png source:(NSURL*)source
                      title:(NSString*)title lease:(parc::PageLease)lease error:(NSString*)error;
@end
@implementation PCNativeContextImage
@synthesize PNGData = _PNGData;
@synthesize errorMessage = _errorMessage;
@synthesize sourceURL = _sourceURL;
@synthesize pageTitle = _pageTitle;
- (instancetype)initWithPNG:(NSData*)png source:(NSURL*)source
                      title:(NSString*)title lease:(parc::PageLease)lease error:(NSString*)error {
  if ((self = [super init])) {
    _PNGData = [png copy]; _sourceURL = [source copy];
    _pageTitle = [title copy]; _lease = std::move(lease); _errorMessage = [error copy];
  }
  return self;
}
- (BOOL)isValid { return _lease.Valid(true); }
@end

// Preserve MenuControllerCocoa's real target, validation and native event flags.
// Only the source-page lease is added; commands are never reconstructed.
@interface PCPageMenuTarget : NSObject <NSUserInterfaceValidations>
- (instancetype)initWithItem:(NSMenuItem*)item controller:(MenuControllerCocoa*)controller
                       lease:(parc::PageLease)lease;
- (void)itemSelected:(NSMenuItem*)item;
@end
@implementation PCPageMenuTarget {
  __weak MenuControllerCocoa* _controller;
  SEL _action;
  parc::PageLease _lease;
}
- (instancetype)initWithItem:(NSMenuItem*)item controller:(MenuControllerCocoa*)controller
                       lease:(parc::PageLease)lease {
  if ((self = [super init])) { _controller = controller; _action = item.action; _lease = std::move(lease); }
  return self;
}
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  return _lease.Valid() && _controller && [_controller validateUserInterfaceItem:item];
}
- (void)itemSelected:(NSMenuItem*)item {
  __attribute__((objc_precise_lifetime)) PCPageMenuTarget* keep = self;
  MenuControllerCocoa* controller = _controller;
  if (_lease.Valid() && controller && !item.hidden &&
      [controller validateUserInterfaceItem:item]) {
    [NSApp sendAction:_action to:controller from:item];
  }
  (void)keep;
}
@end

namespace parc {
namespace {
void ImageFailed(PageLease lease, NSString* message) {
  if (!lease.Valid()) return;
  PCNativePage* page = ExistingNativePage(lease.contents.get());
  id<PCNativePageObserver> observer = page.observer;
  if ([observer respondsToSelector:@selector(nativePage:addContextImageToEasel:)]) {
    PCNativeContextImage* image = [[PCNativeContextImage alloc]
        initWithPNG:[NSData data] source:nil title:@"" lease:std::move(lease) error:message];
    [observer nativePage:page addContextImageToEasel:image];
  }
}
void DeliverImage(PageLease lease, NSURL* source, NSString* title,
                  const SkBitmap& bitmap) {
  if (!lease.Valid()) return;
  PCNativePage* page = ExistingNativePage(lease.contents.get());
  id<PCNativePageObserver> observer = page.observer;
  if (![observer respondsToSelector:@selector(nativePage:addContextImageToEasel:)]) return;
  if (bitmap.empty() || bitmap.width() > 16384 || bitmap.height() > 16384 ||
      int64_t(bitmap.width()) * bitmap.height() > 80000000) {
    ImageFailed(lease, @"This image is unavailable or exceeds the Easel image limit."); return;
  }
  auto png = gfx::PNGCodec::EncodeBGRASkBitmap(bitmap, false);
  if (!png || png->empty() || png->size() > 30 * 1024 * 1024) {
    ImageFailed(lease, @"The image could not be saved within the Easel image limit."); return;
  }
  PCNativeContextImage* image = [[PCNativeContextImage alloc]
      initWithPNG:[NSData dataWithBytes:png->data() length:png->size()]
           source:source title:title lease:std::move(lease) error:nil];
  [observer nativePage:page addContextImageToEasel:image];
}
// Local Easel export is subject to the actual copy/content-analysis policy.
// A denied/replaced payload never becomes a local asset, and this operation
// never changes the user's clipboard.
void CheckImagePolicy(PageLease lease, NSURL* source, NSString* title,
    mojo::AssociatedRemote<chrome::mojom::ChromeRenderFrame> remote,
    const SkBitmap& bitmap) {
  if (!lease.Valid()) return;
  if (bitmap.empty() || bitmap.width() > 16384 || bitmap.height() > 16384 ||
      int64_t(bitmap.width()) * bitmap.height() > 80000000) {
    ImageFailed(lease, @"This image is unavailable or exceeds the Easel image limit."); return;
  }
  auto* frame = lease.document.AsRenderFrameHostIfValid();
#if BUILDFLAG(ENTERPRISE_DATA_CONTROLS)
  const GURL url = enterprise_data_protection::GetUrlFromRenderFrameHost(frame);
#else
  GURL url = frame->GetMainFrame()->GetLastCommittedURL();
  if (!url.is_valid() || url.IsAboutBlank() || url.IsAboutSrcdoc())
    url = frame->GetMainFrame()->GetLastCommittedOrigin().GetURL();
#endif
  ui::DataTransferEndpoint endpoint(url, {
      .off_the_record = frame->GetBrowserContext()->IsOffTheRecord()});
  content::ClipboardEndpoint source_endpoint = content::ClipboardEndpoint::ForFrame(
      endpoint, base::BindRepeating([](content::WeakDocumentPtr document)
          -> content::BrowserContext* {
        auto* frame = document.AsRenderFrameHostIfValid();
        return frame ? frame->GetBrowserContext() : nullptr;
      }, lease.document), *frame);
  content::ClipboardPasteData data;
  data.bitmap = bitmap;
  CefAppManager::Get()->GetContentClient()->browser()->IsClipboardCopyAllowedByPolicy(
      source_endpoint, {.size = bitmap.computeByteSize(),
                        .format_type = ui::ClipboardFormatType::BitmapType()}, data,
      base::BindOnce([](PageLease lease, NSURL* source, NSString* title,
          const ui::ClipboardFormatType&, const content::ClipboardPasteData& approved,
          std::optional<std::u16string> replacement) {
        if (!replacement && !approved.bitmap.drawsNothing()) {
          DeliverImage(std::move(lease), source, title, approved.bitmap);
        } else {
          ImageFailed(lease, @"Your organization does not allow this image to be added to an Easel.");
        }
      }, lease, source, title));
}
//
// never adds, for the same Chromium 156: its own split item replaces 50111,
// the Open Link as/in Profile block and the QR items are gone (QR is also
// disabled at 0x4266488), and so are Glic, Lens/region search, reading mode,
// partial translate and video-frame search. Removal keeps every other item,
// title and command of the genuine model.
constexpr int kArcOmittedCommands[] = {
    IDC_CONTENT_CONTEXT_OPENLINKSPLITVIEW, IDC_CONTENT_CONTEXT_OPENLINKINPROFILE,
    IDC_CONTENT_CONTEXT_GENERATE_QR_CODE, IDC_CONTENT_CONTEXT_OPEN_IN_READING_MODE,
    IDC_CONTENT_CONTEXT_LISTEN_TO_THIS_PAGE, IDC_CONTENT_CONTEXT_LENS_REGION_SEARCH,
    IDC_CONTENT_CONTEXT_WEB_REGION_SEARCH, IDC_CONTENT_CONTEXT_ASK_GOOGLE_ABOUT_THIS_PAGE,
    IDC_CONTENT_CONTEXT_CONTEXTUAL_TASKS_SUBMENU, IDC_CONTENT_CONTEXT_LENS_OVERLAY,
    IDC_CONTENT_CONTEXT_GLIC, IDC_CONTENT_CONTEXT_RELOAD_GLIC, IDC_CONTENT_CONTEXT_ARCHIVE_GLIC,
    IDC_CONTENT_CONTEXT_GLICSHAREIMAGE, IDC_CONTENT_CONTEXT_SEARCHLENSFORVIDEOFRAME,
    IDC_CONTENT_CONTEXT_SEARCHWEBFORVIDEOFRAME, IDC_CONTENT_CONTEXT_PARTIAL_TRANSLATE};
void RemoveCommand(ui::SimpleMenuModel& model, int command) {
  if (auto index = model.GetIndexOfCommandId(command)) model.RemoveItemAt(*index);
}
// Removal must not leave leading, trailing or doubled separators.
void NormalizeSeparators(ui::SimpleMenuModel& model) {
  for (size_t i = model.GetItemCount(); i-- > 0;) {
    if (model.GetTypeAt(i) != ui::MenuModel::TYPE_SEPARATOR) continue;
    if (i == 0 || i + 1 == model.GetItemCount() ||
        model.GetTypeAt(i + 1) == ui::MenuModel::TYPE_SEPARATOR) {
      model.RemoveItemAt(i);
    }
  }
}
class ContextObserver final : public RenderViewContextMenuObserver {
 public:
  explicit ContextObserver(RenderViewContextMenu* menu) : menu_(menu), lease_(Lease(*menu)) {}
  // The real menu calls this last in InitMenu, before the Mac toolkit adds
  //
  void InitMenu(const content::ContextMenuParams& params) override {
    auto& model = const_cast<ui::SimpleMenuModel&>(menu_->menu_model());
    for (int command : kArcOmittedCommands) RemoveCommand(model, command);
    for (int command = IDC_OPEN_LINK_IN_PROFILE_FIRST; command < IDC_OPEN_LINK_IN_PROFILE_FIRST + kProfileLinkCommands; ++command)
      RemoveCommand(model, command);
    //
    // translation: Chrome's translate service needs a Google API key.
    RemoveCommand(model, IDC_CONTENT_CONTEXT_TRANSLATE);
    // Image search is always the plain "Search ‹engine› for Image" item
    // (IDC 50124, IDS_CONTENT_CONTEXT_SEARCHWEBFORIMAGE), never Lens, no icon.
    for (int command : {IDC_CONTENT_CONTEXT_SEARCHLENSFORIMAGE, IDC_CONTENT_CONTEXT_SEARCHWEBFORIMAGE}) {
      auto index = model.GetIndexOfCommandId(command);
      if (!index) continue;
      auto* service = TemplateURLServiceFactory::GetForProfile(
          Profile::FromBrowserContext(lease_.contents->GetBrowserContext()));
      const TemplateURL* provider = service ? service->GetDefaultSearchProvider() : nullptr;
      model.RemoveItemAt(*index);
      if (provider) {
        model.InsertItemAt(*index, IDC_CONTENT_CONTEXT_SEARCHWEBFORIMAGE,
            l10n_util::GetStringFUTF16(IDS_CONTENT_CONTEXT_SEARCHWEBFORIMAGE, provider->short_name()));
      }
      break;
    }
    //
    // a link in a normal browser window, plain title, no icon or separator.
    PCNativePage* page = ExistingNativePage(lease_.contents.get());
    auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(lease_.contents.get());
    auto anchor = model.GetIndexOfCommandId(IDC_CONTENT_CONTEXT_OPENLINKNEWWINDOW);
    if (!anchor) anchor = model.GetIndexOfCommandId(IDC_CONTENT_CONTEXT_OPENLINKNEWTAB);
    if (!params.link_url.is_empty() && anchor && browser &&
        browser->GetType() == BrowserWindowInterface::TYPE_NORMAL && page && !page.embedded &&
        !page.peekParentPage &&
        [page.observer respondsToSelector:@selector(nativePage:openLinkInSplitView:)]) {
      split_ = true;
      model.InsertItemAt(*anchor + 1, kOpenLinkInSplitView, u"Open Link in Split View");
    }
    //
    // selection search at the top when the selection is not inside a link.
    if (!params.link_url.is_valid()) {
      if (auto index = model.GetIndexOfCommandId(IDC_CONTENT_CONTEXT_SEARCHWEBFOR); index && *index) {
        const std::u16string label = model.GetLabelAt(*index);
        model.RemoveItemAt(*index);
        model.InsertItemAt(0, IDC_CONTENT_CONTEXT_SEARCHWEBFOR, label);
      }
    }
    //
    if (!lease_.contents->GetBrowserContext()->IsOffTheRecord() &&
        params.media_type == blink::mojom::ContextMenuDataMediaType::kImage && params.has_image_contents) {
      image_ = true;
      if (auto save = model.GetIndexOfCommandId(IDC_CONTENT_CONTEXT_SAVEIMAGEAS)) {
        model.InsertItemAt(*save + 1, kAddImageToEasel, u"Add Image to Easel…");
      } else {
        menu_->AddMenuItem(kAddImageToEasel, u"Add Image to Easel…");
      }
    }
    NormalizeSeparators(model);
  }
  bool IsCommandIdSupported(int command) override {
    return command == kAddImageToEasel || command == kOpenLinkInSplitView;
  }
  bool IsCommandIdEnabled(int command) override {
    if (command == kOpenLinkInSplitView) {
      //
      // loads only HTTP(S) and asks the shell whether it can place a pane.
      const GURL& link = menu_->params().link_url;
      PCNativePage* page = ExistingNativePage(lease_.contents.get());
      id<PCNativePageObserver> observer = page.observer;
      return split_ && lease_.Valid() && link.is_valid() && link.IsStandard() &&
          link.SchemeIsHTTPOrHTTPS() &&
          (![observer respondsToSelector:@selector(nativePageCanOpenLinkInSplitView:)] ||
           [observer nativePageCanOpenLinkInSplitView:page]);
    }
    return image_ && lease_.Valid() && !lease_.contents->GetBrowserContext()->IsOffTheRecord() &&
        menu_->IsCommandIdEnabled(IDC_CONTENT_CONTEXT_COPYIMAGE);
  }
  void ExecuteCommand(int command) override {
    if (command == kOpenLinkInSplitView) {
      if (!IsCommandIdEnabled(command)) return;
      PCNativePage* page = ExistingNativePage(lease_.contents.get());
      id<PCNativePageObserver> observer = page.observer;
      NSURL* url = [NSURL URLWithString:base::SysUTF8ToNSString(
          PublicInternalURL(menu_->params().link_url).spec())];
      if (url && [observer respondsToSelector:@selector(nativePage:openLinkInSplitView:)])
        [observer nativePage:page openLinkInSplitView:url];
      return;
    }
    if (command != kAddImageToEasel || !IsCommandIdEnabled(command)) return;
    auto* frame = lease_.document.AsRenderFrameHostIfValid();
    mojo::AssociatedRemote<chrome::mojom::ChromeRenderFrame> remote;
    frame->GetRemoteAssociatedInterfaces()->GetInterface(&remote);
    auto* renderer = remote.get();
    NSURL* source = [NSURL URLWithString:base::SysUTF8ToNSString(PublicInternalURL(menu_->params().page_url).spec())];
    NSString* title = base::SysUTF16ToNSString(lease_.contents->GetTitle());
    // Send on the exact menu frame before any next context-node request.
    // The remote stays alive until this reply; no URL fetch or pasteboard use.
    renderer->RequestBitmapForContextNode(base::BindOnce(
        &CheckImagePolicy, lease_, source, title, std::move(remote)));
  }
 private:
  const raw_ptr<RenderViewContextMenu> menu_;
  PageLease lease_;
  bool image_ = false;
  bool split_ = false;
};
class Tracking final : public content::WebContentsObserver {
 public:
  Tracking(PageLease lease, MenuControllerCocoa* controller)
      : WebContentsObserver(lease.contents.get()), lease_(std::move(lease)), controller_(controller) {
    auto cancel = ^(NSNotification*) { [controller cancel]; };
    close_ = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification
        object:lease_.window queue:nil usingBlock:cancel];
    security_ = [NSNotificationCenter.defaultCenter addObserverForName:PCNativeWindowSecurityStateChanged
        object:lease_.window queue:nil usingBlock:cancel];
  }
  ~Tracking() override {
    [NSNotificationCenter.defaultCenter removeObserver:close_];
    [NSNotificationCenter.defaultCenter removeObserver:security_];
  }
  void DidStartNavigation(content::NavigationHandle* handle) override {
    if (!handle->IsSameDocument()) [controller_ cancel];
  }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility != content::Visibility::VISIBLE) [controller_ cancel];
  }
  void RenderFrameDeleted(content::RenderFrameHost*) override {
    if (!lease_.Valid()) [controller_ cancel];
  }
  void WebContentsDestroyed() override { [controller_ cancel]; }
 private:
  PageLease lease_;
  MenuControllerCocoa* __strong controller_;
  id __strong close_;
  id __strong security_;
};
void GuardItems(NSMenu* menu, MenuControllerCocoa* controller, PageLease lease,
                NSMutableArray* targets) {
  for (NSMenuItem* item in menu.itemArray) {
    if (item.submenu) GuardItems(item.submenu, controller, lease, targets);
    if (item.target == controller && item.action) {
      PCPageMenuTarget* target = [[PCPageMenuTarget alloc]
          initWithItem:item controller:controller lease:lease];
      [targets addObject:target]; item.target = target; item.action = @selector(itemSelected:);
    }
  }
}
}  // namespace
std::unique_ptr<RenderViewContextMenuObserver> CreateNativePageContextMenuObserver(
    RenderViewContextMenu* menu) {
  return ExistingNativePage(menu->source_web_contents())
      ? std::make_unique<ContextObserver>(menu) : nullptr;
}
bool ShowNativePageContextMenu(RenderViewContextMenu& menu, NSView* parent,
                              MenuControllerCocoa* __strong* destination) {
  if (!ExistingNativePage(menu.source_web_contents())) return false;
  auto lease = Lease(menu);
  if (!lease.Valid() || !parent || parent.window != lease.window) return true;
  MenuControllerCocoa* controller = [[MenuControllerCocoa alloc]
      initWithModel:const_cast<ui::SimpleMenuModel*>(&menu.menu_model())
      isContextMenu:YES delegate:nil];
  *destination = controller;
  __attribute__((objc_precise_lifetime)) NSMutableArray* targets = [NSMutableArray array];
  GuardItems(controller.menu, controller, lease, targets);
  Tracking tracking(lease, controller);
  const auto params = menu.params();
  NSPoint point = NSMakePoint(params.x, NSHeight(parent.bounds) - params.y);
  point = [parent convertPoint:point toView:nil];
  NSEvent* event = ui::EventForPositioningContextMenuRelativeToWindow(point, parent.window);
  // Chromium's helper supplies the native nested-loop/application-event scope.
  // Neither menu nor destination may be touched after a command destroys it.
  ui::ShowContextMenu(controller.menu, event, parent, true);
  return true;
}
}  // namespace parc
