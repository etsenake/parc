#ifndef COMPONENTS_SERVICES_PAINT_PREVIEW_COMPOSITOR_PARC_PAINT_PREVIEW_PDF_H_
#define COMPONENTS_SERVICES_PAINT_PREVIEW_COMPOSITOR_PARC_PAINT_PREVIEW_PDF_H_

#include <optional>
#include <utility>

#include "base/functional/bind.h"
#include "base/task/thread_pool.h"
#include "base/time/time.h"
#include "base/trace_event/trace_event.h"
#include "build/build_config.h"
#include "components/discardable_memory/client/client_discardable_shared_memory_manager.h"
#include "components/services/paint_preview_compositor/public/mojom/paint_preview_compositor.mojom.h"
#include "mojo/public/cpp/base/big_buffer.h"
#include "skia/ext/skia_utils_base.h"
#include "third_party/skia/include/core/SkCanvas.h"
#include "third_party/skia/include/core/SkData.h"
#include "third_party/skia/include/core/SkPicture.h"
#include "third_party/skia/include/core/SkStream.h"
#include "third_party/skia/include/docs/SkPDFDocument.h"

namespace paint_preview {

inline std::optional<mojo_base::BigBuffer> CreateParcPreviewPdf(
    scoped_refptr<discardable_memory::ClientDiscardableSharedMemoryManager>
        discardable_shared_memory_manager,
    sk_sp<SkPicture> skp) {
  TRACE_EVENT0("paint_preview", "PaintPreviewCompositorImpl::CreatePdf");
  const SkRect bounds = skp->cullRect();
  if (bounds.isEmpty() || !bounds.isFinite()) {
    return std::nullopt;
  }
  base::Time::Exploded exploded;
  base::Time::Now().UTCExplode(&exploded);
  const SkPDF::DateTime now{
      .fTimeZoneMinutes = 0,
      .fYear = static_cast<uint16_t>(exploded.year),
      .fMonth = static_cast<uint8_t>(exploded.month),
      .fDayOfWeek = static_cast<uint8_t>(exploded.day_of_week),
      .fDay = static_cast<uint8_t>(exploded.day_of_month),
      .fHour = static_cast<uint8_t>(exploded.hour),
      .fMinute = static_cast<uint8_t>(exploded.minute),
      .fSecond = static_cast<uint8_t>(exploded.second)};
  SkPDF::Metadata metadata;
  metadata.fCreation = now;
  metadata.fModified = now;
  metadata.fCreator = SkString("Chromium");
  metadata.fRasterDPI = 300.0f;
#if BUILDFLAG(IS_MAC)
  metadata.fRasterizeAlphaGradientsForPrinting = true;
#endif
  SkDynamicMemoryWStream stream;
  sk_sp<SkDocument> document = SkPDF::MakeDocument(&stream, metadata);
  if (!document) {
    return std::nullopt;
  }
  SkCanvas* canvas = document->beginPage(bounds.width(), bounds.height());
  if (!canvas) {
    return std::nullopt;
  }
  canvas->translate(-bounds.x(), -bounds.y());
  canvas->drawPicture(skp);
  document->endPage();
  document->close();
  sk_sp<SkData> data = stream.detachAsData();
  if (!data || data->isEmpty()) {
    return std::nullopt;
  }
  return mojo_base::BigBuffer(skia::as_byte_span(*data));
}

inline void GenerateParcPreviewPdf(
    const scoped_refptr<discardable_memory::ClientDiscardableSharedMemoryManager>& manager,
    const sk_sp<SkPicture>& root_frame,
    mojom::PaintPreviewCompositor::PdfForMainFrameCallback callback) {
  TRACE_EVENT0("paint_preview", "PaintPreviewCompositorImpl::PdfForMainFrame");
  if (root_frame == nullptr) {
    std::move(callback).Run(std::nullopt);
    return;
  }
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE,
      {base::TaskPriority::USER_VISIBLE, base::WithBaseSyncPrimitives(),
       base::TaskShutdownBehavior::CONTINUE_ON_SHUTDOWN},
      base::BindOnce(&CreateParcPreviewPdf, manager,
                     root_frame),
      std::move(callback));
}

}

#endif
