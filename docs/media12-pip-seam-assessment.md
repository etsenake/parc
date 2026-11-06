# MEDIA12: PiP source seam assessment

Source inspection only, October 29. Chromium source is the pinned local

## Existing observer is insufficient

`PictureInPictureWindowManager::Observer` has parameterless enter/exit callbacks (`chrome/browser/picture_in_picture/picture_in_picture_window_manager.h:59-65`). It cannot by itself identify the source document, request or reason. `EnterVideoPictureInPicture` reuses a current controller for the same WebContents with a video bit (`picture_in_picture_window_manager.cc:203-223`); its enter notification is installed only by `CreateWindowInternal` (`:634-646`) and consumed by the controller after `Show`, so replacing an existing session need not produce another enter notification. `ExitPictureInPictureViaWindowUi` calls the controller and returns without the manager's exit notification (`:226-257`). `CloseWindowInternal` calls close and clears its controller before notifying exit (`:659-677`). This observer cannot provide a complete source-bound event history.

The existing `MediaState` is lazily installed through Parc page access (`Engine/ParcNative/native_media_controls.mm`, `State`). An observer installed only there can miss a preceding request or show. Subscribing late must produce an explicit unknown baseline, not an empty history, and must not assume a current PiP bit reconstructs prior causes.

## Dependency and identity boundaries

A dependency-legal candidate would put a typed event/observer API in Chromium `content/public` with source emission in `content/browser`, and consume it from ParcNative. Content must not depend on ParcNative or Chrome. A source-owned observer/store must exist early enough to receive requests, or expose an explicitly unknown late baseline. Its records must be emitted on the UI sequence and carry weak source WebContents, the weak primary document, the actual originating weak document, kind, and a monotonic request/session identity. The sink must validate both documents and identity before changing any MediaState; source retirement and primary replacement must invalidate retained events. Never retain a profile, browser, document or presenter to keep history alive.


Document PiP needs a separate path. Blink rejects non-outermost requesting frames (`third_party/blink/renderer/modules/document_picture_in_picture/document_picture_in_picture.cc:57-62`). Browser window creation captures the actual opener frame in `create_params.opener_id` and marks PiP options (`content/browser/web_contents/web_contents_impl.cc:5812-5829`); an observation there can bind to the actual opener weak document before the manager receives only parent and child WebContents. This is a candidate hook, not proof that all request failures are observable there. The document controller's `SetChildWebContents`, `Show`, `NotifyClosedAndStopObserving` and child/opener destruction paths are distinct from the video service and controller.

The native video presenter's close, return, minimize and system-close branches (`Engine/ParcNative/video_overlay_window.mm`, `Action`) expose specific user intentions before terminal calls, which can synchronously destroy the presenter. To associate those intents with a session, the current session token must reach that presenter or be resolved through a still-valid source-owned record before the call; a raw controller or overlay pointer must not be used afterward. Other presenters and document PiP require separate coverage.

## Mapping and next question


