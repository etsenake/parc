// Copyright 2026 Parc contributors.
#include "fairplay_identity.h"

#import <Foundation/Foundation.h>

#include <map>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/profiles/profile.h"
#include "content/browser/media/parc_fairplay_hooks.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/browser_task_traits.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/document_user_data.h"
#include "content/public/browser/frame_tree_node_id.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/parc_worker_identity.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/service_worker_context.h"
#include "content/public/browser/service_worker_running_info.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/site_instance.h"
#include "content/public/browser/site_isolation_policy.h"
#include "content/public/browser/storage_partition.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "fairplay_identity_policy.h"
#import "native_appkit_bridge.h"
#include "native_appkit_page.h"
#include "native_profile_removal.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "net/base/schemeful_site.h"
#include "third_party/blink/public/common/storage_key/storage_key.h"
#include "third_party/blink/public/common/web_preferences/web_preferences.h"
#include "third_party/blink/public/common/user_agent/user_agent_metadata.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"
#include "url/origin.h"
#include "url/url_constants.h"

namespace parc {
namespace {

using fairplay_identity::SiteLists;

// Empty until InstallFairPlayIdentity; then every page and worker of a Safari
// site uses it.
std::string& SafariUserAgentString() {
  static base::NoDestructor<std::string> user_agent;
  return *user_agent;
}

// A browsing context: the original Profile's path and whether it is the
// private context of that Profile.
using ContextKey = std::pair<std::string, bool>;

std::map<ContextKey, SiteLists>& AllLists() {
  static base::NoDestructor<std::map<ContextKey, SiteLists>> lists;
  return *lists;
}

ContextKey KeyForContext(content::BrowserContext* context) {
  Profile* profile = Profile::FromBrowserContext(context);
  return {profile->GetOriginalProfile()->GetPath().value(),
          profile->IsOffTheRecord()};
}

const SiteLists& ListsForContext(content::BrowserContext* context) {
  static const base::NoDestructor<SiteLists> empty;
  auto found = AllLists().find(KeyForContext(context));
  return found == AllLists().end() ? *empty : found->second;
}

// The registrable domain of an HTTP(S) URL, private registries included, so
// "user.github.io" is its own site; the host for hosts without one
// (localhost, IP addresses). Empty for every other URL, including about:,
// data: and other opaque origins, which load into their parent's process.
std::string SiteForURL(const GURL& url) {
  if (!url.is_valid()) {
    return std::string();
  }
  const url::Origin origin = url::Origin::Create(url);
  if (origin.opaque() || (origin.scheme() != url::kHttpsScheme &&
                          origin.scheme() != url::kHttpScheme)) {
    return std::string();
  }
  std::string domain = net::registry_controlled_domains::GetDomainAndRegistry(
      origin, net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES);
  // Lowercased like the shell's lists: a canonical host is lowercase except
  // for the hex digits of escapes such as %2A.
  return base::ToLowerASCII(domain.empty() ? origin.host() : domain);
}

// Present on a document that was committed with Safari's identity; a frame
// presents what its local root's record says. Chromium deletes it when the
// frame commits another document, so it always describes the document a
// frame shows now, including one restored from the back/forward cache or
// activated from a prerender.
class SafariIdentityDocument final
    : public content::DocumentUserData<SafariIdentityDocument> {
 public:
  ~SafariIdentityDocument() override = default;

 private:
  explicit SafariIdentityDocument(content::RenderFrameHost* frame)
      : DocumentUserData<SafariIdentityDocument>(frame) {}
  friend DocumentUserData<SafariIdentityDocument>;
  DOCUMENT_USER_DATA_KEY_DECL();
};

DOCUMENT_USER_DATA_KEY_IMPL(SafariIdentityDocument);

bool MainDocumentPresentsSafari(content::RenderFrameHost* main_frame) {
  return main_frame &&
         SafariIdentityDocument::GetForCurrentDocument(main_frame) != nullptr;
}

// Whether a frame starts its own part of the page in the renderer: the main
// frame, or a frame whose parent is in another SiteInstanceGroup (another
// process and frame tree). A data: subframe has its own SiteInstance in its
// creator's group, so it isn't one.
bool IsLocalRoot(content::RenderFrameHost* frame) {
  content::RenderFrameHost* parent = frame->GetParent();
  return !parent || frame->GetSiteInstance()->GetSiteInstanceGroupId() !=
                        parent->GetSiteInstance()->GetSiteInstanceGroupId();
}

content::RenderFrameHost* LocalRootOf(content::RenderFrameHost* frame) {
  while (!IsLocalRoot(frame)) {
    frame = frame->GetParent();
  }
  return frame;
}

// The identity a committed frame presents now: Parc's renderer applies the
// override to a frame from its local root's document
// (RenderFrameImpl::ShouldUseUserAgentOverride as native-host-route.patch
// changes it).
bool FramePresentsSafari(content::RenderFrameHost* frame) {
  return SafariIdentityDocument::GetForCurrentDocument(LocalRootOf(frame)) !=
         nullptr;
}

// Whether a committed frame should present its main document's identity
// under NavigationPresentsSafari: it is the main document, a frame on its
// site, or a frame without a site whose nearest ancestor with one is on it.
// Committed addresses are compared as DidStartNavigation compares the
// starting ones.
bool FollowsMainDocument(content::RenderFrameHost* frame) {
  if (!content::SiteIsolationPolicy::UseDedicatedProcessesForAllSites()) {
    return true;
  }
  content::RenderFrameHost* main_frame = frame->GetMainFrame();
  for (; frame && frame != main_frame; frame = frame->GetParent()) {
    if (!SiteForURL(frame->GetLastCommittedURL()).empty()) {
      return net::SchemefulSite(frame->GetLastCommittedURL()) ==
             net::SchemefulSite(main_frame->GetLastCommittedOrigin());
    }
  }
  return true;
}

class FairPlayIdentityHelper;

std::set<FairPlayIdentityHelper*>& Helpers() {
  static base::NoDestructor<std::set<FairPlayIdentityHelper*>> helpers;
  return *helpers;
}

void ReloadContents(base::WeakPtr<content::WebContents> contents) {
  if (contents && !contents->IsBeingDestroyed()) {
    contents->GetController().Reload(content::ReloadType::NORMAL,
                                     /*check_for_repost=*/true);
  }
}

// Loads the page's address again as a GET in place of its entry: for a page
// holding a Widevine request whose entry can't simply reload (a POST result,
// or the initial entry after document.open).
void LoadAgain(content::WebContents* contents, const GURL& url) {
  content::NavigationController::LoadURLParams params(url);
  params.should_replace_current_entry = true;
  params.transition_type = ui::PAGE_TRANSITION_RELOAD;
  contents->GetController().LoadURLWithParams(params);
}

class FairPlayIdentityHelper final
    : public content::WebContentsObserver,
      public content::WebContentsUserData<FairPlayIdentityHelper> {
 public:
  ~FairPlayIdentityHelper() override {
    for (id observer : power_observers_)
      [NSNotificationCenter.defaultCenter removeObserver:observer];
    Helpers().erase(this);
  }

  // The lists changed: reload the page when its main document no longer
  // presents the identity its site now has. A page whose main frame is
  // navigating is left to that navigation, which checks again when it
  // commits; a discarded page reloads with the new identity when it is
  // shown. A POST result is never resubmitted, unless `held`: the page holds
  // a Widevine request and can't play until it loads again.
  void ReconcileWithLists(bool held = false) {
    content::WebContents* contents = web_contents();
    if (!contents || contents->IsBeingDestroyed() || contents->WasDiscarded()) {
      return;
    }
    reconcile_held_ = reconcile_held_ || held;
    content::NavigationEntry* pending =
        contents->GetController().GetPendingEntry();
    // This helper's own reload is waiting on a beforeunload dialog; it applies
    // the identity when it starts, and a "Stay" answer is the user's choice.
    if (primary_navigations_.empty() && pending &&
        pending->GetUniqueID() == own_reload_entry_id_) {
      return;
    }
    // Checked again when that navigation ends without committing; one that
    // commits is checked at its commit. A pending entry with no navigation
    // yet is waiting on a beforeunload dialog, which may be cancelled, and
    // while the browser quits or closes every window the pages may stay
    // after all, so in those cases look again shortly.
    const bool ready = NativeProfileRemovalApplicationReady();
    if (!primary_navigations_.empty() || pending || !ready) {
      reconcile_pending_ = true;
      if ((primary_navigations_.empty() || !ready) && !retry_scheduled_) {
        retry_scheduled_ = true;
        content::GetUIThreadTaskRunner({})->PostDelayedTask(
            FROM_HERE,
            base::BindOnce(&FairPlayIdentityHelper::Retry,
                           contents->GetWeakPtr()),
            base::Milliseconds(500));
      }
      return;
    }
    const bool was_held = reconcile_held_;
    reconcile_pending_ = false;
    reconcile_held_ = false;
    content::NavigationEntry* entry =
        contents->GetController().GetLastCommittedEntry();
    content::RenderFrameHost* main_frame = contents->GetPrimaryMainFrame();
    const std::string site = SiteForURL(main_frame->GetLastCommittedURL());
    if (!entry || site.empty()) {
      return;
    }
    const bool wanted = fairplay_identity::PresentsSafari(
        ListsForContext(contents->GetBrowserContext()), site);
    if (wanted == MainDocumentPresentsSafari(main_frame)) {
      return;
    }
    // The initial entry of a page a script wrote (document.open) has no
    // address of its own to load again.
    if (entry->IsInitialEntry()) {
      return;
    }
    if (entry->GetHasPostData()) {
      if (was_held) {
        LoadAgain(contents, main_frame->GetLastCommittedURL());
        RememberOwnReload(contents);
      }
      return;
    }
    ReloadContents(contents->GetWeakPtr());
    RememberOwnReload(contents);
  }

 private:
  explicit FairPlayIdentityHelper(content::WebContents* contents)
      : content::WebContentsObserver(contents),
        content::WebContentsUserData<FairPlayIdentityHelper>(*contents) {
    Helpers().insert(this);
    auto weak_contents = contents->GetWeakPtr();
    for (NSNotificationName name in @[
             NSProcessInfoPowerStateDidChangeNotification,
             NSProcessInfoThermalStateDidChangeNotification]) {
      id observer = [NSNotificationCenter.defaultCenter
          addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
          usingBlock:^(NSNotification*) {
            if (weak_contents)
              UpdateMediaPowerState(weak_contents.get());
          }];
      power_observers_.push_back(observer);
    }
    UpdateMediaPowerState(contents);
    // Chromium uses the override only for navigations that ask for it, so
    // setting it changes nothing until one does.
    if (!SafariUserAgentString().empty()) {
      contents->SetUserAgentOverride(
          blink::UserAgentOverride::UserAgentOnly(SafariUserAgentString()),
          /*override_in_new_tabs=*/false);
    }
  }
  static void UpdateMediaPowerState(content::WebContents* contents) {
    if (contents->IsBeingDestroyed())
      return;
    // WebKit's LowPowerModeNotifier and ThermalMitigationNotifier.
    NSProcessInfo* info = NSProcessInfo.processInfo;
    bool restricted = info.lowPowerModeEnabled ||
        info.thermalState >= NSProcessInfoThermalStateSerious;
    auto prefs = contents->GetOrCreateWebPreferences();
    if (prefs.parc_media_power_restricted == restricted)
      return;
    prefs.parc_media_power_restricted = restricted;
    contents->SetWebPreferences(prefs);
  }
  std::vector<id> power_observers_;
  friend content::WebContentsUserData<FairPlayIdentityHelper>;
  WEB_CONTENTS_USER_DATA_KEY_DECL();

  // NavigationHandle::SetIsOverridingUserAgent is valid only here. It sets
  // the request's User-Agent and client hints and the identity the new
  // document commits with. A same-document navigation keeps its document; a
  // prerender activation keeps the identity the prerender chose.
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsSameDocument()) {
      return;
    }
    if (navigation->IsInPrimaryMainFrame()) {
      primary_navigations_.insert(navigation->GetNavigationId());
    }
    if (SafariUserAgentString().empty() ||
        navigation->IsPrerenderedPageActivation()) {
      return;
    }
    // A fenced frame is a subframe of the page that holds it, so a learned
    // site inside another site's page stays Chrome there too.
    fairplay_identity::FrameNavigation facts;
    facts.main_frame = navigation->IsInOutermostMainFrame();
    facts.site = SiteForURL(navigation->GetURL());
    if (!facts.main_frame) {
      content::RenderFrameHost* parent =
          navigation->GetParentFrameOrOuterDocument();
      if (!parent) {
        return;
      }
      content::RenderFrameHost* main_frame = parent->GetOutermostMainFrame();
      facts.same_site_as_main =
          !content::SiteIsolationPolicy::UseDedicatedProcessesForAllSites() ||
          net::SchemefulSite(navigation->GetURL()) ==
              net::SchemefulSite(main_frame->GetLastCommittedOrigin());
      facts.main_frame_safari = MainDocumentPresentsSafari(main_frame);
      facts.parent_safari = FramePresentsSafari(parent);
    }
    const bool safari = fairplay_identity::NavigationPresentsSafari(
        ListsForContext(web_contents()->GetBrowserContext()), facts);
    navigation->SetIsOverridingUserAgent(safari);
    decisions_[navigation->GetNavigationId()] = safari;
  }

  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    const int64_t id = navigation->GetNavigationId();
    primary_navigations_.erase(id);
    std::optional<bool> decided;
    if (auto found = decisions_.find(id); found != decisions_.end()) {
      decided = found->second;
      decisions_.erase(found);
    }
    if (!navigation->HasCommitted() || navigation->IsSameDocument()) {
      // A list change waited for this navigation, which kept the document:
      // it never committed (stopped, replaced, a download or a 204) or it
      // stayed in the same document.
      if (reconcile_pending_ && primary_navigations_.empty() &&
          navigation->IsInPrimaryMainFrame()) {
        content::GetUIThreadTaskRunner({})->PostTask(
            FROM_HERE, base::BindOnce(&FairPlayIdentityHelper::Reconcile,
                                      web_contents()->GetWeakPtr()));
      }
      return;
    }
    // GetRenderFrameHost() is valid only once a response arrived, so never
    // before HasCommitted().
    content::RenderFrameHost* frame = navigation->GetRenderFrameHost();
    if (!frame) {
      return;
    }
    if (navigation->IsInPrimaryMainFrame()) {
      reconcile_pending_ = false;
      reconcile_held_ = false;
      own_reload_entry_id_ = 0;
      identity_reloads_.clear();
    }
    // Recorded on every document committed with Safari's identity; a frame
    // reads the record of its local root.
    if (decided.value_or(false)) {
      SafariIdentityDocument::CreateForCurrentDocument(frame);
    }
    if (!navigation->IsInMainFrame()) {
      KeepEntryOnMainDocument(frame);
      // A POST is never sent again, as for the main frame.
      if (!navigation->IsErrorPage() && !navigation->IsPost()) {
        CheckSubframe(frame);
      }
      return;
    }
    if (navigation->IsErrorPage() || !navigation->IsInPrimaryMainFrame()) {
      return;
    }
    content::NavigationEntry* entry =
        web_contents()->GetController().GetLastCommittedEntry();
    const bool wanted = fairplay_identity::PresentsSafari(
        ListsForContext(web_contents()->GetBrowserContext()),
        SiteForURL(navigation->GetURL()));
    bool matches;
    if (decided) {
      // Chosen for the URL the navigation started with. A redirect to a site
      // of the other identity, or a list change while it loaded, commits the
      // wrong one.
      matches = *decided == wanted;
    } else if (navigation->IsPrerenderedPageActivation()) {
      // The prerender's own navigation chose the document's identity.
      const bool safari = MainDocumentPresentsSafari(frame);
      if (entry && entry->GetIsOverridingUserAgent() != safari) {
        entry->SetIsOverridingUserAgent(safari);
      }
      matches = safari == wanted;
    } else {
      // Started before this helper existed, so its request carried Chrome's
      // user agent. The renderer now has Safari's override and applies it if
      // the entry asks for it, so only a Chrome page with a Chrome entry is
      // consistent.
      matches = !wanted && !(entry && entry->GetIsOverridingUserAgent());
    }
    // Reload once with the right identity; never repeat a POST, and never
    // reload the same entry twice in a row.
    if (matches || navigation->IsPost() || !entry ||
        entry->GetUniqueID() == reloaded_entry_id_) {
      return;
    }
    reloaded_entry_id_ = entry->GetUniqueID();
    content::GetUIThreadTaskRunner({})->PostTask(
        FROM_HERE,
        base::BindOnce(&ReloadContents, web_contents()->GetWeakPtr()));
  }

  // NavigationControllerImpl::RendererDidNavigate copies a committing
  // subframe's identity into the page's entry. Keep the entry on the main
  // document's identity, which is what restoring or prerendering it uses.
  void KeepEntryOnMainDocument(content::RenderFrameHost* frame) {
    content::RenderFrameHost* main_frame = web_contents()->GetPrimaryMainFrame();
    if (frame->GetMainFrame() != main_frame) {
      return;
    }
    content::NavigationEntry* entry =
        web_contents()->GetController().GetLastCommittedEntry();
    const bool safari = MainDocumentPresentsSafari(main_frame);
    if (entry && entry->GetIsOverridingUserAgent() != safari) {
      entry->SetIsOverridingUserAgent(safari);
    }
  }

  // A committed subframe of the page whose scripts got another identity than
  // its site has under NavigationPresentsSafari, because the identity was
  // chosen for the URL it started with: a redirect took it off the main
  // document's site into a process of its own with the main document's
  // Safari identity, or onto the main document's site inside a cross-site
  // frame with Chrome's. A frame without a site follows its parent as it was
  // chosen to. A frame whose scripts already fit keeps its document, even if
  // its own request carried the other identity.
  void CheckSubframe(content::RenderFrameHost* frame) {
    content::RenderFrameHost* main_frame = web_contents()->GetPrimaryMainFrame();
    if (!frame->IsActive() || frame->GetMainFrame() != main_frame ||
        SiteForURL(frame->GetLastCommittedURL()).empty()) {
      return;
    }
    const bool wanted =
        FollowsMainDocument(frame) && MainDocumentPresentsSafari(main_frame);
    if (wanted != FramePresentsSafari(frame)) {
      ReloadFrameForIdentity(frame, wanted);
    }
  }

  // Reloads one frame, not the page: its reload starts from the address it
  // ended at, so the identity chosen then fits. At most once per frame and
  // identity until the main document changes, so a frame a reload can't fix
  // (one that redirects again) reloads at most twice and never loops.
  void ReloadFrameForIdentity(content::RenderFrameHost* frame, bool wanted) {
    if (!identity_reloads_.emplace(frame->GetFrameTreeNodeId(), wanted)
             .second) {
      return;
    }
    content::GetUIThreadTaskRunner({})->PostTask(
        FROM_HERE, base::BindOnce(&ReloadFrame, frame->GetGlobalId()));
  }

  static void ReloadFrame(content::GlobalRenderFrameHostId id) {
    content::RenderFrameHost* frame = content::RenderFrameHost::FromID(id);
    if (frame && frame->IsActive()) {
      frame->Reload();
    }
  }

  void RememberOwnReload(content::WebContents* contents) {
    content::NavigationEntry* pending =
        contents->GetController().GetPendingEntry();
    own_reload_entry_id_ = pending ? pending->GetUniqueID() : 0;
  }

  static void Reconcile(base::WeakPtr<content::WebContents> contents) {
    if (!contents) {
      return;
    }
    if (auto* helper = FromWebContents(contents.get())) {
      helper->ReconcileWithLists();
    }
  }

  static void Retry(base::WeakPtr<content::WebContents> contents) {
    if (!contents) {
      return;
    }
    if (auto* helper = FromWebContents(contents.get())) {
      helper->retry_scheduled_ = false;
      if (helper->reconcile_pending_) {
        helper->ReconcileWithLists();
      }
    }
  }

  std::map<int64_t, bool> decisions_;
  std::set<int64_t> primary_navigations_;
  // Frames reloaded for their identity in this main document, each with the
  // identity it was reloaded for.
  std::set<std::pair<content::FrameTreeNodeId, bool>> identity_reloads_;
  bool reconcile_pending_ = false;
  bool reconcile_held_ = false;
  bool retry_scheduled_ = false;
  int own_reload_entry_id_ = 0;
  int reloaded_entry_id_ = 0;
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(FairPlayIdentityHelper);

