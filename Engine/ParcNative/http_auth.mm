// Copyright 2026 Parc contributors.
#include "http_auth.h"

#include <algorithm>
#include <map>
#include <memory>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/supports_user_data.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/blocked_content/popunder_preventer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/login/login_handler.h"
#include "chrome/browser/ui/login/http_auth_coordinator.h"
#include "chrome/browser/ui/login/login_tab_helper.h"
#include "components/password_manager/core/browser/http_auth_observer.h"
#include "components/tabs/public/tab_interface.h"
#include "components/web_modal/single_web_contents_dialog_manager.h"
#include "components/web_modal/web_contents_modal_dialog_manager.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#import "http_auth_presenter.h"
#include "native_auxiliary_page.h"
#include "ui/base/base_window.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
class Request;
auto& NativeHandlers() {
  static base::NoDestructor<std::map<LoginHandler*, std::weak_ptr<Request>>> handlers;
  return *handlers;
}
constexpr char kPageState[] = "parc-native-http-auth-page";
class PageState final : public base::SupportsUserData::Data {
 public:
  bool attached = false;
  std::vector<std::weak_ptr<Request>> requests;
};
PageState* State(content::WebContents* contents) {
  return contents ? static_cast<PageState*>(contents->GetUserData(kPageState))
                  : nullptr;
}
using Result =
    base::OnceCallback<void(PCHTTPAuthChoice, std::u16string, std::u16string)>;

class NativeModal final : public web_modal::SingleWebContentsDialogManager {
 public:
  explicit NativeModal(std::shared_ptr<Request> request);
  ~NativeModal() override;
  void Show() override;
  void Hide() override;
  void Close() override;
  void Focus() override;
  void Pulse() override;
  void HostChanged(web_modal::WebContentsModalDialogHost*) override;
  gfx::NativeWindow dialog() override;
  bool IsActive() const override;

 private:
  const std::shared_ptr<Request> request_;
};

