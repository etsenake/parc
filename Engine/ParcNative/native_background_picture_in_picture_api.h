// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_BACKGROUND_PICTURE_IN_PICTURE_API_H_
#define PARC_NATIVE_NATIVE_BACKGROUND_PICTURE_IN_PICTURE_API_H_

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

}  // namespace parc

#endif  // PARC_NATIVE_NATIVE_BACKGROUND_PICTURE_IN_PICTURE_API_H_
