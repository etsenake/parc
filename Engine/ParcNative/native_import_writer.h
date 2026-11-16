// Copyright 2026 Parc contributors.
#pragma once
#import <AppKit/AppKit.h>
#include <atomic>
#include <memory>
#include <string>
#include "base/functional/callback.h"
#include "parc/importer/parc_import.mojom.h"
class Profile;
namespace parc::importer {
struct WriteResult {
  bool success = false;
  size_t count = 0;
  std::string error;
  std::string warning;
};
using WriteReply = base::OnceCallback<void(WriteResult)>;
class ImportWriter {
 public:
  virtual ~ImportWriter() = default;
  virtual void Cancel() = 0;
  virtual void OnProfileDestroyed() { Cancel(); }
};
std::shared_ptr<ImportWriter> WriteImportBatch(Profile&,
                                               int family,
                                               mojom::BatchPtr,
                                               bool skip_existing_cookies,
                                               WriteReply);
}