class Request final : public content::WebContentsObserver,
                      public password_manager::HttpAuthObserver,
                      public std::enable_shared_from_this<Request> {
 public:
  Request(content::WebContents& contents, Result result)
      : content::WebContentsObserver(&contents), result_(std::move(result)) {
    auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
    auxiliary_ = tab ? nullptr : GetNativeAuxiliaryPage(contents);
    auto* browser = tab          ? tab->GetBrowserWindowInterface()
                    : auxiliary_ ? auxiliary_->browser()
                                 : nullptr;
    if (browser && browser->GetWindow()) {
      browser_ = browser->GetWeakPtr();
      profile_ = browser->GetProfile()->GetWeakPtr();
      window_ = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
      page_ = contents.GetNativeView().GetNativeNSView();
      document_ = contents.GetPrimaryMainFrame()->GetWeakDocumentPtr();
    }
  }
  ~Request() override {
    DetachModel();
    [presenter_ invalidate];
    [reservation_ invalidate];
    RemoveObservers();
  }
  bool Build(const std::u16string& authority,
             const std::u16string& explanation,
             bool proxy,
             LoginHandler::LoginModelData* model) {
    auto keep = shared_from_this();
    if (auxiliary_) {
      if (!auxiliary_->IsValid()) {
        return false;
      }
      std::weak_ptr<Request> weak = keep;
      auxiliary_cancel_ = auxiliary_->OnInvalidated(base::BindRepeating(
          [](std::weak_ptr<Request> weak) {
            if (auto self = weak.lock()) {
              self->Finish(PCHTTPAuthInterrupted, {}, {});
            }
          },
          weak));
    }
    auto* contents = web_contents();
    auto* manager =
        contents ? web_modal::WebContentsModalDialogManager::FromWebContents(
                       contents)
                 : nullptr;
    if (!Valid() || !manager || !manager->delegate() ||
        manager->IsDialogActive() ||
        PCNativeWindowHasSecurityReservation(window_)) {
      return false;
    }
    std::weak_ptr<Request> weak = keep;
    window_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock()) {
                    self->CancelSoon();
                  }
                }];
    security_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock(); self && !self->acquiring_ &&
                                               !self->finished_ &&
                                               !self->Valid()) {
                    self->CancelSoon();
                  }
                }];
    acquiring_ = true;
    auto* lease = [PCNativeWindowSecurityReservation acquireForWindow:window_];
    acquiring_ = false;
    if (finished_) {
      [lease invalidate];
      return false;
    }
    reservation_ = lease;
    if (!Valid()) {
      return false;
    }
    presenter_ = [[PCHTTPAuthPresenter alloc] initWithPage:page_
        window:window_
        authority:base::SysUTF16ToNSString(authority)
        explanation:base::SysUTF16ToNSString(explanation)
        proxy:proxy
        validate:^BOOL {
          auto self = weak.lock();
          return self && !self->finished_ && self->Valid();
        }
        result:^(PCHTTPAuthChoice choice, NSString* username,
                 NSString* password) {
          if (auto self = weak.lock()) {
            self->Finish(choice, base::SysNSStringToUTF16(username),
                         base::SysNSStringToUTF16(password));
          }
        }];
    if (model) {
      model_ = model->model;
      model_->SetObserverAndDeliverCredentials(this, *model->form);
    }
    if (finished_ || !Valid()) {
      return false;
    }
    // The supported native manager preserves Chrome's real renderer blocking,
    // fullscreen exit, navigation dismissal and active-dialog bookkeeping.
    registered_ = true;
    registering_ = true;
    manager->ShowDialogWithManager(Window(),
                                   std::make_unique<NativeModal>(keep));
    registering_ = false;
    if (finished_) {
      RemoveModal();
    }
    return !finished_;
  }
  bool CanAuthorize() const { return Valid(); }
  void Show() {
    if (!finished_) {
      [presenter_ show];
    }
  }
  void Focus() {
    if (!finished_) {
      [presenter_ focus];
    }
  }
  gfx::NativeWindow Window() const {
    return gfx::NativeWindow(presenter_.sheet);
  }
  bool IsActive() const { return !finished_ && presenter_.sheet.keyWindow; }
  void CancelSoon() {
    // Commit rejection before deferring list removal. A host can return to the
    // same window during a nested callback, but that must not revive this
    // request or authorize a propagated SetAuth before the posted close.
    if (cancelled_) {
      return;
    }
    cancelled_ = true;
    if (finished_) {
      return;
    }
    // A host-changed callback can occur while the manager iterates its list or
    // before it inserts this adapter. Never erase that list from the callback.
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(
                       [](std::shared_ptr<Request> self) {
                         self->Finish(PCHTTPAuthInterrupted, {}, {});
                       },
                       shared_from_this()));
  }
  void HostChanged() {
    if (!Valid()) {
      CancelSoon();
    }
  }
  void ModalDestroyed() {
    registered_ = false;
    if (!finished_) {
      CancelSoon();
    }
  }
  void CloseFromManager() {
    // CloseAllDialogs requires synchronous removal to advance its actual list.
    Finish(PCHTTPAuthInterrupted, {}, {});
  }
  void StopSilently() {
    result_.Reset();
    Finish(PCHTTPAuthInterrupted, {}, {});
  }
  void Finish(PCHTTPAuthChoice choice,
              std::u16string username,
              std::u16string password) {
    auto keep = shared_from_this();
    if (finished_) {
      return;
    }
    const bool approved = choice == PCHTTPAuthAccept && Valid();
    finished_ = true;
    DetachModel();
    [presenter_ invalidate];
    RemoveModal();
    [reservation_ invalidate];
    reservation_ = nil;
    RemoveObservers();
    if (choice == PCHTTPAuthAccept && (!approved || !Valid())) {
      choice = PCHTTPAuthInterrupted;
      username.clear();
      password.clear();
    }
    // Real LoginHandler can synchronously destroy itself and its request.
    // Leave the native/engine observer stack first; recheck the exact owner
    // again after release-time observers and competing sheets have run.
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE,
        base::BindOnce(
            [](std::shared_ptr<Request> self, PCHTTPAuthChoice choice,
               std::u16string username, std::u16string password) {
              if (!self->result_) {
                return;
              }
              if (choice == PCHTTPAuthAccept && !self->Valid()) {
                choice = PCHTTPAuthInterrupted;
                username.clear();
                password.clear();
              }
              auto result = std::move(self->result_);
              std::move(result).Run(choice, std::move(username),
                                    std::move(password));
            },
            keep, choice, std::move(username), std::move(password)));
  }
  void OnAutofillDataAvailable(std::u16string_view username,
                               std::u16string_view password) override {
    [presenter_ autofillUsername:base::SysUTF16ToNSString(username)
                        password:base::SysUTF16ToNSString(password)];
  }
  void OnLoginModelDestroying() override { model_ = nullptr; }
  void DidStartNavigation(content::NavigationHandle* handle) override {
    if (handle->IsInPrimaryMainFrame() && !handle->IsSameDocument()) {
      CancelSoon();
    }
  }
  void PrimaryPageChanged(content::Page&) override { CancelSoon(); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN) {
      CancelSoon();
    }
  }
  void WebContentsDestroyed() override { StopSilently(); }

 private:
  bool Valid() const {
    auto* contents = web_contents();
    auto* state = State(contents);
    if (cancelled_ || !contents || !state || !state->attached || !browser_ ||
        !profile_ || browser_->IsDeleteScheduled() || !browser_->GetWindow() ||
        !document_.AsRenderFrameHostIfValid() ||
        contents->GetBrowserContext() != profile_.get() ||
        browser_->GetProfile() != profile_.get() || !window_ || !page_ ||
        page_.window != window_ || !window_.visible || window_.miniaturized ||
        page_.hiddenOrHasHiddenAncestor ||
        contents->GetVisibility() == content::Visibility::HIDDEN ||
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() !=
            window_ ||
        (window_.attachedSheet && window_.attachedSheet != presenter_.sheet) ||
        (reservation_ ? !reservation_.isOnlyReservation
                      : PCNativeWindowHasSecurityReservation(window_))) {
      return false;
    }
    if (auxiliary_) {
      return auxiliary_->IsActive() && auxiliary_->browser() == browser_.get();
    }
    auto* tab = tabs::TabInterface::MaybeGetFromContents(contents);
    return tab && tab->IsActivated() &&
           tab->GetBrowserWindowInterface() == browser_.get();
  }
  void RemoveModal() {
    if (!registered_ || registering_) {
      return;
    }
    registered_ = false;
    if (auto* contents = web_contents()) {
      if (auto* manager =
              web_modal::WebContentsModalDialogManager::FromWebContents(
                  contents)) {
        manager->WillClose(Window());
      }
    }
  }
  void DetachModel() {
    auto* model = model_.get();
    model_ = nullptr;
    if (model) {
      model->DetachObserver(this);
    }
  }
  void RemoveObservers() {
    if (window_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:window_observer_];
    }
    if (security_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:security_observer_];
    }
    window_observer_ = security_observer_ = nil;
  }
  Result result_;
  std::shared_ptr<NativeAuxiliaryPage> auxiliary_;
  base::CallbackListSubscription auxiliary_cancel_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  content::WeakDocumentPtr document_;
  __weak NSWindow* window_;
  __weak NSView* page_;
  PCHTTPAuthPresenter* presenter_;
  PCNativeWindowSecurityReservation* reservation_;
  raw_ptr<password_manager::HttpAuthManager> model_ = nullptr;
  id window_observer_;
  id security_observer_;
  bool finished_ = false;
  bool cancelled_ = false;
  bool acquiring_ = false;
  bool registered_ = false;
  bool registering_ = false;
};

