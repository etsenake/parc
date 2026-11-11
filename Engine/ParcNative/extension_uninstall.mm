#include "extension_uninstall.h"

#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/tab_list/tab_list_interface_observer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/views/extensions/security_dialog_tracker.h"
#include "chrome/grit/generated_resources.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "extension_action_container.h"
#include "extension_security_context.h"
#import "extension_uninstall_presenter.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/browser/ui_util.h"
#include "extensions/common/constants.h"
#include "extensions/common/extension.h"
#include "ui/base/base_window.h"
#include "ui/base/interaction/element_identifier.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/models/dialog_model.h"
#include "ui/base/models/dialog_model_field.h"
#include "ui/base/models/dialog_model_host.h"
#include "ui/base/models/image_model.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia_operations.h"
#include "ui/strings/grit/ui_strings.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
DEFINE_LOCAL_ELEMENT_IDENTIFIER_VALUE(kCheckboxId);

// Owns one context-menu uninstall, as Chromium's UninstallDialogHelper does.
class UninstallFlow final
    : public extensions::ExtensionUninstallDialog::Delegate {
 public:
  static void Begin(BrowserWindowInterface* browser,
                    const extensions::Extension* extension) {
    (new UninstallFlow)->Start(browser, extension);
  }

 private:
  UninstallFlow() = default;
  ~UninstallFlow() override = default;
  void Start(BrowserWindowInterface* browser,
             const extensions::Extension* extension) {
    Profile* profile = browser->GetProfile();
    gfx::NativeWindow parent = browser->GetWindow()->GetNativeWindow();
    auto* service = NativeExtensionUninstallService::Get(
        browser->GetUnownedUserDataHost());
    if (!service) {
      dialog_ =
          extensions::ExtensionUninstallDialog::Create(profile, parent, this);
      dialog_->ConfirmUninstall(
          extension, extensions::UNINSTALL_REASON_USER_INITIATED,
          extensions::UNINSTALL_SOURCE_TOOLBAR_CONTEXT_MENU);
      return;
    }
    auto dialog = std::make_unique<NativeExtensionUninstallDialog>(
        profile, parent, this, service->Capture(*extension));
    auto* native = dialog.get();
    dialog_ = std::move(dialog);
    // May report, and so delete this, before returning.
    native->Confirm(extension, extensions::UNINSTALL_REASON_USER_INITIATED,
                    extensions::UNINSTALL_SOURCE_TOOLBAR_CONTEXT_MENU);
  }
  void OnExtensionUninstallDialogClosed(bool, const std::u16string&) override {
    delete this;
  }
  std::unique_ptr<extensions::ExtensionUninstallDialog> dialog_;
};
}  // namespace

DEFINE_USER_DATA(NativeExtensionUninstallService);

