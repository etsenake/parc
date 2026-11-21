# Easel images and media

Pictures, videos, audio, files and PDFs on an Easel behave like their Notes
blocks, using the Notes views and helpers themselves. Pictures crop, mask and
carry alt text the way note images do, and none of it ever rewrites the
picture. This guide covers what people can do with each media object, how the
file stores it and which code owns each part. Inline pictures inside text objects are a separate
feature described in [Easels](easels.md#inline-images-in-rich-text).

## Empty media and adding things

Image, Video, Audio, File and PDF in the toolbar's Media ▾ menu (and under Add
in ⌘/) place an empty object at the middle of the view, selected, exactly like
a note's empty block: it wears the Notes empty media card with Upload and Embed
link chips, plus Unsplash for images when Parc has an Unsplash key. Like web
pages it is select-first: a click on an unselected one selects it so it can be
moved, and once it's the only thing selected its chips and link field take
clicks and keys. Return on it opens Upload. Dropping a file, picture or link on
an empty object fills it, and so do Upload and Embed link; a filled object
grows around the same centre to its content (a picture at its own shape up to
480 wide, a video at its shape at 480, audio and files at the Notes card
heights, a PDF at its first page's shape), all in one Undo step. Escape or a
click elsewhere leaves it empty, Delete removes it, and exports skip it.
YouTube, Vimeo and Loom links pasted into a video turn it into an Embed with
its player, as a note decides.

Dropping or pasting files anywhere else adds them straight away: pictures,
videos, audio (M4A, MP3, WAV, AAC, AIFF), PDFs and any other file become Image,
Video, Audio, PDF and File objects, several at once laid out in one tidy row
around the drop point as one Undo step. Each kind is checked by its first bytes,
audio must be playable by macOS, and every file is copied into the Easel (up to
30 MB each), keeping its original name for display and Download. Video and
audio links (http or https) are kept as links rather than copied; a web picture
given to Embed link is downloaded into the Easel, so Easels stay
self-contained.

### Pictures

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

Replace… offers Upload or Unsplash, as in a note (just the file picker when
there's no Unsplash key), and swaps in a different picture and keeps the object's exact size
and spot: the new picture fills the old frame from its middle, like a cover
crop, and the mask, rotation and flips stay. The alt text and quarter turns go,
because they described the old picture. Dropping a picture onto the selected
image replaces it the same way, while a drop anywhere else adds a new one. A
replaced image is one Undo step, and Undo brings the old picture back.

## Unsplash, Quick Look and other picture actions

Unsplash opens the Notes Unsplash browser; the chosen photo is downloaded into
the Easel with the photographer credit, which shows as a small "Photo by … on
Unsplash" line under the selected picture (each name opens its page) and under
the picture in exports. Its description becomes the alt text unless the
picture already had some. Quick Look, Full Screen (the Notes zoom view), Download
and View Original sit in the selection toolbar's ••• menu and the context menu
next to Crop, Mask and Alt Text.

## GIFs

An animated GIF shows its first frame, with a small GIF badge, until it is the
only thing selected. Then it plays, honouring each frame's delay, and stops
when the selection changes or the Easel leaves the window, so only one GIF
moves at a time. Frames are decoded off the main thread at the size they're
shown, crop included, and decode sharper again after zooming in. GIFs over 2048 × 2048 pixels or 5,000 frames come in as a still picture
of their first frame. With Reduce Motion
on, GIFs stay on their first frame, as they do in Notes. Copying a GIF puts the
GIF itself on the pasteboard.

## Videos, audio, files and PDFs

MP4 and MOV videos (including M4V) come in through Video in the Media ▾ menu,
a pasted file or a drop, up to 30 MB; anything bigger gets a friendly "a bit big"
message instead. Parc checks the file's first box (an MP4 or QuickTime ftyp
that isn't a HEIC or AVIF still, or an older QuickTime movie's first box),
asks macOS's video player whether it can play it, reads its size and grabs a poster frame from just after
the start, then copies the video and the poster into the Easel's storage. WebM
isn't offered, because macOS's own video player (the one Notes video blocks use
too) can't open it; such files get the same "can't play on an Easel" message as
a broken one.

Each of these objects is the Notes view for its kind, hosted on the canvas in
its place in the stack: the Notes video player (poster, Parc play button,
inline controls with full screen and picture in picture), the Notes audio card
and player, the Notes file row (icon, name, size; clicking it opens Quick Look)
and the Notes PDF viewer (pages at fit width, page indicator, zoom, Full Screen,
Download and View Original). They follow the select-first rule: once one is the
only thing selected its controls take clicks, and scrolling over a selected
PDF turns its pages and hands over to the Easel at the first or last page;
unselected, scrolling pans the Easel. Their hover toolbars offer Replace,
Download and Delete; captions, alignment and width handles stay Notes-only.
The ••• and context menus add Replace…, Quick Look or Full Screen, Download and
View Original.

Pressing Return on a video, choosing Play Video or VoiceOver's Play video plays
it. Only one video plays at a time: starting another, selecting something
else, closing or hiding the tab stops it, and Escape pauses it. Videos take alt
text like images, which VoiceOver reads.

## Export

PDF, PNG and Copy as Image draw every media object through the canvas drawing, so crops,
turns and masks look exactly as they do on the Easel; a playing GIF exports the
frame on screen, and a video exports as its poster frame without the play
button. HTML exports draw a cropped, turned or masked image as an SVG
picture inside a clip path (the mask's own outline), keep animated GIFs
animated, draw videos as their poster, and write alt text as the picture's
`aria-label` and `<title>`. A video kept as a link draws as a labelled card
linking to it, audio and files as cards with their names (linking to their
address when they are links), and a PDF as its first page. Picture credits
draw under the picture, linking to the photographer and Unsplash.

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
| `fileName` | The original name of a video, audio, file or PDF, shown on its card and offered by Download. |
| `credit` | A picture's photographer: `name`, `profileURL` and `photoURL`. |
| `url` | An http or https link on a video or audio object that isn't copied in. |
| `preview` | A bookmark's saved `title`, `summary`, `siteName`, `image` and `icon`; the last two are web addresses or PNG assets. |

Validation refuses each field on anything but an image, crops outside the
picture or thinner than 1% of it, turns outside 1–3, alt text over 4 KB, an
unknown mask, a GIF asset on anything but an image, a video asset on anything
but a video, audio assets on anything but audio, PDF and file assets on
anything but their own kind, a poster that isn't a PNG or sits on an empty
video, a file name on anything but a video, audio, file or PDF, a credit on
anything but an image and a link on a file, PDF or equation, so a malformed
file is rejected whole. An empty object is its kind with neither an asset nor
a link. Asset names are a lowercase UUID plus `.png`, `.gif`, `.mp4`, `.mov`,
`.m4a`, `.mp3`, `.wav`, `.aac`, `.aiff` or `.pdf`; other files are stored as
`.file` plus their own lowercase extension (letters and digits only), so Quick
Look still knows them. Moving an Easel to another Profile copies posters and
saved bookmark pictures along with the assets.

## Where the code lives

- `EaselImageFraming` and `EaselImageCropDraft` in ParcCore hold the crop
  geometry: turning crops between the stored and turned picture, the whole
  picture behind a frame, zoom, pan, aspect fitting, masking and replacement.
  They reuse the Notes crop rectangle, handle geometry and mask outlines.
- `EaselCanvasView+Images.swift` draws images, runs crop mode, the badges and
  GIF playback, and owns the commands the toolbar, menus and VoiceOver call:
  `beginImageCrop`, `finishImageCrop(save:)`, `setImageMask`,
  `editImageAltText`, `chooseReplacementImage` and `replaceImage(id:data:)`.
- `EaselCanvasView+Video.swift` loads video facts, draws posters for exports
  and routes play, pause and stop to the hosted Notes player.
- `NoteMediaHost.swift` is the seam the Notes media views talk to:
  `NoteMediaBlockView` conforms in notes and `EaselMediaObjectView` on Easels.
  `NoteMediaMode` picks and builds the content view for both, and
  `NoteMediaPanels` presents the shared Replace menu and Unsplash browser.
- `EaselMediaHost.swift` is the `EaselHostedObjects` provider the Easel editor
  and Easel blocks in notes register: it hosts the Notes views for empty media,
  videos, audio, files and PDFs and carries out media actions. Canvas files
  reach it only through `EaselHostedObjects` (`performHostedAction`), so the
  canvas test bundles never compile Notes media views.
- `EaselCanvasMediaFill.swift` fills or replaces an object from a file, data or
  link as one Undo step; `EaselCanvasMediaImport.swift` and
  `EaselMediaImportPlan` turn dropped and pasted files into objects;
  `EaselCanvasMediaActions.swift` lists the menu actions; `EaselMediaPlacement`
  sizes placeholders and filled objects.
- `EaselCanvasMediaArt.swift` and `EaselMediaExport` draw media and credits in
  exports.
- `EaselImageChrome.swift` is the crop bar and the alt text and mask popovers,
  reached through the canvas's `imageEditing.chrome`. The Easel editor wires it;
  Easel blocks in notes don't, so they crop with the menu and keys only.
- `EaselStore` checks asset bytes (`EaselAssetType`) and validates the fields.

`tests/EaselImageFramingTests.swift`, run by `scripts/test-easels.sh`, covers
the crop geometry, turns, presets, masking, replacement, validation, asset
sniffing, the saved format and the SVG output without opening a window.
`tests/EaselStoreTests.swift` covers media placeholders, fields, asset types
and placement, and `tests/EaselMediaImportTests.swift` the import plan.
