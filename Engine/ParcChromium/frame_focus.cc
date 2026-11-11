// Copyright 2026 Parc contributors.
#include "parc/frame_focus.h"

#include <memory>
#include <utility>

#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_user_data.h"

namespace parc {
namespace {
class FrameFocus final : public content::WebContentsUserData<FrameFocus> {
 public:
  std::shared_ptr<base::RepeatingClosureList> callbacks =
      std::make_shared<base::RepeatingClosureList>();

 private:
  friend class content::WebContentsUserData<FrameFocus>;
  explicit FrameFocus(content::WebContents* contents)
      : content::WebContentsUserData<FrameFocus>(*contents) {}
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(FrameFocus);
}

base::CallbackListSubscription SubscribeFrameFocus(
    content::WebContents& contents, base::RepeatingClosure callback) {
  FrameFocus::CreateForWebContents(&contents);
  return FrameFocus::FromWebContents(&contents)->callbacks->Add(std::move(callback));
}

void NotifyFrameFocus(content::WebContents* contents) {
  if (auto* state = FrameFocus::FromWebContents(contents)) {
    // A shortcut callback can close the page while notification is in flight.
    auto callbacks = state->callbacks;
    callbacks->Notify();
  }
}
}