class NativeExtensionUninstallService::Request final
    : public ExtensionUninstallNativeBinding,
      public ui::DialogModelHost,
      public ui::DialogModelFieldHost,
      public std::enable_shared_from_this<Request>,
      public content::WebContentsObserver,
      public TabListInterfaceObserver,
      public extensions::ExtensionRegistryObserver,
      public ProfileObserver,
      public extensions::SecurityDialogTracker::Observer {
 public:
  Request(BrowserWindowInterface& browser,
          NativeExtensionActionHost& host,
          const extensions::Extension& extension,
          bool allowed)
      : browser_(browser.GetWeakPtr()),
        host_(&host),
        extension_(&extension),
        window_(host.PopupParentWindow()),
        allowed_(allowed) {
    auto* tabs = TabListInterface::From(&browser);
    if (tabs && tabs->GetActiveTab()) {
      Observe(tabs->GetActiveTab()->GetContents());
    }
  }
  ~Request() override {
    // The real controller closes its installed host before dropping binding.
    CHECK(!model_ && !executing_);
    StopObserving();
    [reservation_ invalidate];
  }
  bool Owns(content::WebContents* page) const { return web_contents() == page; }
  bool Valid() const {
    if (closed_ || !allowed_ || !browser_ || !host_ || !window_ ||
        !window_.visible || window_.miniaturized || !web_contents() ||
        web_contents()->IsBeingDestroyed() || !host_->IsSelectedBrowser() ||
        host_->PopupParentWindow() != window_ ||
        (!acquiring_ && host_->HasVisibleBrowserSecurityUIExcluding(
                            presenter_.sheet, reservation_)) ||
        extensions::SecurityDialogTracker::GetInstance()
            ->BrowserHasVisibleSecurityDialogs(browser_.get()) ||
        !browser_->GetWindow() ||
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() !=
            window_) {
      return false;
    }
    auto* tab = tabs::TabInterface::MaybeGetFromContents(web_contents());
    auto* registry = extensions::ExtensionRegistry::Get(browser_->GetProfile());
    NSView* page = web_contents()->GetNativeView().GetNativeNSView();
    return tab && tab->GetBrowserWindowInterface() == browser_.get() &&
           web_contents()->GetBrowserContext() == browser_->GetProfile() &&
           page && page.window == window_ && registry &&
           registry->GetExtensionById(
               extension_->id(), extensions::ExtensionRegistry::EVERYTHING) ==
               extension_.get() &&
           (!armed_ || reservation_.isOnlyReservation);
  }
  bool Arm(base::RepeatingClosure cancel) override {
    auto keep = shared_from_this();
    CHECK(!armed_ && !cancel_);
    cancel_ = std::move(cancel);
    if (!Valid() || PCNativeWindowHasSecurityReservation(window_)) {
      return false;
    }
    tabs_ = TabListInterface::From(browser_.get());
    registry_ = extensions::ExtensionRegistry::Get(browser_->GetProfile());
    profile_ = browser_->GetProfile();
    tabs_->AddTabListInterfaceObserver(this);
    registry_->AddObserver(this);
    profile_->AddObserver(this);
    extensions::SecurityDialogTracker::GetInstance()->AddObserver(this);
    tracking_security_ = true;
    std::weak_ptr<Request> weak = keep;
    closed_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock()) {
                    self->Invalidate();
                  }
                }];
    security_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock()) {
                    self->CheckContext();
                  }
                }];
    // Acquisition notifies after committing the lease but before returning it.
    // Defer only the aggregate-security check on that stack; validate the
    // returned exact lease and all page/window state before allowing any UI.
    acquiring_ = true;
    PCNativeWindowSecurityReservation* reservation =
        [PCNativeWindowSecurityReservation acquireForWindow:window_];
    acquiring_ = false;
    if (closed_) {
      [reservation invalidate];
      return false;
    }
    reservation_ = reservation;
    armed_ = true;
    if (!Valid()) {
      Invalidate();
      return false;
    }
    return true;
  }
  void Show(std::unique_ptr<ui::DialogModel> model) override {
    auto keep = shared_from_this();
    CHECK(model && !model_ && !executing_);
    if (closed_) {
      // A completed icon load may hand off after owner cancellation. Consume
      // the actual model and resolve destroying without reviving this host.
      model->set_host(ui::DialogModelHost::GetPassKey(), this);
      model->OnDialogDestroying(ui::DialogModelHost::GetPassKey());
      return;
    }
    model_ = std::move(model);
    model_->set_host(ui::DialogModelHost::GetPassKey(), this);
    // Install even a rejected model so its destroying callback resolves the
    // real helper exactly once. No fallback to a currently selected Browser.
    if (!Valid() || !ReadSchema()) {
      Close();
      return;
    }
    std::weak_ptr<Request> weak = keep;
    auto* ok = model_->ok_button(ui::DialogModelHost::GetPassKey());
    auto* cancel = model_->cancel_button(ui::DialogModelHost::GetPassKey());
    const auto& image = model_->icon(ui::DialogModelHost::GetPassKey());
    NSImage* icon = image.IsEmpty() ? nil : image.GetImage().ToNSImage();
    presenter_ = [[PCNativeUninstallPresenter alloc] initWithWindow:window_
        title:base::SysUTF16ToNSString(
                  model_->title(ui::DialogModelHost::GetPassKey()))
        message:base::SysUTF16ToNSString(paragraph_)
        icon:icon
        acceptLabel:base::SysUTF16ToNSString(ok->label())
        cancelLabel:base::SysUTF16ToNSString(
                        cancel->label().empty()
                            ? l10n_util::GetStringUTF16(IDS_APP_CANCEL)
                            : cancel->label())
        checkboxLabel:checkbox_ ? base::SysUTF16ToNSString(
                                      checkbox_->label().GetString())
                                : nil
        checked:checkbox_ && checkbox_->is_checked()
        validate:^BOOL {
          auto self = weak.lock();
          return self && self->Valid();
        }
        changed:^(BOOL checked) {
          if (auto self = weak.lock()) {
            self->CheckChanged(checked);
          }
        }
        result:^(PCUninstallChoice choice) {
          if (auto self = weak.lock()) {
            self->Choose(choice);
          }
        }];
    OnDialogButtonChanged();
    [presenter_ start];
  }
  void Invalidate() {
    auto keep = shared_from_this();
    allowed_ = false;
    Close();
  }
  void CheckContext() {
    if (!Valid()) {
      Invalidate();
    }
  }
  void Close() override {
    auto keep = shared_from_this();
    if (closed_) {
      return;
    }
    closed_ = true;
    // Commit terminal state and detach callbacks before arbitrary observers.
    auto model = std::move(model_);
    auto* executing = std::exchange(executing_, nullptr);
    checkbox_ = nullptr;
    auto cancel = std::move(cancel_);
    PCNativeUninstallPresenter* presenter = std::exchange(presenter_, nil);
    PCNativeWindowSecurityReservation* reservation =
        std::exchange(reservation_, nil);
    StopObserving();
    host_ = nullptr;
    [presenter invalidate];
    [reservation invalidate];
    if (model) {
      model->OnDialogDestroying(ui::DialogModelHost::GetPassKey());
    } else if (executing) {
      executing->OnDialogDestroying(ui::DialogModelHost::GetPassKey());
    } else if (cancel) {
      cancel.Run();
    }
    // If Close reenters a model action, Choose's local unique_ptr retains its
    // storage only until that action unwinds; destroying is already delivered.
  }

 private:
  bool ReadSchema() {
    const auto key = ui::DialogModelHost::GetPassKey();
    if (model_->internal_name(key) != "ExtensionUninstallDialog" ||
        !model_->ok_button(key) || !model_->cancel_button(key) ||
        model_->extra_button(key) || model_->extra_link(key) ||
        !model_->subtitle(key).empty() || !model_->main_image(key).IsEmpty() ||
        !model_->banner(key).IsEmpty() || model_->footnote_label() ||
        (!model_->icon(key).IsEmpty() && !model_->icon(key).IsImage())) {
      return false;
    }
    bool saw_paragraph = false;
    for (const auto& field : model_->fields(key)) {
      if (!field->is_visible() || !field->accelerators().empty()) {
        return false;
      }
      if (field->type() == ui::DialogModelField::kParagraph && !saw_paragraph) {
        auto* paragraph = field->AsParagraph();
        if (!paragraph->header().empty() ||
            !paragraph->label().replacements().empty()) {
          return false;
        }
        saw_paragraph = true;
        paragraph_ = paragraph->label().GetString();
      } else if (field->type() == ui::DialogModelField::kCheckbox &&
                 !checkbox_) {
        checkbox_ = field->AsCheckbox();
        if (!checkbox_->label().replacements().empty()) {
          return false;
        }
      } else {
        return false;
      }
    }
    return true;
  }
  void Choose(PCUninstallChoice choice) {
    auto keep = shared_from_this();
    if (closed_ || !model_) {
      return;
    }
    if (!Valid() || choice == PCUninstallInterrupted) {
      Close();
      return;
    }
    auto model = std::move(model_);
    executing_ = model.get();
    const bool should_close =
        choice == PCUninstallAccept
            ? model->OnDialogAcceptAction(ui::DialogModelHost::GetPassKey())
            : model->OnDialogCancelAction(ui::DialogModelHost::GetPassKey());
    executing_ = nullptr;
    if (closed_) {
      return;
    }
    model_ = std::move(model);
    if (should_close) {
      Close();
    } else {
      // This exact uninstall model uses once-only close actions. A changed
      // repeating/nonclosing model is refused rather than left invisible.
      Close();
    }
  }
  void CheckChanged(bool checked) {
    auto keep = shared_from_this();
    if (Valid() && model_ && checkbox_) {
      checkbox_->OnChecked(ui::DialogModelFieldHost::GetPassKey(), checked);
    }
  }
  void OnDialogButtonChanged() override {
    if (closed_ || !model_) {
      return;
    }
    const auto key = ui::DialogModelHost::GetPassKey();
    auto* ok = model_->ok_button(key);
    auto* cancel = model_->cancel_button(key);
    if (!ok || !cancel || !ok->is_visible() || !cancel->is_visible()) {
      Close();
      return;
    }
    [presenter_ setAcceptEnabled:ok->is_enabled()
                   cancelEnabled:cancel->is_enabled()];
  }
  void OnSecurityDialogAdded(views::Widget* widget) override {
    // Registration precedes Show in supported Chromium paths. Cancel while
    // still invisible if it belongs to this exact native window.
    if (SecurityWidgetBelongsToWindow(widget, window_)) {
      Invalidate();
    }
  }
  void StopObserving() {
    if (tracking_security_) {
      tracking_security_ = false;
      extensions::SecurityDialogTracker::GetInstance()->RemoveObserver(this);
    }
    Observe(nullptr);
    if (tabs_) {
      tabs_->RemoveTabListInterfaceObserver(this);
      tabs_ = nullptr;
    }
    if (registry_) {
      registry_->RemoveObserver(this);
      registry_ = nullptr;
    }
    if (profile_) {
      profile_->RemoveObserver(this);
      profile_ = nullptr;
    }
    if (closed_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:closed_observer_];
    }
    closed_observer_ = nil;
    if (security_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:security_observer_];
    }
    security_observer_ = nil;
  }
  void WebContentsDestroyed() override { Invalidate(); }
  void OnTabRemoved(TabListInterface&,
                    tabs::TabInterface* tab,
                    TabRemovedReason) override {
    if (tab && tab->GetContents() == web_contents()) {
      Invalidate();
    }
  }
  void OnWebContentsReplaced(TabListInterface&,
                             tabs::TabInterface*,
                             content::WebContents* old,
                             content::WebContents*) override {
    if (old == web_contents()) {
      Invalidate();
    }
  }
  void OnTabListDestroyed(TabListInterface&) override {
    tabs_ = nullptr;
    Invalidate();
  }
  void OnExtensionUnloaded(content::BrowserContext*,
                           const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason) override {
    if (extension == extension_.get()) {
      Invalidate();
    }
  }
  void OnExtensionUninstalled(content::BrowserContext*,
                              const extensions::Extension* extension,
                              extensions::UninstallReason) override {
    if (extension == extension_.get()) {
      Invalidate();
    }
  }
  void OnShutdown(extensions::ExtensionRegistry*) override {
    registry_ = nullptr;
    Invalidate();
  }
  void OnProfileWillBeDestroyed(Profile*) override {
    profile_ = nullptr;
    Invalidate();
  }
  base::WeakPtr<BrowserWindowInterface> browser_;
  NativeExtensionActionHost* host_;
  scoped_refptr<const extensions::Extension> extension_;
  __weak NSWindow* window_;
  PCNativeWindowSecurityReservation* __strong reservation_;
  PCNativeUninstallPresenter* __strong presenter_;
  id __strong closed_observer_;
  id __strong security_observer_;
  TabListInterface* tabs_ = nullptr;
  extensions::ExtensionRegistry* registry_ = nullptr;
  Profile* profile_ = nullptr;
  bool tracking_security_ = false;
  bool acquiring_ = false;
  bool allowed_, armed_ = false, closed_ = false;
  base::RepeatingClosure cancel_;
  std::unique_ptr<ui::DialogModel> model_;
  ui::DialogModel* executing_ = nullptr;
  ui::DialogModelCheckbox* checkbox_ = nullptr;
  std::u16string paragraph_;
};
NativeExtensionUninstallService::NativeExtensionUninstallService(
    BrowserWindowInterface& browser,
    NativeExtensionActionHost& host)
    : browser_(browser),
      host_(host),
      registration_(browser.GetUnownedUserDataHost(), *this) {}
