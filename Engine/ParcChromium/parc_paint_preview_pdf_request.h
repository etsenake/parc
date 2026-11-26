#ifndef COMPONENTS_PAINT_PREVIEW_BROWSER_PARC_PAINT_PREVIEW_PDF_REQUEST_H_
#define COMPONENTS_PAINT_PREVIEW_BROWSER_PARC_PAINT_PREVIEW_PDF_REQUEST_H_

#include <utility>

#include "base/functional/bind.h"
#include "base/task/bind_post_task.h"
#include "components/paint_preview/browser/paint_preview_compositor_client_impl.h"

namespace paint_preview {

inline void RequestParcPreviewPdf(
    const scoped_refptr<base::SequencedTaskRunner>& default_runner,
    const scoped_refptr<base::SequencedTaskRunner>& compositor_runner,
    const CompositorPtr& compositor,
    mojom::PaintPreviewCompositor::PdfForMainFrameCallback callback) {
  DCHECK(default_runner->RunsTasksInCurrentSequence());
  compositor_runner->PostTask(
      FROM_HERE,
      base::BindOnce(
          &mojom::PaintPreviewCompositor::PdfForMainFrame,
          base::Unretained(compositor.get()->get()),
          base::BindPostTask(default_runner, std::move(callback))));
}

}

#endif
