// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_DOWNLOAD_FILE_DIALOG_H_
#define PARC_NATIVE_DOWNLOAD_FILE_DIALOG_H_

#include <memory>

#include "base/memory/scoped_refptr.h"
#include "ui/shell_dialogs/select_file_dialog.h"

namespace download {
class DownloadItem;
}
namespace ui {
class SelectFilePolicy;
}
namespace parc {
// Chrome's real DownloadFilePicker calls this only when there is no source
// WebContents. A non-null dialog owns that exact item's Profile identity and
// obtains its parent from the native shell. A null result leaves the picker on
// Chrome's own path, where a chooser without a page is refused. Target determination, policy,
// caller authority, extensions and destination verification stay in Chrome.
scoped_refptr<ui::SelectFileDialog> CreateNativeDownloadFileDialog(
    download::DownloadItem& item,
    ui::SelectFileDialog::Listener* listener,
    std::unique_ptr<ui::SelectFilePolicy> policy);
}  // namespace parc
#endif