NativeExtensionUninstallService::~NativeExtensionUninstallService() {
  Shutdown();
}
bool NativeExtensionUninstallService::CanPresent(
    const extensions::Extension& extension) const {
  if (shutdown_) {
    return false;
  }
  auto request = std::make_shared<Request>(browser_, host_, extension, true);
  return request->Valid() &&
         !PCNativeWindowHasSecurityReservation(host_.PopupParentWindow());
}
std::shared_ptr<ExtensionUninstallNativeBinding>
NativeExtensionUninstallService::Capture(
    const extensions::Extension& extension) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto request =
      std::make_shared<Request>(browser_, host_, extension, !shutdown_);
  std::erase_if(requests_, [](const auto& value) { return value.expired(); });
  requests_.push_back(request);
  return request;
}
void NativeExtensionUninstallService::HostStateChanged() {
  auto requests = requests_;
  for (auto weak : requests) {
    if (auto request = weak.lock()) {
      request->CheckContext();
    }
  }
}
void NativeExtensionUninstallService::PageHostWillDetach(
    content::WebContents* page) {
  auto requests = requests_;
  for (auto weak : requests) {
    if (auto request = weak.lock(); request && request->Owns(page)) {
      request->Invalidate();
    }
  }
}
void NativeExtensionUninstallService::Shutdown() {
  if (shutdown_) {
    return;
  }
  shutdown_ = true;
  auto requests = std::move(requests_);
  requests_.clear();
  for (auto weak : requests) {
    if (auto request = weak.lock()) {
      request->Invalidate();
    }
  }
}

