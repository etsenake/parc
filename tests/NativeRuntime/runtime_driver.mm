// Copyright 2026 Parc contributors.
#include "runtime_driver.h"

#import <QuartzCore/QuartzCore.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cstdio>
#include <memory>
#include <optional>
#include <string>

#include "base/check.h"
#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/run_loop.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "base/uuid.h"
#include "base/values.h"
#import "cef/libcef/browser/parc_native/native_appkit_bridge.h"
#include "cef/libcef/browser/parc_native/native_appkit_page.h"
#include "cef/libcef/browser/parc_native/video_overlay_window.h"
#include "chrome/browser/extensions/extension_util.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/browser_window/public/profile_browser_collection.h"
#include "chrome/browser/ui/login/login_handler.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_service.h"
#include "components/sessions/content/session_tab_helper.h"
#include "components/tabs/public/tab_interface.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "content/public/browser/browser_accessibility_state.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/overlay_window.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/video_picture_in_picture_window_controller.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/common/isolated_world_ids.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/permissions/active_tab_permission_granter.h"
#include "extensions/browser/unpacked_installer.h"
#include "extensions/common/extension.h"
#include "extensions/common/permissions/permissions_data.h"
#include "net/base/auth.h"
#include "ui/base/base_window.h"
#include "url/gurl.h"
#include "url/scheme_host_port.h"

// A temporary observer of the actual production-created page. It intercepts
// only this deliberate renderer-failure test, then restores the shell observer.
@interface PCRuntimePageEventObserver : NSObject <PCNativePageObserver>
@property(nonatomic, weak) id<PCNativePageObserver> original;
@property(nonatomic, copy) void (^changed)(PCNativePage*);
@property(nonatomic, copy) void (^failed)(PCNativePage*, NSError*);
@end
@implementation PCRuntimePageEventObserver
@synthesize original = _original;
@synthesize changed = _changed;
@synthesize failed = _failed;
- (void)nativePageDidChange:(PCNativePage*)page {
  if (_changed) {
    _changed(page);
  }
}
- (void)nativePage:(PCNativePage*)page didFailWithError:(NSError*)error {
  if (_failed) {
    _failed(page, error);
  }
}
- (void)nativePageDidClose:(PCNativePage*)page {
  [_original nativePageDidClose:page];
}
@end

