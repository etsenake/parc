// Copyright 2026 Parc contributors.
#include "file_dialog.h"
#include "native_file_types.h"
#include "download_file_dialog.h"

#import <AppKit/AppKit.h>

#include <map>
#include <set>
#include <string>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/ui/select_file_policy/chrome_select_file_policy.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/download/public/common/download_item.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/download_item_utils.h"
#include "content/public/browser/download_manager.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "printing/buildflags/buildflags.h"
#if BUILDFLAG(ENABLE_PRINT_PREVIEW)
#include "chrome/browser/printing/print_preview_dialog_controller.h"
#endif
#include "native_auxiliary_page.h"
#include "ui/shell_dialogs/select_file_dialog_factory.h"
#include "ui/shell_dialogs/select_file_dialog_mac.h"
#include "ui/shell_dialogs/select_file_policy.h"
#include "ui/shell_dialogs/selected_file_info.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
NativeDownloadDialogParentCallbacks download_parent_callbacks;
content::WebContents* PrintInitiator(content::WebContents& preview) {

#if BUILDFLAG(ENABLE_PRINT_PREVIEW)
  auto* controller = printing::PrintPreviewDialogController::GetInstance();
  return controller ? controller->GetInitiator(&preview) : nullptr;
#else
  return nullptr;
#endif
}
class PrintInitiatorObserver final : public content::WebContentsObserver {
 public:
  PrintInitiatorObserver(content::WebContents& source,
                         base::RepeatingClosure cancel)
      : WebContentsObserver(&source), cancel_(std::move(cancel)) {}
  void WebContentsDestroyed() override { Cancel(); }
  void DidFinishNavigation(content::NavigationHandle* navigation) override {
    if (navigation->HasCommitted() && navigation->IsInPrimaryMainFrame() &&
        !navigation->IsSameDocument()) {
      Cancel();
    }
  }

 private:
  void Cancel() {
    auto cancel = cancel_;
    cancel.Run();
  }
  base::RepeatingClosure cancel_;
};
class NativeFileDialog;
auto& Dialogs() {
  static base::NoDestructor<
      std::map<content::WebContents*, std::set<NativeFileDialog*>>>
      dialogs;
  return *dialogs;
}
auto& DownloadDialogs() {
  static base::NoDestructor<std::set<NativeFileDialog*>> dialogs;
  return *dialogs;
}

