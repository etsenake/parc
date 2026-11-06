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
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/browser_task_traits.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/document_user_data.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/parc_worker_identity.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/site_instance.h"
#include "content/public/browser/site_isolation_policy.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "fairplay_identity_policy.h"
#import "native_appkit_bridge.h"
#include "native_appkit_page.h"
#include "native_profile_removal.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "net/base/schemeful_site.h"
#include "services/network/public/cpp/web_sandbox_flags.h"
#include "services/network/public/mojom/web_sandbox_flags.mojom-shared.h"
#include "third_party/blink/public/common/user_agent/user_agent_metadata.h"
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
  return domain.empty() ? origin.host() : domain;
}

// Present on a main document that was committed with Safari's identity.
// Chromium deletes it when the frame commits another document, so it always
// describes the document a frame shows now, including one restored from the
// back/forward cache or activated from a prerender.
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

// Whether a frame shares the main document's process and frame tree, which
// is what Chromium's renderer goes by when it applies the override. Frames in
// one SiteInstanceGroup do; a data: subframe has its own SiteInstance in its
// creator's group.
bool SharesMainDocumentProcess(content::RenderFrameHost* frame) {
  content::RenderFrameHost* main_frame = frame->GetMainFrame();
  return frame == main_frame ||
         frame->GetSiteInstance()->GetSiteInstanceGroupId() ==
             main_frame->GetSiteInstance()->GetSiteInstanceGroupId();
}

