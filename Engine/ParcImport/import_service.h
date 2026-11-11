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
  void Cancel() override;

 private:
  void Complete(ReadCategoryCallback callback, Batch batch);
  mojo::Receiver<mojom::Reader> receiver_;
  Cancellation cancelled_;
  bool busy_ = false;
  base::WeakPtrFactory<ImportService> weak_factory_{this};
};
}  // namespace parc::importer