// A service or shared worker of a Safari site, outside any other site's
// storage partition, starts, and requests its scripts, with Safari's user
// agent and no client-hint metadata, as its documents do. A dedicated
// worker's script is requested with the identity of the document that
// created it, which the worker takes over in the renderer.
void ApplyWorkerIdentity(content::BrowserContext* context,
                         const GURL& script_url,
                         const GURL& top_level_site,
                         content::RenderFrameHost* creator_frame,
                         std::string* user_agent,
                         blink::UserAgentMetadata* metadata) {
  if (SafariUserAgentString().empty()) {
    return;
  }
  if (creator_frame) {
    if (!FramePresentsSafari(creator_frame)) {
      return;
    }
  } else {
    const std::string site = SiteForURL(script_url);
    if (site.empty() || site != SiteForURL(top_level_site) ||
        !fairplay_identity::PresentsSafari(ListsForContext(context), site)) {
      return;
    }
  }
  *user_agent = SafariUserAgentString();
  *metadata = blink::UserAgentMetadata();
}

std::set<std::string> SitesFromArray(NSArray<NSString*>* array) {
  std::set<std::string> sites;
  for (id value in array) {
    if (![value isKindOfClass:NSString.class]) {
      continue;
    }
    std::string site = base::ToLowerASCII(base::SysNSStringToUTF8(value));
    if (!site.empty() && site.size() <= 253) {
      sites.insert(std::move(site));
    }
  }
  return sites;
}