NativeModal::NativeModal(std::shared_ptr<Request> request)
    : request_(std::move(request)) {}
NativeModal::~NativeModal() {
  request_->ModalDestroyed();
}
void NativeModal::Show() {
  auto keep = request_;
  keep->Show();
}
void NativeModal::Hide() {
  auto keep = request_;
  keep->CancelSoon();
}
void NativeModal::Close() {
  auto keep = request_;
  keep->CloseFromManager();
}
void NativeModal::Focus() {
  auto keep = request_;
  keep->Focus();
}
void NativeModal::Pulse() {
  Focus();
}
void NativeModal::HostChanged(web_modal::WebContentsModalDialogHost*) {
  request_->HostChanged();
}
gfx::NativeWindow NativeModal::dialog() {
  return request_->Window();
}
bool NativeModal::IsActive() const {
  return request_->IsActive();
}

class NativeLoginHandler final : public LoginHandler {
 public:
  NativeLoginHandler(const net::AuthChallengeInfo& info,
                     content::WebContents* contents,
                     content::LoginDelegate::LoginAuthRequiredCallback callback)
      : LoginHandler(info, contents, std::move(callback)),
        popunder_preventer_(std::make_unique<PopunderPreventer>(contents)) {
    NativeHandlers().emplace(this, std::weak_ptr<Request>());
  }
  ~NativeLoginHandler() override {
    NativeHandlers().erase(this);
    weak_factory_.InvalidateWeakPtrs();
    CloseDialog();
  }

