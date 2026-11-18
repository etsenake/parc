// Copyright 2026 Parc contributors.
#include "native_link_routing.h"

#include <memory>

#include "base/memory/weak_ptr.h"
#include "base/functional/bind.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/ui/browser_web_contents_delegate/browser_web_contents_delegate.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/frame_tree_node_id.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "content/public/browser/web_contents_observer.h"
#include "base/supports_user_data.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/parc_native_links.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/site_instance.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/common/referrer.h"
#include "extensions/browser/extension_function.h"
#include "extensions/common/constants.h"
#include "extensions/common/extension.h"
#include "native_appkit_host.h"
#include "native_appkit_page.h"
#import "native_shift_link.h"
#include "services/network/public/mojom/web_sandbox_flags.mojom.h"
#include "ui/base/page_transition_types.h"
#include "third_party/blink/public/common/renderer_preferences/renderer_preferences.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "third_party/blink/public/mojom/window_features/window_features.mojom.h"
#include "url/gurl.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "net/http/http_request_headers.h"

namespace parc {
namespace {
const char kCreatedPageKey = 0;
const char kPendingCurrentLinkKey = 0;
const char kPendingOptionLinkKey = 0;
const char kCurrentLinkSequenceKey = 0;
const char kRoutedPageKey = 0;
const char kCreatedRouteKey = 0;
const char kCreatedRouteAttemptKey = 0;
const char kURLLockKey = 0;
const char kOpenedPageKey = 0;
const char kShiftOpeningHoldKey = 0;
const char kHeldShiftOpeningsKey = 0;
class CreatedPage;
CreatedPage* Creation(content::WebContents& contents);

bool IsMeetingURL(NSURL* url) {
  NSString* host = url.host;
  NSArray<NSString*>* parts = url.pathComponents;
  NSString* lower_host = host.lowercaseString;
  if (([lower_host isEqualToString:@"zoom.us"] ||
       [lower_host hasSuffix:@".zoom.us"]) && parts.count >= 2) {
    NSString* route = parts[parts.count - 2];
    NSString* number = parts.lastObject;
    if (([route isEqualToString:@"j"] || [route isEqualToString:@"s"]) &&
        number.length && [[NSCharacterSet decimalDigitCharacterSet]
            isSupersetOfSet:[NSCharacterSet characterSetWithCharactersInString:number]])
      return true;
  }
  if ([host isEqualToString:@"meet.google.com"] && parts.count == 2) return true;
  return [host isEqualToString:@"teams.microsoft.com"] && parts.count >= 4 &&
      [parts[1] isEqualToString:@"l"] && [parts[2] isEqualToString:@"meetup-join"];
}

std::string RegistrableDomain(NSURL* url) {
  if (!url) return {};
  return net::registry_controlled_domains::GetDomainAndRegistry(
      GURL(url.absoluteString.UTF8String),
      net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES);
}
NSArray<NSString*>* HostLabels(NSString* host) {
  NSMutableArray<NSString*>* labels = [NSMutableArray array];
  for (NSString* label in [host componentsSeparatedByString:@"."])
    if (label.length) [labels addObject:label];
  return labels;
}
bool IsAuthenticationContinuation(NSURL* source, NSURL* target) {
  NSString* source_host = source.host;
  NSString* host = target.host;
  if (!source_host || !host) return false;
  NSArray<NSString*>* parts = target.pathComponents;
  NSArray<NSString*>* labels = HostLabels(host);
  const auto source_domain = RegistrableDomain(source);
  const auto target_domain = RegistrableDomain(target);
  if (!source_domain.empty() && source_domain == target_domain) {
    if ([parts containsObject:@"login"]) return true;
    NSSet<NSString*>* auth = [NSSet setWithArray:@[@"myaccount", @"profile",
        @"account", @"accounts", @"signin", @"user", @"email", @"secure",
        @"login", @"id", @"auth"]];
    for (NSString* label in labels) if ([auth containsObject:label]) return true;
  }
  NSArray<NSString*>* source_labels = HostLabels(source_host);
  if (labels.count == source_labels.count + 1 &&
      [labels.firstObject isEqualToString:@"console"] &&
      [[labels subarrayWithRange:NSMakeRange(1, source_labels.count)]
          isEqualToArray:source_labels]) return true;
  if ([host isEqualToString:@"accounts.google.com"]) return true;
  if ([host isEqualToString:@"appleid.apple.com"] && parts.count > 1 &&
      [parts[1] isEqualToString:@"auth"]) return true;
  bool oauth_path = false;
  for (NSString* part in parts) if ([part hasPrefix:@"oauth"]) oauth_path = true;
  if ([host containsString:@"oauth"] || oauth_path) return true;
  if (target_domain == "okta.com") return true;
  if (target_domain == "google.com" && [parts.lastObject isEqualToString:@"acs"])
    return true;
  if (([host isEqualToString:@"login.microsoftonline.com"] && oauth_path) ||
      ([host isEqualToString:@"login.live.com"] &&
       [parts.lastObject isEqualToString:@"post.srf"])) return true;
  return [source_host hasSuffix:@".atlassian.net"] &&
      [target.absoluteString hasPrefix:@"https://id.atlassian.com/login"];
}

class URLLockState final : public base::SupportsUserData::Data,
                           public content::WebContentsObserver {
 public:
  explicit URLLockState(content::WebContents& contents)
      : content::WebContentsObserver(&contents), previous_(contents.GetLastCommittedURL()) {}
  bool unlocked() const { return baseline_.has_value(); }
  void UpdateURL(const GURL& incoming) {
    const auto self = weak_factory_.GetWeakPtr();
    const uint64_t generation = ++generation_;
    NSURL* target = [NSURL URLWithString:@(incoming.spec().c_str())];
    NSURL* previous = [NSURL URLWithString:@(previous_.spec().c_str())];
    if (baseline_) {
      NSURL* baseline = [NSURL URLWithString:@(baseline_->spec().c_str())];
      bool returned = target.host && [target.host isEqualToString:baseline.host];
      if (!returned && target.host) {
        PCNativePage* page = ExistingNativePage(web_contents());
        PCNativeBrowserWindow* binding = page ? [PCNativeBrowserApplication ownerForPage:page] : nil;
        if ([binding.client respondsToSelector:@selector(nativeBrowser:authenticationReturnURLForPage:)]) {
          NSURL* saved = [binding.client nativeBrowser:binding authenticationReturnURLForPage:page];
          if (!self || generation != generation_) return;
          returned = saved.host && [target.host isEqualToString:saved.host];
        }
      }
      if (returned) baseline_.reset();
    } else if (previous && target &&
        !((!previous.host && !target.host) || [previous.host isEqualToString:target.host]) &&
        IsAuthenticationContinuation(previous, target)) {
      baseline_ = previous_;
    }
    previous_ = incoming;
  }
 private:
  GURL previous_;
  std::optional<GURL> baseline_;
  uint64_t generation_ = 0;
  base::WeakPtrFactory<URLLockState> weak_factory_{this};
};
class SplitSourceObserver final : public content::WebContentsObserver {
 public:
  explicit SplitSourceObserver(content::WebContents& source) : content::WebContentsObserver(&source) {}
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame()) invalid = true;
  }
  void WebContentsDestroyed() override { invalid = true; }
  bool invalid = false;
};
class CreatedPage final : public base::SupportsUserData::Data {
 public:
  CreatedPage(content::WebContents& source, content::RenderFrameHost& opener,
              BrowserWindowInterface& browser)
      : source_(source.GetWeakPtr()), document_(opener.GetWeakDocumentPtr()),
        browser_(browser.GetWeakPtr()), modifiers_(NSEvent.modifierFlags) {}
  CreatedPage(const CreatedPage& source, BrowserWindowInterface& destination)
      : source_(source.source_), document_(source.document_),
        browser_(source.browser_), modifiers_(source.modifiers_),
        routed_creation_(true), destination_(destination.GetWeakPtr()) {}

  PCNativePage* Source(content::WebContents& created) const {
    if (!source_ || !document_.AsRenderFrameHostIfValid() || !browser_ ||
        browser_->IsDeleteScheduled() ||
        document_.AsRenderFrameHostIfValid() != source_->GetPrimaryMainFrame() ||
        source_->GetBrowserContext() != created.GetBrowserContext() ||
        source_->GetBrowserContext() != browser_->GetProfile() ||
        !AppKitBrowserAcceptsNewPages(*browser_)) return nil;
    PCNativePage* parent = ExistingNativePage(source_.get());
    PCNativeBrowserWindow* binding = AppKitBindingForBrowser(browser_.get());
    if (!parent || parent.closed || !binding ||
        [PCNativeBrowserApplication ownerForPage:parent] != binding ||
        parent.nativeView.window != binding.window) return nil;
    return parent;
  }
  PCNativePage* Parent(content::WebContents& created) const {
    PCNativePage* parent = Source(created);
    if (!parent || (split_observer_ && (split_observer_->invalid ||
        source_->GetLastCommittedURL() != split_source_url_))) return nil;
    PCNativePage* child = ExistingNativePage(&created);
    PCNativeBrowserWindow* child_owner = child ?
        [PCNativeBrowserApplication ownerForPage:child] : nil;
    if (child_owner && child_owner != AppKitBindingForBrowser(browser_.get()))
      return nil;
    return parent;
  }
  PCNativePage* CreationSource(content::WebContents& created) const {
    if (!routed_creation_) return Parent(created);
    if (!destination_ || destination_->IsDeleteScheduled() ||
        !AppKitBrowserAcceptsNewPages(*destination_) ||
        destination_->GetProfile() != created.GetBrowserContext()) return nil;
    PCNativePage* parent = Source(created);
    PCNativeBrowserWindow* destination = AppKitBindingForBrowser(destination_.get());
    if (!parent || !destination) return nil;
    PCNativePage* child = ExistingNativePage(&created);
    PCNativeBrowserWindow* owner = child ?
        [PCNativeBrowserApplication ownerForPage:child] : nil;
    if (owner && owner != destination) return nil;
    return parent;
  }
  bool CanPresent(content::WebContents& created) const {
    PCNativePage* parent = Parent(created);
    if (!parent) return false;
    PCNativeBrowserWindow* binding = AppKitBindingForBrowser(browser_.get());
    const auto child = created.GetWeakPtr();
    return [binding.client respondsToSelector:@selector(nativeBrowser:canPresentPeekFrom:)] &&
           [binding.client nativeBrowser:binding canPresentPeekFrom:parent] &&
           child && Creation(*child) == this && Parent(*child) == parent;
  }
  base::WeakPtr<content::WebContents> source_;
  content::WeakDocumentPtr document_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  NSEventModifierFlags modifiers_;
  bool peek_ = false;