// A running service worker keeps the user agent it started with, so one of a
// site whose identity changed is stopped; it starts again with the new one
// when its pages reload.
void StopServiceWorkersForSites(content::BrowserContext* context,
                                const std::set<std::string>& sites) {
  if (!context || sites.empty()) {
    return;
  }
  content::ServiceWorkerContext* workers =
      context->GetDefaultStoragePartition()->GetServiceWorkerContext();
  if (!workers) {
    return;
  }
  std::vector<blink::StorageKey> keys;
  for (const auto& [version_id, info] :
       workers->GetRunningServiceWorkerInfos()) {
    if (sites.count(SiteForURL(info.scope))) {
      keys.push_back(info.key);
    }
  }
  for (const blink::StorageKey& key : keys) {
    workers->StopAllServiceWorkersForStorageKey(key);
  }
}

// The sites whose identity differs between two lists.
std::set<std::string> ChangedSites(const SiteLists& before,
                                   const SiteLists& after) {
  std::set<std::string> all;
  for (const auto* list :
       {&before.safari, &before.chrome, &after.safari, &after.chrome}) {
    all.insert(list->begin(), list->end());
  }
  std::set<std::string> changed;
  for (const std::string& site : all) {
    if (fairplay_identity::PresentsSafari(before, site) !=
        fairplay_identity::PresentsSafari(after, site)) {
      changed.insert(site);
    }
  }
  return changed;
}

