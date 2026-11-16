# Capture and recording capabilities

Parc produces page screenshots and displays existing image and video files in
the Library. Website camera, microphone and screen-sharing indicators describe
actual live streams. Parc does not expose a standalone video-recording workflow
or promise a saved recording from those indicators.

## Production ownership and permissions

| Capability | Owner | Output or action |
|---|---|---|
| Page screenshots | `PageCaptureController` and the native page-capture lease | Region, visible-area, full-page and Portrait image paths; PNG output. |
| Saved screenshots | `CaptureLibraryStore` | Validated PNG pixels and immutable revisions in the original Profile's catalog. |
| Website camera/microphone/sharing | Chromium `MediaStreamCaptureIndicator` and `PCNativeCaptureState` | Exact current-stream indicators and Stop callbacks; normal site/system permission flow. |
| Existing OS media | `ExternalMediaLibrary` | References to accessible original files, with file access checked separately. |
| Diagnostic tracing | Developer diagnostics | Diagnostic data, not a user video recorder. |

A screenshot Save sheet exports PNG. Saving to Library commits captured pixels;
it does not retain a URL as a substitute for those pixels. See
[page capture](page-capture.md) for cancellation, editing and destinations.

Website capture binds the original WebContents, primary document and window.
Stop sharing/camera/microphone is available only when the matching live native
callback exists. No standalone recording permission is requested by these
controls.

Library discovery uses actual filesystem metadata and media types. A movie
without a download-origin attribute can match the screen-recording heuristic,
but that does not identify its producer; the interface calls it a video.
External files are not converted into saved screenshots or deleted by capture
controls. See [Library storage and discovery](capture-library.md).

## Scope and checks

Standalone video recording is outside this capture workflow. Cloud sharing and
telemetry remain excluded by [product scope](product.md#scope-boundaries).

Source/model checks cover screenshot types, stream ownership and file
classification.
