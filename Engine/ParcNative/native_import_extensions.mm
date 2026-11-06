// Copyright 2026 Parc contributors.
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/extensions/extension_install_native_host.h"
#include "chrome/browser/extensions/webstore_install_with_prompt.h"
#include "chrome/browser/profiles/profile.h"
#import "native_appkit_host.h"
#import "native_import_internal.h"
#import "extension_install_presenter.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/common/extension.h"
#import "native_import_writer.h"
#include "ui/gfx/image/image.h"
#import "window_security_reservation.h"
namespace parc::importer {
namespace {
using Result = extensions::ExtensionInstallPromptClient::Result;
using Payload = extensions::ExtensionInstallPromptClient::DoneCallbackPayload;
using Done = extensions::ExtensionInstallPromptClient::DoneCallback;
class Consent final : public extensions::ExtensionInstallNativeBinding,
                      public std::enable_shared_from_this<Consent> {
 public:
  Consent(Profile& profile, NSWindow* window)
      : profile_(profile.GetWeakPtr()), window_(window) {}
  ~Consent() override { Cancel(); }
  bool Begin(const extensions::Extension* extension, Done done) override {
    if (done_)
      return false;
    extension_ = extension;
    done_ = std::move(done);
    if (!CanContinue()) {
      Complete(Result::ABORTED);
      return false;
    }
    return true;
  }
  bool CanContinue() const override {
    return !cancelled_ && profile_ && !profile_->ShutdownStarted() && window_ &&
           window_.visible && !window_.miniaturized &&
           (!window_.attachedSheet ||
            window_.attachedSheet == presenter_.sheet) &&
           (reservation_ ? reservation_.isOnlyReservation
                         : !PCNativeWindowHasSecurityReservation(window_));
  }
  void Show(std::unique_ptr<extensions::InstallPromptData> prompt) override {
    auto keep = shared_from_this();
    if (!CanContinue() || !done_ ||
        prompt->type() != extensions::InstallPromptData::INSTALL_PROMPT ||
        prompt->extension() != extension_.get()) {
      Complete(Result::ABORTED);
      return;
    }
    reservation_ = [PCNativeWindowSecurityReservation acquireForWindow:window_];
    if (!reservation_.active) {
      Complete(Result::ABORTED);
      return;
    }
    prompt_ = std::move(prompt);
    prompt_->OnDialogOpened();
    if (!CanContinue()) {
      Complete(Result::ABORTED);
      return;
    }
    auto permissions = prompt_->GetPermissions();
    if (permissions.permissions.size() != permissions.details.size()) {
      Complete(Result::ABORTED);
      return;
    }
    NSMutableArray* messages = [NSMutableArray array];
    NSMutableArray* details = [NSMutableArray array];
    for (size_t i = 0; i < permissions.permissions.size(); ++i) {
      [messages addObject:base::SysUTF16ToNSString(permissions.permissions[i])];
      [details addObject:base::SysUTF16ToNSString(permissions.details[i])];
    }
    std::weak_ptr<Consent> weak = shared_from_this();
    presenter_ = [[PCExtensionInstallPresenter alloc] initWithWindow:window_
        title:base::SysUTF16ToNSString(prompt_->GetDialogTitle())
        icon:prompt_->icon().IsEmpty() ? nil : prompt_->icon().ToNSImage()
        heading:base::SysUTF16ToNSString(prompt_->GetPermissionsHeading())
        permissions:messages
        details:details
        acceptLabel:base::SysUTF16ToNSString(prompt_->GetAcceptButtonLabel())
        cancelLabel:base::SysUTF16ToNSString(prompt_->GetAbortButtonLabel())
        checkboxLabel:nil
        validate:^BOOL {
          auto self = weak.lock();
          return self && self->CanContinue();
        }
        inputAllowed:^BOOL(NSWindow* sheet) {
          return NSApp.active && sheet.keyWindow &&
                 NSApp.currentEvent.window == sheet;
        }
        result:^(PCExtensionInstallChoice choice, BOOL) {
          if (auto self = weak.lock())
            self->Complete(choice == PCExtensionInstallAccept ? Result::ACCEPTED
                           : choice == PCExtensionInstallCancel
                               ? Result::USER_CANCELED
                               : Result::ABORTED);
        }];
    [presenter_ start];
  }
  // Once the real accepted callback runs, the upstream installer may already
  // own a self-retained CRX download. Its result must remain attached.
  bool authorized() const { return authorized_; }
  void Cancel() override {
    cancelled_ = true;
    Complete(Result::ABORTED);
  }
  void ShowParentApproval(const extensions::Extension*,
                          const gfx::ImageSkia&,
                          Done done) override {
    // A parent reauthentication cannot be replaced by import consent. Current
    // ownerless import reports this refusal; ordinary supervised UI is
    // retained.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(done), Payload(Result::ABORTED)));
  }
  void InstallationFinished(const extensions::Extension*,
                            bool,
                            const std::u16string&,
                            const SkBitmap*,
                            bool) override {}

 private:
  void Complete(Result result) {
    if (!done_)
      return;
    std::weak_ptr<Consent> weak = weak_from_this();
    auto done = std::move(done_);
    auto prompt = std::move(prompt_);
    [presenter_ invalidate];
    presenter_ = nil;
    [reservation_ invalidate];
    reservation_ = nil;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(
            [](std::weak_ptr<Consent> weak,
               std::unique_ptr<extensions::InstallPromptData> prompt, Done done,
               Result result) {
              auto self = weak.lock();
              auto valid = [&] {
                return self && self->CanContinue() &&
                       !PCNativeWindowHasSecurityReservation(self->window_);
              };
              if (result == Result::ACCEPTED && !valid())
                result = Result::ABORTED;
              if (prompt) {
                if (result == Result::ACCEPTED)
                  prompt->OnDialogAccepted();
                else
                  prompt->OnDialogCanceled();
              }
              if (result == Result::ACCEPTED && !valid())
                result = Result::ABORTED;
              if (result == Result::ACCEPTED)
                self->authorized_ = true;
              std::move(done).Run(Payload(result));
            },
            weak, std::move(prompt), std::move(done), result));
  }
  base::WeakPtr<Profile> profile_;
  NSWindow* __weak window_;
  bool cancelled_ = false;
  bool authorized_ = false;
  Done done_;
  scoped_refptr<const extensions::Extension> extension_;
  std::unique_ptr<extensions::InstallPromptData> prompt_;
  PCExtensionInstallPresenter* __strong presenter_;
  PCNativeWindowSecurityReservation* __strong reservation_;
};
class Installer final : public extensions::WebstoreInstallWithPrompt {
 public:
  Installer(const std::string& id,
            Profile& profile,
            NSWindow* window,
            Callback callback)
      : WebstoreInstallWithPrompt(id,
                                  &profile,
                                  gfx::NativeWindow(window),
                                  std::move(callback)),
        window_(window),
        consent_(std::make_shared<Consent>(profile, window)) {
    set_show_post_install_ui(false);
  }
  // False means installation has already been authorized; keep its genuine
  // completion callback and wait rather than claiming to undo that operation.
  bool CancelBeforeInstall() {
    if (consent_->authorized())
      return false;
    consent_->Cancel();
    AbortInstall();
    return true;
  }
  void ProfileDestroyed() {
    // The target services can no longer supply a trustworthy terminal result.
    // Do not retain callbacks into the dead Profile or claim rollback.
    consent_->Cancel();
    AbortInstall();
  }