class NativeFileDialog final : public ui::SelectFileDialog,
                               public ui::SelectFileDialog::Listener,
                               public content::WebContentsObserver,
                               public download::DownloadItem::Observer,
                               public ProfileObserver {
 public:
  NativeFileDialog(content::WebContents& contents,
                   ui::SelectFileDialog::Listener* listener,
                   std::unique_ptr<ui::SelectFilePolicy> policy)
      : ui::SelectFileDialog(this, std::move(policy)),
        WebContentsObserver(&contents),
        identity_(&contents),
        external_listener_(listener) {
    CHECK(NSThread.isMainThread);
    auto* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
    if (!tab) {

      if (auto* initiator = PrintInitiator(contents)) {
        preview_initiator_ = initiator->GetWeakPtr();
        preview_identity_ = initiator;
        preview_document_ =
            initiator->GetPrimaryMainFrame()->GetWeakDocumentPtr();
        tab = tabs::TabInterface::MaybeGetFromContents(initiator);
        Dialogs()[initiator].insert(this);
        preview_observer_ = std::make_unique<PrintInitiatorObserver>(
            *initiator, base::BindRepeating(&NativeFileDialog::Cancel,
                                            weak_factory_.GetWeakPtr()));
      }
    }
    if (tab) {
      tab_ = tab->GetWeakPtr();
      if (auto* browser = tab->GetBrowserWindowInterface()) {
        browser_ = browser->GetWeakPtr();
      }
    }
    if (!tab) {
      auxiliary_ = GetNativeAuxiliaryPage(contents);
      if (auxiliary_) {
        browser_ = auxiliary_->browser()->GetWeakPtr();
      } else {
        extension_page_ = GetNativeExtensionPage(contents);
      }
    }
    Dialogs()[&contents].insert(this);
  }

  NativeFileDialog(Profile& profile,
                   download::DownloadItem& item,
                   ui::SelectFileDialog::Listener* listener,
                   std::unique_ptr<ui::SelectFilePolicy> policy)
      : ui::SelectFileDialog(this, std::move(policy)),
        external_listener_(listener),
        profile_(profile.GetWeakPtr()),
        download_item_(&item),
        download_guid_(item.GetGuid()),
        profile_owned_(true) {
    CHECK(NSThread.isMainThread);
    profile.AddObserver(this);
    item.AddObserver(this);
    DownloadDialogs().insert(this);
  }

  void SelectFileImpl(Type type,
                      const std::u16string& title,
                      const base::FilePath& path,
                      const FileTypeInfo* types,
                      int index,
                      const base::FilePath::StringType& extension,
                      gfx::NativeWindow window,
                      const GURL* caller) override {
    scoped_refptr<NativeFileDialog> keep_alive(this);
    if (started_ || done_) {
      return;
    }
    started_ = true;
    if (profile_owned_) {
      if (!ValidDownload()) {
        Cancel();
        return;
      }

      window = download_parent_callbacks.prepare(*profile_);
      if (done_) {
        return;
      }
    }
    if (auxiliary_) {
      if (!auxiliary_->IsValid()) {
        Cancel();
        return;
      }
      auxiliary_cancel_ = auxiliary_->OnInvalidated(base::BindRepeating(
          &NativeFileDialog::Cancel, weak_factory_.GetWeakPtr()));
    }
    if (extension_page_) {
      if (!extension_page_->IsValid()) {
        Cancel();
        return;
      }
      extension_page_cancel_ = extension_page_->OnInvalidated(
          base::BindRepeating(&NativeFileDialog::Cancel,
                              weak_factory_.GetWeakPtr()));
    }
    parent_ = window.GetNativeNSWindow();
    if (!Valid() || !parent_.visible || parent_.attachedSheet ||
        PCNativeWindowHasSecurityReservation(parent_)) {
      Cancel();
      return;
    }

    auto reservation =
        [PCNativeWindowSecurityReservation acquireForWindow:parent_];
    if (done_ || !Valid() || !reservation.isOnlyReservation ||
        parent_.attachedSheet) {
      [reservation invalidate];
      Cancel();
      return;
    }
    reservation_ = reservation;
    auto weak = weak_factory_.GetWeakPtr();
    close_token_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:parent_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (weak) {
                    weak->Cancel();
                  }
                }];
    security_token_ = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeWindowSecurityStateChanged
                    object:parent_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (weak && !weak->reservation_.isOnlyReservation) {
                    weak->Cancel();
                  }
                }];

    inner_ = base::MakeRefCounted<ui::SelectFileDialogImpl>(this, nullptr);
    multiple_types_ = types ? types->extensions.size() > 1 : true;
    auto inner = inner_;
    inner->SelectFile(type, title, path, types, index, extension, window,
                      caller);
  }

  bool IsRunning(gfx::NativeWindow window) const override {
    return !done_ && started_ && parent_ == window.GetNativeNSWindow();
  }
  bool HasMultipleFileTypeChoicesImpl() override { return multiple_types_; }
  void ListenerDestroyed() override {
    external_listener_ = nullptr;
    Cancel();
  }
  void FileSelected(const ui::SelectedFileInfo& file, int index) override {
    Finish(CanAcceptSelection(), {file}, index, false);
  }
  void MultiFilesSelected(
      const std::vector<ui::SelectedFileInfo>& files) override {
    Finish(CanAcceptSelection(), files, 0, true);
  }
  void FileSelectionCanceled() override { Cancel(); }
  void Cancel() { Finish(false, {}, 0, false); }
  void WebContentsDestroyed() override { Cancel(); }
  void OnDownloadUpdated(download::DownloadItem* item) override {
    if (item == download_item_ && item->IsDone()) {
      Cancel();
    }
  }
  void OnDownloadRemoved(download::DownloadItem* item) override { Cancel(); }
  void OnDownloadDestroyed(download::DownloadItem* item) override {
    download_item_ = nullptr;
    Cancel();
  }
  void OnProfileWillBeDestroyed(Profile* profile) override { Cancel(); }
  void CancelIfInvalidParent(gfx::NativeWindow window) {
    if (parent_ == window.GetNativeNSWindow() && !Valid()) {
      Cancel();
    }
  }
  void CancelForProfile(Profile& profile) {
    if (profile_.get() == &profile) {
      Cancel();
    }
  }
  void DidFinishNavigation(content::NavigationHandle* handle) override {
    if (handle->HasCommitted() && handle->IsInPrimaryMainFrame() &&
        !handle->IsSameDocument()) {
      Cancel();
    }
  }

 private:
  ~NativeFileDialog() override {
    listener_ = nullptr;
    external_listener_ = nullptr;

    if (inner_) {
      inner_->ListenerDestroyed();
    }
    inner_ = nullptr;
    if (close_token_) {
      [NSNotificationCenter.defaultCenter removeObserver:close_token_];
    }
    if (security_token_) {
      [NSNotificationCenter.defaultCenter removeObserver:security_token_];
    }
    [reservation_ invalidate];
    ForgetIdentity();
    ForgetDownload();
  }
  void ForgetIdentity() {
    for (content::WebContents* identity :
         {identity_.get(), preview_identity_.get()}) {
      auto it = Dialogs().find(identity);
      if (it != Dialogs().end()) {
        it->second.erase(this);
        if (it->second.empty()) {
          Dialogs().erase(it);
        }
      }
    }
    identity_ = nullptr;
    preview_identity_ = nullptr;
  }
  void ForgetDownload() {
    DownloadDialogs().erase(this);
    if (download_item_) {
      download_item_->RemoveObserver(this);
      download_item_ = nullptr;
    }
    if (profile_) {
      profile_->RemoveObserver(this);
      profile_.reset();
    }
  }
  bool ValidDownload() const {
    return !done_ && profile_ && download_item_ &&
           !download_item_->IsDone() &&
           download_item_->GetGuid() == download_guid_ &&
           content::DownloadItemUtils::GetBrowserContext(download_item_) ==
               profile_.get() &&
           profile_->GetDownloadManager()->GetDownloadByGuid(download_guid_) ==
               download_item_ &&
           download_parent_callbacks.owns_profile &&
           download_parent_callbacks.prepare &&
           download_parent_callbacks.owns_parent &&
           download_parent_callbacks.owns_profile(*profile_);
  }
  bool ValidPrintPreview() const {
    auto* preview = web_contents();
    auto* initiator = preview_initiator_.get();
    if (done_ || !preview || preview->IsBeingDestroyed() || !initiator ||
        initiator->IsBeingDestroyed() || !parent_ || !tab_ || !browser_ ||
        !browser_->GetWindow() || !tab_->IsActivated() ||
        tab_->GetContents() != initiator ||
        tab_->GetBrowserWindowInterface() != browser_.get() ||
        PrintInitiator(*preview) != initiator ||
        preview->GetBrowserContext() != initiator->GetBrowserContext() ||
        preview_document_.AsRenderFrameHostIfValid() !=
            initiator->GetPrimaryMainFrame() ||
        preview->GetNativeView().GetNativeNSView().window != parent_) {
      return false;
    }
    NSWindow* source_window =
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow();
    return source_window &&
           initiator->GetNativeView().GetNativeNSView().window ==
               source_window &&
           (parent_ == source_window || parent_.sheetParent == source_window ||
            parent_.parentWindow == source_window);
  }
  bool Valid() const {
    if (preview_initiator_) {
      return ValidPrintPreview();
    }
    if (profile_owned_) {
      return ValidDownload() && parent_ &&
             download_parent_callbacks.owns_parent(*profile_,
                                                   gfx::NativeWindow(parent_));
    }
    if (extension_page_) {
      return !done_ && web_contents() && parent_ &&
             extension_page_->IsValid() &&
             extension_page_->window() == parent_ &&
             web_contents()->GetNativeView().GetNativeNSView().window ==
                 parent_;
    }
    const bool owner =
        auxiliary_
            ? auxiliary_->IsValid() && auxiliary_->browser() == browser_.get()
            : tab_ && tab_->GetContents() == web_contents() &&
                  tab_->GetBrowserWindowInterface() == browser_.get();
    return !done_ && web_contents() && owner && browser_ && parent_ &&
           browser_->GetWindow() &&
           browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() ==
               parent_ &&
           web_contents()->GetNativeView().GetNativeNSView().window == parent_;
  }
  bool CanAcceptSelection() const {

    return Valid() && reservation_.isOnlyReservation;
  }
  void Finish(bool accepted,
              std::vector<ui::SelectedFileInfo> files,
              int index,
              bool multiple) {
    if (done_) {
      return;
    }
    scoped_refptr<NativeFileDialog> keep_alive(this);
    done_ = true;
    weak_factory_.InvalidateWeakPtrs();
    Observe(nullptr);
    preview_observer_.reset();
    ForgetIdentity();
    ForgetDownload();
    auto inner = std::move(inner_);
    if (inner) {
      inner->ListenerDestroyed();
    }
    if (close_token_) {
      [NSNotificationCenter.defaultCenter removeObserver:close_token_];
      close_token_ = nil;
    }
    if (security_token_) {
      [NSNotificationCenter.defaultCenter removeObserver:security_token_];
      security_token_ = nil;
    }
    auto reservation = reservation_;
    reservation_ = nil;
    listener_ = nullptr;
    auto listener = std::exchange(external_listener_, nullptr);
    if (listener) {
      if (!accepted || files.empty()) {
        listener->FileSelectionCanceled();
      } else if (multiple) {
        listener->MultiFilesSelected(files);
      } else {
        listener->FileSelected(files.front(), index);
      }
    }

    [reservation invalidate];
    if (inner) {

      base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
          FROM_HERE, base::BindOnce([](scoped_refptr<ui::SelectFileDialog>) {},
                                    std::move(inner)));
    }
  }
  raw_ptr<content::WebContents> identity_ = nullptr;
  raw_ptr<content::WebContents> preview_identity_ = nullptr;
  base::WeakPtr<content::WebContents> preview_initiator_;
  content::WeakDocumentPtr preview_document_;
  std::unique_ptr<PrintInitiatorObserver> preview_observer_;

  raw_ptr<ui::SelectFileDialog::Listener> external_listener_;
  std::shared_ptr<NativeAuxiliaryPage> auxiliary_;
  base::CallbackListSubscription auxiliary_cancel_;
  std::shared_ptr<NativeExtensionPage> extension_page_;
  base::CallbackListSubscription extension_page_cancel_;
  base::WeakPtr<tabs::TabInterface> tab_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  raw_ptr<download::DownloadItem> download_item_ = nullptr;
  std::string download_guid_;
  const bool profile_owned_ = false;
  NSWindow* __weak parent_;
  id __strong close_token_;
  id __strong security_token_;
  PCNativeWindowSecurityReservation* __strong reservation_;
  scoped_refptr<ui::SelectFileDialog> inner_;
  bool started_ = false;
  bool done_ = false;
  bool multiple_types_ = false;
  base::WeakPtrFactory<NativeFileDialog> weak_factory_{this};
};