// Brings a context's workers and open pages to the identity their sites now
// have. `held` is the page holding a Widevine request, if any.
void ReconcileContext(const ContextKey& key,
                      const std::set<std::string>& changed_sites,
                      base::WeakPtr<content::WebContents> held) {
  std::vector<base::WeakPtr<content::WebContents>> pages;
  content::BrowserContext* context = nullptr;
  for (FairPlayIdentityHelper* helper : Helpers()) {
    content::WebContents* contents = helper->web_contents();
    if (contents && KeyForContext(contents->GetBrowserContext()) == key) {
      pages.push_back(contents->GetWeakPtr());
      context = contents->GetBrowserContext();
    }
  }
  StopServiceWorkersForSites(context, changed_sites);
  for (const auto& contents : pages) {
    if (!contents) {
      continue;
    }
    if (auto* helper = FairPlayIdentityHelper::FromWebContents(contents.get())) {
      helper->ReconcileWithLists(held && held.get() == contents.get());
    }
  }
}


void FinishLearning(ContextKey key,
                    std::string site,
                    bool newly_learned,
                    base::WeakPtr<content::WebContents> requester) {
  NSString* learned = base::SysUTF8ToNSString(site);
  // The page's observer hears it (PCBrowserView forwards it to the page's
  // owner), and so does the application, which records it for the context
  // even when no page forwards it: a closed tab, a page not yet adopted.
  if (requester && !requester->IsBeingDestroyed()) {
    if (PCNativePage* page = ExistingNativePage(requester.get())) {
      id<PCNativePageObserver> observer = page.observer;
      if ([observer respondsToSelector:@selector(nativePage:
                                           didLearnSafariIdentityForSite:)]) {
        [observer nativePage:page didLearnSafariIdentityForSite:learned];
      }
    }
  }
  const bool requester_alive = requester && !requester->IsBeingDestroyed();
  // A private session that ended meanwhile took its choices with it.
  if (!key.second || requester_alive) {
    NotifyNativeApplicationLearnedSafariIdentity(
        learned, base::SysUTF8ToNSString(key.first), key.second);
  }
  // A newly learned site's workers restart, and every open page of the site
  // in that context, the requester included, reloads with Safari's identity.
  // A page waits while the browser quits or closes every window, in case it
  // stays.
  std::set<std::string> changed;
  if (newly_learned) {
    changed.insert(site);
  }
  ReconcileContext(key, changed, requester);
}

