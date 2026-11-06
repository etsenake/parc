#include "extension_install.h"

#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/string_number_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/tab_list/tab_list_interface_observer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/views/extensions/security_dialog_tracker.h"
#include "chrome/common/url_constants.h"
#include "chrome/grit/generated_resources.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "extension_action_container.h"
#include "extension_parent_approval.h"
#import "extension_install_presenter.h"
#include "extension_security_context.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/browser/ui_util.h"
#include "extensions/common/extension.h"
#include "ui/base/base_window.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#import "window_security_reservation.h"
namespace parc {
using Result = extensions::ExtensionInstallPromptClient::Result;
using Payload = extensions::ExtensionInstallPromptClient::DoneCallbackPayload;
using Done = extensions::ExtensionInstallPromptClient::DoneCallback;
class NativeExtensionInstallService::Request final
    : public extensions::ExtensionInstallNativeBinding,
      public std::enable_shared_from_this<Request>,
      public content::WebContentsObserver,
      public TabListInterfaceObserver,
      public extensions::ExtensionRegistryObserver,
      public ProfileObserver,
      public extensions::SecurityDialogTracker::Observer {
 public:
  Request(BrowserWindowInterface& browser,
          NativeExtensionActionHost& host,
          content::WebContents* page,
          bool allowed)
      : browser_(browser.GetWeakPtr()),
        host_(&host),
        window_(host.PopupParentWindow()),
        allowed_(allowed) {
    tabs_ = TabListInterface::From(&browser);
    if (!page && tabs_ && tabs_->GetActiveTab()) {
      page = tabs_->GetActiveTab()->GetContents();
    }
    Observe(page);
    if (page && page->GetPrimaryMainFrame()) {
      document_ = page->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    }
  }
  void StartObserving() {
    auto keep = shared_from_this();
    if (!Valid()) {
      allowed_ = false;
      tabs_ = nullptr;
      return;
    }
    profile_ = browser_->GetProfile();
    registry_ = extensions::ExtensionRegistry::Get(profile_);
    if (tabs_) {
      tabs_->AddTabListInterfaceObserver(this);
    }
    profile_->AddObserver(this);
    registry_->AddObserver(this);
    extensions::SecurityDialogTracker::GetInstance()->AddObserver(this);
    tracking_ = true;
    std::weak_ptr<Request> weak = keep;
    security_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto request = weak.lock();
                      request && !request->acquiring_) {
                    request->CheckContext();
                  }
                }];
    close_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto s = weak.lock()) {
                    s->Invalidate();
                  }
                }];
  }
  ~Request() override {
    CHECK(!presenter_ && !parent_approval_ && !done_);
    StopObserving();
    [reservation_ invalidate];
  }
  bool Owns(content::WebContents* page) const {
    return page && web_contents() == page;
  }
  bool Valid() const {
    if (!allowed_ || !browser_ || browser_->IsDeleteScheduled() || !host_ ||
        !window_ || !window_.visible || window_.miniaturized ||
        !host_->IsSelectedBrowser() || host_->PopupParentWindow() != window_ ||
        !browser_->GetWindow() || browser_->GetProfile()->ShutdownStarted() ||
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() !=
            window_ ||
        extensions::SecurityDialogTracker::GetInstance()
            ->BrowserHasVisibleSecurityDialogs(browser_.get())) {
      return false;
    }
    if (!acquiring_) {
      NSWindow* own_sheet = presenter_.sheet ?: (parent_approval_ ? parent_approval_->sheet() : nil);
      if (host_->HasVisibleBrowserSecurityUIExcluding(own_sheet,
                                                      reservation_)) {
        return false;
      }
      if (window_.attachedSheet && window_.attachedSheet != own_sheet) {
        return false;
      }
      if (reservation_ ? !reservation_.isOnlyReservation
                       : PCNativeWindowHasSecurityReservation(window_)) {
        return false;
      }
    }
    if (web_contents()) {
      auto* tab = tabs::TabInterface::MaybeGetFromContents(web_contents());
      auto* list = TabListInterface::From(browser_.get());
      NSView* view = web_contents()->GetNativeView().GetNativeNSView();
      if (web_contents()->IsBeingDestroyed() ||
          web_contents()->GetVisibility() == content::Visibility::HIDDEN ||
          web_contents()->GetBrowserContext() != browser_->GetProfile() ||
          !document_.AsRenderFrameHostIfValid() ||
          document_.AsRenderFrameHostIfValid() !=
              web_contents()->GetPrimaryMainFrame() ||
          !tab || tab->GetBrowserWindowInterface() != browser_.get() || !list ||
          list->GetActiveTab() != tab || !view || view.window != window_) {
        return false;
      }
    }
    return true;
  }
  bool Begin(const extensions::Extension* extension, Done done) override {
    auto keep = shared_from_this();
    CHECK(!began_ && done);
    began_ = true;
    done_ = std::move(done);
    extension_ = extension;
    if (!extension || !Valid() ||
        PCNativeWindowHasSecurityReservation(window_)) {
      Complete(Result::ABORTED);
      return false;
    }
    auto* registry = extensions::ExtensionRegistry::Get(browser_->GetProfile());
    baseline_ = registry->GetExtensionById(
        extension->id(), extensions::ExtensionRegistry::EVERYTHING);
    acquiring_ = true;
    auto* reservation =
        [PCNativeWindowSecurityReservation acquireForWindow:window_];
    acquiring_ = false;
    if (decided_ || !allowed_) {
      [reservation invalidate];
      Complete(Result::ABORTED);
      return false;
    }
    reservation_ = reservation;
    if (!reservation_.active || !Valid()) {
      Complete(Result::ABORTED);
      return false;
    }
    return true;
  }
  bool CanContinue() const override {
    return began_ && !decided_ && Valid() && reservation_.active;
  }
  void Show(std::unique_ptr<extensions::InstallPromptData> prompt) override {
    auto keep = shared_from_this();
    if (decided_) {
      return;
    }
    CHECK(began_ && !prompt_ && prompt);
    prompt_ = std::move(prompt);
    // Keep the real prompt alive across arbitrary observer reentry. Complete
    // moves it into a non-nestable callback task before marking cancellation.
    prompt_->OnDialogOpened();
    if (decided_ || !Valid()) {
      Complete(Result::ABORTED);
      return;
    }
    auto type = prompt_->type();
    const bool supported =
        type == extensions::InstallPromptData::INSTALL_PROMPT ||
        type == extensions::InstallPromptData::RE_ENABLE_PROMPT ||
        type == extensions::InstallPromptData::PERMISSIONS_PROMPT ||
        type == extensions::InstallPromptData::EXTERNAL_INSTALL_PROMPT ||
        type == extensions::InstallPromptData::REMOTE_INSTALL_PROMPT ||
        type == extensions::InstallPromptData::REPAIR_PROMPT ||
        type == extensions::InstallPromptData::EXTENSION_REQUEST_PROMPT ||
        type == extensions::InstallPromptData::EXTENSION_PENDING_REQUEST_PROMPT ||
        type == extensions::InstallPromptData::EXTENSION_PARENT_APPROVAL_PROMPT;
    const bool pending_request =
        type == extensions::InstallPromptData::EXTENSION_PENDING_REQUEST_PROMPT;
    if (!Valid() || !reservation_.active || !supported ||
        prompt_->extension() != extension_.get() ||
        (!pending_request && prompt_->GetAcceptButtonLabel().empty()) ||
        prompt_->GetAbortButtonLabel().empty()) {
      Complete(Result::ABORTED);
      return;
    }
    auto permissions = prompt_->GetPermissions();
    if (permissions.permissions.size() != permissions.details.size()) {
      Complete(Result::ABORTED);
      return;
    }
    NSMutableArray<NSString*>* messages = [NSMutableArray array];
    NSMutableArray<NSString*>* details = [NSMutableArray array];
    for (size_t i = 0; i < permissions.permissions.size(); ++i) {
      [messages addObject:base::SysUTF16ToNSString(permissions.permissions[i])];
      [details addObject:base::SysUTF16ToNSString(permissions.details[i])];
    }
    // Same actual policy and Web Store branch as the current Views presenter.
    withhold_ = prompt_->ShouldWithheldPermissionsOnDialogAccept() &&
                !prompt_->has_webstore_data();
    std::weak_ptr<Request> weak = keep;
    presenter_ = [[PCExtensionInstallPresenter alloc] initWithWindow:window_
        title:base::SysUTF16ToNSString(prompt_->GetDialogTitle())
        icon:prompt_->icon().IsEmpty() ? nil : prompt_->icon().ToNSImage()
        heading:base::SysUTF16ToNSString(prompt_->GetPermissionsHeading())
        permissions:messages
        details:details
        acceptLabel:base::SysUTF16ToNSString(prompt_->GetAcceptButtonLabel())
        cancelLabel:base::SysUTF16ToNSString(prompt_->GetAbortButtonLabel())
        checkboxLabel:
            withhold_ ? base::SysUTF16ToNSString(l10n_util::GetStringUTF16(
                            IDS_EXTENSION_PROMPT_GRANT_PERMISSIONS_CHECKBOX))
                      : nil
        validate:^BOOL {
          auto s = weak.lock();
          return s && !s->decided_ && s->Valid() && s->reservation_.active;
        }
        inputAllowed:^BOOL(NSWindow* sheet) {
          return InputAllowed(sheet);
        }
        result:^(PCExtensionInstallChoice choice, BOOL grant) {
          if (auto s = weak.lock()) {
            const std::string justification =
                s->prompt_ && s->prompt_->type() ==
                    extensions::InstallPromptData::EXTENSION_REQUEST_PROMPT
                    ? base::SysNSStringToUTF8(s->presenter_.justification)
                    : std::string();
            s->Complete(choice == PCExtensionInstallAccept
                            ? (s->withhold_ && !grant
                                   ? Result::ACCEPTED_WITH_WITHHELD_PERMISSIONS
                                   : Result::ACCEPTED)
                        : choice == PCExtensionInstallCancel
                            ? Result::USER_CANCELED
                            : Result::ABORTED,
                        justification);
          }
        }];
    if (type == extensions::InstallPromptData::INSTALL_PROMPT &&
        !extension_->is_app() && !extension_->is_theme() &&
        !prompt_->requires_parent_permission()) {
      [presenter_ configureInstallationEducationWithName:
          base::SysUTF16ToNSString(
              extensions::ui_util::GetFixupExtensionNameForUIDisplay(extension_->name()))];
    }
    if (type == extensions::InstallPromptData::EXTENSION_REQUEST_PROMPT) {
      [presenter_
          configureJustificationLabel:base::SysUTF16ToNSString(
              l10n_util::GetStringUTF16(
                  IDS_ENTERPRISE_EXTENSION_REQUEST_JUSTIFICATION))
          placeholder:base::SysUTF16ToNSString(l10n_util::GetStringUTF16(
              IDS_ENTERPRISE_EXTENSION_REQUEST_JUSTIFICATION_PLACEHOLDER))
          counterText:^NSString*(NSUInteger length) {
            return base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
                IDS_ENTERPRISE_EXTENSION_REQUEST_JUSTIFICATION_LENGTH_LIMIT,
                base::NumberToString16(length), base::NumberToString16(280)));
          }];
    }
    [presenter_ start];
  }
  void ShowParentApproval(const extensions::Extension* extension,
                          const gfx::ImageSkia& icon, Done done) override {
    auto keep = shared_from_this();
    if (!Begin(extension, std::move(done))) return;
    std::weak_ptr<Request> weak = keep;
    parent_approval_ = NativeExtensionParentApproval::Create(
        browser_->GetProfile(), extension, icon, window_,
        base::BindRepeating([](std::weak_ptr<Request> weak) {
          auto self = weak.lock();
          return self && !self->decided_ && self->Valid() && self->reservation_.active;
        }, weak), base::BindRepeating(&Request::InputAllowed),
        base::BindOnce([](std::weak_ptr<Request> weak, Result result) {
          if (auto self = weak.lock()) self->Complete(result);
        }, weak));
    parent_approval_->Start();
  }
  void Cancel() override { Complete(Result::ABORTED); }
  void Invalidate() {
    auto keep = shared_from_this();
    allowed_ = false;
    Complete(Result::ABORTED);
    [presenter_ invalidate];
    presenter_ = nil;
    [reservation_ invalidate];
    reservation_ = nil;
    StopObserving();
    host_ = nullptr;
  }
  void CheckContext() {
    if (!Valid()) {
      Invalidate();
    }
  }
  void InstallationFinished(const extensions::Extension* extension,
                            bool success,
                            const std::u16string&, const SkBitmap*,
                            bool app_installed_bubble) override {
    auto keep = shared_from_this();
    // Installer results present no native UI. Only a non-bubble app opens the
    // Apps page, reusing an open one in the original window like the engine's
    // own install UI.
    if (result_seen_) {
      return;
    }
    result_seen_ = true;
    if (!success || !extension || !extension->is_app() ||
        app_installed_bubble || !Valid() || !web_contents() ||
        window_.attachedSheet || PCNativeWindowHasSecurityReservation(window_)) {
      return;
    }
    auto params = content::OpenURLParams::CreateBrowserInitiated(
        GURL(chrome::kChromeUIAppsURL), WindowOpenDisposition::SINGLETON_TAB,
        ui::PAGE_TRANSITION_AUTO_BOOKMARK);
    params.user_gesture = true;
    web_contents()->OpenURL(params, {});
  }

 private:
  static bool InputAllowed(NSWindow* sheet) {
    if (!sheet) {
      return false;
    }
    auto bounds = PictureInPictureWindowManager::GetInstance()
                      ->GetPictureInPictureWindowBoundsInScreen();
    return !bounds ||
           !bounds->Intersects(gfx::ScreenRectFromNSRect(sheet.frame));
  }
  void Complete(Result result, std::string justification = {}) {
    auto keep = shared_from_this();
    if (!done_ || decided_) {
      return;
    }
    decided_ = true;
    auto done = std::move(done_);
    auto prompt = std::move(prompt_);
    auto parent_approval = std::move(parent_approval_);
    if (parent_approval) parent_approval->Cancel();
    auto* presenter = std::exchange(presenter_, nil);
    auto* reservation = std::exchange(reservation_, nil);
    [presenter invalidate];
    [reservation invalidate];
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE,
        base::BindOnce(
            [](std::shared_ptr<Request> self, Done done,
               std::unique_ptr<extensions::InstallPromptData> prompt,
               Result result, std::string justification) {
              auto accepted = [&] {
                return result == Result::ACCEPTED ||
                       result == Result::ACCEPTED_WITH_WITHHELD_PERMISSIONS;
              };
              if (!self->Valid() ||
                  PCNativeWindowHasSecurityReservation(self->window_)) {
                result = Result::ABORTED;
              }
              if (prompt) {
                if (accepted()) {
                  prompt->OnDialogAccepted();
                } else {
                  prompt->OnDialogCanceled();
                }
              }
              // Prompt observers can destroy/navigate the page or replace the
              // UI.
              if (accepted() &&
                  (!self->Valid() ||
                   PCNativeWindowHasSecurityReservation(self->window_))) {
                result = Result::ABORTED;
              }
              // A request result returns to Chromium's enterprise controller;
              // it does not install, grant permissions or approve parent access.
              // Never retain submitted text for an aborted/canceled request.
              std::move(done).Run(Payload(
                  result, accepted() ? std::move(justification) : std::string()));
            },
            keep, std::move(done), std::move(prompt), result,
            std::move(justification)));
  }
  void StopObserving() {
    if (tracking_) {
      tracking_ = false;
      extensions::SecurityDialogTracker::GetInstance()->RemoveObserver(this);
    }
    Observe(nullptr);
    if (tabs_ && profile_) {
      tabs_->RemoveTabListInterfaceObserver(this);
    }
    tabs_ = nullptr;
    if (registry_) {
      registry_->RemoveObserver(this);
    }
    registry_ = nullptr;
    if (profile_) {
      profile_->RemoveObserver(this);
    }
    profile_ = nullptr;
    if (close_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:close_observer_];
    }
    close_observer_ = nil;
    if (security_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:security_observer_];
    }
    security_observer_ = nil;
  }
  void OnSecurityDialogAdded(views::Widget* widget) override {
    if (SecurityWidgetBelongsToWindow(widget, window_)) {
      Invalidate();
    }
  }
  void WebContentsDestroyed() override { Invalidate(); }
  void OnVisibilityChanged(content::Visibility) override { CheckContext(); }
  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame() && navigation->HasCommitted() &&
        !navigation->IsSameDocument()) {
      Invalidate();
    }
  }
  void OnActiveTabChanged(TabListInterface&, tabs::TabInterface*) override {
    CheckContext();
  }
  void OnTabRemoved(TabListInterface&,
                    tabs::TabInterface* tab,
                    TabRemovedReason) override {
    if (tab && Owns(tab->GetContents())) {
      Invalidate();
    }
  }
  void OnWebContentsReplaced(TabListInterface&,
                             tabs::TabInterface*,
                             content::WebContents* old,
                             content::WebContents*) override {
    if (Owns(old)) {
      Invalidate();
    }
  }
  void OnTabListDestroyed(TabListInterface&) override {
    tabs_ = nullptr;
    Invalidate();
  }
  void OnExtensionLoaded(content::BrowserContext*,
                         const extensions::Extension* extension) override {
    if (!decided_ && extension_ && extension->id() == extension_->id()) {
      Invalidate();
    }
  }
  void OnExtensionUnloaded(content::BrowserContext*,
                           const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason) override {
    if (!decided_ && baseline_ == extension) {
      Invalidate();
    }
  }
  void OnExtensionUninstalled(content::BrowserContext*,
                              const extensions::Extension* extension,
                              extensions::UninstallReason) override {
    if (!decided_ && baseline_ == extension) {
      Invalidate();
    }
  }
  void OnShutdown(extensions::ExtensionRegistry*) override {
    registry_ = nullptr;
    Invalidate();
  }
  void OnProfileWillBeDestroyed(Profile*) override { Invalidate(); }
  base::WeakPtr<BrowserWindowInterface> browser_;
  NativeExtensionActionHost* host_;
  content::WeakDocumentPtr document_;
  scoped_refptr<const extensions::Extension> extension_, baseline_;
  __weak NSWindow* window_;
  std::shared_ptr<NativeExtensionParentApproval> parent_approval_;
  PCExtensionInstallPresenter* __strong presenter_ = nil;
  PCNativeWindowSecurityReservation* __strong reservation_ = nil;
  id __strong close_observer_ = nil;
  id __strong security_observer_ = nil;
  TabListInterface* tabs_ = nullptr;
  extensions::ExtensionRegistry* registry_ = nullptr;
  Profile* profile_ = nullptr;
  bool allowed_, acquiring_ = false, tracking_ = false, began_ = false,
                 decided_ = false, withhold_ = false, result_seen_ = false;
  Done done_;
  std::unique_ptr<extensions::InstallPromptData> prompt_;
};
NativeExtensionInstallService::NativeExtensionInstallService(
    BrowserWindowInterface& browser,
    NativeExtensionActionHost& host)
    : browser_(browser),
      host_(host),
      registration_(browser.GetUnownedUserDataHost(), *this) {
  ExtensionInstallNativeHost::MarkProfile(browser.GetProfile());
}
NativeExtensionInstallService::~NativeExtensionInstallService() {
  Shutdown();
}
std::shared_ptr<extensions::ExtensionInstallNativeBinding>
NativeExtensionInstallService::Capture(content::WebContents* page) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto request = std::make_shared<Request>(browser_, host_, page, !shutdown_);
  std::erase_if(requests_, [](const auto& weak) { return weak.expired(); });
  requests_.push_back(request);
  request->StartObserving();
  return request;
}
void NativeExtensionInstallService::HostStateChanged() {
  auto requests = requests_;
  for (auto weak : requests) {
    if (auto r = weak.lock()) {
      r->CheckContext();
    }
  }
}
void NativeExtensionInstallService::PageHostWillDetach(
    content::WebContents* page) {
  auto requests = requests_;
  for (auto weak : requests) {
    if (auto r = weak.lock(); r && r->Owns(page)) {
      r->Invalidate();
    }
  }
}
void NativeExtensionInstallService::Shutdown() {
  if (shutdown_) {
    return;
  }
  shutdown_ = true;
  auto requests = std::move(requests_);
  requests_.clear();
  for (auto weak : requests) {
    if (auto r = weak.lock()) {
      r->Invalidate();
    }
  }
}
}  // namespace parc
