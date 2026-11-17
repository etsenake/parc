// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_BACKGROUND_PICTURE_IN_PICTURE_API_H_
#define PARC_NATIVE_NATIVE_BACKGROUND_PICTURE_IN_PICTURE_API_H_

#include "base/functional/callback_forward.h"
#include "native_background_picture_in_picture.h"

namespace content {
class WebContents;
}

namespace parc {

void SyncBackgroundPictureInPicture(content::WebContents* contents);

void SyncBackgroundPictureInPicture(content::WebContents* contents,
                                    BackgroundPipVisibility shell_visibility);

bool PageHandlesAutoPictureInPicture(content::WebContents* contents);

bool PageCanEnterAutoPictureInPicture(content::WebContents* contents);

void AutoPictureInPictureEligibilityChanged(content::WebContents& contents);

void SynchronizeAutoPictureInPictureVisibility(
    content::WebContents* contents, base::OnceCallback<void(bool)> callback);

}

#endif