// fairplay-media's hook (content/browser/media/parc_fairplay_hooks.h), on the
// UI thread, for every Widevine CDM a frame asks for. Returning true holds
// the CDM, so no Widevine license request leaves; Netflix signs a user out
// after a failed one. Never ends the document itself: learning and reloads
// run after the hook returns.
bool OnWidevineCdmRequest(content::RenderFrameHost* frame,
                          const std::string& /*key_system*/) {
  if (!frame || SafariUserAgentString().empty()) {
    return false;
  }
  content::WebContents* contents =
      content::WebContents::FromRenderFrameHost(frame);
  if (!contents || contents->IsBeingDestroyed() ||
      !FairPlayIdentityHelper::FromWebContents(contents)) {
    return false;
  }
  content::RenderFrameHost* main_frame = frame->GetMainFrame();
  if (main_frame != contents->GetPrimaryMainFrame()) {
    return false;
  }
  fairplay_identity::WidevineRequestFrame facts;
  facts.site = SiteForURL(main_frame->GetLastCommittedURL());
  facts.follows_main_frame = FollowsMainDocument(frame);
  facts.page_safari = MainDocumentPresentsSafari(main_frame);
  content::BrowserContext* context = contents->GetBrowserContext();
  switch (fairplay_identity::DecideWidevineRequest(ListsForContext(context),
                                                   facts)) {
    case fairplay_identity::WidevineRequest::kAllow:
      return false;
    case fairplay_identity::WidevineRequest::kHold:
      return true;
    case fairplay_identity::WidevineRequest::kHoldAndLearn:
      break;
  }
  // Learned now, so the reload that follows presents Safari's identity even
  // before the shell records it; the shell's next lists include it.
  const ContextKey key = KeyForContext(context);
  const bool newly_learned = AllLists()[key].safari.insert(facts.site).second;
  content::GetUIThreadTaskRunner({})->PostTask(
      FROM_HERE, base::BindOnce(&FinishLearning, key, facts.site,
                                newly_learned, contents->GetWeakPtr()));
  return true;
}

}  // namespace

