#include "extension_parent_approval.h"

#include <algorithm>
#include <string>
#include <utility>
#include <vector>
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/browser/extensions/extension_util.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/signin/identity_manager_factory.h"
#include "chrome/browser/supervised_user/supervised_user_browser_utils.h"
#include "chrome/browser/supervised_user/supervised_user_service_factory.h"
#include "chrome/grit/generated_resources.h"
#include "components/signin/public/base/consent_level.h"
#include "components/signin/public/base/oauth_consumer_id.h"
#include "components/signin/public/identity_manager/access_token_fetcher.h"
#include "components/signin/public/identity_manager/access_token_info.h"
#include "components/signin/public/identity_manager/identity_manager.h"
#include "components/supervised_user/core/browser/supervised_user_service.h"
#include "extension_install_presenter.h"
#include "extensions/browser/install_prompt_permissions.h"
#include "extensions/browser/ui_util.h"
#include "extensions/common/extension.h"
#include "extensions/common/permissions/permission_set.h"
#include "extensions/strings/grit/extensions_strings.h"
#include "google_apis/gaia/core_account_id.h"
#include "google_apis/gaia/gaia_auth_consumer.h"
#include "google_apis/gaia/gaia_auth_fetcher.h"
#include "google_apis/gaia/gaia_constants.h"
#include "google_apis/gaia/gaia_id.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"

