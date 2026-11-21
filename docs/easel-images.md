# Easel images and media

Pictures on an Easel behave like Notes images: they crop, mask and carry alt
text the same way, and none of it ever rewrites the picture itself. This guide
covers what people can do with an image object, how the file stores it and
which code owns each part. Inline pictures inside text objects are a separate
feature described in [Easels](easels.md#inline-images-in-rich-text).

## Adding pictures

Image in the toolbar's Media ▾ menu places an empty image, like a note's empty
image block, whose Upload chip, paste and drops take PNG, JPEG, TIFF, HEIC, WebP
and GIF; pasting or dropping a picture anywhere else adds it straight away.
Every picture is copied into the Easel's own storage, never linked by path:
still pictures are stored as PNG with the camera's rotation already applied, so
a portrait iPhone photo stands up straight, and animated GIFs keep their own
bytes so they can still play. The store checks each file's first bytes against
its type before writing it and refuses anything over 30 MB, pictures larger
than 16,384 pixels on a side or 80 million pixels in all, and anything it can't
decode. A new picture lands near the middle of the view at up to 480 points
wide. Pasting prefers GIF data over PNG or TIFF when an app offers both, so a
GIF copied from a web page stays animated.

## Cropping

Double-click an image, press Return on it, or choose Crop Image from its menu
(or the selection toolbar) to crop it where it sits. Crop mode shows the whole
picture with the parts outside the frame dimmed, white corner and edge handles,
and thirds guides while something is being dragged. The handles change the
frame, which is the object's size and spot on the Easel; dragging the picture
repositions it inside the frame, which stays put. Shift keeps the frame's ratio
while resizing.

A crop bar below the frame, built from the Notes media toolbar parts, holds:

- **Aspect ratio**: Freeform, Original, Square, 4:3, 3:4, 16:9, 9:16 and Circle
  (a square crop with the circle mask). Fixed ratios fit the largest frame of
  that shape inside the current one.
- **Mask**: the Notes mask picker, previewing each shape on this picture.
- **Rotate 90°**: turns the picture clockwise inside its frame; the frame turns
  with it about its centre, and 16:9 becomes 9:16.
- **Zoom**: a slider from 1× (the picture just covers the frame) to 8×, or to a
  tighter saved crop's own zoom, plus zoom out and zoom in buttons. Zooming
  scales the picture about the frame's centre and never uncovers the frame.
- **Reset**, **Cancel** and **Save**. Reset shows the whole picture again at
  1×; Cancel and Escape throw the crop away; Save, Return or a click anywhere
  else keeps it.

Arrow keys move the picture a point at a time (Shift for ten), `=` and `-`
zoom, and Tab saves and moves on. Right-clicking during a crop offers the same
choices, and VoiceOver gets them as actions on the image (move the picture,
zoom, rotate, show the whole picture, done and cancel). Selecting something
else saves the crop, and so does the Easel leaving its window. Each crop is a
single Undo step, and the image keeps its original bytes, so cropping again
always starts from the whole picture. If an Undo changes or removes the image
mid-crop, crop mode ends without saving.

Crop mode works in the picture's own orientation: a rotated or flipped object
is shown upright while it's being cropped and returns to its rotation on Save.

## Masks

Mask clips an image to one of the Notes shapes: rounded rectangle, circle,
squircle, arch, diamond, hexagon, star or heart. The square shapes (everything
but the rounded rectangle and the arch) keep the frame square, taking the
middle of a wider or taller picture. Original removes the mask and keeps the
crop. Masks come from the context menu, the selection toolbar or the crop bar
and apply to every selected unlocked image in one Undo step.

## Alt text and replacing

Alt Text… describes an image for people who can't see it, in the same popover
Notes uses. VoiceOver reads it as the image's value, an ALT badge appears in
the bottom corner while the pointer is over a described image, and clicking
the badge edits it. Empty text removes it; up to 4 KB is kept.

Replace Image… swaps in a different picture and keeps the object's exact size
and spot: the new picture fills the old frame from its middle, like a cover
crop, and the mask, rotation and flips stay. The alt text and quarter turns go,
because they described the old picture. Dropping a picture onto the selected
image replaces it the same way, while a drop anywhere else adds a new one. A
replaced image is one Undo step, and Undo brings the old picture back.

## GIFs

An animated GIF shows its first frame, with a small GIF badge, until it is the
only thing selected. Then it plays, honouring each frame's delay, and stops
when the selection changes or the Easel leaves the window, so only one GIF
moves at a time. Frames are decoded off the main thread at the size they're
shown, crop included, and decode sharper again after zooming in. GIFs over 2048 × 2048 pixels or 5,000 frames come in as a still picture
of their first frame. With Reduce Motion
on, GIFs stay on their first frame, as they do in Notes. Copying a GIF puts the
GIF itself on the pasteboard.

## Videos

MP4 and MOV videos (including M4V) come in through Video in the Media ▾ menu,
a pasted file or a drop, up to 30 MB; anything bigger gets a friendly "a bit big"
message instead. Parc checks the file's first box (an MP4 or QuickTime ftyp
that isn't a HEIC or AVIF still, or an older QuickTime movie's first box),
asks macOS's video player whether it can play it, reads its size and grabs a poster frame from just after
the start, then copies the video and the poster into the Easel's storage. WebM
isn't offered, because macOS's own video player (the one Notes video blocks use
too) can't open it; such files get the same "can't play on an Easel" message as
a broken one.