class RefusedFileDialog final : public ui::SelectFileDialog {
 public:
  RefusedFileDialog(Listener* listener,
                    std::unique_ptr<ui::SelectFilePolicy> policy)
      : ui::SelectFileDialog(listener, std::move(policy)) {}

  void SelectFileImpl(Type,
                      const std::u16string&,
                      const base::FilePath&,
                      const FileTypeInfo*,
                      int,
                      const base::FilePath::StringType&,
                      gfx::NativeWindow,
                      const GURL*) override {
    Listener* listener = listener_;
    listener_ = nullptr;
    if (listener) {
      listener->FileSelectionCanceled();
    }
  }
  bool IsRunning(gfx::NativeWindow) const override { return false; }
  void ListenerDestroyed() override { listener_ = nullptr; }
  bool HasMultipleFileTypeChoicesImpl() override { return false; }

 private:
  ~RefusedFileDialog() override = default;
};

class NativeFileDialogFactory final : public ui::SelectFileDialogFactory {
 public:
  ui::SelectFileDialog* Create(
      ui::SelectFileDialog::Listener* listener,
      std::unique_ptr<ui::SelectFilePolicy> policy) override {
    CHECK(NSThread.isMainThread);

    content::WebContents* source =
        policy ? static_cast<ChromeSelectFilePolicy*>(policy.get())
                     ->source_contents()
               : nullptr;
    if (!source) {
      return new RefusedFileDialog(listener, std::move(policy));
    }
    return new NativeFileDialog(*source->GetOutermostWebContents(), listener,
                                std::move(policy));
  }
};
}

