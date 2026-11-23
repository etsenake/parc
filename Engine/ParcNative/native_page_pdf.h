// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PAGE_PDF_H_
#define PARC_NATIVE_NATIVE_PAGE_PDF_H_

#include <cstdint>
#include <memory>
#include <optional>
#include <vector>

#include "base/functional/callback.h"

namespace content {
class WebContents;
}

namespace parc {

class PagePdf {
 public:
  using RecordedCallback = base::OnceCallback<void(bool)>;
  using FinishedCallback =
      base::OnceCallback<void(std::optional<std::vector<uint8_t>>)>;

  static std::unique_ptr<PagePdf> Start(content::WebContents& contents,
                                        RecordedCallback recorded,
                                        FinishedCallback finished);

  virtual ~PagePdf() = default;
};

}

#endif