namespace {
class Run;
bool HasActiveExtensions();
bool HasActiveVideoPiP();
std::shared_ptr<Run>& Active() {
  static base::NoDestructor<std::shared_ptr<Run>> run;
  return *run;
}
NSView* Find(NSView* view, NSString* identifier) {
  if ([view.identifier isEqualToString:identifier] ||
      ([view isKindOfClass:NSButton.class] &&
       [static_cast<NSButton*>(view).title isEqualToString:identifier])) {
    return view;
  }
  for (NSView* child in view.subviews) {
    if (NSView* found = Find(child, identifier)) {
      return found;
    }
  }
  return nil;
}
// Traverse the genuine AppKit hierarchy under this exact page only. Do not
// request an AX snapshot, force a mode, or supply replacement accessibility
// objects: the test must fail if production AX requests cannot expose the tree.
// Diagnostics retain only bounded class/role tokens and counts, never an AX
// title/value, page text, URL credentials, or the native objects themselves.
std::string DiagnosticToken(NSString* value) {
  std::string token;
  for (NSUInteger i = 0; i < value.length && i < 96; ++i) {
    const unichar character = [value characterAtIndex:i];
    token += ((character >= 'a' && character <= 'z') ||
              (character >= 'A' && character <= 'Z') ||
              (character >= '0' && character <= '9') || character == '_' ||
              character == '.' || character == '-')
                 ? static_cast<char>(character)
                 : '_';
  }
  return token.empty() ? "none" : token;
}
struct AXTraversalDiagnostic {
  std::string nodes;
  int visited = 0;
  int remaining = 512;
  bool queried = false;
};
bool HasNativeWebArea(id element,
                      NSHashTable* visited,
                      int* remaining,
                      AXTraversalDiagnostic* diagnostic = nullptr,
                      int depth = 0) {
  if (!element || *remaining <= 0 || [visited containsObject:element]) {
    return false;
  }
  --*remaining;
  [visited addObject:element];
  NSString* role = [element respondsToSelector:@selector(accessibilityRole)]
                       ? [element accessibilityRole]
                       : nil;
  const bool web_area = [role isEqualToString:@"AXWebArea"];
  // Preserve the existing short circuit and query each native AX property only
  // where the assertion already did. Logging must not activate another path.
  NSArray* children =
      !web_area && [element respondsToSelector:@selector(accessibilityChildren)]
          ? [element accessibilityChildren]
          : nil;
  if (diagnostic) {
    ++diagnostic->visited;
    diagnostic->remaining = *remaining;
    diagnostic->queried = true;
    if (diagnostic->visited <= 32) {
      diagnostic->nodes +=
          "{depth=" + std::to_string(depth) +
          ",class=" + DiagnosticToken(NSStringFromClass([element class])) +
          ",role=" + DiagnosticToken(role) + ",children=" +
          (web_area ? "unqueried" : std::to_string(children.count)) + "}";
    }
  }
  if (web_area) {
    return true;
  }
  for (id child in children) {
    if (HasNativeWebArea(child, visited, remaining, diagnostic, depth + 1)) {
      return true;
    }
  }
  return false;
}
// Observe the ordinary NSView containment independently of AX traversal. This
// is diagnostic only: it never supplies an alternate route to the assertion.
void DescribeNativeSubviews(NSView* view,
                            NSWindow* expected_window,
                            int depth,
                            int* remaining,
                            std::string* summary) {
  if (!view || *remaining <= 0 || depth > 8) {
    return;
  }
  --*remaining;
  NSArray<NSView*>* children = view.subviews;
  *summary += "{depth=" + std::to_string(depth) +
              ",class=" + DiagnosticToken(NSStringFromClass(view.class)) +
              ",children=" + std::to_string(children.count) +
              ",same_window=" + std::to_string(view.window == expected_window) +
              ",hidden=" + std::to_string(view.hidden) + "}";
  for (NSView* child in children) {
    DescribeNativeSubviews(child, expected_window, depth + 1, remaining,
                           summary);
  }
}
// Like CEF's existing internal test helpers, this is not a web or product UI
// entry. Refuse ordinary app processes and real/unmarked profile locations.
bool IsDisposableHarnessProfile(Profile* profile) {
  auto* command = base::CommandLine::ForCurrentProcess();
  if (!profile || profile->IsOffTheRecord() ||
      !command->HasSwitch("parc-native-runtime-controller-tests") ||
      !command->HasSwitch("use-mock-keychain") ||
      profile->GetPath().BaseName().value() != "runtime-profile") {
    return false;
  }
  NSString* root = [NSString
      stringWithUTF8String:profile->GetPath().DirName().value().c_str()];
  if (!root || ![root.stringByResolvingSymlinksInPath isEqualToString:root]) {
    return false;
  }
  struct stat st;
  if (lstat(root.fileSystemRepresentation, &st) || !S_ISDIR(st.st_mode) ||
      st.st_uid != getuid() || (st.st_mode & 0777) != 0700) {
    return false;
  }
  NSString* marker =
      [root stringByAppendingPathComponent:@"parc-native-runtime-test.marker"];
  if (lstat(marker.fileSystemRepresentation, &st) || !S_ISREG(st.st_mode) ||
      st.st_nlink != 1 || st.st_uid != getuid() ||
      (st.st_mode & 0777) != 0600) {
    return false;
  }
  return [[NSString stringWithContentsOfFile:marker
                                    encoding:NSUTF8StringEncoding
                                       error:nil]
      isEqualToString:@"Parc native runtime test v1\n"];
}
class Run final : public content::WebContentsObserver,
                  public std::enable_shared_from_this<Run> {
 public:
  Run(PCNativePage* page,
      PCNativeBrowserWindow* binding,
      NSView* container,
      PCRuntimeHTTPAuthCase test_case,
      void (^finished)(BOOL, NSString*))
      : page_(page),
        binding_(binding),
        container_(container),
        window_(binding.window),
        test_case_(test_case),
        finished_([finished copy]) {
    if (auto* contents = parc::ContentsForNativePage(page)) {
      Observe(contents);
      contents_ = contents->GetWeakPtr();
      if (auto* tab = tabs::TabInterface::MaybeGetFromContents(contents)) {
        tab_ = tab->GetWeakPtr();
        if (auto* browser = tab->GetBrowserWindowInterface()) {
          browser_ = browser->GetWeakPtr();
          profile_ = browser->GetProfile()->GetWeakPtr();
        }
      }
    }
  }
  void Start() {
    auto keep = shared_from_this();
    if (!StableIdentity(false) || !Attached() ||
        !IsDisposableHarnessProfile(profile_.get())) {
      Finish(false, @"Real native fixture page identity is not ready.");
      return;
    }
    // This page was created through the real BrowserManager -> CEF delegate ->
    // NativeBrowserWindow attachment path, including the pre-global-publication
    // registration callback. By the time the shell receives the actual page,
    // both collections must contain its exact owner. StableIdentity/Attached
    // above also require its actual TabInterface and supplied NSWindow/view.
    const auto owns_browser = [this](BrowserCollection* collection) {
      bool found = false;
      collection->ForEach([&](BrowserWindowInterface* candidate) {
        found = candidate == browser_.get();
        return !found;
      });
      return found;
    };
    if (!owns_browser(
            ProfileBrowserCollection::GetForProfile(profile_.get())) ||
        !owns_browser(GlobalBrowserCollection::GetInstance())) {
      Finish(false,
             @"Actual Browser registration was not published for the page.");
      return;
    }
    if (test_case_ == PCRuntimeHTTPAuthAccept) {
      std::fprintf(stdout, "NATIVE_REGISTRATION_PASS manager=true global=true "
                           "tab=true supplied_window=true\n");
      std::fflush(stdout);
    }
    std::weak_ptr<Run> weak = keep;
    diagnostic_started_ = base::TimeTicks::Now();
    SetStage("waiting-document");
    deadline_.Start(FROM_HERE, base::Seconds(15),
                    base::BindOnce(
                        [](std::weak_ptr<Run> weak) {
                          if (auto self = weak.lock()) {
                            self->LogDiagnostic("deadline");
                            self->Finish(false,
                                         @"HTTP-auth controller deadline.");
                          }
                        },
                        weak));
    poll_.Start(FROM_HERE, base::Milliseconds(25),
                base::BindRepeating(
                    [](std::weak_ptr<Run> weak) {
                      if (auto self = weak.lock()) {
                        self->WaitForDocument();
                      }
                    },
                    weak));
    WaitForDocument();
  }
  void Cancel() {
    Finish(false, @"Harness cancelled the active controller test.");
  }

 private:
  void SetStage(const char* stage) {
    if (diagnostic_stage_ == stage) {
      return;
    }
    diagnostic_stage_ = stage;
    LogDiagnostic("stage-change");
  }
  void LogDiagnostic(const char* reason) const {
    auto contents = contents_;
    auto* frame = contents ? contents->GetPrimaryMainFrame() : nullptr;
    const auto global_mode = content::BrowserAccessibilityState::GetInstance()
                                 ->GetAccessibilityMode();
    const char* committed = "no-contents";
    if (contents) {
      const GURL& url = contents->GetLastCommittedURL();
      committed = url.is_empty() ? "empty"
                  : url == GURL(PCRuntimeDocumentURLString().UTF8String)
                      ? "runtime-fixture"
                  : url == GURL("about:blank") ? "about:blank"
                                               : "other-redacted";
    }
    NSView* view = page_.nativeView;
    std::string native_subviews;
    int remaining_views = 32;
    DescribeNativeSubviews(view, window_, 0, &remaining_views,
                           &native_subviews);
    std::fprintf(
        stdout,
        "NATIVE_RUNTIME_DIAGNOSTIC case=%d reason=%s stage=%s elapsed_ms=%lld "
        "committed=%s loading=%d frame=%d frame_live=%d process_ready=%d "
        "crashed=%d global_ax=0x%x page_ax=0x%x engine_ax_root=%d "
        "stable_owner=%d attached=%d view_window=%d container_window=%d "
        "window_visible=%d window_miniaturized=%d "
        "ax_queried=%d ax_visited=%d ax_budget_remaining=%d "
        "ax_summary_limited=%d ax_nodes=%s native_nodes=%s "
        "native_node_budget_remaining=%d native_depth_limit=8\n",
        static_cast<int>(test_case_), reason, diagnostic_stage_.c_str(),
        static_cast<long long>(
            (base::TimeTicks::Now() - diagnostic_started_).InMilliseconds()),
        committed, contents && contents->IsLoading(), frame != nullptr,
        frame && frame->IsRenderFrameLive(),
        frame && frame->GetProcess()->IsReady(),
        contents && contents->IsCrashed(), global_mode.flags(),
        contents ? contents->GetAccessibilityMode().flags() : 0,
        contents && contents->GetAccessibilityRootNode(), StableIdentity(false),
        Attached(), view.window == window_, container_.window == window_,
        window_.visible, window_.miniaturized, ax_diagnostic_.queried,
        ax_diagnostic_.visited, ax_diagnostic_.remaining,
        ax_diagnostic_.visited > 32, ax_diagnostic_.nodes.c_str(),
        native_subviews.c_str(), remaining_views);
    std::fflush(stdout);
  }
  void WaitForDocument() {
    if (!StableIdentity(false) || !Attached()) {
      Finish(false, @"Real page identity changed before initial commit.");
      return;
    }
    if (contents_->IsLoading() ||
        contents_->GetLastCommittedURL() !=
            GURL(PCRuntimeDocumentURLString().UTF8String)) {
      SetStage("waiting-document");
      return;
    }
    auto* accessibility = content::BrowserAccessibilityState::GetInstance();
    const auto before_request = accessibility->GetAccessibilityMode();
    // Exercise the real application request hook, as an assistive client does.
    // Never set the engine AX mode or request a synthetic tree snapshot here.
    (void)[NSApp accessibilityRole];
    if (!StableIdentity(false) || !Attached()) {
      Finish(false, @"Page identity changed during the application AX query.");
      return;
    }
    const auto after_request = accessibility->GetAccessibilityMode();
    const uint32_t advanced = ui::AXMode::kInlineTextBoxes |
                              ui::AXMode::kExtendedProperties |
                              ui::AXMode::kScreenReader;
    if ((after_request.flags() & ~before_request.flags() & advanced) != 0) {
      Finish(false,
             @"A basic native AX query forced unsolicited screen-reader mode.");
      return;
    }
    if (!accessibility->GetAccessibilityMode().has_mode(
            ui::kAXModeBasic.flags()) ||
        !contents_->GetAccessibilityMode().has_mode(ui::kAXModeBasic.flags())) {
      Finish(false, @"The real application role request did not activate basic "
                    @"native AX.");
      return;
    }
    // The live renderer tree is asynchronous. Wait within the existing
    // bounded case deadline, then confirm its real native WebArea is reachable
    // through the supplied page view, not merely an engine-internal tree.
    if (!contents_->GetAccessibilityRootNode()) {
      SetStage("waiting-engine-ax-root");
      return;
    }
    NSHashTable* visited = [NSHashTable
        hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    int remaining = 512;
    ax_diagnostic_ = AXTraversalDiagnostic();
    if (!HasNativeWebArea(page_.nativeView, visited, &remaining,
                          &ax_diagnostic_)) {
      SetStage("waiting-native-web-area");
      return;
    }
    if (!StableIdentity(false) || !Attached()) {
      Finish(false, @"Page ownership changed during native AX traversal.");
      return;
    }
    if (test_case_ == PCRuntimeHTTPAuthAccept) {
      std::fprintf(stdout,
                   "NATIVE_ACCESSIBILITY_PASS requested_basic_mode=true "
                   "live_tree=true native_web_area=true\n");
      std::fflush(stdout);
    }
    document_ = contents_->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    poll_.Stop();
    if (test_case_ == PCRuntimeHTTPAuthAccept) {
      BeginPageEventProbe();
    } else {
      BeginDialog();
    }
  }
  void BeginPageEventProbe() {
    SetStage("waiting-renderer-exit");
    auto keep = shared_from_this();
    original_observer_ = page_.observer;
    probe_observer_ = [[PCRuntimePageEventObserver alloc] init];
    probe_observer_.original = original_observer_;
    std::weak_ptr<Run> weak = keep;
    probe_observer_.changed = ^(PCNativePage* page) {
      if (auto self = weak.lock()) {
        self->ProbeDelivery(page, nil);
      }
    };
    probe_observer_.failed = ^(PCNativePage* page, NSError* error) {
      if (auto self = weak.lock()) {
        self->ProbeDelivery(page, error);
      }
    };
    page_.observer = probe_observer_;
    probe_previous_document_ = document_;
    probe_waiting_for_exit_ = true;
    // Kill only this real renderer in the owned, marked disposable profile.
    // Public Chromium dispatch performs the actual process-gone notification;
    // no fake WebContents, injected status or private header is involved.
    auto* process = contents_->GetPrimaryMainFrame()->GetProcess();
    if (!process->IsReady() || !process->Shutdown(1)) {
      Finish(false, @"Actual disposable renderer shutdown was not accepted.");
    }
  }
  void PrimaryMainFrameRenderProcessGone(
      base::TerminationStatus status) override {
    if (!probe_waiting_for_exit_ || done_) {
      return;
    }
    auto keep = shared_from_this();
    probe_status_ = status;
    ++probe_exit_events_;
    PumpObserverLoop();
    std::weak_ptr<Run> weak = keep;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(^{
          if (auto self = weak.lock(); self && !self->done_) {
            self->CheckPageEventProbe();
          }
        }));
  }
  void DidStartLoading() override {
    if (probe_recovering_) {
      PumpObserverLoop();
    }
  }
  void DidStopLoading() override {
    if (probe_recovering_) {
      PumpObserverLoop();
    }
  }
  void PumpObserverLoop() {
    auto keep = shared_from_this();
    ++probe_nested_loops_;
    const bool was_dispatching = probe_dispatching_;
    probe_dispatching_ = true;
    base::RunLoop nested(base::RunLoop::Type::kNestableTasksAllowed);
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, nested.QuitClosure());
    nested.Run();
    probe_dispatching_ = was_dispatching;
  }
  void ProbeDelivery(PCNativePage* page, NSError* error) {
    if (done_) {
      return;
    }
    // The renderer may be gone and its old document invalid. Retain exact
    // Browser/Profile/tab/page/window ownership, not that obsolete document.
    if (probe_dispatching_ || !StableIdentity(false) || !Attached() ||
        page != page_ || page_.observer != probe_observer_) {
      probe_failed_ = true;
      return;
    }
    if (error) {
      ++probe_errors_;
      // The real SadTab state is the failure notification for this status.
      // A second transient NSError would create duplicate/sticky shell UI.
      probe_failed_ = true;
      return;
    }
    ++probe_changes_;
    if (probe_waiting_for_exit_) {
      PCNativeRendererCrash* crash = page_.rendererCrash;
      if (!crash || (probe_crash_ && crash != probe_crash_) ||
          crash.terminationStatus != probe_status_ ||
          crash.errorCode != contents_->GetCrashedErrorCode() ||
          !contents_->IsCrashed() ||
          contents_->GetCrashedStatus() != probe_status_) {
        probe_failed_ = true;
        return;
      }
      probe_crash_ = crash;
    }
    // This is the actual shell operation from the production crash stack.
    // It must run after the engine observer/nested-event stack returns.
    [binding_ synchronizeSelectionAndLayout];
  }
  void CheckPageEventProbe() {
    if (probe_failed_ || probe_errors_ != 0 || probe_exit_events_ != 1 ||
        !probe_crash_ || page_.rendererCrash != probe_crash_ ||
        probe_nested_loops_ < 1 || !StableIdentity(false) || !Attached() ||
        page_.observer != probe_observer_) {
      Finish(false,
             @"Real renderer failure escaped its observer/nested stack.");
      return;
    }
    // Exercise actual platform detach/attach while retaining the same failed
    // contents/tab/Browser. This is not a claim of cross-Browser transfer.
    [binding_ pageWillDetach:page_];
    if (!StableIdentity(false) || !ExpectedDetached() ||
        page_.rendererCrash != probe_crash_ ||
        ![binding_ pageDidAttach:page_ container:container_] ||
        !StableIdentity(false) || !Attached() ||
        page_.rendererCrash != probe_crash_) {
      Finish(false,
             @"Native crash snapshot did not survive exact page reattachment.");
      return;
    }
    // No crash view was painted by this controller fixture. Do not fake the
    // real SadTab first-paint metric to invoke its button. Same-page Reload
    // remains genuine; the Swift Retry control has a separate runtime gate.
    if ([page_ performRendererCrashAction:probe_crash_]) {
      Finish(false, @"Unpresented native crash action was accepted.");
      return;
    }
    probe_waiting_for_exit_ = false;
    probe_recovering_ = true;
    SetStage("waiting-renderer-recovery");
    document_ = content::WeakDocumentPtr();
    // Use the public native page operation; preserve the same actual contents
    // and tab, then obtain a fresh committed document before controller tests.
    probe_dispatching_ = true;
    [page_ reload];
    probe_dispatching_ = false;
    if (done_) {
      return;
    }
    std::weak_ptr<Run> weak = shared_from_this();
    poll_.Start(FROM_HERE, base::Milliseconds(25),
                base::BindRepeating(
                    [](std::weak_ptr<Run> weak) {
                      if (auto self = weak.lock()) {
                        self->WaitForRendererRecovery();
                      }
                    },
                    weak));
    WaitForRendererRecovery();
  }
  void WaitForRendererRecovery() {
    if (probe_failed_ || !StableIdentity(false) || !Attached() ||
        page_.observer != probe_observer_) {
      Finish(false, @"Real page ownership changed during renderer recovery.");
      return;
    }
    auto* frame = contents_->GetPrimaryMainFrame();
    if (contents_->IsLoading() || contents_->IsCrashed() ||
        !frame->IsRenderFrameLive() ||
        contents_->GetLastCommittedURL() !=
            GURL(PCRuntimeDocumentURLString().UTF8String) ||
        probe_previous_document_.AsRenderFrameHostIfValid()) {
      return;
    }
    if (probe_nested_loops_ < 2 || probe_changes_ < 1 || probe_errors_ != 0) {
      Finish(false,
             @"Renderer recovery did not deliver deferred loading state.");
      return;
    }
    if (page_.rendererCrash ||
        [page_ performRendererCrashAction:probe_crash_] ||
        [page_ rendererCrashDidPresent:probe_crash_]) {
      Finish(false,
             @"Recovered page retained crash state or accepted stale Retry.");
      return;
    }
    document_ = frame->GetWeakDocumentPtr();
    poll_.Stop();
    probe_recovering_ = false;
    RetirePageEventProbe();
    std::fprintf(stdout, "NATIVE_PAGE_EVENTS_PASS renderer_failure=true "
                         "nested_deferred=true recovered=true metadata=true\n");
    std::fprintf(stdout, "NATIVE_RENDERER_CRASH_PASS snapshot_status=true "
                         "persistent_detach=true stale_action_rejected=true "
                         "cleared_on_recovery=true\n");
    std::fflush(stdout);
    BeginDialog();
  }
  void RetirePageEventProbe() {
    if (probe_observer_ && page_.observer == probe_observer_) {
      page_.observer = original_observer_;
    }
    probe_observer_.changed = nil;
    probe_observer_.failed = nil;
    probe_observer_ = nil;
    original_observer_ = nil;
    probe_waiting_for_exit_ = false;
    probe_recovering_ = false;
  }
  void BeginDialog() {
    SetStage("waiting-auth-sheet");
    auto keep = shared_from_this();
    std::weak_ptr<Run> weak = keep;
    auto* modal = Manager();
    if (!modal || !modal->delegate() || modal->IsDialogActive() ||
        window_.attachedSheet) {
      Finish(false, @"Production modal manager is unavailable or occupied.");
      return;
    }
    net::AuthChallengeInfo challenge;
    challenge.scheme = "basic";
    challenge.realm = "Parc synthetic controller test";
    challenge.challenger = url::SchemeHostPort(GURL("http://127.0.0.1:9"));
    handler_ = LoginHandler::Create(
        challenge, contents_.get(),
        base::BindOnce(
            [](std::weak_ptr<Run> weak,
               const std::optional<net::AuthCredentials>& credentials) {
              if (auto self = weak.lock()) {
                self->OnResult(credentials);
              }
            },
            weak));
    if (!handler_) {
      Finish(false, @"Actual LoginHandler factory refused the native page.");
      return;
    }
    handler_->ShowLoginPrompt(GURL("http://127.0.0.1:9/controller-only"));
    if (done_) {
      return;
    }
    poll_.Start(FROM_HERE, base::Milliseconds(25),
                base::BindRepeating(
                    [](std::weak_ptr<Run> weak) {
                      if (auto self = weak.lock()) {
                        self->InspectSheet();
                      }
                    },
                    weak));
  }
  bool StableIdentity(bool require_document = true) const {
    return contents_ && tab_ && browser_ && profile_ && page_ &&
           !browser_->IsDeleteScheduled() && browser_->GetWindow() &&
           tab_->IsActivated() && !page_.isClosed &&
           binding_.window == window_ && window_.visible &&
           !window_.miniaturized && container_.window == window_ &&
           (!require_document || document_.AsRenderFrameHostIfValid() ==
                                     contents_->GetPrimaryMainFrame()) &&
           parc::ContentsForNativePage(page_) == contents_.get() &&
           [PCNativeBrowserApplication ownerForPage:page_] == binding_ &&
           tabs::TabInterface::MaybeGetFromContents(contents_.get()) ==
               tab_.get() &&
           tab_->GetContents() == contents_.get() &&
           tab_->GetBrowserWindowInterface() == browser_.get() &&
           browser_->GetProfile() == profile_.get() &&
           browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() ==
               window_;
  }
  bool Attached() const {
    return page_.nativeView.window == window_ &&
           [page_.nativeView isDescendantOf:container_];
  }
  bool ExpectedDetached() const {
    return page_.nativeView.window == nil &&
           ![page_.nativeView isDescendantOf:container_];
  }
  bool Valid() const { return !done_ && StableIdentity() && Attached(); }
  web_modal::WebContentsModalDialogManager* Manager() const {
    return contents_
               ? web_modal::WebContentsModalDialogManager::FromWebContents(
                     contents_.get())
               : nullptr;
  }
  void InspectSheet() {
    if (!Valid()) {
      Finish(false, @"Page/document/window identity changed during the case.");
      return;
    }
    NSWindow* sheet = window_.attachedSheet;
    if (!sheet || !sheet.visible) {
      return;
    }
    if (!Manager() || !Manager()->IsDialogActive()) {
      Finish(false, @"Visible sheet is not owned by the actual modal manager.");
      return;
    }
    auto* username = Find(sheet.contentView, @"http-auth-username");
    auto* password = Find(sheet.contentView, @"http-auth-password");
    auto* accept = Find(sheet.contentView, @"Sign In");
    auto* cancel = Find(sheet.contentView, @"Cancel");
    if (![username isKindOfClass:NSTextField.class] ||
        ![password isKindOfClass:NSSecureTextField.class] ||
        ![accept isKindOfClass:NSButton.class] ||
        ![cancel isKindOfClass:NSButton.class]) {
      Finish(false, @"Actual HTTP-auth sheet controls are missing.");
      return;
    }
    poll_.Stop();
    acted_ = true;
    SetStage("waiting-auth-result");
    if (test_case_ == PCRuntimeHTTPAuthAccept) {
      static_cast<NSTextField*>(username).stringValue = @"runtime-user";
      static_cast<NSSecureTextField*>(password).stringValue = @"runtime-secret";
      [static_cast<NSButton*>(accept) performClick:nil];
    } else if (test_case_ == PCRuntimeHTTPAuthCancel) {
      [static_cast<NSButton*>(cancel) performClick:nil];
    } else {
      detached_ = true;
      // Exercise the production attachment gate, not the HTTP-auth state
      // helper directly. The original real page and NSWindow stay alive.
      [binding_ pageWillDetach:page_];
    }
    if (!done_ && replies_ != 0) {
      Finish(false, @"Engine result escaped synchronously from native action.");
    }
  }
  void OnResult(const std::optional<net::AuthCredentials>& credentials) {
    ++replies_;
    const bool values_match = credentials &&
                              credentials->username() == u"runtime-user" &&
                              credentials->password() == u"runtime-secret";
    const bool expected =
        test_case_ == PCRuntimeHTTPAuthAccept ? values_match : !credentials;
    auto keep = shared_from_this();
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE,
        base::BindOnce(
            [](std::shared_ptr<Run> keep, bool expected) {
              if (keep->done_) {
                return;
              }
              if (!keep->StableIdentity() ||
                  !(keep->detached_ ? keep->ExpectedDetached()
                                    : keep->Attached()) ||
                  !keep->acted_ || keep->replies_ != 1 || !expected ||
                  !keep->Manager() || keep->Manager()->IsDialogActive() ||
                  keep->window_.attachedSheet) {
                keep->Finish(false,
                             @"Actual auth continuation/modal cleanup failed.");
                return;
              }
              keep->Finish(
                  true,
                  @"Actual controller, native sheet and continuation passed.");
            },
            keep, expected));
  }
  void Finish(bool passed, NSString* detail) {
    if (done_) {
      return;
    }
    auto keep = shared_from_this();
    done_ = true;
    RetirePageEventProbe();
    Observe(nullptr);
    poll_.Stop();
    deadline_.Stop();
    // Retire the real handler before the next case or Browser teardown. Its
    // destructor closes its modal without fabricating a network result.
    handler_.reset();
    if (detached_) {
      if (!StableIdentity() || !ExpectedDetached() ||
          ![binding_ pageDidAttach:page_ container:container_] ||
          !StableIdentity() || !Attached()) {
        passed = false;
        detail = @"Original page failed production reattachment after detach.";
      }
      if (passed) {
        NSHashTable* visited = [NSHashTable
            hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
        int remaining = 512;
        if (!contents_->GetAccessibilityMode().has_mode(
                ui::kAXModeBasic.flags()) ||
            !HasNativeWebArea(page_.nativeView, visited, &remaining) ||
            !StableIdentity() || !Attached()) {
          passed = false;
          detail = @"The real native AX tree was lost across same-page "
                   @"reattachment.";
        }
      }
      detached_ = false;
    }
    if (Active().get() == this) {
      Active().reset();
    }
    auto callback = finished_;
    finished_ = nil;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(^{
          callback(passed, detail);
        }));
  }
  PCRuntimePageEventObserver* __strong probe_observer_;
  id<PCNativePageObserver> __weak original_observer_;
  content::WeakDocumentPtr probe_previous_document_;
  base::TerminationStatus probe_status_ =
      base::TERMINATION_STATUS_STILL_RUNNING;
  int probe_exit_events_ = 0;
  bool probe_waiting_for_exit_ = false;
  bool probe_recovering_ = false;
  int probe_nested_loops_ = 0;
  int probe_errors_ = 0;
  int probe_changes_ = 0;
  bool probe_dispatching_ = false;
  bool probe_failed_ = false;
  PCNativeRendererCrash* __strong probe_crash_;
  PCNativePage* __strong page_;
  PCNativeBrowserWindow* __strong binding_;
  NSView* __strong container_;
  NSWindow* __strong window_;
  const PCRuntimeHTTPAuthCase test_case_;
  void (^finished_)(BOOL, NSString*);
  base::WeakPtr<content::WebContents> contents_;
  content::WeakDocumentPtr document_;
  base::WeakPtr<tabs::TabInterface> tab_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  std::unique_ptr<LoginHandler> handler_;
  base::RepeatingTimer poll_;
  base::OneShotTimer deadline_;
  base::TimeTicks diagnostic_started_;
  std::string diagnostic_stage_;
  AXTraversalDiagnostic ax_diagnostic_;
  int replies_ = 0;
  bool acted_ = false;
  bool detached_ = false;
  bool done_ = false;
};
}  // namespace
extern "C" PARC_RUNTIME_TEST_EXPORT void parc_test_http_auth(
    PCNativePage* page,
    PCNativeBrowserWindow* binding,
    NSView* container,
    PCRuntimeHTTPAuthCase test_case,
    void (^finished)(BOOL, NSString*)) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(finished);
  if (Active() || HasActiveExtensions() || HasActiveVideoPiP() ||
      test_case < PCRuntimeHTTPAuthAccept ||
      test_case > PCRuntimeHTTPAuthDetach) {
    finished(NO, @"Invalid or overlapping controller case.");
    return;
  }
  auto run =
      std::make_shared<Run>(page, binding, container, test_case, finished);
  Active() = run;
  run->Start();
}
extern "C" PARC_RUNTIME_TEST_EXPORT void parc_test_cancel_http_auth() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (auto run = Active()) {
    run->Cancel();
  }
}

