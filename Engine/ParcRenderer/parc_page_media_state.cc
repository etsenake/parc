// Copyright 2026 Parc contributors.
#include "third_party/blink/renderer/core/html/media/parc_page_media_state.h"

#include "third_party/blink/renderer/core/page/page.h"

namespace blink {

const char ParcPageMediaState::kSupplementName[] = "ParcPageMediaState";

// static
ParcPageMediaState& ParcPageMediaState::From(Page& page) {
  auto* state = Supplement<Page>::From<ParcPageMediaState>(page);
  if (!state) {
    state = MakeGarbageCollected<ParcPageMediaState>(page);
    ProvideTo(page, state);
  }
  return *state;
}

ParcPageMediaState::ParcPageMediaState(Page& page) : Supplement<Page>(page) {}

void ParcPageMediaState::SetInWindow(bool in_window) {
  if (in_window_ == in_window) {
    return;
  }
  in_window_ = in_window;
  // WebKit's Page::setCanStartMedia notifies media waiting for page consent,
  // apart from visibility and its DOM and compositor observers.
  for (auto& observer : in_window_observers_) {
    observer->PageInWindowChanged(*GetSupplementable());
  }
}

void ParcPageMediaState::AddInWindowObserver(InWindowObserver* observer) {
  in_window_observers_.insert(observer);
}

void ParcPageMediaState::RemoveInWindowObserver(InWindowObserver* observer) {
  in_window_observers_.erase(observer);
}

void ParcPageMediaState::Trace(Visitor* visitor) const {
  visitor->Trace(in_window_observers_);
  Supplement<Page>::Trace(visitor);
}

}  // namespace blink
