// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_FOLDER_UPLOAD_H_
#define PARC_NATIVE_FOLDER_UPLOAD_H_
#include <memory>

namespace content {
class RenderFrameHost;
class WebContents;
}
namespace ui {
class DialogModel;
}
namespace parc {
// FileSelectHelper's folder-upload confirmation. Installed pages present the
// actual DialogModel natively, keeping its enumerated paths, policy and
// listener continuation; any other page keeps Chromium's tab-modal dialog.
void ShowFolderUploadConfirmation(std::unique_ptr<ui::DialogModel> model,
                                  content::WebContents* contents,
                                  content::RenderFrameHost* frame);
void InstallNativeFolderUpload(content::WebContents& contents);
void SetNativeFolderUploadAttached(content::WebContents& contents,
                                   bool attached);
}  // namespace parc
#endif
