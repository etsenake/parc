// Copyright 2026 Parc contributors.
#pragma once
#import <AppKit/AppKit.h>
#include <atomic>
#include <memory>
#include <string>
#include "base/functional/callback.h"
#include "chrome/common/importer/parc_import.mojom.h"
class Profile;
namespace parc::importer {
struct WriteResult {
  bool success = false;
  size_t count = 0;
  std::string error;
};
using WriteReply = base::OnceCallback<void(WriteResult)>;
// Actual profile services own encryption/policy/commit. Cancellation can stop
// pending records but never claims to roll back writes already accepted.
class ImportWriter {
 public:
  virtual ~ImportWriter() = default;
  virtual void Cancel() = 0;
  // Service teardown may discard callbacks. Report confirmed work and any
  // unconfirmed accepted writes without waiting on a destroyed Profile.
  virtual void OnProfileDestroyed() { Cancel(); }
};
std::shared_ptr<ImportWriter> WriteImportBatch(Profile&,
                                               NSWindow*,
                                               int family,
                                               mojom::BatchPtr,
                                               bool skip_existing_cookies,
                                               WriteReply);
std::shared_ptr<ImportWriter> InstallImportedExtensions(
    Profile&,
    NSWindow*,
    std::vector<mojom::ExtensionPtr>,
    WriteReply);
}  // namespace parc::importer