void RegisterNativeFileDialogs() {
  CHECK(NSThread.isMainThread);
  parc_hooks::SetFileTypeInfoFactory(&NativeFileTypesFromAcceptType);
  ui::SelectFileDialog::SetFactory(std::make_unique<NativeFileDialogFactory>());
}

scoped_refptr<ui::SelectFileDialog> CreateNativeFileDialog(
    content::WebContents& contents,
    ui::SelectFileDialog::Listener* listener,
    std::unique_ptr<ui::SelectFilePolicy> policy) {
  return base::MakeRefCounted<NativeFileDialog>(contents, listener,
                                                std::move(policy));
}
scoped_refptr<ui::SelectFileDialog> CreateNativeDownloadFileDialog(
    download::DownloadItem& item,
    ui::SelectFileDialog::Listener* listener,
    std::unique_ptr<ui::SelectFilePolicy> policy) {
  auto* context = content::DownloadItemUtils::GetBrowserContext(&item);
  auto* profile = context ? Profile::FromBrowserContext(context) : nullptr;
  if (!profile || !download_parent_callbacks.owns_profile ||
      !download_parent_callbacks.prepare ||
      !download_parent_callbacks.owns_parent ||
      !download_parent_callbacks.owns_profile(*profile) ||
      content::DownloadItemUtils::GetWebContents(&item)) {
    return nullptr;
  }
  return base::MakeRefCounted<NativeFileDialog>(*profile, item, listener,
                                               std::move(policy));
}
void SetNativeDownloadDialogParentCallbacks(
    NativeDownloadDialogParentCallbacks callbacks) {
  CHECK(NSThread.isMainThread);
  download_parent_callbacks = callbacks;
}
void CancelInvalidNativeDownloadFileDialogs(gfx::NativeWindow window) {
  std::vector<scoped_refptr<NativeFileDialog>> dialogs(
      DownloadDialogs().begin(), DownloadDialogs().end());
  for (auto& dialog : dialogs) {
    dialog->CancelIfInvalidParent(window);
  }
}
void CancelNativeDownloadFileDialogs(Profile& profile) {
  std::vector<scoped_refptr<NativeFileDialog>> dialogs(
      DownloadDialogs().begin(), DownloadDialogs().end());
  for (auto& dialog : dialogs) {
    dialog->CancelForProfile(profile);
  }
}
void CancelNativeFileDialogs(content::WebContents& contents) {
  auto it = Dialogs().find(&contents);
  if (it == Dialogs().end()) {
    return;
  }
  std::vector<scoped_refptr<NativeFileDialog>> dialogs(it->second.begin(),
                                                       it->second.end());
  for (auto& dialog : dialogs) {
    dialog->Cancel();
  }
}
}
