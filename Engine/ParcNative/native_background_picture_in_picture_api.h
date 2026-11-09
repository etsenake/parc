// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_BACKGROUND_PICTURE_IN_PICTURE_API_H_
#define PARC_NATIVE_NATIVE_BACKGROUND_PICTURE_IN_PICTURE_API_H_

#include "base/functional/callback_forward.h"
#include "native_background_picture_in_picture.h"

namespace content {
class WebContents;
}

namespace parc {

// Ensure the media observer exists and apply tab-leave / return PiP policy for
// the current WebContents visibility. Safe no-op when ineligible.
void SyncBackgroundPictureInPicture(content::WebContents* contents);

// Same policy using a shell-derived visibility that can differ from Chromium's
// paint visibility (e.g. resign-active counts as occluded for auto-PiP while
// the live page stays WasShown so the window does not blank).
void SyncBackgroundPictureInPicture(content::WebContents* contents,
                                    BackgroundPipVisibility shell_visibility);

// Chromium owns automatic entry for this session, including site handlers
// such as Meet's document PiP handler.
bool PageHandlesAutoPictureInPicture(content::WebContents* contents);

// Reports success only after the renderer acknowledges its lifecycle update.
// False means the original document is no longer live/hidden. No timeout may
// substitute for acknowledgement: the media action uses a different IPC pipe.
void SynchronizeAutoPictureInPictureVisibility(
    content::WebContents* contents, base::OnceCallback<void(bool)> callback);

}  // namespace parc

#endif  // PARC_NATIVE_NATIVE_BACKGROUND_PICTURE_IN_PICTURE_API_H_