namespace {
class ExtensionRun;
std::shared_ptr<ExtensionRun>& ActiveExtensions() {
  static base::NoDestructor<std::shared_ptr<ExtensionRun>> run;
  return *run;
}
bool HasActiveExtensions() {
  return !!ActiveExtensions();
}
// These are assertions over the production Browser-owned action bridge and
// genuine models. No fake Browser, extension system or alternate container is
// constructed. The only temporary state is in the marked disposable Profile.
class ExtensionRun final : public std::enable_shared_from_this<ExtensionRun> {
 public:
  ExtensionRun(PCNativePage* first,
               PCNativePage* second,
               PCNativeBrowserWindow* binding,
               NSString* document,
               BOOL (^select_page)(PCNativePage*),
               void (^finished)(BOOL, NSString*))
      : first_(first),
        second_(second),
        binding_(binding),
        window_(binding.window),
        document_url_(document.UTF8String),
        select_([select_page copy]),
        finished_([finished copy]) {
    auto* first_contents = parc::ContentsForNativePage(first);
    auto* second_contents = parc::ContentsForNativePage(second);
    if (first_contents && second_contents) {
      first_contents_ = first_contents->GetWeakPtr();
      second_contents_ = second_contents->GetWeakPtr();
      if (auto* tab =
              tabs::TabInterface::MaybeGetFromContents(first_contents)) {
        first_tab_ = tab->GetWeakPtr();
        if (auto* browser = tab->GetBrowserWindowInterface()) {
          browser_ = browser->GetWeakPtr();
          profile_ = browser->GetProfile()->GetWeakPtr();
        }
      }
      if (auto* tab =
              tabs::TabInterface::MaybeGetFromContents(second_contents)) {
        second_tab_ = tab->GetWeakPtr();
      }
    }
  }
  void Start() {
    auto keep = shared_from_this();
    diagnostic_started_ = base::TimeTicks::Now();
    if (!Identity(false) || !IsDisposableHarnessProfile(profile_.get()) ||
        !document_url_.SchemeIs("http") ||
        document_url_.host() != "127.0.0.1" || !document_url_.has_port() ||
        document_url_.has_query() || document_url_.has_ref() ||
        document_url_.has_username() || document_url_.has_password() ||
        document_url_.path() != "/extension-actions.html") {
      Finish(false,
             @"Extension suite requires exact real pages and launcher origin.");
      return;
    }
    const auto registered = [this](BrowserCollection* collection) {
      bool found = false;
      collection->ForEach([&](BrowserWindowInterface* value) {
        found = value == browser_.get();
        return !found;
      });
      return found;
    };
    if (!registered(ProfileBrowserCollection::GetForProfile(profile_.get())) ||
        !registered(GlobalBrowserCollection::GetInstance())) {
      Finish(false, @"Actual extension Browser registration is absent.");
      return;
    }
    std::fprintf(stdout, "NATIVE_REGISTRATION_PASS manager=true global=true "
                         "tab=true supplied_window=true\n");
    std::fflush(stdout);
    SetStage("waiting-documents");
    std::weak_ptr<ExtensionRun> weak = keep;
    deadline_.Start(
        FROM_HERE, base::Seconds(15),
        base::BindOnce(
            [](std::weak_ptr<ExtensionRun> weak) {
              if (auto self = weak.lock()) {
                self->LogDiagnostic("deadline");
                self->Finish(false, @"Extension action controller deadline.");
              }
            },
            weak));
    poll_.Start(FROM_HERE, base::Milliseconds(25),
                base::BindRepeating(
                    [](std::weak_ptr<ExtensionRun> weak) {
                      if (auto self = weak.lock()) {
                        self->Poll();
                      }
                    },
                    weak));
    Poll();
  }
  void Cancel() {
    Finish(false, @"Harness cancelled the extension action suite.");
  }

