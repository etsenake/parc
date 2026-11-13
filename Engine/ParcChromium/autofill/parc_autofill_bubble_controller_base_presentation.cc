// Copyright 2021 The Chromium Authors

#include "chrome/browser/ui/autofill/autofill_bubble_controller_base.h"

#include <utility>
#include "base/check.h"
#include "base/functional/bind.h"
#include "build/build_config.h"
#include "chrome/browser/ui/autofill/autofill_bubble_base.h"
#include "chrome/browser/ui/autofill/bubble_manager.h"

namespace autofill {

void AutofillBubbleControllerBase::ObservePresentation(
    base::OnceClosure shown,
    base::OnceClosure unavailable) {
  CHECK(bubble_view_);
  auto weak = GetBubbleControllerBaseWeakPtr();
  auto* view = bubble_view_.get();
  const uint64_t generation = presentation_generation_;
  view->SetPresentationCallback(base::BindOnce(
      [](base::WeakPtr<BubbleControllerBase> weak, AutofillBubbleBase* view,
         uint64_t generation, base::OnceClosure shown,
         base::OnceClosure unavailable, bool presented) {
        if (!weak) {
          return;
        }
        auto* self = static_cast<AutofillBubbleControllerBase*>(weak.get());
        if (self->presentation_generation_ != generation ||
            self->bubble_view_ != view) {
          return;
        }
        if (presented) {
          self->was_bubble_shown_ = true;
          if (shown) {
            std::move(shown).Run();
          }
          return;
        }
        self->presentation_unavailable_ = true;
        self->bubble_view_ = nullptr;
        const uint64_t refused_generation = ++self->presentation_generation_;
        if (unavailable) {
          std::move(unavailable).Run();
        }
        if (!weak || self->presentation_generation_ != refused_generation) {
          return;
        }
#if !BUILDFLAG(IS_ANDROID)
        if (auto* manager =
                BubbleManager::GetForWebContents(self->web_contents()))
          manager->OnBubbleHiddenByController(*self, true);
#endif
      },
      weak, view, generation, std::move(shown), std::move(unavailable)));
}

}
