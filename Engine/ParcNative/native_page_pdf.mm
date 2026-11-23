#include "native_page_pdf.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/task/sequenced_task_runner.h"
#include "components/paint_preview/browser/compositor_utils.h"
#include "components/paint_preview/browser/paint_preview_base_service.h"
#include "components/paint_preview/common/recording_map.h"
#include "components/paint_preview/common/serialized_recording.h"
#include "components/paint_preview/public/paint_preview_compositor_client.h"
#include "components/paint_preview/public/paint_preview_compositor_service.h"
#include "components/services/paint_preview_compositor/public/mojom/paint_preview_compositor.mojom.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/base/big_buffer.h"
#include "mojo/public/cpp/base/proto_wrapper.h"

namespace parc {
namespace {

constexpr size_t kMaxRecordingBytes = 100 * 1000 * 1000;
constexpr uint64_t kMaxDecodedImageBytes = 100 * 1000 * 1000;

using paint_preview::mojom::PaintPreviewCompositor;

class PagePdfService final : public PagePdf,
                             public paint_preview::PaintPreviewBaseService {
 public:
  PagePdfService(bool off_the_record, RecordedCallback recorded,
                 FinishedCallback finished)
      : paint_preview::PaintPreviewBaseService(nullptr, nullptr, off_the_record),
        recorded_(std::move(recorded)),
        finished_(std::move(finished)),
        compositor_service_(nullptr, base::OnTaskRunnerDeleter(nullptr)),
        compositor_client_(nullptr, base::OnTaskRunnerDeleter(nullptr)) {}
  ~PagePdfService() override = default;

  base::WeakPtr<PagePdfService> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

  void Begin(base::WeakPtr<content::WebContents> contents) {
    if (!contents || contents->IsBeingDestroyed()) {
      Finish(std::nullopt);
      return;
    }
    auto weak = weak_factory_.GetWeakPtr();
    compositor_service_ = paint_preview::StartCompositorService(
        base::BindOnce(&PagePdfService::Disconnected, weak));
    if (!compositor_service_) {
      Finish(std::nullopt);
      return;
    }
    compositor_client_ = compositor_service_->CreateCompositor(
        base::BindOnce(&PagePdfService::CompositorReady, weak));
    if (!compositor_client_) {
      Finish(std::nullopt);
      return;
    }
    compositor_client_->SetDisconnectHandler(
        base::BindOnce(&PagePdfService::Disconnected, weak));
    CaptureParams params;
    params.web_contents = contents.get();
    params.persistence = paint_preview::RecordingPersistence::kMemoryBuffer;
    params.max_per_capture_size = kMaxRecordingBytes;
    params.max_decoded_image_size_bytes = kMaxDecodedImageBytes;
    CapturePaintPreview(std::move(params),
                        base::BindOnce(&PagePdfService::Captured, weak));
  }

 private:
  void Captured(CaptureStatus status,
                std::unique_ptr<paint_preview::CaptureResult> result) {
    if (done_) return;
    if (status != CaptureStatus::kOk || !result || !result->capture_success) {
      Finish(std::nullopt);
      return;
    }
    Notify(std::move(recorded_), true);
    result_ = std::move(result);
    Composite();
  }

  void CompositorReady() {
    compositor_ready_ = true;
    Composite();
  }

  void Composite() {
    if (done_ || !result_ || !compositor_ready_ || !compositor_client_) return;
    auto request = paint_preview::mojom::PaintPreviewBeginCompositeRequest::New();
    auto [recordings, proto] =
        paint_preview::RecordingMapFromCaptureResult(std::move(*result_));
    result_.reset();
    request->recording_map = std::move(recordings);
    request->preview = mojo_base::ProtoWrapper(std::move(proto));
    compositor_client_->BeginMainFrameComposite(
        std::move(request),
        base::BindOnce(&PagePdfService::Composited, weak_factory_.GetWeakPtr()));
  }

  void Composited(PaintPreviewCompositor::BeginCompositeStatus status,
                  paint_preview::mojom::PaintPreviewBeginCompositeResponsePtr) {
    if (done_) return;
    if ((status != PaintPreviewCompositor::BeginCompositeStatus::kSuccess &&
         status != PaintPreviewCompositor::BeginCompositeStatus::kPartialSuccess) ||
        !compositor_client_) {
      Finish(std::nullopt);
      return;
    }
    compositor_client_->PdfForMainFrame(
        base::BindOnce(&PagePdfService::PdfMade, weak_factory_.GetWeakPtr()));
  }

  void PdfMade(std::optional<mojo_base::BigBuffer> pdf) {
    if (done_) return;
    if (!pdf || pdf->size() == 0) {
      Finish(std::nullopt);
      return;
    }
    const base::span<const uint8_t> bytes = *pdf;
    Finish(std::vector<uint8_t>(bytes.begin(), bytes.end()));
  }

  void Disconnected() { Finish(std::nullopt); }

  void Finish(std::optional<std::vector<uint8_t>> pdf) {
    if (done_) return;
    done_ = true;
    result_.reset();
    if (recorded_) Notify(std::move(recorded_), false);
    Notify(std::move(finished_), std::move(pdf));
  }

  template <typename Callback, typename Value>
  void Notify(Callback callback, Value value) {
    if (!callback) return;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(
            [](base::WeakPtr<PagePdfService> weak, Callback callback,
               Value value) {
              if (weak) std::move(callback).Run(std::move(value));
            },
            weak_factory_.GetWeakPtr(), std::move(callback), std::move(value)));
  }

  RecordedCallback recorded_;
  FinishedCallback finished_;
  std::unique_ptr<paint_preview::CaptureResult> result_;
  bool compositor_ready_ = false;
  bool done_ = false;
  std::unique_ptr<paint_preview::PaintPreviewCompositorService,
                  base::OnTaskRunnerDeleter>
      compositor_service_;
  std::unique_ptr<paint_preview::PaintPreviewCompositorClient,
                  base::OnTaskRunnerDeleter>
      compositor_client_;
  base::WeakPtrFactory<PagePdfService> weak_factory_{this};
};

}

std::unique_ptr<PagePdf> PagePdf::Start(content::WebContents& contents,
                                        RecordedCallback recorded,
                                        FinishedCallback finished) {
  auto service = std::make_unique<PagePdfService>(
      contents.GetBrowserContext()->IsOffTheRecord(), std::move(recorded),
      std::move(finished));
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&PagePdfService::Begin,
                                service->GetWeakPtr(),
                                contents.GetWeakPtr()));
  return service;
}

}