  bool reopened_ = false;
  bool offered_ = false;
  id __strong split_lease_ = nil;
  std::unique_ptr<SplitSourceObserver> split_observer_;
  GURL split_source_url_;
  const bool routed_creation_ = false;
  base::WeakPtr<BrowserWindowInterface> destination_;
};

class OpenedPage final : public base::SupportsUserData::Data {
 public:
  explicit OpenedPage(content::RenderFrameHost& opener)
      : document(opener.GetWeakDocumentPtr()), modifiers(NSEvent.modifierFlags) {}
  const content::WeakDocumentPtr document;
  const NSEventModifierFlags modifiers;
};

class CurrentLinkSequence final : public base::SupportsUserData::Data {
 public:
  uint64_t value = 0;
};
class PendingOptionLink final : public base::SupportsUserData::Data {
 public:
  PendingOptionLink(content::RenderFrameHost& frame, const GURL& target)
      : token(base::UnguessableToken::Create()), initiator(frame.GetGlobalFrameToken()),
        document(frame.GetWeakDocumentPtr()), url(target) {}
  const base::UnguessableToken token;
  const content::GlobalRenderFrameHostToken initiator;
  const content::WeakDocumentPtr document;
  const GURL url;
};
class PendingCurrentLink final : public base::SupportsUserData::Data {
 public:
  PendingCurrentLink(std::unique_ptr<CreatedPage> value, const GURL& target,
                     uint64_t sequence_value, PCNativeLinkRoute* matched_route,
                     WindowOpenDisposition original_disposition)
      : token(base::UnguessableToken::Create()),
        source_url(value->source_->GetLastCommittedURL()),
        sequence(sequence_value), route(matched_route),
        disposition(original_disposition), creation(std::move(value)), url(target) {}
  const base::UnguessableToken token;
  const GURL source_url;
  const uint64_t sequence;
  PCNativeLinkRoute* __strong route;
  const WindowOpenDisposition disposition;
  std::unique_ptr<CreatedPage> creation;
  const GURL url;
};
CreatedPage* Creation(content::WebContents& contents) {
  return static_cast<CreatedPage*>(contents.GetUserData(&kCreatedPageKey));
}

bool CanPresentSource(CreatedPage& state) {
  auto source = state.source_;
  PCNativePage* parent = source ? state.Parent(*source) : nil;
  PCNativeBrowserWindow* binding = state.browser_ ?
      AppKitBindingForBrowser(state.browser_.get()) : nil;
  return parent && binding &&
      [binding.client respondsToSelector:@selector(nativeBrowser:canPresentPeekFrom:)] &&
      [binding.client nativeBrowser:binding canPresentPeekFrom:parent] &&
      source && state.Parent(*source) == parent;
}
bool CanNavigatePeekSource(CreatedPage& state) {
  auto source = state.source_;
  PCNativePage* page = source ? state.Parent(*source) : nil;
  PCNativeBrowserWindow* binding = state.browser_ ?
      AppKitBindingForBrowser(state.browser_.get()) : nil;
  return page && binding &&
      [binding.client respondsToSelector:@selector(nativeBrowser:canNavigatePeekLinkFromPage:)] &&
      [binding.client nativeBrowser:binding canNavigatePeekLinkFromPage:page] &&
      source && state.Parent(*source) == page;
}
NativeShiftLinkClick NativeShiftClick(CreatedPage& creation, content::WebContents& source,
                                      content::RenderFrameHost& frame,
                                      NSEventModifierFlags modifiers) {
  using Sandbox = network::mojom::WebSandboxFlags;
  NativeShiftLinkClick click{.modifiers = modifiers,
      .frame_can_navigate_page = NativeFrameCanNavigatePage(
          &frame == source.GetPrimaryMainFrame(), frame.IsSandboxed(Sandbox::kTopNavigation),
          frame.IsSandboxed(Sandbox::kTopNavigationByUserActivation))};
  PCNativeBrowserWindow* binding = creation.browser_ ?
      AppKitBindingForBrowser(creation.browser_.get()) : nil;
  click.shift_peek_enabled = creation.Parent(source) && binding &&
      [binding.client respondsToSelector:@selector(nativeBrowser:allowsPeekWithShift:)] &&
      [binding.client nativeBrowser:binding allowsPeekWithShift:YES];
  click.in_shown_peek = click.shift_peek_enabled && CanNavigatePeekSource(creation);
  click.can_open_peek = click.shift_peek_enabled && !click.in_shown_peek &&
      CanPresentSource(creation);
  return click;
}
bool CanRouteSource(CreatedPage& state) {
  auto source = state.source_;
  PCNativePage* page = source ? state.Parent(*source) : nil;
  PCNativeBrowserWindow* binding = state.browser_ ? AppKitBindingForBrowser(state.browser_.get()) : nil;
  return page && binding && !state.browser_->GetProfile()->IsOffTheRecord() &&
      [binding.client respondsToSelector:@selector(nativeBrowser:canRouteCurrentLinkFrom:)] &&
      [binding.client nativeBrowser:binding canRouteCurrentLinkFrom:page] &&
      source && state.Parent(*source) == page;
}
PCNativeLinkRoute* MatchedRoute(CreatedPage& state, const GURL& target) {
  if (!CanRouteSource(state)) return nil;
  auto source = state.source_;
  PCNativePage* page = state.Parent(*source);
  PCNativeBrowserWindow* binding = AppKitBindingForBrowser(state.browser_.get());
  NSURL* url = [NSURL URLWithString:@(target.spec().c_str())];
  NSURL* current = [NSURL URLWithString:@(source->GetLastCommittedURL().spec().c_str())];
  if (!url || ![binding.client respondsToSelector:
      @selector(nativeBrowser:routeCurrentLinkFrom:targetURL:authenticationContinuation:)]) return nil;
  PCNativeLinkRoute* route = [binding.client nativeBrowser:binding routeCurrentLinkFrom:page
      targetURL:url authenticationContinuation:IsAuthenticationContinuation(current, url)];
  if (!CanRouteSource(state) || !route.ruleIdentifier.length ||
      !route.spaceIdentifier.length || !route.profilePath.isAbsolutePath ||
      ![route.profilePath isEqualToString:route.profilePath.stringByStandardizingPath]) return nil;
  return route;
}
bool SameRoute(PCNativeLinkRoute* a, PCNativeLinkRoute* b) {
  return a && b && [a.ruleIdentifier isEqualToString:b.ruleIdentifier] &&
      [a.spaceIdentifier isEqualToString:b.spaceIdentifier] &&
      [a.profilePath isEqualToString:b.profilePath];
}
class RoutedPage final : public base::SupportsUserData::Data {
 public:
  RoutedPage(PCNativeLinkRoute* value, BrowserWindowInterface& owner, bool background)
      : route(value), browser(owner.GetWeakPtr()), background(background) {}
  PCNativeLinkRoute* __strong route;
  base::WeakPtr<BrowserWindowInterface> browser;
  const bool background;
};

