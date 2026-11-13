// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_FILE_TYPES_H_
#define PARC_NATIVE_NATIVE_FILE_TYPES_H_
#include <memory>
#include <string>
#include <vector>
#include "ui/shell_dialogs/select_file_dialog.h"
namespace parc_hooks {
using FileTypeInfoFactory =
    std::unique_ptr<ui::SelectFileDialog::FileTypeInfo> (*)(
        const std::vector<std::u16string>&);
void SetFileTypeInfoFactory(FileTypeInfoFactory factory);
}
namespace parc {
std::unique_ptr<ui::SelectFileDialog::FileTypeInfo> NativeFileTypesFromAcceptType(
    const std::vector<std::u16string>& accept_types);
}
#endif