void InstallFairPlayIdentity() {
  CHECK(NSThread.isMainThread);
  // Safari's user agent carries Safari's own version. Since macOS 26 that is
  // macOS's version, the fallback when Safari's bundle cannot be read.
  NSBundle* safari = [NSBundle bundleWithPath:@"/Applications/Safari.app"];
  id version = [safari objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
  std::string value = [version isKindOfClass:NSString.class]
                          ? base::SysNSStringToUTF8(version)
                          : std::string();
  if (!fairplay_identity::IsSafariVersion(value)) {
    const NSOperatingSystemVersion os =
        NSProcessInfo.processInfo.operatingSystemVersion;
    value = std::to_string(os.majorVersion) + "." +
            std::to_string(os.minorVersion);
    if (os.patchVersion) {
      value += "." + std::to_string(os.patchVersion);
    }
  }
  SafariUserAgentString() = fairplay_identity::SafariUserAgent(value);
  content::SetParcWorkerIdentityHook(&ApplyWorkerIdentity);
  parc::fairplay::SetWidevineCdmRequestObserver(
      base::BindRepeating(&OnWidevineCdmRequest));
  parc::fairplay::SetSafariIdentityQuery(
      base::BindRepeating(&FramePresentsSafari));
}

void AttachFairPlayIdentity(content::WebContents& contents) {
  CHECK(NSThread.isMainThread);
  FairPlayIdentityHelper::CreateForWebContents(&contents);
}

}  // namespace parc

