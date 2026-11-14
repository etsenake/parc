// Copyright 2026 Parc contributors.
#import "native_appkit_page.h"

#include <memory>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/json/json_writer.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/timer/timer.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/ui/browser_commands_mac.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_change_registrar.h"
#include "components/prefs/pref_service.h"
#include "content/browser/renderer_host/render_view_host_impl.h"
#include "content/browser/web_contents/web_contents_impl.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "native_appkit_host.h"
#include "native_page_retirement.h"
#include "native_profile_removal.h"
#include "tab_transfer.h"
#include "ui/base/base_window.h"
#import "window_security_reservation.h"

@interface PCNativeAppleScriptResult ()
- (instancetype)initWithJSON:(NSString*)json error:(NSString*)error number:(NSInteger)number;
@end
@implementation PCNativeAppleScriptResult
@synthesize json = _json, errorMessage = _errorMessage, errorNumber = _errorNumber;
- (instancetype)initWithJSON:(NSString*)json error:(NSString*)error number:(NSInteger)number {
  if ((self = [super init])) { _json = [json copy]; _errorMessage = [error copy]; _errorNumber = number; }
  return self;
}
@end

namespace parc {
namespace {
using Completion = void (^)(PCNativeAppleScriptResult*);
PCNativeAppleScriptResult* Failure(NSString* message, NSInteger number = -10000) {
  return [[PCNativeAppleScriptResult alloc] initWithJSON:nil error:message number:number];
}
void Reply(Completion completion, PCNativeAppleScriptResult* result) {
  // Never resume an NSScriptCommand from a renderer, destruction, or policy stack.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce([](Completion callback, PCNativeAppleScriptResult* reply) { callback(reply); },
                     completion, result));
}
BrowserWindowInterface* Owner(PCNativePage* page) {
  auto* contents = ContentsForNativePage(page);
  if (!page || page.closed || !page.observer || !contents || contents->IsBeingDestroyed() ||
      IsNativePageRetiring(page) || IsLiveTabTransferTarget(contents)) return nullptr;
  auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents);
  auto* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  if (!browser || browser->IsDeleteScheduled() || !AppKitBrowserAcceptsNewPages(*browser) ||
      !browser->GetWindow() || !browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() ||
      !profile || profile != browser->GetProfile() || profile->ShutdownStarted() ||
      IsNativeProfileRemovalBlocked(profile->GetPath())) return nullptr;
  return browser;
}
bool Enabled(Profile* profile) {
  auto* prefs = profile ? profile->GetPrefs() : nullptr;
  return prefs && prefs->FindPreference(prefs::kAllowJavascriptAppleEvents) &&
      prefs->GetBoolean(prefs::kAllowJavascriptAppleEvents);
}
bool CanToggle(PCNativePage* page) {
  auto* browser = Owner(page);
  if (!browser) return false;
  auto* contents = ContentsForNativePage(page);
  auto* prefs = browser->GetProfile()->GetPrefs();
  auto* pref = prefs->FindPreference(prefs::kAllowJavascriptAppleEvents);
  NSWindow* window = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
  auto* binding = AppKitBindingForBrowser(browser);
  return pref && pref->IsUserModifiable() && NSApp.active && window.keyWindow &&
      !window.attachedSheet && !NSApp.modalWindow && !PCNativeWindowHasSecurityReservation(window) &&
      binding && [binding.client selectedNativePage] == page &&
      DevToolsWindow::AllowDevToolsFor(browser->GetProfile(), contents);
}