 private:
  bool BuildViewImpl(const std::u16string& authority,
                     const std::u16string& explanation,
                     LoginModelData* model) override {
    auto* contents = web_contents();
    if (!contents || !State(contents)) {
      return false;
    }
    request_ = std::make_shared<Request>(
        *contents, base::BindOnce(
                       [](base::WeakPtr<NativeLoginHandler> handler,
                          PCHTTPAuthChoice choice, std::u16string username,
                          std::u16string password) {
                         if (!handler) {
                           return;
                         }
                         if (choice == PCHTTPAuthAccept) {
                           handler->SetAuth(username, password);
                         } else {
                           handler->CancelAuth(/*notify_others=*/choice ==
                                               PCHTTPAuthCancel);
                         }
                       },
                       weak_factory_.GetWeakPtr()));
    NativeHandlers()[this] = request_;
    auto& requests = State(contents)->requests;
    std::erase_if(requests,
                  [](const auto& request) { return request.expired(); });
    requests.push_back(request_);
    auto request = request_;
    return request->Build(authority, explanation, auth_info().is_proxy, model);
  }
  void CloseDialog() override {
    auto request = std::move(request_);
    if (request) {
      request->StopSilently();
    }
    popunder_preventer_.reset();
  }
  std::shared_ptr<Request> request_;
  std::unique_ptr<PopunderPreventer> popunder_preventer_;
  base::WeakPtrFactory<NativeLoginHandler> weak_factory_{this};
};
class NativeLoginTabHelper final : public LoginTabHelper {
 public:
  explicit NativeLoginTabHelper(content::WebContents* contents)
      : LoginTabHelper(contents) {}

 protected:
  std::unique_ptr<LoginHandler> CreateLoginHandler(
      const net::AuthChallengeInfo& info, content::WebContents* contents,
      content::LoginDelegate::LoginAuthRequiredCallback callback) override {
    if (!State(contents)) {
      return LoginTabHelper::CreateLoginHandler(info, contents,
                                                std::move(callback));
    }
    return std::make_unique<NativeLoginHandler>(info, contents,
                                                 std::move(callback));
  }
};

class NativeHttpAuthCoordinator final : public HttpAuthCoordinator {
 public:
  void CreateLoginTabHelper(content::WebContents* contents) override {
    if (!LoginTabHelper::FromWebContents(contents)) {
      contents->SetUserData(LoginTabHelper::UserDataKey(),
                           std::make_unique<NativeLoginTabHelper>(contents));
    }
  }

  std::unique_ptr<content::LoginDelegate> CreateLoginDelegateFromLoginHandler(
      content::WebContents* contents, const net::AuthChallengeInfo& info,
      const content::GlobalRequestID& request_id, const GURL& url,
      scoped_refptr<net::HttpResponseHeaders> headers,
      content::LoginDelegate::LoginAuthRequiredCallback callback) override {
    if (!State(contents)) {
      return HttpAuthCoordinator::CreateLoginDelegateFromLoginHandler(
          contents, info, request_id, url, std::move(headers),
          std::move(callback));
    }
    auto handler = std::make_unique<NativeLoginHandler>(info, contents,
                                                       std::move(callback));
    handler->ShowLoginPrompt(url);
    return handler;
  }
};
}  // namespace

bool ValidateNativeLoginHandlerAuth(LoginHandler* handler) {
  auto found = NativeHandlers().find(handler);
  if (found == NativeHandlers().end()) {
    return true;
  }
  auto request = found->second.lock();
  return request && request->CanAuthorize();
}

std::unique_ptr<HttpAuthCoordinator> CreateNativeHttpAuthCoordinator() {
  return std::make_unique<NativeHttpAuthCoordinator>();
}

void InstallNativeHTTPAuth(content::WebContents& contents) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!State(&contents)) {
    contents.SetUserData(kPageState, std::make_unique<PageState>());
  }
}
void SetNativeHTTPAuthAttached(content::WebContents& contents, bool attached) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto* state = State(&contents);
  if (!state) {
    return;
  }
  state->attached = attached;
  if (attached) {
    return;
  }
  auto requests = std::move(state->requests);
  for (auto& weak : requests) {
    if (auto request = weak.lock()) {
      request->Finish(PCHTTPAuthInterrupted, {}, {});
    }
  }
}
}  // namespace parc