 protected:
  ~Installer() override = default;
  std::unique_ptr<ExtensionInstallPrompt> CreateInstallUI(
      std::unique_ptr<extensions::InstallPromptData> prompt) override {
    return std::make_unique<ExtensionInstallPrompt>(
        profile(), gfx::NativeWindow(window_), std::move(prompt), consent_);
  }

 private:
  NSWindow* __weak window_;
  std::shared_ptr<Consent> consent_;
};
class ExtensionWriter final
    : public ImportWriter,
      public std::enable_shared_from_this<ExtensionWriter> {
 public:
  ExtensionWriter(Profile& profile,
                  NSWindow* window,
                  std::vector<mojom::ExtensionPtr> items,
                  WriteReply reply)
      : profile_(profile.GetWeakPtr()),
        window_(window),
        items_(std::move(items)),
        reply_(std::move(reply)) {}
  void Cancel() override {
    cancelled_ = true;
    if (installer_ && !installer_->CancelBeforeInstall())
      return;
    installer_ = nullptr;
    Finish({false, count_,
            "Extension import was cancelled; installed extensions remain."});
  }
  void OnProfileDestroyed() override {
    cancelled_ = true;
    if (installer_)
      installer_->ProfileDestroyed();
    installer_ = nullptr;
    Finish({false, count_,
            "The destination Profile closed. Pending extension installation "
            "could not be confirmed; completed installations remain."});
  }
  void Next() {
    if (!reply_)
      return;
    if (cancelled_) {
      Finish({false, count_,
              "Extension import was cancelled; installed extensions remain."});
      return;
    }
    installer_ = nullptr;
    if (!profile_ || profile_->ShutdownStarted() || !window_ ||
        !window_.visible) {
      Cancel();
      return;
    }
    if (index_ == items_.size()) {
      Finish(
          {!failed_, count_,
           failed_
               ? "Some extensions were not installed. They may require policy "
                 "or parent approval, or may be unavailable in the Web Store."
               : ""});
      return;
    }
    const std::string id = items_[index_++]->id;
    if (extensions::ExtensionRegistry::Get(profile_.get())
            ->GetInstalledExtension(id)) {
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE,
          base::BindOnce(&ExtensionWriter::Next, shared_from_this()));
      return;
    }
    installer_ = base::MakeRefCounted<Installer>(
        id, *profile_, window_,
        base::BindOnce(
            [](std::weak_ptr<ExtensionWriter> weak, bool success,
               const std::string&, extensions::webstore_install::Result) {
              if (auto self = weak.lock()) {
                if (success)
                  ++self->count_;
                else
                  self->failed_ = true;
                self->Next();
              }
            },
            weak_from_this()));
    installer_->BeginInstall();
  }