class CreatedRoute final : public base::SupportsUserData::Data,
                           public content::WebContentsObserver {
 public:
  CreatedRoute(std::unique_ptr<CreatedPage> origin, PCNativeLinkRoute* value,
      NSString* source_space, GURL target_url, bool in_background)
      : content::WebContentsObserver(origin->source_.get()),
        source(std::move(origin)), route(value), space([source_space copy]),
        target(std::move(target_url)),
        source_url(source->source_->GetLastCommittedURL()), background(in_background) {}
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame()) invalid = true;
  }
  void WebContentsDestroyed() override { invalid = true; }
  bool invalid = false;
  std::unique_ptr<CreatedPage> source;
  PCNativeLinkRoute* __strong route;
  NSString* __strong space;
  const GURL target;
  const GURL source_url;
  const bool background;
};
NSString* RoutingSourceSpace(CreatedPage& origin) {
  if (!CanRouteSource(origin)) return nil;
  auto source = origin.source_;
  PCNativePage* page = origin.Parent(*source);
  PCNativeBrowserWindow* binding = AppKitBindingForBrowser(origin.browser_.get());
  if (![binding.client respondsToSelector:@selector(nativeBrowser:linkRouteSourceSpaceForPage:)])
    return nil;
  NSString* space = [binding.client nativeBrowser:binding linkRouteSourceSpaceForPage:page];
  return space.length && CanRouteSource(origin) ? [space copy] : nil;
}
bool SameProfileRoute(CreatedPage& origin, PCNativeLinkRoute* route) {
  auto browser = origin.browser_;
  if (!browser || !route || !NativeLeaseForProfile(*browser->GetProfile())) return false;
  return [route.profilePath isEqualToString:
      base::SysUTF8ToNSString(browser->GetProfile()->GetPath().value())];
}
class CreatedRouteAttempt final : public base::SupportsUserData::Data {
 public:
  bool interrupted = false;
};
void AdmitCreatedRoute(content::WebContents& contents) {
  if (auto* active = static_cast<CreatedRouteAttempt*>(
          contents.GetUserData(&kCreatedRouteAttemptKey))) {

    active->interrupted = true;
    return;
  }

  auto data = contents.TakeUserData(&kCreatedRouteKey);
  auto* intent = static_cast<CreatedRoute*>(data.get());
  if (!intent) return;
  auto child = contents.GetWeakPtr();
  auto attempt_data = std::make_unique<CreatedRouteAttempt>();
  auto* attempt = attempt_data.get();
  contents.SetUserData(&kCreatedRouteAttemptKey, std::move(attempt_data));
  auto& origin = *intent->source;
  auto browser = origin.browser_;
  const auto valid = [&] {
    return child && child->GetUserData(&kCreatedRouteAttemptKey) == attempt &&
        !attempt->interrupted && !intent->invalid && browser && origin.source_ &&
        origin.source_->GetLastCommittedURL() == intent->source_url &&
        origin.Parent(*child) &&
        GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(child.get()) == browser.get() &&
        SameProfileRoute(origin, intent->route);
  };
  const bool admitted = [&] {
    if (!valid() || ![intent->space isEqualToString:RoutingSourceSpace(origin)] || !valid() ||
        !SameRoute(intent->route, MatchedRoute(origin, intent->target)) || !valid()) return false;
    PCNativeBrowserWindow* binding = AppKitBindingForBrowser(browser.get());
    return [binding.client respondsToSelector:@selector(nativeBrowser:canAcceptLinkRoute:)] &&
        [binding.client nativeBrowser:binding canAcceptLinkRoute:intent->route] && valid() &&
        [intent->space isEqualToString:RoutingSourceSpace(origin)] && valid();
  }();
  if (child && child->GetUserData(&kCreatedRouteAttemptKey) == attempt)
    child->RemoveUserData(&kCreatedRouteAttemptKey);
  if (!admitted || !child) return;

  child->SetUserData(&kRoutedPageKey,
      std::make_unique<RoutedPage>(intent->route, *browser, intent->background));
}

bool AllowsCurrentLink(CreatedPage& creation, const GURL& target) {
  if (!CanPresentSource(creation)) return false;
  auto source = creation.source_;
  PCNativePage* parent = creation.Parent(*source);
  PCNativeBrowserWindow* binding = AppKitBindingForBrowser(creation.browser_.get());
  NSURL* url = [NSURL URLWithString:@(target.spec().c_str())];
  NSURL* current = [NSURL URLWithString:@(source->GetLastCommittedURL().spec().c_str())];
  return binding && url && !IsMeetingURL(url) &&
      !IsAuthenticationContinuation(current, url) &&
      [binding.client respondsToSelector:@selector(nativeBrowser:allowsPeekWithShift:)] &&
      [binding.client nativeBrowser:binding allowsPeekWithShift:NO] &&
      CanPresentSource(creation) &&
      [binding.client respondsToSelector:@selector(nativeBrowser:shouldOpenCurrentLinkInPeekFrom:targetURL:)] &&
      [binding.client nativeBrowser:binding shouldOpenCurrentLinkInPeekFrom:parent targetURL:url] &&
      CanPresentSource(creation);
}

class HeldShiftOpening final : public content::WebContentsObserver {
 public:
  HeldShiftOpening(content::WebContents& source, const content::WeakDocumentPtr& opener,
                   BrowserWindowInterface& browser, const GURL& target,
                   WindowOpenDisposition disposition,
                   const blink::mojom::WindowFeatures& features, bool user_gesture)
      : source_(source.GetWeakPtr()), opener_(opener), browser_(browser.GetWeakPtr()),
        target_(target), disposition_(disposition), features_(features.Clone()),
        user_gesture_(user_gesture) {}
  ~HeldShiftOpening() override {
    if (auto contents = Unhold())
      base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, std::move(contents));
  }
  content::WebContents* source() const { return source_.get(); }
  base::WeakPtr<HeldShiftOpening> GetWeakPtr() { return weak_factory_.GetWeakPtr(); }
  void Hold(std::unique_ptr<content::WebContents> contents) {
    contents_ = std::move(contents);
    Observe(contents_.get());
  }
  bool Capture(content::NavigationHandle& navigation) {
    if (settled_ || !contents_ || navigation.GetWebContents() != contents_.get() ||
        !navigation.IsInPrimaryMainFrame()) return false;
    settled_ = true;
    auto params = SamePeekParams(navigation);
    if (!params) {
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
          base::BindOnce(&HeldShiftOpening::Release, weak_factory_.GetWeakPtr()));
      return false;
    }
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce(&HeldShiftOpening::Finish, weak_factory_.GetWeakPtr(),
                       std::move(params)));
    return true;
  }
  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    if (settled_ || !navigation->IsInPrimaryMainFrame()) return;
    settled_ = true;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce(&HeldShiftOpening::Release, weak_factory_.GetWeakPtr()));
  }

 private:
  std::unique_ptr<content::WebContents> Unhold() {
    Observe(nullptr);
    if (contents_) contents_->RemoveUserData(&kShiftOpeningHoldKey);
    return std::move(contents_);
  }
  std::unique_ptr<content::OpenURLParams> SamePeekParams(content::NavigationHandle& navigation) {
    auto* opener = opener_.AsRenderFrameHostIfValid();
    const auto& initiator = navigation.GetInitiatorFrameToken();
    NativeHeldShiftNavigation held{
        .web_url = navigation.GetURL().SchemeIsHTTPOrHTTPS(),
        .from_opener = source_ && browser_ && opener && initiator &&
            content::WebContents::FromRenderFrameHost(opener) == source_.get() &&
            opener->GetGlobalFrameToken() == content::GlobalRenderFrameHostToken(
                navigation.GetInitiatorProcessId(), *initiator),
        .post = navigation.IsPost(),
        .has_body = static_cast<bool>(navigation.GetPostData())};
    if (held.from_opener) {
      CreatedPage admission(*source_, *source_->GetPrimaryMainFrame(), *browser_);
      held.peek_takes_link = CanNavigatePeekSource(admission);
    }
    opener = opener_.AsRenderFrameHostIfValid();
    if (!opener || !source_ || !NativeHeldShiftNavigationJoinsPeek(held)) return nullptr;
    auto params = std::make_unique<content::OpenURLParams>(
        content::OpenURLParams::CreateRendererInitiated(navigation.GetURL(),
            WindowOpenDisposition::CURRENT_TAB, ui::PAGE_TRANSITION_LINK, content::Referrer(),
            opener->GetCurrentInitiatorNavigationState()));
    params->user_gesture = true;
    params->initiator_origin = opener->GetLastCommittedOrigin();
    params->initiator_frame_token = opener->GetFrameToken();
    params->initiator_process_id = opener->GetProcess()->GetDeprecatedID();
    params->source_site_instance = opener->GetSiteInstance();
    CarryNativeShiftRequest(*params, content::Referrer(navigation.GetReferrer()),
        held.post ? navigation.GetPostData() : nullptr,
        held.post ? navigation.GetRequestHeaders()
                        .GetHeader(net::HttpRequestHeaders::kContentType)
                        .value_or(std::string())
                  : std::string());
    return params;
  }
  void Finish(std::unique_ptr<content::OpenURLParams> params) {
    const auto self = weak_factory_.GetWeakPtr();
    Unhold().reset();
    const auto source = source_;
    const auto browser = browser_;
    if (source && browser) {
      CreatedPage admission(*source, *source->GetPrimaryMainFrame(), *browser);
      if (!CanNavigatePeekSource(admission))
        params->disposition = WindowOpenDisposition::NEW_WINDOW;
      auto* delegate = source && browser ?
          BrowserWebContentsDelegate::From(browser.get()) : nullptr;
      if (delegate)
        delegate->BrowserWebContentsDelegate::OpenURLFromTab(source.get(), *params, {});
    }
    if (self) Done();
  }
  void Release() {
    const auto self = weak_factory_.GetWeakPtr();
    auto contents = Unhold();
    const auto source = source_;
    const auto browser = browser_;
    const GURL target = target_;
    const auto disposition = disposition_;
    const auto features = features_->Clone();
    const bool user_gesture = user_gesture_;
    auto* delegate = browser ? BrowserWebContentsDelegate::From(browser.get()) : nullptr;
    if (contents && source && delegate) {
      delegate->BrowserWebContentsDelegate::AddNewContents(source.get(), std::move(contents),
          target, disposition, *features, user_gesture, nullptr);
    }
    if (self) Done();
  }
  void Done();

  const base::WeakPtr<content::WebContents> source_;
  const content::WeakDocumentPtr opener_;
  const base::WeakPtr<BrowserWindowInterface> browser_;
  const GURL target_;
  const WindowOpenDisposition disposition_;
  const blink::mojom::WindowFeaturesPtr features_;
  const bool user_gesture_;
  std::unique_ptr<content::WebContents> contents_;
  bool settled_ = false;
  base::WeakPtrFactory<HeldShiftOpening> weak_factory_{this};
};
class ShiftOpeningHold final : public base::SupportsUserData::Data {
 public:
  explicit ShiftOpeningHold(std::unique_ptr<HeldShiftOpening> opening)
      : pending(std::move(opening)) {}
  std::unique_ptr<HeldShiftOpening> pending;
  base::WeakPtr<HeldShiftOpening> held;
};
class HeldShiftOpenings final : public base::SupportsUserData::Data {
 public:
  std::vector<std::unique_ptr<HeldShiftOpening>> openings;
};
void HeldShiftOpening::Done() {
  auto* list = source_ ? static_cast<HeldShiftOpenings*>(
      source_->GetUserData(&kHeldShiftOpeningsKey)) : nullptr;
  if (list)
    std::erase_if(list->openings, [this](const auto& opening) { return opening.get() == this; });
}
class ShiftOpeningThrottle final : public content::NavigationThrottle {
 public:
  using content::NavigationThrottle::NavigationThrottle;
  ThrottleCheckResult WillStartRequest() override {
    auto* hold = static_cast<ShiftOpeningHold*>(
        navigation_handle()->GetWebContents()->GetUserData(&kShiftOpeningHoldKey));
    base::WeakPtr<HeldShiftOpening> opening;
    if (hold) opening = hold->held;
    return opening && opening->Capture(*navigation_handle()) ? CANCEL_AND_IGNORE : PROCEED;
  }
  const char* GetNameForLogging() override { return "ParcShiftOpeningThrottle"; }
};
}
void UpdateNativeLinkURL(content::WebContents& contents, const GURL& url) {
  auto* state = static_cast<URLLockState*>(contents.GetUserData(&kURLLockKey));
  if (state) state->UpdateURL(url);
}
void EnableNativeLinkNavigation(content::WebContents& contents) {
  if (!contents.GetUserData(&kURLLockKey))
    contents.SetUserData(&kURLLockKey, std::make_unique<URLLockState>(contents));
  contents.GetMutableRendererPrefs()->native_main_frame_link_policy = true;
  contents.SyncRendererPrefs();
}
std::optional<base::UnguessableToken> PrepareNativeCurrentLink(
    BrowserWindowInterface& browser, content::RenderFrameHost* frame,
    const GURL& target, WindowOpenDisposition disposition,
    std::optional<uint32_t> input_modifiers) {
  const bool modified = disposition == WindowOpenDisposition::NEW_FOREGROUND_TAB ||
      disposition == WindowOpenDisposition::NEW_BACKGROUND_TAB;

  if (disposition != WindowOpenDisposition::CURRENT_TAB && !modified) return std::nullopt;
  if (modified && (!input_modifiers ||
      (*input_modifiers & blink::WebInputEvent::kAltKey))) return std::nullopt;
  auto* source = frame ? content::WebContents::FromRenderFrameHost(frame) : nullptr;
  if (!source || frame != source->GetPrimaryMainFrame() ||
      source->GetBrowserContext() != browser.GetProfile() ||
      !target.SchemeIsHTTPOrHTTPS() || !AppKitBrowserAcceptsNewPages(browser))
    return std::nullopt;

  auto* sequence = static_cast<CurrentLinkSequence*>(
      source->GetUserData(&kCurrentLinkSequenceKey));
  if (!sequence) {
    auto value = std::make_unique<CurrentLinkSequence>();
    sequence = value.get();
    source->SetUserData(&kCurrentLinkSequenceKey, std::move(value));
  }
  const uint64_t expected_sequence = ++sequence->value;
  const auto source_lease = source->GetWeakPtr();
  const auto is_current = [&] {
    return source_lease && source_lease->GetUserData(&kCurrentLinkSequenceKey) == sequence &&
        sequence->value == expected_sequence;
  };

  source->RemoveUserData(&kPendingCurrentLinkKey);
  auto creation = std::make_unique<CreatedPage>(*source, *frame, browser);
  PCNativeLinkRoute* route = MatchedRoute(*creation, target);
  if ((!route && (modified || !AllowsCurrentLink(*creation, target))) ||
      !is_current()) return std::nullopt;

  auto pending = std::make_unique<PendingCurrentLink>(
      std::move(creation), target, expected_sequence, route, disposition);
  const auto token = pending->token;
  source->SetUserData(&kPendingCurrentLinkKey, std::move(pending));
  return token;
}
struct NativePeekNavigation::State {
  State(std::unique_ptr<CreatedPage> source, const content::OpenURLParams& original)
      : creation(std::move(source)), params(original) {}
  std::unique_ptr<CreatedPage> creation;
  content::OpenURLParams params;
  bool peek = true;
};
NativePeekNavigation::NativePeekNavigation(std::unique_ptr<State> state)
    : state_(std::move(state)) {}
