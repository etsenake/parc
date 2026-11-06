// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_FOLDER_UPLOAD_H_
#define PARC_NATIVE_FOLDER_UPLOAD_H_
namespace content {
class WebContents;
}
namespace parc {
// Installs only the real FileSelectHelper folder-confirmation route. Keeps the
// actual DialogModel, enumerated paths, policy and listener continuation.
void InstallNativeFolderUpload(content::WebContents& contents);
void SetNativeFolderUploadAttached(content::WebContents& contents,
                                   bool attached);
}  // namespace parc
#endif