class Execution final : public content::WebContentsObserver, public ProfileObserver,
                        public std::enable_shared_from_this<Execution> {
 public:
  explicit Execution(PCNativePage* page, Completion completion)
      : content::WebContentsObserver(ContentsForNativePage(page)), page_(page),
        observer_(page.observer), completion_([completion copy]) {}
  ~Execution() override { Finish(Failure(@"The original scripting request was cancelled.", -128)); }

  void Start(NSString* script) {
    auto* browser = Owner(page_);
    auto* contents = web_contents();
    if (!browser || !contents || contents != ContentsForNativePage(page_) || !script ||
        !contents->GetPrimaryMainFrame() || !contents->GetPrimaryMainFrame()->IsRenderFrameLive() ||
        contents->IsCrashed()) {
      Finish(Failure(@"The original live page is unavailable.", -1728)); return;
    }
    browser_ = browser->GetWeakPtr();
    profile_ = browser->GetProfile()->GetWeakPtr();
    window_ = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
    document_ = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    if (!Enabled(profile_.get())) {
      Finish(Failure(@"Allow JavaScript from Apple Events in View → Developer for this profile before executing JavaScript.", -1743)); return;
    }
    if (!DevToolsWindow::AllowDevToolsFor(profile_.get(), contents)) {
      Finish(Failure(@"Developer Tools policy does not permit JavaScript from Apple Events.", -1743)); return;
    }
    // A paused renderer defers even synchronous ExecuteJavaScript requests.
    // Hold genuine lifecycle leases, without changing page visibility or policy.
    static_cast<content::WebContentsImpl*>(contents)->GetPrimaryFrameTree()
        .ForEachRenderViewHost([this](content::RenderViewHostImpl* view) {
          unfreezing_leases_.push_back(
              view->GetPageLifecycleStateManager()->AcquireParcUnfreezingLease());
        });
    profile_observer_.Observe(profile_.get());
    pref_observer_.Init(profile_->GetPrefs());
    auto changed = base::BindRepeating(&Execution::Check, weak_factory_.GetWeakPtr());
    pref_observer_.Add(prefs::kAllowJavascriptAppleEvents, changed);
    if (profile_->GetPrefs()->FindPreference(prefs::kDevToolsAvailability))
      pref_observer_.Add(prefs::kDevToolsAvailability, changed);
    std::weak_ptr<Execution> weak = weak_from_this();
    window_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification object:window_ queue:nil
        usingBlock:^(NSNotification*) { if (auto self = weak.lock()) self->Cancel(); }];
    // A bounded reply watchdog is a Parc adaptation. It never terminates or
    // replays script side effects. Observer callbacks handle document teardown;
    // this also catches native ownership/retirement transitions without a reply.
    ownership_timer_.Start(FROM_HERE, base::Milliseconds(100), changed);
    timeout_.Start(FROM_HERE, base::Seconds(30), base::BindOnce(&Execution::Timeout, weak_factory_.GetWeakPtr()));
    auto code = base::SysNSStringToUTF16(script);
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce(&Execution::Dispatch, weak_factory_.GetWeakPtr(), std::move(code)));
  }
  void Cancel() { Finish(Failure(@"The original scripting request was cancelled.", -128)); }

 private:
  bool Valid() const {
    auto* contents = web_contents();
    auto* browser = Owner(page_);
    return completion_ && browser && browser_.get() == browser && profile_ &&
        browser->GetProfile() == profile_.get() && contents &&
        contents == ContentsForNativePage(page_) && page_.observer == observer_ && observer_ &&
        window_ && browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() == window_ &&
        contents->GetPrimaryMainFrame() &&
        document_.AsRenderFrameHostIfValid() == contents->GetPrimaryMainFrame() &&
        contents->GetPrimaryMainFrame()->IsRenderFrameLive() && !contents->IsCrashed() &&
        Enabled(profile_.get()) && DevToolsWindow::AllowDevToolsFor(profile_.get(), contents);
  }
  void Dispatch(std::u16string script) {
    if (!Valid()) { Cancel(); return; }
    document_.AsRenderFrameHostIfValid()->ExecuteJavaScriptInIsolatedWorld(
        script, base::BindOnce(&Execution::Completed, weak_factory_.GetWeakPtr()),
        ISOLATED_WORLD_ID_APPLESCRIPT);
  }
  void Completed(base::Value value) {
    if (!Valid()) { Cancel(); return; }
    auto json = base::WriteJson(value, 200);
    if (!json) { Finish(Failure(@"The JavaScript result could not be represented as JSON text.")); return; }
    Finish([[PCNativeAppleScriptResult alloc] initWithJSON:base::SysUTF8ToNSString(*json) error:nil number:0]);
  }
  void Check() { if (!Valid()) Cancel(); }
  void Timeout() { Finish(Failure(@"The JavaScript request did not finish within 30 seconds.", -1712)); }
  void Finish(PCNativeAppleScriptResult* result) {
    if (!completion_) return;
    auto completion = completion_; completion_ = nil;
    timeout_.Stop(); ownership_timer_.Stop(); weak_factory_.InvalidateWeakPtrs();
    pref_observer_.RemoveAll(); profile_observer_.Reset();
    if (window_observer_) [NSNotificationCenter.defaultCenter removeObserver:window_observer_];
    window_observer_ = nil;
    Observe(nullptr);
    unfreezing_leases_.clear();
    Reply(completion, result);
  }
  void RenderFrameCreated(content::RenderFrameHost* frame) override {
    auto* original = document_.AsRenderFrameHostIfValid();
    if (!completion_ || !original || frame->GetOutermostMainFrame() != original) return;
    auto* view = static_cast<content::RenderViewHostImpl*>(frame->GetRenderViewHost());
    unfreezing_leases_.push_back(
        view->GetPageLifecycleStateManager()->AcquireParcUnfreezingLease());
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) Cancel();
  }
  void PrimaryPageChanged(content::Page&) override { Cancel(); }
  void WebContentsDestroyed() override { Cancel(); }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override { Cancel(); }
  void OnProfileWillBeDestroyed(Profile*) override { Cancel(); }

  PCNativePage* __weak page_;
  id<PCNativePageObserver> __weak observer_;
  NSWindow* __weak window_;
  id __strong window_observer_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  content::WeakDocumentPtr document_;
  Completion completion_;
  std::vector<base::ScopedClosureRunner> unfreezing_leases_;
  base::OneShotTimer timeout_;
  base::RepeatingTimer ownership_timer_;
  PrefChangeRegistrar pref_observer_;
  base::ScopedObservation<Profile, ProfileObserver> profile_observer_{this};
  base::WeakPtrFactory<Execution> weak_factory_{this};
};
}  // namespace
}  // namespace parc

@interface PCNativeAppleScriptExecution () {
 @public
  std::shared_ptr<parc::Execution> state;
}
@end
@implementation PCNativeAppleScriptExecution
- (void)cancel { if (state) state->Cancel(); }
@end

@implementation PCNativePage (AppleScript)
- (BOOL)appleEventJavaScriptAllowed {
  auto* browser = parc::Owner(self);
  return browser && parc::Enabled(browser->GetProfile());
}
- (BOOL)canToggleAppleEventJavaScript { return parc::CanToggle(self); }
- (BOOL)toggleAppleEventJavaScript {
  auto* browser = parc::Owner(self);
  if (!browser || !parc::CanToggle(self)) return NO;
  const bool previous = parc::Enabled(browser->GetProfile());
  chrome::ToggleJavaScriptFromAppleEventsAllowed(browser);
  return parc::Enabled(browser->GetProfile()) != previous;
}
- (PCNativeAppleScriptExecution*)executeAppleEventJavaScript:(NSString*)script
    completion:(void (^)(PCNativeAppleScriptResult*))completion {
  auto token = [[PCNativeAppleScriptExecution alloc] init];
  token->state = std::make_shared<parc::Execution>(self, completion);
  token->state->Start(script);
  return token;
}
@end
