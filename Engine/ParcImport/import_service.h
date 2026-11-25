// Copyright 2026 Parc contributors.
#pragma once
#include "base/memory/weak_ptr.h"
#include "parc/importer/parc_import.mojom.h"
#include "parc/importer/import_reader.h"
#include "mojo/public/cpp/bindings/receiver.h"
namespace parc::importer {
class ImportService final : public mojom::Reader {
 public:
  explicit ImportService(mojo::PendingReceiver<mojom::Reader>);
  ~ImportService() override;
  void ReadCategory(mojom::SourcePtr source,
                    uint32_t category,
                    ReadCategoryCallback callback) override;
  void DecryptSidebarFile(mojom::SourcePtr source,
                          const std::string& path,
                          mojom::SidebarFormat format,
                          DecryptSidebarFileCallback callback) override;
  void Cancel() override;

 private:
  void Complete(ReadCategoryCallback callback, Batch batch);
  void Decrypted(DecryptSidebarFileCallback callback, DecryptedFile file);
  mojo::Receiver<mojom::Reader> receiver_;
  Cancellation cancelled_;
  bool busy_ = false;
  base::WeakPtrFactory<ImportService> weak_factory_{this};
};
}
