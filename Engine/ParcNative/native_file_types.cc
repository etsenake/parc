// Copyright 2012 The Chromium Authors
#include "native_file_types.h"
#include "base/files/file_path.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/grit/generated_resources.h"
#include "net/base/mime_util.h"
#include "ui/base/l10n/l10n_util.h"
namespace parc {
std::unique_ptr<ui::SelectFileDialog::FileTypeInfo>
NativeFileTypesFromAcceptType(
    const std::vector<std::u16string>& accept_types) {
  auto base_file_type = std::make_unique<ui::SelectFileDialog::FileTypeInfo>();
  if (accept_types.empty())
    return base_file_type;

  auto file_type =
      std::make_unique<ui::SelectFileDialog::FileTypeInfo>(*base_file_type);
  file_type->include_all_files = true;
  file_type->extensions.resize(1);
  std::vector<base::FilePath::StringType>* extensions =
      &file_type->extensions.back();

  std::vector<std::vector<base::FilePath::StringType>> all_extensions;
  std::vector<std::u16string> all_overrides;

  int valid_type_count = 0;
  int combined_description_id = 0;
  for (const auto& accept_type : accept_types) {
    std::vector<base::FilePath::StringType> current_extensions;
    int description_id = 0;

    size_t old_extension_size = extensions->size();
    if (accept_type[0] == '.') {

      base::FilePath::StringType ext =
          base::FilePath::FromUTF16Unsafe(accept_type).value();
      current_extensions.push_back(ext.substr(1));
    } else {
      if (!base::IsStringASCII(accept_type))
        continue;
      std::string ascii_type = base::UTF16ToASCII(accept_type);
      if (ascii_type == "image/*")
        description_id = IDS_IMAGE_FILES;
      else if (ascii_type == "audio/*")
        description_id = IDS_AUDIO_FILES;
      else if (ascii_type == "video/*")
        description_id = IDS_VIDEO_FILES;
      net::GetExtensionsForMimeType(ascii_type, &current_extensions);
    }

    if (!current_extensions.empty()) {
      all_extensions.push_back(current_extensions);
      all_overrides.push_back(description_id != 0
                                  ? l10n_util::GetStringUTF16(description_id)
                                  : std::u16string());
      if (description_id != 0)
        combined_description_id = description_id;

      extensions->insert(extensions->end(), current_extensions.begin(),
                         current_extensions.end());
    }
    if (extensions->size() > old_extension_size)
      valid_type_count++;
  }

  if (valid_type_count == 0)
    return base_file_type;

  if (valid_type_count > 1 ||
      (valid_type_count == 1 && combined_description_id == 0 &&
                               extensions->size() > 1)) {
    combined_description_id = IDS_CUSTOM_FILES;
  }

  file_type->extension_description_overrides.push_back(
      combined_description_id != 0
          ? l10n_util::GetStringUTF16(combined_description_id)
          : std::u16string());

  if (all_extensions.size() > 1) {
    file_type->extensions.insert(file_type->extensions.end(),
                                 all_extensions.begin(), all_extensions.end());
    file_type->extension_description_overrides.insert(
        file_type->extension_description_overrides.end(), all_overrides.begin(),
        all_overrides.end());
  }

  return file_type;
}

}