NativePeekNavigation::~NativePeekNavigation() = default;
const content::OpenURLParams& NativePeekNavigation::params() const {
  return state_->params;
}
bool NativePeekNavigation::SplitStillValid() const {
  auto* creation = state_->creation.get();
  if (!creation || !creation->split_lease_ || !creation->source_ || !creation->browser_) return false;
  auto source = creation->source_;
  PCNativePage* parent = creation->Parent(*source);
  PCNativeBrowserWindow* binding = AppKitBindingForBrowser(creation->browser_.get());
  return parent && binding && [binding.client respondsToSelector:
      @selector(nativeBrowser:isSplitLinkLeaseCurrent:forPage:)] &&
      [binding.client nativeBrowser:binding isSplitLinkLeaseCurrent:creation->split_lease_ forPage:parent] &&
      source && creation->Parent(*source) == parent;
}
void NativePeekNavigation::DidNavigate(content::WebContents* created) {
  if (!state_->creation || !created || created == state_->creation->source_.get() ||
      Creation(*created) || !state_->creation->Parent(*created)) return;

  state_->creation->peek_ = state_->peek;
  created->SetUserData(&kCreatedPageKey, std::move(state_->creation));
}
static std::unique_ptr<CreatedPage> CaptureSplitOrigin(
    BrowserWindowInterface& browser, content::WebContents* source,
    content::RenderFrameHost* frame, content::WebContents& child) {
  if (!source || !frame || frame->IsNestedWithinFencedFrame() ||
      frame->GetOutermostMainFrame() != source->GetPrimaryMainFrame() ||
      source->GetBrowserContext() != browser.GetProfile() ||
      !AppKitBrowserAcceptsNewPages(browser)) return nullptr;
  auto creation = std::make_unique<CreatedPage>(*source, *source->GetPrimaryMainFrame(), browser);
  const auto source_lease = source->GetWeakPtr();
  const auto child_lease = child.GetWeakPtr();
  const GURL source_url = source->GetLastCommittedURL();
  creation->split_source_url_ = source_url;
  creation->split_observer_ = std::make_unique<SplitSourceObserver>(*source);
  PCNativePage* parent = creation->Parent(*source);
  PCNativeBrowserWindow* binding = AppKitBindingForBrowser(&browser);
  if (!parent || !binding || ![binding.client respondsToSelector:
      @selector(nativeBrowser:splitLinkLeaseForPage:)]) return nullptr;
  id lease = [binding.client nativeBrowser:binding splitLinkLeaseForPage:parent];
  if (!lease || !source_lease || !child_lease || source_lease->GetLastCommittedURL() != source_url ||
      creation->Parent(*child_lease) != parent ||
      ![binding.client respondsToSelector:@selector(nativeBrowser:isSplitLinkLeaseCurrent:forPage:)] ||
      ![binding.client nativeBrowser:binding isSplitLinkLeaseCurrent:lease forPage:parent] ||
      !source_lease || !child_lease || source_lease->GetLastCommittedURL() != source_url ||
      creation->Parent(*child_lease) != parent) return nullptr;
  creation->split_lease_ = lease;
  return creation;
}
std::unique_ptr<NativePeekNavigation> PrepareNativeSplitNavigation(
    BrowserWindowInterface& browser, content::WebContents* source,
    const content::OpenURLParams& params) {
  if (!source || !params.is_renderer_initiated || !params.user_gesture ||
      params.started_from_context_menu || !params.url.SchemeIsHTTPOrHTTPS() ||
      params.disposition != WindowOpenDisposition::NEW_SPLIT_VIEW ||
      !params.initiator_frame_token || params.native_route_token ||
      !ui::PageTransitionCoreTypeIs(params.transition, ui::PAGE_TRANSITION_LINK)) return nullptr;
  auto* frame = content::RenderFrameHost::FromFrameToken(content::GlobalRenderFrameHostToken(
      params.initiator_process_id, *params.initiator_frame_token));
  auto creation = CaptureSplitOrigin(browser, source, frame, *source);
  if (!creation) return nullptr;
  auto state = std::make_unique<NativePeekNavigation::State>(std::move(creation), params);
  state->peek = false;
  state->params.native_route_split = true;
  return std::unique_ptr<NativePeekNavigation>(new NativePeekNavigation(std::move(state)));
}
bool NativeSplitLinkAvailable(BrowserWindowInterface& browser, content::WebContents& source) {
  if (!HasNativeSplitOwner(browser, source) || browser.IsDeleteScheduled() ||
      !AppKitBrowserAcceptsNewPages(browser)) return false;
  PCNativePage* page = ExistingNativePage(&source);
  PCNativeBrowserWindow* binding = AppKitBindingForBrowser(&browser);
  return page && !page.closed && binding &&
      [PCNativeBrowserApplication ownerForPage:page] == binding &&
      page.nativeView.window == binding.window &&
      [binding.client respondsToSelector:@selector(nativeBrowser:canSplitLinkFromPage:)] &&
      [binding.client nativeBrowser:binding canSplitLinkFromPage:page];
}
std::optional<base::UnguessableToken> PrepareNativeOptionLink(
    BrowserWindowInterface& browser, content::RenderFrameHost* frame, const GURL& target) {
  auto* source = frame ? content::WebContents::FromRenderFrameHost(frame) : nullptr;
  if (!source || frame->IsNestedWithinFencedFrame() ||
      frame->GetOutermostMainFrame() != source->GetPrimaryMainFrame() ||
      source->GetBrowserContext() != browser.GetProfile() || !target.SchemeIsHTTPOrHTTPS())
    return std::nullopt;
  auto pending = std::make_unique<PendingOptionLink>(*frame, target);
  const auto token = pending->token;
  source->SetUserData(&kPendingOptionLinkKey, std::move(pending));
  return token;
}
std::unique_ptr<content::OpenURLParams> TakeNativeOptionLink(
    content::WebContents* source, const content::OpenURLParams& params) {
  auto* pending = source ? static_cast<PendingOptionLink*>(
      source->GetUserData(&kPendingOptionLinkKey)) : nullptr;
  if (!pending || !params.native_route_token || pending->token != *params.native_route_token ||
      params.disposition != WindowOpenDisposition::SAVE_TO_DISK) return nullptr;
  auto data = source->TakeUserData(&kPendingOptionLinkKey);
  pending = static_cast<PendingOptionLink*>(data.get());
  auto* frame = pending->document.AsRenderFrameHostIfValid();
  if (!frame || frame->GetGlobalFrameToken() != pending->initiator ||
      frame->IsNestedWithinFencedFrame() ||
      frame->GetOutermostMainFrame() != source->GetPrimaryMainFrame() ||
      !params.initiator_frame_token ||
      content::GlobalRenderFrameHostToken(params.initiator_process_id,
          *params.initiator_frame_token) != pending->initiator ||
      !params.is_renderer_initiated || !params.user_gesture ||
      params.started_from_context_menu || params.url != pending->url ||
      !ui::PageTransitionCoreTypeIs(params.transition, ui::PAGE_TRANSITION_LINK))
    return nullptr;
  auto split = std::make_unique<content::OpenURLParams>(params);
  split->native_route_token.reset();
  split->disposition = WindowOpenDisposition::NEW_SPLIT_VIEW;
  return split;
}
std::unique_ptr<NativePeekNavigation> PrepareNativePeekNavigation(
    BrowserWindowInterface& browser, content::WebContents* source,
    const content::OpenURLParams& params) {
  if (params.native_route_token) {
    auto* pending = source ? static_cast<PendingCurrentLink*>(
        source->GetUserData(&kPendingCurrentLinkKey)) : nullptr;
    if (!pending || pending->route ||
        pending->disposition != WindowOpenDisposition::CURRENT_TAB ||
        pending->token != *params.native_route_token) return nullptr;

    auto creation = std::move(pending->creation);
    const GURL target = pending->url;
    const GURL source_url = pending->source_url;
    const uint64_t expected_sequence = pending->sequence;
    const auto source_lease = source->GetWeakPtr();
    source->RemoveUserData(&kPendingCurrentLinkKey);
    if (!creation || creation->browser_.get() != &browser ||
        !params.is_renderer_initiated || !params.user_gesture ||
        params.disposition != WindowOpenDisposition::NEW_FOREGROUND_TAB ||
        params.url != target || !params.initiator_frame_token ||
        !ui::PageTransitionCoreTypeIs(params.transition, ui::PAGE_TRANSITION_LINK))
      return nullptr;
    auto* frame = creation->document_.AsRenderFrameHostIfValid();
    if (!frame || frame != source->GetPrimaryMainFrame() ||
        frame->GetGlobalFrameToken() != content::GlobalRenderFrameHostToken(
            params.initiator_process_id, *params.initiator_frame_token) ||
        source->GetLastCommittedURL() != source_url ||
        !AllowsCurrentLink(*creation, target) || !source_lease) return nullptr;
    auto* sequence = static_cast<CurrentLinkSequence*>(
        source_lease->GetUserData(&kCurrentLinkSequenceKey));
    if (!sequence || sequence->value != expected_sequence) return nullptr;
    auto state = std::make_unique<NativePeekNavigation::State>(std::move(creation), params);
    state->params.native_route_token.reset();
    return std::unique_ptr<NativePeekNavigation>(new NativePeekNavigation(std::move(state)));
  }

  if (source && source->GetBrowserContext() == browser.GetProfile() &&
      AppKitBrowserAcceptsNewPages(browser) &&
      (params.disposition == WindowOpenDisposition::NEW_FOREGROUND_TAB ||
       params.disposition == WindowOpenDisposition::NEW_BACKGROUND_TAB)) {
    auto* frame = params.initiator_frame_token ?
        content::RenderFrameHost::FromFrameToken(content::GlobalRenderFrameHostToken(
            params.initiator_process_id, *params.initiator_frame_token)) :
        (!params.is_renderer_initiated ? source->GetPrimaryMainFrame() : nullptr);
    if (frame && frame == source->GetPrimaryMainFrame()) {
      auto creation = std::make_unique<CreatedPage>(*source, *frame, browser);
      if (creation->Parent(*source)) {
        auto state = std::make_unique<NativePeekNavigation::State>(std::move(creation), params);
        state->peek = false;
        return std::unique_ptr<NativePeekNavigation>(new NativePeekNavigation(std::move(state)));
      }
    }
  }

  if (!source || !params.is_renderer_initiated || !params.user_gesture ||
      params.started_from_context_menu || !params.url.SchemeIsHTTPOrHTTPS() ||
      params.disposition != WindowOpenDisposition::NEW_WINDOW ||
      !ui::PageTransitionCoreTypeIs(params.transition, ui::PAGE_TRANSITION_LINK) ||
      !params.initiator_frame_token || !AppKitBrowserAcceptsNewPages(browser))
    return nullptr;
  auto* frame = content::RenderFrameHost::FromFrameToken(
      content::GlobalRenderFrameHostToken(params.initiator_process_id,
                                         *params.initiator_frame_token));
  auto* main_frame = source->GetPrimaryMainFrame();
  if (!frame || frame->IsNestedWithinFencedFrame() ||
      frame->GetOutermostMainFrame() != main_frame ||
      source->GetBrowserContext() != browser.GetProfile()) return nullptr;
  auto creation = std::make_unique<CreatedPage>(*source, *main_frame, browser);
  const auto link = ClassifyNativeShiftLink(
      NativeShiftClick(*creation, *source, *frame, creation->modifiers_));
  if (link == NativeShiftLink::kOrdinary ||
      !(link == NativeShiftLink::kSamePeek ? CanNavigatePeekSource(*creation)
                                           : CanPresentSource(*creation))) return nullptr;
  auto state = std::make_unique<NativePeekNavigation::State>(std::move(creation), params);
  state->peek = link == NativeShiftLink::kPeek;
  RetargetNativeShiftLink(state->params, link, WindowOpenDisposition::CURRENT_TAB,
                          WindowOpenDisposition::NEW_FOREGROUND_TAB);
  return std::unique_ptr<NativePeekNavigation>(
      new NativePeekNavigation(std::move(state)));
}
namespace {
class MatchedLinkOperation final : public content::WebContentsObserver,
                                  public std::enable_shared_from_this<MatchedLinkOperation> {
 public:
  MatchedLinkOperation(std::unique_ptr<CreatedPage> source,
      PCNativeLinkRoute* route, uint64_t sequence, bool enforce_sequence, GURL source_url,
      const content::OpenURLParams& params,
      base::OnceCallback<void(content::NavigationHandle&)> callback)
      : content::WebContentsObserver(source->source_.get()), source_(std::move(source)),
        route_(route), sequence_(sequence), enforce_sequence_(enforce_sequence),
        source_url_(std::move(source_url)),
        params_(params), callback_(std::move(callback)) {
    params_.native_route_token.reset();
    params_.native_route_background =
        params_.disposition == WindowOpenDisposition::NEW_BACKGROUND_TAB;
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame()) invalid_ = true;
  }
  void WebContentsDestroyed() override { invalid_ = true; }
  bool Valid() {
    if (invalid_ || !source_->source_ || !CanRouteSource(*source_) ||
        source_->source_->GetLastCommittedURL() != source_url_) return false;
    if (!SameRoute(route_, MatchedRoute(*source_, params_.url)) || invalid_ ||
        !source_->source_) return false;
    auto* sequence = static_cast<CurrentLinkSequence*>(
        source_->source_->GetUserData(&kCurrentLinkSequenceKey));

    return !enforce_sequence_ || (sequence && sequence->value == sequence_);
  }
  void Start() {
    if (!Valid()) return Finish(nil);
    PCNativeBrowserWindow* binding = AppKitBindingForBrowser(source_->browser_.get());
    if (![binding.client respondsToSelector:@selector(nativeBrowser:prepareLinkRoute:)])
      return Finish(Error(@"The destination window is unavailable."));
    destination_ = [binding.client nativeBrowser:binding prepareLinkRoute:route_];
    if (!destination_) return Finish(Error(@"The destination window is unavailable."));
    if (!Valid()) return Finish(nil);
    WithNativeRoutingBrowser(destination_, route_.profilePath, base::BindOnce(
        [](std::shared_ptr<MatchedLinkOperation> operation,
           BrowserWindowInterface* browser, bool created, NSError* error) {
          operation->Run(browser, created, error);
        }, shared_from_this()));
  }
 private:
  static NSError* Error(NSString* message) {
    return [NSError errorWithDomain:@"org.parc.internal-routing" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}];
  }
  void Run(BrowserWindowInterface* browser, bool created, NSError* error) {
    const auto destination = browser ? browser->GetWeakPtr() : base::WeakPtr<BrowserWindowInterface>();
    if (created && destination) empty_browser_ = destination;
    if (!destination || !Valid() || !destination ||
        AppKitBindingForBrowser(destination.get()) != destination_ ||
        !AppKitBrowserAcceptsNewPages(*destination) ||
        ![base::SysUTF8ToNSString(destination->GetProfile()->GetPath().value())
            isEqualToString:route_.profilePath] || !NativeLeaseForProfile(*destination->GetProfile()) ||
        ![destination_.client respondsToSelector:@selector(nativeBrowser:canAcceptLinkRoute:)] ||
        ![destination_.client nativeBrowser:destination_ canAcceptLinkRoute:route_] ||
        !destination || !Valid() || !destination) {
      Finish(error); return;
    }
    auto* delegate = BrowserWebContentsDelegate::From(destination.get());
    if (!delegate) { Finish(Error(@"The destination Browser is unavailable.")); return; }

    auto callback = base::BindOnce(
        [](std::shared_ptr<MatchedLinkOperation> operation,
           base::WeakPtr<BrowserWindowInterface> destination,
           content::NavigationHandle& navigation) {

          auto* page = navigation.GetWebContents();
          operation->observed_page_ = page->GetWeakPtr();
          operation->observed_navigation_ = true;
          if (destination && page->GetBrowserContext() == destination->GetProfile()) {
            operation->AttachCreation(*page, *destination);
            page->SetUserData(&kRoutedPageKey,
                std::make_unique<RoutedPage>(operation->route_, *destination,
                    operation->params_.native_route_background));
          }
          if (operation->callback_) std::move(operation->callback_).Run(navigation);
        }, shared_from_this(), destination);
    auto* page = delegate->BrowserWebContentsDelegate::OpenURLFromTab(
        source_->source_.get(), params_, std::move(callback));
    if (!page || !destination ||
        (observed_navigation_ && observed_page_.get() != page) ||
        page->GetBrowserContext() != destination->GetProfile()) {
      Finish(Error(@"This link could not open in its destination.")); return;
    }
    AttachCreation(*page, *destination);
    page->SetUserData(&kRoutedPageKey, std::make_unique<RoutedPage>(route_, *destination, params_.native_route_background));
    const auto page_lease = page->GetWeakPtr();
    if (source_->source_ && source_->document_.AsRenderFrameHostIfValid())
      content::NotifyNativeDeferredOpenURL(source_->source_.get(), page, source_->document_, params_);

    if (!page_lease || !destination ||
        destination->GetTabStripModel()->GetIndexOfWebContents(page_lease.get()) == TabStripModel::kNoTab) {
      Finish(nil); return;
    }

    if (params_.native_route_background && empty_browser_ && destination)
      destination->GetWindow()->ShowInactive();
    empty_browser_.reset();
    Finish(nil);
  }
  void AttachCreation(content::WebContents& page, BrowserWindowInterface& destination) {
    if (Creation(page) || &page == source_->source_.get() ||
        !source_->Source(page) || !source_->browser_ ||
        destination.GetProfile() != source_->browser_->GetProfile()) return;
    auto receipt = std::make_unique<CreatedPage>(*source_, destination);
    if (!receipt->CreationSource(page)) return;
    page.SetUserData(&kCreatedPageKey, std::move(receipt));
  }
  void Finish(NSError* error) {
    if (finished_) return;
    finished_ = true;
    Observe(nullptr);
    callback_.Reset();
    if (empty_browser_ && !empty_browser_->IsDeleteScheduled() &&
        empty_browser_->GetTabStripModel()->empty()) empty_browser_->GetWindow()->Close();
    if (destination_) AbandonEmptyNativeRoutingWindow(destination_);
    if (error && source_->source_ && source_->browser_) {
      PCNativeBrowserWindow* binding = AppKitBindingForBrowser(source_->browser_.get());
      if ([binding.client respondsToSelector:@selector(nativeBrowser:didFailLinkRoute:)])
        [binding.client nativeBrowser:binding didFailLinkRoute:error];
    }
  }
  std::unique_ptr<CreatedPage> source_;
  PCNativeLinkRoute* __strong route_;
  const uint64_t sequence_;
  const bool enforce_sequence_;
  const GURL source_url_;
  content::OpenURLParams params_;
  base::OnceCallback<void(content::NavigationHandle&)> callback_;
  PCNativeBrowserWindow* __strong destination_ = nil;
  base::WeakPtr<BrowserWindowInterface> empty_browser_;
  base::WeakPtr<content::WebContents> observed_page_;
  bool observed_navigation_ = false;
  bool invalid_ = false;
  bool finished_ = false;
};
}
bool HandleNativeMatchedLink(BrowserWindowInterface& browser, content::WebContents* source,
    const content::OpenURLParams& params,
    base::OnceCallback<void(content::NavigationHandle&)>& callback) {
  if (!params.native_route_token || !source) return false;
  auto* pending = static_cast<PendingCurrentLink*>(source->GetUserData(&kPendingCurrentLinkKey));
  if (!pending || !pending->route || pending->token != *params.native_route_token) return false;
  PCNativeLinkRoute* route = pending->route;
  auto creation = std::move(pending->creation);
  const auto sequence = pending->sequence;
  const auto original_disposition = pending->disposition;
  const auto expected_disposition = original_disposition == WindowOpenDisposition::CURRENT_TAB
      ? WindowOpenDisposition::NEW_FOREGROUND_TAB : original_disposition;
  const GURL source_url = pending->source_url;
  const GURL target = pending->url;
  source->RemoveUserData(&kPendingCurrentLinkKey);
  auto* epoch = static_cast<CurrentLinkSequence*>(source->GetUserData(&kCurrentLinkSequenceKey));
  auto* frame = creation ? creation->document_.AsRenderFrameHostIfValid() : nullptr;
  if (!frame || !epoch || epoch->value != sequence || creation->browser_.get() != &browser ||
      frame != source->GetPrimaryMainFrame() || !params.initiator_frame_token ||
      frame->GetGlobalFrameToken() != content::GlobalRenderFrameHostToken(
          params.initiator_process_id, *params.initiator_frame_token) ||
      !params.is_renderer_initiated || !params.user_gesture || target != params.url ||
      params.disposition != expected_disposition ||
      !ui::PageTransitionCoreTypeIs(params.transition, ui::PAGE_TRANSITION_LINK)) {
    callback.Reset(); return true;
  }
  auto operation = std::make_shared<MatchedLinkOperation>(std::move(creation), route,
      sequence, original_disposition == WindowOpenDisposition::CURRENT_TAB,
      source_url, params, std::move(callback));
  operation->Start();
  return true;
}
void CaptureNativeCreatedPage(content::WebContents* source,
    content::GlobalRenderFrameHostId opener_id, content::WebContents* created) {
  if (!source || !created || source == created || Creation(*created)) return;
  auto* opener = content::RenderFrameHost::FromID(opener_id);
  if (opener && content::WebContents::FromRenderFrameHost(opener) == source &&
      !created->GetUserData(&kOpenedPageKey))
    created->SetUserData(&kOpenedPageKey, std::make_unique<OpenedPage>(*opener));
  PCNativePage* page = ExistingNativePage(source);
  PCNativeBrowserWindow* binding = page ?
      [PCNativeBrowserApplication ownerForPage:page] : nil;

  if (!binding || !opener || opener != source->GetPrimaryMainFrame() ||
      source->GetBrowserContext() != created->GetBrowserContext()) return;
  auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(source);
  if (!browser || AppKitBindingForBrowser(browser) != binding ||
      !AppKitBrowserAcceptsNewPages(*browser)) return;
  created->SetUserData(&kCreatedPageKey,
      std::make_unique<CreatedPage>(*source, *opener, *browser));
}
static void PrepareAutomaticCreatedPeek(BrowserWindowInterface& browser,
    content::WebContents* source, content::WebContents& created,
    const GURL& target, WindowOpenDisposition disposition, bool user_gesture) {
  auto* state = Creation(created);
  if (!state || state->source_.get() != source || state->browser_.get() != &browser ||
      state->offered_ || !user_gesture ||
      disposition != WindowOpenDisposition::NEW_FOREGROUND_TAB ||
      !target.SchemeIsHTTPOrHTTPS()) return;
  PCNativePage* parent = state->Parent(created);
  PCNativeBrowserWindow* binding = AppKitBindingForBrowser(&browser);
  NSURL* url = [NSURL URLWithString:@(target.spec().c_str())];
  if (!parent || !binding || !url) return;
  const auto child = created.GetWeakPtr();
  const auto valid = [&]() {
    return child && Creation(*child) == state && state->Parent(*child) == parent;
  };
  if (![binding.client respondsToSelector:@selector(nativeBrowser:allowsPeekWithShift:)] ||
      ![binding.client nativeBrowser:binding allowsPeekWithShift:NO] || !valid()) return;

  if (![binding.client respondsToSelector:@selector(nativeBrowser:shouldOpenNewPageInPeekFrom:targetURL:)] ||
      ![binding.client nativeBrowser:binding shouldOpenNewPageInPeekFrom:parent
                           targetURL:url] || !valid() ||
      !state->CanPresent(*child) || !valid()) return;
  state->peek_ = true;
}
static bool PrepareShiftCreatedPage(
    BrowserWindowInterface& browser, content::WebContents* source,
    content::WebContents& created, const OpenedPage& opened, const GURL& target,
    WindowOpenDisposition& disposition, const blink::mojom::WindowFeatures& features,
    bool user_gesture) {
  auto* frame = opened.document.AsRenderFrameHostIfValid();
  if (!source || !frame || content::WebContents::FromRenderFrameHost(frame) != source ||
      frame->GetOutermostMainFrame() != source->GetPrimaryMainFrame() ||
      source->GetBrowserContext() != browser.GetProfile() ||
      created.GetBrowserContext() != source->GetBrowserContext() ||
      !AppKitBrowserAcceptsNewPages(browser)) return false;
  const auto source_lease = source->GetWeakPtr();
  const auto child = created.GetWeakPtr();
  const bool fenced_frame = frame->IsNestedWithinFencedFrame();
  CreatedPage admission(*source, *source->GetPrimaryMainFrame(), browser);
  NativeShiftCreatedPage page{
      .click = NativeShiftClick(admission, *source, *frame, opened.modifiers),
      .user_gesture = user_gesture, .web_url = target.SchemeIsHTTPOrHTTPS(),
      .new_window = disposition == WindowOpenDisposition::NEW_WINDOW,
      .foreground_tab = disposition == WindowOpenDisposition::NEW_FOREGROUND_TAB,
      .popup = features.is_popup,
      .sized_by_page = features.has_x || features.has_y || features.has_width ||
          features.has_height,
      .fenced_frame = fenced_frame};
  const auto link = ClassifyNativeShiftCreatedPage(page);
  if (!source_lease || !child || link == NativeShiftLink::kOrdinary) return false;
  if (link == NativeShiftLink::kPeek) {
    const bool admitted = !Creation(*child);
    if (admitted)
      child->SetUserData(&kCreatedPageKey, std::make_unique<CreatedPage>(
          *source, *source->GetPrimaryMainFrame(), browser));
    auto* state = Creation(*child);
    if (state->source_.get() != source || state->browser_.get() != &browser ||
        state->offered_ || !state->CanPresent(*child) || !child || Creation(*child) != state) {
      if (admitted && child && Creation(*child) == state) child->RemoveUserData(&kCreatedPageKey);
      return false;
    }
    state->peek_ = true;
    disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
    return false;
  }
  if (!CanNavigatePeekSource(admission) || !source_lease || !child ||
      !opened.document.AsRenderFrameHostIfValid()) return false;
  child->SetUserData(&kShiftOpeningHoldKey, std::make_unique<ShiftOpeningHold>(
      std::make_unique<HeldShiftOpening>(*source_lease, opened.document, browser, target,
                                         disposition, features, user_gesture)));
  return true;
}
bool PrepareNativeCreatedPage(
    BrowserWindowInterface& browser, content::WebContents* source,
    content::WebContents& created, const GURL& target, WindowOpenDisposition& disposition,
    const blink::mojom::WindowFeatures& features, bool user_gesture) {
  const auto child = created.GetWeakPtr();
  auto opened_data = created.TakeUserData(&kOpenedPageKey);
  auto* opened = static_cast<OpenedPage*>(opened_data.get());
  auto* captured = Creation(created);
  const bool main_frame_opener = captured && captured->source_.get() == source &&
      captured->browser_.get() == &browser && !captured->offered_;
  if (main_frame_opener) captured->peek_ = false;
  NSURL* target_url = [NSURL URLWithString:@(target.spec().c_str())];
  const auto opening = ChooseNativeCreatedPageRoute(
      opened ? opened->modifiers : main_frame_opener ? captured->modifiers_ : 0,
      target_url && IsMeetingURL(target_url), main_frame_opener);
  if (opening == NativeCreatedPageRoute::kShift && opened) {
    if (PrepareShiftCreatedPage(browser, source, created, *opened, target, disposition,
                                features, user_gesture))
      return true;
  } else if (opening == NativeCreatedPageRoute::kAutomatic) {
    PrepareAutomaticCreatedPeek(browser, source, created, target, disposition, user_gesture);
  }
  if (!child) return false;
  auto* state = Creation(*child);
  if (state && state->source_.get() == source && state->browser_.get() == &browser &&
      !state->offered_ && !state->peek_ && !state->split_lease_ && user_gesture &&
      !child->GetUserData(&kCreatedRouteKey) &&
      disposition == WindowOpenDisposition::NEW_SPLIT_VIEW && target.SchemeIsHTTPOrHTTPS()) {
    auto* frame = state->document_.AsRenderFrameHostIfValid();
    auto origin = CaptureSplitOrigin(browser, source, frame, *child);
    if (!child || Creation(*child) != state || state->offered_ || state->split_lease_ ||
        child->GetUserData(&kCreatedRouteKey) || !origin || !origin->Parent(*child)) return false;

    NSString* space = RoutingSourceSpace(*origin);
    PCNativeLinkRoute* route = space ? MatchedRoute(*origin, target) : nil;
    if (!child || Creation(*child) != state || state->offered_ || state->split_lease_ ||
        child->GetUserData(&kCreatedRouteKey) || !origin->Parent(*child)) return false;
    std::unique_ptr<CreatedRoute> route_intent;
    if (space && SameProfileRoute(*origin, route) &&
        [space isEqualToString:RoutingSourceSpace(*origin)] && child &&
        Creation(*child) == state && origin->Parent(*child)) {
      auto* current_frame = origin->document_.AsRenderFrameHostIfValid();
      if (current_frame && origin->source_) {
        auto route_origin = std::make_unique<CreatedPage>(*origin->source_, *current_frame, browser);
        route_intent = std::make_unique<CreatedRoute>(std::move(route_origin), route, space, target, false);
      }
    }
    if (!child || Creation(*child) != state || state->offered_ || state->split_lease_ ||
        child->GetUserData(&kCreatedRouteKey) || !origin->Parent(*child)) return false;
    state->split_source_url_ = origin->split_source_url_;
    state->split_lease_ = origin->split_lease_;
    state->split_observer_ = std::move(origin->split_observer_);
    if (route_intent) child->SetUserData(&kCreatedRouteKey, std::move(route_intent));
    return false;
  }
  if (!state || state->source_.get() != source || state->browser_.get() != &browser ||
      state->offered_ || state->peek_ || child->GetUserData(&kCreatedRouteKey) ||
      !target.SchemeIsHTTPOrHTTPS() ||
      (disposition != WindowOpenDisposition::NEW_FOREGROUND_TAB &&
       disposition != WindowOpenDisposition::NEW_BACKGROUND_TAB) || !state->Parent(*child)) return false;
  auto* frame = state->document_.AsRenderFrameHostIfValid();
  if (!frame) return false;

  auto origin = std::make_unique<CreatedPage>(*source, *frame, browser);
  const GURL source_url = source->GetLastCommittedURL();
  NSString* space = RoutingSourceSpace(*origin);
  PCNativeLinkRoute* route = space ? MatchedRoute(*origin, target) : nil;
  if (!child || Creation(*child) != state || !space || !SameProfileRoute(*origin, route) ||
      !origin->source_ || origin->source_->GetLastCommittedURL() != source_url ||
      !origin->Parent(*child) || ![space isEqualToString:RoutingSourceSpace(*origin)] ||
      !child || Creation(*child) != state) return false;
  child->SetUserData(&kCreatedRouteKey, std::make_unique<CreatedRoute>(
      std::move(origin), route, space, target,
      disposition == WindowOpenDisposition::NEW_BACKGROUND_TAB));
  return false;
}
std::unique_ptr<content::WebContents> HoldNativeCreatedPage(
    content::WebContents& source, std::unique_ptr<content::WebContents> created) {
  auto* hold = created ?
      static_cast<ShiftOpeningHold*>(created->GetUserData(&kShiftOpeningHoldKey)) : nullptr;
  if (!hold || !hold->pending || hold->pending->source() != &source) {
    if (created) created->RemoveUserData(&kShiftOpeningHoldKey);
    return created;
  }
  auto opening = std::move(hold->pending);
  hold->held = opening->GetWeakPtr();
  opening->Hold(std::move(created));
  auto* list = static_cast<HeldShiftOpenings*>(source.GetUserData(&kHeldShiftOpeningsKey));
  if (!list) {
    auto value = std::make_unique<HeldShiftOpenings>();
    list = value.get();
    source.SetUserData(&kHeldShiftOpeningsKey, std::move(value));
  }
  list->openings.push_back(std::move(opening));
  return nullptr;
}
void AddNativeShiftOpeningThrottle(content::NavigationThrottleRegistry& registry) {
  auto& navigation = registry.GetNavigationHandle();
  if (navigation.IsInPrimaryMainFrame() &&
      navigation.GetWebContents()->GetUserData(&kShiftOpeningHoldKey))
    registry.AddThrottle(std::make_unique<ShiftOpeningThrottle>(registry));
}
bool OpenNativePdfLinkInPeek(const ExtensionFunction& function,
                             const std::vector<GURL>& urls) {
  const auto* extension = function.extension();
  auto* frame = function.render_frame_host();
  if (!extension || extension->id() != extension_misc::kPdfExtensionId ||
      urls.size() != 1 || !frame) return false;
  auto* source = content::WebContents::FromRenderFrameHost(frame);
  auto* browser = source ?
      GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(source) : nullptr;
  if (!browser) return false;
  auto params = content::OpenURLParams::CreateRendererInitiated(urls.front(),
      WindowOpenDisposition::NEW_WINDOW, ui::PAGE_TRANSITION_LINK, content::Referrer(),
      frame->GetCurrentInitiatorNavigationState());
  params.user_gesture = function.user_gesture();
  params.initiator_origin = frame->GetLastCommittedOrigin();
  params.initiator_frame_token = frame->GetFrameToken();
  params.initiator_process_id = frame->GetProcess()->GetDeprecatedID();
  params.source_site_instance = frame->GetSiteInstance();
  const auto source_lease = source->GetWeakPtr();
  const auto browser_lease = browser->GetWeakPtr();
  auto peek = PrepareNativePeekNavigation(*browser, source, params);
  auto* delegate = peek && source_lease && browser_lease ?
      BrowserWebContentsDelegate::From(browser_lease.get()) : nullptr;
  if (!delegate) return false;
  peek->DidNavigate(delegate->BrowserWebContentsDelegate::OpenURLFromTab(
      source, peek->params(), {}));
  return true;
}
bool PrepareNativeCreatedSplit(BrowserWindowInterface& browser,
                               content::WebContents* source,
                               content::WebContents* child,
                               WindowOpenDisposition& disposition) {
  if (source && child && disposition == WindowOpenDisposition::NEW_SPLIT_VIEW) {
    const auto source_weak = source->GetWeakPtr();
    const auto child_weak = child->GetWeakPtr();
    const bool native_owner = HasNativeSplitOwner(browser, *source);
    if (!source_weak || !child_weak) return false;
    if (ClassifyNativeSplit(native_owner, false) == NativeSplitDecision::kOrdinary)
      disposition = WindowOpenDisposition::NEW_BACKGROUND_TAB;
  }
  return true;
}