@implementation PCNativeBrowserApplication (FairPlayIdentity)
+ (void)setFairPlayIdentitySafariSites:(NSArray<NSString*>*)safariSites
                           chromeSites:(NSArray<NSString*>*)chromeSites
                           profilePath:(NSString*)profilePath
                          offTheRecord:(BOOL)offTheRecord {
  CHECK(NSThread.isMainThread);
  if (![profilePath isKindOfClass:NSString.class] || profilePath.length == 0) {
    return;
  }
  const parc::ContextKey key{base::SysNSStringToUTF8(profilePath),
                             offTheRecord == YES};
  parc::fairplay_identity::SiteLists lists;
  lists.safari = parc::SitesFromArray(safariSites);
  lists.chrome = parc::SitesFromArray(chromeSites);
  auto& all = parc::AllLists();
  auto found = all.find(key);
  if (found != all.end() && found->second.safari == lists.safari &&
      found->second.chrome == lists.chrome) {
    return;
  }
  const parc::fairplay_identity::SiteLists before =
      found != all.end() ? found->second
                         : parc::fairplay_identity::SiteLists();
  std::set<std::string> changed = parc::ChangedSites(before, lists);
  all[key] = std::move(lists);
  // No page exists before the engine is ready, and pages are closing while it
  // quits. Otherwise reload after the caller returns, so no navigation
  // callback reaches the shell while it is still updating its own state.
  if (!parc::NativeProfileRemovalApplicationReady()) {
    return;
  }
  content::GetUIThreadTaskRunner({})->PostTask(
      FROM_HERE,
      base::BindOnce(&parc::ReconcileContext, key, std::move(changed),
                     base::WeakPtr<content::WebContents>()));
}
@end

@implementation PCNativePage (FairPlayIdentity)
- (NSString*)fairPlayIdentitySite {
  content::WebContents* contents = parc::ContentsForNativePage(self);
  if (!contents || contents->IsBeingDestroyed()) {
    return nil;
  }
  const std::string site =
      parc::SiteForURL(contents->GetPrimaryMainFrame()->GetLastCommittedURL());
  return site.empty() ? nil : base::SysUTF8ToNSString(site);
}
- (BOOL)usesSafariIdentity {
  content::WebContents* contents = parc::ContentsForNativePage(self);
  return contents && !contents->IsBeingDestroyed() &&
         parc::MainDocumentPresentsSafari(contents->GetPrimaryMainFrame());
}
- (BOOL)fairPlayIdentityOffTheRecord {
  content::WebContents* contents = parc::ContentsForNativePage(self);
  return contents && contents->GetBrowserContext()->IsOffTheRecord();
}
@end