NativeExtensionUninstallDialog::NativeExtensionUninstallDialog(
    Profile* profile,
    gfx::NativeWindow parent,
    Delegate* delegate,
    std::shared_ptr<ExtensionUninstallNativeBinding> binding)
    : ExtensionUninstallDialog(profile, parent, delegate),
      binding_(std::move(binding)) {}
NativeExtensionUninstallDialog::~NativeExtensionUninstallDialog() {
  // A synchronous native close must not report from this destructor.
  if (std::exchange(model_, nullptr)) {
    binding_->Close();
  }
}
void NativeExtensionUninstallDialog::Confirm(
    const scoped_refptr<const extensions::Extension>& extension,
    extensions::UninstallReason reason,
    extensions::UninstallSource source) {
  auto weak = weak_factory_.GetWeakPtr();
  const bool armed = binding_->Arm(
      base::BindRepeating(&NativeExtensionUninstallDialog::Close, weak));
  if (!weak) {
    return;
  }
  if (!armed) {
    Report(CLOSE_ACTION_CANCELED);
    return;
  }
  ConfirmUninstall(extension, reason, source);
}
// The same model as Chromium's ExtensionUninstallDialogImpl::Show.
void NativeExtensionUninstallDialog::Show() {
  // An icon can finish loading after a cancellation was reported.
  if (reported_) {
    return;
  }
  ui::DialogModel::Builder dialog_builder;
  dialog_builder.SetInternalName("ExtensionUninstallDialog")
      .SetTitle(l10n_util::GetStringFUTF16(
          IDS_EXTENSION_PROMPT_UNINSTALL_TITLE,
          extensions::ui_util::GetFixupExtensionNameForUIDisplay(
              extension()->name())))
      .OverrideShowCloseButton(false)
      .SetDialogDestroyingCallback(
          base::BindOnce(&NativeExtensionUninstallDialog::Closing,
                         weak_factory_.GetWeakPtr()))
      .SetIcon(ui::ImageModel::FromImageSkia(
          gfx::ImageSkiaOperations::CreateResizedImage(
              icon(), skia::ImageOperations::ResizeMethod::RESIZE_GOOD,
              gfx::Size(extension_misc::EXTENSION_ICON_SMALL,
                        extension_misc::EXTENSION_ICON_SMALL))))
      .AddOkButton(base::BindOnce(&NativeExtensionUninstallDialog::Accepted,
                                  weak_factory_.GetWeakPtr()),
                   ui::DialogModel::Button::Params()
                       .SetLabel(l10n_util::GetStringUTF16(
                           IDS_EXTENSION_PROMPT_UNINSTALL_BUTTON))
                       .SetId(kOkButtonElementId))
      .AddCancelButton(
          base::DoNothing() /* Cancel is covered by the destroying callback */,
          ui::DialogModel::Button::Params().SetId(kCancelButtonElementId));
  if (triggering_extension()) {
    dialog_builder.AddParagraph(
        ui::DialogModelLabel(
            l10n_util::GetStringFUTF16(
                IDS_EXTENSION_PROMPT_UNINSTALL_TRIGGERED_BY_EXTENSION,
                extensions::ui_util::GetFixupExtensionNameForUIDisplay(
                    triggering_extension()->name())))
            .set_is_secondary()
            .set_allow_character_break());
  }
  if (ShouldShowCheckbox()) {
    std::u16string checkbox_label =
        triggering_extension()
            ? l10n_util::GetStringFUTF16(
                  IDS_EXTENSION_PROMPT_UNINSTALL_REPORT_ABUSE_FROM_EXTENSION,
                  extensions::ui_util::GetFixupExtensionNameForUIDisplay(
                      extension()->name()))
            : l10n_util::GetStringUTF16(
                  IDS_EXTENSION_PROMPT_UNINSTALL_REPORT_ABUSE);
    dialog_builder.AddCheckbox(kCheckboxId,
                               ui::DialogModelLabel(checkbox_label));
  }
  std::unique_ptr<ui::DialogModel> model = dialog_builder.Build();
  model_ = model.get();
  binding_->Show(std::move(model));
}
void NativeExtensionUninstallDialog::Close() {
  if (model_) {
    binding_->Close();
  } else if (!reported_) {
    Report(CLOSE_ACTION_CANCELED);
  }
}
void NativeExtensionUninstallDialog::Accepted() {
  CHECK(model_);
  const bool checked =
      ShouldShowCheckbox() &&
      model_->GetCheckboxByUniqueId(kCheckboxId)->is_checked();
  model_ = nullptr;
  Report(checked ? CLOSE_ACTION_UNINSTALL_AND_CHECKBOX_CHECKED
                 : CLOSE_ACTION_UNINSTALL);
}
void NativeExtensionUninstallDialog::Closing() {
  if (std::exchange(model_, nullptr)) {
    Report(CLOSE_ACTION_CANCELED);
  }
}
void NativeExtensionUninstallDialog::Report(CloseAction action) {
  reported_ = true;
  OnDialogClosed(action);
}

void BeginExtensionUninstall(BrowserWindowInterface* browser,
                             const extensions::Extension* extension) {
  UninstallFlow::Begin(browser, extension);
}
}  // namespace parc