// The identity a committed frame presents now.
bool FramePresentsSafari(content::RenderFrameHost* frame) {
  return MainDocumentPresentsSafari(frame->GetMainFrame()) &&
         SharesMainDocumentProcess(frame);
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

class FairPlayIdentityHelper final
    : public content::WebContentsObserver,
      public content::WebContentsUserData<FairPlayIdentityHelper> {
 public:
  ~FairPlayIdentityHelper() override { Helpers().erase(this); }

  // The lists changed: reload the page when its main document no longer
  // presents the identity its site now has. A page whose main frame is
  // navigating is left to that navigation, which checks again when it
  // commits; a POST result is never resubmitted; a discarded page reloads
  // with the new identity when it is shown.
  void ReconcileWithLists() {
    content::WebContents* contents = web_contents();
    if (!contents || contents->IsBeingDestroyed() || contents->WasDiscarded()) {
      return;
    }
    // Checked again when that navigation ends without committing; one that
    // commits is checked at its commit.
    if (!primary_navigations_.empty() ||
        contents->GetController().GetPendingEntry()) {
      reconcile_pending_ = true;
      return;
    }
    reconcile_pending_ = false;
    content::NavigationEntry* entry =
        contents->GetController().GetLastCommittedEntry();
    if (!entry || entry->IsInitialEntry() || entry->GetHasPostData()) {
      return;
    }
    content::RenderFrameHost* main_frame = contents->GetPrimaryMainFrame();
    const std::string site = SiteForURL(main_frame->GetLastCommittedURL());
    if (site.empty()) {
      return;
    }
    const bool wanted = fairplay_identity::PresentsSafari(
        ListsForContext(contents->GetBrowserContext()), site);
    if (wanted != MainDocumentPresentsSafari(main_frame)) {
      ReloadContents(contents->GetWeakPtr());
    }
  }

 private:
  explicit FairPlayIdentityHelper(content::WebContents* contents)
      : content::WebContentsObserver(contents),
        content::WebContentsUserData<FairPlayIdentityHelper>(*contents) {
    Helpers().insert(this);
    // Chromium uses the override only for navigations that ask for it, so
    // setting it changes nothing until one does.
    if (!SafariUserAgentString().empty()) {
      contents->SetUserAgentOverride(
          blink::UserAgentOverride::UserAgentOnly(SafariUserAgentString()),
          /*override_in_new_tabs=*/false);
    }
  }
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
    fairplay_identity::FrameNavigation facts;
    facts.main_frame = navigation->IsInMainFrame();
    facts.site = SiteForURL(navigation->GetURL());
    if (!facts.main_frame) {
      content::RenderFrameHost* parent = navigation->GetParentFrame();
      if (!parent) {
        return;
      }
      content::RenderFrameHost* main_frame = parent->GetMainFrame();
      facts.same_site_as_main =
          net::SchemefulSite(navigation->GetURL()) ==
          net::SchemefulSite(main_frame->GetLastCommittedOrigin());
      facts.isolated =
          content::SiteIsolationPolicy::AreIsolatedSandboxedIframesEnabled() &&
          (navigation->SandboxFlagsInherited() &
           network::mojom::WebSandboxFlags::kOrigin) !=
              network::mojom::WebSandboxFlags::kNone;
      facts.main_frame_safari = MainDocumentPresentsSafari(main_frame);
      facts.parent_safari = FramePresentsSafari(parent);
    }
    const bool safari = fairplay_identity::NavigationPresentsSafari(
        ListsForContext(web_contents()->GetBrowserContext()), facts);
    navigation->SetIsOverridingUserAgent(safari);
    if (facts.main_frame) {
      main_frame_decisions_[navigation->GetNavigationId()] = safari;
    }
  }

  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    const int64_t id = navigation->GetNavigationId();
    primary_navigations_.erase(id);
    std::optional<bool> decided;
    if (auto found = main_frame_decisions_.find(id);
        found != main_frame_decisions_.end()) {
      decided = found->second;
      main_frame_decisions_.erase(found);
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
    }
    if (!navigation->IsInMainFrame()) {
      KeepEntryOnMainDocument(frame);
      return;
    }
    if (decided.value_or(false)) {
      SafariIdentityDocument::CreateForCurrentDocument(frame);
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

  static void Reconcile(base::WeakPtr<content::WebContents> contents) {
    if (!contents) {
      return;
    }
    if (auto* helper = FromWebContents(contents.get())) {
      helper->ReconcileWithLists();
    }
  }

  std::map<int64_t, bool> main_frame_decisions_;
  std::set<int64_t> primary_navigations_;
  bool reconcile_pending_ = false;
  int reloaded_entry_id_ = 0;
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(FairPlayIdentityHelper);

// A service or shared worker of a Safari site, outside any other site's
// storage partition, starts with Safari's user agent and no client-hint
// metadata, as its documents do.
void ApplyWorkerIdentity(content::BrowserContext* context,
                         const GURL& script_url,
                         const GURL& top_level_site,
                         std::string* user_agent,
                         blink::UserAgentMetadata* metadata) {
  if (SafariUserAgentString().empty()) {
    return;
  }
  const std::string site = SiteForURL(script_url);
  if (site.empty() || site != SiteForURL(top_level_site) ||
      !fairplay_identity::PresentsSafari(ListsForContext(context), site)) {
    return;
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

void ReconcileContext(const ContextKey& key) {
  std::vector<base::WeakPtr<content::WebContents>> pages;
  for (FairPlayIdentityHelper* helper : Helpers()) {
    content::WebContents* contents = helper->web_contents();
    if (contents && KeyForContext(contents->GetBrowserContext()) == key) {
      pages.push_back(contents->GetWeakPtr());
    }
  }
  for (const auto& contents : pages) {
    if (!contents) {
      continue;
    }
    if (auto* helper = FairPlayIdentityHelper::FromWebContents(contents.get())) {
      helper->ReconcileWithLists();
    }
  }
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
  all[key] = std::move(lists);
  // No page exists before the engine is ready, and pages are closing while it
  // quits. Otherwise reload after the caller returns, so no navigation
  // callback reaches the shell while it is still updating its own state.
  if (!parc::NativeProfileRemovalApplicationReady()) {
    return;
  }
  content::GetUIThreadTaskRunner({})->PostTask(
      FROM_HERE, base::BindOnce(&parc::ReconcileContext, key));
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