A video shows its poster with rounded corners and a play button. Clicking the
play button, double-clicking the video, pressing Return on it or choosing Play
Video from its menu plays it right there with the native inline controls
(scrubbing, volume, full screen and picture in picture). Only one video plays
at a time: starting another, selecting something else, closing or hiding the
tab stops it, and Escape pauses it. A playing video plays upright even if the
object is rotated. Videos take alt text like images, which VoiceOver reads,
and VoiceOver also gets Play video and Pause video actions.

## Export

PDF, PNG and Copy as Image draw images through the canvas drawing, so crops,
turns and masks look exactly as they do on the Easel; a playing GIF exports the
frame on screen, and a video exports as its poster frame without the play
button. HTML exports draw a cropped, turned or masked image as an SVG
picture inside a clip path (the mask's own outline), keep animated GIFs
animated, draw videos as their poster, and write alt text as the picture's
`aria-label` and `<title>`.

## Saved format

All image fields are optional and left out of the file when unused, so an Easel
from before them opens and looks the same:

| Field | Meaning |
|---|---|
| `crop` | A rectangle in 0…1 units of the stored picture; absent means the whole picture. |
| `quarterTurns` | 1, 2 or 3 clockwise quarter turns of the cropped picture inside the frame. |
| `mask` | `rounded`, `circle`, `squircle`, `arch`, `diamond`, `hexagon`, `star` or `heart`. |
| `altText` | The description VoiceOver reads and HTML exports write (images and videos). |
| `poster` | A video's poster frame, a PNG asset in the same store. |

Validation refuses each field on anything but an image, crops outside the
picture or thinner than 1% of it, turns outside 1–3, alt text over 4 KB, an
unknown mask, a GIF asset on anything but an image, a video asset on anything
but a video and a poster that isn't a PNG, so a malformed file is rejected
whole. Video objects are the `video` kind, holding the movie as their asset.
Asset names are a lowercase UUID plus `.png`, `.gif`, `.mp4` or `.mov`, and
moving an Easel to another Profile copies posters along with the assets.

## Where the code lives

- `EaselImageFraming` and `EaselImageCropDraft` in ParcCore hold the crop
  geometry: turning crops between the stored and turned picture, the whole
  picture behind a frame, zoom, pan, aspect fitting, masking and replacement.
  They reuse the Notes crop rectangle, handle geometry and mask outlines.
- `EaselCanvasView+Images.swift` draws images, runs crop mode, the badges and
  GIF playback, and owns the commands the toolbar, menus and VoiceOver call:
  `beginImageCrop`, `finishImageCrop(save:)`, `setImageMask`,
  `editImageAltText`, `chooseReplacementImage` and `replaceImage(id:data:)`.
- `EaselCanvasView+Video.swift` imports videos, draws posters and runs the
  single inline player, an `AVPlayerView` placed over the object.
- `EaselImageChrome.swift` is the crop bar and the alt text and mask popovers,
  reached through the canvas's `imageEditing.chrome`. The Easel editor wires it;
  Easel blocks in notes don't, so they crop with the menu and keys only.
- `EaselStore` checks asset bytes (`EaselAssetType`) and validates the fields.

`tests/EaselImageFramingTests.swift`, run by `scripts/test-easels.sh`, covers
the crop geometry, turns, presets, masking, replacement, validation, asset
sniffing, the saved format and the SVG output without opening a window.
