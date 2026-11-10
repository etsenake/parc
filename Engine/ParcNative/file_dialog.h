// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_FILE_DIALOG_H_
#define PARC_NATIVE_FILE_DIALOG_H_
#include <memory>

#include "base/memory/scoped_refptr.h"
#include "ui/shell_dialogs/select_file_dialog.h"
namespace content {
class WebContents;
}
namespace ui {
class SelectFilePolicy;
}
class Profile;
namespace parc {
// Installs the ui::SelectFileDialog factory once at startup. Every chooser binds
// to the page its ChromeSelectFilePolicy names (or that page's print preview
// initiator); one without an asking page is refused, never parented to the
// frontmost window.
void RegisterNativeFileDialogs();
// Uses Chromium's actual Mac SelectFileDialog / remote_cocoa NSSavePanel bridge
// after FileSelectHelper and SelectFilePolicy. No guessed MIME filtering or
// URL/path recreation. Native identity is the exact originating page/window.
scoped_refptr<ui::SelectFileDialog> CreateNativeFileDialog(
    content::WebContents& contents,
    ui::SelectFileDialog::Listener* listener,
    std::unique_ptr<ui::SelectFilePolicy> policy);
// Before real page detachment, prevent a pending chooser delivering paths into
// another Browser/window. Destruction/navigation/parent-close also cancel.
void CancelNativeFileDialogs(content::WebContents& contents);
// Profile-owned downloads have no originating page. Their parent is selected
// explicitly by the shell and revalidated on shell selection and response.
// Registered by the real application lifecycle. Keeping this small provider
// boundary here avoids a reverse dependency from native_downloads into the
// application.
struct NativeDownloadDialogParentCallbacks {
  bool (*owns_profile)(Profile&) = nullptr;
  gfx::NativeWindow (*prepare)(Profile&) = nullptr;
  bool (*owns_parent)(Profile&, gfx::NativeWindow) = nullptr;
};
void SetNativeDownloadDialogParentCallbacks(
    NativeDownloadDialogParentCallbacks callbacks);
void CancelInvalidNativeDownloadFileDialogs(gfx::NativeWindow window);
void CancelNativeDownloadFileDialogs(Profile& profile);
}  // namespace parc
#endif
