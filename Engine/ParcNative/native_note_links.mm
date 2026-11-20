#include "native_note_links.h"

#include <algorithm>
#include <array>
#include <memory>
#include <optional>
#include <string>
#include <string_view>

#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/web_contents.h"
#include "native_appkit_host.h"
#include "native_appkit_page.h"
#include "net/base/filename_util.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "url/gurl.h"

namespace parc {
namespace {
constexpr auto kNoteExtensions = std::to_array<std::string_view>(
    {"md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext", "txt", "text"});

bool IsNoteFileURL(const GURL& url) {
  if (!url.is_valid() || !url.SchemeIsFile() || url.has_username() || url.has_password() ||
      url.has_port() || (url.has_host() && url.host() != "localhost")) {
    return false;
  }
  base::FilePath path;
  if (!net::FileURLToFilePath(url, &path)) {
    return false;
  }
  const std::string extension = path.FinalExtension();
  return extension.size() > 1 &&
         std::ranges::contains(kNoteExtensions, base::ToLowerASCII(extension.substr(1)));
}

bool IsLinkTransition(ui::PageTransition transition) {
  return ui::PageTransitionCoreTypeIs(transition, ui::PAGE_TRANSITION_LINK) &&
         !(transition & ui::PAGE_TRANSITION_FORWARD_BACK);
}

std::optional<PCNativeNoteLinkDisposition> NewNoteLinkDisposition(
    WindowOpenDisposition disposition) {
  switch (disposition) {
    case WindowOpenDisposition::NEW_FOREGROUND_TAB:
      return PCNativeNoteLinkDispositionForegroundTab;
    case WindowOpenDisposition::NEW_BACKGROUND_TAB:
      return PCNativeNoteLinkDispositionBackgroundTab;
    case WindowOpenDisposition::NEW_WINDOW:
    case WindowOpenDisposition::NEW_POPUP:
      return PCNativeNoteLinkDispositionNewWindow;
    default:
      return std::nullopt;
  }
}

bool OfferNoteLink(content::WebContents& source, PCNativeBrowserWindow* expected,
                   const GURL& url, PCNativeNoteLinkDisposition disposition) {
  PCNativePage* page = ExistingNativePage(&source);
  PCNativeBrowserWindow* binding =
      page && !page.closed ? [PCNativeBrowserApplication ownerForPage:page] : nil;
  NSURL* target = [NSURL URLWithString:base::SysUTF8ToNSString(url.spec())];
  return target && binding && (!expected || binding == expected) &&
         [binding.client respondsToSelector:
             @selector(nativeBrowser:openNoteFileURL:fromPage:disposition:)] &&
         [binding.client nativeBrowser:binding
                       openNoteFileURL:target
                              fromPage:page
                           disposition:disposition];
}

class NoteLinkThrottle final : public content::NavigationThrottle {
 public:
  using content::NavigationThrottle::NavigationThrottle;
  ThrottleCheckResult WillStartRequest() override {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&NoteLinkThrottle::Offer, weak_factory_.GetWeakPtr()));
    return DEFER;
  }
  const char* GetNameForLogging() override { return "ParcNoteLinkThrottle"; }

 private:
  void Offer() {
    const auto self = weak_factory_.GetWeakPtr();
    const bool opened = OfferNoteLink(*navigation_handle()->GetWebContents(), nil,
                                      navigation_handle()->GetURL(),
                                      PCNativeNoteLinkDispositionInPlace);
    if (!self) {
      return;
    }
    if (opened) {
      CancelDeferredNavigation(CANCEL_AND_IGNORE);
    } else {
      Resume();
    }
  }
  base::WeakPtrFactory<NoteLinkThrottle> weak_factory_{this};
};
}

void AddNativeNoteLinkThrottle(content::NavigationThrottleRegistry& registry) {
  auto& navigation = registry.GetNavigationHandle();
  if (navigation.IsInPrimaryMainFrame() && navigation.IsRendererInitiated() &&
      navigation.HasUserGesture() && !navigation.IsPost() &&
      navigation.GetReloadType() == content::ReloadType::NONE &&
      IsLinkTransition(navigation.GetPageTransition()) &&
      !navigation.GetWebContents()->GetController().IsInitialBlankNavigation() &&
      IsNoteFileURL(navigation.GetURL())) {
    registry.AddThrottle(std::make_unique<NoteLinkThrottle>(registry));
  }
}

bool OpenNativeNoteLink(BrowserWindowInterface& browser, content::WebContents& source,
                        const content::OpenURLParams& params) {
  const auto disposition = NewNoteLinkDisposition(params.disposition);
  if (!disposition || params.native_route_token ||
      (params.is_renderer_initiated && !params.user_gesture) ||
      !IsLinkTransition(params.transition) || !IsNoteFileURL(params.url) ||
      source.GetBrowserContext() != browser.GetProfile()) {
    return false;
  }
  PCNativeBrowserWindow* binding = AppKitBindingForBrowser(&browser);
  return binding && OfferNoteLink(source, binding, params.url, *disposition);
}

bool OpenNativeCreatedNoteLink(BrowserWindowInterface& browser, content::WebContents* source,
                               const GURL& url, WindowOpenDisposition disposition,
                               bool user_gesture) {
  const auto offered = NewNoteLinkDisposition(disposition);
  if (!source || !offered || !user_gesture || !IsNoteFileURL(url) ||
      source->GetBrowserContext() != browser.GetProfile()) {
    return false;
  }
  PCNativeBrowserWindow* binding = AppKitBindingForBrowser(&browser);
  return binding && OfferNoteLink(*source, binding, url, *offered);
}
}