bool HasNativeSplitOwner(BrowserWindowInterface& browser, content::WebContents& source) {
  return GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(&source) == &browser &&
      AppKitBindingForBrowser(&browser) && source.GetBrowserContext() == browser.GetProfile();
}
PCNativePageDisposition NativeCreatedPageDisposition(
    content::WebContents& contents, PCNativePageDisposition ordinary) {
  const auto child = contents.GetWeakPtr();
  AdmitCreatedRoute(contents);
  if (!child) return ordinary;
  auto* route = static_cast<RoutedPage*>(contents.GetUserData(&kRoutedPageKey));
  if (route && route->background && route->browser &&
      GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(&contents) == route->browser.get() &&
      contents.GetBrowserContext() == route->browser->GetProfile())
    return PCNativePageDispositionBackgroundTab;
  auto* state = Creation(contents);
  if (state && state->split_lease_ && !state->offered_) {
    id lease = state->split_lease_;
    PCNativePage* parent = state->Parent(contents);
    PCNativeBrowserWindow* binding = state->browser_ ? AppKitBindingForBrowser(state->browser_.get()) : nil;
    state->offered_ = true;
    if (parent && binding && [binding.client respondsToSelector:
        @selector(nativeBrowser:isSplitLinkLeaseCurrent:forPage:)] &&
        [binding.client nativeBrowser:binding isSplitLinkLeaseCurrent:lease forPage:parent] &&
        child && Creation(*child) == state && state->split_lease_ == lease &&
        state->Parent(*child) == parent)
      return PCNativePageDispositionSplitTab;
    return ordinary;
  }
  if (!state || !state->peek_ || state->offered_) return ordinary;
  state->offered_ = true;
  if (ordinary != PCNativePageDispositionForegroundTab ||
      !state->CanPresent(contents)) {
    if (child && Creation(*child) == state) state->peek_ = false;
    return ordinary;
  }
  return PCNativePageDispositionPeek;
}
void AbandonNativeCreatedPagePresentation(content::WebContents& contents) {
  if (auto* state = Creation(contents)) {
    state->peek_ = false;
    state->split_lease_ = nil;
    state->split_observer_.reset();
  }
}
}
@implementation PCNativePage (CreatedPage)
- (PCNativePage*)creationSourcePage {
  auto* contents = parc::ContentsForNativePage(self);
  auto* state = contents ? parc::Creation(*contents) : nullptr;
  return state ? state->CreationSource(*contents) : nil;
}
- (BOOL)routedLinkCreation {
  auto* contents = parc::ContentsForNativePage(self);
  auto* state = contents ? parc::Creation(*contents) : nullptr;
  return state && state->routed_creation_;
}
- (id)splitLinkLease {
  auto* contents = parc::ContentsForNativePage(self);
  auto* state = contents ? parc::Creation(*contents) : nullptr;
  return state && state->split_lease_ && state->Parent(*contents) ? state->split_lease_ : nil;
}
- (void)finishSplitLinkLease:(id)lease {
  auto* contents = parc::ContentsForNativePage(self);
  auto* state = contents ? parc::Creation(*contents) : nullptr;
  if (state && state->split_lease_ == lease) {
    state->split_lease_ = nil;
    state->split_observer_.reset();
  }
}
- (PCNativePage*)peekParentPage {
  auto* contents = parc::ContentsForNativePage(self);
  auto* state = contents ? parc::Creation(*contents) : nullptr;
  return state && state->peek_ ? state->Parent(*contents) : nil;
}
@end
@implementation PCNativePage (ReopenedPeek)
- (BOOL)openPeekWithURL:(NSURL*)url {
  auto* source = parc::ContentsForNativePage(self);
  const GURL target(base::SysNSStringToUTF8(url.absoluteString ?: @""));
  if (!source || self.closed || !target.is_valid() || !target.SchemeIsHTTPOrHTTPS())
    return NO;
  auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(source);
  auto* frame = source->GetPrimaryMainFrame();
  if (!browser || !frame || source->GetBrowserContext() != browser->GetProfile() ||
      !parc::AppKitBrowserAcceptsNewPages(*browser)) return NO;

  parc::CreatedPage admission(*source, *frame, *browser);
  if (!parc::CanPresentSource(admission)) return NO;
  const auto source_lease = source->GetWeakPtr();
  const auto browser_lease = browser->GetWeakPtr();
  content::OpenURLParams params(target, content::Referrer(),
      WindowOpenDisposition::NEW_FOREGROUND_TAB,
      ui::PAGE_TRANSITION_AUTO_BOOKMARK, false);

  content::WebContents* created = source->OpenURL(params, {});
  if (!created) return NO;
  auto* state = parc::Creation(*created);
  if (state && source_lease && browser_lease && created != source_lease.get() &&
      state->source_.get() == source_lease.get() &&
      state->browser_.get() == browser_lease.get() && !state->offered_) {
    state->peek_ = true;
    state->reopened_ = true;
  }
  return YES;
}
- (BOOL)isReopenedPeek {
  auto* contents = parc::ContentsForNativePage(self);
  auto* state = contents ? parc::Creation(*contents) : nullptr;
  return state && state->reopened_;
}
- (BOOL)openPeekWithURL:(NSURL*)url navigationState:(NSObject*)navigation {
  auto* source = navigation ? parc::ContentsForNativePage(self) : nullptr;
  const GURL target(base::SysNSStringToUTF8(url.absoluteString ?: @""));
  if (!source || self.closed || !target.is_valid() || !target.SchemeIsHTTPOrHTTPS())
    return [self openPeekWithURL:url];
  auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(source);
  auto* frame = source->GetPrimaryMainFrame();
  if (!browser || !frame || source->GetBrowserContext() != browser->GetProfile() ||
      !parc::AppKitBrowserAcceptsNewPages(*browser)) return NO;
  auto admission = std::make_unique<parc::CreatedPage>(*source, *frame, *browser);
  if (!parc::CanPresentSource(*admission)) return NO;
  auto restored = parc::CreateRestoredContents(navigation, *browser->GetProfile(),
                                               true);
  if (!restored) return [self openPeekWithURL:url];

  admission->peek_ = true;
  admission->reopened_ = true;
  auto* created = restored.get();
  created->SetUserData(&parc::kCreatedPageKey, std::move(admission));
  auto* tabs = browser->GetTabStripModel();

  tabs->InsertWebContentsAt(tabs->count(), std::move(restored), AddTabTypes::ADD_ACTIVE);
  return YES;
}
@end