 private:
  void SetStage(const char* stage) {
    if (diagnostic_stage_ == stage) {
      return;
    }
    diagnostic_stage_ = stage;
    LogDiagnostic("stage-change");
  }
  void LogDiagnostic(const char* reason) const {
    const auto elapsed = static_cast<long long>(
        (base::TimeTicks::Now() - diagnostic_started_).InMilliseconds());
    std::fprintf(stdout,
                 "NATIVE_EXTENSION_DIAGNOSTIC reason=%s stage=%s "
                 "elapsed_ms=%lld documents_ready=%d extension_received=%d "
                 "developer_mode=%d\n",
                 reason, diagnostic_stage_.c_str(), elapsed, loading_extension_,
                 extension_ != nullptr,
                 profile_ && profile_->GetPrefs()->GetBoolean(
                                 prefs::kExtensionsUIDeveloperMode));
    const auto page = [&](const char* name, content::WebContents* contents,
                          const char* query) {
      if (contents && contents->IsBeingDestroyed()) {
        contents = nullptr;
      }
      auto* frame = contents ? contents->GetPrimaryMainFrame() : nullptr;
      auto* process = frame ? frame->GetProcess() : nullptr;
      const auto id =
          frame ? frame->GetGlobalId() : content::GlobalRenderFrameHostId();
      const char* committed = "no-contents";
      if (contents) {
        const auto& url = contents->GetLastCommittedURL();
        if (url.is_empty()) {
          committed = "empty";
        } else if (url == GURL(document_url_.spec() + query)) {
          committed = "expected";
        } else if (url == GURL("about:blank")) {
          committed = "about-blank";
        } else {
          committed = "other-redacted";
        }
      }
      // Only existing engine state and IDs, never URL/DOM/profile data. These
      // queries do not navigate, initialize a renderer or change visibility.
      std::fprintf(
          stdout,
          "NATIVE_EXTENSION_DIAGNOSTIC_PAGE reason=%s stage=%s "
          "elapsed_ms=%lld page=%s present=%d loading=%d committed=%s "
          "frame=%d frame_id=%d:%d frame_live=%d frame_active=%d "
          "process_initialized=%d process_ready=%d process_blocked=%d "
          "crashed=%d\n",
          reason, diagnostic_stage_.c_str(), elapsed, name, contents != nullptr,
          contents && contents->IsLoading(), committed, frame != nullptr,
          id.child_id.GetUnsafeValue(), id.frame_routing_id,
          frame && frame->IsRenderFrameLive(), frame && frame->IsActive(),
          process && process->IsInitializedAndNotDead(),
          process && process->IsReady(), process && process->IsBlocked(),
          contents && contents->IsCrashed());
    };
    page("first", first_contents_.get(), "?tab=first");
    page("second", second_contents_.get(), "?tab=second");
    std::fflush(stdout);
  }
  bool Identity(bool documents = true) const {
    if (done_ || !first_contents_ || !second_contents_ || !first_tab_ ||
        !second_tab_ || !browser_ || !profile_ || first_ == second_ ||
        first_contents_.get() == second_contents_.get() || first_.closed ||
        second_.closed ||
        parc::ContentsForNativePage(first_) != first_contents_.get() ||
        parc::ContentsForNativePage(second_) != second_contents_.get() ||
        tabs::TabInterface::MaybeGetFromContents(first_contents_.get()) !=
            first_tab_.get() ||
        tabs::TabInterface::MaybeGetFromContents(second_contents_.get()) !=
            second_tab_.get() ||
        first_tab_->GetBrowserWindowInterface() != browser_.get() ||
        second_tab_->GetBrowserWindowInterface() != browser_.get() ||
        browser_->GetProfile() != profile_.get() ||
        first_contents_->GetBrowserContext() != profile_.get() ||
        second_contents_->GetBrowserContext() != profile_.get() ||
        binding_.window != window_ || !window_.visible ||
        first_.nativeView.window != window_ ||
        second_.nativeView.window != window_) {
      return false;
    }
    return !documents ||
           (first_contents_->GetPrimaryMainFrame() &&
            second_contents_->GetPrimaryMainFrame() &&
            first_contents_->GetPrimaryMainFrame()->IsRenderFrameLive() &&
            second_contents_->GetPrimaryMainFrame()->IsRenderFrameLive() &&
            first_document_.AsRenderFrameHostIfValid() ==
                first_contents_->GetPrimaryMainFrame() &&
            second_document_.AsRenderFrameHostIfValid() ==
                second_contents_->GetPrimaryMainFrame() &&
            first_contents_->GetLastCommittedURL() ==
                GURL(document_url_.spec() + "?tab=first") &&
            second_contents_->GetLastCommittedURL() ==
                GURL(document_url_.spec() + "?tab=second"));
  }
  bool Select(PCNativePage* page) {
    if (!Identity() || !select_(page) || !Identity()) {
      return false;
    }
    return browser_->GetActiveTabInterface() ==
           (page == first_ ? first_tab_.get() : second_tab_.get());
  }
  bool ActivateFromEngine(PCNativePage* page) {
    if (!Identity()) {
      return false;
    }
    auto* list = TabListInterface::From(browser_.get());
    if (!list) {
      return false;
    }
    // tabs.update uses this same real tab-list operation. Do not ask the test
    // shell to select the page: production must publish that change itself.
    list->ActivateTab((page == first_ ? first_tab_ : second_tab_)->GetHandle());
    if (!Identity() ||
        browser_->GetActiveTabInterface() !=
            (page == first_ ? first_tab_.get() : second_tab_.get())) {
      return false;
    }
    [binding_ synchronizeLayout];
    return Identity() &&
           browser_->GetActiveTabInterface() ==
               (page == first_ ? first_tab_.get() : second_tab_.get());
  }
  void CheckSelectionAfterUnwind(int step) {
    std::weak_ptr<ExtensionRun> weak = shared_from_this();
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(
                       [](std::weak_ptr<ExtensionRun> weak, int step) {
                         if (auto self = weak.lock()) {
                           self->CheckSelection(step);
                         }
                       },
                       weak, step));
  }
  void CheckSelection(int step) {
    auto keep = shared_from_this();
    PCNativePage* expected = step == 0 ? second_ : first_;
    if (!Identity() ||
        browser_->GetActiveTabInterface() !=
            (expected == first_ ? first_tab_.get() : second_tab_.get()) ||
        [binding_.client selectedNativePage] != expected || !Identity() ||
        ![[binding_.client visibleNativePages] containsObject:expected] ||
        !Identity()) {
      Finish(false, @"Engine selection was lost or not published to the exact "
                    @"native page after observer unwind.");
      return;
    }
    bool changed = false;
    switch (step) {
      case 0:
        changed = ActivateFromEngine(first_);
        break;
      case 1:
        // Only the latest real selection may reach the shell after coalescing.
        changed = ActivateFromEngine(second_) && ActivateFromEngine(first_);
        break;
      case 2:
        // A newer user command wins over an older queued engine notification.
        changed = ActivateFromEngine(second_) && Select(first_);
        break;
      case 3:
        selection_probe_complete_ = true;
        std::fprintf(stdout,
                     "NATIVE_ENGINE_SELECTION_PASS exact_page=true "
                     "deferred=true geometry_preserved=true latest_wins=true "
                     "shell_override=true\n");
        std::fflush(stdout);
        Poll();
        return;
      default:
        Finish(false, @"Unknown engine-selection regression step.");
        return;
    }
    if (!changed) {
      Finish(false, @"Real engine selection changed ownership or layout "
                    @"reselected a stale page.");
      return;
    }
    CheckSelectionAfterUnwind(step + 1);
  }
  PCNativeExtensionAction* Snapshot(PCNativePage* page) {
    if (!Identity() || !extension_) {
      return nil;
    }
    NSString* identifier =
        [NSString stringWithUTF8String:extension_->id().c_str()];
    for (PCNativeExtensionAction* value in
         [binding_ extensionActionsForPage:page]) {
      if ([value.identifier isEqual:identifier]) {
        return value;
      }
    }
    return nil;
  }
  bool HasGrant(content::WebContents* contents) const {
    auto* granter =
        extensions::ActiveTabPermissionGranter::FromWebContents(contents);
    return granter && granter->IsGranted(extension_.get());
  }
  bool HasHost(content::WebContents* contents) const {
    return extension_->permissions_data()->CanAccessPage(
        contents->GetLastCommittedURL(),
        sessions::SessionTabHelper::IdForTab(contents).id(), nullptr);
  }
  bool HasOtherOrigin() const {
    GURL::Replacements replacement;
    replacement.SetHostStr("localhost");
    return extension_->permissions_data()->CanAccessPage(
        document_url_.ReplaceComponents(replacement),
        sessions::SessionTabHelper::IdForTab(first_contents_.get()).id(),
        nullptr);
  }
  void Poll() {
    auto keep = shared_from_this();
    if (!Identity(loading_extension_)) {
      Finish(false, @"Real extension page or document ownership changed.");
      return;
    }
    if (!loading_extension_) {
      if (first_contents_->IsLoading() || second_contents_->IsLoading() ||
          first_contents_->GetLastCommittedURL() !=
              GURL(document_url_.spec() + "?tab=first") ||
          second_contents_->GetLastCommittedURL() !=
              GURL(document_url_.spec() + "?tab=second")) {
        SetStage("waiting-documents");
        return;
      }
      auto* first_frame = first_contents_->GetPrimaryMainFrame();
      auto* second_frame = second_contents_->GetPrimaryMainFrame();
      if (!first_frame || !second_frame || !first_frame->IsRenderFrameLive() ||
          !second_frame->IsRenderFrameLive()) {
        SetStage("waiting-live-frames");
        return;
      }
      first_document_ = first_frame->GetWeakDocumentPtr();
      second_document_ = second_frame->GetWeakDocumentPtr();
      if (!Select(first_)) {
        Finish(false, @"Actual first tab could not be selected.");
        return;
      }
      loading_extension_ = true;
      SetStage("enabling-developer-mode");
      // Match chrome://extensions' normal developer-mode setup on this
      // disposable profile. A successful unpacked installer callback can still
      // describe an extension kept disabled by management policy.
      if (profile_->GetPrefs()->IsManagedPreference(
              prefs::kExtensionsUIDeveloperMode)) {
        Finish(false, @"Developer mode is controlled by policy.");
        return;
      }
      extensions::util::SetDeveloperModeForProfile(profile_.get(), true);
      if (!Identity() || !profile_->GetPrefs()->GetBoolean(
                             prefs::kExtensionsUIDeveloperMode)) {
        Finish(false, @"Normal extension developer mode could not be enabled.");
        return;
      }
      NSString* path = [NSBundle.mainBundle.resourcePath
          stringByAppendingPathComponent:@"NativeExtensionActionFixture"];
      installer_ = extensions::UnpackedInstaller::Create(profile_.get());
      std::weak_ptr<ExtensionRun> weak = keep;
      installer_->set_completion_callback(base::BindOnce(
          [](std::weak_ptr<ExtensionRun> weak,
             const extensions::Extension* extension, const base::FilePath&,
             const std::u16string&) {
            if (auto self = weak.lock()) {
              self->SetStage("installer-callback");
              if (!self->Identity() || !extension) {
                self->Finish(false,
                             @"Real unpacked extension installation failed.");
                return;
              }
              self->extension_ = extension;
            }
          },
          weak));
      // The production installer owns its normal asynchronous load operations.
      // Completion never installs a substitute model or grants permission.
      SetStage("waiting-installer-completion");
      installer_->Load(base::FilePath(path.fileSystemRepresentation));
      return;
    }
    if (!extension_) {
      return;
    }
    auto* registry = extensions::ExtensionRegistry::Get(profile_.get());
    const auto* installed = registry->GetInstalledExtension(extension_->id());
    if (!installed) {
      Finish(false,
             @"Completed unpacked installation is absent from registry.");
      return;
    }
    if (installed != extension_.get()) {
      Finish(false, @"Loaded extension instance changed.");
      return;
    }
    if (registry->enabled_extensions().GetByID(extension_->id()) !=
        extension_.get()) {
      Finish(false, @"Installed extension is disabled, blocked or terminated.");
      return;
    }
    if (selection_probe_started_ && !selection_probe_complete_) {
      return;
    }
    SetStage("waiting-action-snapshot");
    PCNativeExtensionAction* initial = Snapshot(first_);
    if (!initial) {
      return;  // Real toolbar model population is asynchronous.
    }
    if (!selection_probe_started_) {
      selection_probe_started_ = true;
      SetStage("checking-engine-selection");
      if ([binding_.client selectedNativePage] != first_ || !Identity() ||
          !ActivateFromEngine(second_) ||
          [binding_.client selectedNativePage] != first_) {
        Finish(false, @"Engine selection was echoed synchronously or layout "
                      @"overwrote it before observer unwind.");
        return;
      }
      CheckSelectionAfterUnwind(0);
      return;
    }
    poll_.Stop();
    SetStage("exercising-actions");
    Exercise(initial);
  }
  void Exercise(PCNativeExtensionAction* initial) {
    auto keep = shared_from_this();
    if (!Identity()) {
      Finish(false,
             @"Page ownership changed before the first action assertion.");
      return;
    }
    auto* toolbar = ToolbarActionsModel::Get(profile_.get());
    if (!toolbar || !initial.enabled || !initial.canChangePin ||
        ![initial.pageIdentifier isEqual:first_.identifier] ||
        ![initial.profilePath isEqual:first_.profilePath] ||
        ![initial.name isEqual:@"Parc runtime action"] ||
        HasGrant(first_contents_.get()) || HasGrant(second_contents_.get()) ||
        HasHost(first_contents_.get()) || HasHost(second_contents_.get())) {
      Finish(false,
             @"Initial snapshot or ungranted origin precondition failed.");
      return;
    }
    const BOOL was_pinned = initial.pinned;
    if (![binding_ setExtensionAction:initial
                               pinned:!was_pinned
                              forPage:first_] ||
        !Identity()) {
      Finish(false, @"Actual action pin operation was refused.");
      return;
    }
    PCNativeExtensionAction* pinned = Snapshot(first_);
    toolbar = ToolbarActionsModel::Get(profile_.get());
    if (!pinned || pinned.pinned == was_pinned ||
        initial.pinned != was_pinned ||
        toolbar->IsActionPinned(extension_->id()) != !was_pinned ||
        (!pinned.pinned && pinned.pinnedIndex != NSNotFound) ||
        (pinned.pinned &&
         (pinned.pinnedIndex == NSNotFound ||
          pinned.pinnedIndex >= toolbar->pinned_action_ids().size() ||
          toolbar->pinned_action_ids()[pinned.pinnedIndex] !=
              extension_->id()))) {
      Finish(false, @"Snapshot copy/pin order disagreed with the real model.");
      return;
    }
    if (![binding_ setExtensionAction:pinned
                               pinned:was_pinned
                              forPage:first_] ||
        !Identity() ||
        ToolbarActionsModel::Get(profile_.get())
                ->IsActionPinned(extension_->id()) != was_pinned) {
      Finish(false, @"Original real pin state was not restored.");
      return;
    }
    PCNativeExtensionAction* restored = Snapshot(first_);
    toolbar = ToolbarActionsModel::Get(profile_.get());
    if (!restored || restored.pinned != was_pinned ||
        (!restored.pinned && restored.pinnedIndex != NSNotFound) ||
        (restored.pinned &&
         (restored.pinnedIndex == NSNotFound ||
          restored.pinnedIndex >= toolbar->pinned_action_ids().size() ||
          toolbar->pinned_action_ids()[restored.pinnedIndex] !=
              extension_->id()))) {
      Finish(false, @"Restored snapshot disagreed with actual pin order.");
      return;
    }
    std::fprintf(stdout, "NATIVE_EXTENSION_SNAPSHOT_PASS real_profile=true "
                         "copied=true pin_model=true pin_order=true\n");
    std::fflush(stdout);
    PCNativeExtensionAction* stale = Snapshot(first_);
    if (!stale || !Select(second_) ||
        [binding_ extensionActionsForPage:first_].count ||
        [binding_ executeExtensionAction:stale forPage:first_] || !Identity() ||
        [binding_ setExtensionAction:stale pinned:!was_pinned forPage:first_] ||
        !Identity() || !Select(first_) ||
        [binding_ executeExtensionAction:stale forPage:first_] || !Identity() ||
        [binding_ setExtensionAction:stale pinned:!was_pinned forPage:first_] ||
        !Identity() ||
        ToolbarActionsModel::Get(profile_.get())
                ->IsActionPinned(extension_->id()) != was_pinned ||
        HasGrant(first_contents_.get()) || HasGrant(second_contents_.get()) ||
        HasHost(first_contents_.get()) || HasHost(second_contents_.get())) {
      Finish(false,
             @"Unselected or stale action was accepted or granted access.");
      return;
    }
    std::fprintf(
        stdout,
        "NATIVE_EXTENSION_SELECTION_PASS unselected_empty=true "
        "stale_execute_rejected=true stale_pin_rejected=true no_grant=true\n");
    std::fflush(stdout);
    PCNativeExtensionAction* current = Snapshot(first_);
    if (!current || ![binding_ executeExtensionAction:current forPage:first_] ||
        !Identity() || !HasGrant(first_contents_.get()) ||
        HasGrant(second_contents_.get()) || !HasHost(first_contents_.get()) ||
        HasHost(second_contents_.get()) || HasOtherOrigin()) {
      Finish(false,
             @"Genuine action did not grant only the selected tab/origin.");
      return;
    }
    std::fprintf(stdout, "NATIVE_EXTENSION_GRANT_PASS real_action=true "
                         "selected_tab=true loopback_host=true "
                         "other_tab_denied=true other_origin_denied=true\n");
    std::fflush(stdout);
    Finish(true, @"Actual native action snapshots, pinning, stale selection "
                 @"and activeTab host scope passed.");
  }
  void Finish(bool passed, NSString* detail) {
    if (done_) {
      return;
    }
    auto keep = shared_from_this();
    done_ = true;
    deadline_.Stop();
    poll_.Stop();
    select_ = nil;
    // Do not unload the Profile or extension from within its completion/model
    // callbacks. The existing aggregate Browser close and CefShutdown own them.
    if (ActiveExtensions().get() == this) {
      ActiveExtensions().reset();
    }
    auto callback = finished_;
    finished_ = nil;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(^{
          callback(passed, detail);
        }));
  }
  PCNativePage* __strong first_;
  PCNativePage* __strong second_;
  PCNativeBrowserWindow* __strong binding_;
  NSWindow* __strong window_;
  const GURL document_url_;
  BOOL (^select_)(PCNativePage*);
  void (^finished_)(BOOL, NSString*);
  base::WeakPtr<content::WebContents> first_contents_, second_contents_;
  base::WeakPtr<tabs::TabInterface> first_tab_, second_tab_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  content::WeakDocumentPtr first_document_, second_document_;
  scoped_refptr<extensions::UnpackedInstaller> installer_;
  scoped_refptr<const extensions::Extension> extension_;
  base::OneShotTimer deadline_;
  base::RepeatingTimer poll_;
  bool loading_extension_ = false;
  bool selection_probe_started_ = false;
  bool selection_probe_complete_ = false;
  bool done_ = false;
  base::TimeTicks diagnostic_started_;
  std::string diagnostic_stage_;
};
}  // namespace
extern "C" PARC_RUNTIME_TEST_EXPORT void parc_test_extension_actions(
    PCNativePage* first,
    PCNativePage* second,
    PCNativeBrowserWindow* binding,
    NSString* loopback_document,
    BOOL (^select_page)(PCNativePage*),
    void (^finished)(BOOL, NSString*)) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(finished);
  if (Active() || ActiveExtensions() || HasActiveVideoPiP() || !select_page ||
      !loopback_document) {
    finished(NO, @"Invalid or overlapping extension suite.");
    return;
  }
  auto run = std::make_shared<ExtensionRun>(
      first, second, binding, loopback_document, select_page, finished);
  ActiveExtensions() = run;
  run->Start();
}
extern "C" PARC_RUNTIME_TEST_EXPORT void parc_test_cancel_extension_actions() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (auto run = ActiveExtensions()) {
    run->Cancel();
  }
}

