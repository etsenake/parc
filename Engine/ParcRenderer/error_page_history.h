// Copyright 2026 Parc contributors.
#ifndef PARC_RENDERER_ERROR_PAGE_HISTORY_H_
#define PARC_RENDERER_ERROR_PAGE_HISTORY_H_

namespace content {
class RenderFrame;
}

namespace parc {
void TellErrorPageAboutHistory(content::RenderFrame* render_frame);
}  // namespace parc
#endif