@implementation PCNativeLinkRoute
@synthesize ruleIdentifier = _ruleIdentifier, spaceIdentifier = _spaceIdentifier, profilePath = _profilePath;
- (instancetype)initWithRuleIdentifier:(NSString*)ruleIdentifier
    spaceIdentifier:(NSString*)spaceIdentifier profilePath:(NSString*)profilePath {
  self = [super init];
  if (self) { _ruleIdentifier = [ruleIdentifier copy]; _spaceIdentifier = [spaceIdentifier copy]; _profilePath = [profilePath copy]; }
  return self;
}
@end
@implementation PCNativePage (RoutedLink)
- (BOOL)authenticationFlowUnlocked {
  auto* contents = parc::ContentsForNativePage(self);
  auto* state = contents ? static_cast<parc::URLLockState*>(contents->GetUserData(&parc::kURLLockKey)) : nullptr;
  return state && state->unlocked();
}
- (NSString*)routedSpaceIdentifier {
  auto* contents = parc::ContentsForNativePage(self);
  auto* data = contents ? static_cast<parc::RoutedPage*>(contents->GetUserData(&parc::kRoutedPageKey)) : nullptr;
  if (!data || !data->browser || contents->GetBrowserContext() != data->browser->GetProfile() ||
      [PCNativeBrowserApplication ownerForPage:self] != parc::AppKitBindingForBrowser(data->browser.get())) return nil;
  return data->route.spaceIdentifier;
}
@end