namespace {
class VideoPiPRun;
std::shared_ptr<VideoPiPRun>& ActiveVideoPiP() {
  static base::NoDestructor<std::shared_ptr<VideoPiPRun>> run;
  return *run;
}
bool HasActiveVideoPiP() {
  return !!ActiveVideoPiP();
}
constexpr const char* kPiPCases[] = {"close_pauses",
                                     "hide_keeps_playback",
                                     "native_close_destroys",
                                     "reentry_keeps_identity",
                                     "return_original_without_pause",
                                     "resize_notifies_session",
                                     "compositor_bounds"};

class VideoPiPRun final : public content::WebContentsObserver,
                          public std::enable_shared_from_this<VideoPiPRun> {
 public:
  VideoPiPRun(PCNativePage* page,
              PCNativeBrowserWindow* binding,
              NSString* media,
              id<PCNativeVideoPiPWindow> (^presenter)(void),
              void (^finished)(BOOL, NSString*))
      : page_(page),
        binding_(binding),
        window_(binding.window),
        observer_(page.observer),
        media_(media.UTF8String),
        presenter_([presenter copy]),
        finished_([finished copy]) {
    if (auto* contents = parc::ContentsForNativePage(page)) {
      Observe(contents);
      contents_ = contents->GetWeakPtr();
      if (auto* tab = tabs::TabInterface::MaybeGetFromContents(contents)) {
        tab_ = tab->GetWeakPtr();
        if (auto* browser = tab->GetBrowserWindowInterface()) {
          browser_ = browser->GetWeakPtr();
          profile_ = browser->GetProfile()->GetWeakPtr();
        }
      }
    }
  }
  void Start() {
    auto keep = shared_from_this();
    if (!Identity(false) || !IsDisposableHarnessProfile(profile_.get()) ||
        !media_.SchemeIs("http") || media_.host() != "127.0.0.1" ||
        !media_.has_port() || media_.path() != "/bear.webm" ||
        media_.has_query() || media_.has_ref() || media_.has_username() ||
        media_.has_password() ||
        !parc::UsesNativeVideoPictureInPicture(contents_.get())) {
      Finish(false, @"Invalid real native PiP fixture identity.");
      return;
    }
    auto owned = [this](BrowserCollection* collection) {
      bool found = false;
      collection->ForEach([&](BrowserWindowInterface* browser) {
        found = browser == browser_.get();
        return !found;
      });
      return found;
    };
    if (!owned(ProfileBrowserCollection::GetForProfile(profile_.get())) ||
        !owned(GlobalBrowserCollection::GetInstance())) {
      Finish(false, @"PiP Browser registration is not published.");
      return;
    }
    std::fprintf(stdout, "NATIVE_REGISTRATION_PASS manager=true global=true "
                         "tab=true supplied_window=true\n");
    std::fflush(stdout);
    ArmDeadline();
    std::weak_ptr<VideoPiPRun> weak = keep;
    poll_.Start(FROM_HERE, base::Milliseconds(25),
                base::BindRepeating(
                    [](std::weak_ptr<VideoPiPRun> weak) {
                      if (auto self = weak.lock()) {
                        self->WaitForDocument();
                      }
                    },
                    weak));
    WaitForDocument();
  }
  void Cancel() { Finish(false, @"PiP suite cancelled."); }
  void WebContentsDestroyed() override {
    destroying_ = true;
    Finish(false, @"Original PiP WebContents destroyed.");
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (document_.AsRenderFrameHostIfValid() &&
        navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument()) {
      Finish(false, @"Original PiP document began replacement navigation.");
    }
  }

 private:
  bool Identity(bool document = true) const {
    if (done_ || destroying_ || !contents_ || !tab_ || !browser_ || !profile_ ||
        !page_ || page_.closed || !binding_ || !window_ ||
        binding_.window != window_ || page_.observer != observer_ ||
        !observer_ || page_.nativeView.window != window_ ||
        parc::ContentsForNativePage(page_) != contents_.get() ||
        tabs::TabInterface::MaybeGetFromContents(contents_.get()) !=
            tab_.get() ||
        tab_->GetBrowserWindowInterface() != browser_.get() ||
        browser_->GetProfile() != profile_.get() || !tab_->IsActivated() ||
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() !=
            window_) {
      return false;
    }
    if (!document) {
      return true;
    }
    auto* frame = document_.AsRenderFrameHostIfValid();
    return frame && frame == contents_->GetPrimaryMainFrame() &&
           frame->IsRenderFrameLive() && frame->GetLastCommittedURL() == media_;
  }
  content::VideoPictureInPictureWindowController* Controller() {
    return content::PictureInPictureWindowController::
        GetOrCreateVideoPictureInPictureController(contents_.get());
  }
  id<PCNativeVideoPiPWindow> Presenter() {
    return presenter_ ? presenter_() : nil;
  }
  void ArmDeadline() {
    std::weak_ptr<VideoPiPRun> weak = shared_from_this();
    deadline_.Start(
        FROM_HERE, base::Seconds(15),
        base::BindOnce(
            [](std::weak_ptr<VideoPiPRun> weak) {
              if (auto self = weak.lock()) {
                std::fprintf(stderr, "NATIVE_PIP_DEADLINE case=%d phase=%s\n",
                             self->case_, self->phase_);
                self->Finish(false, @"PiP controller deadline.");
              }
            },
            weak));
  }
  void WaitForDocument() {
    auto keep = shared_from_this();
    if (!Identity(false)) {
      Finish(false, @"PiP native page detached before readiness.");
      return;
    }
    auto* frame = contents_->GetPrimaryMainFrame();
    if (contents_->IsLoading() || !frame || !frame->IsRenderFrameLive() ||
        frame->GetLastCommittedURL() != media_) {
      return;
    }
    document_ = frame->GetWeakDocumentPtr();
    poll_.Stop();
    Open();
  }
  // The supported public API supplies test user activation once. It does not
  // await Promises, so keep a unique record on this exact test document and
  // observe completion/rejection with the non-activation public test API.
  // Every actual play/request/exit/resize operation still executes in Blink.
  void JS(const std::string& script,
          base::OnceCallback<void(base::Value)> next) {
    if (!Identity()) {
      Finish(false, @"PiP script lost its original document.");
      return;
    }
    script_poll_.Stop();
    const uint64_t generation = ++script_generation_;
    script_next_ = std::move(next);
    script_query_pending_ = false;
    std::weak_ptr<VideoPiPRun> weak = shared_from_this();
    const std::string program =
        "(() => { const key = '" + script_key_ +
        "'; "
        "if (Object.prototype.hasOwnProperty.call(window,key)) return false; "
        "const record = {state:'pending'}; "
        "Object.defineProperty(window,key,{value:record,configurable:true}); "
        "(async () => { try { const value = await (" +
        script +
        "); "
        "if (window[key] === record) { record.value = value ?? null; "
        "record.state='ok'; } "
        "} catch (_) { if (window[key] === record) record.state='rejected'; } "
        "})(); "
        "return true; })()";
    document_.AsRenderFrameHostIfValid()
        ->ExecuteJavaScriptWithUserGestureForTests(
            base::UTF8ToUTF16(program),
            base::BindOnce(
                [](std::weak_ptr<VideoPiPRun> weak, uint64_t generation,
                   base::Value value) {
                  base::SingleThreadTaskRunner::GetCurrentDefault()
                      ->PostNonNestableTask(
                          FROM_HERE,
                          base::BindOnce(
                              [](std::weak_ptr<VideoPiPRun> weak,
                                 uint64_t generation, base::Value value) {
                                auto self = weak.lock();
                                if (!self || self->done_ ||
                                    generation != self->script_generation_) {
                                  return;
                                }
                                if (!self->Identity() || !value.is_bool() ||
                                    !value.GetBool()) {
                                  self->Finish(
                                      false, @"PiP async script did not start "
                                             @"on its original document.");
                                  return;
                                }
                                self->script_poll_.Start(
                                    FROM_HERE, base::Milliseconds(25),
                                    base::BindRepeating(
                                        [](std::weak_ptr<VideoPiPRun> weak,
                                           uint64_t generation) {
                                          if (auto self = weak.lock()) {
                                            self->PollScript(generation);
                                          }
                                        },
                                        weak, generation));
                                self->PollScript(generation);
                              },
                              weak, generation, std::move(value)));
                },
                weak, generation),
            content::ISOLATED_WORLD_ID_GLOBAL);
  }
  void PollScript(uint64_t generation) {
    if (done_ || generation != script_generation_ || script_query_pending_) {
      return;
    }
    if (!Identity()) {
      Finish(false, @"PiP Promise lost its original document.");
      return;
    }
    script_query_pending_ = true;
    std::weak_ptr<VideoPiPRun> weak = shared_from_this();
    const std::string program =
        "(() => { const key='" + script_key_ +
        "', r=window[key]; "
        "if(!r) return {state:'missing'}; if(r.state==='pending') return "
        "{state:'pending'}; "
        "delete window[key]; return {state:r.state,value:r.value}; })()";
    document_.AsRenderFrameHostIfValid()->ExecuteJavaScriptForTests(
        base::UTF8ToUTF16(program),
        base::BindOnce(
            [](std::weak_ptr<VideoPiPRun> weak, uint64_t generation,
               base::Value value) {
              base::SingleThreadTaskRunner::GetCurrentDefault()
                  ->PostNonNestableTask(
                      FROM_HERE,
                      base::BindOnce(
                          [](std::weak_ptr<VideoPiPRun> weak,
                             uint64_t generation, base::Value value) {
                            auto self = weak.lock();
                            if (!self || self->done_ ||
                                generation != self->script_generation_) {
                              return;
                            }
                            self->script_query_pending_ = false;
                            if (!self->Identity() || !value.is_dict()) {
                              self->Finish(false, @"PiP Promise query lost its "
                                                  @"document or result.");
                              return;
                            }
                            const std::string* state =
                                value.GetDict().FindString("state");
                            if (state && *state == "pending") {
                              return;
                            }
                            self->script_poll_.Stop();
                            const base::Value* result =
                                value.GetDict().Find("value");
                            if (!state || *state != "ok" || !result) {
                              self->Finish(false,
                                           @"PiP Promise rejected or its exact "
                                           @"record disappeared.");
                              return;
                            }
                            auto next = std::move(self->script_next_);
                            std::move(next).Run(result->Clone());
                          },
                          weak, generation, std::move(value)));
            },
            weak, generation),
        content::ISOLATED_WORLD_ID_GLOBAL);
  }
  void Open() {
    auto keep = shared_from_this();
    phase_ = "opening";
    ArmDeadline();
    JS(R"((async () => {
      if (document.pictureInPictureElement) await document.exitPictureInPicture();
      const v = document.querySelector('video');
      if (!v) throw Error('missing video');
      v.muted = true; v.loop = true; await v.play();
      if(window[key] !== record) throw Error('cancelled');
      window.pipWindow = await v.requestPictureInPicture(); return true;
    })())",
       base::BindOnce(
           [](std::shared_ptr<VideoPiPRun> keep, base::Value value) {
             id<PCNativeVideoPiPWindow> presenter = keep->Presenter();
             if (!value.is_bool() || !value.GetBool() || !keep->Identity() ||
                 !presenter || presenter.invalidated ||
                 !presenter.panel.visible ||
                 !keep->Controller()->GetWindowForTesting() ||
                 !keep->Controller()->GetWindowForTesting()->IsVisible()) {
               keep->Finish(false,
                            @"Real DOM PiP did not show the native presenter.");
               return;
             }
             keep->phase_ = "asserting";
             keep->AssertCase(presenter);
           },
           keep));
  }
  bool Click(id<PCNativeVideoPiPWindow> presenter, PCVideoPiPAction action) {
    NSView* view = presenter.panel.contentView;
    if (!view) {
      Finish(false, @"Actual PiP panel content is absent.");
      return false;
    }
    NSButton* button = nil;
    NSMutableArray<NSView*>* pending = [NSMutableArray arrayWithObject:view];
    while (pending.count) {
      NSView* current = pending.lastObject;
      [pending removeLastObject];
      if ([current isKindOfClass:NSButton.class] && current.tag == action) {
        button = (NSButton*)current;
        break;
      }
      [pending addObjectsFromArray:current.subviews];
    }
    if (!button || button.hidden || !button.enabled || !Identity() ||
        Presenter() != presenter) {
      Finish(false, @"Actual PiP control unavailable.");
      return false;
    }
    [button performClick:nil];
    if (!Identity()) {
      Finish(false, @"PiP control changed source identity.");
      return false;
    }
    return true;
  }
  void AssertCase(id<PCNativeVideoPiPWindow> presenter) {
    auto keep = shared_from_this();
    switch (case_) {
      case 0:
        if (!Click(presenter, PCVideoPiPClose)) {
          return;
        }
        JS(R"(new Promise(r => { const v=document.querySelector('video');
          if(v.paused)r(true);else v.addEventListener('pause',()=>r(true),{once:true}); }))",
           base::BindOnce(
               [](std::shared_ptr<VideoPiPRun> keep, base::Value v) {
                 keep->Check(v.is_bool() && v.GetBool() && keep->Hidden());
               },
               keep));
        return;
      case 1:
        Controller()
            ->GetWindowForTesting()
            ->SetHidePictureInPictureButtonVisibility(true);
        if (!Identity()) {
          Finish(false, @"Hide capability changed source identity.");
          return;
        }
        if (!Click(presenter, PCVideoPiPMinimize)) {
          return;
        }
        CheckUnpaused();
        return;
      case 2: {
        NSPanel* panel = presenter.panel;
        [panel close];
        if (!Identity()) {
          Finish(false, @"Native close changed source identity.");
          return;
        }
        Check(!Controller()->GetWindowForTesting() && !panel.visible &&
              !Presenter());
        return;
      }
      case 3:
      case 6:
        original_video_ = presenter.videoView;
        original_overlay_ = Controller()->GetWindowForTesting();
        if (case_ == 6) {
          if (!LayerFills()) {
            Finish(false, @"Initial compositor bounds differ.");
            return;
          }
          original_layer_ = original_video_.layer.sublayers.firstObject;
          [presenter.panel setContentSize:NSMakeSize(640, 360)];
          if (!Identity() || !LayerFills()) {
            Finish(false, @"Resized compositor bounds differ.");
            return;
          }
        }
        JS("document.exitPictureInPicture().then(() => true)",
           base::BindOnce(
               [](std::shared_ptr<VideoPiPRun> keep, base::Value) {
                 keep->JS(
                     "document.querySelector('video').requestPictureInPicture()"
                     ".then(() => true)",
                     base::BindOnce(
                         [](std::shared_ptr<VideoPiPRun> keep, base::Value) {
                           id<PCNativeVideoPiPWindow> current =
                               keep->Presenter();
                           keep->Check(
                               current &&
                               current.videoView == keep->original_video_ &&
                               keep->Controller()->GetWindowForTesting() ==
                                   keep->original_overlay_ &&
                               (keep->case_ != 6 ||
                                (keep->LayerFills() &&
                                 current.videoView.layer.sublayers
                                         .firstObject ==
                                     keep->original_layer_)));
                         },
                         keep));
               },
               keep));
        return;
      case 4:
        if (!Click(presenter, PCVideoPiPReturn)) {
          return;
        }
        CheckUnpaused();
        return;
      case 5:
        // Install the real JS resize observer before native resizing. Avoid
        // awaiting the resize promise until after the actual panel change.
        JS(R"((() => { window.pipResize = new Promise(resolve => {
          pipWindow.addEventListener('resize', () => {
            resolve([pipWindow.width,pipWindow.height].join(','));
          }, {once:true}); }); return true; })())",
           base::BindOnce(
               [](std::shared_ptr<VideoPiPRun> keep, base::Value) {
                 id<PCNativeVideoPiPWindow> current = keep->Presenter();
                 if (!current) {
                   keep->Finish(false, @"Resize presenter disappeared.");
                   return;
                 }
                 [current.panel setContentSize:NSMakeSize(640, 360)];
                 keep->JS(
                     "pipResize",
                     base::BindOnce(
                         [](std::shared_ptr<VideoPiPRun> keep, base::Value v) {
                           keep->Check(v.is_string() &&
                                       v.GetString() == "640,360");
                         },
                         keep));
               },
               keep));
        return;
    }
    Finish(false, @"Unknown PiP case.");
  }
  bool Hidden() {
    auto* window = Controller()->GetWindowForTesting();
    return window && !window->IsVisible();
  }
  bool LayerFills() {
    NSView* view = Presenter().videoView;
    return view && view.layer && view.layer.sublayers.count == 1 &&
           view.layer.sublayers.firstObject.geometryFlipped &&
           NSWidth(view.bounds) > 0 && NSHeight(view.bounds) > 0 &&
           CGRectEqualToRect(view.layer.sublayers.firstObject.bounds,
                             view.layer.bounds);
  }
  void CheckUnpaused() {
    auto keep = shared_from_this();
    JS("document.querySelector('video').paused",
       base::BindOnce(
           [](std::shared_ptr<VideoPiPRun> keep, base::Value v) {
             keep->Check(v.is_bool() && !v.GetBool() && keep->Hidden());
           },
           keep));
  }
  void Check(bool passed) {
    if (!Identity() || !passed) {
      Finish(false, @"Actual PiP controller assertion failed.");
      return;
    }
    auto keep = shared_from_this();
    phase_ = "cleanup";
    JS(R"((async () => {
      if(document.pictureInPictureElement) await document.exitPictureInPicture();
      return !document.pictureInPictureElement;
    })())",
       base::BindOnce(
           [](std::shared_ptr<VideoPiPRun> keep, base::Value value) {
             auto* overlay = keep->Controller()->GetWindowForTesting();
             if (!value.is_bool() || !value.GetBool() ||
                 (overlay && overlay->IsVisible())) {
               keep->Finish(false, @"Actual PiP case cleanup did not exit.");
               return;
             }
             std::fprintf(stdout, "NATIVE_PIP_CASE_%d PASS: %s\n", keep->case_,
                          kPiPCases[keep->case_]);
             std::fflush(stdout);
             keep->original_video_ = nil;
             keep->original_layer_ = nil;
             keep->original_overlay_ = nullptr;
             if (++keep->case_ == 7) {
               keep->Finish(true,
                            @"Seven real native PiP controller cases passed.");
             } else {
               keep->Open();
             }
           },
           keep));
  }
  void Finish(bool passed, NSString* detail) {
    if (done_) {
      return;
    }
    auto keep = shared_from_this();
    const bool can_clean = Identity();
    done_ = true;
    ++script_generation_;
    deadline_.Stop();
    poll_.Stop();
    script_poll_.Stop();
    script_next_.Reset();
    if (can_clean) {
      document_.AsRenderFrameHostIfValid()->ExecuteJavaScriptForTests(
          base::UTF8ToUTF16("delete window['" + script_key_ + "']"),
          base::BindOnce([](base::Value) {}),
          content::ISOLATED_WORLD_ID_GLOBAL);
    }
    Observe(nullptr);
    // Retire only our exact source controller. On replacement/destruction the
    // real WebContents lifecycle owns cleanup; never act on a replacement.
    if (can_clean && Controller()->GetWindowForTesting()) {
      Controller()->Close(false);
    }
    original_video_ = nil;
    original_layer_ = nil;
    original_overlay_ = nullptr;
    presenter_ = nil;
    auto callback = finished_;
    finished_ = nil;
    if (ActiveVideoPiP().get() == this) {
      ActiveVideoPiP().reset();
    }
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(^{
          callback(passed, detail);
        }));
  }
  PCNativePage* __strong page_;
  PCNativeBrowserWindow* __strong binding_;
  NSWindow* __strong window_;
  id<PCNativePageObserver> __weak observer_;
  const GURL media_;
  id<PCNativeVideoPiPWindow> (^presenter_)(void);
  void (^finished_)(BOOL, NSString*);
  base::WeakPtr<content::WebContents> contents_;
  base::WeakPtr<tabs::TabInterface> tab_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  content::WeakDocumentPtr document_;
  base::OneShotTimer deadline_;
  base::RepeatingTimer poll_;
  base::RepeatingTimer script_poll_;
  base::OnceCallback<void(base::Value)> script_next_;
  const std::string script_key_ =
      "parcNativePiP_" + base::Uuid::GenerateRandomV4().AsLowercaseString();
  bool script_query_pending_ = false;
  NSView* __strong original_video_ = nil;
  CALayer* __strong original_layer_ = nil;
  content::VideoOverlayWindow* original_overlay_ = nullptr;
  uint64_t script_generation_ = 0;
  int case_ = 0;
  const char* phase_ = "waiting-document";
  bool done_ = false;
  bool destroying_ = false;
};
}  // namespace
extern "C" PARC_RUNTIME_TEST_EXPORT void parc_test_video_pip(
    PCNativePage* page,
    PCNativeBrowserWindow* binding,
    NSString* loopback_media,
    id<PCNativeVideoPiPWindow> (^presenter)(void),
    void (^finished)(BOOL, NSString*)) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(finished);
  if (Active() || ActiveExtensions() || ActiveVideoPiP() || !page || !binding ||
      !loopback_media || !presenter) {
    finished(NO, @"Invalid or overlapping PiP suite.");
    return;
  }
  auto run = std::make_shared<VideoPiPRun>(page, binding, loopback_media,
                                           presenter, finished);
  ActiveVideoPiP() = run;
  run->Start();
}
extern "C" PARC_RUNTIME_TEST_EXPORT void parc_test_cancel_video_pip() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (auto run = ActiveVideoPiP()) {
    run->Cancel();
  }
}