 private:
  void Finish(WriteResult result) {
    if (!reply_)
      return;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(reply_), std::move(result)));
  }
  base::WeakPtr<Profile> profile_;
  NSWindow* __weak window_;
  std::vector<mojom::ExtensionPtr> items_;
  WriteReply reply_;
  scoped_refptr<Installer> installer_;
  size_t index_ = 0, count_ = 0;
  bool failed_ = false, cancelled_ = false;
};
}  // namespace
std::shared_ptr<ImportWriter> InstallImportedExtensions(
    Profile& profile,
    NSWindow* window,
    std::vector<mojom::ExtensionPtr> extensions,
    WriteReply reply) {
  auto writer = std::make_shared<ExtensionWriter>(
      profile, window, std::move(extensions), std::move(reply));
  writer->Next();
  return writer;
}
}  // namespace parc::importer

namespace parc::setup_password_extension {
namespace {
//
// general unattended-extension API and cannot accept an ID from page content.
constexpr char kICloudPasswordsID[] = "pejdijmoenmkgeppbflobdenhhabjlaj";

class Installer final : public extensions::WebstoreInstallWithPrompt {
 public:
  Installer(Profile& profile, Callback callback)
      : WebstoreInstallWithPrompt(kICloudPasswordsID, &profile,
                                  gfx::NativeWindow(), std::move(callback)),
        profile_(profile.GetWeakPtr()) {
    set_show_post_install_ui(false);
  }
 protected:
  ~Installer() override = default;
  bool CheckRequestorAlive() const override {
    return profile_ && !profile_->ShutdownStarted();
  }
  std::unique_ptr<extensions::InstallPromptData> CreateInstallPrompt() const override {
    // The setup owner has already accepted this particular extension. Keep
    // Chromium's metadata, signature, policy and CRX installation checks.
    return nullptr;
  }

 private:
  base::WeakPtr<Profile> profile_;
};

class Session final : public std::enable_shared_from_this<Session> {
 public:
  Session(NSString* path, void (^completion)(NSError*))
      : path_([path copy]), completion_([completion copy]) {}

  void Start() {
    lifetime_ = shared_from_this();
    auto weak = weak_from_this();
    WithNativeProfile(path_, base::BindOnce(
        [](std::weak_ptr<Session> weak, Profile* profile,
           CefRefPtr<CefRequestContext> context, NSError* error) {
          auto self = weak.lock();
          if (!self || self->finished_) return;
          if (error || !profile || !context || profile->IsOffTheRecord() ||
              profile->ShutdownStarted()) {
            self->Finish(error ?: importer::ImportError(@"The selected Profile is unavailable."));
            return;
          }
          // This setup continuation cannot provide parental reauthentication.
          // Never replace a required parent decision with the setup selection.
          if (profile->IsChild()) {
            self->Finish(importer::ImportError(@"This Profile requires parental approval to install extensions."));
            return;
          }
          self->context_ = context;
          self->installer_ = base::MakeRefCounted<Installer>(*profile,
              base::BindOnce([](std::weak_ptr<Session> weak, bool success,
                                const std::string& message, extensions::webstore_install::Result) {
                if (auto self = weak.lock()) {
                  NSError* failure = success ? nil : importer::ImportError(message.empty()
                      ? @"The selected iCloud Passwords extension could not be installed."
                      : base::SysUTF8ToNSString(message));
                  self->Finish(failure);
                }
              }, weak));
          self->installer_->BeginInstall();
        }, weak));
  }

 private:
  void Finish(NSError* error) {
    if (finished_) return;
    finished_ = true;
    // Do not release the installer/context inside Chromium's own completion
    // stack. Retain this owner through the single main-thread delivery.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([](std::shared_ptr<Session> self, NSError* error) {
          // WebstoreStandaloneInstaller itself observes Profile destruction
          // and supplies its terminal failure before aborting installation.
          self->installer_ = nullptr; self->context_ = nullptr;
          auto completion = self->completion_; self->completion_ = nil;
          self->lifetime_.reset();
          completion(error);
        }, shared_from_this(), error));
  }
  NSString* __strong path_;
  void (^completion_)(NSError*);
  CefRefPtr<CefRequestContext> context_;
  scoped_refptr<Installer> installer_;
  std::shared_ptr<Session> lifetime_;
  bool finished_ = false;
};
}  // namespace
}  // namespace parc::setup_password_extension

@implementation PCNativeBrowserApplication (SetupPasswordExtension)
+ (void)installICloudPasswordsExtensionToProfilePath:(NSString*)profilePath
    completion:(void (^)(NSError*))completion {
  auto session = std::make_shared<parc::setup_password_extension::Session>(profilePath, completion);
  // Always asynchronous, including profile admission failure.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(&parc::setup_password_extension::Session::Start, std::move(session)));
}
@end
