// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_VIDEO_PICTURE_IN_PICTURE_CAPTIONS_H_
#define PARC_NATIVE_VIDEO_PICTURE_IN_PICTURE_CAPTIONS_H_

#include "mojo/public/cpp/bindings/pending_associated_receiver.h"
#include "third_party/blink/public/mojom/parc/picture_in_picture_captions.mojom-forward.h"

namespace content {
class RenderFrameHost;
struct MediaPlayerId;
}  // namespace content

namespace parc {

// The browser started a video picture-in-picture session for `player`: Parc's
// window drops its captions and shows only that session's from now on.
void StartPictureInPictureCaptionsSession(const content::MediaPlayerId& player);

void BindPictureInPictureCaptionsHost(
    content::RenderFrameHost* frame,
    mojo::PendingAssociatedReceiver<mojom::PictureInPictureCaptionsHost>
        receiver);

}  // namespace parc

#endif  // PARC_NATIVE_VIDEO_PICTURE_IN_PICTURE_CAPTIONS_H_
