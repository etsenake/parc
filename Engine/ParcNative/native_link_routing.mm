// Copyright 2026 Parc contributors.
//
// original webContent for ModalV2CreationOptions.webContent. No URL replay.
#include "native_link_routing.h"

#include <memory>

#include "base/memory/weak_ptr.h"
#include "base/functional/bind.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/ui/browser_web_contents_delegate/browser_web_contents_delegate.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents_observer.h"
#include "base/supports_user_data.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/weak_document_ptr.h"
#include "native_appkit_host.h"
#include "native_appkit_page.h"
#include "ui/base/page_transition_types.h"
#include "third_party/blink/public/common/renderer_preferences/renderer_preferences.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "url/gurl.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"

namespace parc {
namespace {
const char kCreatedPageKey = 0;
const char kPendingCurrentLinkKey = 0;
const char kCurrentLinkSequenceKey = 0;
const char kRoutedPageKey = 0;
const char kCreatedRouteKey = 0;
const char kCreatedRouteAttemptKey = 0;
const char kURLLockKey = 0;
class CreatedPage;
CreatedPage* Creation(content::WebContents& contents);
//
// Keep the same Foundation path-component and decimal-character semantics.
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
//
// DomainParser's second output is eTLD+1; Chromium's current PSL (including
//
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

//
// reported URL returns to it or the saved eligible sidebar host. The recovered
// action is WebContentFrameAction.onUpdateURL, not onDidCommitNavigation.
// CEF OnAddressChange supplies the exact source-owned URL update.
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
  // Source identity is independent of Peek admission. A routed ordinary tab
  // may be adopted by another original window, but never another Profile.
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
  // Created by -openPeekWithURL: or -openPeekWithURL:navigationState:.
  bool reopened_ = false;
  bool offered_ = false;
  id __strong split_lease_ = nil;
  std::unique_ptr<SplitSourceObserver> split_observer_;
  GURL split_source_url_;
  const bool routed_creation_ = false;
  base::WeakPtr<BrowserWindowInterface> destination_;
};
// A query can be reentered by an embedder callback. Keep this epoch separate
// from the single-use admission so an older query cannot replace a newer one.
class CurrentLinkSequence final : public base::SupportsUserData::Data {
 public:
  uint64_t value = 0;
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
// This query is used before a new page exists. State is privately owned by the
// synchronous navigation object, so callbacks cannot replace its creation data.
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
// An already-created page retains its original Profile, renderer, opener and
// request. This lease changes only its destination Space at first adoption.
//
// in TabCreationOptions.insertionStrategy; Peek returns before that ordinary
// creation action. No profile switch can be made at this ownership boundary.
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
    // A nested reconciliation must never let this outer decision overwrite
    // a page that the nested callback already offered for ordinary adoption.
    active->interrupted = true;
    return;
  }
  // Take the exact intent before any shell callback. It is never replayed by a
  // later reconciliation, and callback reentry cannot destroy our local lease.
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
  // From here the accepted page follows the destination's ordinary tab lifetime;
  // source navigation after adoption does not move or close it.
  child->SetUserData(&kRoutedPageKey,
      std::make_unique<RoutedPage>(intent->route, *browser, intent->background));
}
// Shared admission/revalidation. Every selector below is a pure existing-
// state query; the renderer may be synchronously waiting for this decision.
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
}  // namespace
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
  //
  //
  // the exact existing OpenURL branch; never sample current NSEvent flags.
  if (disposition != WindowOpenDisposition::CURRENT_TAB && !modified) return std::nullopt;
  if (modified && (!input_modifiers ||
      (*input_modifiers & blink::WebInputEvent::kAltKey))) return std::nullopt;
  auto* source = frame ? content::WebContents::FromRenderFrameHost(frame) : nullptr;
  if (!source || frame != source->GetPrimaryMainFrame() ||
      source->GetBrowserContext() != browser.GetProfile() ||
      !target.SchemeIsHTTPOrHTTPS() || !AppKitBrowserAcceptsNewPages(browser))
    return std::nullopt;
  // This is a synchronous renderer policy query: all called shell selectors
  // must be pure reads of existing state. No UI, storage, new page/profile,
  // nested run loop, or callback into a renderer is permitted here.
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
  // A later query supersedes any unconsumed admission from this document.
  source->RemoveUserData(&kPendingCurrentLinkKey);
  auto creation = std::make_unique<CreatedPage>(*source, *frame, browser);
  PCNativeLinkRoute* route = MatchedRoute(*creation, target);
  if ((!route && (modified || !AllowsCurrentLink(*creation, target))) ||
      !is_current()) return std::nullopt;
  // Keep the admitted original disposition with its source/document token.
  // Original modifier provenance came from Blink, not current NSEvent state.
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
  // Base navigation already applied the original request and all security
  // decisions. The posted reconciliation will consume only this presentation.
  state_->creation->peek_ = state_->peek;
  created->SetUserData(&kCreatedPageKey, std::move(state_->creation));
}
static std::unique_ptr<CreatedPage> CaptureSplitOrigin(
    BrowserWindowInterface& browser, content::WebContents* source,
    content::RenderFrameHost* frame, content::WebContents& child) {
  if (!source || !frame || frame != source->GetPrimaryMainFrame() ||
      source->GetBrowserContext() != browser.GetProfile() ||
      !AppKitBrowserAcceptsNewPages(browser)) return nullptr;
  auto creation = std::make_unique<CreatedPage>(*source, *frame, browser);
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
std::unique_ptr<NativePeekNavigation> PrepareNativePeekNavigation(
    BrowserWindowInterface& browser, content::WebContents* source,
    const content::OpenURLParams& params) {
  if (params.native_route_token) {
    auto* pending = source ? static_cast<PendingCurrentLink*>(
        source->GetUserData(&kPendingCurrentLinkKey)) : nullptr;
    if (!pending || pending->route ||
        pending->disposition != WindowOpenDisposition::CURRENT_TAB ||
        pending->token != *params.native_route_token) return nullptr;
    // Consume before any callbacks. This token can never authorize a second
    // request, and a rejected route cannot become a replacement GET.
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
  // Capture the source of an ordinary new-tab request before entering the
  // upstream navigator. The request and callback remain completely original.
  // This metadata is not a Peek policy or a navigation/security authorization.
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
  //
  //
  // Blink represents Shift-click/Shift-Return on an ordinary link as NEW_WINDOW.
  if (!source || !params.is_renderer_initiated || !params.user_gesture ||
      params.started_from_context_menu || !params.url.SchemeIsHTTPOrHTTPS() ||
      params.disposition != WindowOpenDisposition::NEW_WINDOW ||
      !ui::PageTransitionCoreTypeIs(params.transition, ui::PAGE_TRANSITION_LINK) ||
      !params.initiator_frame_token || !AppKitBrowserAcceptsNewPages(browser))
    return nullptr;
  auto* frame = content::RenderFrameHost::FromFrameToken(
      content::GlobalRenderFrameHostToken(params.initiator_process_id,
                                         *params.initiator_frame_token));
  if (!frame || frame != source->GetPrimaryMainFrame() ||
      source->GetBrowserContext() != browser.GetProfile()) return nullptr;
  auto creation = std::make_unique<CreatedPage>(*source, *frame, browser);
  const auto relevant = NSEventModifierFlagShift | NSEventModifierFlagControl |
      NSEventModifierFlagOption | NSEventModifierFlagCommand;
  if ((creation->modifiers_ & relevant) != NSEventModifierFlagShift ||
      !CanPresentSource(*creation)) return nullptr;
  PCNativeBrowserWindow* binding = AppKitBindingForBrowser(&browser);
  if (!binding ||
      ![binding.client respondsToSelector:@selector(nativeBrowser:allowsPeekWithShift:)] ||
      ![binding.client nativeBrowser:binding allowsPeekWithShift:YES] ||
      !CanPresentSource(*creation)) return nullptr;
  auto state = std::make_unique<NativePeekNavigation::State>(std::move(creation), params);
  // Copy every request field. Changing only the presentation disposition keeps
  // POST/referrer/initiator/blob/security data in Chromium's existing pipeline.
  state->params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
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
    // Multiple consumed background/foreground opens may coexist on this
    // same document. A later click must not cancel a prior admitted tab open.
    // Current-tab conversion retains its stricter superseding-query boundary.
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
    // This is Chromium's original full-request navigator. It deliberately
    // strips source/opener/referrer across Profiles; never transplant contents.
    auto callback = base::BindOnce(
        [](std::shared_ptr<MatchedLinkOperation> operation,
           base::WeakPtr<BrowserWindowInterface> destination,
           content::NavigationHandle& navigation) {
          // Establish Space metadata before the caller's original callback can
          // reenter shell adoption. Forward that callback exactly once.
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
      source_->source_->NotifyNativeDeferredOpenURL(page, source_->document_, params_);
    // Source observers may close or transfer the actual child during delivery.
    if (!page_lease || !destination ||
        destination->GetTabStripModel()->GetIndexOfWebContents(page_lease.get()) == TabStripModel::kNoTab) {
      Finish(nil); return;
    }
    // A newly prepared background window may appear behind the source. An
    // existing destination keeps its selection/visibility. No focus recovery.
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
}  // namespace
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
  PCNativePage* page = ExistingNativePage(source);
  PCNativeBrowserWindow* binding = page ?
      [PCNativeBrowserApplication ownerForPage:page] : nil;
  // FrameCreationInfo is associated with this exact original source. Do not
  // infer top-level intent from a subframe's popup or an unrelated active page.
  if (!binding || !opener || opener != source->GetPrimaryMainFrame() ||
      source->GetBrowserContext() != created->GetBrowserContext()) return;
  auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(source);
  if (!browser || AppKitBindingForBrowser(browser) != binding ||
      !AppKitBrowserAcceptsNewPages(*browser)) return;
  created->SetUserData(&kCreatedPageKey,
      std::make_unique<CreatedPage>(*source, *opener, *browser));
}
static void PrepareCreatedPeek(BrowserWindowInterface& browser,
    content::WebContents* source, content::WebContents& created,
    const GURL& target, WindowOpenDisposition disposition, bool user_gesture) {
  auto* state = Creation(created);
  if (!state || state->source_.get() != source ||
      state->browser_.get() != &browser || state->offered_) return;
  state->peek_ = false;
  // Foreground-only is recovered from the original proposedDisposition
  //
  // Chromium's original route, including its opener and popup protections.
  if (!user_gesture || disposition != WindowOpenDisposition::NEW_FOREGROUND_TAB ||
      !target.SchemeIsHTTPOrHTTPS()) return;
  PCNativePage* parent = state->Parent(created);
  PCNativeBrowserWindow* binding = AppKitBindingForBrowser(&browser);
  if (!parent || !binding || (state->modifiers_ & NSEventModifierFlagCommand)) return;
  NSURL* url = [NSURL URLWithString:@(target.spec().c_str())];
  if (!url || IsMeetingURL(url)) return;
  const auto child = created.GetWeakPtr();
  const auto valid = [&]() {
    return child && Creation(*child) == state && state->Parent(*child) == parent;
  };
  const bool shift = (state->modifiers_ & (NSEventModifierFlagShift |
      NSEventModifierFlagControl | NSEventModifierFlagOption)) == NSEventModifierFlagShift;
  if (![binding.client respondsToSelector:@selector(nativeBrowser:allowsPeekWithShift:)] ||
      ![binding.client nativeBrowser:binding allowsPeekWithShift:shift] || !valid()) return;
  // The native layer owns the document; the shell owns favorite/pinned/Space
  // classification. Never reconstruct it from Chromium's selected tab index.
  if (![binding.client respondsToSelector:@selector(nativeBrowser:shouldOpenNewPageInPeekFrom:targetURL:)] ||
      ![binding.client nativeBrowser:binding shouldOpenNewPageInPeekFrom:parent
                           targetURL:url] || !valid() ||
      !state->CanPresent(*child) || !valid()) return;
  state->peek_ = true;
}
void PrepareNativeCreatedPage(BrowserWindowInterface& browser,
    content::WebContents* source, content::WebContents& created,
    const GURL& target, WindowOpenDisposition disposition, bool user_gesture) {
  const auto child = created.GetWeakPtr();
  // The recovered creation reducer selects Peek before constructing the
  // ordinary tab action with its matched insertion strategy.
  PrepareCreatedPeek(browser, source, created, target, disposition, user_gesture);
  if (!child) return;
  auto* state = Creation(*child);
  if (state && state->source_.get() == source && state->browser_.get() == &browser &&
      !state->offered_ && !state->peek_ && !state->split_lease_ && user_gesture &&
      !child->GetUserData(&kCreatedRouteKey) &&
      disposition == WindowOpenDisposition::NEW_SPLIT_VIEW && target.SchemeIsHTTPOrHTTPS()) {
    auto* frame = state->document_.AsRenderFrameHostIfValid();
    auto origin = CaptureSplitOrigin(browser, source, frame, *child);
    if (!child || Creation(*child) != state || state->offered_ || state->split_lease_ ||
        child->GetUserData(&kCreatedRouteKey) || !origin || !origin->Parent(*child)) return;
    // The created-page reducer matches independently of its split
    // presentation. Retain the existing same-Profile route lease if one
    // exists; absence or a different Profile leaves the original page here.
    NSString* space = RoutingSourceSpace(*origin);
    PCNativeLinkRoute* route = space ? MatchedRoute(*origin, target) : nil;
    if (!child || Creation(*child) != state || state->offered_ || state->split_lease_ ||
        child->GetUserData(&kCreatedRouteKey) || !origin->Parent(*child)) return;
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
        child->GetUserData(&kCreatedRouteKey) || !origin->Parent(*child)) return;
    state->split_source_url_ = origin->split_source_url_;
    state->split_lease_ = origin->split_lease_;
    state->split_observer_ = std::move(origin->split_observer_);
    if (route_intent) child->SetUserData(&kCreatedRouteKey, std::move(route_intent));
    return;
  }
  if (!state || state->source_.get() != source || state->browser_.get() != &browser ||
      state->offered_ || state->peek_ || child->GetUserData(&kCreatedRouteKey) ||
      !target.SchemeIsHTTPOrHTTPS() ||
      (disposition != WindowOpenDisposition::NEW_FOREGROUND_TAB &&
       disposition != WindowOpenDisposition::NEW_BACKGROUND_TAB) || !state->Parent(*child)) return;
  auto* frame = state->document_.AsRenderFrameHostIfValid();
  if (!frame) return;
  // Own the source lease independently of child userdata before callbacks.
  // Unlike Peek, ATC consumes no late OS modifier state at this boundary.
  auto origin = std::make_unique<CreatedPage>(*source, *frame, browser);
  const GURL source_url = source->GetLastCommittedURL();
  NSString* space = RoutingSourceSpace(*origin);
  PCNativeLinkRoute* route = space ? MatchedRoute(*origin, target) : nil;
  if (!child || Creation(*child) != state || !space || !SameProfileRoute(*origin, route) ||
      !origin->source_ || origin->source_->GetLastCommittedURL() != source_url ||
      !origin->Parent(*child) || ![space isEqualToString:RoutingSourceSpace(*origin)] ||
      !child || Creation(*child) != state) return;
  child->SetUserData(&kCreatedRouteKey, std::make_unique<CreatedRoute>(
      std::move(origin), route, space, target,
      disposition == WindowOpenDisposition::NEW_BACKGROUND_TAB));
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
}  // namespace parc
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
  //
  // link policies do not apply. The shell's exact Peek admission still does.
  parc::CreatedPage admission(*source, *frame, *browser);
  if (!parc::CanPresentSource(admission)) return NO;
  const auto source_lease = source->GetWeakPtr();
  const auto browser_lease = browser->GetWeakPtr();
  content::OpenURLParams params(target, content::Referrer(),
      WindowOpenDisposition::NEW_FOREGROUND_TAB,
      ui::PAGE_TRANSITION_AUTO_BOOKMARK, /*is_renderer_initiated=*/false);
  // The browser navigator records this exact parent as the created page's
  // source (PrepareNativePeekNavigation). Marking only this request for Peek
  // before the posted reconciliation offers it keeps the ordinary adoption.
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
                                               /*initially_hidden=*/true);
  if (!restored) return [self openPeekWithURL:url];
  // The restored page carries the same parent provenance a created Peek
  // gets, so the posted reconciliation offers it as this parent's Peek.
  admission->peek_ = true;
  admission->reopened_ = true;
  auto* created = restored.get();
  created->SetUserData(&parc::kCreatedPageKey, std::move(admission));
  auto* tabs = browser->GetTabStripModel();
  // Loads once its Peek attaches it at its size (AppKitBrowserHost Attach).
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