namespace parc {
namespace {
NSString* Text(int id) {
  return base::SysUTF16ToNSString(l10n_util::GetStringUTF16(id));
}
class Approval final : public NativeExtensionParentApproval,
                       public GaiaAuthConsumer,
                       public std::enable_shared_from_this<Approval> {
 public:
  Approval(Profile* profile, const extensions::Extension* extension,
           const gfx::ImageSkia& icon, NSWindow* window,
           base::RepeatingCallback<bool()> validate,
           base::RepeatingCallback<bool(NSWindow*)> input_allowed,
           base::OnceCallback<void(Result)> done)
      : profile_(profile->GetWeakPtr()), extension_(extension), icon_(icon),
        window_(window), validate_(std::move(validate)),
        input_allowed_(std::move(input_allowed)), done_(std::move(done)) {}
  ~Approval() override { [presenter_ invalidate]; }
  NSWindow* sheet() const override { return presenter_.sheet; }
  bool Valid() const {
    return !finished_ && profile_ && !profile_->ShutdownStarted() &&
           profile_->IsChild() && validate_ && validate_.Run();
  }
  void Start() override {
    auto keep = shared_from_this();
    if (started_ || finished_) return;
    started_ = true;
    if (!Valid() || !extension_) { Finish(Result::ABORTED); return; }
    auto* service = supervised_user::SupervisedUserServiceFactory::GetForProfile(profile_.get());
    auto* identity = IdentityManagerFactory::GetForProfile(profile_.get());
    if (!service || !identity ||
        identity->GetPrimaryAccountId(signin::ConsentLevel::kSignin).empty()) {
      Finish(Result::ABORTED);
      return;
    }
    NSMutableArray<NSString*>* emails = [NSMutableArray array];
    if (service->GetCustodian()) {
      parents_.push_back(service->GetCustodian()->GetObfuscatedGaiaId());
      [emails addObject:base::SysUTF8ToNSString(service->GetCustodian()->GetEmailAddress())];
    }
    if (service->GetSecondCustodian()) {
      parents_.push_back(service->GetSecondCustodian()->GetObfuscatedGaiaId());
      [emails addObject:base::SysUTF8ToNSString(service->GetSecondCustodian()->GetEmailAddress())];
    }
    account_ = identity->GetPrimaryAccountId(signin::ConsentLevel::kSignin);
    if (parents_.empty() || std::ranges::any_of(parents_, [](const GaiaId& id) { return id.empty(); })) {
      Finish(Result::ABORTED);
      return;
    }
    auto permissions = extensions::util::GetInstallPromptPermissionSetForExtension(
        extension_.get(), profile_.get());
    extensions::InstallPromptPermissions display;
    display.LoadFromPermissionSet(permissions.get(), extension_->GetType());
    NSMutableArray<NSString*>* messages = [NSMutableArray array];
    NSMutableArray<NSString*>* details = [NSMutableArray array];
    for (size_t i = 0; i < display.permissions.size(); ++i) {
      [messages addObject:base::SysUTF16ToNSString(display.permissions[i])];
      [details addObject:base::SysUTF16ToNSString(display.details[i])];
    }
    const auto child = base::UTF8ToUTF16(supervised_user::GetAccountGivenName(*profile_));
    auto extension_type = l10n_util::GetStringUTF16(extension_->is_app()
        ? IDS_PARENT_PERMISSION_PROMPT_EXTENSION_TYPE_APP
        : IDS_PARENT_PERMISSION_PROMPT_EXTENSION_TYPE_EXTENSION);
    std::weak_ptr<Approval> weak = keep;
    presenter_ = [[PCExtensionInstallPresenter alloc] initWithWindow:window_
        title:base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
            IDS_PARENT_PERMISSION_PROMPT_GO_GET_A_PARENT_FOR_EXTENSION_LABEL,
            extensions::ui_util::GetFixupExtensionNameForUIDisplay(extension_->name())))
        icon:icon_.isNull() ? nil : gfx::Image(icon_).ToNSImage()
        heading:base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
            IDS_PARENT_PERMISSION_PROMPT_CHILD_WANTS_TO_INSTALL_LABEL, child, extension_type))
        permissions:messages details:details
        acceptLabel:Text(IDS_PARENT_PERMISSION_PROMPT_APPROVE_BUTTON)
        cancelLabel:Text(IDS_PARENT_PERMISSION_PROMPT_CANCEL_BUTTON)
        checkboxLabel:nil
        validate:^BOOL { auto self = weak.lock(); return self && self->Valid(); }
        inputAllowed:^BOOL(NSWindow* sheet) {
          auto self = weak.lock();
          return self && self->Valid() && self->input_allowed_.Run(sheet);
        }
        result:^(PCExtensionInstallChoice choice, BOOL) {
          if (auto self = weak.lock())
            self->Finish(choice == PCExtensionInstallCancel
                ? Result::USER_CANCELED : Result::ABORTED);
        }];
    [presenter_ configureParentAccounts:emails
        instructions:@[Text(IDS_PARENT_PERMISSION_PROMPT_PARENT_ACCOUNT_VERIFY_LABEL),
                       Text(IDS_PARENT_PROMPT_ENTER_PASSWORD_TO_ALLOW_EXTENSION_LABEL),
                       base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
                           IDS_SKIP_PARENT_PERMISSION_EXTENSION_INFORMATION, child))]
        passwordLabel:Text(IDS_PARENT_PERMISSION_PROMPT_ENTER_PASSWORD_LABEL)
        submit:^(NSInteger index, NSString* credential) {
          if (auto self = weak.lock()) self->Submit(index, credential);
        }];
    [presenter_ start];
  }
  void Cancel() override { Finish(Result::ABORTED); }
 private:
  bool HasSurface() const {
    NSWindow* sheet = presenter_.sheet;
    return sheet && sheet.visible && sheet.sheetParent == window_;
  }
  bool IsCurrentCustodian(const GaiaId& id) const {
    if (!Valid()) return false;
    auto* identity = IdentityManagerFactory::GetForProfile(profile_.get());
    if (!identity || identity->GetPrimaryAccountId(signin::ConsentLevel::kSignin) != account_)
      return false;
    auto* service = supervised_user::SupervisedUserServiceFactory::GetForProfile(profile_.get());
    return service &&
        ((service->GetCustodian() && service->GetCustodian()->GetObfuscatedGaiaId() == id) ||
         (service->GetSecondCustodian() && service->GetSecondCustodian()->GetObfuscatedGaiaId() == id));
  }
  void Submit(NSInteger index, NSString* password) {
    auto keep = shared_from_this();
    if (!Valid() || !presenter_.sheet || !presenter_.sheet.visible ||
        !input_allowed_.Run(presenter_.sheet) || oauth_ || reauth_ ||
        index < 0 || static_cast<size_t>(index) >= parents_.size() || !password.length) return;
    selected_parent_ = parents_[index];
    if (!IsCurrentCustodian(selected_parent_)) { Finish(Result::ABORTED); return; }
    auto* identity = IdentityManagerFactory::GetForProfile(profile_.get());
    if (!identity) { Finish(Result::ABORTED); return; }
    [presenter_ setParentApprovalPending:YES error:@""];
    oauth_ = identity->CreateAccessTokenFetcherForAccount(
        identity->GetPrimaryAccountId(signin::ConsentLevel::kSignin),
        signin::OAuthConsumerId::kParentPermissionDialog,
        base::BindOnce(&Approval::OnAccessToken, weak_factory_.GetWeakPtr(),
                       selected_parent_, base::SysNSStringToUTF8(password)),
        signin::AccessTokenFetcher::Mode::kImmediate);
  }
  void OnAccessToken(const GaiaId& parent, const std::string& credential,
                     GoogleServiceAuthError error, signin::AccessTokenInfo token) {
    auto keep = shared_from_this();
    oauth_.reset();
    if (!HasSurface()) {
      Finish(Valid() ? Result::USER_CANCELED : Result::ABORTED);
      return;
    }
    if (!IsCurrentCustodian(parent) || error.state() != GoogleServiceAuthError::NONE) {
      Finish(Result::ABORTED);
      return;
    }
    reauth_ = std::make_unique<GaiaAuthFetcher>(this, gaia::GaiaSource::kChromeOS,
                                             profile_->GetURLLoaderFactory());
    reauth_->StartCreateReAuthProofTokenForParent(token.token, parent, credential);
  }
  void OnReAuthProofTokenSuccess(const std::string&) override {
    auto keep = shared_from_this();
    // A deferred native Cancel wins over a late authentication response.
    if (!HasSurface()) {
      Finish(Valid() ? Result::USER_CANCELED : Result::ABORTED);
      return;
    }
    // This is the sole approval source. No native control grants permission.
    Finish(IsCurrentCustodian(selected_parent_) ? Result::ACCEPTED : Result::ABORTED);
  }
  void OnReAuthProofTokenFailure(ReAuthProofTokenStatus error) override {
    auto keep = shared_from_this();
    reauth_.reset();
    if (!HasSurface()) {
      Finish(Valid() ? Result::USER_CANCELED : Result::ABORTED);
      return;
    }
    if (!Valid()) { Finish(Result::ABORTED); return; }
    if (error == ReAuthProofTokenStatus::kInvalidGrant) {
      [presenter_ setParentApprovalPending:NO
          error:Text(IDS_PARENT_PERMISSION_PROMPT_PASSWORD_INCORRECT_LABEL)];
      return;
    }
    Finish(Result::ABORTED);
  }
  void Finish(Result result) {
    auto keep = shared_from_this();
    if (finished_) return;
    const bool valid = Valid();
    finished_ = true;
    weak_factory_.InvalidateWeakPtrs();
    oauth_.reset();
    reauth_.reset();
    [presenter_ invalidate];
    presenter_ = nil;
    auto done = std::move(done_);
    if (done) std::move(done).Run(valid ? result : Result::ABORTED);
  }
  base::WeakPtr<Profile> profile_;
  scoped_refptr<const extensions::Extension> extension_;
  gfx::ImageSkia icon_;
  NSWindow* __weak window_;
  PCExtensionInstallPresenter* __strong presenter_;
  base::RepeatingCallback<bool()> validate_;
  base::RepeatingCallback<bool(NSWindow*)> input_allowed_;
  base::OnceCallback<void(Result)> done_;
  std::vector<GaiaId> parents_;
  GaiaId selected_parent_;
  CoreAccountId account_;
  bool started_ = false, finished_ = false;
  std::unique_ptr<signin::AccessTokenFetcher> oauth_;
  std::unique_ptr<GaiaAuthFetcher> reauth_;
  base::WeakPtrFactory<Approval> weak_factory_{this};
};
}  // namespace
std::shared_ptr<NativeExtensionParentApproval> NativeExtensionParentApproval::Create(
    Profile* profile, const extensions::Extension* extension,
    const gfx::ImageSkia& icon, NSWindow* window,
    base::RepeatingCallback<bool()> validate,
    base::RepeatingCallback<bool(NSWindow*)> input_allowed,
    base::OnceCallback<void(Result)> done) {
  return std::make_shared<Approval>(profile, extension, icon, window,
      std::move(validate), std::move(input_allowed), std::move(done));
}
}  // namespace parc
